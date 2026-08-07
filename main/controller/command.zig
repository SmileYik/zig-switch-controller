const std = @import("std");
const mod = @import("root.zig");

const testing = std.testing;
const ExpectEqual = testing.expectEqual;

const Buttons = std.ArrayList(mod.Button);

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
    /// RESET_STICK stick_type
    reset_stick = 11,
    /// RESET_BUTTON
    reset_button = 12,
    /// RESET_ALL
    reset_all = 13,
    /// WAIT time_num{unit}
    wait = 21,
    /// REPEAT times
    ///     COMMANDS
    /// END
    repeat = 31,
    /// Other commands
    commands = 41,
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
    reset_stick: mod.StickType,
    reset_button,
    reset_all,
    /// unit: milliseconds
    wait: u32,
    repeat: struct { times: u32, commands: Commands },
    commands: Commands,
};

pub const Commands = std.ArrayList(Command);

pub const CommandPack = struct {
    allocator: std.mem.Allocator,
    commands: Commands,
    pub fn deinit(self: *CommandPack) void {
        deinitCommands(self.allocator, &self.commands);
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

pub const parser = @import("command_parser.zig");
