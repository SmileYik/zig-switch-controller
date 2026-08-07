/// Nintendo Switch Pro Controller Emulation via BT Classic HID Device
/// Tested on: ESP32 with IDF v6.0 + Zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const mod = @import("mod");
const idf = mod.idf;
const sys = idf.sys;
const bt = mod.bt;

const ControllerProtocol = mod.protocol.Protocol;
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

    var controller = mod.Controller.init(.{
        .report_queue = queue,
        .heartbeat_rate_hz = 2,
    }) catch |err| {
        log.err("控制器初始化失败!: {s}", .{@errorName(err)});
        return;
    };
    defer controller.deinit();
    controller.start() catch |err| {
        log.err("控制器启动失败!: {s}", .{@errorName(err)});
        return;
    };

    log.info("========== ESP32 Switch HID 手柄已启动 ==========", .{});
    // _ = idf.rtos.Task.create(sendReportTask, "send_report", 1024 * 2, queue, 5) catch @panic("Task send_report not created");

    while (!queue.is_connected.load(.acquire)) {
        idf.rtos.Task.delayMs(1000);
    }

    var command_pack_opt = mod.Controller.parseCommand(allocator, SCRIPT) catch |err| {
        log.err("控制器脚本失败!: {s}", .{@errorName(err)});
        return;
    };
    if (command_pack_opt) |*pack| {
        defer pack.deinit();
        controller.runCommandPack(pack);
    }
}

const SCRIPT =
    \\REPEAT 4294967294
    \\
    \\  REPEAT 5
    \\    DOWN R L
    \\    WAIT 66ms
    \\    UP R L
    \\    WAIT 66ms
    \\  END
    \\
    \\  WAIT 10s
    \\
    \\  REPEAT 1
    \\    DOWN A
    \\    WAIT 66ms
    \\    UP A
    \\    WAIT 66ms
    \\  END
    \\
    \\  WAIT 20s
    \\
    \\REPEAT 3
    \\  DOWN ZR
    \\  WAIT 66ms
    \\  UP ZR
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN R
    \\  WAIT 66ms
    \\  UP R
    \\END
    \\WAIT 1s
    \\
    // \\REPEAT 3
    // \\  DOWN JCL_SL
    // \\  WAIT 66ms
    // \\  UP JCL_SL
    // \\END
    // \\WAIT 1s
    // \\
    // \\REPEAT 3
    // \\  DOWN JCL_SR
    // \\  WAIT 66ms
    // \\  UP JCL_SR
    // \\END
    // \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN A
    \\  WAIT 66ms
    \\  UP A
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN B
    \\  WAIT 66ms
    \\  UP B
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN X
    \\  WAIT 66ms
    \\  UP X
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN Y
    \\  WAIT 66ms
    \\  UP Y
    \\END
    \\WAIT 1s
    \\
    // \\REPEAT 3
    // \\  DOWN CAPTURE
    // \\  WAIT 66ms
    // \\  UP CAPTURE
    // \\END
    // \\WAIT 1s
    \\
    // \\REPEAT 3
    // \\  DOWN HOME
    // \\  WAIT 66ms
    // \\  UP HOME
    // \\END
    // \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN L_STICK_PRESSED
    \\  WAIT 66ms
    \\  UP L_STICK_PRESSED
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN R_STICK_PRESSED
    \\  WAIT 66ms
    \\  UP R_STICK_PRESSED
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN PLUS
    \\  WAIT 66ms
    \\  UP PLUS
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN MINUS
    \\  WAIT 66ms
    \\  UP MINUS
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN ZL
    \\  WAIT 66ms
    \\  UP ZL
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN L
    \\  WAIT 66ms
    \\  UP L
    \\END
    \\WAIT 1s
    \\
    // \\REPEAT 3
    // \\  DOWN JCR_SL
    // \\  WAIT 66ms
    // \\  UP JCR_SL
    // \\END
    // \\WAIT 1s
    // \\
    // \\REPEAT 3
    // \\  DOWN JCR_SR
    // \\  WAIT 66ms
    // \\  UP JCR_SR
    // \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN DPAD_LEFT
    \\  WAIT 66ms
    \\  UP DPAD_LEFT
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN DPAD_RIGHT
    \\  WAIT 66ms
    \\  UP DPAD_RIGHT
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN DPAD_UP
    \\  WAIT 66ms
    \\  UP DPAD_UP
    \\END
    \\WAIT 1s
    \\
    \\REPEAT 3
    \\  DOWN DPAD_DOWN
    \\  WAIT 66ms
    \\  UP DPAD_DOWN
    \\END
    \\
    \\END
    \\
;

pub const panic = idf.esp_panic.panic;
pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
    .logFn = idf.log.espLogFn,
};
