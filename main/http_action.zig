const std = @import("std");
const mod = @import("root.zig");
const sys = mod.sys;
const idf = mod.idf;

const runner = mod.controller.command.runner;
const CommandRunner = runner.CommandRunner(runner.CallStackAlloc);

const log = std.log.scoped(.http_action);

const Self = @This();

allocator: std.mem.Allocator,
controller: *mod.controller.Controller,

uris: [7]mod.http.Uri = [_]mod.http.Uri{
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
    .{
        .uri = "/api/command/test/base64",
        .method = sys.HTTP_POST,
        .handler = &postCommandTestBase64,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/run/sync/raw",
        .method = sys.HTTP_POST,
        .handler = &postCommandRunSyncRaw,
        .user_ctx = null,
    },
},

pub fn init(
    allocator: std.mem.Allocator,
    controller: *mod.controller.Controller,
) Self {
    return .{ .allocator = allocator, .controller = controller };
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
    const template =
        \\{{"ap":{{"ssid": "{s}", "pwd":"{s}"}},"sta":{{"ssid": "{s}", "pwd":"{s}"}}}}
    ;
    const msg = std.fmt.allocPrint(self.allocator, template, .{
        loaded.config.ap.ssid,
        loaded.config.ap.pwd,
        loaded.config.sta.ssid,
        loaded.config.sta.pwd,
    }) catch |e| {
        self.sendError(req, "parsed-wifi-config-failed", e);
        return sys.ESP_FAIL;
    };

    self.sendStructAsJson(req, msg, null);
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
        self.sendStructAsJson(req, null, "configurate wifi success");
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
            self.sendStringAsJson(req, base64.*, "finished compiled");
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
            self.sendStringAsJson(req, base64.*, "finished compiled");
        } else {
            self.sendJsonError(req, 500, "can not compile to bytecode");
        }
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

/// POST /api/command/test/base64
export fn postCommandTestBase64(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var array_opt = self.readBody(self.allocator, req);
    if (array_opt) |*body| {
        defer body.deinit(self.allocator);

        const dec = std.base64.url_safe.Decoder;
        const size = dec.calcSizeForSlice(body.items) catch |e| {
            self.sendError(req, "calculate-base64-decode-size-failed", e);
            return sys.ESP_FAIL;
        };
        const buf = self.allocator.alloc(u8, size) catch |e| {
            self.sendError(req, "alloc-calculate-base64-decode-size-failed", e);
            return sys.ESP_FAIL;
        };
        defer self.allocator.free(buf);
        dec.decode(buf, body.items) catch |e| {
            self.sendError(req, "decode-base64-failed", e);
            return sys.ESP_FAIL;
        };

        mod.controller.command.runner.byteCodeTest(self.allocator, buf) catch |e| {
            self.sendError(req, "decode-base64-failed", e);
            return sys.ESP_FAIL;
        };
        self.sendStructAsJson(req, null, "complete test!");
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

/// POST /api/command/run/sync/raw
export fn postCommandRunSyncRaw(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var array_opt = self.readBody(self.allocator, req);
    if (array_opt) |*body| {
        var opt = mod.controller.command.parser.parseCommand(self.allocator, body.items) catch |e| {
            self.sendError(req, "parse-script-failed", e);
            body.deinit(self.allocator);
            return sys.ESP_FAIL;
        };

        body.deinit(self.allocator);
        if (opt) |*pack| {
            defer pack.deinit();

            var r = CommandRunner{
                .controller = self.controller,
                .stack = .init(self.allocator),
            };
            defer r.deinit();

            self.controller.setHeartbeat(false);
            r.runCommandPack(pack);
            self.controller.setHeartbeat(true);
        }
        self.sendStructAsJson(req, null, "complete!");
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

fn sendError(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime prefix: []const u8,
    err: anyerror,
) void {
    var buf: [256:0]u8 = undefined;
    const msg = std.fmt.bufPrintSentinel(
        &buf,
        prefix ++ ": {s}",
        .{@errorName(err)},
        0,
    ) catch prefix ++ ": error";

    self.sendJsonError(req, 500, msg);
}

fn sendJsonError(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    msg: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, code, "", false, msg) catch |e| {
        self.sendError(req, "send-json-error-failed", e);
    };
}

fn sendStringAsJson(
    self: *Self,
    req: [*c]mod.http.Req,
    value: ?[]const u8,
    message: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, 200, value, true, message) catch |e| {
        self.sendError(req, "send-json-error-failed", e);
    };
}

fn sendStructAsJson(
    self: *Self,
    req: [*c]mod.http.Req,
    value: ?[]const u8,
    message: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, 200, value, false, message) catch |e| {
        self.sendError(req, "send-json-error-failed", e);
    };
}

fn sendStructAsJsonInner(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    value: ?[]const u8,
    has_quote: bool,
    message: ?[]const u8,
) !void {
    const json = try std.fmt.allocPrintSentinel(
        self.allocator,
        "{{\"code\":{d},\"msg\":\"{s}\",\"data\":{s}{s}{s}}}",
        .{
            code,
            message orelse "",
            if (has_quote) "\"" else "",
            value orelse "null",
            if (has_quote) "\"" else "",
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
