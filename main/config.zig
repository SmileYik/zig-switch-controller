const std = @import("std");
const mod = @import("root.zig");
const Allocator = std.mem.Allocator;
const nvs = mod.idf.nvs;

const log = std.log.scoped(.config);
const MAX_KEY_LEN = 15;

/// u128 div
pub export fn __udivti3(a: u128, b: u128) u128 {
    return a / b;
}

// 128位浮点数 (f128) 算术与转换函数
pub export fn roundq(a: f128) callconv(.c) f128 {
    return @round(a);
}

pub export fn __multf3(a: f128, b: f128) callconv(.c) f128 {
    return a * b;
}

pub export fn __divtf3(a: f128, b: f128) callconv(.c) f128 {
    return a / b;
}

pub export fn __fixtfti(a: f128) callconv(.c) i128 {
    return @intFromFloat(a);
}

pub export fn __floatuntitf(a: u128) callconv(.c) f128 {
    return @floatFromInt(a);
}

// 128位浮点数比较函数 (符合 GCC libgcc ABI)
pub export fn __netf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a != b) 1 else 0;
}

pub export fn __gttf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a > b) 1 else if (a == b) 0 else -1;
}

pub export fn __lttf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a < b) -1 else if (a == b) 0 else 1;
}

pub export fn __letf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a <= b) 0 else 1;
}

pub export fn __getf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a >= b) 0 else -1;
}

pub export fn __eqtf2(a: f128, b: f128) callconv(.c) i32 {
    return if (a == b) 0 else 1;
}

fn checkKeyLen(comptime name: [:0]const u8) void {
    if (name.len > MAX_KEY_LEN) {
        @compileError("NVS Key too long!");
    }
}

pub fn loadFloat(
    comptime T: type,
    handle: u32,
    comptime name: [:0]const u8,
) !T {
    checkKeyLen(name);

    const type_info = @typeInfo(T);
    if (type_info != .float) @compileError("only support float type");
    const float = type_info.float;

    switch (float.bits) {
        32 => {
            return @as(f32, @bitCast(try loadInt(u32, handle, name)));
        },
        else => @compileError("not support int type"),
    }
}

pub fn storeFloat(
    handle: u32,
    comptime name: [:0]const u8,
    value: anytype,
) !void {
    checkKeyLen(name);

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .float) @compileError("only support float type");
    const float = type_info.float;

    switch (float.bits) {
        32 => {
            return try storeInt(handle, name, @as(u32, @bitCast(value)));
        },
        else => @compileError("not support int type"),
    }
}

pub fn loadInt(
    comptime T: type,
    handle: u32,
    comptime name: [:0]const u8,
) !T {
    checkKeyLen(name);

    const type_info = @typeInfo(T);
    if (type_info != .int) @compileError("only support int type");
    const int = type_info.int;

    log.debug("load int [{s}] for key {s}", .{ @typeName(T), name });
    const func = if (int.signedness == .signed)
        switch (int.bits) {
            8 => nvs.getI8,
            16 => nvs.getI16,
            32 => nvs.getI32,
            64 => nvs.getI64,
            else => @compileError("not support int type"),
        }
    else switch (int.bits) {
        8 => nvs.getU8,
        16 => nvs.getU16,
        32 => nvs.getU32,
        64 => nvs.getU64,
        else => @compileError("not support int type"),
    };
    return try func(handle, name);
}

pub fn storeInt(
    handle: u32,
    comptime name: [:0]const u8,
    value: anytype,
) !void {
    checkKeyLen(name);

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .int) @compileError("only support int type");
    const int = type_info.int;

    log.debug("store int [{s}] for key {s}", .{ @typeName(T), name });

    const func = if (int.signedness == .signed)
        switch (int.bits) {
            8 => nvs.setI8,
            16 => nvs.setI16,
            32 => nvs.setI32,
            64 => nvs.setI64,
            else => @compileError("not support int type"),
        }
    else switch (int.bits) {
        8 => nvs.setU8,
        16 => nvs.setU16,
        32 => nvs.setU32,
        64 => nvs.setU64,
        else => @compileError("not support int type"),
    };
    try func(handle, name, value);
}

