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

pub fn compileCommand(
    allocator: Allocator,
    writer: *std.ArrayList(u8),
    command: *const Command,
    endian: std.builtin.Endian,
) anyerror!void {
    var cmd_opt: ?Command = command.*;

    while (cmd_opt) |cmd| {
        switch (cmd) {
            .wait => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait));
                var buf: [4]u8 = undefined;
                std.mem.writeInt(u32, &buf, ms, endian);
                try writer.appendSlice(allocator, &buf);
            },
            .wait_u16 => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait_u16));
                var buf: [2]u8 = undefined;
                std.mem.writeInt(u16, &buf, ms, endian);
                try writer.appendSlice(allocator, &buf);
            },
            .wait_u8 => |ms| {
                try writer.append(allocator, @intFromEnum(CommandTag.wait_u8));
                var buf: [1]u8 = undefined;
                std.mem.writeInt(u8, &buf, ms, endian);
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
                try writer.append(allocator, @intFromEnum(CommandTag.up));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },
            .up_combine => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.up_combine));
                try writer.append(allocator, mod.buttonToByte(s.button));
            },

            .stick => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.stick));
                try writer.append(allocator, @intFromEnum(s.stick));
                var buf: [8]u8 = undefined;
                std.mem.writeInt(u32, buf[0..4], @as(u32, @bitCast(s.x)), endian);
                std.mem.writeInt(u32, buf[4..8], @as(u32, @bitCast(s.y)), endian);
                try writer.appendSlice(allocator, &buf);
            },
            .reset_stick => |s| {
                try writer.append(allocator, @intFromEnum(CommandTag.reset_stick));
                try writer.append(allocator, @intFromEnum(s));
            },

            .commands => |*list| {
                try compileCommands(allocator, writer, list, endian);
            },

            .repeat => |repeat| {
                if (repeat.times <= std.math.maxInt(u8)) {
                    try writer.append(allocator, @intFromEnum(CommandTag.repeat_u8));
                    try writer.append(allocator, @as(u8, @intCast(repeat.times)));
                } else if (repeat.times <= std.math.maxInt(u16)) {
                    try writer.append(allocator, @intFromEnum(CommandTag.repeat_u16));
                    var buf: [2]u8 = undefined;
                    std.mem.writeInt(u16, &buf, @as(u16, @intCast(repeat.times)), endian);
                    try writer.appendSlice(allocator, &buf);
                } else {
                    try writer.append(allocator, @intFromEnum(CommandTag.repeat));
                    var buf: [4]u8 = undefined;
                    std.mem.writeInt(u32, &buf, repeat.times, endian);
                    try writer.appendSlice(allocator, &buf);
                }

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
    endian: std.builtin.Endian,
) !void {
    try writer.append(allocator, @intFromEnum(CommandTag.commands));
    for (commands.items) |*command| {
        try compileCommand(allocator, writer, command, endian);
    }
    try writer.append(allocator, @intFromEnum(CommandTag.end));
}

pub fn compile(
    allocator: Allocator,
    command_pack: *const CommandPack,
    endian: std.builtin.Endian,
) !std.ArrayList(u8) {
    var bytes = try std.ArrayList(u8).initCapacity(allocator, 512);
    errdefer bytes.deinit(allocator);

    try bytes.append(allocator, mod.endian2byte(endian));
    try compileCommands(allocator, &bytes, &command_pack.commands, endian);
    try bytes.shrinkToLen(allocator);
    return bytes;
}

test "compile wait" {
    const script = "wait 0.5s";
    const ret_opt = try mod.command.parser.parseCommand(testing.allocator, script);
    try testing.expect(ret_opt != null);

    var pack = ret_opt.?;
    defer pack.deinit();
    var bytes = try compile(testing.allocator, &pack, .little);
    defer bytes.deinit(testing.allocator);

    try ExpectEqual(6, bytes.items.len);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x51, 0x2B, 0xF4, 0x01, 0x00 }, bytes.items);
}

test "compile wait_u16 and wait_u8" {
    // 测试 wait_u16
    {
        const command = Command{ .wait_u16 = 500 };
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &command, .little);

        try ExpectEqual(3, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.wait_u16), list.items[0]);
        try testing.expectEqualSlices(u8, &[_]u8{ 0xF4, 0x01 }, list.items[1..3]);
    }

    // 测试 wait_u8
    {
        const command = Command{ .wait_u8 = 100 };
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &command, .little);

        try ExpectEqual(2, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.wait_u8), list.items[0]);
        try testing.expectEqual(100, list.items[1]);
    }
}

