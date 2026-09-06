//! Native allocation demand for the same complete PKI2 path as the guest.
const std = @import("std");
const data = @import("boundary_data_v2");
const world = @import("world").process_v2;

pub fn main(init: std.process.Init) !void {
    var read_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &read_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .limited(64 << 20));
    defer init.gpa.free(bytes);
    const storage = try init.gpa.alloc(u8, 16 << 20);
    defer init.gpa.free(storage);
    var arena = world.Workspace.init(storage);
    const allocator = arena.allocator();
    const decoded = try data.protocol.decode(data.protocol.Input, allocator, bytes);
    var statistics: world.Statistics = .{};
    const invocation: world.Invocation = .{ .program = .{ .image = decoded.image }, .instance = switch (decoded.instance) {
        .initial_args => |value| .{ .initial_args = value },
        .state => |value| .{ .snapshot = value },
    }, .control = decoded.control, .statistics = &statistics };
    var outcome = try switch (decoded.mode) {
        .run => world.run(allocator, invocation),
        .advance => world.advance(allocator, invocation),
    };
    defer outcome.deinit();
    const encoded = try init.gpa.alloc(u8, try data.protocol.encodedLength(data.protocol.Outcome, outcome.record));
    defer init.gpa.free(encoded);
    _ = try data.protocol.encode(data.protocol.Outcome, allocator, outcome.record, encoded);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{
        .platform = @tagName(@import("builtin").cpu.arch),
        .pointer_bytes = @sizeOf(usize),
        .peak_working_payload_bytes = arena.peak_payload,
        .working_demand_lower_bound = arena.required,
        .working_reservation_bytes = storage.len,
        .outcome = @tagName(outcome.record),
        .output_bytes = encoded.len,
        .output_sha256 = std.fmt.bytesToHex(data.wire.digest(encoded), .lower),
        .statistics = statistics,
    }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
