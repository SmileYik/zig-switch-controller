const std = @import("std");
const builtin = @import("builtin");
const mod = @import("root.zig");
const sys = mod.sys;
const bt = mod.idf.bt;
const log = std.log.scoped(.bluetooth);

const BTError = error{
    SendReportFailed,
    SetMacAddressFailed,
    GAPRegisterCallbackFailed,
    GAPSetCODFailed,
    GAPSetSecurityParamFailed,
    GAPSetDeviceNameFailed,
    HIDDRegisterCallbackFailed,
    HIDDInitFailed,
    EnablePairingFailed,
};

// ----------------------------
// HIDD Things....
// ----------------------------

pub const HIDDType = enum(c_int) {
    init = sys.ESP_HIDD_INIT_EVT,
    register_app = sys.ESP_HIDD_REGISTER_APP_EVT,
    open = sys.ESP_HIDD_OPEN_EVT,
    close = sys.ESP_HIDD_CLOSE_EVT,
    intr = sys.ESP_HIDD_INTR_DATA_EVT,
};

pub const HIDDEvent = union(HIDDType) {
    init: ?*const sys.struct_hidd_init_evt_param_183,
    register_app: ?*const sys.struct_hidd_register_app_evt_param_185,
    open: ?*const sys.struct_hidd_open_evt_param_187,
    close: ?*const sys.struct_hidd_close_evt_param_188,
    intr: ?*const sys.struct_hidd_intr_data_evt_param_194,
};

pub const HIDDCallback = *const fn (event: HIDDEvent) void;

const HID_REPORT_DESCRIPTOR = [_]u8{
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, 0x06, 0x01, 0xff, 0x85, 0x21, 0x09,
    0x21, 0x75, 0x08, 0x95, 0x30, 0x81, 0x02, 0x85, 0x30, 0x09, 0x30, 0x75,
    0x08, 0x95, 0x30, 0x81, 0x02, 0x85, 0x31, 0x09, 0x31, 0x75, 0x08, 0x95,
    0x30, 0x81, 0x02, 0x85, 0x32, 0x09, 0x32, 0x75, 0x08, 0x95, 0x30, 0x81,
    0x02, 0x85, 0x33, 0x09, 0x33, 0x75, 0x08, 0x95, 0x30, 0x81, 0x02, 0x85,
    0x3f, 0x05, 0x09, 0x19, 0x01, 0x29, 0x10, 0x15, 0x00, 0x25, 0x01, 0x75,
    0x01, 0x95, 0x10, 0x81, 0x02, 0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25,
    0x07, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x05, 0x09, 0x75, 0x04, 0x95,
    0x01, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x33, 0x09,
    0x34, 0x16, 0x00, 0x00, 0x27, 0xff, 0xff, 0x00, 0x00, 0x75, 0x10, 0x95,
    0x04, 0x81, 0x02, 0x06, 0x01, 0xff, 0x85, 0x01, 0x09, 0x01, 0x75, 0x08,
    0x95, 0x30, 0x91, 0x02, 0x85, 0x10, 0x09, 0x10, 0x75, 0x08, 0x95, 0x30,
    0x91, 0x02, 0x85, 0x11, 0x09, 0x11, 0x75, 0x08, 0x95, 0x30, 0x91, 0x02,
    0x85, 0x12, 0x09, 0x12, 0x75, 0x08, 0x95, 0x30, 0x91, 0x02, 0xc0,
};

const HIDD_APP_PARAM: sys.esp_hidd_app_param_t = .{
    .name = "Pro Controller",
    .description = "Gamepad",
    .provider = "Nintendo",
    .subclass = 0x08,
    .desc_list = @constCast(&HID_REPORT_DESCRIPTOR),
    .desc_list_len = @intCast(HID_REPORT_DESCRIPTOR.len),
};

