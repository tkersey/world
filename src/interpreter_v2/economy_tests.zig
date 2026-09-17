const std = @import("std");
const data = @import("boundary_data");
const g = data.graph;
const Store = @import("store.zig").Store;
const allocator = std.testing.allocator;

fn value(ref: g.NodeRef) g.Value {
    return .{ .schema = 0, .body = .{ .reference = ref } };
}

test "one eight and sixty-four branches share immutable environments and blobs" {
    var mismatches: usize = 0;
    for ([_]usize{ 1, 8, 64 }) |count| {
        var statistics: @import("store.zig").Statistics = .{};
        var store: Store = .{ .allocator = allocator, .statistics = &statistics };
        defer store.deinit();
        const bytes = try allocator.alloc(u8, 65539);
        defer allocator.free(bytes);
        @memset(bytes, 0x5a);
        // Canonical length 65536 followed by a 64 KiB pointer-free payload.
        @memcpy(bytes[0..3], &[_]u8{ 0x80, 0x80, 0x04 });
        const schemas: []const data.program.Schema = &.{.bytes};
        const blob = try store.literal(schemas, .{ .schema = 0, .bytes = bytes });
        const outer = try store.add(.{ .region = .{ .descriptor = 0, .outer = null, .obligations = &.{} } });
        const shared = try store.add(.{ .cell = .{ .schema = 0, .region = outer, .value = blob } });
        const handler = try store.add(.{ .handler = .{ .definition = 0, .state = &.{value(shared)}, .evidence = null, .region = outer } });
        const delimiter = try store.add(.{ .attachment = .{ .handler = handler, .outer = null, .return_to = null, .phase = .suspended, .region = outer } });
        const local = try store.add(.{ .region = .{ .descriptor = 1, .outer = outer, .obligations = &.{} } });
        const scope = try store.add(.{ .region_scope = .{ .source_block = 0, .region = local, .return_to = delimiter } });
        const cell = try store.add(.{ .cell = .{ .schema = 0, .region = local, .value = blob } });
        const immutable = try store.add(.{ .environment = .{ .values = &.{ blob, value(shared) }, .tail = null } });
        const rebased = try store.add(.{ .environment = .{ .values = &.{ value(cell), value(cell) }, .tail = immutable } });
        const position = try store.add(.{ .continuation = .{ .source_block = 0, .arguments = &.{ value(immutable), value(rebased) }, .parent = scope, .evidence = delimiter, .region = local } });
        const template: g.Capture = .{ .schema = 0, .capture = position, .delimiter = delimiter, .evidence = delimiter };
        const before = statistics.added_nodes;
        var cells = std.AutoHashMap(u64, void).init(allocator);
        defer cells.deinit();
        var shared_environments: usize = 0;
        for (0..count) |_| {
            const copied = try @import("clone.zig").instantiate(allocator, &store, template);
            defer allocator.free(copied.use_site_capabilities);
            const continuation = (try store.get(copied.capture.?)).continuation;
            if (continuation.arguments[0].?.body.reference.id == immutable.id) shared_environments += 1;
            const environment = (try store.get(continuation.arguments[1].?.body.reference)).environment;
            const left = environment.values[0].body.reference;
            try std.testing.expectEqual(left.id, environment.values[1].body.reference.id);
            try std.testing.expect(left.id != cell.id);
            try std.testing.expect(!(try cells.getOrPut(left.id)).found_existing);
            const copied_cell = (try store.get(left)).cell;
            try std.testing.expectEqual(continuation.region.?.id, copied_cell.region.id);
            try std.testing.expectEqual(blob.body.blob.id, copied_cell.value.?.body.blob.id);
            try std.testing.expectEqual(handler.id, (try store.get(copied.delimiter)).attachment.handler.id);
            try std.testing.expectEqual(outer.id, (try store.get(copied_cell.region)).region.outer.?.id);
            // Updating a branch cannot alter the template or another branch.
            try store.replace(left, .{ .cell = .{ .schema = 0, .region = copied_cell.region, .value = null } });
            try std.testing.expect((try store.get(cell)).cell.value != null);
        }
        std.debug.print("branches={d} cloned_nodes={d} shared_environments={d} blob_copies={d} payload_bytes={d}\n", .{ count, statistics.added_nodes - before, shared_environments, store.blobs.items.len, statistics.copied_blob_bytes });
        try std.testing.expectEqual(@as(usize, 1), store.blobs.items.len);
        try std.testing.expectEqual(bytes.len, statistics.copied_blob_bytes);
        mismatches += count - shared_environments;
    }
    try std.testing.expectEqual(@as(usize, 0), mismatches);
}

