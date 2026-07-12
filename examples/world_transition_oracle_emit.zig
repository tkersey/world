// zlinter-disable declaration_naming field_ordering no_inferred_error_unions no_swallow_error require_doc_comment require_errdefer_dealloc
const boundary = @import("boundary");
const builtin = @import("builtin");
const common = @import("world_appliance_common.zig");
const fixtures = @import("world_fixtures");
const std = @import("std");
const universal = @import("world_universal_appliance_wasm.zig");
const world = @import("world");

const corpus_path = "conformance/world-image-v1/v0/world";
const checksum_prefix = corpus_path ++ "/";
const canonical_output_suffix = "conformance/world-image-v1/v0/world";

fn canonicalizePathSeparators(path_bytes: []u8, native_separator: u8) void {
    if (native_separator == '/') return;
    for (path_bytes) |*byte| {
        if (byte.* == native_separator) byte.* = '/';
    }
}

fn isAllowedIsolatedOutputPath(path_bytes: []const u8) bool {
    return std.mem.eql(u8, path_bytes, "./bundle");
}

comptime {
    var windows_isolated = ".\\bundle".*;
    canonicalizePathSeparators(windows_isolated[0..], '\\');
    if (!isAllowedIsolatedOutputPath(windows_isolated[0..])) {
        @compileError("native isolated oracle path must be admitted");
    }

    var windows_nested = "artifacts\\states\\checkpoint.bin".*;
    canonicalizePathSeparators(windows_nested[0..], '\\');
    if (!std.mem.eql(u8, windows_nested[0..], "artifacts/states/checkpoint.bin")) {
        @compileError("native walked paths must have portable identities");
    }

    var windows_unrelated = "C:\\repo\\bundle".*;
    canonicalizePathSeparators(windows_unrelated[0..], '\\');
    if (isAllowedIsolatedOutputPath(windows_unrelated[0..])) {
        @compileError("unrelated native output path must remain rejected");
    }
}

const Case = struct {
    id: []const u8,
    transcript: []const u8,
};

const cases = [_]Case{
    .{ .id = "one-port-execution", .transcript = "cases/one-port-execution.txt" },
    .{ .id = "internal-provider-execution", .transcript = "cases/internal-provider-execution.txt" },
    .{ .id = "provider-parked-externally", .transcript = "cases/provider-parked-externally.txt" },
    .{ .id = "active-provider-restore", .transcript = "cases/active-provider-restore.txt" },
    .{ .id = "replay-without-fresh-effect", .transcript = "cases/replay-without-fresh-effect.txt" },
    .{ .id = "lost-output-retry", .transcript = "cases/lost-output-retry.txt" },
    .{ .id = "migration", .transcript = "cases/migration.txt" },
    .{ .id = "branching", .transcript = "cases/branching.txt" },
    .{ .id = "partial-response-batch", .transcript = "cases/partial-response-batch.txt" },
    .{ .id = "deterministic-failure", .transcript = "cases/deterministic-failure.txt" },
    .{ .id = "capacity-exhaustion", .transcript = "cases/capacity-exhaustion.txt" },
    .{ .id = "malformed-records", .transcript = "cases/malformed-records.txt" },
};

const Writer = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    root: []const u8,
    paths: std.ArrayList([]const u8) = .empty,

    fn write(self: *@This(), relative_path: []const u8, data: []const u8) !void {
        for (self.paths.items) |existing| {
            if (std.mem.eql(u8, existing, relative_path)) return error.DuplicateArtifactPath;
        }
        const full_path = try std.fs.path.join(self.allocator, &.{ self.root, relative_path });
        if (std.fs.path.dirname(full_path)) |parent| try std.Io.Dir.cwd().createDirPath(self.io, parent);
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = full_path, .data = data });
        try self.paths.append(self.allocator, try self.allocator.dupe(u8, relative_path));
    }
};

const OwnedPaths = struct {
    allocator: std.mem.Allocator,
    items: [][]u8,

    fn deinit(self: *@This()) void {
        for (self.items) |item| self.allocator.free(item);
        self.allocator.free(self.items);
        self.items = &.{};
    }
};

const PublicationTarget = union(enum) {
    isolated: []const u8,
    trusted_prefix: []const u8,
};

const ReplayCtx = struct { calls: usize = 0 };

fn replayApprove(ctx: *ReplayCtx, payload: []const u8) !i32 {
    if (!std.mem.eql(u8, payload, "deploy-prod")) return error.UnexpectedPayload;
    ctx.calls += 1;
    return 7;
}

const ReplayApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, replayApprove);
const ReplayMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{ReplayApprovalPort},
    .strict_handler_coverage = true,
});

const BranchCtx = struct {
    allocator: std.mem.Allocator,
    alternate: bool = false,
};

fn branchDecide(ctx: *BranchCtx, observation: []const u8) !fixtures.Agent.Action {
    if (ctx.alternate) return .{ .final = "final=branch alternate" };
    return fixtures.Agent.decideAction(.skeleton, observation);
}

fn branchTool(ctx: *BranchCtx, command: []const u8) ![]const u8 {
    return fixtures.Agent.callTool(ctx.allocator, .skeleton, command);
}

const BranchDecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, branchDecide);
const BranchToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, branchTool);
const BranchMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ BranchDecidePort, BranchToolPort },
    .strict_handler_coverage = true,
});

const BatchCtx = struct {};

fn batchDecide(_: *BatchCtx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "final=actuate skeleton complete" };
}

fn batchTool(_: *BatchCtx, _: []const u8) ![]const u8 {
    return "tool";
}

const BatchDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, batchDecide);
const BatchToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, batchTool);
const BatchActuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "world-image-v1-oracle.batch",
    .supported_response_statuses = world.Actuation.ResponseStatusSet.all,
    .value_policy = world.ValuePolicy.portable,
});
const BatchAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .actuation_bindings = .{
        world.bindActuator(BatchDecideDecl, BatchActuator),
        world.bindActuator(BatchToolDecl, BatchActuator),
    },
});

pub fn main(init: std.process.Init) !void {
    comptime {
        if (world.world_executable_image_format_version != 2) @compileError("update World Image v1 oracle executable image format binding");
        if (world.world_appliance_turn_closure_format_version != 1) @compileError("update World Image v1 oracle TurnClosure format binding");
        if (world.Archive.world_archive_format_version != 1) @compileError("update World Image v1 oracle Archive format binding");
        if (world.world_appliance_abi_version != 4) @compileError("update World Image v1 oracle Appliance ABI binding");
        if (world.world_appliance_command_format_version != 1) @compileError("update World Image v1 oracle Appliance Command format binding");
        if (world.world_appliance_wire_turn_input_format_version != 2) @compileError("update World Image v1 oracle Wire.TurnInput format binding");
        if (world.world_appliance_wire_resolution_input_format_version != 1) @compileError("update World Image v1 oracle Wire.ResolutionInput format binding");
    }
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const command = args.next() orelse return error.InvalidArguments;
    if (!std.mem.eql(u8, command, "generate")) return error.InvalidArguments;
    const target_flag = args.next() orelse return error.InvalidArguments;
    const target_path = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    const publication_target: PublicationTarget = if (std.mem.eql(u8, target_flag, "--out-dir")) blk: {
        const portable_output_dir = try allocator.dupe(u8, target_path);
        canonicalizePathSeparators(portable_output_dir, std.fs.path.sep);
        if (!isAllowedIsolatedOutputPath(portable_output_dir)) return error.InvalidOutputDirectory;
        break :blk .{ .isolated = target_path };
    } else if (std.mem.eql(u8, target_flag, "--trusted-prefix")) blk: {
        if (!std.fs.path.isAbsolute(target_path)) return error.InvalidTrustedPrefix;
        break :blk .{ .trusted_prefix = target_path };
    } else return error.InvalidArguments;

    const staging_dir = "./world-transition-oracle-staging";
    try std.Io.Dir.cwd().deleteTree(init.io, staging_dir);
    try std.Io.Dir.cwd().createDirPath(init.io, staging_dir);
    defer std.Io.Dir.cwd().deleteTree(init.io, staging_dir) catch {};
    var writer = Writer{ .io = init.io, .allocator = allocator, .root = staging_dir };

    try emitOnePort(allocator, &writer);
    try emitInternalProvider(allocator, &writer);
    try emitActiveProvider(allocator, &writer);
    try emitReplay(allocator, &writer);
    try emitRetry(allocator, &writer);
    try emitBranching(allocator, &writer);
    try emitPartialBatch(allocator, &writer);
    try emitDeterministicFailure(allocator, &writer);
    try emitCapacityExhaustion(allocator, &writer);
    try emitMalformed(allocator, &writer);
    try writeManifest(allocator, &writer);
    try writeChecksums(allocator, &writer);
    try promoteCorpus(allocator, &writer, publication_target);
}

