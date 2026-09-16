const std = @import("std");
const data = @import("boundary_data_v2");
const c = @import("custody.zig");
const testing = std.testing;
const scopes = [_]data.activation.CustodyScope{
    .{}, .{ .parent = 0 }, .{ .parent = 0 }, .{ .parent = 1 },
};

fn expect(custody: *c.Custody, state: c.State, order: []const usize) !void {
    const actual = try custody.ordered(state, testing.allocator);
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(usize, order, actual);
}

test "custody splices scope exits and preserves retained versions" {
    var custody = try c.Custody.init(testing.allocator);
    defer custody.deinit();
    var state = try custody.create(8, scopes.len);
    try custody.establish(&state, &scopes, 0);
    try custody.moveTo(&state, &scopes, 1);
    try custody.establish(&state, &scopes, 1);
    try custody.establish(&state, &scopes, 2);
    const old = try custody.fork(state);
    try expect(&custody, state, &.{ 1, 2, 0 });
    try custody.moveTo(&state, &scopes, 0);
    try expect(&custody, state, &.{ 1, 2, 0 });
    try custody.moveTo(&state, &scopes, 2);
    try custody.establish(&state, &scopes, 3);
    try expect(&custody, state, &.{ 3, 1, 2, 0 });
    try custody.remove(&state, 2);
    try custody.remove(&state, 0);
    try custody.establish(&state, &scopes, 4);
    try expect(&custody, state, &.{ 3, 4, 1 });
    try custody.moveTo(&state, &scopes, 1);
    try custody.establish(&state, &scopes, 2);
    try expect(&custody, state, &.{ 2, 3, 4, 1 });
    try custody.remove(&state, 1);
    try custody.remove(&state, 2);
    try expect(&custody, state, &.{ 3, 4 });
    try expect(&custody, old, &.{ 1, 2, 0 });
    for (0..1000) |_| {
        try custody.establish(&state, &scopes, 7);
        try custody.remove(&state, 7);
    }
    try testing.expect(custody.nodes.statistics.live_pages <= 2);
    custody.release(state);
    custody.release(old);
    try testing.expectEqual(0, custody.nodes.statistics.live_pages);
}

fn failureCase(allocator: std.mem.Allocator) !void {
    var custody = try c.Custody.init(allocator);
    defer custody.deinit();
    var state = try custody.create(128, scopes.len);
    try custody.establish(&state, &scopes, 0);
    try custody.moveTo(&state, &scopes, 3);
    try custody.establish(&state, &scopes, 100);
    _ = try custody.fork(state);
    try custody.moveTo(&state, &scopes, 2);
    try custody.establish(&state, &scopes, 64);
    try custody.remove(&state, 100);
}

test "custody partial construction releases its physical owners on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, failureCase, .{});
}
