const std = @import("std");
const zapaste = @import("zapaste");
const FormData = @import("formdata.zig");

const http = std.http;
const HttpClient = http.Client;
const Allocator = std.mem.Allocator;

// Zapaste entities

pub const PageList = zapaste.page_list.PageList;
pub const ApiResult = zapaste.result.create;

pub const Paste = zapaste.paste.Paste;
pub const PasteSummary = Paste.Summary;

pub const File = zapaste.file.File;

pub const PasswordModel = struct { password: ?[]const u8 = null };

pub const UpdatePasteModel = struct { password: ?[]const u8 = null, paste: ?Paste = null };

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

pub const PasteClient = struct {
    allocator: Allocator,
    client: std.http.Client,
    base_url: []const u8,

    pub fn init(allocator: Allocator, base_url: []const u8) PasteClient {
        return .{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .base_url = base_url,
        };
    }

    pub fn deinit(self: *PasteClient) void {
        self.client.deinit();
    }

    /// Get public paste list.
    pub fn getPasteList(self: *PasteClient, page_no: u32, page_size: u32) !std.json.Parsed(ApiResult(PageList(PasteSummary))) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_GET_PASTE_LIST,
            .{ self.base_url, page_no, page_size },
        );

        return self.request(.GET, url, .None, ApiResult(PageList(PasteSummary)));
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

        return self.request(
            .POST,
            url,
            .{ .Manual = .{
                .content_type = HTTP_CONTENT_TYPE_JSON,
                .body = body_array.items,
            } },
            ApiResult(PasteModel),
        );
    }

    /// create paste with files
    pub fn createPaste(self: *PasteClient, paste: Paste, filepaths: ?[]const []const u8) !std.json.Parsed(ApiResult(PasteModel)) {
        var path_buf: [1024]u8 = undefined;
        const url = try std.fmt.bufPrint(
            &path_buf,
            API_CREATE_PASTE,
            .{self.base_url},
        );

        var body = try FormData.init(self.allocator);
        defer body.deinit();

        var paste_json = try parseEntity2Json(self.allocator, paste);
        defer paste_json.deinit(self.allocator);

        try body.appendString("paste", paste_json.items);
        if (filepaths) |paths| {
            for (paths) |path| {
                try body.appendFile("file", path);
            }
        }

        return self.request(
            .POST,
            url,
            .{ .FormData = body },
            ApiResult(PasteModel),
        );
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

        var body = try FormData.init(self.allocator);
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

        return self.request(
            .PUT,
            url,
            .{ .FormData = body },
            ApiResult(PasteModel),
        );
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

        return self.request(
            .POST,
            url,
            .{
                .Manual = .{
                    .content_type = "application/json",
                    .body = body.items,
                },
            },
            ApiResult(u8),
        );
    }

    // 内部通用请求工具函数
    fn request(
        self: *PasteClient,
        method: std.http.Method,
        url_str: []const u8,
        body: BodyData,
        comptime T: type,
    ) !std.json.Parsed(T) {
        std.debug.print("{s}\n", .{url_str});
        const uri = try std.Uri.parse(url_str);

        var req = try self.client.request(
            method,
            uri,
            .{
                .headers = .{
                    .accept_encoding = .{ .override = "" },
                },
            },
        );
        defer req.deinit();

        switch (body) {
            .None => {
                try req.sendBodiless();
            },
            .Manual => |b| {
                req.headers.content_type = .{
                    .override = b.content_type,
                };
                try req.sendBodyComplete(b.body);
            },
            .FormData => |form_| {
                var form = form_;
                req.headers.content_type = .{
                    .override = form.getContentType() catch "",
                };
                try req.sendBodyComplete(form.getBody() catch "");
            },
        }

        // var redirect_buffer: [4 * 1024]u8 = undefined;
        var response = try req.receiveHead(&.{});
        if (response.head.status.class() != .success) {
            var result_buffer: [4096]u8 = undefined;
            const error_msg = try std.fmt.bufPrint(&result_buffer,
                \\{{ "code": {d}, "message": "{s}" }}
            , .{
                @intFromEnum(response.head.status),
                response.head.status.phrase() orelse "",
            });
            return std.json.parseFromSlice(
                T,
                self.allocator,
                error_msg,
                .{ .ignore_unknown_fields = true },
            );
        }

        // header
        var it = response.head.iterateHeaders();
        while (it.next()) |header| {
            std.debug.print("{s}: {s}\n", .{ header.name, header.value });
        }

        // body
        var response_buffer: [4 * 1024]u8 = undefined;
        var reader = response.reader(&response_buffer);
        var response_body = try std.ArrayList(u8).initCapacity(self.allocator, 10 * 1024 * 1024);
        defer response_body.deinit(self.allocator);

        while (reader.takeArray(response_buffer.len)) |bytes| {
            try response_body.appendSlice(self.allocator, bytes);
        } else |err| switch (err) {
            std.io.Reader.Error.EndOfStream => {
                try response_body.appendSlice(self.allocator, reader.buffer[0..reader.end]);
            },
            else => return err,
        }
        std.debug.print("{s}\n", .{response_body.items});
        return std.json.parseFromSlice(
            T,
            self.allocator,
            response_body.items,
            .{ .ignore_unknown_fields = true },
        );
    }
};

// HTTP things

const BodyType = enum {
    None,
    FormData,
    Manual,
};

const BodyData = union(BodyType) {
    None,
    FormData: FormData,
    Manual: struct {
        body: []u8,
        content_type: []const u8,
    },
};

const HTTP_CONTENT_TYPE_JSON = "application/json";

inline fn parseEntity2Json(allocator: Allocator, value: anytype) !std.ArrayList(u8) {
    var array = try std.ArrayList(u8).initCapacity(allocator, 4 * 1024);
    const formatter = std.json.fmt(value, .{ .emit_null_optional_fields = true });
    try array.writer(allocator).print("{f}", .{formatter});
    return array;
}
