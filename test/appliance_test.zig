const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");

const AppliancePortsCtx = struct {};

fn applianceApprove(_: *AppliancePortsCtx, _: []const u8) !i32 {
    return 1;
}

fn applianceDecide(_: *AppliancePortsCtx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "final=actuate skeleton complete" };
}

fn applianceTool(_: *AppliancePortsCtx, _: []const u8) ![]const u8 {
    return "tool";
}

const AppliancePortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, applianceApprove);
const ApplianceAgentDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, applianceDecide);
const ApplianceAgentToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, applianceTool);
const ApplianceActuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "appliance.model",
    .supported_response_statuses = world.Actuation.ResponseStatusSet.all,
    .value_policy = world.ValuePolicy.portable,
});
const ApplianceActuationBinding = world.bindActuator(AppliancePortsDecl, ApplianceActuator);
const ApplianceAgentActuationBinding = world.bindActuator(ApplianceAgentDecideDecl, ApplianceActuator);
const ApplianceAgentToolActuationBinding = world.bindActuator(ApplianceAgentToolDecl, ApplianceActuator);
const ApplianceAgentToolImport = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 1);

fn applianceSyntheticHostRequestArgs(comptime T: type, args: T) struct {
    turn_sequence_number: u64,
    request_ordinal: u32,
    run_handle_fingerprint: u64,
    pending_port_fingerprint: u64,
    world_port_id: u32 = 0,
    target_ref_fingerprint: u64 = 0xD0F0_0001,
    world_surface_fingerprint: u64 = 0xD0F0_0002,
    actuator_ref_fingerprint: u64 = 0xD0F0_0003,
    actuation_class: world.Actuation.Class = .deterministic_fixture,
    allowed_response_statuses: world.Actuation.ResponseStatusSet = .terminal_with_errors,
    intent_fingerprint: u64,
    envelope_fingerprint: u64,
    decision_fingerprint: u64,
    expected_response_descriptor_fingerprint: u64,
    idempotency_key_fingerprint: u64,
    supervision_ref_fingerprint: ?u64 = null,
    metadata: []const u8 = "",
    frame_request_bytes: []const u8 = "",
    payload_value_image_bytes: []const u8 = "",
    prepared_actuation_evidence_bytes: []const u8 = "",
    idempotency_key_bytes: []const u8 = "",
    expected_response_value_ref_fingerprint: ?u64 = null,
    expected_response_schema_ref_fingerprint: ?u64 = null,
} {
    return .{
        .turn_sequence_number = args.turn_sequence_number,
        .request_ordinal = args.request_ordinal,
        .run_handle_fingerprint = args.run_handle_fingerprint,
        .pending_port_fingerprint = args.pending_port_fingerprint,
        .world_port_id = if (@hasField(T, "world_port_id")) args.world_port_id else 0,
        .target_ref_fingerprint = if (@hasField(T, "target_ref_fingerprint")) args.target_ref_fingerprint else 0xD0F0_0001,
        .world_surface_fingerprint = if (@hasField(T, "world_surface_fingerprint")) args.world_surface_fingerprint else 0xD0F0_0002,
        .actuator_ref_fingerprint = if (@hasField(T, "actuator_ref_fingerprint")) args.actuator_ref_fingerprint else 0xD0F0_0003,
        .actuation_class = if (@hasField(T, "actuation_class")) args.actuation_class else .deterministic_fixture,
        .allowed_response_statuses = if (@hasField(T, "allowed_response_statuses")) args.allowed_response_statuses else .terminal_with_errors,
        .intent_fingerprint = args.intent_fingerprint,
        .envelope_fingerprint = args.envelope_fingerprint,
        .decision_fingerprint = args.decision_fingerprint,
        .expected_response_descriptor_fingerprint = args.expected_response_descriptor_fingerprint,
        .idempotency_key_fingerprint = args.idempotency_key_fingerprint,
        .supervision_ref_fingerprint = if (@hasField(T, "supervision_ref_fingerprint")) args.supervision_ref_fingerprint else null,
        .metadata = if (@hasField(T, "metadata")) args.metadata else "",
        .frame_request_bytes = if (@hasField(T, "frame_request_bytes")) args.frame_request_bytes else "",
        .payload_value_image_bytes = if (@hasField(T, "payload_value_image_bytes")) args.payload_value_image_bytes else "",
        .prepared_actuation_evidence_bytes = if (@hasField(T, "prepared_actuation_evidence_bytes")) args.prepared_actuation_evidence_bytes else "",
        .idempotency_key_bytes = if (@hasField(T, "idempotency_key_bytes")) args.idempotency_key_bytes else "",
        .expected_response_value_ref_fingerprint = if (@hasField(T, "expected_response_value_ref_fingerprint")) args.expected_response_value_ref_fingerprint else null,
        .expected_response_schema_ref_fingerprint = if (@hasField(T, "expected_response_schema_ref_fingerprint")) args.expected_response_schema_ref_fingerprint else null,
    };
}

fn applianceSyntheticHostRequest(args: anytype) world.Appliance.HostRequest {
    return world.Appliance.HostRequest.init(applianceSyntheticHostRequestArgs(@TypeOf(args), args));
}

fn applianceManifestRef(fingerprints: []const u64, index: usize) ?u64 {
    if (fingerprints.len == 0) return null;
    const fingerprint = fingerprints[index];
    return if (fingerprint == 0) null else fingerprint;
}

fn applianceManifestHostRequest(manifest: world.Appliance.Manifest, args: anytype) world.Appliance.HostRequest {
    const base = applianceSyntheticHostRequestArgs(@TypeOf(args), args);
    const binding_index: usize = base.request_ordinal;
    const binding_fingerprint = manifest.actuation_binding_fingerprints[binding_index];
    return world.Appliance.HostRequest.init(.{
        .turn_sequence_number = base.turn_sequence_number,
        .request_ordinal = base.request_ordinal,
        .run_handle_fingerprint = base.run_handle_fingerprint,
        .pending_port_fingerprint = base.pending_port_fingerprint,
        .world_port_id = @as(u32, @intCast(manifest.actuation_world_port_ids[binding_index])),
        .target_ref_fingerprint = manifest.root_target_ref_fingerprint,
        .world_surface_fingerprint = manifest.root_world_surface_fingerprint,
        .actuator_ref_fingerprint = manifest.actuation_actuator_ref_fingerprints[binding_index],
        .actuation_class = manifest.actuation_classes[binding_index],
        .allowed_response_statuses = manifest.actuation_allowed_response_statuses[binding_index],
        .intent_fingerprint = base.intent_fingerprint,
        .envelope_fingerprint = base.envelope_fingerprint,
        .decision_fingerprint = base.decision_fingerprint,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[binding_index],
        .idempotency_key_fingerprint = base.idempotency_key_fingerprint,
        .supervision_ref_fingerprint = if (manifest.supervision_policy_fingerprint == 0) null else manifest.supervision_policy_fingerprint,
        .metadata = base.metadata,
        .frame_request_bytes = base.frame_request_bytes,
        .payload_value_image_bytes = base.payload_value_image_bytes,
        .payload_value_ref_fingerprint = applianceManifestRef(manifest.actuation_payload_value_ref_fingerprints, binding_index),
        .payload_schema_ref_fingerprint = binding_fingerprint,
        .expected_response_value_ref_fingerprint = applianceManifestRef(manifest.actuation_response_value_ref_fingerprints, binding_index),
        .expected_response_schema_ref_fingerprint = binding_fingerprint,
        .prepared_actuation_evidence_bytes = base.prepared_actuation_evidence_bytes,
        .idempotency_key_bytes = base.idempotency_key_bytes,
    });
}

fn applianceHostReplyFor(request: world.Appliance.HostRequest, response_fingerprint: u64) world.Appliance.HostReply {
    const HostReplyResponse = struct {
        bytes: []const u8,
        fingerprint: u64,
    };
    const response: HostReplyResponse = if (request.expected_response_value_ref_fingerprint != null or request.expected_response_schema_ref_fingerprint != null) blk: {
        var image = world.Frame.ValueImage.fromCanonicalBytes(
            std.heap.page_allocator,
            null,
            request.expected_response_value_ref_fingerprint,
            request.expected_response_schema_ref_fingerprint,
            std.mem.asBytes(&response_fingerprint),
            false,
        ) catch unreachable;
        defer image.deinit(std.heap.page_allocator);
        const bytes = image.encode(std.heap.page_allocator) catch unreachable;
        break :blk .{ .bytes = bytes, .fingerprint = image.value_image_fingerprint };
    } else .{ .bytes = "", .fingerprint = response_fingerprint };
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response.fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = response.bytes,
        .host_evidence_fingerprint = response_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:fixture",
        .attempt_number = 1,
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
    });
}

fn applianceHostReplyWithStatusFor(
    request: world.Appliance.HostRequest,
    status: world.Appliance.HostOutcomeStatus,
) world.Appliance.HostReply {
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = status,
        .host_evidence_fingerprint = request.request_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:nonterminal",
        .attempt_number = 1,
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
    });
}

fn applianceManifestVariant(base: world.Appliance.Manifest, args: anytype) world.Appliance.Manifest {
    return world.Appliance.Manifest.init(.{
        .root_target_ref_fingerprint = base.root_target_ref_fingerprint,
        .root_world_surface_fingerprint = base.root_world_surface_fingerprint,
        .root_target_certificate_fingerprint = base.root_target_certificate_fingerprint,
        .link_plan_fingerprint = base.link_plan_fingerprint,
        .link_certificate_fingerprint = base.link_certificate_fingerprint,
        .assembly_fingerprint = base.assembly_fingerprint,
        .provider_target_ref_fingerprints = if (@hasField(@TypeOf(args), "provider_target_ref_fingerprints")) args.provider_target_ref_fingerprints else base.provider_target_ref_fingerprints,
        .fabric_plan_fingerprints = if (@hasField(@TypeOf(args), "fabric_plan_fingerprints")) args.fabric_plan_fingerprints else base.fabric_plan_fingerprints,
        .residual_import_set_fingerprint = base.residual_import_set_fingerprint,
        .actuation_descriptor_fingerprints = if (@hasField(@TypeOf(args), "actuation_descriptor_fingerprints")) args.actuation_descriptor_fingerprints else base.actuation_descriptor_fingerprints,
        .actuation_binding_fingerprints = if (@hasField(@TypeOf(args), "actuation_binding_fingerprints")) args.actuation_binding_fingerprints else base.actuation_binding_fingerprints,
        .actuation_actuator_ref_fingerprints = if (@hasField(@TypeOf(args), "actuation_actuator_ref_fingerprints")) args.actuation_actuator_ref_fingerprints else base.actuation_actuator_ref_fingerprints,
        .actuation_world_port_ids = if (@hasField(@TypeOf(args), "actuation_world_port_ids")) args.actuation_world_port_ids else base.actuation_world_port_ids,
        .actuation_payload_value_ref_fingerprints = if (@hasField(@TypeOf(args), "actuation_payload_value_ref_fingerprints")) args.actuation_payload_value_ref_fingerprints else base.actuation_payload_value_ref_fingerprints,
        .actuation_response_value_ref_fingerprints = if (@hasField(@TypeOf(args), "actuation_response_value_ref_fingerprints")) args.actuation_response_value_ref_fingerprints else base.actuation_response_value_ref_fingerprints,
        .actuation_classes = if (@hasField(@TypeOf(args), "actuation_classes")) args.actuation_classes else base.actuation_classes,
        .actuation_allowed_response_statuses = if (@hasField(@TypeOf(args), "actuation_allowed_response_statuses")) args.actuation_allowed_response_statuses else base.actuation_allowed_response_statuses,
        .supervision_policy_fingerprint = base.supervision_policy_fingerprint,
        .default_permit_requirement_fingerprints = if (@hasField(@TypeOf(args), "default_permit_requirement_fingerprints")) args.default_permit_requirement_fingerprints else base.default_permit_requirement_fingerprints,
        .capsule_profile_fingerprint = base.capsule_profile_fingerprint,
        .archive_profile_fingerprint = base.archive_profile_fingerprint,
        .supported_execution_modes = if (@hasField(@TypeOf(args), "supported_execution_modes")) args.supported_execution_modes else base.supported_execution_modes,
        .enabled_features = if (@hasField(@TypeOf(args), "enabled_features")) args.enabled_features else base.enabled_features,
        .capacity_fingerprint = base.capacity_fingerprint,
        .memory_plan_fingerprint = base.memory_plan_fingerprint,
        .required_host_capabilities = if (@hasField(@TypeOf(args), "required_host_capabilities")) args.required_host_capabilities else base.required_host_capabilities,
        .metadata = base.metadata,
    });
}

fn applianceRetentionAckFor(append_batch_fingerprint: u64, metadata: []const u8) world.Appliance.RetentionAck {
    return world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = append_batch_fingerprint,
        .resulting_moment_fingerprint = append_batch_fingerprint ^ 0xA11C_0001,
        .resulting_seal_fingerprint = append_batch_fingerprint ^ 0xA11C_0002,
        .resulting_chronicle_cursor_fingerprint = append_batch_fingerprint ^ 0xA11C_0003,
        .host_claim_status = .responded,
        .metadata = metadata,
    });
}

fn applianceRetentionAckForPendingCore(core: anytype, metadata: []const u8) !world.Appliance.RetentionAck {
    const append_batch_fingerprint = core.pending_archive_append_batch_fingerprint orelse return error.ArchiveParentMismatch;
    const resulting_cursor = core.pending_archive_resulting_cursor orelse return error.ArchiveParentMismatch;
    return world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = append_batch_fingerprint,
        .resulting_moment_fingerprint = append_batch_fingerprint ^ 0xA11C_0001,
        .resulting_seal_fingerprint = append_batch_fingerprint ^ 0xA11C_0002,
        .resulting_chronicle_cursor_fingerprint = resulting_cursor.cursor_fingerprint,
        .host_claim_status = .responded,
        .metadata = metadata,
    });
}

fn expectApplianceTypedPayloadValid(
    kind: world.Continuity.ObjectKind,
    format_version: u32,
    payload: []const u8,
) !void {
    const envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = kind,
        .object_format_version = format_version,
        .payload_bytes = payload,
    });
    try world.Continuity.validateObjectEnvelopeTypedPayload(std.testing.allocator, envelope);
}

fn appendApplianceWasmU32(out: *std.ArrayList(u8), value: u32) !void {
    var remaining = value;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        try out.append(std.testing.allocator, byte);
        if (remaining == 0) break;
    }
}

fn appendApplianceWasmI32Bits(out: *std.ArrayList(u8), value: u32) !void {
    var remaining: i32 = @bitCast(value);
    while (true) {
        var byte: u8 = @intCast(@as(u32, @bitCast(remaining)) & 0x7f);
        const sign_bit_set = (byte & 0x40) != 0;
        remaining >>= 7;
        const done = (remaining == 0 and !sign_bit_set) or (remaining == -1 and sign_bit_set);
        if (!done) byte |= 0x80;
        try out.append(std.testing.allocator, byte);
        if (done) break;
    }
}

fn appendApplianceWasmName(out: *std.ArrayList(u8), name: []const u8) !void {
    try appendApplianceWasmU32(out, @intCast(name.len));
    try out.appendSlice(std.testing.allocator, name);
}

fn appendApplianceWasmSection(module: *std.ArrayList(u8), section_id: u8, section: []const u8) !void {
    try module.append(std.testing.allocator, section_id);
    try appendApplianceWasmU32(module, @intCast(section.len));
    try module.appendSlice(std.testing.allocator, section);
}

fn appendApplianceWasmFuncType(out: *std.ArrayList(u8), param_count: u32, result_count: u32) !void {
    try out.append(std.testing.allocator, 0x60);
    try appendApplianceWasmU32(out, param_count);
    var param_index: u32 = 0;
    while (param_index < param_count) : (param_index += 1) try out.append(std.testing.allocator, 0x7f);
    try appendApplianceWasmU32(out, result_count);
    var result_index: u32 = 0;
    while (result_index < result_count) : (result_index += 1) try out.append(std.testing.allocator, 0x7f);
}

fn applianceRequiredExportParamCount(index: usize) u32 {
    return switch (index) {
        2, 3, 5, 7 => 2,
        else => 0,
    };
}

const ApplianceWasmBuildOptions = struct {
    duplicate_memory_export: bool = false,
    duplicate_memory_section: bool = false,
    start_section_function_index: ?u32 = null,
    data_section_before_code: bool = false,
    helper_exports: HelperExports = .none,
    invalid_required_body_index: ?usize = null,
    missing_required_result_index: ?usize = null,
    dropped_required_result_index: ?usize = null,
    extra_result_stack_index: ?usize = null,
    invalid_required_call_target_index: ?usize = null,
    invalid_required_call_indirect_type_index: ?usize = null,
    invalid_required_externref_call_indirect_table_index: ?usize = null,
    missing_call_indirect_table_operand_index: ?usize = null,
    invalid_required_local_index: ?usize = null,
    invalid_required_non_i32_local_set_index: ?usize = null,
    drop_underflow_required_body_index: ?usize = null,
    invalid_required_block_type_index: ?usize = null,
    invalid_required_else_frame_index: ?usize = null,
    missing_required_if_else_result_index: ?usize = null,
    invalid_required_operand_order_index: ?usize = null,
    missing_required_block_result_index: ?usize = null,
    extra_required_control_stack_index: ?usize = null,
    missing_required_block_param_index: ?usize = null,
    invalid_required_branch_label_index: ?usize = null,
    missing_required_branch_result_index: ?usize = null,
    invalid_required_memory_alignment_index: ?usize = null,
    invalid_required_memory_copy_index: ?usize = null,
    invalid_required_non_i32_comparison_index: ?usize = null,
    invalid_required_prefixed_conversion_index: ?usize = null,
    invalid_required_non_i32_call_index: ?usize = null,
    invalid_required_mixed_call_order_index: ?usize = null,
    trap_only_required_body_index: ?usize = null,
    invalid_unused_body: bool = false,
    invalid_unused_missing_result_body: bool = false,
    invalid_unused_extra_result_body: bool = false,
    invalid_unused_non_i32_param_body: bool = false,
    invalid_extra_export_kind: bool = false,
    invalid_extra_export_function_index: bool = false,
    invalid_unexported_function_type_index: bool = false,
    invalid_unused_type: bool = false,
    invalid_table_max_below_min: bool = false,
    malformed_global_section: bool = false,
    immutable_i32_global_section: bool = false,
    invalid_required_global_set_index: ?usize = null,
    overlong_global_i64_const: bool = false,
    invalid_const_expr_global_get: bool = false,
    invalid_data_i64_offset: bool = false,
    explicit_table_element_section: bool = false,
    externref_table_section: bool = false,
    ref_func_element_section: bool = false,
    invalid_element_function_index: bool = false,
    invalid_ref_null_element_type: bool = false,
    multi_segment_data_section: bool = false,
    mismatched_data_count_section: bool = false,
    invalid_data_memory_index: bool = false,
    custom_section: bool = false,

    const HelperExports = enum {
        none,
        valid,
        malformed_alloc,
    };
};

fn minimalApplianceMetadataValues(memory_pages: u32) [world.Appliance.Abi.metadata_exports.len]u32 {
    var metadata_values = [_]u32{0} ** world.Appliance.Abi.metadata_exports.len;
    metadata_values[7] = memory_pages;
    return metadata_values;
}

fn buildMinimalApplianceWasm(abi_version: u32) !std.ArrayList(u8) {
    return buildMinimalApplianceWasmWithMetadata(
        abi_version,
        minimalApplianceMetadataValues(1),
        1,
        1,
    );
}

fn buildMinimalApplianceWasmWithMetadata(
    abi_version: u32,
    metadata_values: [world.Appliance.Abi.metadata_exports.len]u32,
    memory_initial_pages: u32,
    memory_max_pages: ?u32,
) !std.ArrayList(u8) {
    return buildMinimalApplianceWasmWithMemoryExport(
        abi_version,
        metadata_values,
        memory_initial_pages,
        memory_max_pages,
        null,
        null,
        0,
    );
}

fn buildMinimalApplianceWasmWithMemoryExport(
    abi_version: u32,
    metadata_values: [world.Appliance.Abi.metadata_exports.len]u32,
    memory_initial_pages: u32,
    memory_max_pages: ?u32,
    second_memory_initial_pages: ?u32,
    second_memory_max_pages: ?u32,
    memory_export_index: u32,
) !std.ArrayList(u8) {
    return buildMinimalApplianceWasmWithOptions(
        abi_version,
        metadata_values,
        memory_initial_pages,
        memory_max_pages,
        second_memory_initial_pages,
        second_memory_max_pages,
        memory_export_index,
        .{},
    );
}

fn buildMinimalApplianceWasmWithOptions(
    abi_version: u32,
    metadata_values: [world.Appliance.Abi.metadata_exports.len]u32,
    memory_initial_pages: u32,
    memory_max_pages: ?u32,
    second_memory_initial_pages: ?u32,
    second_memory_max_pages: ?u32,
    memory_export_index: u32,
    options: ApplianceWasmBuildOptions,
) !std.ArrayList(u8) {
    const required_len = world.Appliance.Abi.required_exports.len;
    const metadata_len = world.Appliance.Abi.metadata_exports.len;
    const helper_count: usize = switch (options.helper_exports) {
        .none => 0,
        .valid, .malformed_alloc => 2,
    };
    const extra_unexported_count: usize =
        @as(usize, if (options.invalid_unexported_function_type_index) 1 else 0) +
        @as(usize, if (options.invalid_unused_body) 1 else 0) +
        @as(usize, if (options.invalid_unused_missing_result_body) 1 else 0) +
        @as(usize, if (options.invalid_unused_extra_result_body) 1 else 0) +
        @as(usize, if (options.invalid_required_non_i32_call_index != null) 1 else 0) +
        @as(usize, if (options.invalid_required_mixed_call_order_index != null) 1 else 0) +
        @as(usize, if (options.invalid_unused_non_i32_param_body) 1 else 0);
    const function_count = required_len + metadata_len + helper_count + extra_unexported_count;
    const extra_export_count: usize =
        @as(usize, if (options.duplicate_memory_export) 1 else 0) +
        @as(usize, if (options.invalid_extra_export_kind) 1 else 0) +
        @as(usize, if (options.invalid_extra_export_function_index) 1 else 0);
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(std.testing.allocator);
    try module.appendSlice(std.testing.allocator, "\x00asm");
    try module.appendSlice(std.testing.allocator, &.{ 1, 0, 0, 0 });
    if (options.custom_section) {
        var custom: std.ArrayList(u8) = .empty;
        defer custom.deinit(std.testing.allocator);
        try appendApplianceWasmName(&custom, "name");
        try custom.appendSlice(std.testing.allocator, "appliance");
        try appendApplianceWasmSection(&module, 0, custom.items);
    }

    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(std.testing.allocator);
    const extra_type_count: u32 =
        (if (options.invalid_required_non_i32_call_index != null) @as(u32, 1) else 0) +
        (if (options.invalid_required_mixed_call_order_index != null) @as(u32, 1) else 0) +
        (if (options.invalid_unused_non_i32_param_body) @as(u32, 1) else 0);
    try appendApplianceWasmU32(&types, (if (options.invalid_unused_type) @as(u32, 5) else @as(u32, 4)) + extra_type_count);
    try appendApplianceWasmFuncType(&types, 0, 1);
    try appendApplianceWasmFuncType(&types, 2, 1);
    try appendApplianceWasmFuncType(&types, 1, 1);
    try appendApplianceWasmFuncType(&types, 2, 0);
    if (options.invalid_required_non_i32_call_index != null) {
        try types.append(std.testing.allocator, 0x60);
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0x7d);
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0x7f);
    }
    if (options.invalid_required_mixed_call_order_index != null) {
        try types.append(std.testing.allocator, 0x60);
        try appendApplianceWasmU32(&types, 2);
        try types.appendSlice(std.testing.allocator, &.{ 0x7e, 0x7f });
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0x7f);
    }
    if (options.invalid_unused_non_i32_param_body) {
        try types.append(std.testing.allocator, 0x60);
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0x7e);
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0x7f);
    }
    if (options.invalid_unused_type) {
        try types.append(std.testing.allocator, 0x60);
        try appendApplianceWasmU32(&types, 1);
        try types.append(std.testing.allocator, 0xff);
        try appendApplianceWasmU32(&types, 0);
    }
    try appendApplianceWasmSection(&module, 1, types.items);

    var functions: std.ArrayList(u8) = .empty;
    defer functions.deinit(std.testing.allocator);
    try appendApplianceWasmU32(&functions, @intCast(function_count));
    for (world.Appliance.Abi.required_exports, 0..) |_, index| {
        try appendApplianceWasmU32(&functions, if (applianceRequiredExportParamCount(index) == 2) 1 else 0);
    }
    for (world.Appliance.Abi.metadata_exports) |_| try appendApplianceWasmU32(&functions, 0);
    switch (options.helper_exports) {
        .none => {},
        .valid => {
            try appendApplianceWasmU32(&functions, 2);
            try appendApplianceWasmU32(&functions, 3);
        },
        .malformed_alloc => {
            try appendApplianceWasmU32(&functions, 0);
            try appendApplianceWasmU32(&functions, 3);
        },
    }
    if (options.invalid_unexported_function_type_index) try appendApplianceWasmU32(&functions, 99);
    if (options.invalid_unused_body) try appendApplianceWasmU32(&functions, 0);
    if (options.invalid_unused_missing_result_body) try appendApplianceWasmU32(&functions, 0);
    if (options.invalid_unused_extra_result_body) try appendApplianceWasmU32(&functions, 0);
    if (options.invalid_required_non_i32_call_index != null) try appendApplianceWasmU32(&functions, 4);
    if (options.invalid_required_mixed_call_order_index != null) try appendApplianceWasmU32(&functions, 4 + if (options.invalid_required_non_i32_call_index != null) @as(u32, 1) else @as(u32, 0));
    if (options.invalid_unused_non_i32_param_body) try appendApplianceWasmU32(&functions, 4 + (if (options.invalid_required_non_i32_call_index != null) @as(u32, 1) else @as(u32, 0)) + (if (options.invalid_required_mixed_call_order_index != null) @as(u32, 1) else @as(u32, 0)));
    try appendApplianceWasmSection(&module, 3, functions.items);

    if (options.explicit_table_element_section or options.externref_table_section) {
        var tables: std.ArrayList(u8) = .empty;
        defer tables.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&tables, 1);
        try tables.append(std.testing.allocator, if (options.externref_table_section) 0x6f else 0x70);
        try tables.append(std.testing.allocator, if (options.invalid_table_max_below_min) 1 else 0);
        try appendApplianceWasmU32(&tables, if (options.invalid_table_max_below_min) 2 else 1);
        if (options.invalid_table_max_below_min) try appendApplianceWasmU32(&tables, 1);
        try appendApplianceWasmSection(&module, 4, tables.items);
    }

    var memory: std.ArrayList(u8) = .empty;
    defer memory.deinit(std.testing.allocator);
    try appendApplianceWasmU32(&memory, if (second_memory_initial_pages == null) 1 else 2);
    try memory.append(std.testing.allocator, if (memory_max_pages == null) 0 else 1);
    try appendApplianceWasmU32(&memory, memory_initial_pages);
    if (memory_max_pages) |max_pages| try appendApplianceWasmU32(&memory, max_pages);
    if (second_memory_initial_pages) |second_initial| {
        try memory.append(std.testing.allocator, if (second_memory_max_pages == null) 0 else 1);
        try appendApplianceWasmU32(&memory, second_initial);
        if (second_memory_max_pages) |second_max| try appendApplianceWasmU32(&memory, second_max);
    }
    try appendApplianceWasmSection(&module, 5, memory.items);
    if (options.duplicate_memory_section) try appendApplianceWasmSection(&module, 5, memory.items);

    if (options.malformed_global_section or options.immutable_i32_global_section or options.invalid_required_global_set_index != null or options.overlong_global_i64_const or options.invalid_const_expr_global_get) {
        var globals: std.ArrayList(u8) = .empty;
        defer globals.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&globals, 1);
        try globals.append(std.testing.allocator, if (options.overlong_global_i64_const) 0x7e else 0x7f);
        try globals.append(std.testing.allocator, 0);
        if (options.overlong_global_i64_const) {
            try globals.append(std.testing.allocator, 0x42);
            try globals.appendNTimes(std.testing.allocator, 0x80, 11);
            try globals.append(std.testing.allocator, 0x00);
        } else if (options.invalid_const_expr_global_get) {
            try globals.append(std.testing.allocator, 0x23);
            try appendApplianceWasmU32(&globals, 0);
            try globals.append(std.testing.allocator, 0x0b);
        } else {
            try globals.append(std.testing.allocator, 0x41);
            try globals.append(std.testing.allocator, 0);
        }
        try appendApplianceWasmSection(&module, 6, globals.items);
    }

    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(std.testing.allocator);
    try appendApplianceWasmU32(&exports, @intCast(function_count + 1 + extra_export_count));
    for (world.Appliance.Abi.required_exports, 0..) |name, index| {
        try appendApplianceWasmName(&exports, name);
        try exports.append(std.testing.allocator, 0);
        try appendApplianceWasmU32(&exports, @intCast(index));
    }
    for (world.Appliance.Abi.metadata_exports, 0..) |name, index| {
        try appendApplianceWasmName(&exports, name);
        try exports.append(std.testing.allocator, 0);
        try appendApplianceWasmU32(&exports, @intCast(required_len + index));
    }
    try appendApplianceWasmName(&exports, "memory");
    try exports.append(std.testing.allocator, 2);
    try appendApplianceWasmU32(&exports, memory_export_index);
    if (options.duplicate_memory_export) {
        try appendApplianceWasmName(&exports, "memory");
        try exports.append(std.testing.allocator, 2);
        try appendApplianceWasmU32(&exports, memory_export_index);
    }
    if (options.invalid_extra_export_kind) {
        try appendApplianceWasmName(&exports, "bad_kind");
        try exports.append(std.testing.allocator, 99);
        try appendApplianceWasmU32(&exports, 0);
    }
    if (options.invalid_extra_export_function_index) {
        try appendApplianceWasmName(&exports, "bad_function_index");
        try exports.append(std.testing.allocator, 0);
        try appendApplianceWasmU32(&exports, @intCast(function_count + 16));
    }
    switch (options.helper_exports) {
        .none => {},
        .valid, .malformed_alloc => {
            try appendApplianceWasmName(&exports, "world_alloc");
            try exports.append(std.testing.allocator, 0);
            try appendApplianceWasmU32(&exports, @intCast(required_len + metadata_len));
            try appendApplianceWasmName(&exports, "world_free");
            try exports.append(std.testing.allocator, 0);
            try appendApplianceWasmU32(&exports, @intCast(required_len + metadata_len + 1));
        },
    }
    try appendApplianceWasmSection(&module, 7, exports.items);

    if (options.start_section_function_index) |function_index| {
        var start: std.ArrayList(u8) = .empty;
        defer start.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&start, function_index);
        try appendApplianceWasmSection(&module, 8, start.items);
    }

    if (options.explicit_table_element_section or options.ref_func_element_section or options.invalid_element_function_index or options.invalid_ref_null_element_type) {
        var elements: std.ArrayList(u8) = .empty;
        defer elements.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&elements, 1);
        if (options.ref_func_element_section) {
            try appendApplianceWasmU32(&elements, 5);
            try elements.append(std.testing.allocator, 0x70);
            try appendApplianceWasmU32(&elements, 1);
            try elements.append(std.testing.allocator, 0xd2);
            try appendApplianceWasmU32(&elements, 0);
            try elements.append(std.testing.allocator, 0x0b);
        } else if (options.invalid_ref_null_element_type) {
            try appendApplianceWasmU32(&elements, 5);
            try elements.append(std.testing.allocator, 0x70);
            try appendApplianceWasmU32(&elements, 1);
            try elements.append(std.testing.allocator, 0xd0);
            try elements.append(std.testing.allocator, 0x6f);
            try elements.append(std.testing.allocator, 0x0b);
        } else if (options.invalid_element_function_index) {
            try appendApplianceWasmU32(&elements, 2);
            try appendApplianceWasmU32(&elements, 0);
            try elements.append(std.testing.allocator, 0x41);
            try elements.append(std.testing.allocator, 0);
            try elements.append(std.testing.allocator, 0x0b);
            try elements.append(std.testing.allocator, 0);
            try appendApplianceWasmU32(&elements, 1);
            try appendApplianceWasmU32(&elements, @intCast(function_count + 1));
        } else {
            try appendApplianceWasmU32(&elements, 2);
            try appendApplianceWasmU32(&elements, 0);
            try elements.append(std.testing.allocator, 0x41);
            try elements.append(std.testing.allocator, 0);
            try elements.append(std.testing.allocator, 0x0b);
            try elements.append(std.testing.allocator, 0);
            try appendApplianceWasmU32(&elements, 0);
        }
        try appendApplianceWasmSection(&module, 9, elements.items);
    }

    if (options.data_section_before_code) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmSection(&module, 11, data.items);
    }

    if (options.multi_segment_data_section) {
        var data_count: std.ArrayList(u8) = .empty;
        defer data_count.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data_count, 2);
        try appendApplianceWasmSection(&module, 12, data_count.items);
    } else if (options.mismatched_data_count_section) {
        var data_count: std.ArrayList(u8) = .empty;
        defer data_count.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data_count, 1);
        try appendApplianceWasmSection(&module, 12, data_count.items);
    }

    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(std.testing.allocator);
    try appendApplianceWasmU32(&code, @intCast(function_count));
    var index: usize = 0;
    while (index < function_count) : (index += 1) {
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(std.testing.allocator);
        if (options.invalid_required_body_index != null and index == options.invalid_required_body_index.?) {
            try appendApplianceWasmU32(&body, 1);
            try appendApplianceWasmU32(&body, 1);
            try body.append(std.testing.allocator, 0xff);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_required_result_index != null and index == options.missing_required_result_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.dropped_required_result_index != null and index == options.dropped_required_result_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x1a);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.extra_result_stack_index != null and index == options.extra_result_stack_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 1);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_call_target_index != null and index == options.invalid_required_call_target_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x10);
            try appendApplianceWasmU32(&body, @intCast(function_count + 1));
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_call_indirect_type_index != null and index == options.invalid_required_call_indirect_type_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x11);
            try appendApplianceWasmU32(&body, 999);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_externref_call_indirect_table_index != null and index == options.invalid_required_externref_call_indirect_table_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x11);
            try appendApplianceWasmU32(&body, 0);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_call_indirect_table_operand_index != null and index == options.missing_call_indirect_table_operand_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x11);
            try appendApplianceWasmU32(&body, 0);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x1a);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_local_index != null and index == options.invalid_required_local_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x20);
            try appendApplianceWasmU32(&body, 99);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_non_i32_local_set_index != null and index == options.invalid_required_non_i32_local_set_index.?) {
            try appendApplianceWasmU32(&body, 1);
            try appendApplianceWasmU32(&body, 1);
            try body.append(std.testing.allocator, 0x7d);
            try body.append(std.testing.allocator, 0x42);
            try body.append(std.testing.allocator, 0);
            try body.append(std.testing.allocator, 0x21);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.drop_underflow_required_body_index != null and index == options.drop_underflow_required_body_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x1a);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_block_type_index != null and index == options.invalid_required_block_type_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x02);
            try appendApplianceWasmU32(&body, 99);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_else_frame_index != null and index == options.invalid_required_else_frame_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x02);
            try body.append(std.testing.allocator, 0x40);
            try body.append(std.testing.allocator, 0x05);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_required_if_else_result_index != null and index == options.missing_required_if_else_result_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 1);
            try body.append(std.testing.allocator, 0x04);
            try body.append(std.testing.allocator, 0x7f);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 2);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_operand_order_index != null and index == options.invalid_required_operand_order_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 1);
            try body.append(std.testing.allocator, 0x43);
            try body.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 0 });
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 2);
            try body.append(std.testing.allocator, 0x6a);
            try body.append(std.testing.allocator, 0x1a);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_required_block_result_index != null and index == options.missing_required_block_result_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x02);
            try body.append(std.testing.allocator, 0x7f);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.extra_required_control_stack_index != null and index == options.extra_required_control_stack_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x02);
            try body.append(std.testing.allocator, 0x40);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 1);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_required_block_param_index != null and index == options.missing_required_block_param_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x02);
            try appendApplianceWasmU32(&body, 2);
            try body.append(std.testing.allocator, 0x0b);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_branch_label_index != null and index == options.invalid_required_branch_label_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0c);
            try appendApplianceWasmU32(&body, 99);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.missing_required_branch_result_index != null and index == options.missing_required_branch_result_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0c);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_non_i32_call_index != null and index == options.invalid_required_non_i32_call_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x10);
            try appendApplianceWasmU32(&body, @intCast(function_count - 1));
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_mixed_call_order_index != null and index == options.invalid_required_mixed_call_order_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x42);
            try body.append(std.testing.allocator, 0);
            try body.append(std.testing.allocator, 0x10);
            try appendApplianceWasmU32(&body, @intCast(function_count - 1));
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_global_set_index != null and index == options.invalid_required_global_set_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x24);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_unused_body and index == function_count - 1) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0xff);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_unused_missing_result_body and index == function_count - 1) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_unused_extra_result_body and index == function_count - 1) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 1);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_unused_non_i32_param_body and index == function_count - 1) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x20);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_prefixed_conversion_index != null and index == options.invalid_required_prefixed_conversion_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0xfc);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_memory_alignment_index != null and index == options.invalid_required_memory_alignment_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x28);
            try appendApplianceWasmU32(&body, 3);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_memory_copy_index != null and index == options.invalid_required_memory_copy_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0xfc);
            try appendApplianceWasmU32(&body, 10);
            try appendApplianceWasmU32(&body, 1);
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x41);
            try appendApplianceWasmI32Bits(&body, 0);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.invalid_required_non_i32_comparison_index != null and index == options.invalid_required_non_i32_comparison_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x50);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        if (options.trap_only_required_body_index != null and index == options.trap_only_required_body_index.?) {
            try appendApplianceWasmU32(&body, 0);
            try body.append(std.testing.allocator, 0x00);
            try body.append(std.testing.allocator, 0x0b);
            try appendApplianceWasmU32(&code, @intCast(body.items.len));
            try code.appendSlice(std.testing.allocator, body.items);
            continue;
        }
        try appendApplianceWasmU32(&body, 0);
        const void_helper_index = required_len + metadata_len + 1;
        const emits_result = !(options.helper_exports != .none and index == void_helper_index);
        if (emits_result) {
            try body.append(std.testing.allocator, 0x41);
            const value = if (index == 0)
                abi_version
            else if (index >= required_len and index < required_len + metadata_len)
                metadata_values[index - required_len]
            else
                0;
            try appendApplianceWasmI32Bits(&body, value);
        }
        try body.append(std.testing.allocator, 0x0b);
        try appendApplianceWasmU32(&code, @intCast(body.items.len));
        try code.appendSlice(std.testing.allocator, body.items);
    }
    try appendApplianceWasmSection(&module, 10, code.items);

    if (options.invalid_data_i64_offset) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data, 1);
        try appendApplianceWasmU32(&data, 0);
        try data.append(std.testing.allocator, 0x42);
        try data.append(std.testing.allocator, 0);
        try data.append(std.testing.allocator, 0x0b);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmSection(&module, 11, data.items);
    } else if (options.invalid_data_memory_index) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data, 1);
        try appendApplianceWasmU32(&data, 2);
        try appendApplianceWasmU32(&data, 1);
        try data.append(std.testing.allocator, 0x41);
        try data.append(std.testing.allocator, 0);
        try data.append(std.testing.allocator, 0x0b);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmSection(&module, 11, data.items);
    } else if (options.multi_segment_data_section) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data, 2);
        try appendApplianceWasmU32(&data, 1);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmU32(&data, 1);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmSection(&module, 11, data.items);
    } else if (options.mismatched_data_count_section) {
        var data: std.ArrayList(u8) = .empty;
        defer data.deinit(std.testing.allocator);
        try appendApplianceWasmU32(&data, 0);
        try appendApplianceWasmSection(&module, 11, data.items);
    }
    return module;
}

test "appliance static contract exposes root namespace and versions" {
    try std.testing.expectEqual(@as(u32, 3), world.world_appliance_abi_version);
    try std.testing.expectEqual(@as(u32, 3), world.world_appliance_manifest_format_version);
    try std.testing.expectEqual(@as(u32, 3), world.world_appliance_manifest_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_appliance_memory_plan_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_appliance_command_format_version);
    try std.testing.expectEqual(@as(u32, 4), world.world_appliance_host_request_format_version);
    try std.testing.expectEqual(@as(u32, 4), world.world_appliance_host_request_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 3), world.world_appliance_turn_output_format_version);
    try std.testing.expectEqual(@as(u32, 2), world.world_appliance_turn_output_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_appliance_checkpoint_format_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_appliance_turn_receipt_format_version);
    try std.testing.expectEqual(@as(u32, 3), world.Appliance.Abi.version);
    try std.testing.expectEqual(world.Appliance.Abi.Status.buffer_too_small, @as(world.Appliance.Abi.Status, @enumFromInt(15)));
    try std.testing.expectEqual(@as(usize, 8), world.Appliance.Abi.metadata_exports.len);
    try std.testing.expect(world.Appliance.Abi.statusHasTurnOutput(.needs_host));
    try std.testing.expect(world.Appliance.Abi.statusHasTurnOutput(.completed));
    try std.testing.expect(world.Appliance.Abi.statusHasTurnOutput(.failed));
    try std.testing.expect(world.Appliance.Abi.statusHasTurnOutput(.blocked));
    try std.testing.expect(world.Appliance.Abi.statusHasTurnOutput(.cancelled));
    try std.testing.expect(!world.Appliance.Abi.statusHasTurnOutput(.invalid_command));
    try std.testing.expect(!world.Appliance.Abi.statusHasTurnOutput(.capacity_exceeded));
}

test "appliance wasm inspector validates ABI version from code" {
    var module = try buildMinimalApplianceWasm(world.Appliance.Abi.version);
    defer module.deinit(std.testing.allocator);
    const inspection = try world.Appliance.Abi.inspectWasm(module.items);
    try std.testing.expectEqual(world.Appliance.Abi.version, inspection.abi_version);
    try std.testing.expect(inspection.required_export_signatures_valid);
    try std.testing.expect(inspection.metadata_export_signatures_valid);
    try std.testing.expect(inspection.passed());

    var stale = try buildMinimalApplianceWasm(world.Appliance.Abi.version + 1);
    defer stale.deinit(std.testing.allocator);
    const stale_inspection = try world.Appliance.Abi.inspectWasm(stale.items);
    try std.testing.expectEqual(world.Appliance.Abi.version + 1, stale_inspection.abi_version);
    try std.testing.expect(!stale_inspection.passed());

    const malformed_section_len = [_]u8{
        0x00, 0x61, 0x73, 0x6d,
        0x01, 0x00, 0x00, 0x00,
        0x01, 0xff, 0xff, 0xff,
        0xff, 0x7f,
    };
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(&malformed_section_len));
}

test "appliance wasm inspector binds metadata values and memory limits" {
    const metadata_values = [_]u32{
        0x89abcdef,
        0x01234567,
        0xfedcba98,
        0x76543210,
        0x12345678,
        0x9abcdef0,
        4_259_840,
        65,
    };
    var module = try buildMinimalApplianceWasmWithMetadata(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
    );
    defer module.deinit(std.testing.allocator);

    const inspection = try world.Appliance.Abi.inspectWasm(module.items);
    try std.testing.expect(inspection.passed());
    try std.testing.expect(inspection.metadata_export_values_valid);
    try std.testing.expectEqual(@as(u64, 0x0123456789abcdef), inspection.manifest_fingerprint);
    try std.testing.expectEqual(@as(u64, 0x76543210fedcba98), inspection.capacity_fingerprint);
    try std.testing.expectEqual(@as(u64, 0x9abcdef012345678), inspection.memory_plan_fingerprint);
    try std.testing.expectEqual(@as(u64, 4_259_840), inspection.required_memory_bytes);
    try std.testing.expectEqual(@as(u32, 65), inspection.max_linear_memory_pages);
    try std.testing.expectEqual(@as(u32, 65), inspection.memory_initial_pages);
    try std.testing.expectEqual(@as(?u32, 65), inspection.memory_max_pages);

    var unbounded = try buildMinimalApplianceWasmWithMetadata(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        null,
    );
    defer unbounded.deinit(std.testing.allocator);
    const unbounded_inspection = try world.Appliance.Abi.inspectWasm(unbounded.items);
    try std.testing.expectEqual(@as(?u32, null), unbounded_inspection.memory_max_pages);
    try std.testing.expect(!unbounded_inspection.passed());

    var oversized_required_values = metadata_values;
    oversized_required_values[6] = 65 * 64 * 1024 + 1;
    var oversized_required = try buildMinimalApplianceWasmWithMetadata(
        world.Appliance.Abi.version,
        oversized_required_values,
        65,
        65,
    );
    defer oversized_required.deinit(std.testing.allocator);
    const oversized_required_inspection = try world.Appliance.Abi.inspectWasm(oversized_required.items);
    try std.testing.expect(oversized_required_inspection.metadata_export_values_valid);
    try std.testing.expect(!oversized_required_inspection.passed());

    var too_small = try buildMinimalApplianceWasmWithMetadata(
        world.Appliance.Abi.version,
        metadata_values,
        64,
        65,
    );
    defer too_small.deinit(std.testing.allocator);
    const too_small_inspection = try world.Appliance.Abi.inspectWasm(too_small.items);
    try std.testing.expect(!too_small_inspection.passed());

    var too_large = try buildMinimalApplianceWasmWithMetadata(
        world.Appliance.Abi.version,
        metadata_values,
        66,
        66,
    );
    defer too_large.deinit(std.testing.allocator);
    const too_large_inspection = try world.Appliance.Abi.inspectWasm(too_large.items);
    try std.testing.expect(!too_large_inspection.passed());

    var exported_second = try buildMinimalApplianceWasmWithMemoryExport(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        66,
        66,
        1,
    );
    defer exported_second.deinit(std.testing.allocator);
    const exported_second_inspection = try world.Appliance.Abi.inspectWasm(exported_second.items);
    try std.testing.expectEqual(@as(u32, 66), exported_second_inspection.memory_initial_pages);
    try std.testing.expectEqual(@as(?u32, 66), exported_second_inspection.memory_max_pages);
    try std.testing.expectEqual(@as(u32, 2), exported_second_inspection.memory_count);
    try std.testing.expect(!exported_second_inspection.passed());

    var hidden_second = try buildMinimalApplianceWasmWithMemoryExport(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        66,
        66,
        0,
    );
    defer hidden_second.deinit(std.testing.allocator);
    const hidden_second_inspection = try world.Appliance.Abi.inspectWasm(hidden_second.items);
    try std.testing.expectEqual(@as(u32, 65), hidden_second_inspection.memory_initial_pages);
    try std.testing.expectEqual(@as(u32, 2), hidden_second_inspection.memory_count);
    try std.testing.expect(!hidden_second_inspection.passed());
}

test "appliance wasm inspector rejects malformed exports and required bodies" {
    const metadata_values = minimalApplianceMetadataValues(65);

    var valid_helpers = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .helper_exports = .valid },
    );
    defer valid_helpers.deinit(std.testing.allocator);
    const valid_helper_inspection = try world.Appliance.Abi.inspectWasm(valid_helpers.items);
    try std.testing.expect(valid_helper_inspection.alloc_export_present);
    try std.testing.expect(valid_helper_inspection.free_export_present);
    try std.testing.expect(valid_helper_inspection.optional_helper_exports_valid);
    try std.testing.expect(valid_helper_inspection.passed());

    var malformed_alloc = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .helper_exports = .malformed_alloc },
    );
    defer malformed_alloc.deinit(std.testing.allocator);
    const malformed_alloc_inspection = try world.Appliance.Abi.inspectWasm(malformed_alloc.items);
    try std.testing.expect(!malformed_alloc_inspection.alloc_export_present);
    try std.testing.expect(malformed_alloc_inspection.free_export_present);
    try std.testing.expect(!malformed_alloc_inspection.optional_helper_exports_valid);
    try std.testing.expect(!malformed_alloc_inspection.passed());

    var duplicate_export = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .duplicate_memory_export = true },
    );
    defer duplicate_export.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(duplicate_export.items));

    var invalid_required_body = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_body_index = 1 },
    );
    defer invalid_required_body.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_required_body.items));

    var missing_required_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .missing_required_result_index = 1 },
    );
    defer missing_required_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_required_result.items));

    var dropped_required_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .dropped_required_result_index = 1 },
    );
    defer dropped_required_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(dropped_required_result.items));

    var extra_result_stack = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .extra_result_stack_index = 1 },
    );
    defer extra_result_stack.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(extra_result_stack.items));

    var invalid_call_target = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_call_target_index = 1 },
    );
    defer invalid_call_target.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_call_target.items));

    var non_i32_call = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_non_i32_call_index = 1 },
    );
    defer non_i32_call.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(non_i32_call.items));

    var mixed_call_order = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_mixed_call_order_index = 1 },
    );
    defer mixed_call_order.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(mixed_call_order.items));

    var invalid_call_indirect_type = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_call_indirect_type_index = 1 },
    );
    defer invalid_call_indirect_type.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_call_indirect_type.items));

    var missing_call_indirect_table_operand = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .explicit_table_element_section = true, .missing_call_indirect_table_operand_index = 1 },
    );
    defer missing_call_indirect_table_operand.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_call_indirect_table_operand.items));

    var externref_call_indirect_table = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .externref_table_section = true, .invalid_required_externref_call_indirect_table_index = 1 },
    );
    defer externref_call_indirect_table.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(externref_call_indirect_table.items));

    var invalid_local_index = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_local_index = 1 },
    );
    defer invalid_local_index.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_local_index.items));

    var non_i32_local_type_mismatch = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_non_i32_local_set_index = 1 },
    );
    defer non_i32_local_type_mismatch.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(non_i32_local_type_mismatch.items));

    var drop_underflow = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .drop_underflow_required_body_index = 1 },
    );
    defer drop_underflow.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(drop_underflow.items));

    var invalid_block_type = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_block_type_index = 1 },
    );
    defer invalid_block_type.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_block_type.items));

    var invalid_else_frame = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_else_frame_index = 1 },
    );
    defer invalid_else_frame.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_else_frame.items));

    var missing_if_else_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .missing_required_if_else_result_index = 1 },
    );
    defer missing_if_else_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_if_else_result.items));

    var invalid_operand_order = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_operand_order_index = 1 },
    );
    defer invalid_operand_order.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_operand_order.items));

    var missing_block_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .missing_required_block_result_index = 1 },
    );
    defer missing_block_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_block_result.items));

    var extra_control_stack = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .extra_required_control_stack_index = 1 },
    );
    defer extra_control_stack.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(extra_control_stack.items));

    var missing_block_param = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .missing_required_block_param_index = 1 },
    );
    defer missing_block_param.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_block_param.items));

    var invalid_branch_label = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_branch_label_index = 1 },
    );
    defer invalid_branch_label.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_branch_label.items));

    var missing_branch_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .missing_required_branch_result_index = 1 },
    );
    defer missing_branch_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(missing_branch_result.items));

    var invalid_unused_body = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unused_body = true },
    );
    defer invalid_unused_body.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unused_body.items));

    var invalid_unused_missing_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unused_missing_result_body = true },
    );
    defer invalid_unused_missing_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unused_missing_result.items));

    var invalid_unused_extra_result = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unused_extra_result_body = true },
    );
    defer invalid_unused_extra_result.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unused_extra_result.items));

    var invalid_unused_non_i32_param = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unused_non_i32_param_body = true },
    );
    defer invalid_unused_non_i32_param.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unused_non_i32_param.items));

    var invalid_table_limits = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .explicit_table_element_section = true, .invalid_table_max_below_min = true },
    );
    defer invalid_table_limits.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_table_limits.items));

    var immutable_global_set = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .immutable_i32_global_section = true, .invalid_required_global_set_index = 1 },
    );
    defer immutable_global_set.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(immutable_global_set.items));

    var invalid_memory_alignment = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_memory_alignment_index = 1 },
    );
    defer invalid_memory_alignment.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_memory_alignment.items));

    var invalid_memory_copy = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_memory_copy_index = 1 },
    );
    defer invalid_memory_copy.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_memory_copy.items));

    var invalid_non_i32_comparison = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_non_i32_comparison_index = 1 },
    );
    defer invalid_non_i32_comparison.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_non_i32_comparison.items));

    var invalid_prefixed_conversion = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_required_prefixed_conversion_index = 1 },
    );
    defer invalid_prefixed_conversion.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_prefixed_conversion.items));

    var trap_only_required_body = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .trap_only_required_body_index = 1 },
    );
    defer trap_only_required_body.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(trap_only_required_body.items));

    var invalid_extra_export_kind = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_extra_export_kind = true },
    );
    defer invalid_extra_export_kind.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_extra_export_kind.items));

    var invalid_extra_export_function_index = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_extra_export_function_index = true },
    );
    defer invalid_extra_export_function_index.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_extra_export_function_index.items));

    var invalid_unexported_function_type_index = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unexported_function_type_index = true },
    );
    defer invalid_unexported_function_type_index.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unexported_function_type_index.items));

    var duplicate_memory_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .duplicate_memory_section = true },
    );
    defer duplicate_memory_section.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(duplicate_memory_section.items));

    var start_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .start_section_function_index = 0 },
    );
    defer start_section.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(start_section.items));

    var data_before_code = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .data_section_before_code = true },
    );
    defer data_before_code.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(data_before_code.items));

    var invalid_unused_type = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_unused_type = true },
    );
    defer invalid_unused_type.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_unused_type.items));

    var malformed_global_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .malformed_global_section = true },
    );
    defer malformed_global_section.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(malformed_global_section.items));

    var overlong_global_i64_const = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .overlong_global_i64_const = true },
    );
    defer overlong_global_i64_const.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(overlong_global_i64_const.items));

    var global_get_const_expr = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_const_expr_global_get = true },
    );
    defer global_get_const_expr.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(global_get_const_expr.items));

    var i64_data_offset = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_data_i64_offset = true },
    );
    defer i64_data_offset.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(i64_data_offset.items));

    var explicit_table_element_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .explicit_table_element_section = true },
    );
    defer explicit_table_element_section.deinit(std.testing.allocator);
    const explicit_table_element_inspection = try world.Appliance.Abi.inspectWasm(explicit_table_element_section.items);
    try std.testing.expect(explicit_table_element_inspection.passed());

    var invalid_element_function_index = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_element_function_index = true },
    );
    defer invalid_element_function_index.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_element_function_index.items));

    var ref_func_element_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .ref_func_element_section = true },
    );
    defer ref_func_element_section.deinit(std.testing.allocator);
    const ref_func_element_inspection = try world.Appliance.Abi.inspectWasm(ref_func_element_section.items);
    try std.testing.expect(ref_func_element_inspection.passed());

    var invalid_ref_null_element_type = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_ref_null_element_type = true },
    );
    defer invalid_ref_null_element_type.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_ref_null_element_type.items));

    var invalid_data_memory_index = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .invalid_data_memory_index = true },
    );
    defer invalid_data_memory_index.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(invalid_data_memory_index.items));

    var multi_segment_data_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .multi_segment_data_section = true },
    );
    defer multi_segment_data_section.deinit(std.testing.allocator);
    const multi_segment_data_inspection = try world.Appliance.Abi.inspectWasm(multi_segment_data_section.items);
    try std.testing.expect(multi_segment_data_inspection.passed());

    var mismatched_data_count_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .mismatched_data_count_section = true },
    );
    defer mismatched_data_count_section.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Abi.inspectWasm(mismatched_data_count_section.items));

    var custom_section = try buildMinimalApplianceWasmWithOptions(
        world.Appliance.Abi.version,
        metadata_values,
        65,
        65,
        null,
        null,
        0,
        .{ .custom_section = true },
    );
    defer custom_section.deinit(std.testing.allocator);
    const custom_section_inspection = try world.Appliance.Abi.inspectWasm(custom_section.items);
    try std.testing.expect(custom_section_inspection.passed());
}

test "appliance profile presets are strict and identity-bearing" {
    const minimal = world.Appliance.Profile.minimal;
    const small = world.Appliance.Profile.wasm_small;
    const debug = world.Appliance.Profile.native_debug;
    const full = world.Appliance.Profile.full_evidence;

    try std.testing.expect(minimal.strict_closed_world);
    try std.testing.expect(small.strict_closed_world);
    try std.testing.expect(debug.strict_closed_world);
    try std.testing.expect(full.strict_closed_world);
    try std.testing.expect(!small.allow_manual_port_fallback);
    try std.testing.expect(debug.allow_manual_port_fallback);
    try std.testing.expect(full.require_archive_ack_before_continue);
    try std.testing.expect(minimal.fingerprint() != small.fingerprint());
    try std.testing.expect(small.fingerprint() != debug.fingerprint());
    try std.testing.expect(debug.fingerprint() != full.fingerprint());
}

test "appliance manifest derives supported execution modes from profile" {
    const SmallAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "mode-small",
    });
    const ReplayAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.replay_only,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "mode-replay",
    });
    const FullAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "mode-full",
    });
    const ActuatedSmallAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "mode-actuated-small",
    });
    const ActuatedFullAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "mode-actuated-full",
    });
    const small_modes = SmallAppliance.manifest().supported_execution_modes;
    try std.testing.expect(small_modes.supports(.fresh));
    try std.testing.expect(small_modes.supports(.replay));
    try std.testing.expect(!small_modes.supports(.verify));
    try std.testing.expect(!small_modes.supports(.audit));

    const replay_modes = ReplayAppliance.manifest().supported_execution_modes;
    try std.testing.expect(!replay_modes.supports(.fresh));
    try std.testing.expect(replay_modes.supports(.replay));
    try std.testing.expect(replay_modes.supports(.verify));
    try std.testing.expect(!replay_modes.supports(.audit));

    const full_modes = FullAppliance.manifest().supported_execution_modes;
    try std.testing.expect(full_modes.supports(.fresh));
    try std.testing.expect(full_modes.supports(.replay));
    try std.testing.expect(full_modes.supports(.verify));
    try std.testing.expect(full_modes.supports(.audit));

    const actuated_small = ActuatedSmallAppliance.manifest();
    try std.testing.expect(actuated_small.supported_execution_modes.supports(.fresh));
    try std.testing.expect(!actuated_small.supported_execution_modes.supports(.replay));
    try std.testing.expect(!actuated_small.required_host_capabilities.replay_evidence);

    const actuated_full = ActuatedFullAppliance.manifest();
    try std.testing.expect(actuated_full.supported_execution_modes.supports(.fresh));
    try std.testing.expect(!actuated_full.supported_execution_modes.supports(.replay));
    try std.testing.expect(!actuated_full.supported_execution_modes.supports(.verify));
    try std.testing.expect(!actuated_full.supported_execution_modes.supports(.audit));
    try std.testing.expect(!actuated_full.required_host_capabilities.replay_evidence);

    const replay_only_with_binding_modes = world.Appliance.ExecutionModeSet.forManifest(world.Appliance.Profile.replay_only, 1);
    try std.testing.expect(!replay_only_with_binding_modes.supports(.fresh));
    try std.testing.expect(!replay_only_with_binding_modes.supports(.replay));
    try std.testing.expect(!replay_only_with_binding_modes.supports(.verify));
    try std.testing.expect(!replay_only_with_binding_modes.supports(.audit));
}

test "appliance definition accepts static assembly-covered internal provider port" {
    const AgentAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.wasm_agent,
        .providers = .{fixtures.Strict.Target},
        .assembly_recipe = .{
            .covered_world_ports = .{ApplianceAgentToolImport.world_port_id},
            .link_plan_fingerprint = 0xA6E7_2001,
            .link_certificate_fingerprint = 0xA6E7_2002,
            .assembly_fingerprint = 0xA6E7_2003,
            .fabric_plan_fingerprints = .{0xA6E7_2004},
            .residual_import_set_fingerprint = 0xA6E7_2005,
        },
        .actuation_bindings = .{ApplianceAgentActuationBinding},
        .metadata = "agent-assembly-covered",
    });
    const report = AgentAppliance.definitionReport();
    const manifest = AgentAppliance.manifest();

    try std.testing.expectEqual(@as(usize, 2), report.root_world_port_count);
    try std.testing.expectEqual(@as(usize, 1), report.provider_count);
    try std.testing.expectEqual(@as(usize, 1), report.actuation_binding_count);
    try std.testing.expectEqual(@as(usize, 1), manifest.provider_target_ref_fingerprints.len);
    try std.testing.expectEqual(world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint, manifest.provider_target_ref_fingerprints[0]);
    try std.testing.expectEqual(@as(u64, 0xA6E7_2001), manifest.link_plan_fingerprint);
    try std.testing.expectEqual(@as(u64, 0xA6E7_2002), manifest.link_certificate_fingerprint);
    try std.testing.expectEqual(@as(u64, 0xA6E7_2003), manifest.assembly_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), manifest.fabric_plan_fingerprints.len);
    try std.testing.expectEqual(@as(u64, 0xA6E7_2004), manifest.fabric_plan_fingerprints[0]);
    try std.testing.expectEqual(@as(u64, 0xA6E7_2005), manifest.residual_import_set_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), manifest.actuation_binding_fingerprints.len);
    try manifest.validate();
}

test "appliance capacity presets validate and fingerprint deterministically" {
    const tiny = world.Appliance.Capacity.tiny_one_port;
    const small = world.Appliance.Capacity.wasm_small;
    const agent = world.Appliance.Capacity.wasm_agent;
    const native = world.Appliance.Capacity.large_native_test;

    try tiny.validate();
    try small.validate();
    try agent.validate();
    try native.validate();
    try std.testing.expectEqual(tiny.fingerprint(), world.Appliance.Capacity.tiny_one_port.fingerprint());
    try std.testing.expect(tiny.fingerprint() != small.fingerprint());
    try std.testing.expect(small.fingerprint() != agent.fingerprint());
    try std.testing.expect(agent.fingerprint() != native.fingerprint());

    var invalid = tiny;
    invalid.max_provider_runs = invalid.max_runs + 1;
    try std.testing.expectError(error.CapacityExceeded, invalid.validate());

    var overflowing = tiny;
    overflowing.max_runs = std.math.maxInt(usize);
    try std.testing.expectError(error.CapacityExceeded, overflowing.validate());

    var no_archive_buffer = tiny;
    no_archive_buffer.max_archive_append_bytes = 0;
    try no_archive_buffer.validate();
    try std.testing.expectError(error.CapacityExceeded, no_archive_buffer.validateForProfile(world.Appliance.Profile.wasm_small));
    try no_archive_buffer.validateForProfile(world.Appliance.Profile.minimal);

    var below_emitted_metadata = tiny;
    below_emitted_metadata.max_metadata_bytes = 0;
    try std.testing.expectError(error.CapacityExceeded, below_emitted_metadata.validateForProfile(world.Appliance.Profile.wasm_small));
}

test "appliance memory plan is bounded and derived from capacity and profile" {
    const small = world.Appliance.memoryPlan(world.Appliance.Capacity.wasm_small, world.Appliance.Profile.wasm_small);
    const same = world.Appliance.memoryPlan(world.Appliance.Capacity.wasm_small, world.Appliance.Profile.wasm_small);
    const debug = world.Appliance.memoryPlan(world.Appliance.Capacity.wasm_small, world.Appliance.Profile.native_debug);
    const agent = world.Appliance.memoryPlan(world.Appliance.Capacity.wasm_agent, world.Appliance.Profile.wasm_agent);

    try std.testing.expectEqual(small.plan_fingerprint, same.plan_fingerprint);
    try std.testing.expect(small.plan_fingerprint != debug.plan_fingerprint);
    try std.testing.expect(small.plan_fingerprint != agent.plan_fingerprint);
    try std.testing.expect(small.maximum_linear_memory_pages > 0);
    try std.testing.expectEqual(small.maximum_linear_memory_bytes, small.maximum_linear_memory_pages * 64 * 1024);
    try std.testing.expectEqual(small.maximum_linear_memory_bytes, world.Appliance.requiredMemoryBytes(world.Appliance.Capacity.wasm_small, world.Appliance.Profile.wasm_small));
}

test "appliance Define computes deterministic manifest before boot" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "strict-appliance",
    });
    const same = StrictAppliance.manifest();
    const again = StrictAppliance.manifest();
    const root_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);

    try same.validate();
    try std.testing.expectEqual(same.manifest_fingerprint, again.manifest_fingerprint);
    try std.testing.expectEqual(root_ref.target_ref_fingerprint, same.root_target_ref_fingerprint);
    try std.testing.expectEqual(root_ref.world_surface_fingerprint, same.root_world_surface_fingerprint);
    try std.testing.expectEqual(root_ref.target_certificate_fingerprint, same.root_target_certificate_fingerprint);
    try std.testing.expectEqual(StrictAppliance.memoryPlan().plan_fingerprint, same.memory_plan_fingerprint);
    try std.testing.expectEqual(StrictAppliance.requiredMemoryBytes(), StrictAppliance.memoryPlan().maximum_linear_memory_bytes);
    try std.testing.expect(!same.required_host_capabilities.actuation);
    try std.testing.expect(same.required_host_capabilities.capsule_retention);

    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    try std.testing.expect(PortsAppliance.manifest().required_host_capabilities.actuation);
    const paired = PortsAppliance.manifest();
    try paired.validate();

    var missing_descriptor = paired;
    missing_descriptor.actuation_descriptor_fingerprints = &.{};
    try std.testing.expectError(error.InvalidFrameEncoding, missing_descriptor.validate());

    var zero_binding = paired;
    var binding_fingerprints = [_]u64{0};
    zero_binding.actuation_binding_fingerprints = &binding_fingerprints;
    try std.testing.expectError(error.InvalidFrameEncoding, zero_binding.validate());
}

test "appliance command canonical encode decode and fingerprint stable" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .receiver_permit_fingerprint = 0xD010,
        .receiver_evidence_fingerprints = &.{ 0xD011, 0xD012 },
        .root_argument_image = "root-arg:v1",
        .metadata = "boot",
    });
    const different_argument = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "root-arg:v2",
        .metadata = "boot",
    });
    const different_receiver_refs = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .receiver_permit_fingerprint = 0xD010,
        .receiver_evidence_fingerprints = &.{0xD013},
        .root_argument_image = "root-arg:v1",
        .metadata = "boot",
    });

    try command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(command.command_fingerprint != different_argument.command_fingerprint);
    try std.testing.expect(command.command_fingerprint != different_receiver_refs.command_fingerprint);
    const encoded = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Appliance.Command.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try decoded.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectEqual(command.command_fingerprint, decoded.command_fingerprint);
    try std.testing.expectEqual(command.kind, decoded.kind);
    try std.testing.expectEqual(command.turn_sequence_number, decoded.turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, 0xD010), decoded.receiver_permit_fingerprint);
    try std.testing.expectEqualSlices(u64, command.receiver_evidence_fingerprints, decoded.receiver_evidence_fingerprints);
    try std.testing.expectEqualStrings(command.root_argument_image, decoded.root_argument_image);
    try std.testing.expectEqualStrings(command.metadata, decoded.metadata);

    const nonzero_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, nonzero_boot.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance command encodes decodes and validates host replies" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 0,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD300,
        .pending_port_fingerprint = 0xD301,
        .world_port_id = 0,
        .intent_fingerprint = 0xD302,
        .envelope_fingerprint = 0xD303,
        .decision_fingerprint = 0xD304,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD305,
    });
    const second_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 0,
        .request_ordinal = 1,
        .run_handle_fingerprint = 0xD310,
        .pending_port_fingerprint = 0xD311,
        .world_port_id = 0,
        .intent_fingerprint = 0xD312,
        .envelope_fingerprint = 0xD313,
        .decision_fingerprint = 0xD314,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD315,
    });
    const reply_ack = applianceRetentionAckFor(0xD307, "reply-retained");
    const reply_without_ack = applianceHostReplyFor(request, 0xD306);
    const reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = reply_without_ack.target_host_request_fingerprint,
        .outcome = reply_without_ack.outcome,
        .retention_ack = reply_ack,
        .metadata = "reply-ack",
    });
    const second_reply = applianceHostReplyFor(second_request, 0xD316);
    const ack = reply_ack;
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{reply},
        .retention_ack = ack,
        .metadata = "reply",
    });

    try command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    const encoded = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Appliance.Command.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try decoded.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectEqual(command.command_fingerprint, decoded.command_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.host_replies.len);
    try std.testing.expectEqual(reply.reply_fingerprint, decoded.host_replies[0].reply_fingerprint);
    try std.testing.expectEqual(world.Appliance.HostResponseKind.frame_value_image, decoded.host_replies[0].outcome.response_kind);
    try std.testing.expectEqualStrings("", decoded.host_replies[0].outcome.response_bytes);
    try std.testing.expectEqualStrings("host-claim:fixture", decoded.host_replies[0].outcome.host_evidence_bytes);
    try std.testing.expect(decoded.host_replies[0].retention_ack != null);
    try std.testing.expectEqual(reply_ack.ack_fingerprint, decoded.host_replies[0].retention_ack_fingerprint.?);
    try std.testing.expectEqual(reply_ack.ack_fingerprint, decoded.host_replies[0].retention_ack.?.ack_fingerprint);
    try std.testing.expectEqualStrings("reply-retained", decoded.host_replies[0].retention_ack.?.metadata);
    try decoded.host_replies[0].validate(&.{request}, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(decoded.retention_ack != null);
    try std.testing.expectEqual(ack.ack_fingerprint, decoded.retention_ack.?.ack_fingerprint);
    try decoded.retention_ack.?.validate(null, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectEqualStrings(command.metadata, decoded.metadata);

    const mismatched_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = second_request.request_fingerprint,
        .outcome = reply_without_ack.outcome,
    });
    const mismatched_reply_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{mismatched_reply},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_reply_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const canonical_order = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{ reply, second_reply },
    });
    try canonical_order.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small);

    const duplicate_reply_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{ reply, reply },
    });
    try std.testing.expectError(error.DuplicateReply, duplicate_reply_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small));

    const replay_reply_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .execution_mode = .replay,
        .host_replies = &.{reply},
    });
    try std.testing.expectError(error.InvalidMode, replay_reply_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small));

    const byte_response_outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = 0xD330,
        .response_kind = .bytes,
        .response_bytes = "command-bytes",
    });
    const byte_response_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = byte_response_outcome,
    });
    const byte_response_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{byte_response_reply},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, byte_response_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small));

    const fingerprint_only_ack_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = reply_without_ack.target_host_request_fingerprint,
        .outcome = reply_without_ack.outcome,
        .retention_ack_fingerprint = reply_ack.ack_fingerprint,
        .metadata = "ack-ref-without-evidence",
    });
    const fingerprint_only_ack_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = 0xD308,
        .host_replies = &.{fingerprint_only_ack_reply},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, fingerprint_only_ack_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small));

    const boot_ack_command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .retention_ack = ack,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, boot_ack_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small));
}

test "appliance command encodes decodes and validates restore checkpoint" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 4,
        .capsule_fingerprint = 0xD320,
        .previous_turn_receipt_fingerprint = 0xD321,
        .metadata = "restore-point",
    });
    const command = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 5,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = checkpoint,
        .metadata = "restore",
    });

    try command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    const encoded = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Appliance.Command.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try decoded.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectEqual(command.command_fingerprint, decoded.command_fingerprint);
    try std.testing.expect(decoded.restore_checkpoint != null);
    try std.testing.expectEqual(checkpoint.checkpoint_fingerprint, decoded.restore_checkpoint.?.checkpoint_fingerprint);
    try std.testing.expect(decoded.restore_checkpoint.?.capsule_image_ref_fingerprint != null);
    try std.testing.expectEqualStrings(checkpoint.metadata, decoded.restore_checkpoint.?.metadata);

    const restore_ack_without_pending = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 5,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .retention_ack = applianceRetentionAckFor(0xD330, "orphan-ack"),
        .restore_checkpoint = checkpoint,
    });
    try std.testing.expectError(error.ArchiveParentMismatch, restore_ack_without_pending.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const pending_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 4,
        .capsule_fingerprint = 0xD320,
        .pending_archive_append_batch_fingerprint = 0xD331,
        .pending_archive_resulting_cursor = world.Continuity.Chronicle.Cursor.initial(),
        .previous_turn_receipt_fingerprint = 0xD321,
    });
    const restore_ack_for_other_append = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 5,
        .previous_turn_receipt_fingerprint = pending_checkpoint.previous_turn_receipt_fingerprint,
        .retention_ack = applianceRetentionAckFor(0xD332, "wrong-ack"),
        .restore_checkpoint = pending_checkpoint,
    });
    try std.testing.expectError(error.ArchiveParentMismatch, restore_ack_for_other_append.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance command rejects wrong manifest oversized metadata and malformed bytes" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint + 1,
        .turn_sequence_number = 0,
    });
    try std.testing.expectError(error.WrongManifest, command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const non_boot_argument = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "not-boot",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, non_boot_argument.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const restore_without_checkpoint = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
    });
    try std.testing.expectError(error.RestoreRejected, restore_without_checkpoint.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const boot_with_previous_receipt = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .previous_turn_receipt_fingerprint = 0xD020,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, boot_with_previous_receipt.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const restore_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 4,
        .capsule_fingerprint = 0xD024,
        .previous_turn_receipt_fingerprint = 0xD025,
    });
    const restore_wrong_sequence = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = restore_checkpoint.turn_sequence_number,
        .previous_turn_receipt_fingerprint = restore_checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = restore_checkpoint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, restore_wrong_sequence.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const restore_wrong_previous = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = restore_checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = 0xD026,
        .restore_checkpoint = restore_checkpoint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, restore_wrong_previous.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const reply_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 5,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD027,
        .pending_port_fingerprint = 0xD028,
        .intent_fingerprint = 0xD029,
        .envelope_fingerprint = 0xD02A,
        .decision_fingerprint = 0xD02B,
        .expected_response_descriptor_fingerprint = 0xD02C,
        .idempotency_key_fingerprint = 0xD02D,
    });
    const restore_reply_without_pending = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = restore_checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = restore_checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{applianceHostReplyFor(reply_request, 0xD02E)},
        .restore_checkpoint = restore_checkpoint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, restore_reply_without_pending.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const continue_without_previous_receipt = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, continue_without_previous_receipt.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const zero_receiver_permit = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .receiver_permit_fingerprint = 0,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, zero_receiver_permit.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const zero_receiver_evidence = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .receiver_evidence_fingerprints = &.{0},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, zero_receiver_evidence.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_metadata_bytes = 1;
    const oversized = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .metadata = "too large",
    });
    try std.testing.expectError(error.CapacityExceeded, oversized.validate(manifest.manifest_fingerprint, tight));
    const oversized_receiver_evidence = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .receiver_evidence_fingerprints = &.{0xD022},
    });
    try std.testing.expectError(error.CapacityExceeded, oversized_receiver_evidence.validate(manifest.manifest_fingerprint, tight));
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Command.decode(std.testing.allocator, &.{ 0, 1, 2 }));

    const valid = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const valid_bytes = try valid.encode(std.testing.allocator);
    defer std.testing.allocator.free(valid_bytes);
    var malformed_len = try std.testing.allocator.dupe(u8, valid_bytes);
    defer std.testing.allocator.free(malformed_len);
    const root_argument_len_offset = 44;
    try std.testing.expect(malformed_len.len > root_argument_len_offset + 4);
    std.mem.writeInt(u32, malformed_len[root_argument_len_offset..][0..4], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Command.decode(std.testing.allocator, malformed_len));
}

test "appliance checkpoint carries capsule image ref or bounded bytes" {
    const manifest_fingerprint: u64 = 0xD030;
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .capsule_fingerprint = 0xD031,
        .previous_turn_receipt_fingerprint = 0xD02F,
    });
    try checkpoint.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(checkpoint.capsule_image_ref_fingerprint != null);

    const with_bytes = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .capsule_fingerprint = 0xD031,
        .capsule_image_bytes = "capsule-image:v1",
        .previous_turn_receipt_fingerprint = 0xD02F,
    });
    try with_bytes.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(checkpoint.checkpoint_fingerprint != with_bytes.checkpoint_fingerprint);

    var missing_source = checkpoint;
    missing_source.capsule_image_ref_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_source.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var zero_ref = checkpoint;
    zero_ref.capsule_image_ref_fingerprint = 0;
    try std.testing.expectError(error.InvalidFrameEncoding, zero_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var forged_ref = checkpoint;
    forged_ref.capsule_image_ref_fingerprint = checkpoint.capsule_image_ref_fingerprint.? + 1;
    try std.testing.expectError(error.InvalidFrameEncoding, forged_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const runnable_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .capsule_fingerprint = 0xD035,
        .core_state = .runnable,
        .previous_turn_receipt_fingerprint = 0xD034,
    });
    try runnable_checkpoint.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    var runnable_payload: std.ArrayList(u8) = .empty;
    defer runnable_payload.deinit(std.testing.allocator);
    try runnable_checkpoint.encode(&runnable_payload, std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Checkpoint.decodeArchivePayload(std.testing.allocator, runnable_payload.items));
    const runnable_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 10,
        .restore_checkpoint = runnable_checkpoint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runnable_restore.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const uninitialized_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .capsule_fingerprint = 0xD03A,
        .core_state = .uninitialized,
    });
    try uninitialized_checkpoint.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    const uninitialized_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 10,
        .restore_checkpoint = uninitialized_checkpoint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, uninitialized_restore.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const inspected_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .command_fingerprint = 0xD038,
        .resulting_capsule_fingerprint = runnable_checkpoint.capsule_fingerprint,
        .status = .inspected,
    });
    const runnable_inspected_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .source_state_fingerprint = 0xD039,
        .resulting_state_fingerprint = 0xD039,
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
        }),
        .status = .inspected,
        .checkpoint = runnable_checkpoint,
        .turn_receipt = inspected_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runnable_inspected_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const failed_inspected_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .capsule_fingerprint = 0xD03B,
        .core_state = .failed,
        .previous_turn_receipt_fingerprint = 0xD03C,
    });
    const mismatched_inspected_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 9,
        .source_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 9, 0xD03C),
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 9, 0xD03C),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
        }),
        .status = .inspected,
        .checkpoint = failed_inspected_checkpoint,
        .turn_receipt = inspected_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_inspected_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const missing_prior_receipt = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD03D,
        .core_state = .completed,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, missing_prior_receipt.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const uninitialized_with_prior_state = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD036,
        .core_state = .uninitialized,
        .previous_turn_receipt_fingerprint = 0xD037,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, uninitialized_with_prior_state.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_capsule_bytes = 4;
    try std.testing.expectError(error.CapacityExceeded, with_bytes.validate(manifest_fingerprint, tight));

    const archive_cursor = world.Continuity.Chronicle.Cursor.initial();
    const archive_anchor = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 10,
        .capsule_fingerprint = 0xD032,
        .latest_archive_moment_fingerprint = 0xD033,
        .latest_archive_seal_fingerprint = 0xD034,
        .latest_chronicle_cursor_fingerprint = archive_cursor.cursor_fingerprint,
        .latest_archive_cursor = archive_cursor,
        .previous_turn_receipt_fingerprint = 0xD03E,
    });
    try archive_anchor.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);

    var missing_seal = archive_anchor;
    missing_seal.latest_archive_seal_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_seal.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var missing_cursor = archive_anchor;
    missing_cursor.latest_chronicle_cursor_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_cursor.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var missing_authoritative_cursor = archive_anchor;
    missing_authoritative_cursor.latest_archive_cursor = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_authoritative_cursor.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var orphan_authoritative_cursor = checkpoint;
    orphan_authoritative_cursor.latest_archive_cursor = archive_cursor;
    try std.testing.expectError(error.InvalidFrameEncoding, orphan_authoritative_cursor.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const pending_without_cursor = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 11,
        .capsule_fingerprint = 0xD036,
        .pending_archive_append_batch_fingerprint = 0xD037,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, pending_without_cursor.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance borrowed checkpoint and receipt deinit are no-ops" {
    const manifest_fingerprint: u64 = 0xD038;
    var checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD039,
        .previous_turn_receipt_fingerprint = 0xD03E,
        .metadata = "borrowed-checkpoint",
    });
    checkpoint.deinit(std.testing.allocator);
    try checkpoint.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);

    const applied = [_]u64{0xD03A};
    const emitted = [_]u64{0xD03B};
    var receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD03C,
        .applied_host_reply_fingerprints = &applied,
        .emitted_host_request_fingerprints = &emitted,
        .resulting_capsule_fingerprint = 0xD03D,
        .status = .needs_host,
    });
    receipt.deinit(std.testing.allocator);
    try receipt.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
}

test "appliance Core submit validates command before mutating state" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    try std.testing.expect(!@hasDecl(world.Appliance.Core, "init"));
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, core.state);
    try std.testing.expect(core.pending_command != null);

    const before_state = core.state;
    const stale = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
    });
    const stale_bytes = try stale.encode(std.testing.allocator);
    defer std.testing.allocator.free(stale_bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, core.submit(stale_bytes));
    try std.testing.expectEqual(before_state, core.state);

    const wrong_manifest = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = manifest.manifest_fingerprint + 1,
        .turn_sequence_number = 0,
    });
    const wrong_manifest_bytes = try wrong_manifest.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_manifest_bytes);
    try std.testing.expectError(error.WrongManifest, core.submit(wrong_manifest_bytes));
    try std.testing.expectEqual(before_state, core.state);

    try std.testing.expectError(error.InvalidFrameEncoding, core.submit(&.{ 1, 2, 3 }));
    try std.testing.expectEqual(before_state, core.state);

    var mismatched_capacity_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_small,
    );
    defer mismatched_capacity_core.reset();
    try std.testing.expectError(error.InvalidCommand, mismatched_capacity_core.submit(boot_bytes));
    try std.testing.expect(mismatched_capacity_core.pending_command == null);

    var invalid_manifest = manifest;
    invalid_manifest.actuation_binding_fingerprints = &.{0xD0A0};
    var invalid_manifest_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        invalid_manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer invalid_manifest_core.reset();
    try std.testing.expectError(error.InvalidFrameEncoding, invalid_manifest_core.submit(boot_bytes));
    try std.testing.expect(invalid_manifest_core.pending_command == null);
}

test "appliance Core rejects unsupported execution mode before mutation" {
    const SmallAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "unsupported-verify",
    });
    const manifest = SmallAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        SmallAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const verify_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .verify,
    });
    const verify_boot_bytes = try verify_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(verify_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, core.submit(verify_boot_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, core.state);
    try std.testing.expect(core.pending_command == null);
    try std.testing.expectEqual(@as(usize, 0), core.readOutput().len);

    const FullAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "supported-verify",
    });
    const full_manifest = FullAppliance.manifest();
    var full_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        full_manifest,
        FullAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer full_core.reset();
    const supported_verify_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = full_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .verify,
    });
    const supported_verify_boot_bytes = try supported_verify_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(supported_verify_boot_bytes);
    try full_core.submit(supported_verify_boot_bytes);
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, full_core.state);
    try std.testing.expect(full_core.pending_command != null);
}

test "appliance Core validates continue host replies before completion" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const static_requirement = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, ApplianceActuationBinding.world_port_id);
    try std.testing.expectEqual(@as(usize, 1), manifest.actuation_payload_value_ref_fingerprints.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.actuation_response_value_ref_fingerprints.len);
    try std.testing.expectEqual(static_requirement.payload_value_ref_fingerprint.?, manifest.actuation_payload_value_ref_fingerprints[0]);
    try std.testing.expectEqual(static_requirement.response_value_ref_fingerprint.?, manifest.actuation_response_value_ref_fingerprints[0]);
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expect(core.outstanding_host_request != null);
    const outstanding = core.outstanding_host_request.?;
    try std.testing.expectEqual(static_requirement.payload_value_ref_fingerprint, outstanding.payload_value_ref_fingerprint);
    try std.testing.expectEqual(static_requirement.response_value_ref_fingerprint, outstanding.expected_response_value_ref_fingerprint);
    const first_output = try std.testing.allocator.dupe(u8, core.readOutput());
    defer std.testing.allocator.free(first_output);
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;

    const skipped_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
    });
    const skipped_continue_bytes = try skipped_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(skipped_continue_bytes);
    try std.testing.expectError(error.UnknownRequest, core.submit(skipped_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expect(std.mem.eql(u8, first_output, core.readOutput()));

    var wrong_reply = applianceHostReplyFor(outstanding, 0xD400);
    wrong_reply.target_host_request_fingerprint += 1;
    wrong_reply.reply_fingerprint = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = wrong_reply.target_host_request_fingerprint,
        .outcome = wrong_reply.outcome,
    }).reply_fingerprint;
    const wrong_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{wrong_reply},
    });
    const wrong_continue_bytes = try wrong_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_continue_bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, core.submit(wrong_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expect(std.mem.eql(u8, first_output, core.readOutput()));

    const reply = applianceHostReplyFor(outstanding, 0xD401);
    const replay_reply_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .execution_mode = .replay,
        .host_replies = &.{reply},
    });
    const replay_reply_continue_bytes = try replay_reply_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(replay_reply_continue_bytes);
    try std.testing.expectError(error.InvalidMode, core.submit(replay_reply_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expect(std.mem.eql(u8, first_output, core.readOutput()));

    const valid_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
    });
    const valid_continue_bytes = try valid_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(valid_continue_bytes);
    try core.submit(valid_continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expect(core.outstanding_host_request == null);
    try std.testing.expect(core.previous_turn_receipt_fingerprint != null);
    try std.testing.expect(!std.mem.eql(u8, first_output, core.readOutput()));
    var terminal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer terminal_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.turn_receipt.applied_host_reply_fingerprints.len);
    try std.testing.expectEqual(reply.reply_fingerprint, terminal_output.turn_receipt.applied_host_reply_fingerprints[0]);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != 0);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != reply.outcome.host_evidence_fingerprint.?);
}

test "appliance Core rejects byte HostReply at active request boundary" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "byte-response-start",
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    const outstanding = core.outstanding_host_request orelse return error.StaleTurn;
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;

    const byte_outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = outstanding.request_fingerprint,
        .intent_fingerprint = outstanding.intent_fingerprint,
        .envelope_fingerprint = outstanding.envelope_fingerprint,
        .idempotency_key_fingerprint = outstanding.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = 0xD4B7,
        .response_kind = .bytes,
        .response_bytes = "raw-bytes",
        .host_evidence_fingerprint = 0xD4B8,
        .host_evidence_bytes = "host-claim:bytes",
        .attempt_number = 1,
    });
    const byte_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = outstanding.request_fingerprint,
        .outcome = byte_outcome,
    });
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{byte_reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);

    try std.testing.expectError(error.InvalidFrameEncoding, core.submit(continue_bytes));
}

test "appliance terminal HostReply validation uses active capacity" {
    const roomy_capacity = comptime blk: {
        var capacity = world.Appliance.Capacity.large_native_test;
        capacity.max_metadata_bytes = 128 * 1024;
        break :blk capacity;
    };
    const RoomyAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = roomy_capacity,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = RoomyAppliance.manifest();

    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        RoomyAppliance.memoryPlan(),
        roomy_capacity,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "roomy-start",
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    const outstanding = core.outstanding_host_request orelse return error.StaleTurn;
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;

    const roomy_metadata = [_]u8{'m'} ** (70 * 1024);
    var response_image = try world.Frame.ValueImage.fromCanonicalBytes(
        std.testing.allocator,
        null,
        outstanding.expected_response_value_ref_fingerprint,
        outstanding.expected_response_schema_ref_fingerprint,
        "roomy-response",
        false,
    );
    defer response_image.deinit(std.testing.allocator);
    const response_image_bytes = try response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_image_bytes);
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = outstanding.request_fingerprint,
        .intent_fingerprint = outstanding.intent_fingerprint,
        .envelope_fingerprint = outstanding.envelope_fingerprint,
        .idempotency_key_fingerprint = outstanding.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_image.value_image_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = response_image_bytes,
        .host_evidence_fingerprint = 0xD4F2,
        .host_evidence_bytes = "host-claim:fixture",
        .attempt_number = 1,
        .metadata = roomy_metadata[0..],
    });
    const reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = outstanding.request_fingerprint,
        .outcome = outcome,
    });
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);

    try core.submit(continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    var terminal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        roomy_capacity,
    );
    defer terminal_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.turn_receipt.applied_host_reply_fingerprints.len);
    try std.testing.expectEqual(reply.reply_fingerprint, terminal_output.turn_receipt.applied_host_reply_fingerprints[0]);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != 0);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != reply.outcome.host_evidence_fingerprint.?);
}

test "appliance Core pending and deferred HostReplies keep request outstanding" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();

    for ([_]world.Appliance.HostOutcomeStatus{ .pending, .deferred }) |nonterminal_status| {
        var core = world.Appliance.Core.initWithCapacity(
            std.testing.allocator,
            manifest,
            PortsAppliance.memoryPlan(),
            world.Appliance.Capacity.tiny_one_port,
        );
        defer core.reset();

        const boot = world.Appliance.Command.init(.{
            .kind = .boot,
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = 0,
        });
        const boot_bytes = try boot.encode(std.testing.allocator);
        defer std.testing.allocator.free(boot_bytes);
        try core.submit(boot_bytes);
        try core.executeTurn();
        const outstanding = core.outstanding_host_request orelse return error.UnknownRequest;
        const first_receipt = core.previous_turn_receipt_fingerprint.?;
        const first_output = try std.testing.allocator.dupe(u8, core.readOutput());
        defer std.testing.allocator.free(first_output);

        const nonterminal_reply = applianceHostReplyWithStatusFor(outstanding, nonterminal_status);
        const pending_continue = world.Appliance.Command.init(.{
            .kind = .@"continue",
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = 1,
            .previous_turn_receipt_fingerprint = first_receipt,
            .host_replies = &.{nonterminal_reply},
        });
        const pending_continue_bytes = try pending_continue.encode(std.testing.allocator);
        defer std.testing.allocator.free(pending_continue_bytes);
        try core.submit(pending_continue_bytes);
        try core.executeTurn();

        try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
        try std.testing.expect(core.outstanding_host_request != null);
        try std.testing.expectEqual(outstanding.request_fingerprint, core.outstanding_host_request.?.request_fingerprint);
        try std.testing.expectEqual(@as(u64, 1), core.current_turn_sequence_number);
        try std.testing.expect(core.previous_turn_receipt_fingerprint != null);
        try std.testing.expect(core.previous_turn_receipt_fingerprint.? != first_receipt);
        try std.testing.expect(!std.mem.eql(u8, first_output, core.readOutput()));

        const terminal_reply = applianceHostReplyFor(core.outstanding_host_request.?, 0xD402);
        const terminal_continue = world.Appliance.Command.init(.{
            .kind = .@"continue",
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = 2,
            .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
            .host_replies = &.{terminal_reply},
        });
        const terminal_continue_bytes = try terminal_continue.encode(std.testing.allocator);
        defer std.testing.allocator.free(terminal_continue_bytes);
        try core.submit(terminal_continue_bytes);
        try core.executeTurn();

        try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
        try std.testing.expect(core.outstanding_host_request == null);

        const inspect = world.Appliance.Command.init(.{
            .kind = .inspect,
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = core.current_turn_sequence_number,
            .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        });
        const inspect_bytes = try inspect.encode(std.testing.allocator);
        defer std.testing.allocator.free(inspect_bytes);
        try core.submit(inspect_bytes);
        try core.executeTurn();
        try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);

        const post_inspect_continue = world.Appliance.Command.init(.{
            .kind = .@"continue",
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = core.current_turn_sequence_number + 1,
            .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        });
        const post_inspect_continue_bytes = try post_inspect_continue.encode(std.testing.allocator);
        defer std.testing.allocator.free(post_inspect_continue_bytes);
        try std.testing.expectError(error.StaleTurn, core.submit(post_inspect_continue_bytes));
        try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    }
}

test "appliance Core failed HostReply produces failed turn" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    const outstanding = core.outstanding_host_request orelse return error.UnknownRequest;
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;

    const failed_reply = applianceHostReplyWithStatusFor(outstanding, .failed);
    const failed_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{failed_reply},
    });
    const failed_continue_bytes = try failed_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(failed_continue_bytes);
    try core.submit(failed_continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.failed, core.state);
    var output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.failed, output.status);
    try std.testing.expectEqual(@as(?u64, null), output.root_result_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), output.quiescence.failed_run_count);

    const terminal_again = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
    });
    const terminal_again_bytes = try terminal_again.encode(std.testing.allocator);
    defer std.testing.allocator.free(terminal_again_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(terminal_again_bytes));
}

test "appliance Core rejected HostReply preserves fresh call receipt evidence" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    const outstanding = core.outstanding_host_request orelse return error.UnknownRequest;
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;

    const rejected_reply = applianceHostReplyWithStatusFor(outstanding, .rejected);
    const rejected_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{rejected_reply},
    });
    const rejected_continue_bytes = try rejected_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(rejected_continue_bytes);
    try core.submit(rejected_continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.failed, core.state);
    var output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.blocked, output.status);
    try std.testing.expectEqual(@as(usize, 1), output.finalized_actuation_receipt_fingerprints.len);

    const commit_value = world.Actuation.Commit.init(.{
        .intent_fingerprint = outstanding.intent_fingerprint,
        .decision_fingerprint = outstanding.decision_fingerprint,
        .envelope_fingerprint = outstanding.envelope_fingerprint,
        .idempotency_key_fingerprint = outstanding.idempotency_key_fingerprint,
        .attempt_number = rejected_reply.outcome.attempt_number,
        .status = .rejected,
        .fresh_called = true,
    });
    try commit_value.validate();
    const response = world.Actuation.Response.init(.{
        .intent_fingerprint = outstanding.intent_fingerprint,
        .commit_fingerprint = commit_value.commit_fingerprint,
        .actuator_ref_fingerprint = outstanding.actuator_ref_fingerprint,
        .world_port_id = outstanding.world_port_id,
        .request_fingerprint = outstanding.request_fingerprint,
        .status = .rejected,
        .response_kind = .@"resume",
    });
    const receipt = world.Actuation.Receipt.init(.{
        .intent_fingerprint = outstanding.intent_fingerprint,
        .envelope_fingerprint = outstanding.envelope_fingerprint,
        .decision_fingerprint = outstanding.decision_fingerprint,
        .commit_fingerprint = commit_value.commit_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .frame_response_fingerprint = response.frame_response_fingerprint,
        .response_value_image_fingerprint = response.value_image_fingerprint,
        .recorded_response_fingerprint = response.recorded_response_fingerprint,
        .actuator_ref_fingerprint = outstanding.actuator_ref_fingerprint,
        .idempotency_key_fingerprint = outstanding.idempotency_key_fingerprint,
        .request_fingerprint = outstanding.request_fingerprint,
        .target_ref_fingerprint = outstanding.target_ref_fingerprint,
        .world_surface_fingerprint = outstanding.world_surface_fingerprint,
        .world_port_id = outstanding.world_port_id,
        .class = outstanding.actuation_class,
        .mode = .fresh,
        .fresh_called = true,
        .rejected = true,
        .attempt_number = commit_value.attempt_number,
    });
    const finalized = world.Actuation.Finalized.init(.{
        .commit_value = commit_value,
        .response = response,
        .receipt = receipt,
    });
    try finalized.validate();
    try std.testing.expectEqual(finalized.receipt.receipt_fingerprint, output.finalized_actuation_receipt_fingerprints[0]);
}

test "appliance Core restore clears stale failed status for checkpoint continuation" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var failed_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer failed_core.reset();

    const failed_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const failed_boot_bytes = try failed_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(failed_boot_bytes);
    try failed_core.submit(failed_boot_bytes);
    try failed_core.executeTurn();
    const failed_outstanding = failed_core.outstanding_host_request orelse return error.UnknownRequest;
    const failed_reply = applianceHostReplyWithStatusFor(failed_outstanding, .failed);
    const failed_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = failed_core.previous_turn_receipt_fingerprint,
        .host_replies = &.{failed_reply},
    });
    const failed_continue_bytes = try failed_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(failed_continue_bytes);
    try failed_core.submit(failed_continue_bytes);
    try failed_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.failed, failed_core.state);

    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();
    const boot_bytes = try failed_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();
    const outstanding = resident.outstanding_host_request orelse return error.UnknownRequest;
    var checkpoint_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        resident.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer checkpoint_output.deinit(std.testing.allocator);

    try failed_core.restore(checkpoint_output.checkpoint);
    const reply = applianceHostReplyFor(outstanding, 0xD530);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = checkpoint_output.checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try failed_core.submit(continue_bytes);
    try failed_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, failed_core.state);
}

test "appliance Core restore preserves terminal checkpoint status" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD531,
        .previous_turn_receipt_fingerprint = 0xD532,
        .core_state = .completed,
    });
    try core.restore(checkpoint);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(continue_bytes));

    const restore_command = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = checkpoint,
    });
    const restore_bytes = try restore_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_bytes);
    var restore_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restore_core.reset();
    try restore_core.submit(restore_bytes);
    try restore_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, restore_core.state);

    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const ports_manifest = PortsAppliance.manifest();
    var ports_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        ports_manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer ports_core.reset();
    const ports_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = ports_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const ports_boot_bytes = try ports_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(ports_boot_bytes);
    try ports_core.submit(ports_boot_bytes);
    try ports_core.executeTurn();
    const ports_request = ports_core.outstanding_host_request.?;
    const ports_reply = applianceHostReplyFor(ports_request, 0xD533);
    const ports_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = ports_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = ports_core.previous_turn_receipt_fingerprint,
        .host_replies = &.{ports_reply},
    });
    const ports_continue_bytes = try ports_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(ports_continue_bytes);
    try ports_core.submit(ports_continue_bytes);
    try ports_core.executeTurn();
    var ports_terminal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        ports_core.readOutput(),
        ports_manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer ports_terminal_output.deinit(std.testing.allocator);

    var ports_restore_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        ports_manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer ports_restore_core.reset();
    const ports_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = ports_manifest.manifest_fingerprint,
        .turn_sequence_number = ports_terminal_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = ports_terminal_output.checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = ports_terminal_output.checkpoint,
    });
    const ports_restore_bytes = try ports_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(ports_restore_bytes);
    try ports_restore_core.submit(ports_restore_bytes);
    try ports_restore_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, ports_restore_core.state);
    try std.testing.expect(ports_restore_core.outstanding_host_request == null);

    const MinimalAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.minimal,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const minimal_manifest = MinimalAppliance.manifest();
    var minimal_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        minimal_manifest,
        MinimalAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer minimal_core.reset();
    const minimal_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = minimal_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const minimal_boot_bytes = try minimal_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(minimal_boot_bytes);
    try minimal_core.submit(minimal_boot_bytes);
    try minimal_core.executeTurn();
    var minimal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        minimal_core.readOutput(),
        minimal_manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer minimal_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?u64, null), minimal_output.checkpoint.pending_archive_append_batch_fingerprint);

    const minimal_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = minimal_manifest.manifest_fingerprint,
        .turn_sequence_number = minimal_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = minimal_output.checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = minimal_output.checkpoint,
    });
    const minimal_restore_bytes = try minimal_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(minimal_restore_bytes);
    var minimal_restore_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        minimal_manifest,
        MinimalAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer minimal_restore_core.reset();
    try minimal_restore_core.submit(minimal_restore_bytes);
    try minimal_restore_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, minimal_restore_core.state);
    try std.testing.expectEqual(@as(?u64, null), minimal_restore_core.pending_archive_append_batch_fingerprint);
}

test "appliance Core restore rehydrates outstanding HostRequest for continuation" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, resident.state);
    const outstanding = resident.outstanding_host_request orelse return error.UnknownRequest;
    const prior_receipt = resident.previous_turn_receipt_fingerprint.?;
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = resident.current_turn_sequence_number,
        .capsule_fingerprint = 0xD500,
        .pending_archive_append_batch_fingerprint = resident.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = resident.pending_archive_resulting_cursor,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .outstanding_host_requests = &.{outstanding},
    });
    try checkpoint.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    var checkpoint_bytes: std.ArrayList(u8) = .empty;
    defer checkpoint_bytes.deinit(std.testing.allocator);
    try checkpoint.encode(&checkpoint_bytes, std.testing.allocator);
    var owned_checkpoint = try world.Appliance.Checkpoint.decode(
        std.testing.allocator,
        checkpoint_bytes.items,
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer owned_checkpoint.deinit(std.testing.allocator);

    const reply = applianceHostReplyFor(outstanding, 0xD501);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);

    try resident.submit(continue_bytes);
    try resident.executeTurn();
    const resident_output = try std.testing.allocator.dupe(u8, resident.readOutput());
    defer std.testing.allocator.free(resident_output);

    var restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restored.reset();
    try restored.restore(owned_checkpoint);
    try std.testing.expect(restored.outstanding_host_request != null);
    try std.testing.expectEqual(outstanding.request_fingerprint, restored.outstanding_host_request.?.request_fingerprint);
    try restored.submit(continue_bytes);
    try restored.executeTurn();

    try std.testing.expectEqual(world.Appliance.CoreState.completed, restored.state);
    try std.testing.expect(restored.outstanding_host_request == null);
    try std.testing.expectEqualSlices(u8, resident_output, restored.readOutput());
}

test "appliance Core continuation source state chains from prior output" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    var boot_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer boot_output.deinit(std.testing.allocator);

    const outstanding = core.outstanding_host_request orelse return error.UnknownRequest;
    const reply = applianceHostReplyFor(outstanding, 0xD5B1);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &.{reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try core.submit(continue_bytes);
    try core.executeTurn();
    var continue_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer continue_output.deinit(std.testing.allocator);

    try std.testing.expectEqual(boot_output.resulting_state_fingerprint, continue_output.source_state_fingerprint);
}

test "appliance Core rejects mixed terminal and nonterminal replies" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.wasm_small,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_small,
    );
    defer core.reset();

    const requests = [_]world.Appliance.HostRequest{
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 1,
            .request_ordinal = 0,
            .run_handle_fingerprint = 0xD5C0,
            .pending_port_fingerprint = 0xD5C1,
            .world_port_id = 0,
            .intent_fingerprint = 0xD5C2,
            .envelope_fingerprint = 0xD5C3,
            .decision_fingerprint = 0xD5C4,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xD5C5,
            .metadata = "terminal",
        }),
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 1,
            .request_ordinal = 1,
            .run_handle_fingerprint = 0xD5C6,
            .pending_port_fingerprint = 0xD5C7,
            .world_port_id = 0,
            .intent_fingerprint = 0xD5C8,
            .envelope_fingerprint = 0xD5C9,
            .decision_fingerprint = 0xD5CA,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xD5CB,
            .allowed_response_statuses = world.Actuation.ResponseStatusSet.all,
            .metadata = "pending",
        }),
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 1,
            .request_ordinal = 2,
            .run_handle_fingerprint = 0xD5CE,
            .pending_port_fingerprint = 0xD5CF,
            .world_port_id = 0,
            .intent_fingerprint = 0xD5D0,
            .envelope_fingerprint = 0xD5D1,
            .decision_fingerprint = 0xD5D2,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xD5D3,
            .metadata = "unreplied",
        }),
    };
    core.state = .waiting_host;
    core.current_turn_sequence_number = 1;
    core.previous_turn_receipt_fingerprint = 0xD5CC;
    core.outstanding_host_requests = requests[0..];

    const terminal_reply = applianceHostReplyFor(requests[0], 0xD5CD);
    const pending_reply = applianceHostReplyWithStatusFor(requests[1], .pending);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &.{ terminal_reply, pending_reply },
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try std.testing.expectError(error.InvalidCommand, core.submit(continue_bytes));
}

test "appliance Core failed host reply dominates partial outstanding replies" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.wasm_small,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_small,
    );
    defer core.reset();

    const requests = [_]world.Appliance.HostRequest{
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 1,
            .request_ordinal = 0,
            .run_handle_fingerprint = 0xD5E0,
            .pending_port_fingerprint = 0xD5E1,
            .world_port_id = 0,
            .intent_fingerprint = 0xD5E2,
            .envelope_fingerprint = 0xD5E3,
            .decision_fingerprint = 0xD5E4,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xD5E5,
            .allowed_response_statuses = world.Actuation.ResponseStatusSet.all,
            .metadata = "failed",
        }),
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 1,
            .request_ordinal = 1,
            .run_handle_fingerprint = 0xD5E6,
            .pending_port_fingerprint = 0xD5E7,
            .world_port_id = 0,
            .intent_fingerprint = 0xD5E8,
            .envelope_fingerprint = 0xD5E9,
            .decision_fingerprint = 0xD5EA,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xD5EB,
            .metadata = "unreplied",
        }),
    };
    core.state = .waiting_host;
    core.current_turn_sequence_number = 1;
    core.previous_turn_receipt_fingerprint = 0xD5EC;
    core.outstanding_host_requests = requests[0..];

    const failed_reply = applianceHostReplyWithStatusFor(requests[0], .failed);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &.{failed_reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try core.submit(continue_bytes);
    try core.executeTurn();

    var output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.wasm_small,
    );
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.failed, output.status);
    try std.testing.expectEqual(@as(usize, 1), output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expectEqual(@as(usize, 0), output.host_requests.len);
    try std.testing.expectEqual(@as(usize, 0), output.checkpoint.outstanding_host_requests.len);
    try std.testing.expectEqual(@as(usize, 0), core.outstanding_host_requests.len);
    try std.testing.expectEqual(world.Appliance.CoreState.failed, core.state);
}

test "appliance Core restore with partial terminal replies keeps only unreplied requests" {
    const AgentAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.wasm_agent,
        .actuation_bindings = .{
            ApplianceAgentActuationBinding,
            ApplianceAgentToolActuationBinding,
        },
    });
    const manifest = AgentAppliance.manifest();
    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        AgentAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_agent,
    );
    defer resident.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "agent:prompt",
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();

    var boot_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        resident.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.wasm_agent,
    );
    defer boot_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), boot_output.checkpoint.outstanding_host_requests.len);

    const first = boot_output.checkpoint.outstanding_host_requests[0];
    const second = boot_output.checkpoint.outstanding_host_requests[1];
    const restore_reply = applianceHostReplyFor(first, 0xD5ED);
    const restore_command = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = boot_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{restore_reply},
        .restore_checkpoint = boot_output.checkpoint,
    });
    const restore_bytes = try restore_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_bytes);

    var restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        AgentAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_agent,
    );
    defer restored.reset();
    try restored.submit(restore_bytes);
    try restored.executeTurn();

    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, restored.state);
    try std.testing.expectEqual(@as(usize, 1), restored.outstanding_host_requests.len);
    try std.testing.expectEqual(second.request_fingerprint, restored.outstanding_host_requests[0].request_fingerprint);

    var restore_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        restored.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.wasm_agent,
    );
    defer restore_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.needs_host, restore_output.status);
    try std.testing.expectEqual(@as(usize, 1), restore_output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expectEqual(@as(usize, 1), restore_output.host_requests.len);
    try std.testing.expectEqual(second.request_fingerprint, restore_output.host_requests[0].request_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), restore_output.checkpoint.outstanding_host_requests.len);
    try std.testing.expectEqual(second.request_fingerprint, restore_output.checkpoint.outstanding_host_requests[0].request_fingerprint);
}

test "appliance Core emitted checkpoint carries current TurnReceipt for restore" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();
    var boot_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        resident.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer boot_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(boot_output.turn_receipt.receipt_fingerprint, boot_output.checkpoint.previous_turn_receipt_fingerprint.?);

    const outstanding = boot_output.host_requests[0];
    const reply = applianceHostReplyFor(outstanding, 0xD5A1);
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{reply},
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);

    var restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restored.reset();
    try restored.restore(boot_output.checkpoint);
    const replay_restore_reply = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .execution_mode = .replay,
        .host_replies = &.{reply},
        .restore_checkpoint = boot_output.checkpoint,
    });
    const replay_restore_reply_bytes = try replay_restore_reply.encode(std.testing.allocator);
    defer std.testing.allocator.free(replay_restore_reply_bytes);
    try std.testing.expectError(error.InvalidMode, restored.submit(replay_restore_reply_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, restored.state);

    try restored.submit(continue_bytes);
    try restored.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, restored.state);

    const stale_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = boot_output.checkpoint,
    });
    const stale_restore_bytes = try stale_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(stale_restore_bytes);
    try std.testing.expectError(error.StaleTurn, restored.submit(stale_restore_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.completed, restored.state);
}

test "appliance Core restore command applies checkpoint and replies without side channel" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();
    const outstanding = resident.outstanding_host_request orelse return error.UnknownRequest;
    const prior_receipt = resident.previous_turn_receipt_fingerprint.?;
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = resident.current_turn_sequence_number,
        .capsule_fingerprint = 0xD510,
        .pending_archive_append_batch_fingerprint = resident.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = resident.pending_archive_resulting_cursor,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .outstanding_host_requests = &.{outstanding},
    });
    const forged_outstanding = world.Appliance.HostRequest.init(.{
        .turn_sequence_number = outstanding.turn_sequence_number,
        .request_ordinal = outstanding.request_ordinal,
        .run_handle_fingerprint = outstanding.run_handle_fingerprint,
        .pending_port_fingerprint = outstanding.pending_port_fingerprint,
        .world_port_id = outstanding.world_port_id,
        .target_ref_fingerprint = outstanding.target_ref_fingerprint,
        .world_surface_fingerprint = outstanding.world_surface_fingerprint,
        .actuator_ref_fingerprint = outstanding.actuator_ref_fingerprint,
        .actuation_class = outstanding.actuation_class,
        .allowed_response_statuses = outstanding.allowed_response_statuses,
        .intent_fingerprint = outstanding.intent_fingerprint,
        .envelope_fingerprint = outstanding.envelope_fingerprint,
        .decision_fingerprint = outstanding.decision_fingerprint,
        .expected_response_descriptor_fingerprint = outstanding.expected_response_descriptor_fingerprint,
        .idempotency_key_fingerprint = outstanding.idempotency_key_fingerprint,
        .supervision_ref_fingerprint = outstanding.supervision_ref_fingerprint,
        .metadata = outstanding.metadata,
        .frame_request_bytes = outstanding.frame_request_bytes,
        .payload_value_image_bytes = outstanding.payload_value_image_bytes,
        .payload_value_ref_fingerprint = outstanding.payload_value_ref_fingerprint,
        .payload_schema_ref_fingerprint = outstanding.payload_schema_ref_fingerprint,
        .expected_response_value_ref_fingerprint = null,
        .expected_response_schema_ref_fingerprint = null,
        .prepared_actuation_evidence_bytes = outstanding.prepared_actuation_evidence_bytes,
        .idempotency_key_bytes = outstanding.idempotency_key_bytes,
    });
    const forged_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint.turn_sequence_number,
        .capsule_fingerprint = checkpoint.capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = checkpoint.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = checkpoint.pending_archive_resulting_cursor,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .outstanding_host_requests = &.{forged_outstanding},
    });
    const forged_reply = applianceHostReplyFor(forged_outstanding, 0xD513);
    const forged_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{forged_reply},
        .restore_checkpoint = forged_checkpoint,
    });
    const forged_restore_bytes = try forged_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_restore_bytes);
    var forged_restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer forged_restored.reset();
    try std.testing.expectError(error.InvalidFrameEncoding, forged_restored.submit(forged_restore_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, forged_restored.state);

    const reply = applianceHostReplyFor(outstanding, 0xD511);
    const restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
        .restore_checkpoint = checkpoint,
    });
    const restore_bytes = try restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_bytes);

    const restore_reemit = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .restore_checkpoint = checkpoint,
    });
    const restore_reemit_bytes = try restore_reemit.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_reemit_bytes);

    const orphaned_restore_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = resident.current_turn_sequence_number,
        .capsule_fingerprint = 0xD512,
        .pending_archive_append_batch_fingerprint = resident.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = resident.pending_archive_resulting_cursor,
        .previous_turn_receipt_fingerprint = prior_receipt,
    });
    const orphaned_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .restore_checkpoint = orphaned_restore_checkpoint,
    });
    const orphaned_restore_bytes = try orphaned_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(orphaned_restore_bytes);
    try std.testing.expectError(error.StaleTurn, resident.submit(orphaned_restore_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, resident.state);
    try std.testing.expect(resident.outstanding_host_request != null);

    var reemit_restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer reemit_restored.reset();
    try reemit_restored.submit(restore_reemit_bytes);
    try reemit_restored.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, reemit_restored.state);
    var reemit_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        reemit_restored.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer reemit_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.needs_host, reemit_output.status);
    try std.testing.expectEqual(@as(usize, 1), reemit_output.host_requests.len);
    try std.testing.expectEqual(outstanding.request_fingerprint, reemit_output.host_requests[0].request_fingerprint);

    var restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restored.reset();
    try restored.submit(restore_bytes);
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, restored.state);
    try std.testing.expectEqual(@as(u64, 0), restored.current_turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, null), restored.previous_turn_receipt_fingerprint);
    try std.testing.expect(restored.outstanding_host_request == null);
    try std.testing.expectEqual(@as(?u64, null), restored.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), restored.readOutput().len);
    try restored.executeTurn();

    try std.testing.expectEqual(world.Appliance.CoreState.completed, restored.state);
    try std.testing.expect(restored.outstanding_host_request == null);
    try std.testing.expect(restored.readOutput().len > 0);
}

test "appliance command rejects restore checkpoint cardinalities Core cannot execute" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.wasm_small,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const requests = [_]world.Appliance.HostRequest{
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 0,
            .request_ordinal = 0,
            .run_handle_fingerprint = 0xE210,
            .pending_port_fingerprint = 0xE211,
            .intent_fingerprint = 0xE212,
            .envelope_fingerprint = 0xE213,
            .decision_fingerprint = 0xE214,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xE215,
        }),
        applianceSyntheticHostRequest(.{
            .turn_sequence_number = 0,
            .request_ordinal = 1,
            .run_handle_fingerprint = 0xE216,
            .pending_port_fingerprint = 0xE217,
            .intent_fingerprint = 0xE218,
            .envelope_fingerprint = 0xE219,
            .decision_fingerprint = 0xE21A,
            .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
            .idempotency_key_fingerprint = 0xE21B,
        }),
    };
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .capsule_fingerprint = 0xE21C,
        .core_state = .waiting_host,
        .previous_turn_receipt_fingerprint = 0xE21D,
        .outstanding_host_requests = requests[0..],
    });
    const restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = checkpoint,
    });
    try restore.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small);
}

test "appliance Core rejects waiting-host restore without actuation bindings" {
    const MinimalAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.minimal,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = MinimalAppliance.manifest();
    const forged_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 0,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xE120,
        .pending_port_fingerprint = 0xE121,
        .intent_fingerprint = 0xE122,
        .envelope_fingerprint = 0xE123,
        .decision_fingerprint = 0xE124,
        .expected_response_descriptor_fingerprint = 0xE125,
        .idempotency_key_fingerprint = 0xE126,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .capsule_fingerprint = 0xE127,
        .core_state = .waiting_host,
        .previous_turn_receipt_fingerprint = 0xE128,
        .outstanding_host_requests = &.{forged_request},
    });

    var direct_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        MinimalAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer direct_core.reset();
    try std.testing.expectError(error.InvalidFrameEncoding, direct_core.restore(checkpoint));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, direct_core.state);
    try std.testing.expect(direct_core.outstanding_host_request == null);

    const restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = checkpoint,
    });
    const restore_bytes = try restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_bytes);

    var command_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        MinimalAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer command_core.reset();
    try std.testing.expectError(error.InvalidFrameEncoding, command_core.submit(restore_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, command_core.state);
    try std.testing.expect(command_core.outstanding_host_request == null);
}

test "appliance Core validates command RetentionAck before advancing" {
    const ArchiveAckAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = ArchiveAckAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expect(core.pending_archive_append_batch_fingerprint != null);
    const pending_archive = core.pending_archive_append_batch_fingerprint.?;
    const prior_receipt = core.previous_turn_receipt_fingerprint.?;
    var boot_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer boot_output.deinit(std.testing.allocator);

    const missing_pending_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = boot_output.checkpoint.manifest_fingerprint,
        .turn_sequence_number = boot_output.checkpoint.turn_sequence_number,
        .capsule_fingerprint = boot_output.checkpoint.capsule_fingerprint,
        .capsule_image_ref_fingerprint = boot_output.checkpoint.capsule_image_ref_fingerprint,
        .capsule_image_bytes = boot_output.checkpoint.capsule_image_bytes,
        .latest_archive_moment_fingerprint = boot_output.checkpoint.latest_archive_moment_fingerprint,
        .latest_archive_seal_fingerprint = boot_output.checkpoint.latest_archive_seal_fingerprint,
        .latest_chronicle_cursor_fingerprint = boot_output.checkpoint.latest_chronicle_cursor_fingerprint,
        .latest_archive_cursor = boot_output.checkpoint.latest_archive_cursor,
        .core_state = boot_output.checkpoint.core_state,
        .previous_turn_receipt_fingerprint = boot_output.checkpoint.previous_turn_receipt_fingerprint,
        .outstanding_host_requests = boot_output.checkpoint.outstanding_host_requests,
        .execution_mode = boot_output.checkpoint.execution_mode,
        .metadata = boot_output.checkpoint.metadata,
    });
    const mismatched_pending_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = boot_output.manifest_fingerprint,
        .turn_sequence_number = boot_output.turn_sequence_number,
        .source_state_fingerprint = boot_output.source_state_fingerprint,
        .resulting_state_fingerprint = boot_output.resulting_state_fingerprint,
        .quiescence = boot_output.quiescence,
        .status = boot_output.status,
        .host_requests = boot_output.host_requests,
        .finalized_actuation_receipt_fingerprints = boot_output.finalized_actuation_receipt_fingerprints,
        .root_result_fingerprint = boot_output.root_result_fingerprint,
        .run_receipt_fingerprint = boot_output.run_receipt_fingerprint,
        .archive_append_batch_fingerprint = boot_output.archive_append_batch_fingerprint,
        .checkpoint = missing_pending_checkpoint,
        .turn_receipt = boot_output.turn_receipt,
        .blocker_count = boot_output.blocker_count,
        .warning_count = boot_output.warning_count,
        .diagnostic_metadata = boot_output.diagnostic_metadata,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_pending_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const mismatched_state_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = boot_output.manifest_fingerprint,
        .turn_sequence_number = boot_output.turn_sequence_number,
        .source_state_fingerprint = boot_output.source_state_fingerprint,
        .resulting_state_fingerprint = boot_output.resulting_state_fingerprint + 1,
        .quiescence = boot_output.quiescence,
        .status = boot_output.status,
        .host_requests = boot_output.host_requests,
        .finalized_actuation_receipt_fingerprints = boot_output.finalized_actuation_receipt_fingerprints,
        .root_result_fingerprint = boot_output.root_result_fingerprint,
        .run_receipt_fingerprint = boot_output.run_receipt_fingerprint,
        .archive_append_batch_fingerprint = boot_output.archive_append_batch_fingerprint,
        .checkpoint = boot_output.checkpoint,
        .turn_receipt = boot_output.turn_receipt,
        .blocker_count = boot_output.blocker_count,
        .warning_count = boot_output.warning_count,
        .diagnostic_metadata = boot_output.diagnostic_metadata,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_state_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var recomputed_plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        std.testing.allocator,
        archive.image.latestCursor(),
        boot_output,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer recomputed_plan.deinit();
    try std.testing.expectEqual(pending_archive, recomputed_plan.append_batch.append_batch_fingerprint);

    const missing_ack = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
    });
    const missing_ack_bytes = try missing_ack.encode(std.testing.allocator);
    defer std.testing.allocator.free(missing_ack_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(missing_ack_bytes));
    try std.testing.expectEqual(@as(?u64, pending_archive), core.pending_archive_append_batch_fingerprint);

    const stale_ack = applianceRetentionAckFor(pending_archive, "stale");
    var no_pending_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer no_pending_core.reset();
    no_pending_core.state = .completed;
    no_pending_core.current_turn_sequence_number = 0;
    no_pending_core.previous_turn_receipt_fingerprint = prior_receipt;
    const stale_ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .retention_ack = stale_ack,
    });
    const stale_ack_continue_bytes = try stale_ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(stale_ack_continue_bytes);
    try std.testing.expectError(error.ArchiveParentMismatch, no_pending_core.submit(stale_ack_continue_bytes));

    var restore_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restore_core.reset();
    const stale_ack_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .restore_checkpoint = boot_output.checkpoint,
        .retention_ack = stale_ack,
    });
    const stale_ack_restore_bytes = try stale_ack_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(stale_ack_restore_bytes);
    try std.testing.expectError(error.ArchiveParentMismatch, restore_core.submit(stale_ack_restore_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, restore_core.state);
    try std.testing.expectEqual(@as(?u64, null), restore_core.pending_archive_append_batch_fingerprint);

    const pending_ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = pending_archive,
        .resulting_moment_fingerprint = pending_archive ^ 0xA11C_1001,
        .resulting_seal_fingerprint = pending_archive ^ 0xA11C_1002,
        .resulting_chronicle_cursor_fingerprint = pending_archive ^ 0xA11C_1003,
        .host_claim_status = .pending,
        .metadata = "not-yet-retained",
    });
    const pending_ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .retention_ack = pending_ack,
    });
    const pending_ack_continue_bytes = try pending_ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(pending_ack_continue_bytes);
    try std.testing.expectError(error.ArchiveParentMismatch, core.submit(pending_ack_continue_bytes));
    try std.testing.expectEqual(@as(?u64, pending_archive), core.pending_archive_append_batch_fingerprint);

    const ack = try applianceRetentionAckForPendingCore(core, "retained");
    var fingerprint_conflict_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer fingerprint_conflict_core.reset();
    const outstanding_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD40A,
        .pending_port_fingerprint = 0xD40B,
        .intent_fingerprint = 0xD40C,
        .envelope_fingerprint = 0xD40D,
        .decision_fingerprint = 0xD40E,
        .expected_response_descriptor_fingerprint = 0xD40F,
        .idempotency_key_fingerprint = 0xD410,
    });
    const fingerprint_only_reply_base = applianceHostReplyFor(outstanding_request, 0xD411);
    const conflicting_ack = applianceRetentionAckFor(pending_archive, "conflicting-fingerprint-only");
    const fingerprint_only_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = fingerprint_only_reply_base.target_host_request_fingerprint,
        .outcome = fingerprint_only_reply_base.outcome,
        .retention_ack_fingerprint = conflicting_ack.ack_fingerprint,
        .metadata = "fingerprint-only-conflict",
    });
    fingerprint_conflict_core.state = .waiting_host;
    fingerprint_conflict_core.current_turn_sequence_number = 0;
    fingerprint_conflict_core.previous_turn_receipt_fingerprint = prior_receipt;
    fingerprint_conflict_core.outstanding_host_request = outstanding_request;
    fingerprint_conflict_core.pending_archive_append_batch_fingerprint = pending_archive;
    fingerprint_conflict_core.pending_archive_resulting_cursor = core.pending_archive_resulting_cursor;
    const fingerprint_conflict_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{fingerprint_only_reply},
        .retention_ack = ack,
    });
    const fingerprint_conflict_continue_bytes = try fingerprint_conflict_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(fingerprint_conflict_continue_bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, fingerprint_conflict_core.submit(fingerprint_conflict_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, fingerprint_conflict_core.state);

    const valid_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .retention_ack = ack,
    });
    const valid_continue_bytes = try valid_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(valid_continue_bytes);
    try core.submit(valid_continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expectEqual(@as(?u64, null), core.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(?u64, ack.resulting_moment_fingerprint), core.latest_archive_moment_fingerprint);
    try std.testing.expectEqual(@as(?u64, ack.resulting_seal_fingerprint), core.latest_archive_seal_fingerprint);
    try std.testing.expectEqual(@as(?u64, ack.resulting_chronicle_cursor_fingerprint), core.latest_chronicle_cursor_fingerprint);
}

test "appliance Core applies HostReply RetentionAck before archive-gated advancement" {
    const ArchiveAckAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = ArchiveAckAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();

    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    const pending_archive = core.pending_archive_append_batch_fingerprint orelse return error.ArchiveParentMismatch;
    const prior_receipt = core.previous_turn_receipt_fingerprint orelse return error.StaleTurn;
    const request = core.outstanding_host_request orelse return error.UnknownRequest;

    const pending_ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = pending_archive,
        .resulting_moment_fingerprint = pending_archive ^ 0xA11C_3001,
        .resulting_seal_fingerprint = pending_archive ^ 0xA11C_3002,
        .resulting_chronicle_cursor_fingerprint = pending_archive ^ 0xA11C_3003,
        .host_claim_status = .pending,
        .metadata = "reply-pending",
    });
    const wrong_reply_without_ack = applianceHostReplyFor(request, 0xD460);
    const wrong_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = wrong_reply_without_ack.target_host_request_fingerprint,
        .outcome = wrong_reply_without_ack.outcome,
        .retention_ack = pending_ack,
    });
    const wrong_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{wrong_reply},
    });
    const wrong_continue_bytes = try wrong_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_continue_bytes);
    try std.testing.expectError(error.ArchiveParentMismatch, core.submit(wrong_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(@as(?u64, pending_archive), core.pending_archive_append_batch_fingerprint);
    try std.testing.expect(core.outstanding_host_request != null);

    const ack = try applianceRetentionAckForPendingCore(core, "reply-retained");
    const reply_without_ack = applianceHostReplyFor(request, 0xD461);
    const reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = reply_without_ack.target_host_request_fingerprint,
        .outcome = reply_without_ack.outcome,
        .retention_ack = ack,
    });
    const conflicting_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
        .retention_ack = pending_ack,
    });
    const conflicting_continue_bytes = try conflicting_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(conflicting_continue_bytes);
    try std.testing.expectError(error.ArchiveParentMismatch, core.submit(conflicting_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(@as(?u64, pending_archive), core.pending_archive_append_batch_fingerprint);

    const valid_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
    });
    const valid_continue_bytes = try valid_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(valid_continue_bytes);
    try core.submit(valid_continue_bytes);
    try core.executeTurn();

    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expect(core.outstanding_host_request == null);
    try std.testing.expect(core.pending_archive_append_batch_fingerprint != null);
    try std.testing.expect(core.pending_archive_append_batch_fingerprint.? != pending_archive);
    try std.testing.expectEqual(@as(?u64, ack.resulting_moment_fingerprint), core.latest_archive_moment_fingerprint);
    try std.testing.expectEqual(@as(?u64, ack.resulting_seal_fingerprint), core.latest_archive_seal_fingerprint);
    try std.testing.expectEqual(@as(?u64, ack.resulting_chronicle_cursor_fingerprint), core.latest_chronicle_cursor_fingerprint);

    var terminal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer terminal_output.deinit(std.testing.allocator);
    const terminal_archive_ack = try applianceRetentionAckForPendingCore(core, "terminal-retained");
    const terminal_again = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .retention_ack = terminal_archive_ack,
    });
    const terminal_again_bytes = try terminal_again.encode(std.testing.allocator);
    defer std.testing.allocator.free(terminal_again_bytes);
    try core.submit(terminal_again_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expectEqual(@as(?u64, null), core.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_moment_fingerprint), core.latest_archive_moment_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_seal_fingerprint), core.latest_archive_seal_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_chronicle_cursor_fingerprint), core.latest_chronicle_cursor_fingerprint);

    var restore_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAckAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restore_core.reset();
    const terminal_restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = terminal_output.checkpoint.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = terminal_output.checkpoint.previous_turn_receipt_fingerprint,
        .restore_checkpoint = terminal_output.checkpoint,
        .retention_ack = terminal_archive_ack,
    });
    const terminal_restore_bytes = try terminal_restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(terminal_restore_bytes);
    try restore_core.submit(terminal_restore_bytes);
    try restore_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, restore_core.state);
    try std.testing.expectEqual(@as(?u64, null), restore_core.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_moment_fingerprint), restore_core.latest_archive_moment_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_seal_fingerprint), restore_core.latest_archive_seal_fingerprint);
    try std.testing.expectEqual(@as(?u64, terminal_archive_ack.resulting_chronicle_cursor_fingerprint), restore_core.latest_chronicle_cursor_fingerprint);
}

test "appliance Core accepts replay evidence with verified transcript support" {
    const ReplayAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = ReplayAppliance.manifest();
    try std.testing.expect(!manifest.supported_execution_modes.supports(.replay));
    try std.testing.expect(!manifest.required_host_capabilities.replay_evidence);

    var fresh_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer fresh_core.reset();
    const fresh_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .fresh,
    });
    const fresh_boot_bytes = try fresh_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(fresh_boot_bytes);
    try fresh_core.submit(fresh_boot_bytes);
    try fresh_core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, fresh_core.state);
    var fresh_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        fresh_core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer fresh_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.needs_host, fresh_output.status);
    try std.testing.expectEqual(@as(usize, 1), fresh_output.host_requests.len);
    try std.testing.expectEqualStrings("", fresh_output.diagnostic_metadata);

    const fresh_request = fresh_core.outstanding_host_request orelse return error.UnknownRequest;
    const fresh_reply = applianceHostReplyFor(fresh_request, 0xD501);
    const fresh_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = fresh_core.previous_turn_receipt_fingerprint,
        .host_replies = &.{fresh_reply},
    });
    const fresh_continue_bytes = try fresh_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(fresh_continue_bytes);
    try fresh_core.submit(fresh_continue_bytes);
    try fresh_core.executeTurn();
    var terminal_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        fresh_core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer terminal_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.completed, terminal_output.status);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.turn_receipt.applied_host_reply_fingerprints.len);
    try std.testing.expectEqual(fresh_reply.reply_fingerprint, terminal_output.turn_receipt.applied_host_reply_fingerprints[0]);
    try std.testing.expectEqual(@as(usize, 1), terminal_output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != 0);
    try std.testing.expect(terminal_output.finalized_actuation_receipt_fingerprints[0] != fresh_reply.outcome.host_evidence_fingerprint.?);
    try std.testing.expectEqualStrings("", terminal_output.diagnostic_metadata);

    var incomplete_replay_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer incomplete_replay_core.reset();
    const incomplete_replay_evidence = [_]u64{fresh_output.turn_receipt.receipt_fingerprint};
    const incomplete_replay_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &incomplete_replay_evidence,
    });
    const incomplete_replay_boot_bytes = try incomplete_replay_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(incomplete_replay_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, incomplete_replay_core.submit(incomplete_replay_boot_bytes));

    var replay_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer replay_core.reset();
    const replay_evidence = [_]u64{
        terminal_output.turn_receipt.receipt_fingerprint,
        terminal_output.finalized_actuation_receipt_fingerprints[0],
    };
    const replay_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &replay_evidence,
    });
    const replay_boot_bytes = try replay_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(replay_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, replay_core.submit(replay_boot_bytes));

    var replay_native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer replay_native.deinit();
    replay_native.core.executable_image_fingerprint = 0xD501_E001;
    const native_wire_boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const native_wire_boot_bytes = try native_wire_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(native_wire_boot_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, replay_native.submitTurn(native_wire_boot_bytes));
    var native_fresh_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        replay_native.core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer native_fresh_output.deinit(std.testing.allocator);
    var native_parent_closure = try world.Appliance.TurnClosure.decode(std.testing.allocator, replay_native.last_closure_bytes);
    defer native_parent_closure.deinit(std.testing.allocator);
    try native_parent_closure.validate(std.testing.allocator, .{
        .expected_executable_image_fingerprint = replay_native.core.executable_image_fingerprint,
        .expected_manifest_fingerprint = manifest.manifest_fingerprint,
        .limits = .archive_decode,
    });
    const native_replay_evidence = [_]u64{
        native_fresh_output.turn_receipt.receipt_fingerprint,
        manifest.actuation_binding_fingerprints[0],
    };
    const replay_wire_continue = world.Appliance.Wire.TurnInput.init(.{
        .operation = .replay,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = native_fresh_output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = native_fresh_output.turn_receipt.receipt_fingerprint,
        .receiver_evidence_fingerprints = &native_replay_evidence,
    });
    const replay_wire_continue_bytes = try replay_wire_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(replay_wire_continue_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.invalid_command, replay_native.submitTurn(replay_wire_continue_bytes));

    var forged_replay_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer forged_replay_core.reset();
    try forged_replay_core.submit(fresh_boot_bytes);
    try forged_replay_core.executeTurn();
    var forged_fresh_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        forged_replay_core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer forged_fresh_output.deinit(std.testing.allocator);
    const forged_replay_evidence = [_]u64{
        forged_fresh_output.turn_receipt.receipt_fingerprint,
        manifest.actuation_binding_fingerprints[0] +% 1,
    };
    const forged_replay = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = forged_fresh_output.turn_sequence_number + 1,
        .previous_turn_receipt_fingerprint = forged_fresh_output.turn_receipt.receipt_fingerprint,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &forged_replay_evidence,
    });
    const forged_replay_bytes = try forged_replay.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_replay_bytes);
    try std.testing.expectError(error.InvalidCommand, forged_replay_core.submit(forged_replay_bytes));

    var duplicate_replay_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer duplicate_replay_core.reset();
    const duplicate_replay_evidence = [_]u64{
        terminal_output.turn_receipt.receipt_fingerprint,
        terminal_output.turn_receipt.receipt_fingerprint,
    };
    const duplicate_replay_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
        .receiver_evidence_fingerprints = &duplicate_replay_evidence,
    });
    const duplicate_replay_boot_bytes = try duplicate_replay_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(duplicate_replay_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, duplicate_replay_core.submit(duplicate_replay_boot_bytes));

    var missing_evidence_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ReplayAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer missing_evidence_core.reset();
    const missing_evidence_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
    });
    const missing_evidence_boot_bytes = try missing_evidence_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(missing_evidence_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, missing_evidence_core.submit(missing_evidence_boot_bytes));

    const FullEvidenceAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "actuated-full-evidence-replay-rejected",
    });
    const full_manifest = FullEvidenceAppliance.manifest();
    try std.testing.expect(!full_manifest.supported_execution_modes.supports(.replay));
    try std.testing.expect(!full_manifest.supported_execution_modes.supports(.verify));
    try std.testing.expect(!full_manifest.supported_execution_modes.supports(.audit));
    var verify_core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        full_manifest,
        FullEvidenceAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer verify_core.reset();
    const verify_evidence = [_]u64{ 0xD5F0, 0xD5F1 };
    const verify_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = full_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .verify,
        .receiver_evidence_fingerprints = &verify_evidence,
    });
    const verify_boot_bytes = try verify_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(verify_boot_bytes);
    try std.testing.expectError(error.InvalidCommand, verify_core.submit(verify_boot_bytes));
}

test "appliance Core rejects non-strict archive append advance without ack" {
    const ArchiveAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = ArchiveAppliance.manifest();

    var unacknowledged = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer unacknowledged.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try unacknowledged.submit(boot_bytes);
    try unacknowledged.executeTurn();
    try std.testing.expect(unacknowledged.pending_archive_append_batch_fingerprint != null);
    const first_pending_archive = unacknowledged.pending_archive_append_batch_fingerprint.?;
    const prior_receipt = unacknowledged.previous_turn_receipt_fingerprint.?;

    const no_ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
    });
    const no_ack_continue_bytes = try no_ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(no_ack_continue_bytes);
    try std.testing.expectError(error.StaleTurn, unacknowledged.submit(no_ack_continue_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.completed, unacknowledged.state);
    try std.testing.expectEqual(@as(?u64, first_pending_archive), unacknowledged.pending_archive_append_batch_fingerprint);

    const late_ack = try applianceRetentionAckForPendingCore(unacknowledged, "late-retained");
    const late_ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = unacknowledged.previous_turn_receipt_fingerprint,
        .retention_ack = late_ack,
    });
    const late_ack_continue_bytes = try late_ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(late_ack_continue_bytes);
    try unacknowledged.submit(late_ack_continue_bytes);
    try unacknowledged.executeTurn();
    try std.testing.expectEqual(@as(?u64, null), unacknowledged.pending_archive_append_batch_fingerprint);

    var acknowledged = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        ArchiveAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer acknowledged.reset();
    try acknowledged.submit(boot_bytes);
    try acknowledged.executeTurn();
    const ack = try applianceRetentionAckForPendingCore(acknowledged, "retained");
    const ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = acknowledged.previous_turn_receipt_fingerprint,
        .retention_ack = ack,
    });
    const ack_continue_bytes = try ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(ack_continue_bytes);
    try acknowledged.submit(ack_continue_bytes);
    try acknowledged.executeTurn();

    var acknowledged_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        acknowledged.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer acknowledged_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), acknowledged_output.warning_count);
    try std.testing.expectEqual(@as(usize, 0), acknowledged_output.quiescence.warning_count);
    try std.testing.expectEqual(@as(usize, 0), acknowledged_output.turn_receipt.warning_count);

    const ActuatedArchiveAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const actuated_manifest = ActuatedArchiveAppliance.manifest();
    var actuated = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        actuated_manifest,
        ActuatedArchiveAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer actuated.reset();
    const actuated_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = actuated_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const actuated_boot_bytes = try actuated_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(actuated_boot_bytes);
    try actuated.submit(actuated_boot_bytes);
    try actuated.executeTurn();
    const outstanding = actuated.outstanding_host_request orelse return error.StaleTurn;
    const actuated_reply = applianceHostReplyFor(outstanding, 0xD6A0);
    const actuated_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = actuated_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = actuated.previous_turn_receipt_fingerprint,
        .host_replies = &.{actuated_reply},
    });
    const actuated_continue_bytes = try actuated_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(actuated_continue_bytes);
    try actuated.submit(actuated_continue_bytes);
    try actuated.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, actuated.state);
    try std.testing.expect(actuated.pending_archive_append_batch_fingerprint != null);

    const actuated_no_ack = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = actuated_manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = actuated.previous_turn_receipt_fingerprint,
    });
    const actuated_no_ack_bytes = try actuated_no_ack.encode(std.testing.allocator);
    defer std.testing.allocator.free(actuated_no_ack_bytes);
    try std.testing.expectError(error.StaleTurn, actuated.submit(actuated_no_ack_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.completed, actuated.state);

    var actuated_ack = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        actuated_manifest,
        ActuatedArchiveAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer actuated_ack.reset();
    try actuated_ack.submit(actuated_boot_bytes);
    try actuated_ack.executeTurn();
    const ack_outstanding = actuated_ack.outstanding_host_request orelse return error.StaleTurn;
    const ack_reply = applianceHostReplyFor(ack_outstanding, 0xD6A1);
    const ack_reply_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = actuated_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = actuated_ack.previous_turn_receipt_fingerprint,
        .host_replies = &.{ack_reply},
    });
    const ack_reply_continue_bytes = try ack_reply_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(ack_reply_continue_bytes);
    try actuated_ack.submit(ack_reply_continue_bytes);
    try actuated_ack.executeTurn();
    const terminal_ack = try applianceRetentionAckForPendingCore(actuated_ack, "actuated-terminal-retained");
    const terminal_ack_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = actuated_manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = actuated_ack.previous_turn_receipt_fingerprint,
        .retention_ack = terminal_ack,
    });
    const terminal_ack_continue_bytes = try terminal_ack_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(terminal_ack_continue_bytes);
    try actuated_ack.submit(terminal_ack_continue_bytes);
    try actuated_ack.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, actuated_ack.state);
    try std.testing.expectEqual(@as(?u64, null), actuated_ack.pending_archive_append_batch_fingerprint);
    try std.testing.expect(actuated_ack.outstanding_host_request == null);
}

test "appliance Core executeTurn emits deterministic output and receipt" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);

    try core.submit(boot_bytes);
    try core.executeTurn();
    const first_output = core.readOutput();
    try std.testing.expect(first_output.len > 0);
    const first_output_copy = try std.testing.allocator.dupe(u8, first_output);
    defer std.testing.allocator.free(first_output_copy);
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expect(core.previous_turn_receipt_fingerprint != null);

    const first_receipt = core.previous_turn_receipt_fingerprint.?;
    const inspect = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .previous_turn_receipt_fingerprint = first_receipt,
    });
    const inspect_bytes = try inspect.encode(std.testing.allocator);
    defer std.testing.allocator.free(inspect_bytes);
    try core.submit(inspect_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expectEqual(first_receipt, core.previous_turn_receipt_fingerprint.?);
    try std.testing.expect(core.readOutput().len > 0);
    try std.testing.expect(!std.mem.eql(u8, first_output_copy, core.readOutput()));
}

test "appliance inspect checkpoint preserves waiting host request" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer resident.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try resident.submit(boot_bytes);
    try resident.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, resident.state);
    const outstanding = resident.outstanding_host_request orelse return error.UnknownRequest;
    const prior_receipt = resident.previous_turn_receipt_fingerprint.?;

    const inspect = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .previous_turn_receipt_fingerprint = prior_receipt,
    });
    const inspect_bytes = try inspect.encode(std.testing.allocator);
    defer std.testing.allocator.free(inspect_bytes);
    try resident.submit(inspect_bytes);
    try resident.executeTurn();
    var inspect_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        resident.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer inspect_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.inspected, inspect_output.status);
    try std.testing.expectEqual(@as(usize, 0), inspect_output.host_requests.len);
    try std.testing.expectEqual(@as(usize, 1), inspect_output.checkpoint.outstanding_host_requests.len);
    try std.testing.expectEqual(outstanding.request_fingerprint, inspect_output.checkpoint.outstanding_host_requests[0].request_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), inspect_output.quiescence.pending_host_request_count);

    var restored = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer restored.reset();
    const reply = applianceHostReplyFor(outstanding, 0xD520);
    const restore = world.Appliance.Command.init(.{
        .kind = .restore,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .host_replies = &.{reply},
        .restore_checkpoint = inspect_output.checkpoint,
    });
    const restore_bytes = try restore.encode(std.testing.allocator);
    defer std.testing.allocator.free(restore_bytes);
    try restored.submit(restore_bytes);
    try restored.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, restored.state);
    try std.testing.expect(restored.outstanding_host_request == null);
}

test "appliance Core executeTurn enforces output capacity deterministically" {
    const tight = comptime blk: {
        var capacity = world.Appliance.Capacity.tiny_one_port;
        capacity.max_output_bytes = 1;
        break :blk capacity;
    };
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = tight,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        tight,
    );
    defer core.reset();
    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try std.testing.expectError(error.CapacityExceeded, core.executeTurn());
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, core.state);
    try std.testing.expectEqual(@as(u64, 0), core.current_turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, null), core.previous_turn_receipt_fingerprint);
    try std.testing.expect(core.outstanding_host_request == null);
    try std.testing.expect(core.pending_command != null);
    try std.testing.expectEqual(@as(usize, 0), core.readOutput().len);
}

test "appliance Core restore validates checkpoint before mutating state" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 7,
        .capsule_fingerprint = 0xC001,
        .previous_turn_receipt_fingerprint = 0xC002,
    });
    try core.restore(checkpoint);
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expectEqual(@as(u64, 7), core.current_turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, 0xC002), core.previous_turn_receipt_fingerprint);

    const before_state = core.state;
    const before_turn = core.current_turn_sequence_number;
    const wrong_manifest = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint + 1,
        .turn_sequence_number = 8,
        .capsule_fingerprint = 0xC003,
    });
    try std.testing.expectError(error.WrongManifest, core.restore(wrong_manifest));
    try std.testing.expectEqual(before_state, core.state);
    try std.testing.expectEqual(before_turn, core.current_turn_sequence_number);

    const runnable_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 8,
        .capsule_fingerprint = 0xC006,
        .core_state = .runnable,
        .previous_turn_receipt_fingerprint = 0xC007,
    });
    try runnable_checkpoint.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectError(error.InvalidFrameEncoding, core.restore(runnable_checkpoint));
    try std.testing.expectEqual(before_state, core.state);
    try std.testing.expectEqual(before_turn, core.current_turn_sequence_number);

    const max_turn_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = std.math.maxInt(u64),
        .capsule_fingerprint = 0xC004,
        .previous_turn_receipt_fingerprint = 0xC005,
    });
    try core.restore(max_turn_checkpoint);
    const max_turn_continue = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = std.math.maxInt(u64),
        .previous_turn_receipt_fingerprint = max_turn_checkpoint.previous_turn_receipt_fingerprint,
    });
    const max_turn_continue_bytes = try max_turn_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(max_turn_continue_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(max_turn_continue_bytes));
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), core.current_turn_sequence_number);
}

test "appliance Core restore clears stale public output" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expect(core.readOutput().len > 0);
    try std.testing.expect(core.last_output_status != null);

    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 7,
        .capsule_fingerprint = 0xC101,
        .previous_turn_receipt_fingerprint = 0xC102,
    });
    try core.restore(checkpoint);
    try std.testing.expectEqual(@as(usize, 0), core.readOutput().len);
    try std.testing.expectEqual(@as(?world.Appliance.TurnStatus, null), core.last_output_status);
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);
    try std.testing.expectEqual(@as(u64, 7), core.current_turn_sequence_number);
}

test "appliance Core restore rolls back allocation failure" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 0,
    });
    var core = world.Appliance.Core.initWithCapacity(
        failing_allocator.allocator(),
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();
    const old_request = applianceManifestHostRequest(manifest, .{
        .turn_sequence_number = 6,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD6A0,
        .pending_port_fingerprint = 0xD6A1,
        .intent_fingerprint = 0xD6A2,
        .envelope_fingerprint = 0xD6A3,
        .decision_fingerprint = 0xD6A4,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD6A5,
        .metadata = "old-request",
    });
    core.state = .waiting_host;
    core.current_turn_sequence_number = 6;
    core.previous_turn_receipt_fingerprint = 0xD6A6;
    core.outstanding_host_request = old_request;

    const new_request = applianceManifestHostRequest(manifest, .{
        .turn_sequence_number = 7,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD6B0,
        .pending_port_fingerprint = 0xD6B1,
        .intent_fingerprint = 0xD6B2,
        .envelope_fingerprint = 0xD6B3,
        .decision_fingerprint = 0xD6B4,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD6B5,
        .metadata = "new-request",
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 7,
        .capsule_fingerprint = 0xD6B6,
        .previous_turn_receipt_fingerprint = 0xD6B7,
        .outstanding_host_requests = &.{new_request},
    });

    try std.testing.expectError(error.OutOfMemory, core.restore(checkpoint));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(@as(u64, 6), core.current_turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, 0xD6A6), core.previous_turn_receipt_fingerprint);
    try std.testing.expect(core.outstanding_host_request != null);
    try std.testing.expectEqual(old_request.request_fingerprint, core.outstanding_host_request.?.request_fingerprint);
    try std.testing.expectEqualStrings("old-request", core.outstanding_host_request.?.metadata);
}

test "appliance Core executeTurn preserves output on needs-host allocation failure" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);

    var observed_induced_failure = false;
    var observed_success = false;
    var fail_offset: usize = 0;
    while (fail_offset < 512 and !observed_success) : (fail_offset += 1) {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = std.math.maxInt(usize),
        });
        var core = world.Appliance.Core.initWithCapacity(
            failing_allocator.allocator(),
            manifest,
            PortsAppliance.memoryPlan(),
            world.Appliance.Capacity.tiny_one_port,
        );
        defer core.reset();
        core.last_output_bytes = "previous-output";
        core.last_output_status = .completed;

        try core.submit(boot_bytes);
        failing_allocator.fail_index = failing_allocator.alloc_index + fail_offset;
        core.executeTurn() catch |err| switch (err) {
            error.OutOfMemory => {
                observed_induced_failure = true;
                try std.testing.expect(failing_allocator.has_induced_failure);
                try std.testing.expectEqualStrings("previous-output", core.readOutput());
                try std.testing.expectEqual(@as(?world.Appliance.TurnStatus, .completed), core.last_output_status);
                continue;
            },
            else => return err,
        };
        observed_success = true;
    }

    try std.testing.expect(observed_induced_failure);
    try std.testing.expect(observed_success);
}

test "appliance Core cancel produces deterministic cancelled output" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const future_cancel = world.Appliance.Command.init(.{
        .kind = .cancel,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
    });
    const future_cancel_bytes = try future_cancel.encode(std.testing.allocator);
    defer std.testing.allocator.free(future_cancel_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(future_cancel_bytes));

    const cancel = world.Appliance.Command.init(.{
        .kind = .cancel,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const cancel_bytes = try cancel.encode(std.testing.allocator);
    defer std.testing.allocator.free(cancel_bytes);
    try core.submit(cancel_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.cancelled, core.state);
    try std.testing.expect(core.readOutput().len > 0);
    try std.testing.expect(core.previous_turn_receipt_fingerprint != null);
}

test "appliance Core reset command clears continuation state and allows fresh boot" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.full_evidence,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "reset-command",
    });
    const manifest = PortsAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expect(core.previous_turn_receipt_fingerprint != null);
    try std.testing.expect(core.outstanding_host_request != null);
    try std.testing.expect(core.pending_archive_append_batch_fingerprint != null);

    const future_reset = world.Appliance.Command.init(.{
        .kind = .reset,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 3,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
    });
    const future_reset_bytes = try future_reset.encode(std.testing.allocator);
    defer std.testing.allocator.free(future_reset_bytes);
    try std.testing.expectError(error.StaleTurn, core.submit(future_reset_bytes));

    const reset = world.Appliance.Command.init(.{
        .kind = .reset,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
    });
    const reset_bytes = try reset.encode(std.testing.allocator);
    defer std.testing.allocator.free(reset_bytes);
    const prior_receipt = core.previous_turn_receipt_fingerprint;
    const prior_archive = core.pending_archive_append_batch_fingerprint;
    const prior_output_len = core.readOutput().len;
    try core.submit(reset_bytes);
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(@as(u64, 0), core.current_turn_sequence_number);
    try std.testing.expectEqual(prior_receipt, core.previous_turn_receipt_fingerprint);
    try std.testing.expect(core.outstanding_host_request != null);
    try std.testing.expectEqual(prior_archive, core.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(prior_output_len, core.readOutput().len);

    const reset_ack = try applianceRetentionAckForPendingCore(core, "reset-ack-dropped");
    const reset_with_ack = world.Appliance.Command.init(.{
        .kind = .reset,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .retention_ack = reset_ack,
    });
    const reset_with_ack_bytes = try reset_with_ack.encode(std.testing.allocator);
    defer std.testing.allocator.free(reset_with_ack_bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, core.submit(reset_with_ack_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(prior_archive, core.pending_archive_append_batch_fingerprint);

    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, core.state);
    try std.testing.expectEqual(@as(u64, 0), core.current_turn_sequence_number);
    try std.testing.expectEqual(@as(?u64, null), core.previous_turn_receipt_fingerprint);
    try std.testing.expect(core.outstanding_host_request == null);
    try std.testing.expectEqual(@as(?u64, null), core.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(?u64, null), core.latest_archive_moment_fingerprint);
    try std.testing.expect(core.readOutput().len > 0);

    var reset_output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer reset_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.cancelled, reset_output.status);
    try std.testing.expectEqual(@as(u64, 0), reset_output.checkpoint.turn_sequence_number);
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, reset_output.checkpoint.core_state);
    try std.testing.expectEqual(@as(?u64, null), reset_output.archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(?u64, null), reset_output.checkpoint.pending_archive_append_batch_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), reset_output.warning_count);

    const reboot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "after-reset",
    });
    const reboot_bytes = try reboot.encode(std.testing.allocator);
    defer std.testing.allocator.free(reboot_bytes);
    try core.submit(reboot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
}

test "appliance host request validates and is carried by needs-host TurnOutput" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD100,
        .pending_port_fingerprint = 0xD101,
        .world_port_id = 0,
        .intent_fingerprint = 0xD102,
        .envelope_fingerprint = 0xD103,
        .decision_fingerprint = 0xD104,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD105,
        .metadata = "model",
    });
    try request.validate(world.Appliance.Capacity.tiny_one_port);
    const segmented_frame_payload = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD100,
        .pending_port_fingerprint = 0xD101,
        .world_port_id = 0,
        .intent_fingerprint = 0xD102,
        .envelope_fingerprint = 0xD103,
        .decision_fingerprint = 0xD104,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD105,
        .metadata = "model",
        .frame_request_bytes = "ab",
        .payload_value_image_bytes = "c",
        .prepared_actuation_evidence_bytes = "de",
        .idempotency_key_bytes = "f",
    });
    const shifted_frame_payload = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD100,
        .pending_port_fingerprint = 0xD101,
        .world_port_id = 0,
        .intent_fingerprint = 0xD102,
        .envelope_fingerprint = 0xD103,
        .decision_fingerprint = 0xD104,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD105,
        .metadata = "model",
        .frame_request_bytes = "a",
        .payload_value_image_bytes = "bc",
        .prepared_actuation_evidence_bytes = "de",
        .idempotency_key_bytes = "f",
    });
    try std.testing.expect(segmented_frame_payload.request_fingerprint != shifted_frame_payload.request_fingerprint);
    const shifted_prepared_key = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD100,
        .pending_port_fingerprint = 0xD101,
        .world_port_id = 0,
        .intent_fingerprint = 0xD102,
        .envelope_fingerprint = 0xD103,
        .decision_fingerprint = 0xD104,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD105,
        .metadata = "model",
        .frame_request_bytes = "ab",
        .payload_value_image_bytes = "c",
        .prepared_actuation_evidence_bytes = "d",
        .idempotency_key_bytes = "ef",
    });
    try std.testing.expect(segmented_frame_payload.request_fingerprint != shifted_prepared_key.request_fingerprint);

    const capsule_fingerprint: u64 = 0xD106;
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD107,
        .emitted_host_request_fingerprints = &.{request.request_fingerprint},
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .status = .needs_host,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
        .outstanding_host_requests = &.{request},
    });
    const output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD108,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.waiting_host, 1, receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .pending_host_request_count = 1,
            .prepared_actuation_count = 1,
        }),
        .status = .needs_host,
        .host_requests = &.{request},
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });
    try output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    const output_bytes = try output.encode(std.testing.allocator);
    defer std.testing.allocator.free(output_bytes);
    try std.testing.expect(output_bytes.len > 0);

    const second_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 1,
        .run_handle_fingerprint = 0xD10B,
        .pending_port_fingerprint = 0xD10C,
        .world_port_id = 0,
        .intent_fingerprint = 0xD10D,
        .envelope_fingerprint = 0xD10E,
        .decision_fingerprint = 0xD10F,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD110,
    });
    const multi_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD111,
        .emitted_host_request_fingerprints = &.{ request.request_fingerprint, second_request.request_fingerprint },
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .status = .needs_host,
    });
    const multi_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = multi_receipt.receipt_fingerprint,
        .outstanding_host_requests = &.{ request, second_request },
    });
    const multi_request_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD112,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.waiting_host, 1, multi_receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .pending_host_request_count = 2,
            .prepared_actuation_count = 2,
        }),
        .status = .needs_host,
        .host_requests = &.{ request, second_request },
        .checkpoint = multi_checkpoint,
        .turn_receipt = multi_receipt,
    });
    try multi_request_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_small);

    const non_quiescent_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD108,
        .resulting_state_fingerprint = output.resulting_state_fingerprint,
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = false,
            .pending_host_request_count = 1,
            .prepared_actuation_count = 1,
        }),
        .status = .needs_host,
        .host_requests = &.{request},
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, non_quiescent_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const active_fabric_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD108,
        .resulting_state_fingerprint = output.resulting_state_fingerprint,
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .pending_host_request_count = 1,
            .active_fabric_count = 1,
            .prepared_actuation_count = 1,
        }),
        .status = .needs_host,
        .host_requests = &.{request},
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, active_fabric_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const failed_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD10A,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .status = .failed,
    });
    const completed_checkpoint_for_failed_output = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .core_state = .completed,
        .previous_turn_receipt_fingerprint = failed_receipt.receipt_fingerprint,
    });
    const failed_output_with_completed_checkpoint = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD108,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 1, failed_receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .failed_run_count = 1,
        }),
        .status = .failed,
        .checkpoint = completed_checkpoint_for_failed_output,
        .turn_receipt = failed_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, failed_output_with_completed_checkpoint.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const mismatched_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD107,
        .emitted_host_request_fingerprints = &.{request.request_fingerprint + 1},
        .resulting_capsule_fingerprint = checkpoint.capsule_fingerprint,
        .status = .needs_host,
    });
    const mismatched_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD108,
        .resulting_state_fingerprint = 0xD109,
        .quiescence = output.quiescence,
        .status = .needs_host,
        .host_requests = &.{request},
        .checkpoint = output.checkpoint,
        .turn_receipt = mismatched_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_output.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance host reply validates against outstanding request identity" {
    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 3,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD200,
        .pending_port_fingerprint = 0xD201,
        .world_port_id = 0,
        .intent_fingerprint = 0xD202,
        .envelope_fingerprint = 0xD203,
        .decision_fingerprint = 0xD204,
        .expected_response_descriptor_fingerprint = 0xD205,
        .idempotency_key_fingerprint = 0xD206,
    });
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = 0xD207,
        .response_kind = .frame_value_image,
        .host_evidence_fingerprint = 0xD208,
        .host_evidence_bytes = "local-claim",
        .attempt_number = 1,
    });
    const ack = applianceRetentionAckFor(0xD20B, "reply-retained");
    const reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
        .retention_ack = ack,
    });
    try reply.validate(&.{request}, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectEqual(@as(?u64, ack.ack_fingerprint), reply.retention_ack_fingerprint);

    var response_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as(i32, 42), .portable);
    defer response_image.deinit(std.testing.allocator);
    const response_image_bytes = try response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_image_bytes);
    const embedded_response = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_image.value_image_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = response_image_bytes,
        .host_evidence_fingerprint = 0xD20D,
        .host_evidence_bytes = "embedded-response",
        .attempt_number = 1,
    });
    try embedded_response.validate(request, world.Appliance.Capacity.tiny_one_port);

    const expected_response_value_ref: u64 = 0xD210;
    const expected_response_schema_ref: u64 = 0xD211;
    const bound_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 3,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD220,
        .pending_port_fingerprint = 0xD221,
        .world_port_id = 0,
        .intent_fingerprint = 0xD222,
        .envelope_fingerprint = 0xD223,
        .decision_fingerprint = 0xD224,
        .expected_response_descriptor_fingerprint = 0xD225,
        .idempotency_key_fingerprint = 0xD226,
        .expected_response_value_ref_fingerprint = expected_response_value_ref,
        .expected_response_schema_ref_fingerprint = expected_response_schema_ref,
    });
    var bound_response_image = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        null,
        expected_response_value_ref,
        expected_response_schema_ref,
        @as(i32, 7),
        .portable,
    );
    defer bound_response_image.deinit(std.testing.allocator);
    const bound_response_image_bytes = try bound_response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(bound_response_image_bytes);
    const bound_embedded_response = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = bound_request.request_fingerprint,
        .intent_fingerprint = bound_request.intent_fingerprint,
        .envelope_fingerprint = bound_request.envelope_fingerprint,
        .idempotency_key_fingerprint = bound_request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = bound_response_image.value_image_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = bound_response_image_bytes,
        .host_evidence_fingerprint = 0xD227,
        .host_evidence_bytes = "embedded-response-bound",
        .attempt_number = 1,
    });
    try bound_embedded_response.validate(bound_request, world.Appliance.Capacity.tiny_one_port);

    var wrong_ref_response_image = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        null,
        expected_response_value_ref + 1,
        expected_response_schema_ref,
        @as(i32, 7),
        .portable,
    );
    defer wrong_ref_response_image.deinit(std.testing.allocator);
    const wrong_ref_response_image_bytes = try wrong_ref_response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_ref_response_image_bytes);
    const wrong_ref_embedded_response = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = bound_request.request_fingerprint,
        .intent_fingerprint = bound_request.intent_fingerprint,
        .envelope_fingerprint = bound_request.envelope_fingerprint,
        .idempotency_key_fingerprint = bound_request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = wrong_ref_response_image.value_image_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = wrong_ref_response_image_bytes,
        .host_evidence_fingerprint = 0xD228,
        .host_evidence_bytes = "embedded-response-wrong-ref",
        .attempt_number = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_ref_embedded_response.validate(bound_request, world.Appliance.Capacity.tiny_one_port));

    var wrong_schema_response_image = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        null,
        expected_response_value_ref,
        expected_response_schema_ref + 1,
        @as(i32, 7),
        .portable,
    );
    defer wrong_schema_response_image.deinit(std.testing.allocator);
    const wrong_schema_response_image_bytes = try wrong_schema_response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_schema_response_image_bytes);
    const wrong_schema_embedded_response = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = bound_request.request_fingerprint,
        .intent_fingerprint = bound_request.intent_fingerprint,
        .envelope_fingerprint = bound_request.envelope_fingerprint,
        .idempotency_key_fingerprint = bound_request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = wrong_schema_response_image.value_image_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = wrong_schema_response_image_bytes,
        .host_evidence_fingerprint = 0xD229,
        .host_evidence_bytes = "embedded-response-wrong-schema",
        .attempt_number = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_schema_embedded_response.validate(bound_request, world.Appliance.Capacity.tiny_one_port));

    const forged_embedded_response = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_image.value_image_fingerprint + 1,
        .response_kind = .frame_value_image,
        .response_bytes = response_image_bytes,
        .host_evidence_fingerprint = 0xD20E,
        .host_evidence_bytes = "forged-embedded-response",
        .attempt_number = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, forged_embedded_response.validate(request, world.Appliance.Capacity.tiny_one_port));

    const wrong_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint + 1,
        .outcome = outcome,
    });
    try std.testing.expectError(error.UnknownRequest, wrong_reply.validate(&.{request}, world.Appliance.Capacity.tiny_one_port));
    var wrong_reply_payload: std.ArrayList(u8) = .empty;
    defer wrong_reply_payload.deinit(std.testing.allocator);
    try wrong_reply.encode(&wrong_reply_payload, std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.HostReply.decodeArchivePayload(std.testing.allocator, wrong_reply_payload.items));

    const stale_outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint + 1,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = 0xD209,
        .response_kind = .bytes,
        .response_bytes = "approved-bytes",
    });
    const stale_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = stale_outcome,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, stale_reply.validate(&.{request}, world.Appliance.Capacity.tiny_one_port));

    const pending_with_payload = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .pending,
        .response_kind = .bytes,
        .response_bytes = "not-terminal",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, pending_with_payload.validate(request, world.Appliance.Capacity.tiny_one_port));

    const pending_outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .pending,
        .host_evidence_fingerprint = 0xD21C,
        .host_evidence_bytes = "local-pending-claim",
        .attempt_number = 1,
    });
    const pending_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = pending_outcome,
    });
    try std.testing.expectError(error.PortRuleDenied, pending_reply.validate(&.{request}, world.Appliance.Capacity.tiny_one_port));

    const rejected_with_payload = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .rejected,
        .response_fingerprint = 0xD20C,
        .response_kind = .bytes,
        .response_bytes = "not-a-response",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, rejected_with_payload.validate(request, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_metadata_bytes = 4;
    const oversized_evidence = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = 0xD20A,
        .response_kind = .frame_value_image,
        .host_evidence_bytes = "too-large",
    });
    try std.testing.expectError(error.CapacityExceeded, oversized_evidence.validate(request, tight));
}

test "appliance continuity typed payload validation accepts advertised appliance objects" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const manifest_bytes = try manifest.encode(std.testing.allocator);
    defer std.testing.allocator.free(manifest_bytes);
    try expectApplianceTypedPayloadValid(.appliance_manifest, world.world_appliance_manifest_format_version, manifest_bytes);

    const command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "typed-payload",
    });
    const command_bytes = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(command_bytes);
    try expectApplianceTypedPayloadValid(.appliance_command, world.world_appliance_command_format_version, command_bytes);

    const archive_command_bytes = try std.testing.allocator.alloc(u8, world.Appliance.Capacity.large_native_test.max_command_bytes + 1);
    defer std.testing.allocator.free(archive_command_bytes);
    @memset(archive_command_bytes, 'c');
    const archive_sized_command = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = archive_command_bytes,
    });
    const archive_sized_command_payload = try archive_sized_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(archive_sized_command_payload);
    try expectApplianceTypedPayloadValid(.appliance_command, world.world_appliance_command_format_version, archive_sized_command_payload);

    const archive_metadata = try std.testing.allocator.alloc(u8, world.Appliance.Capacity.large_native_test.max_metadata_bytes + 1);
    defer std.testing.allocator.free(archive_metadata);
    @memset(archive_metadata, 'm');

    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD300,
        .pending_port_fingerprint = 0xD301,
        .world_port_id = 0,
        .intent_fingerprint = 0xD302,
        .envelope_fingerprint = 0xD303,
        .decision_fingerprint = 0xD304,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD305,
        .metadata = "typed-request",
    });
    var request_payload: std.ArrayList(u8) = .empty;
    defer request_payload.deinit(std.testing.allocator);
    try request.encode(&request_payload, std.testing.allocator);
    try expectApplianceTypedPayloadValid(.appliance_host_request, world.world_appliance_host_request_format_version, request_payload.items);

    const archive_sized_request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD310,
        .pending_port_fingerprint = 0xD311,
        .world_port_id = 0,
        .intent_fingerprint = 0xD312,
        .envelope_fingerprint = 0xD313,
        .decision_fingerprint = 0xD314,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xD315,
        .metadata = archive_metadata,
    });
    var archive_sized_request_payload: std.ArrayList(u8) = .empty;
    defer archive_sized_request_payload.deinit(std.testing.allocator);
    try archive_sized_request.encode(&archive_sized_request_payload, std.testing.allocator);
    try expectApplianceTypedPayloadValid(.appliance_host_request, world.world_appliance_host_request_format_version, archive_sized_request_payload.items);

    const reply = applianceHostReplyFor(request, 0xD306);
    var reply_payload: std.ArrayList(u8) = .empty;
    defer reply_payload.deinit(std.testing.allocator);
    try reply.encode(&reply_payload, std.testing.allocator);
    try expectApplianceTypedPayloadValid(.appliance_host_reply, world.world_appliance_host_reply_format_version, reply_payload.items);

    const archive_sized_reply = world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = reply.target_host_request_fingerprint,
        .outcome = reply.outcome,
        .metadata = archive_metadata,
    });
    var archive_sized_reply_payload: std.ArrayList(u8) = .empty;
    defer archive_sized_reply_payload.deinit(std.testing.allocator);
    try archive_sized_reply.encode(&archive_sized_reply_payload, std.testing.allocator);
    try expectApplianceTypedPayloadValid(.appliance_host_reply, world.world_appliance_host_reply_format_version, archive_sized_reply_payload.items);

    const archive_sized_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD320,
        .previous_turn_receipt_fingerprint = 0xD321,
        .metadata = archive_metadata,
    });
    var archive_sized_checkpoint_payload: std.ArrayList(u8) = .empty;
    defer archive_sized_checkpoint_payload.deinit(std.testing.allocator);
    try archive_sized_checkpoint.encode(&archive_sized_checkpoint_payload, std.testing.allocator);
    try expectApplianceTypedPayloadValid(.appliance_checkpoint, world.world_appliance_checkpoint_format_version, archive_sized_checkpoint_payload.items);

    const reconstruction = world.Appliance.ReconstructionReport.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .resident_turn_output_fingerprint = 0xD307,
        .reconstructed_turn_output_fingerprint = 0xD307,
    });
    const reconstruction_payload = try world.Continuity.encodePortableEvidence(
        world.Appliance.ReconstructionReport,
        std.testing.allocator,
        reconstruction,
    );
    defer std.testing.allocator.free(reconstruction_payload);
    try expectApplianceTypedPayloadValid(
        .appliance_reconstruction_report,
        world.world_appliance_reconstruction_report_fingerprint_version,
        reconstruction_payload,
    );
    const reconstruction_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_reconstruction_report,
        .object_format_version = world.world_appliance_reconstruction_report_fingerprint_version,
        .payload_bytes = reconstruction_payload,
    });
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, reconstruction_envelope),
    );
    const reconstruction_output_only_deps = [_]world.Continuity.ObjectRef{
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_turn_output,
            .object_format_version = world.Continuity.ObjectKind.appliance_turn_output.defaultFormatVersion(),
            .object_fingerprint = reconstruction.resident_turn_output_fingerprint,
            .byte_len = 0,
        }),
    };
    const reconstruction_without_manifest_dep = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_reconstruction_report,
        .object_format_version = world.world_appliance_reconstruction_report_fingerprint_version,
        .dependency_refs = &reconstruction_output_only_deps,
        .payload_bytes = reconstruction_payload,
    });
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, reconstruction_without_manifest_dep),
    );
    const reconstruction_deps = [_]world.Continuity.ObjectRef{
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_manifest,
            .object_format_version = world.Continuity.ObjectKind.appliance_manifest.defaultFormatVersion(),
            .object_fingerprint = reconstruction.manifest_fingerprint,
            .byte_len = 0,
        }),
        reconstruction_output_only_deps[0],
    };
    const reconstruction_with_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_reconstruction_report,
        .object_format_version = world.world_appliance_reconstruction_report_fingerprint_version,
        .dependency_refs = &reconstruction_deps,
        .payload_bytes = reconstruction_payload,
    });
    try world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, reconstruction_with_deps);

    const OtherAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "other-reconstruction-manifest",
    });
    const other_manifest = OtherAppliance.manifest();
    const other_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = other_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xD340,
        .resulting_capsule_fingerprint = 0xD341,
        .root_result_fingerprint = 0xD342,
        .status = .completed,
    });
    const other_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = other_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xD341,
        .core_state = .completed,
        .previous_turn_receipt_fingerprint = other_receipt.receipt_fingerprint,
    });
    var other_checkpoint_bytes: std.ArrayList(u8) = .empty;
    defer other_checkpoint_bytes.deinit(std.testing.allocator);
    try other_checkpoint.encode(&other_checkpoint_bytes, std.testing.allocator);
    const other_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = other_manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xD343,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 1, other_receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .completed_run_count = 1,
        }),
        .status = .completed,
        .root_result_fingerprint = 0xD342,
        .checkpoint_bytes = other_checkpoint_bytes.items,
        .checkpoint = other_checkpoint,
        .turn_receipt = other_receipt,
    });
    const other_output_payload = try other_output.encode(std.testing.allocator);
    defer std.testing.allocator.free(other_output_payload);
    const mismatched_reconstruction = world.Appliance.ReconstructionReport.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .resident_turn_output_fingerprint = other_output.output_fingerprint,
        .reconstructed_turn_output_fingerprint = other_output.output_fingerprint,
    });
    const mismatched_reconstruction_payload = try world.Continuity.encodePortableEvidence(
        world.Appliance.ReconstructionReport,
        std.testing.allocator,
        mismatched_reconstruction,
    );
    defer std.testing.allocator.free(mismatched_reconstruction_payload);
    const mismatched_reconstruction_deps = [_]world.Continuity.ObjectRef{
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_turn_output,
            .object_format_version = world.Continuity.ObjectKind.appliance_turn_output.defaultFormatVersion(),
            .object_fingerprint = other_output.output_fingerprint,
            .byte_len = 0,
        }),
    };
    const mismatched_reconstruction_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_reconstruction_report,
        .object_format_version = world.world_appliance_reconstruction_report_fingerprint_version,
        .dependency_refs = &mismatched_reconstruction_deps,
        .payload_bytes = mismatched_reconstruction_payload,
    });
    const other_output_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_output,
        .object_format_version = world.world_appliance_turn_output_format_version,
        .payload_bytes = other_output_payload,
    });
    const mismatched_bundle = [_]world.Continuity.ObjectEnvelope{
        other_output_envelope,
        mismatched_reconstruction_envelope,
    };
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeDependencyPayloads(
            std.testing.allocator,
            &mismatched_bundle,
            mismatched_reconstruction_envelope,
        ),
    );

    const mismatched_conformance = world.Appliance.ConformanceReport.init(.{
        .vector_fingerprint = 0xD408,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .native_core_output_fingerprint = other_output.output_fingerprint,
        .resident_core_output_fingerprint = other_output.output_fingerprint,
        .reconstructed_core_output_fingerprint = other_output.output_fingerprint,
    });
    const mismatched_conformance_payload = try world.Continuity.encodePortableEvidence(
        world.Appliance.ConformanceReport,
        std.testing.allocator,
        mismatched_conformance,
    );
    defer std.testing.allocator.free(mismatched_conformance_payload);
    const mismatched_conformance_deps = [_]world.Continuity.ObjectRef{
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_turn_output,
            .object_format_version = world.Continuity.ObjectKind.appliance_turn_output.defaultFormatVersion(),
            .object_fingerprint = other_output.output_fingerprint,
            .byte_len = 0,
        }),
    };
    const mismatched_conformance_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_conformance_report,
        .object_format_version = world.world_appliance_conformance_report_fingerprint_version,
        .dependency_refs = &mismatched_conformance_deps,
        .payload_bytes = mismatched_conformance_payload,
    });
    const mismatched_conformance_bundle = [_]world.Continuity.ObjectEnvelope{
        other_output_envelope,
        mismatched_conformance_envelope,
    };
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeDependencyPayloads(
            std.testing.allocator,
            &mismatched_conformance_bundle,
            mismatched_conformance_envelope,
        ),
    );

    const conformance = world.Appliance.ConformanceReport.init(.{
        .vector_fingerprint = 0xD308,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .native_core_output_fingerprint = 0xD309,
        .resident_core_output_fingerprint = 0xD309,
        .reconstructed_core_output_fingerprint = 0xD309,
    });
    const conformance_payload = try world.Continuity.encodePortableEvidence(
        world.Appliance.ConformanceReport,
        std.testing.allocator,
        conformance,
    );
    defer std.testing.allocator.free(conformance_payload);
    try expectApplianceTypedPayloadValid(
        .appliance_conformance_report,
        world.world_appliance_conformance_report_fingerprint_version,
        conformance_payload,
    );
    const conformance_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_conformance_report,
        .object_format_version = world.world_appliance_conformance_report_fingerprint_version,
        .payload_bytes = conformance_payload,
    });
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, conformance_envelope),
    );
    const conformance_deps = [_]world.Continuity.ObjectRef{
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_manifest,
            .object_format_version = world.Continuity.ObjectKind.appliance_manifest.defaultFormatVersion(),
            .object_fingerprint = manifest.manifest_fingerprint,
            .byte_len = 0,
        }),
        world.Continuity.ObjectRef.init(.{
            .kind = .appliance_turn_output,
            .object_format_version = world.Continuity.ObjectKind.appliance_turn_output.defaultFormatVersion(),
            .object_fingerprint = conformance.native_core_output_fingerprint,
            .byte_len = 0,
        }),
    };
    const conformance_with_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_conformance_report,
        .object_format_version = world.world_appliance_conformance_report_fingerprint_version,
        .dependency_refs = &conformance_deps,
        .payload_bytes = conformance_payload,
    });
    try world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, conformance_with_deps);

    var corrupt_payload = try std.testing.allocator.dupe(u8, request_payload.items);
    defer std.testing.allocator.free(corrupt_payload);
    corrupt_payload[8] = 0;
    const corrupt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_host_request,
        .object_format_version = world.world_appliance_host_request_format_version,
        .payload_bytes = corrupt_payload,
    });
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeTypedPayload(std.testing.allocator, corrupt_envelope),
    );
}

test "appliance turn receipt binds host reply and request evidence" {
    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 4,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD240,
        .pending_port_fingerprint = 0xD241,
        .world_port_id = 0,
        .intent_fingerprint = 0xD242,
        .envelope_fingerprint = 0xD243,
        .decision_fingerprint = 0xD244,
        .expected_response_descriptor_fingerprint = 0xD245,
        .idempotency_key_fingerprint = 0xD246,
    });
    const reply = applianceHostReplyFor(request, 0xD247);
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD248,
        .turn_sequence_number = 4,
        .command_fingerprint = 0xD249,
        .applied_host_reply_fingerprints = &.{reply.reply_fingerprint},
        .emitted_host_request_fingerprints = &.{request.request_fingerprint},
        .resulting_capsule_fingerprint = 0xD24A,
        .status = .needs_host,
    });
    try receipt.validate(0xD248, world.Appliance.Capacity.tiny_one_port);

    var missing_reply = receipt;
    missing_reply.applied_host_reply_fingerprints = &.{};
    try std.testing.expectError(error.InvalidFrameEncoding, missing_reply.validate(0xD248, world.Appliance.Capacity.tiny_one_port));

    var zero_request = receipt;
    zero_request.emitted_host_request_fingerprints = &.{0};
    try std.testing.expectError(error.InvalidFrameEncoding, zero_request.validate(0xD248, world.Appliance.Capacity.tiny_one_port));

    const terminal_with_request = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD248,
        .turn_sequence_number = 4,
        .command_fingerprint = 0xD249,
        .emitted_host_request_fingerprints = &.{request.request_fingerprint},
        .resulting_capsule_fingerprint = 0xD24A,
        .root_result_fingerprint = 0xD24B,
        .status = .completed,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, terminal_with_request.validate(0xD248, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_host_replies_per_turn = 0;
    try std.testing.expectError(error.CapacityExceeded, receipt.validate(0xD248, tight));
}

test "appliance turn receipt binds restore source evidence" {
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD260,
        .turn_sequence_number = 5,
        .command_fingerprint = 0xD261,
        .prior_checkpoint_fingerprint = 0xD262,
        .source_capsule_fingerprint = 0xD263,
        .resulting_capsule_fingerprint = 0xD264,
        .root_result_fingerprint = 0xD266,
        .status = .completed,
    });
    try receipt.validate(0xD260, world.Appliance.Capacity.tiny_one_port);

    const without_source = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD260,
        .turn_sequence_number = 5,
        .command_fingerprint = 0xD261,
        .resulting_capsule_fingerprint = 0xD264,
        .root_result_fingerprint = 0xD266,
        .status = .completed,
    });
    try without_source.validate(0xD260, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(receipt.receipt_fingerprint != without_source.receipt_fingerprint);

    var missing_capsule = receipt;
    missing_capsule.source_capsule_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_capsule.validate(0xD260, world.Appliance.Capacity.tiny_one_port));

    var stale_fingerprint = receipt;
    stale_fingerprint.prior_checkpoint_fingerprint = 0xD265;
    try std.testing.expectError(error.InvalidFrameEncoding, stale_fingerprint.validate(0xD260, world.Appliance.Capacity.tiny_one_port));
}

test "appliance turn receipt binds archive result anchors" {
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD270,
        .turn_sequence_number = 6,
        .command_fingerprint = 0xD271,
        .resulting_capsule_fingerprint = 0xD272,
        .archive_append_batch_fingerprint = 0xD273,
        .resulting_archive_moment_fingerprint = 0xD274,
        .resulting_archive_seal_fingerprint = 0xD275,
        .resulting_chronicle_cursor_fingerprint = 0xD276,
        .root_result_fingerprint = 0xD278,
        .status = .completed,
    });
    try receipt.validate(0xD270, world.Appliance.Capacity.tiny_one_port);

    const without_anchors = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = 0xD270,
        .turn_sequence_number = 6,
        .command_fingerprint = 0xD271,
        .resulting_capsule_fingerprint = 0xD272,
        .archive_append_batch_fingerprint = 0xD273,
        .root_result_fingerprint = 0xD278,
        .status = .completed,
    });
    try without_anchors.validate(0xD270, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(receipt.receipt_fingerprint != without_anchors.receipt_fingerprint);

    var partial = receipt;
    partial.resulting_archive_seal_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, partial.validate(0xD270, world.Appliance.Capacity.tiny_one_port));

    var stale_fingerprint = receipt;
    stale_fingerprint.resulting_chronicle_cursor_fingerprint = 0xD277;
    try std.testing.expectError(error.InvalidFrameEncoding, stale_fingerprint.validate(0xD270, world.Appliance.Capacity.tiny_one_port));
}

test "appliance TurnOutput binds root result through receipt parity" {
    const manifest_fingerprint: u64 = 0xD280;
    const root_result_fingerprint: u64 = 0xD281;
    const capsule_fingerprint: u64 = 0xD282;
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .command_fingerprint = 0xD283,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    const output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 7, receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .completed_run_count = 1,
        }),
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });
    try output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);

    const missing_root_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .command_fingerprint = 0xD283,
        .resulting_capsule_fingerprint = checkpoint.capsule_fingerprint,
        .status = .completed,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, missing_root_receipt.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
    const missing_root_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = 0xD285,
        .quiescence = output.quiescence,
        .status = .completed,
        .checkpoint = checkpoint,
        .turn_receipt = missing_root_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, missing_root_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const failed_root_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .command_fingerprint = 0xD283,
        .resulting_capsule_fingerprint = checkpoint.capsule_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .failed,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, failed_root_receipt.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
    const failed_root_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = 0xD285,
        .quiescence = output.quiescence,
        .status = .failed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = failed_root_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, failed_root_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const mismatched_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = 0xD285,
        .quiescence = output.quiescence,
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint + 1,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const wrong_capsule_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .command_fingerprint = 0xD283,
        .resulting_capsule_fingerprint = checkpoint.capsule_fingerprint + 1,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const wrong_capsule_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = 0xD285,
        .quiescence = output.quiescence,
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = wrong_capsule_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_capsule_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const replay_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
        .execution_mode = .replay,
    });
    const replay_fingerprint_only_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 7,
        .source_state_fingerprint = 0xD284,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 7, receipt.receipt_fingerprint),
        .quiescence = output.quiescence,
        .status = .completed,
        .finalized_actuation_receipt_fingerprints = &.{0xD286},
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = replay_checkpoint,
        .turn_receipt = receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, replay_fingerprint_only_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance TurnOutput deinit does not free borrowed init slices" {
    const manifest_fingerprint: u64 = 0xD2A0;
    const request = applianceSyntheticHostRequest(.{
        .turn_sequence_number = 3,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xD2A1,
        .pending_port_fingerprint = 0xD2A2,
        .world_port_id = 0,
        .intent_fingerprint = 0xD2A3,
        .envelope_fingerprint = 0xD2A4,
        .decision_fingerprint = 0xD2A5,
        .expected_response_descriptor_fingerprint = 0xD2A6,
        .idempotency_key_fingerprint = 0xD2A7,
    });
    const requests = [_]world.Appliance.HostRequest{request};
    const emitted = [_]u64{request.request_fingerprint};
    const capsule_fingerprint: u64 = 0xD2A9;
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 3,
        .command_fingerprint = 0xD2AA,
        .emitted_host_request_fingerprints = emitted[0..],
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .status = .needs_host,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 3,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
        .outstanding_host_requests = requests[0..],
    });
    var output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 3,
        .source_state_fingerprint = 0xD2AB,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.waiting_host, 3, receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .pending_host_request_count = 1,
            .prepared_actuation_count = 1,
        }),
        .status = .needs_host,
        .host_requests = requests[0..],
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
        .diagnostic_metadata = "borrowed-output-metadata",
    });
    try output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    output.deinit(std.testing.allocator);

    const terminal_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 3,
        .command_fingerprint = 0xD2AA,
        .emitted_host_request_fingerprints = emitted[0..],
        .resulting_capsule_fingerprint = checkpoint.capsule_fingerprint,
        .root_result_fingerprint = 0xD2AD,
        .status = .completed,
    });
    const terminal_with_request = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 3,
        .source_state_fingerprint = 0xD2AB,
        .resulting_state_fingerprint = 0xD2AC,
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .pending_host_request_count = 1,
            .completed_run_count = 1,
        }),
        .status = .completed,
        .host_requests = requests[0..],
        .root_result_fingerprint = 0xD2AD,
        .checkpoint = checkpoint,
        .turn_receipt = terminal_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, terminal_with_request.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
}

test "appliance TurnOutput binds finalized evidence refs and diagnostics" {
    const manifest_fingerprint: u64 = 0xD290;
    const archive_append_fingerprint: u64 = 0xD291;
    const run_receipt = world.RunReceipt.init(.{
        .run_permit_fingerprint = 0xD292,
        .environment_certificate_fingerprint = 0xD2921,
        .target_ref_fingerprint = 0xD2922,
        .usage_ledger_fingerprint = 0xD2923,
        .final_run_state_fingerprint = 0xD2924,
        .final_status = .failed,
    });
    const run_receipt_fingerprint: u64 = run_receipt.receipt_fingerprint;
    const run_receipt_bytes = try world.Continuity.encodePortableEvidence(world.RunReceipt, std.testing.allocator, run_receipt);
    defer std.testing.allocator.free(run_receipt_bytes);
    const finalized_receipt_fingerprint: u64 = 0xD293;
    const applied_reply_fingerprint: u64 = 0xD299;
    const archive_resulting_cursor = world.Continuity.Chronicle.Cursor.initial();
    const capsule_fingerprint: u64 = 0xD294;
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .command_fingerprint = 0xD295,
        .applied_host_reply_fingerprints = &.{applied_reply_fingerprint},
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .status = .blocked,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .blocker_count = 1,
        .warning_count = 1,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .capsule_fingerprint = capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = archive_append_fingerprint,
        .pending_archive_resulting_cursor = archive_resulting_cursor,
        .core_state = .failed,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    const output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .source_state_fingerprint = 0xD296,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.failed, 8, receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .blocker_count = 1,
            .warning_count = 1,
        }),
        .status = .blocked,
        .finalized_actuation_receipt_fingerprints = &.{finalized_receipt_fingerprint},
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .run_receipt_bytes = run_receipt_bytes,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
        .blocker_count = 1,
        .warning_count = 1,
        .diagnostic_metadata = "blocked-by-host",
    });
    try output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expect(output.archive_append_batch_ref_fingerprint != null);
    try std.testing.expect(output.archive_append_batch_ref_fingerprint.? != archive_append_fingerprint);
    const encoded = try output.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(encoded.len > 0);

    const different_finalized_ref = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .source_state_fingerprint = 0xD296,
        .resulting_state_fingerprint = 0xD297,
        .quiescence = output.quiescence,
        .status = .blocked,
        .finalized_actuation_receipt_fingerprints = &.{finalized_receipt_fingerprint + 1},
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
        .blocker_count = 1,
        .warning_count = 1,
        .diagnostic_metadata = "blocked-by-host",
    });
    try std.testing.expect(output.output_fingerprint != different_finalized_ref.output_fingerprint);

    var zero_finalized_ref = output;
    zero_finalized_ref.finalized_actuation_receipt_fingerprints = &.{0};
    try std.testing.expectError(error.InvalidFrameEncoding, zero_finalized_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const duplicate_applied_reply_fingerprints = [_]u64{ applied_reply_fingerprint, applied_reply_fingerprint ^ 0x11 };
    const duplicate_finalized_ref_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .command_fingerprint = 0xD295,
        .applied_host_reply_fingerprints = &duplicate_applied_reply_fingerprints,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .status = .blocked,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .blocker_count = 1,
        .warning_count = 1,
    });
    const duplicate_finalized_ref_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .capsule_fingerprint = capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = archive_append_fingerprint,
        .pending_archive_resulting_cursor = archive_resulting_cursor,
        .core_state = .failed,
        .previous_turn_receipt_fingerprint = duplicate_finalized_ref_receipt.receipt_fingerprint,
    });
    const duplicate_finalized_refs = [_]u64{ finalized_receipt_fingerprint, finalized_receipt_fingerprint };
    const duplicate_finalized_ref_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .source_state_fingerprint = 0xD296,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.failed, 8, duplicate_finalized_ref_receipt.receipt_fingerprint),
        .quiescence = output.quiescence,
        .status = .blocked,
        .finalized_actuation_receipt_fingerprints = &duplicate_finalized_refs,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .run_receipt_bytes = run_receipt_bytes,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .checkpoint = duplicate_finalized_ref_checkpoint,
        .turn_receipt = duplicate_finalized_ref_receipt,
        .blocker_count = 1,
        .warning_count = 1,
        .diagnostic_metadata = "blocked-by-host",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, duplicate_finalized_ref_output.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    const missing_finalized_ref = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .source_state_fingerprint = 0xD296,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.failed, 8, receipt.receipt_fingerprint),
        .quiescence = output.quiescence,
        .status = .blocked,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
        .blocker_count = 1,
        .warning_count = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, missing_finalized_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));
    try std.testing.expect(output.output_fingerprint != missing_finalized_ref.output_fingerprint);

    const zero_blocker_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .command_fingerprint = 0xD295,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .status = .blocked,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .warning_count = 1,
    });
    const zero_blocker_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .capsule_fingerprint = capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = archive_append_fingerprint,
        .pending_archive_resulting_cursor = archive_resulting_cursor,
        .core_state = .failed,
        .previous_turn_receipt_fingerprint = zero_blocker_receipt.receipt_fingerprint,
    });
    const blocked_without_blocker = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 8,
        .source_state_fingerprint = 0xD296,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.failed, 8, zero_blocker_receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .warning_count = 1,
        }),
        .status = .blocked,
        .run_receipt_fingerprint = run_receipt_fingerprint,
        .archive_append_batch_fingerprint = archive_append_fingerprint,
        .checkpoint = zero_blocker_checkpoint,
        .turn_receipt = zero_blocker_receipt,
        .warning_count = 1,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, blocked_without_blocker.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var mismatched_run_receipt = output;
    mismatched_run_receipt.run_receipt_fingerprint = run_receipt_fingerprint + 1;
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_run_receipt.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var forged_run_receipt_bytes = try std.testing.allocator.dupe(u8, run_receipt_bytes);
    defer std.testing.allocator.free(forged_run_receipt_bytes);
    forged_run_receipt_bytes[forged_run_receipt_bytes.len - 1] ^= 1;
    var mismatched_run_receipt_bytes = output;
    mismatched_run_receipt_bytes.run_receipt_bytes = forged_run_receipt_bytes;
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_run_receipt_bytes.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var mismatched_archive = output;
    mismatched_archive.archive_append_batch_fingerprint = archive_append_fingerprint + 1;
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_archive.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var missing_archive_ref = output;
    missing_archive_ref.archive_append_batch_ref_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_archive_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var orphan_archive_ref = output;
    orphan_archive_ref.archive_append_batch_fingerprint = null;
    try std.testing.expectError(error.InvalidFrameEncoding, orphan_archive_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var mismatched_archive_ref = output;
    mismatched_archive_ref.archive_append_batch_ref_fingerprint = archive_append_fingerprint + 2;
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_archive_ref.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var mismatched_blockers = output;
    mismatched_blockers.blocker_count = 0;
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_blockers.validate(manifest_fingerprint, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_metadata_bytes = 4;
    try std.testing.expectError(error.CapacityExceeded, output.validate(manifest_fingerprint, tight));
}

test "appliance archive RetentionAck validates append parent and capacity" {
    const ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = 0xD001,
        .resulting_moment_fingerprint = 0xD002,
        .resulting_seal_fingerprint = 0xD003,
        .resulting_chronicle_cursor_fingerprint = 0xD004,
        .host_claim_status = .responded,
        .metadata = "retained",
    });
    try ack.validate(0xD001, world.Appliance.Capacity.tiny_one_port);
    try std.testing.expectError(error.ArchiveParentMismatch, ack.validate(0xD099, world.Appliance.Capacity.tiny_one_port));
    const pending_ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = 0xD001,
        .resulting_moment_fingerprint = 0xD002,
        .resulting_seal_fingerprint = 0xD003,
        .resulting_chronicle_cursor_fingerprint = 0xD004,
        .host_claim_status = .pending,
        .metadata = "pending",
    });
    try std.testing.expectError(error.ArchiveParentMismatch, pending_ack.validate(0xD001, world.Appliance.Capacity.tiny_one_port));

    var tight = world.Appliance.Capacity.tiny_one_port;
    tight.max_metadata_bytes = 1;
    try std.testing.expectError(error.CapacityExceeded, ack.validate(0xD001, tight));
}

test "appliance archive plan commits turn evidence through Archive owner" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const quiescence = world.Appliance.QuiescenceReport.init(.{
        .quiescent = true,
        .completed_run_count = 1,
    });
    const capsule_fingerprint: u64 = 0xA001;
    const root_result_fingerprint: u64 = 0xA005;
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xA002,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    const output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xA003,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 1, receipt.receipt_fingerprint),
        .quiescence = quiescence,
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = checkpoint,
        .turn_receipt = receipt,
    });

    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();

    var plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        std.testing.allocator,
        archive.image.latestCursor(),
        output,
        capacity,
    );
    defer plan.deinit();

    try plan.append_batch.validate();
    const serialized_append_batch_len = try world.Archive.appendBatchSerializedByteLen(std.testing.allocator, plan.append_batch);
    try std.testing.expect(serialized_append_batch_len <= capacity.max_archive_append_bytes);
    const archive_append_batch_bytes = try world.Archive.encodeAppendBatchOwned(std.testing.allocator, plan.append_batch);
    defer std.testing.allocator.free(archive_append_batch_bytes);
    const archived_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xA002,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .archive_append_batch_fingerprint = plan.append_batch.append_batch_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const archived_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = plan.append_batch.append_batch_fingerprint,
        .pending_archive_resulting_cursor = plan.resulting_cursor,
        .core_state = .completed,
        .previous_turn_receipt_fingerprint = archived_receipt.receipt_fingerprint,
    });
    const output_with_archive_bytes = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xA003,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 1, archived_receipt.receipt_fingerprint),
        .quiescence = quiescence,
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .archive_append_batch_fingerprint = plan.append_batch.append_batch_fingerprint,
        .checkpoint = archived_checkpoint,
        .archive_append_batch_bytes = archive_append_batch_bytes,
        .turn_receipt = archived_receipt,
    });
    try output_with_archive_bytes.validate(manifest.manifest_fingerprint, capacity);
    var forged_archive_append_batch_bytes = try std.testing.allocator.dupe(u8, archive_append_batch_bytes);
    defer std.testing.allocator.free(forged_archive_append_batch_bytes);
    forged_archive_append_batch_bytes[forged_archive_append_batch_bytes.len - 1] ^= 1;
    var output_with_forged_archive_bytes = output_with_archive_bytes;
    output_with_forged_archive_bytes.archive_append_batch_bytes = forged_archive_append_batch_bytes;
    try std.testing.expectError(error.InvalidFrameEncoding, output_with_forged_archive_bytes.validate(manifest.manifest_fingerprint, capacity));
    var serialized_tight_capacity = capacity;
    serialized_tight_capacity.max_archive_append_bytes = serialized_append_batch_len - 1;
    try std.testing.expectError(
        error.CapacityExceeded,
        world.Appliance.ArchivePlan.initForTurnOutput(
            std.testing.allocator,
            archive.image.latestCursor(),
            output,
            serialized_tight_capacity,
        ),
    );
    try std.testing.expectEqual(@as(usize, 3), plan.objects.len);
    try std.testing.expectEqual(@as(usize, 1), plan.events.len);
    try std.testing.expectEqual(plan.parent_cursor.cursor_fingerprint, plan.append_batch.parent_cursor.cursor_fingerprint);
    try std.testing.expectEqual(plan.resulting_cursor.cursor_fingerprint, plan.append_batch.commit.resulting_cursor_fingerprint);
    try std.testing.expectEqual(@as(usize, 2), plan.objects[2].dependency_refs.len);
    try std.testing.expect(plan.objects[2].dependency_refs[0].eql(plan.object_refs[0]));
    try std.testing.expect(plan.objects[2].dependency_refs[1].eql(plan.object_refs[1]));
    var archived_output = try world.Appliance.TurnOutput.decodeArchivePayload(
        std.testing.allocator,
        plan.objects[2].payload_bytes,
    );
    defer archived_output.deinit(std.testing.allocator);

    const finalized_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .command_fingerprint = 0xA006,
        .applied_host_reply_fingerprints = &.{0xA007},
        .resulting_capsule_fingerprint = 0xA008,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const finalized_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .capsule_fingerprint = finalized_receipt.resulting_capsule_fingerprint,
        .previous_turn_receipt_fingerprint = finalized_receipt.receipt_fingerprint,
    });
    const finalized_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .source_state_fingerprint = 0xA009,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 2, finalized_receipt.receipt_fingerprint),
        .quiescence = quiescence,
        .status = .completed,
        .finalized_actuation_receipt_fingerprints = &.{0xA00A},
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = finalized_checkpoint,
        .turn_receipt = finalized_receipt,
    });
    try finalized_output.validate(manifest.manifest_fingerprint, capacity);
    var finalized_archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer finalized_archive.deinit();
    var finalized_plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        std.testing.allocator,
        finalized_archive.image.latestCursor(),
        finalized_output,
        capacity,
    );
    defer finalized_plan.deinit();
    try std.testing.expectEqual(@as(usize, 3), finalized_plan.objects[2].dependency_refs.len);
    var archived_finalized_output = try world.Appliance.TurnOutput.decodeArchivePayload(
        std.testing.allocator,
        finalized_plan.objects[2].payload_bytes,
    );
    defer archived_finalized_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), archived_finalized_output.turn_receipt.applied_host_reply_fingerprints.len);
    try std.testing.expectEqual(@as(u64, 0xA007), archived_finalized_output.turn_receipt.applied_host_reply_fingerprints[0]);
    try std.testing.expectEqual(@as(usize, 1), archived_finalized_output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expectEqual(@as(u64, 0xA00A), archived_finalized_output.finalized_actuation_receipt_fingerprints[0]);
    try std.testing.expectError(error.ObjectMissing, finalized_archive.appendBatch(finalized_plan.append_batch));

    for (plan.objects) |object| {
        try world.Continuity.validateObjectEnvelopeTypedPayload(std.testing.allocator, object);
        try world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, object);
    }
    try world.Continuity.validateObjectEnvelopeDependencyPayloads(std.testing.allocator, plan.objects, plan.objects[2]);

    const pending_cursor = world.Continuity.Chronicle.Cursor.initial();
    const pending_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = capsule_fingerprint,
        .pending_archive_append_batch_fingerprint = 0xA044,
        .pending_archive_resulting_cursor = pending_cursor,
        .core_state = .completed,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    const pending_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .source_state_fingerprint = 0xA003,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 1, receipt.receipt_fingerprint),
        .quiescence = quiescence,
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = pending_checkpoint,
        .turn_receipt = receipt,
    });
    try pending_output.validate(manifest.manifest_fingerprint, capacity);
    var pending_plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        std.testing.allocator,
        plan.resulting_cursor,
        pending_output,
        capacity,
    );
    defer pending_plan.deinit();
    var archived_pending_output = try world.Appliance.TurnOutput.decodeArchivePayload(
        std.testing.allocator,
        pending_plan.objects[2].payload_bytes,
    );
    defer archived_pending_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?u64, 0xA044), archived_pending_output.checkpoint.pending_archive_append_batch_fingerprint);
    try std.testing.expect(archived_pending_output.checkpoint.pending_archive_resulting_cursor != null);
    try std.testing.expectEqual(
        pending_cursor.cursor_fingerprint,
        archived_pending_output.checkpoint.pending_archive_resulting_cursor.?.cursor_fingerprint,
    );

    var zero_manifest_output = pending_output;
    zero_manifest_output.manifest_fingerprint = 0;
    zero_manifest_output.checkpoint.manifest_fingerprint = 0;
    zero_manifest_output.turn_receipt.manifest_fingerprint = 0;
    const zero_manifest_payload = try zero_manifest_output.encode(std.testing.allocator);
    defer std.testing.allocator.free(zero_manifest_payload);
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Appliance.TurnOutput.decodeArchivePayload(std.testing.allocator, zero_manifest_payload),
    );

    const large_metadata = try std.testing.allocator.alloc(u8, 70 * 1024);
    defer std.testing.allocator.free(large_metadata);
    @memset(large_metadata, 'm');
    var roomy_capacity = capacity;
    roomy_capacity.max_metadata_bytes = 128 * 1024;
    const large_metadata_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = archived_pending_output.turn_sequence_number,
        .source_state_fingerprint = archived_pending_output.source_state_fingerprint,
        .resulting_state_fingerprint = archived_pending_output.resulting_state_fingerprint,
        .quiescence = archived_pending_output.quiescence,
        .status = archived_pending_output.status,
        .host_requests = archived_pending_output.host_requests,
        .finalized_actuation_receipt_fingerprints = archived_pending_output.finalized_actuation_receipt_fingerprints,
        .root_result_fingerprint = archived_pending_output.root_result_fingerprint,
        .root_result_value_image_bytes = archived_pending_output.root_result_value_image_bytes,
        .root_result_value_ref_fingerprint = archived_pending_output.root_result_value_ref_fingerprint,
        .run_receipt_fingerprint = archived_pending_output.run_receipt_fingerprint,
        .run_receipt_bytes = archived_pending_output.run_receipt_bytes,
        .archive_append_batch_fingerprint = archived_pending_output.archive_append_batch_fingerprint,
        .archive_append_batch_ref_fingerprint = archived_pending_output.archive_append_batch_ref_fingerprint,
        .checkpoint_bytes = archived_pending_output.checkpoint_bytes,
        .archive_append_batch_bytes = archived_pending_output.archive_append_batch_bytes,
        .checkpoint = archived_pending_output.checkpoint,
        .turn_receipt = archived_pending_output.turn_receipt,
        .blocker_count = archived_pending_output.blocker_count,
        .warning_count = archived_pending_output.warning_count,
        .diagnostic_metadata = large_metadata,
    });
    try large_metadata_output.validate(manifest.manifest_fingerprint, roomy_capacity);
    const large_metadata_payload = try large_metadata_output.encode(std.testing.allocator);
    defer std.testing.allocator.free(large_metadata_payload);
    var archived_large_metadata_output = try world.Appliance.TurnOutput.decodeArchivePayload(
        std.testing.allocator,
        large_metadata_payload,
    );
    defer archived_large_metadata_output.deinit(std.testing.allocator);
    try std.testing.expectEqual(large_metadata.len, archived_large_metadata_output.diagnostic_metadata.len);
    const large_metadata_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_output,
        .object_format_version = world.world_appliance_turn_output_format_version,
        .payload_bytes = large_metadata_payload,
        .label = "archived appliance output with roomy metadata",
    });
    try world.Continuity.validateObjectEnvelopeTypedPayload(std.testing.allocator, large_metadata_envelope);

    const wrong_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .command_fingerprint = 0xA006,
        .resulting_capsule_fingerprint = capsule_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    var wrong_receipt_payload: std.ArrayList(u8) = .empty;
    defer wrong_receipt_payload.deinit(std.testing.allocator);
    try wrong_receipt.encode(&wrong_receipt_payload, std.testing.allocator);
    var forged_receipt_envelope = plan.objects[1];
    forged_receipt_envelope.payload_bytes = wrong_receipt_payload.items;
    const missing_checkpoint_with_bad_receipt = [_]world.Continuity.ObjectEnvelope{
        forged_receipt_envelope,
        plan.objects[2],
    };
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Continuity.validateObjectEnvelopeDependencyPayloads(
            std.testing.allocator,
            &missing_checkpoint_with_bad_receipt,
            plan.objects[2],
        ),
    );

    const malformed_output = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_output,
        .dependency_refs = plan.objects[2].dependency_refs,
        .payload_bytes = "not an appliance turn output",
        .label = "malformed appliance output",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, world.Continuity.validateObjectEnvelopeTypedPayload(std.testing.allocator, malformed_output));

    const missing_required_dependencies = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_output,
        .payload_bytes = plan.objects[2].payload_bytes,
        .label = "appliance output without deps",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, world.Continuity.validateObjectEnvelopeRequiredDependencies(std.testing.allocator, missing_required_dependencies));

    var vault = world.Continuity.MemoryVault.init(std.testing.allocator);
    defer vault.deinit();
    _ = try vault.put(plan.objects[0]);
    _ = try vault.put(plan.objects[1]);
    _ = try vault.put(plan.objects[2]);
    const output_ref = (try vault.refByKindFingerprint(.appliance_turn_output, archived_output.output_fingerprint)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(output_ref.eql(plan.objects[2].objectRef()));

    const wrong_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = checkpoint.turn_sequence_number + 1,
        .capsule_fingerprint = capsule_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    const wrong_output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number,
        .source_state_fingerprint = output.source_state_fingerprint,
        .resulting_state_fingerprint = output.resulting_state_fingerprint,
        .quiescence = output.quiescence,
        .status = output.status,
        .root_result_fingerprint = output.root_result_fingerprint,
        .checkpoint_bytes = plan.objects[0].payload_bytes,
        .checkpoint = wrong_checkpoint,
        .turn_receipt = output.turn_receipt,
    });
    const wrong_output_payload = try wrong_output.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_output_payload);
    const wrong_output_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_output,
        .dependency_refs = plan.objects[2].dependency_refs,
        .payload_bytes = wrong_output_payload,
        .label = "appliance output with mismatched checkpoint payload",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, vault.put(wrong_output_envelope));

    const moment = try archive.appendBatch(plan.append_batch);
    for (plan.object_refs) |ref| try std.testing.expect(archive.hasObject(ref));
    const seal = archive.image.latestSeal() orelse return error.ObjectMissing;
    const ack = world.Appliance.RetentionAck.init(.{
        .append_batch_fingerprint = plan.append_batch.append_batch_fingerprint,
        .resulting_moment_fingerprint = moment.moment_fingerprint,
        .resulting_seal_fingerprint = seal.seal_fingerprint,
        .resulting_chronicle_cursor_fingerprint = moment.chronicle_resulting_cursor.cursor_fingerprint,
        .host_claim_status = .responded,
    });
    try ack.validate(plan.append_batch.append_batch_fingerprint, capacity);
}

test "appliance reconstruction report binds resident and restored output fingerprints" {
    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    });
    const manifest = StrictAppliance.manifest();
    const equivalent = world.Appliance.ReconstructionReport.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .resident_turn_output_fingerprint = 0xE001,
        .reconstructed_turn_output_fingerprint = 0xE001,
    });
    try equivalent.validate(manifest.manifest_fingerprint);
    try std.testing.expect(equivalent.equivalent);
    try std.testing.expectEqual(@as(usize, 0), equivalent.mismatch_count);

    const mismatch = world.Appliance.ReconstructionReport.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .resident_turn_output_fingerprint = 0xE001,
        .reconstructed_turn_output_fingerprint = 0xE002,
    });
    try mismatch.validate(manifest.manifest_fingerprint);
    try std.testing.expect(!mismatch.equivalent);
    try std.testing.expectEqual(@as(usize, 1), mismatch.mismatch_count);
    try std.testing.expectError(error.WrongManifest, mismatch.validate(manifest.manifest_fingerprint + 1));
}

test "appliance conformance report binds native resident reconstructed replay archive and wasm evidence" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
    });
    const manifest = PortsAppliance.manifest();
    const capacity = world.Appliance.Capacity.tiny_one_port;
    const checkpoint_request = applianceManifestHostRequest(manifest, .{
        .turn_sequence_number = 1,
        .request_ordinal = 0,
        .run_handle_fingerprint = 0xC0F0_0010,
        .pending_port_fingerprint = 0xC0F0_0011,
        .intent_fingerprint = 0xC0F0_0012,
        .envelope_fingerprint = 0xC0F0_0013,
        .decision_fingerprint = 0xC0F0_0014,
        .expected_response_descriptor_fingerprint = manifest.actuation_descriptor_fingerprints[0],
        .idempotency_key_fingerprint = 0xC0F0_0016,
    });
    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .capsule_fingerprint = 0xC0F0_0001,
        .previous_turn_receipt_fingerprint = 0xC0F0_0002,
        .core_state = .waiting_host,
        .outstanding_host_requests = &.{checkpoint_request},
    });
    const checkpoint_reply = applianceHostReplyFor(checkpoint_request, 0xC0F0_0017);
    const command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint,
        .host_replies = &.{checkpoint_reply},
    });
    const command_bytes = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(command_bytes);

    var native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        capacity,
    ));
    defer native.core.reset();
    try native.core.restore(checkpoint);
    try native.core.submit(command_bytes);
    try native.core.executeTurn();
    const native_output_fingerprint = std.hash.Wyhash.hash(0, native.core.readOutput());

    var resident = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        capacity,
    );
    defer resident.reset();
    try resident.restore(checkpoint);
    try resident.submit(command_bytes);
    try resident.executeTurn();
    const resident_output_fingerprint = std.hash.Wyhash.hash(0, resident.readOutput());

    var reconstructed = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        capacity,
    );
    defer reconstructed.reset();
    try reconstructed.restore(checkpoint);
    try reconstructed.submit(command_bytes);
    try reconstructed.executeTurn();
    const reconstructed_output_fingerprint = std.hash.Wyhash.hash(0, reconstructed.readOutput());

    const root_result_fingerprint: u64 = 0xC0F0_0006;
    const output_capsule_fingerprint: u64 = 0xC0F0_0005;
    const output_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .command_fingerprint = command.command_fingerprint,
        .resulting_capsule_fingerprint = output_capsule_fingerprint,
        .root_result_fingerprint = root_result_fingerprint,
        .status = .completed,
    });
    const output = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 2,
        .source_state_fingerprint = 0xC0F0_0003,
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 2, output_receipt.receipt_fingerprint),
        .quiescence = world.Appliance.QuiescenceReport.init(.{
            .quiescent = true,
            .completed_run_count = 1,
        }),
        .status = .completed,
        .root_result_fingerprint = root_result_fingerprint,
        .checkpoint = world.Appliance.Checkpoint.init(.{
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = 2,
            .capsule_fingerprint = output_capsule_fingerprint,
            .previous_turn_receipt_fingerprint = output_receipt.receipt_fingerprint,
        }),
        .turn_receipt = output_receipt,
    });
    var archive = try world.Archive.Memory.open(std.testing.allocator, .{});
    defer archive.deinit();
    var archive_plan = try world.Appliance.ArchivePlan.initForTurnOutput(
        std.testing.allocator,
        archive.image.latestCursor(),
        output,
        capacity,
    );
    defer archive_plan.deinit();
    const moment = try archive.appendBatch(archive_plan.append_batch);

    const vector = world.Appliance.ConformanceVector.init(.{
        .kind = .reconstruction,
        .name = "core-reconstruction-archive-wasm",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .initial_command_fingerprint = command.command_fingerprint,
        .expected_turn_output_fingerprint = output.output_fingerprint,
        .expected_status_sequence = &.{.completed},
        .expected_checkpoint_fingerprints = &.{output.checkpoint.checkpoint_fingerprint},
        .expected_archive_append_fingerprint = archive_plan.append_batch.append_batch_fingerprint,
        .expected_archive_append_fingerprints = &.{archive_plan.append_batch.append_batch_fingerprint},
        .expected_resident_reconstructed_equivalence = true,
    });
    try vector.validate(manifest.manifest_fingerprint);
    var stale_vector = vector;
    stale_vector.expected_status_sequence = &.{.failed};
    try std.testing.expectError(error.InvalidFrameEncoding, stale_vector.validate(manifest.manifest_fingerprint));
    var zero_checkpoint_vector = vector;
    zero_checkpoint_vector.expected_checkpoint_fingerprints = &.{0};
    try std.testing.expectError(error.InvalidFrameEncoding, zero_checkpoint_vector.validate(manifest.manifest_fingerprint));

    const report = world.Appliance.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .direct_native_owner_output_fingerprint = native_output_fingerprint,
        .appliance_native_output_fingerprint = native_output_fingerprint,
        .native_core_output_fingerprint = native_output_fingerprint,
        .resident_core_output_fingerprint = resident_output_fingerprint,
        .reconstructed_core_output_fingerprint = reconstructed_output_fingerprint,
        .wasm_manifest_fingerprint = manifest.manifest_fingerprint,
        .wasm_required_exports_present = true,
        .wasm_forbidden_import_count = 0,
        .wasm_inspection_passed = true,
        .external_runtime_output_fingerprint = native_output_fingerprint,
        .replay_output_fingerprint = resident_output_fingerprint,
        .archive_append_batch_fingerprint = archive_plan.append_batch.append_batch_fingerprint,
        .archive_replay_projection_fingerprint = moment.chronicle_resulting_cursor.cursor_fingerprint,
    });
    try report.validate(manifest.manifest_fingerprint);
    try std.testing.expect(report.passed);
    var stale_report = report;
    stale_report.wasm_forbidden_import_count = 1;
    try std.testing.expectError(error.InvalidFrameEncoding, stale_report.validate(manifest.manifest_fingerprint));
    const missing_wasm_exports = world.Appliance.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .native_core_output_fingerprint = native_output_fingerprint,
        .resident_core_output_fingerprint = resident_output_fingerprint,
        .reconstructed_core_output_fingerprint = reconstructed_output_fingerprint,
        .wasm_manifest_fingerprint = manifest.manifest_fingerprint,
        .wasm_required_exports_present = false,
    });
    try missing_wasm_exports.validate(manifest.manifest_fingerprint);
    try std.testing.expect(!missing_wasm_exports.passed);
    const failed_wasm_inspection = world.Appliance.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .native_core_output_fingerprint = native_output_fingerprint,
        .resident_core_output_fingerprint = resident_output_fingerprint,
        .reconstructed_core_output_fingerprint = reconstructed_output_fingerprint,
        .wasm_manifest_fingerprint = manifest.manifest_fingerprint,
        .wasm_required_exports_present = true,
        .wasm_forbidden_import_count = 0,
        .wasm_inspection_passed = false,
    });
    try failed_wasm_inspection.validate(manifest.manifest_fingerprint);
    try std.testing.expect(!failed_wasm_inspection.passed);
    try std.testing.expectEqual(native_output_fingerprint, resident_output_fingerprint);
    try std.testing.expectEqual(native_output_fingerprint, reconstructed_output_fingerprint);
}

test "appliance Native exposes ABI-shaped operations over canonical Core output" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
        .metadata = "native-abi",
    });
    const manifest = PortsAppliance.manifest();
    const command = common_boot: {
        break :common_boot world.Appliance.Command.init(.{
            .kind = .boot,
            .manifest_fingerprint = manifest.manifest_fingerprint,
            .turn_sequence_number = 0,
        });
    };
    const command_bytes = try command.encode(std.testing.allocator);
    defer std.testing.allocator.free(command_bytes);

    var native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer native.core.reset();

    const expected_manifest_bytes = try manifest.encode(std.testing.allocator);
    defer std.testing.allocator.free(expected_manifest_bytes);
    try std.testing.expect(expected_manifest_bytes.len > @sizeOf(u64));
    try std.testing.expectEqual(expected_manifest_bytes.len, native.manifestLen());

    const manifest_bytes = try std.testing.allocator.alloc(u8, native.manifestLen());
    defer std.testing.allocator.free(manifest_bytes);
    try std.testing.expectEqual(expected_manifest_bytes.len, native.readManifest(manifest_bytes));
    try std.testing.expectEqualSlices(u8, expected_manifest_bytes, manifest_bytes);

    var manifest_too_small: [1]u8 = .{0xAA};
    try std.testing.expectEqual(expected_manifest_bytes.len, native.readManifest(&manifest_too_small));
    try std.testing.expectEqual(@as(u8, 0xAA), manifest_too_small[0]);

    try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, native.submitCommand(command_bytes));
    try std.testing.expect(native.outputLen() > 0);

    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    );
    defer core.reset();
    try core.submit(command_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(core.readOutput().len, native.outputLen());

    const native_output = try std.testing.allocator.alloc(u8, native.outputLen());
    defer std.testing.allocator.free(native_output);
    try std.testing.expectEqual(native.outputLen(), native.readOutput(native_output));
    try std.testing.expectEqualSlices(u8, core.readOutput(), native_output);

    var too_small: [1]u8 = .{0};
    try std.testing.expectEqual(native.outputLen(), native.readOutput(&too_small));

    const previous_len = native.outputLen();
    try std.testing.expectEqual(world.Appliance.Abi.Status.invalid_command, native.submitCommand("bad"));
    try std.testing.expectEqual(previous_len, native.outputLen());
    try std.testing.expectEqualStrings("submit.decode:InvalidFrameEncoding", native.lastErrorBytes());
    var last_error_too_small: [1]u8 = .{0xAA};
    try std.testing.expectEqual(native.lastErrorLen(), native.readLastError(&last_error_too_small));
    try std.testing.expectEqual(@as(u8, 0xAA), last_error_too_small[0]);
    var last_error_bytes: [64]u8 = undefined;
    const last_error_len = native.readLastError(&last_error_bytes);
    try std.testing.expectEqualStrings("submit.decode:InvalidFrameEncoding", last_error_bytes[0..last_error_len]);

    try std.testing.expectEqual(world.Appliance.Abi.Status.stale_turn, native.submitCommand(command_bytes));
    try std.testing.expectEqualStrings("submit.sequence:StaleTurn", native.lastErrorBytes());

    try std.testing.expectEqual(world.Appliance.Abi.Status.ok, native.reset());
    try std.testing.expectEqual(@as(usize, 0), native.outputLen());
    try std.testing.expectEqual(@as(usize, 0), native.lastErrorLen());
}

test "appliance Native legacy command clears stale turn closure cache" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
        .metadata = "native-legacy-closure-clear",
    });
    const manifest = PortsAppliance.manifest();

    var native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer native.deinit();
    try std.testing.expect(native.core.executable_image_fingerprint != 0);

    const wire_boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const wire_boot_bytes = try wire_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(wire_boot_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, native.submitTurn(wire_boot_bytes));
    try std.testing.expect(native.closureLen() > 0);

    const inspect = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = native.core.current_turn_sequence_number,
        .previous_turn_receipt_fingerprint = native.core.previous_turn_receipt_fingerprint,
    });
    const inspect_bytes = try inspect.encode(std.testing.allocator);
    defer std.testing.allocator.free(inspect_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.output_ready, native.submitCommand(inspect_bytes));
    try std.testing.expectEqual(@as(usize, 0), native.closureLen());

    try std.testing.expectEqual(world.Appliance.Abi.Status.invalid_command, native.submitCommand("bad"));
    try std.testing.expectEqual(@as(usize, 0), native.closureLen());
}

test "appliance Native submitTurn preserves closure on command validation failure" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
        .metadata = "native-submit-turn-command-failure-rollback",
    });
    const manifest = PortsAppliance.manifest();

    var native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer native.deinit();

    const wire_boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const wire_boot_bytes = try wire_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(wire_boot_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, native.submitTurn(wire_boot_bytes));

    const prior_turn_sequence_number = native.core.current_turn_sequence_number;
    const prior_receipt = native.core.previous_turn_receipt_fingerprint;
    const prior_output = try std.testing.allocator.dupe(u8, native.core.readOutput());
    defer std.testing.allocator.free(prior_output);
    const prior_closure = try std.testing.allocator.dupe(u8, native.last_closure_bytes);
    defer std.testing.allocator.free(prior_closure);
    const request = native.core.outstanding_host_request orelse return error.UnknownRequest;
    var response_image = try world.Frame.ValueImage.fromCanonicalBytes(
        std.testing.allocator,
        null,
        request.expected_response_value_ref_fingerprint,
        request.expected_response_schema_ref_fingerprint,
        "native-submit-turn-command-failure-response",
        false,
    );
    defer response_image.deinit(std.testing.allocator);
    const response_image_bytes = try response_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_image_bytes);
    const resolution = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .status = .responded,
        .response_value_image_bytes = response_image_bytes,
        .host_claim_bytes = "native-submit-turn-command-failure-host-claim",
        .attempt_number = 1,
    });
    const bad_continue = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = prior_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const bad_continue_bytes = try bad_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(bad_continue_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.invalid_command, native.submitTurn(bad_continue_bytes));
    try std.testing.expectEqualSlices(u8, prior_output, native.core.readOutput());
    try std.testing.expectEqualSlices(u8, prior_closure, native.last_closure_bytes);

    const good_continue = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .previous_turn_receipt_fingerprint = prior_receipt,
        .turn_sequence_number = prior_turn_sequence_number + 1,
        .resolutions = &.{resolution},
    });
    const good_continue_bytes = try good_continue.encode(std.testing.allocator);
    defer std.testing.allocator.free(good_continue_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.completed, native.submitTurn(good_continue_bytes));
}

test "appliance Native submitTurn rolls back closure materialization failure" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
        .metadata = "native-submit-turn-rollback",
    });
    const manifest = PortsAppliance.manifest();

    const wire_boot = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const wire_boot_bytes = try wire_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(wire_boot_bytes);

    var observed_closure_failure = false;
    var observed_success = false;
    var fail_offset: usize = 0;
    while (fail_offset < 1024 and !(observed_closure_failure and observed_success)) : (fail_offset += 1) {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = std.math.maxInt(usize),
        });
        var native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
            failing_allocator.allocator(),
            manifest,
            PortsAppliance.memoryPlan(),
            world.Appliance.Capacity.tiny_one_port,
        ));
        defer native.deinit();
        try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, native.submitTurn(wire_boot_bytes));

        const prior_turn_sequence_number = native.core.current_turn_sequence_number;
        const prior_receipt = native.core.previous_turn_receipt_fingerprint;
        const prior_state = native.core.state;
        const prior_output = try std.testing.allocator.dupe(u8, native.core.readOutput());
        defer std.testing.allocator.free(prior_output);
        const prior_closure = try std.testing.allocator.dupe(u8, native.last_closure_bytes);
        defer std.testing.allocator.free(prior_closure);
        const request = native.core.outstanding_host_request orelse return error.UnknownRequest;
        var response_image = try world.Frame.ValueImage.fromCanonicalBytes(
            std.testing.allocator,
            null,
            request.expected_response_value_ref_fingerprint,
            request.expected_response_schema_ref_fingerprint,
            "native-submit-turn-response",
            false,
        );
        defer response_image.deinit(std.testing.allocator);
        const response_image_bytes = try response_image.encode(std.testing.allocator);
        defer std.testing.allocator.free(response_image_bytes);
        const resolution = world.Appliance.Wire.ResolutionInput.init(.{
            .target_host_request_fingerprint = request.request_fingerprint,
            .status = .responded,
            .response_value_image_bytes = response_image_bytes,
            .host_claim_bytes = "native-submit-turn-host-claim",
            .attempt_number = 1,
        });
        const wire_continue = world.Appliance.Wire.TurnInput.init(.{
            .operation = .@"continue",
            .appliance_manifest_fingerprint = manifest.manifest_fingerprint,
            .previous_turn_receipt_fingerprint = prior_receipt,
            .turn_sequence_number = prior_turn_sequence_number + 1,
            .resolutions = &.{resolution},
        });
        const wire_continue_bytes = try wire_continue.encode(std.testing.allocator);
        defer std.testing.allocator.free(wire_continue_bytes);

        failing_allocator.fail_index = failing_allocator.alloc_index + fail_offset;
        const status = native.submitTurn(wire_continue_bytes);
        if (status == .capacity_exceeded and std.mem.startsWith(u8, native.lastErrorBytes(), "submit.closure:")) {
            observed_closure_failure = true;
            try std.testing.expect(failing_allocator.has_induced_failure);
            try std.testing.expectEqual(prior_state, native.core.state);
            try std.testing.expectEqual(prior_turn_sequence_number, native.core.current_turn_sequence_number);
            try std.testing.expectEqual(prior_receipt, native.core.previous_turn_receipt_fingerprint);
            try std.testing.expectEqualSlices(u8, prior_output, native.core.readOutput());
            try std.testing.expectEqualSlices(u8, prior_closure, native.last_closure_bytes);

            failing_allocator.fail_index = std.math.maxInt(usize);
            try std.testing.expectEqual(world.Appliance.Abi.Status.completed, native.submitTurn(wire_continue_bytes));
            continue;
        }
        if (failing_allocator.has_induced_failure) continue;
        try std.testing.expectEqual(world.Appliance.Abi.Status.completed, status);
        observed_success = true;
    }

    try std.testing.expect(observed_closure_failure);
    try std.testing.expect(observed_success);
}

test "appliance Native submit status preserves canonical TurnOutput status" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
        .metadata = "native-status-ports",
    });
    const ports_manifest = PortsAppliance.manifest();
    const fresh_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = ports_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .fresh,
    });
    const fresh_boot_bytes = try fresh_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(fresh_boot_bytes);
    var needs_host_native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        ports_manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer needs_host_native.core.reset();
    try std.testing.expectEqual(world.Appliance.Abi.Status.needs_host, needs_host_native.submitCommand(fresh_boot_bytes));

    const missing_replay = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = ports_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .execution_mode = .replay,
    });
    const missing_replay_bytes = try missing_replay.encode(std.testing.allocator);
    defer std.testing.allocator.free(missing_replay_bytes);
    var blocked_native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        ports_manifest,
        PortsAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer blocked_native.core.reset();
    try std.testing.expectEqual(world.Appliance.Abi.Status.invalid_command, blocked_native.submitCommand(missing_replay_bytes));
    try std.testing.expectEqual(world.Appliance.CoreState.uninitialized, blocked_native.core.state);
    try std.testing.expect(blocked_native.lastErrorLen() != 0);

    const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .metadata = "native-status-strict",
    });
    const strict_manifest = StrictAppliance.manifest();
    const strict_boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = strict_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const strict_boot_bytes = try strict_boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(strict_boot_bytes);
    var completed_native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        strict_manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer completed_native.core.reset();
    try std.testing.expectEqual(world.Appliance.Abi.Status.completed, completed_native.submitCommand(strict_boot_bytes));
    const inspect_completed = world.Appliance.Command.init(.{
        .kind = .inspect,
        .manifest_fingerprint = strict_manifest.manifest_fingerprint,
        .turn_sequence_number = completed_native.core.current_turn_sequence_number,
        .previous_turn_receipt_fingerprint = completed_native.core.previous_turn_receipt_fingerprint,
    });
    const inspect_completed_bytes = try inspect_completed.encode(std.testing.allocator);
    defer std.testing.allocator.free(inspect_completed_bytes);
    try std.testing.expectEqual(world.Appliance.Abi.Status.output_ready, completed_native.submitCommand(inspect_completed_bytes));

    const cancel = world.Appliance.Command.init(.{
        .kind = .cancel,
        .manifest_fingerprint = strict_manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
    const cancel_bytes = try cancel.encode(std.testing.allocator);
    defer std.testing.allocator.free(cancel_bytes);
    var cancelled_native = world.Appliance.Native.init(world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        strict_manifest,
        StrictAppliance.memoryPlan(),
        world.Appliance.Capacity.tiny_one_port,
    ));
    defer cancelled_native.core.reset();
    try std.testing.expectEqual(world.Appliance.Abi.Status.cancelled, cancelled_native.submitCommand(cancel_bytes));
}

test "appliance Define requires explicit strict actuation bindings and derives dense evidence" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "ports-appliance",
    });
    const manifest = PortsAppliance.manifest();
    const binding = ApplianceActuationBinding.actuationBindingRecord();
    const descriptor = ApplianceActuationBinding.actuationDescriptor();

    try manifest.validate();
    try std.testing.expectEqual(@as(usize, 1), PortsAppliance.definitionReport().root_world_port_count);
    try std.testing.expectEqual(@as(usize, 1), PortsAppliance.definitionReport().actuation_binding_count);
    try std.testing.expectEqual(@as(usize, 1), manifest.actuation_binding_fingerprints.len);
    try std.testing.expectEqual(binding.binding_fingerprint, manifest.actuation_binding_fingerprints[0]);
    try std.testing.expectEqual(descriptor.descriptor_fingerprint, manifest.actuation_descriptor_fingerprints[0]);
    try std.testing.expectEqual(world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint, manifest.residual_import_set_fingerprint);
}

test "appliance manifest allows distinct bindings on the same world port" {
    const AgentAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.wasm_agent,
        .actuation_bindings = .{
            ApplianceAgentActuationBinding,
            ApplianceAgentToolActuationBinding,
        },
    });
    const manifest = AgentAppliance.manifest();
    try std.testing.expectEqual(@as(usize, 2), manifest.actuation_binding_fingerprints.len);

    const duplicate_world_port_ids = [_]u64{
        manifest.actuation_world_port_ids[0],
        manifest.actuation_world_port_ids[0],
    };
    const same_port_manifest = applianceManifestVariant(manifest, .{
        .actuation_world_port_ids = &duplicate_world_port_ids,
    });

    try same_port_manifest.validate();
    try std.testing.expect(same_port_manifest.actuation_binding_fingerprints[0] != same_port_manifest.actuation_binding_fingerprints[1]);
}

test "appliance manifest rejects multiple runtime actuation bindings" {
    const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
        .profile = world.Appliance.Profile.wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
        .actuation_bindings = .{ApplianceActuationBinding},
        .metadata = "ports-appliance",
    });
    const manifest = PortsAppliance.manifest();
    const descriptor_fingerprints = [_]u64{
        manifest.actuation_descriptor_fingerprints[0],
        manifest.actuation_descriptor_fingerprints[0] ^ 0x10,
    };
    const binding_fingerprints = [_]u64{
        manifest.actuation_binding_fingerprints[0],
        manifest.actuation_binding_fingerprints[0] ^ 0x10,
    };
    const actuator_ref_fingerprints = [_]u64{
        manifest.actuation_actuator_ref_fingerprints[0],
        manifest.actuation_actuator_ref_fingerprints[0] ^ 0x10,
    };
    const actuation_classes = [_]world.Actuation.Class{ .deterministic_fixture, .deterministic_fixture };
    const allowed_response_statuses = [_]world.Actuation.ResponseStatusSet{ .terminal_with_errors, .terminal_with_errors };
    const multi_binding_manifest = applianceManifestVariant(manifest, .{
        .actuation_descriptor_fingerprints = &descriptor_fingerprints,
        .actuation_binding_fingerprints = &binding_fingerprints,
        .actuation_actuator_ref_fingerprints = &actuator_ref_fingerprints,
        .actuation_classes = &actuation_classes,
        .actuation_allowed_response_statuses = &allowed_response_statuses,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, multi_binding_manifest.validate());

    const zero_provider_manifest = applianceManifestVariant(manifest, .{
        .provider_target_ref_fingerprints = &.{0},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, zero_provider_manifest.validate());

    const zero_fabric_manifest = applianceManifestVariant(manifest, .{
        .fabric_plan_fingerprints = &.{0},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, zero_fabric_manifest.validate());

    const zero_default_permit_manifest = applianceManifestVariant(manifest, .{
        .default_permit_requirement_fingerprints = &.{0},
    });
    try std.testing.expectError(error.InvalidFrameEncoding, zero_default_permit_manifest.validate());

    var replay_modes = manifest.supported_execution_modes;
    replay_modes.replay = true;
    const replay_advertised_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = replay_modes,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, replay_advertised_manifest.validate());

    var verify_modes = manifest.supported_execution_modes;
    verify_modes.verify = true;
    const verify_advertised_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = verify_modes,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, verify_advertised_manifest.validate());

    var audit_modes = manifest.supported_execution_modes;
    audit_modes.audit = true;
    const audit_advertised_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = audit_modes,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, audit_advertised_manifest.validate());

    var no_fresh_modes = manifest.supported_execution_modes;
    no_fresh_modes.fresh = false;
    const no_fresh_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = no_fresh_modes,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, no_fresh_manifest.validate());

    var replay_evidence_capabilities = manifest.required_host_capabilities;
    replay_evidence_capabilities.replay_evidence = true;
    const replay_evidence_manifest = applianceManifestVariant(manifest, .{
        .required_host_capabilities = replay_evidence_capabilities,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, replay_evidence_manifest.validate());

    var actuated_replay_modes = manifest.supported_execution_modes;
    actuated_replay_modes.replay = true;
    var actuated_replay_capabilities = manifest.required_host_capabilities;
    actuated_replay_capabilities.replay_evidence = true;
    const actuated_replay_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = actuated_replay_modes,
        .required_host_capabilities = actuated_replay_capabilities,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, actuated_replay_manifest.validate());

    var hidden_actuation_capabilities = manifest.required_host_capabilities;
    hidden_actuation_capabilities.actuation = false;
    const hidden_actuation_manifest = applianceManifestVariant(manifest, .{
        .required_host_capabilities = hidden_actuation_capabilities,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, hidden_actuation_manifest.validate());

    var disabled_actuation_features = manifest.enabled_features;
    disabled_actuation_features.actuation = false;
    const disabled_actuation_manifest = applianceManifestVariant(manifest, .{
        .enabled_features = disabled_actuation_features,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, disabled_actuation_manifest.validate());

    var reserved_modes = manifest.supported_execution_modes;
    reserved_modes._reserved = 1;
    const reserved_modes_manifest = applianceManifestVariant(manifest, .{
        .supported_execution_modes = reserved_modes,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, reserved_modes_manifest.validate());

    var reserved_features = manifest.enabled_features;
    reserved_features._reserved = 1;
    const reserved_features_manifest = applianceManifestVariant(manifest, .{
        .enabled_features = reserved_features,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, reserved_features_manifest.validate());

    var reserved_capabilities = manifest.required_host_capabilities;
    reserved_capabilities._reserved = 1;
    const reserved_capabilities_manifest = applianceManifestVariant(manifest, .{
        .required_host_capabilities = reserved_capabilities,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, reserved_capabilities_manifest.validate());
}

fn applianceTestCapsuleBytes(allocator: std.mem.Allocator, metadata: []const u8) ![]const u8 {
    const manifest = world.Capsule.Manifest.init(.{
        .kind = .reference_only,
        .root_target_ref_fingerprint = 0xC105_0001,
        .normal_form = .quiescent_completed,
        .metadata = metadata,
    });
    const runspace_image = world.Capsule.RunspaceImage.init(.{
        .runspace_fingerprint = 0xC105_0002,
        .runspace_report_fingerprint = 0xC105_0003,
        .metadata = metadata,
    });
    const image = world.Capsule.Image.init(.{
        .manifest = manifest,
        .runspace_image = runspace_image,
        .metadata = metadata,
    });
    try image.validate(.{});
    return image.encode(allocator);
}

fn applianceTestWriteU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn applianceTestWriteU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn applianceTestWriteBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    if (bytes.len > std.math.maxInt(u32)) return error.CapacityExceeded;
    try applianceTestWriteU32(out, allocator, @intCast(bytes.len));
    try out.appendSlice(allocator, bytes);
}

fn applianceTestReadU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* + 1 > bytes.len) return error.InvalidFrameEncoding;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn applianceTestReadU32(bytes: []const u8, cursor: *usize) !u32 {
    if (cursor.* + 4 > bytes.len) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u32, bytes[cursor.*..][0..4], .little);
    cursor.* += 4;
    return value;
}

fn applianceTestReadU64(bytes: []const u8, cursor: *usize) !u64 {
    if (cursor.* + 8 > bytes.len) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u64, bytes[cursor.*..][0..8], .little);
    cursor.* += 8;
    return value;
}

fn applianceTestSkipOptionalU64(bytes: []const u8, cursor: *usize) !void {
    switch (try applianceTestReadU8(bytes, cursor)) {
        0 => {},
        1 => _ = try applianceTestReadU64(bytes, cursor),
        else => return error.InvalidFrameEncoding,
    }
}

fn applianceTestSkipBytes(bytes: []const u8, cursor: *usize) !void {
    const len = try applianceTestReadU32(bytes, cursor);
    if (cursor.* + len > bytes.len) return error.InvalidFrameEncoding;
    cursor.* += len;
}

fn applianceTestSkipU64Slice(bytes: []const u8, cursor: *usize) !void {
    const count = try applianceTestReadU64(bytes, cursor);
    if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
    const byte_len = try std.math.mul(usize, @as(usize, @intCast(count)), @sizeOf(u64));
    if (cursor.* + byte_len > bytes.len) return error.InvalidFrameEncoding;
    cursor.* += byte_len;
}

fn applianceTestTurnClosureFinalizedReceiptBytesCountOffset(bytes: []const u8) !usize {
    var cursor: usize = 0;
    _ = try applianceTestReadU32(bytes, &cursor);
    _ = try applianceTestReadU32(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    _ = try applianceTestReadU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipOptionalU64(bytes, &cursor);
    try applianceTestSkipBytes(bytes, &cursor);
    try applianceTestSkipU64Slice(bytes, &cursor);
    return cursor;
}

fn applianceTestRootResultValueImageBytes(allocator: std.mem.Allocator, fingerprint: u64) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try applianceTestWriteBytes(&out, allocator, "world.appliance.root_result.value_image");
    try applianceTestWriteU64(&out, allocator, fingerprint);
    return out.toOwnedSlice(allocator);
}

fn applianceTestClosureBundleBytes(
    allocator: std.mem.Allocator,
    checkpoint_bytes: []const u8,
    turn_receipt_bytes: []const u8,
    capsule_bytes: []const u8,
    root_result_bytes: []const u8,
    actuation_receipt_bytes: []const u8,
) ![]const u8 {
    const checkpoint_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_checkpoint,
        .payload_bytes = checkpoint_bytes,
        .label = "checkpoint",
    });
    const receipt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_receipt,
        .payload_bytes = turn_receipt_bytes,
        .label = "receipt",
    });
    const capsule_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .object_format_version = world.world_capsule_image_format_version,
        .payload_bytes = capsule_bytes,
        .label = "capsule",
    });
    const root_result_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .root_result,
        .payload_bytes = root_result_bytes,
        .label = "root-result",
    });
    const actuation_receipt_envelope_without_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .payload_bytes = actuation_receipt_bytes,
        .label = "actuation-receipt",
    });
    const actuation_receipt_deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, actuation_receipt_envelope_without_deps);
    defer allocator.free(actuation_receipt_deps);
    const actuation_receipt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .dependency_refs = actuation_receipt_deps,
        .payload_bytes = actuation_receipt_bytes,
        .label = "actuation-receipt",
    });
    const roots = [_]world.Continuity.ObjectRef{
        checkpoint_envelope.objectRef(),
        receipt_envelope.objectRef(),
        capsule_envelope.objectRef(),
        root_result_envelope.objectRef(),
        actuation_receipt_envelope.objectRef(),
    };
    var envelopes = [_]world.Continuity.ObjectEnvelope{
        checkpoint_envelope,
        receipt_envelope,
        capsule_envelope,
        root_result_envelope,
        actuation_receipt_envelope,
    };
    const bundle = world.Continuity.Bundle{
        .allocator = allocator,
        .manifest = world.Continuity.BundleManifest.init(.{ .roots = &roots, .object_count = envelopes.len }),
        .envelopes = &envelopes,
    };
    return bundle.toBytes(allocator);
}

fn applianceTestClosureBundleBytesWithRunReceipt(
    allocator: std.mem.Allocator,
    checkpoint_bytes: []const u8,
    turn_receipt_bytes: []const u8,
    capsule_bytes: []const u8,
    root_result_bytes: []const u8,
    actuation_receipt_bytes: []const u8,
    run_receipt_bytes: []const u8,
) ![]const u8 {
    const checkpoint_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_checkpoint,
        .payload_bytes = checkpoint_bytes,
        .label = "checkpoint",
    });
    const receipt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_receipt,
        .payload_bytes = turn_receipt_bytes,
        .label = "receipt",
    });
    const capsule_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .capsule_image,
        .object_format_version = world.world_capsule_image_format_version,
        .payload_bytes = capsule_bytes,
        .label = "capsule",
    });
    const root_result_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .root_result,
        .payload_bytes = root_result_bytes,
        .label = "root-result",
    });
    const actuation_receipt_envelope_without_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .payload_bytes = actuation_receipt_bytes,
        .label = "actuation-receipt",
    });
    const actuation_receipt_deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, actuation_receipt_envelope_without_deps);
    defer allocator.free(actuation_receipt_deps);
    const actuation_receipt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .actuation_receipt,
        .dependency_refs = actuation_receipt_deps,
        .payload_bytes = actuation_receipt_bytes,
        .label = "actuation-receipt",
    });
    const run_receipt_envelope_without_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .run_receipt,
        .payload_bytes = run_receipt_bytes,
        .label = "run-receipt",
    });
    const run_receipt_deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, run_receipt_envelope_without_deps);
    defer allocator.free(run_receipt_deps);
    const run_receipt_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .run_receipt,
        .dependency_refs = run_receipt_deps,
        .payload_bytes = run_receipt_bytes,
        .label = "run-receipt",
    });
    const roots = [_]world.Continuity.ObjectRef{
        checkpoint_envelope.objectRef(),
        receipt_envelope.objectRef(),
        capsule_envelope.objectRef(),
        root_result_envelope.objectRef(),
        actuation_receipt_envelope.objectRef(),
        run_receipt_envelope.objectRef(),
    };
    var envelopes = [_]world.Continuity.ObjectEnvelope{
        checkpoint_envelope,
        receipt_envelope,
        capsule_envelope,
        root_result_envelope,
        actuation_receipt_envelope,
        run_receipt_envelope,
    };
    const bundle = world.Continuity.Bundle{
        .allocator = allocator,
        .manifest = world.Continuity.BundleManifest.init(.{ .roots = &roots, .object_count = envelopes.len }),
        .envelopes = &envelopes,
    };
    return bundle.toBytes(allocator);
}

fn applianceTurnClosureFixture(allocator: std.mem.Allocator) !struct {
    closure: world.Appliance.TurnClosure,
    capsule_bytes: []const u8,
    checkpoint_bytes: []const u8,
    turn_receipt_bytes: []const u8,
    actuation_receipt_fingerprints: []const u64,
    actuation_receipt_byte_slices: []const []const u8,
    actuation_receipt_bytes: []const u8,
    root_result_bytes: []const u8,
    bundle_bytes: []const u8,
} {
    const manifest_fingerprint: u64 = 0xD7C1;
    const executable_fingerprint: u64 = 0xE7C1;
    const root_result_value_fingerprint: u64 = 0xD7C3;
    const root_result_bytes = try applianceTestRootResultValueImageBytes(allocator, root_result_value_fingerprint);
    errdefer allocator.free(root_result_bytes);
    const root_result_ref = world.Continuity.ObjectRef.fromPayload(.root_result, world.Continuity.ObjectKind.root_result.defaultFormatVersion(), root_result_bytes, "root.result");
    const root_result_fingerprint = root_result_ref.object_fingerprint;

    const capsule_bytes = try applianceTestCapsuleBytes(allocator, "turn-closure");
    errdefer allocator.free(capsule_bytes);
    const capsule_ref = world.Continuity.ObjectRef.fromPayload(.capsule_image, world.world_capsule_image_format_version, capsule_bytes, "capsule.image");

    const applied_host_reply_fingerprints = [_]u64{0xA7C0};
    const receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .command_fingerprint = 0xD7C2,
        .applied_host_reply_fingerprints = applied_host_reply_fingerprints[0..],
        .resulting_capsule_fingerprint = capsule_ref.object_fingerprint,
        .root_result_fingerprint = root_result_value_fingerprint,
        .status = .completed,
    });
    var receipt_payload: std.ArrayList(u8) = .empty;
    defer receipt_payload.deinit(allocator);
    try receipt.encode(&receipt_payload, allocator);
    const turn_receipt_bytes = try allocator.dupe(u8, receipt_payload.items);
    errdefer allocator.free(turn_receipt_bytes);

    const actuation_receipt = world.Actuation.Receipt.init(.{
        .intent_fingerprint = 0xA7C1,
        .envelope_fingerprint = 0xA7C2,
        .decision_fingerprint = 0xA7C3,
        .commit_fingerprint = 0xA7C4,
        .response_fingerprint = 0xA7C5,
        .frame_response_fingerprint = 0xA7C6,
        .actuator_ref_fingerprint = 0xA7C7,
        .idempotency_key_fingerprint = 0xA7C8,
        .request_fingerprint = 0xA7C9,
        .target_ref_fingerprint = 0xA7CA,
        .world_surface_fingerprint = 0xA7CB,
        .world_port_id = 1,
        .class = .deterministic_fixture,
        .mode = .fresh,
        .fresh_called = true,
    });
    const actuation_receipt_bytes = try actuation_receipt.encode(allocator);
    errdefer allocator.free(actuation_receipt_bytes);
    const actuation_receipt_fingerprints = try allocator.alloc(u64, 1);
    errdefer allocator.free(actuation_receipt_fingerprints);
    actuation_receipt_fingerprints[0] = actuation_receipt.receipt_fingerprint;
    const actuation_receipt_byte_slices = try allocator.alloc([]const u8, 1);
    errdefer allocator.free(actuation_receipt_byte_slices);
    actuation_receipt_byte_slices[0] = actuation_receipt_bytes;

    const checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .capsule_fingerprint = capsule_ref.object_fingerprint,
        .previous_turn_receipt_fingerprint = receipt.receipt_fingerprint,
    });
    var checkpoint_payload: std.ArrayList(u8) = .empty;
    defer checkpoint_payload.deinit(allocator);
    try checkpoint.encode(&checkpoint_payload, allocator);
    const checkpoint_bytes = try allocator.dupe(u8, checkpoint_payload.items);
    errdefer allocator.free(checkpoint_bytes);

    const bundle_bytes = try applianceTestClosureBundleBytes(allocator, checkpoint_bytes, turn_receipt_bytes, capsule_bytes, root_result_bytes, actuation_receipt_bytes);
    errdefer allocator.free(bundle_bytes);

    const initial_cursor_fingerprint = world.Continuity.Chronicle.Cursor.initial().cursor_fingerprint;
    const closure = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = executable_fingerprint,
        .appliance_manifest_fingerprint = manifest_fingerprint,
        .turn_sequence_number = 0,
        .parent_state_fingerprint = world.Appliance.coreStateFingerprint(.uninitialized, 0, null),
        .resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, 0, receipt.receipt_fingerprint),
        .chronicle_parent_cursor_fingerprint = initial_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = initial_cursor_fingerprint,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .checkpoint_bytes = checkpoint_bytes,
        .capsule_fingerprint = capsule_ref.object_fingerprint,
        .capsule_bytes = capsule_bytes,
        .turn_receipt_fingerprint = receipt.receipt_fingerprint,
        .turn_receipt_bytes = turn_receipt_bytes,
        .evidence_bundle_bytes = bundle_bytes,
        .root_result_fingerprint = root_result_fingerprint,
        .root_result_bytes = root_result_bytes,
        .root_result_value_ref_fingerprint = root_result_ref.ref_fingerprint,
        .finalized_actuation_receipt_fingerprints = actuation_receipt_fingerprints,
        .finalized_actuation_receipt_bytes = actuation_receipt_byte_slices,
        .status = .completed,
    });
    return .{
        .closure = closure,
        .capsule_bytes = capsule_bytes,
        .checkpoint_bytes = checkpoint_bytes,
        .turn_receipt_bytes = turn_receipt_bytes,
        .actuation_receipt_fingerprints = actuation_receipt_fingerprints,
        .actuation_receipt_byte_slices = actuation_receipt_byte_slices,
        .actuation_receipt_bytes = actuation_receipt_bytes,
        .root_result_bytes = root_result_bytes,
        .bundle_bytes = bundle_bytes,
    };
}

fn applianceTestRecomputedTurnClosure(closure: world.Appliance.TurnClosure) world.Appliance.TurnClosure {
    return world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = closure.executable_image_fingerprint,
        .appliance_manifest_fingerprint = closure.appliance_manifest_fingerprint,
        .parent_closure_fingerprint = closure.parent_closure_fingerprint,
        .turn_sequence_number = closure.turn_sequence_number,
        .parent_state_fingerprint = closure.parent_state_fingerprint,
        .resulting_state_fingerprint = closure.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = closure.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = closure.chronicle_resulting_cursor_fingerprint,
        .archive_parent_moment_fingerprint = closure.archive_parent_moment_fingerprint,
        .archive_parent_seal_fingerprint = closure.archive_parent_seal_fingerprint,
        .archive_resulting_moment_fingerprint = closure.archive_resulting_moment_fingerprint,
        .archive_resulting_seal_fingerprint = closure.archive_resulting_seal_fingerprint,
        .checkpoint_fingerprint = closure.checkpoint_fingerprint,
        .checkpoint_bytes = closure.checkpoint_bytes,
        .capsule_fingerprint = closure.capsule_fingerprint,
        .capsule_bytes = closure.capsule_bytes,
        .turn_receipt_fingerprint = closure.turn_receipt_fingerprint,
        .turn_receipt_bytes = closure.turn_receipt_bytes,
        .evidence_bundle_bytes = closure.evidence_bundle_bytes,
        .archive_append_batch_fingerprint = closure.archive_append_batch_fingerprint,
        .archive_append_batch_bytes = closure.archive_append_batch_bytes,
        .pending_host_request_bytes = closure.pending_host_request_bytes,
        .root_result_fingerprint = closure.root_result_fingerprint,
        .root_result_bytes = closure.root_result_bytes,
        .root_result_value_ref_fingerprint = closure.root_result_value_ref_fingerprint,
        .run_receipt_fingerprint = closure.run_receipt_fingerprint,
        .run_receipt_bytes = closure.run_receipt_bytes,
        .finalized_actuation_receipt_fingerprints = closure.finalized_actuation_receipt_fingerprints,
        .finalized_actuation_receipt_bytes = closure.finalized_actuation_receipt_bytes,
        .replay_receipt_fingerprints = closure.replay_receipt_fingerprints,
        .replay_receipt_bytes = closure.replay_receipt_bytes,
        .verify_report_fingerprints = closure.verify_report_fingerprints,
        .blockers = closure.blockers,
        .warnings = closure.warnings,
        .diagnostics = closure.diagnostics,
        .status = closure.status,
    });
}

test "appliance TurnClosure complete one-port closure validates" {
    const allocator = std.testing.allocator;
    const fixture = try applianceTurnClosureFixture(allocator);
    defer allocator.free(fixture.capsule_bytes);
    defer allocator.free(fixture.checkpoint_bytes);
    defer allocator.free(fixture.turn_receipt_bytes);
    defer allocator.free(fixture.actuation_receipt_fingerprints);
    defer allocator.free(fixture.actuation_receipt_byte_slices);
    defer allocator.free(fixture.actuation_receipt_bytes);
    defer allocator.free(fixture.root_result_bytes);
    defer allocator.free(fixture.bundle_bytes);

    const external_dependency_options = world.Appliance.TurnClosureValidation{
        .limits = .archive_decode,
        .bundle_options = .{ .allow_external_dependencies = true },
    };
    try std.testing.expectError(error.InvalidFrameEncoding, fixture.closure.validate(allocator, .{ .limits = .archive_decode }));
    try fixture.closure.validate(allocator, .{
        .expected_executable_image_fingerprint = fixture.closure.executable_image_fingerprint,
        .expected_manifest_fingerprint = fixture.closure.appliance_manifest_fingerprint,
        .limits = .archive_decode,
        .bundle_options = .{ .allow_external_dependencies = true },
    });
    const report = try fixture.closure.validationReport(allocator, external_dependency_options);
    try report.validate();
    try std.testing.expect(report.valid);

    const encoded = try fixture.closure.encode(allocator);
    defer allocator.free(encoded);
    var decoded = try world.Appliance.TurnClosure.decode(allocator, encoded);
    defer decoded.deinit(allocator);
    try decoded.validate(allocator, external_dependency_options);
    var archived = try world.Appliance.TurnClosure.decodeArchivePayload(allocator, encoded);
    defer archived.deinit(allocator);
    const closure_envelope_without_deps = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_closure,
        .payload_bytes = encoded,
        .label = "turn-closure",
    });
    const closure_deps = try world.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, closure_envelope_without_deps);
    defer allocator.free(closure_deps);
    var closure_envelope = world.Continuity.ObjectEnvelope.init(.{
        .kind = .appliance_turn_closure,
        .dependency_refs = closure_deps,
        .payload_bytes = encoded,
        .label = "turn-closure",
    });
    var closure_envelopes = [_]world.Continuity.ObjectEnvelope{closure_envelope};
    var closure_bundle = world.Continuity.Bundle{
        .allocator = allocator,
        .manifest = world.Continuity.BundleManifest.init(.{
            .roots = &.{closure_envelope.objectRef()},
            .object_count = 1,
        }),
        .envelopes = &closure_envelopes,
    };
    const closure_bundle_bytes = try closure_bundle.toBytes(allocator);
    defer allocator.free(closure_bundle_bytes);
    const closure_bundle_report = try world.Continuity.Bundle.validate(allocator, closure_bundle_bytes, .{ .allow_external_dependencies = true });
    try std.testing.expect(closure_bundle_report.valid);
    try std.testing.expect(closure_bundle_report.missing_dependency_count != 0);
    try std.testing.expectEqual(fixture.closure.closure_fingerprint, decoded.closure_fingerprint);
    try std.testing.expectEqual(fixture.closure.closure_fingerprint, archived.closure_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.finalized_actuation_receipt_bytes.len);
    var actuation_receipt = try world.Actuation.Receipt.decode(allocator, decoded.finalized_actuation_receipt_bytes[0]);
    defer actuation_receipt.deinit(allocator);
    try std.testing.expectEqual(decoded.finalized_actuation_receipt_fingerprints[0], actuation_receipt.receipt_fingerprint);

    const materialized_checkpoint = try decoded.materializeCheckpoint(allocator);
    defer allocator.free(materialized_checkpoint);
    try std.testing.expectEqualSlices(u8, fixture.checkpoint_bytes, materialized_checkpoint);
    const materialized_capsule = try decoded.materializeCapsule(allocator);
    defer allocator.free(materialized_capsule);
    try std.testing.expectEqualSlices(u8, fixture.capsule_bytes, materialized_capsule);

    var child = fixture.closure;
    child.parent_closure_fingerprint = fixture.closure.closure_fingerprint;
    child.turn_sequence_number = fixture.closure.turn_sequence_number + 1;
    child.parent_state_fingerprint = fixture.closure.resulting_state_fingerprint;
    child.chronicle_parent_cursor_fingerprint = fixture.closure.chronicle_resulting_cursor_fingerprint;
    child.archive_parent_moment_fingerprint = fixture.closure.archive_resulting_moment_fingerprint;
    child.archive_parent_seal_fingerprint = fixture.closure.archive_resulting_seal_fingerprint;
    child = applianceTestRecomputedTurnClosure(child);
    try world.Appliance.validateTurnClosureParentContinuity(child, fixture.closure);

    var wrong_manifest_parent = fixture.closure;
    wrong_manifest_parent.appliance_manifest_fingerprint +%= 1;
    wrong_manifest_parent = applianceTestRecomputedTurnClosure(wrong_manifest_parent);
    var wrong_manifest_child = child;
    wrong_manifest_child.parent_closure_fingerprint = wrong_manifest_parent.closure_fingerprint;
    wrong_manifest_child.parent_state_fingerprint = wrong_manifest_parent.resulting_state_fingerprint;
    wrong_manifest_child.chronicle_parent_cursor_fingerprint = wrong_manifest_parent.chronicle_resulting_cursor_fingerprint;
    wrong_manifest_child = applianceTestRecomputedTurnClosure(wrong_manifest_child);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.validateTurnClosureParentContinuity(wrong_manifest_child, wrong_manifest_parent));

    var skipped_turn_child = child;
    skipped_turn_child.turn_sequence_number = fixture.closure.turn_sequence_number + 2;
    skipped_turn_child = applianceTestRecomputedTurnClosure(skipped_turn_child);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.validateTurnClosureParentContinuity(skipped_turn_child, fixture.closure));
}

test "appliance TurnClosure validationReport preserves allocation failures" {
    const allocator = std.testing.allocator;
    const fixture = try applianceTurnClosureFixture(allocator);
    defer allocator.free(fixture.capsule_bytes);
    defer allocator.free(fixture.checkpoint_bytes);
    defer allocator.free(fixture.turn_receipt_bytes);
    defer allocator.free(fixture.actuation_receipt_fingerprints);
    defer allocator.free(fixture.actuation_receipt_byte_slices);
    defer allocator.free(fixture.actuation_receipt_bytes);
    defer allocator.free(fixture.root_result_bytes);
    defer allocator.free(fixture.bundle_bytes);

    const external_dependency_options = world.Appliance.TurnClosureValidation{
        .limits = .archive_decode,
        .bundle_options = .{ .allow_external_dependencies = true },
    };
    var observed_induced_failure = false;
    var observed_success = false;
    var fail_offset: usize = 0;
    while (fail_offset < 128 and !observed_success) : (fail_offset += 1) {
        var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = std.math.maxInt(usize),
        });
        failing_allocator.fail_index = failing_allocator.alloc_index + fail_offset;
        const report = fixture.closure.validationReport(failing_allocator.allocator(), external_dependency_options) catch {
            observed_induced_failure = true;
            try std.testing.expect(failing_allocator.has_induced_failure);
            continue;
        };
        try report.validate();
        try std.testing.expect(report.valid);
        observed_success = true;
    }

    try std.testing.expect(observed_induced_failure);
    try std.testing.expect(observed_success);
}

test "appliance TurnClosure rejects over-limit byte payloads before allocation" {
    const allocator = std.testing.allocator;
    const fixture = try applianceTurnClosureFixture(allocator);
    defer allocator.free(fixture.capsule_bytes);
    defer allocator.free(fixture.checkpoint_bytes);
    defer allocator.free(fixture.turn_receipt_bytes);
    defer allocator.free(fixture.actuation_receipt_fingerprints);
    defer allocator.free(fixture.actuation_receipt_byte_slices);
    defer allocator.free(fixture.actuation_receipt_bytes);
    defer allocator.free(fixture.root_result_bytes);
    defer allocator.free(fixture.bundle_bytes);

    const encoded = try fixture.closure.encode(allocator);
    defer allocator.free(encoded);
    var malformed = try allocator.dupe(u8, encoded);
    defer allocator.free(malformed);
    const count_offset = try applianceTestTurnClosureFinalizedReceiptBytesCountOffset(malformed);
    std.mem.writeInt(u64, malformed[count_offset..][0..8], world.Appliance.TurnClosureLimits.default.max_items + 1, .little);

    try std.testing.expectError(error.CapacityExceeded, world.Appliance.TurnClosure.decode(allocator, malformed));

    const limits = world.Appliance.TurnClosureLimits.default;
    var oversized_receipt = try allocator.dupe(u8, encoded);
    defer allocator.free(oversized_receipt);
    const first_receipt_len_offset = count_offset + @sizeOf(u64);
    std.mem.writeInt(u32, oversized_receipt[first_receipt_len_offset..][0..4], @intCast(limits.max_receipt_bytes + 1), .little);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.TurnClosure.decode(allocator, oversized_receipt));

    const oversized_checkpoint = try allocator.alloc(u8, limits.max_checkpoint_bytes + 1);
    defer allocator.free(oversized_checkpoint);
    @memset(oversized_checkpoint, 'c');
    var oversized_checkpoint_closure = fixture.closure;
    oversized_checkpoint_closure.checkpoint_bytes = oversized_checkpoint;
    oversized_checkpoint_closure = applianceTestRecomputedTurnClosure(oversized_checkpoint_closure);
    const oversized_checkpoint_encoded = try oversized_checkpoint_closure.encode(allocator);
    defer allocator.free(oversized_checkpoint_encoded);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.TurnClosure.decode(allocator, oversized_checkpoint_encoded));

    var overlimit_pending_count_bytes: [@sizeOf(u64)]u8 = undefined;
    std.mem.writeInt(u64, &overlimit_pending_count_bytes, limits.max_items + 1, .little);
    var overlimit_pending_closure = fixture.closure;
    overlimit_pending_closure.pending_host_request_bytes = &overlimit_pending_count_bytes;
    overlimit_pending_closure.status = .needs_host;
    overlimit_pending_closure = applianceTestRecomputedTurnClosure(overlimit_pending_closure);
    try std.testing.expectError(error.CapacityExceeded, overlimit_pending_closure.validate(allocator, .{
        .limits = limits,
        .bundle_options = .{ .allow_external_dependencies = true },
    }));
}

test "appliance TurnClosure rejects mismatched required bytes and unresolved roots" {
    const allocator = std.testing.allocator;
    const fixture = try applianceTurnClosureFixture(allocator);
    defer allocator.free(fixture.capsule_bytes);
    defer allocator.free(fixture.checkpoint_bytes);
    defer allocator.free(fixture.turn_receipt_bytes);
    defer allocator.free(fixture.actuation_receipt_fingerprints);
    defer allocator.free(fixture.actuation_receipt_byte_slices);
    defer allocator.free(fixture.actuation_receipt_bytes);
    defer allocator.free(fixture.root_result_bytes);
    defer allocator.free(fixture.bundle_bytes);

    var wrong_checkpoint = fixture.closure;
    wrong_checkpoint.checkpoint_fingerprint +%= 1;
    wrong_checkpoint.closure_fingerprint = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = wrong_checkpoint.executable_image_fingerprint,
        .appliance_manifest_fingerprint = wrong_checkpoint.appliance_manifest_fingerprint,
        .turn_sequence_number = wrong_checkpoint.turn_sequence_number,
        .parent_state_fingerprint = wrong_checkpoint.parent_state_fingerprint,
        .resulting_state_fingerprint = wrong_checkpoint.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = wrong_checkpoint.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = wrong_checkpoint.chronicle_resulting_cursor_fingerprint,
        .checkpoint_fingerprint = wrong_checkpoint.checkpoint_fingerprint,
        .checkpoint_bytes = wrong_checkpoint.checkpoint_bytes,
        .capsule_fingerprint = wrong_checkpoint.capsule_fingerprint,
        .capsule_bytes = wrong_checkpoint.capsule_bytes,
        .turn_receipt_fingerprint = wrong_checkpoint.turn_receipt_fingerprint,
        .turn_receipt_bytes = wrong_checkpoint.turn_receipt_bytes,
        .evidence_bundle_bytes = wrong_checkpoint.evidence_bundle_bytes,
        .root_result_fingerprint = wrong_checkpoint.root_result_fingerprint,
        .root_result_bytes = wrong_checkpoint.root_result_bytes,
        .root_result_value_ref_fingerprint = wrong_checkpoint.root_result_value_ref_fingerprint,
        .status = wrong_checkpoint.status,
    }).closure_fingerprint;
    const external_dependency_options = world.Appliance.TurnClosureValidation{
        .limits = .archive_decode,
        .bundle_options = .{ .allow_external_dependencies = true },
    };
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_checkpoint.validate(allocator, external_dependency_options));

    var wrong_resulting_state = fixture.closure;
    wrong_resulting_state.resulting_state_fingerprint +%= 1;
    wrong_resulting_state.closure_fingerprint = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = wrong_resulting_state.executable_image_fingerprint,
        .appliance_manifest_fingerprint = wrong_resulting_state.appliance_manifest_fingerprint,
        .turn_sequence_number = wrong_resulting_state.turn_sequence_number,
        .parent_state_fingerprint = wrong_resulting_state.parent_state_fingerprint,
        .resulting_state_fingerprint = wrong_resulting_state.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = wrong_resulting_state.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = wrong_resulting_state.chronicle_resulting_cursor_fingerprint,
        .checkpoint_fingerprint = wrong_resulting_state.checkpoint_fingerprint,
        .checkpoint_bytes = wrong_resulting_state.checkpoint_bytes,
        .capsule_fingerprint = wrong_resulting_state.capsule_fingerprint,
        .capsule_bytes = wrong_resulting_state.capsule_bytes,
        .turn_receipt_fingerprint = wrong_resulting_state.turn_receipt_fingerprint,
        .turn_receipt_bytes = wrong_resulting_state.turn_receipt_bytes,
        .evidence_bundle_bytes = wrong_resulting_state.evidence_bundle_bytes,
        .root_result_fingerprint = wrong_resulting_state.root_result_fingerprint,
        .root_result_bytes = wrong_resulting_state.root_result_bytes,
        .root_result_value_ref_fingerprint = wrong_resulting_state.root_result_value_ref_fingerprint,
        .finalized_actuation_receipt_fingerprints = wrong_resulting_state.finalized_actuation_receipt_fingerprints,
        .finalized_actuation_receipt_bytes = wrong_resulting_state.finalized_actuation_receipt_bytes,
        .status = wrong_resulting_state.status,
    }).closure_fingerprint;
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_resulting_state.validate(allocator, external_dependency_options));

    const tampered_capsule = try allocator.dupe(u8, fixture.capsule_bytes);
    defer allocator.free(tampered_capsule);
    tampered_capsule[tampered_capsule.len - 1] ^= 0x01;
    var wrong_capsule_bytes = fixture.closure;
    wrong_capsule_bytes.capsule_bytes = tampered_capsule;
    wrong_capsule_bytes.closure_fingerprint = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = wrong_capsule_bytes.executable_image_fingerprint,
        .appliance_manifest_fingerprint = wrong_capsule_bytes.appliance_manifest_fingerprint,
        .turn_sequence_number = wrong_capsule_bytes.turn_sequence_number,
        .parent_state_fingerprint = wrong_capsule_bytes.parent_state_fingerprint,
        .resulting_state_fingerprint = wrong_capsule_bytes.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = wrong_capsule_bytes.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = wrong_capsule_bytes.chronicle_resulting_cursor_fingerprint,
        .checkpoint_fingerprint = wrong_capsule_bytes.checkpoint_fingerprint,
        .checkpoint_bytes = wrong_capsule_bytes.checkpoint_bytes,
        .capsule_fingerprint = wrong_capsule_bytes.capsule_fingerprint,
        .capsule_bytes = wrong_capsule_bytes.capsule_bytes,
        .turn_receipt_fingerprint = wrong_capsule_bytes.turn_receipt_fingerprint,
        .turn_receipt_bytes = wrong_capsule_bytes.turn_receipt_bytes,
        .evidence_bundle_bytes = wrong_capsule_bytes.evidence_bundle_bytes,
        .root_result_fingerprint = wrong_capsule_bytes.root_result_fingerprint,
        .root_result_bytes = wrong_capsule_bytes.root_result_bytes,
        .root_result_value_ref_fingerprint = wrong_capsule_bytes.root_result_value_ref_fingerprint,
        .finalized_actuation_receipt_fingerprints = wrong_capsule_bytes.finalized_actuation_receipt_fingerprints,
        .finalized_actuation_receipt_bytes = wrong_capsule_bytes.finalized_actuation_receipt_bytes,
        .status = wrong_capsule_bytes.status,
    }).closure_fingerprint;
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_capsule_bytes.validate(allocator, external_dependency_options));

    var missing_receipt_bytes = fixture.closure;
    missing_receipt_bytes.finalized_actuation_receipt_bytes = &.{};
    try std.testing.expectError(error.InvalidFrameEncoding, missing_receipt_bytes.validate(allocator, external_dependency_options));

    var missing_finalized_evidence = fixture.closure;
    missing_finalized_evidence.finalized_actuation_receipt_fingerprints = &.{};
    missing_finalized_evidence.finalized_actuation_receipt_bytes = &.{};
    missing_finalized_evidence = applianceTestRecomputedTurnClosure(missing_finalized_evidence);
    try std.testing.expectError(error.InvalidFrameEncoding, missing_finalized_evidence.validate(allocator, external_dependency_options));

    var duplicate_base_receipt = try world.Appliance.TurnReceipt.decodeArchivePayload(allocator, fixture.turn_receipt_bytes);
    defer duplicate_base_receipt.deinit(allocator);
    const duplicate_applied_replies = [_]u64{
        duplicate_base_receipt.applied_host_reply_fingerprints[0],
        duplicate_base_receipt.applied_host_reply_fingerprints[0] ^ 0xD1,
    };
    const duplicate_turn_receipt = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = duplicate_base_receipt.manifest_fingerprint,
        .turn_sequence_number = duplicate_base_receipt.turn_sequence_number,
        .command_fingerprint = duplicate_base_receipt.command_fingerprint,
        .prior_checkpoint_fingerprint = duplicate_base_receipt.prior_checkpoint_fingerprint,
        .applied_host_reply_fingerprints = &duplicate_applied_replies,
        .emitted_host_request_fingerprints = duplicate_base_receipt.emitted_host_request_fingerprints,
        .source_capsule_fingerprint = duplicate_base_receipt.source_capsule_fingerprint,
        .resulting_capsule_fingerprint = duplicate_base_receipt.resulting_capsule_fingerprint,
        .archive_append_batch_fingerprint = duplicate_base_receipt.archive_append_batch_fingerprint,
        .resulting_archive_moment_fingerprint = duplicate_base_receipt.resulting_archive_moment_fingerprint,
        .resulting_archive_seal_fingerprint = duplicate_base_receipt.resulting_archive_seal_fingerprint,
        .resulting_chronicle_cursor_fingerprint = duplicate_base_receipt.resulting_chronicle_cursor_fingerprint,
        .root_result_fingerprint = duplicate_base_receipt.root_result_fingerprint,
        .status = duplicate_base_receipt.status,
        .run_receipt_fingerprint = duplicate_base_receipt.run_receipt_fingerprint,
        .blocker_count = duplicate_base_receipt.blocker_count,
        .warning_count = duplicate_base_receipt.warning_count,
    });
    var duplicate_turn_receipt_payload: std.ArrayList(u8) = .empty;
    defer duplicate_turn_receipt_payload.deinit(allocator);
    try duplicate_turn_receipt.encode(&duplicate_turn_receipt_payload, allocator);
    const duplicate_turn_receipt_bytes = try allocator.dupe(u8, duplicate_turn_receipt_payload.items);
    defer allocator.free(duplicate_turn_receipt_bytes);
    var duplicate_base_checkpoint = try world.Appliance.Checkpoint.decodeArchivePayload(allocator, fixture.checkpoint_bytes);
    defer duplicate_base_checkpoint.deinit(allocator);
    const duplicate_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = duplicate_base_checkpoint.manifest_fingerprint,
        .turn_sequence_number = duplicate_base_checkpoint.turn_sequence_number,
        .capsule_fingerprint = duplicate_base_checkpoint.capsule_fingerprint,
        .capsule_image_ref_fingerprint = duplicate_base_checkpoint.capsule_image_ref_fingerprint,
        .capsule_image_bytes = duplicate_base_checkpoint.capsule_image_bytes,
        .latest_archive_moment_fingerprint = duplicate_base_checkpoint.latest_archive_moment_fingerprint,
        .latest_archive_seal_fingerprint = duplicate_base_checkpoint.latest_archive_seal_fingerprint,
        .latest_chronicle_cursor_fingerprint = duplicate_base_checkpoint.latest_chronicle_cursor_fingerprint,
        .pending_archive_append_batch_fingerprint = duplicate_base_checkpoint.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = duplicate_base_checkpoint.pending_archive_resulting_cursor,
        .latest_archive_cursor = duplicate_base_checkpoint.latest_archive_cursor,
        .core_state = duplicate_base_checkpoint.core_state,
        .previous_turn_receipt_fingerprint = duplicate_turn_receipt.receipt_fingerprint,
        .outstanding_host_requests = duplicate_base_checkpoint.outstanding_host_requests,
        .execution_mode = duplicate_base_checkpoint.execution_mode,
        .metadata = duplicate_base_checkpoint.metadata,
    });
    var duplicate_checkpoint_payload: std.ArrayList(u8) = .empty;
    defer duplicate_checkpoint_payload.deinit(allocator);
    try duplicate_checkpoint.encode(&duplicate_checkpoint_payload, allocator);
    const duplicate_checkpoint_bytes = try allocator.dupe(u8, duplicate_checkpoint_payload.items);
    defer allocator.free(duplicate_checkpoint_bytes);
    const duplicate_finalized_receipts = [_]u64{
        fixture.actuation_receipt_fingerprints[0],
        fixture.actuation_receipt_fingerprints[0],
    };
    const duplicate_finalized_receipt_bytes = [_][]const u8{
        fixture.actuation_receipt_bytes,
        fixture.actuation_receipt_bytes,
    };
    const duplicate_finalized_bundle = try applianceTestClosureBundleBytes(
        allocator,
        duplicate_checkpoint_bytes,
        duplicate_turn_receipt_bytes,
        fixture.capsule_bytes,
        fixture.root_result_bytes,
        fixture.actuation_receipt_bytes,
    );
    defer allocator.free(duplicate_finalized_bundle);
    var duplicate_finalized_evidence = fixture.closure;
    duplicate_finalized_evidence.checkpoint_fingerprint = duplicate_checkpoint.checkpoint_fingerprint;
    duplicate_finalized_evidence.checkpoint_bytes = duplicate_checkpoint_bytes;
    duplicate_finalized_evidence.turn_receipt_fingerprint = duplicate_turn_receipt.receipt_fingerprint;
    duplicate_finalized_evidence.turn_receipt_bytes = duplicate_turn_receipt_bytes;
    duplicate_finalized_evidence.evidence_bundle_bytes = duplicate_finalized_bundle;
    duplicate_finalized_evidence.resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, fixture.closure.turn_sequence_number, duplicate_turn_receipt.receipt_fingerprint);
    duplicate_finalized_evidence.finalized_actuation_receipt_fingerprints = &duplicate_finalized_receipts;
    duplicate_finalized_evidence.finalized_actuation_receipt_bytes = &duplicate_finalized_receipt_bytes;
    duplicate_finalized_evidence = applianceTestRecomputedTurnClosure(duplicate_finalized_evidence);
    try std.testing.expectError(error.InvalidFrameEncoding, duplicate_finalized_evidence.validate(allocator, external_dependency_options));

    const forged_warnings = [_]u64{0xD7C4};
    var forged_warning_count = fixture.closure;
    forged_warning_count.warnings = &forged_warnings;
    forged_warning_count = applianceTestRecomputedTurnClosure(forged_warning_count);
    try std.testing.expectError(error.InvalidFrameEncoding, forged_warning_count.validate(allocator, external_dependency_options));

    var forged_genesis_parent_state = fixture.closure;
    forged_genesis_parent_state.parent_state_fingerprint +%= 1;
    forged_genesis_parent_state = applianceTestRecomputedTurnClosure(forged_genesis_parent_state);
    try std.testing.expectError(error.InvalidFrameEncoding, forged_genesis_parent_state.validate(allocator, external_dependency_options));
    const forged_genesis_parent_state_bytes = try forged_genesis_parent_state.encode(allocator);
    defer allocator.free(forged_genesis_parent_state_bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.TurnClosure.decodeArchivePayload(allocator, forged_genesis_parent_state_bytes));

    var forged_genesis_parent_cursor = fixture.closure;
    forged_genesis_parent_cursor.chronicle_parent_cursor_fingerprint +%= 1;
    forged_genesis_parent_cursor = applianceTestRecomputedTurnClosure(forged_genesis_parent_cursor);
    try std.testing.expectError(error.InvalidFrameEncoding, forged_genesis_parent_cursor.validate(allocator, external_dependency_options));

    var missing_run_receipt_bytes = fixture.closure;
    missing_run_receipt_bytes.run_receipt_fingerprint = 0xD7C4;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_run_receipt_bytes.validate(allocator, external_dependency_options));

    const run_receipt = world.RunReceipt.init(.{
        .run_permit_fingerprint = 0xD7D0,
        .environment_certificate_fingerprint = 0xD7D1,
        .target_ref_fingerprint = 0xD7D2,
        .usage_ledger_fingerprint = 0xD7D3,
        .final_run_state_fingerprint = 0xD7D4,
        .final_status = .completed,
    });
    const run_receipt_bytes = try world.Continuity.encodePortableEvidence(world.RunReceipt, allocator, run_receipt);
    defer allocator.free(run_receipt_bytes);
    var base_turn_receipt = try world.Appliance.TurnReceipt.decodeArchivePayload(allocator, fixture.turn_receipt_bytes);
    defer base_turn_receipt.deinit(allocator);
    const turn_receipt_with_run = world.Appliance.TurnReceipt.init(.{
        .manifest_fingerprint = base_turn_receipt.manifest_fingerprint,
        .turn_sequence_number = base_turn_receipt.turn_sequence_number,
        .command_fingerprint = base_turn_receipt.command_fingerprint,
        .prior_checkpoint_fingerprint = base_turn_receipt.prior_checkpoint_fingerprint,
        .applied_host_reply_fingerprints = base_turn_receipt.applied_host_reply_fingerprints,
        .emitted_host_request_fingerprints = base_turn_receipt.emitted_host_request_fingerprints,
        .source_capsule_fingerprint = base_turn_receipt.source_capsule_fingerprint,
        .resulting_capsule_fingerprint = base_turn_receipt.resulting_capsule_fingerprint,
        .archive_append_batch_fingerprint = base_turn_receipt.archive_append_batch_fingerprint,
        .resulting_archive_moment_fingerprint = base_turn_receipt.resulting_archive_moment_fingerprint,
        .resulting_archive_seal_fingerprint = base_turn_receipt.resulting_archive_seal_fingerprint,
        .resulting_chronicle_cursor_fingerprint = base_turn_receipt.resulting_chronicle_cursor_fingerprint,
        .root_result_fingerprint = base_turn_receipt.root_result_fingerprint,
        .status = base_turn_receipt.status,
        .run_receipt_fingerprint = run_receipt.receipt_fingerprint,
        .blocker_count = base_turn_receipt.blocker_count,
        .warning_count = base_turn_receipt.warning_count,
    });
    var turn_receipt_with_run_payload: std.ArrayList(u8) = .empty;
    defer turn_receipt_with_run_payload.deinit(allocator);
    try turn_receipt_with_run.encode(&turn_receipt_with_run_payload, allocator);
    const turn_receipt_with_run_bytes = try allocator.dupe(u8, turn_receipt_with_run_payload.items);
    defer allocator.free(turn_receipt_with_run_bytes);
    var base_checkpoint = try world.Appliance.Checkpoint.decodeArchivePayload(allocator, fixture.checkpoint_bytes);
    defer base_checkpoint.deinit(allocator);
    const checkpoint_with_run = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = base_checkpoint.manifest_fingerprint,
        .turn_sequence_number = base_checkpoint.turn_sequence_number,
        .capsule_fingerprint = base_checkpoint.capsule_fingerprint,
        .capsule_image_ref_fingerprint = base_checkpoint.capsule_image_ref_fingerprint,
        .capsule_image_bytes = base_checkpoint.capsule_image_bytes,
        .latest_archive_moment_fingerprint = base_checkpoint.latest_archive_moment_fingerprint,
        .latest_archive_seal_fingerprint = base_checkpoint.latest_archive_seal_fingerprint,
        .latest_chronicle_cursor_fingerprint = base_checkpoint.latest_chronicle_cursor_fingerprint,
        .pending_archive_append_batch_fingerprint = base_checkpoint.pending_archive_append_batch_fingerprint,
        .pending_archive_resulting_cursor = base_checkpoint.pending_archive_resulting_cursor,
        .latest_archive_cursor = base_checkpoint.latest_archive_cursor,
        .core_state = base_checkpoint.core_state,
        .previous_turn_receipt_fingerprint = turn_receipt_with_run.receipt_fingerprint,
        .outstanding_host_requests = base_checkpoint.outstanding_host_requests,
        .execution_mode = base_checkpoint.execution_mode,
        .metadata = base_checkpoint.metadata,
    });
    var checkpoint_with_run_payload: std.ArrayList(u8) = .empty;
    defer checkpoint_with_run_payload.deinit(allocator);
    try checkpoint_with_run.encode(&checkpoint_with_run_payload, allocator);
    const checkpoint_with_run_bytes = try allocator.dupe(u8, checkpoint_with_run_payload.items);
    defer allocator.free(checkpoint_with_run_bytes);
    const bundle_missing_run_receipt = try applianceTestClosureBundleBytes(
        allocator,
        checkpoint_with_run_bytes,
        turn_receipt_with_run_bytes,
        fixture.capsule_bytes,
        fixture.root_result_bytes,
        fixture.actuation_receipt_bytes,
    );
    defer allocator.free(bundle_missing_run_receipt);
    var closure_missing_run_receipt_root = fixture.closure;
    closure_missing_run_receipt_root.checkpoint_fingerprint = checkpoint_with_run.checkpoint_fingerprint;
    closure_missing_run_receipt_root.checkpoint_bytes = checkpoint_with_run_bytes;
    closure_missing_run_receipt_root.turn_receipt_fingerprint = turn_receipt_with_run.receipt_fingerprint;
    closure_missing_run_receipt_root.turn_receipt_bytes = turn_receipt_with_run_bytes;
    closure_missing_run_receipt_root.evidence_bundle_bytes = bundle_missing_run_receipt;
    closure_missing_run_receipt_root.resulting_state_fingerprint = world.Appliance.coreStateFingerprint(.completed, fixture.closure.turn_sequence_number, turn_receipt_with_run.receipt_fingerprint);
    closure_missing_run_receipt_root.run_receipt_fingerprint = run_receipt.receipt_fingerprint;
    closure_missing_run_receipt_root.run_receipt_bytes = run_receipt_bytes;
    closure_missing_run_receipt_root = applianceTestRecomputedTurnClosure(closure_missing_run_receipt_root);
    try std.testing.expectError(error.ObjectMissing, closure_missing_run_receipt_root.validate(allocator, external_dependency_options));

    const bundle_with_run_receipt = try applianceTestClosureBundleBytesWithRunReceipt(
        allocator,
        checkpoint_with_run_bytes,
        turn_receipt_with_run_bytes,
        fixture.capsule_bytes,
        fixture.root_result_bytes,
        fixture.actuation_receipt_bytes,
        run_receipt_bytes,
    );
    defer allocator.free(bundle_with_run_receipt);
    var closure_with_run_receipt_root = closure_missing_run_receipt_root;
    closure_with_run_receipt_root.evidence_bundle_bytes = bundle_with_run_receipt;
    closure_with_run_receipt_root = applianceTestRecomputedTurnClosure(closure_with_run_receipt_root);
    try closure_with_run_receipt_root.validate(allocator, external_dependency_options);

    const replay_checkpoint = world.Appliance.Checkpoint.init(.{
        .manifest_fingerprint = fixture.closure.appliance_manifest_fingerprint,
        .turn_sequence_number = fixture.closure.turn_sequence_number,
        .capsule_fingerprint = fixture.closure.capsule_fingerprint,
        .previous_turn_receipt_fingerprint = fixture.closure.turn_receipt_fingerprint,
        .execution_mode = .replay,
    });
    var replay_checkpoint_payload: std.ArrayList(u8) = .empty;
    defer replay_checkpoint_payload.deinit(allocator);
    try replay_checkpoint.encode(&replay_checkpoint_payload, allocator);
    const replay_checkpoint_bytes = try allocator.dupe(u8, replay_checkpoint_payload.items);
    defer allocator.free(replay_checkpoint_bytes);
    var replay_missing_receipt_payloads = fixture.closure;
    replay_missing_receipt_payloads.checkpoint_fingerprint = replay_checkpoint.checkpoint_fingerprint;
    replay_missing_receipt_payloads.checkpoint_bytes = replay_checkpoint_bytes;
    replay_missing_receipt_payloads.finalized_actuation_receipt_bytes = &.{};
    try std.testing.expectError(error.InvalidFrameEncoding, replay_missing_receipt_payloads.validate(allocator, external_dependency_options));

    const tampered_payload = try allocator.dupe(u8, fixture.actuation_receipt_bytes);
    defer allocator.free(tampered_payload);
    tampered_payload[tampered_payload.len - 1] ^= 0x01;
    var tampered_receipt_bytes = fixture.closure;
    tampered_receipt_bytes.finalized_actuation_receipt_bytes = &.{tampered_payload};
    try std.testing.expectError(error.InvalidFrameEncoding, tampered_receipt_bytes.validate(allocator, external_dependency_options));

    var receipt = try world.Appliance.TurnReceipt.decodeArchivePayload(allocator, fixture.turn_receipt_bytes);
    defer receipt.deinit(allocator);
    const forged_root_result_bytes = try applianceTestRootResultValueImageBytes(allocator, receipt.root_result_fingerprint.? +% 1);
    defer allocator.free(forged_root_result_bytes);
    const forged_root_result_ref = world.Continuity.ObjectRef.fromPayload(.root_result, world.Continuity.ObjectKind.root_result.defaultFormatVersion(), forged_root_result_bytes, "root.result");
    const forged_bundle_bytes = try applianceTestClosureBundleBytes(
        allocator,
        fixture.checkpoint_bytes,
        fixture.turn_receipt_bytes,
        fixture.capsule_bytes,
        forged_root_result_bytes,
        fixture.actuation_receipt_bytes,
    );
    defer allocator.free(forged_bundle_bytes);
    var forged_root_result = fixture.closure;
    forged_root_result.root_result_fingerprint = forged_root_result_ref.object_fingerprint;
    forged_root_result.root_result_value_ref_fingerprint = forged_root_result_ref.ref_fingerprint;
    forged_root_result.root_result_bytes = forged_root_result_bytes;
    forged_root_result.evidence_bundle_bytes = forged_bundle_bytes;
    forged_root_result.closure_fingerprint = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = forged_root_result.executable_image_fingerprint,
        .appliance_manifest_fingerprint = forged_root_result.appliance_manifest_fingerprint,
        .turn_sequence_number = forged_root_result.turn_sequence_number,
        .parent_state_fingerprint = forged_root_result.parent_state_fingerprint,
        .resulting_state_fingerprint = forged_root_result.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = forged_root_result.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = forged_root_result.chronicle_resulting_cursor_fingerprint,
        .checkpoint_fingerprint = forged_root_result.checkpoint_fingerprint,
        .checkpoint_bytes = forged_root_result.checkpoint_bytes,
        .capsule_fingerprint = forged_root_result.capsule_fingerprint,
        .capsule_bytes = forged_root_result.capsule_bytes,
        .turn_receipt_fingerprint = forged_root_result.turn_receipt_fingerprint,
        .turn_receipt_bytes = forged_root_result.turn_receipt_bytes,
        .evidence_bundle_bytes = forged_root_result.evidence_bundle_bytes,
        .root_result_fingerprint = forged_root_result.root_result_fingerprint,
        .root_result_bytes = forged_root_result.root_result_bytes,
        .root_result_value_ref_fingerprint = forged_root_result.root_result_value_ref_fingerprint,
        .finalized_actuation_receipt_fingerprints = forged_root_result.finalized_actuation_receipt_fingerprints,
        .finalized_actuation_receipt_bytes = forged_root_result.finalized_actuation_receipt_bytes,
        .status = forged_root_result.status,
    }).closure_fingerprint;
    try std.testing.expectError(error.InvalidFrameEncoding, forged_root_result.validate(allocator, external_dependency_options));

    var missing_root = fixture.closure;
    missing_root.capsule_fingerprint +%= 1;
    missing_root.closure_fingerprint = world.Appliance.TurnClosure.init(.{
        .executable_image_fingerprint = missing_root.executable_image_fingerprint,
        .appliance_manifest_fingerprint = missing_root.appliance_manifest_fingerprint,
        .turn_sequence_number = missing_root.turn_sequence_number,
        .parent_state_fingerprint = missing_root.parent_state_fingerprint,
        .resulting_state_fingerprint = missing_root.resulting_state_fingerprint,
        .chronicle_parent_cursor_fingerprint = missing_root.chronicle_parent_cursor_fingerprint,
        .chronicle_resulting_cursor_fingerprint = missing_root.chronicle_resulting_cursor_fingerprint,
        .checkpoint_fingerprint = missing_root.checkpoint_fingerprint,
        .checkpoint_bytes = missing_root.checkpoint_bytes,
        .capsule_fingerprint = missing_root.capsule_fingerprint,
        .capsule_bytes = missing_root.capsule_bytes,
        .turn_receipt_fingerprint = missing_root.turn_receipt_fingerprint,
        .turn_receipt_bytes = missing_root.turn_receipt_bytes,
        .evidence_bundle_bytes = missing_root.evidence_bundle_bytes,
        .root_result_fingerprint = missing_root.root_result_fingerprint,
        .root_result_bytes = missing_root.root_result_bytes,
        .root_result_value_ref_fingerprint = missing_root.root_result_value_ref_fingerprint,
        .status = missing_root.status,
    }).closure_fingerprint;
    try std.testing.expectError(error.InvalidFrameEncoding, missing_root.validate(allocator, external_dependency_options));
}

test "appliance Wire TurnInput canonicalizes resolution input order" {
    const allocator = std.testing.allocator;
    const first = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = 0xA001,
        .status = .responded,
        .response_value_image_bytes = "one",
        .host_claim_bytes = "claim-one",
        .attempt_number = 1,
    });
    const second = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = 0xA002,
        .status = .failed,
        .host_claim_bytes = "claim-two",
        .attempt_number = 2,
    });
    const sorted = [_]world.Appliance.Wire.ResolutionInput{ first, second };
    const reversed = [_]world.Appliance.Wire.ResolutionInput{ second, first };
    const sorted_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA010,
        .expected_parent_closure_fingerprint = 0xA011,
        .previous_turn_receipt_fingerprint = 0xA012,
        .turn_sequence_number = 1,
        .resolutions = &sorted,
    });
    const reversed_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA010,
        .expected_parent_closure_fingerprint = 0xA011,
        .previous_turn_receipt_fingerprint = 0xA012,
        .turn_sequence_number = 1,
        .resolutions = &reversed,
    });
    const sorted_bytes = try sorted_input.encode(allocator);
    defer allocator.free(sorted_bytes);
    const reversed_bytes = try reversed_input.encode(allocator);
    defer allocator.free(reversed_bytes);
    try std.testing.expectEqualSlices(u8, sorted_bytes, reversed_bytes);

    var decoded = try world.Appliance.Wire.TurnInput.decode(allocator, reversed_bytes);
    defer decoded.deinit(allocator);
    try decoded.validate(.default);
    try std.testing.expectEqual(@as(u64, 0xA001), decoded.resolutions[0].target_host_request_fingerprint);
    try std.testing.expectEqual(@as(u64, 0xA002), decoded.resolutions[1].target_host_request_fingerprint);

    const duplicate = [_]world.Appliance.Wire.ResolutionInput{ first, first };
    const duplicate_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA010,
        .expected_parent_closure_fingerprint = 0xA011,
        .previous_turn_receipt_fingerprint = 0xA012,
        .turn_sequence_number = 1,
        .resolutions = &duplicate,
    });
    try std.testing.expectError(error.DuplicateHostReply, duplicate_input.encode(allocator));
}

test "appliance Wire TurnInput rejects ignored parent closure bytes" {
    const allocator = std.testing.allocator;
    const input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA010,
        .expected_parent_closure_fingerprint = 0xA011,
        .previous_turn_receipt_fingerprint = 0xA012,
        .turn_sequence_number = 1,
        .parent_turn_closure_bytes = "ignored-parent-closure",
    });
    const bytes = try input.encode(allocator);
    defer allocator.free(bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Wire.TurnInput.decode(allocator, bytes));
}

test "appliance Wire TurnInput rejects unsupported deterministic turn budgets" {
    const allocator = std.testing.allocator;
    const input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = 0xA010,
        .turn_sequence_number = 0,
        .deterministic_turn_budget = 1,
    });
    const bytes = try input.encode(allocator);
    defer allocator.free(bytes);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.Wire.TurnInput.decode(allocator, bytes));
}

test "appliance Wire TurnInput rejects over-limit counts before reading entries" {
    const allocator = std.testing.allocator;
    const input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = 0xA010,
        .turn_sequence_number = 0,
    });
    const bytes = try input.encode(allocator);
    defer allocator.free(bytes);

    const limits = world.Appliance.TurnClosureLimits.fromCapacity(world.Appliance.Capacity.tiny_one_port);
    const root_argument_count_offset =
        @sizeOf(u32) +
        @sizeOf(u8) +
        @sizeOf(u64) +
        3 * @sizeOf(u8) +
        @sizeOf(u64);
    var malformed_roots = try allocator.dupe(u8, bytes);
    defer allocator.free(malformed_roots);
    std.mem.writeInt(u64, malformed_roots[root_argument_count_offset..][0..8], limits.max_items + 1, .little);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, malformed_roots, limits));

    const resolution_count_offset =
        @sizeOf(u32) +
        @sizeOf(u8) +
        @sizeOf(u64) +
        3 * @sizeOf(u8) +
        @sizeOf(u64) +
        @sizeOf(u64) +
        @sizeOf(u32);
    var malformed = try allocator.dupe(u8, bytes);
    defer allocator.free(malformed);
    std.mem.writeInt(u64, malformed[resolution_count_offset..][0..8], limits.max_resolution_inputs + 1, .little);

    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, malformed, limits));

    const receiver_evidence_count_offset = resolution_count_offset + @sizeOf(u64);
    var malformed_receiver_evidence = try allocator.dupe(u8, bytes);
    defer allocator.free(malformed_receiver_evidence);
    std.mem.writeInt(u64, malformed_receiver_evidence[receiver_evidence_count_offset..][0..8], limits.max_items + 1, .little);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, malformed_receiver_evidence, limits));
}

test "appliance Wire TurnInput rejects over-limit byte fields during decode" {
    const allocator = std.testing.allocator;
    const limits = world.Appliance.TurnClosureLimits.fromCapacity(world.Appliance.Capacity.tiny_one_port);

    const root_argument = try allocator.alloc(u8, limits.max_result_bytes + 1);
    defer allocator.free(root_argument);
    @memset(root_argument, 'r');
    const root_argument_images = [_][]const u8{root_argument};
    const boot_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = 0xA030,
        .turn_sequence_number = 0,
        .root_argument_images = &root_argument_images,
    });
    const boot_bytes = try boot_input.encode(allocator);
    defer allocator.free(boot_bytes);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, boot_bytes, limits));

    const parent_closure = try allocator.alloc(u8, limits.max_closure_bytes + 1);
    defer allocator.free(parent_closure);
    @memset(parent_closure, 'p');
    const restore_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .restore,
        .appliance_manifest_fingerprint = 0xA031,
        .turn_sequence_number = 1,
        .parent_turn_closure_bytes = parent_closure,
    });
    const restore_bytes = try restore_input.encode(allocator);
    defer allocator.free(restore_bytes);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, restore_bytes, limits));

    const response_value = try allocator.alloc(u8, limits.max_result_bytes + 1);
    defer allocator.free(response_value);
    @memset(response_value, 'v');
    const resolution = world.Appliance.Wire.ResolutionInput.init(.{
        .target_host_request_fingerprint = 0xA032,
        .status = .responded,
        .response_value_image_bytes = response_value,
    });
    const resolution_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA033,
        .turn_sequence_number = 1,
        .resolutions = &.{resolution},
    });
    const resolution_bytes = try resolution_input.encode(allocator);
    defer allocator.free(resolution_bytes);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, resolution_bytes, limits));

    const retention_metadata = try allocator.alloc(u8, limits.max_metadata_bytes + 1);
    defer allocator.free(retention_metadata);
    @memset(retention_metadata, 'm');
    const retention = world.Appliance.Wire.RetentionInput.init(.{
        .prior_archive_append_batch_fingerprint = 0xA034,
        .resulting_moment_fingerprint = 0xA035,
        .resulting_seal_fingerprint = 0xA036,
        .resulting_chronicle_cursor_fingerprint = 0xA037,
        .host_retention_status = .retained,
        .metadata = retention_metadata,
    });
    const retention_input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .@"continue",
        .appliance_manifest_fingerprint = 0xA038,
        .turn_sequence_number = 1,
        .retention = retention,
    });
    const retention_bytes = try retention_input.encode(allocator);
    defer allocator.free(retention_bytes);
    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decodeWithLimits(allocator, retention_bytes, limits));
}

test "appliance Wire turn input decodes against active capacity limits" {
    const allocator = std.testing.allocator;
    const metadata = try allocator.alloc(u8, world.Appliance.Capacity.wasm_small.max_metadata_bytes + 1);
    defer allocator.free(metadata);
    @memset(metadata, 'm');

    const input = world.Appliance.Wire.TurnInput.init(.{
        .operation = .boot,
        .appliance_manifest_fingerprint = 0xA020,
        .turn_sequence_number = 0,
        .host_metadata = metadata,
    });
    const bytes = try input.encode(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Wire.TurnInput.decode(allocator, bytes));
    var decoded = try world.Appliance.Wire.TurnInput.decodeWithLimits(
        allocator,
        bytes,
        world.Appliance.TurnClosureLimits.fromCapacity(world.Appliance.Capacity.wasm_agent),
    );
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(metadata.len, decoded.host_metadata.len);
    try std.testing.expectEqualSlices(u8, metadata, decoded.host_metadata);
}

test "appliance Continuity object kinds are canonical evidence kinds" {
    try std.testing.expectEqual(world.world_appliance_manifest_format_version, world.Continuity.ObjectKind.appliance_manifest.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_command_format_version, world.Continuity.ObjectKind.appliance_command.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_host_request_format_version, world.Continuity.ObjectKind.appliance_host_request.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_host_reply_format_version, world.Continuity.ObjectKind.appliance_host_reply.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_turn_output_format_version, world.Continuity.ObjectKind.appliance_turn_output.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_checkpoint_format_version, world.Continuity.ObjectKind.appliance_checkpoint.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_turn_receipt_format_version, world.Continuity.ObjectKind.appliance_turn_receipt.defaultFormatVersion());
    try std.testing.expectEqual(world.world_appliance_turn_closure_format_version, world.Continuity.ObjectKind.appliance_turn_closure.defaultFormatVersion());
    try std.testing.expectEqual(@as(u32, 1), world.Continuity.ObjectKind.archive_append_batch.defaultFormatVersion());
    try std.testing.expectEqual(@as(u32, 1), world.Continuity.ObjectKind.root_result.defaultFormatVersion());

    const ref = world.Continuity.ObjectRef.fromPayload(.appliance_manifest, world.world_appliance_manifest_format_version, "manifest", "appliance manifest");
    try ref.validate();
    try std.testing.expectEqual(world.Continuity.ObjectKind.appliance_manifest, ref.kind);
}

test "appliance actuation prepareHost emits prepared evidence without host effect" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    try prepared.validate();
    try std.testing.expect(prepared.decision.approved);
    try std.testing.expectEqual(fixture.intent.intent_fingerprint, prepared.intent.intent_fingerprint);
    try std.testing.expectEqual(fixture.envelope.envelope_fingerprint, prepared.envelope.envelope_fingerprint);
    try std.testing.expectEqual(fixture.descriptor.descriptor_fingerprint, prepared.expected_response_descriptor_fingerprint);
}

test "appliance actuation Prepared rejects descriptor value policy mismatch" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const native_descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = fixture.ref,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_port_id = 0,
        .allowed_response_kinds = .all,
        .value_policy = world.ValuePolicy.native_compatible,
    });
    const native_intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = native_descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
    });
    const native_envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = native_intent.intent_fingerprint,
        .idempotency_key = fixture.key,
    });
    const forged_prepared = world.Actuation.Prepared.init(.{
        .policy = world.Actuation.Policy.strict_fresh,
        .intent = native_intent,
        .envelope = native_envelope,
        .descriptor = native_descriptor,
        .decision = world.Actuation.Decision.approvedDecision(native_intent, world.Actuation.Policy.strict_fresh, null),
        .expected_response_descriptor_fingerprint = native_descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    try std.testing.expectError(error.PortableValueRequired, forged_prepared.validate());
}

test "appliance actuation prepareHost denies before HostRequest emission" {
    const fixture = applianceActuationFixture(.idempotent_mutation);
    try std.testing.expectError(error.SupervisionDenied, world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.strict_fresh,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .key_present = false,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    }));

    const permitted_class_fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.strict_fresh,
        .intent = permitted_class_fixture.intent,
        .envelope = permitted_class_fixture.envelope,
        .descriptor = permitted_class_fixture.descriptor,
        .target_ref_fingerprint = permitted_class_fixture.target_ref_fingerprint,
        .world_surface_fingerprint = permitted_class_fixture.world_surface_fingerprint,
    });
    try prepared.validate();

    const pending_outcome = world.Actuation.HostOutcomeInput{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .pending,
    };
    try std.testing.expectError(error.PortRuleDenied, world.Actuation.Membrane.finalizeHost(prepared, pending_outcome, .{}));
}

test "appliance actuation prepareHost enforces precommit permit budgets" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const permit = world.RunPermit.init(.{
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xAA10,
        .environment_certificate_fingerprint = 0xEE10,
        .binding_plan_fingerprint = 0,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_actuation = true,
            .allow_fresh_actuation = true,
            .allow_pending_actuation = true,
        }),
        .budget = world.Budget.init(.{ .max_actuation_calls = 0 }),
    });
    const intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .environment_certificate_fingerprint = permit.environment_certificate_fingerprint,
    });
    const envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = intent.intent_fingerprint,
        .idempotency_key = fixture.key,
        .supervision_ref_fingerprints = &.{permit.permit_fingerprint},
    });

    try std.testing.expectError(error.BudgetExceeded, world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = intent,
        .envelope = envelope,
        .descriptor = fixture.descriptor,
        .run_permit = permit,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    }));

    const pending_policy_denied_permit = world.RunPermit.init(.{
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xAA12,
        .environment_certificate_fingerprint = 0xEE12,
        .binding_plan_fingerprint = 0,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_actuation = true,
            .allow_fresh_actuation = true,
            .allow_pending_actuation = false,
        }),
    });
    const pending_policy_denied_intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
        .run_permit_fingerprint = pending_policy_denied_permit.permit_fingerprint,
        .environment_certificate_fingerprint = pending_policy_denied_permit.environment_certificate_fingerprint,
    });
    const pending_policy_denied_envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = pending_policy_denied_intent.intent_fingerprint,
        .idempotency_key = fixture.key,
        .supervision_ref_fingerprints = &.{pending_policy_denied_permit.permit_fingerprint},
    });
    const pending_policy_denied_prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = pending_policy_denied_intent,
        .envelope = pending_policy_denied_envelope,
        .descriptor = fixture.descriptor,
        .run_permit = pending_policy_denied_permit,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const pending_policy_denied_outcome = world.Actuation.HostOutcomeInput{
        .intent_fingerprint = pending_policy_denied_prepared.intent.intent_fingerprint,
        .envelope_fingerprint = pending_policy_denied_prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = pending_policy_denied_prepared.envelope.idempotency_key.key_fingerprint,
        .status = .pending,
    };
    try std.testing.expectError(error.SupervisionDenied, world.Actuation.Membrane.finalizeHost(pending_policy_denied_prepared, pending_policy_denied_outcome, .{
        .run_permit = pending_policy_denied_permit,
    }));

    const pending_rule_denied_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .allow_pending = false,
    })};
    const pending_rule_denied_permit = world.RunPermit.init(.{
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xAA13,
        .environment_certificate_fingerprint = 0xEE13,
        .binding_plan_fingerprint = 0,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_actuation = true,
            .allow_fresh_actuation = true,
            .allow_pending_actuation = true,
        }),
        .port_rules = &pending_rule_denied_rules,
    });
    const pending_rule_denied_intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
        .run_permit_fingerprint = pending_rule_denied_permit.permit_fingerprint,
        .environment_certificate_fingerprint = pending_rule_denied_permit.environment_certificate_fingerprint,
    });
    const pending_rule_denied_envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = pending_rule_denied_intent.intent_fingerprint,
        .idempotency_key = fixture.key,
        .supervision_ref_fingerprints = &.{pending_rule_denied_permit.permit_fingerprint},
    });
    const pending_rule_denied_prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = pending_rule_denied_intent,
        .envelope = pending_rule_denied_envelope,
        .descriptor = fixture.descriptor,
        .run_permit = pending_rule_denied_permit,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const pending_rule_denied_outcome = world.Actuation.HostOutcomeInput{
        .intent_fingerprint = pending_rule_denied_prepared.intent.intent_fingerprint,
        .envelope_fingerprint = pending_rule_denied_prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = pending_rule_denied_prepared.envelope.idempotency_key.key_fingerprint,
        .status = .pending,
    };
    try std.testing.expectError(error.PortRuleDenied, world.Actuation.Membrane.finalizeHost(pending_rule_denied_prepared, pending_rule_denied_outcome, .{
        .run_permit = pending_rule_denied_permit,
    }));

    const forged_prepared = world.Actuation.Prepared.init(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = intent,
        .envelope = envelope,
        .descriptor = fixture.descriptor,
        .decision = world.Actuation.Decision.approvedDecision(intent, world.Actuation.Policy.fixture_test, permit.permit_fingerprint),
        .expected_response_descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    try forged_prepared.validate();
    const outcome = world.Actuation.HostOutcomeInput{
        .intent_fingerprint = forged_prepared.intent.intent_fingerprint,
        .envelope_fingerprint = forged_prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = forged_prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA905,
    };
    try std.testing.expectError(error.SupervisionDenied, world.Actuation.Membrane.finalizeHost(forged_prepared, outcome, .{}));
    try std.testing.expectError(error.BudgetExceeded, world.Actuation.Membrane.finalizeHost(forged_prepared, outcome, .{
        .run_permit = permit,
    }));
}

test "appliance actuation finalizeHost enforces run permit response status" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const permit = world.RunPermit.init(.{
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xAA11,
        .environment_certificate_fingerprint = 0xEE11,
        .binding_plan_fingerprint = 0,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_actuation = true,
            .allow_fresh_actuation = true,
            .allow_pending_actuation = true,
            .allow_rejected_responses = false,
        }),
    });
    const intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .environment_certificate_fingerprint = permit.environment_certificate_fingerprint,
    });
    const envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = intent.intent_fingerprint,
        .idempotency_key = fixture.key,
        .supervision_ref_fingerprints = &.{permit.permit_fingerprint},
    });
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = intent,
        .envelope = envelope,
        .descriptor = fixture.descriptor,
        .run_permit = permit,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    try std.testing.expectError(error.SupervisionDenied, world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .rejected,
        .reason = "host rejected",
    }, .{
        .run_permit = permit,
    }));
}

test "appliance actuation finalizeHost constructs commit response and receipt" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const finalized = try world.Actuation.Membrane.finalizeHost(prepared, .{
        .host_request_fingerprint = prepared.intent.frame_request_fingerprint,
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA906,
    }, .{});

    try finalized.validate();
    try std.testing.expect(finalized.commit_value.fresh_called);
    try std.testing.expectEqual(world.Actuation.ResponseStatus.responded, finalized.response.status);
    try std.testing.expectEqual(finalized.commit_value.commit_fingerprint, finalized.receipt.commit_fingerprint);
    try std.testing.expectEqual(finalized.response.response_fingerprint, finalized.receipt.response_fingerprint);
    try std.testing.expectEqual(prepared.envelope.idempotency_key.key_fingerprint, finalized.receipt.idempotency_key_fingerprint);
    try std.testing.expectEqual(@as(?u64, fixture.key.request_fingerprint), finalized.receipt.request_fingerprint);
}

test "appliance actuation finalizeHost rejects forged prepared decision" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const other_intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = fixture.ref.ref_fingerprint,
        .descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
        .world_port_id = 1,
        .frame_request_fingerprint = fixture.intent.frame_request_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .class = .deterministic_fixture,
        .requested_mode = .fresh,
    });
    const forged_prepared = world.Actuation.Prepared.init(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .decision = world.Actuation.Decision.approvedDecision(other_intent, world.Actuation.Policy.fixture_test, null),
        .expected_response_descriptor_fingerprint = fixture.descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, world.Actuation.Membrane.finalizeHost(forged_prepared, .{
        .intent_fingerprint = fixture.intent.intent_fingerprint,
        .envelope_fingerprint = fixture.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = fixture.key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA9F0,
    }, .{}));
}

test "appliance actuation finalizeHost preserves rejected commit evidence" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const finalized = try world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .rejected,
        .frame_response_fingerprint = 0xA908,
    }, .{});

    try finalized.validate();
    try std.testing.expectEqual(world.Actuation.CommitStatus.rejected, finalized.commit_value.status);
    try std.testing.expectEqual(world.Actuation.ResponseStatus.rejected, finalized.response.status);
    try std.testing.expect(finalized.receipt.rejected);
}

test "appliance actuation finalizeHost rejects recorded fresh outcomes" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    for ([_]world.Actuation.ResponseStatus{ .rejected, .failed, .cancelled }) |status| {
        try std.testing.expectError(error.InvalidFrameEncoding, world.Actuation.Membrane.finalizeHost(prepared, .{
            .intent_fingerprint = prepared.intent.intent_fingerprint,
            .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
            .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
            .status = status,
            .recorded_response_fingerprint = 0xA90A,
        }, .{}));
    }
}

test "appliance actuation Finalized validates commit response receipt tuple" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const finalized = try world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA90B,
    }, .{});
    const wrong_response = world.Actuation.Response.init(.{
        .intent_fingerprint = finalized.response.intent_fingerprint,
        .commit_fingerprint = finalized.commit_value.commit_fingerprint + 1,
        .actuator_ref_fingerprint = finalized.response.actuator_ref_fingerprint,
        .world_port_id = finalized.response.world_port_id,
        .request_fingerprint = finalized.response.request_fingerprint,
        .status = finalized.response.status,
        .response_kind = finalized.response.response_kind,
        .frame_response_fingerprint = finalized.response.frame_response_fingerprint,
        .value_image_fingerprint = finalized.response.value_image_fingerprint,
        .recorded_response_fingerprint = finalized.response.recorded_response_fingerprint,
    });
    const forged = world.Actuation.Finalized.init(.{
        .commit_value = finalized.commit_value,
        .response = wrong_response,
        .receipt = finalized.receipt,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, forged.validate());

    const wrong_status_commit = world.Actuation.Commit.init(.{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .decision_fingerprint = prepared.decision.decision_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .attempt_number = prepared.attempt_number,
        .status = .commit_failed,
        .fresh_called = true,
    });
    const wrong_status_response = world.Actuation.Response.init(.{
        .intent_fingerprint = finalized.response.intent_fingerprint,
        .commit_fingerprint = wrong_status_commit.commit_fingerprint,
        .actuator_ref_fingerprint = finalized.response.actuator_ref_fingerprint,
        .world_port_id = finalized.response.world_port_id,
        .request_fingerprint = finalized.response.request_fingerprint,
        .status = .responded,
        .response_kind = finalized.response.response_kind,
        .frame_response_fingerprint = finalized.response.frame_response_fingerprint,
        .value_image_fingerprint = finalized.response.value_image_fingerprint,
    });
    const wrong_status_receipt = world.Actuation.Receipt.fromResponse(.{
        .intent = prepared.intent,
        .envelope = prepared.envelope,
        .decision = prepared.decision,
        .commit = wrong_status_commit,
        .response = wrong_status_response,
        .target_ref_fingerprint = prepared.target_ref_fingerprint,
        .world_surface_fingerprint = prepared.world_surface_fingerprint,
        .class = prepared.intent.class,
        .mode = prepared.intent.requested_mode,
    });
    const wrong_status_finalized = world.Actuation.Finalized.init(.{
        .commit_value = wrong_status_commit,
        .response = wrong_status_response,
        .receipt = wrong_status_receipt,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, wrong_status_finalized.validate());

    const unrelated_report = world.Actuation.VerifyReport.init(.{
        .intent_fingerprint = finalized.commit_value.intent_fingerprint,
        .expected_receipt_fingerprint = finalized.receipt.receipt_fingerprint,
        .fresh_receipt_fingerprint = finalized.receipt.receipt_fingerprint,
        .matched = true,
    });
    const non_verify_with_report = world.Actuation.Finalized.init(.{
        .commit_value = finalized.commit_value,
        .response = finalized.response,
        .receipt = finalized.receipt,
        .verify_report = unrelated_report,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, non_verify_with_report.validate());

    const mailbox_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = prepared.world_surface_fingerprint,
        .target_certificate_fingerprint = 0xA90C,
        .world_port_id = prepared.intent.world_port_id,
        .request_fingerprint = prepared.intent.frame_request_fingerprint,
        .response_fingerprint = 0xA90D,
        .replay_key = 0xA90E,
        .status = .responded,
    });
    const finalized_with_mailbox = try world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = mailbox_response.frame_fingerprint,
    }, .{
        .mailbox_response = mailbox_response,
    });
    try finalized_with_mailbox.validate();

    var forged_mailbox = mailbox_response;
    forged_mailbox.request_fingerprint += 1;
    const forged_mailbox_finalized = world.Actuation.Finalized.init(.{
        .commit_value = finalized_with_mailbox.commit_value,
        .response = finalized_with_mailbox.response,
        .receipt = finalized_with_mailbox.receipt,
        .mailbox_response = forged_mailbox,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, forged_mailbox_finalized.validate());
}

test "appliance actuation finalizeHost rejects mismatched host outcome" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });

    try std.testing.expectError(error.InvalidFrameEncoding, world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint + 1,
        .status = .responded,
        .frame_response_fingerprint = 0xA907,
    }, .{}));
    try std.testing.expectError(error.InvalidFrameEncoding, world.Actuation.Membrane.finalizeHost(prepared, .{
        .host_request_fingerprint = 0,
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA908,
    }, .{}));
    try std.testing.expectError(error.InvalidFrameEncoding, world.Actuation.Membrane.finalizeHost(prepared, .{
        .host_request_fingerprint = prepared.intent.frame_request_fingerprint + 1,
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .responded,
        .frame_response_fingerprint = 0xA909,
    }, .{}));
}

test "appliance actuation pending host outcome keeps parent parked" {
    const fixture = applianceActuationFixture(.deterministic_fixture);
    const prepared = try world.Actuation.Membrane.prepareHost(.{
        .policy = world.Actuation.Policy.fixture_test,
        .intent = fixture.intent,
        .envelope = fixture.envelope,
        .descriptor = fixture.descriptor,
        .target_ref_fingerprint = fixture.target_ref_fingerprint,
        .world_surface_fingerprint = fixture.world_surface_fingerprint,
    });
    const finalized = try world.Actuation.Membrane.finalizeHost(prepared, .{
        .intent_fingerprint = prepared.intent.intent_fingerprint,
        .envelope_fingerprint = prepared.envelope.envelope_fingerprint,
        .idempotency_key_fingerprint = prepared.envelope.idempotency_key.key_fingerprint,
        .status = .pending,
    }, .{});

    try finalized.validate();
    try std.testing.expect(finalized.commit_value.isInFlight());
    try std.testing.expect(finalized.receipt.pending);
    try std.testing.expect(!finalized.response.isTerminalForParent());
    try std.testing.expect(finalized.mailbox_response == null);
}

test "Universal Runtime initializes Appliance Core from Executable Image" {
    const root_bytes = try fixtures.Ports.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(std.testing.allocator, .{});
    defer builder.deinit();
    try builder.addRootModule(root_bytes);

    const root_module = builder.modules.items[0];
    const root_import = root_module.imports[0];
    const executable_descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = ApplianceActuationBinding.actuator_ref,
        .world_surface_fingerprint = root_module.target_ref.world_surface_fingerprint,
        .target_ref_fingerprint = root_module.target_ref.target_ref_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = root_import.source_effect_shape_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .response_value_table_id = root_import.response_value_table_id,
        .label = "universal-runtime.fixture",
    });
    try builder.addExternalBinding(world.Executable.ExternalBinding.init(.{
        .parent_module_fingerprint = root_module.module_ref.boundary_module_fingerprint,
        .world_port_id = root_import.world_port_id,
        .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
        .payload_value_table_id = root_import.payload_value_table_id,
        .payload_value_ref_fingerprint = root_import.payload_value_ref_fingerprint,
        .response_value_table_id = root_import.response_value_table_id,
        .response_value_ref_fingerprint = root_import.response_value_ref_fingerprint,
        .actuator_ref = ApplianceActuationBinding.actuator_ref,
        .descriptor = executable_descriptor,
        .label = "universal-runtime.fixture",
    }));

    var prepared = try builder.prepare();
    defer prepared.deinit();
    var image = try prepared.seal();
    defer image.deinit(std.testing.allocator);

    try std.testing.expectError(error.CapacityExceeded, world.Appliance.Core.initExecutable(std.testing.allocator, image, .{
        .profile = .wasm_small,
        .capacity = world.Appliance.Capacity.tiny_one_port,
    }));
    var core = try world.Appliance.Core.initExecutable(std.testing.allocator, image, .{
        .profile = .wasm_small,
    });
    defer core.deinit();
    try std.testing.expectEqual(
        prepared.link_result.plan.externalImportSet().residual_import_set_fingerprint,
        core.manifest_value.residual_import_set_fingerprint,
    );
    try std.testing.expect(core.manifest_value.residual_import_set_fingerprint != image.dispatch_image.dispatch_fingerprint);

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = core.manifest_value.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "seed:argument",
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);

    var output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        core.manifest_value.manifest_fingerprint,
        world.Appliance.Capacity.tiny_one_port,
    );
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), output.host_requests.len);
    try std.testing.expectEqual(root_import.payload_value_ref_fingerprint, output.host_requests[0].payload_value_ref_fingerprint);
    try std.testing.expectEqual(root_import.response_value_ref_fingerprint, output.host_requests[0].expected_response_value_ref_fingerprint);
    try std.testing.expect(output.host_requests[0].frame_request_bytes.len != 0);
    try std.testing.expect(output.host_requests[0].payload_value_image_bytes.len != 0);
    try std.testing.expect(output.host_requests[0].prepared_actuation_evidence_bytes.len != 0);
    try std.testing.expect(output.host_requests[0].idempotency_key_bytes.len != 0);
    try std.testing.expect(!std.mem.eql(u8, output.host_requests[0].frame_request_bytes, "world.appliance.frame_request.v1"));
    try std.testing.expect(!std.mem.eql(u8, output.host_requests[0].payload_value_image_bytes, "world.appliance.payload_value_image.v1"));
    try std.testing.expect(!std.mem.eql(u8, output.host_requests[0].prepared_actuation_evidence_bytes, "world.appliance.prepared_actuation.v1"));
    try std.testing.expect(!std.mem.eql(u8, output.host_requests[0].idempotency_key_bytes, "world.appliance.idempotency_key.v1"));
    try std.testing.expect(output.checkpoint_bytes.len != 0);
    const missing_checkpoint_bytes = world.Appliance.TurnOutput.init(.{
        .manifest_fingerprint = output.manifest_fingerprint,
        .turn_sequence_number = output.turn_sequence_number,
        .source_state_fingerprint = output.source_state_fingerprint,
        .resulting_state_fingerprint = output.resulting_state_fingerprint,
        .quiescence = output.quiescence,
        .status = output.status,
        .host_requests = output.host_requests,
        .finalized_actuation_receipt_fingerprints = output.finalized_actuation_receipt_fingerprints,
        .root_result_fingerprint = output.root_result_fingerprint,
        .root_result_value_image_bytes = output.root_result_value_image_bytes,
        .root_result_value_ref_fingerprint = output.root_result_value_ref_fingerprint,
        .run_receipt_fingerprint = output.run_receipt_fingerprint,
        .run_receipt_bytes = output.run_receipt_bytes,
        .archive_append_batch_fingerprint = output.archive_append_batch_fingerprint,
        .archive_append_batch_ref_fingerprint = output.archive_append_batch_ref_fingerprint,
        .checkpoint_bytes = "",
        .archive_append_batch_bytes = output.archive_append_batch_bytes,
        .checkpoint = output.checkpoint,
        .turn_receipt = output.turn_receipt,
        .blocker_count = output.blocker_count,
        .warning_count = output.warning_count,
        .diagnostic_metadata = output.diagnostic_metadata,
    });
    const missing_checkpoint_payload = try missing_checkpoint_bytes.encode(std.testing.allocator);
    defer std.testing.allocator.free(missing_checkpoint_payload);
    try std.testing.expectError(
        error.InvalidFrameEncoding,
        world.Appliance.TurnOutput.decode(
            std.testing.allocator,
            missing_checkpoint_payload,
            core.manifest_value.manifest_fingerprint,
            world.Appliance.Capacity.tiny_one_port,
        ),
    );
}

test "Universal Runtime validates executable optional import counts" {
    const root_bytes = try fixtures.Agent.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(std.testing.allocator, .{});
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    const root_module = builder.modules.items[0];
    try std.testing.expectEqual(@as(usize, 2), root_module.imports.len);

    const required_import = root_module.imports[0];
    const optional_source = root_module.imports[1];
    const optional_import = world.ImportRequirement.init(.{
        .target_ref_fingerprint = optional_source.target_ref_fingerprint,
        .world_value_table_fingerprint = optional_source.world_value_table_fingerprint,
        .world_surface_fingerprint = optional_source.world_surface_fingerprint,
        .world_port_id = optional_source.world_port_id,
        .world_port_ref_fingerprint = optional_source.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = optional_source.source_effect_shape_ref_fingerprint,
        .residual_site_index = optional_source.residual_site_index,
        .residual_site_fingerprint = optional_source.residual_site_fingerprint,
        .payload_value_table_id = optional_source.payload_value_table_id,
        .payload_value_ref_fingerprint = optional_source.payload_value_ref_fingerprint,
        .response_value_table_id = optional_source.response_value_table_id,
        .response_value_ref_fingerprint = optional_source.response_value_ref_fingerprint,
        .mode = optional_source.mode,
        .allowed_response_kinds = optional_source.allowed_response_kinds,
        .replay_key_recipe_fingerprint = optional_source.replay_key_recipe_fingerprint,
        .suggested_symbolic_name = optional_source.suggested_symbolic_name,
        .required = false,
        .tags = optional_source.tags,
        .metadata = optional_source.metadata,
    });
    const imports = [_]world.ImportRequirement{ required_import, optional_import };

    var optional_module = root_module;
    optional_module.imports = imports[0..];
    optional_module.import_set = world.ImportSet.init(.{
        .target_ref_fingerprint = root_module.import_set.target_ref_fingerprint,
        .required_count = 1,
        .optional_count = 1,
        .world_port_count = root_module.import_set.world_port_count,
        .value_table_entry_count = root_module.import_set.value_table_entry_count,
        .surface_profile_fingerprint = root_module.import_set.surface_profile_fingerprint,
    });
    try optional_module.validate();

    var flattened_module = optional_module;
    flattened_module.import_set = world.ImportSet.init(.{
        .target_ref_fingerprint = root_module.import_set.target_ref_fingerprint,
        .required_count = imports.len,
        .world_port_count = root_module.import_set.world_port_count,
        .value_table_entry_count = root_module.import_set.value_table_entry_count,
        .surface_profile_fingerprint = root_module.import_set.surface_profile_fingerprint,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, flattened_module.validate());
}

test "Universal Runtime orders executable host bindings by dispatch residuals" {
    const root_bytes = try fixtures.Agent.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(root_bytes);

    var builder = world.Executable.Builder.init(std.testing.allocator, .{});
    defer builder.deinit();
    try builder.addRootModule(root_bytes);
    const root_module = builder.modules.items[0];
    try std.testing.expectEqual(@as(usize, 2), root_module.imports.len);

    for (root_module.imports) |root_import| {
        const actuator_ref = if (root_import.world_port_id == ApplianceAgentToolImport.world_port_id)
            ApplianceAgentToolActuationBinding.actuator_ref
        else
            ApplianceAgentActuationBinding.actuator_ref;
        const descriptor = world.Actuation.Descriptor.init(.{
            .actuator_ref = actuator_ref,
            .world_surface_fingerprint = root_module.target_ref.world_surface_fingerprint,
            .target_ref_fingerprint = root_module.target_ref.target_ref_fingerprint,
            .world_port_id = root_import.world_port_id,
            .world_port_ref_fingerprint = root_import.world_port_ref_fingerprint,
            .source_effect_shape_ref_fingerprint = root_import.source_effect_shape_ref_fingerprint,
            .payload_value_table_id = root_import.payload_value_table_id,
            .response_value_table_id = root_import.response_value_table_id,
            .label = "universal-runtime.agent",
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
            .label = "universal-runtime.agent",
        }));
    }

    var prepared = try builder.prepare();
    defer prepared.deinit();
    var image = try prepared.seal();
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), image.external_bindings.len);
    try std.testing.expectEqual(@as(usize, 2), image.dispatch_image.residual_request_order.len);

    const reversed_bindings = [_]world.Executable.ExternalBinding{
        image.external_bindings[1],
        image.external_bindings[0],
    };
    const reordered_image = world.Executable.Image.init(.{
        .required_runtime_profile = image.required_runtime_profile,
        .module_set = image.module_set,
        .link_plan_fingerprint = image.link_plan_fingerprint,
        .linker_certificate_fingerprint = image.linker_certificate_fingerprint,
        .assembly_fingerprint = image.assembly_fingerprint,
        .dispatch_image = image.dispatch_image,
        .external_bindings = &reversed_bindings,
        .memory_plan = image.memory_plan,
        .compatibility_report = image.compatibility_report,
        .metadata = image.metadata,
    });
    const report = try reordered_image.validate(world.Executable.RuntimeProfile.universal_v1);
    try std.testing.expect(report.compatible);

    var core = try world.Appliance.Core.initExecutable(std.testing.allocator, reordered_image, .{
        .profile = .wasm_agent,
    });
    defer core.deinit();
    var expected_binding_fingerprints: [2]u64 = undefined;
    var expected_world_port_ids: [2]u64 = undefined;
    for (image.dispatch_image.residual_request_order, 0..) |requirement_fingerprint, index| {
        const requirement = for (root_module.imports) |root_import| {
            if (root_import.requirement_fingerprint == requirement_fingerprint) break root_import;
        } else return error.ExpectedImportRequirement;
        const binding = for (image.external_bindings) |candidate| {
            if (candidate.matchesRequirement(root_module, requirement)) break candidate;
        } else return error.ExpectedExternalBinding;
        expected_binding_fingerprints[index] = binding.binding_fingerprint;
        expected_world_port_ids[index] = binding.world_port_id;
    }
    try std.testing.expectEqualSlices(u64, &expected_binding_fingerprints, core.manifest_value.actuation_binding_fingerprints);
    try std.testing.expectEqualSlices(u64, &expected_world_port_ids, core.manifest_value.actuation_world_port_ids);
}

test "World Seed Replay accepts batched host replies for independent requests" {
    const AgentAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
        .profile = world.Appliance.Profile.wasm_agent,
        .capacity = world.Appliance.Capacity.wasm_agent,
        .actuation_bindings = .{
            ApplianceAgentActuationBinding,
            ApplianceAgentToolActuationBinding,
        },
    });
    const manifest = AgentAppliance.manifest();
    var core = world.Appliance.Core.initWithCapacity(
        std.testing.allocator,
        manifest,
        AgentAppliance.memoryPlan(),
        world.Appliance.Capacity.wasm_agent,
    );
    defer core.reset();

    const boot = world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
        .root_argument_image = "agent:prompt",
    });
    const boot_bytes = try boot.encode(std.testing.allocator);
    defer std.testing.allocator.free(boot_bytes);
    try core.submit(boot_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.waiting_host, core.state);
    try std.testing.expectEqual(@as(usize, 2), core.outstanding_host_requests.len);
    try std.testing.expectEqual(@as(u32, 0), core.outstanding_host_requests[0].request_ordinal);
    try std.testing.expectEqual(@as(u32, 1), core.outstanding_host_requests[1].request_ordinal);

    const first = core.outstanding_host_requests[0];
    const second = core.outstanding_host_requests[1];
    const duplicate_replies = [_]world.Appliance.HostReply{
        applianceHostReplyFor(first, 0xD600),
        applianceHostReplyFor(first, 0xD601),
    };
    const duplicate_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &duplicate_replies,
    });
    try std.testing.expectError(
        error.DuplicateReply,
        duplicate_command.validate(manifest.manifest_fingerprint, world.Appliance.Capacity.wasm_agent),
    );

    const mixed_replies = [_]world.Appliance.HostReply{
        applianceHostReplyWithStatusFor(first, .failed),
        applianceHostReplyWithStatusFor(second, .pending),
    };
    const mixed_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &mixed_replies,
    });
    const mixed_bytes = try mixed_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(mixed_bytes);
    try std.testing.expectError(error.InvalidCommand, core.submit(mixed_bytes));

    const replies = [_]world.Appliance.HostReply{
        applianceHostReplyFor(second, 0xD602),
        applianceHostReplyFor(first, 0xD603),
    };
    const continue_command = world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 1,
        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
        .host_replies = &replies,
    });
    const continue_bytes = try continue_command.encode(std.testing.allocator);
    defer std.testing.allocator.free(continue_bytes);
    try core.submit(continue_bytes);
    try core.executeTurn();
    try std.testing.expectEqual(world.Appliance.CoreState.completed, core.state);

    var output = try world.Appliance.TurnOutput.decode(
        std.testing.allocator,
        core.readOutput(),
        manifest.manifest_fingerprint,
        world.Appliance.Capacity.wasm_agent,
    );
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Appliance.TurnStatus.completed, output.status);
    try std.testing.expectEqual(@as(usize, 2), output.finalized_actuation_receipt_fingerprints.len);
    try std.testing.expect(output.root_result_fingerprint != null);
    try std.testing.expect(output.root_result_value_image_bytes.len != 0);
    try std.testing.expectEqual(@as(?u64, null), output.root_result_value_ref_fingerprint);
    try std.testing.expect(output.checkpoint_bytes.len != 0);
}

test "WorldV0Report requires every completion proof bit" {
    var proof_receipt_storage: [world.Protocol.required_proof_kind_count]world.Protocol.ProofReceipt = undefined;
    const release_receipt = world.Protocol.canonicalReleaseReceipt(world.Protocol.buildCanonicalProofReceipts(&proof_receipt_storage));
    try release_receipt.validate();
    const report = try world.Appliance.WorldV0Report.fromReleaseReceipt(release_receipt);
    try report.validate();
    try std.testing.expect(report.passed);
    try std.testing.expect(report.allRequiredBooleansPassed());

    const manually_asserted = world.Appliance.WorldV0Report.init(.{
        .boundary_v0_5_0_portable_v2_baseline_passed = true,
        .canonical_executable_image_passed = true,
        .actual_universal_wasm_executed = true,
        .genuinely_unrelated_images_executed = true,
        .internal_loaded_provider_executed = true,
        .multi_suspension_loaded_root_executed = true,
        .active_loaded_fabric_restored = true,
        .verified_replay_without_fresh_effect_passed = true,
        .unsupported_actuated_replay_rejected = true,
        .deterministic_retry_passed = true,
        .batched_request_reply_passed = true,
        .independent_javascript_codec_passed = true,
        .exact_root_result_bytes_passed = true,
        .exact_receipt_bytes_passed = true,
        .exact_capsule_bytes_passed = true,
        .exact_archive_append_batch_bytes_passed = true,
        .native_wasm_parity_passed = true,
        .cold_warm_parity_passed = true,
        .memory_bound_passed = true,
        .malformed_input_suite_passed = true,
        .regression_matrix_passed = true,
        .reproducible_artifact_passed = true,
    });
    try manually_asserted.validate();
    try std.testing.expect(!manually_asserted.passed);
    try std.testing.expect(manually_asserted.allRequiredBooleansPassed());

    const missing_active_restore = world.Appliance.WorldV0Report.init(.{
        .boundary_v0_5_0_portable_v2_baseline_passed = true,
        .canonical_executable_image_passed = true,
        .actual_universal_wasm_executed = true,
        .genuinely_unrelated_images_executed = true,
        .internal_loaded_provider_executed = true,
        .multi_suspension_loaded_root_executed = true,
        .active_loaded_fabric_restored = false,
        .verified_replay_without_fresh_effect_passed = true,
        .unsupported_actuated_replay_rejected = true,
        .deterministic_retry_passed = true,
        .batched_request_reply_passed = true,
        .independent_javascript_codec_passed = true,
        .exact_root_result_bytes_passed = true,
        .exact_receipt_bytes_passed = true,
        .exact_capsule_bytes_passed = true,
        .exact_archive_append_batch_bytes_passed = true,
        .native_wasm_parity_passed = true,
        .cold_warm_parity_passed = true,
        .memory_bound_passed = true,
        .malformed_input_suite_passed = true,
        .regression_matrix_passed = true,
        .reproducible_artifact_passed = true,
    });
    try missing_active_restore.validate();
    try std.testing.expect(!missing_active_restore.passed);

    const missing_actuated_replay_rejection = world.Appliance.WorldV0Report.init(.{
        .boundary_v0_5_0_portable_v2_baseline_passed = true,
        .canonical_executable_image_passed = true,
        .actual_universal_wasm_executed = true,
        .genuinely_unrelated_images_executed = true,
        .internal_loaded_provider_executed = true,
        .multi_suspension_loaded_root_executed = true,
        .active_loaded_fabric_restored = true,
        .verified_replay_without_fresh_effect_passed = true,
        .unsupported_actuated_replay_rejected = false,
        .deterministic_retry_passed = true,
        .batched_request_reply_passed = true,
        .independent_javascript_codec_passed = true,
        .exact_root_result_bytes_passed = true,
        .exact_receipt_bytes_passed = true,
        .exact_capsule_bytes_passed = true,
        .exact_archive_append_batch_bytes_passed = true,
        .native_wasm_parity_passed = true,
        .cold_warm_parity_passed = true,
        .memory_bound_passed = true,
        .malformed_input_suite_passed = true,
        .regression_matrix_passed = true,
        .reproducible_artifact_passed = true,
    });
    try missing_actuated_replay_rejection.validate();
    try std.testing.expect(!missing_actuated_replay_rejection.passed);

    const blocked = world.Appliance.WorldV0Report.init(.{
        .boundary_v0_5_0_portable_v2_baseline_passed = true,
        .canonical_executable_image_passed = true,
        .actual_universal_wasm_executed = true,
        .genuinely_unrelated_images_executed = true,
        .internal_loaded_provider_executed = true,
        .multi_suspension_loaded_root_executed = true,
        .active_loaded_fabric_restored = true,
        .verified_replay_without_fresh_effect_passed = true,
        .unsupported_actuated_replay_rejected = true,
        .deterministic_retry_passed = true,
        .batched_request_reply_passed = true,
        .independent_javascript_codec_passed = true,
        .exact_root_result_bytes_passed = true,
        .exact_receipt_bytes_passed = true,
        .exact_capsule_bytes_passed = true,
        .exact_archive_append_batch_bytes_passed = true,
        .native_wasm_parity_passed = true,
        .cold_warm_parity_passed = true,
        .memory_bound_passed = true,
        .malformed_input_suite_passed = true,
        .regression_matrix_passed = true,
        .reproducible_artifact_passed = true,
        .blockers = &.{0xF00D},
    });
    try blocked.validate();
    try std.testing.expect(blocked.allRequiredBooleansPassed());
    try std.testing.expect(!blocked.passed);

    var missing_proof_storage = proof_receipt_storage;
    missing_proof_storage[@intFromEnum(world.Protocol.ProofKind.active_fabric_restore)] = world.Protocol.ProofReceipt.init(.{
        .proof_kind = .active_fabric_restore,
        .actual_comparison_result = false,
        .blocker_count = 1,
    });
    const incomplete_release_receipt = world.Protocol.canonicalReleaseReceipt(&missing_proof_storage);
    try std.testing.expect(!incomplete_release_receipt.complete);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Appliance.WorldV0Report.fromReleaseReceipt(incomplete_release_receipt));

    var forged = report;
    forged.active_loaded_fabric_restored = false;
    try std.testing.expectError(error.InvalidFrameEncoding, forged.validate());
}

const ApplianceActuationFixture = struct {
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    ref: world.Actuation.Ref,
    descriptor: world.Actuation.Descriptor,
    key: world.Actuation.IdempotencyKey,
    intent: world.Actuation.Intent,
    envelope: world.Actuation.Envelope,
};

fn applianceActuationFixture(class: world.Actuation.Class) ApplianceActuationFixture {
    const target_ref_fingerprint: u64 = 0xA901;
    const world_surface_fingerprint: u64 = 0xA902;
    const request_fingerprint: u64 = 0xA903;
    const ref = world.Actuation.Ref.init(.{
        .kind = .fixture,
        .class = class,
        .label = "appliance-host-model",
        .supported_response_statuses = .all,
    });
    const descriptor = world.Actuation.Descriptor.init(.{
        .actuator_ref = ref,
        .world_surface_fingerprint = world_surface_fingerprint,
        .target_ref_fingerprint = target_ref_fingerprint,
        .world_port_id = 0,
        .allowed_response_kinds = .all,
    });
    const key = world.Actuation.IdempotencyKey.init(.{
        .target_ref_fingerprint = target_ref_fingerprint,
        .world_surface_fingerprint = world_surface_fingerprint,
        .world_port_id = 0,
        .request_fingerprint = request_fingerprint,
        .actuator_ref_fingerprint = ref.ref_fingerprint,
    });
    const intent = world.Actuation.Intent.init(.{
        .actuator_ref_fingerprint = ref.ref_fingerprint,
        .descriptor_fingerprint = descriptor.descriptor_fingerprint,
        .target_ref_fingerprint = target_ref_fingerprint,
        .world_surface_fingerprint = world_surface_fingerprint,
        .world_port_id = 0,
        .frame_request_fingerprint = request_fingerprint,
        .idempotency_key_fingerprint = key.key_fingerprint,
        .class = class,
        .requested_mode = .fresh,
    });
    const envelope = world.Actuation.Envelope.init(.{
        .intent_fingerprint = intent.intent_fingerprint,
        .idempotency_key = key,
        .supervision_ref_fingerprints = &.{0xA904},
    });
    return .{
        .target_ref_fingerprint = target_ref_fingerprint,
        .world_surface_fingerprint = world_surface_fingerprint,
        .ref = ref,
        .descriptor = descriptor,
        .key = key,
        .intent = intent,
        .envelope = envelope,
    };
}
