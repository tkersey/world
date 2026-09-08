//! Standalone malformed-State producer. Never imported by the production root.
const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const fixtures = @import("tests.zig");
const p = data.program;
const g = data.graph;
const Row = struct { name: []const u8, input_hex: []const u8, rejection: []const u8 };
const Collector = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList(Row) = .empty,
    fn emit(self: *Collector, name: []const u8, program: p.Program, state: g.State) !void {
        if (data.state_admission.validate(self.allocator, program, state)) |_| return error.ExpectedInvalidState else |err| {
            if (err == error.OutOfMemory) return err;
        }
        const image = try self.allocator.alloc(u8, try data.image.encodedLength(program));
        _ = try data.image.encode(self.allocator, program, image);
        const saved = try data.snapshot.emit(self.allocator, state, self.allocator, null);
        var normalized = saved.normalized;
        defer normalized.deinit();
        const rejection = if (process.run(self.allocator, .{ .program = .{ .image = image }, .instance = .{ .snapshot = saved.bytes } })) |result| blk: {
            var outcome = result;
            outcome.deinit();
            break :blk @as(?[]const u8, null);
        } else |err| if (err == error.OutOfMemory) return err else @as(?[]const u8, @errorName(err));
        if (rejection == null) return error.PublishedMalformedSuccessor;
        const input: data.protocol.Input = .{ .mode = .run, .image = image, .instance = .{ .state = saved.bytes }, .control = .{ .continue_value = null } };
        const bytes = try self.allocator.alloc(u8, try data.protocol.encodedLength(data.protocol.Input, input));
        _ = try data.protocol.encode(data.protocol.Input, self.allocator, input, bytes);
        const hex = try self.allocator.alloc(u8, bytes.len * 2);
        const digits = "0123456789abcdef";
        for (bytes, 0..) |byte, index| {
            hex[index * 2] = digits[byte >> 4];
            hex[index * 2 + 1] = digits[byte & 15];
        }
        try self.rows.append(self.allocator, .{ .name = name, .input_hex = hex, .rejection = rejection.? });
    }
};
fn stateBytes(outcome: process.Outcome) ?[]const u8 {
    return switch (outcome.record) {
        .progressed => |state| state,
        .yielded => |state| state,
        .requested => |request| request.state,
        else => null,
    };
}
fn pendingCases(collector: *Collector) !void {
    const a = collector.allocator;
    var program = try data.canonical.normalize(a, fixtures.suspended);
    defer program.deinit();
    var parked = try process.run(a, .{ .program = .{ .records = program.program }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var decoded = try data.snapshot.decodeGraph(a, parked.record.requested.state);
    defer decoded.deinit();
    try data.state_admission.validate(a, program.program, decoded.state);
    const nodes = @constCast(decoded.state.nodes);
    const index: usize = @intCast(decoded.state.roots.pending.?.id);
    const original = nodes[index];
    nodes[index].pending.effect = program.program.effects.len;
    try collector.emit("pending-effect", program.program, decoded.state);
    nodes[index] = original;
    nodes[index].pending.continuation = .{ .id = index };
    try collector.emit("pending-continuation", program.program, decoded.state);
    nodes[index] = original;
    decoded.state.program_identity[0] ^= 1;
    try collector.emit("state-program-identity", program.program, decoded.state);
    decoded.state.program_identity[0] ^= 1;
    decoded.state.status = .active;
    try collector.emit("state-root-status", program.program, decoded.state);
}
fn blobCases(collector: *Collector) !void {
    const a = collector.allocator;
    var source = fixtures.suspended;
    source.schemas = &.{.bytes};
    source.constants = &.{.{ .schema = 0, .bytes = &.{ 1, 0x80 } }};
    var program = try data.canonical.normalize(a, source);
    defer program.deinit();
    var parked = try process.run(a, .{ .program = .{ .records = program.program }, .instance = .{ .initial_args = &.{} } });
    defer parked.deinit();
    var decoded = try data.snapshot.decodeGraph(a, parked.record.requested.state);
    defer decoded.deinit();
    try data.state_admission.validate(a, program.program, decoded.state);
    const blobs = @constCast(decoded.state.blobs);
    const original = blobs[0];
    blobs[0].schema = 99;
    try collector.emit("blob-schema", program.program, decoded.state);
    blobs[0] = original;
    blobs[0].bytes = &.{ 2, 0x80 };
    try collector.emit("blob-value", program.program, decoded.state);
}
fn captureCases(collector: *Collector) !void {
    const a = collector.allocator;
    var one = false;
    var multi = false;
    var region_alias = false;
    for ([_]p.Program{ fixtures.deep, fixtures.choice, fixtures.local_regions }) |original| {
        var program = try data.canonical.normalize(a, original);
        defer program.deinit();
        var outcome = try process.advance(a, .{ .program = .{ .records = program.program }, .instance = .{ .initial_args = &.{} } });
        defer outcome.deinit();
        var iterations: usize = 0;
        while (stateBytes(outcome)) |bytes| {
            iterations += 1;
            if (iterations > 1000) return error.FiniteFixtureHarnessLimit;
            var saved = try data.snapshot.decodeGraph(a, bytes);
            defer saved.deinit();
            try data.state_admission.validate(a, program.program, saved.state);
            const nodes = @constCast(saved.state.nodes);
            for (nodes, 0..) |node, index| {
                if ((node == .one_shot and !one) or (node == .multi_template and !multi)) {
                    const capture = if (node == .one_shot) node.one_shot else node.multi_template;
                    const delimiter: usize = @intCast(capture.delimiter.id);
                    const before = nodes[delimiter];
                    nodes[delimiter].attachment.phase = .active;
                    try collector.emit(if (node == .one_shot) "one-shot-delimiter" else "multi-delimiter", program.program, saved.state);
                    nodes[delimiter] = before;
                    if (node == .one_shot) one = true else multi = true;
                }
                if (node == .cell and !region_alias) for (nodes) |other| {
                    if (other != .cell or other.cell.schema != node.cell.schema or other.cell.region.id == node.cell.region.id) continue;
                    nodes[index].cell.region = other.cell.region;
                    try collector.emit("local-region-alias", program.program, saved.state);
                    nodes[index] = node;
                    region_alias = true;
                    break;
                };
            }
            if (outcome.record == .requested) break;
            const next = try process.advance(a, .{ .program = .{ .records = program.program }, .instance = .{ .snapshot = bytes } });
            outcome.deinit();
            outcome = next;
        }
    }
    if (!one or !multi or !region_alias) return error.MissingFixture;
}
fn replaceOwned(comptime T: type, value: *T, from: p.Id, to: p.Id) bool {
    if (T == g.Value) {
        if (value.body == .owned and value.body.owned.node.id == from) {
            value.body.owned.node.id = to;
            return true;
        }
        return false;
    }
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (info.child != u8) for (@constCast(value.*)) |*child| if (replaceOwned(info.child, child, from, to)) return true;
        },
        .array => |info| {
            if (info.child != u8) for (value) |*child| if (replaceOwned(info.child, child, from, to)) return true;
        },
        .optional => |info| {
            if (value.*) |*child| return replaceOwned(info.child, child, from, to);
        },
        .@"struct" => |info| inline for (info.fields) |field| {
            if (replaceOwned(field.type, &@field(value, field.name), from, to)) return true;
        },
        .@"union" => |info| inline for (info.fields) |field| {
            if (std.mem.eql(u8, @tagName(value.*), field.name)) return replaceOwned(field.type, &@field(value, field.name), from, to);
        },
        else => {},
    }
    return false;
}
fn duplicateToken(collector: *Collector, image: []const u8) !void {
    const a = collector.allocator;
    var program = try data.image.decode(a, image);
    defer program.deinit();
    var yielded = try process.run(a, .{ .program = .{ .image = image }, .instance = .{ .initial_args = &.{} } });
    defer yielded.deinit();
    if (yielded.record != .yielded) return error.ExpectedOwnedTokensAtYield;
    var saved = try data.snapshot.decodeGraph(a, yielded.record.yielded);
    defer saved.deinit();
    try data.state_admission.validate(a, program.program, saved.state);
    const nodes = @constCast(saved.state.nodes);
    for (nodes, 0..) |first, from| if (first == .one_shot) {
        for (nodes, 0..) |second, to| if (second == .one_shot and from != to and first.one_shot.schema == second.one_shot.schema) {
            var completed = try process.run(a, .{ .program = .{ .image = image }, .instance = .{ .snapshot = yielded.record.yielded } });
            defer completed.deinit();
            if (completed.record != .completed or completed.record.completed[0] != 1) return error.InvalidPositiveCounterpart;
            for (nodes) |*node| if (replaceOwned(g.Node, node, from, to)) {
                try collector.emit("duplicate-token-custody", program.program, saved.state);
                return;
            };
        };
    };
    return error.MissingTwoSameTypeTokens;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const image = try input.interface.allocRemaining(a, .limited(16 << 20));
    var collector: Collector = .{ .allocator = a };
    try pendingCases(&collector);
    try blobCases(&collector);
    try captureCases(&collector);
    const return_paths = @import("return_path_tests.zig");
    for (std.enums.values(return_paths.Kind)) |kind| {
        var example = try return_paths.witness(a, kind);
        defer example.deinit();
        const name = try std.fmt.allocPrint(a, "return-path-{s}", .{@tagName(kind)});
        try collector.emit(name, example.program.program, example.state.state);
    }
    const capture_states = @import("capture_state_tests.zig");
    for ([_]bool{ false, true }) |multi| {
        var example = try capture_states.witness(a, multi, false);
        defer example.deinit();
        const name = if (multi) "multi-captured-handler-state" else "one-shot-captured-handler-state";
        try collector.emit(name, example.program.program, example.state.state);
    }
    try duplicateToken(&collector, image);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .format = "world-v2-state-rejections/v1", .cases = collector.rows.items }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
