const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var source = world.Continuity.MemoryVault.init(allocator);
    defer source.deinit();
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();

    var capsule = try world.Capsule.freezeRunspace(&runspace, .{});
    defer capsule.deinit(allocator);
    const capsule_ref = try world.Capsule.store(&source, capsule);
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4402_0001,
        .world_surface_fingerprint = 0x4402_0002,
        .world_port_id = 2,
        .request_fingerprint = 0x4402_0003,
        .actuator_ref_fingerprint = 0x4402_0004,
    });
    const receipt = world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0x4402_0010,
        .envelope_fingerprint = 0x4402_0011,
        .decision_fingerprint = 0x4402_0012,
        .commit_fingerprint = 0x4402_0013,
        .response_fingerprint = 0x4402_0014,
        .frame_response_fingerprint = 0x4402_0015,
        .actuator_ref_fingerprint = key.actuator_ref_fingerprint,
        .idempotency_key_fingerprint = key.key_fingerprint,
        .request_fingerprint = key.request_fingerprint,
        .target_ref_fingerprint = key.target_ref_fingerprint,
        .world_surface_fingerprint = key.world_surface_fingerprint,
        .world_port_id = key.world_port_id,
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
    });
    const receipt_ref = try world.Actuation.storeReceipt(&source, receipt);

    var bundle = try world.Continuity.Bundle.exportFromVault(&source, &.{ capsule_ref, receipt_ref }, .{ .include_dependencies = false });
    defer bundle.deinit();
    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);

    var target = world.Continuity.MemoryVault.init(allocator);
    defer target.deinit();
    var manifest = try world.Continuity.Bundle.importIntoVault(&target, bytes, .{ .allow_external_dependencies = true });
    defer manifest.deinit(allocator);
    var capsule_graph = try world.Continuity.CapsuleGraph.fromCapsule(&target, capsule_ref);
    defer capsule_graph.deinit();
    var actuation_graph = try world.Continuity.ActuationGraph.fromReceipt(&target, receipt_ref);
    defer actuation_graph.deinit();

    try stdout.print("bundle_fingerprint={x}\n", .{bundle.manifest.manifest_fingerprint});
    try stdout.print("imported_object_count={d}\n", .{target.objectCount()});
    try stdout.print("capsule_restored_to_inspectable_state={}\n", .{capsule_graph.restorable and actuation_graph.receipt_refs.len == 1});
    try stdout.flush();
}
