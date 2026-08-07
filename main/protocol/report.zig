const mod = @import("root.zig");

response: mod.Constants.SwitchResponse,
subcommand_id: u8 = 0,
payload: []const u8 = &[_]u8{},
subcommand: []const u8 = &[_]u8{},
