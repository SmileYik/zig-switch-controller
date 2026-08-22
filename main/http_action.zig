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

const POSTS = .{
    .{ "/cmd/queue", &postCommandEnqueue },
    .{ "/cmd/run", &postCommandRunSync },
    .{ "/cmd/run/raw", &postCommandRunSyncRaw },
    .{ "/cmd/test", &postCommandTest },
    .{ "/cfg/wifi", &postWifiConfig },
};

const Self = @This();

allocator: std.mem.Allocator,
heap: *idf.heap.HeapCapsAllocator,
controller: *mod.controller.Controller,
queue: Queue,
queue_capacity: u8 = QUEUE_CAPACITY,

uris: [5]mod.http.Uri = [_]mod.http.Uri{
    .{
        .uri = "/api",
        .method = sys.HTTP_OPTIONS,
        .handler = &handleApiOptions,
        .user_ctx = null,
    },
    .{
        .uri = "/api",
        .method = sys.HTTP_POST,
        .handler = &handleApiPost,
        .user_ctx = null,
    },
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
        .uri = "/api/command/queue",
        .method = sys.HTTP_GET,
        .handler = &getCommandQueueStatus,
        .user_ctx = null,
    },
},

pub fn init(
    allocator: std.mem.Allocator,
    controller: *mod.controller.Controller,
    heap: *idf.heap.HeapCapsAllocator,
) !Self {
    return .{
        .allocator = allocator,
        .controller = controller,
        .queue = try .init(.{ .allocator = allocator }),
        .heap = heap,
    };
}

pub fn getUris(self: *Self) []const mod.http.Uri {
    for (&self.uris) |*uri| {
        uri.user_ctx = self;
    }
    return self.uris[0..];
}

pub fn logMemory(self: *Self) void {
    log.info("--- memory: {d}/{d}", .{ self.heap.freeSize(), self.heap.totalSize() });
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

export fn handleApiOptions(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Headers", "*") catch {};
    idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Origin", "*") catch {};
    idf.http.Server.Response.sendStr(req, "") catch {};
    return sys.ESP_OK;
}

export fn handleApiPost(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    var self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));
    self.logMemory();
    defer self.logMemory();

    var query: [64:0]u8 = undefined;
    var mode: [16:0]u8 = undefined;
    @memset(&query, 0);
    @memset(&mode, 0);

    idf.http.Server.Request.getUrlQueryStr(req, &query, query.len) catch {};
    idf.http.Server.queryKeyValue(&query, "mode", &mode, mode.len) catch {};

    inline for (POSTS) |post| {
        if (std.mem.eql(u8, std.mem.sliceTo(&mode, 0), post[0])) {
            post[1](self, req) catch |err| {
                self.sendJsonError(req, 500, @errorName(err));
            };
            return sys.ESP_OK;
        }
    }

    idf.http.Server.Response.sendError(req, 6, "") catch {};
    return sys.ESP_OK;
}

/// GET /api/config/wifi
export fn getWifiConfig(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));
    self.logMemory();
    defer self.logMemory();

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
fn postWifiConfig(self: *Self, req: [*c]mod.http.Req) !void {
    self.logMemory();
    defer self.logMemory();

    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (try self.readBody(&body_buffer, req)) |body| {
        var parsed = std.json.parseFromSlice(
            mod.Configuration.WifiConfig,
            self.allocator,
            body,
            .{ .ignore_unknown_fields = true },
        ) catch |e| {
            self.logError("parsed-body-failed", e);
            return error.ParseWifiConfigFailed;
        };
        defer parsed.deinit();

        mod.config.storeStruct(@tagName(mod.Configuration.Keys.wf), parsed.value) catch |e| {
            self.logError("store-wifi-config-failed", e);
            return error.StoreWifiConfigFailed;
        };
        self.sendStructAsJson(req, null, "configurate wifi success");
    }
    return error.RequestBodyIsNotValid;
}

/// POST /api/command/test
fn postCommandTest(self: *Self, req: [*c]mod.http.Req) !void {
    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (try self.readBody(&body_buffer, req)) |body| {
        mod.controller.command.runner.byteCodeTest(self.allocator, body) catch |e| {
            self.logError("test-failed", e);
            return error.TestFailed;
        };
        self.sendStructAsJson(req, null, "complete test!");
    }
    return error.RequestBodyIsNotValid;
}

