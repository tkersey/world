const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const root_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const manifest = world.Capsule.Manifest.init(.{
        .kind = .completed_assembly,
        .root_target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .link_plan_fingerprint = 0x5150_d001,
        .link_certificate_fingerprint = 0x5150_d002,
        .assembly_fingerprint = 0x5150_d003,
        .normal_form = .quiescent_completed,
    });
    const runspace_image = world.Capsule.RunspaceImage.init(.{
        .runspace_fingerprint = 0x5150_d004,
        .runspace_report_fingerprint = 0x5150_d005,
    });
    const link_image = world.Capsule.LinkImage.init(.{
        .link_plan_fingerprint = 0x5150_d001,
        .link_certificate_fingerprint = 0x5150_d002,
        .assembly_fingerprint = 0x5150_d003,
        .linker_policy_fingerprint = 0x5150_d006,
        .catalog_fingerprint = 0x5150_d007,
        .residual_import_set_fingerprint = 0x5150_d008,
    });
    const capsule = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = runspace_image,
        .link_image = link_image,
    });
    const thaw = try world.Capsule.verifyLink(capsule, 0x5150_d009, .{});

    try stdout.print("relink_rejected={}\n", .{thaw.relink_status == .rejected});
    try stdout.print("blocker_tag={s}\n", .{@tagName(thaw.blockers[0])});
    try stdout.print("thaw_plan_fingerprint={x}\n", .{thaw.thaw_plan_fingerprint});
    try stdout.flush();
}
