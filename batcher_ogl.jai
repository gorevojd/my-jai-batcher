#scope_export

// Owns GPU resources only; keep one cache per batcher and do not copy live caches.
OGL_BatcherCache :: struct {
    vao: u32;
    vertex_buffer: u32;
    index_buffer: u32;
    per_triangle_buffer: u32;
    transform_buffer: u32;
    per_triangle_texture: u32;
    transform_texture: u32;
    shader_program: u32;
    projection_uniform: s32 = -1;

    // Allocated sizes in bytes. Storage grows as needed and survives frame resets.
    vertex_buffer_capacity: int;
    index_buffer_capacity: int;
    per_triangle_buffer_capacity: int;
    transform_buffer_capacity: int;
}

// Requires a current OpenGL context and loaded GL procedures. Does not touch CPU batcher data.
ogl_init_batcher :: (cache: *OGL_BatcherCache) -> bool {
    assert(cache.vao == 0 && cache.shader_program == 0, "Batcher cache is already initialized.");
    cache.shader_program = ogl_batcher_create_program();
    if cache.shader_program == 0 return false;

    glGenVertexArrays(1, *cache.vao);
    glGenBuffers(1, *cache.vertex_buffer);
    glGenBuffers(1, *cache.index_buffer);
    glGenBuffers(1, *cache.per_triangle_buffer);
    glGenBuffers(1, *cache.transform_buffer);
    glGenTextures(1, *cache.per_triangle_texture);
    glGenTextures(1, *cache.transform_texture);

    glBindVertexArray(cache.vao);
    glBindBuffer(GL_ARRAY_BUFFER, cache.vertex_buffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, cache.index_buffer);

    stride := cast(GLsizei) size_of(BatcherVertex);
    offset: *BatcherVertex = null;
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, *offset.point);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, *offset.uv);
    glEnableVertexAttribArray(2);
    glVertexAttribIPointer(2, 1, GL_UNSIGNED_INT, stride, *offset.transform_index);

    // Allocate the texture buffers before attaching their persistent texture views.
    ogl_batcher_upload_buffer(cache.per_triangle_buffer, GL_TEXTURE_BUFFER, null, 256, *cache.per_triangle_buffer_capacity);
    glActiveTexture(GL_TEXTURE0 + BATCHER_MAX_TEXTURE_COUNT);
    glBindTexture(GL_TEXTURE_BUFFER, cache.per_triangle_texture);
    glTexBuffer(GL_TEXTURE_BUFFER, GL_RG32UI, cache.per_triangle_buffer);
    ogl_batcher_upload_buffer(cache.transform_buffer, GL_TEXTURE_BUFFER, null, 256, *cache.transform_buffer_capacity);
    glActiveTexture(GL_TEXTURE0 + BATCHER_MAX_TEXTURE_COUNT + 1);
    glBindTexture(GL_TEXTURE_BUFFER, cache.transform_texture);
    glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA32F, cache.transform_buffer);

    glUseProgram(cache.shader_program);
    cache.projection_uniform = glGetUniformLocation(cache.shader_program, "projection".data);
    texture_units: [BATCHER_MAX_TEXTURE_COUNT] GLint;
    for i: 0..texture_units.count-1 texture_units[i] = xx i;
    glUniform1iv(glGetUniformLocation(cache.shader_program, "textures[0]".data), xx texture_units.count, texture_units.data);
    glUniform1i(glGetUniformLocation(cache.shader_program, "per_triangle_data".data), BATCHER_MAX_TEXTURE_COUNT);
    glUniform1i(glGetUniformLocation(cache.shader_program, "object_transform_data".data), BATCHER_MAX_TEXTURE_COUNT + 1);

    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_TEXTURE_BUFFER, 0);
    return true;
}

