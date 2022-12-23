const std = @import("std");
const overrides = @import("overrides.zig");
const Allocator = std.mem.Allocator;

const TypeMap = std.StringHashMap([]const u8);
const EnumMap = std.StringHashMap(bool);
//const Writer = std.ArrayList(u8).Writer;

const template = @embedFile("template.zig");
const cimgui_file = @embedFile("../src/cimgui.h");
const typedefs_dict_file = @embedFile("typedefs_dict.json");
const structs_and_enums_file = @embedFile("structs_and_enums.json");
const definitions_file = @embedFile("definitions.json");
//const impl_definitions_file = @embedFile("impl_definitions.json");

pub var allocator: Allocator = undefined;
var type_map: TypeMap = undefined;
//var writer: Writer = undefined;

// TODO(Daniel): The below TODOs should be optional features that build system can ask for or not?
// TODO(Daniel): Any arg name that ends with "_count" should detect if there is a corrosponding items arg. If so, combine into slice.
// TODO(Daniel): If there is only one default arg, dont use a default args struct. Just pass the default arg directly.

const FuncDef = struct {
    const Arg = struct {
        name: []const u8,
        type: []const u8,
        default: ?[]const u8,
    };

    extern_name: []const u8,
    name: []const u8,
    ret: []const u8,
    args: []const Arg,
    base: ?struct {
        name: []const u8,
        constructor: bool,
        destructor: bool,
    },

    fn printExternFunc(self: @This(), writer: anytype) !void {
        try writer.print("pub extern fn {s}(", .{self.extern_name});
        _ = try self.printArgs(true, true, true, writer);
        try writer.print(") {s};\n", .{self.ret});
    }

    fn printFunc(self: @This(), writer: anytype) !void {
        if (self.base) |base| {
            if (base.constructor) {
                if (!std.mem.endsWith(u8, self.extern_name, base.name)) {
                    // This is an overloaded function.
                    const start = std.mem.lastIndexOfScalar(u8, self.extern_name, '_').? + 1;
                    try writer.print("pub inline fn init{s}(", .{self.extern_name[start..]});
                } else {
                    try writer.writeAll("pub inline fn init(");
                }
                _ = try self.printArgs(true, false, false, writer);
                try writer.print(") *@This() {{return raw.{s}(", .{self.extern_name});
                _ = try self.printArgs(false, false, false, writer);
                try writer.writeAll(");\n}\n");
                return;
            } else if (base.destructor) {
                std.debug.assert(self.args.len == 1);
                std.debug.assert(std.mem.eql(u8, self.args[0].name, "self"));
                std.debug.assert(std.mem.eql(u8, self.ret, "void"));
                try writer.print(
                    "pub inline fn deinit(self: {s}) void{{\nraw.{s}(self);\n}}\n",
                    .{ self.args[0].type, self.extern_name },
                );
                return;
            }
        }

        if (self.args.len != 0 and std.mem.eql(u8, self.args[self.args.len - 1].name, "...")) {
            // This is a varargs function.
            //try writer.print("pub const {s} = raw.{s};\n", .{ self.name, self.extern_name });
            try writer.print("pub fn {s}(", .{self.name});
            for (self.args) |arg, i| {
                if (i != 0) try writer.writeAll(", ");
                if (std.mem.eql(u8, arg.name, "...")) {
                    try writer.writeAll("var_args: anytype");
                    continue;
                }
                try writer.print("{s}: {s}", .{ arg.name, arg.type });
            }
            try writer.print(") {s} {{\nreturn @call(.{{}}, raw.{s}, .{{", .{ self.ret, self.extern_name });
            for (self.args) |arg, i| {
                if (std.mem.eql(u8, arg.name, "...")) continue;
                try writer.writeAll(arg.name);
                if (i < self.args.len - 2) try writer.writeAll(", ");
            }
            try writer.writeAll("} ++ var_args);\n}\n");
            return;
        }

        const ret = self.getReturnArg();
        var default_count: usize = 0;
        for (self.args) |arg| {
            if (arg.default != null) default_count += 1;
        }

        if (default_count != 0) {
            var struct_name = try allocator.dupe(u8, self.name);
            struct_name[0] = std.ascii.toUpper(struct_name[0]);

            // Print Default Struct
            try writer.print("pub const {s}Defaults = struct {{\n", .{struct_name});
            for (self.args) |arg| {
                if (arg.default == null) continue;
                try writer.print("{s}: {s} = {s},\n", .{ arg.name, arg.type, arg.default.? });
            }
            try writer.writeAll("};\n");

            // Print Extended Function
            try writer.print("pub inline fn {s}Ext(", .{self.name});
            const written = try self.printArgs(true, false, false, writer);
            try writer.print(
                "{s}default_args: @This().{s}Defaults) {s} {{\n",
                .{ if (written != 0) ", " else "", struct_name, ret },
            );
            try self.printCallReturn(writer);
            try writer.print("raw.{s}(", .{self.extern_name});
            _ = try self.printArgs(false, false, true, writer);
            for (self.args) |arg, i| {
                if (arg.default == null) continue;
                if (i != 0) try writer.writeAll(", ");
                try writer.print("default_args.{s}", .{arg.name});
            }
            try writer.writeAll(");\n");
            if (self.hasReturnArg()) try writer.writeAll("return out;\n");
            try writer.writeAll("}\n");
        }

        // Print Regular Function
        try writer.print("pub inline fn {s}(", .{self.name});
        _ = try self.printArgs(true, false, false, writer);
        try writer.print(") {s} {{\n", .{ret});

        if (default_count == 0) {
            try self.printCallReturn(writer);
            try writer.print("raw.{s}(", .{self.extern_name});
            _ = try self.printArgs(false, true, true, writer);
            try writer.writeAll(");\n");
            if (self.hasReturnArg()) try writer.writeAll("return out;\n");
        } else {
            try writer.print("return @This().{s}Ext(", .{self.name});
            const written = try self.printArgs(false, false, false, writer);
            if (written != 0) try writer.writeAll(", ");
            try writer.writeAll(".{});\n");
        }
        try writer.writeAll("}\n");
    }

    fn printCallReturn(self: @This(), writer: anytype) !void {
        if (self.hasReturnArg()) {
            try writer.print("var out: {s} = undefined;\nconst pOut = &out;\n", .{self.getReturnArg()});
        } else if (!std.mem.eql(u8, self.ret, "void")) {
            try writer.writeAll("return ");
        }
    }

    fn printArgs(self: @This(), print_types: bool, print_defaults: bool, print_ret_arg: bool, writer: anytype) !usize {
        // TODO(Daniel): Instead of handling this here, handle this in the function parser and add a `ret_arg` field.
        const args = if (self.hasReturnArg() and !print_ret_arg) self.args[1..] else self.args;
        var i: usize = 0;
        for (args) |arg| {
            if (!print_defaults and arg.default != null) continue;
            std.debug.assert(print_ret_arg or i == 0 or !std.mem.eql(u8, arg.name, "self"));
            if (i != 0) try writer.writeAll(", ");
            if (print_types and !std.mem.eql(u8, arg.name, "...")) {
                try writer.print("{s}: {s}", .{ arg.name, arg.type });
            } else {
                try writer.print("{s}", .{arg.name});
            }
            i += 1;
        }
        return i;
    }

    fn hasReturnArg(self: @This()) bool {
        // TODO(Daniel): func object in json has `"nonUDT": 1,`. Use that instead.
        if (self.args.len == 0) return false;
        if (!std.mem.eql(u8, self.args[0].name, "pOut")) return false;
        if (!std.mem.startsWith(u8, self.args[0].type, "[*c]")) return false;
        std.debug.assert(std.mem.eql(u8, self.ret, "void"));
        return true;
    }

    fn getReturnArg(self: @This()) []const u8 {
        return if (self.hasReturnArg()) prefixTrim(self.args[0].type, "[*c]") else self.ret;
    }
};

