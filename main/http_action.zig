const std = @import("std");
const mod = @import("root.zig");
const sys = mod.sys;
const idf = mod.idf;

const runner = mod.controller.command.runner;
const CommandRunner = runner.CommandRunner(runner.CallStackStatic(8));

const MAX_BODY_SIZE = 4096;
const QUEUE_CAPACITY = 16;
const Queue = mod.Queue(ByteCode, QUEUE_CAPACITY);

const log = std.log.scoped(.http_action);

const ByteCode = struct {
    bytes: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ByteCode) void {
        self.allocator.free(self.bytes);
    }
};

const Self = @This();

allocator: std.mem.Allocator,
controller: *mod.controller.Controller,
queue: Queue,
queue_capacity: u8 = QUEUE_CAPACITY,

uris: [8]mod.http.Uri = [_]mod.http.Uri{
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
        .uri = "/api/command/test",
        .method = sys.HTTP_POST,
        .handler = &postCommandTest,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/run/sync",
        .method = sys.HTTP_POST,
        .handler = &postCommandRunSync,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/run/sync/raw",
        .method = sys.HTTP_POST,
        .handler = &postCommandRunSyncRaw,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/queue",
        .method = sys.HTTP_GET,
        .handler = &getCommandQueueStatus,
        .user_ctx = null,
    },
    .{
        .uri = "/api/command/queue",
        .method = sys.HTTP_POST,
        .handler = &postCommandEnqueue,
        .user_ctx = null,
    },
},

