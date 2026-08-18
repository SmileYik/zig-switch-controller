const std = @import("std");
const mod = @import("root.zig");

const log = std.log.scoped(.tomodachi);

const MAX_COLOR = 256;
const MAX_WIDTH = 256;
const MAX_HEIGHT = 256;
const DELAY = 50;

const Image = packed struct {
    width: u16,
    height: u16,
    color_size: u8,
    color: [MAX_COLOR * 3]u8,
    pixels: [MAX_HEIGHT * MAX_WIDTH]u8,
};

const Self = @This();

array: std.ArrayList(u8),
allocator: std.mem.Allocator,
controller: *mod.controller.Controller,

color_panel_idx: usize = 0,

pub fn init(
    allocator: std.mem.Allocator,
    controller: *mod.controller.Controller,
    bytes: std.ArrayList(u8),
) !*Self {
    const ptr = try allocator.create(Self);
    ptr.* = .{
        .array = bytes,
        .allocator = allocator,
        .controller = controller,
    };
    return ptr;
}

pub fn deinit(self: *Self) void {
    self.array.deinit(self.allocator);
    self.allocator.destroy(self);
}

fn width(self: *Self) u16 {
    return std.mem.readInt(u16, self.array.items[0..2], .little);
}

fn height(self: *Self) u16 {
    return std.mem.readInt(u16, self.array.items[2..4], .little);
}

fn colorSize(self: *Self) u8 {
    return self.array.items[5];
}

fn getColor(self: *Self, idx: usize) []const u8 {
    const i = (idx - 1) * 3 + 5;
    return self.array.items[i .. i + 3];
}

fn getPixel(self: *Self, idx: usize) u8 {
    const i = self.colorSize() * 3 + 5 + idx;
    return self.array.items[i];
}

fn resetHSVColorPanel(self: *Self) void {
    self.controller.setStick(.left_stick, -100, 100);
    self.controller.pressButton(.{ .lower = .ZL }, .down, false);
    self.controller.handler.sleep(5000);
    self.controller.pressButton(.{ .lower = .ZL }, .up, false);
    self.controller.resetStick(.left_stick);
}

fn tap(self: *Self, button: mod.controller.Button, interval: u8, after_interval: u8) void {
    self.controller.pressButton(button, .down, false);
    if (interval > 0)
        self.controller.handler.sleep(interval);
    self.controller.pressButton(button, .up, false);
    if (after_interval > 0)
        self.controller.handler.sleep(after_interval);
}

fn tapLower(self: *Self, button: mod.controller.ButtonLower, interval: u8, after_interval: u8) void {
    self.tap(.{ .lower = button }, interval, after_interval);
}

fn tapUpper(self: *Self, button: mod.controller.ButtonUpper, interval: u8, after_interval: u8) void {
    self.tap(.{ .upper = button }, interval, after_interval);
}

fn tapY(self: *Self) void {
    self.tapUpper(.Y, DELAY, DELAY);
}

fn tapA(self: *Self) void {
    self.tapUpper(.A, DELAY, DELAY);
}

fn tapB(self: *Self) void {
    self.tapUpper(.B, DELAY, DELAY);
}

fn tapUp(self: *Self) void {
    self.tapLower(.DPAD_UP, DELAY, DELAY);
}

fn tapDown(self: *Self) void {
    self.tapLower(.DPAD_DOWN, DELAY, DELAY);
}

fn tapLeft(self: *Self) void {
    self.tapLower(.DPAD_LEFT, DELAY, DELAY);
}

fn tapRight(self: *Self) void {
    self.tapLower(.DPAD_RIGHT, DELAY, DELAY);
}

fn initColorPanel(self: *Self) void {
    self.tapY();
    for (0..9) |_| {
        self.tapUp();
    }
    self.tapY();
    self.tap(.{ .upper = .R }, DELAY, DELAY);
    self.tapA();
    self.color_panel_idx = 0;
}

fn chooseColorPanel(self: *Self, idx: usize) void {
    if (self.color_panel_idx == idx) return;

    self.tapY();
    if (idx > self.color_panel_idx) {
        for (self.color_panel_idx..idx) |_| {
            self.tapDown();
        }
    } else {
        for (idx..self.color_panel_idx) |_| {
            self.tapUp();
        }
    }
    self.color_panel_idx = idx;
    self.tapA();
}

fn chooseHSVColor(self: *Self, idx: usize, color_idx: usize) void {
    const color = self.getColor(color_idx);

    self.chooseColorPanel(idx);
    self.tapY();
    self.tapY();

    self.resetHSVColorPanel();
    for (0..color[0]) |_| self.tapUpper(.ZR, DELAY, DELAY);
    for (0..color[1]) |_| self.tapRight();
    for (0..color[2]) |_| self.tapDown();
}

pub fn run(self: *Self) void {
    self.initColorPanel();

    // 0 means no color.
    var color_idx: usize = 1;
    while (color_idx < self.colorSize()) {
        for (0..9) |i| {
            if (color_idx + i < self.colorSize())
                self.chooseHSVColor(i, color_idx + i);
        }
        defer color_idx += 9;

        for (0..self.height()) |i| {
            for (0..self.width()) |j| {
                const j_rev = self.width() - j - 1;
                const is_rev = if (i & 0x1 != 0) true else false;
                const idx = i * self.height() + if (is_rev) j_rev else j;
                const direction: mod.controller.Button =
                    if (is_rev)
                        .{ .lower = .DPAD_LEFT }
                    else
                        .{ .lower = .DPAD_RIGHT };
                const pixel = self.getPixel(idx);
                if (pixel != 0) {
                    self.chooseColorPanel(pixel - color_idx);
                    self.tapA();
                }
                self.tap(direction, DELAY, DELAY);
            }
            self.tapDown();
        }

        for (0..self.height()) |_| self.tapUp();
        for (0..self.width()) |_| self.tapLeft();
    }
}

pub fn start(self: *Self) !void {
    _ = try mod.idf.rtos.Task.create(
        tomodachiDrawTask,
        "tomodachi",
        1024 * 4,
        self,
        5,
    );
}

export fn tomodachiDrawTask(ctx: ?*anyopaque) callconv(.c) void {
    defer mod.idf.rtos.Task.delete(null);
    var self: *Self = @ptrCast(@alignCast(ctx.?));
    log.info("start draw", .{});
    self.run();
    log.info("finished", .{});
}