pub fn generate(user_allocator: Allocator, writer: anytype) !void {
    allocator = user_allocator;
    try writer.writeAll(template);

    { // Write Version
        const start = std.mem.indexOfScalar(u8, cimgui_file, '"').? + 1;
        const end = std.mem.indexOfScalarPos(u8, cimgui_file, start, '"').?;
        try writer.print("pub const version = \"{s}\";\n", .{cimgui_file[start..end]});
    }

    // Get structs and enums and cull unused ones.
    const decls = blk: {
        var parser = std.json.Parser.init(allocator, false);
        var tree = try parser.parse(structs_and_enums_file);
        var data = .{
            .structs = tree.root.Object.get("structs").?.Object,
            .enums = tree.root.Object.get("enums").?.Object,
        };
        var it = tree.root.Object.get("locations").?.Object.iterator();
        while (it.next()) |entry| if (isSkip(entry.key_ptr.*, entry.value_ptr.String)) {
            _ = data.structs.swapRemove(entry.key_ptr.*);
            _ = data.enums.swapRemove(entry.key_ptr.*);
        };
        break :blk data;
    };

    type_map = TypeMap.init(allocator);

    { // Common Types
        try type_map.putNoClobber("int", "i32");
        try type_map.putNoClobber("unsigned int", "u32");
        try type_map.putNoClobber("short", "i16");
        try type_map.putNoClobber("unsigned short", "u16");
        try type_map.putNoClobber("float", "f32");
        try type_map.putNoClobber("double", "f64");
        try type_map.putNoClobber("void", "void");
        try type_map.putNoClobber("void*", "?*anyopaque");
        try type_map.putNoClobber("void const*", "?*const anyopaque");
        try type_map.putNoClobber("const void*", "?*const anyopaque");
        try type_map.putNoClobber("const char*", "[*c]const u8");
        try type_map.putNoClobber("char const*", "[*c]const u8");
        try type_map.putNoClobber("bool", "bool");
        try type_map.putNoClobber("char", "i8");
        try type_map.putNoClobber("signed char", "i8");
        try type_map.putNoClobber("unsigned char", "u8");
        try type_map.putNoClobber("size_t", "usize");
        try type_map.putNoClobber("ImS8", "i8");
        try type_map.putNoClobber("ImS16", "i16");
        try type_map.putNoClobber("ImS32", "i32");
        try type_map.putNoClobber("ImS64", "i64");
        try type_map.putNoClobber("ImU8", "u8");
        try type_map.putNoClobber("ImU16", "u16");
        try type_map.putNoClobber("ImU32", "u32");
        try type_map.putNoClobber("ImU64", "u64");
        try type_map.putNoClobber("ImGuiCond", "CondFlags");
        try type_map.putNoClobber("FILE*", "?*anyopaque");
        try type_map.putNoClobber("...", "...");
        //try type_map.putNoClobber("[*c]anyopaque", "*anyopaque");
    }

    { // Parse typedefs_dict
        var parser = std.json.Parser.init(allocator, false);
        const tree = try parser.parse(typedefs_dict_file);
        var it = tree.root.Object.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const type_str = entry.value_ptr.String;
            if (type_map.contains(name)) continue;
            if (std.mem.endsWith(u8, name, "Flags")) continue;
            if (std.mem.eql(u8, name, "const_iterator")) continue;
            if (std.mem.eql(u8, name, "iterator")) continue;
            if (std.mem.eql(u8, name, "value_type")) continue;
            if (isSkip(name, "")) continue;
            if (decls.enums.contains(name)) continue;
            if (decls.enums.contains(try std.mem.concat(allocator, u8, &.{ name, "_" }))) continue;
            if (decls.structs.contains(name)) continue;
            const parsed_name = try parseIdentifier(name);
            if (std.mem.startsWith(u8, type_str, "struct ")) {
                // Pointers to opaque types must be single item.
                try type_map.putNoClobber(
                    try std.fmt.allocPrint(allocator, "[*c]const {s}", .{parsed_name}),
                    try std.fmt.allocPrint(allocator, "?*const {s}", .{parsed_name}),
                );
                try type_map.putNoClobber(
                    try std.fmt.allocPrint(allocator, "[*c]{s}", .{parsed_name}),
                    try std.fmt.allocPrint(allocator, "?*{s}", .{parsed_name}),
                );
                try writer.print("pub const {s} = opaque{{}};\n", .{parsed_name});
                continue;
            }
            try type_map.putNoClobber(name, parsed_name);
            try writer.print("pub const {s} = {s};\n", .{ parsed_name, try parseType(type_str, false) });
        }
        try writer.writeAll("\n");
    }

    // Parse enums
    var enum_map = EnumMap.init(allocator);
    var enum_it = decls.enums.iterator();
    while (enum_it.next()) |entry| {
        var name: []const u8 = entry.key_ptr.*;
        if (std.mem.endsWith(u8, name, "_")) name = trimBack(name, 1);
        const fields = entry.value_ptr.Array.items;
        if (std.mem.endsWith(u8, name, "Flags") or std.mem.eql(u8, name, "ImGuiCond")) {
            // This is a flag.
            var parsed_name: []const u8 = "CondFlags";
            if (!std.mem.eql(u8, name, "ImGuiCond")) {
                std.debug.assert(std.mem.endsWith(u8, name, "Flags"));
                parsed_name = try parseIdentifier(name);
            }
            try writer.print(
                //pub const {s}FlagsInt = FlagsInt;\n
                "pub const {s} = packed struct(FlagsInt) {{\nusingnamespace FlagsMixin(@This());\n",
                .{parsed_name},
            );
            var field_names: [32]?[]const u8 = comptime .{null} ** 32;
            for (fields) |field| {
                const value: u64 = @intCast(u64, field.Object.get("calc_value").?.Integer);
                const field_name = try parseFieldName(name, field.Object.get("name").?.String);
                if (value == 0) {
                    // This is the empty struct. We can't take the log2 of 0 anyway.
                    try writer.print("pub const {s} = @This(){{}};\n", .{field_name});
                } else if (std.math.isPowerOfTwo(value)) {
                    // This is a bit flag.
                    field_names[std.math.log2_int(u64, value)] = field_name;
                } else {
                    // This is not a bit flag, but instead a combination of flags.
                    try writer.print("pub const {s} = @bitCast(@This(), @as(FlagsInt, {d}));\n", .{ field_name, value });
                }
            }
            for (field_names) |field_name, i| {
                if (field_name) |name_str| {
                    try writer.print("{s}: bool = false,\n", .{name_str});
                } else {
                    try writer.print("__reserved_bit_{d}: bool = false,\n", .{i});
                }
            }
            try enum_map.putNoClobber(parsed_name, true);
        } else {
            const parsed_name = try parseIdentifier(name);
            try writer.print("pub const {s} = enum(i32) {{\n", .{parsed_name});
            var overloads = std.ArrayList(u8).init(allocator);
            for (fields) |field| {
                const value: i32 = @intCast(i32, field.Object.get("calc_value").?.Integer);
                const raw_name = field.Object.get("name").?.String;
                // HACK(Daniel): This collides with `ImGuiKey_None`
                if (value == 0 and std.mem.eql(u8, raw_name, "ImGuiMod_None")) continue;
                // HACK(Daniel): This collides with `ImGuiKey_Ctrl`
                if (std.mem.eql(u8, raw_name, "ImGuiMod_Shortcut")) continue;

                const field_name = suffixTrim(try parseFieldName(name, raw_name), "_");
                if (std.mem.startsWith(u8, raw_name, "ImGuiKey_NamedKey_") or
                    std.mem.startsWith(u8, raw_name, "ImGuiKey_KeysData_"))
                {
                    try overloads.writer().print("pub const {s} = {d};\n", .{ field_name, value });
                } else {
                    try writer.print("{s} = {d},\n", .{ field_name, value });
                }
            }
            try writer.writeAll(overloads.items);
            try enum_map.putNoClobber(parsed_name, false);
        }
        try writer.writeAll("};\n\n");
    }

    const funcs: []const FuncDef = blk: {
        var functions_list = std.ArrayList(FuncDef).init(allocator);
        var parser = std.json.Parser.init(allocator, false);
        const tree = try parser.parse(definitions_file);
        var func_it = tree.root.Object.iterator();
        while (func_it.next()) |entry| {
            //const base_name = entry.key_ptr.*;
            overload_loop: for (entry.value_ptr.Array.items) |overload| {
                if (overload.Object.contains("templated")) continue;

                const location = overload.Object.get("location") orelse continue;
                if (std.mem.startsWith(u8, location.String, "imgui_internal")) continue;

                const defaults = overload.Object.get("defaults").?.Object;
                var struct_name = overload.Object.get("stname").?.String;
                if (struct_name.len != 0) struct_name = try parseIdentifier(struct_name);
                const raw_name = overload.Object.get("ov_cimguiname").?.String;
                const func_name = try parseFunctionName(raw_name, struct_name.len != 0);
                var args = std.ArrayList(FuncDef.Arg).init(allocator);
                for (overload.Object.get("argsT").?.Array.items) |arg| {
                    const arg_name = arg.Object.get("name").?.String;
                    const parsed_name = parseArgName(arg_name);

                    const arg_type = arg.Object.get("type").?.String;
                    // TODO(Daniel): Support va_list functions in the future.
                    if (std.mem.eql(u8, arg_type, "va_list")) continue :overload_loop;
                    var parsed_type = try parseArgType(struct_name, func_name, parsed_name, arg_type);

                    try args.append(.{
                        .name = parsed_name,
                        .type = parsed_type,
                        .default = if (defaults.get(arg_name)) |d| try parseDefaultValue(enum_map, parsed_type, d.String) else null,
                    });
                }

                if (std.mem.startsWith(u8, raw_name, "ImVector")) continue;
                try functions_list.append(.{
                    .name = func_name,
                    .extern_name = raw_name,
                    .args = args.items,
                    .ret = if (overload.Object.get("ret")) |r| try parseArgType(struct_name, func_name, "return", r.String) else "void",
                    .base = if (struct_name.len == 0) null else .{
                        .name = struct_name,
                        .constructor = overload.Object.contains("constructor"),
                        .destructor = overload.Object.contains("destructor"),
                    },
                });
            }
        }
        break :blk functions_list.items;
    };

    // Parse structs
    var struct_it = decls.structs.iterator();
    while (struct_it.next()) |entry| {
        const raw_name = entry.key_ptr.*;
        const struct_name = try parseIdentifier(raw_name);
        const fields = entry.value_ptr.Array.items;
        try writer.print("pub const {s} = extern struct {{\n", .{struct_name});
        for (fields) |field| {
            var name = field.Object.get("name").?.String;
            var type_str = field.Object.get("type").?.String;
            const template_type: ?[]const u8 = if (field.Object.get("template_type")) |s| s.String else null;
            const size: ?i64 = if (field.Object.get("size")) |s| s.Integer else null;
            if (size != null) name = trim(name[0..std.mem.indexOfScalar(u8, name, '[').?]);
            name = try parseFieldName(raw_name, name);
            try writer.print("{s}: ", .{name});
            if (size) |s| try writer.print("[{d}]", .{s});
            if (template_type) |template_str| {
                if (!std.mem.startsWith(u8, type_str, "ImVector_")) {
                    std.debug.print("{s}\n", .{type_str});
                    unreachable;
                }
                const parsed_template = try std.fmt.allocPrint(allocator, "Vector({s})\n", .{try parseType(template_str, false)});
                try writer.print("{s},\n", .{try overrides.parse(struct_name, null, name, parsed_template)});
            } else {
                try writer.print("{s},\n", .{try parseFieldType(struct_name, name, type_str)});
            }
        }
        for (funcs) |func| {
            if (func.base == null) continue;
            const base = func.base.?;
            if (!std.mem.eql(u8, base.name, struct_name)) continue;
            try writer.writeAll("\n");
            try func.printFunc(writer);
        }
        try writer.writeAll("};\n\n");
    }

    // Print all the functions that aren't in a struct.
    for (funcs) |func| {
        if (func.base != null) continue;
        try func.printFunc(writer);
        try writer.writeAll("\n");
    }

    // Print raw functions
    try writer.writeAll("pub const raw = struct {\n");
    for (funcs) |func| try func.printExternFunc(writer);
    try writer.writeAll("};\n");
}

