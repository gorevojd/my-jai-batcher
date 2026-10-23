BatcherTextureFlags :: enum_flags u32 {
    ANTIALIAS_NEAREST_NEIGHBOUR;
}

BatcherTexture :: struct {
    // Backend-defined handle. The OpenGL implementation expects a GL texture name.
    handle: u64;
    width, height: u32;
    flags: BatcherTextureFlags;
}

BatcherVertex :: struct {
    point: Vec2;
    uv: Vec2;
    transform_index: u32;
}

BatcherPerTriangleData :: struct {
    /*
        Bits 0..3: texture index, or 15 for untextured triangles.
        Bit 4: `anti_alias_nearest_neighbour` flag.
        Bits 5..31 are zero.
    */
    packed_data: u32;
    // RGBA8: R in bits 0..7, G in 8..15, B in 16..23, A in 24..31.
    packed_color: u32;
}

BatcherObjectTransformData :: struct {
    position: Vec2;
    scaled_rotation: Complex; // rotation * scale; do not normalize.
}

Batcher :: struct {
    vertices: [..] BatcherVertex;
    indices: [..] u32;

    per_triangle_data: [..] BatcherPerTriangleData;
    object_transform_data: [..] BatcherObjectTransformData;

    textures: [BATCHER_MAX_TEXTURE_COUNT] u64;
    num_textures: int;
}

BATCHER_MAX_TEXTURE_COUNT :: 14;
BATCHER_INVALID_TEXTURE_INDEX :: 15;
BATCHER_IDENTITY_TRANSFORM_INDEX :: 0;

begin_batcher_frame :: (batcher: *Batcher, estimated_num_quads: int, allocator: Allocator = temp) {
    batcher.vertices.allocator = allocator;
    batcher.indices.allocator = allocator;
    batcher.per_triangle_data.allocator = allocator;
    batcher.object_transform_data.allocator = allocator;

    array_reset(*batcher.vertices);
    array_reset(*batcher.indices);
    array_reset(*batcher.per_triangle_data);
    array_reset(*batcher.object_transform_data);

    estimated_num_vertices := estimated_num_quads * 4;
    array_reserve(*batcher.vertices, estimated_num_vertices);
    array_reserve(*batcher.indices, estimated_num_quads * 6);
    array_reserve(*batcher.per_triangle_data, estimated_num_quads * 2);
    array_reserve(*batcher.object_transform_data, estimated_num_quads);
    // World-space geometry shares one identity transform for the entire frame.
    array_add(*batcher.object_transform_data, .{});

    for texture_index: 0..batcher.textures.count-1 {
        batcher.textures[texture_index] = 0;
    }
    batcher.num_textures = 0;
}

register_texture :: (batcher: *Batcher, texture: u64) -> u8 {
    actual_texture_index: int = BATCHER_INVALID_TEXTURE_INDEX; // Invalid value (invalid index);

    found_texture_index := -1;

    for texture_index: 0..batcher.num_textures-1 {
        if batcher.textures[texture_index] == texture {
            found_texture_index = texture_index;
            break;
        }
    }

    if found_texture_index == -1 {
        if (batcher.num_textures < BATCHER_MAX_TEXTURE_COUNT) {
            batcher.textures[batcher.num_textures] = texture;

            actual_texture_index = batcher.num_textures;

            batcher.num_textures += 1;
        }
        else
        {
            log("Batcher ERROR: Textures overlap. Skipping texture.", flags=.ERROR);
        }
    }
    else
    {
        actual_texture_index = found_texture_index;
    }

    return xx actual_texture_index;
}

#scope_module

pack_batcher_per_triangle_data :: inline (color: Color, texture_index: u8, anti_alias_nearest_neighbour: bool) -> BatcherPerTriangleData {
    assert(texture_index < BATCHER_MAX_TEXTURE_COUNT || texture_index == BATCHER_INVALID_TEXTURE_INDEX);
    texture_bits := cast(u32) texture_index;
    aa_bits := cast(u32) anti_alias_nearest_neighbour;
    return .{packed_data = texture_bits | (aa_bits << 4), packed_color = color.rgba};
}

