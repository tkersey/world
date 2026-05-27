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
const Machine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{ApprovalPort},
    .strict_handler_coverage = true,
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var transcript = world.Transcript.init(std.heap.page_allocator);
    defer transcript.deinit();

    var fresh_runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: Ctx = .{};
    var fresh = try Machine.run(&fresh_runtime, .{}, .{
        .allocator = std.heap.page_allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(std.heap.page_allocator);

    var replay_runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer replay_runtime.deinit();
    var replay_ctx: Ctx = .{};
    var replayed = try Machine.run(&replay_runtime, .{}, .{
        .allocator = std.heap.page_allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(std.heap.page_allocator);

    const summary = transcript.summary();
    try stdout.print("recorded_interaction_count={d}\n", .{summary.port_responded});
    try stdout.print("replayed_interaction_count={d}\n", .{replayed.audit.replayed_response_count});
    try stdout.print("replay_verified={}\n", .{fresh.value == replayed.value and replay_ctx.calls == 0});
    try stdout.print("final_result={d}\n", .{replayed.value});
    try stdout.flush();
}
