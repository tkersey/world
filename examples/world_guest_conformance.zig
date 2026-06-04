const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {
    calls: usize = 0,
};

const Summary = struct {
    status: world.Guest.Status,
    request_fingerprint: u64,
    result_fingerprint: u64,
    status_sequence: [4]world.Guest.Status = [_]world.Guest.Status{.initialized} ** 4,
    status_sequence_len: usize = 0,

    fn observedStatusSequence(self: *const @This()) []const world.Guest.Status {
        return self.status_sequence[0..self.status_sequence_len];
    }
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

fn guestStatusFromCode(code: u32) !world.Guest.Status {
    inline for (std.meta.fields(world.Guest.Status)) |field| {
        if (field.value == code) return @as(world.Guest.Status, @enumFromInt(code));
    }
    return error.InvalidGuestStatus;
}

fn nativeSummary(allocator: std.mem.Allocator) !Summary {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, Env, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame orelse return error.ExpectedFrameRequest;
    _ = try runspace.respondValue(0, @as(i32, 7));
    _ = try runspace.tick();
    var image = try runspace.exportRun(handle);
    defer image.deinit(allocator);
    return .{
        .status = .done,
        .request_fingerprint = request.frame_fingerprint,
        .result_fingerprint = image.run_image_fingerprint,
    };
}

fn guestSummary(allocator: std.mem.Allocator) !Summary {
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
    const init_status = try guestStatusFromCode(guest.world_init());
    const first_tick_status = try guestStatusFromCode(guest.world_tick());
    const request_len = guest.world_pending_request_len(0);
    const request_bytes = try allocator.alloc(u8, request_len);
    defer allocator.free(request_bytes);
    _ = guest.world_read_pending_request(0, request_bytes);
    var request = try world.Frame.Request.decode(allocator, request_bytes);
    defer request.deinit(allocator);
    var response = try world.Frame.Response.fromPortableValue(allocator, request, request.expected_response_value_table_id, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(allocator);
    const response_bytes = try response.encode(allocator);
    defer allocator.free(response_bytes);
    const submit_status = try guestStatusFromCode(guest.world_submit_response(response_bytes));
    const final_tick_status = try guestStatusFromCode(guest.world_tick());
    const result_len = guest.world_result_len();
    const result_bytes = try allocator.alloc(u8, result_len);
    defer allocator.free(result_bytes);
    _ = guest.world_read_result(result_bytes);
    var image = try world.RunImage.decode(allocator, result_bytes);
    defer image.deinit(allocator);
    return .{
        .status = .done,
        .request_fingerprint = request.frame_fingerprint,
        .result_fingerprint = image.run_image_fingerprint,
        .status_sequence = .{ init_status, first_tick_status, submit_status, final_tick_status },
        .status_sequence_len = 4,
    };
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;
    const native = try nativeSummary(allocator);
    const guest = try guestSummary(allocator);
    const pending_match = native.request_fingerprint == guest.request_fingerprint;
    const result_match = native.result_fingerprint == guest.result_fingerprint;
    const vector = world.Guest.ConformanceVector.init(.{
        .name = "one-port",
        .kind = .one_port,
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .expected_pending_frame_fingerprints = &.{native.request_fingerprint},
        .expected_final_result_fingerprint = native.result_fingerprint,
        .expected_status_sequence = &.{ .initialized, .parked, .running, .done },
    });
    const status_sequence_match = std.mem.eql(world.Guest.Status, guest.observedStatusSequence(), vector.expected_status_sequence);
    const report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .native_run_result = .{ .status = native.status, .result_fingerprint = native.result_fingerprint, .pending_frame_fingerprints = &.{native.request_fingerprint} },
        .native_abi_result = .{ .status = guest.status, .result_fingerprint = guest.result_fingerprint, .pending_frame_fingerprints = &.{guest.request_fingerprint} },
        .status_sequence_match = status_sequence_match,
        .pending_frame_match = pending_match,
        .final_result_match = result_match,
    });
    try stdout.print("vector_fingerprint={x}\n", .{vector.vector_fingerprint});
    try stdout.print("report_fingerprint={x}\n", .{report.report_fingerprint});
    try stdout.print("conformance={}\n", .{status_sequence_match and pending_match and result_match});
    try stdout.flush();
}
