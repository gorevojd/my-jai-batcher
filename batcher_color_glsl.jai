// GLSL 3.30 decoders for the MyMath packed linear RGBA formats. Add after #version.
// PACK_U32 uses an RG32UI record (flags, RGBA8); PACK_U64 uses RGBA32UI (flags, 0, low, high).
#assert cast(u32) ColorPackMode.PACK_U32 == 0 && cast(u32) ColorPackMode.PACK_U64 == 1;
// Check the CPU encoding contract without depending on MyMath's private declarations.
#assert #run pack_rgba_to_u64(Linear_Color.{1.0, 0.0, 0.0, 0.0}) == 0x000000000003c000;
#assert #run pack_rgba_to_u64(Linear_Color.{0.0, 1.0, 0.0, 0.0}) == 0x0000001e00000000;
#assert #run pack_rgba_to_u64(Linear_Color.{0.0, 0.0, 1.0, 0.0}) == 0x0078000000000000;
#assert #run pack_rgba_to_u64(Linear_Color.{0.0, 0.0, 0.0, 1.0}) == 0xff00000000000000;
#assert #run pack_rgba_to_u64(Linear_Color.{65534.0, 65534.0, 65532.0, 1.0}) == 0xfff7fffdffffbfff;

PACKED_COLOR_GLSL :: #string PACKED_RGBA64_GLSL

vec4 unpack_rgba_from_u32(uint value)
{
    return vec4(
        float(value & 255u),
        float((value >> 8u) & 255u),
        float((value >> 16u) & 255u),
        float(value >> 24u)
    ) * (1.0 / 255.0);
}

float unpack_rgba_u64_channel(uint value, uint fraction_bits)
{
    uint fraction_mask = (1u << fraction_bits) - 1u;
    uint fraction = value & fraction_mask;
    uint exponent = value >> fraction_bits;
    if (exponent == 0u) {
        float quantum = uintBitsToFloat((113u - fraction_bits) << 23u);
        return float(fraction) * quantum;
    }
    if (exponent == 31u) {
        exponent = 30u;
        fraction = fraction_mask;
    }
    uint float_bits = ((exponent + 112u) << 23u) | (fraction << (23u - fraction_bits));
    return uintBitsToFloat(float_bits);
}

vec4 unpack_rgba_from_u64(uvec2 words)
{
    uint red = words.x & 0x7ffffu;
    uint green = ((words.x >> 19u) | (words.y << 13u)) & 0x7ffffu;
    uint blue = (words.y >> 6u) & 0x3ffffu;
    uint alpha = words.y >> 24u;
    return vec4(
        unpack_rgba_u64_channel(red, 14u),
        unpack_rgba_u64_channel(green, 14u),
        unpack_rgba_u64_channel(blue, 13u),
        float(alpha) * (1.0 / 255.0)
    );
}

vec4 unpack_batcher_color(uvec4 triangle_data, int color_pack_mode)
{
    if (color_pack_mode == 0) {
        return unpack_rgba_from_u32(triangle_data.y);
    }
    return unpack_rgba_from_u64(triangle_data.zw);
}

PACKED_RGBA64_GLSL;
