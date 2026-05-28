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
    const response_fingerprint = try recordedResponseFingerprint(allocator);

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var run = try Machine.start(&runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
    });
    defer run.deinit();

    const step = try run.nextFrame();
    var request_frame = switch (step) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request_frame.deinit(allocator);
    var response_frame = try world.Frame.Response.fromValue(
        allocator,
        request_frame,
        1,
        response_fingerprint,
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer response_frame.deinit(allocator);
    try run.resumeFrame(response_frame);
    const done = try run.nextFrame();
    const final_result = switch (done) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };

    try stdout.print("request_frame_fingerprint={x}\n", .{request_frame.frame_fingerprint});
    try stdout.print("response_frame_fingerprint={x}\n", .{response_frame.frame_fingerprint});
    try stdout.print("world_port_id={d}\n", .{request_frame.world_port_id});
    try stdout.print("final_result={d}\n", .{final_result});
    try stdout.flush();
}
