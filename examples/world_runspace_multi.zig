const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct { calls: usize = 0 };

fn approve(ctx: *Ctx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    ctx.calls += 1;
    return 7;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Env = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(approve))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var runtime_a = boundary.Runtime.init(allocator);
    defer runtime_a.deinit();
    var runtime_b = boundary.Runtime.init(allocator);
    defer runtime_b.deinit();
    var ctx_a: Ctx = .{};
    var ctx_b: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();

    const first = try runspace.installMachineRun(fixtures.Ports.Target, Env, &runtime_a, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &ctx_a });
    const second = try runspace.installMachineRun(fixtures.Ports.Target, Env, &runtime_b, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &ctx_b });
    _ = try runspace.tick();
    _ = try runspace.respondValue(0, @as(i32, 7));
    _ = try runspace.tick();
    _ = try runspace.respondValue(1, @as(i32, 7));
    _ = try runspace.tick();

    const report = runspace.report();
    try stdout.print("first_run={x}\n", .{first.handle_fingerprint});
    try stdout.print("second_run={x}\n", .{second.handle_fingerprint});
    try stdout.print("pending_count={d}\n", .{report.pending_port_count});
    try stdout.print("completed_count={d}\n", .{report.completed_count});
    try stdout.flush();
}
