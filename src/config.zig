const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @This();

pub const ConfigJson = struct {
    base_url: ?[]const u8 = null,
    token: ?[]const u8 = null,
};

allocator: Allocator,
data: ConfigJson = .{},

pub fn init(allocator: Allocator) !Config {
    var config: Config = .{ .allocator = allocator };
    config.load() catch |e| switch (e) {
        error.FileNotFound => {},
        else => return e,
    };
    return config;
}

pub fn deinit(self: Config) void {
    if (self.data.base_url) |str| {
        self.allocator.free(str);
    }
    if (self.data.token) |str| {
        self.allocator.free(str);
    }
}

inline fn load(self: *Config) !void {
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
    try self.setConfigData(parsed.value);
}

inline fn store(self: Config) !void {
    const fmt = std.json.fmt(self.data, .{ .whitespace = .indent_4 });
    const content = try std.fmt.allocPrint(self.allocator, "{f}", .{fmt});
    defer self.allocator.free(content);

    const filepath = try self.getConfigPath(self.allocator);
    defer self.allocator.free(filepath);
    try std.fs.cwd().writeFile(.{
        .data = content,
        .flags = .{ .truncate = true },
        .sub_path = filepath,
    });
}

pub fn setConfigData(self: *Config, config: ConfigJson) !void {
    self.deinit();
    self.data.base_url = null;
    self.data.token = null;

    self.data.base_url = if (config.base_url) |str|
        try self.allocator.dupe(u8, str)
    else
        null;

    self.data.token = if (config.token) |str|
        try self.allocator.dupe(u8, str)
    else
        null;

    try self.store();
}

inline fn openConfigFile(self: Config, mode: std.fs.File.OpenMode) !std.fs.File {
    const dir = try std.fs.getAppDataDir(self.allocator, "zapaste-cli");
    defer self.allocator.free(dir);

    try std.fs.cwd().makePath(dir);

    var buffer: [4 * 1024]u8 = undefined;
    const config_file = try std.fmt.bufPrint(&buffer, "{s}/config.json", .{dir});
    return std.fs.cwd().openFile(config_file, .{ .mode = mode });
}

inline fn getConfigPath(self: Config, allocator: Allocator) ![]const u8 {
    const dir = try std.fs.getAppDataDir(self.allocator, "zapaste-cli");
    defer self.allocator.free(dir);
    return try std.fmt.allocPrint(allocator, "{s}/config.json", .{dir});
}