#scope_export
push_quad_manual :: (batcher: *Batcher,
                     ps: [] BatcherVertex,
                     transform_index: u32,
                     color: Color,
                     texture_index: u8 = xx BATCHER_INVALID_TEXTURE_INDEX,
                     texture_flags: BatcherTextureFlags = 0)
{
    num_before := cast(u32) batcher.vertices.count;

    for i: 0..3 {
        vertex := ps[i];
        vertex.transform_index = transform_index;
        array_add(*batcher.vertices, vertex);
    }
    array_add(*batcher.indices,
              num_before + 0,
              num_before + 1,
              num_before + 2,
              num_before + 0,
              num_before + 2,
              num_before + 3);

    anti_alias_nearest_neighbour: bool = (texture_flags & .ANTIALIAS_NEAREST_NEIGHBOUR) != 0;

    per_triangle_data := pack_batcher_per_triangle_data(color, texture_index, anti_alias_nearest_neighbour);

    array_add(*batcher.per_triangle_data, per_triangle_data, per_triangle_data);
}

#scope_module
get_quad_vertex_data_for_rect_points :: inline (points: [] Vec2) -> [4] BatcherVertex #no_abc {
    quad_data: [4] BatcherVertex = .[
        .{point=points[0], uv=.{0.0, 1.0}},
        .{point=points[1], uv=.{1.0, 1.0}},
        .{point=points[2], uv=.{1.0, 0.0}},
        .{point=points[3], uv=.{0.0, 0.0}},
    ];

    return quad_data;
}

#scope_export
register_transform :: inline (batcher: *Batcher, position: Vec2, rotation: float, scale: float = 1.0) -> u32 {
    return register_transform(batcher, position, complex_from_angle(rotation), scale);
}

register_transform :: inline (batcher: *Batcher, position: Vec2, rotation: Complex, scale: float = 1.0) -> u32 {
    result := cast(u32) batcher.object_transform_data.count;

    transform_data: BatcherObjectTransformData = .{position=position, scaled_rotation=rotation * scale};
    array_add(*batcher.object_transform_data, transform_data);

    return result;
}

#scope_module
push_polygon_internal :: (batcher: *Batcher,
                          ps: [4] Vec2,
                          transform_index: u32,
                          color: Color = Colors.WHITE,
                          texture_index: u8 = xx BATCHER_INVALID_TEXTURE_INDEX,
                          texture_flags: BatcherTextureFlags = 0) #no_abc
{
    quad_data := get_quad_vertex_data_for_rect_points(ps);
    push_quad_manual(batcher, quad_data, transform_index, color, texture_index, texture_flags);
}

push_triangle_internal :: (batcher: *Batcher, p0: Vec2, p1: Vec2, p2: Vec2, transform_index: u32, color: Color = Colors.WHITE) {
    base_vertex := cast(u32) batcher.vertices.count;
    vertices := BatcherVertex.[.{point = p0, transform_index = transform_index},
                              .{point = p1, transform_index = transform_index},
                              .{point = p2, transform_index = transform_index}];
    array_add(*batcher.vertices, vertices[0], vertices[1], vertices[2]);
    array_add(*batcher.indices, base_vertex, base_vertex + 1, base_vertex + 2);

    data := pack_batcher_per_triangle_data(color, xx BATCHER_INVALID_TEXTURE_INDEX, false);
    array_add(*batcher.per_triangle_data, data);
}

push_outline_internal :: (batcher: *Batcher, points: [] Vec2, points_count: int, thickness: float, transform_index: u32, color: Color) {
    MAX_POINTS_FOR_THIS_ALGO :: 128;
    helper_normal_holder: [MAX_POINTS_FOR_THIS_ALGO] Vec2;
    helper_avg_normal_holder: [MAX_POINTS_FOR_THIS_ALGO] Vec2;

    // Calculate normals
    for 0..points_count-1 {
        next_index := (it + 1) % points_count;

        curr_direction := normalize_safe(points[next_index] - points[it]);

        curr_normal := perp(curr_direction);
        helper_normal_holder[it] = curr_normal;
    }

    // Calculate Avg normals
    for 0..points_count-1 {
        prev_index := (it + points_count - 1) % points_count;
        next_index := (it + 1) % points_count;

        curr_normal := helper_normal_holder[it];
        prev_normal := helper_normal_holder[prev_index];

        angle := acos(clamp(dot(curr_normal, prev_normal), -1, 1));
        cos_half_angle := cos(angle * 0.5);
        averaged_normal := normalize_safe(curr_normal + prev_normal);

        helper_avg_normal_holder[it] = averaged_normal / cos_half_angle;
    }

    // Apply normals
    for 0..points_count-1 {
        next_index := (it + 1) % points_count;

        curr_avg_normal := helper_avg_normal_holder[it];
        next_avg_normal := helper_avg_normal_holder[next_index];

        polygon_points: [4] Vec2 = .[
            points[it] + curr_avg_normal * thickness,
            points[next_index] + next_avg_normal * thickness,
            points[next_index],
            points[it],
        ];

        push_polygon_internal(batcher, polygon_points, transform_index, color);
    }
}

