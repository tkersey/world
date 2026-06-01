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
const Machine = world.Machine(fixtures.Ports.Target, .{ .environment = Env });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var sender_runtime = boundary.Runtime.init(allocator);
    defer sender_runtime.deinit();
    var sender_ctx: Ctx = .{};
    var sender = try Machine.start(&sender_runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &sender_ctx });
    defer sender.deinit();
    var request = switch (try sender.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
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
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .resume_parked,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{ .mode = .fresh, .policy = world.SupervisionPolicy.handoff_receiver });
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const admitter = world.Admission.Admitter.init(.{ .registry = world.Admission.TargetRegistry.init(&.{entry}), .policy = world.Admission.AdmissionPolicy.handoff_receiver });
    var admitted = admitter.admitForTarget(fixtures.Ports.Target, Env, package, .{ .permit = permit }).admitted_run orelse return error.AdmissionRejected;

    var runspace = world.Runspace.init(allocator, .{ .require_admission = true });
    defer runspace.deinit();
    const handle = try runspace.installAdmitted(admitted);
    var exported = try runspace.exportPending(0);
    defer exported.deinit(allocator);

    var receiver_runtime = boundary.Runtime.init(allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: Ctx = .{};
    var receiver = try admitted.@"resume"(allocator, fixtures.Ports.Target, Env, &receiver_runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &receiver_ctx, .permit = permit });
    defer receiver.deinit();
    try receiver.dispatch();
    const result = switch (try receiver.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };

    try stdout.print("admission_receipt={x}\n", .{admitted.admission_receipt_fingerprint});
    try stdout.print("run_handle={x}\n", .{handle.handle_fingerprint});
    try stdout.print("final_result={d}\n", .{result});
    try stdout.flush();
}
