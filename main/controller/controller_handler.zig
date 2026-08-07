const std = @import("std");
const ReportType = @import("report").ReportType;

const ControllerHandler = @This();

ctx: *anyopaque,
sendFn: *const fn (ctx: *anyopaque, report: ReportType) anyerror!void = undefined,
sleepFn: *const fn (ctx: *anyopaque, ms: u32) void = undefined,

pub inline fn init(handler: anytype) ControllerHandler {
    const Pointer = @TypeOf(handler);
    comptime {
        const info = @typeInfo(Pointer);
        if (info != .pointer or info.pointer.size != .one) {
            @panic("handler need be a struct pointer");
        }
        if (!std.meta.hasMethod(Pointer, "send")) {
            @panic("handler need has a function named send.");
        }
        if (!std.meta.hasMethod(Pointer, "sleep")) {
            @panic("handler need has a function named sleep.");
        }
    }

    var interface: ControllerHandler = .{ .ctx = handler };

    if (std.meta.hasMethod(Pointer, "send")) {
        interface.sendFn = (struct {
            fn send(ctx: *anyopaque, report: ReportType) !void {
                var ptr: Pointer = @ptrCast(@alignCast(ctx));
                try ptr.send(report);
            }
        }).send;
    }

    if (std.meta.hasMethod(Pointer, "sleep")) {
        interface.sleepFn = (struct {
            fn sleep(ctx: *anyopaque, ms: u32) void {
                var ptr: Pointer = @ptrCast(@alignCast(ctx));
                ptr.sleep(ms);
            }
        }).sleep;
    }

    return interface;
}

pub inline fn send(self: *ControllerHandler, report: ReportType) !void {
    return self.sendFn(self.ctx, report);
}

pub inline fn sleep(self: *ControllerHandler, ms: u32) void {
    self.sleepFn(self.ctx, ms);
}
