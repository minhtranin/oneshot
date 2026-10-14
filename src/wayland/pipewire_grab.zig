//! Grabs a single frame from a portal ScreenCast PipeWire stream as a cairo
//! ARGB32 image. Raw pixels straight from the compositor: no PNG round trip.
//!
//! SPA pods are built and parsed by hand: translate-c can't compile the
//! spa/pod inline helpers.

const std = @import("std");
const Image = @import("../types.zig").Image;
const dbus_portal = @import("dbus_portal.zig");

const c = @cImport({
    @cInclude("pipewire/pipewire.h");
    @cInclude("spa/param/video/raw.h");
    @cInclude("spa/param/format.h");
    @cInclude("spa/param/param.h");
    @cInclude("spa/buffer/buffer.h");
});

pub const Error = error{
    PipeWireInitFailed,
    StreamConnectFailed,
    FormatTimeout,
    FrameTimeout,
    UnsupportedFormat,
    OutOfMemory,
};

pub const Format = struct {
    width: u32,
    height: u32,
    spa_format: u32,
};

/// Portal ScreenCast → first frame → Image. Session is closed before return.
pub fn captureScreen(allocator: std.mem.Allocator) !Image {
    var session = try dbus_portal.openScreenCast(allocator);
    defer session.close();
    const grab = try Grab.create(allocator, session.pw_fd, session.stream.node_id);
    defer grab.destroy();
    return grab.waitImage(3 * std.time.ns_per_s);
}

