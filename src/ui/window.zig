const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const types = @import("../types.zig");
const Image = types.Image;
const Point = types.Point;
const Rect = types.Rect;
const Color = types.Color;
const Tool = types.Tool;

const canvas_mod = @import("../drawing/canvas.zig");
const clipboard = @import("../clipboard/wayland.zig");

const GdkEventKey = extern struct {
    type_: c.GdkEventType,
    window: ?*c.GdkWindow,
    send_event: i8,
    time: u32,
    state: u32,
    keyval: u32,
    length: i32,
    string: [*c]u8,
    hardware_keycode: u16,
    group: u8,
    is_modifier: u32,
};

const GdkEventButton = extern struct {
    type_: c.GdkEventType,
    window: ?*c.GdkWindow,
    send_event: i8,
    time: u32,
    x: f64,
    y: f64,
    axes: [*c]f64,
    state: u32,
    button: u32,
    device: ?*c.GdkDevice,
    x_root: f64,
    y_root: f64,
};

const GdkEventMotion = extern struct {
    type_: c.GdkEventType,
    window: ?*c.GdkWindow,
    send_event: i8,
    time: u32,
    x: f64,
    y: f64,
    axes: [*c]f64,
    state: u32,
    is_hint: i16,
    device: ?*c.GdkDevice,
    x_root: f64,
    y_root: f64,
};

pub const AppData = struct {
    allocator: std.mem.Allocator,
    window: [*c]c.GtkWidget,
    canvas: canvas_mod.Canvas,
    drawing_area: [*c]c.GtkWidget,
    status_label: [*c]c.GtkWidget,
    start_pos: ?Point = null,
    is_dragging: bool = false,

    colors: [7]Color = .{
        Color.rgb(255, 0, 0),
        Color.rgb(0, 255, 0),
        Color.rgb(0, 0, 255),
        Color.rgb(255, 255, 0),
        Color.rgb(255, 0, 255),
        Color.rgb(255, 255, 255),
        Color.rgb(0, 0, 0),
    },
};

pub fn createWindow(allocator: std.mem.Allocator, screenshot: Image) !*AppData {
    if (c.gtk_init_check(null, null) == 0) {
        return error.GTKInitFailed;
    }

    const window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL);
    c.gtk_window_set_title(@ptrCast(window), "Oneshot - Select Area");
    c.gtk_window_fullscreen(@ptrCast(window));

    const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_container_add(@ptrCast(window), vbox);

    const drawing_area = c.gtk_drawing_area_new();
    c.gtk_box_pack_start(@ptrCast(vbox), drawing_area, 1, 1, 0);
    c.gtk_widget_set_size_request(drawing_area, @intCast(screenshot.width), @intCast(screenshot.height));

    const status_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 10);
    c.gtk_box_pack_start(@ptrCast(vbox), status_box, 0, 0, 5);

    const help_label = c.gtk_label_new(
        \\ L=Line  R=Rect  T=Text  1-7=Colors  Esc=Quit/Cancel
    );
    c.gtk_box_pack_start(@ptrCast(status_box), help_label, 0, 0, 5);

    const status_label = c.gtk_label_new("Drag to select area, then press Enter");
    c.gtk_box_pack_end(@ptrCast(status_box), status_label, 0, 0, 5);

    const app_data = try allocator.create(AppData);
    app_data.* = .{
        .allocator = allocator,
        .window = window,
        .canvas = canvas_mod.Canvas.init(allocator, screenshot),
        .drawing_area = drawing_area,
        .status_label = status_label,
    };

    // Connect signals
    _ = c.g_signal_connect_data(drawing_area, "draw", @ptrCast(&onDraw), app_data, null, 0);
    _ = c.g_signal_connect_data(window, "button-press-event", @ptrCast(&onButtonPress), app_data, null, 0);
    _ = c.g_signal_connect_data(window, "button-release-event", @ptrCast(&onButtonRelease), app_data, null, 0);
    _ = c.g_signal_connect_data(window, "motion-notify-event", @ptrCast(&onMotionNotify), app_data, null, 0);
    _ = c.g_signal_connect_data(window, "key-press-event", @ptrCast(&onKeyPress), app_data, null, 0);
    _ = c.g_signal_connect_data(window, "destroy", @ptrCast(&onDestroy), app_data, null, 0);

    c.gtk_widget_add_events(drawing_area, c.GDK_BUTTON_PRESS_MASK | c.GDK_BUTTON_RELEASE_MASK | c.GDK_POINTER_MOTION_MASK);
    c.gtk_widget_add_events(window, c.GDK_KEY_PRESS_MASK);
    c.gtk_widget_set_can_focus(window, 1);
    c.gtk_widget_grab_focus(window);

    c.gtk_widget_show_all(window);

    return app_data;
}

