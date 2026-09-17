const std = @import("std");
const data = @import("data");
const world = @import("world");
const current = @hasDecl(world, "Session");
const runtime = if (current) world else world.process_v2;
const protocol = if (current) data.invocation else data.protocol;
fn invoke(a: std.mem.Allocator, input: []const u8, output: []u8) ![]const u8 {
    if (current) return world.invocation.invokeInto(a, input, output);
    const decoded = try protocol.decode(protocol.Input, a, input);
    var result = try runtime.invoke(a, decoded);
    defer result.deinit();
    return protocol.encode(protocol.Outcome, a, result.record, output);
}
pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    var expected: [32]u8 = undefined;
    const hex = args.next() orelse return error.ExpectedDigest;
    if (hex.len != 64) return error.InvalidDigest;
    _ = try std.fmt.hexToBytes(&expected, hex);
    var ib: [4096]u8 = undefined;
    var in = std.Io.File.stdin().reader(init.io, &ib);
    const input = try in.interface.allocRemaining(init.gpa, .limited(64 << 20));
    defer init.gpa.free(input);
    const storage = try init.gpa.alloc(u8, 256 << 20);
    defer init.gpa.free(storage);
    const output = try init.gpa.alloc(u8, 8 << 20);
    defer init.gpa.free(output);
    var samples: [9]u64 = undefined;
    for (0..12) |i| {
        const start = std.Io.Clock.awake.now(init.io);
        var arena = runtime.Workspace.init(storage);
        const result = try invoke(arena.allocator(), input, output);
        const elapsed: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
        if (!std.mem.eql(u8, &data.wire.digest(result), &expected)) return error.OutcomeMismatch;
        if (i >= 3) samples[i - 3] = elapsed;
    }
    var arena = runtime.Workspace.init(storage);
    var tracked = std.testing.FailingAllocator.init(arena.allocator(), .{});
    const result = try invoke(tracked.allocator(), input, output);
    if (!std.mem.eql(u8, &data.wire.digest(result), &expected)) return error.OutcomeMismatch;
    var ob: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &ob);
    try std.json.Stringify.value(.{ .inputBytes = input.len, .inputSha256 = std.fmt.bytesToHex(data.wire.digest(input), .lower), .outputBytes = result.len, .outputSha256 = hex, .samplesNs = samples, .peakWorkingBytes = arena.peak_payload, .allocationCalls = tracked.allocations, .allocatedBytes = tracked.allocated_bytes }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
