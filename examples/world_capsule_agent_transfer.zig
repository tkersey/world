const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct {};

fn decide(_: *Ctx, _: []const u8) !fixtures.Agent.Action {
    return error.ManualOnly;
}

fn tool(_: *Ctx, _: []const u8) ![]const u8 {
    return error.ManualOnly;
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, tool);
const Env = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(DecidePort, world.NativeAdapter(decide)),
        world.bind(ToolPort, world.NativeAdapter(tool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const root_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const decide_import = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 0);
    const tool_import = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 1);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const provider_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = tool_import.response_value_table_id, .value_ref_fingerprint = tool_import.response_value_ref_fingerprint },
        .label = "tool-provider",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = provider_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "tool-provider",
        }),
    };
    var linked = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Agent.Target),
        .root_imports = &.{ decide_import, tool_import },
        .catalog = world.Linker.Catalog.init(&entries),
        .policy = .allow_external_ports,
    });
    defer linked.deinit();

    var source = world.Runspace.init(allocator, .{});
    defer source.deinit();
    try linked.assembly.installIntoRunspace(&source);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = source.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = root_ref.target_ref_fingerprint,
    });
    const request = world.Frame.Request.init(.{
        .world_surface_fingerprint = root_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = root_ref.target_certificate_fingerprint,
        .world_port_id = decide_import.world_port_id,
        .residual_site_index = 0,
        .residual_site_fingerprint = decide_import.requirement_fingerprint,
        .request_fingerprint = 0x5150_a901,
        .turn_index = 0,
        .expected_response_value_table_id = decide_import.response_value_table_id,
    });
    const parked_state = world.RunState.init(.{
        .target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = root_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .current_state = parked_state,
        .pending_request_frame = request,
    });
    try source.slots.append(allocator, world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = root_ref,
        .current_state = parked_state,
        .status = .parked_on_port,
        .pending_mailbox_id = 0,
        .installed_run_image = parked_image,
        .owns_installed_run_image = true,
    }));
    _ = try source.mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 0,
        .request = request,
        .target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    source.next_mailbox_id = 1;
    var capsule = try world.Capsule.freezeAssembly(&source, linked.assembly, .{});
    defer capsule.deinit(allocator);
    const receiver_permit = world.Supervision.issue(fixtures.Agent.Target, Env, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
    });
    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(capsule, &receiver, root_ref.target_ref_fingerprint, 0, receiver_permit.permit_fingerprint, .{ .mode = .restore_parked });
    defer restore.deinit(allocator);

    try stdout.print("capsule_fingerprint={x}\n", .{capsule.image_fingerprint});
    try stdout.print("residual_external_import_count={d}\n", .{linked.assembly.residualImportSet().required_count});
    try stdout.print("receiver_permit_fingerprint={x}\n", .{receiver_permit.permit_fingerprint});
    try stdout.print("restore_accepted={}\n", .{restore.accepted});
    if (restore.accepted) {
        try stdout.print("final_result=final=actuate skeleton complete\n", .{});
    } else {
        try stdout.print("final_result=parked-restore-denied\n", .{});
    }
    try stdout.flush();
}
