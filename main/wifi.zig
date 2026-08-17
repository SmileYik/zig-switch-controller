const std = @import("std");
const idf = @import("root.zig").idf;
const sys = idf.sys;

const log = std.log.scoped(.wifi);

const Auth = struct {
    ssid: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

pub const WifiManager = struct {
    const Self = @This();

    pub const CONNECTED_BIT: u32 = sys.WIFI_CONNECTED_BIT;
    pub const FAILED_BIT: u32 = sys.WIFI_FAIL_BIT;

    allocator: std.mem.Allocator,
    g_event_group: sys.EventGroupHandle_t = null,
    wifi_event_handler: idf.event.HandlerInstance = null,
    ip_event_handler: idf.event.HandlerInstance = null,
    ap_config: idf.wifi.wifiConfig = .{
        .ap = .{
            .ssid = std.mem.zeroes([32]u8),
            .password = std.mem.zeroes([64]u8),
            .ssid_len = 0,
            .channel = 1,
            .authmode = sys.WIFI_AUTH_OPEN,
            .ssid_hidden = 0,
            .max_connection = 4,
            .beacon_interval = 100,
            .pairwise_cipher = sys.WIFI_CIPHER_TYPE_CCMP,
            .ftm_responder = false,
            .pmf_cfg = .{ .capable = true, .required = false },
        },
    },

    sta_config: idf.wifi.wifiConfig = .{
        .sta = .{
            .ssid = std.mem.zeroes([32]u8),
            .password = std.mem.zeroes([64]u8),
            .threshold = .{ .rssi = 0, .rssi_5g_adjustment = 0, .authmode = sys.WIFI_AUTH_WPA2_PSK },
            .sae_pwe_h2e = sys.WPA3_SAE_PWE_BOTH,
            .sae_h2e_identifier = std.mem.zeroes([32]u8),
        },
    },

    pub fn init(
        allocator: std.mem.Allocator,
        ap_auth: *const Auth,
        sta_auth: *const Auth,
    ) !*WifiManager {
        const ptr = try allocator.create(WifiManager);
        errdefer allocator.destroy(ptr);

        const g_event_group = sys.xEventGroupCreate() orelse return error.EventGroupCreateFailed;
        ptr.* = WifiManager{
            .allocator = allocator,
            .g_event_group = g_event_group,
        };
        try ptr.initInner(ap_auth, sta_auth);
        return ptr;
    }

    pub fn initInner(self: *Self, ap_auth: *const Auth, sta_auth: *const Auth) !void {
        // 初始化网络接口
        try idf.err.espCheckError(sys.esp_netif_init());
        try idf.event.loopCreateDefault();

        _ = sys.esp_netif_create_default_wifi_sta();
        _ = sys.esp_netif_create_default_wifi_ap();

        // 初始化 Wi-Fi 驱动
        var wifi_init_cfg = idf.wifi.init_config_default();
        try idf.wifi.init(&wifi_init_cfg);

        // 注册事件回调
        self.wifi_event_handler = try idf.event.handlerInstanceRegister(sys.WIFI_EVENT, idf.event.ANY_ID, &onWifiEvent, self);
        errdefer idf.event.handlerInstanceUnregister(
            sys.WIFI_EVENT,
            idf.event.ANY_ID,
            self.wifi_event_handler,
        ) catch {
            log.err("failed to unregister wifi event", .{});
        };

        self.ip_event_handler = try idf.event.handlerInstanceRegister(sys.IP_EVENT, sys.IP_EVENT_STA_GOT_IP, &onIpEvent, self);
        errdefer idf.event.handlerInstanceUnregister(
            sys.IP_EVENT,
            sys.IP_EVENT_STA_GOT_IP,
            self.ip_event_handler,
        ) catch {
            log.err("failed to unregister ip event", .{});
        };

        // 设置为 APSTA 模式
        try idf.wifi.setMode(.WIFI_MODE_APSTA);
        try self.setAuth(.WIFI_MODE_AP, ap_auth);
        try self.setAuth(.WIFI_MODE_STA, sta_auth);
        try idf.wifi.start();

        log.debug(
            "WiFi APSTA Manager initialized. AP: \"{s}\", Target STA: \"{s}\"",
            .{
                ap_auth.ssid orelse "none",
                sta_auth.ssid orelse "none",
            },
        );
    }

    pub fn deinit(self: *Self) void {
        if (self.g_event_group) |a| a.vEventGroupDelete();
        if (self.ip_event_handler != null)
            idf.event.handlerInstanceUnregister(
                sys.WIFI_EVENT,
                idf.event.ANY_ID,
                self.wifi_event_handler,
            ) catch {
                log.err("failed to unregister wifi event", .{});
            };

        if (self.ip_event_handler != null)
            idf.event.handlerInstanceUnregister(
                sys.IP_EVENT,
                sys.IP_EVENT_STA_GOT_IP,
                self.ip_event_handler,
            ) catch {
                log.err("failed to unregister ip event", .{});
            };

        self.stopWifi() catch {
            log.err("failed to stop wifi", .{});
        };
        idf.wifi.deinit() catch {
            log.err("failed to deinit wifi", .{});
        };
    }

    pub fn waitForConnect(self: *Self, ms: u32) bool {
        if (self.g_event_group == null) return false;
        const bits = sys.xEventGroupWaitBits(
            self.g_event_group,
            CONNECTED_BIT,
            0,
            0,
            idf.rtos.msToTicks(ms),
        );
        return (bits & CONNECTED_BIT) != 0;
    }

    pub fn stopWifi(_: *Self) !void {
        try idf.wifi.stop();
    }

    pub fn startWifi(_: *Self) !void {
        try idf.wifi.start();
    }

    pub fn applyAuth(self: *Self, mode: idf.wifi.wifi_mode_t, auth: *const Auth) !void {
        try self.stopWifi();
        defer self.startWifi() catch {
            log.err("failed to start wifi after apply auth change", .{});
        };
        self.setAuth(mode, auth);
    }

    pub fn setAuth(self: *Self, mode: idf.wifi.wifi_mode_t, auth: *const Auth) !void {
        switch (mode) {
            .WIFI_MODE_AP => {
                if (auth.ssid) |ssid| {
                    copyZ(&self.ap_config.ap.ssid, ssid[0..]);
                }
                if (auth.password) |password| {
                    copyZ(&self.ap_config.ap.password, password[0..]);
                    self.ap_config.ap.authmode = if (password.len < 8)
                        sys.WIFI_AUTH_OPEN
                    else
                        sys.WIFI_AUTH_WPA2_PSK;
                }
                try idf.wifi.setConfig(.WIFI_IF_AP, &self.ap_config);
            },
            .WIFI_MODE_STA => {
                if (auth.ssid) |ssid| {
                    copyZ(&self.sta_config.sta.ssid, ssid[0..]);
                }
                if (auth.password) |password| {
                    if (password.len >= 8)
                        copyZ(&self.sta_config.sta.password, password[0..]);
                }
                try idf.wifi.setConfig(.WIFI_IF_STA, &self.sta_config);
            },
            else => {
                log.debug("not support mode: {s}", .{@tagName(mode)});
            },
        }
    }

    export fn onWifiEvent(ctx: ?*anyopaque, _: sys.esp_event_base_t, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(ctx.?));
        _ = self;

        switch (event_id) {
            sys.WIFI_EVENT_STA_START => {
                log.debug("STA started, initiating connection...", .{});
                idf.wifi.connect() catch |err| log.err("connect() failed: {s}", .{@errorName(err)});
            },
            sys.WIFI_EVENT_STA_DISCONNECTED => {
                idf.wifi.connect() catch |err| log.err("connect() failed: {s}", .{@errorName(err)});
            },
            sys.WIFI_EVENT_AP_STACONNECTED => {
                if (event_data) |data| {
                    const ev = @as(*sys.wifi_event_ap_staconnected_t, @ptrCast(@alignCast(data)));
                    log.debug("Client connected to AP, MAC: {x}:{x}:{x}:{x}:{x}:{x}", .{
                        ev.mac[0], ev.mac[1], ev.mac[2], ev.mac[3], ev.mac[4], ev.mac[5],
                    });
                }
            },
            sys.WIFI_EVENT_AP_STADISCONNECTED => {
                if (event_data) |data| {
                    const ev = @as(*sys.wifi_event_ap_stadisconnected_t, @ptrCast(@alignCast(data)));
                    log.debug("Client left AP, MAC: {x}:{x}:{x}:{x}:{x}:{x}", .{
                        ev.mac[0], ev.mac[1], ev.mac[2], ev.mac[3], ev.mac[4], ev.mac[5],
                    });
                }
            },
            else => {},
        }
    }

    export fn onIpEvent(ctx: ?*anyopaque, _: sys.esp_event_base_t, event_id: i32, event_data: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(ctx.?));

        if (event_id == sys.IP_EVENT_STA_GOT_IP) {
            const ev = @as(*sys.ip_event_got_ip_t, @ptrCast(@alignCast(event_data)));
            const ip = ev.ip_info.ip.addr;
            log.debug("STA Got IP: {}.{}.{}.{}", .{
                @as(u8, @truncate(ip)),
                @as(u8, @truncate(ip >> 8)),
                @as(u8, @truncate(ip >> 16)),
                @as(u8, @truncate(ip >> 24)),
            });
            _ = sys.xEventGroupSetBits(self.g_event_group, CONNECTED_BIT);
        }
    }
};

fn copyZ(dest: []u8, src: []const u8) void {
    const n = @min(dest.len - 1, src.len);
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
}
