const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var outbound_vault = world.Continuity.MemoryVault.init(allocator);
    defer outbound_vault.deinit();
    var outbound_session = try world.Continuity.Session.init(allocator, &outbound_vault, world.Continuity.PersistPolicy.full_local_evidence());
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    const capsule_ref = try world.Capsule.freezeToSession(&outbound_session, &runspace, .{});
    var outbox = world.Continuity.Chronicle.Outbox.init(&outbound_session);
    const outbound_ref = try outbox.stageCapsule(capsule_ref);
    var bundle = try outbox.exportBundle(outbound_ref);
    defer bundle.deinit();
    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);
    try outbox.markExported(outbound_ref);

    var inbound_vault = world.Continuity.MemoryVault.init(allocator);
    defer inbound_vault.deinit();
    var inbound_session = try world.Continuity.Session.init(allocator, &inbound_vault, world.Continuity.PersistPolicy.full_local_evidence());
    var inbox = world.Continuity.Chronicle.Inbox.init(&inbound_session);
    const inbound_ref = try inbox.importBundle(bytes);
    try inbox.validate(inbound_ref);
    try inbox.planRecovery(inbound_ref);
    try inbox.accept(inbound_ref);

    try stdout.print("outbound_envelope_ref={x}\n", .{outbound_ref.ref_fingerprint});
    try stdout.print("inbound_envelope_ref={x}\n", .{inbound_ref.ref_fingerprint});
    try stdout.print("accepted=true\n", .{});
    try stdout.flush();
}
