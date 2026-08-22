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
    end = 0x00,
    /// UP button
    up = 0x01,
    /// DOWN button
    down = 0x02,
    /// TAP button time_num{unit}
    tap = 0x03,
    /// STICK stick_type x y
    stick = 0x04,

    up_combine = 0x05,
    /// DOWN button
    down_combine = 0x06,
    /// TAP time_num1{unit} time_num2{unit} BUTTONS
    tap_combine = 0x07,

    /// RESET_STICK stick_type
    reset_stick = 0x21,
    /// RESET_BUTTON
    reset_button = 0x22,
    /// RESET_ALL
    reset_all = 0x23,

    /// WAIT time_num{unit}
    wait = 0x41,
    wait_u8 = 0x42,
    wait_u16 = 0x43,

    /// REPEAT times
    ///     COMMANDS
    /// END
    repeat = 0x61,
    repeat_u16 = 0x62,
    repeat_u8 = 0x63,

    /// Other commands
    commands = 0x81,
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
    stick: struct { stick: mod.StickType, x: i8, y: i8 },
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

pub fn deinitCommands(allocator: std.mem.Allocator, commands: *Commands) void {
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