fn onDraw(_: [*c]c.GtkWidget, cr: *anyopaque, user_data: *AppData) callconv(.C) c.gboolean {
    if (user_data.canvas.selecting_area) {
        // Phase 1: blit raw screenshot directly (no copy), then draw overlay
        // with Cairo compositing — avoids the expensive per-pixel darkening loop.
        const img = &user_data.canvas.base_image;
        const surface = c.cairo_image_surface_create_for_data(
            img.data.ptr,
            c.CAIRO_FORMAT_ARGB32,
            @intCast(img.width),
            @intCast(img.height),
            @intCast(img.stride),
        );
        defer c.cairo_surface_destroy(surface);
        c.cairo_set_source_surface(@ptrCast(cr), surface, 0, 0);
        c.cairo_paint(@ptrCast(cr));

        if (user_data.canvas.selection) |sel| {
            const iw: f64 = @floatFromInt(img.width);
            const ih: f64 = @floatFromInt(img.height);
            const sx: f64 = @floatCast(sel.x);
            const sy: f64 = @floatCast(sel.y);
            const sw: f64 = @floatCast(sel.width);
            const sh: f64 = @floatCast(sel.height);

            c.cairo_set_source_rgba(@ptrCast(cr), 0, 0, 0, 0.5);
            c.cairo_rectangle(@ptrCast(cr), 0, 0, iw, sy);
            c.cairo_fill(@ptrCast(cr));
            c.cairo_rectangle(@ptrCast(cr), 0, sy + sh, iw, ih - sy - sh);
            c.cairo_fill(@ptrCast(cr));
            c.cairo_rectangle(@ptrCast(cr), 0, sy, sx, sh);
            c.cairo_fill(@ptrCast(cr));
            c.cairo_rectangle(@ptrCast(cr), sx + sw, sy, iw - sx - sw, sh);
            c.cairo_fill(@ptrCast(cr));

            c.cairo_set_source_rgba(@ptrCast(cr), 1.0, 0.2, 0.2, 1.0);
            c.cairo_set_line_width(@ptrCast(cr), 3.0);
            c.cairo_rectangle(@ptrCast(cr), sx, sy, sw, sh);
            c.cairo_stroke(@ptrCast(cr));
        }
        return 1;
    }

    // Phase 2: full software render (editor mode, cropped image)
    const rendered = user_data.canvas.render() catch return 0;
    defer rendered.deinit();

    const surface = c.cairo_image_surface_create_for_data(
        rendered.data.ptr,
        c.CAIRO_FORMAT_ARGB32,
        @intCast(rendered.width),
        @intCast(rendered.height),
        @intCast(rendered.stride),
    );
    defer c.cairo_surface_destroy(surface);

    c.cairo_set_source_surface(@ptrCast(cr), surface, 0, 0);
    c.cairo_paint(@ptrCast(cr));
    return 1;
}

fn onButtonPress(_: [*c]c.GtkWidget, event: *anyopaque, user_data: *AppData) callconv(.C) c.gboolean {
    const btn: *const GdkEventButton = @alignCast(@ptrCast(event));
    const pos = Point{ .x = @floatCast(btn.x), .y = @floatCast(btn.y) };

    if (btn.button == 1) {
        if (user_data.canvas.selecting_area) {
            // Phase 1: area selection drag
            user_data.start_pos = pos;
            user_data.is_dragging = true;
        } else {
            // Phase 2: drawing tools
            if (user_data.canvas.tool_state.is_typing) {
                // Commit any in-progress text first
                if (user_data.canvas.commitText() catch null) |obj| {
                    user_data.canvas.addObject(obj) catch {};
                }
            }
            user_data.canvas.startDraw(pos);
        }
        c.gtk_widget_grab_focus(user_data.window);
    }
    return 1;
}

