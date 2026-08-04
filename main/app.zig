/// Nintendo Switch Pro Controller Emulation via BT Classic HID Device
/// Tested on: ESP32 with IDF v6.0 + Zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const mod = @import("mod");
const idf = mod.idf;
const sys = idf.sys;
const bt = mod.bt;

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
                    bt.sendReport(controller.report[0..]) catch {};
                },
                .sending => |s| {
                    bt.sendReport(s) catch {};
                },
                .press_button => |s| {
                    controller.setFullInputReport();
                    if (COMBINE_PRESSED_BUTTON) {
                        controller.combineButtonInputs(s.upper, s.shared, s.lower);
                    } else {
                        controller.setButtonInputs(s.upper, s.shared, s.lower);
                    }
                    defer controller.clearReport();
                    bt.sendReport(controller.report[0..]) catch {};
                },
            }
        }

        idf.rtos.Task.delayMs(66);
    }
}

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

// ---------------------------------------------------------------------------
// 5. HID Callback
// ---------------------------------------------------------------------------

fn hiddCallback(event: bt.HIDDEvent) void {
    switch (event) {
        .open => {
            controller.processCommands(&[_]u8{});
            defer controller.clearReport();
            bt.sendReport(controller.report[0..]) catch {};
            is_connected = true;
        },
        .close => {
            is_connected = false;
        },
        .intr => |intr_opt| {
            if (intr_opt) |intr| {
                if (intr.data != null and intr.len > 0) {
                    const rx_slice = intr.data[0..intr.len];

                    report_queue.enqueue(.{ .incoming = rx_slice }) catch |e| {
                        log.err("error when enqueue: {}", .{e});
                    };
                }
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// 6. 初始化与 app_main
// ---------------------------------------------------------------------------

export fn app_main() callconv(.c) void {
    var heap = idf.heap.HeapCapsAllocator.init(.{ .@"8bit" = true });
    var arena = std.heap.ArenaAllocator.init(heap.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    report_queue = Queue.init(.{
        .allocator = allocator,
        .deinitValueFn = deinitReportTag,
        .initValueFn = dupeReportTag,
    }) catch |err| {
        log.err("队列初始化失败: {s}", .{@errorName(err)});
        return;
    };

    idf.nvs.flashInitOrErase() catch |err| {
        log.err("NVS 初始化失败: {s}", .{@errorName(err)});
        return;
    };

    bt.setHIDDCallback(&hiddCallback);
    bt.init(switch_mac) catch |err| {
        log.err("bluetooth 初始化失败: {s}", .{@errorName(err)});
        return;
    };

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
