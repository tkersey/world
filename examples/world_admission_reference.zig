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

fn recordedResponseFingerprint(allocator: std.mem.Allocator) !u64 {
    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var result = try Machine.run(&runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(allocator);
    for (transcript.events.items) |event| {
        if (event.kind == .port_responded) return event.response_fingerprint.?;
    }
    return error.MissingResponse;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{entry});
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const admitter = world.Admission.Admitter.init(.{ .registry = registry, .policy = world.Admission.AdmissionPolicy.test_fixture });
    const admission = admitter.admitForTarget(fixtures.Ports.Target, Env, package, .{});
    var admitted = admission.admitted_run orelse return error.AdmissionRejected;
    const target_match = admission.target_match orelse return error.AdmissionRejected;

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var run = try admitted.start(fixtures.Ports.Target, Env, &runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh, .ctx = &ctx });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(allocator);
    var response = try world.Frame.Response.fromValue(
        allocator,
        request,
        1,
        try recordedResponseFingerprint(allocator),
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer response.deinit(allocator);
    try run.resumeFrame(response);
    const result = switch (try run.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };

    try stdout.print("package_fingerprint={x}\n", .{package.package_fingerprint});
    try stdout.print("target_match_fingerprint={x}\n", .{target_match.match_fingerprint});
    try stdout.print("admission_receipt_fingerprint={x}\n", .{admitted.admission_receipt_fingerprint});
    try stdout.print("final_result={d}\n", .{result});
    try stdout.flush();
}
