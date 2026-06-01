const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct { response: i32 = 7 };

fn approve(ctx: *Ctx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    return ctx.response;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const NativeEnv = world.Environment(fixtures.Ports.Target, .{ .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(approve))}, .policy = world.EnvironmentPolicy.fresh_and_replay });
const ReplayEnv = world.Environment(fixtures.Ports.Target, .{ .bindings = .{world.bind(ApprovalPort, world.ReplayAdapter(0x5150))}, .policy = world.EnvironmentPolicy.strict_replay });
const NativeMachine = world.Machine(fixtures.Ports.Target, .{ .environment = NativeEnv });
const ReplayMachine = world.Machine(fixtures.Ports.Target, .{ .environment = ReplayEnv });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{};
    var fresh = try NativeMachine.run(&fresh_runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &fresh_ctx, .transcript = &transcript });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .replay_only,
    });
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{entry});
    const replay_admitter = world.Admission.Admitter.init(.{ .registry = registry, .policy = world.Admission.AdmissionPolicy.replay_only });
    const replay_admission = replay_admitter.admitForTarget(fixtures.Ports.Target, ReplayEnv, package, .{ .mode = .replay_only });

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var transcript_image = image;
    transcript_image.resetReplay();
    var replayed = try ReplayMachine.run(&replay_runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.replay, .transcript_image = &transcript_image });
    defer replayed.deinit(allocator);

    const verify_admitter = world.Admission.Admitter.init(.{ .registry = registry, .policy = world.Admission.AdmissionPolicy.verify_receiver });
    const verify_admission = verify_admitter.admitForTarget(fixtures.Ports.Target, NativeEnv, package, .{ .mode = .verify_only });
    image.resetReplay();
    var diverged_runtime = boundary.Runtime.init(allocator);
    defer diverged_runtime.deinit();
    var diverged_ctx: Ctx = .{ .response = 99 };
    const divergence_detected = if (NativeMachine.run(&diverged_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.verify,
        .ctx = &diverged_ctx,
        .transcript_image = &image,
    })) |bad| blk: {
        var owned_bad = bad;
        owned_bad.deinit(allocator);
        break :blk false;
    } else |err| err == error.VerifyDivergence;

    try stdout.print("replay_admission_receipt={x}\n", .{replay_admission.receipt.?.receipt_fingerprint});
    try stdout.print("verify_admission_receipt={x}\n", .{verify_admission.receipt.?.receipt_fingerprint});
    try stdout.print("divergence_detected={}\n", .{divergence_detected});
    try stdout.flush();
}
