const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");
const boundary_agent_runtime = @import("boundary_agent_runtime");
const universal = @import("world_universal_appliance_wasm.zig");

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    if (args.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "--agent-runtime")) {
            const out_dir = args.next() orelse return error.InvalidArguments;
            if (args.next() != null) return error.InvalidArguments;
            try exportAgentRuntimeArtifacts(init.io, allocator, out_dir);
            return;
        }
        if (std.mem.eql(u8, first_arg, "--check-agent-runtime")) {
            const out_dir = args.next() orelse return error.InvalidArguments;
            if (args.next() != null) return error.InvalidArguments;
            try checkAgentRuntimeArtifacts(init.io, allocator, out_dir);
            return;
        }
        if (std.mem.eql(u8, first_arg, "--reply")) {
            const output_path = args.next() orelse return error.InvalidArguments;
            const command_path = args.next() orelse return error.InvalidArguments;
            const metadata = args.next() orelse return error.InvalidArguments;
            if (args.next() != null) return error.InvalidArguments;
            const output_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, output_path, allocator, .limited(1024 * 1024));
            var output = try world.Appliance.TurnOutput.decodeArchivePayload(allocator, output_bytes);
            defer output.deinit(allocator);
            if (output.status != .needs_host or output.host_requests.len != 1) return error.InvalidFrameEncoding;
            const command = try replyCommandBytesForOutput(allocator, output, metadata);
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_path, .data = command });
            return;
        }
        args = std.process.Args.Iterator.init(init.minimal.args);
        _ = args.next();
    }
    const image_a_path = args.next() orelse return error.InvalidArguments;
    const command_a_path = args.next() orelse return error.InvalidArguments;
    const image_b_path = args.next() orelse return error.InvalidArguments;
    const command_b_path = args.next() orelse return error.InvalidArguments;
    const proof_path = args.next() orelse return error.InvalidArguments;
    if (args.next() != null) return error.InvalidArguments;

    const image_a = try buildExecutableImage(allocator, "universal.fixture.a", "universal.fixture.a");
    const image_a_bytes = try image_a.encode(allocator);
    const manifest_a_fingerprint = try manifestFingerprintForImage(allocator, image_a);
    const command_a = try bootCommandBytes(allocator, manifest_a_fingerprint, "universal.fixture.a");

    const image_b = try buildLoadedProviderImage(allocator);
    const image_b_bytes = try image_b.encode(allocator);
    const manifest_b_fingerprint = try manifestFingerprintForImage(allocator, image_b);
    const command_b = try bootCommandBytes(allocator, manifest_b_fingerprint, "universal.fixture.b.loaded-provider");
    const proof = try twoProgramProofBytes(allocator, image_a, manifest_a_fingerprint, image_b, manifest_b_fingerprint);

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = image_a_path, .data = image_a_bytes });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_a_path, .data = command_a });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = image_b_path, .data = image_b_bytes });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = command_b_path, .data = command_b });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = proof_path, .data = proof });
}

fn buildExecutableImage(allocator: std.mem.Allocator, image_metadata: []const u8, binding_label: []const u8) !world.Executable.Image {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .metadata = image_metadata,
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);

    const root_module = builder.modules.items[0];
    const root_import = root_module.imports[0];
    const actuator_ref = world.Actuation.Ref.init(.{
        .kind = .fixture,
        .class = .deterministic_fixture,
        .label = binding_label,
        .supported_modes = .all,
        .supported_response_statuses = .all,
        .value_policy_fingerprint = world.Actuation.valuePolicyFingerprint(.portable),
    });
    const descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = actuator_ref,
        .world_surface_fingerprint = root_module.target_ref.world_surface_fingerprint,
        .target_ref_fingerprint = root_module.target_ref.target_ref_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = root_import.source_effect_shape_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .response_value_table_id = root_import.response_value_table_id,
        .label = binding_label,
    });
    try builder.addExternalBinding(world.Executable.ExternalBinding.init(.{
        .parent_module_fingerprint = root_module.module_ref.boundary_module_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .payload_value_ref_fingerprint = root_import.payload_value_ref_fingerprint,
        .response_value_table_id = root_import.response_value_table_id,
        .response_value_ref_fingerprint = root_import.response_value_ref_fingerprint,
        .actuator_ref = actuator_ref,
        .descriptor = descriptor,
        .label = binding_label,
    }));

    var prepared = try builder.prepare();
    defer prepared.deinit();
    return try prepared.seal();
}