fn parseArgType(
    struct_name: []const u8,
    func_name: []const u8,
    arg_name: []const u8,
    type_name: []const u8,
) ![]const u8 {
    const parsed_type = try parseType(type_name, !std.mem.eql(u8, arg_name, "return"));
    return try overrides.parse(if (struct_name.len == 0) null else struct_name, func_name, arg_name, parsed_type);
}

fn parseFieldType(
    struct_name: []const u8,
    field_name: []const u8,
    type_name: []const u8,
) ![]const u8 {
    const parsed_type = try parseType(type_name, false);
    return try overrides.parse(struct_name, null, field_name, parsed_type);
}

fn parseType(type_str_arg: []const u8, is_func_arg: bool) ![]const u8 {
    // Remove trailing const, it doesn't mean anything to Zig.
    var type_str = suffixTrim(type_str_arg, "const");
    if (type_map.get(type_str)) |v| return v;

    if (std.mem.startsWith(u8, type_str, "union")) {
        var parsed_union = std.ArrayList(u8).init(allocator);
        try parsed_union.appendSlice("extern union {");
        const start = std.mem.indexOfScalar(u8, type_str, '{').? + 1;
        const end = std.mem.lastIndexOfScalar(u8, type_str, '}').?;
        var tokens = std.mem.tokenize(u8, type_str[start..end], ";");
        while (tokens.next()) |token| {
            const name_index = std.mem.lastIndexOfAny(u8, token, &std.ascii.whitespace).? + 1;
            try parsed_union.writer().print("{s}: {s}, ", .{ trim(token[name_index..]), try parseType(token[0..name_index], is_func_arg) });
        }
        try parsed_union.append('}');
        return parsed_union.toOwnedSlice();
    }

    if (std.mem.indexOf(u8, type_str, "(*)")) |ptr_index| {
        // Function pointer
        const return_type = try parseType(type_str[0..ptr_index], is_func_arg);
        var args = type_str[ptr_index + 3 ..];
        args = args[std.mem.indexOfScalar(u8, args, '(').? + 1 .. std.mem.lastIndexOfScalar(u8, args, ')').?];
        var split = std.mem.tokenize(u8, args, ",");
        var parsed_args = std.ArrayList(u8).init(allocator);
        while (split.next()) |arg| {
            var arg_str: []const u8 = undefined;
            if (getIdentifierCount(arg) > 1) {
                const split_index = std.mem.lastIndexOfAny(u8, arg, comptime std.ascii.whitespace ++ "*").? + 1;
                const parsed_name = trimFront(arg, split_index);
                const parsed_type = try parseType(trim(arg[0..split_index]), is_func_arg);
                arg_str = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ parsed_name, parsed_type });
            } else {
                arg_str = try parseType(trim(arg), is_func_arg);
            }
            try parsed_args.appendSlice(arg_str);
            try parsed_args.append(',');
        }
        _ = parsed_args.pop(); // Remove the last comma if it exists.
        return std.fmt.allocPrint(allocator, "?*const fn ({s}) callconv(.C) {s}", .{ parsed_args.items, return_type });
    }

    { // Parse pointers
        const is_const = std.mem.startsWith(u8, type_str, "const");
        if (is_const) type_str = trimFront(type_str, 5);
        var ptr_ending: ?[]const u8 = null;
        if (std.mem.endsWith(u8, type_str, "*")) ptr_ending = "*";
        if (std.mem.endsWith(u8, type_str, "[]")) ptr_ending = "[]";
        if (ptr_ending) |end_str| {
            const ptr_type = try std.fmt.allocPrint(allocator, "[*c]{s}{s}", .{
                if (is_const) "const " else "",
                try parseType(suffixTrim(type_str, end_str), is_func_arg),
            });
            return type_map.get(ptr_type) orelse ptr_type;
        }
    }

    if (std.mem.endsWith(u8, type_str, "]")) {
        const start = std.mem.lastIndexOfScalar(u8, type_str, '[').?;
        const end = std.mem.lastIndexOfScalar(u8, type_str, ']').?;
        const number_str = type_str[start + 1 .. end];
        //const num = std.fmt.parseInt(u64, number_str, 0) catch unreachable;
        return try std.fmt.allocPrint(allocator, "{s}[{s}]{s}", .{
            if (is_func_arg) "*" else "",
            number_str,
            try parseType(trim(type_str[0..start]), is_func_arg),
        });
    }

    return parseIdentifier(type_str);
}

