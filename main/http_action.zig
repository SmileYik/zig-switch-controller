const std = @import("std");
const mod = @import("root.zig");
const sys = mod.sys;
const idf = mod.idf;

const log = std.log.scoped(.http_action);

const Self = @This();

allocator: std.mem.Allocator,
uris: [2]mod.http.Uri = [_]mod.http.Uri{
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

    self.sendStructAsJson(req, loaded.config, null) catch |e| {
        self.sendError(req, "getWifiConfig", e);
    };
    return sys.ESP_OK;
}

/// POST /api/config/wifi
export fn postWifiConfig(req: [*c]mod.http.Req) callconv(.c) sys.esp_err_t {
    const self: *Self = @ptrCast(@alignCast(req.?.*.user_ctx.?));

    var loaded = mod.config.loadStruct(
        self.allocator,
        @tagName(mod.Configuration.Keys.wf),
        mod.Configuration.WifiConfig,
    ) catch
        mod.config.DefaultConfig(mod.Configuration.WifiConfig{});
    defer loaded.deinit();

    self.sendStructAsJson(req, loaded.config, null) catch |e| {
        self.sendError(req, "getWifiConfig", e);
    };
    return sys.ESP_OK;
}

fn Result(comptime T: type) type {
    return struct {
        code: u16 = 200,
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

fn sendStructAsJson(
    self: *Self,
    req: [*c]mod.http.Req,
    value: anytype,
    message: ?[]const u8,
) !void {
    const T = @TypeOf(value);
    const R = Result(T);
    const json = try std.fmt.allocPrintSentinel(
        self.allocator,
        "{f}",
        .{
            std.json.fmt(R{
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
