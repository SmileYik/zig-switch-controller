const std = @import("std");
const mod = @import("root.zig");
const Allocator = std.mem.Allocator;
const Protocol = mod.Protocol;
const testing = std.testing;
const ExpectEqual = testing.expectEqual;
const log = std.log.scoped(.report_queue);

pub const ReportTag = enum {
    incoming,
    sending,
    press_button,
    input,
    stop,
};

pub const ReportType = union(ReportTag) {
    incoming: ?[]u8,
    sending: []u8,
    press_button: struct { upper: u8, shared: u8, lower: u8 },
    input: struct {
        upper: u8 = 0,
        shared: u8 = 0,
        lower: u8 = 0,
        left_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },
        right_stick_centre: [3]u8 = [_]u8{ 0, 0, 0 },
    },
    stop,
};

pub fn ReportQueue(comptime size: usize) type {
    return struct {
        pub const Queue = mod.Queue(ReportType, size);
        const Self = @This();

        const Options = struct {
            queue: ?Queue = null,
            protocol: Protocol,
        };

        running: std.atomic.Value(bool) = .init(false),
        allocator: Allocator,
        queue: Queue,
        protocol: Protocol,
        bt: *mod.bt,
        is_connected: std.atomic.Value(bool) = .init(false),

        pub fn init(allocator: Allocator, opt: Options, bt_opt: mod.bt.Options) !*Self {
            const p: *Self = try allocator.create(Self);
            errdefer allocator.destroy(p);

            var queue = opt.queue orelse try Queue.init(.{
                .allocator = allocator,
                .deinitValueFn = &deinitReportTag,
                .initValueFn = &dupeReportTag,
            });
            errdefer if (opt.queue == null) queue.deinit();

            p.* = .{
                .allocator = allocator,
                .bt = undefined,
                .protocol = opt.protocol,
                .queue = queue,
            };

            var bt = try mod.bt.init(allocator, p, bt_opt);
            errdefer bt.deinit();

            p.bt = bt;
            return p;
        }

        pub fn deinit(self: *Self) void {
            self.running.store(false, .release);
            self.queue.enqueueWait(.stop, 60) catch {};
            self.queue.deinit();
            self.allocator.destroy(self);
        }

        pub fn start(self: *Self) !void {
            self.running.store(true, .release);
            _ = try mod.idf.rtos.Task.create(
                reportTask,
                "report_task",
                1024 * 8,
                self,
                5,
            );
        }

        pub inline fn enqueue(self: *Self, item: ReportType) !void {
            try self.queue.enqueue(item);
        }

        pub inline fn enqueueWait(self: *Self, item: ReportType, ticks: u32) !void {
            try self.queue.enqueueWait(item, ticks);
        }

        fn dupeReportTag(allocator: Allocator, old: ReportType) !ReportType {
            return switch (old) {
                .incoming => |s| .{ .incoming = if (s == null) null else try allocator.dupe(u8, s.?) },
                .sending => |s| .{ .sending = try allocator.dupe(u8, s) },
                else => old,
            };
        }

        fn deinitReportTag(allocator: Allocator, item: ReportType) void {
            switch (item) {
                .incoming => |s| if (s) |*ss| allocator.free(ss.*),
                .sending => |s| allocator.free(s),
                else => {},
            }
        }

        export fn reportTask(ctx: ?*anyopaque) callconv(.c) void {
            var self: *Self = @ptrCast(@alignCast(ctx.?));
            while (self.running.load(.acquire)) {
                while (self.queue.pollWait(std.math.maxInt(u32))) |*item| {
                    defer item.deinit();

                    // drop report if not connected.
                    if (!self.is_connected.load(.acquire) and item.value != .stop) {
                        continue;
                    }

                    switch (item.value) {
                        .incoming => |s| {
                            self.protocol.processCommands(s orelse &[_]u8{});
                            defer self.protocol.clearReport();
                            self.bt.sendReport(self.protocol.report[0..]) catch {};
                        },

                        .sending => |s| {
                            self.bt.sendReport(s) catch {};
                        },

                        .press_button => |s| {
                            self.protocol.setFullInputReport();
                            self.protocol.setButtonInputs(s.upper, s.shared, s.lower);
                            defer self.protocol.clearReport();
                            self.bt.sendReport(self.protocol.report[0..]) catch {};
                        },

                        .input => |s| {
                            self.protocol.setFullInputReport();
                            self.protocol.setButtonInputs(s.upper, s.shared, s.lower);
                            self.protocol.setLeftStickInputs(s.left_stick_centre);
                            self.protocol.setRightStickInputs(s.right_stick_centre);
                            defer self.protocol.clearReport();
                            self.bt.sendReport(self.protocol.report[0..]) catch {};
                        },

                        .stop => return,
                    }
                }
            }
        }

        pub fn handleHIDD(self: *Self, event: mod.bt.HIDDEvent) void {
            if (!self.running.load(.acquire)) return;
            switch (event) {
                .open => {
                    self.enqueue(.{ .incoming = null }) catch |e| {
                        log.err("error when enqueue: {}", .{e});
                    };
                    self.is_connected.store(true, .release);
                },
                .close => {
                    self.is_connected.store(false, .release);
                },
                .intr => |intr_opt| {
                    if (intr_opt) |intr| {
                        if (intr.data != null and intr.len > 0) {
                            const rx_slice = intr.data[0..intr.len];

                            self.enqueue(.{ .incoming = rx_slice }) catch |e| {
                                log.err("error when enqueue: {}", .{e});
                            };
                        }
                    }
                },
                else => {},
            }
        }
    };
}
