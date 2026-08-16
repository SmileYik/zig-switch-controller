const std = @import("std");
const mod = @import("root.zig");
const sys = mod.sys;
const idf = mod.idf;

const log = std.log.scoped(.http_action);

const Self = @This();

allocator: std.mem.Allocator,
uris: [5]mod.http.Uri = [_]mod.http.Uri{
    .{
        .uri = "/",
        .method = sys.HTTP_GET,
        .handler = &handleRoot,
        .user_ctx = null,
    },
    .{
        .uri = "/api/config/wifi",
        .method = sys.HTTP_GET,
        .handler = &getWifiConfig,
        .user_ctx = null,
    },
    .{
        .uri = "/api/config/wifi",
        .method = sys.HTTP_POST,
        .handler = &postWifiConfig,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/compile/base64",
        .method = sys.HTTP_POST,
        .handler = &postCommandCompileBase64,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/compile/hex",
        .method = sys.HTTP_POST,
        .handler = &postCommandCompileHex,
        .user_ctx = null,
    },
},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn getUris(self: *Self) []const mod.http.Uri {
    for (&self.uris) |*uri| {
        uri.user_ctx = self;
    }
    return self.uris[0..];
}

const index_html =
    \\<!DOCTYPE html><html><body>
    \\<h1>Hello from Zig on ESP32!</h1>
    \\<p>This page is served by the Zig HTTP server wrapper.</p>
    \\</body></html>
;

/// GET / — serve the index page.
export fn handleRoot(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    idf.http.Server.Response.sendStr(req, index_html) catch |err| {
        log.err("sendStr: {s}", .{@errorName(err)});
        return sys.ESP_FAIL;
    };
    return sys.ESP_OK;
}

/// GET /api/config/wifi
export fn getWifiConfig(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var loaded = mod.config.loadStruct(
        self.allocator,
        @tagName(mod.Configuration.Keys.wf),
        mod.Configuration.WifiConfig,
    ) catch
        mod.config.DefaultConfig(mod.Configuration.WifiConfig{});
    defer loaded.deinit();

    self.sendStructAsJson(req, loaded.config, null);
    return sys.ESP_OK;
}

/// POST /api/config/wifi
export fn postWifiConfig(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var array_opt = self.readBody(self.allocator, req);
    if (array_opt) |*body| {
        defer body.deinit(self.allocator);

        var parsed = std.json.parseFromSlice(
            mod.Configuration.WifiConfig,
            self.allocator,
            body.items,
            .{ .ignore_unknown_fields = true },
        ) catch |e| {
            self.sendError(req, "parsed-body-failed", e);
            return sys.ESP_FAIL;
        };
        defer parsed.deinit();

        mod.config.storeStruct(@tagName(mod.Configuration.Keys.wf), parsed.value) catch |e| {
            self.sendError(req, "store-wifi-config-failed", e);
            return sys.ESP_FAIL;
        };
        self.sendStructAsJson(req, " ", "configurate wifi success");
    } else {
        self.sendJsonError(req, 500, "request body is empty");
    }
    return sys.ESP_OK;
}

/// POST /api/command/compile/base64
export fn postCommandCompileBase64(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var array_opt = self.readBody(self.allocator, req);
    if (array_opt) |*body| {
        defer body.deinit(self.allocator);

        log.debug("compile command to base64: {s}", .{body.items});

        var opt = mod.controller.command.compileToBase64(
            self.allocator,
            body.items[0..body.items.len],
        ) catch |e| {
            self.sendError(req, "compile-script-to-base64-failed", e);
            return sys.ESP_FAIL;
        };
        if (opt) |*base64| {
            defer self.allocator.free(base64.*);
            self.sendStructAsJson(req, base64, "finished compiled");
        } else {
            self.sendJsonError(req, 500, "can not compile to bytecode");
        }
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

/// POST /api/command/compile/hex
export fn postCommandCompileHex(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var array_opt = self.readBody(self.allocator, req);
    if (array_opt) |*body| {
        defer body.deinit(self.allocator);

        log.debug("compile command to hex: {s}", .{body.items});

        var opt = mod.controller.command.compileToHex(
            self.allocator,
            body.items[0..body.items.len],
        ) catch |e| {
            self.sendError(req, "compile-script-to-hex-failed", e);
            return sys.ESP_FAIL;
        };
        if (opt) |*base64| {
            defer self.allocator.free(base64.*);
            self.sendStructAsJson(req, base64, "finished compiled");
        } else {
            self.sendJsonError(req, 500, "can not compile to bytecode");
        }
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

fn Result(comptime T: type) type {
    return struct {
        code: u16,
        data: ?T = null,
        msg: ?[]const u8 = null,
    };
}

fn sendError(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime prefix: []const u8,
    err: anyerror,
) void {
    const R = Result([]const u8);
    var buf: [256:0]u8 = undefined;
    const msg = std.fmt.bufPrintSentinel(
        &buf,
        prefix ++ ": {s}",
        .{@errorName(err)},
        0,
    ) catch prefix ++ ": error";

    const json = std.fmt.allocPrintSentinel(
        self.allocator,
        "{f}",
        .{
            std.json.fmt(R{
                .code = 500,
                .msg = msg,
            }, .{}),
        },
        0,
    ) catch {
        idf.http.Server.Response.sendStr(req, msg) catch {
            log.err("failed to send error message: {s}", .{msg});
            return;
        };
        return;
    };
    defer self.allocator.free(json);

    idf.http.Server.Response.setHDR(req, "content-type", "application/json") catch {
        log.err("failed to send error message: {s}", .{msg});
        return;
    };
    idf.http.Server.Response.sendStr(req, json) catch {
        log.err("failed to send error message: {s}", .{msg});
        return;
    };
}

fn sendJsonError(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    comptime msg: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, code, ' ', msg) catch |e| {
        self.sendError(req, "send-json-error-failed", e);
    };
}

fn sendStructAsJson(
    self: *Self,
    req: [*c]mod.http.Req,
    value: anytype,
    comptime message: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, 200, value, message) catch |e| {
        self.sendError(req, "send-json-error-failed", e);
    };
}

fn sendStructAsJsonInner(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    value: anytype,
    comptime message: ?[]const u8,
) !void {
    const T = @TypeOf(value);
    const R = Result(T);
    const json = try std.fmt.allocPrintSentinel(
        self.allocator,
        "{f}",
        .{
            std.json.fmt(R{
                .code = code,
                .data = value,
                .msg = message,
            }, .{}),
        },
        0,
    );
    defer self.allocator.free(json);

    try idf.http.Server.Response.setHDR(req, "content-type", "application/json");
    try idf.http.Server.Response.sendStr(req, json);
}

fn readBody(
    self: *Self,
    allocator: std.mem.Allocator,
    req: [*c]mod.http.Req,
) ?std.ArrayList(u8) {
    var buf: [1024]u8 = undefined;
    var array: std.ArrayList(u8) = .empty;
    errdefer array.deinit(allocator);

    while (true) {
        const len = idf.http.Server.Request.receiver(req, &buf, buf.len);
        if (len > 0) {
            array.appendSlice(allocator, buf[0..@as(usize, @intCast(len))]) catch |e| {
                self.sendError(req, "Read-body-failed", e);
                defer array.deinit(allocator);
                return null;
            };
        } else break;
    }
    return array;
}