const Grab = struct {
    allocator: std.mem.Allocator,
    loop: *c.pw_thread_loop,
    context: *c.pw_context,
    core: *c.pw_core,
    stream: *c.pw_stream,
    hook: c.spa_hook = std.mem.zeroes(c.spa_hook),
    events: c.pw_stream_events = std.mem.zeroes(c.pw_stream_events),

    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},
    format: ?Format = null,
    stream_error: bool = false,
    image: ?Image = null,

    /// Takes ownership of `fd`. Result must not move (callbacks hold a pointer).
    fn create(allocator: std.mem.Allocator, fd: c_int, node_id: u32) Error!*Grab {
        c.pw_init(null, null);

        const loop = c.pw_thread_loop_new("oneshot-pw", null) orelse return Error.PipeWireInitFailed;
        errdefer c.pw_thread_loop_destroy(loop);
        const context = c.pw_context_new(c.pw_thread_loop_get_loop(loop), null, 0) orelse return Error.PipeWireInitFailed;
        errdefer c.pw_context_destroy(context);

        if (c.pw_thread_loop_start(loop) < 0) return Error.PipeWireInitFailed;
        c.pw_thread_loop_lock(loop);
        var locked = true;
        defer if (locked) c.pw_thread_loop_unlock(loop);

        const core = c.pw_context_connect_fd(context, fd, null, 0) orelse return Error.PipeWireInitFailed;
        const props = c.pw_properties_new(
            c.PW_KEY_MEDIA_TYPE,
            "Video",
            c.PW_KEY_MEDIA_CATEGORY,
            "Capture",
            c.PW_KEY_MEDIA_ROLE,
            "Screen",
            @as(?*anyopaque, null),
        );
        const stream = c.pw_stream_new(core, "oneshot", props) orelse return Error.PipeWireInitFailed;

        const self = allocator.create(Grab) catch return Error.OutOfMemory;
        self.* = .{
            .allocator = allocator,
            .loop = loop,
            .context = context,
            .core = core,
            .stream = stream,
        };
        self.events.version = c.PW_VERSION_STREAM_EVENTS;
        self.events.state_changed = onStateChanged;
        self.events.param_changed = onParamChanged;
        self.events.process = onProcess;
        c.pw_stream_add_listener(stream, &self.hook, &self.events, self);

        var pod_buf: [1024]u8 align(8) = undefined;
        var b = PodBuilder{ .buf = &pod_buf };
        const enum_format = buildEnumFormat(&b);
        var params = [_]?*const c.spa_pod{enum_format};

        const flags = c.PW_STREAM_FLAG_AUTOCONNECT | c.PW_STREAM_FLAG_MAP_BUFFERS;
        if (c.pw_stream_connect(stream, c.PW_DIRECTION_INPUT, node_id, flags, @ptrCast(&params), params.len) < 0) {
            c.pw_stream_destroy(stream);
            _ = c.pw_core_disconnect(core);
            c.pw_thread_loop_unlock(loop);
            locked = false;
            allocator.destroy(self);
            return Error.StreamConnectFailed;
        }
        return self;
    }

    fn waitImage(self: *Grab, timeout_ns: u64) Error!Image {
        self.mutex.lock();
        defer self.mutex.unlock();
        var timer = std.time.Timer.start() catch unreachable;
        while (self.image == null and !self.stream_error) {
            const elapsed = timer.read();
            if (elapsed >= timeout_ns) return Error.FrameTimeout;
            self.cond.timedWait(&self.mutex, timeout_ns - elapsed) catch {};
        }
        if (self.stream_error) return Error.StreamConnectFailed;
        const img = self.image.?;
        self.image = null;
        return img;
    }

    fn destroy(self: *Grab) void {
        c.pw_thread_loop_stop(self.loop);
        c.pw_stream_destroy(self.stream);
        _ = c.pw_core_disconnect(self.core);
        c.pw_context_destroy(self.context);
        c.pw_thread_loop_destroy(self.loop);
        if (self.image) |img| img.deinit();
        self.allocator.destroy(self);
    }

    /// Copies one frame into a cairo ARGB32 (BGRA in memory) image.
    fn takeFrame(self: *Grab, src: [*]const u8, src_len: usize, stride: u32) void {
        const fmt = self.format orelse return;
        const w = fmt.width;
        const h = fmt.height;
        const row_bytes = @as(usize, w) * 4;
        if (@as(usize, h - 1) * stride + row_bytes > src_len) return;

        const data = self.allocator.alloc(u8, row_bytes * h) catch return;
        const swap_rb = fmt.spa_format == c.SPA_VIDEO_FORMAT_RGBx or fmt.spa_format == c.SPA_VIDEO_FORMAT_RGBA;
        for (0..h) |row| {
            const in = src[row * stride ..][0..row_bytes];
            const out = data[row * row_bytes ..][0..row_bytes];
            @memcpy(out, in);
            var px: usize = 0;
            while (px < row_bytes) : (px += 4) {
                if (swap_rb) std.mem.swap(u8, &out[px], &out[px + 2]);
                out[px + 3] = 0xff;
            }
        }
        self.image = .{
            .data = data,
            .width = w,
            .height = h,
            .stride = @intCast(row_bytes),
            .allocator = self.allocator,
        };
        self.cond.broadcast();
    }
};

// --- stream callbacks (run on the PipeWire thread) ---

fn onStateChanged(data: ?*anyopaque, _: c.enum_pw_stream_state, state: c.enum_pw_stream_state, err: [*c]const u8) callconv(.c) void {
    const self: *Grab = @ptrCast(@alignCast(data));
    if (state == c.PW_STREAM_STATE_ERROR or state == c.PW_STREAM_STATE_UNCONNECTED) {
        if (err != null) std.log.err("pipewire stream: {s}", .{std.mem.span(err)});
        self.mutex.lock();
        self.stream_error = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }
}

fn onParamChanged(data: ?*anyopaque, id: u32, param: [*c]const c.spa_pod) callconv(.c) void {
    const self: *Grab = @ptrCast(@alignCast(data));
    if (param == null or id != c.SPA_PARAM_Format) return;
    const fmt = parseVideoFormat(param) orelse {
        std.log.err("pipewire: could not parse negotiated format", .{});
        return;
    };

    if (fmt.spa_format != c.SPA_VIDEO_FORMAT_BGRx and fmt.spa_format != c.SPA_VIDEO_FORMAT_BGRA and
        fmt.spa_format != c.SPA_VIDEO_FORMAT_RGBx and fmt.spa_format != c.SPA_VIDEO_FORMAT_RGBA)
    {
        std.log.err("pipewire: unsupported format {d}", .{fmt.spa_format});
        return;
    }
    self.mutex.lock();
    self.format = fmt;
    self.cond.broadcast();
    self.mutex.unlock();

    var pod_buf: [256]u8 align(8) = undefined;
    var b = PodBuilder{ .buf = &pod_buf };
    const start = b.beginObject(c.SPA_TYPE_OBJECT_ParamBuffers, c.SPA_PARAM_Buffers);
    b.prop(c.SPA_PARAM_BUFFERS_dataType);
    b.int((1 << c.SPA_DATA_MemPtr) | (1 << c.SPA_DATA_MemFd));
    const buffers = b.endObject(start);
    var params = [_]?*const c.spa_pod{buffers};
    _ = c.pw_stream_update_params(self.stream, @ptrCast(&params), params.len);
}

