const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const Ctx = struct { native_calls: usize = 0 };

fn unexpectedNative(ctx: *Ctx, _: []const u8) !i32 {
    ctx.native_calls += 1;
    return error.UnexpectedNativeHandler;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, unexpectedNative);
const ParentEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{world.bind(ApprovalPort, world.NativeAdapter(unexpectedNative))},
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
        0x5150_1a01,
        null,
        value,
        world.ValuePolicy.portable,
    );
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0x5150_1a01,
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

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    const root_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const root_import = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const provider_export = world.Linker.ExportDescriptor.init(.{
        .target_ref = provider_ref,
        .result_ref = .{ .value_table_id = root_import.response_value_table_id, .value_ref_fingerprint = root_import.response_value_ref_fingerprint },
        .label = "strict-provider-main",
    });
    const entries = [_]world.Linker.Catalog.Entry{
        world.Linker.Catalog.Entry.generatedTarget(.{
            .target_ref = provider_ref,
            .export_descriptor = provider_export,
            .import_set = world.ImportSet.fromTarget(fixtures.Strict.Target),
            .label = "strict-provider",
        }),
    };
    const hint = world.Linker.Hint.init(.{
        .parent_target_ref_fingerprint = root_ref.target_ref_fingerprint,
        .parent_world_port_id = root_import.world_port_id,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_export_fingerprint = provider_export.export_fingerprint,
        .route_kind = .target_export,
        .label = "strict-provider",
    });
    var linked = try world.Linker.link(allocator, .{
        .root_target_ref = root_ref,
        .root_import_set = world.ImportSet.fromTarget(fixtures.Ports.Target),
        .root_imports = &.{root_import},
        .catalog = world.Linker.Catalog.init(&entries),
        .hints = &.{hint},
        .policy = .strict_closed,
    });
    defer linked.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();
    try linked.assembly.installIntoRunspace(&runspace);
    _ = try runspace.installMachineRun(fixtures.Ports.Target, ParentEnv, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    _ = try runspace.tick();
    var provider = try providerImage(allocator, 7);
    defer provider.value_image.deinit(allocator);
    const provider_handle = try runspace.installRunImage(provider.image);
    const invocation = try runspace.routePendingToProviderRun(0, linked.plan.fabric_plans[0], provider_handle);
    _ = try runspace.respondFromFabric(invocation);
    _ = try runspace.tick();

    try stdout.print("link_plan_fingerprint={x}\n", .{linked.plan.plan_fingerprint});
    try stdout.print("fabric_route_count={d}\n", .{linked.report.route_count});
    try stdout.print("assembly_fingerprint={x}\n", .{linked.assembly.assembly_fingerprint});
    try stdout.print("final_result=7\n", .{});
    try stdout.print("native_handler_calls={d}\n", .{ctx.native_calls});
    try stdout.flush();
}
