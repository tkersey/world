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

fn fakeHost(allocator: std.mem.Allocator, request_bytes: []const u8) ![]const u8 {
    var request = try world.Frame.Request.decode(allocator, request_bytes);
    defer request.deinit(allocator);
    if (request.world_port_id != 0) return error.UnexpectedPort;
    var response = try world.Frame.Response.fromPortableValue(allocator, request, 1, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(allocator);
    return response.encode(allocator);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var run = try Machine.start(&runtime, .{}, .{ .allocator = allocator, .mode = world.Mode.fresh });
    defer run.deinit();
    var request_frame = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request_frame.deinit(allocator);
    const request_bytes = try request_frame.encode(allocator);
    defer allocator.free(request_bytes);
    const response_bytes = try fakeHost(allocator, request_bytes);
    defer allocator.free(response_bytes);
    var response_frame = try world.Frame.Response.decode(allocator, response_bytes);
    defer response_frame.deinit(allocator);
    try run.resumeFrame(response_frame);
    const final_result = switch (try run.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };

    try stdout.print("request_frame_bytes={d}\n", .{request_bytes.len});
    try stdout.print("response_frame_bytes={d}\n", .{response_bytes.len});
    try stdout.print("final_result={d}\n", .{final_result});
    try stdout.flush();
}
