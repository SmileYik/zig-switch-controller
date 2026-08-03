const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Queue(comptime T: type, comptime capacity: usize) type {
    return struct {
        pub const Self = @This();
        pub const CAPACITY = capacity;
        pub const InitFn = *const fn (allocator: Allocator, old: T) anyerror!T;
        pub const DeinitFn = *const fn (allocator: Allocator, value: T) void;

        pub const Item = struct {
            _ctx: *Self,
            value: T,

            pub fn deinit(self: Item) void {
                self._ctx.deinitValue(self.value);
            }
        };

        pub const Options = struct {
            allocator: std.mem.Allocator,
            initValueFn: ?InitFn = null,
            deinitValueFn: ?DeinitFn = null,
        };

        read: usize = 0,
        write: usize = 0,
        items: [CAPACITY]T = undefined,
        allocator: Allocator,
        initValueFn: ?InitFn = null,
        deinitValueFn: ?DeinitFn = null,

        pub fn init(opt: Options) Self {
            return .{
                .allocator = opt.allocator,
                .deinitValueFn = opt.deinitValueFn,
                .initValueFn = opt.initValueFn,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.deinitValueFn) |f| {
                while (self.pollInner()) |v| f(self.allocator, v);
            }
        }

        pub fn deinitValue(self: *Self, value: T) void {
            if (self.deinitValueFn) |f| f(self.allocator, value);
        }

        pub fn enqueue(self: *Self, item: T) !void {
            if (self.write -% @atomicLoad(usize, &self.read, .acquire) >= CAPACITY) {
                return error.QueueFull;
            }
            const idx = self.write % CAPACITY;
            self.items[idx] = if (self.initValueFn) |f|
                try f(self.allocator, item)
            else
                item;
            @atomicStore(usize, &self.write, self.write +% 1, .release);
        }

        pub fn poll(self: *Self) ?Item {
            return if (self.pollInner()) |value|
                .{ ._ctx = self, .value = value }
            else
                null;
        }

        inline fn pollInner(self: *Self) ?T {
            const limit = @atomicLoad(usize, &self.write, .acquire);
            if (self.read != limit) {
                const item = self.items[self.read % CAPACITY];
                @atomicStore(usize, &self.read, self.read +% 1, .release);
                return item;
            }
            return null;
        }
    };
}
