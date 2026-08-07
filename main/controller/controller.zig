const std = @import("std");
const mod = @import("root.zig");
const Mutex = @import("mutex");

const ButtonLower = mod.Constants.ButtonLower;
const ButtonShared = mod.Constants.ButtonShared;
const ButtonUpper = mod.Constants.ButtonUpper;

const ReportType = @import("report").ReportType;

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const log = std.log.scoped(.controller);

const Controller = @This();

/// NS Switch Controller Pro x/y value in [0, 4095], u12
pub const StickCalibration = struct {
    center_x: i16 = 2048,
    center_y: i16 = 2048,
    min_x: i16 = -1600,
    max_x: i16 = 1600,
    min_y: i16 = -1600,
    max_y: i16 = 1600,
};

const Handler = struct {
    ctx: *anyopaque,
    sendFn: *const fn (ctx: *anyopaque, report: ReportType) anyerror!void = undefined,
    sleepFn: *const fn (ctx: *anyopaque, ms: u32) void = undefined,

    pub inline fn init(handler: anytype) Handler {
        const Pointer = @TypeOf(handler);
        comptime {
            const info = @typeInfo(Pointer);
            if (info != .pointer or info.pointer.size != .one) {
                @panic("handler need be a struct pointer");
            }
            if (!std.meta.hasMethod(Pointer, "send")) {
                @panic("handler need has a function named send.");
            }
            if (!std.meta.hasMethod(Pointer, "sleep")) {
                @panic("handler need has a function named sleep.");
            }
        }

        var interface: Handler = .{ .ctx = handler };

        if (std.meta.hasMethod(Pointer, "send")) {
            interface.sendFn = (struct {
                fn send(ctx: *anyopaque, report: ReportType) !void {
                    var ptr: Pointer = @ptrCast(@alignCast(ctx));
                    try ptr.send(report);
                }
            }).send;
        }

        if (std.meta.hasMethod(Pointer, "sleep")) {
            interface.sleepFn = (struct {
                fn sleep(ctx: *anyopaque, ms: u32) void {
                    var ptr: Pointer = @ptrCast(@alignCast(ctx));
                    ptr.sleep(ms);
                }
            }).sleep;
        }

        return interface;
    }

    pub inline fn send(self: *Handler, report: ReportType) !void {
        return self.sendFn(self.ctx, report);
    }

    pub inline fn sleep(self: *Handler, ms: u32) void {
        self.sleepFn(self.ctx, ms);
    }
};

pub const Options = struct {
    left_stick_calibration: StickCalibration = .{},
    right_stick_calibration: StickCalibration = .{},

    /// unit is HZ
    heartbeat_rate_hz: u32 = 50,
};

button_upper: u8 = 0,
button_shared: u8 = 0,
button_lower: u8 = 0,
left_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },
right_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },

left_stick_calibration: StickCalibration,
right_stick_calibration: StickCalibration,

mutex: Mutex,
handler: Handler,
running: std.atomic.Value(bool) = .init(false),

pub fn init(handler: anytype, opt: Options) !Controller {
    var mutex = try Mutex.init();
    errdefer mutex.deinit();

    return .{
        .mutex = mutex,
        .handler = Handler.init(handler),
        .left_stick_calibration = opt.left_stick_calibration,
        .right_stick_calibration = opt.right_stick_calibration,
    };
}

pub fn deinit(self: *Controller) void {
    self.running.store(false, .release);
    self.mutex.deinit();
}

inline fn packetUnlocked(self: *Controller) ReportType {
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

pub fn packet(self: *Controller) ReportType {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    return self.packetUnlocked();
}

pub fn setStickCalibration(self: *Controller, stick: mod.StickType, calibration: StickCalibration) void {
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

pub fn pressButton(self: *Controller, button: mod.Button, state: mod.ButtonState, combine: bool) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (button) {
        .lower => |mask| self.button_lower = setButtonBit(self.button_lower, @intFromEnum(mask), state),
        .shared => |mask| self.button_shared = setButtonBit(self.button_shared, @intFromEnum(mask), state),
        .upper => |mask| self.button_upper = setButtonBit(self.button_upper, @intFromEnum(mask), state),
    }

    log.info(
        "set button [{}] to [{}]. combine = [{}], [lower, shared, upper] = [{x}, {x}, {x}]",
        .{
            button,
            state,
            combine,
            self.button_lower,
            self.button_shared,
            self.button_upper,
        },
    );

    if (!combine)
        self.handler.send(self.packetUnlocked()) catch |err| {
            log.err("failed to send press button report: {s}", .{@errorName(err)});
        };
}

pub fn setStick(self: *Controller, stick: mod.StickType, x: f32, y: f32) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (stick) {
        .left_stick => self.left_stick_centre = calibratedPosition(x, y, self.left_stick_calibration),
        .right_stick => self.right_stick_centre = calibratedPosition(x, y, self.right_stick_calibration),
    }

    self.handler.send(self.packetUnlocked()) catch |err| {
        log.err("failed to send stick report: {s}", .{@errorName(err)});
    };
}

pub fn resetStick(self: *Controller, stick: mod.StickType) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    switch (stick) {
        .left_stick => @memset(&self.left_stick_centre, 0),
        .right_stick => @memset(&self.right_stick_centre, 0),
    }

    self.handler.send(self.packetUnlocked()) catch |err| {
        log.err("failed to reset stick report: {s}", .{@errorName(err)});
    };
}

pub fn resetButton(self: *Controller) void {
    self.mutex.lockUncancelable();
    defer self.mutex.unlock();

    self.button_lower = 0;
    self.button_shared = 0;
    self.button_upper = 0;

    self.handler.send(self.packetUnlocked()) catch |err| {
        log.err("failed to send reset button report: {s}", .{@errorName(err)});
    };
}

pub inline fn runCommand(self: *Controller, command: *const mod.command.Command) void {
    // log.info("run command {}", .{std.meta.activeTag(command.*)});
    switch (command.*) {
        .down => |b| self.pressButton(b.button, .down, b.combine),
        .up => |b| self.pressButton(b.button, .up, b.combine),
        .reset_all => {
            self.resetButton();
            self.resetStick(.left_stick);
            self.resetStick(.right_stick);
        },
        .reset_button => self.resetButton(),
        .reset_stick => |stick| self.resetStick(stick),
        .stick => |stick| self.setStick(stick.stick, stick.x, stick.y),
        .wait => |ms| self.handler.sleep(ms),
        .commands => |*cs| self.runCommands(cs),
        .repeat => |*repeat| {
            for (0..repeat.times) |_| {
                self.runCommands(&repeat.commands);
            }
        },
        else => {},
    }
}

pub fn runCommands(self: *Controller, commands: *const mod.command.Commands) void {
    for (commands.items) |*item| {
        self.runCommand(item);
    }
}

pub fn runCommandPack(self: *Controller, command_pack: *const mod.command.CommandPack) void {
    self.runCommands(&command_pack.commands);
}

/// set button bit. if state is press then set bit to `1`, else set bit to `0`.
inline fn setButtonBit(byte: u8, mask: u8, state: mod.ButtonState) u8 {
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
