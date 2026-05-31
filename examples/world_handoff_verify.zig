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

    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{};
    var fresh = try Machine.run(&fresh_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
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

    var verify_runtime = boundary.Runtime.init(allocator);
    defer verify_runtime.deinit();
    var verify_ctx: Ctx = .{};
    var verified = try Machine.run(&verify_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer verified.deinit(allocator);

    handoff.run_image.transcript_image.?.resetReplay();
    var diverged_runtime = boundary.Runtime.init(allocator);
    defer diverged_runtime.deinit();
    var diverged_ctx: Ctx = .{ .response = 99 };
    const divergence_detected = if (Machine.run(&diverged_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.verify,
        .ctx = &diverged_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    })) |bad| blk: {
        var owned_bad = bad;
        owned_bad.deinit(allocator);
        break :blk false;
    } else |err| err == error.VerifyDivergence;

    try stdout.print("verification_accepted={}\n", .{verified.value == fresh.value});
    try stdout.print("divergence_detected={}\n", .{divergence_detected});
    try stdout.flush();
}
