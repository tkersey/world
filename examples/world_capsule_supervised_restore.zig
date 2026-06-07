const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {};

fn approve(_: *Ctx, _: []const u8) !i32 {
    return error.ManualOnly;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Env = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(approve))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});

fn parkedSource(allocator: std.mem.Allocator, runspace: *world.Runspace, target_ref: world.TargetRef, permit_fingerprint: u64) !void {
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit_fingerprint,
    });
    const request = world.Frame.Request.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = 0,
        .residual_site_fingerprint = 0x5150_f001,
        .request_fingerprint = 0x5150_f002,
        .turn_index = 0,
        .expected_response_value_table_id = 1,
    });
    const parked_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = parked_state,
        .pending_request_frame = request,
        .prior_run_permit_fingerprint = permit_fingerprint,
    });
    try runspace.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = parked_state,
        .status = .parked_on_port,
        .run_permit_fingerprint = permit_fingerprint,
        .pending_mailbox_id = 0,
        .installed_run_image = parked_image,
        .owns_installed_run_image = true,
    }));
    _ = try runspace.mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 0,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .run_permit_fingerprint = permit_fingerprint,
        .inserted_event_index = 0,
    });
    runspace.next_mailbox_id = 1;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const sender_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
    });
    var source = world.Runspace.init(allocator, .{});
    defer source.deinit();
    try parkedSource(allocator, &source, target_ref, sender_permit.permit_fingerprint);
    var capsule = try world.Capsule.freezeRunspace(&source, .{});
    defer capsule.deinit(allocator);

    const receiver_permit = world.Supervision.issue(fixtures.Ports.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(capsule, &receiver, target_ref.target_ref_fingerprint, 0, receiver_permit.permit_fingerprint, .{ .mode = .restore_parked });
    defer restore.deinit(allocator);

    try stdout.print("sender_permit_fingerprint={x}\n", .{sender_permit.permit_fingerprint});
    try stdout.print("receiver_permit_fingerprint={x}\n", .{receiver_permit.permit_fingerprint});
    try stdout.print("restore_allowed={}\n", .{restore.accepted});
    try stdout.flush();
}