fn parseIdentifier(name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, name, "STB_TexteditState")) return "StbTexteditState";
    if (std.mem.startsWith(u8, name, "ImVector_")) {
        var rest = name[9..];
        var prefix: []const u8 = "";
        if (std.mem.endsWith(u8, rest, "Ptr")) {
            rest = rest[0 .. rest.len - 3];
            prefix = "?*";
        }
        return std.fmt.allocPrint(allocator, "{s}Vector({s})", .{ prefix, try parseIdentifier(rest) });
    }
    if (std.mem.startsWith(u8, name, "ImGui")) return name[5..];
    if (std.mem.startsWith(u8, name, "Im")) return name[2..];
    return name;
}

fn parseArgName(str: []const u8) []const u8 {
    if (std.mem.eql(u8, str, "type")) return "@\"type\"";
    if (std.mem.eql(u8, str, "u0")) return "@\"u0\"";
    if (std.mem.eql(u8, str, "u1")) return "@\"u1\"";
    // HACK(Daniel): We should detect name clashes with functions and append "_arg" that way.
    if (std.mem.eql(u8, str, "button")) return "button_arg";
    if (std.mem.eql(u8, str, "text")) return "text_arg";
    if (std.mem.eql(u8, str, "separator")) return "separator_arg";
    return str;
}

