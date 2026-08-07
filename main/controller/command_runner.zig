const std = @import("std");
const mod = @import("root.zig");

pub const StackFrame = struct {
    body_pc: usize,
    remaining_times: u32,
};

pub fn CallStackStatic(comptime cap: usize) type {
    return struct {
        const Self = @This();

        items: [cap]StackFrame = undefined,
        top_index: usize = 0,

        pub fn push(self: *Self, frame: StackFrame) !void {
            if (self.top_index >= cap)
                return error.StackOverflow;

            self.items[self.top_index] = frame;
            self.top_index += 1;
        }

        pub fn top(self: *Self) ?*StackFrame {
            return if (self.top_index > 0)
                &self.items[self.top_index - 1]
            else
                null;
        }

        pub fn pop(self: *Self) ?StackFrame {
            if (self.top_index == 0) return null;
            self.top_index -= 1;
            return self.items[self.top_index];
        }

        pub fn len(self: *const Self) usize {
            return self.top_index;
        }

        pub fn capacity(_: *const Self) usize {
            return capacity;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.top_index == 0;
        }

        pub fn clear(self: *Self) void {
            self.top_index = 0;
        }

        pub fn deinit(_: *Self) void {}
    };
}

pub const CallStackAlloc = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    items: std.ArrayList(StackFrame),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .items = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit(self.allocator);
    }

    pub fn push(self: *Self, frame: StackFrame) !void {
        try self.items.append(self.allocator, frame);
    }

    pub fn top(self: *Self) ?*StackFrame {
        std.debug.assert(self.items.items.len > 0);
        return if (self.items.items.len > 0)
            &self.items.items[self.items.items.len - 1]
        else
            null;
    }

    pub fn pop(self: *Self) ?StackFrame {
        return self.items.pop();
    }

    pub fn len(self: *const Self) usize {
        return self.items.items.len;
    }

    pub fn capacity(self: *const Self) usize {
        return self.items.capacity;
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.items.items.len == 0;
    }

    pub fn clear(self: *Self) void {
        self.items.clearRetainingCapacity();
    }
};

// pub const CallStack = struct {
//     pub const VTable = struct {
//         pushFn: *const fn (ctx: *anyopaque, frame: StackFrame) anyerror!void,
//         topFn: *const fn (ctx: *anyopaque) *StackFrame,
//         popFn: *const fn (ctx: *anyopaque) StackFrame,

//         lenFn: *const fn (ctx: *anyopaque) usize,
//         capacityFn: *const fn (ctx: *anyopaque) usize,

//         deinitFn: *const fn (ctx: *anyopaque) void,
//     };

//     ctx: *anyopaque,
//     vtable: *const VTable,

//     pub inline fn push(self: *CallStack, frame: StackFrame) !void {
//         try self.vtable.pushFn(self.ctx, frame);
//     }

//     pub inline fn top(self: *CallStack) *StackFrame {
//         return self.vtable.topFn(self.ctx);
//     }

//     pub inline fn pop(self: *CallStack) StackFrame {
//         return self.vtable.popFn(self.ctx);
//     }

//     pub inline fn len(self: *CallStack) usize {
//         return self.vtable.lenFn(self.ctx);
//     }

//     pub inline fn capacity(self: *CallStack) usize {
//         return self.vtable.capacityFn(self.ctx);
//     }

//     pub inline fn isEmpty(self: *CallStack) bool {
//         return self.len() == 0;
//     }

//     pub inline fn isFull(self: *CallStack) bool {
//         return self.len() >= self.capacity();
//     }

//     pub inline fn deinit(self: *CallStack) void {
//         self.vtable.deinitFn(self.ctx);
//     }
// };