fn emitOnePort(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA100_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const manifest_bytes = try manifest.encode(allocator);
    try writer.write("artifacts/manifests/one-port.appliance-manifest", manifest_bytes);

    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/one-port.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const waiting_output_bytes = try common.readOutputOwned(allocator, &native);
    const waiting_closure_bytes = try common.readClosureOwned(allocator, &native);
    var waiting_output = try world.Appliance.TurnOutput.decode(allocator, waiting_output_bytes, manifest.manifest_fingerprint, capacity);
    defer waiting_output.deinit(allocator);
    var waiting_closure = try world.Appliance.TurnClosure.decode(allocator, waiting_closure_bytes);
    defer waiting_closure.deinit(allocator);
    try waiting_closure.validate(allocator, .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });
    if (waiting_output.host_requests.len != 1) return error.ExpectedOneHostRequest;
    try writer.write("artifacts/outputs/one-port.waiting.turn-output", waiting_output_bytes);
    try writer.write("artifacts/transitions/one-port.waiting.turn-closure", waiting_closure_bytes);
    try writer.write("artifacts/states/one-port.waiting.checkpoint", waiting_closure.checkpoint_bytes);
    try writer.write("artifacts/states/one-port.waiting.capsule", waiting_closure.capsule_bytes);
    try writer.write("artifacts/effects/one-port.pending.host-requests", waiting_closure.pending_host_request_bytes);

    const resolution = try common.wireResolutionFor(allocator, waiting_output.host_requests[0], .responded, 0xA100_0002);
    var resolution_bytes: std.ArrayList(u8) = .empty;
    try resolution.encode(&resolution_bytes, allocator);
    try writer.write("artifacts/effects/one-port.responded.resolution-input", resolution_bytes.items);
    const continue_turn = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = waiting_closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = waiting_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_turn.encode(allocator);
    try writer.write("artifacts/inputs/one-port.continue.turn-input", continue_bytes);
    if (native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const completed_output_bytes = try common.readOutputOwned(allocator, &native);
    const completed_closure_bytes = try common.readClosureOwned(allocator, &native);
    var completed_output = try world.Appliance.TurnOutput.decode(allocator, completed_output_bytes, manifest.manifest_fingerprint, capacity);
    defer completed_output.deinit(allocator);
    var completed_closure = try world.Appliance.TurnClosure.decode(allocator, completed_closure_bytes);
    defer completed_closure.deinit(allocator);
    try completed_closure.validate(allocator, .{
        .expected_executable_image_fingerprint = executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = waiting_closure.closure_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });
    try writer.write("artifacts/outputs/one-port.completed.turn-output", completed_output_bytes);
    try writer.write("artifacts/transitions/one-port.completed.turn-closure", completed_closure_bytes);
    try writer.write("artifacts/states/one-port.completed.checkpoint", completed_closure.checkpoint_bytes);
    try writer.write("artifacts/states/one-port.completed.capsule", completed_closure.capsule_bytes);
    try writer.write("artifacts/results/one-port.root-result", completed_closure.root_result_bytes);
    try writer.write("artifacts/history/one-port.archive-append-batch", completed_closure.archive_append_batch_bytes);

    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: one-port-execution\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "waiting_status: {s}\n" ++
            "completed_status: {s}\n" ++
            "request_count: {d}\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "completed_closure_fingerprint: 0x{x:0>16}\n" ++
            "result_bytes_present: true\n" ++
            "archive_append_present: true\n",
        .{
            @tagName(waiting_output.status),
            @tagName(completed_output.status),
            waiting_output.host_requests.len,
            waiting_closure.closure_fingerprint,
            completed_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/one-port-execution.txt", transcript);
}

fn buildLoadedProviderImage(allocator: std.mem.Allocator) !world.Executable.Image {
    const root_bytes = try fixtures.ProviderPorts.Target.Module.fullImage(allocator);
    const provider_bytes = try fixtures.Strict.Target.Module.fullImage(allocator);
    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .linker_policy = .strict_closed,
        .metadata = "world-image-v1-oracle.internal-provider",
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    try builder.addProviderModule(provider_bytes);
    var prepared = try builder.prepare();
    defer prepared.deinit();
    return prepared.seal();
}

fn emitInternalProvider(allocator: std.mem.Allocator, writer: *Writer) !void {
    var image = try buildLoadedProviderImage(allocator);
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    try writer.write("artifacts/images/internal-provider.executable-image", image_bytes);
    var loaded_image = try world.Executable.Image.decode(allocator, image_bytes, .{
        .max_image_bytes = image_bytes.len,
    });
    defer loaded_image.deinit(allocator);

    const capacity = universal.abi_capacity;
    const core = try world.Appliance.Core.initExecutable(allocator, loaded_image, .{
        .profile = .wasm_small,
        .capacity = capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-image-v1-oracle.internal-provider",
    });
    var native = world.Appliance.Native.init(core);
    defer native.deinit();
    const manifest = native.core.readManifest();
    const manifest_bytes = try manifest.encode(allocator);
    try writer.write("artifacts/manifests/internal-provider.appliance-manifest", manifest_bytes);

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/internal-provider.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .completed) return error.ExpectedCompleted;
    const output_bytes = try common.readOutputOwned(allocator, &native);
    const closure_bytes = try common.readClosureOwned(allocator, &native);
    var output = try world.Appliance.TurnOutput.decode(allocator, output_bytes, manifest.manifest_fingerprint, capacity);
    defer output.deinit(allocator);
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    defer closure.deinit(allocator);
    try closure.validate(allocator, .{
        .expected_executable_image_fingerprint = loaded_image.image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .bundle_options = .{ .allow_external_dependencies = true },
    });
    if (output.host_requests.len != 0) return error.UnexpectedHostRequest;
    try writer.write("artifacts/outputs/internal-provider.completed.turn-output", output_bytes);
    try writer.write("artifacts/transitions/internal-provider.completed.turn-closure", closure_bytes);
    try writer.write("artifacts/states/internal-provider.completed.capsule", closure.capsule_bytes);
    try writer.write("artifacts/results/internal-provider.root-result", closure.root_result_bytes);

    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: internal-provider-execution\n" ++
            "owner_surface: Executable/Runspace/Fabric/TurnClosure\n" ++
            "status: {s}\n" ++
            "module_count: {d}\n" ++
            "provider_module_count: 1\n" ++
            "route_count: {d}\n" ++
            "external_request_count: {d}\n" ++
            "image_fingerprint: 0x{x:0>16}\n" ++
            "closure_fingerprint: 0x{x:0>16}\n",
        .{
            @tagName(output.status),
            loaded_image.module_set.modules.len,
            loaded_image.dispatch_image.route_ids.len,
            output.host_requests.len,
            loaded_image.image_fingerprint,
            closure.closure_fingerprint,
        },
    );
    try writer.write("cases/internal-provider-execution.txt", transcript);
}