fn parseFieldName(parent: []const u8, str: []const u8) ![]const u8 {
    if (str.len == 0) return "value";
    var name = str;
    if (std.mem.startsWith(u8, name, parent)) {
        name = prefixTrim(name, parent);
        name = prefixTrim(name, "_");
    }
    name = prefixTrim(name, "ImGui");
    // NOTE(Daniel): Do not trim '_' at the front because it denotes that a field is meant to be private.
    //name = prefixTrim(name, "_");
    //if (std.mem.indexOfScalar(u8, name, '_')) |underscore| name = name[underscore + 1 ..];

    // We have to convert to snake case here.
    var snake_case = std.ArrayList(u8).init(allocator);
    for (name) |c, i| {
        if (std.ascii.isLower(c) or c == '_') {
            try snake_case.append(c);
            continue;
        }
        if (i != 0 and std.ascii.isLower(name[i - 1])) try snake_case.append('_');
        try snake_case.append(std.ascii.toLower(c));
    }

    _ = std.fmt.parseInt(u64, snake_case.items, 0) catch return snake_case.items;
    // This parsed to a number, which means we have to wrap it.
    try snake_case.insertSlice(0, "@\"");
    try snake_case.append('"');
    return snake_case.items;
}

fn parseFunctionName(str: []const u8, is_struct_func: bool) ![]const u8 {
    var name = prefixTrim(str, "ig");
    if (is_struct_func) name = trimFront(str, std.mem.indexOfScalar(u8, name, '_').? + 1);
    var camel_case = std.ArrayList(u8).init(allocator);
    try camel_case.appendSlice(name);
    camel_case.items[0] = std.ascii.toLower(camel_case.items[0]);
    var i: usize = 0;
    while (i < camel_case.items.len) {
        if (camel_case.items[i] == '_') {
            _ = camel_case.orderedRemove(i);
            camel_case.items[i] = std.ascii.toUpper(camel_case.items[i]);
            continue;
        }
        i += 1;
    }
    return camel_case.toOwnedSlice();
}