fn buildAgentRuntimeImage(allocator: std.mem.Allocator) !world.Executable.Image {
    const root_bytes = try boundary_agent_runtime.RootTarget.Module.fullImage(allocator);
    defer allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .metadata = "agent-runtime-v0.1.world-agent",
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);

    const root_module = builder.modules.items[0];
    for (root_module.imports) |root_import| {
        const is_tool_port = root_import.world_port_id == world.ImportRequirement.fromTargetPort(boundary_agent_runtime.RootTarget, 1).world_port_id;
        const actuator_ref = if (is_tool_port)
            world.Actuation.Ref.init(.{
                .kind = .tool_like,
                .class = .idempotent_mutation,
                .label = "sandbox:file",
                .supported_modes = .all,
                .supported_response_statuses = .all,
                .value_policy_fingerprint = world.Actuation.valuePolicyFingerprint(.portable),
            })
        else
            world.Actuation.Ref.init(.{
                .kind = .model_like,
                .class = .deterministic_fixture,
                .label = "fixture:agent-model",
                .supported_modes = .all,
                .supported_response_statuses = .all,
                .value_policy_fingerprint = world.Actuation.valuePolicyFingerprint(.portable),
            });
        const binding_label = if (is_tool_port) "agent-runtime.tool" else "agent-runtime.model";
        const descriptor = world.Actuation.Descriptor.init(.{
            .actuator_ref = actuator_ref,
            .world_surface_fingerprint = root_module.target_ref.world_surface_fingerprint,
            .target_ref_fingerprint = root_module.target_ref.target_ref_fingerprint,
            .world_port_id = root_import.world_port_id,
            .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
            .source_effect_shape_ref_fingerprint = root_import.source_effect_shape_ref_fingerprint,
            .payload_value_table_id = root_import.payload_value_table_id,
            .response_value_table_id = root_import.response_value_table_id,
            .label = binding_label,
        });
        try builder.addExternalBinding(world.Executable.ExternalBinding.init(.{
            .parent_module_fingerprint = root_module.module_ref.boundary_module_fingerprint,
            .world_port_id = root_import.world_port_id,
            .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
            .payload_value_table_id = root_import.payload_value_table_id,
            .payload_value_ref_fingerprint = root_import.payload_value_ref_fingerprint,
            .response_value_table_id = root_import.response_value_table_id,
            .response_value_ref_fingerprint = root_import.response_value_ref_fingerprint,
            .actuator_ref = actuator_ref,
            .descriptor = descriptor,
            .label = binding_label,
        }));
    }

    var prepared = try builder.prepare();
    defer prepared.deinit();
    return try prepared.seal();
}

fn buildLoadedProviderImage(allocator: std.mem.Allocator) !world.Executable.Image {
    const root_bytes = try fixtures.ProviderPorts.Target.Module.fullImage(allocator);
    defer allocator.free(root_bytes);
    const provider_bytes = try fixtures.Strict.Target.Module.fullImage(allocator);
    defer allocator.free(provider_bytes);

    var builder = world.Executable.Builder.init(allocator, .{
        .runtime_profile = universal.executable_runtime_profile,
        .linker_policy = .strict_closed,
        .metadata = "universal.fixture.b.loaded-provider",
    });
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    try builder.addProviderModule(provider_bytes);
    var prepared = try builder.prepare();
    defer prepared.deinit();
    return try prepared.seal();
}