fn activeProviderRequest(target_ref: world.TargetRef, world_port_id: u32, seed: u64) world.Frame.Request {
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

fn emitActiveProvider(allocator: std.mem.Allocator, writer: *Writer) !void {
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
    const parent_request = activeProviderRequest(parent_ref, 0, 0xA103_0001);
    const provider_request = activeProviderRequest(provider_ref, 0, 0xA103_0002);
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
        .route_id = 0xA103_0003,
        .kind = .target_export,
        .parent_world_surface_fingerprint = parent_ref.world_surface_fingerprint,
        .parent_target_certificate_fingerprint = parent_ref.target_certificate_fingerprint,
        .parent_world_port_id = 0,
        .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
        .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
        .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
        .response_value_mapping_fingerprint = mapping.mapping_fingerprint,
        .metadata = "world-image-v1-oracle.active-provider",
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

    var source_capsule = try world.Capsule.freezeRunspace(&source, .{ .allow_active_fabric_parked = true });
    defer source_capsule.deinit(allocator);
    const source_capsule_bytes = try source_capsule.encode(allocator);
    var decoded_source_capsule = try world.Capsule.Image.decode(allocator, source_capsule_bytes);
    defer decoded_source_capsule.deinit(allocator);
    try decoded_source_capsule.validate(.{});
    const provider_request_bytes = try provider_request.encode(allocator);
    try writer.write("artifacts/states/active-provider.source.capsule", source_capsule_bytes);
    try writer.write("artifacts/effects/active-provider.external.request-frame", provider_request_bytes);
    source.deinit();
    source_destroyed = true;

    var receiver = world.Runspace.init(allocator, .{});
    defer receiver.deinit();
    var restore = try world.Capsule.thawIntoRunspace(decoded_source_capsule, &receiver, parent_ref.target_ref_fingerprint, 0, 0xA103_0004, .{
        .mode = .restore_parked,
        .require_local_permit = false,
        .require_link_match = false,
    });
    defer restore.deinit(allocator);
    if (!restore.accepted) return error.ExpectedRestoreAccepted;
    var migrated_capsule = try world.Capsule.freezeRunspace(&receiver, .{ .allow_active_fabric_parked = true });
    defer migrated_capsule.deinit(allocator);
    const migrated_capsule_bytes = try migrated_capsule.encode(allocator);
    try writer.write("artifacts/states/active-provider.migrated.capsule", migrated_capsule_bytes);

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
    var completed_capsule = try world.Capsule.freezeRunspace(&receiver, .{});
    defer completed_capsule.deinit(allocator);
    const completed_capsule_bytes = try completed_capsule.encode(allocator);
    var decoded_completed_capsule = try world.Capsule.Image.decode(allocator, completed_capsule_bytes);
    defer decoded_completed_capsule.deinit(allocator);
    try decoded_completed_capsule.validate(.{});
    try writer.write("artifacts/states/active-provider.completed.capsule", completed_capsule_bytes);

    const parked_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: provider-parked-externally\n" ++
            "owner_surface: Runspace/Fabric/Capsule\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "parent_status: parked_on_port\n" ++
            "provider_status: parked_on_port\n" ++
            "fabric_invocation_status: provider_parked\n" ++
            "pending_port_fingerprint: 0x{x:0>16}\n" ++
            "capsule_fingerprint: 0x{x:0>16}\n",
        .{ provider_pending.pending_port_fingerprint, source_capsule.image_fingerprint },
    );
    try writer.write("cases/provider-parked-externally.txt", parked_transcript);

    const restore_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: active-provider-restore\n" ++
            "owner_surface: Capsule/Runspace/Fabric\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "restore_accepted: true\n" ++
            "restored_route_count: {d}\n" ++
            "restored_invocation_count: {d}\n" ++
            "provider_completed: {}\n" ++
            "root_completed: {}\n" ++
            "completed_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_state_artifact: artifacts/states/active-provider.completed.capsule\n",
        .{
            receiver.fabric_routes.items.len,
            receiver.fabric_invocations.items.len,
            provider_event.kind == .run_completed,
            root_event.kind == .run_completed,
            completed_capsule.image_fingerprint,
        },
    );
    try writer.write("cases/active-provider-restore.txt", restore_transcript);

    const migration_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: migration\n" ++
            "owner_surface: Capsule/Runspace/Fabric\n" ++
            "fixture_provenance: synthetic-owner-state\n" ++
            "source_destroyed: {}\n" ++
            "receiver_fresh_instance: true\n" ++
            "restore_accepted: true\n" ++
            "source_capsule_fingerprint: 0x{x:0>16}\n" ++
            "migrated_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_after_migration: {}\n" ++
            "completed_capsule_fingerprint: 0x{x:0>16}\n" ++
            "completed_state_artifact: artifacts/states/active-provider.completed.capsule\n",
        .{
            source_destroyed,
            source_capsule.image_fingerprint,
            migrated_capsule.image_fingerprint,
            provider_event.kind == .run_completed and root_event.kind == .run_completed,
            completed_capsule.image_fingerprint,
        },
    );
    try writer.write("cases/migration.txt", migration_transcript);
}

const RetryParent = struct {
    closure_bytes: []const u8,
    closure: world.Appliance.TurnClosure,
};

fn makeRetryParent(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    executable_image_fingerprint: u64,
) !RetryParent {
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();
    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const closure_bytes = try common.readClosureOwned(allocator, &native);
    return .{
        .closure_bytes = closure_bytes,
        .closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes),
    };
}

fn nativeFromClosure(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    executable_image_fingerprint: u64,
    closure_bytes: []const u8,
) !world.Appliance.Native {
    var closure = try world.Appliance.TurnClosure.decode(allocator, closure_bytes);
    defer closure.deinit(allocator);
    const checkpoint_bytes = try closure.materializeCheckpoint(allocator);
    var checkpoint = try world.Appliance.Checkpoint.decode(allocator, checkpoint_bytes, manifest.manifest_fingerprint, capacity);
    defer checkpoint.deinit(allocator);
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    errdefer core.deinit();
    try core.restore(checkpoint);
    var native = world.Appliance.Native.init(core);
    native.last_closure_bytes = try allocator.dupe(u8, closure_bytes);
    native.last_closure_owned = true;
    return native;
}

fn emitRetry(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA106_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    try writer.write("artifacts/transitions/retry.parent.turn-closure", parent.closure_bytes);
    try writer.write("artifacts/states/retry.parent.checkpoint", parent.closure.checkpoint_bytes);

    var first_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer first_native.deinit();
    if (first_native.core.outstanding_host_requests.len != 1) return error.ExpectedOneHostRequest;
    const request = first_native.core.outstanding_host_requests[0];
    const response_bytes = try common.responseValueImageBytes(allocator, request, 0xA106_0002);
    const resolution = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.effect-called-once",
        .attempt_number = 1,
        .metadata = "persisted-before-world-submission",
    });
    var resolution_bytes: std.ArrayList(u8) = .empty;
    try resolution.encode(&resolution_bytes, allocator);
    try writer.write("artifacts/effects/retry.persisted.resolution-input", resolution_bytes.items);
    const continue_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = first_native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = first_native.core.current_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const continue_bytes = try continue_input.encode(allocator);
    try writer.write("artifacts/inputs/retry.continue.turn-input", continue_bytes);
    if (first_native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const first_output_bytes = try common.readOutputOwned(allocator, &first_native);
    const first_closure_bytes = try common.readClosureOwned(allocator, &first_native);
    try writer.write("artifacts/outputs/retry.first.turn-output", first_output_bytes);
    try writer.write("artifacts/transitions/retry.first.turn-closure", first_closure_bytes);

    var retry_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer retry_native.deinit();
    if (retry_native.submitTurn(continue_bytes) != .completed) return error.ExpectedCompleted;
    const retry_output_bytes = try common.readOutputOwned(allocator, &retry_native);
    const retry_closure_bytes = try common.readClosureOwned(allocator, &retry_native);
    try writer.write("artifacts/outputs/retry.repeated.turn-output", retry_output_bytes);
    try writer.write("artifacts/transitions/retry.repeated.turn-closure", retry_closure_bytes);
    if (!std.mem.eql(u8, first_output_bytes, retry_output_bytes)) return error.RetryOutputMismatch;
    if (!std.mem.eql(u8, first_closure_bytes, retry_closure_bytes)) return error.RetryClosureMismatch;

    const restore_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .restore,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent.closure.turn_receipt_fingerprint,
        .turn_sequence_number = parent.closure.turn_sequence_number + 1,
        .parent_turn_closure_bytes = parent.closure_bytes,
        .resolutions = &.{resolution},
    });
    const restore_bytes = try restore_input.encode(allocator);
    try writer.write("artifacts/inputs/retry.cold-restore.turn-input", restore_bytes);
    var restore_core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    restore_core.executable_image_fingerprint = executable_image_fingerprint;
    var restore_native = world.Appliance.Native.init(restore_core);
    defer restore_native.deinit();
    if (restore_native.submitTurn(restore_bytes) != .completed) return error.ExpectedCompleted;
    const restore_closure_bytes = try common.readClosureOwned(allocator, &restore_native);
    try writer.write("artifacts/transitions/retry.cold-restore.turn-closure", restore_closure_bytes);

    var first_closure = try world.Appliance.TurnClosure.decode(allocator, first_closure_bytes);
    defer first_closure.deinit(allocator);
    const transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: lost-output-retry\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "effect_call_count: 1\n" ++
            "result_persisted_before_step: true\n" ++
            "first_retry_output_byte_equal: true\n" ++
            "first_retry_closure_byte_equal: true\n" ++
            "cold_restore_completed: true\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "result_closure_fingerprint: 0x{x:0>16}\n",
        .{ parent.closure.closure_fingerprint, first_closure.closure_fingerprint },
    );
    try writer.write("cases/lost-output-retry.txt", transcript);
}

