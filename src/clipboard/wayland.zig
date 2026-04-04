const std = @import("std");

pub const ClipboardError = error{
    CopyFailed,
    CommandNotFound,
    WriteFailed,
};

/// Copy image data to Wayland clipboard using wl-copy
pub fn copyImage(allocator: std.mem.Allocator, data: []const u8) !void {
    std.debug.print("[clipboard] piping {d} bytes to wl-copy...\n", .{data.len});

    var proc = std.process.Child.init(&.{ "wl-copy", "-t", "image/png" }, allocator);
    proc.stdin_behavior = .Pipe;
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;

    try proc.spawn();
    {
        const stdin = proc.stdin.?;
        defer stdin.close();

        try stdin.writeAll(data);
    }
    // wl-copy runs in the foreground serving clipboard requests until a paste
    // occurs — do NOT wait on it or we block forever. It will be reparented to
    // init when our process exits and cleaned up there.
    proc.stdin = null; // already closed above

    std.debug.print("Copied to clipboard\n", .{});
}

/// Alternative method using Wayland data device protocol
/// This is more complex but doesn't require external tools
pub fn copyImageNative(allocator: std.mem.Allocator, data: []const u8) !void {
    _ = allocator;
    _ = data;

    // TODO: Implement native Wayland data device protocol
    // This requires:
    // 1. Connect to Wayland display
    // 2. Get wl_seat and wl_data_device_manager
    // 3. Create data device and data source
    // 4. Set MIME type to "image/png"
    // 5. Offer the data
    // This is complex and requires more Wayland protocol handling

    return error.NotImplemented;
}
