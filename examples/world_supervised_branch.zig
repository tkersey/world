const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

fn approve(_: *u8, _: []const u8) !i32 {
    return 7;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Binding = world.bind(ApprovalPort, world.NativeAdapter(approve));
const Env = world.Environment(fixtures.Ports.Target, .{ .bindings = .{Binding}, .policy = world.EnvironmentPolicy.fresh_and_replay });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.branch_limited,
        .budget = world.Budget.init(.{ .max_checkpoints = 1, .max_branches = 1 }),
    });
    var supervisor = try world.Supervisor.init(allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .event_index = 1,
        .turn_index = 1,
        .transcript_prefix_fingerprint = 0xabc,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    try supervisor.beforeCheckpoint(0);
    try supervisor.beforeBranch(1);
    const second_denied = supervisor.beforeBranch(1) == error.BudgetExceeded;

    try stdout.print("checkpoint_fingerprint={x}\n", .{checkpoint.checkpoint_fingerprint});
    try stdout.print("first_branch_result=allowed\n", .{});
    try stdout.print("second_branch_denied={}\n", .{second_denied});
    try stdout.flush();
}
