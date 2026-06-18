const std = @import("std");
const world = @import("world");

fn receiptFor(port_id: u32, key_fingerprint: u64) world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0x4506_0010 + port_id,
        .envelope_fingerprint = 0x4506_0020 + port_id,
        .decision_fingerprint = 0x4506_0030 + port_id,
        .commit_fingerprint = 0x4506_0040 + port_id,
        .response_fingerprint = 0x4506_0050 + port_id,
        .frame_response_fingerprint = 0x4506_0060 + port_id,
        .actuator_ref_fingerprint = 0x4506_0004 + port_id,
        .idempotency_key_fingerprint = key_fingerprint,
        .request_fingerprint = 0x4506_0100 + port_id,
        .target_ref_fingerprint = 0x4506_0001,
        .world_surface_fingerprint = 0x4506_0002,
        .world_port_id = port_id,
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
    });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();
    var session = try world.Continuity.Session.init(allocator, &vault, world.Continuity.PersistPolicy.full_local_evidence());
    var sink = world.Continuity.Sink.init(&session, world.Continuity.SinkPolicy.full_local_evidence());
    _ = (try sink.recordActuationReceipt(receiptFor(0, 0x4506_0200))).?;
    const tool_ref = (try sink.recordActuationReceipt(receiptFor(1, 0x4506_0201))).?;
    _ = tool_ref;
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    const capsule_ref = (try sink.recordCompletedCapsule(&runspace, .{})).?;
    var bundle = try session.exportBundle(&.{capsule_ref});
    defer bundle.deinit();
    const replay = try world.Continuity.Chronicle.replay(&vault, .{});

    try stdout.print("capsule_ref={x}\n", .{capsule_ref.ref_fingerprint});
    try stdout.print("model_receipt_count=1\n", .{});
    try stdout.print("tool_receipt_count=1\n", .{});
    try stdout.print("bundle_fingerprint={x}\n", .{bundle.manifest.manifest_fingerprint});
    try stdout.print("projection_replay={}\n", .{replay.mismatch_count == 0});
    try stdout.flush();
}
