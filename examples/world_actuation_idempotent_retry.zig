const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const ctx = common.context(.{
        .label = "idempotent.retry",
        .kind = .tool_like,
        .class = .idempotent_mutation,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_7001,
    });
    const fresh = try common.execute(ctx, world.Actuation.Policy.strict_fresh, .{
        .fixture = .{ .frame_response_fingerprint = 0xacc7_7002 },
    }, 0);
    var journal = world.Actuation.Journal.init();
    defer journal.deinit(allocator);
    try journal.appendCommit(allocator, fresh.commit_value);
    try journal.appendReceipt(allocator, fresh.receipt);

    const replay_ctx = common.context(.{
        .label = "idempotent.retry",
        .kind = .tool_like,
        .class = .idempotent_mutation,
        .mode = .replay,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_7001,
    });
    const replay_seed = common.receiptWithResponseFingerprint(fresh.receipt, fresh.receipt.response_fingerprint, .replay);
    const replay_source = world.Actuation.ReplaySource.init(.{ .receipts = &.{replay_seed} });
    const retry = try common.execute(replay_ctx, world.Actuation.Policy.fixture_test, .{
        .replay = .{ .source = replay_source },
    }, 1);
    const recorded = journal.lookupByIdempotencyKey(ctx.key.key_fingerprint) != null;

    try stdout.print("idempotency_key={x}\n", .{ctx.key.key_fingerprint});
    try stdout.print("fresh_call_count=1\n", .{});
    try stdout.print("retry_replayed={}\n", .{recorded and retry.receipt.replayed and !retry.fresh_called});
    try stdout.flush();
}
