const std = @import("std");

pub const Constants = @import("constants.zig");
pub const command = @import("command.zig");
pub const Controller = @import("controller.zig");
pub const ControllerHandler = @import("controller_handler.zig");

pub const ButtonLower = Constants.ButtonLower;
pub const ButtonShared = Constants.ButtonShared;
pub const ButtonUpper = Constants.ButtonUpper;
pub const ButtonState = Constants.ButtonState;
pub const ButtonTag = Constants.ButtonTag;
pub const Button = Constants.Button;
pub const StickType = Constants.StickType;

pub fn buttonToByte(btn: Button) u8 {
    return switch (btn) {
        .lower => |mask| @ctz(@intFromEnum(mask)),
        .shared => |mask| @as(u8, @ctz(@intFromEnum(mask))) | 0x40,
        .upper => |mask| @as(u8, @ctz(@intFromEnum(mask))) | 0x80,
    };
}

const testing = @import("std").testing;
test "buttonToByte" {
    try testing.expectEqual(0x06, buttonToByte(.{ .lower = .L }));
    try testing.expectEqual(0x40, buttonToByte(.{ .shared = .PLUS }));
    try testing.expectEqual(0x83, buttonToByte(.{ .upper = .A }));
}

pub fn byteToButton(byte: u8) Button {
    return if (byte & 0x80 != 0)
        .{ .upper = @enumFromInt(@as(u8, 1) << @intCast(byte & ~@as(u8, 0x80))) }
    else if (byte & 0x40 != 0)
        .{ .shared = @enumFromInt(@as(u8, 1) << @intCast(byte & ~@as(u8, 0x40))) }
    else
        .{ .lower = @enumFromInt(@as(u8, 1) << @intCast(byte)) };
}

test "byteToButton" {
    try testing.expectEqual(Button{ .lower = ButtonLower.L }, byteToButton(0x06));
    try testing.expectEqual(Button{ .shared = ButtonShared.PLUS }, byteToButton(0x40));
    try testing.expectEqual(Button{ .upper = ButtonUpper.A }, byteToButton(0x83));
}

test "buttonToByte all buttons" {
    // Upper Buttons (base = 0x80)
    try testing.expectEqual(@as(u8, 0x87), buttonToByte(.{ .upper = .ZR }));
    // 1 << 7 -> idx 7 -> 0x80 | 7 = 0x87
    try testing.expectEqual(@as(u8, 0x86), buttonToByte(.{ .upper = .R }));
    // 1 << 6 -> idx 6 -> 0x80 | 6 = 0x86
    try testing.expectEqual(@as(u8, 0x85), buttonToByte(.{ .upper = .JCL_SL }));
    // 1 << 5 -> idx 5 -> 0x80 | 5 = 0x85
    try testing.expectEqual(@as(u8, 0x84), buttonToByte(.{ .upper = .JCL_SR }));
    // 1 << 4 -> idx 4 -> 0x80 | 4 = 0x84
    try testing.expectEqual(@as(u8, 0x83), buttonToByte(.{ .upper = .A }));
    // 1 << 3 -> idx 3 -> 0x80 | 3 = 0x83
    try testing.expectEqual(@as(u8, 0x82), buttonToByte(.{ .upper = .B }));
    // 1 << 2 -> idx 2 -> 0x80 | 2 = 0x82
    try testing.expectEqual(@as(u8, 0x81), buttonToByte(.{ .upper = .X }));
    // 1 << 1 -> idx 1 -> 0x80 | 1 = 0x81
    try testing.expectEqual(@as(u8, 0x80), buttonToByte(.{ .upper = .Y }));
    // 1 << 0 -> idx 0 -> 0x80 | 0 = 0x80

    // Shared Buttons (base = 0x40)
    try testing.expectEqual(@as(u8, 0x40), buttonToByte(.{ .shared = .PLUS }));
    // 1 << 0 -> idx 0 -> 0x40 | 0 = 0x40
    try testing.expectEqual(@as(u8, 0x41), buttonToByte(.{ .shared = .MINUS }));
    // 1 << 1 -> idx 1 -> 0x40 | 1 = 0x41
    try testing.expectEqual(@as(u8, 0x42), buttonToByte(.{ .shared = .R_STICK_PRESSED }));
    // 1 << 2 -> idx 2 -> 0x40 | 2 = 0x42
    try testing.expectEqual(@as(u8, 0x43), buttonToByte(.{ .shared = .L_STICK_PRESSED }));
    // 1 << 3 -> idx 3 -> 0x40 | 3 = 0x43
    try testing.expectEqual(@as(u8, 0x44), buttonToByte(.{ .shared = .HOME }));
    // 1 << 4 -> idx 4 -> 0x40 | 4 = 0x44
    try testing.expectEqual(@as(u8, 0x45), buttonToByte(.{ .shared = .CAPTURE }));
    // 1 << 5 -> idx 5 -> 0x40 | 5 = 0x45

    // Lower Buttons (base = 0x00)
    try testing.expectEqual(@as(u8, 0x07), buttonToByte(.{ .lower = .ZL }));
    // 1 << 7 -> idx 7 -> 0x07
    try testing.expectEqual(@as(u8, 0x06), buttonToByte(.{ .lower = .L }));
    // 1 << 6 -> idx 6 -> 0x06
    try testing.expectEqual(@as(u8, 0x05), buttonToByte(.{ .lower = .JCR_SL }));
    // 1 << 5 -> idx 5 -> 0x05
    try testing.expectEqual(@as(u8, 0x04), buttonToByte(.{ .lower = .JCR_SR }));
    // 1 << 4 -> idx 4 -> 0x04
    try testing.expectEqual(@as(u8, 0x03), buttonToByte(.{ .lower = .DPAD_LEFT }));
    // 1 << 3 -> idx 3 -> 0x03
    try testing.expectEqual(@as(u8, 0x02), buttonToByte(.{ .lower = .DPAD_RIGHT }));
    // 1 << 2 -> idx 2 -> 0x02
    try testing.expectEqual(@as(u8, 0x01), buttonToByte(.{ .lower = .DPAD_UP }));
    // 1 << 1 -> idx 1 -> 0x01
    try testing.expectEqual(@as(u8, 0x00), buttonToByte(.{ .lower = .DPAD_DOWN }));
    // 1 << 0 -> idx 0 -> 0x00
}

