const std = @import("std");
const c = @cImport({
    @cInclude("cairo.h");
});

const Image = @import("../types.zig").Image;
const dbus_portal = @import("dbus_portal.zig");
const pipewire_grab = @import("pipewire_grab.zig");

pub const PortalError = error{
    ScreenshotFailed,
    FileNotFound,
    InvalidResponse,
    Timeout,
};

fn nowMillis() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return @as(i64, @intCast(ts.sec)) * 1000 + @divFloor(@as(i64, @intCast(ts.nsec)), 1_000_000);
}

/// GNOME: portal ScreenCast single frame (raw pixels, ~50ms once the share
/// grant is saved), then the portal Screenshot API, then CLI tools.
/// Elsewhere: grim first (fast on wlroots), then the portals.
pub fn captureScreen(allocator: std.mem.Allocator) !Image {
    if (isGnome()) {
        if (pipewire_grab.captureScreen(allocator)) |img| return img else |e| std.debug.print("screencast capture failed: {}\n", .{e});
        if (captureViaPortal(allocator)) |img| return img else |_| {}
        if (captureViaGnomeScreenshot(allocator)) |img| return img else |_| {}
        if (captureViaGrim(allocator)) |img| return img else |_| {}
    } else {
        if (captureViaGrim(allocator)) |img| return img else |_| {}
        if (captureViaPortal(allocator)) |img| return img else |_| {}
        if (pipewire_grab.captureScreen(allocator)) |img| return img else |_| {}
        if (captureViaGnomeScreenshot(allocator)) |img| return img else |_| {}
    }

    std.debug.print("All screen capture methods failed\n", .{});
    std.debug.print("Ensure you're running on Wayland with a supported compositor\n", .{});
    return PortalError.ScreenshotFailed;
}

fn isGnome() bool {
    const desktop = std.posix.getenv("XDG_CURRENT_DESKTOP") orelse return false;
    return std.mem.indexOf(u8, desktop, "GNOME") != null;
}

fn captureViaPortal(allocator: std.mem.Allocator) !Image {
    const path = try dbus_portal.screenshot(allocator);
    defer allocator.free(path);
    return loadPNG(allocator, path);
}

fn captureViaGrim(allocator: std.mem.Allocator) !Image {
    const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_grim_{d}.png", .{nowMillis()});
    defer allocator.free(temp_file);

    // Use "-s 1" to capture at logical (1:1) resolution so the image matches
    // GTK's logical coordinate system regardless of HiDPI/fractional scaling.
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "grim", "-s", "1", temp_file },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return PortalError.ScreenshotFailed;
    }

    return loadPNG(allocator, temp_file);
}

fn captureViaGnomeScreenshot(allocator: std.mem.Allocator) !Image {
    const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_gnome_{d}.png", .{nowMillis()});
    defer allocator.free(temp_file);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "gnome-screenshot", "-f", temp_file },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return PortalError.ScreenshotFailed;
    }

    return loadPNG(allocator, temp_file);
}

fn loadPNG(allocator: std.mem.Allocator, path: []const u8) !Image {
    // Need null-terminated path for C API
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const surface = c.cairo_image_surface_create_from_png(path_z.ptr);
    if (surface == null) return PortalError.FileNotFound;

    defer c.cairo_surface_destroy(surface);

    const status = c.cairo_surface_status(surface);
    if (status != c.CAIRO_STATUS_SUCCESS) {
        return PortalError.InvalidResponse;
    }

    const width = c.cairo_image_surface_get_width(surface);
    const height = c.cairo_image_surface_get_height(surface);
    const stride = c.cairo_image_surface_get_stride(surface);
    const data = c.cairo_image_surface_get_data(surface);

    const data_len = @as(usize, @intCast(height)) * @as(usize, @intCast(stride));
    const image_data = try allocator.alloc(u8, data_len);
    @memcpy(image_data, data[0..data_len]);

    // Clean up temp file
    std.posix.unlink(path) catch {};

    return Image{
        .data = image_data,
        .width = @intCast(width),
        .height = @intCast(height),
        .stride = @intCast(stride),
        .allocator = allocator,
    };
}

pub fn savePNG(image: Image, path: []const u8) !void {
    std.debug.print("[savePNG] saving {d}x{d} stride={d} to {s}\n", .{ image.width, image.height, image.stride, path });

    const path_z = image.allocator.dupeZ(u8, path) catch return error.WriteFailed;
    defer image.allocator.free(path_z);

    const surface = c.cairo_image_surface_create_for_data(
        image.data.ptr,
        c.CAIRO_FORMAT_ARGB32,
        @intCast(image.width),
        @intCast(image.height),
        @intCast(image.stride),
    );
    if (surface == null) {
        std.debug.print("[savePNG] surface creation returned null\n", .{});
        return error.SurfaceCreationFailed;
    }
    defer c.cairo_surface_destroy(surface);

    const surf_status = c.cairo_surface_status(surface);
    if (surf_status != c.CAIRO_STATUS_SUCCESS) {
        std.debug.print("[savePNG] surface status error: {d}\n", .{surf_status});
        return error.SurfaceCreationFailed;
    }

    const status = c.cairo_surface_write_to_png(surface, path_z.ptr);
    if (status != c.CAIRO_STATUS_SUCCESS) {
        std.debug.print("[savePNG] write_to_png error: {d}\n", .{status});
        return error.WriteFailed;
    }

    std.debug.print("[savePNG] done\n", .{});
}
