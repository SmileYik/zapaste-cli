const std = @import("std");
pub const FormData = @import("form_data.zig");

const Allocator = std.mem.Allocator;

pub const BodyType = enum {
    None,
    FormData,
    Manual,
};

pub const BodyData = union(BodyType) {
    None,
    FormData: FormData,
    Manual: struct {
        body: []u8,
        content_type: []const u8,
    },
};

pub const RequestOptions = struct {
    allocator: Allocator,
    client: *std.http.Client,
    method: std.http.Method,
    url: []const u8,
    body: ?BodyData = .None,
    authorization: ?[]const u8 = null,
};

pub inline fn request(
    comptime T: type,
    options: RequestOptions,
) !std.json.Parsed(T) {
    const uri = try std.Uri.parse(options.url);
    const method = options.method;
    const allocator = options.allocator;
    const body = options.body orelse .None;
    const authorization: std.http.Client.Request.Headers.Value =
        if (options.authorization) |auth|
            .{ .override = auth }
        else
            .default;

    // we use a new client instance. because seems use the same client will occur issue when read body data.
    var client_: std.http.Client = .{ .allocator = allocator };
    const client = &client_;
    defer client.deinit();

    std.log.debug(
        \\
        \\
        \\==================
        \\  {s}: '{s}'
        \\  AUTH: '{s}'
        \\  Body: '{s}'
        \\------------------
    , .{
        @tagName(method),
        options.url,
        options.authorization orelse "",
        @tagName(body),
    });

    var req = try client.request(
        method,
        uri,
        .{
            .headers = .{
                .accept_encoding = .{ .override = "" },
                .authorization = authorization,
            },
            .keep_alive = false,
        },
    );
    defer req.deinit();

    // send body
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
            std.log.debug("****BodyStart\n{s}\n****BodyEnd", .{try form.getBody()});
            try req.sendBodyComplete(try form.getBody());
        },
    }

    // receive
    var response = try req.receiveHead(&.{});

    std.log.debug("Response {d}: {s}", .{
        @intFromEnum(response.head.status),
        response.head.status.phrase() orelse "",
    });
    if (response.head.status.class() != .success) {
        var buffer: [4096]u8 = undefined;
        const error_msg = try std.fmt.bufPrint(&buffer,
            \\{{ "code": {d}, "message": "{s}" }}
        , .{
            @intFromEnum(response.head.status),
            response.head.status.phrase() orelse "",
        });
        std.log.debug("Request Failed: {s}", .{error_msg});
        return std.json.parseFromSlice(
            T,
            allocator,
            error_msg,
            .{ .ignore_unknown_fields = true },
        );
    }

    // header
    var it = response.head.iterateHeaders();
    while (it.next()) |header| {
        std.log.debug("Header: {s}: {s}", .{ header.name, header.value });
    }

    // body
    var response_buffer: [4 * 1024]u8 = undefined;
    var reader = response.reader(&response_buffer);
    var response_body = try std.ArrayList(u8).initCapacity(allocator, 10 * 1024 * 1024);
    defer response_body.deinit(allocator);

    while (reader.takeArray(response_buffer.len)) |bytes| {
        try response_body.appendSlice(allocator, bytes);
    } else |err| switch (err) {
        std.io.Reader.Error.EndOfStream => {
            try response_body.appendSlice(allocator, reader.buffer[0..reader.end]);
        },
        else => return err,
    }

    std.log.debug("Request Successful: {s}", .{response_body.items});
    return std.json.parseFromSlice(
        T,
        allocator,
        response_body.items,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
}
