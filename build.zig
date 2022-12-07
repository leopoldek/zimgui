const std = @import("std");
const builtin = @import("builtin");
const generate = @import("generator/generate.zig").generate;
const Builder = std.build.Builder;
const Step = std.build.Step;
const path = std.fs.path;
const LibExeObjStep = std.build.LibExeObjStep;
const Allocator = std.mem.Allocator;

inline fn pathName() []const u8 {
    comptime return path.dirname(@src().file).?;
}

pub const ImguiStep = struct {
    step: Step,
    allocator: Allocator,
    output_file: std.build.GeneratedFile,
    package: std.build.Pkg,
    
    pub fn init(b: *Builder, out_path: []const u8) *@This() {
        const self = b.allocator.create(@This()) catch unreachable;
        const full_out_path = path.join(b.allocator, &[_][]const u8{
            b.build_root,
            b.cache_root,
            out_path,
        }) catch unreachable;
        self.* = .{
            .step = Step.init(.custom, "zimgui-generate", b.allocator, make),
            .allocator = b.allocator,
            .output_file = .{
                .step = &self.step,
                .path = full_out_path,
            },
            .package = .{
                .name = "zimgui",
                .source = .{ .generated = &self.output_file },
                .dependencies = null,
            },
        };
        return self;
    }
    
    fn make(step: *Step) !void {
        const self = @fieldParentPtr(@This(), "step", step);
        
        var out_buffer = std.ArrayList(u8).init(self.allocator);
        try generate(self.allocator, out_buffer.writer());
        try out_buffer.append(0);
        const code = out_buffer.items[0 .. out_buffer.items.len - 1:0];
        
        const tree = try std.zig.parse(self.allocator, code);
        //std.debug.assert(tree.errors.len == 0); // If this triggers, we produced invalid code.
        const formatted = if (tree.errors.len == 0) try tree.render(self.allocator) else code;
        
        const cwd = std.fs.cwd();
        try cwd.makePath(path.dirname(self.output_file.path.?).?);
        try cwd.writeFile(self.output_file.path.?, formatted);
    }
    
    fn addTest(self: @This(), b: *Builder) *LibExeObjStep {
        const test_step = b.addTest("tests.zig");
        test_step.addPackage(self.package);
        link(test_step);
        return test_step;
    }
};

pub fn link(step: *LibExeObjStep) void {
    const base = comptime pathName();
    //step.addIncludePath(base ++ "/src");
    step.linkLibCpp();
    step.addCSourceFiles(&.{
        base ++ "/src/cimgui.cpp",
        base ++ "/src/imgui/imgui.cpp",
        base ++ "/src/imgui/imgui_widgets.cpp",
        base ++ "/src/imgui/imgui_tables.cpp",
        base ++ "/src/imgui/imgui_draw.cpp",
        base ++ "/src/imgui/imgui_demo.cpp",
        //base ++ "/src/imgui/implot_demo.cpp",
        //base ++ "/src/imgui/implot.cpp",
        //base ++ "/src/imgui/implot_items.cpp",
        //base ++ "/src/imgui/backends/imgui_impl_glfw.cpp",
    }, &.{
        "-fno-sanitize=undefined",
        "-DIMGUI_IMPL_API=extern \"C\"",
        "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1",
        //"-DIMGUI_DISABLE_OBSOLETE_KEYIO=1",
    });
}

pub fn build(b: *Builder) void {
    const imgui_step = ImguiStep.init(b, "imgui.zig");
    const test_step = imgui_step.addTest(b);
    test_step.setBuildMode(b.standardReleaseOptions());
    test_step.setTarget(b.standardTargetOptions(.{}));
    
    b.step("test", "Run zimgui tests").dependOn(&test_step.step);
    b.default_step.dependOn(&test_step.step);
}
