const std = @import("std");
const mod = @import("root.zig");

const sys = mod.sys;
const log = std.log.scoped(.switch_controller);

pub const Protocol = @This();
pub const MAX_REPORT_SIZE = 50;
const VIBRATOR_BYTES = [_]u8{ 0xA0, 0xB0, 0xC0, 0x90 };

/// 控制器类型定义
pub const ControllerType = enum {
    joycon_l,
    joycon_r,
    pro_controller,

    pub fn id(self: ControllerType) u8 {
        return switch (self) {
            .joycon_l => 0x01,
            .joycon_r => 0x02,
            .pro_controller => 0x03,
        };
    }

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

pub const Report = struct {
    response: SwitchResponse,
    subcommand_id: u8 = 0,
    payload: []const u8 = &[_]u8{},
    subcommand: []const u8 = &[_]u8{},
};

pub const SwitchReportParser = struct {
    pub const Options = struct {
        data_len: u8,
        payload_len: u8 = 10,
        magic_head: ?u8 = null,
    };

    data_len: u8,
    payload_len: u8,
    magic_head: ?u8,

    pub fn init(opt: SwitchReportParser.Options) SwitchReportParser {
        return .{
            .data_len = opt.data_len,
            .payload_len = opt.payload_len,
            .magic_head = opt.magic_head,
        };
    }

    pub fn parse(self: *const SwitchReportParser, data: []const u8) Report {
        if (data.len == 0) {
            return .{ .response = .no_data };
        } else if (data.len < self.data_len) {
            return .{ .response = .too_short };
        } else if (self.magic_head) |magic_head| {
            if (data[0] != magic_head) {
                return .{ .response = .malformed };
            }
        }

        const payload = data[0..@min(self.payload_len, data.len)];
        const subcommand = if (data.len > self.payload_len) data[self.payload_len..] else &[_]u8{};
        const subcommand_id = if (subcommand.len > 0) subcommand[0] else 0;

        const response: SwitchResponse = @enumFromInt(subcommand_id);
        log.info("init parse: {any}", .{response});

        return .{
            .response = response,
            .subcommand_id = subcommand_id,
            .payload = payload,
            .subcommand = subcommand,
        };
    }
};

pub const Options = struct {
    controller_type: ControllerType,
    bt_address_mac: [6]u8,
    colour_body: [3]u8 = [_]u8{ 0x82, 0x82, 0x82 },
    colour_buttons: [3]u8 = [_]u8{ 0x0F, 0x0F, 0x0F },
    parser: SwitchReportParser,
};

parser: SwitchReportParser,

bt_address: [6]u8,
controller_type: ControllerType,
report: [MAX_REPORT_SIZE]u8,

mode: ?InputReportMode = null,
player_number: ?u8 = null,
device_info_queried: bool = false,

timer: u8 = 0,
last_timestamp_us: i64 = 0,

battery_level: u8 = 0x90,
connection_info: u8,

button_status: [3]u8 = [_]u8{ 0, 0, 0 },
left_stick_centre: [3]u8,
right_stick_centre: [3]u8,

vibration_enabled: bool = false,
vibrator_report: u8 = 0xA0,

imu_enabled: bool = false,

colour_body: [3]u8,
colour_buttons: [3]u8,

pub fn init(opt: Options) Protocol {
    var self = Protocol{
        .parser = opt.parser,
        .bt_address = opt.bt_address_mac,
        .controller_type = opt.controller_type,
        .report = undefined,
        .connection_info = opt.controller_type.connectionInfo(),
        .left_stick_centre = if (opt.controller_type == .joycon_r) [_]u8{ 0, 0, 0 } else [_]u8{ 0x6F, 0xC8, 0x77 },
        .right_stick_centre = if (opt.controller_type == .joycon_l) [_]u8{ 0, 0, 0 } else [_]u8{ 0x16, 0xD8, 0x7D },
        .colour_body = opt.colour_body,
        .colour_buttons = opt.colour_buttons,
    };
    self.setEmptyReport();
    return self;
}

/// get current report buffer array. you should invoke `clearReport()` method after you send this report.
pub fn gerReport(self: *Protocol) *[MAX_REPORT_SIZE]u8 {
    return &self.report;
}

/// dupe report to your buf and clear self report.
pub fn bufReport(self: *Protocol, dest: *[MAX_REPORT_SIZE]u8) void {
    @memcpy(dest, &self.report);
    self.setEmptyReport();
}

/// allocate and dupe self report and return
pub fn allocReport(self: *Protocol, allocator: std.mem.Allocator) ![]u8 {
    var report = try allocator.alloc(u8, MAX_REPORT_SIZE);
    self.bufReport(report[0..MAX_REPORT_SIZE]);
    return report;
}

/// you should invoke this method after get and send report.
pub fn clearReport(self: *Protocol) void {
    self.setEmptyReport();
}

inline fn setEmptyReport(self: *Protocol) void {
    @memset(&self.report, 0);
    self.report[0] = 0xA1;
}

pub fn processCommands(self: *Protocol, data: []const u8) void {
    const message = self.parser.parse(data);

    switch (message.response) {
        .request_device_info => {
            self.device_info_queried = true;
            self.setSubcommandReply();
            self.setDeviceInfo();
        },
        .set_shipment => {
            self.setSubcommandReply();
            self.setShipment();
        },
        .spi_read => {
            self.setSubcommandReply();
            self.spiRead(message);
        },
        .set_mode => {
            self.setSubcommandReply();
            self.setMode(message);
        },
        .trigger_buttons => {
            self.setSubcommandReply();
            self.setTriggerButtons();
        },
        .toggle_imu => {
            self.setSubcommandReply();
            self.toggleImu(message);
        },
        .enable_vibration => {
            self.setSubcommandReply();
            self.enableVibration();
        },
        .set_player => {
            self.setSubcommandReply();
            self.setPlayerLights(message);
        },
        .set_nfc_ir_state => {
            self.setSubcommandReply();
            self.setNfcIrState();
        },
        .set_nfc_ir_config => {
            self.setSubcommandReply();
            self.setNfcIrConfig();
        },
        .no_data, .too_short, .malformed, _ => {
            self.setFullInputReport();
        },
    }
}

pub fn setSubcommandReply(self: *Protocol) void {
    self.report[1] = 0x21;
    self.vibrator_report = getRandomVibratorByte();
    self.setStandardInputReport();
}

pub fn setUnknownSubcommand(self: *Protocol, subcommand_id: u8) void {
    self.report[15] = subcommand_id;
}

pub fn setTimer(self: *Protocol) void {
    const now_us = sys.esp_timer_get_time();
    if (self.last_timestamp_us == 0) {
        self.last_timestamp_us = now_us;
        self.report[2] = 0x00;
        return;
    }

    const delta_ms = @as(f64, @floatFromInt(now_us - self.last_timestamp_us)) / 1000.0;
    const elapsed_ticks: u32 = @intFromFloat(delta_ms * 4.0);

    self.timer = @truncate(@as(u32, self.timer) + elapsed_ticks);
    self.report[2] = self.timer;
    self.last_timestamp_us = now_us;
}

pub fn setFullInputReport(self: *Protocol) void {
    self.report[1] = 0x30;
    self.setStandardInputReport();
    self.setImuData();
}

pub fn setStandardInputReport(self: *Protocol) void {
    self.setTimer();

    if (self.device_info_queried) {
        self.report[3] = self.battery_level + self.connection_info;

        self.report[4] = self.button_status[0];
        self.report[5] = self.button_status[1];
        self.report[6] = self.button_status[2];

        self.report[7] = self.left_stick_centre[0];
        self.report[8] = self.left_stick_centre[1];
        self.report[9] = self.left_stick_centre[2];

        self.report[10] = self.right_stick_centre[0];
        self.report[11] = self.right_stick_centre[1];
        self.report[12] = self.right_stick_centre[2];

        self.report[13] = self.vibrator_report;
    }
}

pub fn setButtonInputs(self: *Protocol, upper: u8, shared: u8, lower: u8) void {
    self.report[4] = upper;
    self.report[5] = shared;
    self.report[6] = lower;
}

pub fn combineButtonInputs(self: *Protocol, upper: u8, shared: u8, lower: u8) void {
    self.report[4] |= upper;
    self.report[5] |= shared;
    self.report[6] |= lower;
}

pub fn setLeftStickInputs(self: *Protocol, left: [3]u8) void {
    self.report[7] = left[0];
    self.report[8] = left[1];
    self.report[9] = left[2];
}

pub fn setRightStickInputs(self: *Protocol, right: [3]u8) void {
    self.report[10] = right[0];
    self.report[11] = right[1];
    self.report[12] = right[2];
}

pub fn setDeviceInfo(self: *Protocol) void {
    // ACK
    self.report[14] = 0x82;
    // Subcommand Reply
    self.report[15] = 0x02;
    // Firmware Major
    self.report[16] = 0x03;
    // Firmware Minor
    self.report[17] = 0x8B;
    self.report[18] = self.controller_type.id();
    // Unknown
    self.report[19] = 0x02;

    replaceSubarray(&self.report, 20, &self.bt_address);

    // Unknown
    self.report[26] = 0x01;
    // Colours Location
    self.report[27] = 0x01;
}

pub fn setShipment(self: *Protocol) void {
    self.report[14] = 0x80;
    self.report[15] = 0x08;
}

pub fn toggleImu(self: *Protocol, message: Report) void {
    if (message.subcommand.len > 1 and message.subcommand[1] == 0x01) {
        self.imu_enabled = true;
    } else {
        self.imu_enabled = false;
    }
    self.report[14] = 0x80;
    self.report[15] = 0x40;
}

pub fn setImuData(self: *Protocol) void {
    if (!self.imu_enabled) return;

    const imu_data = [_]u8{
        0x75, 0xFD, 0xFD, 0xFF, 0x09, 0x10, 0x21, 0x00, 0xD5, 0xFF,
        0xE0, 0xFF, 0x72, 0xFD, 0xF9, 0xFF, 0x0A, 0x10, 0x22, 0x00,
        0xD5, 0xFF, 0xE0, 0xFF, 0x76, 0xFD, 0xFC, 0xFF, 0x09, 0x10,
        0x23, 0x00, 0xD5, 0xFF, 0xE0, 0xFF,
    };
    replaceSubarray(&self.report, 14, &imu_data);
}

pub fn spiRead(self: *Protocol, message: Report) void {
    if (message.subcommand.len < 6) return;

    const addr_bottom = message.subcommand[1];
    const addr_top = message.subcommand[2];
    const read_length = message.subcommand[5];

    // ACK
    self.report[14] = 0x90;
    // Subcommand reply
    self.report[15] = 0x10;
    self.report[16] = addr_bottom;
    self.report[17] = addr_top;
    self.report[20] = read_length;

    var params = [_]u8{
        0x0F, 0x30, 0x61,
        0x96, 0x30, 0xF3,
        0xD4, 0x14, 0x54,
        0x41, 0x15, 0x54,
        0xC7, 0x79, 0x9C,
        0x33, 0x36, 0x63,
    };

    if (self.controller_type != .pro_controller) {
        params[3] = 0xAE;
    }

    if (addr_top == 0x60 and addr_bottom == 0x00) {
        fillSubarray(&self.report, 21, 16, 0xFF);
    } else if (addr_top == 0x60 and addr_bottom == 0x50) {
        replaceSubarray(&self.report, 21, &self.colour_body);
        replaceSubarray(&self.report, 24, &self.colour_buttons);
        fillSubarray(&self.report, 27, 7, 0xFF);
    } else if (addr_top == 0x60 and addr_bottom == 0x80) {
        if (self.controller_type == .pro_controller) {
            self.report[21] = 0x50;
            self.report[22] = 0xFD;
            self.report[23] = 0x00;
            self.report[24] = 0x00;
            self.report[25] = 0xC6;
            self.report[26] = 0x0F;
        } else {
            self.report[21] = 0x5E;
            self.report[22] = 0x01;
            self.report[23] = 0x00;
            self.report[24] = 0x00;
            if (self.controller_type == .joycon_l) {
                self.report[25] = 0xF1;
                self.report[26] = 0x0F;
            } else {
                self.report[25] = 0x0F;
                self.report[26] = 0xF0;
            }
        }
        replaceSubarray(&self.report, 27, &params);
    } else if (addr_top == 0x60 and addr_bottom == 0x98) {
        replaceSubarray(&self.report, 21, &params);
    } else if (addr_top == 0x80 and addr_bottom == 0x10) {
        fillSubarray(&self.report, 21, 24, 0xFF);
    } else if (addr_top == 0x60 and addr_bottom == 0x3D) {
        const l_calibration = [_]u8{
            0xBA, 0xF5, 0x62,
            0x6F, 0xC8, 0x77,
            0xED, 0x95, 0x5B,
        };
        const r_calibration = [_]u8{
            0x16, 0xD8, 0x7D,
            0xF2, 0xB5, 0x5F,
            0x86, 0x65, 0x5E,
        };

        if (self.controller_type != .joycon_r) {
            replaceSubarray(&self.report, 21, &l_calibration);
        } else {
            fillSubarray(&self.report, 21, 9, 0xFF);
        }

        if (self.controller_type != .joycon_l) {
            replaceSubarray(&self.report, 30, &r_calibration);
        } else {
            fillSubarray(&self.report, 30, 9, 0xFF);
        }

        self.report[39] = 0xFF;
        replaceSubarray(&self.report, 40, &self.colour_body);
        replaceSubarray(&self.report, 43, &self.colour_buttons);
    } else if (addr_top == 0x60 and addr_bottom == 0x20) {
        const sa_calibration = [_]u8{
            0xD3, 0xFF, 0xD5, 0xFF, 0x55, 0x01,
            0x00, 0x40, 0x00, 0x40, 0x00, 0x40,
            0x19, 0x00, 0xDD, 0xFF, 0xDC, 0xFF,
            0x3B, 0x34, 0x3B, 0x34, 0x3B, 0x34,
        };
        replaceSubarray(&self.report, 21, &sa_calibration);
    }
}

pub fn setMode(self: *Protocol, message: Report) void {
    self.report[14] = 0x80;
    self.report[15] = 0x03;

    if (message.subcommand.len > 1) {
        if (message.subcommand[1] == 0x30) {
            self.mode = .standard;
        } else if (message.subcommand[1] == 0x31) {
            self.mode = .nfc_ir;
        } else if (message.subcommand[1] == 0x3F) {
            self.mode = .simple_hid;
        }
    }
}

pub fn setTriggerButtons(self: *Protocol) void {
    self.report[14] = 0x83;
    self.report[15] = 0x04;
}

pub fn enableVibration(self: *Protocol) void {
    self.report[14] = 0x82;
    self.report[15] = 0x48;
    self.vibration_enabled = true;
}

pub fn setPlayerLights(self: *Protocol, message: Report) void {
    self.report[14] = 0x80;
    self.report[15] = 0x30;

    if (message.subcommand.len > 1) {
        const bitfield = message.subcommand[1];
        if (bitfield == 0x01 or bitfield == 0x10) {
            self.player_number = 1;
        } else if (bitfield == 0x03 or bitfield == 0x30) {
            self.player_number = 2;
        } else if (bitfield == 0x07 or bitfield == 0x70) {
            self.player_number = 3;
        } else if (bitfield == 0x0F or bitfield == 0xF0) {
            self.player_number = 4;
        }
    }
}

pub fn setNfcIrState(self: *Protocol) void {
    self.report[14] = 0x80;
    self.report[15] = 0x22;
}

pub fn setNfcIrConfig(self: *Protocol) void {
    self.report[14] = 0xA0;
    self.report[15] = 0x21;

    const params = [_]u8{ 0x01, 0x00, 0xFF, 0x00, 0x08, 0x00, 0x1B, 0x01 };
    replaceSubarray(&self.report, 16, &params);
    self.report[49] = 0xC8;
}

inline fn fillSubarray(slice: []u8, comptime start: usize, comptime len: usize, value: u8) void {
    @memset(slice[start .. start + len], value);
}

inline fn replaceSubarray(slice: []u8, comptime start: usize, src: []const u8) void {
    @memcpy(slice[start .. start + src.len], src);
}

inline fn getRandomVibratorByte() u8 {
    const rand_idx = @as(usize, @intCast(sys.esp_random() % VIBRATOR_BYTES.len));
    return VIBRATOR_BYTES[rand_idx];
}

pub fn combine(masks: anytype) u8 {
    var mask: u8 = 0;
    inline for (masks) |bit| {
        mask |= @intFromEnum(bit);
    }
    return mask;
}