fn onProcess(data: ?*anyopaque) callconv(.c) void {
    const self: *Grab = @ptrCast(@alignCast(data));
    // Drain to the newest buffer; older ones are stale.
    var newest: ?*c.pw_buffer = null;
    while (c.pw_stream_dequeue_buffer(self.stream)) |pb| {
        if (newest) |old| _ = c.pw_stream_queue_buffer(self.stream, old);
        newest = pb;
    }
    const pb = newest orelse return;
    defer _ = c.pw_stream_queue_buffer(self.stream, pb);

    const buf = pb.*.buffer;
    if (buf.*.n_datas < 1) return;
    const d = &buf.*.datas[0];
    if (d.data == null) return;
    const chunk = d.chunk;
    if (chunk.*.size == 0 or (chunk.*.flags & c.SPA_CHUNK_FLAG_CORRUPTED) != 0) return;

    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.image != null) return;
    const fmt = self.format orelse return;
    const stride: u32 = if (chunk.*.stride > 0) @intCast(chunk.*.stride) else fmt.width * 4;
    const base: [*]const u8 = @ptrCast(d.data);
    const off: usize = chunk.*.offset;
    if (off >= d.maxsize) return;
    self.takeFrame(base + off, d.maxsize - off, stride);
}

// --- SPA pod building / parsing ---

const PodBuilder = struct {
    buf: []align(8) u8,
    len: usize = 0,

    fn putU32(self: *PodBuilder, v: u32) void {
        std.mem.writeInt(u32, self.buf[self.len..][0..4], v, .little);
        self.len += 4;
    }

    fn pad(self: *PodBuilder) void {
        while (self.len % 8 != 0) {
            self.buf[self.len] = 0;
            self.len += 1;
        }
    }

    fn header(self: *PodBuilder, size: u32, typ: u32) void {
        self.putU32(size);
        self.putU32(typ);
    }

    fn id(self: *PodBuilder, v: u32) void {
        self.header(4, c.SPA_TYPE_Id);
        self.putU32(v);
        self.pad();
    }

    fn int(self: *PodBuilder, v: u32) void {
        self.header(4, c.SPA_TYPE_Int);
        self.putU32(v);
        self.pad();
    }

    fn prop(self: *PodBuilder, key: u32) void {
        self.putU32(key);
        self.putU32(0);
    }

    fn choice(self: *PodBuilder, kind: u32, child_type: u32, child_size: u32, values: []const u32) void {
        const per = child_size / 4;
        const n: u32 = @intCast(values.len / per);
        self.header(16 + n * child_size, c.SPA_TYPE_Choice);
        self.putU32(kind);
        self.putU32(0);
        self.header(child_size, child_type);
        for (values) |v| self.putU32(v);
        self.pad();
    }

    fn beginObject(self: *PodBuilder, typ: u32, obj_id: u32) usize {
        const start = self.len;
        self.header(0, c.SPA_TYPE_Object);
        self.putU32(typ);
        self.putU32(obj_id);
        return start;
    }

    fn endObject(self: *PodBuilder, start: usize) *const c.spa_pod {
        const size: u32 = @intCast(self.len - start - 8);
        std.mem.writeInt(u32, self.buf[start..][0..4], size, .little);
        return @ptrCast(@alignCast(&self.buf[start]));
    }
};