const HIDD_QOS_IN: sys.esp_hidd_qos_param_t = .{
    .service_type = 0x01,
    .token_rate = 0,
    .token_bucket_size = 0,
    .peak_bandwidth = 0,
    .delay_variation = 0,
    .access_latency = 0,
};
const HIDD_QOS_OUT: sys.esp_hidd_qos_param_t = .{
    .service_type = 0x01,
    .token_rate = 0,
    .token_bucket_size = 0,
    .peak_bandwidth = 0,
    .delay_variation = 0,
    .access_latency = 0,
};

var hiddCallbackFn: ?HIDDCallback = null;

pub fn setHIDDCallback(callback: HIDDCallback) void {
    hiddCallbackFn = callback;
}

pub fn enablePairing() !void {
    switch (sys.esp_bt_gap_set_scan_mode(
        sys.ESP_BT_CONNECTABLE,
        sys.ESP_BT_GENERAL_DISCOVERABLE,
    )) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("change scan mode to connectable and discoverable failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.EnablePairingFailed;
        },
    }
}

export fn hiddCallback(
    event: sys.esp_hidd_cb_event_t,
    param: [*c]sys.esp_hidd_cb_param_t,
) callconv(.c) void {
    const raw_evt: u32 = event;
    switch (raw_evt) {
        sys.ESP_HIDD_INIT_EVT => {
            log.info("[HIDD] [INIT] prepare to init", .{});
            switch (sys.esp_bt_hid_device_register_app(
                @constCast(&HIDD_APP_PARAM),
                @constCast(&HIDD_QOS_IN),
                @constCast(&HIDD_QOS_OUT),
            )) {
                sys.ESP_OK => {},
                else => |err| {
                    log.err("[HIDD] [INIT] failed to init: {s}", .{sys.esp_err_to_name(err)});
                },
            }
            if (hiddCallbackFn) |callback| {
                callback(.{ .init = if (param == null) null else &param.*.init });
            }
        },

        sys.ESP_HIDD_REGISTER_APP_EVT => {
            log.info("[HIDD] [REGISTER_APP] wating for paring", .{});
            enablePairing() catch {};
            if (hiddCallbackFn) |callback| {
                callback(.{ .register_app = if (param == null) null else &param.*.register_app });
            }
        },

        sys.ESP_HIDD_OPEN_EVT => {
            log.info("[HIDD] [OPEN] connecting", .{});

            if (hiddCallbackFn) |callback| {
                callback(.{ .open = if (param == null) null else &param.*.open });
            }
        },

        sys.ESP_HIDD_CLOSE_EVT => {
            log.warn("[HIDD] [CLOSE] closing", .{});

            enablePairing() catch {};
            if (hiddCallbackFn) |callback| {
                callback(.{ .close = if (param == null) null else &param.*.close });
            }
        },

        sys.ESP_HIDD_INTR_DATA_EVT => {
            if (hiddCallbackFn) |callback| {
                callback(.{ .intr = if (param == null) null else &param.*.intr_data });
            }
            if (builtin.mode == .Debug) {
                if (param != null and param.*.intr_data.data != null) {
                    const intr = param.*.intr_data;
                    log.info(
                        "[HIDD] [INTR] [len={d}] [id={x}]: {x}",
                        .{
                            intr.len,
                            intr.report_id,
                            intr.data[0..intr.len],
                        },
                    );
                }
            }
        },

        else => {},
    }
}

// ----------------------------
// GAP things
// ----------------------------

const GAP_COD: u32 = 0x002508;

/// re-export this function.
extern fn esp_bt_gap_set_cod(cod: u32, mode: sys.esp_bt_cod_mode_t) callconv(.c) sys.esp_err_t;

