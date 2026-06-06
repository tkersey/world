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

fn providerImage(allocator: std.mem.Allocator, seed: u64, value: i32) !struct {
    image: world.RunImage,
    value_image: world.Frame.ValueImage,
} {
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    var value_image = try world.Frame.ValueImage.fromValue(
        allocator,
        1,
        seed,
        null,
        value,
        world.ValuePolicy.portable,
    );
    errdefer value_image.deinit(allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .final_response_fingerprint = seed,
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

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: Ctx = .{};
    var runspace = world.Runspace.init(allocator, .{});
    defer runspace.deinit();

    const parent_handle = try runspace.installMachineRun(fixtures.Ports.Target, ParentEnv, &runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    _ = try runspace.tick();

    var provider = try providerImage(allocator, 0x5150_fab1, 7);
    defer provider.value_image.deinit(allocator);
    const provider_handle = try runspace.installRunImage(provider.image);
    const parent_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const provider_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const mapping = world.Fabric.ValueMapping.init(.{
        .kind = .provider_result_to_parent_response,
        .provider_result_value_table_id = 1,
        .parent_response_value_table_id = 1,
    });
    const route = world.Fabric.Route.init(.{
        .route_id = 0xfab1,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = ApprovalPort.world_port_id,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .value_mapping_fingerprint = mapping.mapping_fingerprint,
        .max_depth = 2,
        .metadata = "approval provider",
    });
    const plan = world.Fabric.Plan.init(.{
        .target_ref_fingerprint = parent_ref.target_ref_fingerprint,
        .module_fingerprint = parent_ref.boundary_module_fingerprint,
        .world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .routes = &.{route},
        .value_mappings = &.{mapping},
        .max_depth = 2,
        .max_provider_runs = 1,
    });
    try runspace.installFabricPlan(parent_ref, plan);
    const invocation = try runspace.routePendingToProviderRun(0, plan, provider_handle);
    _ = try runspace.respondFromFabric(invocation);
    _ = try runspace.tick();

    const receipt = runspace.fabric_receipts.items[0];
    try stdout.print("parent_run_handle={x}\n", .{parent_handle.handle_fingerprint});
    try stdout.print("provider_run_handle={x}\n", .{provider_handle.handle_fingerprint});
    try stdout.print("fabric_receipt_fingerprint={x}\n", .{receipt.receipt_fingerprint});
    try stdout.print("final_result=7\n", .{});
    try stdout.print("native_handler_calls={d}\n", .{ctx.native_calls});
    try stdout.flush();
}
