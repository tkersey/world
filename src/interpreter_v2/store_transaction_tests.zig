const std = @import("std");
const data = @import("boundary_data_v2");
const heap = @import("store.zig");
const testing = std.testing;

fn bytes(store: *heap.Store, roots: data.graph.Roots) ![]u8 {
    const nodes = try testing.allocator.alloc(data.process_state.Node, store.nodes.items.len);
    defer testing.allocator.free(nodes);
    for (nodes, store.nodes.items) |*target, source| target.* = .{ .record = source };
    return data.state_image.emit(testing.allocator, .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = roots,
        .nodes = nodes,
        .blobs = store.blobs.items,
    });
}

test "journal retains one entry version across repeated changes, collection and ID reuse" {
    var store: heap.Store = .{ .allocator = testing.allocator };
    defer store.deinit();
    const old = try store.literal(&.{.bytes}, .{ .schema = 0, .bytes = &.{ 3, 'o', 'l', 'd' } });
    const root = try store.add(.{ .environment = .{ .values = &.{old}, .tail = null } });
    const roots: data.graph.Roots = .{ .current = root };
    const before = try bytes(&store, roots);
    defer testing.allocator.free(before);
    const old_fields = (try store.get(root)).environment.values.ptr;
    const old_payload = store.blobs.items[0].bytes.ptr;
    try store.begin();
    for (0..64) |index| {
        const value = try store.literal(&.{.bytes}, .{ .schema = 0, .bytes = &.{ 1, @intCast(index) } });
        try store.replace(root, .{ .environment = .{ .values = &.{value}, .tail = null } });
        try store.collect(roots);
    }
    try testing.expectEqual(1, store.journal.?.nodes.count());
    try testing.expectEqual(1, store.journal.?.blobs.count());
    try testing.expect(old_fields == store.journal.?.nodes.get(0).?.value.environment.values.ptr);
    try testing.expect(old_payload == store.journal.?.blobs.get(0).?.value.bytes.ptr);
    store.rollback();
    const after = try bytes(&store, roots);
    defer testing.allocator.free(after);
    try testing.expectEqualSlices(u8, before, after);
    try testing.expectEqual(0, (try store.literal(&.{.bytes}, .{ .schema = 0, .bytes = &.{ 3, 'o', 'l', 'd' } })).body.blob.id);
    try store.begin();
    const value = try store.literal(&.{.bytes}, .{ .schema = 0, .bytes = &.{ 1, 99 } });
    try store.replace(root, .{ .environment = .{ .values = &.{value}, .tail = null } });
    try store.collect(roots);
    store.commit();
    try testing.expectEqualSlices(u8, &.{ 1, 99 }, store.blobs.items[@intCast(value.body.blob.id)].bytes);
}

test "journal rollback retains imported bytes after collection and replacement" {
    const state: data.process_state.State = .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .current = .{ .id = 0 } },
        .nodes = &.{.{ .record = .{ .environment = .{ .values = &.{.{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } }}, .tail = null } } }},
        .blobs = &.{.{ .schema = 0, .bytes = &.{ 3, 'o', 'l', 'd' } }},
    };
    const encoded = try data.state_image.emit(testing.allocator, state);
    defer testing.allocator.free(encoded);
    var owner = try data.state_image.decodeGraph(testing.allocator, encoded);
    var moved = false;
    defer if (!moved) owner.deinit();
    var store: heap.Store = .{ .allocator = testing.allocator };
    defer store.deinit();
    try store.importOwned(&owner);
    moved = true;
    try store.begin();
    try store.replace(.{ .id = 0 }, .{ .environment = .{ .values = &.{}, .tail = null } });
    try store.collect(state.roots);
    try testing.expect(store.imported != null);
    store.rollback();
    const restored = try bytes(&store, state.roots);
    defer testing.allocator.free(restored);
    try testing.expectEqualSlices(u8, encoded, restored);
}
