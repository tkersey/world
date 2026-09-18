// Copyright (c) 2026 World contributors. MIT license.
//! Reusable caller-owned storage. Allocation metadata is never process State.
const std = @import("std");

pub const Arena = struct {
    const Block = struct {
        length: usize,
        requested: usize = 0,
        previous: ?*Block = null,
        next: ?*Block = null,
        available: bool = true,
    };
    const block_alignment = @alignOf(Block);
    buffer: []u8,
    first: ?*Block,
    // Blocks before this hint are known allocated. Unsuccessful holes remain
    // candidates for later, smaller allocations.
    search: ?*Block = null,
    address_ordered: bool = true,
    live_payload: usize = 0,
    live_blocks: usize = 0,
    peak_payload: usize = 0,
    required: u64 = 0,
    grow_context: ?*anyopaque = null,
    grow: ?*const fn (*anyopaque, usize) ?[]u8 = null,

    pub fn init(buffer: []u8) Arena {
        const start = @intFromPtr(buffer.ptr);
        const aligned = std.mem.alignForward(usize, start, block_alignment);
        const padding = aligned - start;
        if (padding > buffer.len or buffer.len - padding < @sizeOf(Block))
            return .{ .buffer = buffer, .first = null };
        const first: *Block = @ptrFromInt(aligned);
        first.* = .{ .length = buffer.len - padding };
        return .{ .buffer = buffer, .first = first };
    }

    pub fn allocator(self: *Arena) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = allocate,
            .resize = std.mem.Allocator.noResize,
            .remap = std.mem.Allocator.noRemap,
            .free = release,
        } };
    }

    fn allocate(context: *anyopaque, length: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *Arena = @ptrCast(@alignCast(context));
        // Simultaneously live payload and mandatory metadata form a lower bound.
        // It intentionally does not promise a sufficient size under fragmentation.
        const overhead = @as(u64, @sizeOf(Block) + @sizeOf(usize));
        const live_metadata = (@as(u64, self.live_blocks) +| 1) *| overhead;
        const demand = @as(u64, self.live_payload) +| length +| live_metadata;
        self.required = @max(self.required, demand);
        const requested_alignment = @max(alignment.toByteUnits(), @alignOf(usize));
        var cursor = self.search orelse self.first;
        var last: ?*Block = null;
        var first_available: ?*Block = null;
        while (cursor) |block| : (cursor = block.next) {
            last = block;
            if (!block.available) continue;
            if (first_available == null) first_available = block;
            const start = @intFromPtr(block);
            const header_end = std.math.add(usize, start, @sizeOf(Block) + @sizeOf(usize)) catch return null;
            const padding = (0 -% header_end) & (requested_alignment - 1);
            const address = std.math.add(usize, header_end, padding) catch return null;
            const end = std.math.add(usize, address, length) catch return null;
            const used = end - start;
            if (used > block.length) continue;
            const padded = std.math.add(usize, used, (0 -% end) & (block_alignment - 1)) catch return null;
            if (padded <= block.length and block.length - padded >= @sizeOf(Block) + @sizeOf(usize) + 1) {
                const successor: *Block = @ptrFromInt(start + padded);
                successor.* = .{ .length = block.length - padded, .previous = block, .next = block.next };
                if (block.next) |next| next.previous = successor;
                block.next = successor;
                block.length = padded;
            }
            block.available = false;
            block.requested = length;
            self.search = if (first_available == block) block.next else first_available;
            const saved: *usize = @ptrFromInt(address - @sizeOf(usize));
            saved.* = start;
            self.live_payload += length;
            self.live_blocks += 1;
            self.peak_payload = @max(self.peak_payload, self.live_payload);
            return @ptrFromInt(address);
        }
        if (self.grow) |grow| {
            const metadata = std.math.add(usize, @sizeOf(Block) + @sizeOf(usize), requested_alignment) catch return null;
            const needed = std.math.add(usize, length, metadata) catch return null;
            const segment = grow(self.grow_context.?, needed) orelse return null;
            const added = Arena.init(segment);
            const first = added.first orelse return null;
            if (last) |tail| self.address_ordered = self.address_ordered and @intFromPtr(tail) < @intFromPtr(first);
            if (last) |tail| tail.next = first else self.first = first;
            first.previous = last;
            self.search = first_available orelse first;
            // The new segment was requested with sufficient alignment and metadata.
            const saved_grow = self.grow;
            self.grow = null;
            defer self.grow = saved_grow;
            return allocate(context, length, alignment, 0);
        }
        return null;
    }

    fn release(context: *anyopaque, bytes: []u8, _: std.mem.Alignment, _: usize) void {
        const self: *Arena = @ptrCast(@alignCast(context));
        const saved: *const usize = @ptrFromInt(@intFromPtr(bytes.ptr) - @sizeOf(usize));
        const block: *Block = @ptrFromInt(saved.*);
        self.live_payload -= block.requested;
        self.live_blocks -= 1;
        block.available = true;
        var merged = block;
        if (block.next) |next| if (next.available and @intFromPtr(block) + block.length == @intFromPtr(next)) {
            block.length += next.length;
            block.next = next.next;
            if (next.next) |after| after.previous = block;
        };
        if (block.previous) |previous| if (previous.available and @intFromPtr(previous) + previous.length == @intFromPtr(block)) {
            previous.length += block.length;
            previous.next = block.next;
            if (block.next) |after| after.previous = previous;
            merged = previous;
        };
        // Address order is a proof of list order only while appended segments
        // remain ordered. Otherwise invalidate and use the original full scan.
        if (self.address_ordered) {
            if (self.search) |hint| {
                if (@intFromPtr(merged) < @intFromPtr(hint)) self.search = merged;
            }
        } else self.search = null;
    }
};