// Call before destroying the GL context. CPU geometry, transforms and textures stay owned by the caller.
ogl_destroy_batcher :: (cache: *OGL_BatcherCache) {
    glDeleteVertexArrays(1, *cache.vao);
    glDeleteBuffers(1, *cache.vertex_buffer);
    glDeleteBuffers(1, *cache.index_buffer);
    glDeleteBuffers(1, *cache.per_triangle_buffer);
    glDeleteBuffers(1, *cache.transform_buffer);
    glDeleteTextures(1, *cache.per_triangle_texture);
    glDeleteTextures(1, *cache.transform_texture);
    if cache.shader_program != 0 {
        current_program: GLint;
        glGetIntegerv(GL_CURRENT_PROGRAM, *current_program);
        if cast(u32) current_program == cache.shader_program glUseProgram(0);
        glDeleteProgram(cache.shader_program);
    }
    cache.* = .{};
}

// The caller supplies its camera's matrix, keeping the module independent of application render types.
ogl_render_batcher :: (cache: *OGL_BatcherCache, batcher: *Batcher, view_projection: *Mat4) {
    if batcher.indices.count <= 0 return;
    assert(cache.vao != 0 && cache.shader_program != 0, "Initialize the batcher cache before rendering.");
    assert(batcher.indices.count % 3 == 0 && batcher.per_triangle_data.count == batcher.indices.count / 3);
    #assert size_of(BatcherPerTriangleData) == 2 * size_of(u32);
    #assert size_of(BatcherObjectTransformData) == 4 * size_of(float);

    glBindVertexArray(cache.vao);
    ogl_batcher_upload_buffer(cache.vertex_buffer, GL_ARRAY_BUFFER, batcher.vertices.data,
                             batcher.vertices.count * size_of(BatcherVertex), *cache.vertex_buffer_capacity);
    ogl_batcher_upload_buffer(cache.index_buffer, GL_ELEMENT_ARRAY_BUFFER, batcher.indices.data,
                             batcher.indices.count * size_of(u32), *cache.index_buffer_capacity);
    ogl_batcher_upload_buffer(cache.per_triangle_buffer, GL_TEXTURE_BUFFER, batcher.per_triangle_data.data,
                             batcher.per_triangle_data.count * size_of(BatcherPerTriangleData), *cache.per_triangle_buffer_capacity);
    ogl_batcher_upload_buffer(cache.transform_buffer, GL_TEXTURE_BUFFER, batcher.object_transform_data.data,
                             batcher.object_transform_data.count * size_of(BatcherObjectTransformData), *cache.transform_buffer_capacity);

    glUseProgram(cache.shader_program);
    glUniformMatrix4fv(cache.projection_uniform, 1, GL_TRUE, *view_projection._00);
    glActiveTexture(GL_TEXTURE0 + BATCHER_MAX_TEXTURE_COUNT);
    glBindTexture(GL_TEXTURE_BUFFER, cache.per_triangle_texture);
    glActiveTexture(GL_TEXTURE0 + BATCHER_MAX_TEXTURE_COUNT + 1);
    glBindTexture(GL_TEXTURE_BUFFER, cache.transform_texture);
    for texture_index: 0..batcher.num_textures-1 {
        glActiveTexture(GL_TEXTURE0 + cast(u32) texture_index);
        glBindTexture(GL_TEXTURE_2D, xx batcher.textures[texture_index]);
    }

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glDrawElements(GL_TRIANGLES, xx batcher.indices.count, GL_UNSIGNED_INT, null);
    glDisable(GL_BLEND);
    glBindVertexArray(0);
}

#scope_module

ogl_batcher_upload_buffer :: (buffer: u32, target: GLenum, data: *void, data_size: int, capacity: *int) {
    glBindBuffer(target, buffer);
    if data_size > capacity.* {
        capacity.* = max(data_size, max(256, capacity.* * 2));
        glBufferData(target, capacity.*, null, GL_STREAM_DRAW);
    }
    if data != null && data_size > 0 glBufferSubData(target, 0, data_size, data);
}