/// POST /api/command/run/sync/raw
fn postCommandRunSyncRaw(self: *Self, req: [*c]mod.http.Req) !void {
    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (try self.readBody(&body_buffer, req)) |body| {
        var opt = mod.controller.command.parser.parseCommand(self.allocator, body) catch |e| {
            self.logError("parse-script-failed", e);
            return error.ParseMacroFailed;
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
    }
    return error.RequestBodyIsNotValid;
}

/// POST /api/command/run/sync
fn postCommandRunSync(self: *Self, req: [*c]mod.http.Req) !void {
    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (try self.readBody(&body_buffer, req)) |body| {
        var r = CommandRunner{
            .controller = self.controller,
            .stack = .{},
        };
        defer r.deinit();

        self.controller.setHeartbeat(false);
        defer self.controller.setHeartbeat(true);
        r.runByteCode(body) catch |e| {
            self.logError("run-bytecode-failed", e);
            return error.RunBytecodeFailed;
        };

        self.sendStructAsJson(req, null, "complete test!");
    }
    return error.RequestBodyIsNotValid;
}

/// get /api/command/queue
export fn getCommandQueueStatus(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));
    self.logMemory();
    defer self.logMemory();

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
fn postCommandEnqueue(self: *Self, req: [*c]mod.http.Req) !void {
    var body_buffer: [MAX_BODY_SIZE]u8 = undefined;
    if (try self.readBody(&body_buffer, req)) |body| {
        if (QUEUE_CAPACITY - self.queue.spacesAvailable() >= self.queue_capacity) {
            self.sendJsonError(req, 500, "full");
            return error.Full;
        }

        var buf = self.allocator.alloc(u8, body.len) catch {
            self.sendJsonError(req, 500, "alloc-bytecode-size-buffer-failed");
            return error.AllocFail;
        };
        errdefer self.allocator.free(buf);
        @memcpy(buf[0..], body);

        self.queue.enqueue(.{ .allocator = self.allocator, .bytes = buf }) catch |err|
            switch (err) {
                Queue.QueueError.Full => {
                    self.sendJsonError(req, 500, "full");
                    return error.Full;
                },
                else => {
                    self.sendJsonError(req, 500, "enqueue-error");
                    return error.EnqueueError;
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
            self.logError("msg buf too small", e);
            return error.MsgBufTooSmall;
        };
        self.sendStructAsJson(req, msg, "enqueued!");
    }
    return error.RequestBodyIsNotValid;
}

fn logError(
    _: *Self,
    comptime prefix: []const u8,
    err: anyerror,
) void {
    var buf: [128:0]u8 = undefined;
    const msg = std.fmt.bufPrintSentinel(
        &buf,
        prefix ++ ": {s}",
        .{@errorName(err)},
        0,
    ) catch prefix ++ ": error";

    log.err("error message: {s}, error: {s}", .{ msg, @errorName(err) });
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

    idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Origin", "*") catch {};
    idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Headers", "*") catch {};
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
    try idf.http.Server.Response.setHDR(req, "Access-Control-Allow-Headers", "*");
    try idf.http.Server.Response.setHDR(req, "content-type", "application/json");
    try idf.http.Server.Response.sendStr(req, json);
}

fn readBody(
    _: *Self,
    buffer: anytype,
    req: [*c]mod.http.Req,
) !?[]const u8 {
    var i: usize = 0;
    while (true) {
        const len = idf.http.Server.Request.receiver(req, (buffer[i..]).ptr, buffer.len - i);
        if (len > 0) {
            i += @as(usize, @intCast(len));
            if (i > buffer.len) {
                log.err("0. body too long, max body size is {d} bytes", .{MAX_BODY_SIZE});
                return error.RequestBodyTooLarge;
            } else if (i == buffer.len) {
                var test_buf: [1]u8 = undefined;
                while (true) {
                    const check_len = idf.http.Server.Request.receiver(req, &test_buf, test_buf.len);
                    if (check_len > 0) {
                        log.err("1. body too long, max body size is {d} bytes", .{MAX_BODY_SIZE});
                        return error.RequestBodyTooLarge;
                    } else if (check_len == sys.HTTPD_SOCK_ERR_TIMEOUT) {
                        continue;
                    } else break;
                }
            }
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
            log.info("start consuming bytecode!", .{});
            self.logMemory();
            defer self.logMemory();

            defer item.deinit();

            var bytecode = item.value;
            defer bytecode.deinit();

            self.controller.setHeartbeat(false);
            defer self.controller.setHeartbeat(true);

            r.runByteCodeUnsafe(bytecode.bytes) catch |e| {
                log.err("exception when consuming bytecode: {s}", .{@errorName(e)});
            };
        }
    }
}