test "collection and canonicalization traverse each reachable node and edge once" {
    var statistics: @import("store.zig").Statistics = .{};
    var store: Store = .{ .allocator = allocator, .statistics = &statistics };
    defer store.deinit();
    const shared = try store.add(.{ .environment = .{ .values = &.{}, .tail = null } });
    const cycle = try store.add(.{ .environment = .{ .values = &.{ value(shared), value(shared) }, .tail = null } });
    try store.replace(shared, .{ .environment = .{ .values = &.{}, .tail = cycle } });
    _ = try store.add(.{ .environment = .{ .values = &.{}, .tail = null } });
    const roots: g.Roots = .{ .current = cycle, .evidence = shared };
    try store.collect(roots);
    try std.testing.expectEqual(@as(u64, 2), statistics.traced_nodes);
    try std.testing.expectEqual(@as(u64, 5), statistics.traced_edges);
    try std.testing.expectEqual(@as(u64, 3), statistics.swept_slots);
    var measured: data.graph_order.Statistics = .{};
    var normalized = try data.graph_order.canonicalize(allocator, store.state(@splat(0), .active, roots), &measured);
    defer normalized.deinit();
    try std.testing.expectEqual(statistics.traced_nodes, measured.nodes);
    try std.testing.expectEqual(statistics.traced_edges, measured.edges);
    try std.testing.expectEqual(@as(u64, 2), measured.remapped_nodes);
}

test "collection reuses scratch and clears marks when cyclic roots disappear" {
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    var store: Store = .{ .allocator = failing.allocator() };
    defer store.deinit();
    const root = try store.add(.{ .environment = .{ .values = &.{}, .tail = null } });
    try store.replace(root, .{ .environment = .{ .values = &.{value(root)}, .tail = root } });
    try store.collect(.{ .current = root });
    failing.fail_index = failing.alloc_index;
    try store.collect(.{ .current = root });
    try store.collect(.{});
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectError(error.InvalidReference, store.get(root));
    const reused = try store.add(.{ .environment = .{ .values = &.{}, .tail = null } });
    try std.testing.expectEqual(root.id, reused.id);
    try store.collect(.{ .current = reused });
    _ = try store.get(reused);
}

fn ownedInsertionCase(a: std.mem.Allocator) !void {
    var store: Store = .{ .allocator = a };
    defer store.deinit();
    const ref = blk: {
        const values = try a.alloc(g.Value, 2);
        errdefer a.free(values);
        @memset(values, .{ .schema = 0, .body = .{ .scalar = @splat(7) } });
        const ref = try store.addOwned(.{ .control = .{ .block = 0, .arguments = values } });
        try std.testing.expectEqual(values.ptr, (try store.get(ref)).control.arguments.ptr);
        break :blk ref;
    };
    // Borrowed replacement remains safe even when it aliases the previous node.
    const previous = (try store.get(ref)).control;
    try store.replace(ref, .{ .control = .{ .block = 0, .arguments = previous.arguments[1..] } });
    try std.testing.expectEqual(@as(usize, 1), (try store.get(ref)).control.arguments.len);
    try store.collect(.{ .current = ref });
    try store.collect(.{});
}

test "owned insertion transfers buffers once and borrowed replacement tolerates aliases" {
    try std.testing.checkAllAllocationFailures(allocator, ownedInsertionCase, .{});
}

fn ownedExitReplacementCase(a: std.mem.Allocator) !void {
    const storage = @import("store.zig");
    var store: Store = .{ .allocator = a };
    defer store.deinit();
    const scalar: g.Value = .{ .schema = 0, .body = .{ .scalar = @splat(1) } };
    const ref = try store.add(.{ .exit = .{
        .reason = .{ .failure = scalar },
        .cancellation = .{ .text = "first cancellation" },
        .cleanup_failures = &.{scalar},
        .discarded = &.{scalar},
    } });
    {
        const replacement = try storage.duplicate(g.Node, a, try store.get(ref));
        errdefer storage.release(g.Node, a, replacement);
        try store.replaceOwned(ref, replacement);
    }
    const result = (try store.get(ref)).exit;
    try std.testing.expectEqualStrings("first cancellation", result.cancellation.?.text);
    try std.testing.expectEqualSlices(g.Value, &.{scalar}, result.cleanup_failures);
    try std.testing.expectEqualSlices(g.Value, &.{scalar}, result.discarded);
}

test "owned exit replacement retains nested cancellation bytes and both field buffers" {
    try std.testing.checkAllAllocationFailures(allocator, ownedExitReplacementCase, .{});
}
