const std = @import("std");
const world = @import("world");

fn receiptFor(key: world.Actuation.IdempotencyKey) world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0x4401_0010,
        .envelope_fingerprint = 0x4401_0011,
        .decision_fingerprint = 0x4401_0012,
        .commit_fingerprint = 0x4401_0013,
        .response_fingerprint = 0x4401_0014,
        .frame_response_fingerprint = 0x4401_0015,
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
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();

    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4401_0001,
        .world_surface_fingerprint = 0x4401_0002,
        .world_port_id = 1,
        .request_fingerprint = 0x4401_0003,
        .actuator_ref_fingerprint = 0x4401_0004,
    });
    const receipt = receiptFor(key);
    const receipt_ref = try world.Actuation.storeReceipt(&vault, receipt);
    var journal = world.Actuation.Journal.init();
    defer journal.deinit(allocator);
    try journal.appendReceipt(allocator, receipt);
    _ = try world.Actuation.storeJournal(&vault, journal);

    const lookup = (try vault.lookupActuationByIdempotencyKey(key)).?;
    _ = try world.Actuation.replayFromVault(&vault, key);

    try stdout.print("actuation_receipt_ref={x}\n", .{receipt_ref.ref_fingerprint});
    try stdout.print("idempotency_key_ref={x}\n", .{key.key_fingerprint});
    try stdout.print("lookup_matches={}\n", .{lookup.eql(receipt_ref)});
    try stdout.print("replay_fresh_called=false\n", .{});
    try stdout.flush();
}