fn twoProgramProofBytes(
    allocator: std.mem.Allocator,
    image_a: world.Executable.Image,
    manifest_a_fingerprint: u64,
    image_b: world.Executable.Image,
    manifest_b_fingerprint: u64,
) ![]const u8 {
    const root_a = image_a.module_set.root() orelse return error.InvalidFrameEncoding;
    const root_b = image_b.module_set.root() orelse return error.InvalidFrameEncoding;
    return std.fmt.allocPrint(
        allocator,
        "image_a_fingerprint={x}\n" ++
            "image_b_fingerprint={x}\n" ++
            "manifest_a_fingerprint={x}\n" ++
            "manifest_b_fingerprint={x}\n" ++
            "root_module_a_fingerprint={x}\n" ++
            "root_module_b_fingerprint={x}\n" ++
            "program_plan_a_hash={x}\n" ++
            "program_plan_b_hash={x}\n" ++
            "module_count_a={d}\n" ++
            "module_count_b={d}\n" ++
            "dispatch_a_fingerprint={x}\n" ++
            "dispatch_b_fingerprint={x}\n" ++
            "external_binding_count_a={d}\n" ++
            "external_binding_count_b={d}\n" ++
            "route_count_a={d}\n" ++
            "route_count_b={d}\n" ++
            "provider_module_count_b={d}\n",
        .{
            image_a.image_fingerprint,
            image_b.image_fingerprint,
            manifest_a_fingerprint,
            manifest_b_fingerprint,
            root_a.module_ref.boundary_module_fingerprint,
            root_b.module_ref.boundary_module_fingerprint,
            root_a.module_ref.residual_program_plan_hash orelse 0,
            root_b.module_ref.residual_program_plan_hash orelse 0,
            image_a.module_set.modules.len,
            image_b.module_set.modules.len,
            image_a.dispatch_image.dispatch_fingerprint,
            image_b.dispatch_image.dispatch_fingerprint,
            image_a.external_bindings.len,
            image_b.external_bindings.len,
            image_a.dispatch_image.route_ids.len,
            image_b.dispatch_image.route_ids.len,
            providerModuleCount(image_b),
        },
    );
}

fn providerModuleCount(image: world.Executable.Image) usize {
    var count: usize = 0;
    for (image.module_set.modules) |module| {
        if (module.role == .provider) count += 1;
    }
    return count;
}

fn manifestFingerprintForImage(allocator: std.mem.Allocator, image: world.Executable.Image) !u64 {
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();
    return core.readManifest().manifest_fingerprint;
}

fn exportAgentRuntimeArtifacts(io: std.Io, allocator: std.mem.Allocator, out_dir: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, out_dir);

    var image = try buildAgentRuntimeImage(allocator);
    defer image.deinit(allocator);
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();

    const image_bytes = try image.encode(allocator);
    const manifest = core.readManifest();
    const manifest_bytes = try manifest.encode(allocator);
    const metadata = try agentRuntimeMetadataJson(allocator, image, manifest);

    try writeJoined(io, allocator, out_dir, "agent.executable-image", image_bytes);
    try writeJoined(io, allocator, out_dir, "appliance-manifest.bin", manifest_bytes);
    try writeJoined(io, allocator, out_dir, "agent-runtime-world-artifacts.json", metadata);
    try writeAgentRuntimeChecksums(io, allocator, out_dir, &.{
        .{ .basename = "agent.executable-image", .data = image_bytes },
        .{ .basename = "appliance-manifest.bin", .data = manifest_bytes },
        .{ .basename = "agent-runtime-world-artifacts.json", .data = metadata },
    });
}

const AgentRuntimeMetadata = struct {
    world_package_version: []const u8,
    world_executable_image_format_version: u32,
    world_executable_image_fingerprint_version: u32,
    world_executable_image_fingerprint: []const u8,
    world_appliance_manifest_fingerprint: []const u8,
    world_appliance_abi_version: u32,
    world_turn_closure_format_version: u32,
    world_archive_format_version: u32,
    root_module_fingerprint: []const u8,
    dispatch_fingerprint: []const u8,
    required_actuator_refs: []const []const u8,
    required_descriptor_fingerprints: []const []const u8,
    required_actuator_ref_fingerprints: []const []const u8,
    required_world_port_ids: []const []const u8,
    metadata: []const u8,
};

