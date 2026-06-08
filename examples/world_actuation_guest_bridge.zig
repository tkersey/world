const common = @import("world_actuation_common.zig");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const ctx = common.context(.{
        .label = "guest.bridge",
        .kind = .guest_bridge,
        .world_port_id = 0,
        .request_fingerprint = 0xacc7_6001,
    });
    const execution = try common.execute(ctx, world.Actuation.Policy.fixture_test, .{
        .fixture = .{ .frame_response_fingerprint = 0xacc7_6002 },
    }, 1);
    const receipt_refs = [_]u64{execution.receipt.receipt_fingerprint};
    const vector = world.Guest.ConformanceVector.init(.{
        .name = "actuation-guest-bridge",
        .kind = .one_port,
        .target_ref_fingerprint = ctx.target_ref_fingerprint,
        .expected_pending_frame_fingerprints = &.{ctx.request_fingerprint},
        .actuation_receipt_fingerprints = &receipt_refs,
    });
    const summary = world.Guest.RunResultSummary{
        .status = .done,
        .result_fingerprint = execution.response.response_fingerprint,
        .pending_frame_fingerprints = &.{ctx.request_fingerprint},
        .actuation_receipt_fingerprints = &receipt_refs,
    };
    const report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .native_run_result = summary,
        .native_abi_result = summary,
        .status_sequence_match = true,
        .pending_frame_match = true,
        .final_result_match = true,
        .receipt_match = true,
    });

    try stdout.print("guest_request_fingerprint={x}\n", .{ctx.request_fingerprint});
    try stdout.print("actuation_receipt_fingerprint={x}\n", .{execution.receipt.receipt_fingerprint});
    try stdout.print("conformance={}\n", .{report.blockers.len == 0 and report.receipt_match});
    try stdout.flush();
}
