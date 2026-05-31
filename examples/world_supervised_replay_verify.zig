const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    calls: usize = 0,
    response: i32 = 7,
};

fn approve(ctx: *Ctx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    ctx.calls += 1;
    return ctx.response;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const NativeBinding = world.bind(ApprovalPort, world.NativeAdapter(approve));
const ReplayBinding = world.bind(ApprovalPort, world.ReplayAdapter(0x7777));
const NativeEnv = world.Environment(fixtures.Ports.Target, .{ .bindings = .{NativeBinding}, .policy = world.EnvironmentPolicy.fresh_and_replay });
const ReplayEnv = world.Environment(fixtures.Ports.Target, .{ .bindings = .{ReplayBinding}, .policy = world.EnvironmentPolicy.strict_replay });
const NativeMachine = world.Machine(fixtures.Ports.Target, .{ .environment = NativeEnv });
const ReplayMachine = world.Machine(fixtures.Ports.Target, .{ .environment = ReplayEnv });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    const fresh_permit = world.Supervision.issue(fixtures.Ports.Target, NativeEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{};
    var fresh = try NativeMachine.run(&fresh_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
        .permit = fresh_permit,
    });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);

    const replay_permit = world.Supervision.issue(fixtures.Ports.Target, ReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .budget = world.Budget.init(.{ .max_replay_calls = 1 }),
        .transcript_image_available = true,
    });
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replay = try ReplayMachine.run(&replay_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
        .permit = replay_permit,
    });
    defer replay.deinit(allocator);

    image.resetReplay();
    const verify_permit = world.Supervision.issue(fixtures.Ports.Target, NativeEnv, .{
        .mode = .verify,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_verify_calls = true,
            .allow_native_adapters = true,
            .require_environment_certificate = true,
            .require_transcript_image_for_replay = true,
        }),
        .budget = world.Budget.init(.{ .max_verify_calls = 1 }),
        .transcript_image_available = true,
    });
    var verify_runtime = boundary.Runtime.init(allocator);
    defer verify_runtime.deinit();
    var changed_ctx: Ctx = .{ .response = 8 };
    const divergence = NativeMachine.run(&verify_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.verify,
        .ctx = &changed_ctx,
        .transcript_image = &image,
        .permit = verify_permit,
    }) == error.VerifyDivergence;

    try stdout.print("fresh_receipt={x}\n", .{fresh.receipt.?.receipt_fingerprint});
    try stdout.print("replay_receipt={x}\n", .{replay.receipt.?.receipt_fingerprint});
    try stdout.print("verify_divergence_detected={}\n", .{divergence});
    try stdout.flush();
}