fn emitReplay(allocator: std.mem.Allocator, writer: *Writer) !void {
    var transcript = world.Transcript.init(allocator);
    defer transcript.deinit();
    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: ReplayCtx = .{};
    var fresh = try ReplayMachine.run(&fresh_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(allocator);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    try writer.write("artifacts/states/replay.transcript-image", image_bytes);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const run_image_bytes = try run_image.encode(allocator);
    try writer.write("artifacts/states/replay.completed.run-image", run_image_bytes);

    var decoded = try world.TranscriptImage.decode(allocator, image_bytes);
    defer decoded.deinit(allocator);
    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replayed = try ReplayMachine.run(&replay_runtime, .{}, .{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    });
    defer replayed.deinit(allocator);
    if (fresh_ctx.calls != 1 or replayed.audit.replayed_response_count != 1 or fresh.value != replayed.value) {
        return error.ReplaySemanticMismatch;
    }

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: replay-without-fresh-effect\n" ++
            "owner_surface: Machine/Transcript\n" ++
            "turn_closure_authority: false\n" ++
            "fresh_handler_calls: {d}\n" ++
            "replay_handler_calls: 0\n" ++
            "replayed_response_count: {d}\n" ++
            "fresh_result: {d}\n" ++
            "replay_result: {d}\n" ++
            "transcript_image_fingerprint: 0x{x:0>16}\n" ++
            "run_image_fingerprint: 0x{x:0>16}\n",
        .{
            fresh_ctx.calls,
            replayed.audit.replayed_response_count,
            fresh.value,
            replayed.value,
            image.transcript_image_fingerprint,
            run_image.run_image_fingerprint,
        },
    );
    try writer.write("cases/replay-without-fresh-effect.txt", case_transcript);
}

const BranchRun = struct {
    value: []const u8,
    transcript: world.Transcript,
    image: world.TranscriptImage,
};

fn runBranch(allocator: std.mem.Allocator, alternate: bool) !BranchRun {
    var transcript = world.Transcript.init(allocator);
    errdefer transcript.deinit();
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var ctx: BranchCtx = .{ .allocator = allocator, .alternate = alternate };
    var result = try BranchMachine.run(&runtime, .{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(allocator);
    const value = try allocator.dupe(u8, result.value);
    var image = try transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    errdefer image.deinit(allocator);
    return .{ .value = value, .transcript = transcript, .image = image };
}

fn forkBranchTranscript(
    allocator: std.mem.Allocator,
    baseline: *const world.Transcript,
    alternate: *const world.Transcript,
    checkpoint_event_index: usize,
) !world.Transcript {
    if (checkpoint_event_index > baseline.events.items.len or checkpoint_event_index > alternate.events.items.len) return error.InvalidFrameEncoding;
    var forked = world.Transcript.init(allocator);
    errdefer forked.deinit();
    for (baseline.events.items[0..checkpoint_event_index]) |event| try forked.append(event);
    for (alternate.events.items[checkpoint_event_index..]) |event| try forked.append(event);
    return forked;
}

fn emitBranching(allocator: std.mem.Allocator, writer: *Writer) !void {
    var baseline = try runBranch(allocator, false);
    defer {
        baseline.image.deinit(allocator);
        baseline.transcript.deinit();
    }
    var alternate = try runBranch(allocator, true);
    defer {
        alternate.image.deinit(allocator);
        alternate.transcript.deinit();
    }
    const checkpoint_event_index = 2;
    const checkpoint_event = baseline.image.events[checkpoint_event_index - 1];
    if (alternate.image.events[checkpoint_event_index - 1].request_fingerprint != checkpoint_event.request_fingerprint) {
        return error.BranchParentMismatch;
    }
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = checkpoint_event_index,
        .turn_index = checkpoint_event.turn_index orelse 0,
        .current_request_fingerprint = checkpoint_event.request_fingerprint,
        .transcript_prefix_fingerprint = checkpoint_event.event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    var forked_transcript = try forkBranchTranscript(allocator, &baseline.transcript, &alternate.transcript, checkpoint.event_index);
    defer forked_transcript.deinit();
    var forked_image = try forked_transcript.toImage(allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer forked_image.deinit(allocator);
    const baseline_image_bytes = try baseline.image.encode(allocator);
    const branch_image_bytes = try forked_image.encode(allocator);
    try writer.write("artifacts/states/branch.baseline.transcript-image", baseline_image_bytes);
    try writer.write("artifacts/states/branch.alternate.transcript-image", branch_image_bytes);

    const baseline_run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, baseline.image, .completed_run);
    const baseline_run_bytes = try baseline_run_image.encode(allocator);
    try writer.write("artifacts/states/branch.baseline.run-image", baseline_run_bytes);
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const branch = world.Timeline.Branch{
        .branch_id = 1,
        .parent_branch_id = null,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "world-image-v1-oracle.alternate",
        .start_event_index = checkpoint.event_index,
        .final_event_index = forked_image.events.len,
        .final_status = .completed,
        .event_count = forked_image.events.len - checkpoint.event_index,
        .response_count = forked_image.response_count,
    };
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = forked_image.transcript_image_fingerprint,
        .branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .status = .completed,
    });
    const branch_run_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = forked_image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    try branch_run_image.validate(.{ .require_portable_values = true });
    const branch_run_bytes = try branch_run_image.encode(allocator);
    try writer.write("artifacts/states/branch.alternate.run-image", branch_run_bytes);
    var decoded_branch_run = try world.RunImage.decode(allocator, branch_run_bytes);
    defer decoded_branch_run.deinit(allocator);
    try decoded_branch_run.validate(.{ .require_portable_values = true });

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: branching\n" ++
            "owner_surface: Machine/Transcript/Timeline/RunImage\n" ++
            "turn_closure_authority: false\n" ++
            "checkpoint_fingerprint: 0x{x:0>16}\n" ++
            "common_parent_request_fingerprint: 0x{x:0>16}\n" ++
            "baseline_transcript_fingerprint: 0x{x:0>16}\n" ++
            "alternate_transcript_fingerprint: 0x{x:0>16}\n" ++
            "baseline_result: {s}\n" ++
            "alternate_result: {s}\n" ++
            "parent_unchanged: true\n",
        .{
            checkpoint.checkpoint_fingerprint,
            checkpoint.current_request_fingerprint orelse 0,
            baseline.image.transcript_image_fingerprint,
            forked_image.transcript_image_fingerprint,
            baseline.value,
            alternate.value,
        },
    );
    try writer.write("cases/branching.txt", case_transcript);
}

