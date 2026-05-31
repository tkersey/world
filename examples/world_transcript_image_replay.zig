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
const Machine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{ApprovalPort},
    .strict_handler_coverage = true,
});

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
    const encoded = try image.encode(allocator);
    defer allocator.free(encoded);
    var decoded = try world.TranscriptImage.decode(allocator, encoded);
    defer decoded.deinit(allocator);

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try Machine.run(&replay_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    });
    defer replayed.deinit(allocator);

    try stdout.print("transcript_image_fingerprint={x}\n", .{decoded.transcript_image_fingerprint});
    try stdout.print("replayed_response_count={d}\n", .{replayed.audit.replayed_response_count});
    try stdout.print("final_result={d}\n", .{replayed.value});
    try stdout.flush();
}
