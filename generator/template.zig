//! ==========================================================
//! This file is generated from template.zig and generate.zig
//! Do not modify it by hand.
//! ==========================================================

const std = @import("std");
const builtin = @import("builtin");
const assert = @import("std").debug.assert;
const imgui = @This();

comptime {
    // NOTE(Daniel): Since we use hardcoded integer sizes, we should check that they are compatible with C.
    std.debug.assert(@sizeOf(u32) == @sizeOf(c_uint));
    std.debug.assert(@sizeOf(i32) == @sizeOf(c_int));
    std.debug.assert(@sizeOf(u16) == @sizeOf(c_ushort));
    std.debug.assert(@sizeOf(i16) == @sizeOf(c_short));
}

pub const reset_render_state = @intToPtr(DrawCallback, ~@as(usize, 0));

pub fn checkVersion() void {
    if (builtin.mode != .ReleaseFast) {
        assert(raw.igDebugCheckVersionAndDataLayout(version, @sizeOf(IO), @sizeOf(Style), @sizeOf(Vec2), @sizeOf(Vec4), @sizeOf(DrawVert), @sizeOf(DrawIdx)));
    }
}

pub const FLT_MAX: f32 = std.math.f32_max;
pub const FLT_MIN: f32 = std.math.f32_min;

pub const FlagsInt = c_uint;

pub fn FlagsMixin(comptime FlagsType: type) type {
    return struct {
        pub const IntType = @typeInfo(FlagsType).Struct.backing_integer.?;
        pub fn toInt(self: FlagsType) IntType {
            return @bitCast(IntType, self);
        }
        pub fn fromInt(flags: IntType) FlagsType {
            return @bitCast(FlagsType, flags);
        }
        pub fn merge(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) | toInt(rhs));
        }
        pub fn intersect(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) & toInt(rhs));
        }
        pub fn complement(self: FlagsType) FlagsType {
            return fromInt(~toInt(self));
        }
        pub fn subtract(lhs: FlagsType, rhs: FlagsType) FlagsType {
            return fromInt(toInt(lhs) & toInt(rhs.complement()));
        }
        pub fn contains(lhs: FlagsType, rhs: FlagsType) bool {
            return toInt(intersect(lhs, rhs)) == toInt(rhs);
        }
    };
}

fn destruct(comptime T: type, ptr: *T) void {
    if (@typeInfo(T) == .Struct or @typeInfo(T) == .Union) {
        if (@hasDecl(T, "deinit")) {
            ptr.deinit();
        }
    }
}

fn eql(comptime T: type, a: T, b: T) bool {
    if (@typeInfo(T) == .Struct or @typeInfo(T) == .Union) {
        if (@hasDecl(T, "eql")) {
            return a.eql(b);
        }
    }
    return a == b;
}

