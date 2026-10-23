#scope_export
TextAlignX :: enum { LEFT; CENTER; RIGHT; }
TextAlignY :: enum { TOP; CENTER; BOTTOM; }

// UTF-8 text; position is the first line's pen baseline. Coordinates use Y up.
// pixel_height=0 uses the baked size. Newlines and four-space tabs are supported.
print_text :: (batcher: *Batcher, font: *Font, text: string, position: Vec2,
               color: Color = Colors.WHITE, pixel_height: float = 0, shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{center = position};
    layout := get_text_layout(font, text, shape_params);
    return print_text_layout(batcher, font, layout, scale, position, color);
}

// Aligns the metric rectangle (ascent/descent + shaped advances/ink overhangs), not the baseline.
// Each line aligns horizontally on its own. Does not wrap or clip overflowing text.
print_text_in_rect_aligned :: (batcher: *Batcher, font: *Font, text: string, rect: Rect,
                               align_x: TextAlignX = .LEFT, align_y: TextAlignY = .TOP,
                               color: Color = Colors.WHITE, pixel_height: float = 0,
                               shape_params: TextShapeParams = .{}) -> Rect {
    return print_text_in_rect_aligned(batcher, font, text, rect, text_alignment(align_x, align_y), color, pixel_height, shape_params);
}

// align: X=0 left, 0.5 center, 1 right; Y=0 bottom, 0.5 center, 1 top.
print_text_in_rect_aligned :: (batcher: *Batcher, font: *Font, text: string, rect: Rect,
                               align: Vec2, color: Color = Colors.WHITE, pixel_height: float = 0,
                               shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{center = rect.center};
    layout := get_text_layout(font, text, shape_params);
    return print_text_layout_aligned(batcher, font, layout, scale, rect, align, color);
}

// Bounds relative to the first baseline; uses exactly the same shaping/layout as print_text.
measure_text :: (font: *Font, text: string, pixel_height: float = 0, shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{};
    return scale_text_bounds(get_text_layout(font, text, shape_params).bounds, scale);
}

// Resolves missing/unsupported translations to English (then ???), carrying the actual language into the cache.
print_localized_text :: (batcher: *Batcher, font: *Font, table: *LocalizationTable, key: LocalizationKey,
                         language: TextLanguage, position: Vec2, color: Color = Colors.WHITE,
                         pixel_height: float = 0, shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{center = position};
    layout := get_localized_text_layout(font, get_localized_text_for_font(font, table, key, language, shape_params), shape_params);
    return print_text_layout(batcher, font, layout, scale, position, color);
}

// Same language/cache rules as print_localized_text; aligns each line on X and the block on Y.
print_localized_text_in_rect_aligned :: (batcher: *Batcher, font: *Font, table: *LocalizationTable,
                                         key: LocalizationKey, language: TextLanguage, rect: Rect,
                                         align_x: TextAlignX = .LEFT, align_y: TextAlignY = .TOP,
                                         color: Color = Colors.WHITE, pixel_height: float = 0,
                                         shape_params: TextShapeParams = .{}) -> Rect {
    return print_localized_text_in_rect_aligned(batcher, font, table, key, language, rect, text_alignment(align_x, align_y), color, pixel_height, shape_params);
}

// align uses the same normalized X/Y coordinates as print_text_in_rect_aligned.
print_localized_text_in_rect_aligned :: (batcher: *Batcher, font: *Font, table: *LocalizationTable,
                                         key: LocalizationKey, language: TextLanguage, rect: Rect,
                                         align: Vec2, color: Color = Colors.WHITE, pixel_height: float = 0,
                                         shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{center = rect.center};
    layout := get_localized_text_layout(font, get_localized_text_for_font(font, table, key, language, shape_params), shape_params);
    return print_text_layout_aligned(batcher, font, layout, scale, rect, align, color);
}