fn checkAgentRuntimeArtifacts(io: std.Io, allocator: std.mem.Allocator, out_dir: []const u8) !void {
    const image_bytes = try readJoined(io, allocator, out_dir, "agent.executable-image", 16 * 1024 * 1024);
    const manifest_bytes = try readJoined(io, allocator, out_dir, "appliance-manifest.bin", 1024 * 1024);
    const metadata_bytes = try readJoined(io, allocator, out_dir, "agent-runtime-world-artifacts.json", 1024 * 1024);

    var image = try world.Executable.Image.decode(allocator, image_bytes, .{ .max_image_bytes = image_bytes.len });
    defer image.deinit(allocator);
    const compatibility = try image.validateWithAllocator(allocator, universal.executable_runtime_profile);
    if (!compatibility.compatible) return error.ExecutableLoadRejected;

    var expected_core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer expected_core.deinit();
    const expected_manifest = expected_core.readManifest();
    const expected_manifest_bytes = try expected_manifest.encode(allocator);
    if (!std.mem.eql(u8, manifest_bytes, expected_manifest_bytes)) return error.InvalidFrameEncoding;

    var manifest = try world.Appliance.Manifest.decode(allocator, manifest_bytes);
    defer manifest.deinit(allocator);
    const parsed = try std.json.parseFromSlice(AgentRuntimeMetadata, allocator, metadata_bytes, .{});
    defer parsed.deinit();
    const metadata = parsed.value;

    try expectStringEquals("v0.1.0", metadata.world_package_version);
    try expectStringEquals("world-owned agent runtime export", metadata.metadata);
    try expectEqualU32(world.world_executable_image_format_version, metadata.world_executable_image_format_version);
    try expectEqualU32(world.world_executable_image_fingerprint_version, metadata.world_executable_image_fingerprint_version);
    try expectEqualU32(world.world_appliance_abi_version, metadata.world_appliance_abi_version);
    try expectEqualU32(world.world_appliance_turn_closure_format_version, metadata.world_turn_closure_format_version);
    try expectEqualU32(world.Archive.world_archive_format_version, metadata.world_archive_format_version);
    try expectEqualU64(image.image_fingerprint, try parseHexU64(metadata.world_executable_image_fingerprint));
    try expectEqualU64(manifest.manifest_fingerprint, try parseHexU64(metadata.world_appliance_manifest_fingerprint));
    try expectEqualU64((image.module_set.root() orelse return error.InvalidFrameEncoding).module_ref.boundary_module_fingerprint, try parseHexU64(metadata.root_module_fingerprint));
    try expectEqualU64(image.dispatch_image.dispatch_fingerprint, try parseHexU64(metadata.dispatch_fingerprint));
    try expectActuatorRefLabels(metadata.required_actuator_refs, image.external_bindings, manifest.actuation_world_port_ids);
    try expectHexArrayEquals(manifest.actuation_descriptor_fingerprints, metadata.required_descriptor_fingerprints);
    try expectHexArrayEquals(manifest.actuation_actuator_ref_fingerprints, metadata.required_actuator_ref_fingerprints);
    try expectHexArrayEquals(manifest.actuation_world_port_ids, metadata.required_world_port_ids);
    try checkAgentRuntimeChecksums(io, allocator, out_dir, &.{
        .{ .basename = "agent.executable-image", .data = image_bytes },
        .{ .basename = "appliance-manifest.bin", .data = manifest_bytes },
        .{ .basename = "agent-runtime-world-artifacts.json", .data = metadata_bytes },
    });
}

fn agentRuntimeMetadataJson(
    allocator: std.mem.Allocator,
    image: world.Executable.Image,
    manifest: world.Appliance.Manifest,
) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.print(allocator,
        \\{{
        \\  "world_package_version": "v0.1.0",
        \\  "world_executable_image_format_version": {d},
        \\  "world_executable_image_fingerprint_version": {d},
        \\  "world_executable_image_fingerprint": "0x{x:0>16}",
        \\  "world_appliance_manifest_fingerprint": "0x{x:0>16}",
        \\  "world_appliance_abi_version": {d},
        \\  "world_turn_closure_format_version": {d},
        \\  "world_archive_format_version": {d},
        \\  "root_module_fingerprint": "0x{x:0>16}",
        \\  "dispatch_fingerprint": "0x{x:0>16}",
        \\  "required_actuator_refs":
    , .{
        world.world_executable_image_format_version,
        world.world_executable_image_fingerprint_version,
        image.image_fingerprint,
        manifest.manifest_fingerprint,
        world.world_appliance_abi_version,
        world.world_appliance_turn_closure_format_version,
        world.Archive.world_archive_format_version,
        (image.module_set.root() orelse return error.InvalidFrameEncoding).module_ref.boundary_module_fingerprint,
        image.dispatch_image.dispatch_fingerprint,
    });
    try writeActuatorRefLabelArrayForWorldPorts(allocator, &out, image.external_bindings, manifest.actuation_world_port_ids);
    try out.appendSlice(allocator, ",\n  \"required_descriptor_fingerprints\": ");
    try writeU64Array(allocator, &out, manifest.actuation_descriptor_fingerprints);
    try out.appendSlice(allocator, ",\n  \"required_actuator_ref_fingerprints\": ");
    try writeU64Array(allocator, &out, manifest.actuation_actuator_ref_fingerprints);
    try out.appendSlice(allocator, ",\n  \"required_world_port_ids\": ");
    try writeU64Array(allocator, &out, manifest.actuation_world_port_ids);
    try out.appendSlice(allocator, ",\n  \"metadata\": \"world-owned agent runtime export\"\n}\n");
    return try out.toOwnedSlice(allocator);
}

fn writeStringArray(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8) !void {
    try out.append(allocator, '[');
    for (values, 0..) |value, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "\"{s}\"", .{value});
    }
    try out.append(allocator, ']');
}

