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
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const sender_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{ .mode = .fresh, .policy = world.SupervisionPolicy.agent_fixture });
    var sender_runtime = boundary.Runtime.init(allocator);
    defer sender_runtime.deinit();
    var sender_ctx: Ctx = .{};
    var sender = try Machine.start(&sender_runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &sender_ctx, .permit = sender_permit });
    defer sender.deinit();
    var request = switch (try sender.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(allocator);
    const parked_state = world.RunState.init(.{
        .target_ref_fingerprint = sender_permit.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const sender_receipt = sender.supervisor.?.receipt(.parked, parked_state.run_state_fingerprint, null, null);
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = parked_state,
        .pending_request_frame = request,
        .prior_run_permit_fingerprint = sender_permit.permit_fingerprint,
        .prior_run_receipt_fingerprint = sender_receipt.receipt_fingerprint,
    });
    const encoded = try run_image.encode(allocator);
    defer allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(allocator, encoded);
    defer handoff.deinit();

    const receiver_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    const report = handoff.preflightWithPermit(fixtures.Ports.Target, Env, .accept_fresh, receiver_permit);
    if (!report.accepted) return error.PreflightRejected;
    var receiver_runtime = boundary.Runtime.init(allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: Ctx = .{};
    var receiver = try handoff.resumeWithPermit(fixtures.Ports.Target, Env, &receiver_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
        .permit = receiver_permit,
    }, .accept_fresh, receiver_permit);
    defer receiver.deinit();
    try receiver.dispatch();
    const final_result = switch (try receiver.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };
    const completed_state = world.RunState.init(.{ .target_ref_fingerprint = receiver_permit.target_ref_fingerprint, .status = .completed });
    const receipt = receiver.supervisor.?.receipt(.completed, completed_state.run_state_fingerprint, null, null);

    try stdout.print("received_run_image_fingerprint={x}\n", .{run_image.run_image_fingerprint});
    try stdout.print("receiver_permit_fingerprint={x}\n", .{receiver_permit.permit_fingerprint});
    try stdout.print("receiver_receipt_fingerprint={x}\n", .{receipt.receipt_fingerprint});
    try stdout.print("final_result={d}\n", .{final_result});
    try stdout.flush();
}
