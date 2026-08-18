const std = @import("std");
const mod = @import("root.zig");
const Allocator = std.mem.Allocator;

const sys = mod.sys;
const rtos = mod.idf.rtos;

pub fn Queue(comptime T: type, comptime capacity: usize) type {
    return struct {
        pub const Self = @This();
        pub const CAPACITY = capacity;
        pub const InitFn = *const fn (allocator: Allocator, old: T) anyerror!T;
        pub const DeinitFn = *const fn (allocator: Allocator, value: T) void;
        pub const QueueError = error{
            Full,
            /// initValueFn and deinitValueFn must be null together or all none null.
            WrongOptions,
            StorageNotEnough,
        };

        pub const Item = struct {
            _ctx: *Self,
            value: T,

            pub fn deinit(self: Item) void {
                self._ctx.deinitValue(self.value);
            }
        };

        pub const Options = struct {
            allocator: std.mem.Allocator,
            /// initValueFn and deinitValueFn must be null together or all none null.
            initValueFn: ?InitFn = null,
            /// initValueFn and deinitValueFn must be null together or all none null.
            deinitValueFn: ?DeinitFn = null,
        };

        allocator: Allocator,
        initValueFn: ?InitFn = null,
        deinitValueFn: ?DeinitFn = null,
        xqueue: rtos.Queue.Handle,

        pub fn init(opt: Options) !Self {
            if (opt.initValueFn == null and opt.deinitValueFn == null or
                opt.initValueFn != null and opt.deinitValueFn != null)
            {
                return .{
                    .xqueue = (try rtos.Queue.create(CAPACITY, @sizeOf(T))),
                    .allocator = opt.allocator,
                    .deinitValueFn = opt.deinitValueFn,
                    .initValueFn = opt.initValueFn,
                };
            }
            return QueueError.WrongOptions;
        }

        pub fn initStatic(
            opt: Options,
            storage: []u8,
            buf: *sys.StaticQueue_t,
        ) !Self {
            if (storage.len < CAPACITY * @sizeOf(T)) {
                return QueueError.StorageNotEnough;
            } else if (opt.initValueFn == null and opt.deinitValueFn == null or
                opt.initValueFn != null and opt.deinitValueFn != null)
            {
                return .{
                    .xqueue = rtos.Queue.createStatic(CAPACITY, @sizeOf(T), storage.ptr, buf),
                    .allocator = opt.allocator,
                    .deinitValueFn = opt.deinitValueFn,
                    .initValueFn = opt.initValueFn,
                };
            }
            return QueueError.WrongOptions;
        }

        pub fn deinit(self: *Self) void {
            while (self.pollInner(0)) |v| {
                self.deinitValue(v);
            }
            rtos.Queue.delete(self.xqueue);
        }

        pub fn deinitValue(self: *Self, value: T) void {
            if (self.deinitValueFn) |f|
                f(self.allocator, value);
        }

        pub fn enqueue(self: *Self, item: T) !void {
            try self.enqueueWait(item, 0);
        }

        pub fn enqueueWait(self: *Self, item: T, ticks_to_wait: rtos.TickType) !void {
            const self_item = if (self.initValueFn) |f|
                try f(self.allocator, item)
            else
                item;

            if (!rtos.Queue.send(self.xqueue, &self_item, ticks_to_wait)) {
                if (self.deinitValueFn) |f|
                    f(self.allocator, self_item);
                return QueueError.Full;
            }
        }

        pub fn poll(self: *Self) ?Item {
            return if (self.pollInner(0)) |value|
                .{ ._ctx = self, .value = value }
            else
                null;
        }

        pub fn pollWait(self: *Self, ticks_to_wait: rtos.TickType) ?Item {
            return if (self.pollInner(ticks_to_wait)) |value|
                .{ ._ctx = self, .value = value }
            else
                null;
        }

        pub fn pollInner(self: *Self, ticks_to_wait: rtos.TickType) ?T {
            var item: T = undefined;
            if (rtos.Queue.receive(self.xqueue, &item, ticks_to_wait)) {
                return item;
            }
            return null;
        }

        pub fn spacesAvailable(self: *Self) usize {
            return rtos.Queue.spacesAvailable(self.xqueue);
        }
    };
}