fn emitPartialBatch(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA109_0000_0000_0001;
    const manifest = BatchAppliance.manifest();
    const capacity = world.Appliance.Capacity.wasm_agent;
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, BatchAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_images = &.{"agent:prompt"},
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.boot.turn-input", boot_bytes);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const parent_output_bytes = try common.readOutputOwned(allocator, &native);
    const parent_closure_bytes = try common.readClosureOwned(allocator, &native);
    var parent_output = try world.Appliance.TurnOutput.decode(allocator, parent_output_bytes, manifest.manifest_fingerprint, capacity);
    defer parent_output.deinit(allocator);
    var parent_closure = try world.Appliance.TurnClosure.decode(allocator, parent_closure_bytes);
    defer parent_closure.deinit(allocator);
    if (parent_output.host_requests.len != 2) return error.ExpectedBatchedRequests;
    try writer.write("artifacts/outputs/partial-batch.parent.turn-output", parent_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.parent.turn-closure", parent_closure_bytes);

    const first_resolution = try common.wireResolutionFor(allocator, parent_output.host_requests[0], .responded, 0xA109_0002);
    const partial_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{first_resolution},
    });
    const partial_input_bytes = try partial_input.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.one-result.turn-input", partial_input_bytes);
    if (native.submitTurn(partial_input_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const partial_output_bytes = try common.readOutputOwned(allocator, &native);
    const partial_closure_bytes = try common.readClosureOwned(allocator, &native);
    var partial_output = try world.Appliance.TurnOutput.decode(allocator, partial_output_bytes, manifest.manifest_fingerprint, capacity);
    defer partial_output.deinit(allocator);
    var partial_closure = try world.Appliance.TurnClosure.decode(allocator, partial_closure_bytes);
    defer partial_closure.deinit(allocator);
    if (partial_output.host_requests.len != 1) return error.ExpectedOneHostRequest;
    if (partial_output.host_requests[0].request_fingerprint != parent_output.host_requests[1].request_fingerprint) return error.PartialBatchMismatch;
    try writer.write("artifacts/outputs/partial-batch.remaining.turn-output", partial_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.remaining.turn-closure", partial_closure_bytes);
    try writer.write("artifacts/states/partial-batch.remaining.checkpoint", partial_closure.checkpoint_bytes);

    const second_resolution = try common.wireResolutionFor(allocator, partial_output.host_requests[0], .responded, 0xA109_0003);
    const final_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = partial_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = partial_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = partial_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 2,
        .resolutions = &.{second_resolution},
    });
    const final_input_bytes = try final_input.encode(allocator);
    try writer.write("artifacts/inputs/partial-batch.final-result.turn-input", final_input_bytes);
    if (native.submitTurn(final_input_bytes) != .completed) return error.ExpectedCompleted;
    const final_output_bytes = try common.readOutputOwned(allocator, &native);
    const final_closure_bytes = try common.readClosureOwned(allocator, &native);
    var final_output = try world.Appliance.TurnOutput.decode(allocator, final_output_bytes, manifest.manifest_fingerprint, capacity);
    defer final_output.deinit(allocator);
    try writer.write("artifacts/outputs/partial-batch.completed.turn-output", final_output_bytes);
    try writer.write("artifacts/transitions/partial-batch.completed.turn-closure", final_closure_bytes);

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: partial-response-batch\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "initial_request_count: {d}\n" ++
            "supplied_first_batch_count: 1\n" ++
            "remaining_request_count: {d}\n" ++
            "remaining_request_identity_preserved: true\n" ++
            "final_status: {s}\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "partial_closure_fingerprint: 0x{x:0>16}\n",
        .{
            parent_output.host_requests.len,
            partial_output.host_requests.len,
            @tagName(final_output.status),
            parent_closure.closure_fingerprint,
            partial_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/partial-response-batch.txt", case_transcript);
}

fn emitDeterministicFailure(allocator: std.mem.Allocator, writer: *Writer) !void {
    const executable_image_fingerprint: u64 = 0xA10A_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, common.PortsAppliance.memoryPlan(), capacity);
    core.executable_image_fingerprint = executable_image_fingerprint;
    var native = world.Appliance.Native.init(core);
    defer native.deinit();

    const boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    if (native.submitTurn(boot_bytes) != .needs_host) return error.ExpectedNeedsHost;
    const parent_output_bytes = try common.readOutputOwned(allocator, &native);
    const parent_closure_bytes = try common.readClosureOwned(allocator, &native);
    var parent_output = try world.Appliance.TurnOutput.decode(allocator, parent_output_bytes, manifest.manifest_fingerprint, capacity);
    defer parent_output.deinit(allocator);
    var parent_closure = try world.Appliance.TurnClosure.decode(allocator, parent_closure_bytes);
    defer parent_closure.deinit(allocator);
    const failed_resolution = try common.wireResolutionFor(allocator, parent_output.host_requests[0], .failed, 0);
    var failed_resolution_bytes: std.ArrayList(u8) = .empty;
    try failed_resolution.encode(&failed_resolution_bytes, allocator);
    try writer.write("artifacts/effects/failure.failed.resolution-input", failed_resolution_bytes.items);
    const failed_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent_closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent_closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = parent_output.turn_receipt.receipt_fingerprint,
        .turn_sequence_number = 1,
        .resolutions = &.{failed_resolution},
    });
    const failed_input_bytes = try failed_input.encode(allocator);
    try writer.write("artifacts/inputs/failure.failed-result.turn-input", failed_input_bytes);
    if (native.submitTurn(failed_input_bytes) != .failed) return error.ExpectedFailed;
    const failed_output_bytes = try common.readOutputOwned(allocator, &native);
    const failed_closure_bytes = try common.readClosureOwned(allocator, &native);
    var failed_output = try world.Appliance.TurnOutput.decode(allocator, failed_output_bytes, manifest.manifest_fingerprint, capacity);
    defer failed_output.deinit(allocator);
    var failed_closure = try world.Appliance.TurnClosure.decode(allocator, failed_closure_bytes);
    defer failed_closure.deinit(allocator);
    if (failed_output.status != .failed or failed_closure.status != .failed) return error.ExpectedFailed;
    try writer.write("artifacts/outputs/failure.failed.turn-output", failed_output_bytes);
    try writer.write("artifacts/transitions/failure.failed.turn-closure", failed_closure_bytes);
    try writer.write("artifacts/states/failure.failed.checkpoint", failed_closure.checkpoint_bytes);

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: deterministic-failure\n" ++
            "owner_surface: Appliance/TurnClosure\n" ++
            "result_transport_owner: Wire.TurnInput\n" ++
            "accepted_result_status: failed\n" ++
            "transition_status: {s}\n" ++
            "next_state_status: failed\n" ++
            "root_result_present: {}\n" ++
            "parent_closure_fingerprint: 0x{x:0>16}\n" ++
            "failed_closure_fingerprint: 0x{x:0>16}\n",
        .{
            @tagName(failed_output.status),
            failed_closure.root_result_bytes.len != 0,
            parent_closure.closure_fingerprint,
            failed_closure.closure_fingerprint,
        },
    );
    try writer.write("cases/deterministic-failure.txt", case_transcript);
}

fn emitCapacityExhaustion(allocator: std.mem.Allocator, writer: *Writer) !void {
    const tight = comptime blk: {
        var capacity = world.Appliance.Capacity.tiny_one_port;
        capacity.max_output_bytes = 1;
        break :blk capacity;
    };
    const TightAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = tight,
    });
    const manifest = TightAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(allocator, manifest, TightAppliance.memoryPlan(), tight);
    defer core.reset();
    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(allocator);
    try writer.write("artifacts/inputs/capacity-exhaustion.boot.command", boot_bytes);
    try core.submit(boot_bytes);
    var observed_error: ?anyerror = null;
    core.executeTurn() catch |err| {
        observed_error = err;
    };
    if (observed_error == null or observed_error.? != error.CapacityExceeded) return error.ExpectedCapacityExceeded;
    if (core.state != .uninitialized or core.current_turn_sequence_number != 0 or core.previous_turn_receipt_fingerprint != null) {
        return error.PartialSemanticMutation;
    }
    if (core.outstanding_host_requests.len != 0 or
        core.outstanding_host_request != null or
        core.readOutput().len != 0 or
        core.pending_command == null)
    {
        return error.PartialSemanticMutation;
    }
    const state_snapshot = "core_state=uninitialized\nturn_sequence_number=0\nprevious_turn_receipt=null\noutstanding_host_request=null\noutput_bytes=0\npending_command_preserved=true\n";
    try writer.write("artifacts/states/capacity-exhaustion.after.txt", state_snapshot);
    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: capacity-exhaustion\n" ++
            "owner_surface: Appliance/Core\n" ++
            "turn_closure_produced: false\n" ++
            "error: {s}\n" ++
            "state_unchanged: true\n" ++
            "turn_sequence_number: 0\n" ++
            "output_bytes: 0\n" ++
            "pending_command_preserved: true\n",
        .{@errorName(observed_error.?)},
    );
    try writer.write("cases/capacity-exhaustion.txt", case_transcript);
}

const NativeSemanticSnapshot = struct {
    state: world.Appliance.CoreState,
    sequence: u64,
    previous_receipt: ?u64,
    pending_command_present: bool,
    pending_archive_append_batch_fingerprint: ?u64,
    pending_archive_resulting_cursor_fingerprint: ?u64,
    latest_archive_cursor_fingerprint: u64,
    latest_archive_moment_fingerprint: ?u64,
    latest_archive_seal_fingerprint: ?u64,
    latest_chronicle_cursor_fingerprint: ?u64,
    last_output_status: ?world.Appliance.TurnStatus,
    last_turn_status: ?world.Appliance.TurnStatus,
    outstanding_request_bytes: []const u8,
    output_bytes: []const u8,
    closure_bytes: []const u8,
};

