const std = @import("std");
const gui = @import("zimgui");
const builtin = @import("builtin");
const assert = std.debug.assert;

extern fn igGET_FLT_MAX() callconv(.C) f32;
extern fn igGET_FLT_MIN() callconv(.C) f32;

test "FLT_MIN" {
    try std.testing.expect(gui.FLT_MIN == igGET_FLT_MIN());
}

test "FLT_MAX" {
    try std.testing.expect(gui.FLT_MAX == igGET_FLT_MAX());
}

test "Check version" {
    gui.checkVersion();
}

const skip_none = &[_][]const u8{};
fn compileEverything(comptime Outer: type, comptime skip_items: []const []const u8) void {
    inline for (@typeInfo(Outer).Struct.decls) |decl| {
        if (!decl.is_pub) continue;
        const skip = comptime for (skip_items) |item| {
            if (std.mem.eql(u8, item, decl.name)) {
                break true;
            }
        } else false;
        if (skip) continue;
        const T = @TypeOf(@field(Outer, decl.name));
        if (T == type and @typeInfo(@field(Outer, decl.name)) == .Struct) {
            compileEverything(@field(Outer, decl.name), skip_none);
        }
    }
}

test "Compile everything" {
    // TODO(Daniel): Remove when fixed.
    // This forces gui.DrawCmd to be analyzed before gui.DrawCallback,
    // which avoids a false positive circular dependency bug.
    var draw: gui.DrawCmd = undefined;
    _ = draw;

    @setEvalBranchQuota(10000);
    // Compile static function wrappers
    compileEverything(gui, skip_none);

    // Compile instantiations of Vector
    const skip_value_type = &[_][]const u8{ "value_type" };
    const skip_clear_delete = skip_value_type ++ &[_][]const u8{ "clearDelete" };
    const skip_comparisons = skip_clear_delete ++ &[_][]const u8{ "contains", "find", "eql" };
    compileEverything(gui.Vector(gui.Vec2), skip_clear_delete);
    compileEverything(gui.Vector(*gui.Vec4), skip_value_type);
    compileEverything(gui.Vector(?*gui.Vec4), skip_value_type);
    compileEverything(gui.Vector(*const gui.Vec4), skip_clear_delete);
    compileEverything(gui.Vector(?*const gui.Vec4), skip_clear_delete);
    compileEverything(gui.Vector(*gui.Vec4), skip_value_type);
    compileEverything(gui.Vector(?*gui.Vec4), skip_value_type);
    compileEverything(gui.Vector(u32), skip_clear_delete);
    compileEverything(gui.Vector(i32), skip_clear_delete);
    compileEverything(gui.Vector(*gui.Vector(u32)), skip_value_type);
    compileEverything(gui.Vector(?*gui.Vector(u32)), skip_value_type);
    compileEverything(gui.Vector(gui.Vector(u32)), skip_clear_delete);
    compileEverything(gui.Vector([*:0]u8), skip_clear_delete);
    compileEverything(gui.Vector(?[*:0]u8), skip_clear_delete);
    compileEverything(gui.Vector([*]u8), skip_clear_delete);
    compileEverything(gui.Vector(?[*]u8), skip_clear_delete);
    compileEverything(gui.Vector([]u8), skip_comparisons);
    compileEverything(gui.Vector(?[]u8), skip_comparisons);
}

test "Initialize Imgui" {
    _ = gui.createContext();
    gui.destroyContext();
}