test "out-of-order frees coalesce and permit reuse of the complete buffer" {
    var buffer: [8192]u8 align(64) = undefined;
    var arena = Arena.init(&buffer);
    const allocator = arena.allocator();
    const a = try allocator.alignedAlloc(u8, .@"64", 500);
    const b = try allocator.alloc(u64, 100);
    const c = try allocator.alloc(u8, 300);
    allocator.free(b);
    allocator.free(a);
    allocator.free(c);
    try std.testing.expectEqual(@as(usize, 0), arena.live_payload);
    try std.testing.expectEqual(@as(usize, 0), arena.live_blocks);
    const all = try allocator.alloc(u8, 8000);
    allocator.free(all);
}

test "unrepresentable allocation demand preserves live workspace contents" {
    var buffer: [256]u8 align(64) = undefined;
    var arena = Arena.init(&buffer);
    const allocator = arena.allocator();
    const live = try allocator.alloc(u8, 16);
    defer allocator.free(live);
    @memset(live, 0xa5);
    const first = arena.first.?.*;
    const tail = arena.first.?.next.?.*;
    try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, std.math.maxInt(usize)));
    try std.testing.expect(std.meta.eql(first, arena.first.?.*));
    try std.testing.expect(std.meta.eql(tail, arena.first.?.next.?.*));
    try std.testing.expectEqual(@as(usize, 16), arena.live_payload);
    try std.testing.expectEqual(@as(usize, 1), arena.live_blocks);
    try std.testing.expect(std.mem.allEqual(u8, live, 0xa5));
    try std.testing.expect(arena.required >= std.math.maxInt(usize));
    const next = try allocator.alloc(u8, 32);
    allocator.free(next);
}

test "search hint preserves earlier holes after a larger allocation" {
    var bytes: [4096]u8 align(64) = undefined;
    var arena = Arena.init(&bytes);
    const a = arena.allocator();
    const small = try a.alloc(u8, 32);
    const separator = try a.alloc(u8, 16);
    const large = try a.alloc(u8, 256);
    const end = try a.alloc(u8, 16);
    a.free(small);
    a.free(large);
    const middle = try a.alloc(u8, 128);
    try std.testing.expectEqual(@intFromPtr(large.ptr), @intFromPtr(middle.ptr));
    const first = try a.alloc(u8, 16);
    try std.testing.expectEqual(@intFromPtr(small.ptr), @intFromPtr(first.ptr));
    a.free(first);
    a.free(middle);
    a.free(separator);
    a.free(end);
    try std.testing.expectEqual(@as(usize, 0), arena.live_payload);
    const whole = try a.alloc(u8, 4000);
    a.free(whole);
}

test "search hint resets on free and preserves segment order during growth" {
    const Growth = struct {
        bytes: []u8,
        used: bool = false,
        fn grow(context: *anyopaque, minimum: usize) ?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.used or minimum > self.bytes.len) return null;
            self.used = true;
            return self.bytes;
        }
    };
    for ([_]usize{ 0, 1 }) |initial| {
        var buffers: [2][256]u8 align(64) = undefined;
        var growth: Growth = .{ .bytes = &buffers[1 - initial] };
        // Exercise both address orders. A free tail in the new segment must
        // not hide a subsequently freed block in the first segment.
        var arena = Arena.init(&buffers[initial]);
        arena.grow_context = &growth;
        arena.grow = Growth.grow;
        const a = arena.allocator();
        const first = try a.alloc(u8, 200);
        const second = try a.alloc(u8, 64);
        try std.testing.expect(growth.used);
        try std.testing.expectEqual(initial == 1, @intFromPtr(second.ptr) < @intFromPtr(first.ptr));
        try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 200));
        a.free(first);
        const reused = try a.alloc(u8, 64);
        try std.testing.expectEqual(@intFromPtr(first.ptr), @intFromPtr(reused.ptr));
        a.free(reused);
        a.free(second);
        try std.testing.expectEqual(@as(usize, 0), arena.live_payload);
        try std.testing.expectEqual(@as(usize, 0), arena.live_blocks);
    }
}