test "byteToButton all buttons" {
    // Upper
    try testing.expectEqual(Button{ .upper = .ZR }, byteToButton(0x87));
    try testing.expectEqual(Button{ .upper = .R }, byteToButton(0x86));
    try testing.expectEqual(Button{ .upper = .JCL_SL }, byteToButton(0x85));
    try testing.expectEqual(Button{ .upper = .JCL_SR }, byteToButton(0x84));
    try testing.expectEqual(Button{ .upper = .A }, byteToButton(0x83));
    try testing.expectEqual(Button{ .upper = .B }, byteToButton(0x82));
    try testing.expectEqual(Button{ .upper = .X }, byteToButton(0x81));
    try testing.expectEqual(Button{ .upper = .Y }, byteToButton(0x80));

    // Shared
    try testing.expectEqual(Button{ .shared = .PLUS }, byteToButton(0x40));
    try testing.expectEqual(Button{ .shared = .MINUS }, byteToButton(0x41));
    try testing.expectEqual(Button{ .shared = .R_STICK_PRESSED }, byteToButton(0x42));
    try testing.expectEqual(Button{ .shared = .L_STICK_PRESSED }, byteToButton(0x43));
    try testing.expectEqual(Button{ .shared = .HOME }, byteToButton(0x44));
    try testing.expectEqual(Button{ .shared = .CAPTURE }, byteToButton(0x45));

    // Lower
    try testing.expectEqual(Button{ .lower = .ZL }, byteToButton(0x07));
    try testing.expectEqual(Button{ .lower = .L }, byteToButton(0x06));
    try testing.expectEqual(Button{ .lower = .JCR_SL }, byteToButton(0x05));
    try testing.expectEqual(Button{ .lower = .JCR_SR }, byteToButton(0x04));
    try testing.expectEqual(Button{ .lower = .DPAD_LEFT }, byteToButton(0x03));
    try testing.expectEqual(Button{ .lower = .DPAD_RIGHT }, byteToButton(0x02));
    try testing.expectEqual(Button{ .lower = .DPAD_UP }, byteToButton(0x01));
    try testing.expectEqual(Button{ .lower = .DPAD_DOWN }, byteToButton(0x00));
}

pub fn byte2Endian(byte: u8) std.builtin.Endian {
    return switch (byte) {
        0 => .big,
        else => .little,
    };
}

pub fn endian2byte(endian: std.builtin.Endian) u8 {
    return switch (endian) {
        .big => 0,
        .little => 1,
    };
}
