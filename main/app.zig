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

const switch_mac = [_]u8{ 0x7C, 0xBB, 0x8A, 0x77, 0x88, 0x9C };
var protocol = ControllerProtocol.init(.{
    .controller_type = .pro_controller,
    .bt_address_mac = switch_mac,
    .parser = .{
        .data_len = 48,
        .magic_head = null,
        .payload_len = 9,
    },
});

// ---------------------------------------------------------------------------
// 6. 初始化与 app_main
// ---------------------------------------------------------------------------
var bluetooth: *bt = undefined;
export fn app_main() callconv(.c) void {
    var heap = idf.heap.HeapCapsAllocator.init(.{ .@"8bit" = true });
    var arena = std.heap.ArenaAllocator.init(heap.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    idf.nvs.flashInitOrErase() catch |err| {
        log.err("NVS 初始化失败: {s}", .{@errorName(err)});
        return;
    };

    var queue = mod.ReportQueue.init(
        allocator,
        .{ .protocol = protocol },
        .{
            .mac = switch_mac,
            .send_report_offset = 1,
        },
    ) catch |err| {
        log.err("初始化消息队列失败: {s}", .{@errorName(err)});
        return;
    };
    defer queue.deinit();
    queue.start() catch @panic("消息队列启动失败!");

    log.info("========== ESP32 Switch HID 手柄已启动 ==========", .{});
    _ = idf.rtos.Task.create(sendReportTask, "send_report", 1024 * 2, queue, 5) catch @panic("Task send_report not created");

    while (true) {
        idf.rtos.Task.delayMs(1000);
    }
}

export fn sendReportTask(ctx: ?*anyopaque) callconv(.c) void {
    var q: *mod.ReportQueue = @ptrCast(@alignCast(ctx.?));
    var press_lr_toggle = false;
    while (true) {
        press_lr_toggle = !press_lr_toggle;

        q.enqueue(.{
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
