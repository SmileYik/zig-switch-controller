const std = @import("std");

pub const MAX_REPORT_SIZE = 50;

pub const ControllerType = enum(u8) {
    joycon_l = 0x01,
    joycon_r = 0x02,
    pro_controller = 0x03,

    pub fn connectionInfo(self: ControllerType) u8 {
        return switch (self) {
            .joycon_l => 0x0E,
            .joycon_r => 0x0E,
            .pro_controller => 0x00,
        };
    }
};

/// 状态与响应枚举
pub const SwitchResponse = enum(i16) {
    no_data = -1,
    malformed = -2,
    too_short = -3,
    request_device_info = 0x02,
    set_shipment = 0x08,
    spi_read = 0x10,
    set_mode = 0x03,
    trigger_buttons = 0x04,
    toggle_imu = 0x40,
    enable_vibration = 0x48,
    set_player = 0x30,
    set_nfc_ir_state = 0x22,
    set_nfc_ir_config = 0x21,
    _,
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

/// 输入报告模式
pub const InputReportMode = enum {
    standard,
    nfc_ir,
    simple_hid,
};
