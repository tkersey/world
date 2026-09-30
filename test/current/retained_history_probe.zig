// Public Resident witness plus native-only inspection of transaction work.
const std = @import("std");
const world = @import("world");
const data = @import("boundary_data");
const protocol = data.invocation;

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    const path = args.next() orelse return error.Image;
    const depth = try std.fmt.parseInt(u64, args.next() orelse return error.Depth, 10);
    if (args.next() != null) return error.Arguments;
    const pending = std.mem.eql(u8, mode, "Q");
    if (!pending and !std.mem.eql(u8, mode, "H")) return error.Mode;
    const image = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 << 20));
    defer init.gpa.free(image);
    var counting = std.testing.FailingAllocator.init(init.gpa, .{});
    const a = counting.allocator();
    var prepared = try world.Prepared.init(a, image);
    var input: [8]u8 = undefined;
    std.mem.writeInt(u64, &input, depth, .little);
    var resident = try world.Resident.start(a, &prepared, &input);
    var first = try resident.drive(a, .none, .{});
    errdefer first.deinit();
    if ((pending and first.record != .requested) or (!pending and first.record != .yielded)) return error.WrongPause;
    const frames = resident.session.?.frames.entries.count();
    // Directly inspect the same begin operation called by Resident.publish.
    // This uninstalled cross-version harness is the only historical adapter.
    var transaction = try resident.session.?.begin();
    const protected_at_begin = if (@hasDecl(@TypeOf(resident.session.?.frames), "backup"))
        transaction.frames.entries.count()
    else
        resident.session.?.frames.journal.?.entries.count();
    transaction.commit(&resident.session.?);
    var changes: [64]struct { allocations: usize, bytes: usize, traced: u64, copies: u64, savedFrames: u64 } = undefined;
    var stats: world.Statistics = .{};
    resident.session.?.statistics = &stats;
    resident.session.?.store.statistics = &stats.storage;
    if (!pending) {
        var resumed = try resident.drive(a, .resume_yield, .{ .quantum = 0 });
        resumed.deinit();
        for (&changes) |*change| {
            const allocations = counting.allocations;
            const bytes = counting.allocated_bytes;
            const traced = stats.storage.traced_nodes;
            const copies = resident.session.?.frames.slots.statistics.value_copies;
            const saved = if (@hasField(world.Statistics, "frames")) stats.frames.saved_entries else 0;
            var out = try resident.drive(a, .none, .{ .quantum = 1 });
            defer out.deinit();
            if (out.record != .progressed) return error.WrongProgress;
            change.* = .{ .allocations = counting.allocations - allocations, .bytes = counting.allocated_bytes - bytes, .traced = stats.storage.traced_nodes - traced, .copies = resident.session.?.frames.slots.statistics.value_copies - copies, .savedFrames = if (@hasField(world.Statistics, "frames")) stats.frames.saved_entries - saved else @intCast(frames) };
        }
    } else @memset(&changes, .{ .allocations = 0, .bytes = 0, .traced = 0, .copies = 0, .savedFrames = 0 });
    var current = try resident.drive(a, .none, .{});
    var expected_payload: u64 = if (pending) 0 else 1;
    var replies: usize = 0;
    while (current.record == .requested) {
        var request = try protocol.decode(protocol.Request, a, current.record.requested.request);
        defer request.deinit();
        if (std.mem.readInt(u64, request.value.binding.payload[0..8], .little) != expected_payload) return error.WrongHistory;
        expected_payload += 1;
        var reply_value: [8]u8 = undefined;
        std.mem.writeInt(u64, &reply_value, 7, .little);
        const reply = try protocol.encodeOwned(protocol.Result, a, .{ .request_identity = request.value.request_identity, .value = &reply_value });
        defer a.free(reply);
        current.deinit();
        current = try resident.drive(a, .{ .reply = reply }, .{});
        replies += 1;
    }
    if (current.record != .completed or std.mem.readInt(u64, current.record.completed[0..8], .little) != (if (pending) @as(u64, 135) else 128)) return error.WrongResult;
    current.deinit();
    try resident.close();
    prepared.deinit();
    first.deinit();
    if (counting.allocated_bytes != counting.freed_bytes) return error.Leak;
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .family = mode, .depth = depth, .retainedFrames = frames, .protectedAtBegin = protected_at_begin, .changes = changes, .distinctReplies = replies, .totalAllocatedBytes = counting.allocated_bytes }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
