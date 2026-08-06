const std = @import("std");
const mod = @import("root.zig");
const Mutex = mod.Mutex;

const Protocol = mod.Protocol;
const ButtonLower = Protocol.ButtonLower;
const ButtonShared = Protocol.ButtonShared;
const ButtonUpper = Protocol.ButtonUpper;

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const log = std.log.scoped(.controller);

const Controller = @This();

pub const ButtonState = enum { down, up };
pub const ButtonTag = enum { lower, shared, upper };
pub const Button = union(ButtonTag) {
    lower: ButtonLower,
    shared: ButtonShared,
    upper: ButtonUpper,
};

pub const CommandTimeUnit = enum {
    /// millisecond
    ms,
    /// second
    s,
    m,
    h,
};
pub const CommandTag = enum {
    /// STICK stick_type x y
    stick,
    /// RESET_STICK stick_type
    reset_stick,
    /// RESET_BUTTON
    reset_button,
    /// RESET_ALL
    reset_all,
    /// WAIT time_num{unit}
    wait,
    /// UP button
    up,
    /// DOWN button
    down,
    /// REPEAT times {
    ///     COMMANDS
    /// }
    repeat,
    /// Other commands
    commands,
    end,
    /// TAP button time_num{unit}
    tap,
};
pub const Command = union(CommandTag) {
    stick: struct { stick: StickType, x: f32, y: f32 },
    reset_stick: StickType,
    reset_button,
    reset_all,
    /// unit: milliseconds
    wait: u32,
    up: Button,
    down: Button,
    repeat: struct { times: u32, commands: Commands },
    commands: Commands,
    end,
    tap: struct { button: Button, duration: u32 },
};
pub const Commands = std.ArrayList(Command);
pub const CommandPack = struct {
    allocator: std.mem.Allocator,
    commands: Commands,
    pub fn deinit(self: *CommandPack) void {
        deinitCommands(self.allocator, &self.commands);
    }
};

/// NS Switch Controller Pro x/y value in [0, 4095], u12
pub const StickCalibration = struct {
    center_x: i16 = 2048,
    center_y: i16 = 2048,
    min_x: i16 = -1600,
    max_x: i16 = 1600,
    min_y: i16 = -1600,
    max_y: i16 = 1600,
};

pub const StickType = enum {
    left_stick,
    right_stick,
};

pub const Options = struct {
    left_stick_calibration: StickCalibration = .{},
    right_stick_calibration: StickCalibration = .{},

    /// unit is HZ
    update_rate_hz: u32 = 50,
    report_queue: *mod.ReportQueue,
};

button_upper: u8 = 0,
button_shared: u8 = 0,
button_lower: u8 = 0,
left_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },
right_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },

left_stick_calibration: StickCalibration,
right_stick_calibration: StickCalibration,

mutex: Mutex,
delay_ms: u32,
report_queue: *mod.ReportQueue,
running: std.atomic.Value(bool) = .init(false),
task_mutex: Mutex,

pub fn init(opt: Options) !Controller {
    var mutex = try Mutex.init();
    errdefer mutex.deinit();
    var task_mutex = try Mutex.init();
    errdefer task_mutex.deinit();

    return .{
        .mutex = mutex,
        .task_mutex = task_mutex,
        .report_queue = opt.report_queue,
        .delay_ms = @trunc(@as(f32, @round(1000.0 / @as(f32, @floatFromInt(opt.update_rate_hz))))),
        .left_stick_calibration = opt.left_stick_calibration,
        .right_stick_calibration = opt.right_stick_calibration,
    };
}

pub fn deinit(self: *Controller) void {
    self.running.store(false, .release);
    self.task_mutex.lockUncancelable();
    self.task_mutex.unlock();
    self.task_mutex.deinit();

    self.mutex.deinit();
}

pub fn packet(self: *Controller) mod.report_queue.ReportType {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    return .{
        .input = .{
            .lower = self.button_lower,
            .shared = self.button_shared,
            .upper = self.button_upper,
            .left_stick_centre = self.left_stick_centre,
            .right_stick_centre = self.right_stick_centre,
        },
    };
}

pub fn setStickCalibration(self: *Controller, stick: StickType, calibration: StickCalibration) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (stick) {
        .left_stick => {
            self.left_stick_calibration = calibration;
        },
        .right_stick => {
            self.right_stick_calibration = calibration;
        },
    }
}

pub fn pressButton(self: *Controller, button: Button, state: ButtonState) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (button) {
        .lower => |mask| self.button_lower = setButtonBit(self.button_lower, @intFromEnum(mask), state),
        .shared => |mask| self.button_shared = setButtonBit(self.button_shared, @intFromEnum(mask), state),
        .upper => |mask| self.button_upper = setButtonBit(self.button_upper, @intFromEnum(mask), state),
    }
}

