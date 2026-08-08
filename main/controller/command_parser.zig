const std = @import("std");
const mod = @import("root.zig");

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const Buttons = std.ArrayList(mod.Button);
const CommandTimeUnit = mod.command.CommandTimeUnit;
const CommandTag = mod.command.CommandTag;
const CombinedButton = mod.command.CombinedButton;
const Command = mod.command.Command;
const Commands = std.ArrayList(Command);
const CommandPack = mod.command.CommandPack;

pub inline fn isUpperString(str: []const u8) bool {
    for (str) |c| {
        if (std.ascii.isLower(c)) return false;
    }
    return true;
}

pub inline fn isLowerString(str: []const u8) bool {
    for (str) |c| {
        if (std.ascii.isUpper(c)) return false;
    }
    return true;
}

pub inline fn maxEnumsFieldLen(comptime types: anytype) comptime_int {
    var max: comptime_int = 0;
    inline for (types) |t| {
        max = @max(max, comptime maxEnumFieldLen(t));
    }
    return max;
}

pub inline fn maxEnumFieldLen(comptime T: type) comptime_int {
    const info = @typeInfo(T);
    if (info != .@"enum") return 0;

    var max: comptime_int = 0;
    inline for (info.@"enum".fields) |field| {
        max = @max(max, field.name.len);
    }
    return max;
}

/// `button_name` should be upper.
inline fn stringToButtonInner(button_name: []const u8) ?mod.Button {
    return if (std.meta.stringToEnum(mod.ButtonUpper, button_name)) |btn|
        .{ .upper = btn }
    else if (std.meta.stringToEnum(mod.ButtonLower, button_name)) |btn|
        .{ .lower = btn }
    else if (std.meta.stringToEnum(mod.ButtonShared, button_name)) |btn|
        .{ .shared = btn }
    else
        null;
}

pub inline fn stringToButton(button_name: []const u8) ?mod.Button {
    if (isUpperString(button_name)) {
        return stringToButtonInner(button_name);
    } else {
        const max_len = comptime maxEnumsFieldLen(.{ mod.ButtonLower, mod.ButtonShared, mod.ButtonUpper });
        if (button_name.len > max_len) return null;
        var buf: [max_len]u8 = undefined;
        const upper_name = std.ascii.upperString(&buf, button_name);
        return stringToButtonInner(upper_name);
    }
}

test "stringToButton" {
    try ExpectEqual(mod.Button{ .lower = .DPAD_RIGHT }, stringToButton("dpad_right"));
    try ExpectEqual(mod.Button{ .lower = .DPAD_RIGHT }, stringToButton("dpaD_right"));
    try ExpectEqual(mod.Button{ .lower = .DPAD_RIGHT }, stringToButton("DPAD_RIGHT"));
    try ExpectEqual(mod.Button{ .shared = .HOME }, stringToButton("home"));
    try ExpectEqual(mod.Button{ .upper = .A }, stringToButton("A"));
    try ExpectEqual(mod.Button{ .upper = .A }, stringToButton("a"));
}

pub inline fn lowerStringToEnum(comptime E: anytype, name: []const u8) ?E {
    if (isLowerString(name)) {
        return std.meta.stringToEnum(E, name);
    } else {
        const max_len = comptime maxEnumFieldLen(E);
        if (name.len > max_len) return null;
        var buf: [max_len]u8 = undefined;
        const lower_name = std.ascii.lowerString(&buf, name);
        return std.meta.stringToEnum(E, lower_name);
    }
}

pub inline fn stringToStick(stick_name: []const u8) ?mod.StickType {
    return lowerStringToEnum(mod.StickType, stick_name);
}

test "stringToStick" {
    try ExpectEqual(mod.StickType.left_stick, stringToStick("left_stick"));
    try ExpectEqual(mod.StickType.left_stick, stringToStick("lefT_stick"));
    try ExpectEqual(mod.StickType.left_stick, stringToStick("LEFT_STICK"));
    try ExpectEqual(mod.StickType.right_stick, stringToStick("right_stick"));
}

pub inline fn stringToButtonState(button_state_name: []const u8) ?mod.ButtonState {
    return lowerStringToEnum(mod.ButtonState, button_state_name);
}

test "stringToButtonState" {
    try ExpectEqual(mod.ButtonState.up, stringToButtonState("Up"));
    try ExpectEqual(mod.ButtonState.up, stringToButtonState("up"));
    try ExpectEqual(mod.ButtonState.up, stringToButtonState("UP"));
}

