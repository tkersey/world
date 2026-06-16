const std = @import("std");
const world = @import("world");

fn receiptFor(key: world.Actuation.IdempotencyKey, fresh: bool) world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = if (fresh) 0x4501_0010 else 0x4501_0030,
        .envelope_fingerprint = if (fresh) 0x4501_0011 else 0x4501_0031,
        .decision_fingerprint = if (fresh) 0x4501_0012 else 0x4501_0032,
        .commit_fingerprint = if (fresh) 0x4501_0013 else 0x4501_0033,
        .response_fingerprint = if (fresh) 0x4501_0014 else 0x4501_0034,
        .frame_response_fingerprint = if (fresh) 0x4501_0015 else 0x4501_0035,
        .actuator_ref_fingerprint = key.actuator_ref_fingerprint,
        .idempotency_key_fingerprint = key.key_fingerprint,
        .request_fingerprint = key.request_fingerprint,
        .target_ref_fingerprint = key.target_ref_fingerprint,
        .world_surface_fingerprint = key.world_surface_fingerprint,
        .world_port_id = key.world_port_id,
        .class = .deterministic_fixture,
        .mode = if (fresh) .fresh else .replay,
        .fresh_called = fresh,
        .replayed = !fresh,
    });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();
    var session = try world.Continuity.Session.init(allocator, &vault, world.Continuity.PersistPolicy.actuation_only());
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = 0x4501_0001,
        .world_surface_fingerprint = 0x4501_0002,
        .world_port_id = 1,
        .request_fingerprint = 0x4501_0003,
        .actuator_ref_fingerprint = 0x4501_0004,
    });

    const first_ref = try world.Actuation.commitToSession(&session, receiptFor(key, true), .{});
    const duplicate_rejected = if (world.Actuation.commitToSession(&session, receiptFor(key, true), .{})) |_| false else |err| err == error.DuplicateBinding;
    _ = try world.Actuation.commitToSession(&session, receiptFor(key, false), .{});

    try stdout.print("idempotency_key={x}\n", .{key.key_fingerprint});
    try stdout.print("first_receipt_ref={x}\n", .{first_ref.ref_fingerprint});
    try stdout.print("duplicate_fresh_rejected={}\n", .{duplicate_rejected});
    try stdout.print("replay_fresh_called=false\n", .{});
    try stdout.flush();
}