export fn gapCallback(
    event: sys.esp_bt_gap_cb_event_t,
    param: [*c]sys.esp_bt_gap_cb_param_t,
) callconv(.c) void {
    switch (event) {
        sys.ESP_BT_GAP_CFM_REQ_EVT => {
            log.info("[GAP] [ESP_BT_GAP_CFM_REQ_EVT] Accepted!", .{});
            switch (sys.esp_bt_gap_ssp_confirm_reply(&param.*.cfm_req.bda[0], true)) {
                sys.ESP_OK => {},
                else => |err| {
                    log.err("[GAP] [ESP_BT_GAP_CFM_REQ_EVT] auto accept failed: {s}", .{sys.esp_err_to_name(err)});
                },
            }
        },

        sys.ESP_BT_GAP_AUTH_CMPL_EVT => {
            if (param.*.auth_cmpl.stat == sys.ESP_BT_STATUS_SUCCESS) {
                log.info("[GAP] [ESP_BT_GAP_AUTH_CMPL_EVT] auth success！", .{});
            } else {
                log.warn("[GAP] [ESP_BT_GAP_AUTH_CMPL_EVT] auth status: {d}", .{param.*.auth_cmpl.stat});
            }
        },

        sys.ESP_BT_GAP_PIN_REQ_EVT => {
            log.info("[GAP] [ESP_BT_GAP_PIN_REQ_EVT] Requesting PIN, responsing 0000...", .{});
            var pin_code = [_]u8{ '0', '0', '0', '0' };
            switch (sys.esp_bt_gap_pin_reply(
                &param.*.pin_req.bda[0],
                true,
                4,
                &pin_code[0],
            )) {
                sys.ESP_OK => {},
                else => |err| {
                    log.err("[GAP] [ESP_BT_GAP_PIN_REQ_EVT] auto respone PIN failed: {s}", .{sys.esp_err_to_name(err)});
                },
            }
        },

        else => {},
    }
}

fn classicInit(mac: [6]u8) !void {
    switch (sys.esp_base_mac_addr_set(&mac)) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("sed mac address failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.SetMacAddressFailed;
        },
    }

    var cfg = bt.Controller.defaultConfig();
    try bt.Controller.memRelease(.ble);
    try bt.Controller.init(&cfg);
    try bt.Controller.enable(.classic);
    try bt.Bluedroid.init();
    try bt.Bluedroid.enable();
}

pub fn init(mac: [6]u8) !void {
    classicInit(mac) catch |err| {
        log.err("Classic BT initialization failed: {s}", .{@errorName(err)});
        return err;
    };

    switch (sys.esp_bt_gap_register_callback(&gapCallback)) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("GAP register callback failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.GAPRegisterCallbackFailed;
        },
    }

    switch (esp_bt_gap_set_cod(GAP_COD, sys.ESP_BT_SET_COD_ALL)) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("GAP set COD failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.GAPSetCODFailed;
        },
    }

    switch (sys.esp_bt_gap_set_security_param(
        sys.ESP_BT_SP_IOCAP_MODE,
        @constCast(&sys.ESP_BT_IO_CAP_NONE),
        @sizeOf(sys.esp_bt_io_cap_t),
    )) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("GAP set security param failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.GAPSetSecurityParamFailed;
        },
    }

    switch (sys.esp_bt_gap_set_device_name("Pro Controller")) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("GAP set device name failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.GAPSetDeviceNameFailed;
        },
    }

    switch (sys.esp_bt_hid_device_register_callback(&hiddCallback)) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("HIDD register callback failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.HIDDRegisterCallbackFailed;
        },
    }

    switch (sys.esp_bt_hid_device_init()) {
        sys.ESP_OK => {},
        else => |err| {
            log.err("HIDD init failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.HIDDInitFailed;
        },
    }
}

pub fn sendReport(data: []u8) !void {
    log.info("send report [len={d}]: {x}", .{ data.len, data });

    const report_id = data[0];
    const payload = data[1..];
    switch (sys.esp_bt_hid_device_send_report(
        sys.ESP_HIDD_REPORT_TYPE_INTRDATA,
        report_id,
        @intCast(payload.len),
        &payload[0],
    )) {
        sys.ESP_OK => return,
        else => |err| {
            log.err("send report failed: {s}", .{sys.esp_err_to_name(err)});
            return BTError.SendReportFailed;
        },
    }
}
