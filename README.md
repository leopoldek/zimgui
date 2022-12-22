# zimgui

zimgui uses [cimgui](https://github.com/cimgui/cimgui) to generate [Zig](https://github.com/ziglang/zig) bindings for [Dear ImGui](https://github.com/ocornut/imgui).
Based off of [SpexGuy/Zig-ImGui](https://github.com/SpexGuy/Zig-ImGui).

## Using the pre-generated bindings

zimgui strives to be easy to use.  To use the pre-generated bindings, do the following:

- Copy the zimgui directory into your project
- In your build.zig, do the following:
    ```zig
    const zimgui = @import("path/to/zimgui/build.zig");
    // "b" is your "*std.build.Builder"
    const imgui_step = zimgui.ImguiStep.init(b, "imgui.zig");
    // "step" is your "*std.build.LibExeObjStep"
    step.addPackage(imgui_step.package);
    ```
- If you would like to run basic tests on the bindings in your project, add this to build.zig:
    ```zig
    const test_step = imgui_step.addTest(b);
    // Change the build/target if desired.
    // test_step.setBuildMode(...);
    // test_step.setTarget(...);
    b.step("imgui:test", "Run zimgui tests").dependOn(&test_step.step);
    ```
    and then run `zig build imgui:test`
- If you need to use zimgui as a dependency of another package, use `imgui_build.pkg` as the dependency.  Be sure to call `imgui_build.link` or `imgui_build.linkWithoutPackage` on any executable or test which uses this dependency.
- In your project, use `@import("zimgui")` to obtain the bindings.
- For more detailed documentation, see the [official ImGui documentation](https://github.com/ocornut/imgui/tree/v1.89/docs).

## Binding style

These bindings generally prefer the Zig style. Functions, types, and fields follow the casing of the zig style guide.
- Prefixes like ImGui* or Im* have been stripped. Enum names as prefixes to enum values have also been stripped.
- Constructors and destructors have been renamed to `init` and `deinit` respectively (constructors also include the overload type suffix if it's overloaded).
- "Flags" enums have been translated to packed structs of bools, with helper functions for performing bit operations.
- `ImGuiCond` specifically has been translated to `CondFlags` to match the naming style of other flag enums.
- Functions with default values have two generated variants. The original name maps to the "simple" version with all defaults set. Adding "Ext" to the end of the function will produce the more complex version with all default parameters inside a default struct.
- Functions with multiple overloads have a postfix appended based on the first difference in parameter types.

For example, these two C++ functions generate four Zig functions:
```c++
void ImGui::SetWindowCollapsed(char const *name, bool collapsed, ImGuiCond cond = 0);
void ImGui::SetWindowCollapsed(bool collapsed, ImGuiCond cond = 0);
```
```zig
pub const SetWindowCollapsedStrDefaults = struct {
    cond: CondFlags = @bitCast(CondFlags, @as(FlagsInt, 0)),
};
pub inline fn setWindowCollapsedStrExt(name: [*c]const u8, collapsed: bool, default_args: @This().SetWindowCollapsedStrDefaults) void;
pub inline fn setWindowCollapsedStr(name: [*c]const u8, collapsed: bool) void;

pub const SetWindowCollapsedBoolDefaults = struct {
    cond: CondFlags = @bitCast(CondFlags, @as(FlagsInt, 0)),
};
pub inline fn setWindowCollapsedBoolExt(collapsed: bool, default_args: SetWindowCollapsedBoolDefaults) void;
pub inline fn setWindowCollapsedBool(collapsed: bool) void;
```

If you find any incorrect translations, please open an issue.

## Generating new bindings

Since bindings are generated on the fly, no extra commands/dependencies are necessary.
Instead you need only replace a few files (while preserving tree structure):
- The imgui files under `src/`.
- All the `.json` files under `generator/`.

Some changes to Dear ImGui may require more in-depth changes to generate correct bindings.
You may need to check for updates to upstream cimgui, or modify `generator.zig`.

You can do a quick check of the integrity of the bindings with zig build test.
This will verify that the version of Dear ImGui matches the bindings, and compile all wrapper functions in the bindings.
