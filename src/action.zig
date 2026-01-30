//! The methods in this source code file are primarily for providing complex or simplified business logic.

const std = @import("std");
const api = @import("api.zig");

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
