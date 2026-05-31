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
const NativeBinding = world.bind(ApprovalPort, world.NativeAdapter(approve));
const NativeEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{NativeBinding},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const MissingEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{},
    .policy = world.EnvironmentPolicy.strict_fresh,
});
const ReplayOnlyEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{},
    .policy = world.EnvironmentPolicy.strict_replay,
});
const Machine = world.Machine(fixtures.Ports.Target, .{ .environment = NativeEnv });

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

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
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);

    const fresh = MissingEnv.acceptanceReport(.fresh, false);
    const replay = ReplayOnlyEnv.acceptanceReport(.replay, true);
    try stdout.print("fresh_missing_accepted={}\n", .{fresh.accepted});
    try stdout.print("fresh_blocker={s}\n", .{@tagName(fresh.blockers[0])});
    try stdout.print("replay_without_handlers_accepted={}\n", .{replay.accepted});
    try stdout.print("transcript_image_fingerprint={x}\n", .{image.transcript_image_fingerprint});
    try stdout.flush();
}
