const std = @import("std");
const mod = @import("root.zig");
const Allocator = std.mem.Allocator;
const nvs = mod.idf.nvs;

const log = std.log.scoped(.config);
const MAX_KEY_LEN = 15;

pub export fn __udivti3(a: u128, b: u128) u128 {
    return a / b;
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
                } else @compileError("not support this array type");
            },
            .pointer => |p| blk: {
                if (p.child == u8) {
                    var buf_len: usize = 0;
                    try nvs.getBlob(handle, name, null, &buf_len);
                    var buf = try allocator.alloc(u8, buf_len);
                    try nvs.getBlob(handle, name, @ptrCast(buf[0..]), &buf_len);
                    break :blk buf;
                } else {
                    @compileError("not support this array type");
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
                } else @compileError("not support this array type");
            },
            .pointer => |p| {
                if (p.child == u8) {
                    const str: []const u8 = f[0..];
                    try nvs.setBlob(handle, name, str);
                } else {
                    @compileError("not support this array type");
                }
            },
            .@"enum" => try storeEnum(handle, name, f),
            else => @compileError("not support type"),
        }
    }
}

pub fn loadStruct(allocator: Allocator, comptime namespace: [*:0]const u8, comptime T: type) !T {
    const handle = try nvs.open(namespace, .read_only);
    return try loadStructInner(allocator, handle, namespace, T);
}

pub fn storeStruct(
    comptime namespace: [*:0]const u8,
    value: anytype,
) !void {
    const handle = try nvs.open(namespace, .read_write);
    return try storeStructInner(handle, namespace, value);
}
