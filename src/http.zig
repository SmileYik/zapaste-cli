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
    var body = options.body orelse .None;
    const authorization: std.http.Client.Request.Headers.Value =
        if (options.authorization) |auth|
            .{ .override = auth }
        else
            .default;

    // we use a new client instance. because seems use the same client will occur issue when read body data.
    var client_: std.http.Client = .{ .allocator = allocator };
    const client = &client_;
    defer client.deinit();

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    const payload, const content_type = switch (body) {
        .FormData => |*data| .{ try data.getBody(), try data.getContentType() },
        .Manual => |data| .{ data.body, data.content_type },
        else => .{ null, null },
    };

    const result = try client.fetch(.{
        .method = method,
        .location = .{ .uri = uri },
        .payload = payload,
        .headers = .{
            .accept_encoding = .{ .override = "" },
            .authorization = authorization,
            .content_type = if (content_type) |t| .{ .override = t } else .default,
        },
        .keep_alive = false,
        .response_writer = &allocating.writer,
    });

    std.log.debug("Response {d}: {s}", .{
        @intFromEnum(result.status),
        result.status.phrase() orelse "",
    });
    if (result.status.class() != .success) {
        var buffer: [4096]u8 = undefined;
        const error_msg = try std.fmt.bufPrint(&buffer,
            \\{{ "code": {d}, "message": "{s}" }}
        , .{
            @intFromEnum(result.status),
            result.status.phrase() orelse "",
        });
        std.log.debug("Request Failed: {s}", .{error_msg});
        return std.json.parseFromSlice(
            T,
            allocator,
            error_msg,
            .{ .ignore_unknown_fields = true },
        );
    }

    const content_body = allocating.written();
    std.log.debug("Request Successful: {s}", .{content_body});
    return std.json.parseFromSlice(
        T,
        allocator,
        content_body,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
}
