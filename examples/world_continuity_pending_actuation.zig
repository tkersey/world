const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();

    const manifest = world.Capsule.Manifest.init(.{
        .kind = .completed_assembly,
        .root_target_ref_fingerprint = 0x4403_0001,
        .actuation_intent_fingerprints = &.{0x4403_0010},
        .normal_form = .quiescent_completed,
    });
    const runspace_image = world.Capsule.RunspaceImage.init(.{
        .runspace_fingerprint = 0x4403_0002,
        .runspace_report_fingerprint = 0x4403_0003,
        .actuation_intent_refs = &.{0x4403_0010},
    });
    const image = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = runspace_image,
        .actuation_intent_refs = &.{0x4403_0010},
    });
    const capsule_ref = try world.Capsule.store(&vault, image);
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4403_0001,
        .world_surface_fingerprint = 0x4403_0004,
        .world_port_id = 3,
        .request_fingerprint = 0x4403_0005,
        .actuator_ref_fingerprint = 0x4403_0006,
    });
    var graph = try world.Continuity.Recovery.preflightPendingActuation(&vault, capsule_ref, key, {});
    defer graph.deinit();

    try stdout.print("capsule_ref={x}\n", .{capsule_ref.ref_fingerprint});
    try stdout.print("pending_actuation_count={d}\n", .{graph.actuation_intent_refs.len});
    try stdout.print("local_fresh_actuation_required={}\n", .{graph.local_fresh_actuation_required});
    try stdout.flush();
}
