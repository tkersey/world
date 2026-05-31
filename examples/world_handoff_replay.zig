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
const NativeEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(approve))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const ReplayEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.ReplayAdapter(0x5150))},
    .policy = world.EnvironmentPolicy.strict_replay,
});
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
    var ctx: Ctx = .{};
    var fresh = try NativeMachine.run(&fresh_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const encoded = try run_image.encode(allocator);
    defer allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(allocator, encoded);
    defer handoff.deinit();

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try ReplayMachine.run(&replay_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replayed.deinit(allocator);

    try stdout.print("run_image_fingerprint={x}\n", .{run_image.run_image_fingerprint});
    try stdout.print("replayed_response_count={d}\n", .{replayed.audit.replayed_response_count});
    try stdout.print("final_result={d}\n", .{replayed.value});
    try stdout.flush();
}
