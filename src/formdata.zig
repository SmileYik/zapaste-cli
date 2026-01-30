const std = @import("std");

const Allocator = std.mem.Allocator;
const Array = std.ArrayList(u8);

const Self = @This();

const prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
const NEW_LIEN = "\r\n";

pub const UploadFile = struct {
    filename: []const u8,
    mimetype: []const u8,
    data: []const u8,
};

// fields

allocator: Allocator,
array: Array,
writer: std.io.Writer,
boundary: []const u8,
finished: bool,
content_type: ?[]const u8 = null,

pub fn init(allocator: Allocator) !Self {
    var array = try Array.initCapacity(allocator, 4 * 1024);
    return .{
        .allocator = allocator,
        .array = array,
        .writer = array.writer(allocator),
        .boundary = try randomBoundary(allocator, 16),
        .finished = false,
    };
}

pub fn deinit(self: Self) void {
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

    try self.writer.print(
        \\--{s}
        \\Content-Disposition: form-data; name="{s}"
        \\
        \\
        \\{s}
        \\
    , self.boundary, key, value);
}

pub fn appendFile(
    self: *Self,
    key: []const u8,
    filepath: []const u8,
) !void {
    if (self.finished) return error.FinishedFormData;

    const filename = std.fs.path.basename(filepath);
    const data = try std.fs.cwd().readFileAlloc(self.allocator, filepath, @bitCast(-1));
    try self.appendFileData(key, .{
        .filename = filename,
        .data = data,
        .mimetype = "",
    });
}

pub fn appendFileData(
    self: *Self,
    key: []const u8,
    filedata: UploadFile,
) !void {
    if (self.finished) return error.FinishedFormData;

    try self.writer.print(
        \\--{s}
        \\
        \\Content-Disposition: form-data; name="{s}"; filename="{s}"
        \\
        \\Content-Type: {s}
        \\
        \\{s}
        \\
    ,
        self.boundary,
        key,
        filedata.filename,
        filedata.mimetype,
        filedata.data,
    );
}

pub fn getBody(self: *Self) ![]u8 {
    if (!self.finished) {
        self.finished = true;
        try self.writer.print("--{s}--\r\n", .{self.boundary});
    }
    return self.array.items;
}

pub fn getContentType(self: *Self) ![]const u8 {
    if (self.content_type == null) {
        self.content_type = try std.fmt.allocPrint(
            self.allocator,
            "multipart/form-data; boundary={s}",
            .{self.boundary},
        );
    }
    return self.content_type.?;
}

inline fn randomBoundary(allocator: std.mem.Allocator, length: usize) ![]u8 {
    const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const prefix = "----ZapasteBoundary";
    const random = prng.random();

    var result = try allocator.alloc(u8, prefix.len + length);
    for (0..length) |i| {
        const random_index = random.uintAtMost(usize, charset.len - 1);
        result[prefix.len + i] = charset[random_index];
    }

    return result;
}