pub fn CommandRunner(comptime CallStack: type) type {
    return struct {
        const Self = @This();

        controller: *mod.Controller,
        stack: CallStack,
        pc: usize = 0,

        pub fn deinit(self: *Self) void {
            self.stack.deinit();
        }

        pub inline fn runCommand(self: *Self, command: *const mod.command.Command) void {
            // log.info("run command {}", .{std.meta.activeTag(command.*)});
            switch (command.*) {
                .down => |b| self.controller.pressButton(b.button, .down, b.combine),
                .up => |b| self.controller.pressButton(b.button, .up, b.combine),
                .reset_all => {
                    self.controller.resetButton();
                    self.controller.resetStick(.left_stick);
                    self.controller.resetStick(.right_stick);
                },
                .reset_button => self.controller.resetButton(),
                .reset_stick => |stick| self.controller.resetStick(stick),
                .stick => |stick| self.controller.setStick(stick.stick, stick.x, stick.y),
                .wait => |ms| self.controller.handler.sleep(ms),
                .wait_u16 => |ms| self.controller.handler.sleep(@intCast(ms)),
                .wait_u8 => |ms| self.controller.handler.sleep(@intCast(ms)),
                .commands => |*cs| self.controller.runCommands(cs),
                .repeat => |*repeat| {
                    for (0..repeat.times) |_| {
                        self.controller.runCommands(&repeat.commands);
                    }
                },
                else => {},
            }
        }

        pub fn runCommands(self: *Self, commands: *const mod.command.Commands) void {
            for (commands.items) |*item| {
                self.runCommand(item);
            }
        }

        pub fn runCommandPack(self: *Self, command_pack: *const mod.command.CommandPack) void {
            self.runCommands(&command_pack.commands);
        }

        pub fn runByteCode(self: *Self, bytecode: []const u8) !void {
            if (bytecode.len <= 1) return;

            self.pc = 1;
            const endian = mod.byte2Endian(bytecode[0]);

            self.stack.clear();

            while (self.pc < bytecode.len) {
                const tag_val = bytecode[self.pc];
                self.pc += 1;

                const tag: mod.command.CommandTag = @enumFromInt(tag_val);
                switch (tag) {
                    .wait => {
                        const ms = std.mem.readInt(u32, bytecode[self.pc..][0..4], endian);
                        self.pc += 4;
                        self.controller.handler.sleep(ms);
                    },
                    .wait_u16 => {
                        const ms = std.mem.readInt(u16, bytecode[self.pc..][0..2], endian);
                        self.pc += 2;
                        self.controller.handler.sleep(@intCast(ms));
                    },
                    .wait_u8 => {
                        const ms = bytecode[self.pc];
                        self.pc += 1;
                        self.controller.handler.sleep(@intCast(ms));
                    },

                    .down => {
                        const button_byte = bytecode[self.pc];
                        self.pc += 1;
                        const button = mod.byteToButton(button_byte);
                        self.controller.pressButton(button, .down, false);
                    },
                    .down_combine => {
                        const button_byte = bytecode[self.pc];
                        self.pc += 1;
                        const combine = self.pc < bytecode.len and
                            bytecode[self.pc] == @intFromEnum(mod.command.CommandTag.down_combine);

                        const button = mod.byteToButton(button_byte);
                        self.controller.pressButton(button, .down, combine);
                    },

                    .up => {
                        const button_byte = bytecode[self.pc];
                        self.pc += 1;
                        const button = mod.byteToButton(button_byte);
                        self.controller.pressButton(button, .up, false);
                    },
                    .up_combine => {
                        const button_byte = bytecode[self.pc];
                        self.pc += 1;
                        const combine = self.pc < bytecode.len and
                            bytecode[self.pc] == @intFromEnum(mod.command.CommandTag.up_combine);

                        const button = mod.byteToButton(button_byte);
                        self.controller.pressButton(button, .up, combine);
                    },

                    .stick => {
                        const stick_type: mod.StickType = @enumFromInt(bytecode[self.pc]);
                        self.pc += 1;

                        const x_u32 = std.mem.readInt(u32, bytecode[self.pc..][0..4], endian);
                        self.pc += 4;
                        const y_u32 = std.mem.readInt(u32, bytecode[self.pc..][0..4], endian);
                        self.pc += 4;

                        const x: f32 = @bitCast(x_u32);
                        const y: f32 = @bitCast(y_u32);

                        self.controller.setStick(stick_type, x, y);
                    },

                    .reset_stick => {
                        const stick_type: mod.StickType = @enumFromInt(bytecode[self.pc]);
                        self.pc += 1;
                        self.controller.resetStick(stick_type);
                    },

                    .commands => {
                        try self.stack.push(.{
                            .body_pc = self.pc,
                            .remaining_times = 0,
                        });
                    },

                    .repeat => {
                        const times = std.mem.readInt(u32, bytecode[self.pc..][0..4], endian);
                        self.pc += 5;

                        try self.stack.push(.{
                            .body_pc = self.pc,
                            .remaining_times = times - 1,
                        });
                    },
                    .repeat_u16 => {
                        const times = std.mem.readInt(u16, bytecode[self.pc..][0..2], endian);
                        self.pc += 3;

                        try self.stack.push(.{
                            .body_pc = self.pc,
                            .remaining_times = times - 1,
                        });
                    },
                    .repeat_u8 => {
                        const times = bytecode[self.pc];
                        self.pc += 2;

                        try self.stack.push(.{
                            .body_pc = self.pc,
                            .remaining_times = times - 1,
                        });
                    },

                    .reset_button => {
                        self.controller.resetButton();
                    },

                    .reset_all => {
                        self.controller.resetButton();
                        self.controller.resetStick(.left_stick);
                        self.controller.resetStick(.right_stick);
                    },

                    .end => {
                        if (self.stack.top()) |frame| {
                            if (frame.remaining_times > 0) {
                                self.pc = frame.body_pc;
                                frame.remaining_times -= 1;
                            } else {
                                _ = self.stack.pop();
                            }
                        } else {
                            break;
                        }
                    },
                    else => {},
                }
            }
        }
    };
}
