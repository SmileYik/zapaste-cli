const std = @import("std");
const zapaste = @import("zapaste");
const http = @import("http.zig");

const HttpClient = std.http.Client;
const Allocator = std.mem.Allocator;

// Zapaste entities

pub const PageList = zapaste.page_list.PageList;
pub const ApiResult = zapaste.result.create;

pub const Paste = zapaste.paste.Paste;
pub const PasteSummary = Paste.Summary;

pub const File = zapaste.file.File;

pub const PasswordModel = struct {
    password: ?[]const u8 = null,
};

pub const UpdatePasteModel = struct {
    password: ?[]const u8 = null,
    paste: ?Paste = null,
};

pub const PasteModel = struct {
    paste: ?Paste = null,
    files: ?[]File = null,
};

// API URLS

/// get paste list by page no and page size.
const API_GET_PASTE_LIST = "{s}/api/paste?page_no={d}&page_size={d}";

/// create paste
const API_CREATE_PASTE = "{s}/api/paste";

/// get paste by paste name,
const API_GET_PASTE = "{s}/api/paste/{s}";

/// update paste by paste name
const API_UPDATE_PASTE = "{s}/api/paste/{s}";

/// delete paste by paste name
const API_DELETE_PASTE = "{s}/api/paste/{s}/delete";

/// download paste file by paste name and file name.
const API_DOWNLOAD_FILE = "{s}/api/paste/{s}/file/name/{s}";

// API implements

pub const Options = struct {
    allocator: Allocator,
    base_url: []const u8,
    authorization: ?[]const u8 = null,
};

pub const PasteClient = struct {
    allocator: Allocator,
    client: std.http.Client,
    base_url: []const u8,
    authorization: ?[]const u8,

    pub fn init(options: Options) PasteClient {
        const allocator = options.allocator;
        const base_url = options.base_url;
        const authorization = options.authorization;

        return .{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .base_url = base_url,
            .authorization = authorization,
        };
    }

    pub fn deinit(self: *PasteClient) void {
        &self.client.deinit();
    }

    /// Get public paste list.
    pub fn getPasteList(self: *PasteClient, page_no: u32, page_size: u32) !std.json.Parsed(ApiResult(PageList(PasteSummary))) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_GET_PASTE_LIST,
            .{ self.base_url, page_no, page_size },
        );

        return http.request(ApiResult(PageList(PasteSummary)), .{
            .method = .GET,
            .url = url,
            .body = .None,
            .allocator = self.allocator,
            .authorization = self.authorization,
            .client = &self.client,
        });
    }

    /// get paste
    pub fn getPaste(self: *PasteClient, name: []const u8, password: ?[]const u8) !std.json.Parsed(ApiResult(PasteModel)) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_GET_PASTE,
            .{ self.base_url, name },
        );

        const password_model: PasswordModel = .{ .password = password };
        var body_array = try parseEntity2Json(self.allocator, password_model);
        defer body_array.deinit(self.allocator);

        return http.request(ApiResult(PasteModel), .{
            .method = .POST,
            .url = url,
            .body = .{ .Manual = .{
                .content_type = HTTP_CONTENT_TYPE_JSON,
                .body = body_array.items,
            } },
            .allocator = self.allocator,
            .authorization = self.authorization,
            .client = &self.client,
        });
    }

    /// create paste with files
    pub fn createPaste(self: *PasteClient, paste: Paste, filepaths: ?[]const []const u8) !std.json.Parsed(ApiResult(PasteModel)) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_CREATE_PASTE,
            .{self.base_url},
        );

        var body = try http.FormData.init(self.allocator);
        defer body.deinit();

        var paste_json = try parseEntity2Json(self.allocator, paste);
        defer paste_json.deinit(self.allocator);

        try body.appendString("paste", paste_json.items);
        if (filepaths) |paths| {
            for (paths) |path| {
                try body.appendFile("file", path);
            }
        }

        return http.request(ApiResult(PasteModel), .{
            .method = .POST,
            .allocator = self.allocator,
            .client = &self.client,
            .body = .{ .FormData = body },
            .url = url,
            .authorization = self.authorization,
        });
    }

    /// update paste with files
    pub fn updatePaste(
        self: *PasteClient,
        paste_name: []const u8,
        password: ?[]const u8,
        paste: Paste,
        filepaths: ?[]const []const u8,
    ) !std.json.Parsed(ApiResult(PasteModel)) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_UPDATE_PASTE,
            .{ self.base_url, paste_name },
        );

        var body = try http.FormData.init(self.allocator);
        defer body.deinit();

        const update_model: UpdatePasteModel = .{ .password = password, .paste = paste };
        var paste_json = try parseEntity2Json(self.allocator, update_model);
        defer paste_json.deinit(self.allocator);

        try body.appendString("paste", paste_json.items);
        if (filepaths) |paths| {
            for (paths) |path| {
                try body.appendFile("file", path);
            }
        }
        return http.request(ApiResult(PasteModel), .{
            .allocator = self.allocator,
            .method = .PUT,
            .url = url,
            .authorization = self.authorization,
            .body = .{ .FormData = body },
            .client = &self.client,
        });
    }

    /// delete Paste
    pub fn deletePaste(self: *PasteClient, name: []const u8, password: ?[]const u8) !std.json.Parsed(ApiResult(u8)) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_DELETE_PASTE,
            .{ self.base_url, name },
        );

        const model: PasswordModel = .{ .password = password };
        const body = try parseEntity2Json(self.allocator, model);
        defer body.deinit(self.allocator);

        return http.request(ApiResult(u8), .{
            .allocator = self.allocator,
            .method = .POST,
            .url = url,
            .authorization = self.authorization,
            .body = .{ .Manual = .{
                .content_type = HTTP_CONTENT_TYPE_JSON,
                .body = body.items,
            } },
            .client = &self.client,
        });
    }
};

// HTTP things

const HTTP_CONTENT_TYPE_JSON = "application/json";

inline fn parseEntity2Json(allocator: Allocator, value: anytype) !std.ArrayList(u8) {
    var array = try std.ArrayList(u8).initCapacity(allocator, 4 * 1024);
    const formatter = std.json.fmt(value, .{ .emit_null_optional_fields = true });
    try array.writer(allocator).print("{f}", .{formatter});
    return array;
}
