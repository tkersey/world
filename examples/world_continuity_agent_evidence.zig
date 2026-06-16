const std = @import("std");
const world = @import("world");

fn receipt(args: struct {
    key: world.Actuation.IdempotencyKey,
    intent: u64,
    commit: u64,
    response: u64,
    capsule_fingerprint: u64,
}) world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = args.intent,
        .envelope_fingerprint = args.intent + 1,
        .decision_fingerprint = args.intent + 2,
        .commit_fingerprint = args.commit,
        .response_fingerprint = args.response,
        .frame_response_fingerprint = args.response + 1,
        .actuator_ref_fingerprint = args.key.actuator_ref_fingerprint,
        .idempotency_key_fingerprint = args.key.key_fingerprint,
        .request_fingerprint = args.key.request_fingerprint,
        .target_ref_fingerprint = args.key.target_ref_fingerprint,
        .world_surface_fingerprint = args.key.world_surface_fingerprint,
        .world_port_id = args.key.world_port_id,
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
        .capsule_fingerprint = args.capsule_fingerprint,
    });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    var capsule = try world.Capsule.freezeRunspace(&runspace, .{});
    defer capsule.deinit(allocator);
    const capsule_ref = try world.Capsule.store(&vault, capsule);

    const model_key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4404_0001,
        .world_surface_fingerprint = 0x4404_0002,
        .world_port_id = 0,
        .request_fingerprint = 0x4404_0003,
        .actuator_ref_fingerprint = 0x4404_0100,
    });
    const tool_key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4404_0001,
        .world_surface_fingerprint = 0x4404_0002,
        .world_port_id = 1,
        .request_fingerprint = 0x4404_0004,
        .actuator_ref_fingerprint = 0x4404_0200,
    });
    _ = try world.Actuation.storeReceipt(&vault, receipt(.{
        .key = model_key,
        .intent = 0x4404_0010,
        .commit = 0x4404_0020,
        .response = 0x4404_0030,
        .capsule_fingerprint = capsule_ref.object_fingerprint,
    }));
    _ = try world.Actuation.storeReceipt(&vault, receipt(.{
        .key = tool_key,
        .intent = 0x4404_0040,
        .commit = 0x4404_0050,
        .response = 0x4404_0060,
        .capsule_fingerprint = capsule_ref.object_fingerprint,
    }));

    const actuation_index = world.Continuity.ActuationIndex.init(&vault);
    const model_receipts = try actuation_index.receiptsByActuator(model_key.actuator_ref_fingerprint);
    defer allocator.free(model_receipts);
    const tool_receipts = try actuation_index.receiptsByActuator(tool_key.actuator_ref_fingerprint);
    defer allocator.free(tool_receipts);
    const capsule_index = world.Continuity.CapsuleIndex.init(&vault);
    const completed_capsules = try capsule_index.completedCapsules();
    defer allocator.free(completed_capsules);

    try stdout.print("capsule_ref={x}\n", .{capsule_ref.ref_fingerprint});
    try stdout.print("model_receipt_count={d}\n", .{model_receipts.len});
    try stdout.print("tool_receipt_count={d}\n", .{tool_receipts.len});
    try stdout.print("final_result=continuity-agent-evidence-ok\n", .{});
    try stdout.flush();
}