pub fn Vector(comptime T: type) type {
    return extern struct {
        size: c_int = 0,
        capacity: c_int = 0,
        data: ?[*]T = null,
        
        pub inline fn getSize(self: @This()) usize {
            return @intCast(usize, self.size);
        }

        pub inline fn getCapacity(self: @This()) usize {
            return @intCast(usize, self.capacity);
        }

        pub inline fn items(self: @This()) []T {
            return if (self.data) |d| d[0..self.getSize()] else &.{};
        }

        pub fn deinit(self: *@This()) void {
            if (self.data) |d| raw.igMemFree(@ptrCast(*anyopaque, d));
            self.* = undefined;
        }

        pub fn clone(self: @This()) @This() {
            var cloned = @This(){};
            if (self.size != 0) {
                cloned.resize(self.getSize());
                @memcpy(@ptrCast([*]u8, cloned.data.?), @ptrCast([*]const u8, self.data.?), self.getSize() * @sizeOf(T));
            }
            return cloned;
        }

        pub fn fromSlice(slice: []const T) @This() {
            var result = @This(){};
            if (slice.len != 0) {
                result.resize(slice.len);
                @memcpy(@ptrCast([*]u8, result.data.?), @ptrCast([*]const u8, slice.ptr), slice.len * @sizeOf(T));
            }
            return result;
        }

        /// Important: does not destruct anything
        pub fn clear(self: *@This()) void {
            if (self.data) |d| raw.igMemFree(@ptrCast(?*anyopaque, d));
            self.* = .{};
        }

        /// Destruct and delete all pointer values, then clear the array.
        /// T must be a pointer or optional pointer.
        pub fn clearDelete(self: *@This()) void {
            comptime var ti = @typeInfo(T);
            const is_optional = (ti == .Optional);
            if (is_optional) ti = @typeInfo(ti.Optional.child);
            if (ti != .Pointer or ti.Pointer.is_const or ti.Pointer.size != .One)
                @compileError("clearDelete() can only be called on vectors of mutable single-item pointers, cannot apply to Vector(" ++ @typeName(T) ++ ").");
            const ValueT = ti.Pointer.child;

            if (is_optional) {
                for (self.items()) |it| {
                    if (it) |_ptr| {
                        const ptr: *ValueT = _ptr;
                        destruct(ValueT, ptr);
                        raw.igMemFree(ptr);
                    }
                }
            } else {
                for (self.items()) |_ptr| {
                    const ptr: *ValueT = _ptr;
                    destruct(ValueT, ptr);
                    raw.igMemFree(@ptrCast(?*anyopaque, ptr));
                }
            }
            self.clear();
        }

        pub fn clearDestruct(self: *@This()) void {
            for (self.items()) |*ptr| {
                destruct(T, ptr);
            }
            self.clear();
        }

        /// Resize a vector. If smaller or equal, guaranteed not to cause a reallocation
        pub fn resize(self: *@This(), new_size: usize) void {
            self.reserve(new_size);
            self.size = @intCast(c_int, new_size);
        }

        pub fn reserve(self: *@This(), user_capacity: usize) void {
            if (user_capacity <= self.capacity) return;
            var new_capacity = self.getCapacity();
            if (new_capacity < 16) new_capacity = 16;
            while (new_capacity < user_capacity) new_capacity += new_capacity >> 1;
            
            const new_data = @ptrCast(?[*]T, @alignCast(@alignOf(T), raw.igMemAlloc(new_capacity * @sizeOf(T))));
            if (self.data) |sd| {
                if (self.size != 0) @memcpy(@ptrCast([*]u8, new_data.?), @ptrCast([*]const u8, sd), self.getSize() * @sizeOf(T));
                memFree(@ptrCast(?*anyopaque, sd));
            }
            self.data = new_data;
            self.capacity = @intCast(c_int, new_capacity);
        }

        // NB: It is illegal to call pushBack/pushFront/insert with a reference pointing inside the ImVector data itself! e.g. v.pushBack(v.items()[10]) is forbidden.
        pub fn pushBack(self: *@This(), v: T) void {
            self.insert(self.getSize(), v);
        }

        pub fn pushFront(self: *@This(), v: T) void {
            self.insert(0, v);
        }

        pub fn popBack(self: *@This()) void {
            self.size -= 1;
        }
        
        pub fn popFront(self: *@This()) void {
            self.orderedRemove(0);
        }

        pub fn swapRemove(self: *@This(), index: usize) void {
            assert(index < self.size);
            self.size -= 1;
            self.data.?[index] = self.data.?[self.getSize()];
        }

        pub fn orderedRemove(self: *@This(), index: usize) void {
            assert(index < self.size);
            self.size -= 1;
            if (index == self.size) return;
            const data = self.data.?;
            var i = index;
            while (i <= self.size) : (i += 1) data[i] = data[i + 1];
        }

        pub fn insert(self: *@This(), index: usize, v: T) void {
            assert(index <= self.size);
            self.reserve(self.getSize() + 1);
            const data = self.data.?;
            if (index < self.size) {
                var it = self.getSize();
                while (it > index) : (it -= 1) {
                    data[it] = data[it - 1];
                }
            }
            data[index] = v;
            self.size += 1;
        }

        //pub fn contains(self: @This(), v: T) bool {
        //    for (self.items()) |*it| {
        //        if (imgui.eql(T, v, it.*)) return true;
        //    }
        //    return false;
        //}
        //
        //pub fn find(self: @This(), v: T) ?c_int {
        //    return for (self.items()) |*it, i| {
        //        if (imgui.eql(T, v, it.*)) break @intCast(c_int, i);
        //    } else null;
        //}

        pub fn eql(self: @This(), other: @This()) bool {
            if (self.size != other.size) return false;
            var i: usize = 0;
            while (i < self.size) : (i += 1) {
                if (!imgui.eql(T, self.data.?[i], other.data.?[i]))
                    return false;
            }
            return true;
        }
    };
}