#scope_export
push_polygon :: (batcher: *Batcher,
                 ps: [4] Vec2,
                 color: Color = Colors.WHITE,
                 texture_index: u8 = xx BATCHER_INVALID_TEXTURE_INDEX,
                 texture_flags: BatcherTextureFlags = 0) #no_abc
{
    push_polygon_internal(batcher, ps, BATCHER_IDENTITY_TRANSFORM_INDEX, color, texture_index, texture_flags);
}

push_mesh_2d :: (batcher: *Batcher, mesh: Mesh2D, transform: Transform2D, color: Color = Colors.WHITE) {
    triangle_count := get_mesh_triangle_count(mesh);
    if triangle_count == 0 return;

    base_vertex := cast(u32) batcher.vertices.count;
    vertex_count := mesh.vertices.count;

    array_reserve(*batcher.vertices, batcher.vertices.count + vertex_count);
    array_reserve(*batcher.indices, batcher.indices.count + triangle_count * 3);
    array_reserve(*batcher.per_triangle_data, batcher.per_triangle_data.count + triangle_count);
    transform_index := register_transform(batcher, transform.position, transform.rotation, transform.scale);

    // Copy vertices directly into the batcher
    for i: 0..vertex_count-1 {
        vertex: BatcherVertex = .{point = mesh.vertices[i], transform_index = transform_index};
        array_add(*batcher.vertices, vertex);
    }

    // Copy shifted indices directly into the batcher
    if mesh.indices.count > 0 {
        for i: 0..mesh.indices.count - 1 {
            array_add(*batcher.indices, base_vertex + mesh.indices[i]);
        }
    } else {
        for i: 0..vertex_count-1 {
            array_add(*batcher.indices, base_vertex + cast(u32) i);
        }
    }

    // push per triangle data
    data := pack_batcher_per_triangle_data(color, xx BATCHER_INVALID_TEXTURE_INDEX, false);

    for 0..triangle_count-1 {
        array_add(*batcher.per_triangle_data, data);
    }
}

push_quad :: (batcher: *Batcher, position: Vec2, size: float = 1.0, color: Color = Colors.WHITE) {
    rect_points := #run rect_get_points(rect_center_dim(Vec2.{}, Vec2.{1, 1}));

    quad_data := get_quad_vertex_data_for_rect_points(rect_points);
    push_quad_manual(batcher, quad_data, register_transform(batcher, position, 0.0, size), color);
}

push_rect :: (batcher: *Batcher, position: Vec2, rotation: Complex, size: Vec2, color: Color = Colors.WHITE) {
    rect_points := rect_get_points(rect_center_dim(Vec2.{}, size));

    quad_data := get_quad_vertex_data_for_rect_points(rect_points);
    push_quad_manual(batcher, quad_data, register_transform(batcher, position, rotation), color);
}

push_rect :: (batcher: *Batcher, rect: Rect, color: Color = Colors.WHITE) {
    rect_points := rect_get_points(.{radius = rect.radius});
    quad_data := get_quad_vertex_data_for_rect_points(rect_points);
    push_quad_manual(batcher, quad_data, register_transform(batcher, rect.center, 0.0), color);
}

push_rotated_rect_outline :: (batcher: *Batcher,
                              position: Vec2,
                              rotation: Complex,
                              size: Vec2,
                              outline_thickness: float,
                              color: Color = Colors.WHITE)
{
    rect_points := rect_get_points(rect_center_dim(Vec2.{}, size));

    push_outline_internal(batcher, rect_points, 4, outline_thickness, register_transform(batcher, position, rotation), color);
}

push_texture :: (batcher: *Batcher,
                 texture: BatcherTexture,
                 position: Vec2,
                 height: float,
                 align: Vec2 = .{0.5, 0.5},
                 color: Color = Colors.WHITE)
{
    push_rotated_texture(batcher, texture, position, height, 0.0, align, color);
}

