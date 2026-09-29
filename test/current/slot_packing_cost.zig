const std = @import("std");
const data = @import("boundary_data");
const Slots = @import("slots").Slots(data.graph.Value);
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const count = try std.fmt.parseInt(usize, args.next() orelse return error.Count, 10);
    const branches = try std.fmt.parseInt(usize, args.next() orelse return error.Branches, 10);
    const mode = args.next();
    if (count == 0 or count > 16 or branches > 128 or args.next() != null) return error.Arguments;
    if (mode) |selected| {
        if (!std.mem.eql(u8, selected, "timing")) return error.Arguments;
        return timing(init, count, branches);
    }
    var counter = std.testing.FailingAllocator.init(init.gpa, .{});
    var store = try Slots.init(counter.allocator());
    const original = try store.create(16);
    for (0..count) |i| {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, i + 1, .little);
        try store.set(original, i, .{ .schema = 0, .body = .{ .scalar = bytes } });
    }
    const handles = try init.gpa.alloc(Slots.Handle, branches);
    defer init.gpa.free(handles);
    const before = counter.allocated_bytes - counter.freed_bytes;
    const original_page_bytes = before - store.views.capacity * @sizeOf(@TypeOf(store.views.items[0]));
    for (handles, 0..) |*handle, index| {
        handle.* = try store.fork(original);
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, index + 100, .little);
        try store.set(handle.*, 0, .{ .schema = 0, .body = .{ .scalar = bytes } });
    }
    const retained = counter.allocated_bytes - counter.freed_bytes;
    const peak_page_bytes = if (@hasField(@TypeOf(store.statistics), "peak_page_bytes"))
        store.statistics.peak_page_bytes
    else
        store.statistics.peak_pages * original_page_bytes;
    const value_copies = store.statistics.value_copies;
    const packed_moves = if (@hasField(@TypeOf(store.statistics), "packed_moves")) store.statistics.packed_moves else 0;
    for (handles, 0..) |handle, index| {
        const value = try store.get(handle, 0);
        if (std.mem.readInt(u64, &value.body.scalar, .little) != index + 100) return error.BranchValue;
        for (1..count) |slot| {
            const other = try store.get(handle, slot);
            if (std.mem.readInt(u64, &other.body.scalar, .little) != slot + 1) return error.SharedValue;
        }
        try store.release(handle);
    }
    const value = try store.get(original, 0);
    if (std.mem.readInt(u64, &value.body.scalar, .little) != 1) return error.OriginalValue;
    try store.release(original);
    store.deinit();
    if (counter.allocated_bytes != counter.freed_bytes) return error.Leak;
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .values = count, .branches = branches, .ownerBytes = @sizeOf(Slots), .beforeBytes = before, .retainedBytes = retained, .peakPageBytes = peak_page_bytes, .valueCopies = value_copies, .packedMoves = packed_moves, .allocations = counter.allocations, .allocatedBytes = counter.allocated_bytes }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}

fn timing(init: std.process.Init, count: usize, branches: usize) !void {
    const handles = try init.gpa.alloc(Slots.Handle, branches);
    defer init.gpa.free(handles);
    var samples: [9]f64 = undefined;
    for (0..12) |window| {
        const start = std.Io.Clock.awake.now(init.io);
        for (0..128) |_| {
            var store = try Slots.init(init.gpa);
            defer store.deinit();
            const original = try store.create(16);
            for (0..count) |slot| try store.set(original, slot, .{ .schema = 0, .body = .{ .scalar = @splat(@intCast(slot)) } });
            for (handles, 0..) |*handle, index| {
                handle.* = try store.fork(original);
                try store.set(handle.*, 0, .{ .schema = 0, .body = .{ .scalar = @splat(@intCast(index)) } });
                if (count > 1) try store.clear(handle.*, count - 1);
            }
            for (handles, 0..) |handle, index| {
                const value = try store.get(handle, 0);
                if (value.body.scalar[0] != index) return error.WrongValue;
                try store.release(handle);
            }
            const unchanged = try store.get(original, 0);
            if (unchanged.body.scalar[0] != 0) return error.ChangedOriginal;
            try store.release(original);
        }
        if (window >= 3) samples[window - 3] = @as(f64, @floatFromInt(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds)) / 128;
    }
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .values = count, .branches = branches, .samplesNs = samples }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