fn parseDefaultValue(enums: EnumMap, type_str: []const u8, str: []const u8) ![]const u8 {
    var value_str = suffixTrim(str, "f");
    value_str = prefixTrim(value_str, "+");
    if (std.mem.eql(u8, value_str, "NULL")) return "null";
    if (std.mem.startsWith(u8, value_str, "ImVec2") or std.mem.startsWith(u8, value_str, "ImVec4")) {
        var it = std.mem.tokenize(u8, value_str[7 .. value_str.len - 1], std.ascii.whitespace ++ ",");
        var i: usize = 0;
        var builder = std.ArrayList(u8).init(allocator);
        try builder.appendSlice(value_str[2..6]);
        try builder.appendSlice(".init(");
        while (it.next()) |token| : (i += 1) {
            if (i != 0) try builder.appendSlice(", ");
            try builder.appendSlice(try parseDefaultValue(enums, type_str, token));
        }
        try builder.append(')');
        return builder.toOwnedSlice();
    }
    if (enums.get(type_str)) |is_flag| {
        if (is_flag) {
            return std.fmt.allocPrint(allocator, "@bitCast({s}, @as(FlagsInt, {s}))", .{ type_str, value_str });
        } else {
            return std.fmt.allocPrint(allocator, "@intToEnum({s}, {s})", .{ type_str, value_str });
        }
    }
    if (std.mem.startsWith(u8, value_str, "sizeof")) {
        return std.fmt.allocPrint(allocator, "@sizeOf({s})", .{try parseType(value_str[7..value_str.len - 1], false)});
    }
    return value_str;
}

