const std = @import("std");
const world = @import("world");

fn receiptFor() world.Actuation.Receipt {
    return world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0x4502_0010,
        .envelope_fingerprint = 0x4502_0011,
        .decision_fingerprint = 0x4502_0012,
        .commit_fingerprint = 0x4502_0013,
        .response_fingerprint = 0x4502_0014,
        .frame_response_fingerprint = 0x4502_0015,
        .actuator_ref_fingerprint = 0x4502_0004,
        .idempotency_key_fingerprint = 0x4502_0020,
        .request_fingerprint = 0x4502_0003,
        .target_ref_fingerprint = 0x4502_0001,
        .world_surface_fingerprint = 0x4502_0002,
        .world_port_id = 1,
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
    var session = try world.Continuity.Session.init(allocator, &vault, world.Continuity.PersistPolicy.capsule_and_actuation());
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    _ = try world.Capsule.freezeToSession(&session, &runspace, .{});
    _ = try world.Actuation.commitToSession(&session, receiptFor(), .{});

    const replay = try world.Continuity.Chronicle.replay(&vault, .{});
    try replay.validate();
    const match = replay.mismatch_count == 0;

    try stdout.print("event_count={d}\n", .{vault.eventCount()});
    try stdout.print("replay_report_fingerprint={x}\n", .{replay.report_fingerprint});
    try stdout.print("projection_match={}\n", .{match});
    try stdout.flush();
}
