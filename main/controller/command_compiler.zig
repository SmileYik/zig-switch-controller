const std = @import("std");
const mod = @import("root.zig");
const Allocator = std.mem.Allocator;

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const Buttons = std.ArrayList(mod.Button);
const CommandTimeUnit = mod.command.CommandTimeUnit;
const CommandTag = mod.command.CommandTag;
const CombinedButton = mod.command.CombinedButton;
const Command = mod.command.Command;
const Commands = std.ArrayList(Command);
const CommandPack = mod.command.CommandPack;

const ENDIAN: std.builtin.Endian = .little;

pub fn compileCommand(
    allocator: Allocator,
    writer: *std.ArrayList(u8),
    command: *const Command,
) !void {
    var cmd_opt: ?Command = command.*;

    while (cmd_opt) |cmd| {
        switch (cmd) {
            .wait => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait));
                var buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &buf, ms, ENDIAN);
                try writer.appendSlice(allocator, &buf);
            },
            .wait_u16 => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait_u16));
                var buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &buf, ms, ENDIAN);
                try writer.appendSlice(allocator, &buf);
            },
            .wait_u8 => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait_u8));
                var buf: [1]u8 = undefined;
                std.mem.writeInt(u8, &buf, ms, ENDIAN);
                try writer.appendSlice(allocator, &buf);
            },

            .down => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.down));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },
            .down_combine => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.down_combine));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },

            .up => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.down));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },
            .up_combine => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.down_combine));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },

            .stick => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.stick));
                try writer.append(allocator, @intFromEnum(s.stick));
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u32, buf[0..4], @as(u32, @bitCast(s.x)), ENDIAN);
                std.mem.writeInt(u32, buf[4..8], @as(u32, @bitCast(s.y)), ENDIAN);
                try writer.appendSlice(allocator, &buf);
            },
            .reset_stick => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.reset_stick));
                try writer.append(allocator, @intFromEnum(s));
            },

            .repeat => |repeat| {
                try writer.append(allocator, @intFromEnum(CommandTag.repeat));
                var buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &buf, repeat.times, ENDIAN);
                try writer.appendSlice(allocator, &buf);
                cmd_opt = .{ .commands = repeat.commands };
                continue;
            },

            .end => try writer.append(allocator, @intFromEnum(CommandTag.end)),
            .reset_button => try writer.append(allocator, @intFromEnum(CommandTag.reset_button)),
            .reset_all => try writer.append(allocator, @intFromEnum(CommandTag.reset_all)),
            else => {},
        }
        break;
    }
}

pub fn compileCommands(
    allocator: Allocator,
    writer: *std.ArrayList(u8),
    commands: *const Commands,
) !void {
    for (commands.items) |*command| {
        try writer.append(allocator, @intFromEnum(CommandTag.commands));
        if (command.* == .commands) {
            try compileCommands(allocator, writer, &command.commands);
        } else {
            try compileCommand(allocator, writer, command);
        }
        try writer.append(allocator, @intFromEnum(CommandTag.end));
    }
}

pub fn compile(
    allocator: Allocator,
    command_pack: *const CommandPack,
) !std.ArrayList(u8) {
    var bytes = try std.ArrayList(u8).initCapacity(allocator, 512);
    errdefer bytes.deinit(allocator);

    try compileCommands(allocator, &bytes, &command_pack.commands);
    try bytes.shrinkToLen(allocator);
    return bytes;
}

test "compile wait" {
    const script = "wait 0.5s";
    const ret_opt = try mod.command.parser.parseCommand(testing.allocator, script);
    try testing.expect(ret_opt != null);

    var pack = ret_opt.?;
    defer pack.deinit();
    var bytes = try compile(testing.allocator, &pack);
    defer bytes.deinit(testing.allocator);

    try ExpectEqual(5, bytes.items.len);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x51, 0x2B, 0xF4, 0x01, 0x00 }, bytes.items);
}
