const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const vector = world.Guest.ConformanceVector.init(.{
        .name = "capsule-guest",
        .kind = .one_port,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .expected_pending_frame_fingerprints = &.{0x5150_e001},
        .expected_final_result_fingerprint = 0x5150_e002,
        .expected_status_sequence = &.{ .initialized, .parked, .running, .done },
    });
    const guest_report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .native_run_result = .{
            .status = .done,
            .result_fingerprint = 0x5150_e002,
            .pending_frame_fingerprints = &.{0x5150_e001},
        },
        .native_abi_result = .{
            .status = .done,
            .result_fingerprint = 0x5150_e002,
            .pending_frame_fingerprints = &.{0x5150_e001},
        },
        .status_sequence_match = true,
        .pending_frame_match = true,
        .final_result_match = true,
    });
    const manifest = world.Capsule.Manifest.init(.{
        .kind = .inspect_only,
        .root_target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .guest_conformance_report_fingerprints = &.{guest_report.report_fingerprint},
        .normal_form = .quiescent_completed,
    });
    const capsule = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = world.Capsule.RunspaceImage.init(.{
            .runspace_fingerprint = 0x5150_e003,
            .runspace_report_fingerprint = 0x5150_e004,
        }),
        .guest_conformance_refs = &.{guest_report.report_fingerprint},
    });
    const restore = world.Capsule.RestoreReport.init(.{
        .capsule_image_fingerprint = capsule.image_fingerprint,
        .thaw_plan_fingerprint = (try world.Capsule.planThaw(capsule, target_ref.target_ref_fingerprint, 0, null, .{ .mode = .inspect_only })).thaw_plan_fingerprint,
        .restored_runspace_fingerprint = 0x5150_e005,
        .guest_conformance_refs = &.{guest_report.report_fingerprint},
        .accepted = true,
    });

    try stdout.print("guest_report_fingerprint={x}\n", .{guest_report.report_fingerprint});
    try stdout.print("restore_report_fingerprint={x}\n", .{restore.restore_report_fingerprint});
    try stdout.print("conformance={}\n", .{guest_report.status_sequence_match and guest_report.pending_frame_match and guest_report.final_result_match});
    try stdout.flush();
}
