const std = @import("std");
const data = @import("boundary_data");
const Frames = @import("activation_frames.zig").Frames;
const Frame = @import("activation_frames.zig").Frame;
const Layouts = @import("frame_layouts.zig").Layouts;
const Values = @import("values.zig").Values;
const testing = std.testing;

const Context = struct {
    allocator: std.mem.Allocator,
    pool: data.analysis_sets.Pool,
    slots: []data.program.Id,
    functions: [1]data.activation.Function,
    layouts: Layouts,
    frames: Frames,

    fn init(self: *Context, allocator: std.mem.Allocator, width: usize) !void {
        self.allocator = allocator;
        self.pool = .{ .allocator = allocator, .limit = width };
        errdefer self.pool.deinit();
        self.slots = try allocator.alloc(data.program.Id, width);
        errdefer allocator.free(self.slots);
        @memset(self.slots, 0);
        self.functions = .{.{ .entry = 0, .inputs = &.{0}, .layout = .{ .slots = self.slots }, .result = 0 }};
        self.layouts = try Layouts.init(allocator, &self.functions);
        errdefer self.layouts.deinit();
        self.frames = try Frames.init(allocator, &self.pool, &self.layouts);
    }
    fn deinit(self: *Context) void {
        self.frames.deinit();
        self.layouts.deinit();
        self.allocator.free(self.slots);
        self.pool.deinit();
    }
    fn insert(self: *Context, id: u64, number: u64) !void {
        var frame = try self.frames.create(0);
        errdefer self.frames.releaseFrame(frame);
        try self.frames.write(&frame, 0, Values.natural(0, number));
        try self.frames.put(id, frame);
    }
    fn value(self: *Context, id: u64, slot: usize) !u64 {
        const frame = try self.frames.get(id);
        const item = try self.frames.slots.get(frame.view, slot);
        return std.mem.readInt(u64, item.body.scalar[0..8], .little);
    }
};

test "frame transaction setup and commit visit only acquired entries" {
    for ([_]usize{ 1, 7, 16, 31, 63, 64, 65, 256, 257, 1024 }) |count| {
        var c: Context = undefined;
        try c.init(testing.allocator, 65);
        defer c.deinit();
        for (0..count) |id| try c.insert(id, id + 10);
        try c.frames.begin(count);
        for (0..count) |id| _ = try c.frames.get(id);
        try testing.expectEqual(0, c.frames.statistics.saved_entries);
        const frame = try c.frames.getMutable(0);
        try c.frames.write(frame, 0, Values.natural(0, 20));
        try c.frames.write(try c.frames.getMutable(0), 64, Values.natural(0, 30));
        try testing.expectEqual(1, c.frames.statistics.saved_entries);
        try testing.expectEqual(1, c.frames.statistics.forked_frames);
        c.frames.commit();
        try testing.expectEqual(1, c.frames.statistics.commit_entries);
        try testing.expectEqual(20, try c.value(0, 0));
        try testing.expectEqual(30, try c.value(0, 64));
        for (1..count) |id| try testing.expectEqual(id + 10, try c.value(id, 0));
    }
}

