const std = @import("std");

pub const Point = struct {
    x: f32,
    y: f32,

    pub fn distance(self: Point, other: Point) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn contains(self: Rect, p: Point) bool {
        return p.x >= self.x and p.x <= self.x + self.width and
               p.y >= self.y and p.y <= self.y + self.height;
    }

    pub fn normalize(self: Rect) Rect {
        var result = self;
        if (result.width < 0) {
            result.x += result.width;
            result.width = @abs(result.width);
        }
        if (result.height < 0) {
            result.y += result.height;
            result.height = @abs(result.height);
        }
        return result;
    }

    pub fn fromPoints(p1: Point, p2: Point) Rect {
        return .{
            .x = @min(p1.x, p2.x),
            .y = @min(p1.y, p2.y),
            .width = @abs(p2.x - p1.x),
            .height = @abs(p2.y - p1.y),
        };
    }

    pub fn fromPointsNormalized(p1: Point, p2: Point) Rect {
        return fromPoints(p1, p2).normalize();
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
               (@as(u32, self.r) << 16) |
               (@as(u32, self.g) << 8) |
               @as(u32, self.b);
    }
};

pub const Tool = enum {
    none,
    select,
    line,
    rectangle,
    text,
    draw,

    pub fn toString(self: Tool) []const u8 {
        return switch (self) {
            .none => "None",
            .select => "Select",
            .line => "Line",
            .rectangle => "Rectangle",
            .text => "Text",
            .draw => "Draw",
        };
    }
};

pub const ToolState = struct {
    current_tool: Tool = .none,
    color: Color = Color.rgb(255, 0, 0),
    line_width: u32 = 3,
    start_pos: ?Point = null,
    current_pos: Point = .{ .x = 0, .y = 0 },
    is_drawing: bool = false,

    // Text input state
    is_typing: bool = false,
    text_buffer: std.ArrayList(u8) = .empty,
    text_pos: Point = .{ .x = 0, .y = 0 },

    // Freehand draw state
    freehand_points: std.ArrayList(Point) = .empty,

    // Allocator stored for deinit
    allocator: std.mem.Allocator = undefined,

    pub fn initTextBuffer(self: *ToolState, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.text_buffer = .empty;
        self.freehand_points = .empty;
    }

    pub fn deinitTextBuffer(self: *ToolState) void {
        self.text_buffer.deinit(self.allocator);
        self.freehand_points.deinit(self.allocator);
    }
};

pub const DrawObject = union(enum) {
    line: LineObject,
    rectangle: RectangleObject,
    text: TextObject,
    freehand: FreehandObject,
};

pub const LineObject = struct {
    start: Point,
    end: Point,
    color: Color,
    width: u32,
};

pub const RectangleObject = struct {
    rect: Rect,
    color: Color,
    width: u32,
    fill: bool = false,
};

pub const TextObject = struct {
    pos: Point,
    text: []const u8,
    color: Color,
    size: u32 = 16,
};

pub const FreehandObject = struct {
    points: []Point,
    color: Color,
    width: u32,
};

pub const Image = struct {
    data: []u8,
    width: u32,
    height: u32,
    stride: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Image {
        const stride = width * 4;
        const data = try allocator.alloc(u8, @as(usize, height) * @as(usize, stride));
        @memset(data, 0);

        return .{
            .data = data,
            .width = width,
            .height = height,
            .stride = stride,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Image) void {
        self.allocator.free(self.data);
    }

    pub fn setPixel(self: *Image, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        const offset = @as(usize, y) * @as(usize, self.stride) + @as(usize, x) * 4;
        self.data[offset] = color.r;
        self.data[offset + 1] = color.g;
        self.data[offset + 2] = color.b;
        self.data[offset + 3] = color.a;
    }

    pub fn getPixel(self: *const Image, x: u32, y: u32) Color {
        if (x >= self.width or y >= self.height) {
            return Color.rgb(0, 0, 0);
        }
        const offset = @as(usize, y) * @as(usize, self.stride) + @as(usize, x) * 4;
        return .{
            .r = self.data[offset],
            .g = self.data[offset + 1],
            .b = self.data[offset + 2],
            .a = self.data[offset + 3],
        };
    }
};
