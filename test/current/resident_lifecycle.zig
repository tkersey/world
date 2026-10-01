// Native counterpart of the frozen public H/Q lifecycle schedule.
const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
const Replies = struct { invalid: [3][]const u8, valid: []const u8 };

fn cycle(a: std.mem.Allocator, image: []const u8, pending: bool, depth: u64, replies: Replies) !void {
    var prepared = try world.Prepared.init(a, image);
    defer prepared.deinit();
    var input: [8]u8 = undefined;
    std.mem.writeInt(u64, &input, depth, .little);
    var resident = try world.Resident.start(a, &prepared, &input);
    var first = try resident.drive(a, .none, .{});
    if ((pending and first.record != .requested) or (!pending and first.record != .yielded)) return error.WrongPause;
    first.deinit();
    if (!pending) {
        var resumed = try resident.drive(a, .resume_yield, .{ .quantum = 0 });
        resumed.deinit();
        for (0..64) |_| {
            var out = try resident.drive(a, .none, .{ .quantum = 1 });
            if (out.record != .progressed) return error.WrongProgress;
            out.deinit();
        }
        const checkpoint = try resident.takeCheckpoint(a);
        defer a.free(checkpoint);
        resident = try world.Resident.restore(a, &prepared, checkpoint);
    } else {
        for (replies.invalid, [_]anyerror{ error.InvalidResult, error.Truncated, error.InvalidValue }) |reply, expected| {
            if (resident.drive(a, .{ .reply = reply }, .{ .quantum = 0 })) |result| {
                var out = result;
                out.deinit();
                return error.AcceptedInvalidReply;
            } else |err| if (err != expected) return err;
        }
        var out = try resident.drive(a, .{ .reply = replies.valid }, .{ .quantum = 0 });
        if (out.record != .progressed) return error.WrongProgress;
        out.deinit();
    }
    var cancelled = try resident.drive(a, .{ .cancel = .{ .text = "lifecycle-complete" } }, .{});
    if (cancelled.record != .cancelled) return error.WrongCancellation;
    cancelled.deinit();
    try resident.close();
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const family = args.next() orelse return error.Family;
    const corpus = args.next() orelse return error.Corpus;
    const depth = try std.fmt.parseInt(u64, args.next() orelse return error.Depth, 10);
    const pending = std.mem.eql(u8, family, "Q");
    if ((!pending and !std.mem.eql(u8, family, "H")) or args.next() != null) return error.Arguments;
    var files = std.heap.ArenaAllocator.init(init.gpa);
    defer files.deinit();
    const f = files.allocator();
    const image_path = try std.fmt.allocPrint(f, "{s}/{s}.bpi3", .{ corpus, family });
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, image_path, f, .limited(16 << 20));
    var replies: Replies = .{ .invalid = .{ &.{}, &.{}, &.{} }, .valid = &.{} };
    if (pending) {
        for (&replies.invalid, 0..) |*value, index| {
            const path = try std.fmt.allocPrint(f, "{s}/Q-{d}-invalid-{d}.ers3", .{ corpus, depth, index });
            value.* = try std.Io.Dir.cwd().readFileAlloc(init.io, path, f, .limited(16 << 20));
        }
        const path = try std.fmt.allocPrint(f, "{s}/Q-{d}-valid.ers3", .{ corpus, depth });
        replies.valid = try std.Io.Dir.cwd().readFileAlloc(init.io, path, f, .limited(16 << 20));
    }
    var samples: [9]f64 = undefined;
    for (0..12) |sample| {
        const start = std.Io.Clock.awake.now(init.io);
        try cycle(init.gpa, image, pending, depth, replies);
        const elapsed = start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds;
        if (sample >= 3) samples[sample - 3] = @floatFromInt(elapsed);
    }
    // Complete allocation interval in a separate pass, including preparation,
    // outputs, checkpoint transfer and release. The fixed workspace reservation
    // is reported separately from requested live/peak payload.
    const storage = try init.gpa.alloc(u8, 32 << 20);
    defer init.gpa.free(storage);
    var workspace = world.Workspace.init(storage);
    try cycle(workspace.allocator(), image, pending, depth, replies);
    if (workspace.live_payload != 0) return error.Leak;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .family = family, .depth = depth, .imageDigest = data.wire.digest(image), .samplesNs = samples, .peakBytes = workspace.peak_payload, .reservedBytes = storage.len, .sessionBytes = @sizeOf(world.Session), .residentBytes = @sizeOf(world.Resident), .outcomeBytes = @sizeOf(world.invocation.Outcome) }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