pub fn loadBool(
    handle: u32,
    comptime name: [:0]const u8,
) !bool {
    checkKeyLen(name);

    return 0 != try loadInt(u8, handle, name);
}

pub fn storeBool(handle: u32, comptime name: [:0]const u8, value: bool) !void {
    try storeInt(handle, name, @as(u8, if (value) 1 else 0));
}

pub fn loadEnum(
    comptime T: type,
    handle: u32,
    comptime name: [:0]const u8,
) !T {
    checkKeyLen(name);

    const type_info = @typeInfo(T);
    if (type_info != .@"enum") @compileError("Only support enum type");
    const enum_info = type_info.@"enum";
    log.debug("load enum {s} from {s}, type: {s}", .{ @typeName(T), name, @typeName(enum_info.tag_type) });
    const value = try loadInt(enum_info.tag_type, handle, name);

    log.debug("load enum {s} from {s}, type: {s}, value: {any}", .{ @typeName(T), name, @typeName(enum_info.tag_type), value });
    return @enumFromInt(value);
}

pub fn storeEnum(
    handle: u32,
    comptime name: [:0]const u8,
    value: anytype,
) !void {
    checkKeyLen(name);

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .@"enum") @compileError("Only support enum type");
    try storeInt(handle, name, @as(type_info.@"enum".tag_type, @intFromEnum(value)));
}

pub fn loadStructArray(
    allocator: Allocator,
    comptime T: type,
    handle: u32,
    comptime name: [:0]const u8,
) ![]T {
    checkKeyLen(name);

    const type_info = @typeInfo(T);
    if (type_info != .array) @compileError("Only support array type");
    const len = type_info.array.len;
    const child_type = type_info.array.child;
    if (@typeInfo(child_type) != .@"struct") @compileError("Only support struct array type");

    if (len == 0) return &[0]child_type{};
    var array: [len]child_type = undefined;

    inline for (0..len) |i| {
        const key = std.fmt.comptimePrint("{s}.{d}", .{ name, i });
        array[i] = loadStructInner(allocator, handle, key, child_type) catch undefined;
    }

    return array;
}

pub fn storeStructArray(
    handle: u32,
    comptime name: [:0]const u8,
    value: anytype,
) !void {
    checkKeyLen(name);

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .array) @compileError("Only support array type");
    const len = type_info.array.len;
    const child_type = type_info.array.child;
    if (@typeInfo(child_type) != .@"struct") @compileError("Only support struct array type");

    if (len == 0) return;

    inline for (0..len) |i| {
        const key = std.fmt.comptimePrint("{s}.{d}", .{ name, i });
        try storeStructInner(handle, key, value[i]);
    }
}

pub fn loadStructSlice(
    allocator: Allocator,
    comptime T: type,
    handle: u32,
    comptime name: [:0]const u8,
) ![]T {
    checkKeyLen(name);

    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("Only support struct type");

    const len_key = std.fmt.comptimePrint("{s}.LEN", .{name});
    const size = try loadInt(u8, handle, len_key);
    if (size == 0) return &[0]T{};

    var slice: []T = try allocator.alloc(T, size);
    errdefer allocator.free(slice);

    inline for (0..255) |i| {
        if (i >= size) return slice;
        const key = std.fmt.comptimePrint("{s}.{d}", .{ name, i });
        slice[i] = try loadStructInner(allocator, handle, key, T);
    }

    return slice;
}

pub fn storeStructSlice(
    handle: u32,
    comptime name: [:0]const u8,
    value: anytype,
) !void {
    checkKeyLen(name);

    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .pointer) @compileError("Only struct slice struct type");
    const child_type = @typeInfo(type_info.pointer.child);
    if (@typeInfo(child_type) != .@"struct") @compileError("Only support struct slice type");

    const len_key = std.fmt.comptimePrint("{s}.LEN", .{name});
    try storeInt(u8, len_key, value.len);

    inline for (0..255) |i| {
        if (i >= value.len) return;
        const key = std.fmt.comptimePrint("{s}.{d}", .{ name, i });
        try storeStructInner(handle, key, value[i]);
    }
}