pub fn setStick(self: *Controller, stick: StickType, x: f32, y: f32) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (stick) {
        .left_stick => self.left_stick_centre = calibratedPosition(x, y, self.left_stick_calibration),
        .right_stick => self.right_stick_centre = calibratedPosition(x, y, self.right_stick_calibration),
    }
}

pub fn resetStick(self: *Controller, stick: StickType) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (stick) {
        .left_stick => @memset(&self.left_stick_centre, 0),
        .right_stick => @memset(&self.right_stick_centre, 0),
    }
}

pub fn resetButton(self: *Controller) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    self.button_lower = 0;
    self.button_shared = 0;
    self.button_upper = 0;
}

pub fn start(self: *Controller) !void {
    self.running.store(true, .release);
    _ = try mod.idf.rtos.Task.create(
        task,
        "controller_task",
        1024 * 4,
        self,
        5,
    );
}

export fn task(ctx: ?*anyopaque) callconv(.c) void {
    var self: *Controller = @ptrCast(@alignCast(ctx.?));
    self.task_mutex.lockUncancelable();
    defer self.task_mutex.unlock();
    defer mod.idf.rtos.Task.delete(null);

    while (self.running.load(.acquire)) {
        const report = self.packet();
        self.report_queue.enqueue(report) catch |err| {
            log.err("failed to send report: {s}", .{@errorName(err)});
        };
        mod.idf.rtos.Task.delayMs(self.delay_ms);
    }
}

pub inline fn runCommand(self: *Controller, command: *const Command) void {
    switch (command.*) {
        .down => |b| self.pressButton(b, .down),
        .up => |b| self.pressButton(b, .up),
        .reset_all => {
            self.resetButton();
            self.resetStick(.left_stick);
            self.resetStick(.right_stick);
        },
        .reset_button => self.resetButton(),
        .reset_stick => |stick| self.resetStick(stick),
        .stick => |stick| self.setStick(stick.stick, stick.x, stick.y),
        .wait => |ms| mod.idf.rtos.Task.delayMs(ms),
        .commands => |*cs| self.runCommands(cs),
        .repeat => |*repeat| {
            for (0..repeat.times) |_| {
                self.runCommands(&repeat.commands);
            }
        },
        else => {},
    }
}

pub fn runCommands(self: *Controller, commands: *const Commands) void {
    for (commands.items) |*item| {
        self.runCommand(item);
    }
}

pub fn runCommandPack(self: *Controller, command_pack: *const CommandPack) void {
    self.runCommands(&command_pack.commands);
}

/// set button bit. if state is press then set bit to `1`, else set bit to `0`.
inline fn setButtonBit(byte: u8, mask: u8, state: ButtonState) u8 {
    return switch (state) {
        .down => byte | mask,
        .up => byte & ~mask,
    };
}

test "setButtonBit" {
    try ExpectEqual(0x01, setButtonBit(0x00, 0x01, .down));
    try ExpectEqual(0xA2, setButtonBit(0xA3, 0x01, .up));
    try ExpectEqual(0xA3, setButtonBit(0xA3, 0x01, .down));
    try ExpectEqual(0xA3, setButtonBit(0xB3, 0x10, .up));
}

inline fn calibratedPositionInner(x: f32, y: f32, calibration: StickCalibration) [3]u8 {
    const fx = @as(f32, @floatFromInt(calibration.center_x)) + @abs(x) *
        if (x < 0)
            @as(f32, @floatFromInt(calibration.min_x))
        else
            @as(f32, @floatFromInt(calibration.max_x));

    const fy = @as(f32, @floatFromInt(calibration.center_y)) + @abs(y) *
        if (y < 0)
            @as(f32, @floatFromInt(calibration.min_y))
        else
            @as(f32, @floatFromInt(calibration.max_y));

    const ix = @as(i16, @intFromFloat(@round(fx)));
    const iy = @as(i16, @intFromFloat(@round(fy)));

    const ux: u16 = @intCast(@as(i16, std.math.clamp(ix, 0, std.math.maxInt(u12))));
    const uy: u16 = @intCast(@as(i16, std.math.clamp(iy, 0, std.math.maxInt(u12))));

    return .{
        @truncate(ux),
        @truncate((((uy & 0x0F) << 4) | (ux >> 8) & 0x0F)),
        @truncate(uy >> 4),
    };
}

pub inline fn calibratedPosition(x: f32, y: f32, calibration: StickCalibration) [3]u8 {
    return calibratedPositionInner(
        std.math.clamp(x, -1.0, 1.0),
        std.math.clamp(y, -1.0, 1.0),
        calibration,
    );
}

