const std = @import("std");
const Allocator = std.mem.Allocator;
const Encoder = std.base64.url_safe.Encoder;

pub fn getBasicToken(
    allocator: Allocator,
    username: []const u8,
    password: []const u8,
) ![]const u8 {
    const str = try std.fmt.allocPrint(
        allocator,
        "{s}:{s}",
        .{
            std.mem.trim(u8, username, " \n\t"),
            std.mem.trim(u8, password, " \n\t"),
        },
    );
    defer allocator.free(str);

    const size = Encoder.calcSize(str.len);
    const buffer = try allocator.alloc(u8, size);
    defer allocator.free(buffer);

    @memset(buffer, 0);
    const encoded = Encoder.encode(buffer, str);
    return try std.fmt.allocPrint(allocator, "Basic {s}", .{encoded});
}
