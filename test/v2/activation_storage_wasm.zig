// Copyright (c) 2026 World contributors. MIT license.
//! Storage qualification only; this is not a Program evaluator or a kernel ABI.
const std = @import("std");
const Slots = @import("activation_slots").Slots(u64);
var memory: [1 << 20]u8 align(16) = undefined;

pub export fn test_storage() u32 {
    exercise() catch return 1;
    return 0;
}

fn exercise() !void {
    var allocator = std.heap.FixedBufferAllocator.init(&memory);
    var store = try Slots.init(allocator.allocator());
    defer store.deinit();
    const current = try store.create(4096);
    for (0..256) |index| try store.set(current, index, index + 1);
    const retained = try store.fork(current);
    try store.set(current, 127, 900);
    if (try store.get(retained, 127) != 128) return error.Failed;
    if (try store.get(current, 127) != 900) return error.Failed;
    try store.retainOnly(current, &.{127});
    try store.release(retained);
    if (store.statistics.live_pages != 1) return error.Failed;
    const successor = try store.fork(current);
    try store.set(successor, 127, 901);
    try store.commit(current, successor);
    var values = try store.iterator(current);
    const binding = (try values.next()) orelse return error.Failed;
    if (binding.slot != 127 or binding.value != 901 or try values.next() != null)
        return error.Failed;
    try store.release(current);
    if (store.statistics.live_pages != 0 or store.statistics.live_directories != 0)
        return error.Failed;
}
