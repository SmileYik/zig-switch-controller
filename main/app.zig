/// Nintendo Switch Pro Controller Emulation via BT Classic HID Device
/// Tested on: ESP32 with IDF v6.0 + Zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const mod = @import("mod");
const idf = mod.idf;
const sys = idf.sys;
const bt = idf.bt;

const ControllerProtocol = mod.Protocol;
const log = std.log.scoped(.switch_controller);

const COMBINE_PRESSED_BUTTON = true;

const ReportTag = enum {
    incoming,
    sending,
    press_button,
};
const ReportType = union(ReportTag) {
    incoming: []u8,
    sending: []u8,
    press_button: struct { upper: u8, shared: u8, lower: u8 },
};
const Queue = mod.Queue(ReportType, 16);
var report_queue: Queue = undefined;

fn dupeReportTag(allocator: Allocator, old: ReportType) !ReportType {
    return switch (old) {
        .incoming => |s| .{ .incoming = try allocator.dupe(u8, s) },
        .sending => |s| .{ .sending = try allocator.dupe(u8, s) },
        .press_button => |s| .{
            .press_button = .{
                .lower = s.lower,
                .shared = s.shared,
                .upper = s.upper,
            },
        },
    };
}
fn deinitReportTag(allocator: Allocator, item: ReportType) void {
    switch (item) {
        .incoming => |s| allocator.free(s),
        .sending => |s| allocator.free(s),
        else => {},
    }
}

export fn reportTask(_: ?*anyopaque) callconv(.c) void {
    while (true) {
        while (report_queue.poll()) |*item| {
            defer item.deinit();

            switch (item.value) {
                .incoming => |s| {
                    controller.processCommands(s);
                    defer controller.clearReport();
                    sendReport(controller.report[0..]);
                },
                .sending => |s| {
                    sendReport(s);
                },
                .press_button => |s| {
                    controller.setFullInputReport();
                    if (COMBINE_PRESSED_BUTTON) {
                        controller.combineButtonInputs(s.upper, s.shared, s.lower);
                    } else {
                        controller.setButtonInputs(s.upper, s.shared, s.lower);
                    }
                    defer controller.clearReport();
                    sendReport(controller.report[0..]);
                },
            }
        }

        idf.rtos.Task.delayMs(66);
    }
}
// ---------------------------------------------------------------------------
// 1. 底层结构体与 extern 声明
// ---------------------------------------------------------------------------

const EspHiddDescriptor = extern struct {
    data: [*c]const u8,
    dl_len: u16,
};

// ---------------------------------------------------------------------------
// 2. 166 字节标准 Switch Pro Controller HID 描述符
// ---------------------------------------------------------------------------