push_rotated_texture :: (batcher: *Batcher,
                         texture: BatcherTexture,
                         position: Vec2,
                         height: float,
                         rotation_angle: float = 0.0,
                         align: Vec2 = .{0.5, 0.5},
                         color: Color = Colors.WHITE)
{
    if texture.height == 0 || texture.width == 0 then return; // No need to draw the image of zero size;

    texture_index := register_texture(batcher, texture.handle);
    if texture_index == BATCHER_INVALID_TEXTURE_INDEX return;

    ar: float = cast(float) texture.width / cast(float) texture.height;
    final_image_dim: Vec2 = .{height * ar, height};

    init_offset_rect := rect_align_dim(Vec2.{0, 0}, final_image_dim, align);
    points := rect_get_points(init_offset_rect);
    quad_data := get_quad_vertex_data_for_rect_points(points);

    push_quad_manual(batcher,
                    quad_data,
                    register_transform(batcher, position, rotation_angle),
                    color,
                    texture_index,
                    texture.flags);
}

// Draw an atlas region (normalized UVs) on a local rectangle, transformed as one object.
push_texture_region :: (batcher: *Batcher, texture: BatcherTexture, rect: Rect, uv_rect: Rect,
                        transform: Transform2D, color: Color = Colors.WHITE) {
    if texture.width == 0 || texture.height == 0 return;
    texture_index := register_texture(batcher, texture.handle);
    if texture_index == BATCHER_INVALID_TEXTURE_INDEX return;

    vertices := get_quad_vertex_data_for_rect_points(rect_get_points(rect));
    uv_min := rect_min(uv_rect);
    uv_size := rect_dim(uv_rect);
    for *vertex: vertices vertex.uv = uv_min + vertex.uv * uv_size;
    push_quad_manual(batcher, vertices, register_transform(batcher, transform.position, transform.rotation, transform.scale),
                     color, texture_index, texture.flags);
}

push_triangle :: (batcher: *Batcher, p0: Vec2, p1: Vec2, p2: Vec2, color: Color = Colors.WHITE) {
    push_triangle_internal(batcher, p0, p1, p2, BATCHER_IDENTITY_TRANSFORM_INDEX, color);
}

push_circle_sector :: (batcher: *Batcher,
                       center: Vec2,
                       angle_start: float,
                       angle_end: float,
                       radius_inner: float,
                       radius_outer: float,
                       color: Color = Colors.WHITE,
                       num_segments: int = 24)
{
    if (is_nearly_zero(radius_outer) ||
        values_are_close(radius_inner, radius_outer) ||
        values_are_close(angle_start, angle_end))
    {
        return;
    }

    angle_range := angle_end - angle_start;
    angle_per_segment := angle_range / cast(float) num_segments;
    transform_index := register_transform(batcher, center, 0.0);

    for 0..num_segments-1 {
        segment_angle_start := angle_start + cast(float)it * angle_per_segment;
        segment_angle_end := segment_angle_start + angle_per_segment;

        normal_start := xy(cos(segment_angle_start), sin(segment_angle_start));
        normal_end := xy(cos(segment_angle_end), sin(segment_angle_end));

        point_inner_start := normal_start * radius_inner;
        point_inner_end := normal_end * radius_inner;
        point_outer_start := normal_start * radius_outer;
        point_outer_end := normal_end * radius_outer;

        points := Vec2.[
            point_outer_end,
            point_outer_start,
            point_inner_start,
            point_inner_end
        ];

        push_polygon_internal(batcher, points, transform_index, color);
    }
}

push_circle :: (batcher: *Batcher, center: Vec2, radius: float, color: Color = Colors.WHITE, num_segments: int = 24) {
    push_circle_sector(batcher, center, 0, TAU, 0, radius, color, num_segments);
}

push_circle_outline :: (batcher: *Batcher, center: Vec2, radius: float, outline_thickness: float, color: Color = Colors.WHITE, num_segments: int = 24) {
    push_circle_sector(batcher, center, 0, TAU, radius, radius + outline_thickness, color, num_segments);
}

push_capsule :: (batcher: *Batcher, a: Vec2, b: Vec2, radius: float, color: Color = Colors.WHITE, num_segments_of_half: int = 12) {
    if is_nearly_zero(radius) then return;

    if equal(a, b) {
         push_circle(batcher, a, radius, color, num_segments_of_half * 2);
         return;
    }

    line_dir := push_line_internal(batcher, a, b, radius * 2.0, color);

    line_dir_angle := atan2(line_dir.y, line_dir.x);

    push_circle_sector(batcher, a, line_dir_angle + PI_05, line_dir_angle + PI * 1.5, 0, radius, color, num_segments_of_half);
    push_circle_sector(batcher, b, line_dir_angle - PI_05, line_dir_angle + PI_05, 0, radius, color, num_segments_of_half);
}

