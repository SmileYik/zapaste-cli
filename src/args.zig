const std = @import("std");
const api = @import("api.zig");
const Allocator = std.mem.Allocator;

const Args = @This();

const Item = struct {
    /// based field name
    field_name: []const u8,

    /// command name
    name: []const u8,
    /// command alias
    alias: []const []const u8 = &.{},
    // description
    description: []const u8 = "",
    /// command args length
    length: u8 = 1,
    /// sub commands
    children: *const []const Item = &EMPTY_ITEMS,

    /// command handler
    ///
    /// - `args` is the instance of includes this command item.
    /// - `item` is the currently active Item
    /// - `field_path` is a path by `field_name`. format is `.field_name_1.field_name_2.field_name_n`. based on fields of `args` instance.
    /// - `params` is the command args slince, length is `length`
    ///
    handle: *const fn (
        args: *Args,
        item: *const Item,
        comptime field_path: []const u8,
        params: []const []const u8,
    ) anyerror!void,

    fn isMatch(self: Item, name: []const u8) bool {
        if (self.name.len == 0 or
            std.ascii.eqlIgnoreCase(self.name, name))
        {
            return true;
        }
        for (self.alias) |alias| {
            if (std.mem.eql(u8, alias, name)) {
                return true;
            }
        }
        return false;
    }
};

const Mode = enum {
    upload,
};

const EMPTY_ITEMS: []const Item = &.{};
const ITEMS: []const Item = &.{
    helpItem("--help", &.{"-h"}, "查看帮助", &ITEMS),
    actionSetItem("base_url", "--url", &.{"-u"}, "设置基础URL"),
    actionSetItem("token", "--token", &.{"-t"}, "设置Token"),
    subcommandItem("options_upload", "upload", &.{"u"}, "上传文件至剪切板.", &(&[_]Item{
        ITEM_FILEPATHS,
        ITEM_PASTE_NAME,
        ITEM_PASTE_PASSWORD,
        ITEM_PASTE_CONTENT,
        ITEM_PASTE_CONTENT_TYPE,
        ITEM_PASTE_PRIVATE,
        ITEM_PASTE_READ_ONLY,
        ITEM_PASTE_BURN_AFTER_READS,
    })),
};

const ITEM_FILEPATHS = actionSetItem("filepaths", "--file", &.{"-F"}, "添加要上传的文件的路径");
// paste current name and password
const ITEM_PASTE_NAME = actionSetItem("target_paste_name", "--name", &.{"-n"}, "剪切板名称");
const ITEM_PASTE_PASSWORD = actionSetItem("verify_password", "--password", &.{"-p"}, "剪切板密码");
// paste new name and password
const ITEM_PASTE_NEW_NAME = actionSetItem("paste.name", "--new-name", &.{"-nn"}, "设置剪切板新名称");
const ITEM_PASTE_NEW_PASSWORD = actionSetItem("paste.password", "--new-password", &.{"-np"}, "设置剪切板新密码");
// other paste things
const ITEM_PASTE_CONTENT = actionSetItem("paste.content", "--content", &.{"-c"}, "设置剪切板内容");
const ITEM_PASTE_CONTENT_TYPE = actionSetItem("paste.content_type", "--content-type", &.{"-ct"}, "设置剪切板内容类型");
const ITEM_PASTE_PRIVATE = actionSetBoolItem("paste.private", "--private", &.{"-P"}, "设置剪切板为私人可见");
const ITEM_PASTE_READ_ONLY = actionSetBoolItem("paste.read_only", "--readonly", &.{"--r"}, "设置剪切板仅可读");
const ITEM_PASTE_BURN_AFTER_READS = actionSetItem("paste.burn_after_reads", "--burn-after-reads", &.{"-bar"}, "设置剪切板阅读量到达指定数量后自动销毁");

const OptionsUpload = struct {
    paste: api.Paste = .{},
    filepaths: ?std.ArrayList([]const u8) = null,
    verify_password: ?[]const u8 = null,
    target_paste_name: ?[]const u8 = null,
};

allocator: Allocator,
base_url: ?[]const u8 = null,
token: ?[]const u8 = null,
mode: ?Mode = null,
args: std.ArrayList([]const u8),

options_upload: OptionsUpload = .{},

pub fn init(allocator: Allocator) !Args {
    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    while (iter.next()) |next| {
        try args.append(allocator, try std.fmt.allocPrint(allocator, "{s}", .{next}));
    }

    return .{
        .allocator = allocator,
        .args = args,
    };
}

pub fn deinit(self: *Args) void {
    if (self.options_upload.filepaths) |filepaths| {
        var f = filepaths;
        f.deinit(self.allocator);
    }

    for (self.args.items) |item| {
        self.allocator.free(item);
    }
    self.args.deinit(self.allocator);
}

pub fn parseArgs(self: *Args) !void {
    try handleCommandItems(
        self,
        ITEMS,
        null,
        "",
        self.args.items[1..],
    );
}

