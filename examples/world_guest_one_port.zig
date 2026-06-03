const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    calls: usize = 0,
};

fn approve(ctx: *Ctx, payload: []const u8) !i32 {
    _ = payload;
    ctx.calls += 1;
    return 7;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Env = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(approve))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var guest = world.Guest.NativeGuest.init(allocator, .{});
    defer guest.deinit();
    try guest.installMachineRun(fixtures.Ports.Target, Env, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });

    _ = guest.world_tick();
    const request_len = guest.world_pending_request_len(0);
    const request_bytes = try allocator.alloc(u8, request_len);
    defer allocator.free(request_bytes);
    _ = guest.world_read_pending_request(0, request_bytes);
    var request = try world.Frame.Request.decode(allocator, request_bytes);
    defer request.deinit(allocator);

    var response = try world.Frame.Response.fromPortableValue(
        allocator,
        request,
        request.expected_response_value_table_id,
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer response.deinit(allocator);
    const response_bytes = try response.encode(allocator);
    defer allocator.free(response_bytes);
    _ = guest.world_submit_response(response_bytes);
    _ = guest.world_tick();

    const result_len = guest.world_result_len();
    const result_bytes = try allocator.alloc(u8, result_len);
    defer allocator.free(result_bytes);
    _ = guest.world_read_result(result_bytes);
    var image = try world.RunImage.decode(allocator, result_bytes);
    defer image.deinit(allocator);

    try stdout.print("request_frame_fingerprint={x}\n", .{request.frame_fingerprint});
    try stdout.print("response_frame_fingerprint={x}\n", .{response.frame_fingerprint});
    try stdout.print("result_fingerprint={x}\n", .{image.run_image_fingerprint});
    try stdout.flush();
}