pub fn init(
    allocator: std.mem.Allocator,
    controller: *mod.controller.Controller,
) !Self {
    return .{
        .allocator = allocator,
        .controller = controller,
        .queue = try .init(.{ .allocator = allocator }),
    };
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

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, template, .{
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

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (self.readBody(&body_buffer, req)) |body| {
        var parsed = std.json.parseFromSlice(
            mod.Configuration.WifiConfig,
            self.allocator,
            body,
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

/// POST /api/command/test
export fn postCommandTest(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (self.readBody(&body_buffer, req)) |body| {
        mod.controller.command.runner.byteCodeTest(self.allocator, body) catch |e| {
            self.sendError(req, "test-failed", e);
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

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (self.readBody(&body_buffer, req)) |body| {
        var opt = mod.controller.command.parser.parseCommand(self.allocator, body) catch |e| {
            self.sendError(req, "parse-script-failed", e);
            return sys.ESP_FAIL;
        };

        if (opt) |*pack| {
            defer pack.deinit();

            var r = CommandRunner{
                .controller = self.controller,
                .stack = .{},
            };
            defer r.deinit();

            self.controller.setHeartbeat(false);
            defer self.controller.setHeartbeat(true);
            r.runCommandPack(pack);
        }
        self.sendStructAsJson(req, null, "complete!");
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

/// POST /api/command/run/sync
export fn postCommandRunSync(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (self.readBody(&body_buffer, req)) |body| {
        var r = CommandRunner{
            .controller = self.controller,
            .stack = .{},
        };
        defer r.deinit();

        self.controller.setHeartbeat(false);
        defer self.controller.setHeartbeat(true);
        r.runByteCode(body) catch |e| {
            self.sendError(req, "run-bytecode-failed", e);
            return sys.ESP_FAIL;
        };

        self.sendStructAsJson(req, null, "complete test!");
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

/// get /api/command/queue
export fn getCommandQueueStatus(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));
    const total = self.queue_capacity;
    const space = self.queue.spacesAvailable();

    var buf: [128]u8 = undefined;
    const template =
        \\{{"total":{d},"available":{d}}}
    ;
    const msg = std.fmt.bufPrint(&buf, template, .{ total, space }) catch |e| {
        self.sendError(req, "parsed-wifi-config-failed", e);
        return sys.ESP_FAIL;
    };
    self.sendStructAsJson(req, msg, null);

    return sys.ESP_OK;
}

/// POST /api/command/queue
export fn postCommandEnqueue(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (self.readBody(&body_buffer, req)) |body| {
        if (QUEUE_CAPACITY - self.queue.spacesAvailable() >= self.queue_capacity) {
            self.sendJsonError(req, 500, "full");
            return sys.ESP_FAIL;
        }

        var buf = self.allocator.alloc(u8, body.len) catch {
            self.sendJsonError(req, 500, "alloc-bytecode-size-buffer-failed");
            return sys.ESP_FAIL;
        };
        errdefer self.allocator.free(buf);
        @memcpy(buf[0..], body);

        self.queue.enqueue(.{ .allocator = self.allocator, .bytes = buf }) catch |err|
            switch (err) {
                Queue.QueueError.Full => {
                    self.allocator.free(buf);
                    self.sendJsonError(req, 500, "full");
                    return sys.ESP_FAIL;
                },
                else => {
                    self.allocator.free(buf);
                    self.sendJsonError(req, 500, "enqueue-error");
                    return sys.ESP_FAIL;
                },
            };

        var msg_buf = body_buffer;
        const template =
            \\{{"total":{d},"available":{d}}}
        ;
        const msg = std.fmt.bufPrint(&msg_buf, template, .{
            self.queue_capacity,
            self.queue.spacesAvailable(),
        }) catch |e| {
            self.sendError(req, "msg buf too small", e);
            return sys.ESP_FAIL;
        };
        self.sendStructAsJson(req, msg, "enqueued!");
    } else {
        self.sendJsonError(req, 500, "not a valid payload");
    }
    return sys.ESP_OK;
}

fn sendError(
    _: *Self,
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

    idf.http.Server.Response.sendStr(req, msg) catch |e| {
        log.err("error message: {s}, sendStr: {s}", .{ msg, @errorName(e) });
    };
}

fn sendJsonError(
    self: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    msg: ?[]const u8,
) void {
    self.sendStructAsJsonInner(req, code, null, false, msg) catch |e| {
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
    _: *Self,
    req: [*c]mod.http.Req,
    comptime code: u16,
    value: ?[]const u8,
    has_quote: bool,
    message: ?[]const u8,
) !void {
    var buf: [1024:0]u8 = undefined;
    const json = try std.fmt.bufPrintSentinel(
        &buf,
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

    try idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Origin", "*");
    try idf.http.Server.Response.setHDR(req, "content-type", "application/json");
    try idf.http.Server.Response.sendStr(req, json);
}

fn readBody(
    _: *Self,
    buffer: anytype,
    req: [*c]mod.http.Req,
) ?[]const u8 {
    var buf: [1024]u8 = undefined;

    var i: usize = 0;
    while (true) {
        const len = idf.http.Server.Request.receiver(req, &buf, buf.len);
        if (len > 0) {
            if (i + @as(usize, @intCast(len)) > buffer.len) {
                log.err("body too long", .{});
                return null;
            }
            @memcpy(buffer[i .. i + @as(usize, @intCast(len))], buf[0..@as(usize, @intCast(len))]);
            i += @as(usize, @intCast(len));
        } else if (len == sys.HTTPD_SOCK_ERR_TIMEOUT)
            continue
        else
            break;
    }
    return if (i > 0) buffer[0..i] else null;
}

fn readBodyAlloc(
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

pub fn startConsume(self: *Self) !void {
    _ = try mod.idf.rtos.Task.create(
        consumeByteCode,
        "consume_bytecode",
        1024 * 4,
        self,
        5,
    );
}

export fn consumeByteCode(ctx: ?*anyopaque) callconv(.c) void {
    var self: *Self = @ptrCast(@alignCast(ctx.?));

    var r = CommandRunner{
        .controller = self.controller,
        .stack = .{},
    };
    defer r.deinit();

    while (true) {
        while (self.queue.pollWait(std.math.maxInt(u32))) |*item| {
            defer item.deinit();

            var bytecode = item.value;
            defer bytecode.deinit();

            log.info("start consuming bytecode!", .{});

            self.controller.setHeartbeat(false);
            defer self.controller.setHeartbeat(true);

            r.runByteCodeUnsafe(bytecode.bytes) catch |e| {
                log.err("exception when consuming bytecode: {s}", .{@errorName(e)});
            };
        }
    }
}