fn writeActuatorRefLabelArrayForWorldPorts(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bindings: []const world.Executable.ExternalBinding,
    world_port_ids: []const u64,
) !void {
    try out.append(allocator, '[');
    for (world_port_ids, 0..) |world_port_id, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "\"{s}\"", .{try actuatorLabelForWorldPortId(bindings, world_port_id)});
    }
    try out.append(allocator, ']');
}

fn writeU64Array(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const u64) !void {
    try out.append(allocator, '[');
    for (values, 0..) |value, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "\"0x{x:0>16}\"", .{value});
    }
    try out.append(allocator, ']');
}

fn writeJoined(io: std.Io, allocator: std.mem.Allocator, dir: []const u8, basename: []const u8, data: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ dir, basename });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

const AgentRuntimeChecksumEntry = struct {
    basename: []const u8,
    data: []const u8,
};

fn writeAgentRuntimeChecksums(
    io: std.Io,
    allocator: std.mem.Allocator,
    out_dir: []const u8,
    entries: []const AgentRuntimeChecksumEntry,
) !void {
    const dist_dir = std.fs.path.dirname(out_dir) orelse return error.InvalidArguments;
    const checksum_path = try std.fs.path.join(allocator, &.{ dist_dir, "checksums.txt" });
    const existing = std.Io.Dir.cwd().readFileAlloc(io, checksum_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };

    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, existing, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "  agent-runtime/") != null) continue;
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
    for (entries) |entry| {
        try appendChecksumLine(allocator, &out, entry);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = checksum_path, .data = out.items });
}

fn checkAgentRuntimeChecksums(
    io: std.Io,
    allocator: std.mem.Allocator,
    out_dir: []const u8,
    entries: []const AgentRuntimeChecksumEntry,
) !void {
    const dist_dir = std.fs.path.dirname(out_dir) orelse return error.InvalidArguments;
    const checksum_path = try std.fs.path.join(allocator, &.{ dist_dir, "checksums.txt" });
    const checksums = try std.Io.Dir.cwd().readFileAlloc(io, checksum_path, allocator, .limited(1024 * 1024));
    for (entries) |entry| {
        var expected: std.ArrayList(u8) = .empty;
        try appendChecksumLine(allocator, &expected, entry);
        if (std.mem.indexOf(u8, checksums, expected.items) == null) return error.InvalidFrameEncoding;
    }
}

fn appendChecksumLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), entry: AgentRuntimeChecksumEntry) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(entry.data, &digest, .{});
    for (digest) |byte| {
        try out.print(allocator, "{x:0>2}", .{byte});
    }
    try out.print(allocator, "  agent-runtime/{s}\n", .{entry.basename});
}

fn readJoined(io: std.Io, allocator: std.mem.Allocator, dir: []const u8, basename: []const u8, limit: usize) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ dir, basename });
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(limit));
}

fn expectStringEquals(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) return error.InvalidFrameEncoding;
}

fn expectEqualU32(expected: u32, actual: u32) !void {
    if (expected != actual) return error.InvalidFrameEncoding;
}

fn expectEqualU64(expected: u64, actual: u64) !void {
    if (expected != actual) return error.InvalidFrameEncoding;
}

fn expectHexArrayEquals(expected: []const u64, actual: []const []const u8) !void {
    if (expected.len != actual.len) return error.InvalidFrameEncoding;
    for (expected, actual) |expected_value, actual_value| {
        try expectEqualU64(expected_value, try parseHexU64(actual_value));
    }
}