inline fn parseTimeString(str: []const u8) !u32 {
    if (str.len == 0) return error.WrongTimeNumber;

    const unit_start = blk: {
        for (str, 0..) |c, i| {
            if (!std.ascii.isDigit(c) and c != '.') break :blk i;
        }
        break :blk str.len;
    };

    // if just a unit that defaut 0
    const num: f32 =
        if (unit_start == 0)
            0
        else
            std.fmt.parseFloat(f32, str[0..unit_start]) catch
                return error.WrongTimeNumber;

    // if no unit string than defaut is `ms`
    const unit =
        if (unit_start == str.len)
            CommandTimeUnit.ms
        else if (lowerStringToEnum(CommandTimeUnit, str[unit_start..])) |unit|
            unit
        else
            return error.WrongTimeUnit;

    return switch (unit) {
        .h => @trunc(@as(f32, @round(num * @as(f32, @floatFromInt(60 * 60 * 1000))))),
        .m => @trunc(@as(f32, @round(num * @as(f32, @floatFromInt(60 * 1000))))),
        .s => @trunc(@as(f32, @round(num * @as(f32, @floatFromInt(1000))))),
        .ms => @trunc(@as(f32, @round(num))),
    };
}

test "parseTimeString" {
    try testing.expectError(error.WrongTimeNumber, parseTimeString(""));

    try ExpectEqual(1, parseTimeString("1ms"));
    try ExpectEqual(1500, parseTimeString("1.5s"));
    try ExpectEqual(1, parseTimeString("1"));
    try ExpectEqual(1000, parseTimeString("1s"));
    try ExpectEqual(1187, parseTimeString("1.18725s"));

    try testing.expectError(error.WrongTimeUnit, parseTimeString("0.S1s"));
}

pub fn parseCommandButtons(allocator: std.mem.Allocator, iter: anytype) !Buttons {
    var buttons: Buttons = try Buttons.initCapacity(allocator, 4);
    errdefer buttons.deinit(allocator);
    while (iter.next()) |str| {
        const btn = stringToButton(str) orelse return error.UnknownButton;
        try buttons.append(allocator, btn);
    }
    if (buttons.items.len == 0) return error.MissingArgument;
    return buttons;
}

inline fn appendWaitCommand(
    allocator: std.mem.Allocator,
    commands: *Commands,
    ms: u32,
) !void {
    if (ms == 0) return;

    if (ms <= std.math.maxInt(u8)) {
        try commands.append(allocator, Command{ .wait_u8 = @intCast(ms) });
    } else if (ms <= std.math.maxInt(u16)) {
        try commands.append(allocator, Command{ .wait_u16 = @intCast(ms) });
    } else {
        try commands.append(allocator, Command{ .wait = ms });
    }
}

