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

pub const IMU_DATA = [_]u8{
    0x75, 0xFD, 0xFD, 0xFF, 0x09, 0x10, 0x21, 0x00, 0xD5, 0xFF,
    0xE0, 0xFF, 0x72, 0xFD, 0xF9, 0xFF, 0x0A, 0x10, 0x22, 0x00,
    0xD5, 0xFF, 0xE0, 0xFF, 0x76, 0xFD, 0xFC, 0xFF, 0x09, 0x10,
    0x23, 0x00, 0xD5, 0xFF, 0xE0, 0xFF,
};

pub const L_CALIBRATION = [_]u8{
    0xBA, 0xF5, 0x62,
    0x6F, 0xC8, 0x77,
    0xED, 0x95, 0x5B,
};
pub const R_CALIBRATION = [_]u8{
    0x16, 0xD8, 0x7D,
    0xF2, 0xB5, 0x5F,
    0x86, 0x65, 0x5E,
};
pub const SA_CALIBRATION = [_]u8{
    0xD3, 0xFF, 0xD5, 0xFF, 0x55, 0x01,
    0x00, 0x40, 0x00, 0x40, 0x00, 0x40,
    0x19, 0x00, 0xDD, 0xFF, 0xDC, 0xFF,
    0x3B, 0x34, 0x3B, 0x34, 0x3B, 0x34,
};
