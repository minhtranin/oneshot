const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const portal = @import("wayland/portal.zig");
const window = @import("ui/window.zig");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("Oneshot Screenshot Tool\n", .{});
    std.debug.print("Capturing screen...\n", .{});

    // Capture screen
    const screenshot = portal.captureScreen(allocator) catch |err| {
        std.debug.print("Failed to capture screen: {}\n", .{err});
        std.debug.print("Make sure you have 'grim' or 'gnome-screenshot' installed\n", .{});
        std.debug.print("\nInstall with: sudo apt install grim wl-clipboard\n", .{});
        return err;
    };

    std.debug.print("Screen captured: {}x{}\n", .{ screenshot.width, screenshot.height });

    // Canvas takes ownership of screenshot data - do NOT defer screenshot.deinit()
    const app_data = window.createWindow(allocator, screenshot) catch {
        screenshot.deinit();
        return error.WindowCreationFailed;
    };

    std.debug.print("\nKeys:\n", .{});
    std.debug.print("  L       - Line tool\n", .{});
    std.debug.print("  R       - Rectangle tool\n", .{});
    std.debug.print("  T       - Text tool\n", .{});
    std.debug.print("  1-7     - Colors (Red, Green, Blue, Yellow, Magenta, White, Black)\n", .{});
    std.debug.print("  Drag    - Select area\n", .{});
    std.debug.print("  Enter   - Save to clipboard\n", .{});
    std.debug.print("  Ctrl+Enter - Save to ~/Documents\n", .{});
    std.debug.print("  Esc     - Quit\n\n", .{});

    // Run GTK main loop
    c.gtk_main();

    allocator.destroy(app_data);
}
