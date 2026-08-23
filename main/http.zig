const std = @import("std");
const mod = @import("root.zig");
const idf = mod.idf;
const sys = idf.sys;

const http = @This();

pub const Uri = sys.httpd_uri_t;
pub const Req = sys.httpd_req_t;

running: std.atomic.Value(bool) = .init(false),
server: sys.httpd_handle_t,

pub fn init() http {
    return .{ .server = null };
}

pub fn start(self: *http) !void {
    self.running.store(true, .release);
    errdefer self.running.store(false, .release);

    var config = sys.zig_httpd_default_config();
    config.stack_size = 12280;
    config.recv_wait_timeout = 90;
    config.max_uri_handlers = 16;
    config.max_open_sockets = 4;
    config.max_uri_len = 64;

    self.server = try idf.http.Server.start(&config);
}

pub fn stop(self: *http) !void {
    if (self.running.load(.acquire)) {
        self.running.store(false, .release);
        errdefer self.running.store(true, .release);

        try idf.http.Server.stop(self.server);
    }
}

pub fn registerUris(self: *http, uris: []const Uri) !void {
    if (!self.running.load(.acquire)) {
        return error.ServerNotRunning;
    }
    for (uris) |*uri| {
        try idf.http.Server.registerUri(self.server, uri);
    }
}