pub const Vec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: Vec2, other: Vec2) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const Vec4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return .{ .x = x, .y = y, .z = z, .w = w };
    }

    pub fn eql(self: Vec4, other: Vec4) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z and self.w == other.w;
    }
};

pub const Color = extern struct {
    Value: Vec4,

    pub fn initRGBA(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .Value = Vec4.init(r, g, b, a) };
    }

    pub fn initRGBAUnorm(r: u8, g: u8, b: u8, a: u8) Color {
        const inv_255: f32 = 1.0 / 255.0;
        return initRGBA(
            @intToFloat(f32, r) * inv_255,
            @intToFloat(f32, g) * inv_255,
            @intToFloat(f32, b) * inv_255,
            @intToFloat(f32, a) * inv_255,
        );
    }

    /// Convert an integer 0xaabbggrr to a floating point color
    pub fn initABGRPacked(value: u32) Color {
        return initRGBAUnorm(
            @truncate(u8, value >> 0),
            @truncate(u8, value >> 8),
            @truncate(u8, value >> 16),
            @truncate(u8, value >> 24),
        );
    }

    /// Convert HSVA to RGBA color
    pub fn initHSVA(h: f32, s: f32, v: f32, a: f32) Color {
        var r: f32 = undefined;
        var g: f32 = undefined;
        var b: f32 = undefined;
        colorConvertHSVtoRGB(h, s, v, &r, &g, &b);
        return initRGBA(r, g, b, a);
    }

    /// Convert from a floating point color to an integer 0xaabbggrr
    pub fn packABGR(self: Color) u32 {
        return colorConvertFloat4ToU32(self.Value);
    }

    pub fn eql(self: Color, other: Color) bool {
        return self.Value.eql(other.Value);
    }
};

fn imguiZigAlloc(_: *anyopaque, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
    _ = len_align;
    _ = ret_addr;
    assert(ptr_align <= @alignOf(*anyopaque)); // Alignment larger than pointers is not supported
    return @ptrCast([*]u8, raw.igMemAlloc(len) orelse return error.OutOfMemory)[0..len];
}
fn imguiZigResize(_: *anyopaque, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
    _ = len_align;
    _ = ret_addr;
    assert(buf_align <= @alignOf(*anyopaque)); // Alignment larger than pointers is not supported
    if (new_len > buf.len) return null;
    if (new_len == 0 and buf.len != 0) raw.igMemFree(buf.ptr);
    return new_len;
}
fn imguiZigFree(_: *anyopaque, buf: []u8, buf_align: u29, ret_addr: usize) void {
    _ = buf_align;
    _ = ret_addr;
    if (buf.len != 0) raw.igMemFree(buf.ptr);
}

const allocator_vtable: std.mem.Allocator.VTable = .{
    .alloc = imguiZigAlloc,
    .resize = imguiZigResize,
    .free = imguiZigFree,
};

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &allocator_vtable,
};

// ---------------- Everything above here comes from template.zig ------------------
// ---------------- Everything below here is generated -----------------------------

