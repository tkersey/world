// Common before/after probe. Allocation instrumentation is separate from timing.
const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const image_path = args.next() orelse return error.Image;
    const input_path = args.next() orelse return error.Input;
    const quantum = try std.fmt.parseInt(u64, args.next() orelse return error.Quantum, 10);
    const expected = try std.fmt.parseInt(u64, args.next() orelse return error.Expected, 10);
    if (args.next() != null) return error.Arguments;
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, image_path, init.gpa, .limited(64 << 20));
    defer init.gpa.free(image);
    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(128 << 20));
    defer init.gpa.free(input);
    var prepared = try world.Prepared.init(init.gpa, image);
    defer prepared.deinit();
    var counting = std.testing.FailingAllocator.init(init.gpa, .{});
    var resident = try world.Resident.start(counting.allocator(), &prepared, input);
    const start_live = counting.allocated_bytes - counting.freed_bytes;
    const start_allocations = counting.allocations;
    const start_bytes = counting.allocated_bytes;
    var paused = try resident.drive(init.gpa, .none, .{ .quantum = quantum });
    defer paused.deinit();
    const pause_live = counting.allocated_bytes - counting.freed_bytes;
    const pause_allocations = counting.allocations - start_allocations;
    const pause_bytes = counting.allocated_bytes - start_bytes;
    var result = try resident.drive(init.gpa, .none, .{});
    defer result.deinit();
    if (result.record != .completed or std.mem.readInt(u64, result.record.completed[0..8], .little) != expected) return error.WrongResult;
    const run_allocations = counting.allocations - start_allocations;
    const run_bytes = counting.allocated_bytes - start_bytes;
    try resident.close();
    if (counting.allocated_bytes != counting.freed_bytes) return error.Leak;
    var samples: [9]f64 = undefined;
    for (0..12) |sample| {
        var session = try world.Resident.start(init.gpa, &prepared, input);
        const start = std.Io.Clock.awake.now(init.io);
        var out = try session.drive(init.gpa, .none, .{ .quantum = quantum });
        const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds;
        out.deinit();
        if (sample >= 3) samples[sample - 3] = @floatFromInt(elapsed);
        var final = try session.drive(init.gpa, .none, .{});
        defer final.deinit();
        if (final.record != .completed or std.mem.readInt(u64, final.record.completed[0..8], .little) != expected) return error.WrongResult;
        try session.close();
    }
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .imageDigest = data.wire.digest(image), .startLive = start_live, .pauseLive = pause_live, .pauseAllocations = pause_allocations, .pauseAllocatedBytes = pause_bytes, .runAllocations = run_allocations, .runAllocatedBytes = run_bytes, .samplesNs = samples }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