pub fn loadStructInner(
    allocator: Allocator,
    handle: u32,
    comptime namespace: [*:0]const u8,
    comptime T: type,
) !T {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("only struct supportted");
    const s = type_info.@"struct";

    var t: T = undefined;
    inline for (s.fields) |field| {
        const name = std.fmt.comptimePrint("{s}.{s}", .{ namespace, field.name });
        log.debug("start load {s}", .{name});
        const field_info = @typeInfo(field.type);
        @field(t, field.name) = switch (field_info) {
            .@"struct" => try loadStructInner(allocator, handle, name, field.type),
            .float => try loadFloat(field.type, handle, name),
            .int => try loadInt(field.type, handle, name),
            .bool => try loadBool(handle, name),
            .array => |array| blk: {
                if (array.child == u8) {
                    var buf_len: usize = 0;
                    try nvs.getBlob(handle, name, null, &buf_len);
                    var buf: [array.len]u8 = std.mem.zeroes([array.len]u8);
                    try nvs.getBlob(handle, name, @ptrCast(&buf), &buf_len);
                    break :blk buf;
                } else break :blk try loadStructArray(allocator, field.type, handle, name);
            },
            .pointer => |p| blk: {
                if (p.child == u8) {
                    var buf_len: usize = 0;
                    try nvs.getBlob(handle, name, null, &buf_len);
                    var buf = try allocator.alloc(u8, buf_len);
                    try nvs.getBlob(handle, name, @ptrCast(buf[0..]), &buf_len);
                    break :blk buf;
                } else {
                    break :blk try loadStructSlice(allocator, p.child, handle, name);
                }
            },
            .@"enum" => try loadEnum(field.type, handle, name),
            else => @compileError(field_info),
        };

        log.debug("finished load {s}: {any}", .{ name, @field(t, field.name) });
    }

    return t;
}

pub fn storeStructInner(
    handle: u32,
    comptime namespace: [*:0]const u8,
    value: anytype,
) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("only struct supportted");
    const s = type_info.@"struct";

    inline for (s.fields) |field| {
        const name = std.fmt.comptimePrint("{s}.{s}", .{ namespace, field.name });
        const f = @field(value, field.name);
        log.debug("start store {s}: {any}", .{ name, f });
        const field_info = @typeInfo(field.type);
        switch (field_info) {
            .@"struct" => try storeStructInner(handle, name, f),
            .float => try storeFloat(handle, name, f),
            .int => try storeInt(handle, name, f),
            .bool => try storeBool(handle, name, f),
            .array => |array| {
                if (array.child == u8) {
                    const str: []const u8 = f[0..];
                    try nvs.setBlob(handle, name, str);
                } else try storeStructArray(handle, name, f);
            },
            .pointer => |p| {
                if (p.child == u8) {
                    const str: []const u8 = f[0..];
                    try nvs.setBlob(handle, name, str);
                } else {
                    try storeStructSlice(handle, name, f);
                }
            },
            .@"enum" => try storeEnum(handle, name, f),
            else => @compileError("not support type"),
        }
    }
}

pub fn LoadedConfig(comptime T: type) type {
    return struct {
        allocator: ?std.heap.ArenaAllocator = null,
        config: T,

        pub fn deinit(self: *@This()) void {
            if (self.allocator != null)
                self.allocator.?.deinit();
        }
    };
}

pub fn DefaultConfig(config: anytype) LoadedConfig(@TypeOf(config)) {
    return LoadedConfig(@TypeOf(config)){
        .config = config,
    };
}

pub fn loadStruct(
    allocator: Allocator,
    comptime namespace: [*:0]const u8,
    comptime T: type,
) !LoadedConfig(T) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const alloc = arena.allocator();
    errdefer arena.deinit();

    const handle = try nvs.open(namespace, .read_only);
    const result = try loadStructInner(alloc, handle, namespace, T);
    return .{ .allocator = arena, .config = result };
}

pub fn storeStruct(
    comptime namespace: [*:0]const u8,
    value: anytype,
) !void {
    const handle = try nvs.open(namespace, .read_write);
    return try storeStructInner(handle, namespace, value);
}
