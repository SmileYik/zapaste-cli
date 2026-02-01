const std = @import("std");

const Allocator = std.mem.Allocator;
const Array = std.ArrayList(u8);

const Self = @This();

const NEW_LIEN = "\r\n";

var prng: ?std.Random.DefaultPrng = null;
inline fn getPrng() *std.Random.DefaultPrng {
    if (prng == null) {
        prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    }
    return &prng.?;
}

pub const UploadFile = struct {
    filename: []const u8,
    mimetype: []const u8,
    data: []const u8,
};

// fields

allocator: Allocator,
array: Array,
boundary: []const u8,
finished: bool,
content_type: ?[]const u8 = null,

pub fn init(allocator: Allocator) !Self {
    const boundary = try randomBoundary(allocator, 16);
    return .{
        .allocator = allocator,
        .array = try Array.initCapacity(allocator, 4 * 1024),
        .boundary = boundary,
        .content_type = try std.fmt.allocPrint(
            allocator,
            "multipart/form-data; boundary={s}",
            .{boundary},
        ),
        .finished = false,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.boundary);
    self.array.deinit(self.allocator);
    if (self.content_type) |content_type| {
        self.allocator.free(content_type);
    }
}

pub fn appendString(
    self: *Self,
    key: []const u8,
    value: []const u8,
) !void {
    if (self.finished) return error.FinishedFormData;

    try self.array.writer(self.allocator).print(
        \\--{s}
        \\Content-Disposition: form-data; name="{s}"
        \\
        \\
        \\{s}
        \\
    , .{ self.boundary, key, value });
}

pub fn appendFile(
    self: *Self,
    key: []const u8,
    filepath: []const u8,
) !void {
    if (self.finished) return error.FinishedFormData;

    const filename = std.fs.path.basename(filepath);
    const data = try std.fs.cwd().readFileAlloc(
        self.allocator,
        filepath,
        std.math.maxInt(usize),
    );
    try self.appendFileData(key, .{
        .filename = filename,
        .data = data,
        .mimetype = "application/octet-stream",
    });
}

pub fn appendFileData(
    self: *Self,
    key: []const u8,
    filedata: UploadFile,
) !void {
    if (self.finished) return error.FinishedFormData;

    try self.array.writer(self.allocator).print(
        \\--{s}
        \\
        \\Content-Disposition: form-data; name="{s}"; filename="{s}"
        \\Content-Type: {s}
        \\
        \\{s}
        \\
    , .{
        self.boundary,
        key,
        filedata.filename,
        filedata.mimetype,
        filedata.data,
    });
}

pub fn getBody(self: *Self) ![]u8 {
    if (!self.finished) {
        self.finished = true;
        try self.array.writer(self.allocator).print("--{s}--\r\n", .{self.boundary});
    }
    return self.array.items;
}

pub fn getContentType(self: *Self) ![]const u8 {
    return self.content_type.?;
}

inline fn randomBoundary(allocator: std.mem.Allocator, length: usize) ![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const prefix = "----ZapasteBoundary";
    const random = getPrng().random();

    var result = try allocator.alloc(u8, prefix.len + length);
    @memcpy(result[0..prefix.len], prefix);
    for (0..length) |i| {
        const random_index = random.uintAtMost(usize, charset.len - 1);
        result[prefix.len + i] = charset[random_index];
    }

    return result;
}
