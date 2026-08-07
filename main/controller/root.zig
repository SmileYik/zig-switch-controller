pub const Constants = @import("constants.zig");
pub const command = @import("command.zig");
pub const Controller = @import("controller.zig");

pub const ButtonLower = Constants.ButtonLower;
pub const ButtonShared = Constants.ButtonShared;
pub const ButtonUpper = Constants.ButtonUpper;
pub const ButtonState = Constants.ButtonState;
pub const ButtonTag = Constants.ButtonTag;
pub const Button = Constants.Button;
pub const StickType = Constants.StickType;

pub inline fn buttonToByte(btn: Button) u8 {
    return switch (btn) {
        .lower => |mask| @intFromEnum(mask),
        .shared => |mask| @intFromEnum(mask) | 0x40,
        .upper => |mask| @intFromEnum(mask) | 0x80,
    };
}

pub inline fn byteToButton(byte: u8) Button {
    return if (byte & 0x80 != 0)
        .{ .upper = @enumFromInt(byte) }
    else if (byte & 0x40 != 0)
        .{ .shared = @enumFromInt(byte) }
    else
        .{ .lower = @enumFromInt(byte) };
}
