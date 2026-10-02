//! Same-image native structural probe; also runs unchanged against W0.
const std = @import("std");
const runtime = @import("runtime");
const data = @import("boundary_data");
const Statistics = std.meta.Child(std.meta.Child(@FieldType(runtime.Session, "statistics")));
const Snapshot = struct { frames: usize, transitions: usize, saved: u64, committed: u64, copies: u64, directories: u64 };
fn snapshot(resident: *runtime.Resident) !Snapshot {
    if (@hasDecl(runtime.Resident, "diagnostics")) {
        const view = try resident.diagnostics();
        return .{ .frames = view.frames, .transitions = view.transitions, .saved = view.transactions.saved_entries, .committed = view.transactions.commit_entries, .copies = view.slots.value_copies, .directories = view.slots.directory_copies };
    } else {
        const session = &resident.session.?;
        return .{ .frames = session.frames.entries.count(), .transitions = session.transitions, .saved = 0, .committed = 0, .copies = session.frames.slots.statistics.value_copies, .directories = session.frames.slots.statistics.directory_copies };
    }
}
fn statistics(resident: *runtime.Resident, value: ?*Statistics) !void {
    if (@hasDecl(runtime.Resident, "setStatistics")) return resident.setStatistics(value);
    resident.session.?.statistics = value;
    resident.session.?.store.statistics = if (value) |v| &v.storage else null;
}

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
    var observed: Statistics = .{};
    try statistics(&resident, &observed);
    var parked = try resident.drive(init.gpa, .none, .{});
    defer parked.deinit();
    const frames = (try snapshot(&resident)).frames;
    if (frames < depth) return error.EliminatedHistory;
    const start_live = counting.allocated_bytes - counting.freed_bytes;
    // Measure the same transaction constructor independently, on the exported
    // state, without obtaining a mutable reference to Resident-owned execution.
    const checkpoint = try resident.checkpoint(init.gpa);
    defer init.gpa.free(checkpoint);
    var entry_counting = std.testing.FailingAllocator.init(init.gpa, .{});
    var entry = try runtime.Session.restore(entry_counting.allocator(), &prepared, checkpoint);
    defer entry.deinit();
    if (entry.frames.entries.count() != frames) return error.FrameCount;
    const allocations = entry_counting.allocations;
    const allocated_bytes = entry_counting.allocated_bytes;
    var retained: usize = 0;
    {
        var transaction = try entry.begin();
        if (@hasField(runtime.Session.Transaction, "frames")) retained = transaction.frames.entries.count();
        transaction.commit(&entry);
    }
    const begin_allocations = entry_counting.allocations - allocations;
    const begin_bytes = entry_counting.allocated_bytes - allocated_bytes;
    if (std.mem.eql(u8, mode, "H")) {
        if (parked.record != .yielded) return error.NotYielded;
        var resumed = try resident.drive(init.gpa, .resume_yield, .{ .quantum = 0 });
        resumed.deinit();
        // Stay away from a natural collection cut, without changing its schedule.
        if ((try snapshot(&resident)).transitions % 256 > 253) {
            var aligned = try resident.drive(init.gpa, .none, .{ .quantum = 3 });
            aligned.deinit();
        }
        const before = try snapshot(&resident);
        const before_bytes = counting.allocated_bytes;
        observed = .{};
        var progress = try resident.drive(init.gpa, .none, .{ .quantum = 1 });
        defer progress.deinit();
        const after = try snapshot(&resident);
        if (progress.record != .progressed or after.transitions != before.transitions + 1) return error.Prefix;
        if (observed.storage.traced_nodes != 0 or observed.storage.swept_slots != 0) return error.Collection;
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .mode = mode, .depth = depth, .frames = frames, .beginRetainedFrames = retained, .beginAllocations = begin_allocations, .beginAllocatedBytes = begin_bytes, .driveAllocatedBytes = counting.allocated_bytes - before_bytes, .transactionSavedEntries = if (@hasDecl(runtime.Resident, "diagnostics")) after.saved - before.saved else retained, .transactionCommitEntries = if (@hasDecl(runtime.Resident, "diagnostics")) after.committed - before.committed else retained, .slotValueCopies = after.copies - before.copies, .slotDirectoryCopies = after.directories - before.directories, .tracedNodes = observed.storage.traced_nodes, .transitionBefore = before.transitions, .transitionAfter = after.transitions, .startLive = start_live, .pauseLive = counting.allocated_bytes - counting.freed_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    } else {
        if (parked.record != .requested) return error.NotRequested;
        var expected = try data.invocation.decode(data.invocation.Request, init.gpa, parked.record.requested.request);
        defer expected.deinit();
        var wrong = expected.value.request_identity;
        wrong[0] ^= 1;
        const ill_typed = try data.invocation.encodeOwned(data.invocation.Result, init.gpa, .{ .request_identity = expected.value.request_identity, .value = &.{} });
        defer init.gpa.free(ill_typed);
        const wrong_binding = try data.invocation.encodeOwned(data.invocation.Result, init.gpa, .{ .request_identity = wrong, .value = arguments[8..16] });
        defer init.gpa.free(wrong_binding);
        const before_bytes = counting.allocated_bytes;
        observed = .{};
        var rejected: usize = 0;
        for ([_][]const u8{ &.{0}, wrong_binding, ill_typed }) |reply| {
            if (resident.drive(init.gpa, .{ .reply = reply }, .{})) |value| {
                var unexpected = value;
                unexpected.deinit();
                return error.AcceptedInvalidReply;
            } else |_| rejected += 1;
        }
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try std.json.Stringify.value(.{ .mode = mode, .depth = depth, .frames = frames, .rejected = rejected, .invalidAllocatedBytes = counting.allocated_bytes - before_bytes, .stateProjections = if (@hasField(Statistics, "state_projections")) observed.state_projections else null, .expectedBindingChecks = if (@hasField(Statistics, "expected_binding_checks")) observed.expected_binding_checks else null, .reusedExpectedBindings = if (@hasField(Statistics, "reused_expected_bindings")) observed.reused_expected_bindings else null, .startLive = start_live, .pauseLive = counting.allocated_bytes - counting.freed_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
    var cancelled = try resident.drive(init.gpa, .{ .cancel = .{ .text = "probe complete" } }, .{});
    cancelled.deinit();
    try resident.close();
    if (counting.allocated_bytes != counting.freed_bytes) return error.Leak;
}
