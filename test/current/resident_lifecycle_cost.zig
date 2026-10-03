//! Complete native Resident lifecycles. Instrumented and latency runs are separate.
const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
const Hash = std.crypto.hash.sha2.Sha256;
const Record = struct {
    mode: enum { H, Q, R },
    depth: u64 = 0,
    imageSha256: []const u8,
    replies: []const []const u8 = &.{},
    input: ?[]const u8 = null,
    quantum: u64 = 1,
    expected: u64 = 0,
};
const Inputs = struct { image: []const u8, arguments: []const u8, record: Record, replies: []const []const u8, final: ?[]const u8 };
const Measurement = struct { totalNs: i96, preparationNs: i96, executionNs: i96, digest: [32]u8, preparedLive: usize, pauseLive: usize };

fn drive(comptime instrument: bool, allocator: std.mem.Allocator, resident: *world.Resident, control: data.invocation.Control, quantum: ?u64, tag: u8, hash: *Hash, expected: ?[]const u8) !void {
    const output = try resident.driveEncoded(allocator, control, .{ .quantum = quantum });
    defer allocator.free(output);
    if (output.len < 21 or output[20] != tag) return error.UnexpectedOutcome;
    if (expected) |bytes| if (!std.mem.eql(u8, output, bytes)) return error.WrongValue;
    if (instrument) hash.update(output);
}

fn run(comptime instrument: bool, io: std.Io, allocator: std.mem.Allocator, input: Inputs, workspace: ?*world.Workspace) !Measurement {
    var digest = Hash.init(.{});
    const start = std.Io.Clock.awake.now(io);
    var prepared = try world.Prepared.init(allocator, input.image);
    const prepared_live = if (workspace) |w| w.live_payload else 0;
    const preparation_end = std.Io.Clock.awake.now(io);
    var resident = try world.Resident.start(allocator, &prepared, input.arguments);
    var paused_live: usize = 0;
    switch (input.record.mode) {
        .H => {
            try drive(instrument, allocator, &resident, .none, null, 2, &digest, null);
            for (0..64) |i| try drive(instrument, allocator, &resident, if (i == 0) .resume_yield else .none, 1, 0, &digest, null);
            paused_live = if (workspace) |w| w.live_payload else 0;
            const checkpoint = try resident.checkpoint(allocator);
            if (instrument) digest.update(checkpoint);
            allocator.free(checkpoint);
        },
        .Q => {
            try drive(instrument, allocator, &resident, .none, null, 1, &digest, null);
            const errors = [_]anyerror{ error.Truncated, error.InvalidResult, error.InvalidValue };
            for (input.replies[0..3], errors) |reply, expected_error| {
                if (resident.driveEncoded(allocator, .{ .reply = reply }, .{ .quantum = 0 })) |output| {
                    allocator.free(output);
                    return error.AcceptedInvalidReply;
                } else |err| {
                    if (err != expected_error) return err;
                    if (instrument) digest.update(@errorName(err));
                }
            }
            paused_live = if (workspace) |w| w.live_payload else 0;
            try drive(instrument, allocator, &resident, .{ .reply = input.replies[3] }, 0, 0, &digest, null);
        },
        .R => {
            try drive(instrument, allocator, &resident, .none, input.record.quantum, 0, &digest, null);
            paused_live = if (workspace) |w| w.live_payload else 0;
            try drive(instrument, allocator, &resident, .none, null, 3, &digest, input.final);
        },
    }
    if (input.record.mode != .R)
        try drive(instrument, allocator, &resident, .{ .cancel = .{ .text = "retained lifecycle complete" } }, null, 5, &digest, null);
    try resident.close();
    prepared.deinit();
    const end = std.Io.Clock.awake.now(io);
    return .{ .totalNs = start.durationTo(end).nanoseconds, .preparationNs = start.durationTo(preparation_end).nanoseconds, .executionNs = preparation_end.durationTo(end).nanoseconds, .digest = digest.finalResult(), .preparedLive = prepared_live, .pauseLive = paused_live };
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const image_path = args.next() orelse return error.Image;
    const record_path = args.next() orelse return error.Record;
    if (args.next() != null) return error.Arguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, image_path, a, .limited(64 << 20));
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, record_path, a, .limited(64 << 20));
    const parsed = try std.json.parseFromSlice(Record, a, text, .{ .ignore_unknown_fields = true });
    const record = parsed.value;
    var expected_image: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_image, record.imageSha256);
    if (!std.mem.eql(u8, &expected_image, &data.wire.digest(image))) return error.ImageIdentity;
    const replies = try a.alloc([]const u8, record.replies.len);
    for (replies, record.replies) |*reply, hex| reply.* = try std.fmt.hexToBytes(try a.alloc(u8, hex.len / 2), hex);
    var arguments: [16]u8 = undefined;
    std.mem.writeInt(u64, arguments[0..8], record.depth, .little);
    std.mem.writeInt(u64, arguments[8..16], 17, .little);
    var expected_value: [8]u8 = undefined;
    std.mem.writeInt(u64, &expected_value, record.expected, .little);
    const input: Inputs = .{
        .image = image,
        .record = record,
        .arguments = if (record.input) |hex| try std.fmt.hexToBytes(try a.alloc(u8, hex.len / 2), hex) else &arguments,
        .replies = replies,
        .final = if (record.mode == .R) try data.invocation.encodeOwned(data.invocation.Outcome, a, .{ .completed = &expected_value }) else null,
    };
    const backing = try a.alloc(u8, 128 << 20);
    var workspace = world.Workspace.init(backing);
    const memory = try run(true, init.io, workspace.allocator(), input, &workspace);
    if (workspace.live_payload != 0) return error.Leak;
    var samples: [9]struct { totalNs: i96, preparationNs: i96, executionNs: i96 } = undefined;
    for (0..12) |iteration| {
        const observation = try run(false, init.io, init.gpa, input, null);
        if (iteration >= 3) samples[iteration - 3] = .{ .totalNs = observation.totalNs, .preparationNs = observation.preparationNs, .executionNs = observation.executionNs };
    }
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .mode = record.mode, .depth = record.depth, .imageSha256 = record.imageSha256, .samples = samples, .peakBytes = workspace.peak_payload, .preparedLive = memory.preparedLive, .pauseLive = memory.pauseLive, .reservedBytes = backing.len, .outcomeDigest = memory.digest }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