fn getIdentifierCount(str: []const u8) usize {
    var i: usize = 0;
    var it = std.mem.tokenize(u8, str, std.ascii.whitespace ++ "*");
    while (it.next()) |token| {
        if (std.mem.eql(u8, token, "const")) continue;
        i += 1;
    }
    std.debug.assert(i > 0 and i < 3);
    return i;
}

fn isSkip(name: []const u8, location: []const u8) bool {
    // Internals not supported.
    if (std.mem.startsWith(u8, location, "imgui_internal")) return true;
    // We include these in the template file.
    if (std.mem.eql(u8, name, "ImColor")) return true;
    if (std.mem.eql(u8, name, "ImVec2")) return true;
    if (std.mem.eql(u8, name, "ImVec4")) return true;
    return false;
}

fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, &std.ascii.whitespace);
}

fn trimFront(str: []const u8, start: usize) []const u8 {
    return std.mem.trim(u8, str[start..], &std.ascii.whitespace);
}

fn trimBack(str: []const u8, end: usize) []const u8 {
    return std.mem.trim(u8, str[0 .. str.len - end], &std.ascii.whitespace);
}

fn prefixTrim(str: []const u8, starts: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, str, starts)) trimFront(str, starts.len) else trim(str);
}

fn suffixTrim(str: []const u8, ends: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, str, ends)) trimBack(str, ends.len) else trim(str);
}
