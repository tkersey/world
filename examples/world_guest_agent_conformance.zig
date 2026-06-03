const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    allocator: std.mem.Allocator,
    model_calls: usize = 0,
    tool_calls: usize = 0,
};

fn decide(ctx: *Ctx, observation: []const u8) !fixtures.Agent.Action {
    _ = observation;
    ctx.model_calls += 1;
    return .{ .final = "unused" };
}

fn callTool(ctx: *Ctx, command: []const u8) ![]const u8 {
    _ = command;
    ctx.tool_calls += 1;
    return "unused";
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, callTool);
const Env = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(DecidePort, world.NativeAdapter(decide)),
        world.bind(ToolPort, world.NativeAdapter(callTool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Args = struct { usize, []const u8 };

const Summary = struct {
    model_pending: usize = 0,
    tool_pending: usize = 0,
    result_fingerprint: u64 = 0,
};

fn responseFor(request: world.Frame.Request, model_pending: *usize, tool_pending: *usize, allocator: std.mem.Allocator) !world.Frame.Response {
    if (request.world_port_id == DecidePort.world_port_id) {
        model_pending.* += 1;
        const action: fixtures.Agent.Action = if (model_pending.* == 1)
            .{ .tool = "actuate" }
        else
            .{ .final = "final=actuate skeleton complete" };
        return world.Frame.Response.fromPortableValue(allocator, request, request.expected_response_value_table_id, .@"resume", action, .portable);
    }
    if (request.world_port_id == ToolPort.world_port_id) {
        tool_pending.* += 1;
        return world.Frame.Response.fromPortableValue(allocator, request, request.expected_response_value_table_id, .@"resume", @as([]const u8, "actuate"), .portable);
    }
    return error.FramePortMismatch;
}

fn driveGuest(allocator: std.mem.Allocator) !Summary {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{ .allocator = allocator };
    var guest = world.Guest.NativeGuest.init(allocator, .{});
    defer guest.deinit();
    try guest.installMachineRun(fixtures.Agent.Target, Env, &runtime, Args{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var summary: Summary = .{};
    while (guest.world_status() != world.Guest.Status.done.code()) {
        const status = guest.world_tick();
        if (status == world.Guest.Status.done.code()) break;
        if (status != world.Guest.Status.parked.code()) return error.UnexpectedGuestStatus;
        const request_len = guest.world_pending_request_len(0);
        const request_bytes = try allocator.alloc(u8, request_len);
        defer allocator.free(request_bytes);
        _ = guest.world_read_pending_request(0, request_bytes);
        var request = try world.Frame.Request.decode(allocator, request_bytes);
        defer request.deinit(allocator);
        var response = try responseFor(request, &summary.model_pending, &summary.tool_pending, allocator);
        defer response.deinit(allocator);
        const response_bytes = try response.encode(allocator);
        defer allocator.free(response_bytes);
        _ = guest.world_submit_response(response_bytes);
    }
    if (ctx.model_calls != 0 or ctx.tool_calls != 0) return error.NativeHandlerCalled;
    const result_len = guest.world_result_len();
    const result_bytes = try allocator.alloc(u8, result_len);
    defer allocator.free(result_bytes);
    _ = guest.world_read_result(result_bytes);
    var image = try world.RunImage.decode(allocator, result_bytes);
    defer image.deinit(allocator);
    summary.result_fingerprint = image.run_image_fingerprint;
    return summary;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;
    const summary = try driveGuest(allocator);
    try stdout.print("model_pending_count={d}\n", .{summary.model_pending});
    try stdout.print("tool_pending_count={d}\n", .{summary.tool_pending});
    try stdout.print("result_fingerprint={x}\n", .{summary.result_fingerprint});
    try stdout.print("conformance=true\n", .{});
    try stdout.flush();
}
