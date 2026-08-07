const mod = @import("root.zig");

pub const ButtonState = enum { down, up };

pub const ButtonTag = enum { lower, shared, upper };

pub const Button = union(ButtonTag) {
    lower: mod.ButtonLower,
    shared: mod.ButtonShared,
    upper: mod.ButtonUpper,
};

pub const StickType = enum {
    left_stick,
    right_stick,
};

pub const ButtonUpper = enum(u8) {
    ZR = 1 << 7,
    R = 1 << 6,
    JCL_SL = 1 << 5,
    JCL_SR = 1 << 4,
    A = 1 << 3,
    B = 1 << 2,
    X = 1 << 1,
    Y = 1 << 0,
};

pub const ButtonShared = enum(u8) {
    PLUS = 1 << 0,
    MINUS = 1 << 1,
    R_STICK_PRESSED = 1 << 2,
    L_STICK_PRESSED = 1 << 3,
    HOME = 1 << 4,
    CAPTURE = 1 << 5,
    // bit6         = 1 << 6 未使用
    // bit7         = 1 << 7 未使用
};

pub const ButtonLower = enum(u8) {
    ZL = 1 << 7,
    L = 1 << 6,
    JCR_SL = 1 << 5,
    JCR_SR = 1 << 4,
    DPAD_LEFT = 1 << 3,
    DPAD_RIGHT = 1 << 2,
    DPAD_UP = 1 << 1,
    DPAD_DOWN = 1 << 0,
};
