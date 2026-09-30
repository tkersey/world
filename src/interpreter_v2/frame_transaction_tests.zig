const std = @import("std");
const data = @import("boundary_data");
const bindings = @import("activation_frames.zig");
const Values = @import("values.zig").Values;
const testing = std.testing;

fn mutate(frames: *bindings.Frames, last: u64) !void {
    {
        const frame = try frames.getMutable(0);
        try frames.write(frame, 1, Values.natural(0, 7));
        try frames.clear(frame, 0);
        try frames.write(frame, 1, Values.natural(0, 8));
        frame.position = 19;
    }
    // A semantic successor is distinct from transaction-only protection.
    try frames.copyFrame(0, 4);
    {
        const frame = try frames.getMutable(0);
        try frames.write(frame, 1, Values.natural(0, 9));
        try frames.clear(frame, last);
    }
    try frames.remove(1);
    {
        var replacement = try frames.create(0);
        errdefer frames.releaseFrame(replacement);
        try frames.write(&replacement, 0, Values.natural(0, 255));
        try frames.put(1, replacement);
    }
    try frames.remove(4);
    try frames.copyFrame(0, 5);
    try frames.remove(2);
}

fn attempt(width: usize, fail_after: ?usize, commit: bool) !struct { failed: bool, allocations: usize } {
    var failing = testing.FailingAllocator.init(testing.allocator, .{});
    const a = failing.allocator();
    var pool: data.analysis_sets.Pool = .{ .allocator = a, .limit = width };
    defer pool.deinit();
    const slots = try a.alloc(data.program.Id, width);
    defer a.free(slots);
    @memset(slots, 0);
    const functions = [_]data.activation.Function{.{ .entry = 0, .inputs = &.{}, .layout = .{ .slots = slots }, .result = 0 }};
    var layouts = try bindings.Layouts.init(a, &functions);
    defer layouts.deinit();
    var frames = try bindings.Frames.init(a, &pool, &layouts);
    defer frames.deinit();
    var statistics: bindings.Statistics = .{};
    frames.statistics = &statistics;
    for (0..3) |id| {
        var frame = try frames.create(0);
        errdefer frames.releaseFrame(frame);
        try frames.write(&frame, 0, Values.natural(0, 42 + id));
        try frames.write(&frame, width - 1, Values.natural(0, 99));
        frame.position = 7 + id;
        try frames.put(id, frame);
    }
    const old = try frames.forkFrame(try frames.get(0));
    defer frames.releaseFrame(old);
    try frames.begin();
    try testing.expectError(error.InvalidState, frames.begin());
    for (0..3) |id| _ = try frames.get(id);
    try testing.expectEqual(0, frames.journal.?.entries.count());
    try testing.expectEqual(0, statistics.forked_frames);
    if (fail_after) |offset| {
        failing.fail_index = failing.alloc_index + offset;
        failing.resize_fail_index = failing.resize_index;
    }
    const mutation_start = failing.alloc_index;
    var failed = false;
    mutate(&frames, width - 1) catch |err| {
        try testing.expectEqual(error.OutOfMemory, err);
        failed = true;
    };
    // Deny every future allocation during resolution, including successful
    // commit, so allocation-free rollback is tested after each actual failure.
    const allocations = failing.alloc_index;
    const resizes = failing.resize_index;
    failing.fail_index = allocations;
    failing.resize_fail_index = resizes;
    if (commit and !failed) frames.commit() else frames.rollback();
    try testing.expectEqual(allocations, failing.alloc_index);
    try testing.expectEqual(resizes, failing.resize_index);
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try testing.expect(frames.journal == null);
    try testing.expectEqual(42, (try frames.slots.get(old.view, 0)).body.scalar[0]);
    try testing.expectEqual(99, (try frames.slots.get(old.view, width - 1)).body.scalar[0]);
    if (!commit or failed) {
        try testing.expectEqual(3, frames.entries.count());
        for (0..3) |id| {
            const frame = try frames.get(id);
            try testing.expectEqual(42 + id, (try frames.slots.get(frame.view, 0)).body.scalar[0]);
            try testing.expectEqual(99, (try frames.slots.get(frame.view, width - 1)).body.scalar[0]);
            try testing.expectEqual(7 + id, frame.position);
            try testing.expectError(error.UninitializedSlot, frames.slots.get(frame.view, 1));
        }
    } else {
        try testing.expectEqual(3, frames.entries.count());
        const active = try frames.get(0);
        try testing.expectError(error.UninitializedSlot, frames.slots.get(active.view, 0));
        try testing.expectEqual(9, (try frames.slots.get(active.view, 1)).body.scalar[0]);
        try testing.expectEqual(255, (try frames.slots.get((try frames.get(1)).view, 0)).body.scalar[0]);
        try testing.expectError(error.InvalidState, frames.get(2));
        try testing.expectError(error.InvalidState, frames.get(4));
        try testing.expectEqual(9, (try frames.slots.get((try frames.get(5)).view, 1)).body.scalar[0]);
        try testing.expectEqual(5, statistics.saved_entries);
        try testing.expectEqual(3, statistics.forked_frames);
        try testing.expectEqual(5, statistics.commit_entries);
    }
    return .{ .failed = failed, .allocations = allocations - mutation_start };
}

test "frame first-touch journal restores entry versions across packed shifts, semantic forks, removal and ID reuse" {
    for ([_]usize{ 4, 65, 4096, 65536 }) |width| {
        try testing.expect(!(try attempt(width, null, false)).failed);
        try testing.expect(!(try attempt(width, null, true)).failed);
    }
}

test "every fallible frame protection and successor allocation preserves retryable entry ownership" {
    for ([_]usize{ 4, 65, 4096 }) |width| {
        var failures: usize = 0;
        while (true) : (failures += 1) {
            const result = try attempt(width, failures, false);
            if (!result.failed) {
                // Every allocation in the successful attempt was selected as
                // a failure point, rather than requiring an arbitrary ordinal.
                try testing.expectEqual(failures, result.allocations);
                try testing.expect(failures != 0);
                break;
            }
        }
    }
}
