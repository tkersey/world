const std = @import("std");
const world = @import("world");

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
    var loaded = try world.Capsule.load(&vault, capsule_ref);
    defer loaded.deinit(allocator);

    var graph = try world.Continuity.CapsuleGraph.fromCapsule(&vault, capsule_ref);
    defer graph.deinit();

    try stdout.print("stored_object_count={d}\n", .{vault.objectCount()});
    try stdout.print("capsule_ref={x}\n", .{capsule_ref.ref_fingerprint});
    try stdout.print("capsule_certificate_ref={x}\n", .{if (graph.capsule_certificate_ref) |ref| ref.ref_fingerprint else 0});
    try stdout.print("graph_restorable={}\n", .{graph.restorable});
    try stdout.print("graph_replayable={}\n", .{graph.replayable});
    try stdout.flush();
}