test "compile button down and up" {
    // 测试 down 指令
    {
        const command = Command{ .down = .{ .button = .{ .upper = .A } } };
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &command, .little);

        try ExpectEqual(2, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.down), list.items[0]);
        try testing.expectEqual(mod.buttonToByte(.{ .upper = .A }), list.items[1]);
    }

    // 测试 up 指令
    {
        const command = Command{ .up = .{ .button = .{ .upper = .A } } };
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &command, .little);

        try ExpectEqual(2, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.up), list.items[0]);
        try testing.expectEqual(mod.buttonToByte(.{ .upper = .A }), list.items[1]);
    }
}

test "compile stick move and reset" {
    // 测试 stick 指令 (摇杆 x=1.0, y=-1.0)
    {
        const stick_cmd = Command{
            .stick = .{
                .stick = .left_stick,
                .x = 1.0,
                .y = -1.0,
            },
        };

        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &stick_cmd, .little);

        // 字节数: 1 (Tag) + 1 (StickEnum) + 4 (X float as u32) + 4 (Y float as u32) = 10
        try ExpectEqual(10, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.stick), list.items[0]);
        try testing.expectEqual(@intFromEnum(mod.StickType.left_stick), list.items[1]);

        // 验证 f32 的 bitCast 序列化 (小端序)
        const expected_x = @as(u32, @bitCast(@as(f32, 1.0)));
        const expected_y = @as(u32, @bitCast(@as(f32, -1.0)));

        var expected_buf: [8]u8 = undefined;
        std.mem.writeInt(u32, expected_buf[0..4], expected_x, .little);
        std.mem.writeInt(u32, expected_buf[4..8], expected_y, .little);

        try testing.expectEqualSlices(u8, &expected_buf, list.items[2..10]);
    }

    // 测试 reset_stick 指令
    {
        const command = Command{ .reset_stick = .left_stick };
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &command, .little);

        try ExpectEqual(2, list.items.len);
        try testing.expectEqual(@intFromEnum(CommandTag.reset_stick), list.items[0]);
        try testing.expectEqual(@intFromEnum(mod.StickType.left_stick), list.items[1]);
    }
}

test "compile reset control commands" {
    const cases = [_]struct {
        cmd: Command,
        tag: CommandTag,
    }{
        .{ .cmd = .reset_button, .tag = CommandTag.reset_button },
        .{ .cmd = .reset_all, .tag = CommandTag.reset_all },
        .{ .cmd = .end, .tag = CommandTag.end },
    };

    for (cases) |c| {
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
        defer list.deinit(testing.allocator);

        try compileCommand(testing.allocator, &list, &c.cmd, .little);

        try ExpectEqual(1, list.items.len);
        try testing.expectEqual(@intFromEnum(c.tag), list.items[0]);
    }
}

test "compile repeat nested commands" {
    // 构建 repeat 指令：重复 3 次 { wait_u8 50 }
    var inner_cmds = try Commands.initCapacity(testing.allocator, 10);
    defer inner_cmds.deinit(testing.allocator);

    try inner_cmds.append(testing.allocator, Command{ .wait_u8 = 50 });

    const repeat_cmd = Command{
        .repeat = .{
            .times = 3,
            .commands = inner_cmds,
        },
    };

    var list = try std.ArrayList(u8).initCapacity(testing.allocator, 16);
    defer list.deinit(testing.allocator);

    try compileCommand(testing.allocator, &list, &repeat_cmd, .little);

    // 预期结构:
    // 1. Tag.repeat (1 byte)
    // 2. times = 3 (4 bytes, u32)
    // 3. Tag.commands (1 byte)
    // 4. Tag.wait_u8 + 50 (2 bytes)
    // 5. Tag.end (1 byte)
    // 总计: 1 + 4 + 1 + 2 + 1 = 9 字节
    try ExpectEqual(9, list.items.len);
    try testing.expectEqual(@intFromEnum(CommandTag.repeat), list.items[0]);

    // 验证重复次数 (3)
    const times_bytes = list.items[1..5];
    try testing.expectEqualSlices(u8, &[_]u8{ 0x03, 0x00, 0x00, 0x00 }, times_bytes);

    // 验证内部嵌套命令编码
    try testing.expectEqual(@intFromEnum(CommandTag.commands), list.items[5]);
    try testing.expectEqual(@intFromEnum(CommandTag.wait_u8), list.items[6]);
    try testing.expectEqual(50, list.items[7]);
    try testing.expectEqual(@intFromEnum(CommandTag.end), list.items[8]);
}
