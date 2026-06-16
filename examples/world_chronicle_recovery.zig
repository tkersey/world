const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var vault = world.Continuity.MemoryVault.init(allocator);
    defer vault.deinit();
    var session = try world.Continuity.Session.init(allocator, &vault, world.Continuity.PersistPolicy.full_local_evidence());
    var source = world.Runspace.init(allocator, .{});
    defer source.deinit();
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .completed,
        }),
        .status = .completed,
    }));
    const capsule_ref = try world.Capsule.freezeToSession(&session, &source, .{});
    var target = world.Runspace.init(allocator, .{});
    defer target.deinit();
    const permit = .{ .permit_fingerprint = @as(u64, 0x4505_0004) };

    const plan = try world.Continuity.Recovery.planThawFromVault(&session, capsule_ref, target_ref, {}, permit, .{});
    var report = try world.Continuity.Recovery.thawFromVault(&session, &target, capsule_ref, target_ref, {}, permit, .{});
    defer report.deinit(allocator);

    try stdout.print("recovery_plan_fingerprint={x}\n", .{plan.plan_fingerprint});
    try stdout.print("recovery_report_fingerprint={x}\n", .{report.report_fingerprint});
    try stdout.print("restored={}\n", .{report.accepted});
    try stdout.print("final_result=chronicle-recovery-ok\n", .{});
    try stdout.flush();
}
