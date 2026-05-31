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
const Binding = world.bind(ApprovalPort, world.NativeAdapter(approve));
const Env = world.Environment(fixtures.Ports.Target, .{ .bindings = .{Binding}, .policy = world.EnvironmentPolicy.fresh_and_replay });
const Machine = world.Machine(fixtures.Ports.Target, .{ .environment = Env });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const ok_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    var ok_runtime = boundary.Runtime.init(allocator);
    defer ok_runtime.deinit();
    var ok_ctx: Ctx = .{};
    var ok = try Machine.run(&ok_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ok_ctx,
        .permit = ok_permit,
    });
    defer ok.deinit(allocator);

    const denied_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    var denied_runtime = boundary.Runtime.init(allocator);
    defer denied_runtime.deinit();
    var denied_ctx: Ctx = .{};
    const denied = Machine.run(&denied_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &denied_ctx,
        .permit = denied_permit,
    }) == error.BudgetExceeded;

    try stdout.print("permit_fingerprint={x}\n", .{ok_permit.permit_fingerprint});
    try stdout.print("receipt_fingerprint={x}\n", .{ok.receipt.?.receipt_fingerprint});
    try stdout.print("budget_exceeded=false\n", .{});
    try stdout.print("denied_budget_exceeded={}\n", .{denied});
    try stdout.flush();
}