/// set field value by field path.
inline fn setField(self: *Args, field_path: []const u8, value: []const u8) !void {
    try self.setFieldRecursive(
        self,
        field_path[@min(@as(usize, 1), field_path.len)..],
        value,
    );
}

/// set field value of `instance`
inline fn setFieldRecursive(
    self: *Args,
    instance: anytype,
    comptime field_path: []const u8,
    value: []const u8,
) !void {
    const dot_idx: ?usize = comptime blk: {
        for (field_path, 0..) |char, idx| {
            if (char == '.') break :blk idx;
        }
        break :blk null;
    };

    if (dot_idx) |idx| {
        const name = field_path[0..idx];
        const path = field_path[idx + 1 ..];
        try self.setFieldRecursive(
            &@field(instance.*, name),
            path,
            value,
        );
    } else {
        try assignValue(self, instance, field_path, value);
    }
}

inline fn assignValue(self: *Args, instance: anytype, comptime field_name: []const u8, value: []const u8) !void {
    const T = @TypeOf(@field(instance, field_name));

    switch (@typeInfo(T)) {
        // optional
        .optional => |opt| {
            if (opt.child == std.ArrayList([]const u8)) {
                if (@field(instance, field_name) == null) {
                    @field(instance, field_name) = try std.ArrayList([]const u8).initCapacity(self.allocator, 16);
                }
                try (@field(instance, field_name)).?.append(self.allocator, value);
            } else {
                if (@field(instance, field_name) == null) {
                    try assignValueByType(instance, field_name, opt.child, value);
                }
            }
        },
        else => {
            try assignValueByType(instance, field_name, T, value);
        },
    }
}

inline fn assignValueByType(
    instance: anytype,
    comptime field_name: []const u8,
    comptime field_type: type,
    value: []const u8,
) !void {
    switch (@typeInfo(field_type)) {
        .int => {
            @field(instance, field_name) = try std.fmt.parseInt(field_type, value, 10);
        },
        .float => {
            @field(instance, field_name) = try std.fmt.parseFloat(field_type, value);
        },
        .bool => {
            @field(instance, field_name) = std.ascii.eqlIgnoreCase(value, "true");
        },
        .@"enum" => {
            @field(instance, field_name) = std.meta.stringToEnum(field_type, value);
        },
        // []const u8
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                @field(instance, field_name) = value;
            }
        },
        else => {},
    }
}

inline fn actionFixItem(
    comptime field_name: []const u8,
    comptime desc: []const u8,
) Item {
    return .{
        .field_name = field_name,
        .name = "",
        .length = 0,
        .description = desc,
        .handle = struct {
            fn h(args: *Args, _: *const Item, comptime field_path: []const u8, params: []const []const u8) !void {
                try args.setField(field_path ++ "." ++ field_name, params[0]);
            }
        }.h,
    };
}

inline fn actionSetItem(
    comptime field_name: []const u8,
    comptime name: []const u8,
    comptime alias: []const []const u8,
    comptime desc: []const u8,
) Item {
    return .{
        .field_name = field_name,
        .name = name,
        .alias = alias,
        .length = 1,
        .description = desc,
        .handle = struct {
            fn h(args: *Args, _: *const Item, comptime field_path: []const u8, params: []const []const u8) !void {
                try args.setField(field_path ++ "." ++ field_name, params[0]);
            }
        }.h,
    };
}

inline fn actionSetBoolItem(
    comptime field_name: []const u8,
    comptime name: []const u8,
    comptime alias: []const []const u8,
    comptime desc: []const u8,
) Item {
    return .{
        .field_name = field_name,
        .name = name,
        .alias = alias,
        .length = 0,
        .description = desc,
        .handle = struct {
            fn h(args: *Args, _: *const Item, comptime field_path: []const u8, _: []const []const u8) !void {
                try args.setField(field_path ++ "." ++ field_name, "true");
            }
        }.h,
    };
}

inline fn subcommandItem(
    comptime field_name: []const u8,
    comptime name: []const u8,
    comptime alias: []const []const u8,
    comptime desc: []const u8,
    comptime children: *const []const Item,
) Item {
    return .{
        .name = name,
        .field_name = field_name,
        .alias = alias,
        .length = std.math.maxInt(u8),
        .children = children,
        .description = desc,
        .handle = struct {
            fn h(
                args: *Args,
                item: *const Item,
                comptime field_path: []const u8,
                params: []const []const u8,
            ) !void {
                try handleCommandItems(
                    args,
                    item.children.*,
                    item.field_name,
                    field_path,
                    params,
                );
                try args.setField(".mode", name);
            }
        }.h,
    };
}