test "frame transaction restores entry membership through reuse and semantic forks without allocation" {
    var counting = testing.FailingAllocator.init(testing.allocator, .{});
    var c: Context = undefined;
    try c.init(counting.allocator(), 65);
    defer c.deinit();
    try c.insert(0, 10);
    try c.insert(1, 11);
    try c.insert(2, 12);
    const original = try c.frames.get(0);
    const semantic = try c.frames.forkFrame(original);
    defer c.frames.releaseFrame(semantic);
    try c.frames.begin(5);
    // Two writes must preserve the entry version and packed occupancy/rank.
    var changed = try c.frames.getForUpdate(0);
    try c.frames.write(&changed, 0, Values.natural(0, 20));
    try c.frames.write(&changed, 1, Values.natural(0, 21));
    try c.frames.write(&changed, 64, Values.natural(0, 22));
    changed.position = 42;
    changed.custody.scope = 7;
    try c.frames.update(0, changed);
    try c.frames.clear(try c.frames.getMutable(0), 0);
    try c.frames.remove(1); // Transfer untouched entry ownership.
    try c.insert(1, 90); // Reuse an entry identity.
    try c.insert(3, 33); // Reuse an entry-era Store hole.
    try c.frames.remove(3);
    try c.insert(3, 34);
    try c.frames.copyFrame(0, 5); // Fork during transaction, in appended range.
    try c.frames.write(try c.frames.getMutable(5), 1, Values.natural(0, 99));
    try testing.expectEqual(1, c.frames.statistics.moved_frames);
    // Rollback must not even ask for another allocation.
    const allocations = counting.allocations;
    counting.fail_index = counting.alloc_index;
    c.frames.rollback(6);
    try testing.expectEqual(allocations, counting.allocations);
    try testing.expect(!counting.has_induced_failure);
    try testing.expectEqual(3, c.frames.entries.count());
    try testing.expectEqual(10, try c.value(0, 0));
    try testing.expectEqual(11, try c.value(1, 0));
    try testing.expectEqual(12, try c.value(2, 0));
    const restored = try c.frames.get(0);
    try testing.expectEqual(0, restored.position);
    try testing.expectEqual(0, restored.custody.scope);
    try testing.expectError(error.UninitializedSlot, c.frames.slots.get(restored.view, 1));
    try testing.expectError(error.UninitializedSlot, c.frames.slots.get(restored.view, 64));
    try testing.expectEqual(10, (try c.frames.slots.get(semantic.view, 0)).body.scalar[0]);
    try testing.expectError(error.InvalidState, c.frames.get(3));
    try testing.expectError(error.InvalidState, c.frames.get(5));
}

fn mutate(c: *Context) !void {
    var frame = try c.frames.getForUpdate(0);
    try c.frames.write(&frame, 0, Values.natural(0, 90));
    try c.frames.write(&frame, 1, Values.natural(0, 91));
    try c.frames.write(&frame, 64, Values.natural(0, 92));
    frame.position = 9;
    try c.frames.update(0, frame);
    try c.frames.remove(1);
    try c.insert(1, 70);
    try c.insert(3, 71);
    try c.frames.copyFrame(0, 4);
    try c.frames.remove(4);
    try c.insert(4, 72);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    var c: Context = undefined;
    try c.init(allocator, 65);
    defer c.deinit();
    try c.insert(0, 10);
    try c.insert(1, 11);
    try c.frames.begin(4);
    mutate(&c) catch |err| {
        c.frames.rollback(5);
        try testing.expectEqual(2, c.frames.entries.count());
        try testing.expectEqual(10, try c.value(0, 0));
        try testing.expectEqual(11, try c.value(1, 0));
        try testing.expectEqual(0, (try c.frames.get(0)).position);
        return err;
    };
    c.frames.rollback(5);
    try testing.expectEqual(2, c.frames.entries.count());
    try testing.expectEqual(10, try c.value(0, 0));
    try testing.expectEqual(11, try c.value(1, 0));
}

test "every frame journal allocation failure preserves entry values and membership" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationFailure, .{});
}

test "repeated frame commits release rollback views and retain a bounded plateau" {
    var counting = testing.FailingAllocator.init(testing.allocator, .{});
    var c: Context = undefined;
    try c.init(counting.allocator(), 65);
    defer c.deinit();
    try c.insert(0, 10);
    var plateau: usize = 0;
    for (0..2048) |iteration| {
        try c.frames.begin(1);
        try c.frames.write(try c.frames.getMutable(0), 0, Values.natural(0, iteration));
        c.frames.commit();
        if (iteration == 16) plateau = counting.allocated_bytes - counting.freed_bytes;
        if (iteration > 16) try testing.expectEqual(plateau, counting.allocated_bytes - counting.freed_bytes);
        try testing.expectEqual(1, c.frames.slots.statistics.live_pages);
    }
    try testing.expectEqual(2047, try c.value(0, 0));
}
