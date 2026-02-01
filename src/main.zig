const std = @import("std");
const zapaste_cli = @import("zapaste_cli");

const FALLBACK_API = "https://paste-demo.smileyik.eu.org";

pub fn simpleResultMessage(result: *const zapaste_cli.api.ApiResult(zapaste_cli.api.PasteModel)) void {
    if (result.message) |message| {
        if (result.code == 200) {
            std.log.info("{s}", .{message});
        } else {
            std.log.err("{s}", .{message});
        }
    }
}

pub fn displayHelp(args: zapaste_cli.Args) void {
    std.log.info("Type \"{s} --help\" for help!", .{args.args.items[0]});
}

pub fn main() !void {
    const gpa_type = std.heap.DebugAllocator(.{});
    var gpa = gpa_type.init;
    defer if (gpa.deinit() == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    };
    const allocator = gpa.allocator();

    var client = zapaste_cli.api.PasteClient.init(.{
        .allocator = allocator,
        .base_url = undefined,
    });
    defer client.deinit();

    var args = try zapaste_cli.Args.init(allocator);
    defer args.deinit();
    try args.parseArgs();
    if (args.unknown_args.items.len > 0) {
        for (args.unknown_args.items) |item| {
            std.log.info("Unknown Arg: '{s}'", .{item});
        }
        displayHelp(args);
        return error.UnknownArgs;
    }

    if (args.mode) |mode| switch (mode) {
        .help => |opt| {
            std.log.info("{s}", .{opt.help_message.?.items});
        },
        .config => |opt| {
            const config = try zapaste_cli.action.setConfig(allocator, opt);
            if (config.data.base_url) |url| {
                std.log.info("API URL is '{s}'.", .{url});
            } else {
                std.log.warn("Not set API URL yet!", .{});
            }
            if (config.data.token) |_| {
                std.log.info("Already set API token.", .{});
            } else {
                std.log.info("No API token was found.", .{});
            }
            defer config.deinit();
        },
        .upload => |opt| {
            const config = try zapaste_cli.Config.init(allocator);
            defer config.deinit();
            client.base_url = args.base_url orelse config.data.base_url orelse FALLBACK_API;
            client.authorization = args.token orelse config.data.token;
            const parsed = try zapaste_cli.action.handleOptionsUpload(&client, opt);
            defer parsed.deinit();
            simpleResultMessage(&parsed.value);
        },
        .create => |opt| {
            const config = try zapaste_cli.Config.init(allocator);
            defer config.deinit();
            client.base_url = args.base_url orelse config.data.base_url orelse FALLBACK_API;
            client.authorization = args.token orelse config.data.token;
            const parsed = try zapaste_cli.action.handleOptionsCreate(&client, opt);
            defer parsed.deinit();
            simpleResultMessage(&parsed.value);
        },
        .update => |opt| {
            const config = try zapaste_cli.Config.init(allocator);
            defer config.deinit();
            client.base_url = args.base_url orelse config.data.base_url orelse FALLBACK_API;
            client.authorization = args.token orelse config.data.token;
            const parsed = try zapaste_cli.action.handleOptionsUpdate(&client, opt);
            defer parsed.deinit();
            simpleResultMessage(&parsed.value);
        },
        .reset => |opt| {
            const config = try zapaste_cli.Config.init(allocator);
            defer config.deinit();
            client.base_url = args.base_url orelse config.data.base_url orelse FALLBACK_API;
            client.authorization = args.token orelse config.data.token;
            const parsed = try zapaste_cli.action.handleOptionsReset(&client, opt);
            defer parsed.deinit();
            simpleResultMessage(&parsed.value);
        },
    } else {
        displayHelp(args);
    }
}