fn captureNativeSemanticSnapshot(allocator: std.mem.Allocator, native: *world.Appliance.Native) !NativeSemanticSnapshot {
    var requests: std.ArrayList(u8) = .empty;
    for (effectiveOutstandingHostRequests(&native.core)) |request| {
        var encoded: std.ArrayList(u8) = .empty;
        try request.encode(&encoded, allocator);
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(encoded.items.len), .little);
        try requests.appendSlice(allocator, &length_bytes);
        try requests.appendSlice(allocator, encoded.items);
    }
    return .{
        .state = native.core.state,
        .sequence = native.core.current_turn_sequence_number,
        .previous_receipt = native.core.previous_turn_receipt_fingerprint,
        .pending_command_present = native.core.pending_command != null,
        .pending_archive_append_batch_fingerprint = native.core.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor_fingerprint = if (native.core.pending_archive_resulting_cursor) |cursor| cursor.cursor_fingerprint else null,
        .latest_archive_cursor_fingerprint = native.core.latest_archive_cursor.cursor_fingerprint,
        .latest_archive_moment_fingerprint = native.core.latest_archive_moment_fingerprint,
        .latest_archive_seal_fingerprint = native.core.latest_archive_seal_fingerprint,
        .latest_chronicle_cursor_fingerprint = native.core.latest_chronicle_cursor_fingerprint,
        .last_output_status = native.core.last_output_status,
        .last_turn_status = native.core.last_turn_status,
        .outstanding_request_bytes = try requests.toOwnedSlice(allocator),
        .output_bytes = try allocator.dupe(u8, native.core.readOutput()),
        .closure_bytes = try allocator.dupe(u8, native.last_closure_bytes),
    };
}

fn effectiveOutstandingHostRequests(core: *const world.Appliance.Core) []const world.Appliance.HostRequest {
    if (core.outstanding_host_requests.len != 0) return core.outstanding_host_requests;
    if (core.outstanding_host_request) |*request| return request[0..1];
    return &.{};
}

fn nativeSemanticSnapshotEqual(lhs: NativeSemanticSnapshot, rhs: NativeSemanticSnapshot) bool {
    return lhs.state == rhs.state and
        lhs.sequence == rhs.sequence and
        lhs.previous_receipt == rhs.previous_receipt and
        lhs.pending_command_present == rhs.pending_command_present and
        lhs.pending_archive_append_batch_fingerprint == rhs.pending_archive_append_batch_fingerprint and
        lhs.pending_archive_resulting_cursor_fingerprint == rhs.pending_archive_resulting_cursor_fingerprint and
        lhs.latest_archive_cursor_fingerprint == rhs.latest_archive_cursor_fingerprint and
        lhs.latest_archive_moment_fingerprint == rhs.latest_archive_moment_fingerprint and
        lhs.latest_archive_seal_fingerprint == rhs.latest_archive_seal_fingerprint and
        lhs.latest_chronicle_cursor_fingerprint == rhs.latest_chronicle_cursor_fingerprint and
        lhs.last_output_status == rhs.last_output_status and
        lhs.last_turn_status == rhs.last_turn_status and
        std.mem.eql(u8, lhs.outstanding_request_bytes, rhs.outstanding_request_bytes) and
        std.mem.eql(u8, lhs.output_bytes, rhs.output_bytes) and
        std.mem.eql(u8, lhs.closure_bytes, rhs.closure_bytes);
}

test "effective outstanding requests include the legacy singular fallback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const executable_image_fingerprint: u64 = 0xA10C_0000_0000_1001;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    var native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer native.deinit();

    const request = native.core.outstanding_host_requests[0];
    native.core.outstanding_host_requests = &.{};
    native.core.outstanding_host_requests_owned = false;
    native.core.outstanding_host_request = request;

    const effective = effectiveOutstandingHostRequests(&native.core);
    try std.testing.expectEqual(@as(usize, 1), effective.len);
    try std.testing.expectEqual(request.request_fingerprint, effective[0].request_fingerprint);
}

fn replaceUniqueU64LittleEndian(bytes: []u8, from: u64, to: u64) !void {
    var from_bytes = [_]u8{0} ** 8;
    var to_bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &from_bytes, from, .little);
    std.mem.writeInt(u64, &to_bytes, to, .little);
    var found: ?usize = null;
    var cursor: usize = 0;
    while (cursor + from_bytes.len <= bytes.len) : (cursor += 1) {
        if (!std.mem.eql(u8, bytes[cursor .. cursor + from_bytes.len], &from_bytes)) continue;
        if (found != null) return error.NonUniqueMutationTarget;
        found = cursor;
    }
    const offset = found orelse return error.MutationTargetMissing;
    @memcpy(bytes[offset .. offset + to_bytes.len], &to_bytes);
}

fn emitMalformed(allocator: std.mem.Allocator, writer: *Writer) !void {
    var image = try buildLoadedProviderImage(allocator);
    defer image.deinit(allocator);
    const image_bytes = try image.encode(allocator);
    const malformed_image = try allocator.alloc(u8, image_bytes.len + 1);
    @memcpy(malformed_image[0..image_bytes.len], image_bytes);
    malformed_image[malformed_image.len - 1] = 0;
    try writer.write("artifacts/malformed/executable-image.trailing-byte", malformed_image);
    var image_error: ?anyerror = null;
    var decoded_image: ?world.Executable.Image = world.Executable.Image.decode(allocator, malformed_image, .{
        .max_image_bytes = malformed_image.len,
    }) catch |err| blk: {
        image_error = err;
        break :blk null;
    };
    if (decoded_image) |*decoded| decoded.deinit(allocator);
    if (image_error == null) return error.MalformedImageAccepted;

    const executable_image_fingerprint: u64 = 0xA10C_0000_0000_0001;
    const manifest = common.PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    var parent = try makeRetryParent(allocator, manifest, capacity, executable_image_fingerprint);
    defer parent.closure.deinit(allocator);
    const malformed_state = try allocator.alloc(u8, parent.closure_bytes.len + 1);
    @memcpy(malformed_state[0..parent.closure_bytes.len], parent.closure_bytes);
    malformed_state[malformed_state.len - 1] = 0;
    try writer.write("artifacts/malformed/state.turn-closure.trailing-byte", malformed_state);
    var state_error: ?anyerror = null;
    var decoded_state: ?world.Appliance.TurnClosure = world.Appliance.TurnClosure.decode(allocator, malformed_state) catch |err| blk: {
        state_error = err;
        break :blk null;
    };
    if (decoded_state) |*decoded| decoded.deinit(allocator);
    if (state_error == null) return error.MalformedStateAccepted;

    var native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer native.deinit();
    const request = native.core.outstanding_host_requests[0];
    const response_bytes = try common.responseValueImageBytes(allocator, request, 0xA10C_0002);
    var wrong_target = request.request_fingerprint ^ 0xFFFF;
    if (wrong_target == 0) wrong_target = 1;
    const wrong_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = wrong_target,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.wrong-target",
        .attempt_number = 1,
    });
    const wrong_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number + 1,
        .resolutions = &.{wrong_result},
    });
    const wrong_input_bytes = try wrong_input.encode(allocator);
    try writer.write("artifacts/malformed/result.wrong-target.turn-input", wrong_input_bytes);
    const before_wrong = try captureNativeSemanticSnapshot(allocator, &native);
    const wrong_status = native.submitTurn(wrong_input_bytes);
    if (wrong_status == .completed or wrong_status == .needs_host or wrong_status == .failed) return error.MalformedResultAccepted;
    const after_wrong = try captureNativeSemanticSnapshot(allocator, &native);
    if (!nativeSemanticSnapshotEqual(before_wrong, after_wrong)) return error.PartialSemanticMutation;

    const valid_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.valid-result",
        .attempt_number = 1,
    });
    var fake_target = request.request_fingerprint ^ 0xA10C_A10C_A10C_A10C;
    if (fake_target == 0 or fake_target == request.request_fingerprint) fake_target = request.request_fingerprint +% 1;
    const fake_result = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = fake_target,
        .status = .responded,
        .response_value_image_bytes = response_bytes,
        .host_claim_bytes = "world-image-v1-oracle.fake-second-result",
        .attempt_number = 1,
    });
    const distinct_results = [_]world.Appliance.Wire.ResolutionInput{ valid_result, fake_result };
    const distinct_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number + 1,
        .resolutions = &distinct_results,
    });
    const distinct_input_bytes = try distinct_input.encode(allocator);
    const duplicate_input_bytes = try allocator.dupe(u8, distinct_input_bytes);
    try replaceUniqueU64LittleEndian(duplicate_input_bytes, fake_target, request.request_fingerprint);
    try writer.write("artifacts/malformed/result.duplicate-target.turn-input", duplicate_input_bytes);
    var duplicate_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer duplicate_native.deinit();
    const before_duplicate = try captureNativeSemanticSnapshot(allocator, &duplicate_native);
    const duplicate_status = duplicate_native.submitTurn(duplicate_input_bytes);
    if (duplicate_status == .completed or duplicate_status == .needs_host or duplicate_status == .failed) return error.DuplicateResultAccepted;
    const after_duplicate = try captureNativeSemanticSnapshot(allocator, &duplicate_native);
    if (!nativeSemanticSnapshotEqual(before_duplicate, after_duplicate)) return error.PartialSemanticMutation;

    const duplicate_preflight_results = [_]world.Appliance.Wire.ResolutionInput{ valid_result, valid_result };
    const duplicate_preflight_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .previous_turn_receipt_fingerprint = parent.closure.turn_receipt_fingerprint,
        .turn_sequence_number = parent.closure.turn_sequence_number + 1,
        .resolutions = &duplicate_preflight_results,
    });
    var duplicate_preflight_error: ?anyerror = null;
    _ = duplicate_preflight_input.encode(allocator) catch |err| {
        duplicate_preflight_error = err;
    };
    if (duplicate_preflight_error == null) return error.DuplicateResultAccepted;

    var stale_native = try nativeFromClosure(allocator, manifest, capacity, executable_image_fingerprint, parent.closure_bytes);
    defer stale_native.deinit();
    const stale_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .expected_parent_closure_fingerprint = parent.closure.closure_fingerprint,
        .expected_parent_state_fingerprint = parent.closure.resulting_state_fingerprint,
        .previous_turn_receipt_fingerprint = stale_native.core.previous_turn_receipt_fingerprint,
        .turn_sequence_number = stale_native.core.current_turn_sequence_number + 1,
        .resolutions = &.{valid_result},
    });
    const stale_input_bytes = try stale_input.encode(allocator);
    try writer.write("artifacts/malformed/result.stale-replay.turn-input", stale_input_bytes);
    if (stale_native.submitTurn(stale_input_bytes) != .completed) return error.ExpectedCompleted;
    const before_stale = try captureNativeSemanticSnapshot(allocator, &stale_native);
    const stale_status = stale_native.submitTurn(stale_input_bytes);
    if (stale_status == .completed or stale_status == .needs_host or stale_status == .failed) return error.StaleResultAccepted;
    const after_stale = try captureNativeSemanticSnapshot(allocator, &stale_native);
    if (!nativeSemanticSnapshotEqual(before_stale, after_stale)) return error.PartialSemanticMutation;

    const case_transcript = try std.fmt.allocPrint(
        allocator,
        "case_id: malformed-records\n" ++
            "owner_surface: Executable.Image + Appliance/TurnClosure + Appliance/Wire\n" ++
            "malformed_image_error: {s}\n" ++
            "malformed_state_error: {s}\n" ++
            "wrong_target_result_status: {s}\n" ++
            "duplicate_result_status: {s}\n" ++
            "duplicate_preflight_error: {s}\n" ++
            "stale_result_status: {s}\n" ++
            "state_unchanged_after_wrong_result: true\n" ++
            "state_unchanged_after_duplicate_result: true\n" ++
            "state_unchanged_after_stale_result: true\n" ++
            "partial_transition_published: false\n",
        .{
            @errorName(image_error.?),
            @errorName(state_error.?),
            @tagName(wrong_status),
            @tagName(duplicate_status),
            @errorName(duplicate_preflight_error.?),
            @tagName(stale_status),
        },
    );
    try writer.write("cases/malformed-records.txt", case_transcript);
}