var hid_report_descriptor = [_]u8{
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
// ---------------------------------------------------------------------------
// 3. 全局变量
// ---------------------------------------------------------------------------

const switch_mac = [_]u8{ 0x7C, 0xBB, 0x8A, 0x77, 0x88, 0x9C };
var controller = ControllerProtocol.init(.{
    .controller_type = .pro_controller,
    .bt_address_mac = switch_mac,
    .parser = .{
        .data_len = 49,
        .magic_head = null,
        .payload_len = 10,
    },
});
var is_connected: bool = false;

var g_hid_desc: EspHiddDescriptor = .{
    .data = &hid_report_descriptor,
    .dl_len = hid_report_descriptor.len,
};
var g_app_param: sys.esp_hidd_app_param_t = .{
    .name = "Pro Controller",
    .description = "Gamepad",
    .provider = "Nintendo",
    .subclass = 0x08,
    .desc_list = &hid_report_descriptor[0],
    .desc_list_len = hid_report_descriptor.len,
};
var g_in_qos: sys.esp_hidd_qos_param_t = .{
    .service_type = 0x01,
    .token_rate = 0,
    .token_bucket_size = 0,
    .peak_bandwidth = 0,
    .delay_variation = 0,
    .access_latency = 0,
};
var g_out_qos: sys.esp_hidd_qos_param_t = .{
    .service_type = 0x01,
    .token_rate = 0,
    .token_bucket_size = 0,
    .peak_bandwidth = 0,
    .delay_variation = 0,
    .access_latency = 0,
};

// ---------------------------------------------------------------------------
// 4. GAP 回调函数
// ---------------------------------------------------------------------------

export fn gapCallback(
    event: sys.esp_bt_gap_cb_event_t,
    param: [*c]sys.esp_bt_gap_cb_param_t,
) callconv(.c) void {
    switch (event) {
        sys.ESP_BT_GAP_CFM_REQ_EVT => {
            log.info("【BT GAP】收到 SSP 确认请求，自动确认...", .{});
            _ = sys.esp_bt_gap_ssp_confirm_reply(&param.*.cfm_req.bda[0], true);
        },

        sys.ESP_BT_GAP_AUTH_CMPL_EVT => {
            if (param.*.auth_cmpl.stat == sys.ESP_BT_STATUS_SUCCESS) {
                log.info("【BT GAP】身份验证成功！", .{});
            } else {
                log.warn("【BT GAP】身份验证失败，状态码: {d}", .{param.*.auth_cmpl.stat});
            }
        },

        sys.ESP_BT_GAP_PIN_REQ_EVT => {
            log.info("【BT GAP】收到 PIN 请求，自动回复 0000...", .{});
            var pin_code = [_]u8{ '0', '0', '0', '0' };
            _ = sys.esp_bt_gap_pin_reply(&param.*.pin_req.bda[0], true, 4, &pin_code[0]);
        },

        else => {},
    }
}

fn sendReport(data: []u8) void {
    const report_id = data[0];
    const payload = data[1..50];
    log.info("TX: {x}", .{data});

    _ = sys.esp_bt_hid_device_send_report(
        sys.ESP_HIDD_REPORT_TYPE_INTRDATA,
        report_id,
        @intCast(payload.len),
        &payload[0],
    );
}

// ---------------------------------------------------------------------------
// 5. HID Callback
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 5. HID Callback (修复版)
// ---------------------------------------------------------------------------

export fn hiddCallback(
    event: sys.esp_hidd_cb_event_t,
    param: [*c]sys.esp_hidd_cb_param_t,
) callconv(.c) void {
    const raw_evt: u32 = event;
    switch (raw_evt) {
        // ESP_HIDD_INIT_EVT (0)
        sys.ESP_HIDD_INIT_EVT => {
            log.info("HID Device 驱动初始化完成，准备注册 SDP...", .{});
            _ = sys.esp_bt_hid_device_register_app(&g_app_param, &g_in_qos, &g_out_qos);
        },

        // ESP_HIDD_REGISTER_APP_EVT (2)
        sys.ESP_HIDD_REGISTER_APP_EVT => {
            log.info("【配对就绪】SDP 注册成功，广播开启！请在 Switch 更改握法界面等待...", .{});
            _ = sys.esp_bt_gap_set_scan_mode(
                sys.ESP_BT_CONNECTABLE,
                sys.ESP_BT_GENERAL_DISCOVERABLE,
            );
        },

        // ESP_HIDD_OPEN_EVT (4)
        sys.ESP_HIDD_OPEN_EVT => {
            log.info("🎉🎉🎉【连接成功】Switch 已与 ESP32 建立 HID 通道！", .{});

            // 连接建立后主动发一个空 Input Report，促使 Switch 启动 Subcommand 握手
            // controller.setButtonInputs(ControllerProtocol.combine(.{ControllerProtocol.ButtonLower.L}), 0, ControllerProtocol.combine(.{ControllerProtocol.ButtonUpper.R}));
            controller.processCommands(&[_]u8{});
            defer controller.clearReport();
            sendReport(controller.report[0..]);
            is_connected = true;
        },

        // ESP_HIDD_CLOSE_EVT (5)
        sys.ESP_HIDD_CLOSE_EVT => {
            is_connected = false;
            log.warn("【断开连接】与 Switch 的 HID 通道已断开，重新广播...", .{});
            _ = sys.esp_bt_gap_set_scan_mode(
                sys.ESP_BT_CONNECTABLE,
                sys.ESP_BT_GENERAL_DISCOVERABLE,
            );
        },

        // ESP_HIDD_SEND_REPORT_EVT (6)
        sys.ESP_HIDD_SEND_REPORT_EVT => {
            // 发送完成事件，属于正常刷屏日志，不用处理
        },

        sys.ESP_HIDD_INTR_DATA_EVT => {
            if (param != null) {
                const intr = param.*.intr_data;
                if (intr.data != null and intr.len > 0) {
                    const rx_slice = intr.data[0..intr.len];
                    log.info("Switch (INTR) [evtid={d}] [id={x}] [len={d}]: {x}", .{ event, intr.report_id, intr.len, rx_slice });

                    report_queue.enqueue(.{ .incoming = rx_slice }) catch |e| {
                        log.err("error when enqueue: {}", .{e});
                    };
                }
            }
        },

        // 捕获所有数据接收事件 (ESP-IDF 中 INTR_DATA 或 SET_REPORT 通常为 7, 8, 12, 13 等)
        else => {},
    }
}
// ---------------------------------------------------------------------------
// 6. 初始化与 app_main
// ---------------------------------------------------------------------------

fn classicInit() !void {
    _ = sys.esp_base_mac_addr_set(&switch_mac);

    var cfg = bt.Controller.defaultConfig();
    try bt.Controller.memRelease(.ble);
    try bt.Controller.init(&cfg);
    try bt.Controller.enable(.classic);
    try bt.Bluedroid.init();
    try bt.Bluedroid.enable();
}

extern fn esp_bt_gap_set_cod(cod: u32, mode: sys.esp_bt_cod_mode_t) callconv(.c) sys.esp_err_t;

export fn app_main() callconv(.c) void {
    var heap = idf.heap.HeapCapsAllocator.init(.{ .@"8bit" = true });
    var arena = std.heap.ArenaAllocator.init(heap.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    report_queue = Queue.init(.{
        .allocator = allocator,
        .deinitValueFn = deinitReportTag,
        .initValueFn = dupeReportTag,
    });

    idf.nvs.flashInitOrErase() catch |err| {
        log.err("NVS 初始化失败: {s}", .{@errorName(err)});
        return;
    };

    classicInit() catch |err| {
        log.err("BT 初始化失败: {s}", .{@errorName(err)});
        return;
    };

    _ = sys.esp_bt_gap_register_callback(&gapCallback);

    const cod_u32: u32 = 0x002508;
    _ = esp_bt_gap_set_cod(cod_u32, sys.ESP_BT_SET_COD_ALL);

    var iocap: sys.esp_bt_io_cap_t = sys.ESP_BT_IO_CAP_NONE;
    _ = sys.esp_bt_gap_set_security_param(
        sys.ESP_BT_SP_IOCAP_MODE,
        &iocap,
        @sizeOf(sys.esp_bt_io_cap_t),
    );

    _ = sys.esp_bt_gap_set_device_name("Pro Controller");

    _ = sys.esp_bt_hid_device_register_callback(&hiddCallback);
    _ = sys.esp_bt_hid_device_init();

    log.info("========== ESP32 Switch HID 手柄已启动 ==========", .{});
    _ = idf.rtos.Task.create(reportTask, "report_task", 1024 * 8, null, 5) catch @panic("Task blink not created");

    var press_lr_toggle = false;

    while (true) {
        if (!is_connected) {
            idf.rtos.Task.delayMs(500);
            continue;
        }

        press_lr_toggle = !press_lr_toggle;

        // const btn_upper: u8 = if (press_lr_toggle) 0x02 else 0x00; // R
        // const btn_lower: u8 = if (press_lr_toggle) 0x02 else 0x00; // L

        // controller.setFullInputReport();
        report_queue.enqueue(.{
            .press_button = .{
                .lower = if (press_lr_toggle) ControllerProtocol.combine(.{ControllerProtocol.ButtonLower.L}) else 0,
                .shared = 0,
                .upper = if (press_lr_toggle) ControllerProtocol.combine(.{ControllerProtocol.ButtonUpper.R}) else 0,
            },
        }) catch {};

        idf.rtos.Task.delayMs(66);
    }
}

pub const panic = idf.esp_panic.panic;
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    .logFn = idf.log.espLogFn,
};
