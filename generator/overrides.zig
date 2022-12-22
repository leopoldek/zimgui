const std = @import("std");
const Regex = @import("regex/regex.zig").Regex;
const generate = @import("generate.zig");
const Allocator = std.mem.Allocator;

/// There are all regex expressions (except for the type)
const Rule = struct {
    // TODO(Daniel): Fix this when we update to latest zig by removing the field names.
    @"0": []const u8,
    @"1": ?[]const u8,
    @"2": ?[]const u8,
    @"3": []const u8,
    @"4": []const u8,
};

/// Rules are checked top-to-bottom for the first match.
/// .{type_matcher, struct_matcher, func_matcher, field_arg_matcher, type_override}
/// - Any matcher that starts with a '#' is regex expression.
/// - If struct_matcher is null, we match a top-level function.
/// - If func_matcher is null, we match fields only.
/// - Empty matcher means match any.
/// - In the type override, '$' means we subsitute the type stripped of any pointer (so just the identifer).
const rules = [_]Rule{
    .{ "", "#.+", "", "self", "*$" },
    .{ "#^\\[\\*c\\]", "", "", "#^p_", "?*$" },

    .{ "", "FontAtlas", "", "out_bytes_per_pixel", "?*$" },
    .{ "", "", "saveIniSettingsToMemory", "out_ini_size", "?*$" },
    .{ "#^\\[\\*c\\]\\[\\*c\\]", "FontAtlas", "", "out_pixels", "*[*]$" },
    .{ "#^\\[\\*c\\]", "", "", "#^out_", "*$" },

    .{ "[*c]IO", "", "", "", "*IO" },
    .{ "[*c]DrawData", "", "", "", "*DrawData" },
    .{ "[*c]DrawList", "", "", "", "*DrawList" },
    .{ "[*c]FontAtlas", "", "", "", "?*FontAtlas" },
    .{ "[*c]Style", "", "", "", "?*Style" },

    .{ "", "DrawData", null, "cmd_lists", "[*]*DrawList" },
    .{ "", "IO", null, "get_clipboard_text_fn", "?*const fn (user_data: ?*anyopaque) callconv(.C) [*:0]const u8" },
    .{ "", "IO", null, "set_clipboard_text_fn", "?*const fn (user_data: ?*anyopaque, text: [*:0]const u8) callconv(.C) void" },
};

pub fn parse(
    struct_name: ?[]const u8,
    func_name: ?[]const u8,
    field_arg_name: []const u8,
    type_name: []const u8,
) ![]const u8 {
    for (rules) |rule| {
        if (!match(type_name, rule.@"0")) continue;
        if (rule.@"1" == null and struct_name != null) continue;
        if (rule.@"1") |matcher| {
            if (!match(struct_name orelse "", matcher)) continue;
        }
        if (rule.@"2" == null and struct_name == null) continue;
        if (rule.@"2" == null and func_name != null) continue;
        if (rule.@"2") |matcher| {
            if (!match(func_name orelse "", matcher)) continue;
        }
        if (!match(field_arg_name, rule.@"3")) continue;

        // Found rule.
        const identifier = if (std.mem.lastIndexOfAny(u8, type_name, "]*")) |i| type_name[i + 1 ..] else type_name;
        return try std.mem.replaceOwned(u8, generate.allocator, rule.@"4", "$", identifier);
    }
    return type_name;
}

fn match(input: []const u8, matcher: []const u8) bool {
    if (matcher.len == 0) return true;
    if (matcher[0] == '#') {
        var re = Regex.compile(generate.allocator, matcher[1..]) catch unreachable;
        return re.match(input) catch unreachable;
    } else {
        return std.mem.eql(u8, input, matcher);
    }
}
