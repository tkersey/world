//! Same-image native structural probe; also runs unchanged against W0.
const std = @import("std");
const runtime = @import("runtime");
const data = @import("boundary_data");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const image_path = args.next() orelse return error.Image;
    const depth = try std.fmt.parseInt(u64, args.next() orelse return error.Depth, 10);
    const mode = args.next() orelse "H";
    if (args.next() != null) return error.Arguments;
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, image_path, init.gpa, .limited(64 << 20));
    defer init.gpa.free(image);
    var prepared = try runtime.Prepared.init(init.gpa, image);
    defer prepared.deinit();
    var counting = std.testing.FailingAllocator.init(init.gpa, .{});
    var arguments: [16]u8 = undefined;
    std.mem.writeInt(u64, arguments[0..8], depth, .little);
    std.mem.writeInt(u64, arguments[8..16], 17, .little);
    var resident = try runtime.Resident.start(counting.allocator(), &prepared, &arguments);
    var parked = try resident.drive(init.gpa, .none, .{});
    defer parked.deinit();
    const session = &resident.session.?;
    const frames = session.frames.entries.count();
    if (frames < depth) return error.EliminatedHistory;
    const start_live = counting.allocated_bytes - counting.freed_bytes;
    const allocations = counting.allocations;
    const allocated_bytes = counting.allocated_bytes;
    var retained: usize = 0;
    {
        var transaction = try session.begin();
        if (@hasField(runtime.Session.Transaction, "frames")) retained = transaction.frames.entries.count();
        transaction.commit(session);
    }
    const begin_allocations = counting.allocations - allocations;
    const begin_bytes = counting.allocated_bytes - allocated_bytes;
    if (std.mem.eql(u8, mode, "H")) {
        if (parked.record != .yielded) return error.NotYielded;
        var resumed = try resident.drive(init.gpa, .resume_yield, .{ .quantum = 0 });
        resumed.deinit();
        // Stay away from a natural collection cut, without changing its schedule.
        if (session.transitions % 256 > 253) {
            var aligned = try resident.drive(init.gpa, .none, .{ .quantum = 3 });
            aligned.deinit();
        }
        const before_transitions = session.transitions;
        const before_bytes = counting.allocated_bytes;
        const saved_before = if (@hasField(@TypeOf(session.frames), "statistics")) session.frames.statistics.saved_entries else 0;
        const committed_before = if (@hasField(@TypeOf(session.frames), "statistics")) session.frames.statistics.commit_entries else 0;
        const copies_before = session.frames.slots.statistics.value_copies;
        const directories_before = session.frames.slots.statistics.directory_copies;
        var storage_statistics: std.meta.Child(std.meta.Child(@TypeOf(session.store.statistics))) = .{};
        session.store.statistics = &storage_statistics;
        var progress = try resident.drive(init.gpa, .none, .{ .quantum = 1 });
        defer progress.deinit();
        if (progress.record != .progressed or session.transitions != before_transitions + 1) return error.Prefix;
        if (storage_statistics.traced_nodes != 0 or storage_statistics.swept_slots != 0) return error.Collection;
        session.store.statistics = null;
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .mode = mode, .depth = depth, .frames = frames, .beginRetainedFrames = retained, .beginAllocations = begin_allocations, .beginAllocatedBytes = begin_bytes, .driveAllocatedBytes = counting.allocated_bytes - before_bytes, .transactionSavedEntries = if (@hasField(@TypeOf(session.frames), "statistics")) session.frames.statistics.saved_entries - saved_before else retained, .transactionCommitEntries = if (@hasField(@TypeOf(session.frames), "statistics")) session.frames.statistics.commit_entries - committed_before else retained, .slotValueCopies = session.frames.slots.statistics.value_copies - copies_before, .slotDirectoryCopies = session.frames.slots.statistics.directory_copies - directories_before, .tracedNodes = storage_statistics.traced_nodes, .transitionBefore = before_transitions, .transitionAfter = session.transitions, .startLive = start_live, .pauseLive = counting.allocated_bytes - counting.freed_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    } else {
        if (parked.record != .requested) return error.NotRequested;
        var expected = try data.invocation.decode(data.invocation.Request, init.gpa, parked.record.requested.request);
        defer expected.deinit();
        const reply = try data.invocation.encodeOwned(data.invocation.Result, init.gpa, .{ .request_identity = expected.value.request_identity, .value = &.{} });
        defer init.gpa.free(reply);
        const before_bytes = counting.allocated_bytes;
        var rejected: usize = 0;
        for (0..3) |_| {
            if (resident.drive(init.gpa, .{ .reply = reply }, .{})) |value| {
                var unexpected = value;
                unexpected.deinit();
                return error.AcceptedInvalidReply;
            } else |_| rejected += 1;
        }
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .mode = mode, .depth = depth, .frames = frames, .rejected = rejected, .invalidAllocatedBytes = counting.allocated_bytes - before_bytes, .startLive = start_live, .pauseLive = counting.allocated_bytes - counting.freed_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
    var cancelled = try resident.drive(init.gpa, .{ .cancel = .{ .text = "probe complete" } }, .{});
    cancelled.deinit();
    try resident.close();
    if (counting.allocated_bytes != counting.freed_bytes) return error.Leak;
}