fn pathLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn mutablePathLessThan(_: void, lhs: []u8, rhs: []u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn listFiles(io: std.Io, allocator: std.mem.Allocator, root: std.Io.Dir) !OwnedPaths {
    var walker = try root.walk(allocator);
    defer walker.deinit();
    var items: std.ArrayList([]u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                const portable_path = try allocator.dupe(u8, entry.path);
                errdefer allocator.free(portable_path);
                canonicalizePathSeparators(portable_path, std.fs.path.sep);
                try items.append(allocator, portable_path);
            },
            .directory => {},
            .block_device,
            .character_device,
            .named_pipe,
            .sym_link,
            .unix_domain_socket,
            .whiteout,
            .door,
            .event_port,
            .unknown,
            => return error.UnsupportedOracleTreeEntry,
        }
    }
    const owned = try items.toOwnedSlice(allocator);
    std.mem.sort([]u8, owned, {}, mutablePathLessThan);
    return .{ .allocator = allocator, .items = owned };
}

fn isExpectedPath(writer: *const Writer, relative_path: []const u8) bool {
    for (writer.paths.items) |expected| {
        if (std.mem.eql(u8, expected, relative_path)) return true;
    }
    return false;
}

fn validatePublicationDestination(io: std.Io, allocator: std.mem.Allocator, output_dir: std.Io.Dir) !void {
    var existing_paths = try listFiles(io, allocator, output_dir);
    defer existing_paths.deinit();
    for (existing_paths.items) |relative_path| {
        if (std.mem.endsWith(u8, relative_path, ".oracle-tmp")) {
            return error.UnsafePublicationTemporaryPath;
        }
    }
}

fn promoteFile(
    allocator: std.mem.Allocator,
    writer: *Writer,
    output_dir: std.Io.Dir,
    relative_path: []const u8,
) !void {
    const source_path = try std.fs.path.join(allocator, &.{ writer.root, relative_path });
    try std.Io.Dir.cwd().copyFile(
        source_path,
        output_dir,
        relative_path,
        writer.io,
        .{ .make_path = true, .replace = true },
    );
}

fn requirePublicationDirectory(dir: std.Io.Dir, io: std.Io) !std.Io.Dir {
    errdefer dir.close(io);
    if ((try dir.stat(io)).kind != .directory) return error.UnsafePublicationPath;
    return dir;
}

fn openPublicationChild(parent: std.Io.Dir, io: std.Io, name: []const u8) !std.Io.Dir {
    const options: std.Io.Dir.OpenOptions = .{
        .follow_symlinks = false,
        .iterate = true,
    };
    const child = parent.openDir(io, name, options) catch |open_error| switch (open_error) {
        error.FileNotFound => blk: {
            parent.createDir(io, name, .default_dir) catch |create_error| switch (create_error) {
                error.PathAlreadyExists => {},
                error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
                else => |err| return err,
            };
            break :blk parent.openDir(io, name, options) catch |retry_error| switch (retry_error) {
                error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
                else => |err| return err,
            };
        },
        error.NotDir, error.SymLinkLoop => return error.UnsafePublicationPath,
        else => |err| return err,
    };
    return requirePublicationDirectory(child, io);
}

fn openPublicationPathNoFollow(io: std.Io, output_dir: []const u8) !std.Io.Dir {
    var components = std.fs.path.componentIterator(output_dir);
    const initial = if (components.root()) |root|
        try std.Io.Dir.cwd().openDir(io, root, .{ .follow_symlinks = false, .iterate = true })
    else
        try std.Io.Dir.cwd().openDir(io, ".", .{ .follow_symlinks = false, .iterate = true });
    var current = try requirePublicationDirectory(initial, io);
    errdefer current.close(io);

    while (components.next()) |component| {
        if (std.mem.eql(u8, component.name, ".")) continue;
        if (std.mem.eql(u8, component.name, "..")) return error.UnsafePublicationPath;
        const child = try openPublicationChild(current, io, component.name);
        current.close(io);
        current = child;
    }
    return current;
}

fn openTrustedPublicationDirectory(io: std.Io, trusted_prefix: []const u8) !std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    const prefix_dir = try cwd.createDirPathOpen(io, trusted_prefix, .{
        .open_options = .{ .follow_symlinks = true, .iterate = true },
    });
    var current = try requirePublicationDirectory(prefix_dir, io);
    errdefer current.close(io);

    var components = std.fs.path.componentIterator(canonical_output_suffix);
    while (components.next()) |component| {
        const child = try openPublicationChild(current, io, component.name);
        current.close(io);
        current = child;
    }
    return current;
}

fn openPublicationDirectory(io: std.Io, target: PublicationTarget) !std.Io.Dir {
    return switch (target) {
        .isolated => |output_dir| openPublicationPathNoFollow(io, output_dir),
        .trusted_prefix => |prefix| openTrustedPublicationDirectory(io, prefix),
    };
}

