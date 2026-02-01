//! The methods in this source code file are primarily for providing complex or simplified business logic.

const std = @import("std");
const api = @import("api.zig");
const Args = @import("args.zig");
const Config = @import("config.zig");
const Auth = @import("auth.zig");

const Allocator = std.mem.Allocator;

pub const PasteModelResult = std.json.Parsed(api.ApiResult(api.PasteModel));

pub fn createOrUpdatePaste(
    client: *api.PasteClient,
    paste: api.Paste,
    password: ?[]const u8,
) !bool {
    if (paste.name) |name| {
        var parsed = try client.getPaste(name, password);
        defer parsed.deinit();

        const result = parsed.value;
        var next =
            if (result.code == 200)
                // update
                try client.updatePaste(name, password, paste, null)
            else
                // create
                try client.createPaste(paste, null);
        defer next.deinit();
        return next.value.code == 200;
    }
}

pub fn uploadFiles(
    client: *api.PasteClient,
    name: []const u8,
    password: ?[]const u8,
    filepaths: []const []const u8,
) !bool {
    var parsed = try client.updatePaste(name, password, .{}, filepaths);
    defer parsed.deinit();
    return parsed.value.code == 200;
}

/// set global config.
pub fn setConfig(allocator: Allocator, config_options: Args.OptionsConfig) !Config {
    const config = Config.init(allocator);
    defer config.deinit();

    try config.load();
    const data = config.data;

    if (config_options.url) |url| {
        data.base_url = url;
    }

    if (config_options.user) |user| {
        if (config_options.password) |password| {
            const token = try Auth.getBasicToken(allocator, user, password);
            defer allocator.free(token);
            data.token = token;
        }
    }
    try config.setConfigData(data);

    const return_config = Config.init(allocator);
    try return_config.load();
    return return_config;
}

pub fn handleOptionsUpdate(
    client: *api.PasteClient,
    options: Args.OptionsUpdate,
) !PasteModelResult {
    const paste_name = options.target_paste_name.?;
    const password = options.verify_password;
    const paste = options.paste;
    const filepaths = if (options.filepaths) |paths| paths.items else null;
    try checkFilePathExists(filepaths);

    return client.updatePaste(paste_name, password, paste, filepaths);
}

pub fn handleOptionsReset(
    client: *api.PasteClient,
    options: Args.OptionsReset,
) !PasteModelResult {
    const paste_name = options.target_paste_name.?;
    const password = options.verify_password;
    const paste = options.paste;
    const filepaths = if (options.filepaths) |paths| paths.items else null;
    try checkFilePathExists(filepaths);

    if (options.clean_attachments) {
        paste.attachements = "";
    }

    var parsed = try client.getPaste(paste_name, password);
    defer parsed.deinit();

    const result = parsed.value;
    return if (result.code == 200)
        // update
        try client.updatePaste(paste_name, password, paste, filepaths)
    else if (options.create_if_not_exists)
        // create
        try client.createPaste(paste, null)
    else
        error.PasteIsNotExists;
}

pub fn handleOptionsCreate(
    client: *api.PasteClient,
    options: Args.OptionsCreate,
) !PasteModelResult {
    const paste = options.paste;
    const filepaths = if (options.filepaths) |paths| paths.items else null;
    try checkFilePathExists(filepaths);

    return try client.createPaste(paste, filepaths);
}

pub fn handleOptionsUpload(
    client: *api.PasteClient,
    options: Args.OptionsUpload,
) !PasteModelResult {
    const paste_name = options.target_paste_name.?;
    const password = options.verify_password;
    const filepaths = if (options.filepaths) |paths| paths.items else null;
    try checkFilePathExists(filepaths);

    return try client.updatePaste(paste_name, password, .{}, filepaths);
}

inline fn checkFilePathExists(filepaths: ?[]const []const u8) !void {
    if (filepaths) |paths| for (paths) |path| {
        try std.fs.cwd().access(path, .{ .mode = .read_only });
    };
}
