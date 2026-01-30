const std = @import("std");
const zapaste = @import("zapaste");
const FormData = @import("formdata.zig");

const http = std.http;
const HttpClient = http.Client;
const Allocator = std.mem.Allocator;

// Zapaste entities

pub const PageList = zapaste.common.PageList;
pub const ApiResult = zapaste.common.Result.create;

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
        const body_array = try pasteEntity2Json(PasswordModel, self.allocator, password_model);

        return self.request(
            .GET,
            url,
            .{ .Manual = .{
                .content_type = HTTP_CONTENT_TYPE_JSON,
                .body = body_array.items,
            } },
            ApiResult(PasteModel),
        );
    }

    /// 创建新的 Paste
    pub fn createPaste(self: *PasteClient, paste: Paste) !std.json.Parsed(ApiResult(PasteModel)) {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/paste", .{self.base_url});
        defer self.allocator.free(url);

        const body = try std.json.stringifyAlloc(self.allocator, paste, .{ .emit_null_optional_fields = false });
        defer self.allocator.free(body);

        return self.request(.POST, url, body, ApiResult(PasteModel));
    }

    /// 删除 Paste
    pub fn deletePaste(self: *PasteClient, name: []const u8, password: ?[]const u8) !std.json.Parsed(ApiResult(u8)) {
        var path_buf: [1024]u8 = undefined;
        var url: []const u8 = "";
        var body: ?[]const u8 = null;

        if (password) |pw| {
            url = try std.fmt.bufPrint(&path_buf, "{s}/api/paste/{s}/delete", .{ self.base_url, name });
            const payload = .{ .password = pw };
            body = try std.json.stringifyAlloc(self.allocator, payload, .{});
        } else {
            url = try std.fmt.bufPrint(&path_buf, "{s}/api/paste/{s}", .{ self.base_url, name });
        }
        defer if (body) |b| self.allocator.free(b);

        return self.request(
            if (password != null) .POST else .DELETE,
            url,
            .{
                .Manual = .{
                    .content_type = "application/json",
                    .body = body,
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
            return error.HttpError;
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

inline fn pasteEntity2Json(comptime T: type, allocator: Allocator, value: T) !std.ArrayList(u8) {
    var array = try std.ArrayList(u8).initCapacity(allocator, 4 * 1024);
    const formatter = std.json.fmt(value, .{ .emit_null_optional_fields = true });

    const result = try std.fmt.allocPrint(allocator, "{f}", formatter);
    defer allocator.free(result);
    try array.appendSlice(allocator, result);
    return array;
}
