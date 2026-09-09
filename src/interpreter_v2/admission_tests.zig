//! Malformed logical States are rejected before an observable transition.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const fixtures = @import("tests.zig");
const p = data.program;
const g = data.graph;
const allocator = std.testing.allocator;

fn rejected(program: p.Program, state: g.State) !void {
    if (data.state_admission.validate(allocator, program, state)) |_| return error.ExpectedAdmissionRejection else |err| {
        try std.testing.expect(err != error.OutOfMemory and err != error.Capacity);
    }
    if (process.run(allocator, .{ .program = .{ .records = program }, .instance = .{ .records = state } })) |result| {
        var outcome = result;
        outcome.deinit();
        return error.PublishedMalformedSuccessor;
    } else |err| try std.testing.expect(err != error.OutOfMemory and err != error.Capacity);
}
fn bytes(outcome: process.Outcome) ?[]const u8 {
    return switch (outcome.record) {
        .progressed => |state| state,
        .yielded => |state| state,
        .requested => |request| request.state,
        else => null,
    };
}

test "pending contracts, continuation types and State identity reject before any request" {
    var normalized = try data.canonical.normalize(allocator, fixtures.suspended);
    defer normalized.deinit();
    var parked = try process.run(allocator, .{ .program = .{ .records = fixtures.suspended }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var decoded = try data.snapshot.decodeGraph(allocator, parked.record.requested.state);
    defer decoded.deinit();
    try data.state_admission.validate(allocator, normalized.program, decoded.state);
    const nodes = @constCast(decoded.state.nodes);
    const pending_id: usize = @intCast(decoded.state.roots.pending.?.id);
    const original = nodes[pending_id];
    nodes[pending_id].pending.effect = normalized.program.effects.len;
    try rejected(normalized.program, decoded.state);
    nodes[pending_id] = original;
    nodes[pending_id].pending.payload.schema = normalized.program.schemas.len;
    try rejected(normalized.program, decoded.state);
    nodes[pending_id] = original;
    nodes[pending_id].pending.continuation = .{ .id = pending_id };
    try rejected(normalized.program, decoded.state);
    nodes[pending_id] = original;
    decoded.state.program_identity[0] ^= 1;
    try rejected(normalized.program, decoded.state);
    decoded.state.program_identity[0] ^= 1;
    decoded.state.status = .active;
    try rejected(normalized.program, decoded.state);
    decoded.state.status = .parked;
    try data.state_admission.validate(allocator, normalized.program, decoded.state);
    var retry = try process.run(allocator, .{ .program = .{ .records = normalized.program }, .instance = .{ .records = decoded.state } });
    defer retry.deinit();
    try std.testing.expectEqualSlices(u8, parked.record.requested.state, retry.record.requested.state);
    try std.testing.expectEqualSlices(u8, parked.record.requested.request, retry.record.requested.request);
}

test "blob schemas, complete values and blob references cannot bypass State admission" {
    var program = fixtures.suspended;
    program.schemas = &.{.bytes};
    program.constants = &.{.{ .schema = 0, .bytes = &.{ 1, 0x80 } }};
    var normalized = try data.canonical.normalize(allocator, program);
    defer normalized.deinit();
    var parked = try process.run(allocator, .{ .program = .{ .records = program }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var decoded = try data.snapshot.decodeGraph(allocator, parked.record.requested.state);
    defer decoded.deinit();
    try data.state_admission.validate(allocator, normalized.program, decoded.state);
    const blobs = @constCast(decoded.state.blobs);
    try std.testing.expectEqual(@as(usize, 1), blobs.len);
    const original = blobs[0];
    blobs[0].schema = 99;
    try rejected(normalized.program, decoded.state);
    blobs[0] = original;
    blobs[0].bytes = &.{ 2, 0x80 };
    try rejected(normalized.program, decoded.state);
    blobs[0] = original;
    const nodes = @constCast(decoded.state.nodes);
    const pending_id: usize = @intCast(decoded.state.roots.pending.?.id);
    const pending = nodes[pending_id];
    nodes[pending_id].pending.payload.body.blob.id = 99;
    try rejected(normalized.program, decoded.state);
    nodes[pending_id] = pending;
    try data.state_admission.validate(allocator, normalized.program, decoded.state);
}

test "captured delimiters and branch-local region aliases are validated across active continuations" {
    var one_shot = false;
    var multi = false;
    var local_alias = false;
    for ([_]p.Program{ fixtures.deep, fixtures.choice, fixtures.local_regions }) |program| {
        var normalized = try data.canonical.normalize(allocator, program);
        defer normalized.deinit();
        var outcome = try process.advance(allocator, .{ .program = .{ .records = program }, .instance = .{ .initial_args = &.{} } });
        defer outcome.deinit();
        var iterations: usize = 0;
        while (bytes(outcome)) |saved| {
            iterations += 1;
            try std.testing.expect(iterations < 1000); // Harness bound, never program fuel.
            var decoded = try data.snapshot.decodeGraph(allocator, saved);
            defer decoded.deinit();
            try data.state_admission.validate(allocator, normalized.program, decoded.state);
            const nodes = @constCast(decoded.state.nodes);
            for (nodes, 0..) |node, index| {
                if ((node == .one_shot and !one_shot) or (node == .multi_template and !multi)) {
                    const capture = if (node == .one_shot) node.one_shot else node.multi_template;
                    const delimiter_id: usize = @intCast(capture.delimiter.id);
                    const delimiter = nodes[delimiter_id];
                    try std.testing.expect(delimiter == .attachment and delimiter.attachment.phase == .suspended);
                    nodes[delimiter_id].attachment.phase = .active;
                    try rejected(normalized.program, decoded.state);
                    nodes[delimiter_id] = delimiter;
                    if (node == .one_shot) one_shot = true else multi = true;
                }
                if (node == .cell and !local_alias) for (nodes) |other| {
                    if (other != .cell or other.cell.schema != node.cell.schema or other.cell.region.id == node.cell.region.id) continue;
                    nodes[index].cell.region = other.cell.region;
                    try rejected(normalized.program, decoded.state);
                    nodes[index] = node;
                    local_alias = true;
                    break;
                };
            }
            try data.state_admission.validate(allocator, normalized.program, decoded.state);
            if (outcome.record == .requested) break;
            const next = try process.advance(allocator, .{ .program = .{ .records = normalized.program }, .instance = .{ .snapshot = saved } });
            outcome.deinit();
            outcome = next;
        }
    }
    try std.testing.expect(one_shot and multi and local_alias);
}
