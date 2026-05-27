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

    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.heap.page_allocator);
    defer transcript.deinit();
    var ctx: Ctx = .{};

    var result = try Machine.run(&runtime, .{}, .{
        .allocator = std.heap.page_allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.heap.page_allocator);

    try stdout.print("world_surface_fingerprint={x}\n", .{fixtures.Ports.Target.WorldSurface.surface_fingerprint});
    try stdout.print("world_port_id={d}\n", .{ApprovalPort.world_port_id});
    const request_fingerprint = for (transcript.events.items) |event| {
        if (event.kind == .port_requested) break event.request_fingerprint.?;
    } else 0;
    try stdout.print("request_fingerprint={x}\n", .{request_fingerprint});
    try stdout.print("final_result={d}\n", .{result.value});
    try stdout.flush();
}