test "test calibratedPosition" {
    const result = calibratedPosition(-1.5, 0, .{
        .center_x = 2070,
        .center_y = 2013,
        .min_x = -1522,
        .max_x = 1414,
        .min_y = -1531,
        .max_y = 1510,
    });
    std.debug.print("{x}\n", .{result[0..]});
}

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
inline fn stringToButtonInner(button_name: []const u8) ?Button {
    return if (std.meta.stringToEnum(ButtonUpper, button_name)) |btn|
        .{ .upper = btn }
    else if (std.meta.stringToEnum(ButtonLower, button_name)) |btn|
        .{ .lower = btn }
    else if (std.meta.stringToEnum(ButtonShared, button_name)) |btn|
        .{ .shared = btn }
    else
        null;
}

pub inline fn stringToButton(button_name: []const u8) ?Button {
    if (isUpperString(button_name)) {
        return stringToButtonInner(button_name);
    } else {
        const max_len = comptime maxEnumsFieldLen(.{ ButtonLower, ButtonShared, ButtonUpper });
        if (button_name.len > max_len) return null;
        var buf: [max_len]u8 = undefined;
        const upper_name = std.ascii.upperString(&buf, button_name);
        return stringToButtonInner(upper_name);
    }
}

test "stringToButton" {
    try ExpectEqual(Button{ .lower = .DPAD_RIGHT }, stringToButton("dpad_right"));
    try ExpectEqual(Button{ .lower = .DPAD_RIGHT }, stringToButton("dpaD_right"));
    try ExpectEqual(Button{ .lower = .DPAD_RIGHT }, stringToButton("DPAD_RIGHT"));
    try ExpectEqual(Button{ .shared = .HOME }, stringToButton("home"));
    try ExpectEqual(Button{ .upper = .A }, stringToButton("A"));
    try ExpectEqual(Button{ .upper = .A }, stringToButton("a"));
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

pub inline fn stringToStick(stick_name: []const u8) ?StickType {
    return lowerStringToEnum(StickType, stick_name);
}

test "stringToStick" {
    try ExpectEqual(StickType.left_stick, stringToStick("left_stick"));
    try ExpectEqual(StickType.left_stick, stringToStick("lefT_stick"));
    try ExpectEqual(StickType.left_stick, stringToStick("LEFT_STICK"));
    try ExpectEqual(StickType.right_stick, stringToStick("right_stick"));
}

pub inline fn stringToButtonState(button_state_name: []const u8) ?ButtonState {
    return lowerStringToEnum(ButtonState, button_state_name);
}

test "stringToButtonState" {
    try ExpectEqual(ButtonState.up, stringToButtonState("Up"));
    try ExpectEqual(ButtonState.up, stringToButtonState("up"));
    try ExpectEqual(ButtonState.up, stringToButtonState("UP"));
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

inline fn deinitCommands(allocator: std.mem.Allocator, commands: *Commands) void {
    defer commands.deinit(allocator);
    for (commands.items) |*command|
        deinitCommand(allocator, command);
}

fn deinitCommand(allocator: std.mem.Allocator, command: *Command) void {
    switch (command.*) {
        .commands => |*commands| deinitCommands(allocator, commands),
        .repeat => |*repeat| deinitCommands(allocator, &repeat.commands),
        else => {},
    }
}

pub fn parseCommandLine(script_line: []const u8) !?Command {
    const trimmed = std.mem.trim(u8, script_line, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var iter = std.mem.tokenizeAny(u8, trimmed, " \t");
    const cmd_str = iter.next() orelse return null;

    const tag = lowerStringToEnum(CommandTag, cmd_str) orelse return error.UnknownCommand;
    return switch (tag) {
        .wait => {
            const time_str = iter.next() orelse return error.MissingArgument;
            const ms = try parseTimeString(time_str);
            return Command{ .wait = ms };
        },
        .down => {
            const btn_str = iter.next() orelse return error.MissingArgument;
            const btn = stringToButton(btn_str) orelse return error.UnknownButton;
            return Command{ .down = btn };
        },
        .up => {
            const btn_str = iter.next() orelse return error.MissingArgument;
            const btn = stringToButton(btn_str) orelse return error.UnknownButton;
            return Command{ .up = btn };
        },
        .tap => {
            const btn_str = iter.next() orelse return error.MissingArgument;
            const btn = stringToButton(btn_str) orelse return error.UnknownButton;
            const duration = if (iter.next()) |time_str|
                try parseTimeString(time_str)
            else
                50;
            return Command{ .tap = .{ .button = btn, .duration = duration } };
        },
        .stick => {
            const stick_str = iter.next() orelse return error.MissingArgument;
            const x_str = iter.next() orelse return error.MissingArgument;
            const y_str = iter.next() orelse return error.MissingArgument;

            const stick = stringToStick(stick_str) orelse return error.UnknownStick;
            const x = try std.fmt.parseFloat(f32, x_str);
            const y = try std.fmt.parseFloat(f32, y_str);

            return Command{ .stick = .{ .stick = stick, .x = x, .y = y } };
        },
        .reset_stick => {
            if (iter.next()) |stick_str| {
                const stick = stringToStick(stick_str) orelse return error.UnknownStick;
                return Command{ .reset_stick = stick };
            }
            // 若没填参数可返回默认值或单独处理
            return Command{ .reset_stick = .left_stick };
        },
        .repeat => {
            const times_str = iter.next() orelse return error.MissingArgument;
            const times = try std.fmt.parseInt(u32, times_str, 10);
            return Command{ .repeat = .{ .times = times, .commands = undefined } };
        },
        .end => .end,
        .reset_button => .reset_button,
        .reset_all => .reset_all,
        else => null,
    };
}

// pub fn flatCommand(allocator: std.mem.Allocator, command: Command) ?Command {
//     switch (command) {
//         .commands => |inner| {
//             return flatCommands(allocator, inner);
//         },
//         .repeat => |inner_command| {
//             if (flatCommand(allocator, inner_command.command)) |simplified| {
//                 return if (simplified == .repeat)
//                     .{ .repeat = .{ .times = inner_command.times * simplified.repeat.times, .command = simplified.repeat.command } }
//                 else
//                     .{ .repeat = .{ .times = inner_command.times, .command = simplified } };
//             }
//             return null;
//         },

//         else => return command,
//     }
// }

// test "flatCommand 1" {
//     const command: Command = .{ .repeat = .{ .times = 1, .command = .{ .down = .{ .lower = .DPAD_DOWN } } } };
//     try ExpectEqual(command, flatCommand(testing.allocator, command));
// }

// pub fn flatCommands(allocator: std.mem.Allocator, commands: Commands) ?Command {
//     if (commands.items.len == 0) return null;
//     if (commands.items.len == 1) {
//         defer commands.deinit(allocator);

//         const command = commands.items[0];
//         return flatCommand(allocator, command);
//     }
//     return .{ .commands = commands };
// }

// test "flat" {}

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

pub fn appendCommand(
    allocator: std.mem.Allocator,
    list: *Commands,
    command: Command,
) !void {
    switch (command) {
        .tap => |t| {
            try appendCommand(allocator, list, .{ .down = t.button });
            if (t.duration > 0) {
                try appendCommand(allocator, list, .{ .wait = t.duration });
            }
            try appendCommand(allocator, list, .{ .up = t.button });
        },
        .up => |btn| {
            _ = eraseTailSameCommand(list, command);
            if (!eraseTailSameCommand(list, .{ .down = btn })) {
                try list.append(allocator, command);
            }
        },
        .down => |btn| {
            var flag = true;
            while (flag) {
                const a = eraseTailSameCommand(list, command);
                const b = eraseTailSameCommand(list, .{ .up = btn });
                flag = a or b;
            }
            try list.append(allocator, command);
        },
        .reset_all, .reset_button, .reset_stick => {
            _ = eraseTailSameCommand(list, command);
            try list.append(allocator, command);
        },
        .stick => {
            while (list.getLastOrNull()) |last| {
                if (last == .stick and last.stick.stick == command.stick.stick) {
                    _ = list.pop();
                } else break;
            }
            try list.append(allocator, command);
        },
        .wait => |ms| {
            var need_append = true;
            if (list.getLastOrNull()) |last| {
                if (last == .wait) {
                    list.items[list.items.len - 1] = .{ .wait = ms + last.wait };
                    need_append = false;
                }
            }
            if (need_append) {
                try list.append(allocator, command);
            }
        },
        else => {
            try list.append(allocator, command);
        },
    }
}

pub fn parseCommandBlock(allocator: std.mem.Allocator, lines: anytype) !?Commands {
    var list = try Commands.initCapacity(allocator, 16);
    errdefer deinitCommands(allocator, &list);

    while (lines.next()) |line| {
        if (try parseCommandLine(line)) |command|
            switch (command) {
                .end => break,
                .repeat => |s| {
                    var opt = try parseCommandBlock(allocator, lines);
                    if (opt) |*inner_list| {
                        errdefer deinitCommands(allocator, inner_list);

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

    try list.shrinkToLen(allocator);
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
        try ExpectEqual(Command{ .down = .{ .upper = .B } }, pack.commands.items[2]);
        try ExpectEqual(Command{ .up = .{ .lower = .L } }, pack.commands.items[3]);
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
        try ExpectEqual(Command{ .wait = 1523 }, list.items[3]);
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
        try ExpectEqual(3, pack.commands.items.len);
        try ExpectEqual(Command{ .wait = 2900 }, pack.commands.items[0]);
        try ExpectEqual(CommandTag.reset_all, pack.commands.items[1]);
    }
}