inline fn helpItem(
    comptime name: []const u8,
    comptime alias: []const []const u8,
    comptime desc: []const u8,
    comptime _: *const []const Item,
) Item {
    return .{
        .name = name,
        .field_name = "",
        .alias = alias,
        .length = std.math.maxInt(u8),
        .description = desc,
        .handle = struct {
            inline fn maxItemNameAndAliasWidth(items: *const []const Item) struct { usize, usize, usize } {
                var size: usize = 0;
                var subcommand: usize = 0;
                var options: usize = 0;
                inline for (items.*) |item| {
                    const s = itemNameAndAliasWidth(&item);
                    if (item.children.len == 0) {
                        options = @max(options, s);
                    } else {
                        subcommand = @max(subcommand, s);
                    }
                }
                size = @max(options, subcommand);
                return .{ subcommand, options, size };
            }

            inline fn itemNameAndAliasWidth(item: *const Item) usize {
                var size: usize = 0;
                size += item.name.len;
                inline for (item.alias) |a| {
                    size += 2;
                    size += a.len;
                }
                if (item.field_name.len != 0 and item.children.len == 0 and item.length != 0) {
                    size += getItemRealFieldName(item).len;
                    size += 3;
                }
                return size;
            }

            inline fn getItemRealFieldName(item: *const Item) []const u8 {
                const pos = std.mem.lastIndexOf(u8, item.field_name, ".");
                if (pos) |p| {
                    return item.field_name[p + 1 ..];
                }
                return item.field_name;
            }

            inline fn itemNameAndAlias(
                writer: *std.ArrayList(u8).Writer,
                item: *const Item,
            ) !usize {
                var size: usize = item.name.len;

                try writer.print("{s}", .{item.name});
                if (item.field_name.len != 0 and item.children.len == 0 and item.length != 0) {
                    const field_name = getItemRealFieldName(item);
                    size += field_name.len;
                    size += 3;
                    try writer.print(" [{s}]", .{field_name});
                }
                inline for (item.alias) |a| {
                    try writer.print(", {s}", .{a});
                    size += a.len;
                    size += 2;
                }

                return size;
            }

            inline fn printItemInSameWidth(
                writer: *std.ArrayList(u8).Writer,
                comptime prefix: []const u8,
                item: *const Item,
                width: usize,
            ) !void {
                try writer.writeAll(prefix);
                const size = try itemNameAndAlias(writer, item);
                try writer.writeBytesNTimes(" ", width - size);
                try writer.print("{s}\n", .{item.description});
            }

            fn h(
                args: *Args,
                _: *const Item,
                comptime _: []const u8,
                _: []const []const u8,
            ) !void {
                const allocator = std.heap.page_allocator;
                var text = try std.ArrayList(u8).initCapacity(allocator, 4 * 1024);
                defer text.deinit(allocator);

                var writer = text.writer(allocator);
                try writer.print(
                    \\Usage: {s} [options] [command] [command options]
                    \\
                    \\Options:
                    \\
                    \\
                , .{args.args.items[0]});

                // width
                const subcommand, const options, _ = maxItemNameAndAliasWidth(&ITEMS);

                // no children
                inline for (ITEMS) |item| {
                    if (item.children.len == 0) {
                        try printItemInSameWidth(&writer, "  ", &item, options + 4);
                    }
                }

                // subcommands
                try writer.print(
                    \\
                    \\Commands:
                    \\
                , .{});
                inline for (ITEMS) |item| {
                    if (item.children.len != 0) {
                        // subcommands
                        try writer.print("\n", .{});
                        try printItemInSameWidth(&writer, "  ", &item, subcommand + 4);

                        // options
                        _, const children_opts, _ = maxItemNameAndAliasWidth(item.children);
                        inline for (item.children.*) |child| {
                            try printItemInSameWidth(&writer, "    ", &child, children_opts + 4);
                        }
                    }
                }

                std.log.info("\n{s}", .{text.items});
            }
        }.h,
    };
}

inline fn handleCommandItems(
    args: *Args,
    items: []const Item,
    comptime field_name: ?[]const u8,
    comptime field_path: []const u8,
    params: []const []const u8,
) !void {
    var i: usize = 0;
    var next_fixed_item_idx: usize = 0;
    while (i < params.len) {
        const param = params[i];
        var found = false;
        const next_field_path = if (field_name) |name|
            field_path ++ "." ++ name
        else
            field_path;

        blk: {
            inline for (items, 0..) |child, item_idx| {
                const is_fix_item = child.name.len == 0;

                if (is_fix_item) {
                    if (item_idx == next_fixed_item_idx) {
                        try child.handle(
                            args,
                            &child,
                            next_field_path,
                            params[i .. i + 1],
                        );
                        next_fixed_item_idx += 1;
                        found = true;
                        break :blk;
                    }
                } else if (child.isMatch(param)) {
                    const next = i + @as(usize, @intCast(child.length));
                    try child.handle(
                        args,
                        &child,
                        next_field_path,
                        params[i + 1 .. @min(next + 1, params.len)],
                    );
                    i = next;
                    found = true;
                    break :blk;
                }
            }
        }

        i += 1;
        if (!found) {
            std.log.debug("Ignore unknown parameter: {s}", .{param});
        }
    }
}
