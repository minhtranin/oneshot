const std = @import("std");
const types = @import("../types.zig");
const Image = types.Image;
const Color = types.Color;
const Point = types.Point;
const Rect = types.Rect;
const DrawObject = types.DrawObject;
const ToolState = types.ToolState;
const renderer = @import("renderer.zig");

pub const Canvas = struct {
    allocator: std.mem.Allocator,
    base_image: Image,
    objects: std.ArrayList(DrawObject),
    selection: ?Rect = null,
    tool_state: ToolState = .{},
    /// When true, we're in the initial "select area" phase
    selecting_area: bool = true,

    pub fn init(allocator: std.mem.Allocator, base_image: Image) Canvas {
        var c = Canvas{
            .allocator = allocator,
            .base_image = base_image,
            .objects = std.ArrayList(DrawObject).init(allocator),
        };
        c.tool_state.initTextBuffer(allocator);
        return c;
    }

    pub fn deinit(self: *Canvas) void {
        for (self.objects.items) |obj| {
            switch (obj) {
                .text => |t| self.allocator.free(t.text),
                .freehand => |f| self.allocator.free(f.points),
                else => {},
            }
        }
        self.objects.deinit();
        self.tool_state.deinitTextBuffer();
        self.base_image.deinit();
    }

    pub fn addObject(self: *Canvas, obj: DrawObject) !void {
        try self.objects.append(obj);
    }

    /// Crop the base image to the current selection and switch to editor mode.
    /// Returns the old base image so caller can deinit it.
    pub fn cropToSelection(self: *Canvas) !Image {
        const sel = self.selection orelse return error.NoSelection;
        const sx: u32 = @intFromFloat(@max(sel.x, 0));
        const sy: u32 = @intFromFloat(@max(sel.y, 0));
        const sw: u32 = @intFromFloat(@min(sel.width, @as(f32, @floatFromInt(self.base_image.width)) - @as(f32, @floatFromInt(sx))));
        const sh: u32 = @intFromFloat(@min(sel.height, @as(f32, @floatFromInt(self.base_image.height)) - @as(f32, @floatFromInt(sy))));

        if (sw == 0 or sh == 0) return error.InvalidSelection;

        const cropped = try Image.init(self.allocator, sw, sh);
        var y: u32 = 0;
        while (y < sh) : (y += 1) {
            const src_row = (sy + y) * self.base_image.stride + sx * 4;
            const dst_row = y * cropped.stride;
            @memcpy(
                cropped.data[dst_row .. dst_row + sw * 4],
                self.base_image.data[src_row .. src_row + sw * 4],
            );
        }

        // Swap: free old base, set new cropped base
        self.base_image.deinit();
        self.base_image = cropped;
        self.selection = null;
        self.selecting_area = false;
        self.tool_state.current_tool = .draw;
        return cropped;
    }

    pub fn startDraw(self: *Canvas, pos: Point) void {
        self.tool_state.start_pos = pos;
        self.tool_state.current_pos = pos;
        self.tool_state.is_drawing = true;
        if (self.tool_state.current_tool == .draw) {
            self.tool_state.freehand_points.clearRetainingCapacity();
            self.tool_state.freehand_points.append(pos) catch {};
        }
    }

    pub fn updateDraw(self: *Canvas, pos: Point) void {
        self.tool_state.current_pos = pos;
        if (self.tool_state.current_tool == .draw and self.tool_state.is_drawing) {
            self.tool_state.freehand_points.append(pos) catch {};
        }
    }

    pub fn endDraw(self: *Canvas) !?DrawObject {
        defer {
            self.tool_state.is_drawing = false;
            self.tool_state.start_pos = null;
        }

        const start = self.tool_state.start_pos orelse return null;

        return switch (self.tool_state.current_tool) {
            .line => DrawObject{
                .line = .{
                    .start = start,
                    .end = self.tool_state.current_pos,
                    .color = self.tool_state.color,
                    .width = self.tool_state.line_width,
                },
            },
            .rectangle => DrawObject{
                .rectangle = .{
                    .rect = Rect.fromPoints(start, self.tool_state.current_pos),
                    .color = self.tool_state.color,
                    .width = self.tool_state.line_width,
                    .fill = false,
                },
            },
            .text => {
                self.tool_state.is_typing = true;
                self.tool_state.text_pos = start;
                self.tool_state.text_buffer.clearAndFree();
                return null;
            },
            .draw => {
                const pts = self.tool_state.freehand_points.items;
                if (pts.len < 2) return null;
                const owned = self.allocator.dupe(Point, pts) catch return null;
                return DrawObject{ .freehand = .{
                    .points = owned,
                    .color = self.tool_state.color,
                    .width = self.tool_state.line_width,
                }};
            },
            else => null,
        };
    }

    pub fn typeChar(self: *Canvas, ch: u8) !void {
        if (!self.tool_state.is_typing) return;
        try self.tool_state.text_buffer.append(ch);
    }

    pub fn backspace(self: *Canvas) void {
        if (!self.tool_state.is_typing) return;
        if (self.tool_state.text_buffer.items.len > 0) {
            _ = self.tool_state.text_buffer.pop();
        }
    }

    pub fn commitText(self: *Canvas) !?DrawObject {
        if (!self.tool_state.is_typing) return null;
        self.tool_state.is_typing = false;

        if (self.tool_state.text_buffer.items.len == 0) return null;

        const text = try self.allocator.dupe(u8, self.tool_state.text_buffer.items);
        self.tool_state.text_buffer.clearAndFree();

        return DrawObject{
            .text = .{
                .pos = self.tool_state.text_pos,
                .text = text,
                .color = self.tool_state.color,
                .size = 20,
            },
        };
    }

    pub fn setSelection(self: *Canvas, rect: Rect) void {
        self.selection = rect.normalize();
    }

    pub fn clearSelection(self: *Canvas) void {
        self.selection = null;
    }

    pub fn render(self: *const Canvas) !Image {
        var output = try Image.init(
            self.allocator,
            self.base_image.width,
            self.base_image.height,
        );
        @memcpy(output.data, self.base_image.data);

        // Draw committed objects
        for (self.objects.items) |obj| {
            drawObject(&output, obj);
        }

        // Draw current shape in progress
        if (self.tool_state.is_drawing) {
            if (self.tool_state.start_pos) |start| {
                switch (self.tool_state.current_tool) {
                    .line => {
                        renderer.drawLine(
                            &output,
                            start,
                            self.tool_state.current_pos,
                            self.tool_state.color,
                            self.tool_state.line_width,
                        );
                    },
                    .rectangle => {
                        const rect = Rect.fromPoints(start, self.tool_state.current_pos);
                        renderer.drawRect(&output, rect, self.tool_state.color, self.tool_state.line_width, false);
                    },
                    .draw => {
                        renderer.drawFreehand(
                            &output,
                            self.tool_state.freehand_points.items,
                            self.tool_state.color,
                            self.tool_state.line_width,
                        );
                    },
                    else => {},
                }
            }
        }

        // Draw text being typed
        if (self.tool_state.is_typing and self.tool_state.text_buffer.items.len > 0) {
            renderer.drawText(
                &output,
                self.tool_state.text_pos,
                self.tool_state.text_buffer.items,
                self.tool_state.color,
                20,
            ) catch {};
            // Cursor bar
            const cursor_x = self.tool_state.text_pos.x + @as(f32, @floatFromInt(self.tool_state.text_buffer.items.len * 10));
            renderer.drawLine(
                &output,
                .{ .x = cursor_x, .y = self.tool_state.text_pos.y },
                .{ .x = cursor_x, .y = self.tool_state.text_pos.y + 20 },
                self.tool_state.color,
                2,
            );
        }

        // Selection overlay (phase 1 or if drawing selection)
        if (self.selection) |sel| {
            renderer.drawRect(&output, sel, Color.rgb(255, 50, 50), 3, false);
            try drawOverlay(&output, sel);
        }

        return output;
    }

    fn drawObject(image: *Image, obj: DrawObject) void {
        switch (obj) {
            .line => |line| {
                renderer.drawLine(image, line.start, line.end, line.color, line.width);
            },
            .rectangle => |rect| {
                renderer.drawRect(image, rect.rect, rect.color, rect.width, rect.fill);
            },
            .text => |text| {
                renderer.drawText(image, text.pos, text.text, text.color, text.size) catch {};
            },
            .freehand => |fh| {
                renderer.drawFreehand(image, fh.points, fh.color, fh.width);
            },
        }
    }

    fn drawOverlay(image: *Image, selection: Rect) !void {
        const width = image.width;
        const height = image.height;

        var y: u32 = 0;
        while (y < height) : (y += 1) {
            var x: u32 = 0;
            while (x < width) : (x += 1) {
                const px: f32 = @floatFromInt(x);
                const py: f32 = @floatFromInt(y);
                if (!(px >= selection.x and px <= selection.x + selection.width and
                    py >= selection.y and py <= selection.y + selection.height))
                {
                    var pixel = image.getPixel(x, y);
                    pixel.r = @divTrunc(pixel.r, @as(u8, 3));
                    pixel.g = @divTrunc(pixel.g, @as(u8, 3));
                    pixel.b = @divTrunc(pixel.b, @as(u8, 3));
                    image.setPixel(x, y, pixel);
                }
            }
        }
    }

    pub fn saveToFile(self: *const Canvas, path: []const u8) !void {
        std.debug.print("[saveToFile] rendering...\n", .{});
        const rendered = try self.render();
        defer rendered.deinit();
        std.debug.print("[saveToFile] rendered {d}x{d}, writing to {s}\n", .{ rendered.width, rendered.height, path });
        const portal = @import("../wayland/portal.zig");
        try portal.savePNG(rendered, path);
        std.debug.print("[saveToFile] done\n", .{});
    }

    pub fn toPNG(self: *const Canvas, allocator: std.mem.Allocator) ![]u8 {
        std.debug.print("[toPNG] starting (base_image {d}x{d}, {d} objects)\n", .{ self.base_image.width, self.base_image.height, self.objects.items.len });

        const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_save_{d}.png", .{
            std.time.milliTimestamp(),
        });
        defer allocator.free(temp_file);

        try self.saveToFile(temp_file);

        std.debug.print("[toPNG] reading back temp file...\n", .{});
        const file = try std.fs.openFileAbsolute(temp_file, .{});
        defer file.close();

        const data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        std.posix.unlink(temp_file) catch {};

        std.debug.print("[toPNG] got {d} bytes\n", .{data.len});
        return data;
    }
};
