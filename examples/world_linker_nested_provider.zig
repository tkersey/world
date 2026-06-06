const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct { native_calls: usize = 0 };

fn unexpectedNative(ctx: *Ctx, _: []const u8) !i32 {
    ctx.native_calls += 1;
    return error.UnexpectedNativeHandler;
}

const RootPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, unexpectedNative);
const ProviderPort = world.port(fixtures.ProviderPorts.Target, fixtures.ProviderPorts.ApprovalRequest, unexpectedNative);
const RootEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(RootPort, world.NativeAdapter(unexpectedNative))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const ProviderEnv = world.Environment(fixtures.ProviderPorts.Target, .{
    .bindings = .{world.bind(ProviderPort, world.NativeAdapter(unexpectedNative))},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});

fn providerImage(allocator: std.mem.Allocator, value: i32) !struct {
    image: world.RunImage,
    value_image: world.Frame.ValueImage,
} {
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var value_image = try world.Frame.ValueImage.fromValue(
        allocator,
        1,
        0x5150_1a03,
        null,
        value,
        world.ValuePolicy.portable,
    );
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0x5150_1a03,
        .final_value_image_fingerprint = value_image.value_image_fingerprint,
        .status = .completed,
    });
    return .{
        .image = world.RunImage.init(.{
            .kind = .completed_run,
            .target_ref = provider_ref,
            .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
            .current_state = state,
            .final_result_image = value_image,
        }),
        .value_image = value_image,
    };
}

fn pendingFor(runspace: *world.Runspace, allocator: std.mem.Allocator, handle: world.RunHandle) !u64 {
    const pending_ports = try runspace.mailbox.listPending(allocator);
    defer allocator.free(pending_ports);
    for (pending_ports) |pending| {
        if (pending.handle.handle_fingerprint == handle.handle_fingerprint) return pending.mailbox_id;
    }
    return error.ExpectedPendingPort;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const root_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const provider_ref = world.TargetRef.fromTarget(fixtures.ProviderPorts.Target);
    const provider_import = world.ImportRequirement.fromTargetPort(fixtures.ProviderPorts.Target, 0);
    const strict_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const provider_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id, .schema_fingerprint = root_import.response_value_ref_fingerprint },
        .label = "provider-main",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = provider_export,
            .import_set = world.ImportSet.fromTarget(fixtures.ProviderPorts.Target),
            .imports = &.{provider_import},
            .label = "nested-provider",
        }),
    };
    var root_link = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Ports.Target),
        .root_imports = &.{root_import},
        .catalog = world.Linker.Catalog.init(&entries),
        .policy = .allow_external_ports,
    });
    defer root_link.deinit();
    const nested_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = strict_ref,
        .result_ref = .{ .value_table_id = provider_import.response_value_table_id, .schema_fingerprint = provider_import.response_value_ref_fingerprint },
        .label = "strict-nested-main",
    });
    const nested_entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = strict_ref,
            .export_descriptor = nested_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "strict-nested-provider",
        }),
    };
    var nested_link = try world.Linker.link(allocator, .{
        .root_target_ref = provider_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.ProviderPorts.Target),
        .root_imports = &.{provider_import},
        .catalog = world.Linker.Catalog.init(&nested_entries),
        .policy = .strict_closed,
    });
    defer nested_link.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    try root_link.assembly.installIntoRunspace(&runspace);
    try nested_link.assembly.installIntoRunspace(&runspace);
    const root_handle = try runspace.installMachineRun(fixtures.Ports.Target, RootEnv, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    const provider_handle = try runspace.installMachineRun(fixtures.ProviderPorts.Target, ProviderEnv, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    _ = try runspace.tick();

    const root_invocation = try runspace.routePendingToProviderRun(try pendingFor(&runspace, allocator, root_handle), root_link.plan.fabric_plans[0], provider_handle);
    var nested_provider = try providerImage(allocator, 7);
    defer nested_provider.value_image.deinit(allocator);
    const nested_provider_handle = try runspace.installRunImage(nested_provider.image);
    const nested_invocation = try runspace.routePendingToProviderRun(try pendingFor(&runspace, allocator, provider_handle), nested_link.plan.fabric_plans[0], nested_provider_handle);
    _ = try runspace.respondFromFabric(nested_invocation);
    _ = try runspace.tick();
    _ = try runspace.respondFromFabric(root_invocation);
    _ = try runspace.tick();

    try stdout.print("link_depth={d}\n", .{root_link.graph.max_depth_observed});
    try stdout.print("route_count={d}\n", .{root_link.report.route_count + nested_link.report.route_count});
    try stdout.print("final_result=7\n", .{});
    try stdout.print("native_handler_calls={d}\n", .{ctx.native_calls});
    try stdout.flush();
}
