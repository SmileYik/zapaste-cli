const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @This();

pub const ConfigJson = struct {
    base_url: ?[]const u8 = null,
    token: ?[]const u8 = null,
};

allocator: Allocator = null,
data: ConfigJson = .{},

pub fn init(allocator: Allocator) Config {
    return .{ .allocator = allocator };
}

pub fn deinit(self: Config) void {
    if (self.data.base_url) |str| {
        self.allocator.free(str);
    }
    if (self.data.token) |str| {
        self.allocator.free(str);
    }
}

pub fn load(self: Config) !void {
    var file = try self.openConfigFile(.read_only);
    defer file.close();

    const content = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    defer self.allocator.free(content);

    const parsed = try std.json.parseFromSlice(
        ConfigJson,
        self.allocator,
        content,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    self.setConfigData(parsed.value);
}

pub fn store(self: Config) !void {
    const fmt = std.json.fmt(self.data, .{ .whitespace = .indent_4 });
    const content = try std.fmt.allocPrint(self.allocator, "{f}", .{fmt});
    defer self.allocator.free(content);

    var file = try self.openConfigFile(.write_only);
    defer file.close();
    try file.writeAll(content);
}

pub fn setConfigData(self: Config, config: ConfigJson) !void {
    self.data.base_url = if (config.base_url) |str|
        try self.allocator.dupe(u8, str)
    else
        null;

    self.data.token = if (config.token) |str|
        try self.allocator.dupe(u8, str)
    else
        null;
}

inline fn openConfigFile(self: Config, mode: std.fs.File.OpenMode) !std.fs.File {
    const dir = try std.fs.getAppDataDir(self.allocator, "zapaste-cli");
    defer self.allocator.free(dir);

    try std.fs.cwd().makePath(dir);

    var buffer: [4 * 1024]u8 = undefined;
    const config_file = try std.fmt.bufPrint(&buffer, "{s}/config.json", .{dir});
    return std.fs.cwd().openFile(config_file, .{ .mode = mode });
}