fn expectActuatorRefLabels(expected: []const []const u8, bindings: []const world.Executable.ExternalBinding, world_port_ids: []const u64) !void {
    if (expected.len != world_port_ids.len) return error.InvalidFrameEncoding;
    for (expected, world_port_ids) |label, world_port_id| {
        if (!std.mem.eql(u8, label, try actuatorLabelForWorldPortId(bindings, world_port_id))) return error.InvalidFrameEncoding;
    }
}

fn actuatorLabelForWorldPortId(bindings: []const world.Executable.ExternalBinding, world_port_id: u64) ![]const u8 {
    if (world_port_id > std.math.maxInt(u32)) return error.InvalidFrameEncoding;
    const port_id: u32 = @intCast(world_port_id);
    var label: ?[]const u8 = null;
    for (bindings) |binding| {
        if (binding.world_port_id != port_id) continue;
        if (label != null) return error.InvalidFrameEncoding;
        label = binding.actuator_ref.label;
    }
    return label orelse error.InvalidFrameEncoding;
}

fn parseHexU64(value: []const u8) !u64 {
    if (value.len != 18 or value[0] != '0' or value[1] != 'x') return error.InvalidFrameEncoding;
    return std.fmt.parseInt(u64, value[2..], 16) catch error.InvalidFrameEncoding;
}

fn bootCommandBytes(allocator: std.mem.Allocator, manifest_fingerprint: u64, metadata: []const u8) ![]const u8 {
    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = metadata,
    });
    return command.encode(allocator);
}

fn replyCommandBytesForBoot(
    allocator: std.mem.Allocator,
    image: world.Executable.Image,
    boot_command_bytes: []const u8,
    metadata: []const u8,
) ![]const u8 {
    var core = try world.Appliance.Core.initExecutable(allocator, image, .{
        .profile = .wasm_small,
        .capacity = universal.abi_capacity,
        .supported_runtime_profile = universal.executable_runtime_profile,
        .metadata = "world-universal-appliance",
    });
    defer core.deinit();

    try core.submit(boot_command_bytes);
    try core.executeTurn();
    const output_bytes = core.readOutput();
    var output = try world.Appliance.TurnOutput.decode(
        allocator,
        output_bytes,
        core.readManifest().manifest_fingerprint,
        universal.abi_capacity,
    );
    defer output.deinit(allocator);
    if (output.status != .needs_host or output.host_requests.len != 1) return error.InvalidFrameEncoding;

    const reply = try hostReplyFor(allocator, output.host_requests[0], 0x600D_0001);
    defer if (reply.outcome.response_bytes.len != 0) allocator.free(reply.outcome.response_bytes);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
        .metadata = metadata,
    });
    return command.encode(allocator);
}

fn replyCommandBytesForOutput(
    allocator: std.mem.Allocator,
    output: world.Appliance.TurnOutput,
    metadata: []const u8,
) ![]const u8 {
    const reply = try hostReplyFor(allocator, output.host_requests[0], 0x600D_0001);
    defer if (reply.outcome.response_bytes.len != 0) allocator.free(reply.outcome.response_bytes);
    try reply.validateWithAllocator(allocator, output.host_requests, universal.abi_capacity);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = output.turn_receipt.receipt_fingerprint,
        .host_replies = &.{reply},
        .metadata = metadata,
    });
    try command.validateWithAllocator(allocator, output.manifest_fingerprint, universal.abi_capacity);
    return command.encode(allocator);
}

fn hostReplyFor(
    allocator: std.mem.Allocator,
    request: world.Appliance.HostRequest,
    response_fingerprint: u64,
) !world.Appliance.HostReply {
    var response_bytes: []const u8 = "";
    var response_value_fingerprint = response_fingerprint;
    if (request.expected_response_value_ref_fingerprint != null or request.expected_response_schema_ref_fingerprint != null) {
        var image = try world.Frame.ValueImage.fromCanonicalBytes(
            allocator,
            null,
            request.expected_response_value_ref_fingerprint,
            request.expected_response_schema_ref_fingerprint,
            std.mem.asBytes(&response_fingerprint),
            false,
        );
        defer image.deinit(allocator);
        response_bytes = try image.encode(allocator);
        response_value_fingerprint = image.value_image_fingerprint;
    }
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_value_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = response_bytes,
        .host_evidence_fingerprint = request.request_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:fixture",
        .attempt_number = 1,
        .metadata = "fixture-response",
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
        .metadata = "fixture-reply",
    });
}
