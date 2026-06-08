const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const fresh_ctx = common.context(.{
        .label = "fixture.replay.verify",
        .kind = .fixture,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_3001,
    });
    const fresh = try common.execute(fresh_ctx, world.Actuation.Policy.fixture_test, .{
        .fixture = .{ .frame_response_fingerprint = 0xacc7_3002 },
    }, 1);

    const replay_ctx = common.context(.{
        .label = "fixture.replay.verify",
        .kind = .fixture,
        .mode = .replay,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_3001,
    });
    const replay_seed = common.receiptWithResponseFingerprint(fresh.receipt, fresh.receipt.response_fingerprint, .replay);
    const replay_source = world.Actuation.ReplaySource.init(.{ .receipts = &.{replay_seed} });
    const replay = try common.execute(replay_ctx, world.Actuation.Policy.fixture_test, .{
        .replay = .{ .source = replay_source },
    }, 2);

    const verify_ctx = common.context(.{
        .label = "fixture.replay.verify",
        .kind = .fixture,
        .mode = .verify,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_3001,
    });
    const changed = common.receiptWithResponseEvidence(fresh.receipt, 0xacc7_3999, 0xacc7_3003, .verify);
    const verify = try common.execute(verify_ctx, world.Actuation.Policy.fixture_test, .{
        .verify = .{
            .expected_receipt = fresh.receipt,
            .fresh_receipt = changed,
            .response_template = .{ .frame_response_fingerprint = 0xacc7_3003 },
        },
    }, 3);

    try stdout.print("fresh_receipt_count=1\n", .{});
    try stdout.print("replay_fresh_called={}\n", .{replay.fresh_called});
    try stdout.print("divergence_detected={}\n", .{!verify.verify_report.?.matched});
    try stdout.flush();
}