fn promoteCorpus(allocator: std.mem.Allocator, writer: *Writer, target: PublicationTarget) !void {
    var publication_dir = try openPublicationDirectory(writer.io, target);
    defer publication_dir.close(writer.io);
    try validatePublicationDestination(writer.io, allocator, publication_dir);

    // The standard atomic-copy primitive owns collision-safe temporary files
    // beside each destination and replaces only after the full file is ready.
    for (writer.paths.items) |relative_path| {
        try promoteFile(allocator, writer, publication_dir, relative_path);
    }

    // Retire obsolete artifacts only after the complete new file set is present.
    // An interrupted cleanup can leave detectable extras, but cannot remove any
    // artifact required by the new manifest.
    var published_paths = try listFiles(writer.io, allocator, publication_dir);
    defer published_paths.deinit();
    for (published_paths.items) |relative_path| {
        if (isExpectedPath(writer, relative_path)) continue;
        try publication_dir.deleteFile(writer.io, relative_path);
    }
}

test "publication rejects unsafe temporary symlink before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const victim_path = try std.fs.path.join(allocator, &.{ root, "victim.txt" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";
    const destination_path = try std.fs.path.join(allocator, &.{ output_dir, relative_path });
    const temporary_path = try std.fmt.allocPrint(allocator, "{s}.oracle-tmp", .{destination_path});

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(temporary_path).?);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_path, temporary_path, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsupportedOracleTreeEntry,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
    try std.testing.expectError(error.FileNotFound, cwd.access(io, destination_path, .{}));
}

test "publication rejects symlinked output root before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const output_dir = try std.fs.path.join(allocator, &.{ root, "output" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, output_dir, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
}

test "publication rejects symlinked output ancestor before writing" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const linked_ancestor = try std.fs.path.join(allocator, &.{ root, "linked" });
    const output_dir = try std.fs.path.join(allocator, &.{ linked_ancestor, "output" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, linked_ancestor, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .isolated = output_dir }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
    const redirected_output = try std.fs.path.join(allocator, &.{ victim_dir, "output" });
    try std.testing.expectError(error.FileNotFound, cwd.access(io, redirected_output, .{}));
}

test "publication accepts a symlinked trusted prefix" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const real_prefix = try std.fs.path.join(allocator, &.{ root, "real-prefix" });
    const linked_prefix = try std.fs.path.join(allocator, &.{ root, "linked-prefix" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";
    const destination_path = try std.fs.path.join(allocator, &.{ real_prefix, canonical_output_suffix, relative_path });

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, real_prefix);
    try cwd.symLink(io, real_prefix, linked_prefix, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try promoteCorpus(allocator, &writer, .{ .trusted_prefix = linked_prefix });

    const destination_bytes = try cwd.readFileAlloc(io, destination_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("replacement", destination_bytes);
}

test "trusted prefix rejects a symlinked oracle suffix" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const staging_dir = try std.fs.path.join(allocator, &.{ root, "staging" });
    const trusted_prefix = try std.fs.path.join(allocator, &.{ root, "prefix" });
    const victim_dir = try std.fs.path.join(allocator, &.{ root, "victim" });
    const victim_path = try std.fs.path.join(allocator, &.{ victim_dir, "sentinel.txt" });
    const linked_suffix = try std.fs.path.join(allocator, &.{ trusted_prefix, "conformance" });
    const relative_path = "artifacts/manifests/one-port.appliance-manifest";

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, trusted_prefix);
    try cwd.createDirPath(io, victim_dir);
    try cwd.writeFile(io, .{ .sub_path = victim_path, .data = "must survive\n" });
    try cwd.symLink(io, victim_dir, linked_suffix, .{});

    var writer = Writer{ .io = io, .allocator = allocator, .root = staging_dir };
    try writer.write(relative_path, "replacement");
    try std.testing.expectError(
        error.UnsafePublicationPath,
        promoteCorpus(allocator, &writer, .{ .trusted_prefix = trusted_prefix }),
    );

    const victim_bytes = try cwd.readFileAlloc(io, victim_path, allocator, .limited(1024));
    try std.testing.expectEqualStrings("must survive\n", victim_bytes);
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest = [_]u8{0} ** 32;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

fn digestHex(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

fn readArtifact(allocator: std.mem.Allocator, writer: *Writer, relative_path: []const u8) ![]u8 {
    const full_path = try std.fs.path.join(allocator, &.{ writer.root, relative_path });
    return std.Io.Dir.cwd().readFileAlloc(writer.io, full_path, allocator, .limited(16 * 1024 * 1024));
}

fn writeManifest(allocator: std.mem.Allocator, writer: *Writer) !void {
    std.mem.sort([]const u8, writer.paths.items, {}, pathLessThan);
    var artifact_set_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (writer.paths.items) |relative_path| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const digest = sha256(bytes);
        var length_bytes = [_]u8{0} ** 8;
        std.mem.writeInt(u64, &length_bytes, @intCast(bytes.len), .little);
        artifact_set_hasher.update(relative_path);
        artifact_set_hasher.update(&.{0});
        artifact_set_hasher.update(&length_bytes);
        artifact_set_hasher.update(&digest);
    }
    var artifact_set_digest = [_]u8{0} ** 32;
    artifact_set_hasher.final(&artifact_set_digest);
    const artifact_set_hex = digestHex(artifact_set_digest);

    var manifest: std.ArrayList(u8) = .empty;
    try manifest.appendSlice(
        allocator,
        "{\n" ++
            "  \"format\": \"world-image-v1-rewrite-world-oracle-v0\",\n" ++
            "  \"format_version\": 1,\n" ++
            "  \"semantic_source\": {\n" ++
            "    \"package\": \"world\",\n" ++
            "    \"package_version\": \"0.1.0\",\n" ++
            "    \"baseline_commit\": \"969f23f6bad87ca9d535d92d62b6418612891699\",\n" ++
            "    \"baseline_tree\": \"b2bd776125bc17215916e2a48bc7102a861788db\",\n" ++
            "    \"boundary_package\": \"0.6.2\",\n" ++
            "    \"boundary_package_hash\": \"boundary-0.6.2-flclaA4FhQCQL_ODFaXPP7HtNOn21toNs6rc14-cQqYJ\",\n" ++
            "    \"world_executable_image_format\": 2,\n" ++
            "    \"world_turn_closure_format\": 1,\n" ++
            "    \"world_archive_format\": 1,\n" ++
            "    \"world_appliance_abi\": 4,\n" ++
            "    \"world_appliance_command_format\": 1,\n" ++
            "    \"world_appliance_wire_turn_input_format\": 2,\n" ++
            "    \"world_appliance_wire_resolution_input_format\": 1,\n" ++
            "    \"zig_version\": \"0.16.0\"\n" ++
            "  },\n" ++
            "  \"offline_regeneration\": \"requires-preseeded-boundary-package-cache\",\n" ++
            "  \"generator\": \"zig build update-world-image-v1-transition-oracle\",\n" ++
            "  \"normal_check\": \"zig build check-world-image-v1-transition-oracle --summary all\",\n" ++
            "  \"case_count\": 12,\n" ++
            "  \"cases\": [\n",
    );
    for (cases, 0..) |case, index| {
        try manifest.print(allocator, "    {{\"id\":\"{s}\",\"transcript\":\"{s}\"}}{s}\n", .{
            case.id,
            case.transcript,
            if (index + 1 == cases.len) "" else ",",
        });
    }
    try manifest.print(
        allocator,
        "  ],\n" ++
            "  \"artifact_set_sha256\": \"{s}\",\n" ++
            "  \"artifact_count\": {d},\n" ++
            "  \"artifacts\": [\n",
        .{ &artifact_set_hex, writer.paths.items.len },
    );
    for (writer.paths.items, 0..) |relative_path, index| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const hex = digestHex(sha256(bytes));
        try manifest.print(allocator, "    {{\"path\":\"{s}\",\"length\":{d},\"sha256\":\"{s}\"}}{s}\n", .{
            relative_path,
            bytes.len,
            &hex,
            if (index + 1 == writer.paths.items.len) "" else ",",
        });
    }
    try manifest.appendSlice(allocator, "  ]\n}\n");
    try writer.write("manifest.json", manifest.items);
}

fn writeChecksums(allocator: std.mem.Allocator, writer: *Writer) !void {
    std.mem.sort([]const u8, writer.paths.items, {}, pathLessThan);
    var checksums: std.ArrayList(u8) = .empty;
    for (writer.paths.items) |relative_path| {
        const bytes = try readArtifact(allocator, writer, relative_path);
        const hex = digestHex(sha256(bytes));
        try checksums.print(allocator, "{s}  {s}{s}\n", .{ &hex, checksum_prefix, relative_path });
    }
    try writer.write("checksums.sha256", checksums.items);
}
