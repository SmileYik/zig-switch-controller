const std = @import("std");
const mod = @import("root.zig");
const Protocol = mod.Protocol;
const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const Self = @This();

const ButtonLower = Protocol.ButtonLower;
const ButtonShared = Protocol.ButtonShared;
const ButtonUpper = Protocol.ButtonUpper;

pub const ButtonTag = enum {
    lower,
    shared,
    upper,
};

pub const Button = union(ButtonTag) {
    lower: ButtonLower,
    shared: ButtonShared,
    upper: ButtonUpper,
};

pub const ButtonState = enum { down, up };

pub const StickCalibration = struct {
    center_x: i16,
    center_y: i16,
    min_x: i16,
    max_x: i16,
    min_y: i16,
    max_y: i16,
};

pub const StickType = enum {
    left_stick,
    right_stick,
};

button_upper: u8 = 0,
button_shared: u8 = 0,
button_lower: u8 = 0,
left_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },
right_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },

left_stick_calibration: StickCalibration,
right_stick_calibration: StickCalibration,

inline fn calibratedPositionInner(x: f16, y: f16, calibration: StickCalibration) [3]u8 {
    const fx = @as(f16, @floatFromInt(calibration.center_x)) + @abs(x) *
        if (x < 0)
            @as(f16, @floatFromInt(calibration.min_x))
        else
            @as(f16, @floatFromInt(calibration.max_x));

    const fy = @as(f16, @floatFromInt(calibration.center_y)) + @abs(y) *
        if (y < 0)
            @as(f16, @floatFromInt(calibration.min_y))
        else
            @as(f16, @floatFromInt(calibration.max_y));

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

pub inline fn calibratedPosition(x: f16, y: f16, calibration: StickCalibration) [3]u8 {
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

pub const LEFT_STICK_CALIBRATION = StickCalibration{
    .center_x = 2159,
    .center_y = 1916,
    .min_x = -1466,
    .max_x = 1517,
    .min_y = -1583,
    .max_y = 1465,
};

pub const RIGHT_STICK_CALIBRATION = StickCalibration{
    .center_x = 2070,
    .center_y = 2013,
    .min_x = -1522,
    .max_x = 1414,
    .min_y = -1531,
    .max_y = 1510,
};