push_capsule_outline :: (batcher: *Batcher, a: Vec2, b: Vec2, radius: float, thickness: float, color: Color = Colors.WHITE, num_segments_of_half: int = 12) {
    if equal(a, b) {
         push_circle_outline(batcher, a, radius, thickness, color, num_segments_of_half * 2);
         return;
    }

    line_dir := normalize(b - a);
    line_dir_angle := atan2(line_dir.y, line_dir.x);

    perp_offset := perp(line_dir) * (radius + thickness * 0.5);
    push_line(batcher, a + perp_offset, b + perp_offset, thickness, color);
    push_line(batcher, a - perp_offset, b - perp_offset, thickness, color);

    push_circle_sector(batcher, a, line_dir_angle + PI_05, line_dir_angle + PI * 1.5, radius, radius + thickness, color, num_segments_of_half);
    push_circle_sector(batcher, b, line_dir_angle - PI_05, line_dir_angle + PI_05, radius, radius + thickness, color, num_segments_of_half);
}

#scope_module
push_line_internal :: (batcher: *Batcher, a: Vec2, b: Vec2, thickness: float, color: Color = Colors.WHITE) -> Vec2 {
    if equal(a, b) then return Vec2.{};

    direction, length := normalize_safe_and_get_length(b - a);

    perp_vector := perp(direction);
    perp_offset := perp_vector * thickness * 0.5;

    points: [4] Vec2 = .[
        a + perp_offset,
        b + perp_offset,
        b - perp_offset,
        a - perp_offset
    ];

    push_polygon(batcher, points, color);

    return direction;
}

#scope_export
push_line :: (batcher: *Batcher, a: Vec2, b: Vec2, thickness: float, color: Color = Colors.WHITE) {
    push_line_internal(batcher, a, b, thickness, color);
}

// Arrowhead length and full base width are percentages of line_thickness (100 = 1x).
push_line_with_arrows :: (batcher: *Batcher,
                          begin: Vec2,
                          end: Vec2,
                          line_thickness: float,
                          color: Color = Colors.WHITE,
                          arrow_at_begin: bool = false,
                          arrow_at_end: bool = true,
                          arrowhead_length_percent: float = 400.0,
                          arrowhead_width_percent: float = 300.0)
{
    if line_thickness <= 0 then return;

    direction, line_length := normalize_safe_and_get_length(end - begin);
    if line_length <= DEFAULT_EPSILON then return;

    num_arrowheads := cast(int) arrow_at_begin + cast(int) arrow_at_end;
    if num_arrowheads == 0 || arrowhead_length_percent <= 0 || arrowhead_width_percent <= 0 {
        push_line(batcher, begin, end, line_thickness, color);
        return;
    }

    // Shorten heads on short segments so their bases never cross.
    arrowhead_length := min(line_thickness * arrowhead_length_percent * 0.01,
                            line_length / cast(float) num_arrowheads);
    arrowhead_offset := perp(direction) * (line_thickness * arrowhead_width_percent * 0.01 * 0.5);

    line_begin := begin;
    line_end := end;
    if arrow_at_begin then line_begin += direction * arrowhead_length;
    if arrow_at_end then line_end -= direction * arrowhead_length;

    // Meet the heads at their bases to avoid overlapping translucent geometry.
    push_line(batcher, line_begin, line_end, line_thickness, color);

    if arrow_at_begin {
        push_triangle(batcher, begin, line_begin + arrowhead_offset, line_begin - arrowhead_offset, color);
    }
    if arrow_at_end {
        push_triangle(batcher, end, line_end - arrowhead_offset, line_end + arrowhead_offset, color);
    }
}

push_arrow :: (batcher: *Batcher, begin: Vec2, end: Vec2, line_thickness: float, color: Color = Colors.WHITE) {
    push_line_with_arrows(batcher, begin, end, line_thickness, color);
}

// direction is a displacement: its magnitude determines the arrow's length.
push_direction :: (batcher: *Batcher, pos: Vec2, direction: Vec2, line_thickness: float, color: Color = Colors.WHITE) {
    push_arrow(batcher, pos, pos + direction, line_thickness, color);
}

push_rounded_line :: (batcher: *Batcher, a: Vec2, b: Vec2, thickness: float, color: Color = Colors.WHITE) {
    push_capsule(batcher, a, b, thickness * 0.5, color, 8);
}
