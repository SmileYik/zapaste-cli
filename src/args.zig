const std = @import("std");
const api = @import("api.zig");
const Allocator = std.mem.Allocator;

const Args = @This();

const Item = struct {
    name: []const u8,
    alias: []const []const u8 = &.{},
    length: u8 = 1,
    handle: *const fn (args: *Args, params: []const []const u8) anyerror!void,
};

const ITEMS: []const Item = &.{
    autoSetItem("--url", "base_url", &.{"-u"}),
    autoSetItem("--token", "token", &.{"-t"}),
};

allocator: Allocator,
paste: api.Paste = .{},
base_url: ?[]const u8 = null,
filepaths: std.ArrayList([]const u8),
token: ?[]const u8 = null,
verify_password: ?[]const u8 = null,
target_paste_name: ?[]const u8 = null,
args: std.ArrayList([]const u8),

pub fn init(allocator: Allocator) !Args {
    var iter = try std.process.argsWithAllocator(allocator);
    defer iter.deinit();

    var args = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    while (iter.next()) |next| {
        try args.append(allocator, try std.fmt.allocPrint(allocator, "{s}", .{next}));
    }

    return .{
        .allocator = allocator,
        .filepaths = try std.ArrayList([]const u8).initCapacity(allocator, 4),
        .args = args,
    };
}

pub fn parseArgs(self: *Args) !void {
    var i: usize = 1;
    while (i < self.args.items.len) {
        const name = self.args.items[i];
        var find = false;
        for (ITEMS) |item| {
            if (std.mem.eql(u8, name, item.name)) {
                const next = i + item.length;
                try item.handle(self, self.args.items[i + 1 .. next + 1]);
                i = next;
                find = true;
                break;
            }
        }
        if (!find) {
            std.log.debug("Unknown params: {s}", .{name});
        }
        i += 1;
    }
}

inline fn setField(self: *Args, name: []const u8, value: []const u8) !void {
    inline for (std.meta.fields(Args)) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            try self.assignValue(f.name, value);
        }
    }

    inline for (std.meta.fields(api.Paste)) |f| {
        const full_name = "paste." ++ f.name;
        if (std.mem.eql(u8, full_name, name)) {
            if (@field(self.paste, f.name) == null) {
                // try self.assignValue(f.name, value);
                // @field(self.paste, f.name) = value;
            }
        }
    }
}

inline fn assignValue(self: *Args, comptime field_name: []const u8, value: []const u8) !void {
    const T = @TypeOf(@field(self, field_name));

    switch (@typeInfo(T)) {
        // ?[]const u8
        .optional => |opt| {
            if (opt.child == []const u8) {
                if (@field(self, field_name) == null) {
                    @field(self, field_name) = value;
                }
            }
        },
        .int => {
            @field(self, field_name) = try std.fmt.parseInt(T, value, 10);
        },
        // []const u8
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                @field(self, field_name) = value;
            }
        },
        else => {},
    }
}

inline fn autoSetItem(
    comptime name: []const u8,
    comptime field_name: []const u8,
    comptime alias: []const []const u8,
) Item {
    return .{
        .name = name,
        .alias = alias,
        .handle = struct {
            fn h(args: *Args, params: []const []const u8) !void {
                _ = try args.setField(field_name, params[0]);
            }
        }.h,
    };
}
