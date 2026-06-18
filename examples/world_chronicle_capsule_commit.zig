const std = @import("std");
const world = @import("world");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();
    var session = try world.Continuity.Session.init(allocator, &vault, world.Continuity.PersistPolicy.capsule_only());
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();

    const capsule_ref = try world.Capsule.freezeToSession(&session, &runspace, .{});
    var projection = try world.Continuity.Chronicle.Projection.rebuild(&vault, .capsule_index);
    defer projection.deinit();
    try projection.assertFresh(session.cursor());

    const commit = vault.chronicle_commits.items[vault.chronicle_commits.items.len - 1];
    try stdout.print("capsule_ref={x}\n", .{capsule_ref.ref_fingerprint});
    try stdout.print("commit_fingerprint={x}\n", .{commit.commit_fingerprint});
    try stdout.print("cursor_fingerprint={x}\n", .{session.cursor().cursor_fingerprint});
    try stdout.print("final_result=chronicle-capsule-commit-ok\n", .{});
    try stdout.flush();
}
