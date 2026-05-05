const std = @import("std");
const c = @cImport({
    @cInclude("cairo.h");
});

const Image = @import("../types.zig").Image;

pub const PortalError = error{
    ScreenshotFailed,
    FileNotFound,
    InvalidResponse,
    Timeout,
};

/// Capture screen using FreeDesktop Portal (works on GNOME Wayland).
/// Falls back to grim / gnome-screenshot if portal is unavailable.
pub fn captureScreen(allocator: std.mem.Allocator) !Image {
    // Try FreeDesktop Portal first (works on GNOME Wayland)
    if (captureViaPortal(allocator)) |img| {
        return img;
    } else |_| {
        // fallback
    }

    // Try grim (wlroots compositors)
    if (captureViaGrim(allocator)) |img| {
        return img;
    } else |_| {
        // fallback
    }

    // Try gnome-screenshot
    if (captureViaGnomeScreenshot(allocator)) |img| {
        return img;
    } else |_| {
        // fallback
    }

    std.debug.print("All screen capture methods failed\n", .{});
    std.debug.print("Ensure you're running on Wayland with a supported compositor\n", .{});
    return PortalError.ScreenshotFailed;
}

fn captureViaPortal(allocator: std.mem.Allocator) !Image {
    const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_portal_{d}.png", .{std.time.milliTimestamp()});
    defer allocator.free(temp_file);

    // Write a small Python helper script to call the portal.
    // This is the most reliable method on GNOME Wayland.
    const script_path = try std.fmt.allocPrint(allocator, "/tmp/oneshot_portal_{d}.py", .{std.time.milliTimestamp()});
    defer allocator.free(script_path);

    const script_content =
        \\import dbus, gi, os, sys, urllib.parse
        \\from gi.repository import GLib
        \\from dbus.mainloop.glib import DBusGMainLoop
        \\
        \\DBusGMainLoop(set_as_default=True)
        \\bus = dbus.SessionBus()
        \\portal = bus.get_object('org.freedesktop.portal.Desktop',
        \\                        '/org/freedesktop/portal/desktop')
        \\iface = dbus.Interface(portal, 'org.freedesktop.portal.Screenshot')
        \\
        \\loop = GLib.MainLoop()
        \\timed_out = [False]
        \\
        \\def on_response(handle, results):
        \\    uri = str(results.get('uri', ''))
        \\    if uri.startswith('file://'):
        \\        path = urllib.parse.unquote(uri[7:])
        \\    else:
        \\        path = uri
        \\    if path and os.path.exists(path):
        \\        out = sys.argv[1]
        \\        with open(path, 'rb') as f:
        \\            data = f.read()
        \\        with open(out, 'wb') as f:
        \\            f.write(data)
        \\        try:
        \\            os.unlink(path)
        \\        except:
        \\            pass
        \\        print('OK')
        \\    else:
        \\        print('FAIL: no uri in response')
        \\    loop.quit()
        \\
        \\def on_timeout():
        \\    timed_out[0] = True
        \\    print('TIMEOUT')
        \\    loop.quit()
        \\
        \\request_path = iface.Screenshot('', {})
        \\bus.add_signal_receiver(
        \\    on_response,
        \\    signal_name='Response',
        \\    dbus_interface='org.freedesktop.portal.Request',
        \\    path=str(request_path),
        \\    bus_name='org.freedesktop.portal.Desktop',
        \\)
        \\
        \\GLib.timeout_add_seconds(15, on_timeout)
        \\loop.run()
        \\
        \\if timed_out[0]:
        \\    sys.exit(2)
    ;

    // Write script to file
    const script_file = try std.fs.createFileAbsolute(script_path, .{});
    defer script_file.close();
    try script_file.writeAll(script_content);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", script_path, temp_file },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("Portal capture failed (exit={d}): {s}\n", .{ result.term.Exited, result.stderr });
        return PortalError.ScreenshotFailed;
    }

    // Check stdout contains OK
    if (std.mem.indexOf(u8, result.stdout, "OK") == null) {
        std.debug.print("Portal capture unexpected output: {s}\n", .{result.stdout});
        std.posix.unlink(script_path) catch {};
        return PortalError.ScreenshotFailed;
    }

    // Clean up script file
    std.posix.unlink(script_path) catch {};

    return loadPNG(allocator, temp_file);
}

fn captureViaGrim(allocator: std.mem.Allocator) !Image {
    const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_grim_{d}.png", .{std.time.milliTimestamp()});
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
    const temp_file = try std.fmt.allocPrint(allocator, "/tmp/oneshot_gnome_{d}.png", .{std.time.milliTimestamp()});
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
