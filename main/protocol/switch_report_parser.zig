const protocol = @import("root.zig");

const SwitchReportParser = @This();

pub const Options = struct {
    data_len: u8,
    payload_len: u8 = 10,
    magic_head: ?u8 = null,
};

data_len: u8,
payload_len: u8,
magic_head: ?u8,

pub inline fn init(opt: SwitchReportParser.Options) SwitchReportParser {
    return .{
        .data_len = opt.data_len,
        .payload_len = opt.payload_len,
        .magic_head = opt.magic_head,
    };
}

pub inline fn parse(self: *const SwitchReportParser, data: []const u8) protocol.Report {
    if (data.len == 0) {
        return .{ .response = .no_data };
    } else if (data.len < self.data_len) {
        return .{ .response = .too_short };
    } else if (self.magic_head) |magic_head| {
        if (data[0] != magic_head) {
            return .{ .response = .malformed };
        }
    }

    const payload = data[0..@min(self.payload_len, data.len)];
    const subcommand = if (data.len > self.payload_len) data[self.payload_len..] else &[_]u8{};
    const subcommand_id = if (subcommand.len > 0) subcommand[0] else 0;

    const response: protocol.Constants.SwitchResponse = @enumFromInt(subcommand_id);

    return .{
        .response = response,
        .subcommand_id = subcommand_id,
        .payload = payload,
        .subcommand = subcommand,
    };
}
