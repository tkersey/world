const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

fn requestFor(target_ref: world.TargetRef, world_port_id: u32, seed: u64) world.Frame.Request {
    return world.Frame.Request.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .world_port_id = world_port_id,
        .residual_site_index = world_port_id,
        .residual_site_fingerprint = seed,
        .request_fingerprint = seed ^ 0x5150,
        .turn_index = 0,
        .expected_response_value_table_id = 1,
    });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const parent_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var source = world.Runspace.init(allocator, .{});
    defer source.deinit();

    const parent_handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
    });
    const provider_handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 1,
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
    });
    const parent_request = requestFor(parent_ref, 0, 0x5150_a001);
    const provider_request = requestFor(provider_ref, 0, 0x5150_a002);
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = parent_handle,
        .target_ref = parent_ref,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
            .pending_request_fingerprint = parent_request.frame_fingerprint,
            .status = .parked_on_port,
        }),
        .status = .parked_on_port,
        .pending_mailbox_id = 0,
    }));
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = provider_handle,
        .target_ref = provider_ref,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
            .pending_request_fingerprint = provider_request.frame_fingerprint,
            .status = .parked_on_port,
        }),
        .status = .parked_on_port,
        .pending_mailbox_id = 1,
        .parent_run_handle_fingerprint = parent_handle.handle_fingerprint,
    }));
    const parent_pending = try source.mailbox.push(.{
        .run_handle = parent_handle,
        .mailbox_id = 0,
        .request = parent_request,
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    const provider_pending = try source.mailbox.push(.{
        .run_handle = provider_handle,
        .mailbox_id = 1,
        .request = provider_request,
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .inserted_event_index = 1,
    });
    source.next_mailbox_id = 2;
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .parent_response_value_table_id = root_import.response_value_table_id,
        .parent_response_value_fingerprint = root_import.response_value_ref_fingerprint,
        .provider_result_value_table_id = root_import.response_value_table_id,
        .provider_result_value_fingerprint = root_import.response_value_ref_fingerprint,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0x5150_a003,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = 0,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .response_value_mapping_fingerprint = mapping.mapping_fingerprint,
        .metadata = "capsule-active-fabric",
    });
    const plan = world.Fabric.Plan.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .routes = &.{route},
        .value_mappings = &.{mapping},
    });
    try source.fabric_plan_fingerprints.append(allocator, plan.plan_fingerprint);
    try source.fabric_routes.append(allocator, route);
    try source.fabric_value_mappings.append(allocator, mapping);
    const invocation = world.Fabric.Invocation.init(.{
        .plan_fingerprint = plan.plan_fingerprint,
        .route_fingerprint = route.route_fingerprint,
        .parent_run_handle_fingerprint = parent_handle.handle_fingerprint,
        .parent_pending_port_fingerprint = parent_pending.pending_port_fingerprint,
        .parent_mailbox_id = 0,
        .request_frame_fingerprint = parent_request.frame_fingerprint,
        .provider_run_handle_fingerprint = provider_handle.handle_fingerprint,
        .depth = 1,
        .sequence = 0,
        .status = .provider_parked,
    });
    try source.fabric_invocations.append(allocator, invocation);

    var capsule = try world.Capsule.freezeRunspace(&source, .{ .allow_active_fabric_parked = true });
    defer capsule.deinit(allocator);
    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(capsule, &receiver, parent_ref.target_ref_fingerprint, 0, 0x5150_c002, .{ .mode = .restore_parked });
    defer restore.deinit(allocator);

    try stdout.print("active_fabric_invocation_fingerprint={x}\n", .{invocation.invocation_fingerprint});
    try stdout.print("pending_provider_port_fingerprint={x}\n", .{provider_pending.pending_port_fingerprint});
    try stdout.print("restore_report_fingerprint={x}\n", .{restore.restore_report_fingerprint});
    try stdout.print("final_result=active-fabric-restored\n", .{});
    try stdout.flush();
}
