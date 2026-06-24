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
    var source_destroyed = false;
    defer if (!source_destroyed) source.deinit();

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
    const parent_state = world.RunState.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .pending_request_fingerprint = parent_request.frame_fingerprint,
        .turn_index = parent_request.turn_index,
        .status = .parked_on_port,
    });
    const provider_state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .pending_request_fingerprint = provider_request.frame_fingerprint,
        .turn_index = provider_request.turn_index,
        .status = .parked_on_port,
    });
    const parent_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = parent_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = parent_state,
        .pending_request_frame = parent_request,
    });
    const provider_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = provider_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = provider_state,
        .pending_request_frame = provider_request,
    });
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = parent_handle,
        .target_ref = parent_ref,
        .current_state = parent_state,
        .status = .parked_on_port,
        .pending_mailbox_id = 0,
        .installed_run_image = parent_run_image,
        .owns_installed_run_image = true,
    }));
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = provider_handle,
        .target_ref = provider_ref,
        .current_state = provider_state,
        .status = .parked_on_port,
        .pending_mailbox_id = 1,
        .parent_run_handle_fingerprint = parent_handle.handle_fingerprint,
        .installed_run_image = provider_run_image,
        .owns_installed_run_image = true,
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
        .provider_result_value_table_id = root_import.response_value_table_id,
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
    try source.fabric_route_plan_fingerprints.append(allocator, plan.plan_fingerprint);
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
    source.deinit();
    source_destroyed = true;

    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(capsule, &receiver, parent_ref.target_ref_fingerprint, 0, 0x5150_c002, .{
        .mode = .restore_parked,
        .require_local_permit = false,
        .require_link_match = false,
    });
    defer restore.deinit(allocator);
    if (!restore.accepted) return error.ExpectedRestoreAccepted;
    if (receiver.fabric_routes.items.len != 1) return error.ExpectedRestoredFabricRoute;
    const source_route_metadata = capsule.fabric_image.?.route_witnesses[0].metadata;
    if (receiver.fabric_routes.items[0].metadata.ptr == source_route_metadata.ptr) return error.BorrowedRestoredFabricRouteMetadata;
    @constCast(source_route_metadata)[0] = 'X';
    if (!std.mem.eql(u8, receiver.fabric_routes.items[0].metadata, "capsule-active-fabric")) return error.RestoredFabricRouteMetadataMutated;

    var restored_provider_mailbox_id: ?u64 = null;
    for (receiver.slots.items) |slot| {
        if (slot.parent_run_handle_fingerprint != null) {
            restored_provider_mailbox_id = slot.pending_mailbox_id;
            break;
        }
    }
    const provider_event = try receiver.respondActiveFabricProviderValue(restored_provider_mailbox_id orelse return error.ExpectedPendingRequestFrame, @as(i32, 1));
    const restored_invocation = receiver.fabric_invocations.items[0];
    const root_event = try receiver.respondFromFabric(restored_invocation);

    try stdout.print("provider_parked={}\n", .{provider_pending.pending_port_fingerprint != 0});
    try stdout.print("source_destroyed={}\n", .{source_destroyed});
    try stdout.print("restore_accepted={}\n", .{restore.accepted});
    try stdout.print("active_fabric_restore_accepted={}\n", .{restore.accepted});
    try stdout.print("provider_completed={}\n", .{provider_event.kind == .run_completed});
    try stdout.print("root_completed={}\n", .{root_event.kind == .run_completed});
    try stdout.flush();
}
