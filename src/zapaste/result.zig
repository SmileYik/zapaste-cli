pub fn create(comptime T: type) type {
    return struct {
        pub const Self = @This();

        code: u16,
        data: ?T = null,
        message: ?[]const u8 = null,
    };
}