fn onButtonRelease(_: [*c]c.GtkWidget, event: *anyopaque, user_data: *AppData) callconv(.C) c.gboolean {
    const btn: *const GdkEventButton = @alignCast(@ptrCast(event));
    const pos = Point{ .x = @floatCast(btn.x), .y = @floatCast(btn.y) };

    if (btn.button == 1) {
        if (user_data.canvas.selecting_area) {
            // Phase 1: finish area selection
            if (user_data.is_dragging) {
                if (user_data.start_pos) |start| {
                    const r = Rect.fromPoints(start, pos);
                    if (r.width > 5 and r.height > 5) {
                        user_data.canvas.setSelection(r);
                        updateStatus(user_data, "Enter = confirm selection | Esc = quit");
                    } else {
                        user_data.canvas.clearSelection();
                    }
                }
                user_data.is_dragging = false;
                user_data.start_pos = null;
            }
        } else {
            // Phase 2: finish drawing
            const obj = user_data.canvas.endDraw() catch null;
            if (obj) |o| {
                user_data.canvas.addObject(o) catch {};
            }
            if (user_data.canvas.tool_state.is_typing) {
                updateStatus(user_data, "Type text, Enter=done, Esc=cancel text");
            }
        }
        c.gtk_widget_queue_draw(user_data.drawing_area);
    }
    return 1;
}

fn onMotionNotify(_: [*c]c.GtkWidget, event: *anyopaque, user_data: *AppData) callconv(.C) c.gboolean {
    const motion: *const GdkEventMotion = @alignCast(@ptrCast(event));
    const pos = Point{ .x = @floatCast(motion.x), .y = @floatCast(motion.y) };

    if (user_data.canvas.selecting_area and user_data.is_dragging) {
        // Phase 1: update selection preview
        if (user_data.start_pos) |start| {
            user_data.canvas.setSelection(Rect.fromPoints(start, pos));
        }
        c.gtk_widget_queue_draw(user_data.drawing_area);
    } else if (!user_data.canvas.selecting_area) {
        // Phase 2: update drawing preview
        user_data.canvas.updateDraw(pos);
        c.gtk_widget_queue_draw(user_data.drawing_area);
    }
    return 1;
}

fn onKeyPress(_: [*c]c.GtkWidget, event: *anyopaque, user_data: *AppData) callconv(.C) c.gboolean {
    const key_event: *const GdkEventKey = @alignCast(@ptrCast(event));
    const keyval = key_event.keyval;
    const state = key_event.state;
    const ctrl = (state & c.GDK_CONTROL_MASK) != 0;

    // ── Phase 1: Area Selection ──
    if (user_data.canvas.selecting_area) {
        switch (keyval) {
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                if (user_data.canvas.selection != null) {
                    // Crop to selection and enter editor mode
                    _ = user_data.canvas.cropToSelection() catch {
                        updateStatus(user_data, "Crop failed - try again");
                        return 1;
                    };
                    c.gtk_window_set_title(@ptrCast(user_data.window), "Oneshot - Editor");
                    c.gtk_window_unfullscreen(@ptrCast(user_data.window));
                    updateStatus(user_data, "L=line R=rect T=text 1-7=colors Enter=save Esc=quit");
                    c.gtk_widget_queue_draw(user_data.drawing_area);
                }
            },
            c.GDK_KEY_Escape => {
                c.gtk_window_close(@ptrCast(user_data.window));
            },
            else => {},
        }
        return 1;
    }

    // ── Phase 2a: If typing text ──
    if (user_data.canvas.tool_state.is_typing) {
        switch (keyval) {
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                if (user_data.canvas.commitText() catch null) |obj| {
                    user_data.canvas.addObject(obj) catch {};
                }
                updateStatus(user_data, "Text placed");
                c.gtk_widget_queue_draw(user_data.drawing_area);
                return 1;
            },
            c.GDK_KEY_Escape => {
                // Cancel text, go back to tool (don't quit)
                user_data.canvas.tool_state.is_typing = false;
                user_data.canvas.tool_state.text_buffer.clearAndFree();
                updateStatus(user_data, "Text cancelled - Esc again to quit");
                c.gtk_widget_queue_draw(user_data.drawing_area);
                return 1;
            },
            c.GDK_KEY_BackSpace => {
                user_data.canvas.backspace();
                c.gtk_widget_queue_draw(user_data.drawing_area);
                return 1;
            },
            c.GDK_KEY_space => {
                user_data.canvas.typeChar(' ') catch {};
                c.gtk_widget_queue_draw(user_data.drawing_area);
                return 1;
            },
            else => {
                if (keyval >= 0x20 and keyval < 0x7F) {
                    user_data.canvas.typeChar(@intCast(keyval)) catch {};
                    c.gtk_widget_queue_draw(user_data.drawing_area);
                }
                return 1;
            },
        }
    }

    // ── Phase 2b: Editor mode (not typing) ──
    switch (keyval) {
        c.GDK_KEY_Escape => {
            // If a tool is selected, deselect it. If no tool, quit.
            if (user_data.canvas.tool_state.current_tool != .none) {
                user_data.canvas.tool_state.current_tool = .none;
                updateStatus(user_data, "Tool deselected. L/R/T to pick, Esc=quit");
            } else {
                c.gtk_window_close(@ptrCast(user_data.window));
            }
        },
        c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
            doSaveAndClose(user_data, ctrl) catch |err| {
                std.debug.print("[onKeyPress] doSaveAndClose error: {}\n", .{err});
            };
        },
        c.GDK_KEY_l, c.GDK_KEY_L => {
            user_data.canvas.tool_state.current_tool = .line;
            updateStatus(user_data, "Line tool - drag to draw | Esc=deselect");
        },
        c.GDK_KEY_r, c.GDK_KEY_R => {
            user_data.canvas.tool_state.current_tool = .rectangle;
            updateStatus(user_data, "Rectangle tool - drag to draw | Esc=deselect");
        },
        c.GDK_KEY_t, c.GDK_KEY_T => {
            user_data.canvas.tool_state.current_tool = .text;
            updateStatus(user_data, "Text tool - click to place, then type | Esc=cancel");
        },
        c.GDK_KEY_1...c.GDK_KEY_7 => {
            const idx: usize = @intCast(keyval - c.GDK_KEY_1);
            if (idx < user_data.colors.len) {
                user_data.canvas.tool_state.color = user_data.colors[idx];
                updateStatus(user_data, "Color changed");
            }
        },
        else => {},
    }
    return 1;
}

