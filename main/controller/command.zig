const std = @import("std");
const mod = @import("root.zig");

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const Buttons = std.ArrayList(mod.Button);

pub const parser = @import("command_parser.zig");
pub const runner = @import("command_runner.zig");
pub const compiler = @import("command_compiler.zig");

pub const CommandTimeUnit = enum {
    /// millisecond
    ms,
    /// second
    s,
    m,
    h,
};

pub const CommandTag = enum(u8) {
    end = 0,
    /// UP button
    up = 1,
    /// DOWN button
    down = 2,
    /// TAP button time_num{unit}
    tap = 3,
    /// STICK stick_type x y
    stick = 4,

    up_combine = 5,
    /// DOWN button
    down_combine = 6,
    /// TAP button time_num{unit}
    tap_combine = 7,

    /// RESET_STICK stick_type
    reset_stick = 21,
    /// RESET_BUTTON
    reset_button = 22,
    /// RESET_ALL
    reset_all = 23,

    /// WAIT time_num{unit}
    wait = 41,
    wait_u8 = 42,
    wait_u16 = 43,

    /// REPEAT times
    ///     COMMANDS
    /// END
    repeat = 61,
    repeat_u16 = 62,
    repeat_u8 = 63,

    /// Other commands
    commands = 81,
};

pub const CombinedButton = struct {
    button: mod.Button,
    combine: bool = false,
};

pub const Command = union(CommandTag) {
    end,
    up: CombinedButton,
    down: CombinedButton,
    tap: struct { button: CombinedButton, duration: u32 },
    stick: struct { stick: mod.StickType, x: f32, y: f32 },
    up_combine: CombinedButton,
    down_combine: CombinedButton,
    tap_combine: struct { button: CombinedButton, duration: u32 },
    reset_stick: mod.StickType,
    reset_button,
    reset_all,
    /// unit: milliseconds
    wait: u32,
    wait_u8: u8,
    wait_u16: u16,
    repeat: struct { times: u32, commands: Commands },
    repeat_u16,
    repeat_u8,
    commands: Commands,
};

pub const Commands = std.ArrayList(Command);

pub const CommandPack = struct {
    allocator: std.mem.Allocator,
    commands: Commands,

    pub fn deinit(self: *CommandPack) void {
        deinitCommands(self.allocator, &self.commands);
    }

    pub fn compile(self: *const CommandPack, allocator: std.mem.Allocator, endian: std.builtin.Endian) !std.ArrayList(u8) {
        return try compiler.compile(allocator, self, endian);
    }
};

pub inline fn deinitCommands(allocator: std.mem.Allocator, commands: *Commands) void {
    defer commands.deinit(allocator);
    for (commands.items) |*command|
        deinitCommand(allocator, command);
}

fn deinitCommand(allocator: std.mem.Allocator, command: *Command) void {
    switch (command.*) {
        .commands => |*commands| deinitCommands(allocator, commands),
        .repeat => |*repeat| deinitCommands(allocator, &repeat.commands),
        else => {},
    }
}

pub fn compile(allocator: std.mem.Allocator, script: []const u8) !?std.ArrayList(u8) {
    var opt = try parser.parseCommand(allocator, script);
    if (opt) |*pack| {
        defer pack.deinit();
        const array = try compiler.compile(allocator, pack, .little);
        try runner.byteCodeTest(allocator, array.items);
        return array;
    }
    return null;
}

pub fn compileToHex(allocator: std.mem.Allocator, script: []const u8) !?[]const u8 {
    var opt = try compile(allocator, script);
    if (opt) |*bytes| {
        defer bytes.deinit(allocator);
        return try std.fmt.allocPrint(allocator, "{x}", .{bytes.items});
    }
    return null;
}

pub fn compileToBase64(allocator: std.mem.Allocator, script: []const u8) !?[]const u8 {
    var opt = try compile(allocator, script);
    if (opt) |*bytecode| {
        defer bytecode.deinit(allocator);

        const enc = std.base64.url_safe.Encoder;
        const size = enc.calcSize(bytecode.items.len);
        const base64_bytecode = try allocator.alloc(u8, size);
        return enc.encode(base64_bytecode, bytecode.items);
    }
    return null;
}
