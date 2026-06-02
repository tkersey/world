const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    calls: usize = 0,
};

fn approve(ctx: *Ctx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    ctx.calls += 1;
    return 7;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Binding = world.bind(ApprovalPort, world.NativeAdapter(approve));
const Env = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{Binding},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Machine = world.Machine(fixtures.Ports.Target, .{ .environment = Env });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var run = try Machine.start(&runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
        .environment_certificate_fingerprint = Env.certificate(.fresh, false).certificate_fingerprint,
    });
    const encoded = try run_image.encode(allocator);
    defer allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(allocator, encoded);
    defer handoff.deinit();
    const report = handoff.preflight(fixtures.Ports.Target, Env, .accept_fresh);
    if (!report.accepted) return error.PreflightRejected;

    var receiver_runtime = boundary.Runtime.init(allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: Ctx = .{};
    var receiver_run = try handoff.@"resume"(fixtures.Ports.Target, Env, &receiver_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
    }, .accept_fresh);
    defer receiver_run.deinit();
    try receiver_run.dispatch();
    const done = switch (try receiver_run.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };

    try stdout.print("run_image_fingerprint={x}\n", .{run_image.run_image_fingerprint});
    try stdout.print("pending_request_fingerprint={x}\n", .{request.frame_fingerprint});
    try stdout.print("environment_certificate_fingerprint={x}\n", .{Env.certificate(.fresh, false).certificate_fingerprint});
    try stdout.print("final_result={d}\n", .{done});
    try stdout.flush();
}