ogl_batcher_compile_shader :: (type: GLenum, source: string) -> u32 {
    shader := glCreateShader(type);
    source_length: GLint = xx source.count;
    glShaderSource(shader, 1, *source.data, *source_length);
    glCompileShader(shader);
    success: GLint;
    glGetShaderiv(shader, GL_COMPILE_STATUS, *success);
    if !success {
        info_log: [2048] u8;
        glGetShaderInfoLog(shader, info_log.count, null, info_log.data);
        log("Batcher shader compilation failed: %", to_string(info_log.data), flags = .ERROR);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

ogl_batcher_create_program :: () -> u32 {
    vs := ogl_batcher_compile_shader(GL_VERTEX_SHADER, OGL_BATCHER_VERTEX_SHADER);
    if vs == 0 return 0;
    defer glDeleteShader(vs);
    fs := ogl_batcher_compile_shader(GL_FRAGMENT_SHADER, OGL_BATCHER_FRAGMENT_SHADER);
    if fs == 0 return 0;
    defer glDeleteShader(fs);

    program := glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    success: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *success);
    if !success {
        info_log: [2048] u8;
        glGetProgramInfoLog(program, info_log.count, null, info_log.data);
        log("Batcher shader link failed: %", to_string(info_log.data), flags = .ERROR);
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

#scope_export

OGL_BATCHER_VERTEX_SHADER :: #string BATCHER_VS

#version 330 core

layout (location=0) in vec2 in_p;
layout (location=1) in vec2 in_uv;
layout (location=2) in uint in_transform_index;

uniform mat4 projection;
uniform samplerBuffer object_transform_data;

out vec2 vs_uv;

void main()
{
    vec4 transform = texelFetch(object_transform_data, int(in_transform_index));

    vec2 position = transform.xy;
    float re = transform.z;
    float im = transform.w;
    vec2 world_position = vec2(re * in_p.x - im * in_p.y, im * in_p.x + re * in_p.y) + position;
    gl_Position = projection * vec4(world_position, 0.0f, 1.0f);

    vs_uv = in_uv;
}

BATCHER_VS;

OGL_BATCHER_FRAGMENT_SHADER :: #string BATCHER_FS

#version 330 core

in vec2 vs_uv;
out vec4 color;

uniform sampler2D textures[14];
uniform usamplerBuffer per_triangle_data;

void main()
{
    uvec2 triangle_data = texelFetch(per_triangle_data, gl_PrimitiveID).rg;
    uint packed_data = triangle_data.r;
    uint packed_color = triangle_data.g;
    color = vec4(float(packed_color & 255u),
                 float((packed_color >> 8u) & 255u),
                 float((packed_color >> 16u) & 255u),
                 float((packed_color >> 24u) & 255u)) / 255.0;
    uint texture_index = packed_data & 15u;
    uint aa_nearest_neighbour = (packed_data >> 4u) & 1u;

    vec2 f_width = fwidth(vs_uv);

    if (texture_index != 15u) {
        vec2 actual_uv = vs_uv;

        if (aa_nearest_neighbour != 0u) {
            vec2 texture_size = textureSize(textures[texture_index], 0);
            vec2 texel_coord = vs_uv * texture_size;

            vec2 num_texels_per_pixel = clamp(f_width * texture_size, 0.00001f, 1.0f); // Do not allow more than 1 texel per pixel

            /*

            // https://colececil.dev/blog/2017/scaling-pixel-art-without-destroying-it/
            vec2 coord_inside_texel = fract(texel_coord);
            vec2 factor1 = clamp(coord_inside_texel / num_texels_per_pixel, 0.0f, 0.5f);
            vec2 factor2 = clamp((coord_inside_texel - 1.0f) / num_texels_per_pixel + 0.5f, 0.0f, 0.5f);
            vec2 lerp_factor = factor1 + factor2;
            actual_uv = (floor(texel_coord) + lerp_factor) / texture_size;

            */

            // https://jorenjoestar.github.io/post/pixel_art_filtering/
            vec2 texel_base = floor(texel_coord - 0.5f) + 0.5f;
            vec2 half_box_width = 0.5f * num_texels_per_pixel;
            vec2 lerp_factor = smoothstep(0.5f - half_box_width, 0.5f + half_box_width, texel_coord - texel_base);
            actual_uv = (texel_base + lerp_factor) / texture_size;
        }

        vec4 texture_color = texture2D(textures[texture_index], actual_uv);

        color *= texture_color;
    }
}

BATCHER_FS;