fn onDestroy(_: [*c]c.GtkWidget, user_data: *AppData) callconv(.C) void {
    user_data.canvas.deinit();
    c.gtk_main_quit();
}

fn updateStatus(app_data: *AppData, msg: []const u8) void {
    const msg_z = std.heap.c_allocator.dupeZ(u8, msg) catch return;
    defer std.heap.c_allocator.free(msg_z);
    c.gtk_label_set_text(@ptrCast(app_data.status_label), msg_z.ptr);
}

fn doSaveAndClose(app_data: *AppData, to_file: bool) !void {
    std.debug.print("[doSaveAndClose] to_file={}\n", .{to_file});

    std.debug.print("[doSaveAndClose] calling toPNG...\n", .{});
    const png_data = try app_data.canvas.toPNG(app_data.allocator);
    defer app_data.allocator.free(png_data);
    std.debug.print("[doSaveAndClose] toPNG returned {d} bytes\n", .{png_data.len});

    // Always copy to clipboard
    std.debug.print("[doSaveAndClose] copying to clipboard...\n", .{});
    clipboard.copyImage(app_data.allocator, png_data) catch |err| {
        std.debug.print("[doSaveAndClose] clipboard error: {}\n", .{err});
    };

    // Additionally save to file if Ctrl was pressed
    if (to_file) {
        std.debug.print("[doSaveAndClose] saving to file...\n", .{});
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const documents_dir = try std.fs.path.resolve(app_data.allocator, &.{home, "Pictures"});
        defer app_data.allocator.free(documents_dir);

        const filename = try std.fmt.allocPrint(app_data.allocator, "screenshot_{d}.png", .{std.time.timestamp()});
        defer app_data.allocator.free(filename);

        const filepath = try std.fs.path.join(app_data.allocator, &.{ documents_dir, filename });
        defer app_data.allocator.free(filepath);

        std.fs.makeDirAbsolute(documents_dir) catch {};
        const file = try std.fs.createFileAbsolute(filepath, .{});
        defer file.close();
        try file.writeAll(png_data);
        std.debug.print("Saved to {s}\n", .{filepath});
    }

    std.debug.print("[doSaveAndClose] closing window\n", .{});
    c.gtk_window_close(@ptrCast(app_data.window));
}
