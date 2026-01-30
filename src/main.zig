const std = @import("std");
const zapaste_cli = @import("zapaste_cli");

pub fn main() !void {
    var client = zapaste_cli.api.PasteClient.init(
        std.heap.page_allocator,
        "https://paste-demo.smileyik.eu.org",
    );
    const result = try client.getPasteList(1, 4);
    std.debug.print("{any}\n", .{result});
    const paste = try client.getPaste("vagueid-hammerhead", null);
    defer paste.deinit();
    std.debug.print("{any}\n", .{paste.value});

    const created_paste = try client.createPaste(.{ .name = "test" }, null);
    defer created_paste.deinit();
    // std.debug.print("{any}\n", .{created_paste.value.data});

    const created_paste2 = try client.createPaste(
        .{ .name = "test-3" },
        &.{"zig-out/bin/zapaste-cli"},
    );
    defer created_paste2.deinit();
    // std.debug.print("{any}\n", .{created_paste2.value.data});
}