measure_localized_text :: (font: *Font, table: *LocalizationTable, key: LocalizationKey,
                           language: TextLanguage, pixel_height: float = 0, shape_params: TextShapeParams = .{}) -> Rect {
    scale := text_draw_scale(font, pixel_height);
    if scale <= 0 return .{};
    layout := get_localized_text_layout(font, get_localized_text_for_font(font, table, key, language, shape_params), shape_params);
    return scale_text_bounds(layout.bounds, scale);
}

#scope_module
text_alignment :: (x: TextAlignX, y: TextAlignY) -> Vec2 {
    result: Vec2;
    if #complete x == {
        case .LEFT; result.x = 0;
        case .CENTER; result.x = 0.5;
        case .RIGHT; result.x = 1;
    }
    if #complete y == {
        case .TOP; result.y = 1;
        case .CENTER; result.y = 0.5;
        case .BOTTOM; result.y = 0;
    }
    return result;
}

text_draw_scale :: (font: *Font, height: float) -> float {
    if font.pixel_height <= 0 || !is_finite(height) || height < 0 return 0;
    return ifx height == 0 then 1.0 else height / cast(float) font.pixel_height;
}
scale_text_bounds :: (bounds: Rect, scale: float) -> Rect { return .{bounds.center * scale, bounds.radius * scale}; }

print_text_layout :: (batcher: *Batcher, font: *Font, layout: TextLayout, scale: float, position: Vec2, color: Color) -> Rect {
    draw_text_glyphs(batcher, font, layout.glyphs, scale, position, color);
    bounds := scale_text_bounds(layout.bounds, scale);
    bounds.center += position;
    return bounds;
}

print_text_layout_aligned :: (batcher: *Batcher, font: *Font, layout: TextLayout, scale: float, rect: Rect,
                              align: Vec2, color: Color) -> Rect {
    if layout.lines.count == 0 return .{center = rect.center};
    bounds := scale_text_bounds(layout.bounds, scale);
    low := rect_min(rect);
    high := rect_max(rect);
    origin: Vec2;
    origin.y = low.y - rect_min(bounds).y + ((high.y - low.y) - 2 * bounds.radius.y) * align.y;
    for line: layout.lines {
        x := low.x - line.min_x * scale + ((high.x - low.x) - (line.max_x - line.min_x) * scale) * align.x;
        // Alignment changes only the draw origin; shared cached positions stay immutable.
        glyphs := array_view(layout.glyphs, line.first, line.count);
        draw_text_glyphs(batcher, font, glyphs, scale, .{x, origin.y}, color);
    }
    result := bounds;
    widest: float;
    for line: layout.lines widest = max(widest, (line.max_x * scale) - (line.min_x * scale));
    result.radius.x = widest * 0.5;
    result.center.y += origin.y;
    result.center.x = low.x + result.radius.x + ((high.x - low.x) - widest) * align.x;
    return result;
}

draw_text_glyphs :: (batcher: *Batcher, font: *Font, glyphs: [] PlacedTextGlyph, scale: float, origin: Vec2, color: Color) {
    if glyphs.count == 0 || font.atlas.handle == 0 return;
    texture_index := register_texture(batcher, font.atlas.handle);
    if texture_index == BATCHER_INVALID_TEXTURE_INDEX return;
    transform_index := register_transform(batcher, origin, 0.0, scale);
    for item: glyphs {
        glyph := item.glyph;
        low := item.position + glyph.offset;
        high := low + Vec2.{cast(float) glyph.atlas_width, cast(float) glyph.atlas_height};
        uv0 := glyph.min_uv_in_atlas;
        uv1 := glyph.max_uv_in_atlas;
        vertices := BatcherVertex.[
            .{point = .{low.x, high.y}, uv = .{uv0.x, uv1.y}},
            .{point = high, uv = uv1},
            .{point = .{high.x, low.y}, uv = .{uv1.x, uv0.y}},
            .{point = low, uv = uv0}
        ];
        push_quad_manual(batcher, vertices, transform_index, color, texture_index, font.atlas.flags);
    }
}