pub fn parseCommandLine(allocator: std.mem.Allocator, script_line: []const u8) !?Commands {
    const trimmed = std.mem.trim(u8, script_line, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var iter = std.mem.tokenizeAny(u8, trimmed, " \t");
    const cmd_str = iter.next() orelse return null;

    var commands = try Commands.initCapacity(allocator, 4);
    errdefer commands.deinit(allocator);

    const tag = lowerStringToEnum(CommandTag, cmd_str) orelse return error.UnknownCommand;
    switch (tag) {
        .wait, .wait_u8, .wait_u16 => {
            const time_str = iter.next() orelse return error.MissingArgument;
            const ms = try parseTimeString(time_str);
            try appendWaitCommand(allocator, &commands, ms);
        },
        .down, .down_combine => {
            var buttons = try parseCommandButtons(allocator, &iter);
            defer buttons.deinit(allocator);

            const active_combine = tag == CommandTag.down_combine;
            var items = try commands.addManyAsSlice(allocator, buttons.items.len);
            for (buttons.items, 0..) |btn, i| {
                const combined = active_combine and i + 1 < buttons.items.len;
                items[i] = .{
                    .down = .{ .button = btn, .combine = combined },
                };
            }
        },
        .up, .up_combine => {
            var buttons = try parseCommandButtons(allocator, &iter);
            defer buttons.deinit(allocator);

            const active_combine = tag == CommandTag.up_combine;
            var items = try commands.addManyAsSlice(allocator, buttons.items.len);
            for (buttons.items, 0..) |btn, i| {
                const combined = active_combine and i + 1 < buttons.items.len;
                items[i] = .{
                    .up = .{ .button = btn, .combine = combined },
                };
            }
        },
        .tap, .tap_combine => {
            const duration = if (iter.next()) |time_str|
                try parseTimeString(time_str)
            else
                return error.MissingArgument;

            var buttons = try parseCommandButtons(allocator, &iter);
            defer buttons.deinit(allocator);

            var items = try commands.addManyAsSlice(allocator, buttons.items.len * 2 + 1);
            var downs = items[0..buttons.items.len];
            items[buttons.items.len] = .{ .wait = duration };
            var ups = items[buttons.items.len + 1 ..];

            const active_combine = tag == CommandTag.tap_combine;
            for (buttons.items, 0..) |btn, i| {
                const combined = active_combine and i + 1 < buttons.items.len;
                downs[i] = .{
                    .down = .{ .button = btn, .combine = combined },
                };
                ups[i] = .{
                    .up = .{ .button = btn, .combine = combined },
                };
            }
        },
        .stick => {
            const stick_str = iter.next() orelse return error.MissingArgument;
            const x_str = iter.next() orelse return error.MissingArgument;
            const y_str = iter.next() orelse return error.MissingArgument;

            const stick = stringToStick(stick_str) orelse return error.UnknownStick;
            const x = try std.fmt.parseFloat(f32, x_str);
            const y = try std.fmt.parseFloat(f32, y_str);

            try commands.append(allocator, Command{ .stick = .{ .stick = stick, .x = x, .y = y } });
        },
        .reset_stick => {
            const stick_str = iter.next() orelse return error.MissingArgument;
            const stick = stringToStick(stick_str) orelse return error.UnknownStick;
            try commands.append(allocator, Command{ .reset_stick = stick });
        },
        .repeat => {
            const times_str = iter.next() orelse return error.MissingArgument;
            const times = try std.fmt.parseInt(u32, times_str, 10);
            try commands.append(allocator, Command{ .repeat = .{ .times = times, .commands = undefined } });
        },
        .end => {
            try commands.append(allocator, .end);
        },
        .reset_button => try commands.append(allocator, .reset_button),
        .reset_all => try commands.append(allocator, .reset_all),
        else => return null,
    }
    return commands;
}

inline fn eraseTailSameCommand(
    commands: *Commands,
    command: Command,
) bool {
    const len = commands.items.len;
    while (commands.getLastOrNull()) |last| {
        if (std.meta.eql(command, last)) {
            _ = commands.pop();
        } else break;
    }
    return len != commands.items.len;
}

inline fn safeAppendCombineTime(
    allocator: std.mem.Allocator,
    commands: *Commands,
    total_ms: u32,
    ms: u32,
) !u32 {
    return std.math.add(u32, total_ms, ms) catch {
        try commands.append(allocator, .{ .wait = std.math.maxInt(u32) });
        return total_ms +% ms;
    };
}

inline fn combineTailWaitTime(
    allocator: std.mem.Allocator,
    commands: *Commands,
    current_ms: u32,
) !void {
    var total_ms: u32 = current_ms;

    var new_list = try Commands.initCapacity(allocator, 2);
    defer new_list.deinit(allocator);

    while (commands.getLastOrNull()) |last| {
        switch (last) {
            .wait => |ms| {
                total_ms = try safeAppendCombineTime(allocator, &new_list, total_ms, ms);
                _ = commands.pop();
            },
            .wait_u16 => |ms_u| {
                const ms = @as(u32, @intCast(ms_u));
                total_ms = try safeAppendCombineTime(allocator, &new_list, total_ms, ms);
                _ = commands.pop();
            },
            .wait_u8 => |ms_u| {
                const ms = @as(u32, @intCast(ms_u));
                total_ms = try safeAppendCombineTime(allocator, &new_list, total_ms, ms);
                _ = commands.pop();
            },
            else => break,
        }
    }
    for (new_list.items) |c| {
        try commands.append(allocator, c);
    }
    try appendWaitCommand(allocator, commands, total_ms);
}

pub fn appendCommand(
    allocator: std.mem.Allocator,
    list: *Commands,
    command: Command,
) !void {
    switch (command) {
        .reset_all, .reset_button, .reset_stick => {
            _ = eraseTailSameCommand(list, command);
            try list.append(allocator, command);
        },
        .wait => |ms| {
            try combineTailWaitTime(allocator, list, ms);
        },
        .wait_u16 => |ms| {
            try combineTailWaitTime(allocator, list, @as(u32, @intCast(ms)));
        },
        .wait_u8 => |ms| {
            try combineTailWaitTime(allocator, list, @as(u32, @intCast(ms)));
        },
        else => {
            try list.append(allocator, command);
        },
    }
}

pub fn parseCommandBlock(allocator: std.mem.Allocator, lines: anytype) !?Commands {
    var list = try Commands.initCapacity(allocator, 16);
    errdefer mod.command.deinitCommands(allocator, &list);

    stop_lines: while (lines.next()) |line| {
        var commands_opt = try parseCommandLine(allocator, line);
        if (commands_opt) |*commands| {
            defer commands.deinit(allocator);

            for (commands.items) |command|
                switch (command) {
                    .end => break :stop_lines,
                    .repeat => |s| {
                        var opt = try parseCommandBlock(allocator, lines);
                        if (opt) |*inner_list| {
                            errdefer mod.command.deinitCommands(allocator, inner_list);

                            try list.append(allocator, .{
                                .repeat = .{
                                    .commands = inner_list.*,
                                    .times = s.times,
                                },
                            });
                        }
                    },
                    else => {
                        try appendCommand(allocator, &list, command);
                    },
                };
        }
    }

    return list;
}

pub fn parseCommand(allocator: std.mem.Allocator, script: []const u8) !?CommandPack {
    const trimmed = std.mem.trim(u8, script, " \t\r\n");
    var lines = std.mem.splitAny(u8, trimmed, "\n");

    var opt = try parseCommandBlock(allocator, &lines);
    if (opt) |*list| {
        if (list.items.len == 0) {
            defer list.deinit(allocator);
            return null;
        }
        return .{
            .allocator = allocator,
            .commands = list.*,
        };
    }
    return null;
}

test "parseCommand all commend" {
    const script =
        \\# command line 1
        \\
        \\# command line 2
    ;

    try ExpectEqual(null, try parseCommand(testing.allocator, script));
}

test "parseCommand one command" {
    const script =
        \\# command line 1
        \\   WAIT 200ms
        \\# command line 2
    ;

    var opt = try parseCommand(testing.allocator, script);
    try testing.expect(opt != null);
    if (opt) |*pack| {
        defer pack.deinit();
        try ExpectEqual(1, pack.commands.items.len);
        try ExpectEqual(Command{ .wait = 200 }, pack.commands.items[0]);
    }
}

test "parseCommand commands" {
    const script =
        \\# command line 1
        \\RESET_ALL
        \\   wait 200ms
        \\      DoWN B
        \\Up L
        \\   STiCk leFt_stIck 0.5 0.25
        \\
        \\# command line 2
    ;

    var opt = try parseCommand(testing.allocator, script);
    try testing.expect(opt != null);
    if (opt) |*pack| {
        defer pack.deinit();
        try ExpectEqual(5, pack.commands.items.len);
        try ExpectEqual(CommandTag.reset_all, pack.commands.items[0]);
        try ExpectEqual(Command{ .wait = 200 }, pack.commands.items[1]);
        try ExpectEqual(Command{ .down = .{ .button = .{ .upper = .B } } }, pack.commands.items[2]);
        try ExpectEqual(Command{ .up = .{ .button = .{ .lower = .L } } }, pack.commands.items[3]);
        try ExpectEqual(Command{ .stick = .{ .stick = .left_stick, .x = 0.5, .y = 0.25 } }, pack.commands.items[4]);
    }
}

test "parseCommand repeat commands" {
    const script =
        \\
        \\REPEAT 5
        \\    STICK left_stick 1.0 0.0
        \\    WAIT 1s
        \\        # command line 1
        \\STICK right_stick -1.0 -0.15
        \\WAIT 1.5235s
        \\END
        \\# command line 2
    ;

    var opt = try parseCommand(testing.allocator, script);
    try testing.expect(opt != null);
    if (opt) |*pack| {
        defer pack.deinit();
        try ExpectEqual(1, pack.commands.items.len);

        const command = pack.commands.items[0];
        try testing.expect(command == .repeat);
        const list = command.repeat.commands;
        try ExpectEqual(4, list.items.len);
        try ExpectEqual(Command{ .stick = .{ .stick = .left_stick, .x = 1.0, .y = 0 } }, list.items[0]);
        try ExpectEqual(Command{ .wait = 1000 }, list.items[1]);
        try ExpectEqual(Command{ .stick = .{ .stick = .right_stick, .x = -1.0, .y = -0.15 } }, list.items[2]);
        try ExpectEqual(Command{ .wait = 1524 }, list.items[3]);
    }
}

test "parseCommand merge commands" {
    const script =
        \\# command line 1
        \\   WAIT 200ms
        \\# command line 2
        \\WAIT 1.05s
        \\WAIT 1.65s
        \\RESET_ALL
        \\RESET_ALL
        \\DOWN B
        \\DOWN B
        \\DOWN B
        \\UP B
        \\UP B
    ;

    var opt = try parseCommand(testing.allocator, script);
    try testing.expect(opt != null);
    if (opt) |*pack| {
        defer pack.deinit();
        try ExpectEqual(7, pack.commands.items.len);
        try ExpectEqual(Command{ .wait = 2900 }, pack.commands.items[0]);
        try ExpectEqual(CommandTag.reset_all, pack.commands.items[1]);
    }
}

pub const CheckError = struct {
    index: ?usize = null,
    err: anyerror,
};

pub fn checkCommand(
    allocator: std.mem.Allocator,
    script: []const u8,
) ?CheckError {
    const trimmed = std.mem.trim(u8, script, " \t\r\n");
    var lines = std.mem.splitAny(u8, trimmed, "\n");

    var opt = parseCommandBlock(allocator, &lines) catch |err| {
        return .{ .index = lines.index, .err = err };
    };
    if (opt) |*list| {
        mod.command.deinitCommands(allocator, list);
    }
    return null;
}