fn buildEnumFormat(b: *PodBuilder) *const c.spa_pod {
    const start = b.beginObject(c.SPA_TYPE_OBJECT_Format, c.SPA_PARAM_EnumFormat);
    b.prop(c.SPA_FORMAT_mediaType);
    b.id(c.SPA_MEDIA_TYPE_video);
    b.prop(c.SPA_FORMAT_mediaSubtype);
    b.id(c.SPA_MEDIA_SUBTYPE_raw);
    b.prop(c.SPA_FORMAT_VIDEO_format);
    b.choice(c.SPA_CHOICE_Enum, c.SPA_TYPE_Id, 4, &.{
        c.SPA_VIDEO_FORMAT_BGRx, // default
        c.SPA_VIDEO_FORMAT_BGRx,
        c.SPA_VIDEO_FORMAT_BGRA,
        c.SPA_VIDEO_FORMAT_RGBx,
        c.SPA_VIDEO_FORMAT_RGBA,
    });
    b.prop(c.SPA_FORMAT_VIDEO_size);
    b.choice(c.SPA_CHOICE_Range, c.SPA_TYPE_Rectangle, 8, &.{ 1920, 1080, 1, 1, 16384, 16384 });
    b.prop(c.SPA_FORMAT_VIDEO_framerate);
    b.choice(c.SPA_CHOICE_Range, c.SPA_TYPE_Fraction, 8, &.{ 60, 1, 0, 1, 1000, 1 });
    return b.endObject(start);
}

fn readU32(p: [*]const u8, off: usize) u32 {
    return std.mem.readInt(u32, p[off..][0..4], .little);
}

/// Extracts format + size from a negotiated SPA_PARAM_Format object.
fn parseVideoFormat(pod: *const c.spa_pod) ?Format {
    const p: [*]const u8 = @ptrCast(pod);
    const size = readU32(p, 0);
    if (readU32(p, 4) != c.SPA_TYPE_Object) return null;
    const end: usize = 8 + size;

    var fmt = Format{ .width = 0, .height = 0, .spa_format = 0 };
    var off: usize = 16; // pod header + object type/id
    while (off + 16 <= end) {
        const key = readU32(p, off);
        var vsize = readU32(p, off + 8);
        var vtype = readU32(p, off + 12);
        var body: usize = off + 16;
        const next = body + std.mem.alignForward(usize, vsize, 8);

        // A fixed value may still be wrapped in a Choice; take its default.
        if (vtype == c.SPA_TYPE_Choice and vsize >= 16) {
            vsize = readU32(p, body + 8);
            vtype = readU32(p, body + 12);
            body += 16;
        }

        if (key == c.SPA_FORMAT_VIDEO_format and vtype == c.SPA_TYPE_Id and vsize >= 4) {
            fmt.spa_format = readU32(p, body);
        } else if (key == c.SPA_FORMAT_VIDEO_size and vtype == c.SPA_TYPE_Rectangle and vsize >= 8) {
            fmt.width = readU32(p, body);
            fmt.height = readU32(p, body + 4);
        }
        off = next;
    }
    if (fmt.width == 0 or fmt.height == 0) return null;
    return fmt;
}

test "enum format pod round-trips size and format via parser" {
    var buf: [1024]u8 align(8) = undefined;
    var b = PodBuilder{ .buf = &buf };
    const start = b.beginObject(c.SPA_TYPE_OBJECT_Format, c.SPA_PARAM_Format);
    b.prop(c.SPA_FORMAT_VIDEO_format);
    b.id(c.SPA_VIDEO_FORMAT_BGRx);
    b.prop(c.SPA_FORMAT_VIDEO_size);
    b.choice(c.SPA_CHOICE_None, c.SPA_TYPE_Rectangle, 8, &.{ 2560, 1440 });
    const pod = b.endObject(start);
    const f = parseVideoFormat(pod).?;
    try std.testing.expectEqual(@as(u32, 2560), f.width);
    try std.testing.expectEqual(@as(u32, 1440), f.height);
    try std.testing.expectEqual(@as(u32, c.SPA_VIDEO_FORMAT_BGRx), f.spa_format);
}
