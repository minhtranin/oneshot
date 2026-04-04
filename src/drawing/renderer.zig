const std = @import("std");
const Image = @import("../types.zig").Image;
const Color = @import("../types.zig").Color;
const Point = @import("../types.zig").Point;
const Rect = @import("../types.zig").Rect;

const cairo = @cImport({
    @cInclude("cairo.h");
    @cInclude("pango/pangocairo.h");
});

pub fn drawLine(image: *Image, start: Point, end: Point, color: Color, width: u32) void {
    const surface = cairo.cairo_image_surface_create_for_data(
        image.data.ptr,
        cairo.CAIRO_FORMAT_ARGB32,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.stride),
    );
    defer cairo.cairo_surface_destroy(surface);

    const cr = cairo.cairo_create(surface);
    defer cairo.cairo_destroy(cr);

    // Convert color to 0-1 range
    const r = @as(f64, @floatFromInt(color.r)) / 255.0;
    const g = @as(f64, @floatFromInt(color.g)) / 255.0;
    const b = @as(f64, @floatFromInt(color.b)) / 255.0;
    const a = @as(f64, @floatFromInt(color.a)) / 255.0;

    cairo.cairo_set_source_rgba(cr, r, g, b, a);
    cairo.cairo_set_line_width(cr, @floatFromInt(width));
    cairo.cairo_set_line_cap(cr, cairo.CAIRO_LINE_CAP_ROUND);
    cairo.cairo_set_line_join(cr, cairo.CAIRO_LINE_JOIN_ROUND);

    cairo.cairo_move_to(cr, start.x, start.y);
    cairo.cairo_line_to(cr, end.x, end.y);
    cairo.cairo_stroke(cr);
}

pub fn drawRect(image: *Image, rect: Rect, color: Color, width: u32, fill: bool) void {
    const surface = cairo.cairo_image_surface_create_for_data(
        image.data.ptr,
        cairo.CAIRO_FORMAT_ARGB32,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.stride),
    );
    defer cairo.cairo_surface_destroy(surface);

    const cr = cairo.cairo_create(surface);
    defer cairo.cairo_destroy(cr);

    const r = @as(f64, @floatFromInt(color.r)) / 255.0;
    const g = @as(f64, @floatFromInt(color.g)) / 255.0;
    const b = @as(f64, @floatFromInt(color.b)) / 255.0;
    const a = @as(f64, @floatFromInt(color.a)) / 255.0;

    cairo.cairo_set_source_rgba(cr, r, g, b, a);
    cairo.cairo_set_line_width(cr, @floatFromInt(width));

    if (fill) {
        cairo.cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height);
        cairo.cairo_fill(cr);
    } else {
        cairo.cairo_rectangle(cr, rect.x, rect.y, rect.width, rect.height);
        cairo.cairo_stroke(cr);
    }
}

pub fn drawText(image: *Image, pos: Point, text: []const u8, color: Color, size: u32) !void {
    const surface = cairo.cairo_image_surface_create_for_data(
        image.data.ptr,
        cairo.CAIRO_FORMAT_ARGB32,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.stride),
    );
    defer cairo.cairo_surface_destroy(surface);

    const cr = cairo.cairo_create(surface);
    defer cairo.cairo_destroy(cr);

    const r = @as(f64, @floatFromInt(color.r)) / 255.0;
    const g = @as(f64, @floatFromInt(color.g)) / 255.0;
    const b = @as(f64, @floatFromInt(color.b)) / 255.0;
    const a = @as(f64, @floatFromInt(color.a)) / 255.0;

    cairo.cairo_set_source_rgba(cr, r, g, b, a);

    // Create Pango layout
    const font_map = cairo.pango_cairo_font_map_get_default();
    const context = cairo.pango_font_map_create_context(font_map);
    defer cairo.g_object_unref(context);

    const layout = cairo.pango_layout_new(context);
    defer cairo.g_object_unref(layout);

    // Set text (need to add null terminator for C)
    const text_z = try std.heap.c_allocator.dupeZ(u8, text);
    defer std.heap.c_allocator.free(text_z);

    cairo.pango_layout_set_text(layout, text_z.ptr, -1);

    // Set font
    const font_desc = cairo.pango_font_description_from_string("sans");
    defer cairo.pango_font_description_free(font_desc);

    cairo.pango_font_description_set_absolute_size(font_desc, @as(f64, @floatFromInt(size)) * cairo.PANGO_SCALE);
    cairo.pango_layout_set_font_description(layout, font_desc);

    // Move to position and draw
    cairo.cairo_move_to(cr, pos.x, pos.y);
    cairo.pango_cairo_show_layout(cr, layout);
}

pub fn drawFreehand(image: *Image, points: []const Point, color: Color, width: u32) void {
    if (points.len < 2) return;

    const surface = cairo.cairo_image_surface_create_for_data(
        image.data.ptr,
        cairo.CAIRO_FORMAT_ARGB32,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.stride),
    );
    defer cairo.cairo_surface_destroy(surface);

    const cr = cairo.cairo_create(surface);
    defer cairo.cairo_destroy(cr);

    const r = @as(f64, @floatFromInt(color.r)) / 255.0;
    const g = @as(f64, @floatFromInt(color.g)) / 255.0;
    const b = @as(f64, @floatFromInt(color.b)) / 255.0;
    const a = @as(f64, @floatFromInt(color.a)) / 255.0;

    cairo.cairo_set_source_rgba(cr, r, g, b, a);
    cairo.cairo_set_line_width(cr, @floatFromInt(width));
    cairo.cairo_set_line_cap(cr, cairo.CAIRO_LINE_CAP_ROUND);
    cairo.cairo_set_line_join(cr, cairo.CAIRO_LINE_JOIN_ROUND);

    cairo.cairo_move_to(cr, points[0].x, points[0].y);
    for (points[1..]) |p| {
        cairo.cairo_line_to(cr, p.x, p.y);
    }
    cairo.cairo_stroke(cr);
}

pub fn clearImage(image: *Image, color: Color) void {
    var y: u32 = 0;
    while (y < image.height) : (y += 1) {
        var x: u32 = 0;
        while (x < image.width) : (x += 1) {
            image.setPixel(x, y, color);
        }
    }
}

pub fn copyImage(dest: *Image, source: Image) void {
    const min_width = @min(dest.width, source.width);
    const min_height = @min(dest.height, source.height);

    var y: u32 = 0;
    while (y < min_height) : (y += 1) {
        const src_offset = y * source.stride;
        const dst_offset = y * dest.stride;
        @memcpy(dest.data[dst_offset..][0..min_width * 4], source.data[src_offset..][0..min_width * 4]);
    }
}
