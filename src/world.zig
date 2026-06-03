const std = @import("std");

pub const Mode = enum {
    fresh,
    replay,
    verify,
    audit,
};

pub const Error = error{
    SurfaceMismatch,
    TargetCertificateMismatch,
    MissingHandler,
    ExtraHandler,
    UnknownWorldPort,
    UnknownResidualSite,
    ResidualSiteFingerprintMismatch,
    WrongTarget,
    PortMismatch,
    ReplayMissing,
    ReplayPortMismatch,
    ReplayRequestFingerprintMismatch,
    ReplayResponseKindMismatch,
    ReplayTargetCertificateMismatch,
    ReplayUnusedEvent,
    ReplaySurfaceMismatch,
    VerifyDivergence,
    HandlerRejected,
    HandlerPending,
    HandlerFailed,
    UnsupportedAfterRequest,
    InvalidMode,
    UnsupportedValueImage,
    NativeOnlyValue,
    MissingValueImage,
    InvalidFrameEncoding,
    FrameSurfaceMismatch,
    FrameTargetCertificateMismatch,
    FramePortMismatch,
    FrameRequestFingerprintMismatch,
    FrameValueTableMismatch,
    MissingBinding,
    ExtraBinding,
    DuplicateBinding,
    WrongWorldSurface,
    WrongTargetCertificate,
    WrongPortId,
    AdapterModeNotAllowed,
    PortableValuesRequired,
    NativeOnlyValueRejected,
    ReplaySourceMissing,
    VerifyTranscriptMissing,
    TranscriptImageRequired,
    TranscriptImageSurfaceMismatch,
    HandoffTargetMismatch,
    HandoffCheckpointMismatch,
    HandoffPendingFrameMismatch,
    SurfaceProfileIncompatible,
    BudgetExceeded,
    SupervisionDenied,
    PortRuleDenied,
    AdapterKindDenied,
    AuthorityDenied,
    PortableValueRequired,
    NativeValueRejected,
    FreshCallDenied,
    ReplayCallDenied,
    PendingDenied,
    BranchDenied,
    HandoffDenied,
    VerifyMissingExpected,
    VerifyResponseKindMismatch,
    VerifyResponseFingerprintMismatch,
    VerifyValueImageMismatch,
    StaleRunHandle,
    RunspaceAdmissionRequired,
    RunspaceInstallDenied,
    InvalidRunspaceTransition,
    InvalidPendingPortTransition,
    PendingPortConsumed,
    OutOfMemory,
};

pub const ResponseKind = enum {
    @"resume",
    return_now,
};

pub const ResponseStatus = enum {
    responded,
    rejected,
    pending,
    failed,
};

pub const EventKind = enum {
    run_started,
    port_requested,
    port_responded,
    port_replayed,
    port_rejected,
    port_failed,
    frame_requested,
    frame_responded,
    frame_replayed,
    frame_verified,
    frame_rejected,
    frame_failed,
    checkpoint_recorded,
    branch_started,
    branch_joined,
    run_completed,
    run_failed,
    permit_issued,
    supervision_check,
    budget_exceeded,
    supervision_denied,
    run_interrupted,
    receipt_recorded,
    admission_requested,
    admission_accepted,
    admission_rejected,
    module_matched_target,
};

test "EventKind keeps legacy transcript ordinals behind v2 image format" {
    try std.testing.expectEqual(@as(u32, 3), world_transcript_image_format_version);
    try std.testing.expectEqual(@as(u8, 15), @intFromEnum(EventKind.run_completed));
    try std.testing.expectEqual(@as(u8, 16), @intFromEnum(EventKind.run_failed));
    try std.testing.expectEqual(@as(u8, 17), @intFromEnum(EventKind.permit_issued));
    try std.testing.expectEqual(@as(u8, 18), @intFromEnum(EventKind.supervision_check));
    try std.testing.expect(@intFromEnum(EventKind.admission_requested) > @intFromEnum(EventKind.receipt_recorded));
}

test "TranscriptImage rejects legacy v1 event stream after supervision event vocabulary bump" {
    var header = [_]u8{0} ** 49;
    std.mem.writeInt(u32, header[0..4], 1, .little);
    std.mem.writeInt(u32, header[4..8], world_transcript_image_fingerprint_version, .little);
    try std.testing.expectError(error.InvalidFrameEncoding, TranscriptImage.decode(std.testing.allocator, &header));
}

pub const ReplayKey = struct {
    world_surface_scope_fingerprint: u64,
    world_port_id: u32,
    request_fingerprint: u64,
    response_fingerprint: u64,

    pub fn fingerprint(self: @This()) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hashBytes(&hasher, "world.replay.key.v0");
        hashU64(&hasher, self.world_surface_scope_fingerprint);
        hashU64(&hasher, self.world_port_id);
        hashU64(&hasher, self.request_fingerprint);
        hashU64(&hasher, self.response_fingerprint);
        return hasher.final();
    }
};

pub const ReplayKeySeed = struct {
    world_surface_fingerprint: u64,
    world_surface_scope_fingerprint: u64,
    world_port_id: u32,
    request_fingerprint: u64,

    pub fn withResponse(self: @This(), response_fingerprint: u64) ReplayKey {
        return .{
            .world_surface_scope_fingerprint = self.world_surface_scope_fingerprint,
            .world_port_id = self.world_port_id,
            .request_fingerprint = self.request_fingerprint,
            .response_fingerprint = response_fingerprint,
        };
    }
};

pub const world_frame_request_format_version: u32 = 1;
pub const world_frame_request_fingerprint_version: u32 = 1;
pub const world_frame_response_format_version: u32 = 1;
pub const world_frame_response_fingerprint_version: u32 = 1;
pub const world_frame_value_image_format_version: u32 = 1;
pub const world_frame_value_image_fingerprint_version: u32 = 1;
pub const world_transcript_image_format_version: u32 = 3;
pub const world_transcript_image_fingerprint_version: u32 = 1;
pub const world_timeline_event_format_version: u32 = 1;
pub const world_timeline_event_fingerprint_version: u32 = 1;
pub const world_timeline_checkpoint_format_version: u32 = 1;
pub const world_timeline_checkpoint_fingerprint_version: u32 = 1;
pub const world_timeline_branch_format_version: u32 = 1;
pub const world_timeline_branch_fingerprint_version: u32 = 1;
pub const world_audit_image_format_version: u32 = 1;
pub const world_audit_image_fingerprint_version: u32 = 1;
pub const world_target_ref_format_version: u32 = 2;
pub const world_target_ref_fingerprint_version: u32 = 1;
pub const world_import_requirement_fingerprint_version: u32 = 1;
pub const world_import_set_fingerprint_version: u32 = 1;
pub const world_binding_format_version: u32 = 1;
pub const world_binding_fingerprint_version: u32 = 1;
pub const world_port_authority_fingerprint_version: u32 = 1;
pub const world_environment_policy_fingerprint_version: u32 = 1;
pub const world_binding_plan_fingerprint_version: u32 = 1;
pub const world_acceptance_report_fingerprint_version: u32 = 1;
pub const world_environment_certificate_format_version: u32 = 1;
pub const world_environment_certificate_fingerprint_version: u32 = 1;
pub const world_adapter_descriptor_fingerprint_version: u32 = 1;
pub const world_run_state_fingerprint_version: u32 = 1;
pub const world_run_image_format_version: u32 = 3;
pub const world_run_image_fingerprint_version: u32 = 1;
pub const world_run_permit_format_version: u32 = 1;
pub const world_run_permit_fingerprint_version: u32 = 1;
pub const world_supervision_policy_fingerprint_version: u32 = 1;
pub const world_budget_fingerprint_version: u32 = 1;
pub const world_cost_model_fingerprint_version: u32 = 1;
pub const world_port_rule_fingerprint_version: u32 = 1;
pub const world_usage_ledger_fingerprint_version: u32 = 1;
pub const world_supervision_check_fingerprint_version: u32 = 1;
pub const world_run_receipt_format_version: u32 = 1;
pub const world_run_receipt_fingerprint_version: u32 = 1;
pub const world_transfer_package_format_version: u32 = 1;
pub const world_transfer_package_fingerprint_version: u32 = 1;
pub const world_package_manifest_format_version: u32 = 1;
pub const world_package_manifest_fingerprint_version: u32 = 1;
pub const world_module_ref_format_version: u32 = 1;
pub const world_module_ref_fingerprint_version: u32 = 1;
pub const world_target_registry_fingerprint_version: u32 = 1;
pub const world_target_registry_entry_fingerprint_version: u32 = 1;
pub const world_target_match_fingerprint_version: u32 = 1;
pub const world_export_summary_fingerprint_version: u32 = 1;
pub const world_admission_policy_fingerprint_version: u32 = 2;
pub const world_admission_request_fingerprint_version: u32 = 1;
pub const world_admission_report_fingerprint_version: u32 = 1;
pub const world_admission_receipt_format_version: u32 = 1;
pub const world_admission_receipt_fingerprint_version: u32 = 3;
pub const world_admitted_run_fingerprint_version: u32 = 5;
pub const world_run_handle_format_version: u32 = 1;
pub const world_run_handle_fingerprint_version: u32 = 1;
pub const world_pending_port_format_version: u32 = 1;
pub const world_pending_port_fingerprint_version: u32 = 1;
pub const world_runspace_config_fingerprint_version: u32 = 1;
pub const world_runspace_event_fingerprint_version: u32 = 1;
pub const world_guest_abi_version: u32 = 1;
pub const world_guest_abi_contract_fingerprint_version: u32 = 1;
pub const world_guest_conformance_vector_fingerprint_version: u32 = 2;
pub const world_guest_conformance_report_fingerprint_version: u32 = 1;

var next_runspace_instance_id = std.atomic.Value(u64).init(0);
pub const world_max_decoded_byte_field_len: usize = 16 * 1024 * 1024;
const frame_response_deferred_fingerprint_flag: u32 = 1 << 0;
const world_min_transcript_event_image_encoded_len_v2: usize = 8 + 1 + 8 + 8 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1;
const world_min_transcript_event_image_encoded_len: usize = world_min_transcript_event_image_encoded_len_v2 + 1 + 1 + 1 + 1 + 1;

pub const ValuePolicy = struct {
    require_portable_values: bool = false,
    allow_native_only_values: bool = true,
    require_response_images_for_replay: bool = false,
    allow_diagnostic_type_labels: bool = true,
    max_value_image_bytes: ?usize = null,

    pub const portable = ValuePolicy{
        .require_portable_values = true,
        .allow_native_only_values = false,
        .require_response_images_for_replay = true,
        .allow_diagnostic_type_labels = false,
    };

    pub const native_compatible = ValuePolicy{};

    pub const audit_only = ValuePolicy{
        .require_portable_values = false,
        .allow_native_only_values = true,
        .require_response_images_for_replay = false,
        .allow_diagnostic_type_labels = true,
    };
};

pub const NormalFormKind = enum {
    unknown,
    strict_closed,
    world_ports_only,
    boundary_normal_form,
};

pub const AdapterKind = enum {
    native,
    replay,
    verify,
    byte,
    null_reject,
    pending_stub,
    custom,
};

pub const BindingModePolicy = enum {
    fresh,
    replay,
    verify,
    audit,
    fresh_and_replay,
    all,
};

pub const AcceptanceBlocker = enum {
    MissingBinding,
    ExtraBinding,
    WrongWorldSurface,
    WrongTargetCertificate,
    WrongPortId,
    PayloadValueMismatch,
    ResponseValueMismatch,
    AdapterModeNotAllowed,
    PortableValuesRequired,
    NativeOnlyValueRejected,
    ReplaySourceMissing,
    VerifyTranscriptMissing,
    SurfaceProfileIncompatible,
    TranscriptImageRequired,
    TranscriptImageSurfaceMismatch,
    HandoffTargetMismatch,
    HandoffCheckpointMismatch,
    HandoffPendingFrameMismatch,
    SupervisionPolicyMismatch,
    SupervisionBudgetExceeded,
    SupervisionPortRuleDenied,
    FreshCallDenied,
    ReplayCallDenied,
    VerifyCallDenied,
};

pub const TargetRef = struct {
    format_version: u32 = world_target_ref_format_version,
    fingerprint_version: u32 = world_target_ref_fingerprint_version,
    target_ref_fingerprint: u64,
    target_label: ?[]const u8 = null,
    world_surface_fingerprint: u64,
    world_surface_replay_scope_fingerprint: ?u64 = null,
    target_certificate_fingerprint: u64,
    residual_program_plan_hash: ?u64 = null,
    normal_form_kind: NormalFormKind = .unknown,
    world_port_table_fingerprint: ?u64 = null,
    world_value_table_fingerprint: ?u64 = null,
    world_dispatch_table_fingerprint: ?u64 = null,
    surface_profile_fingerprint: ?u64 = null,
    boundary_module_fingerprint: ?u64 = null,
    metadata: []const u8 = "",

    pub fn fromTarget(comptime Target: type) @This() {
        @setEvalBranchQuota(20_000);
        var result = @This(){
            .target_ref_fingerprint = 0,
            .target_label = targetLabel(Target),
            .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
            .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
            .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
            .residual_program_plan_hash = residualProgramPlanHash(Target),
            .normal_form_kind = normalFormKind(Target),
            .world_port_table_fingerprint = tableFingerprint(Target.WorldPortTable),
            .world_value_table_fingerprint = tableFingerprint(Target.WorldValueTable),
            .world_dispatch_table_fingerprint = tableFingerprint(Target.WorldDispatchTable),
            .surface_profile_fingerprint = if (@hasDecl(Target, "SurfaceProfile")) tableFingerprint(Target.SurfaceProfile) else null,
            .boundary_module_fingerprint = if (@hasDecl(Target, "Module")) tableFingerprint(Target.Module) else null,
        };
        result.target_ref_fingerprint = fingerprintTargetRef(result);
        return result;
    }

    pub fn matchesTarget(self: @This(), comptime Target: type) bool {
        const expected = fromTarget(Target);
        return self.world_surface_fingerprint == expected.world_surface_fingerprint and
            self.target_certificate_fingerprint == expected.target_certificate_fingerprint and
            self.target_ref_fingerprint == expected.target_ref_fingerprint and
            self.residual_program_plan_hash == expected.residual_program_plan_hash;
    }
};

pub const ImportRequirement = struct {
    requirement_fingerprint: u64,
    world_surface_fingerprint: u64,
    world_port_id: u32,
    world_port_ref_fingerprint: ?u64 = null,
    source_effect_shape_ref_fingerprint: ?u64 = null,
    residual_site_index: usize,
    residual_site_fingerprint: u64,
    payload_value_table_id: ?u32 = null,
    response_value_table_id: ?u32 = null,
    mode: BindingModePolicy = .all,
    allowed_response_kinds: ResponseKindMask = .resume_only,
    replay_key_recipe_fingerprint: ?u64 = null,
    suggested_symbolic_name: ?[]const u8 = null,
    required: bool = true,
    tags: []const []const u8 = &.{},
    metadata: []const u8 = "",

    pub const ResponseKindMask = enum {
        resume_only,
        return_now_only,
        all,
    };

    pub fn fromTargetPort(comptime Target: type, comptime world_port_id: u32) @This() {
        if (world_port_id >= Target.WorldPortTable.entries.len) @compileError("world_port_id out of range");
        const entry = Target.WorldPortTable.entries[world_port_id];
        var result = @This(){
            .requirement_fingerprint = 0,
            .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
            .world_port_id = world_port_id,
            .world_port_ref_fingerprint = refFingerprint(entry.world_port_ref),
            .source_effect_shape_ref_fingerprint = refFingerprint(entry.source_ref),
            .residual_site_index = entry.residual_site_index,
            .residual_site_fingerprint = entry.residual_site_fingerprint,
            .payload_value_table_id = valueIdFor(Target, world_port_id, .payload),
            .response_value_table_id = valueIdFor(Target, world_port_id, .@"resume"),
            .replay_key_recipe_fingerprint = replayKeyRecipeFingerprint(Target),
            .suggested_symbolic_name = if (entry.semantic_label) |label| label else entry.op_name,
        };
        result.requirement_fingerprint = fingerprintImportRequirement(result);
        return result;
    }
};

pub const ImportSet = struct {
    import_set_fingerprint: u64,
    target_ref_fingerprint: u64,
    required_count: usize,
    optional_count: usize = 0,
    world_port_count: usize,
    value_table_entry_count: usize,
    surface_profile_fingerprint: ?u64 = null,

    pub fn fromTarget(comptime Target: type) @This() {
        const target_ref = TargetRef.fromTarget(Target);
        var result = @This(){
            .import_set_fingerprint = 0,
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .required_count = Target.WorldPortTable.entries.len,
            .world_port_count = Target.WorldPortTable.entries.len,
            .value_table_entry_count = Target.WorldValueTable.entries.len,
            .surface_profile_fingerprint = target_ref.surface_profile_fingerprint,
        };
        result.import_set_fingerprint = fingerprintImportSet(result);
        return result;
    }

    pub fn requiredPortIds(self: @This(), allocator: std.mem.Allocator) ![]u32 {
        const ids = try allocator.alloc(u32, self.required_count);
        for (ids, 0..) |*id, index| id.* = @intCast(index);
        return ids;
    }

    pub fn requirementForPort(_: @This(), comptime Target: type, comptime world_port_id: u32) ImportRequirement {
        return ImportRequirement.fromTargetPort(Target, world_port_id);
    }
};

pub const PortAuthority = struct {
    authority_fingerprint: u64,
    authority_label: []const u8 = "",
    authority_kind: Kind = .custom,
    allowed_modes: ModeMask = .all,
    allows_fresh_calls: bool = true,
    allows_replay: bool = true,
    allows_verify: bool = true,
    requires_portable_values: bool = false,
    allows_native_only_values: bool = true,
    max_payload_image_bytes: ?usize = null,
    max_response_image_bytes: ?usize = null,
    metadata: []const u8 = "",

    pub const Kind = enum {
        fixture,
        replay_source,
        native_function,
        byte_adapter,
        model_like,
        tool_like,
        file_like,
        human_like,
        custom,
    };

    pub const ModeMask = enum {
        fresh,
        replay,
        verify,
        audit,
        fresh_and_replay,
        all,
    };

    pub fn init(args: struct {
        authority_label: []const u8 = "",
        authority_kind: Kind = .custom,
        allowed_modes: ModeMask = .all,
        allows_fresh_calls: bool = true,
        allows_replay: bool = true,
        allows_verify: bool = true,
        requires_portable_values: bool = false,
        allows_native_only_values: bool = true,
        max_payload_image_bytes: ?usize = null,
        max_response_image_bytes: ?usize = null,
        metadata: []const u8 = "",
    }) @This() {
        var result = @This(){
            .authority_fingerprint = 0,
            .authority_label = args.authority_label,
            .authority_kind = args.authority_kind,
            .allowed_modes = args.allowed_modes,
            .allows_fresh_calls = args.allows_fresh_calls,
            .allows_replay = args.allows_replay,
            .allows_verify = args.allows_verify,
            .requires_portable_values = args.requires_portable_values,
            .allows_native_only_values = args.allows_native_only_values,
            .max_payload_image_bytes = args.max_payload_image_bytes,
            .max_response_image_bytes = args.max_response_image_bytes,
            .metadata = args.metadata,
        };
        result.authority_fingerprint = fingerprintPortAuthority(result);
        return result;
    }

    pub const fixture = init(.{ .authority_label = "fixture", .authority_kind = .fixture, .allowed_modes = .all });
    pub const replay_source = init(.{ .authority_label = "replay", .authority_kind = .replay_source, .allowed_modes = .replay, .allows_fresh_calls = false, .allows_verify = false });
    pub const native_function = init(.{ .authority_label = "native", .authority_kind = .native_function, .allowed_modes = .all });
};

pub const AdapterDescriptor = struct {
    adapter_kind: AdapterKind,
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    world_port_id: u32,
    value_policy: ValuePolicy = .native_compatible,
    authority_fingerprint: ?u64 = null,
    label: []const u8 = "",
    metadata: []const u8 = "",
    replay_source_fingerprint: ?u64 = null,
    byte_adapter_protocol_label: ?[]const u8 = null,
    descriptor_fingerprint: u64,

    pub fn init(args: struct {
        adapter_kind: AdapterKind,
        target_ref_fingerprint: u64,
        world_surface_fingerprint: u64,
        world_port_id: u32,
        value_policy: ValuePolicy = .native_compatible,
        authority_fingerprint: ?u64 = null,
        label: []const u8 = "",
        metadata: []const u8 = "",
        replay_source_fingerprint: ?u64 = null,
        byte_adapter_protocol_label: ?[]const u8 = null,
    }) @This() {
        var result = @This(){
            .adapter_kind = args.adapter_kind,
            .target_ref_fingerprint = args.target_ref_fingerprint,
            .world_surface_fingerprint = args.world_surface_fingerprint,
            .world_port_id = args.world_port_id,
            .value_policy = args.value_policy,
            .authority_fingerprint = args.authority_fingerprint,
            .label = args.label,
            .metadata = args.metadata,
            .replay_source_fingerprint = args.replay_source_fingerprint,
            .byte_adapter_protocol_label = args.byte_adapter_protocol_label,
            .descriptor_fingerprint = 0,
        };
        result.descriptor_fingerprint = fingerprintAdapterDescriptor(result);
        return result;
    }
};

pub const Binding = struct {
    format_version: u32 = world_binding_format_version,
    fingerprint_version: u32 = world_binding_fingerprint_version,
    binding_fingerprint: u64,
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    world_port_id: u32,
    import_requirement_fingerprint: u64,
    world_port_ref_fingerprint: ?u64 = null,
    source_effect_shape_ref_fingerprint: ?u64 = null,
    payload_value_table_id: ?u32 = null,
    response_value_table_id: ?u32 = null,
    adapter_kind: AdapterKind = .native,
    binding_mode_policy: BindingModePolicy = .all,
    value_policy: ValuePolicy = .native_compatible,
    authority_fingerprint: ?u64 = null,
    adapter_descriptor_fingerprint: u64,
    label: []const u8 = "",
    tags: []const []const u8 = &.{},
    metadata: []const u8 = "",

    pub fn init(args: struct {
        target_ref_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        import_requirement_fingerprint: u64,
        world_port_ref_fingerprint: ?u64 = null,
        source_effect_shape_ref_fingerprint: ?u64 = null,
        payload_value_table_id: ?u32 = null,
        response_value_table_id: ?u32 = null,
        adapter_kind: AdapterKind = .native,
        binding_mode_policy: BindingModePolicy = .all,
        value_policy: ValuePolicy = .native_compatible,
        authority_fingerprint: ?u64 = null,
        adapter_descriptor_fingerprint: u64,
        label: []const u8 = "",
        tags: []const []const u8 = &.{},
        metadata: []const u8 = "",
    }) @This() {
        var result = @This(){
            .binding_fingerprint = 0,
            .target_ref_fingerprint = args.target_ref_fingerprint,
            .world_surface_fingerprint = args.world_surface_fingerprint,
            .target_certificate_fingerprint = args.target_certificate_fingerprint,
            .world_port_id = args.world_port_id,
            .import_requirement_fingerprint = args.import_requirement_fingerprint,
            .world_port_ref_fingerprint = args.world_port_ref_fingerprint,
            .source_effect_shape_ref_fingerprint = args.source_effect_shape_ref_fingerprint,
            .payload_value_table_id = args.payload_value_table_id,
            .response_value_table_id = args.response_value_table_id,
            .adapter_kind = args.adapter_kind,
            .binding_mode_policy = args.binding_mode_policy,
            .value_policy = args.value_policy,
            .authority_fingerprint = args.authority_fingerprint,
            .adapter_descriptor_fingerprint = args.adapter_descriptor_fingerprint,
            .label = args.label,
            .tags = args.tags,
            .metadata = args.metadata,
        };
        result.binding_fingerprint = fingerprintBinding(result);
        return result;
    }
};

pub fn NativeAdapter(comptime handler_fn: anytype) type {
    return struct {
        pub const kind: AdapterKind = .native;
        pub const handler = handler_fn;
        pub const authority = PortAuthority.native_function;
        pub const value_policy = ValuePolicy.native_compatible;
        pub const label = "native";
    };
}

pub fn ReplayAdapter(comptime replay_source_fingerprint: u64) type {
    return struct {
        pub const kind: AdapterKind = .replay;
        pub const authority = PortAuthority.replay_source;
        pub const value_policy = ValuePolicy.portable;
        pub const replay_fingerprint = replay_source_fingerprint;
        pub const label = "replay";
    };
}

pub fn ByteAdapter(comptime protocol_label: []const u8) type {
    return struct {
        pub const kind: AdapterKind = .byte;
        pub const authority = PortAuthority.init(.{ .authority_label = protocol_label, .authority_kind = .byte_adapter, .allowed_modes = .all });
        pub const value_policy = ValuePolicy.portable;
        pub const label = protocol_label;
    };
}

pub fn bind(comptime Decl: type, comptime Adapter: type) type {
    const BasePortDecl = Decl;
    return struct {
        pub const PortDecl = BasePortDecl;
        pub const TargetType = BasePortDecl.TargetType;
        pub const SiteType = BasePortDecl.SiteType;
        pub const Payload = BasePortDecl.Payload;
        pub const Response = BasePortDecl.Response;
        pub const Result = BasePortDecl.Result;
        pub const world_port_id = BasePortDecl.world_port_id;
        pub const residual_site_index = BasePortDecl.residual_site_index;
        pub const residual_site_fingerprint = BasePortDecl.residual_site_fingerprint;
        pub const payload_ref = BasePortDecl.payload_ref;
        pub const response_ref = BasePortDecl.response_ref;
        pub const result_ref = BasePortDecl.result_ref;
        pub const source_ref = BasePortDecl.source_ref;
        pub const world_port_ref = BasePortDecl.world_port_ref;
        pub const suggested_name = BasePortDecl.suggested_name;
        pub const response_deinit = BasePortDecl.response_deinit;
        pub const adapter_kind: AdapterKind = Adapter.kind;
        pub const authority = Adapter.authority;
        pub const value_policy = Adapter.value_policy;
        pub const replay_source_fingerprint: ?u64 = if (@hasDecl(Adapter, "replay_fingerprint")) Adapter.replay_fingerprint else null;
        pub const byte_adapter_protocol_label: ?[]const u8 = if (Adapter.kind == .byte and @hasDecl(Adapter, "label")) Adapter.label else null;
        pub const handler = if (@hasDecl(Adapter, "handler"))
            Adapter.handler
        else if (Adapter.kind == .native)
            BasePortDecl.handler
        else {};

        pub fn replayKey(request_fingerprint: u64) ReplayKeySeed {
            return BasePortDecl.replayKey(request_fingerprint);
        }

        pub fn bindingRecord() Binding {
            const target_ref = TargetRef.fromTarget(TargetType);
            const requirement = ImportRequirement.fromTargetPort(TargetType, world_port_id);
            const descriptor = AdapterDescriptor.init(.{
                .adapter_kind = adapter_kind,
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .world_surface_fingerprint = TargetType.WorldSurface.surface_fingerprint,
                .world_port_id = world_port_id,
                .value_policy = value_policy,
                .authority_fingerprint = authority.authority_fingerprint,
                .label = suggested_name,
                .replay_source_fingerprint = replay_source_fingerprint,
                .byte_adapter_protocol_label = byte_adapter_protocol_label,
            });
            return Binding.init(.{
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .world_surface_fingerprint = TargetType.WorldSurface.surface_fingerprint,
                .target_certificate_fingerprint = TargetType.Certificate.certificate_fingerprint,
                .world_port_id = world_port_id,
                .import_requirement_fingerprint = requirement.requirement_fingerprint,
                .world_port_ref_fingerprint = requirement.world_port_ref_fingerprint,
                .source_effect_shape_ref_fingerprint = requirement.source_effect_shape_ref_fingerprint,
                .payload_value_table_id = requirement.payload_value_table_id,
                .response_value_table_id = requirement.response_value_table_id,
                .adapter_kind = adapter_kind,
                .value_policy = value_policy,
                .authority_fingerprint = authority.authority_fingerprint,
                .adapter_descriptor_fingerprint = descriptor.descriptor_fingerprint,
                .label = suggested_name,
            });
        }
    };
}

pub const EnvironmentPolicy = struct {
    require_all_required_ports_bound: bool = true,
    reject_extra_bindings: bool = true,
    reject_wrong_surface: bool = true,
    require_target_certificate_match: bool = true,
    allow_replay_without_handlers: bool = false,
    allow_fresh_without_transcript: bool = true,
    allow_verify_without_transcript: bool = false,
    require_portable_values: bool = false,
    allow_native_only_values: bool = true,
    require_frame_images_for_replay: bool = true,
    allow_pending_adapters: bool = false,
    allow_reject_adapters: bool = false,
    allow_byte_adapters: bool = true,
    allow_native_adapters: bool = true,
    max_world_ports: ?usize = null,
    max_bindings: ?usize = null,
    policy_fingerprint: u64 = 0,

    pub fn init(args: struct {
        require_all_required_ports_bound: bool = true,
        reject_extra_bindings: bool = true,
        reject_wrong_surface: bool = true,
        require_target_certificate_match: bool = true,
        allow_replay_without_handlers: bool = false,
        allow_fresh_without_transcript: bool = true,
        allow_verify_without_transcript: bool = false,
        require_portable_values: bool = false,
        allow_native_only_values: bool = true,
        require_frame_images_for_replay: bool = true,
        allow_pending_adapters: bool = false,
        allow_reject_adapters: bool = false,
        allow_byte_adapters: bool = true,
        allow_native_adapters: bool = true,
        max_world_ports: ?usize = null,
        max_bindings: ?usize = null,
    }) @This() {
        var result = @This(){
            .require_all_required_ports_bound = args.require_all_required_ports_bound,
            .reject_extra_bindings = args.reject_extra_bindings,
            .reject_wrong_surface = args.reject_wrong_surface,
            .require_target_certificate_match = args.require_target_certificate_match,
            .allow_replay_without_handlers = args.allow_replay_without_handlers,
            .allow_fresh_without_transcript = args.allow_fresh_without_transcript,
            .allow_verify_without_transcript = args.allow_verify_without_transcript,
            .require_portable_values = args.require_portable_values,
            .allow_native_only_values = args.allow_native_only_values,
            .require_frame_images_for_replay = args.require_frame_images_for_replay,
            .allow_pending_adapters = args.allow_pending_adapters,
            .allow_reject_adapters = args.allow_reject_adapters,
            .allow_byte_adapters = args.allow_byte_adapters,
            .allow_native_adapters = args.allow_native_adapters,
            .max_world_ports = args.max_world_ports,
            .max_bindings = args.max_bindings,
        };
        result.policy_fingerprint = fingerprintEnvironmentPolicy(result);
        return result;
    }

    pub const strict_fresh = init(.{ .allow_replay_without_handlers = false });
    pub const strict_replay = init(.{ .allow_replay_without_handlers = true, .allow_native_adapters = false, .require_portable_values = true, .allow_native_only_values = false });
    pub const fresh_and_replay = init(.{ .allow_replay_without_handlers = true });
    pub const verify_against_transcript = init(.{ .allow_verify_without_transcript = false, .require_portable_values = true, .allow_native_only_values = false });
    pub const audit_only = init(.{ .require_all_required_ports_bound = false, .allow_replay_without_handlers = true });
    pub const test_fixture = init(.{ .allow_replay_without_handlers = true, .allow_pending_adapters = true, .allow_reject_adapters = true });
};

pub const BindingPlan = struct {
    plan_fingerprint: u64,
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    binding_count: usize,
    dense_entries: []const Entry = &.{},
    missing_port_ids: []const u32 = &.{},
    extra_binding_ids: []const u32 = &.{},
    accepted: bool,

    pub const Entry = struct {
        world_port_id: u32,
        adapter_slot: usize,
        binding_fingerprint: u64,
        adapter_kind: AdapterKind,
        value_policy: ValuePolicy,
        authority_fingerprint: ?u64,
        adapter_descriptor_fingerprint: u64,
    };

    pub fn lookup(self: @This(), world_port_id: u32) ?usize {
        for (self.dense_entries) |entry| {
            if (entry.world_port_id == world_port_id) return entry.adapter_slot;
        }
        return null;
    }
};

pub const AcceptanceReport = struct {
    report_fingerprint: u64,
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    requested_mode: Mode,
    accepted: bool,
    required_port_count: usize = 0,
    bound_port_count: usize = 0,
    missing_port_count: usize = 0,
    extra_binding_count: usize = 0,
    replay_only_port_count: usize = 0,
    native_port_count: usize = 0,
    byte_adapter_port_count: usize = 0,
    portable_value_compatible_count: usize = 0,
    native_only_value_count: usize = 0,
    blockers: []const AcceptanceBlocker = &.{},
    warnings: []const AcceptanceBlocker = &.{},
    summary: []const u8 = "",
};

pub const EnvironmentCertificate = struct {
    format_version: u32 = world_environment_certificate_format_version,
    fingerprint_version: u32 = world_environment_certificate_fingerprint_version,
    certificate_fingerprint: u64,
    target_ref_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    import_set_fingerprint: u64,
    binding_plan_fingerprint: u64,
    acceptance_report_fingerprint: u64,
    policy_fingerprint: u64,
    authority_descriptor_fingerprint: u64,
    adapter_descriptor_fingerprint: u64,
    accepted_modes: ModeMask = .fresh_replay_verify,
    blocker_count: usize = 0,

    pub const ModeMask = enum {
        none,
        fresh,
        replay,
        verify,
        audit,
        fresh_replay,
        fresh_replay_verify,
        all,
    };
};

pub const Supervisor = Supervision.Supervisor;
pub const RunPermit = Supervision.RunPermit;
pub const SupervisionPolicy = Supervision.SupervisionPolicy;
pub const Budget = Supervision.Budget;
pub const CostModel = Supervision.CostModel;
pub const PortRule = Supervision.PortRule;
pub const UsageLedger = Supervision.UsageLedger;
pub const SupervisionCheck = Supervision.SupervisionCheck;
pub const RunReceipt = Supervision.RunReceipt;

pub const Admission = struct {
    pub const PackageKind = enum {
        target_reference_only,
        module_reference,
        full_module,
        run_reference,
        parked_run,
        completed_run,
        replay_run,
        branch_run,
        inspect_only,
    };

    pub const AdmissionMode = enum {
        inspect_only,
        replay_only,
        verify_only,
        resume_parked,
        continue_fresh,
        branch_resume,
        completed_replay,
        local_target_match_only,
    };

    pub const BoundaryModuleKind = enum {
        reference_only,
        full_module,
        partial_module,
    };

    pub const MatchMode = enum {
        exact,
        reference_only,
        module_full_to_local_target,
        mismatch,
    };

    pub const MatchMismatch = enum {
        WorldSurface,
        TargetCertificate,
        ProgramPlanHash,
        BoundaryModule,
        WorldPortTable,
        WorldValueTable,
        WorldDispatchTable,
        NormalForm,
        ImportSet,
        ExportSet,
    };

    pub const AdmissionBlocker = enum {
        PackageInvalid,
        PackageUnsupportedKind,
        TargetRefMissing,
        TargetNotRegistered,
        TargetMismatch,
        ModuleInvalid,
        ModuleRequiresLocalTarget,
        ModuleLoadedExecutionUnsupported,
        ImportSetUnavailable,
        EnvironmentMissing,
        EnvironmentRejected,
        PermitMissing,
        PermitRejected,
        RunImageInvalid,
        RunImageTargetMismatch,
        TranscriptImageInvalid,
        TranscriptTargetMismatch,
        CheckpointMismatch,
        BranchMismatch,
        PriorReceiptMismatch,
        AdmissionModeNotAllowed,
        PackageLimitExceeded,
    };

    pub const ModuleRef = struct {
        format_version: u32 = world_module_ref_format_version,
        fingerprint_version: u32 = world_module_ref_fingerprint_version,
        module_ref_fingerprint: u64,
        boundary_module_fingerprint: u64,
        module_kind: BoundaryModuleKind,
        target_ref_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        residual_program_plan_hash: ?u64 = null,
        import_surface_fingerprint: ?u64 = null,
        export_surface_fingerprint: ?u64 = null,
        module_graph_fingerprint: ?u64 = null,
        normal_form_kind: NormalFormKind = .unknown,
        world_port_count: usize = 0,
        world_port_table_fingerprint: ?u64 = null,
        world_value_table_fingerprint: ?u64 = null,
        world_dispatch_table_fingerprint: ?u64 = null,
        label: ?[]const u8 = null,
        metadata: []const u8 = "",

        pub fn init(args: struct {
            boundary_module_fingerprint: u64,
            module_kind: BoundaryModuleKind,
            target_ref_fingerprint: u64,
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            residual_program_plan_hash: ?u64 = null,
            import_surface_fingerprint: ?u64 = null,
            export_surface_fingerprint: ?u64 = null,
            module_graph_fingerprint: ?u64 = null,
            normal_form_kind: NormalFormKind = .unknown,
            world_port_count: usize = 0,
            world_port_table_fingerprint: ?u64 = null,
            world_value_table_fingerprint: ?u64 = null,
            world_dispatch_table_fingerprint: ?u64 = null,
            label: ?[]const u8 = null,
            metadata: []const u8 = "",
        }) Admission.ModuleRef {
            var result = Admission.ModuleRef{
                .module_ref_fingerprint = 0,
                .boundary_module_fingerprint = args.boundary_module_fingerprint,
                .module_kind = args.module_kind,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .residual_program_plan_hash = args.residual_program_plan_hash,
                .import_surface_fingerprint = args.import_surface_fingerprint,
                .export_surface_fingerprint = args.export_surface_fingerprint,
                .module_graph_fingerprint = args.module_graph_fingerprint,
                .normal_form_kind = args.normal_form_kind,
                .world_port_count = args.world_port_count,
                .world_port_table_fingerprint = args.world_port_table_fingerprint,
                .world_value_table_fingerprint = args.world_value_table_fingerprint,
                .world_dispatch_table_fingerprint = args.world_dispatch_table_fingerprint,
                .label = args.label,
                .metadata = args.metadata,
            };
            result.module_ref_fingerprint = fingerprintModuleRef(result);
            return result;
        }

        pub fn fromTarget(comptime Target: type) Admission.ModuleRef {
            const target_ref = TargetRef.fromTarget(Target);
            return init(.{
                .boundary_module_fingerprint = target_ref.boundary_module_fingerprint orelse target_ref.target_ref_fingerprint,
                .module_kind = .reference_only,
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .world_surface_fingerprint = target_ref.world_surface_fingerprint,
                .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
                .residual_program_plan_hash = target_ref.residual_program_plan_hash,
                .import_surface_fingerprint = if (@hasDecl(Target, "Module")) Target.Module.manifest.import_surface_fingerprint else null,
                .export_surface_fingerprint = if (@hasDecl(Target, "Module")) Target.Module.manifest.export_surface_fingerprint else null,
                .normal_form_kind = target_ref.normal_form_kind,
                .world_port_count = Target.WorldPortTable.entries.len,
                .world_port_table_fingerprint = target_ref.world_port_table_fingerprint,
                .world_value_table_fingerprint = target_ref.world_value_table_fingerprint,
                .world_dispatch_table_fingerprint = target_ref.world_dispatch_table_fingerprint,
                .label = target_ref.target_label,
            });
        }
    };

    pub fn moduleImageFingerprintForBytes(bytes: []const u8) u64 {
        return moduleImageFingerprint(bytes);
    }

    pub const PackageManifest = struct {
        format_version: u32 = world_package_manifest_format_version,
        fingerprint_version: u32 = world_package_manifest_fingerprint_version,
        manifest_fingerprint: u64,
        package_fingerprint: u64,
        package_kind: PackageKind,
        target_ref_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        module_image_fingerprint: ?u64 = null,
        run_image_fingerprint: ?u64 = null,
        transcript_image_fingerprint: ?u64 = null,
        checkpoint_count: usize = 0,
        branch_count: usize = 0,
        prior_receipt_count: usize = 0,
        requested_mode: Admission.AdmissionMode,
        summary_metadata: []const u8 = "",

        pub fn init(args: struct {
            package_fingerprint: u64,
            package_kind: PackageKind,
            target_ref_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            module_image_fingerprint: ?u64 = null,
            run_image_fingerprint: ?u64 = null,
            transcript_image_fingerprint: ?u64 = null,
            checkpoint_count: usize = 0,
            branch_count: usize = 0,
            prior_receipt_count: usize = 0,
            requested_mode: Admission.AdmissionMode,
            summary_metadata: []const u8 = "",
        }) Admission.PackageManifest {
            var result = Admission.PackageManifest{
                .manifest_fingerprint = 0,
                .package_fingerprint = args.package_fingerprint,
                .package_kind = args.package_kind,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .module_image_fingerprint = args.module_image_fingerprint,
                .run_image_fingerprint = args.run_image_fingerprint,
                .transcript_image_fingerprint = args.transcript_image_fingerprint,
                .checkpoint_count = args.checkpoint_count,
                .branch_count = args.branch_count,
                .prior_receipt_count = args.prior_receipt_count,
                .requested_mode = args.requested_mode,
                .summary_metadata = args.summary_metadata,
            };
            result.manifest_fingerprint = fingerprintPackageManifest(result);
            return result;
        }
    };

    pub const TransferPackage = struct {
        format_version: u32 = world_transfer_package_format_version,
        fingerprint_version: u32 = world_transfer_package_fingerprint_version,
        package_fingerprint: u64,
        manifest: Admission.PackageManifest,
        kind: PackageKind,
        target_ref: ?TargetRef = null,
        module_ref: ?Admission.ModuleRef = null,
        module_image_bytes: ?[]const u8 = null,
        run_image: ?RunImage = null,
        transcript_image: ?TranscriptImage = null,
        checkpoint_refs: []const u64 = &.{},
        branch_refs: []const u64 = &.{},
        prior_run_permit_refs: []const u64 = &.{},
        prior_run_receipt_refs: []const u64 = &.{},
        requested_mode: Admission.AdmissionMode,
        requested_supervision_hint_fingerprint: ?u64 = null,
        metadata: []const u8 = "",
        owns_target_ref_bytes: bool = false,
        owns_module_ref_bytes: bool = false,
        owns_module_image_bytes: bool = false,
        owns_run_image: bool = false,
        owns_transcript_image: bool = false,
        owns_checkpoint_refs: bool = false,
        owns_branch_refs: bool = false,
        owns_prior_run_permit_refs: bool = false,
        owns_prior_run_receipt_refs: bool = false,
        owns_metadata: bool = false,

        pub const ValidateOptions = struct {
            max_package_bytes: usize = world_max_decoded_byte_field_len,
            max_module_bytes: usize = world_max_decoded_byte_field_len,
            max_transcript_bytes: usize = world_max_decoded_byte_field_len,
            max_branches: usize = 4096,
            max_checkpoints: usize = 4096,
            require_target_ref: bool = false,
            require_run_image: bool = false,
            allow_full_module: bool = true,
            allow_reference_only: bool = true,
            allow_inspect_only: bool = true,
            reject_unknown_extensions: bool = true,
        };

        pub fn init(args: struct {
            kind: PackageKind,
            target_ref: ?TargetRef = null,
            module_ref: ?Admission.ModuleRef = null,
            module_image_bytes: ?[]const u8 = null,
            run_image: ?RunImage = null,
            transcript_image: ?TranscriptImage = null,
            checkpoint_refs: []const u64 = &.{},
            branch_refs: []const u64 = &.{},
            prior_run_permit_refs: []const u64 = &.{},
            prior_run_receipt_refs: []const u64 = &.{},
            requested_mode: Admission.AdmissionMode,
            requested_supervision_hint_fingerprint: ?u64 = null,
            metadata: []const u8 = "",
        }) Admission.TransferPackage {
            var result = Admission.TransferPackage{
                .package_fingerprint = 0,
                .manifest = undefined,
                .kind = args.kind,
                .target_ref = args.target_ref,
                .module_ref = args.module_ref,
                .module_image_bytes = args.module_image_bytes,
                .run_image = args.run_image,
                .transcript_image = args.transcript_image,
                .checkpoint_refs = args.checkpoint_refs,
                .branch_refs = args.branch_refs,
                .prior_run_permit_refs = args.prior_run_permit_refs,
                .prior_run_receipt_refs = args.prior_run_receipt_refs,
                .requested_mode = args.requested_mode,
                .requested_supervision_hint_fingerprint = args.requested_supervision_hint_fingerprint,
                .metadata = args.metadata,
            };
            result.package_fingerprint = fingerprintTransferPackageContent(result);
            result.manifest = manifestForTransferPackage(result);
            return result;
        }

        pub fn deinit(self: *Admission.TransferPackage, allocator: std.mem.Allocator) void {
            if (self.owns_target_ref_bytes) {
                if (self.target_ref) |target_ref| {
                    if (target_ref.target_label) |label| allocator.free(@constCast(label));
                    allocator.free(@constCast(target_ref.metadata));
                }
            }
            if (self.owns_module_ref_bytes) {
                if (self.module_ref) |module_ref| {
                    if (module_ref.label) |label| allocator.free(@constCast(label));
                    allocator.free(@constCast(module_ref.metadata));
                }
            }
            if (self.owns_module_image_bytes) if (self.module_image_bytes) |bytes| allocator.free(@constCast(bytes));
            if (self.owns_run_image) if (self.run_image) |*image| image.deinit(allocator);
            if (self.owns_transcript_image) if (self.transcript_image) |*image| image.deinit(allocator);
            if (self.owns_checkpoint_refs) allocator.free(self.checkpoint_refs);
            if (self.owns_branch_refs) allocator.free(self.branch_refs);
            if (self.owns_prior_run_permit_refs) allocator.free(self.prior_run_permit_refs);
            if (self.owns_prior_run_receipt_refs) allocator.free(self.prior_run_receipt_refs);
            if (self.owns_metadata and self.manifest.summary_metadata.ptr != self.metadata.ptr) allocator.free(@constCast(self.manifest.summary_metadata));
            if (self.owns_metadata) allocator.free(@constCast(self.metadata));
            self.* = undefined;
        }

        pub fn encode(self: Admission.TransferPackage, allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.package_fingerprint);
            try encodePackageManifest(&out, allocator, self.manifest);
            try writeU8(&out, allocator, @intFromEnum(self.kind));
            try writeU8(&out, allocator, @intFromEnum(self.requested_mode));
            try writeOptionalTargetRef(&out, allocator, self.target_ref);
            try writeOptionalModuleRef(&out, allocator, self.module_ref);
            try writeOptionalBytes(&out, allocator, self.module_image_bytes);
            try writeOptionalRunImage(&out, allocator, self.run_image);
            try writeOptionalTranscriptImage(&out, allocator, self.transcript_image);
            try writeU64Slice(&out, allocator, self.checkpoint_refs);
            try writeU64Slice(&out, allocator, self.branch_refs);
            try writeU64Slice(&out, allocator, self.prior_run_permit_refs);
            try writeU64Slice(&out, allocator, self.prior_run_receipt_refs);
            try writeOptionalU64(&out, allocator, self.requested_supervision_hint_fingerprint);
            try writeBytes(&out, allocator, self.metadata);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Admission.TransferPackage {
            if (bytes.len > world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
            var cursor: usize = 0;
            const format_version = try readU32(bytes, &cursor);
            if (format_version != world_transfer_package_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, &cursor);
            if (fingerprint_version != world_transfer_package_fingerprint_version) return error.InvalidFrameEncoding;
            const package_fingerprint = try readU64(bytes, &cursor);
            const manifest = try decodePackageManifest(allocator, bytes, &cursor);
            errdefer allocator.free(@constCast(manifest.summary_metadata));
            const kind = try enumFromByte(PackageKind, try readU8(bytes, &cursor));
            const requested_mode = try enumFromByte(Admission.AdmissionMode, try readU8(bytes, &cursor));
            const target_ref = try readOptionalTargetRef(allocator, bytes, &cursor);
            errdefer if (target_ref) |ref| {
                if (ref.target_label) |label| allocator.free(@constCast(label));
                allocator.free(@constCast(ref.metadata));
            };
            const module_ref = try readOptionalModuleRef(allocator, bytes, &cursor);
            errdefer if (module_ref) |ref| {
                if (ref.label) |label| allocator.free(@constCast(label));
                allocator.free(@constCast(ref.metadata));
            };
            const module_image_bytes = try readOptionalBytesOwned(allocator, bytes, &cursor);
            errdefer if (module_image_bytes) |owned| allocator.free(@constCast(owned));
            var run_image = try readOptionalRunImage(allocator, bytes, &cursor);
            errdefer if (run_image) |*image| image.deinit(allocator);
            var transcript_image = try readOptionalTranscriptImage(allocator, bytes, &cursor);
            errdefer if (transcript_image) |*image| image.deinit(allocator);
            const checkpoint_refs = try readU64SliceOwned(allocator, bytes, &cursor, (ValidateOptions{}).max_checkpoints);
            errdefer allocator.free(checkpoint_refs);
            const branch_refs = try readU64SliceOwned(allocator, bytes, &cursor, (ValidateOptions{}).max_branches);
            errdefer allocator.free(branch_refs);
            const prior_run_permit_refs = try readU64SliceOwned(allocator, bytes, &cursor, 4096);
            errdefer allocator.free(prior_run_permit_refs);
            const prior_run_receipt_refs = try readU64SliceOwned(allocator, bytes, &cursor, 4096);
            errdefer allocator.free(prior_run_receipt_refs);
            const requested_supervision_hint_fingerprint = try readOptionalU64(bytes, &cursor);
            const metadata = try readBytesOwned(allocator, bytes, &cursor);
            errdefer allocator.free(metadata);
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            var result = Admission.TransferPackage{
                .format_version = format_version,
                .fingerprint_version = fingerprint_version,
                .package_fingerprint = package_fingerprint,
                .manifest = manifest,
                .kind = kind,
                .target_ref = target_ref,
                .module_ref = module_ref,
                .module_image_bytes = module_image_bytes,
                .run_image = run_image,
                .transcript_image = transcript_image,
                .checkpoint_refs = checkpoint_refs,
                .branch_refs = branch_refs,
                .prior_run_permit_refs = prior_run_permit_refs,
                .prior_run_receipt_refs = prior_run_receipt_refs,
                .requested_mode = requested_mode,
                .requested_supervision_hint_fingerprint = requested_supervision_hint_fingerprint,
                .metadata = metadata,
                .owns_target_ref_bytes = target_ref != null,
                .owns_module_ref_bytes = module_ref != null,
                .owns_module_image_bytes = module_image_bytes != null,
                .owns_run_image = run_image != null,
                .owns_transcript_image = transcript_image != null,
                .owns_checkpoint_refs = true,
                .owns_branch_refs = true,
                .owns_prior_run_permit_refs = true,
                .owns_prior_run_receipt_refs = true,
                .owns_metadata = true,
            };
            try result.validate(.{ .max_package_bytes = bytes.len });
            run_image = null;
            transcript_image = null;
            return result;
        }

        pub fn validate(self: Admission.TransferPackage, options: ValidateOptions) !void {
            _ = options.reject_unknown_extensions;
            if (self.format_version != world_transfer_package_format_version) return error.InvalidFrameEncoding;
            if (self.fingerprint_version != world_transfer_package_fingerprint_version) return error.InvalidFrameEncoding;
            if (self.metadata.len > options.max_package_bytes) return error.InvalidFrameEncoding;
            if (options.require_target_ref and self.target_ref == null and self.run_image == null) return error.InvalidFrameEncoding;
            if (options.require_run_image and self.run_image == null) return error.InvalidFrameEncoding;
            if (!options.allow_inspect_only and self.kind == .inspect_only) return error.InvalidFrameEncoding;
            if (self.kind == .target_reference_only and self.target_ref == null and self.run_image == null) return error.InvalidFrameEncoding;
            if (!options.allow_reference_only and self.kind == .target_reference_only) return error.InvalidFrameEncoding;
            if (self.target_ref) |target_ref| {
                if (target_ref.target_label) |label| if (label.len > options.max_package_bytes) return error.InvalidFrameEncoding;
                if (target_ref.metadata.len > options.max_package_bytes) return error.InvalidFrameEncoding;
            }
            switch (self.kind) {
                .target_reference_only => {},
                .inspect_only => if (self.target_ref == null and self.module_ref == null and self.module_image_bytes == null and self.run_image == null and self.transcript_image == null) return error.InvalidFrameEncoding,
                .module_reference => if (self.module_ref == null) return error.InvalidFrameEncoding,
                .full_module => if (self.module_image_bytes == null) return error.InvalidFrameEncoding,
                .replay_run => if (self.run_image == null and self.transcript_image == null) return error.InvalidFrameEncoding,
                .run_reference, .parked_run, .completed_run, .branch_run => if (self.run_image == null) return error.InvalidFrameEncoding,
            }
            if (self.run_image) |image| {
                if (!transferPackageKindMatchesRunImage(self.kind, image.kind, self.requested_mode)) return error.InvalidFrameEncoding;
            }
            if (self.module_ref) |module_ref| {
                if (module_ref.format_version != world_module_ref_format_version) return error.InvalidFrameEncoding;
                if (module_ref.fingerprint_version != world_module_ref_fingerprint_version) return error.InvalidFrameEncoding;
                if (module_ref.module_ref_fingerprint != fingerprintModuleRef(module_ref)) return error.InvalidFrameEncoding;
                if (!options.allow_reference_only and module_ref.module_kind == .reference_only) return error.InvalidFrameEncoding;
                if (!options.allow_full_module and module_ref.module_kind == .full_module) return error.InvalidFrameEncoding;
                if (module_ref.module_kind == .full_module and self.module_image_bytes == null) return error.InvalidFrameEncoding;
                if (module_ref.metadata.len > options.max_package_bytes) return error.InvalidFrameEncoding;
                if (module_ref.label) |label| if (label.len > options.max_package_bytes) return error.InvalidFrameEncoding;
            }
            if (self.kind == .full_module and self.module_image_bytes == null) return error.InvalidFrameEncoding;
            if (self.module_image_bytes) |bytes| {
                const module_image_matches_run = if (self.run_image) |image|
                    if (image.module_image_fingerprint) |fingerprint| fingerprint == moduleImageFingerprint(bytes) else false
                else
                    false;
                if (self.kind != .full_module and !module_image_matches_run) return error.InvalidFrameEncoding;
                if (!options.allow_full_module) return error.InvalidFrameEncoding;
                if (bytes.len > options.max_module_bytes) return error.InvalidFrameEncoding;
                if (bytes.len > options.max_package_bytes) return error.InvalidFrameEncoding;
            }
            if (self.checkpoint_refs.len > options.max_checkpoints) return error.InvalidFrameEncoding;
            if (self.branch_refs.len > options.max_branches) return error.InvalidFrameEncoding;
            if (self.transcript_image) |image| {
                try validateTranscriptImageFingerprint(image);
                if (transcriptImageEncodedByteSize(image) > options.max_transcript_bytes) return error.InvalidFrameEncoding;
                if (transcriptImageEncodedByteSize(image) > options.max_package_bytes) return error.InvalidFrameEncoding;
            }
            if (self.run_image) |image| {
                try image.validate(.{
                    .max_image_bytes = options.max_package_bytes,
                    .max_branches = options.max_branches,
                    .max_checkpoints = options.max_checkpoints,
                    .allow_reference_target = options.allow_reference_only,
                });
                if (image.transcript_image) |embedded| {
                    try validateTranscriptImageFingerprint(embedded);
                    if (transcriptImageEncodedByteSize(embedded) > options.max_transcript_bytes) return error.InvalidFrameEncoding;
                    if (transcriptImageEncodedByteSize(embedded) > options.max_package_bytes) return error.InvalidFrameEncoding;
                }
            }
            if (transferPackageEncodedByteSize(self) > options.max_package_bytes) return error.InvalidFrameEncoding;
            if (self.target_ref) |target_ref| {
                try validateTargetRef(target_ref);
                if (self.module_ref) |module_ref| {
                    if (module_ref.module_kind != .full_module and module_ref.target_ref_fingerprint != target_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
                    if (module_ref.world_surface_fingerprint != target_ref.world_surface_fingerprint) return error.HandoffTargetMismatch;
                    if (module_ref.target_certificate_fingerprint != target_ref.target_certificate_fingerprint) return error.HandoffTargetMismatch;
                    if (module_ref.residual_program_plan_hash != target_ref.residual_program_plan_hash) return error.HandoffTargetMismatch;
                }
            }
            if (self.run_image) |image| {
                if (self.target_ref) |target_ref| {
                    if (image.target_ref.target_ref_fingerprint != target_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
                }
                if (runImageHasModuleWitness(image) and self.module_ref == null and self.module_image_bytes == null) return error.InvalidFrameEncoding;
                if (self.module_ref) |module_ref| {
                    if (runImageHasModuleWitness(image) and image.module_ref_fingerprint == null) return error.InvalidFrameEncoding;
                    if (image.module_ref_fingerprint) |run_module_ref_fingerprint| {
                        if (run_module_ref_fingerprint != module_ref.module_ref_fingerprint) return error.HandoffTargetMismatch;
                    }
                    if (image.boundary_module_fingerprint) |run_boundary_module_fingerprint| {
                        if (run_boundary_module_fingerprint != module_ref.boundary_module_fingerprint) return error.HandoffTargetMismatch;
                    }
                    if (image.module_image_fingerprint) |run_module_image_fingerprint| {
                        const module_image_bytes = self.module_image_bytes orelse return error.InvalidFrameEncoding;
                        if (run_module_image_fingerprint != moduleImageFingerprint(module_image_bytes)) return error.HandoffTargetMismatch;
                    }
                    if (module_ref.module_kind == .full_module) {
                        if (image.target_ref.world_surface_fingerprint != module_ref.world_surface_fingerprint) return error.HandoffTargetMismatch;
                        if (image.target_ref.target_certificate_fingerprint != module_ref.target_certificate_fingerprint) return error.HandoffTargetMismatch;
                        if (image.target_ref.residual_program_plan_hash != module_ref.residual_program_plan_hash) return error.HandoffTargetMismatch;
                    } else if (image.target_ref.target_ref_fingerprint != module_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
                }
            }
            if (self.transcript_image) |image| {
                if (self.target_ref) |target_ref| {
                    if (image.world_surface_fingerprint != target_ref.world_surface_fingerprint) return error.TranscriptImageSurfaceMismatch;
                    if (image.target_certificate_fingerprint != target_ref.target_certificate_fingerprint) return error.TargetCertificateMismatch;
                }
                if (self.run_image) |run_image| {
                    if (run_image.current_state.transcript_image_fingerprint) |state_fingerprint| {
                        if (state_fingerprint != image.transcript_image_fingerprint) return error.InvalidFrameEncoding;
                    } else {
                        return error.InvalidFrameEncoding;
                    }
                    if (run_image.transcript_image) |embedded| {
                        if (embedded.transcript_image_fingerprint != image.transcript_image_fingerprint) return error.InvalidFrameEncoding;
                    }
                    if (image.world_surface_fingerprint != run_image.target_ref.world_surface_fingerprint) return error.TranscriptImageSurfaceMismatch;
                    if (image.target_certificate_fingerprint != run_image.target_ref.target_certificate_fingerprint) return error.TargetCertificateMismatch;
                }
            }
            if (self.package_fingerprint != fingerprintTransferPackageContent(self)) return error.InvalidFrameEncoding;
            const manifest = manifestForTransferPackage(self);
            if (!packageManifestEquals(self.manifest, manifest)) return error.InvalidFrameEncoding;
        }
    };

    pub const TargetRegistry = struct {
        registry_fingerprint: u64,
        entries: []const Entry = &.{},

        pub const Entry = struct {
            entry_fingerprint: u64,
            target_ref: TargetRef,
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            program_plan_hash: ?u64 = null,
            import_surface_fingerprint: ?u64 = null,
            export_surface_fingerprint: ?u64 = null,
            import_set_fingerprint: u64,
            world_port_count: usize = 0,
            world_port_table_fingerprint: ?u64 = null,
            world_value_table_fingerprint: ?u64 = null,
            world_dispatch_table_fingerprint: ?u64 = null,
            normal_form_kind: NormalFormKind = .unknown,
            label: ?[]const u8 = null,
            metadata: []const u8 = "",

            pub fn fromTarget(comptime Target: type) Entry {
                const target_ref = TargetRef.fromTarget(Target);
                const import_set = ImportSet.fromTarget(Target);
                var result = Entry{
                    .entry_fingerprint = 0,
                    .target_ref = target_ref,
                    .world_surface_fingerprint = target_ref.world_surface_fingerprint,
                    .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
                    .program_plan_hash = target_ref.residual_program_plan_hash,
                    .import_surface_fingerprint = if (@hasDecl(Target, "Module")) Target.Module.manifest.import_surface_fingerprint else null,
                    .export_surface_fingerprint = if (@hasDecl(Target, "Module")) Target.Module.manifest.export_surface_fingerprint else null,
                    .import_set_fingerprint = import_set.import_set_fingerprint,
                    .world_port_count = import_set.world_port_count,
                    .world_port_table_fingerprint = target_ref.world_port_table_fingerprint,
                    .world_value_table_fingerprint = target_ref.world_value_table_fingerprint,
                    .world_dispatch_table_fingerprint = target_ref.world_dispatch_table_fingerprint,
                    .normal_form_kind = target_ref.normal_form_kind,
                    .label = target_ref.target_label,
                };
                result.entry_fingerprint = fingerprintTargetRegistryEntry(result);
                return result;
            }
        };

        pub fn init(entries: []const Entry) Admission.TargetRegistry {
            var result = Admission.TargetRegistry{
                .registry_fingerprint = 0,
                .entries = entries,
            };
            result.registry_fingerprint = fingerprintTargetRegistry(result);
            return result;
        }

        pub fn initChecked(entries: []const Entry) !Admission.TargetRegistry {
            const registry = init(entries);
            try registry.validate();
            return registry;
        }

        pub fn validate(self: Admission.TargetRegistry) !void {
            for (self.entries) |entry| {
                try validateTargetRegistryEntry(entry);
                if (entry.entry_fingerprint != fingerprintTargetRegistryEntry(entry)) return error.TargetRegistryConflict;
            }
            if (self.registry_fingerprint != fingerprintTargetRegistry(self)) return error.TargetRegistryConflict;
            for (self.entries, 0..) |entry, index| {
                for (self.entries[index + 1 ..]) |other| {
                    if (entry.target_ref.target_ref_fingerprint == other.target_ref.target_ref_fingerprint and
                        entry.entry_fingerprint != other.entry_fingerprint)
                    {
                        return error.TargetRegistryConflict;
                    }
                }
            }
        }

        pub fn register(comptime Target: type) Entry {
            return Entry.fromTarget(Target);
        }

        pub fn find(self: Admission.TargetRegistry, target_ref: TargetRef) ?Entry {
            for (self.entries) |entry| {
                if (entry.target_ref.target_ref_fingerprint == target_ref.target_ref_fingerprint) return entry;
            }
            return null;
        }

        pub fn matchModule(self: Admission.TargetRegistry, module_ref: Admission.ModuleRef) ?Entry {
            for (self.entries) |entry| {
                const candidate = entry.target_ref.target_ref_fingerprint == module_ref.target_ref_fingerprint or
                    (entry.world_surface_fingerprint == module_ref.world_surface_fingerprint and
                        entry.target_certificate_fingerprint == module_ref.target_certificate_fingerprint and
                        entry.program_plan_hash == module_ref.residual_program_plan_hash);
                if (!candidate) continue;
                const match_result = Admission.TargetMatch.matchEntry(null, module_ref, entry);
                if (match_result.matched) return entry;
            }
            return null;
        }

        fn matchModuleTarget(self: Admission.TargetRegistry, target_ref: ?TargetRef, module_ref: Admission.ModuleRef) ?Admission.TargetMatch {
            var fallback: ?Admission.TargetMatch = null;
            for (self.entries) |entry| {
                const candidate = entry.target_ref.target_ref_fingerprint == module_ref.target_ref_fingerprint or
                    (entry.world_surface_fingerprint == module_ref.world_surface_fingerprint and
                        entry.target_certificate_fingerprint == module_ref.target_certificate_fingerprint and
                        entry.program_plan_hash == module_ref.residual_program_plan_hash);
                if (!candidate) continue;
                const match_result = Admission.TargetMatch.matchEntry(target_ref, module_ref, entry);
                if (match_result.matched) return match_result;
                if (fallback == null) fallback = match_result;
            }
            return fallback;
        }

        pub fn requireMatch(self: Admission.TargetRegistry, target_ref: TargetRef) !Entry {
            return self.find(target_ref) orelse error.HandoffTargetMismatch;
        }

        pub fn match(self: Admission.TargetRegistry, target_ref: ?TargetRef, module_ref: ?Admission.ModuleRef) Admission.TargetMatch {
            if (module_ref) |module| {
                if (self.matchModuleTarget(target_ref, module)) |match_result| return match_result;
                return Admission.TargetMatch.missing(target_ref, module);
            }
            if (target_ref) |target| {
                if (self.find(target)) |entry| return Admission.TargetMatch.matchEntry(target, null, entry);
                return Admission.TargetMatch.missing(target, null);
            }
            return Admission.TargetMatch.missing(null, null);
        }
    };

    pub const TargetMatch = struct {
        match_fingerprint: u64,
        transferred_target_ref_fingerprint: ?u64 = null,
        local_target_ref_fingerprint: ?u64 = null,
        matched: bool = false,
        match_mode: MatchMode = .mismatch,
        mismatches: []const MatchMismatch = &.{},
        diagnostics: []const u8 = "",

        pub fn matchTarget(ref: TargetRef, comptime Target: type) Admission.TargetMatch {
            return matchEntry(ref, null, Admission.TargetRegistry.Entry.fromTarget(Target));
        }

        pub fn matchModule(module_ref: Admission.ModuleRef, comptime Target: type) Admission.TargetMatch {
            return matchEntry(null, module_ref, Admission.TargetRegistry.Entry.fromTarget(Target));
        }

        fn matchEntry(target_ref: ?TargetRef, module_ref: ?Admission.ModuleRef, entry: Admission.TargetRegistry.Entry) Admission.TargetMatch {
            var first_mismatch: ?MatchMismatch = null;
            if (target_ref) |target| {
                if (target.world_surface_fingerprint != entry.world_surface_fingerprint and first_mismatch == null) first_mismatch = .WorldSurface;
                if (target.target_certificate_fingerprint != entry.target_certificate_fingerprint and first_mismatch == null) first_mismatch = .TargetCertificate;
                if (target.residual_program_plan_hash != entry.program_plan_hash and first_mismatch == null) first_mismatch = .ProgramPlanHash;
                if (target.normal_form_kind != entry.normal_form_kind and first_mismatch == null) first_mismatch = .NormalForm;
                if (!providedFingerprintMatches(target.world_port_table_fingerprint, entry.world_port_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldPortTable;
                if (!providedFingerprintMatches(target.world_value_table_fingerprint, entry.world_value_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldValueTable;
                if (!providedFingerprintMatches(target.world_dispatch_table_fingerprint, entry.world_dispatch_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldDispatchTable;
            }
            if (module_ref) |module| {
                if (module.module_kind != .full_module and module.target_ref_fingerprint != entry.target_ref.target_ref_fingerprint and first_mismatch == null) first_mismatch = .ProgramPlanHash;
                if (module.world_surface_fingerprint != entry.world_surface_fingerprint and first_mismatch == null) first_mismatch = .WorldSurface;
                if (module.target_certificate_fingerprint != entry.target_certificate_fingerprint and first_mismatch == null) first_mismatch = .TargetCertificate;
                if (module.residual_program_plan_hash != entry.program_plan_hash and first_mismatch == null) first_mismatch = .ProgramPlanHash;
                if (module.module_kind != .full_module and module.boundary_module_fingerprint != (entry.target_ref.boundary_module_fingerprint orelse entry.target_ref.target_ref_fingerprint) and first_mismatch == null) first_mismatch = .BoundaryModule;
                if (module.normal_form_kind != .unknown and module.normal_form_kind != entry.normal_form_kind and first_mismatch == null) first_mismatch = .NormalForm;
                if (module.world_port_count != 0 and module.world_port_count != entry.world_port_count and first_mismatch == null) first_mismatch = .WorldPortTable;
                if (!providedFingerprintMatches(module.import_surface_fingerprint, entry.import_surface_fingerprint) and first_mismatch == null) first_mismatch = .ImportSet;
                if (!providedFingerprintMatches(module.export_surface_fingerprint, entry.export_surface_fingerprint) and first_mismatch == null) first_mismatch = .ExportSet;
                if (!providedFingerprintMatches(module.world_port_table_fingerprint, entry.world_port_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldPortTable;
                if (!providedFingerprintMatches(module.world_value_table_fingerprint, entry.world_value_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldValueTable;
                if (!providedFingerprintMatches(module.world_dispatch_table_fingerprint, entry.world_dispatch_table_fingerprint) and first_mismatch == null) first_mismatch = .WorldDispatchTable;
            }
            const supported_module_kind = if (module_ref) |module| module.module_kind != .partial_module else true;
            const matched = first_mismatch == null and supported_module_kind;
            var result = Admission.TargetMatch{
                .match_fingerprint = 0,
                .transferred_target_ref_fingerprint = if (target_ref) |target| target.target_ref_fingerprint else if (module_ref) |module| module.target_ref_fingerprint else null,
                .local_target_ref_fingerprint = entry.target_ref.target_ref_fingerprint,
                .matched = matched,
                .match_mode = if (!matched) .mismatch else if (module_ref) |module| switch (module.module_kind) {
                    .reference_only => .reference_only,
                    .full_module => .module_full_to_local_target,
                    .partial_module => .mismatch,
                } else .exact,
                .mismatches = mismatchSlice(first_mismatch),
                .diagnostics = if (matched) "matched" else "target/module identity mismatch",
            };
            result.match_fingerprint = fingerprintTargetMatch(result);
            return result;
        }

        fn missing(target_ref: ?TargetRef, module_ref: ?Admission.ModuleRef) Admission.TargetMatch {
            var result = Admission.TargetMatch{
                .match_fingerprint = 0,
                .transferred_target_ref_fingerprint = if (target_ref) |target| target.target_ref_fingerprint else if (module_ref) |module| module.target_ref_fingerprint else null,
                .matched = false,
                .match_mode = .mismatch,
                .diagnostics = "target not registered",
            };
            result.match_fingerprint = fingerprintTargetMatch(result);
            return result;
        }
    };

    pub const ExportSummary = struct {
        export_summary_fingerprint: u64,
        target_ref_fingerprint: u64,
        module_ref_fingerprint: ?u64 = null,
        main_export_present: bool = true,
        result_value_ref_fingerprint: ?u64 = null,
        argument_value_ref_count: usize = 0,
        normal_form_kind: NormalFormKind = .unknown,
        target_label: ?[]const u8 = null,
        loaded_execution_supported: bool = false,
        loaded_execution_unsupported_reason: ?[]const u8 = "Boundary LoadedModule.Session is fail-closed",

        pub fn init(args: struct {
            target_ref_fingerprint: u64,
            module_ref_fingerprint: ?u64 = null,
            main_export_present: bool = true,
            result_value_ref_fingerprint: ?u64 = null,
            argument_value_ref_count: usize = 0,
            normal_form_kind: NormalFormKind = .unknown,
            target_label: ?[]const u8 = null,
            loaded_execution_supported: bool = false,
            loaded_execution_unsupported_reason: ?[]const u8 = "Boundary LoadedModule.Session is fail-closed",
        }) Admission.ExportSummary {
            var result = Admission.ExportSummary{
                .export_summary_fingerprint = 0,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .main_export_present = args.main_export_present,
                .result_value_ref_fingerprint = args.result_value_ref_fingerprint,
                .argument_value_ref_count = args.argument_value_ref_count,
                .normal_form_kind = args.normal_form_kind,
                .target_label = args.target_label,
                .loaded_execution_supported = args.loaded_execution_supported,
                .loaded_execution_unsupported_reason = args.loaded_execution_unsupported_reason,
            };
            result.export_summary_fingerprint = fingerprintExportSummary(result);
            return result;
        }
    };

    pub const ModuleGateway = struct {
        pub fn decodeBoundaryModule(comptime Target: type, allocator: std.mem.Allocator, bytes: []const u8) !Target.Module.LoadedModule {
            return Target.Module.decode(allocator, bytes);
        }

        pub fn refFromTarget(comptime Target: type) Admission.ModuleRef {
            return Admission.ModuleRef.fromTarget(Target);
        }

        pub fn refFromBoundaryModule(module: anytype) Admission.ModuleRef {
            const manifest = module.manifest();
            const main_export = module.mainExport();
            return Admission.ModuleRef.init(.{
                .boundary_module_fingerprint = manifest.module_fingerprint,
                .module_kind = boundaryModuleKindFromName(@tagName(manifest.module_kind)),
                .target_ref_fingerprint = fingerprintTargetRef(targetRefFromModuleManifest(manifest)),
                .world_surface_fingerprint = manifest.world_surface_fingerprint,
                .target_certificate_fingerprint = manifest.target_certificate_fingerprint,
                .residual_program_plan_hash = manifest.program_plan_hash,
                .import_surface_fingerprint = manifest.import_surface_fingerprint,
                .export_surface_fingerprint = manifest.export_surface_fingerprint,
                .normal_form_kind = normalFormKindFromName(@tagName(main_export.normal_form)),
                .world_port_count = manifest.world_port_count,
                .label = manifest.target_label,
            });
        }

        pub fn importSetFromTarget(comptime Target: type) ImportSet {
            return ImportSet.fromTarget(Target);
        }

        pub fn importSetFromBoundaryModule(module: anytype) ImportSet {
            const module_ref = refFromBoundaryModule(module);
            const imports = module.imports();
            var result = ImportSet{
                .import_set_fingerprint = 0,
                .target_ref_fingerprint = module_ref.target_ref_fingerprint,
                .required_count = module.requiredImports().len,
                .optional_count = module.optionalImports().len,
                .world_port_count = imports.len,
                .value_table_entry_count = imports.len * 2,
            };
            result.import_set_fingerprint = fingerprintImportSet(result);
            return result;
        }

        pub fn exportSummaryFromTarget(comptime Target: type) Admission.ExportSummary {
            const target_ref = TargetRef.fromTarget(Target);
            return Admission.ExportSummary.init(.{
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .module_ref_fingerprint = Admission.ModuleRef.fromTarget(Target).module_ref_fingerprint,
                .normal_form_kind = target_ref.normal_form_kind,
                .target_label = target_ref.target_label,
            });
        }

        pub fn exportSummaryFromBoundaryModule(module: anytype) Admission.ExportSummary {
            const module_ref = refFromBoundaryModule(module);
            return Admission.ExportSummary.init(.{
                .target_ref_fingerprint = module_ref.target_ref_fingerprint,
                .module_ref_fingerprint = module_ref.module_ref_fingerprint,
                .main_export_present = true,
                .argument_value_ref_count = module.argumentValueRefs().len,
                .normal_form_kind = module_ref.normal_form_kind,
                .target_label = module_ref.label,
                .loaded_execution_supported = false,
                .loaded_execution_unsupported_reason = "Boundary LoadedModule.Session is fail-closed",
            });
        }

        pub fn matchLocalTarget(registry: Admission.TargetRegistry, module_ref: Admission.ModuleRef) Admission.TargetMatch {
            return registry.match(null, module_ref);
        }
    };

    pub const AdmissionPolicy = struct {
        allow_reference_targets: bool = true,
        allow_full_modules: bool = false,
        allow_inspect_only_full_modules: bool = false,
        require_local_target_for_execution: bool = true,
        require_environment_preflight: bool = true,
        require_supervision_permit: bool = true,
        allow_continue_fresh: bool = true,
        allow_replay_without_environment: bool = false,
        allow_verify_without_fresh_environment: bool = false,
        allow_parked_resume: bool = true,
        allow_branch_resume: bool = true,
        allow_completed_replay: bool = true,
        reject_target_mismatch: bool = true,
        reject_module_mismatch: bool = true,
        reject_transcript_mismatch: bool = true,
        reject_prior_receipt_mismatch: bool = false,
        max_package_bytes: usize = world_max_decoded_byte_field_len,
        max_module_bytes: usize = world_max_decoded_byte_field_len,
        max_transcript_bytes: usize = world_max_decoded_byte_field_len,
        max_branches: usize = 4096,
        max_checkpoints: usize = 4096,
        policy_fingerprint: u64 = 0,

        pub fn init(args: struct {
            allow_reference_targets: bool = true,
            allow_full_modules: bool = false,
            allow_inspect_only_full_modules: bool = false,
            require_local_target_for_execution: bool = true,
            require_environment_preflight: bool = true,
            require_supervision_permit: bool = true,
            allow_continue_fresh: bool = true,
            allow_replay_without_environment: bool = false,
            allow_verify_without_fresh_environment: bool = false,
            allow_parked_resume: bool = true,
            allow_branch_resume: bool = true,
            allow_completed_replay: bool = true,
            reject_target_mismatch: bool = true,
            reject_module_mismatch: bool = true,
            reject_transcript_mismatch: bool = true,
            reject_prior_receipt_mismatch: bool = false,
            max_package_bytes: usize = world_max_decoded_byte_field_len,
            max_module_bytes: usize = world_max_decoded_byte_field_len,
            max_transcript_bytes: usize = world_max_decoded_byte_field_len,
            max_branches: usize = 4096,
            max_checkpoints: usize = 4096,
        }) Admission.AdmissionPolicy {
            var result = Admission.AdmissionPolicy{
                .allow_reference_targets = args.allow_reference_targets,
                .allow_full_modules = args.allow_full_modules,
                .allow_inspect_only_full_modules = args.allow_inspect_only_full_modules,
                .require_local_target_for_execution = args.require_local_target_for_execution,
                .require_environment_preflight = args.require_environment_preflight,
                .require_supervision_permit = args.require_supervision_permit,
                .allow_continue_fresh = args.allow_continue_fresh,
                .allow_replay_without_environment = args.allow_replay_without_environment,
                .allow_verify_without_fresh_environment = args.allow_verify_without_fresh_environment,
                .allow_parked_resume = args.allow_parked_resume,
                .allow_branch_resume = args.allow_branch_resume,
                .allow_completed_replay = args.allow_completed_replay,
                .reject_target_mismatch = args.reject_target_mismatch,
                .reject_module_mismatch = args.reject_module_mismatch,
                .reject_transcript_mismatch = args.reject_transcript_mismatch,
                .reject_prior_receipt_mismatch = args.reject_prior_receipt_mismatch,
                .max_package_bytes = args.max_package_bytes,
                .max_module_bytes = args.max_module_bytes,
                .max_transcript_bytes = args.max_transcript_bytes,
                .max_branches = args.max_branches,
                .max_checkpoints = args.max_checkpoints,
            };
            result.policy_fingerprint = fingerprintAdmissionPolicy(result);
            return result;
        }

        pub fn allowsMode(self: Admission.AdmissionPolicy, mode: Admission.AdmissionMode) bool {
            return switch (mode) {
                .inspect_only => self.allow_inspect_only_full_modules or self.allow_reference_targets,
                .replay_only => self.allow_completed_replay or self.allow_replay_without_environment,
                .verify_only => self.allow_verify_without_fresh_environment or self.require_environment_preflight,
                .resume_parked => self.allow_parked_resume,
                .continue_fresh => self.allow_continue_fresh and self.require_environment_preflight,
                .branch_resume => self.allow_branch_resume,
                .completed_replay => self.allow_completed_replay,
                .local_target_match_only => true,
            };
        }

        pub fn withFingerprint(self: Admission.AdmissionPolicy) Admission.AdmissionPolicy {
            var result = self;
            result.policy_fingerprint = 0;
            result.policy_fingerprint = fingerprintAdmissionPolicy(result);
            return result;
        }

        pub const strict_local_execution = init(.{});
        pub const inspect_modules = init(.{
            .allow_full_modules = true,
            .allow_inspect_only_full_modules = true,
            .require_local_target_for_execution = false,
            .require_environment_preflight = false,
            .require_supervision_permit = false,
            .allow_continue_fresh = false,
            .allow_parked_resume = false,
            .allow_branch_resume = false,
            .allow_completed_replay = false,
        });
        pub const replay_only = init(.{
            .require_environment_preflight = false,
            .require_supervision_permit = false,
            .allow_replay_without_environment = true,
            .allow_parked_resume = false,
            .allow_branch_resume = false,
        });
        pub const handoff_receiver = init(.{});
        pub const verify_receiver = init(.{
            .require_supervision_permit = false,
            .allow_verify_without_fresh_environment = true,
            .allow_continue_fresh = false,
            .allow_parked_resume = false,
            .allow_branch_resume = false,
            .allow_completed_replay = false,
        });
        pub const test_fixture = init(.{
            .allow_full_modules = true,
            .allow_inspect_only_full_modules = true,
            .require_supervision_permit = false,
            .allow_replay_without_environment = true,
            .allow_verify_without_fresh_environment = true,
        });
    };

    pub const AdmissionRequest = struct {
        request_fingerprint: u64,
        package_fingerprint: u64,
        mode: Admission.AdmissionMode,
        policy_fingerprint: u64,
        target_registry_fingerprint: ?u64 = null,
        environment_certificate_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        requested_branch_id: ?u64 = null,
        requested_checkpoint_ref: ?u64 = null,
        metadata: []const u8 = "",

        pub fn init(args: struct {
            package_fingerprint: u64,
            mode: Admission.AdmissionMode,
            policy_fingerprint: u64,
            target_registry_fingerprint: ?u64 = null,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            requested_branch_id: ?u64 = null,
            requested_checkpoint_ref: ?u64 = null,
            metadata: []const u8 = "",
        }) Admission.AdmissionRequest {
            var result = Admission.AdmissionRequest{
                .request_fingerprint = 0,
                .package_fingerprint = args.package_fingerprint,
                .mode = args.mode,
                .policy_fingerprint = args.policy_fingerprint,
                .target_registry_fingerprint = args.target_registry_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .requested_branch_id = args.requested_branch_id,
                .requested_checkpoint_ref = args.requested_checkpoint_ref,
                .metadata = args.metadata,
            };
            result.request_fingerprint = fingerprintAdmissionRequest(result);
            return result;
        }
    };

    pub const AdmissionReport = struct {
        report_fingerprint: u64,
        accepted: bool,
        mode: Admission.AdmissionMode,
        package_fingerprint: u64,
        manifest_fingerprint: u64,
        target_ref_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        import_set_fingerprint: ?u64 = null,
        environment_acceptance_report_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        handoff_preflight_report_fingerprint: ?u64 = null,
        blockers: []const AdmissionBlocker = &.{},
        warnings: []const AdmissionBlocker = &.{},
        summary: []const u8 = "",

        pub fn accept(args: struct {
            request: Admission.AdmissionRequest,
            package_fingerprint: u64,
            manifest_fingerprint: u64,
            target_ref_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            target_match_fingerprint: ?u64 = null,
            import_set_fingerprint: ?u64 = null,
            environment_acceptance_report_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            handoff_preflight_report_fingerprint: ?u64 = null,
            warnings: []const AdmissionBlocker = &.{},
            summary: []const u8 = "admission accepted",
        }) Admission.AdmissionReport {
            var result = Admission.AdmissionReport{
                .report_fingerprint = 0,
                .accepted = true,
                .mode = args.request.mode,
                .package_fingerprint = args.package_fingerprint,
                .manifest_fingerprint = args.manifest_fingerprint,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .target_match_fingerprint = args.target_match_fingerprint,
                .import_set_fingerprint = args.import_set_fingerprint,
                .environment_acceptance_report_fingerprint = args.environment_acceptance_report_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .handoff_preflight_report_fingerprint = args.handoff_preflight_report_fingerprint,
                .warnings = args.warnings,
                .summary = args.summary,
            };
            result.report_fingerprint = fingerprintAdmissionReport(result);
            return result;
        }

        pub fn rejected(args: struct {
            request: Admission.AdmissionRequest,
            package_fingerprint: u64,
            manifest_fingerprint: u64,
            target_ref_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            target_match_fingerprint: ?u64 = null,
            import_set_fingerprint: ?u64 = null,
            environment_acceptance_report_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            handoff_preflight_report_fingerprint: ?u64 = null,
            blockers: []const AdmissionBlocker,
            warnings: []const AdmissionBlocker = &.{},
            summary: []const u8 = "admission rejected",
        }) Admission.AdmissionReport {
            var result = Admission.AdmissionReport{
                .report_fingerprint = 0,
                .accepted = false,
                .mode = args.request.mode,
                .package_fingerprint = args.package_fingerprint,
                .manifest_fingerprint = args.manifest_fingerprint,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .target_match_fingerprint = args.target_match_fingerprint,
                .import_set_fingerprint = args.import_set_fingerprint,
                .environment_acceptance_report_fingerprint = args.environment_acceptance_report_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .handoff_preflight_report_fingerprint = args.handoff_preflight_report_fingerprint,
                .blockers = args.blockers,
                .warnings = args.warnings,
                .summary = args.summary,
            };
            result.report_fingerprint = fingerprintAdmissionReport(result);
            return result;
        }
    };

    pub const AdmissionReceipt = struct {
        format_version: u32 = world_admission_receipt_format_version,
        fingerprint_version: u32 = world_admission_receipt_fingerprint_version,
        receipt_fingerprint: u64,
        admission_request_fingerprint: u64,
        admission_report_fingerprint: u64,
        package_fingerprint: u64,
        target_ref_fingerprint: u64,
        module_ref_fingerprint: ?u64 = null,
        local_target_ref_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        environment_certificate_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        admitted_run_fingerprint: ?u64 = null,
        accepted_mode: Admission.AdmissionMode,
        warnings: []const AdmissionBlocker = &.{},
        metadata: []const u8 = "",

        pub fn init(args: struct {
            request: Admission.AdmissionRequest,
            report: Admission.AdmissionReport,
            target_ref_fingerprint: u64,
            module_ref_fingerprint: ?u64 = null,
            local_target_ref_fingerprint: ?u64 = null,
            target_match_fingerprint: ?u64 = null,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            admitted_run_fingerprint: ?u64 = null,
            warnings: []const AdmissionBlocker = &.{},
            metadata: []const u8 = "",
        }) Admission.AdmissionReceipt {
            var result = Admission.AdmissionReceipt{
                .receipt_fingerprint = 0,
                .admission_request_fingerprint = args.request.request_fingerprint,
                .admission_report_fingerprint = args.report.report_fingerprint,
                .package_fingerprint = args.report.package_fingerprint,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .local_target_ref_fingerprint = args.local_target_ref_fingerprint,
                .target_match_fingerprint = args.target_match_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .admitted_run_fingerprint = args.admitted_run_fingerprint,
                .accepted_mode = args.request.mode,
                .warnings = args.warnings,
                .metadata = args.metadata,
            };
            result.receipt_fingerprint = fingerprintAdmissionReceipt(result);
            return result;
        }
    };

    pub const AdmittedRun = struct {
        admitted_run_fingerprint: u64,
        admission_receipt_fingerprint: u64,
        admission_receipt: ?Admission.AdmissionReceipt = null,
        target_ref: TargetRef,
        module_ref_fingerprint: ?u64 = null,
        import_set_fingerprint: ?u64 = null,
        environment_certificate_fingerprint: ?u64 = null,
        run_permit: ?RunPermit = null,
        run_image: ?RunImage = null,
        owns_run_image: bool = false,
        transcript_image: ?TranscriptImage = null,
        owns_transcript_image: bool = false,
        selected_branch_id: ?u64 = null,
        selected_checkpoint_ref: ?u64 = null,
        mode: Admission.AdmissionMode,

        pub fn init(args: struct {
            admission_receipt_fingerprint: u64,
            admission_receipt: ?Admission.AdmissionReceipt = null,
            target_ref: TargetRef,
            module_ref_fingerprint: ?u64 = null,
            import_set_fingerprint: ?u64 = null,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit: ?RunPermit = null,
            run_image: ?RunImage = null,
            owns_run_image: bool = false,
            transcript_image: ?TranscriptImage = null,
            owns_transcript_image: bool = false,
            selected_branch_id: ?u64 = null,
            selected_checkpoint_ref: ?u64 = null,
            mode: Admission.AdmissionMode,
        }) Admission.AdmittedRun {
            var result = Admission.AdmittedRun{
                .admitted_run_fingerprint = 0,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .admission_receipt = args.admission_receipt,
                .target_ref = args.target_ref,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .import_set_fingerprint = args.import_set_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .run_permit = args.run_permit,
                .run_image = args.run_image,
                .owns_run_image = args.owns_run_image,
                .transcript_image = args.transcript_image,
                .owns_transcript_image = args.owns_transcript_image,
                .selected_branch_id = args.selected_branch_id,
                .selected_checkpoint_ref = args.selected_checkpoint_ref,
                .mode = args.mode,
            };
            result.admitted_run_fingerprint = fingerprintAdmittedRun(result);
            return result;
        }

        pub fn deinit(self: *Admission.AdmittedRun, allocator: std.mem.Allocator) void {
            if (self.owns_run_image) if (self.run_image) |*image| image.deinit(allocator);
            if (self.owns_transcript_image) if (self.transcript_image) |*image| image.deinit(allocator);
            self.* = undefined;
        }

        pub fn start(self: *Admission.AdmittedRun, comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !Machine(Target, Env.machine_config).Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            if (!self.target_ref.matchesTarget(Target)) return Error.HandoffTargetMismatch;
            const Options = @TypeOf(options);
            const requested_mode: Mode = if (comptime @hasField(Options, "mode")) @field(options, "mode") else .fresh;
            if (requested_mode != admissionModeToRunMode(self.mode)) return Error.HandoffDenied;
            if (self.mode == .resume_parked or self.mode == .branch_resume) return Error.HandoffDenied;
            const stored_transcript_image: ?*TranscriptImage = if (self.transcript_image) |*image|
                image
            else if (self.run_image) |*image|
                if (image.transcript_image) |*transcript_image| transcript_image else null
            else
                null;
            const supplied_transcript_image: ?*TranscriptImage = if (comptime @hasField(Options, "transcript_image"))
                @field(options, "transcript_image")
            else
                null;
            const transcript_sink_available = comptime @hasField(Options, "transcript") and Env.policy_decl.allow_native_adapters;
            const transcript_available = if (requested_mode == .fresh)
                transcript_sink_available
            else
                supplied_transcript_image != null or stored_transcript_image != null or transcript_sink_available;
            if (self.environment_certificate_fingerprint) |fingerprint| {
                if (Env.certificate(requested_mode, transcript_available).certificate_fingerprint != fingerprint) return Error.HandoffDenied;
            }
            const expected_transcript_fingerprint: ?u64 = if (self.mode == .continue_fresh)
                null
            else if (self.transcript_image) |image|
                image.transcript_image_fingerprint
            else if (self.run_image) |image|
                image.current_state.transcript_image_fingerprint
            else
                null;
            if (expected_transcript_fingerprint) |fingerprint| {
                const candidate = supplied_transcript_image orelse stored_transcript_image orelse return Error.HandoffDenied;
                validateTranscriptImageFingerprint(candidate.*) catch return Error.HandoffDenied;
                if (candidate.transcript_image_fingerprint != fingerprint) return Error.HandoffDenied;
            }
            const use_stored_transcript = modeConsumesTranscript(requested_mode) and
                supplied_transcript_image == null and
                stored_transcript_image != null;
            if (use_stored_transcript) {
                const image = stored_transcript_image.?;
                image.resetReplay();
                image.validateReplayRun(
                    Target.WorldSurface.surface_fingerprint,
                    Target.Certificate.certificate_fingerprint,
                ) catch return Error.HandoffDenied;
            }
            if (self.run_permit) |permit| {
                if (comptime !@hasField(Options, "permit")) return Error.SupervisionDenied;
                if (@field(options, "permit").permit_fingerprint != permit.permit_fingerprint) return Error.SupervisionDenied;
                const scoped_permit = scopePermitToAdmission(permit, self.admission_receipt_fingerprint);
                if (use_stored_transcript) return Machine(Target, Env.machine_config).startWithAdmittedTranscriptPermit(runtime, args, options, scoped_permit, stored_transcript_image.?);
                return Machine(Target, Env.machine_config).startWithPermit(runtime, args, options, scoped_permit);
            }
            if (use_stored_transcript) return Machine(Target, Env.machine_config).startWithAdmittedTranscript(runtime, args, options, stored_transcript_image.?);
            return Machine(Target, Env.machine_config).start(runtime, args, options);
        }

        pub fn @"resume"(self: *Admission.AdmittedRun, allocator: std.mem.Allocator, comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !Machine(Target, Env.machine_config).Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            if (self.mode != .resume_parked and self.mode != .branch_resume) return Error.HandoffDenied;
            const Options = @TypeOf(options);
            const requested_mode: Mode = if (comptime @hasField(Options, "mode")) @field(options, "mode") else .fresh;
            if (requested_mode != .fresh) return Error.HandoffDenied;
            if (self.run_permit) |permit| {
                if (comptime !@hasField(Options, "permit")) return Error.SupervisionDenied;
                if (@field(options, "permit").permit_fingerprint != permit.permit_fingerprint) return Error.SupervisionDenied;
            }
            var image = self.run_image orelse return error.HandoffPendingFrameMismatch;
            if (image.transcript_image) |transcript_image| {
                try attachBorrowedTranscriptToRunImage(&image, transcript_image);
            } else if (self.transcript_image) |transcript_image| {
                try attachBorrowedTranscriptToRunImage(&image, transcript_image);
            }
            const transcript_sink_available = comptime @hasField(Options, "transcript") and Env.policy_decl.allow_native_adapters;
            if (self.environment_certificate_fingerprint) |fingerprint| {
                if (Env.certificate(.fresh, image.transcript_image != null or transcript_sink_available).certificate_fingerprint != fingerprint) return Error.HandoffDenied;
            }
            const encoded = try image.encode(allocator);
            defer allocator.free(encoded);
            var handoff = try Handoff.fromRunImage(allocator, encoded);
            defer handoff.deinit();
            if (self.run_permit) |permit| {
                const scoped_permit = scopePermitToAdmission(permit, self.admission_receipt_fingerprint);
                return handoff.resumeWithPermit(Target, Env, runtime, args, options, .accept_fresh, scoped_permit);
            }
            return handoff.@"resume"(Target, Env, runtime, args, options, .accept_fresh);
        }
    };

    pub const AdmissionResult = struct {
        request: Admission.AdmissionRequest,
        report: Admission.AdmissionReport,
        receipt: ?Admission.AdmissionReceipt = null,
        admitted_run: ?Admission.AdmittedRun = null,
        target_match: ?Admission.TargetMatch = null,

        pub fn deinit(self: *Admission.AdmissionResult, allocator: std.mem.Allocator) void {
            if (self.admitted_run) |*admitted| admitted.deinit(allocator);
            self.* = undefined;
        }
    };

    pub const Admitter = struct {
        registry: Admission.TargetRegistry,
        policy: Admission.AdmissionPolicy = .strict_local_execution,

        pub fn init(args: struct {
            registry: Admission.TargetRegistry,
            policy: Admission.AdmissionPolicy = .strict_local_execution,
        }) Admitter {
            return .{ .registry = args.registry, .policy = args.policy };
        }

        pub fn admitForTarget(self: Admitter, comptime Target: type, comptime Env: type, package: Admission.TransferPackage, args: struct {
            mode: ?Admission.AdmissionMode = null,
            permit: ?RunPermit = null,
            requested_branch_id: ?u64 = null,
            requested_checkpoint_ref: ?u64 = null,
            fresh_transcript_sink_available: bool = false,
            metadata: []const u8 = "",
            allocator: std.mem.Allocator = std.heap.page_allocator,
        }) AdmissionResult {
            const mode = args.mode orelse package.requested_mode;
            const policy = self.policy.withFingerprint();
            const package_transcript_available = package.transcript_image != null or
                (package.run_image != null and package.run_image.?.transcript_image != null);
            const fresh_transcript_sink_available = args.fresh_transcript_sink_available and Env.policy_decl.allow_native_adapters;
            const transcript_available = switch (mode) {
                .continue_fresh => fresh_transcript_sink_available,
                .resume_parked, .branch_resume => package_transcript_available or fresh_transcript_sink_available,
                else => package_transcript_available,
            };
            const environment_certificate_fingerprint: ?u64 = if (mode == .inspect_only)
                null
            else
                Env.certificate(admissionModeToRunMode(mode), transcript_available).certificate_fingerprint;
            const request = Admission.AdmissionRequest.init(.{
                .package_fingerprint = package.package_fingerprint,
                .mode = mode,
                .policy_fingerprint = policy.policy_fingerprint,
                .target_registry_fingerprint = self.registry.registry_fingerprint,
                .environment_certificate_fingerprint = environment_certificate_fingerprint,
                .run_permit_fingerprint = if (args.permit) |permit| permit.permit_fingerprint else null,
                .requested_branch_id = args.requested_branch_id,
                .requested_checkpoint_ref = args.requested_checkpoint_ref,
                .metadata = args.metadata,
            });
            if (package.kind == .target_reference_only and package.target_ref == null and package.run_image == null) {
                return rejectedResult(request, package, null, null, null, &.{.TargetRefMissing}, "target reference package is missing target ref");
            }
            if (package.transcript_image != null and package.target_ref == null and package.run_image == null and package.module_ref == null) {
                return rejectedResult(request, package, null, null, null, &.{.TargetRefMissing}, "transcript package is missing target binding");
            }
            const module_reference_only = package.target_ref == null and package.run_image == null and package.module_image_bytes == null and package.module_ref != null;
            const target_ref = package.target_ref orelse if (package.run_image) |image| image.target_ref else TargetRef.fromTarget(Target);
            var module_ref = package.module_ref;
            if (!effectiveAdmissionModeMatchesPackage(package.requested_mode, mode)) {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.PackageInvalid}, "admission mode does not match package requested mode");
            }
            package.validate(.{
                .max_package_bytes = policy.max_package_bytes,
                .max_module_bytes = policy.max_module_bytes,
                .max_transcript_bytes = policy.max_transcript_bytes,
                .max_branches = policy.max_branches,
                .max_checkpoints = policy.max_checkpoints,
                .require_target_ref = false,
                .require_run_image = admissionModeNeedsRunImage(mode),
                .allow_full_module = policy.allow_full_modules or (mode == .inspect_only and policy.allow_inspect_only_full_modules),
                .allow_reference_only = policy.allow_reference_targets,
                .allow_inspect_only = policy.allow_reference_targets or policy.allow_inspect_only_full_modules,
            }) catch {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.PackageInvalid}, "package validation failed");
            };
            if (package.run_image) |image| {
                if (!runImageFitsAdmissionMode(image, mode)) {
                    if (mode != .inspect_only and mode != .local_target_match_only) {
                        return rejectedResult(request, package, target_ref, module_ref, null, &.{.RunImageInvalid}, "run image does not match requested admission mode");
                    }
                }
            }
            if ((mode == .replay_only or mode == .verify_only) and package.run_image == null and package.transcript_image == null) {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.RunImageInvalid}, "replay or verify admission requires run or transcript evidence");
            }
            if (package.module_image_bytes) |module_bytes| {
                if (comptime !@hasDecl(Target, "Module")) {
                    return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleLoadedExecutionUnsupported}, "target has no Boundary module validator");
                }
                _ = Target.Module.validate(module_bytes, .{}) catch {
                    return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "full module bytes failed validation");
                };
                var loaded_module = Admission.ModuleGateway.decodeBoundaryModule(Target, args.allocator, module_bytes) catch {
                    return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "full module bytes failed decoding");
                };
                defer loaded_module.deinit();
                const loaded_module_ref = Admission.ModuleGateway.refFromBoundaryModule(loaded_module);
                if (package.run_image) |image| {
                    if (image.module_ref_fingerprint) |fingerprint| {
                        if (fingerprint != loaded_module_ref.module_ref_fingerprint) {
                            return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "run image module ref does not match module bytes");
                        }
                    }
                    if (image.boundary_module_fingerprint) |fingerprint| {
                        if (fingerprint != loaded_module_ref.boundary_module_fingerprint) {
                            return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "run image boundary module does not match module bytes");
                        }
                    }
                    if (image.module_image_fingerprint) |fingerprint| {
                        if (fingerprint != moduleImageFingerprint(module_bytes)) {
                            return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "run image module image does not match module bytes");
                        }
                    }
                }
                if (module_ref) |supplied| {
                    if (supplied.module_ref_fingerprint != loaded_module_ref.module_ref_fingerprint) {
                        return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "module ref does not match module bytes");
                    }
                } else {
                    module_ref = loaded_module_ref;
                }
                if (target_ref.world_surface_fingerprint != loaded_module_ref.world_surface_fingerprint or
                    target_ref.target_certificate_fingerprint != loaded_module_ref.target_certificate_fingerprint or
                    target_ref.residual_program_plan_hash != loaded_module_ref.residual_program_plan_hash)
                {
                    return rejectedResult(request, package, target_ref, module_ref, null, &.{.ModuleInvalid}, "target ref does not match module bytes");
                }
            }
            self.registry.validate() catch {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.TargetMismatch}, "target registry contains conflicting entries");
            };
            if (mode == .inspect_only and !policy.allow_reference_targets and module_ref == null and package.module_image_bytes == null) {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.PackageInvalid}, "inspect-only admission requires module evidence");
            }
            if (!policy.allowsMode(mode)) {
                return rejectedResult(request, package, target_ref, module_ref, null, &.{.AdmissionModeNotAllowed}, "admission mode is not allowed by policy");
            }
            const match = self.registry.match(target_ref, module_ref);
            if (module_reference_only and !match.matched) return rejectedResult(request, package, target_ref, module_ref, match, &.{.TargetNotRegistered}, "module reference did not match a local target");
            if (policy.require_local_target_for_execution or mode != .inspect_only) {
                if (!match.matched and module_ref != null and policy.reject_module_mismatch) return rejectedResult(request, package, target_ref, module_ref, match, &.{.ModuleInvalid}, "module mismatch");
                if (!match.matched) return rejectedResult(request, package, target_ref, module_ref, match, &.{.TargetNotRegistered}, "target not registered");
                if (policy.reject_target_mismatch and match.match_mode == .mismatch) return rejectedResult(request, package, target_ref, module_ref, match, &.{.TargetMismatch}, "target mismatch");
            }
            if (policy.reject_prior_receipt_mismatch) {
                if (package.run_image) |image| {
                    if (image.prior_run_permit_fingerprint) |fingerprint| {
                        if (!containsU64(package.prior_run_permit_refs, fingerprint)) return rejectedResult(request, package, target_ref, module_ref, match, &.{.PriorReceiptMismatch}, "run image prior permit is not listed in package prior permits");
                    }
                    if (image.prior_run_receipt_fingerprint) |fingerprint| {
                        if (!containsU64(package.prior_run_receipt_refs, fingerprint)) return rejectedResult(request, package, target_ref, module_ref, match, &.{.PriorReceiptMismatch}, "run image prior receipt is not listed in package prior receipts");
                    }
                }
            }
            if (args.requested_branch_id) |branch_id| {
                if (!packageContainsBranch(package, branch_id)) return rejectedResult(request, package, target_ref, module_ref, match, &.{.BranchMismatch}, "requested branch is not present in transfer package");
                if (package.run_image == null or package.run_image.?.current_state.branch_id != branch_id) return rejectedResult(request, package, target_ref, module_ref, match, &.{.BranchMismatch}, "requested branch does not match current run state");
            } else if (mode == .branch_resume) {
                return rejectedResult(request, package, target_ref, module_ref, match, &.{.BranchMismatch}, "branch resume requires a selected branch");
            }
            if (args.requested_checkpoint_ref) |checkpoint_ref| {
                if (!packageContainsCheckpoint(package, checkpoint_ref)) return rejectedResult(request, package, target_ref, module_ref, match, &.{.CheckpointMismatch}, "requested checkpoint is not present in transfer package");
                if (package.run_image == null or package.run_image.?.current_state.checkpoint_fingerprint != checkpoint_ref) return rejectedResult(request, package, target_ref, module_ref, match, &.{.CheckpointMismatch}, "requested checkpoint does not match current run state");
            }
            const local_target_ref = TargetRef.fromTarget(Target);
            if (match.matched and match.local_target_ref_fingerprint != local_target_ref.target_ref_fingerprint) {
                return rejectedResult(request, package, target_ref, module_ref, match, &.{.TargetMismatch}, "registry match does not name requested local target");
            }
            if (module_ref) |module| {
                if (module.module_kind == .full_module and mode != .inspect_only and policy.require_local_target_for_execution and !match.matched) {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.ModuleRequiresLocalTarget}, "full module requires local target for execution");
                }
            }
            if (policy.reject_transcript_mismatch) {
                if (package.transcript_image) |image| {
                    if (image.world_surface_fingerprint != target_ref.world_surface_fingerprint or
                        image.target_certificate_fingerprint != target_ref.target_certificate_fingerprint)
                    {
                        return rejectedResult(request, package, target_ref, module_ref, match, &.{.TranscriptTargetMismatch}, "transcript image does not match target");
                    }
                }
            }
            if (mode == .inspect_only or mode == .local_target_match_only) {
                const report = Admission.AdmissionReport.accept(.{
                    .request = request,
                    .package_fingerprint = package.package_fingerprint,
                    .manifest_fingerprint = package.manifest.manifest_fingerprint,
                    .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                    .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                    .target_match_fingerprint = match.match_fingerprint,
                    .summary = if (mode == .inspect_only) "inspect-only admission accepted" else "local target match accepted",
                });
                const receipt = Admission.AdmissionReceipt.init(.{
                    .request = request,
                    .report = report,
                    .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                    .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                    .local_target_ref_fingerprint = match.local_target_ref_fingerprint,
                    .target_match_fingerprint = match.match_fingerprint,
                });
                return .{ .request = request, .report = report, .receipt = receipt, .target_match = match };
            }
            const cert = Env.certificate(admissionModeToRunMode(mode), transcript_available);
            if (policy.require_environment_preflight) {
                const env_report = Env.acceptanceReport(admissionModeToRunMode(mode), transcript_available);
                if (!env_report.accepted) {
                    const report = Admission.AdmissionReport.rejected(.{
                        .request = request,
                        .package_fingerprint = package.package_fingerprint,
                        .manifest_fingerprint = package.manifest.manifest_fingerprint,
                        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                        .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                        .target_match_fingerprint = match.match_fingerprint,
                        .import_set_fingerprint = ImportSet.fromTarget(Target).import_set_fingerprint,
                        .environment_acceptance_report_fingerprint = env_report.report_fingerprint,
                        .blockers = &.{.EnvironmentRejected},
                        .summary = "environment preflight rejected admission",
                    });
                    return .{ .request = request, .report = report, .target_match = match };
                }
            }
            if (policy.require_supervision_permit and args.permit == null) {
                return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitMissing}, "receiver permit is required");
            }
            if (args.permit) |permit| {
                if (permit.target_ref_fingerprint != local_target_ref.target_ref_fingerprint) {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitRejected}, "permit target mismatch");
                }
                if (permit.admission_receipt_fingerprint != null) {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitRejected}, "permit admission scope mismatch");
                }
                if (permit.module_ref_fingerprint) |permit_module_ref| {
                    if (module_ref == null or module_ref.?.module_ref_fingerprint != permit_module_ref) {
                        return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitRejected}, "permit module mismatch");
                    }
                }
                const permit_report = Env.acceptanceReportWithPermit(admissionModeToRunMode(mode), transcript_available, permit);
                if (!permit_report.accepted) {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitRejected}, "permit preflight rejected admission");
                }
            }
            if ((mode == .replay_only or mode == .verify_only) and package.run_image == null) {
                var transcript_image = package.transcript_image.?;
                validateTranscriptImageForEnvironment(Env, &transcript_image) catch {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.TranscriptImageInvalid}, "transcript image failed environment preflight");
                };
                transcript_image.validateReplayRun(target_ref.world_surface_fingerprint, target_ref.target_certificate_fingerprint) catch {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.TranscriptImageInvalid}, "transcript image failed replay preflight");
                };
                if (args.permit) |permit| {
                    var handoff_run_image = RunImage.fromTranscriptImage(Target, transcript_image, .replay_only_run);
                    attachPackageModuleWitnessToRunImage(&handoff_run_image, package, module_ref);
                    var transcript_handoff = Handoff{ .allocator = args.allocator, .run_image = handoff_run_image };
                    const handoff_report = transcript_handoff.preflightWithPermit(Target, Env, admissionModeToHandoffMode(mode).?, permit);
                    if (!handoff_report.accepted) {
                        return rejectedResult(request, package, target_ref, module_ref, match, &.{.PermitRejected}, "permit preflight rejected transcript-only admission");
                    }
                }
            }
            var handoff_preflight_report_fingerprint: ?u64 = null;
            if (admissionModeToHandoffMode(mode)) |handoff_mode| {
                if (package.run_image) |run_image| {
                    var handoff_run_image = run_image;
                    attachPackageModuleWitnessToRunImage(&handoff_run_image, package, module_ref);
                    if (handoff_run_image.transcript_image) |transcript_image| {
                        attachBorrowedTranscriptToRunImage(&handoff_run_image, transcript_image) catch {
                            return rejectedResult(request, package, target_ref, module_ref, match, &.{.RunImageInvalid}, "handoff transcript evidence rejected admission");
                        };
                    } else if (package.transcript_image) |transcript_image| {
                        attachBorrowedTranscriptToRunImage(&handoff_run_image, transcript_image) catch {
                            return rejectedResult(request, package, target_ref, module_ref, match, &.{.RunImageInvalid}, "handoff transcript evidence rejected admission");
                        };
                    }
                    var handoff = Handoff{ .allocator = args.allocator, .run_image = handoff_run_image };
                    const handoff_report = if (args.permit) |permit|
                        handoff.preflightWithPermitFreshTranscriptSink(Target, Env, handoff_mode, permit, fresh_transcript_sink_available)
                    else
                        handoff.preflightWithFreshTranscriptSink(Target, Env, handoff_mode, fresh_transcript_sink_available);
                    if (!handoff_report.accepted) {
                        return rejectedResult(request, package, target_ref, module_ref, match, handoffPreflightBlockers(args.permit != null), "handoff preflight rejected admission");
                    }
                    handoff_preflight_report_fingerprint = handoff_report.report_fingerprint;
                } else if (mode != .replay_only and mode != .verify_only) {
                    return rejectedResult(request, package, target_ref, module_ref, match, &.{.RunImageInvalid}, "run image is required for handoff admission");
                }
            }
            const report = Admission.AdmissionReport.accept(.{
                .request = request,
                .package_fingerprint = package.package_fingerprint,
                .manifest_fingerprint = package.manifest.manifest_fingerprint,
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                .target_match_fingerprint = match.match_fingerprint,
                .import_set_fingerprint = ImportSet.fromTarget(Target).import_set_fingerprint,
                .environment_acceptance_report_fingerprint = Env.acceptanceReport(admissionModeToRunMode(mode), transcript_available).report_fingerprint,
                .run_permit_fingerprint = if (args.permit) |permit| permit.permit_fingerprint else null,
                .handoff_preflight_report_fingerprint = handoff_preflight_report_fingerprint,
                .summary = "admission accepted for local execution",
            });
            var receipt = Admission.AdmissionReceipt.init(.{
                .request = request,
                .report = report,
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                .local_target_ref_fingerprint = local_target_ref.target_ref_fingerprint,
                .target_match_fingerprint = match.match_fingerprint,
                .environment_certificate_fingerprint = cert.certificate_fingerprint,
                .run_permit_fingerprint = if (args.permit) |permit| permit.permit_fingerprint else null,
            });
            var admitted_run_image: ?RunImage = null;
            var admitted_owns_run_image = false;
            if (package.run_image) |image| {
                if (package.owns_run_image) {
                    admitted_run_image = cloneRunImage(args.allocator, image) catch {
                        return rejectedResult(request, package, target_ref, module_ref, match, &.{.PackageInvalid}, "admitted run image ownership failed");
                    };
                    admitted_owns_run_image = true;
                } else {
                    admitted_run_image = image;
                }
                if (admitted_run_image) |*admitted_image| {
                    attachPackageModuleWitnessToRunImage(admitted_image, package, module_ref);
                }
            }
            var admitted_transcript_image: ?TranscriptImage = null;
            var admitted_owns_transcript_image = false;
            if (package.transcript_image) |image| {
                if (package.owns_transcript_image) {
                    admitted_transcript_image = cloneTranscriptImage(args.allocator, image) catch {
                        if (admitted_owns_run_image) if (admitted_run_image) |*owned| owned.deinit(args.allocator);
                        return rejectedResult(request, package, target_ref, module_ref, match, &.{.PackageInvalid}, "admitted transcript image ownership failed");
                    };
                    admitted_owns_transcript_image = true;
                } else {
                    admitted_transcript_image = image;
                }
            }
            var admitted = Admission.AdmittedRun.init(.{
                .admission_receipt_fingerprint = receipt.receipt_fingerprint,
                .target_ref = local_target_ref,
                .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                .import_set_fingerprint = ImportSet.fromTarget(Target).import_set_fingerprint,
                .environment_certificate_fingerprint = cert.certificate_fingerprint,
                .run_permit = args.permit,
                .run_image = admitted_run_image,
                .owns_run_image = admitted_owns_run_image,
                .transcript_image = admitted_transcript_image,
                .owns_transcript_image = admitted_owns_transcript_image,
                .selected_branch_id = args.requested_branch_id,
                .selected_checkpoint_ref = args.requested_checkpoint_ref,
                .mode = mode,
            });
            receipt.admitted_run_fingerprint = admitted.admitted_run_fingerprint;
            receipt.receipt_fingerprint = fingerprintAdmissionReceipt(receipt);
            admitted.admission_receipt_fingerprint = receipt.receipt_fingerprint;
            admitted.admission_receipt = receipt;
            return .{ .request = request, .report = report, .receipt = receipt, .admitted_run = admitted, .target_match = match };
        }

        fn rejectedResult(request: Admission.AdmissionRequest, package: Admission.TransferPackage, target_ref: ?TargetRef, module_ref: ?Admission.ModuleRef, match: ?Admission.TargetMatch, blockers: []const AdmissionBlocker, summary: []const u8) AdmissionResult {
            const report = Admission.AdmissionReport.rejected(.{
                .request = request,
                .package_fingerprint = package.package_fingerprint,
                .manifest_fingerprint = package.manifest.manifest_fingerprint,
                .target_ref_fingerprint = if (target_ref) |target| target.target_ref_fingerprint else null,
                .module_ref_fingerprint = if (module_ref) |module| module.module_ref_fingerprint else null,
                .target_match_fingerprint = if (match) |target_match| target_match.match_fingerprint else null,
                .blockers = blockers,
                .summary = summary,
            });
            return .{ .request = request, .report = report, .target_match = match };
        }
    };
};

pub const Supervision = struct {
    pub const ResponseClass = enum {
        responded,
        rejected,
        pending,
        failed,
    };

    pub const PermitBranchPolicy = enum {
        inherit,
        require_new_permit,
        deny,
    };

    pub const PermitHandoffPolicy = enum {
        allow,
        require_new_permit,
        deny,
    };

    pub const BudgetExceededBehavior = enum {
        fail,
        park,
        audit_only,
    };

    pub const AllowedAdapterKinds = packed struct(u8) {
        native: bool = false,
        replay: bool = false,
        verify: bool = false,
        byte: bool = false,
        null_reject: bool = false,
        pending_stub: bool = false,
        custom: bool = false,
        _padding: u1 = 0,

        pub const none = @This(){};
        pub const fresh_native = @This(){ .native = true };
        pub const replay_only = @This(){ .replay = true };
        pub const byte_only = @This(){ .byte = true };
        pub const all = @This(){
            .native = true,
            .replay = true,
            .verify = true,
            .byte = true,
            .null_reject = true,
            .pending_stub = true,
            .custom = true,
        };

        pub fn allows(self: @This(), kind: AdapterKind) bool {
            return switch (kind) {
                .native => self.native,
                .replay => self.replay,
                .verify => self.verify,
                .byte => self.byte,
                .null_reject => self.null_reject,
                .pending_stub => self.pending_stub,
                .custom => self.custom,
            };
        }
    };

    pub const AllowedModes = packed struct(u8) {
        fresh: bool = false,
        replay: bool = false,
        verify: bool = false,
        audit: bool = false,
        _padding: u4 = 0,

        pub const none = @This(){};
        pub const all = @This(){ .fresh = true, .replay = true, .verify = true, .audit = true };
        pub const fresh_only = @This(){ .fresh = true };
        pub const replay_only = @This(){ .replay = true };
        pub const verify_only = @This(){ .verify = true };

        pub fn allows(self: @This(), mode: Mode) bool {
            return switch (mode) {
                .fresh => self.fresh,
                .replay => self.replay,
                .verify => self.verify,
                .audit => self.audit,
            };
        }
    };

    pub const AllowedAuthorityKinds = packed struct(u16) {
        fixture: bool = false,
        replay_source: bool = false,
        native_function: bool = false,
        byte_adapter: bool = false,
        model_like: bool = false,
        tool_like: bool = false,
        file_like: bool = false,
        human_like: bool = false,
        custom: bool = false,
        _padding: u7 = 0,

        pub const none = @This(){};
        pub const fixtures = @This(){ .fixture = true };
        pub const native = @This(){ .native_function = true };
        pub const replay = @This(){ .replay_source = true };
        pub const all = @This(){
            .fixture = true,
            .replay_source = true,
            .native_function = true,
            .byte_adapter = true,
            .model_like = true,
            .tool_like = true,
            .file_like = true,
            .human_like = true,
            .custom = true,
        };

        pub fn allows(self: @This(), kind: PortAuthority.Kind) bool {
            return switch (kind) {
                .fixture => self.fixture,
                .replay_source => self.replay_source,
                .native_function => self.native_function,
                .byte_adapter => self.byte_adapter,
                .model_like => self.model_like,
                .tool_like => self.tool_like,
                .file_like => self.file_like,
                .human_like => self.human_like,
                .custom => self.custom,
            };
        }
    };

    pub const Blocker = enum {
        none,
        budget_exceeded,
        port_rule_denied,
        adapter_kind_denied,
        authority_denied,
        portable_value_required,
        native_value_rejected,
        fresh_call_denied,
        replay_call_denied,
        verify_call_denied,
        pending_denied,
        rejected_denied,
        failed_denied,
        branch_denied,
        checkpoint_denied,
        handoff_denied,
        transcript_image_required,
        environment_certificate_required,
        max_supervision_events_exceeded,
    };

    pub const BudgetExceededKind = enum {
        session_steps,
        port_requests,
        port_responses,
        fresh_calls,
        replay_calls,
        verify_calls,
        failed_calls,
        rejected_calls,
        pending_calls,
        frame_request_bytes,
        frame_response_bytes,
        value_image_bytes,
        transcript_events,
        transcript_image_bytes,
        checkpoints,
        branches,
        branch_depth,
        handoff_exports,
        handoff_accepts,
        total_cost_units,
        per_port_requests,
        per_port_fresh_calls,
        per_port_replay_calls,
        per_port_response_bytes,
        per_port_value_image_bytes,
        per_port_cost_units,
        supervision_events,
    };

    pub const SupervisionPolicy = struct {
        policy_fingerprint: u64 = 0,
        allow_fresh_calls: bool = false,
        allow_replay_calls: bool = false,
        allow_verify_calls: bool = false,
        allow_audit_only: bool = false,
        allow_native_adapters: bool = false,
        allow_byte_adapters: bool = false,
        allow_replay_adapters: bool = false,
        allow_pending_responses: bool = false,
        allow_rejected_responses: bool = false,
        allow_failed_responses: bool = false,
        allow_branching: bool = false,
        allow_checkpoints: bool = false,
        allow_handoff_export: bool = false,
        allow_handoff_accept: bool = false,
        require_portable_value_images: bool = false,
        reject_native_only_values: bool = false,
        require_environment_certificate: bool = true,
        require_transcript_image_for_replay: bool = true,
        fail_on_budget_exceeded: bool = true,
        park_on_budget_exceeded: bool = false,
        audit_only_on_budget_exceeded: bool = false,
        max_supervision_events: ?usize = null,

        pub fn init(args: anytype) @This() {
            const Args = @TypeOf(args);
            var result = @This(){};
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "policy_fingerprint")) continue;
                if (comptime @hasField(Args, field.name)) {
                    @field(result, field.name) = @field(args, field.name);
                }
            }
            result.policy_fingerprint = fingerprintSupervisionPolicy(result);
            return result;
        }

        pub fn withFingerprint(self: @This()) @This() {
            var result = self;
            result.policy_fingerprint = 0;
            result.policy_fingerprint = fingerprintSupervisionPolicy(result);
            return result;
        }

        pub fn budgetBehavior(self: @This()) BudgetExceededBehavior {
            if (self.park_on_budget_exceeded) return .park;
            if (self.audit_only_on_budget_exceeded) return .audit_only;
            return .fail;
        }

        pub const strict_fresh = init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = true,
            .allow_checkpoints = true,
            .require_environment_certificate = true,
            .fail_on_budget_exceeded = true,
        });
        pub const strict_replay = init(.{
            .allow_replay_calls = true,
            .allow_replay_adapters = true,
            .require_portable_value_images = true,
            .reject_native_only_values = true,
            .require_environment_certificate = true,
            .require_transcript_image_for_replay = true,
        });
        pub const verify_replay = init(.{
            .allow_fresh_calls = true,
            .allow_replay_calls = true,
            .allow_verify_calls = true,
            .allow_native_adapters = true,
            .allow_replay_adapters = true,
            .require_portable_value_images = true,
            .reject_native_only_values = true,
            .require_environment_certificate = true,
            .require_transcript_image_for_replay = true,
        });
        pub const agent_fixture = init(.{
            .allow_fresh_calls = true,
            .allow_replay_calls = true,
            .allow_verify_calls = true,
            .allow_native_adapters = true,
            .allow_replay_adapters = true,
            .allow_pending_responses = false,
            .allow_rejected_responses = false,
            .allow_failed_responses = false,
            .allow_branching = true,
            .allow_checkpoints = true,
            .allow_handoff_export = true,
            .allow_handoff_accept = true,
            .require_environment_certificate = true,
        });
        pub const audit_only = init(.{
            .allow_audit_only = true,
            .allow_fresh_calls = true,
            .allow_replay_calls = true,
            .allow_verify_calls = true,
            .allow_native_adapters = true,
            .allow_byte_adapters = true,
            .allow_replay_adapters = true,
            .allow_pending_responses = true,
            .allow_rejected_responses = true,
            .allow_failed_responses = true,
            .allow_branching = true,
            .allow_checkpoints = true,
            .allow_handoff_export = true,
            .allow_handoff_accept = true,
            .require_environment_certificate = false,
            .fail_on_budget_exceeded = false,
            .audit_only_on_budget_exceeded = true,
        });
        pub const handoff_receiver = init(.{
            .allow_fresh_calls = true,
            .allow_replay_calls = true,
            .allow_verify_calls = true,
            .allow_native_adapters = true,
            .allow_replay_adapters = true,
            .allow_handoff_accept = true,
            .require_environment_certificate = true,
            .require_transcript_image_for_replay = true,
        });
        pub const branch_limited = init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = true,
            .allow_branching = true,
            .allow_checkpoints = true,
            .require_environment_certificate = true,
        });
    };

    pub const PerPortBudget = struct {
        world_port_id: u32,
        max_requests: ?usize = null,
        max_fresh_calls: ?usize = null,
        max_replay_calls: ?usize = null,
        max_response_bytes: ?usize = null,
        max_value_image_bytes: ?usize = null,
        max_cost_units: ?u64 = null,
    };

    pub const Budget = struct {
        budget_fingerprint: u64 = 0,
        max_session_steps: ?usize = null,
        max_port_requests: ?usize = null,
        max_port_responses: ?usize = null,
        max_fresh_calls: ?usize = null,
        max_replay_calls: ?usize = null,
        max_verify_calls: ?usize = null,
        max_failed_calls: ?usize = null,
        max_rejected_calls: ?usize = null,
        max_pending_calls: ?usize = null,
        max_frame_request_bytes: ?usize = null,
        max_frame_response_bytes: ?usize = null,
        max_value_image_bytes: ?usize = null,
        max_transcript_events: ?usize = null,
        max_transcript_image_bytes: ?usize = null,
        max_checkpoints: ?usize = null,
        max_branches: ?usize = null,
        max_branch_depth: ?usize = null,
        max_handoff_exports: ?usize = null,
        max_handoff_accepts: ?usize = null,
        max_total_cost_units: ?u64 = null,
        per_port_budgets: []const PerPortBudget = &.{},

        pub fn init(args: anytype) @This() {
            const Args = @TypeOf(args);
            var result = @This(){};
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "budget_fingerprint")) continue;
                if (comptime @hasField(Args, field.name)) {
                    @field(result, field.name) = @field(args, field.name);
                }
            }
            result.budget_fingerprint = fingerprintBudget(result);
            return result;
        }

        pub fn withFingerprint(self: @This()) @This() {
            var result = self;
            result.budget_fingerprint = 0;
            result.budget_fingerprint = fingerprintBudget(result);
            return result;
        }

        pub fn perPort(self: @This(), world_port_id: u32) ?PerPortBudget {
            for (self.per_port_budgets) |budget| {
                if (budget.world_port_id == world_port_id) return budget;
            }
            return null;
        }

        pub const unlimited = init(.{});
    };

    pub const PerPortCost = struct {
        world_port_id: u32,
        port_request_base_cost: ?u64 = null,
        port_response_base_cost: ?u64 = null,
        fresh_call_cost: ?u64 = null,
        replay_call_cost: ?u64 = null,
        verify_call_cost: ?u64 = null,
        failed_call_cost: ?u64 = null,
        rejected_call_cost: ?u64 = null,
        pending_call_cost: ?u64 = null,
        frame_byte_cost: ?u64 = null,
        value_image_byte_cost: ?u64 = null,
    };

    pub const CostModel = struct {
        cost_model_fingerprint: u64 = 0,
        session_step_cost: u64 = 1,
        port_request_base_cost: u64 = 1,
        port_response_base_cost: u64 = 1,
        fresh_call_cost: u64 = 1,
        replay_call_cost: u64 = 1,
        verify_call_cost: u64 = 1,
        failed_call_cost: u64 = 1,
        rejected_call_cost: u64 = 1,
        pending_call_cost: u64 = 1,
        frame_byte_cost: u64 = 0,
        value_image_byte_cost: u64 = 0,
        checkpoint_cost: u64 = 1,
        branch_cost: u64 = 1,
        handoff_export_cost: u64 = 1,
        handoff_accept_cost: u64 = 1,
        per_port_costs: []const PerPortCost = &.{},

        pub fn init(args: anytype) @This() {
            const Args = @TypeOf(args);
            var result = @This(){};
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "cost_model_fingerprint")) continue;
                if (comptime @hasField(Args, field.name)) {
                    @field(result, field.name) = @field(args, field.name);
                }
            }
            result.cost_model_fingerprint = fingerprintCostModel(result);
            return result;
        }

        pub fn withFingerprint(self: @This()) @This() {
            var result = self;
            result.cost_model_fingerprint = 0;
            result.cost_model_fingerprint = fingerprintCostModel(result);
            return result;
        }

        pub fn perPort(self: @This(), world_port_id: u32) ?PerPortCost {
            for (self.per_port_costs) |cost| {
                if (cost.world_port_id == world_port_id) return cost;
            }
            return null;
        }

        pub fn requestCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.port_request_base_cost) |override| return override;
            }
            return self.port_request_base_cost;
        }

        pub fn responseCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.port_response_base_cost) |override| return override;
            }
            return self.port_response_base_cost;
        }

        pub fn freshCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.fresh_call_cost) |override| return override;
            }
            return self.fresh_call_cost;
        }

        pub fn replayCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.replay_call_cost) |override| return override;
            }
            return self.replay_call_cost;
        }

        pub fn verifyCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.verify_call_cost) |override| return override;
            }
            return self.verify_call_cost;
        }

        pub fn failedCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.failed_call_cost) |override| return override;
            }
            return self.failed_call_cost;
        }

        pub fn rejectedCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.rejected_call_cost) |override| return override;
            }
            return self.rejected_call_cost;
        }

        pub fn pendingCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.pending_call_cost) |override| return override;
            }
            return self.pending_call_cost;
        }

        pub fn frameByteCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.frame_byte_cost) |override| return override;
            }
            return self.frame_byte_cost;
        }

        pub fn valueImageByteCost(self: @This(), world_port_id: u32) u64 {
            if (self.perPort(world_port_id)) |cost| {
                if (cost.value_image_byte_cost) |override| return override;
            }
            return self.value_image_byte_cost;
        }

        pub const default = init(.{});
    };

    pub const PortRule = struct {
        rule_fingerprint: u64 = 0,
        world_surface_fingerprint: u64,
        world_port_id: u32,
        allowed_adapter_kinds: AllowedAdapterKinds = .all,
        allowed_authority_kinds: AllowedAuthorityKinds = .all,
        allowed_modes: AllowedModes = .all,
        allow_fresh: bool = true,
        allow_replay: bool = true,
        allow_verify: bool = true,
        allow_pending: bool = false,
        allow_reject: bool = false,
        allow_fail: bool = false,
        require_portable_values: bool = false,
        max_payload_image_bytes: ?usize = null,
        max_response_image_bytes: ?usize = null,
        max_requests: ?usize = null,
        max_cost_units: ?u64 = null,

        pub fn init(args: anytype) @This() {
            const Args = @TypeOf(args);
            var result = @This(){
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .world_port_id = args.world_port_id,
            };
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "rule_fingerprint")) continue;
                if (comptime std.mem.eql(u8, field.name, "world_surface_fingerprint")) continue;
                if (comptime std.mem.eql(u8, field.name, "world_port_id")) continue;
                if (comptime @hasField(Args, field.name)) {
                    @field(result, field.name) = @field(args, field.name);
                }
            }
            result.rule_fingerprint = fingerprintPortRule(result);
            return result;
        }

        pub fn permitsMode(self: @This(), mode: Mode) bool {
            if (!self.allowed_modes.allows(mode)) return false;
            return switch (mode) {
                .fresh => self.allow_fresh,
                .audit => true,
                .replay => self.allow_replay,
                .verify => self.allow_verify,
            };
        }
    };

    pub const RunPermit = struct {
        format_version: u32 = world_run_permit_format_version,
        fingerprint_version: u32 = world_run_permit_fingerprint_version,
        permit_fingerprint: u64 = 0,
        target_ref_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        environment_certificate_fingerprint: u64,
        binding_plan_fingerprint: u64,
        mode: Mode,
        transcript_image_available: bool = false,
        admission_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        supervision_policy_fingerprint: u64,
        budget_fingerprint: u64,
        cost_model_fingerprint: u64,
        branch_policy: PermitBranchPolicy = .inherit,
        handoff_policy: PermitHandoffPolicy = .require_new_permit,
        metadata: []const u8 = "",
        label: []const u8 = "",
        policy: Supervision.SupervisionPolicy,
        budget: Supervision.Budget,
        cost_model: Supervision.CostModel,
        port_rules: []const Supervision.PortRule = &.{},

        pub fn init(args: struct {
            target_ref_fingerprint: u64,
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            environment_certificate_fingerprint: u64,
            binding_plan_fingerprint: u64,
            mode: Mode,
            transcript_image_available: bool = false,
            admission_receipt_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            policy: Supervision.SupervisionPolicy = Supervision.SupervisionPolicy.strict_fresh,
            budget: Supervision.Budget = Supervision.Budget.unlimited,
            cost_model: Supervision.CostModel = Supervision.CostModel.default,
            branch_policy: PermitBranchPolicy = .inherit,
            handoff_policy: PermitHandoffPolicy = .require_new_permit,
            metadata: []const u8 = "",
            label: []const u8 = "",
            port_rules: []const Supervision.PortRule = &.{},
        }) @This() {
            const policy = args.policy.withFingerprint();
            const budget = args.budget.withFingerprint();
            const cost_model = args.cost_model.withFingerprint();
            var result = @This(){
                .permit_fingerprint = 0,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .binding_plan_fingerprint = args.binding_plan_fingerprint,
                .mode = args.mode,
                .transcript_image_available = args.transcript_image_available,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .supervision_policy_fingerprint = policy.policy_fingerprint,
                .budget_fingerprint = budget.budget_fingerprint,
                .cost_model_fingerprint = cost_model.cost_model_fingerprint,
                .branch_policy = args.branch_policy,
                .handoff_policy = args.handoff_policy,
                .metadata = args.metadata,
                .label = args.label,
                .policy = policy,
                .budget = budget,
                .cost_model = cost_model,
                .port_rules = args.port_rules,
            };
            result.permit_fingerprint = fingerprintRunPermit(result);
            return result;
        }

        pub fn ruleFor(self: @This(), world_port_id: u32) ?Supervision.PortRule {
            for (self.port_rules) |rule| {
                if (rule.world_port_id == world_port_id) return rule;
            }
            return null;
        }
    };

    pub fn issue(comptime Target: type, comptime Env: type, args: anytype) Supervision.RunPermit {
        comptime validateTarget(Target);
        const Args = @TypeOf(args);
        const mode: Mode = if (@hasField(Args, "mode")) args.mode else .fresh;
        const transcript_available: bool = if (@hasField(Args, "transcript_image_available")) args.transcript_image_available else false;
        const cert = Env.certificate(mode, transcript_available);
        const policy: Supervision.SupervisionPolicy = if (@hasField(Args, "policy")) args.policy else Supervision.SupervisionPolicy.strict_fresh;
        const budget: Supervision.Budget = if (@hasField(Args, "budget")) args.budget else Supervision.Budget.unlimited;
        const cost_model: Supervision.CostModel = if (@hasField(Args, "cost_model")) args.cost_model else Supervision.CostModel.default;
        const branch_policy: PermitBranchPolicy = if (@hasField(Args, "branch_policy")) args.branch_policy else .inherit;
        const handoff_policy: PermitHandoffPolicy = if (@hasField(Args, "handoff_policy")) args.handoff_policy else .require_new_permit;
        const admission_receipt_fingerprint: ?u64 = if (@hasField(Args, "admission_receipt_fingerprint")) args.admission_receipt_fingerprint else null;
        const module_ref_fingerprint: ?u64 = if (@hasField(Args, "module_ref_fingerprint")) args.module_ref_fingerprint else null;
        const metadata: []const u8 = if (@hasField(Args, "metadata")) args.metadata else "";
        const label: []const u8 = if (@hasField(Args, "label")) args.label else "";
        const port_rules: []const Supervision.PortRule = if (@hasField(Args, "port_rules")) args.port_rules else &.{};
        return Supervision.RunPermit.init(.{
            .target_ref_fingerprint = TargetRef.fromTarget(Target).target_ref_fingerprint,
            .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
            .environment_certificate_fingerprint = cert.certificate_fingerprint,
            .binding_plan_fingerprint = cert.binding_plan_fingerprint,
            .mode = mode,
            .transcript_image_available = transcript_available,
            .admission_receipt_fingerprint = admission_receipt_fingerprint,
            .module_ref_fingerprint = module_ref_fingerprint,
            .policy = policy,
            .budget = budget,
            .cost_model = cost_model,
            .branch_policy = branch_policy,
            .handoff_policy = handoff_policy,
            .metadata = metadata,
            .label = label,
            .port_rules = port_rules,
        });
    }

    pub const PerPortUsage = struct {
        world_port_id: u32,
        requests: usize = 0,
        responses: usize = 0,
        fresh_calls: usize = 0,
        replay_calls: usize = 0,
        verify_calls: usize = 0,
        failed_calls: usize = 0,
        rejected_calls: usize = 0,
        pending_calls: usize = 0,
        response_bytes: usize = 0,
        value_image_bytes: usize = 0,
        cost_units: u64 = 0,
    };

    pub const UsageLedger = struct {
        ledger_fingerprint: u64 = 0,
        run_permit_fingerprint: u64,
        target_ref_fingerprint: u64,
        environment_certificate_fingerprint: u64,
        total_session_steps: usize = 0,
        total_port_requests: usize = 0,
        total_port_responses: usize = 0,
        total_fresh_calls: usize = 0,
        total_replay_calls: usize = 0,
        total_verify_calls: usize = 0,
        total_failed_calls: usize = 0,
        total_rejected_calls: usize = 0,
        total_pending_calls: usize = 0,
        total_frame_request_bytes: usize = 0,
        total_frame_response_bytes: usize = 0,
        total_value_image_bytes: usize = 0,
        total_transcript_events: usize = 0,
        total_transcript_image_bytes: usize = 0,
        total_checkpoints: usize = 0,
        total_branches: usize = 0,
        total_handoff_exports: usize = 0,
        total_handoff_accepts: usize = 0,
        total_cost_units: u64 = 0,
        per_port_usage: []PerPortUsage = &.{},
        exceeded_budget: ?BudgetExceededKind = null,

        pub fn init(allocator: std.mem.Allocator, permit: Supervision.RunPermit, port_count: usize) !@This() {
            const per_port = try allocator.alloc(PerPortUsage, port_count);
            for (per_port, 0..) |*usage, index| usage.* = .{ .world_port_id = @intCast(index) };
            var result = @This(){
                .run_permit_fingerprint = permit.permit_fingerprint,
                .target_ref_fingerprint = permit.target_ref_fingerprint,
                .environment_certificate_fingerprint = permit.environment_certificate_fingerprint,
                .per_port_usage = per_port,
            };
            result.refreshFingerprint();
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.per_port_usage);
            self.per_port_usage = &.{};
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            var result = self;
            result.per_port_usage = try allocator.dupe(PerPortUsage, self.per_port_usage);
            return result;
        }

        pub fn refreshFingerprint(self: *@This()) void {
            self.ledger_fingerprint = 0;
            self.ledger_fingerprint = fingerprintUsageLedger(self.*);
        }

        pub fn perPort(self: *@This(), world_port_id: u32) *PerPortUsage {
            return &self.per_port_usage[world_port_id];
        }
    };

    pub const SupervisionCheck = struct {
        check_fingerprint: u64 = 0,
        run_permit_fingerprint: u64,
        event_kind: Supervision.SupervisionCheck.EventKind,
        world_port_id: ?u32 = null,
        usage_before_fingerprint: u64,
        usage_after_fingerprint: u64,
        allowed: bool,
        blocker: ?Blocker = null,
        budget_exceeded: ?BudgetExceededKind = null,
        rule_fingerprint: ?u64 = null,
        budget_fingerprint: ?u64 = null,
        summary: []const u8 = "",

        pub const EventKind = enum {
            before_session_step,
            after_session_step,
            before_port_request,
            before_adapter_call,
            after_adapter_response,
            before_resume,
            before_transcript_append,
            before_checkpoint,
            before_branch,
            before_handoff_export,
            before_handoff_accept,
        };

        pub fn init(args: struct {
            run_permit_fingerprint: u64,
            event_kind: Supervision.SupervisionCheck.EventKind,
            world_port_id: ?u32 = null,
            usage_before_fingerprint: u64,
            usage_after_fingerprint: u64,
            allowed: bool,
            blocker: ?Blocker = null,
            budget_exceeded: ?BudgetExceededKind = null,
            rule_fingerprint: ?u64 = null,
            budget_fingerprint: ?u64 = null,
            summary: []const u8 = "",
        }) @This() {
            var result = @This(){
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .event_kind = args.event_kind,
                .world_port_id = args.world_port_id,
                .usage_before_fingerprint = args.usage_before_fingerprint,
                .usage_after_fingerprint = args.usage_after_fingerprint,
                .allowed = args.allowed,
                .blocker = args.blocker,
                .budget_exceeded = args.budget_exceeded,
                .rule_fingerprint = args.rule_fingerprint,
                .budget_fingerprint = args.budget_fingerprint,
                .summary = args.summary,
            };
            result.check_fingerprint = fingerprintSupervisionCheck(result);
            return result;
        }

        pub fn validateFingerprint(self: @This()) bool {
            return self.check_fingerprint == fingerprintSupervisionCheck(self);
        }
    };

    pub const RunReceipt = struct {
        format_version: u32 = world_run_receipt_format_version,
        fingerprint_version: u32 = world_run_receipt_fingerprint_version,
        receipt_fingerprint: u64 = 0,
        run_permit_fingerprint: u64,
        environment_certificate_fingerprint: u64,
        target_ref_fingerprint: u64,
        run_image_fingerprint: ?u64 = null,
        transcript_image_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        usage_ledger_fingerprint: u64,
        final_run_state_fingerprint: u64,
        final_status: FinalStatus,
        exceeded_budget: ?BudgetExceededKind = null,
        blocker: ?Blocker = null,
        warning_count: usize = 0,
        total_session_steps: usize = 0,
        total_port_requests: usize = 0,
        total_port_responses: usize = 0,
        total_cost_units: u64 = 0,
        branch_count: usize = 0,
        checkpoint_count: usize = 0,
        handoff_export_count: usize = 0,
        handoff_accept_count: usize = 0,

        pub const FinalStatus = enum {
            completed,
            failed,
            parked,
            interrupted,
            rejected,
        };

        pub fn init(args: struct {
            run_permit_fingerprint: u64,
            environment_certificate_fingerprint: u64,
            target_ref_fingerprint: u64,
            run_image_fingerprint: ?u64 = null,
            transcript_image_fingerprint: ?u64 = null,
            admission_receipt_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            usage_ledger_fingerprint: u64,
            final_run_state_fingerprint: u64,
            final_status: FinalStatus,
            exceeded_budget: ?BudgetExceededKind = null,
            blocker: ?Blocker = null,
            warning_count: usize = 0,
            ledger: ?Supervision.UsageLedger = null,
        }) @This() {
            var result = @This(){
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .run_image_fingerprint = args.run_image_fingerprint,
                .transcript_image_fingerprint = args.transcript_image_fingerprint,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .usage_ledger_fingerprint = args.usage_ledger_fingerprint,
                .final_run_state_fingerprint = args.final_run_state_fingerprint,
                .final_status = args.final_status,
                .exceeded_budget = args.exceeded_budget,
                .blocker = args.blocker,
                .warning_count = args.warning_count,
            };
            if (args.ledger) |ledger| {
                result.total_session_steps = ledger.total_session_steps;
                result.total_port_requests = ledger.total_port_requests;
                result.total_port_responses = ledger.total_port_responses;
                result.total_cost_units = ledger.total_cost_units;
                result.branch_count = ledger.total_branches;
                result.checkpoint_count = ledger.total_checkpoints;
                result.handoff_export_count = ledger.total_handoff_exports;
                result.handoff_accept_count = ledger.total_handoff_accepts;
            }
            result.receipt_fingerprint = fingerprintRunReceipt(result);
            return result;
        }
    };

    pub const Supervisor = struct {
        allocator: std.mem.Allocator,
        permit: Supervision.RunPermit,
        ledger: Supervision.UsageLedger,
        last_check: ?Supervision.SupervisionCheck = null,
        warning_count: usize = 0,
        supervision_event_count: usize = 0,
        interrupted: bool = false,
        blocker: ?Blocker = null,

        const SupervisionEventReservation = enum {
            recorded,
            audit_only_exceeded,
        };

        pub fn init(allocator: std.mem.Allocator, permit: Supervision.RunPermit, port_count: usize) !@This() {
            try validatePermitForRun(permit, port_count);
            const ledger = try Supervision.UsageLedger.init(allocator, permit, port_count);
            return .{
                .allocator = allocator,
                .permit = permit,
                .ledger = ledger,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.ledger.deinit(self.allocator);
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            const ledger = try self.ledger.clone(allocator);
            return .{
                .allocator = allocator,
                .permit = self.permit,
                .ledger = ledger,
                .last_check = self.last_check,
                .warning_count = self.warning_count,
                .supervision_event_count = self.supervision_event_count,
                .interrupted = self.interrupted,
                .blocker = self.blocker,
            };
        }

        pub fn validatePermitForRun(permit: Supervision.RunPermit, port_count: usize) !void {
            if (!modeAllowedByPolicy(permit.policy, permit.mode)) return Error.SupervisionDenied;
            const policy = permit.policy.withFingerprint();
            if (permit.policy.policy_fingerprint != policy.policy_fingerprint) return Error.SupervisionDenied;
            if (permit.supervision_policy_fingerprint != policy.policy_fingerprint) return Error.SupervisionDenied;
            const budget = permit.budget.withFingerprint();
            if (permit.budget.budget_fingerprint != budget.budget_fingerprint) return Error.SupervisionDenied;
            if (permit.budget_fingerprint != budget.budget_fingerprint) return Error.SupervisionDenied;
            const cost_model = permit.cost_model.withFingerprint();
            if (permit.cost_model.cost_model_fingerprint != cost_model.cost_model_fingerprint) return Error.SupervisionDenied;
            if (permit.cost_model_fingerprint != cost_model.cost_model_fingerprint) return Error.SupervisionDenied;
            for (permit.budget.per_port_budgets, 0..) |per_port_budget, index| {
                if (per_port_budget.world_port_id >= port_count) return Error.SupervisionDenied;
                for (permit.budget.per_port_budgets[0..index]) |previous| {
                    if (previous.world_port_id == per_port_budget.world_port_id) return Error.SupervisionDenied;
                }
            }
            for (permit.cost_model.per_port_costs, 0..) |per_port_cost, index| {
                if (per_port_cost.world_port_id >= port_count) return Error.SupervisionDenied;
                for (permit.cost_model.per_port_costs[0..index]) |previous| {
                    if (previous.world_port_id == per_port_cost.world_port_id) return Error.SupervisionDenied;
                }
            }
            for (permit.port_rules, 0..) |rule, index| {
                if (rule.world_surface_fingerprint != permit.world_surface_fingerprint) return Error.SupervisionDenied;
                if (rule.world_port_id >= port_count) return Error.SupervisionDenied;
                if (rule.rule_fingerprint != fingerprintPortRule(rule)) return Error.SupervisionDenied;
                for (permit.port_rules[0..index]) |previous| {
                    if (previous.world_port_id == rule.world_port_id) return Error.SupervisionDenied;
                }
            }
            if (permit.permit_fingerprint != fingerprintRunPermit(permit)) return Error.SupervisionDenied;
            if (permit.policy.require_environment_certificate and permit.environment_certificate_fingerprint == 0) return Error.SupervisionDenied;
            if (permit.policy.require_transcript_image_for_replay and modeConsumesTranscript(permit.mode) and !permit.transcript_image_available) return Error.TranscriptImageRequired;
        }

        fn validateWorldPortId(self: *@This(), world_port_id: u32) !void {
            if (world_port_id >= self.ledger.per_port_usage.len) return Error.SupervisionDenied;
        }

        fn addSatUsize(a: usize, b: usize) usize {
            return a +| b;
        }

        fn addSatU64(a: u64, b: u64) u64 {
            return a +| b;
        }

        fn addSatU64Many(values: []const u64) u64 {
            var total: u64 = 0;
            for (values) |value| total = addSatU64(total, value);
            return total;
        }

        fn mulSatUsizeU64(a: usize, b: u64) u64 {
            const narrowed = std.math.cast(u64, a) orelse std.math.maxInt(u64);
            return narrowed *| b;
        }

        pub fn beforeSessionStep(self: *@This()) !void {
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_session_steps = addSatUsize(next.total_session_steps, 1);
            next.total_cost_units = addSatU64(next.total_cost_units, self.permit.cost_model.session_step_cost);
            try self.commitCheck(.before_session_step, null, &next, null, null, "session step");
        }

        pub fn beforePortRequest(self: *@This(), world_port_id: u32, request_bytes: usize, value_image_bytes: usize) !void {
            try self.validateWorldPortId(world_port_id);
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            const request_cost = self.permit.cost_model.requestCost(world_port_id);
            const request_byte_cost = mulSatUsizeU64(request_bytes, self.permit.cost_model.frameByteCost(world_port_id));
            const value_image_cost = mulSatUsizeU64(value_image_bytes, self.permit.cost_model.valueImageByteCost(world_port_id));
            const current_usage = next.per_port_usage[world_port_id];
            const cost_delta = addSatU64Many(&.{ request_cost, request_byte_cost, value_image_cost });
            const next_requests = addSatUsize(current_usage.requests, 1);
            const next_value_image_bytes = addSatUsize(current_usage.value_image_bytes, value_image_bytes);
            const next_cost_units = addSatU64(current_usage.cost_units, cost_delta);
            const rule = self.permit.ruleFor(world_port_id);
            if (rule) |port_rule| {
                if (port_rule.max_payload_image_bytes) |max| {
                    if (value_image_bytes > max) return self.deny(.before_port_request, world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule payload image cap");
                }
                if (port_rule.max_requests) |max| {
                    if (next_requests > max) return self.deny(.before_port_request, world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule request cap");
                }
                if (port_rule.max_cost_units) |max| {
                    if (next_cost_units > max) return self.deny(.before_port_request, world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule cost cap");
                }
            }
            next.total_port_requests = addSatUsize(next.total_port_requests, 1);
            next.total_frame_request_bytes = addSatUsize(next.total_frame_request_bytes, request_bytes);
            next.total_value_image_bytes = addSatUsize(next.total_value_image_bytes, value_image_bytes);
            next.total_cost_units = addSatU64(next.total_cost_units, cost_delta);
            const usage = &next.per_port_usage[world_port_id];
            usage.requests = next_requests;
            usage.value_image_bytes = next_value_image_bytes;
            usage.cost_units = next_cost_units;
            try self.commitCheck(.before_port_request, world_port_id, &next, null, rule, "port request");
        }

        pub fn accountPortRequestBytes(self: *@This(), world_port_id: u32, request_bytes: usize, value_image_bytes: usize) !void {
            try self.validateWorldPortId(world_port_id);
            if (request_bytes == 0 and value_image_bytes == 0) return;
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            const request_byte_cost = mulSatUsizeU64(request_bytes, self.permit.cost_model.frameByteCost(world_port_id));
            const value_image_cost = mulSatUsizeU64(value_image_bytes, self.permit.cost_model.valueImageByteCost(world_port_id));
            const cost_delta = addSatU64(request_byte_cost, value_image_cost);
            const current_usage = next.per_port_usage[world_port_id];
            const next_value_image_bytes = addSatUsize(current_usage.value_image_bytes, value_image_bytes);
            const next_cost_units = addSatU64(current_usage.cost_units, cost_delta);
            const rule = self.permit.ruleFor(world_port_id);
            if (rule) |port_rule| {
                if (port_rule.max_payload_image_bytes) |max| {
                    if (value_image_bytes > max) return self.deny(.before_port_request, world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule payload image cap");
                }
                if (port_rule.max_cost_units) |max| {
                    if (next_cost_units > max) return self.deny(.before_port_request, world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule cost cap");
                }
            }
            next.total_frame_request_bytes = addSatUsize(next.total_frame_request_bytes, request_bytes);
            next.total_value_image_bytes = addSatUsize(next.total_value_image_bytes, value_image_bytes);
            next.total_cost_units = addSatU64(next.total_cost_units, cost_delta);
            const usage = &next.per_port_usage[world_port_id];
            usage.value_image_bytes = next_value_image_bytes;
            usage.cost_units = next_cost_units;
            try self.commitCheck(.before_port_request, world_port_id, &next, null, rule, "port request bytes");
        }

        pub fn needsPortRequestByteAccounting(self: *@This(), world_port_id: u32) !bool {
            try self.validateWorldPortId(world_port_id);
            if (self.permit.budget.max_frame_request_bytes != null) return true;
            if (self.permit.budget.max_value_image_bytes != null) return true;
            if (self.permit.budget.perPort(world_port_id)) |budget| {
                if (budget.max_value_image_bytes != null) return true;
                if (budget.max_cost_units != null and
                    (self.permit.cost_model.frameByteCost(world_port_id) != 0 or self.permit.cost_model.valueImageByteCost(world_port_id) != 0)) return true;
            }
            if (self.permit.cost_model.frameByteCost(world_port_id) != 0) return true;
            if (self.permit.cost_model.valueImageByteCost(world_port_id) != 0) return true;
            if (self.permit.ruleFor(world_port_id)) |rule| {
                if (rule.max_payload_image_bytes != null) return true;
                if (rule.max_cost_units != null and self.permit.cost_model.valueImageByteCost(world_port_id) != 0) return true;
            }
            return false;
        }

        pub fn beforeAdapterCall(self: *@This(), args: struct {
            world_port_id: u32,
            mode: Mode,
            accounting_mode: ?Mode = null,
            adapter_kind: AdapterKind,
            authority_kind: ?PortAuthority.Kind = null,
            value_policy: ValuePolicy = .native_compatible,
        }) !void {
            try self.validateWorldPortId(args.world_port_id);
            const policy = self.permit.policy;
            if (!modeAllowedByPolicy(policy, args.mode)) {
                const blocker: Supervision.Blocker = switch (args.mode) {
                    .fresh, .audit => .fresh_call_denied,
                    .replay => .replay_call_denied,
                    .verify => .verify_call_denied,
                };
                return self.deny(.before_adapter_call, args.world_port_id, blocker, null, "mode denied");
            }
            if (!adapterAllowedByPolicy(policy, args.adapter_kind)) return self.deny(.before_adapter_call, args.world_port_id, .adapter_kind_denied, null, "adapter denied");
            if (args.value_policy.require_portable_values == false and policy.require_portable_value_images) return self.deny(.before_adapter_call, args.world_port_id, .portable_value_required, null, "portable value required");
            if (args.value_policy.allow_native_only_values and policy.reject_native_only_values) return self.deny(.before_adapter_call, args.world_port_id, .native_value_rejected, null, "native value rejected");
            if (self.permit.ruleFor(args.world_port_id)) |rule| {
                if (!rule.permitsMode(args.mode)) return self.deny(.before_adapter_call, args.world_port_id, .port_rule_denied, rule.rule_fingerprint, "rule mode denied");
                if (!rule.allowed_adapter_kinds.allows(args.adapter_kind)) return self.deny(.before_adapter_call, args.world_port_id, .adapter_kind_denied, rule.rule_fingerprint, "rule adapter denied");
                if (rule.require_portable_values and !args.value_policy.require_portable_values) return self.deny(.before_adapter_call, args.world_port_id, .portable_value_required, rule.rule_fingerprint, "rule portable value required");
                const authority_kind = args.authority_kind orelse if (args.adapter_kind == .native) PortAuthority.native_function.authority_kind else null;
                if (authority_kind) |kind| {
                    if (!rule.allowed_authority_kinds.allows(kind)) return self.deny(.before_adapter_call, args.world_port_id, .authority_denied, rule.rule_fingerprint, "rule authority denied");
                } else if (!std.meta.eql(rule.allowed_authority_kinds, Supervision.AllowedAuthorityKinds.all)) {
                    return self.deny(.before_adapter_call, args.world_port_id, .authority_denied, rule.rule_fingerprint, "rule authority missing");
                }
            }
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            const current_usage = next.per_port_usage[args.world_port_id];
            var fresh_delta: usize = 0;
            var replay_delta: usize = 0;
            var verify_delta: usize = 0;
            var cost_delta: u64 = 0;
            switch (args.accounting_mode orelse args.mode) {
                .fresh, .audit => {
                    fresh_delta = 1;
                    cost_delta = self.permit.cost_model.freshCost(args.world_port_id);
                },
                .replay => {
                    replay_delta = 1;
                    cost_delta = self.permit.cost_model.replayCost(args.world_port_id);
                },
                .verify => {
                    verify_delta = 1;
                    cost_delta = self.permit.cost_model.verifyCost(args.world_port_id);
                },
            }
            const rule = self.permit.ruleFor(args.world_port_id);
            if (rule) |port_rule| {
                if (port_rule.max_cost_units) |max| {
                    if (addSatU64(current_usage.cost_units, cost_delta) > max) return self.deny(.before_adapter_call, args.world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule cost cap");
                }
            }
            next.total_fresh_calls = addSatUsize(next.total_fresh_calls, fresh_delta);
            next.total_replay_calls = addSatUsize(next.total_replay_calls, replay_delta);
            next.total_verify_calls = addSatUsize(next.total_verify_calls, verify_delta);
            next.total_cost_units = addSatU64(next.total_cost_units, cost_delta);
            const usage = &next.per_port_usage[args.world_port_id];
            usage.fresh_calls = addSatUsize(usage.fresh_calls, fresh_delta);
            usage.replay_calls = addSatUsize(usage.replay_calls, replay_delta);
            usage.verify_calls = addSatUsize(usage.verify_calls, verify_delta);
            usage.cost_units = addSatU64(usage.cost_units, cost_delta);
            try self.commitCheck(.before_adapter_call, args.world_port_id, &next, null, rule, "adapter call");
        }

        pub fn afterAdapterResponse(self: *@This(), args: struct {
            world_port_id: u32,
            status: ResponseStatus,
            response_bytes: usize = 0,
            value_image_bytes: usize = 0,
        }) !void {
            try self.validateWorldPortId(args.world_port_id);
            if (!responseAllowedByPolicy(self.permit.policy, args.status)) {
                const blocker: Blocker = switch (args.status) {
                    .pending => .pending_denied,
                    .rejected => .rejected_denied,
                    .failed => .failed_denied,
                    .responded => .none,
                };
                return self.deny(.after_adapter_response, args.world_port_id, blocker, null, "response status denied");
            }
            if (self.permit.ruleFor(args.world_port_id)) |rule| {
                const allowed = switch (args.status) {
                    .responded => true,
                    .pending => rule.allow_pending,
                    .rejected => rule.allow_reject,
                    .failed => rule.allow_fail,
                };
                if (!allowed) return self.deny(.after_adapter_response, args.world_port_id, .port_rule_denied, rule.rule_fingerprint, "rule response denied");
            }
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            const response_cost = self.permit.cost_model.responseCost(args.world_port_id);
            const response_byte_cost = mulSatUsizeU64(args.response_bytes, self.permit.cost_model.frameByteCost(args.world_port_id));
            const value_image_cost = mulSatUsizeU64(args.value_image_bytes, self.permit.cost_model.valueImageByteCost(args.world_port_id));
            const current_usage = next.per_port_usage[args.world_port_id];
            var pending_delta: usize = 0;
            var rejected_delta: usize = 0;
            var failed_delta: usize = 0;
            var status_cost: u64 = 0;
            switch (args.status) {
                .responded => {},
                .pending => {
                    pending_delta = 1;
                    status_cost = self.permit.cost_model.pendingCost(args.world_port_id);
                },
                .rejected => {
                    rejected_delta = 1;
                    status_cost = self.permit.cost_model.rejectedCost(args.world_port_id);
                },
                .failed => {
                    failed_delta = 1;
                    status_cost = self.permit.cost_model.failedCost(args.world_port_id);
                },
            }
            const cost_delta = addSatU64Many(&.{ response_cost, response_byte_cost, value_image_cost, status_cost });
            const rule = self.permit.ruleFor(args.world_port_id);
            if (rule) |port_rule| {
                if (port_rule.max_response_image_bytes) |max| {
                    if (args.value_image_bytes > max) return self.deny(.after_adapter_response, args.world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule response image cap");
                }
                if (port_rule.max_cost_units) |max| {
                    if (addSatU64(current_usage.cost_units, cost_delta) > max) return self.deny(.after_adapter_response, args.world_port_id, .port_rule_denied, port_rule.rule_fingerprint, "rule cost cap");
                }
            }
            next.total_port_responses = addSatUsize(next.total_port_responses, 1);
            next.total_frame_response_bytes = addSatUsize(next.total_frame_response_bytes, args.response_bytes);
            next.total_value_image_bytes = addSatUsize(next.total_value_image_bytes, args.value_image_bytes);
            next.total_cost_units = addSatU64(next.total_cost_units, cost_delta);
            next.total_pending_calls = addSatUsize(next.total_pending_calls, pending_delta);
            next.total_rejected_calls = addSatUsize(next.total_rejected_calls, rejected_delta);
            next.total_failed_calls = addSatUsize(next.total_failed_calls, failed_delta);
            const usage = &next.per_port_usage[args.world_port_id];
            usage.responses = addSatUsize(usage.responses, 1);
            usage.response_bytes = addSatUsize(usage.response_bytes, args.response_bytes);
            usage.value_image_bytes = addSatUsize(usage.value_image_bytes, args.value_image_bytes);
            usage.cost_units = addSatU64(usage.cost_units, cost_delta);
            usage.pending_calls = addSatUsize(usage.pending_calls, pending_delta);
            usage.rejected_calls = addSatUsize(usage.rejected_calls, rejected_delta);
            usage.failed_calls = addSatUsize(usage.failed_calls, failed_delta);
            try self.commitCheck(.after_adapter_response, args.world_port_id, &next, null, rule, "adapter response");
        }

        pub fn beforeTranscriptAppend(self: *@This(), event_count_after_append: usize, image_bytes_after_append: usize) !void {
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_transcript_events = event_count_after_append;
            next.total_transcript_image_bytes = image_bytes_after_append;
            try self.commitCheck(.before_transcript_append, null, &next, null, null, "transcript append");
        }

        pub fn beforeCheckpoint(self: *@This(), value_image_bytes: usize) !void {
            if (!self.permit.policy.allow_checkpoints) return self.deny(.before_checkpoint, null, .checkpoint_denied, null, "checkpoint denied");
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            const value_image_cost = mulSatUsizeU64(value_image_bytes, self.permit.cost_model.value_image_byte_cost);
            next.total_checkpoints = addSatUsize(next.total_checkpoints, 1);
            next.total_value_image_bytes = addSatUsize(next.total_value_image_bytes, value_image_bytes);
            next.total_cost_units = addSatU64(next.total_cost_units, addSatU64(self.permit.cost_model.checkpoint_cost, value_image_cost));
            try self.commitCheck(.before_checkpoint, null, &next, null, null, "checkpoint");
        }

        pub fn beforeBranch(self: *@This(), depth: usize) !void {
            if (!self.permit.policy.allow_branching or self.permit.branch_policy != .inherit) return self.deny(.before_branch, null, .branch_denied, null, "branch denied");
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_branches = addSatUsize(next.total_branches, 1);
            next.total_cost_units = addSatU64(next.total_cost_units, self.permit.cost_model.branch_cost);
            if (self.permit.budget.max_branch_depth) |max| {
                if (depth > max) return self.exceed(.before_branch, null, .branch_depth, &next, null, "branch depth");
            }
            try self.commitCheck(.before_branch, null, &next, null, null, "branch");
        }

        pub fn beforeHandoffExport(self: *@This()) !void {
            if (!self.permit.policy.allow_handoff_export or self.permit.handoff_policy == .deny) return self.deny(.before_handoff_export, null, .handoff_denied, null, "handoff export denied");
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_handoff_exports = addSatUsize(next.total_handoff_exports, 1);
            next.total_cost_units = addSatU64(next.total_cost_units, self.permit.cost_model.handoff_export_cost);
            try self.commitCheck(.before_handoff_export, null, &next, null, null, "handoff export");
        }

        pub fn beforeInterruptedHandoffExport(self: *@This()) !void {
            if (!self.interrupted) return self.beforeHandoffExport();
            if (!self.permit.policy.allow_handoff_export or self.permit.handoff_policy == .deny) return self.deny(.before_handoff_export, null, .handoff_denied, null, "handoff export denied");
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_handoff_exports = addSatUsize(next.total_handoff_exports, 1);
            next.total_cost_units = addSatU64(next.total_cost_units, self.permit.cost_model.handoff_export_cost);
            if (self.permit.budget.max_handoff_exports) |max| {
                if (next.total_handoff_exports > max) return self.exceed(.before_handoff_export, null, .handoff_exports, &next, null, "interrupted handoff export");
            }
            if (self.permit.budget.max_total_cost_units) |max| {
                if (self.ledger.total_cost_units <= max and next.total_cost_units > max) return self.exceed(.before_handoff_export, null, .total_cost_units, &next, null, "interrupted handoff export");
            }
            const usage_before = self.ledger.ledger_fingerprint;
            const reservation = try self.reserveSupervisionEvent(.before_handoff_export, null, usage_before, null, "interrupted handoff export");
            if (reservation == .audit_only_exceeded) next.exceeded_budget = .supervision_events;
            self.ledger.deinit(self.allocator);
            self.ledger = next;
            next.per_port_usage = &.{};
            self.ledger.refreshFingerprint();
            if (reservation == .audit_only_exceeded) {
                self.last_check = Supervision.SupervisionCheck.init(.{
                    .run_permit_fingerprint = self.permit.permit_fingerprint,
                    .event_kind = .before_handoff_export,
                    .usage_before_fingerprint = usage_before,
                    .usage_after_fingerprint = self.ledger.ledger_fingerprint,
                    .allowed = true,
                    .blocker = .max_supervision_events_exceeded,
                    .budget_exceeded = .supervision_events,
                    .budget_fingerprint = self.permit.budget_fingerprint,
                    .summary = "interrupted handoff export",
                });
                return;
            }
            self.last_check = Supervision.SupervisionCheck.init(.{
                .run_permit_fingerprint = self.permit.permit_fingerprint,
                .event_kind = .before_handoff_export,
                .usage_before_fingerprint = usage_before,
                .usage_after_fingerprint = self.ledger.ledger_fingerprint,
                .allowed = true,
                .budget_fingerprint = self.permit.budget_fingerprint,
                .summary = "interrupted handoff export",
            });
        }

        pub fn encodeHandoffExport(self: *@This(), image: RunImage) ![]const u8 {
            try self.beforeHandoffExport();
            return image.encode(self.allocator);
        }

        pub fn beforeHandoffAccept(self: *@This()) !void {
            if (!self.permit.policy.allow_handoff_accept or self.permit.handoff_policy == .deny) return self.deny(.before_handoff_accept, null, .handoff_denied, null, "handoff accept denied");
            var next = try self.ledger.clone(self.allocator);
            defer next.deinit(self.allocator);
            next.total_handoff_accepts = addSatUsize(next.total_handoff_accepts, 1);
            next.total_cost_units = addSatU64(next.total_cost_units, self.permit.cost_model.handoff_accept_cost);
            try self.commitCheck(.before_handoff_accept, null, &next, null, null, "handoff accept");
        }

        pub fn receipt(self: *@This(), final_status: Supervision.RunReceipt.FinalStatus, final_run_state_fingerprint: u64, transcript_image_fingerprint: ?u64, run_image_fingerprint: ?u64) Supervision.RunReceipt {
            self.ledger.refreshFingerprint();
            return Supervision.RunReceipt.init(.{
                .run_permit_fingerprint = self.permit.permit_fingerprint,
                .environment_certificate_fingerprint = self.permit.environment_certificate_fingerprint,
                .target_ref_fingerprint = self.permit.target_ref_fingerprint,
                .run_image_fingerprint = run_image_fingerprint,
                .transcript_image_fingerprint = transcript_image_fingerprint,
                .admission_receipt_fingerprint = self.permit.admission_receipt_fingerprint,
                .module_ref_fingerprint = self.permit.module_ref_fingerprint,
                .usage_ledger_fingerprint = self.ledger.ledger_fingerprint,
                .final_run_state_fingerprint = final_run_state_fingerprint,
                .final_status = final_status,
                .exceeded_budget = self.ledger.exceeded_budget,
                .blocker = self.blocker,
                .warning_count = self.warning_count,
                .ledger = self.ledger,
            });
        }

        fn commitCheck(self: *@This(), kind: Supervision.SupervisionCheck.EventKind, world_port_id: ?u32, candidate: *Supervision.UsageLedger, blocker: ?Supervision.Blocker, rule: ?Supervision.PortRule, summary: []const u8) !void {
            candidate.refreshFingerprint();
            if (budgetExceeded(self.permit.budget, candidate.*, world_port_id)) |exceeded_kind| {
                return self.exceed(kind, world_port_id, exceeded_kind, candidate, if (rule) |r| r.rule_fingerprint else null, summary);
            }
            const usage_before = self.ledger.ledger_fingerprint;
            const reservation = try self.reserveSupervisionEvent(kind, world_port_id, usage_before, if (rule) |r| r.rule_fingerprint else null, "max supervision events");
            if (reservation == .audit_only_exceeded) candidate.exceeded_budget = .supervision_events;
            self.ledger.deinit(self.allocator);
            self.ledger = candidate.*;
            candidate.per_port_usage = &.{};
            self.ledger.refreshFingerprint();
            if (reservation == .audit_only_exceeded) {
                self.last_check = Supervision.SupervisionCheck.init(.{
                    .run_permit_fingerprint = self.permit.permit_fingerprint,
                    .event_kind = kind,
                    .world_port_id = world_port_id,
                    .usage_before_fingerprint = usage_before,
                    .usage_after_fingerprint = self.ledger.ledger_fingerprint,
                    .allowed = true,
                    .blocker = .max_supervision_events_exceeded,
                    .budget_exceeded = .supervision_events,
                    .rule_fingerprint = if (rule) |r| r.rule_fingerprint else null,
                    .budget_fingerprint = self.permit.budget_fingerprint,
                    .summary = "max supervision events",
                });
                return;
            }
            self.last_check = Supervision.SupervisionCheck.init(.{
                .run_permit_fingerprint = self.permit.permit_fingerprint,
                .event_kind = kind,
                .world_port_id = world_port_id,
                .usage_before_fingerprint = usage_before,
                .usage_after_fingerprint = self.ledger.ledger_fingerprint,
                .allowed = true,
                .blocker = blocker,
                .rule_fingerprint = if (rule) |r| r.rule_fingerprint else null,
                .budget_fingerprint = self.permit.budget_fingerprint,
                .summary = summary,
            });
        }

        fn deny(self: *@This(), kind: Supervision.SupervisionCheck.EventKind, world_port_id: ?u32, blocker: Supervision.Blocker, rule_fingerprint: ?u64, summary: []const u8) !void {
            const usage_before = self.ledger.ledger_fingerprint;
            _ = try self.reserveSupervisionEvent(kind, world_port_id, usage_before, rule_fingerprint, "max supervision events");
            self.blocker = blocker;
            self.last_check = Supervision.SupervisionCheck.init(.{
                .run_permit_fingerprint = self.permit.permit_fingerprint,
                .event_kind = kind,
                .world_port_id = world_port_id,
                .usage_before_fingerprint = usage_before,
                .usage_after_fingerprint = usage_before,
                .allowed = false,
                .blocker = blocker,
                .rule_fingerprint = rule_fingerprint,
                .budget_fingerprint = self.permit.budget_fingerprint,
                .summary = summary,
            });
            return errorForBlocker(blocker);
        }

        fn exceed(self: *@This(), kind: Supervision.SupervisionCheck.EventKind, world_port_id: ?u32, exceeded_kind: Supervision.BudgetExceededKind, candidate: *Supervision.UsageLedger, rule_fingerprint: ?u64, summary: []const u8) !void {
            candidate.exceeded_budget = exceeded_kind;
            candidate.refreshFingerprint();
            const usage_before = self.ledger.ledger_fingerprint;
            _ = try self.reserveSupervisionEvent(kind, world_port_id, usage_before, rule_fingerprint, "max supervision events");
            self.ledger.deinit(self.allocator);
            self.ledger = candidate.*;
            candidate.per_port_usage = &.{};
            self.last_check = Supervision.SupervisionCheck.init(.{
                .run_permit_fingerprint = self.permit.permit_fingerprint,
                .event_kind = kind,
                .world_port_id = world_port_id,
                .usage_before_fingerprint = usage_before,
                .usage_after_fingerprint = self.ledger.ledger_fingerprint,
                .allowed = false,
                .blocker = .budget_exceeded,
                .budget_exceeded = exceeded_kind,
                .rule_fingerprint = rule_fingerprint,
                .budget_fingerprint = self.permit.budget_fingerprint,
                .summary = summary,
            });
            switch (self.permit.policy.budgetBehavior()) {
                .fail => {
                    self.blocker = .budget_exceeded;
                    return Error.BudgetExceeded;
                },
                .park => {
                    self.blocker = .budget_exceeded;
                    self.interrupted = true;
                    return Error.BudgetExceeded;
                },
                .audit_only => {
                    self.warning_count += 1;
                    var check = self.last_check.?;
                    check.allowed = true;
                    check.check_fingerprint = fingerprintSupervisionCheck(check);
                    self.last_check = check;
                    return;
                },
            }
        }

        fn reserveSupervisionEvent(self: *@This(), kind: Supervision.SupervisionCheck.EventKind, world_port_id: ?u32, usage_before: u64, rule_fingerprint: ?u64, summary: []const u8) !SupervisionEventReservation {
            if (self.permit.policy.max_supervision_events) |max| {
                if (self.supervision_event_count >= max) {
                    var check = Supervision.SupervisionCheck.init(.{
                        .run_permit_fingerprint = self.permit.permit_fingerprint,
                        .event_kind = kind,
                        .world_port_id = world_port_id,
                        .usage_before_fingerprint = usage_before,
                        .usage_after_fingerprint = usage_before,
                        .allowed = false,
                        .blocker = .max_supervision_events_exceeded,
                        .budget_exceeded = .supervision_events,
                        .rule_fingerprint = rule_fingerprint,
                        .budget_fingerprint = self.permit.budget_fingerprint,
                        .summary = summary,
                    });
                    switch (self.permit.policy.budgetBehavior()) {
                        .fail => {
                            self.blocker = .max_supervision_events_exceeded;
                            self.last_check = check;
                            return Error.BudgetExceeded;
                        },
                        .park => {
                            self.blocker = .max_supervision_events_exceeded;
                            self.interrupted = true;
                            self.last_check = check;
                            return Error.BudgetExceeded;
                        },
                        .audit_only => {
                            self.warning_count += 1;
                            check.allowed = true;
                            check.check_fingerprint = fingerprintSupervisionCheck(check);
                            self.last_check = check;
                            return .audit_only_exceeded;
                        },
                    }
                }
            }
            self.supervision_event_count += 1;
            return .recorded;
        }
    };

    pub fn modeAllowedByPolicy(policy: Supervision.SupervisionPolicy, mode: Mode) bool {
        return switch (mode) {
            .fresh => policy.allow_fresh_calls,
            .audit => policy.allow_audit_only,
            .replay => policy.allow_replay_calls,
            .verify => policy.allow_verify_calls,
        };
    }

    pub fn adapterAllowedByPolicy(policy: Supervision.SupervisionPolicy, kind: AdapterKind) bool {
        return switch (kind) {
            .native => policy.allow_native_adapters,
            .byte => policy.allow_byte_adapters,
            .replay => policy.allow_replay_adapters,
            .verify => policy.allow_native_adapters and policy.allow_verify_calls,
            .null_reject => policy.allow_rejected_responses,
            .pending_stub => policy.allow_pending_responses,
            .custom => policy.allow_native_adapters or policy.allow_byte_adapters or policy.allow_replay_adapters,
        };
    }

    pub fn responseAllowedByPolicy(policy: Supervision.SupervisionPolicy, status: ResponseStatus) bool {
        return switch (status) {
            .responded => true,
            .pending => policy.allow_pending_responses,
            .rejected => policy.allow_rejected_responses,
            .failed => policy.allow_failed_responses,
        };
    }

    fn budgetExceeded(budget: Supervision.Budget, ledger: Supervision.UsageLedger, world_port_id: ?u32) ?Supervision.BudgetExceededKind {
        if (budget.max_session_steps) |max| if (ledger.total_session_steps > max) return .session_steps;
        if (budget.max_port_requests) |max| if (ledger.total_port_requests > max) return .port_requests;
        if (budget.max_port_responses) |max| if (ledger.total_port_responses > max) return .port_responses;
        if (budget.max_fresh_calls) |max| if (ledger.total_fresh_calls > max) return .fresh_calls;
        if (budget.max_replay_calls) |max| if (ledger.total_replay_calls > max) return .replay_calls;
        if (budget.max_verify_calls) |max| if (ledger.total_verify_calls > max) return .verify_calls;
        if (budget.max_failed_calls) |max| if (ledger.total_failed_calls > max) return .failed_calls;
        if (budget.max_rejected_calls) |max| if (ledger.total_rejected_calls > max) return .rejected_calls;
        if (budget.max_pending_calls) |max| if (ledger.total_pending_calls > max) return .pending_calls;
        if (budget.max_frame_request_bytes) |max| if (ledger.total_frame_request_bytes > max) return .frame_request_bytes;
        if (budget.max_frame_response_bytes) |max| if (ledger.total_frame_response_bytes > max) return .frame_response_bytes;
        if (budget.max_value_image_bytes) |max| if (ledger.total_value_image_bytes > max) return .value_image_bytes;
        if (budget.max_transcript_events) |max| if (ledger.total_transcript_events > max) return .transcript_events;
        if (budget.max_transcript_image_bytes) |max| if (ledger.total_transcript_image_bytes > max) return .transcript_image_bytes;
        if (budget.max_checkpoints) |max| if (ledger.total_checkpoints > max) return .checkpoints;
        if (budget.max_branches) |max| if (ledger.total_branches > max) return .branches;
        if (budget.max_handoff_exports) |max| if (ledger.total_handoff_exports > max) return .handoff_exports;
        if (budget.max_handoff_accepts) |max| if (ledger.total_handoff_accepts > max) return .handoff_accepts;
        if (budget.max_total_cost_units) |max| if (ledger.total_cost_units > max) return .total_cost_units;
        if (world_port_id) |id| {
            if (budget.perPort(id)) |per_port_budget| {
                const usage = ledger.per_port_usage[id];
                if (per_port_budget.max_requests) |max| if (usage.requests > max) return .per_port_requests;
                if (per_port_budget.max_fresh_calls) |max| if (usage.fresh_calls > max) return .per_port_fresh_calls;
                if (per_port_budget.max_replay_calls) |max| if (usage.replay_calls > max) return .per_port_replay_calls;
                if (per_port_budget.max_response_bytes) |max| if (usage.response_bytes > max) return .per_port_response_bytes;
                if (per_port_budget.max_value_image_bytes) |max| if (usage.value_image_bytes > max) return .per_port_value_image_bytes;
                if (per_port_budget.max_cost_units) |max| if (usage.cost_units > max) return .per_port_cost_units;
            }
        }
        return null;
    }

    fn errorForBlocker(blocker: Supervision.Blocker) Error {
        return switch (blocker) {
            .budget_exceeded, .max_supervision_events_exceeded => Error.BudgetExceeded,
            .port_rule_denied => Error.PortRuleDenied,
            .adapter_kind_denied => Error.AdapterKindDenied,
            .authority_denied => Error.AuthorityDenied,
            .portable_value_required => Error.PortableValueRequired,
            .native_value_rejected => Error.NativeValueRejected,
            .fresh_call_denied => Error.FreshCallDenied,
            .replay_call_denied => Error.ReplayCallDenied,
            .verify_call_denied => Error.SupervisionDenied,
            .pending_denied => Error.PendingDenied,
            .rejected_denied => Error.HandlerRejected,
            .failed_denied => Error.HandlerFailed,
            .branch_denied => Error.BranchDenied,
            .checkpoint_denied => Error.SupervisionDenied,
            .handoff_denied => Error.HandoffDenied,
            .transcript_image_required => Error.TranscriptImageRequired,
            .environment_certificate_required => Error.SupervisionDenied,
            .none => Error.SupervisionDenied,
        };
    }
};

pub fn Environment(comptime Target: type, comptime Config: anytype) type {
    comptime validateTarget(Target);
    const bindings = if (@hasField(@TypeOf(Config), "bindings")) Config.bindings else .{};
    const policy = if (@hasField(@TypeOf(Config), "policy")) Config.policy else EnvironmentPolicy.fresh_and_replay;
    return struct {
        pub const Policy = EnvironmentPolicy;
        pub const TargetType = Target;
        pub const target_ref = TargetRef.fromTarget(Target);
        pub const import_set = ImportSet.fromTarget(Target);
        pub const bindings_decl = bindings;
        pub const policy_decl = policy;
        pub const ports = boundPorts(bindings);
        pub const dense_binding_entries = bindingPlanEntries(Target, bindings);
        pub const machine_config = .{ .environment = @This() };

        pub fn acceptanceReport(requested_mode: Mode, transcript_image_available: bool) AcceptanceReport {
            return acceptanceReportFor(Target, bindings, policy, requested_mode, transcript_image_available);
        }

        pub fn acceptanceReportWithSupervision(requested_mode: Mode, transcript_image_available: bool, supervision_policy: SupervisionPolicy) AcceptanceReport {
            const report = acceptanceReportFor(Target, bindings, policy, requested_mode, transcript_image_available);
            if (!report.accepted) return report;
            if (!Supervision.modeAllowedByPolicy(supervision_policy, requested_mode)) return rejectedReport(report, &.{supervisionModeAcceptanceBlocker(requested_mode)});
            if (supervision_policy.require_transcript_image_for_replay and modeConsumesTranscript(requested_mode) and !transcript_image_available) {
                return rejectedReport(report, &.{.TranscriptImageRequired});
            }
            inline for (dense_binding_entries) |entry| {
                if (!Supervision.adapterAllowedByPolicy(supervision_policy, entry.adapter_kind)) {
                    return rejectedReport(report, &.{.SupervisionPolicyMismatch});
                }
                if (supervision_policy.require_portable_value_images and !entry.value_policy.require_portable_values) {
                    return rejectedReport(report, &.{.PortableValuesRequired});
                }
                if (supervision_policy.reject_native_only_values and entry.value_policy.allow_native_only_values) {
                    return rejectedReport(report, &.{.NativeOnlyValueRejected});
                }
            }
            return report;
        }

        pub fn acceptanceReportWithPermit(requested_mode: Mode, transcript_image_available: bool, permit: RunPermit) AcceptanceReport {
            const environment_target_ref = TargetRef.fromTarget(Target);
            if (permit.mode != requested_mode) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            if (permit.target_ref_fingerprint != environment_target_ref.target_ref_fingerprint) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            if (permit.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            if (permit.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            const cert = certificate(requested_mode, transcript_image_available);
            if (permit.environment_certificate_fingerprint != cert.certificate_fingerprint) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            if (permit.binding_plan_fingerprint != cert.binding_plan_fingerprint) {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{.SupervisionPolicyMismatch});
            }
            const report = acceptanceReportWithSupervision(requested_mode, transcript_image_available, permit.policy);
            if (!report.accepted) return report;
            Supervision.Supervisor.validatePermitForRun(permit, Target.WorldPortTable.entries.len) catch |err| {
                return rejectedAcceptance(environment_target_ref, requested_mode, &.{supervisionPreflightBlocker(err)});
            };
            inline for (bindings) |BindingDecl| {
                if (BindingDecl.TargetType != Target) continue;
                if (BindingDecl.world_port_id >= Target.WorldPortTable.entries.len) continue;
                if (permit.ruleFor(BindingDecl.world_port_id)) |rule| {
                    if (!rule.permitsMode(requested_mode)) return rejectedReport(report, &.{.SupervisionPortRuleDenied});
                    const adapter_kind: AdapterKind = if (@hasDecl(BindingDecl, "adapter_kind")) BindingDecl.adapter_kind else .native;
                    if (!rule.allowed_adapter_kinds.allows(adapter_kind)) return rejectedReport(report, &.{.SupervisionPortRuleDenied});
                    const value_policy: ValuePolicy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible;
                    if (rule.require_portable_values and !value_policy.require_portable_values) return rejectedReport(report, &.{.SupervisionPortRuleDenied});
                    const authority_kind = comptime authorityKindForDecl(BindingDecl);
                    if (authority_kind) |kind| {
                        if (!rule.allowed_authority_kinds.allows(kind)) return rejectedReport(report, &.{.SupervisionPortRuleDenied});
                    } else if (!std.meta.eql(rule.allowed_authority_kinds, Supervision.AllowedAuthorityKinds.all)) {
                        return rejectedReport(report, &.{.SupervisionPortRuleDenied});
                    }
                }
            }
            return report;
        }

        pub fn bindingPlan() BindingPlan {
            return bindingPlanForMode(.fresh, false);
        }

        pub fn bindingPlanForMode(requested_mode: Mode, transcript_image_available: bool) BindingPlan {
            const report = acceptanceReport(requested_mode, transcript_image_available);
            return bindingPlanFor(Target, bindings, policy, dense_binding_entries[0..], report.accepted);
        }

        pub fn certificate(requested_mode: Mode, transcript_image_available: bool) EnvironmentCertificate {
            const report = acceptanceReport(requested_mode, transcript_image_available);
            const plan = bindingPlanForMode(requested_mode, transcript_image_available);
            var cert = EnvironmentCertificate{
                .certificate_fingerprint = 0,
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                .import_set_fingerprint = import_set.import_set_fingerprint,
                .binding_plan_fingerprint = plan.plan_fingerprint,
                .acceptance_report_fingerprint = report.report_fingerprint,
                .policy_fingerprint = policy.policy_fingerprint,
                .authority_descriptor_fingerprint = authoritySetFingerprint(dense_binding_entries[0..]),
                .adapter_descriptor_fingerprint = adapterSetFingerprint(dense_binding_entries[0..]),
                .accepted_modes = acceptedModeMask(report),
                .blocker_count = report.blockers.len,
            };
            cert.certificate_fingerprint = fingerprintEnvironmentCertificate(cert);
            return cert;
        }
    };
}

pub const Frame = struct {
    pub const Status = ResponseStatus;
    pub const Error = error{
        UnsupportedValueImage,
        NativeOnlyValue,
        MissingValueImage,
        InvalidFrameEncoding,
        FrameSurfaceMismatch,
        FrameTargetCertificateMismatch,
        FramePortMismatch,
        FrameRequestFingerprintMismatch,
        FrameValueTableMismatch,
        VerifyMissingExpected,
        VerifyResponseKindMismatch,
        VerifyResponseFingerprintMismatch,
        VerifyValueImageMismatch,
        OutOfMemory,
    };

    pub const Codec = struct {
        pub const reject_trailing_junk = true;
    };

    pub const ValueImage = struct {
        format_version: u32 = world_frame_value_image_format_version,
        fingerprint_version: u32 = world_frame_value_image_fingerprint_version,
        value_image_fingerprint: u64,
        value_table_id: ?u32 = null,
        boundary_value_fingerprint: ?u64 = null,
        codec_schema_descriptor_fingerprint: ?u64 = null,
        bytes: []const u8,
        dynamic_size: bool = false,
        diagnostic_type_label: ?[]const u8 = null,

        pub fn fromValue(
            allocator: std.mem.Allocator,
            value_table_id: ?u32,
            boundary_value_fingerprint: ?u64,
            codec_schema_descriptor_fingerprint: ?u64,
            value: anytype,
            policy: ValuePolicy,
        ) !@This() {
            var bytes: std.ArrayList(u8) = .empty;
            errdefer bytes.deinit(allocator);
            if (policy.max_value_image_bytes) |max| {
                if (portableValueDynamicByteLowerBound(@TypeOf(value), value) > max) return error.UnsupportedValueImage;
            }
            try encodePortableValue(@TypeOf(value), allocator, &bytes, value);
            if (policy.max_value_image_bytes) |max| {
                if (bytes.items.len > max) return error.UnsupportedValueImage;
            }
            const owned_bytes = try bytes.toOwnedSlice(allocator);
            errdefer allocator.free(owned_bytes);
            const label = if (policy.allow_diagnostic_type_labels)
                try allocator.dupe(u8, @typeName(@TypeOf(value)))
            else
                null;
            errdefer if (label) |owned_label| allocator.free(owned_label);
            const dynamic_size = valueIsDynamic(@TypeOf(value));
            return .{
                .value_image_fingerprint = fingerprintValueImage(
                    value_table_id,
                    boundary_value_fingerprint,
                    codec_schema_descriptor_fingerprint,
                    dynamic_size,
                    label,
                    owned_bytes,
                ),
                .value_table_id = value_table_id,
                .boundary_value_fingerprint = boundary_value_fingerprint,
                .codec_schema_descriptor_fingerprint = codec_schema_descriptor_fingerprint,
                .bytes = owned_bytes,
                .dynamic_size = dynamic_size,
                .diagnostic_type_label = label,
            };
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            const bytes = try allocator.dupe(u8, self.bytes);
            errdefer allocator.free(bytes);
            const label = if (self.diagnostic_type_label) |diagnostic|
                try allocator.dupe(u8, diagnostic)
            else
                null;
            errdefer if (label) |owned| allocator.free(owned);
            var result = self;
            result.bytes = bytes;
            result.diagnostic_type_label = label;
            return result;
        }

        fn cloneWithBoundaryValueFingerprint(self: @This(), allocator: std.mem.Allocator, boundary_value_fingerprint: u64) !@This() {
            var result = try self.clone(allocator);
            result.boundary_value_fingerprint = boundary_value_fingerprint;
            result.value_image_fingerprint = fingerprintValueImage(
                result.value_table_id,
                result.boundary_value_fingerprint,
                result.codec_schema_descriptor_fingerprint,
                result.dynamic_size,
                result.diagnostic_type_label,
                result.bytes,
            );
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.bytes);
            if (self.diagnostic_type_label) |label| allocator.free(label);
            self.* = undefined;
        }

        pub fn decodeValue(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
            var cursor: usize = 0;
            const value = try decodePortableValue(Value, allocator, self.bytes, &cursor);
            errdefer deinitOwnedValue(allocator, value);
            if (cursor != self.bytes.len) return error.InvalidFrameEncoding;
            return value;
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.value_image_fingerprint);
            try writeOptionalU32(&out, allocator, self.value_table_id);
            try writeOptionalU64(&out, allocator, self.boundary_value_fingerprint);
            try writeOptionalU64(&out, allocator, self.codec_schema_descriptor_fingerprint);
            try writeBool(&out, allocator, self.dynamic_size);
            try writeBytes(&out, allocator, self.bytes);
            try writeOptionalBytes(&out, allocator, self.diagnostic_type_label);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_value_image_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_value_image_fingerprint_version) return error.InvalidFrameEncoding;
            const value_image_fingerprint = try readU64(bytes, cursor);
            const value_table_id = try readOptionalU32(bytes, cursor);
            const boundary_value_fingerprint = try readOptionalU64(bytes, cursor);
            const codec_schema_descriptor_fingerprint = try readOptionalU64(bytes, cursor);
            const dynamic_size = try readBool(bytes, cursor);
            const image_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(image_bytes);
            const label = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (label) |owned| allocator.free(owned);
            const expected = fingerprintValueImage(
                value_table_id,
                boundary_value_fingerprint,
                codec_schema_descriptor_fingerprint,
                dynamic_size,
                label,
                image_bytes,
            );
            if (expected != value_image_fingerprint) return error.VerifyValueImageMismatch;
            return .{
                .value_image_fingerprint = value_image_fingerprint,
                .value_table_id = value_table_id,
                .boundary_value_fingerprint = boundary_value_fingerprint,
                .codec_schema_descriptor_fingerprint = codec_schema_descriptor_fingerprint,
                .bytes = image_bytes,
                .dynamic_size = dynamic_size,
                .diagnostic_type_label = label,
            };
        }
    };

    pub const Request = struct {
        format_version: u32 = world_frame_request_format_version,
        fingerprint_version: u32 = world_frame_request_fingerprint_version,
        frame_fingerprint: u64,
        world_surface_fingerprint: u64,
        world_surface_replay_scope_fingerprint: ?u64 = null,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        request_fingerprint: u64,
        turn_index: usize,
        payload_value_table_id: ?u32 = null,
        expected_response_value_table_id: ?u32 = null,
        payload_value_fingerprint: ?u64 = null,
        payload_image: ?ValueImage = null,
        replay_key_seed: ReplayKeySeed,
        source_effect_shape_fingerprint: ?u64 = null,
        world_port_ref_fingerprint: ?u64 = null,
        trace_ref_fingerprint: ?u64 = null,
        evidence_ref_fingerprint: ?u64 = null,
        flags: u32 = 0,

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            world_surface_replay_scope_fingerprint: ?u64 = null,
            target_certificate_fingerprint: u64,
            world_port_id: u32,
            residual_site_index: usize,
            residual_site_fingerprint: u64,
            request_fingerprint: u64,
            turn_index: usize,
            payload_value_table_id: ?u32 = null,
            expected_response_value_table_id: ?u32 = null,
            payload_image: ?ValueImage = null,
            flags: u32 = 0,
        }) @This() {
            const replay_scope = args.world_surface_replay_scope_fingerprint orelse args.world_surface_fingerprint;
            var result = @This(){
                .frame_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .world_surface_replay_scope_fingerprint = args.world_surface_replay_scope_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .world_port_id = args.world_port_id,
                .residual_site_index = args.residual_site_index,
                .residual_site_fingerprint = args.residual_site_fingerprint,
                .request_fingerprint = args.request_fingerprint,
                .turn_index = args.turn_index,
                .payload_value_table_id = args.payload_value_table_id,
                .expected_response_value_table_id = args.expected_response_value_table_id,
                .payload_value_fingerprint = if (args.payload_image) |image| image.value_image_fingerprint else null,
                .payload_image = args.payload_image,
                .replay_key_seed = .{
                    .world_surface_fingerprint = args.world_surface_fingerprint,
                    .world_surface_scope_fingerprint = replay_scope,
                    .world_port_id = args.world_port_id,
                    .request_fingerprint = args.request_fingerprint,
                },
                .flags = args.flags,
            };
            result.frame_fingerprint = fingerprintRequest(result);
            return result;
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            var result = self;
            result.payload_image = if (self.payload_image) |image| try image.clone(allocator) else null;
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.payload_image) |*image| image.deinit(allocator);
            self.* = undefined;
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.frame_fingerprint);
            try writeU64(&out, allocator, self.world_surface_fingerprint);
            try writeOptionalU64(&out, allocator, self.world_surface_replay_scope_fingerprint);
            try writeU64(&out, allocator, self.target_certificate_fingerprint);
            try writeU32(&out, allocator, self.world_port_id);
            try writeU64(&out, allocator, self.residual_site_index);
            try writeU64(&out, allocator, self.residual_site_fingerprint);
            try writeU64(&out, allocator, self.request_fingerprint);
            try writeU64(&out, allocator, self.turn_index);
            try writeOptionalU32(&out, allocator, self.payload_value_table_id);
            try writeOptionalU32(&out, allocator, self.expected_response_value_table_id);
            try writeOptionalU64(&out, allocator, self.payload_value_fingerprint);
            try writeOptionalValueImage(&out, allocator, self.payload_image);
            try writeU64(&out, allocator, self.replay_key_seed.world_surface_fingerprint);
            try writeU64(&out, allocator, self.replay_key_seed.world_surface_scope_fingerprint);
            try writeU32(&out, allocator, self.replay_key_seed.world_port_id);
            try writeU64(&out, allocator, self.replay_key_seed.request_fingerprint);
            try writeOptionalU64(&out, allocator, self.source_effect_shape_fingerprint);
            try writeOptionalU64(&out, allocator, self.world_port_ref_fingerprint);
            try writeOptionalU64(&out, allocator, self.trace_ref_fingerprint);
            try writeOptionalU64(&out, allocator, self.evidence_ref_fingerprint);
            try writeU32(&out, allocator, self.flags);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_request_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_request_fingerprint_version) return error.InvalidFrameEncoding;
            const frame_fingerprint = try readU64(bytes, cursor);
            const world_surface_fingerprint = try readU64(bytes, cursor);
            const world_surface_replay_scope_fingerprint = try readOptionalU64(bytes, cursor);
            const target_certificate_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const residual_site_index = try readU64AsUsize(bytes, cursor);
            const residual_site_fingerprint = try readU64(bytes, cursor);
            const request_fingerprint = try readU64(bytes, cursor);
            const turn_index = try readU64AsUsize(bytes, cursor);
            const payload_value_table_id = try readOptionalU32(bytes, cursor);
            const expected_response_value_table_id = try readOptionalU32(bytes, cursor);
            const payload_value_fingerprint = try readOptionalU64(bytes, cursor);
            var payload_image = try readOptionalValueImage(allocator, bytes, cursor);
            errdefer if (payload_image) |*image| image.deinit(allocator);
            const replay_key_seed = ReplayKeySeed{
                .world_surface_fingerprint = try readU64(bytes, cursor),
                .world_surface_scope_fingerprint = try readU64(bytes, cursor),
                .world_port_id = try readU32(bytes, cursor),
                .request_fingerprint = try readU64(bytes, cursor),
            };
            const source_effect_shape_fingerprint = try readOptionalU64(bytes, cursor);
            const world_port_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const trace_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const evidence_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const flags = try readU32(bytes, cursor);
            var result = @This(){
                .frame_fingerprint = frame_fingerprint,
                .world_surface_fingerprint = world_surface_fingerprint,
                .world_surface_replay_scope_fingerprint = world_surface_replay_scope_fingerprint,
                .target_certificate_fingerprint = target_certificate_fingerprint,
                .world_port_id = world_port_id,
                .residual_site_index = residual_site_index,
                .residual_site_fingerprint = residual_site_fingerprint,
                .request_fingerprint = request_fingerprint,
                .turn_index = turn_index,
                .payload_value_table_id = payload_value_table_id,
                .expected_response_value_table_id = expected_response_value_table_id,
                .payload_value_fingerprint = payload_value_fingerprint,
                .payload_image = payload_image,
                .replay_key_seed = replay_key_seed,
                .source_effect_shape_fingerprint = source_effect_shape_fingerprint,
                .world_port_ref_fingerprint = world_port_ref_fingerprint,
                .trace_ref_fingerprint = trace_ref_fingerprint,
                .evidence_ref_fingerprint = evidence_ref_fingerprint,
                .flags = flags,
            };
            payload_image = null;
            errdefer result.deinit(allocator);
            const expected_payload_value_fingerprint: ?u64 = if (result.payload_image) |image| image.value_image_fingerprint else null;
            if (result.payload_value_fingerprint != expected_payload_value_fingerprint) return error.InvalidFrameEncoding;
            if (result.payload_image) |image| {
                if (image.value_table_id != result.payload_value_table_id) return error.InvalidFrameEncoding;
                if (image.boundary_value_fingerprint != null) return error.InvalidFrameEncoding;
            }
            const expected_replay_scope = result.world_surface_replay_scope_fingerprint orelse result.world_surface_fingerprint;
            if (result.replay_key_seed.world_surface_fingerprint != result.world_surface_fingerprint) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.world_surface_scope_fingerprint != expected_replay_scope) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.world_port_id != result.world_port_id) return error.InvalidFrameEncoding;
            if (result.replay_key_seed.request_fingerprint != result.request_fingerprint) return error.InvalidFrameEncoding;
            if (fingerprintRequest(result) != result.frame_fingerprint) return error.InvalidFrameEncoding;
            return result;
        }
    };

    pub const Response = struct {
        format_version: u32 = world_frame_response_format_version,
        fingerprint_version: u32 = world_frame_response_fingerprint_version,
        frame_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        request_fingerprint: u64,
        response_kind: ResponseKind = .@"resume",
        response_value_table_id: ?u32 = null,
        response_fingerprint: u64,
        response_value_fingerprint: ?u64 = null,
        response_image: ?ValueImage = null,
        replay_key: u64,
        status: ResponseStatus = .responded,
        error_tag: ?[]const u8 = null,
        reason: ?[]const u8 = null,
        owns_error_tag: bool = false,
        owns_reason: bool = false,
        flags: u32 = 0,

        pub fn fromValue(
            allocator: std.mem.Allocator,
            request: Request,
            response_value_table_id: ?u32,
            response_fingerprint: u64,
            response_kind: ResponseKind,
            value: anytype,
            policy: ValuePolicy,
        ) !@This() {
            var image = try ValueImage.fromValue(
                allocator,
                response_value_table_id,
                response_fingerprint,
                null,
                value,
                policy,
            );
            errdefer image.deinit(allocator);
            return init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_kind = response_kind,
                .response_value_table_id = response_value_table_id,
                .response_fingerprint = response_fingerprint,
                .response_image = image,
                .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
                .status = .responded,
            });
        }

        pub fn fromPortableValue(
            allocator: std.mem.Allocator,
            request: Request,
            response_value_table_id: ?u32,
            response_kind: ResponseKind,
            value: anytype,
            policy: ValuePolicy,
        ) !@This() {
            var image = try ValueImage.fromValue(
                allocator,
                response_value_table_id,
                null,
                null,
                value,
                policy,
            );
            errdefer image.deinit(allocator);
            return init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_kind = response_kind,
                .response_value_table_id = response_value_table_id,
                .response_fingerprint = 0,
                .response_image = image,
                .replay_key = 0,
                .status = .responded,
                .flags = frame_response_deferred_fingerprint_flag,
            });
        }

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            world_port_id: u32,
            request_fingerprint: u64,
            response_kind: ResponseKind = .@"resume",
            response_value_table_id: ?u32 = null,
            response_fingerprint: u64,
            response_image: ?ValueImage = null,
            replay_key: u64,
            status: ResponseStatus = .responded,
            error_tag: ?[]const u8 = null,
            reason: ?[]const u8 = null,
            flags: u32 = 0,
        }) @This() {
            var result = @This(){
                .frame_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .world_port_id = args.world_port_id,
                .request_fingerprint = args.request_fingerprint,
                .response_kind = args.response_kind,
                .response_value_table_id = args.response_value_table_id,
                .response_fingerprint = args.response_fingerprint,
                .response_value_fingerprint = if (args.response_image) |image| image.value_image_fingerprint else null,
                .response_image = args.response_image,
                .replay_key = args.replay_key,
                .status = args.status,
                .error_tag = args.error_tag,
                .reason = args.reason,
                .owns_error_tag = false,
                .owns_reason = false,
                .flags = args.flags,
            };
            result.frame_fingerprint = fingerprintResponse(result);
            return result;
        }

        pub fn responseFingerprintDeferred(self: @This()) bool {
            return (self.flags & frame_response_deferred_fingerprint_flag) != 0;
        }

        fn bindDeferredResponseFingerprint(self: @This(), allocator: std.mem.Allocator, request: Request, response_fingerprint: u64) !@This() {
            if (!self.responseFingerprintDeferred()) return error.InvalidFrameEncoding;
            if (self.status != .responded) return error.InvalidFrameEncoding;
            const response_image = self.response_image orelse return error.MissingValueImage;
            var rebound_image = try response_image.cloneWithBoundaryValueFingerprint(allocator, response_fingerprint);
            errdefer rebound_image.deinit(allocator);
            return init(.{
                .world_surface_fingerprint = self.world_surface_fingerprint,
                .target_certificate_fingerprint = self.target_certificate_fingerprint,
                .world_port_id = self.world_port_id,
                .request_fingerprint = self.request_fingerprint,
                .response_kind = self.response_kind,
                .response_value_table_id = self.response_value_table_id,
                .response_fingerprint = response_fingerprint,
                .response_image = rebound_image,
                .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
                .status = self.status,
                .error_tag = self.error_tag,
                .reason = self.reason,
                .flags = self.flags & ~frame_response_deferred_fingerprint_flag,
            });
        }

        pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
            var result = self;
            result.response_image = if (self.response_image) |image| try image.clone(allocator) else null;
            errdefer if (result.response_image) |*image| image.deinit(allocator);
            result.error_tag = if (self.error_tag) |tag| try allocator.dupe(u8, tag) else null;
            result.owns_error_tag = result.error_tag != null;
            errdefer if (result.error_tag) |tag| allocator.free(tag);
            result.reason = if (self.reason) |reason| try allocator.dupe(u8, reason) else null;
            result.owns_reason = result.reason != null;
            errdefer if (result.reason) |reason| allocator.free(reason);
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.response_image) |*image| image.deinit(allocator);
            if (self.owns_error_tag) if (self.error_tag) |tag| allocator.free(tag);
            if (self.owns_reason) if (self.reason) |reason| allocator.free(reason);
            self.* = undefined;
        }

        pub fn decodeValue(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
            const image = self.response_image orelse return error.MissingValueImage;
            return image.decodeValue(allocator, Value);
        }

        pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeU32(&out, allocator, self.format_version);
            try writeU32(&out, allocator, self.fingerprint_version);
            try writeU64(&out, allocator, self.frame_fingerprint);
            try writeU64(&out, allocator, self.world_surface_fingerprint);
            try writeU64(&out, allocator, self.target_certificate_fingerprint);
            try writeU32(&out, allocator, self.world_port_id);
            try writeU64(&out, allocator, self.request_fingerprint);
            try writeU8(&out, allocator, @intFromEnum(self.response_kind));
            try writeOptionalU32(&out, allocator, self.response_value_table_id);
            try writeU64(&out, allocator, self.response_fingerprint);
            try writeOptionalU64(&out, allocator, self.response_value_fingerprint);
            try writeOptionalValueImage(&out, allocator, self.response_image);
            try writeU64(&out, allocator, self.replay_key);
            try writeU8(&out, allocator, @intFromEnum(self.status));
            try writeOptionalBytes(&out, allocator, self.error_tag);
            try writeOptionalBytes(&out, allocator, self.reason);
            try writeU32(&out, allocator, self.flags);
            return out.toOwnedSlice(allocator);
        }

        pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
            var cursor: usize = 0;
            const result = try decodeFrom(allocator, bytes, &cursor);
            errdefer {
                var owned = result;
                owned.deinit(allocator);
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return result;
        }

        fn decodeFrom(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !@This() {
            const format_version = try readU32(bytes, cursor);
            if (format_version != world_frame_response_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, cursor);
            if (fingerprint_version != world_frame_response_fingerprint_version) return error.InvalidFrameEncoding;
            const frame_fingerprint = try readU64(bytes, cursor);
            const world_surface_fingerprint = try readU64(bytes, cursor);
            const target_certificate_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const request_fingerprint = try readU64(bytes, cursor);
            const response_kind = try enumFromByte(ResponseKind, try readU8(bytes, cursor));
            const response_value_table_id = try readOptionalU32(bytes, cursor);
            const response_fingerprint = try readU64(bytes, cursor);
            const response_value_fingerprint = try readOptionalU64(bytes, cursor);
            var response_image = try readOptionalValueImage(allocator, bytes, cursor);
            errdefer if (response_image) |*image| image.deinit(allocator);
            const expected_response_value_fingerprint: ?u64 = if (response_image) |image| image.value_image_fingerprint else null;
            if (response_value_fingerprint != expected_response_value_fingerprint) return error.InvalidFrameEncoding;
            const replay_key = try readU64(bytes, cursor);
            const status = try enumFromByte(ResponseStatus, try readU8(bytes, cursor));
            const error_tag = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (error_tag) |tag| allocator.free(tag);
            const reason = try readOptionalBytesOwned(allocator, bytes, cursor);
            errdefer if (reason) |owned_reason| allocator.free(owned_reason);
            const flags = try readU32(bytes, cursor);
            const deferred_response_fingerprint = (flags & frame_response_deferred_fingerprint_flag) != 0;
            if (response_image) |image| {
                if (image.value_table_id != response_value_table_id) return error.InvalidFrameEncoding;
                if (deferred_response_fingerprint) {
                    if (image.boundary_value_fingerprint != null) return error.InvalidFrameEncoding;
                } else if (image.boundary_value_fingerprint != response_fingerprint) {
                    return error.InvalidFrameEncoding;
                }
            }
            var result = init(.{
                .world_surface_fingerprint = world_surface_fingerprint,
                .target_certificate_fingerprint = target_certificate_fingerprint,
                .world_port_id = world_port_id,
                .request_fingerprint = request_fingerprint,
                .response_kind = response_kind,
                .response_value_table_id = response_value_table_id,
                .response_fingerprint = response_fingerprint,
                .response_image = response_image,
                .replay_key = replay_key,
                .status = status,
                .error_tag = error_tag,
                .reason = reason,
                .flags = flags,
            });
            result.owns_error_tag = error_tag != null;
            result.owns_reason = reason != null;
            try validateResponseFrameImage(result);
            if (result.frame_fingerprint != frame_fingerprint) return error.InvalidFrameEncoding;
            return result;
        }
    };

    pub const NativeAdapter = struct {};
    pub const ReplayAdapter = struct {};
    pub const VerifyAdapter = struct {};
};

pub const StoredValue = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    portable_image: ?Frame.ValueImage = null,
    clone_fn: *const fn (std.mem.Allocator, *anyopaque) anyerror!StoredValue,
    image_fn: *const fn (std.mem.Allocator, *anyopaque, ?u32, ?u64, ?u64, ValuePolicy) anyerror!Frame.ValueImage,
    destroy_fn: *const fn (std.mem.Allocator, *anyopaque) void,

    pub fn init(allocator: std.mem.Allocator, value: anytype) !@This() {
        const cloned = try cloneOwnedValue(allocator, value);
        errdefer deinitOwnedValue(allocator, cloned);
        return initOwned(allocator, cloned);
    }

    fn initOwned(allocator: std.mem.Allocator, value: anytype) !@This() {
        const Value = @TypeOf(value);
        const ptr = try allocator.create(Value);
        errdefer allocator.destroy(ptr);
        ptr.* = value;
        const result = @This(){
            .ptr = @ptrCast(ptr),
            .type_name = @typeName(Value),
            .clone_fn = struct {
                fn clone(inner_allocator: std.mem.Allocator, erased: *anyopaque) anyerror!StoredValue {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    return StoredValue.init(inner_allocator, typed.*);
                }
            }.clone,
            .image_fn = struct {
                fn image(
                    inner_allocator: std.mem.Allocator,
                    erased: *anyopaque,
                    value_table_id: ?u32,
                    boundary_value_fingerprint: ?u64,
                    codec_schema_descriptor_fingerprint: ?u64,
                    policy: ValuePolicy,
                ) anyerror!Frame.ValueImage {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    return Frame.ValueImage.fromValue(
                        inner_allocator,
                        value_table_id,
                        boundary_value_fingerprint,
                        codec_schema_descriptor_fingerprint,
                        typed.*,
                        policy,
                    );
                }
            }.image,
            .destroy_fn = struct {
                fn destroy(inner_allocator: std.mem.Allocator, erased: *anyopaque) void {
                    const typed: *Value = @ptrCast(@alignCast(erased));
                    deinitOwnedValue(inner_allocator, typed.*);
                    inner_allocator.destroy(typed);
                }
            }.destroy,
        };
        return result;
    }

    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
        return self.clone_fn(allocator, self.ptr);
    }

    pub fn valueImage(
        self: @This(),
        allocator: std.mem.Allocator,
        value_table_id: ?u32,
        boundary_value_fingerprint: ?u64,
        codec_schema_descriptor_fingerprint: ?u64,
        policy: ValuePolicy,
    ) !Frame.ValueImage {
        return self.image_fn(
            allocator,
            self.ptr,
            value_table_id,
            boundary_value_fingerprint,
            codec_schema_descriptor_fingerprint,
            policy,
        );
    }

    pub fn as(self: @This(), allocator: std.mem.Allocator, comptime Value: type) !Value {
        if (!std.mem.eql(u8, self.type_name, @typeName(Value))) return Error.ReplayResponseKindMismatch;
        const typed: *Value = @ptrCast(@alignCast(self.ptr));
        return cloneOwnedValue(allocator, typed.*);
    }

    fn borrow(self: @This(), comptime Value: type) !Value {
        if (!std.mem.eql(u8, self.type_name, @typeName(Value))) return Error.ReplayResponseKindMismatch;
        const typed: *Value = @ptrCast(@alignCast(self.ptr));
        return typed.*;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.portable_image) |*image| image.deinit(allocator);
        self.destroy_fn(allocator, self.ptr);
        self.ptr = undefined;
    }
};

pub const Transcript = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event) = .empty,
    replay_cursor: usize = 0,
    replay_limit: ?usize = null,

    pub const Event = struct {
        kind: EventKind,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: ?u32 = null,
        request_fingerprint: ?u64 = null,
        response_fingerprint: ?u64 = null,
        response_kind: ?ResponseKind = null,
        replay_key: ?u64 = null,
        admission_request_fingerprint: ?u64 = null,
        admission_report_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        world_surface_replay_scope_fingerprint: ?u64 = null,
        payload_value_table_id: ?u32 = null,
        expected_response_value_table_id: ?u32 = null,
        turn_index: ?usize = null,
        residual_site_index: ?usize = null,
        residual_site_fingerprint: ?u64 = null,
        status: ?ResponseStatus = null,
        source_run: bool = true,
        value: ?StoredValue = null,
        request_frame: ?Frame.Request = null,
        response_frame: ?Frame.Response = null,
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        for (self.events.items) |*event| {
            if (event.value) |*stored| stored.deinit(self.allocator);
            if (event.request_frame) |*frame| frame.deinit(self.allocator);
            if (event.response_frame) |*frame| frame.deinit(self.allocator);
        }
        self.events.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn truncateRetainingCapacity(self: *@This(), new_len: usize) void {
        std.debug.assert(new_len <= self.events.items.len);
        for (self.events.items[new_len..]) |*event| {
            if (event.value) |*stored| stored.deinit(self.allocator);
            if (event.request_frame) |*frame| frame.deinit(self.allocator);
            if (event.response_frame) |*frame| frame.deinit(self.allocator);
        }
        self.events.shrinkRetainingCapacity(new_len);
        if (self.replay_cursor > new_len) self.replay_cursor = new_len;
        if (self.replay_limit) |limit| {
            if (limit > new_len) self.replay_limit = new_len;
        }
    }

    pub fn append(self: *@This(), event: Event) !void {
        var cloned = event;
        cloned.value = null;
        if (event.value) |stored| {
            cloned.value = try stored.clone(self.allocator);
        }
        errdefer if (cloned.value) |*stored| stored.deinit(self.allocator);
        cloned.request_frame = null;
        if (event.request_frame) |frame| {
            cloned.request_frame = try frame.clone(self.allocator);
        }
        errdefer if (cloned.request_frame) |*frame| frame.deinit(self.allocator);
        cloned.response_frame = null;
        if (event.response_frame) |frame| {
            cloned.response_frame = try frame.clone(self.allocator);
        }
        errdefer if (cloned.response_frame) |*frame| frame.deinit(self.allocator);
        try self.events.append(self.allocator, cloned);
    }

    fn appendOwned(self: *@This(), event: *Event) !void {
        try self.events.append(self.allocator, event.*);
        event.value = null;
        event.request_frame = null;
        event.response_frame = null;
    }

    pub fn resetReplay(self: *@This()) void {
        self.replay_cursor = 0;
        self.replay_limit = null;
    }

    pub fn nextResponse(
        self: *@This(),
        key: ReplayKeySeed,
        expected_target_certificate_fingerprint: u64,
        expected_response_kind: ResponseKind,
    ) !*const Event {
        const replay_limit = self.replay_limit orelse self.events.items.len;
        while (self.replay_cursor < replay_limit) : (self.replay_cursor += 1) {
            const index = self.replay_cursor;
            const event = &self.events.items[index];
            if (!eventKindIsSourceResponse(event.kind)) continue;
            if (event.status) |status| {
                if (status != .responded) return Error.ReplayMissing;
            }
            if ((event.kind == .frame_responded or event.kind == .frame_replayed) and event.response_frame == null) return Error.ReplayMissing;
            if (event.response_frame) |frame| {
                if (frame.status != .responded) return Error.ReplayMissing;
            }
            if (event.world_surface_fingerprint != key.world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
            if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
            if ((event.world_port_id orelse return Error.ReplayPortMismatch) != key.world_port_id) return Error.ReplayPortMismatch;
            if ((event.request_fingerprint orelse return Error.ReplayRequestFingerprintMismatch) != key.request_fingerprint) return Error.ReplayRequestFingerprintMismatch;
            if ((event.response_kind orelse return Error.ReplayResponseKindMismatch) != expected_response_kind) return Error.ReplayResponseKindMismatch;
            const response_fingerprint = event.response_fingerprint orelse return Error.ReplayMissing;
            const key_fingerprint = key.withResponse(response_fingerprint).fingerprint();
            if ((event.replay_key orelse return Error.ReplayMissing) != key_fingerprint) return Error.ReplayMissing;
            self.replay_cursor = index + 1;
            return event;
        }
        return Error.ReplayMissing;
    }

    pub fn assertReplayComplete(self: *const @This()) !void {
        const replay_limit = self.replay_limit orelse self.events.items.len;
        var index = self.replay_cursor;
        while (index < replay_limit) : (index += 1) {
            if (eventKindIsSourceResponse(self.events.items[index].kind)) return Error.ReplayUnusedEvent;
        }
    }

    pub fn validateReplayRun(
        self: *@This(),
        expected_world_surface_fingerprint: u64,
        expected_target_certificate_fingerprint: u64,
    ) !void {
        var active_start: ?usize = null;
        var selected_start: ?usize = null;
        var selected_limit: ?usize = null;
        var active_is_source_run = false;
        var active_has_port_event = false;
        var active_has_source_response = false;
        var latest_run_failed = false;
        for (self.events.items, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return Error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_has_port_event = false;
                    active_has_source_response = false;
                    latest_run_failed = true;
                },
                .run_completed => {
                    const start = active_start orelse continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    if (active_is_source_run and (!active_has_port_event or active_has_source_response)) {
                        selected_start = start;
                        selected_limit = index;
                    }
                    active_start = null;
                    latest_run_failed = false;
                },
                .run_failed => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return Error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return Error.ReplayTargetCertificateMismatch;
                    const failed_source_run = active_is_source_run;
                    active_start = null;
                    active_is_source_run = false;
                    if (failed_source_run) {
                        selected_start = null;
                        selected_limit = null;
                    }
                    latest_run_failed = failed_source_run;
                },
                .port_responded,
                .port_replayed,
                .frame_responded,
                .frame_replayed,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
                .permit_issued,
                .admission_requested,
                .admission_accepted,
                .admission_rejected,
                .module_matched_target,
                .supervision_check,
                .budget_exceeded,
                .supervision_denied,
                .run_interrupted,
                .receipt_recorded,
                => {},
            }
        }
        if (active_start != null or latest_run_failed) return Error.ReplayMissing;
        self.replay_cursor = (selected_start orelse return Error.ReplayMissing) + 1;
        self.replay_limit = selected_limit orelse return Error.ReplayMissing;
    }

    pub fn summary(self: *const @This()) Summary {
        var result: Summary = .{};
        for (self.events.items) |event| {
            switch (event.kind) {
                .run_started => result.run_started += 1,
                .port_requested => result.port_requested += 1,
                .port_responded => result.port_responded += 1,
                .port_replayed => result.port_replayed += 1,
                .port_rejected => result.port_rejected += 1,
                .port_failed => result.port_failed += 1,
                .frame_requested => result.frame_requested += 1,
                .frame_responded => result.frame_responded += 1,
                .frame_replayed => result.frame_replayed += 1,
                .frame_verified => result.frame_verified += 1,
                .frame_rejected => result.frame_rejected += 1,
                .frame_failed => result.frame_failed += 1,
                .checkpoint_recorded => result.checkpoint_recorded += 1,
                .branch_started => result.branch_started += 1,
                .branch_joined => result.branch_joined += 1,
                .permit_issued => result.permit_issued += 1,
                .admission_requested => result.admission_requested += 1,
                .admission_accepted => result.admission_accepted += 1,
                .admission_rejected => result.admission_rejected += 1,
                .module_matched_target => result.module_matched_target += 1,
                .supervision_check => result.supervision_check += 1,
                .budget_exceeded => result.budget_exceeded += 1,
                .supervision_denied => result.supervision_denied += 1,
                .run_interrupted => result.run_interrupted += 1,
                .receipt_recorded => result.receipt_recorded += 1,
                .run_completed => result.run_completed += 1,
                .run_failed => result.run_failed += 1,
            }
        }
        return result;
    }

    pub fn toImage(self: *const @This(), allocator: std.mem.Allocator, options: anytype) !TranscriptImage {
        const policy: ValuePolicy = if (@hasField(@TypeOf(options), "value_policy"))
            @field(options, "value_policy")
        else
            .native_compatible;
        return TranscriptImage.fromTranscript(allocator, self, policy);
    }

    pub fn fromImage(allocator: std.mem.Allocator, image: TranscriptImage) !@This() {
        var transcript = Transcript.init(allocator);
        errdefer transcript.deinit();
        for (image.events) |event| {
            try transcript.append(.{
                .kind = event.kind,
                .world_surface_fingerprint = event.world_surface_fingerprint,
                .target_certificate_fingerprint = event.target_certificate_fingerprint,
                .world_port_id = event.world_port_id,
                .request_fingerprint = event.request_fingerprint,
                .response_fingerprint = event.response_fingerprint,
                .response_kind = event.response_kind,
                .replay_key = event.replay_key,
                .admission_request_fingerprint = event.admission_request_fingerprint,
                .admission_report_fingerprint = event.admission_report_fingerprint,
                .admission_receipt_fingerprint = event.admission_receipt_fingerprint,
                .module_ref_fingerprint = event.module_ref_fingerprint,
                .target_match_fingerprint = event.target_match_fingerprint,
                .world_surface_replay_scope_fingerprint = if (event.request_frame) |frame| frame.world_surface_replay_scope_fingerprint else null,
                .payload_value_table_id = if (event.request_frame) |frame| frame.payload_value_table_id else null,
                .expected_response_value_table_id = if (event.request_frame) |frame| frame.expected_response_value_table_id else null,
                .turn_index = event.turn_index,
                .residual_site_index = event.residual_site_index,
                .residual_site_fingerprint = event.residual_site_fingerprint,
                .status = event.status,
                .source_run = event.source_run,
                .request_frame = event.request_frame,
                .response_frame = event.response_frame,
            });
        }
        return transcript;
    }

    pub const Summary = struct {
        run_started: usize = 0,
        port_requested: usize = 0,
        port_responded: usize = 0,
        port_replayed: usize = 0,
        port_rejected: usize = 0,
        port_failed: usize = 0,
        frame_requested: usize = 0,
        frame_responded: usize = 0,
        frame_replayed: usize = 0,
        frame_verified: usize = 0,
        frame_rejected: usize = 0,
        frame_failed: usize = 0,
        checkpoint_recorded: usize = 0,
        branch_started: usize = 0,
        branch_joined: usize = 0,
        permit_issued: usize = 0,
        admission_requested: usize = 0,
        admission_accepted: usize = 0,
        admission_rejected: usize = 0,
        module_matched_target: usize = 0,
        supervision_check: usize = 0,
        budget_exceeded: usize = 0,
        supervision_denied: usize = 0,
        run_interrupted: usize = 0,
        receipt_recorded: usize = 0,
        run_completed: usize = 0,
        run_failed: usize = 0,
    };
};

pub const Timeline = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event) = .empty,

    pub const Event = struct {
        format_version: u32 = world_timeline_event_format_version,
        fingerprint_version: u32 = world_timeline_event_fingerprint_version,
        event_fingerprint: u64,
        kind: EventKind,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        request_frame_fingerprint: ?u64 = null,
        response_frame_fingerprint: ?u64 = null,
        replay_key: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        branch_id: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        supervision_check_fingerprint: ?u64 = null,
        usage_ledger_fingerprint: ?u64 = null,
        run_receipt_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        blocker_tag: ?Supervision.Blocker = null,
        turn_index: usize = 0,
        status: ?ResponseStatus = null,

        pub fn init(args: struct {
            kind: EventKind,
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            request_frame_fingerprint: ?u64 = null,
            response_frame_fingerprint: ?u64 = null,
            replay_key: ?u64 = null,
            checkpoint_fingerprint: ?u64 = null,
            branch_id: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            supervision_check_fingerprint: ?u64 = null,
            usage_ledger_fingerprint: ?u64 = null,
            run_receipt_fingerprint: ?u64 = null,
            admission_receipt_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            target_match_fingerprint: ?u64 = null,
            blocker_tag: ?Supervision.Blocker = null,
            turn_index: usize = 0,
            status: ?ResponseStatus = null,
        }) @This() {
            var event = @This(){
                .event_fingerprint = 0,
                .kind = args.kind,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .request_frame_fingerprint = args.request_frame_fingerprint,
                .response_frame_fingerprint = args.response_frame_fingerprint,
                .replay_key = args.replay_key,
                .checkpoint_fingerprint = args.checkpoint_fingerprint,
                .branch_id = args.branch_id,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .supervision_check_fingerprint = args.supervision_check_fingerprint,
                .usage_ledger_fingerprint = args.usage_ledger_fingerprint,
                .run_receipt_fingerprint = args.run_receipt_fingerprint,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .target_match_fingerprint = args.target_match_fingerprint,
                .blocker_tag = args.blocker_tag,
                .turn_index = args.turn_index,
                .status = args.status,
            };
            event.event_fingerprint = fingerprintTimelineEvent(event);
            return event;
        }
    };

    pub const Checkpoint = struct {
        format_version: u32 = world_timeline_checkpoint_format_version,
        fingerprint_version: u32 = world_timeline_checkpoint_fingerprint_version,
        checkpoint_fingerprint: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        event_index: usize,
        turn_index: usize,
        current_request_fingerprint: ?u64 = null,
        last_response_fingerprint: ?u64 = null,
        capsule_image_fingerprint: ?u64 = null,
        transcript_prefix_fingerprint: u64,
        branch_id: u64,
        status: Status,

        pub const Status = enum {
            running,
            parked_on_port,
            completed,
            failed,
        };

        pub fn init(args: struct {
            world_surface_fingerprint: u64,
            target_certificate_fingerprint: u64,
            event_index: usize,
            turn_index: usize,
            current_request_fingerprint: ?u64 = null,
            last_response_fingerprint: ?u64 = null,
            capsule_image_fingerprint: ?u64 = null,
            transcript_prefix_fingerprint: u64,
            branch_id: u64 = 0,
            status: Status,
        }) @This() {
            var checkpoint = @This(){
                .checkpoint_fingerprint = 0,
                .world_surface_fingerprint = args.world_surface_fingerprint,
                .target_certificate_fingerprint = args.target_certificate_fingerprint,
                .event_index = args.event_index,
                .turn_index = args.turn_index,
                .current_request_fingerprint = args.current_request_fingerprint,
                .last_response_fingerprint = args.last_response_fingerprint,
                .capsule_image_fingerprint = args.capsule_image_fingerprint,
                .transcript_prefix_fingerprint = args.transcript_prefix_fingerprint,
                .branch_id = args.branch_id,
                .status = args.status,
            };
            checkpoint.checkpoint_fingerprint = fingerprintCheckpoint(checkpoint);
            return checkpoint;
        }
    };

    pub const Branch = struct {
        format_version: u32 = world_timeline_branch_format_version,
        fingerprint_version: u32 = world_timeline_branch_fingerprint_version,
        branch_id: u64,
        parent_branch_id: ?u64 = null,
        checkpoint_fingerprint: u64,
        branch_label: []const u8 = "",
        start_event_index: usize,
        final_event_index: ?usize = null,
        final_status: Checkpoint.Status = .running,
        event_count: usize = 0,
        response_count: usize = 0,

        pub fn fingerprint(self: @This()) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.timeline.branch.fingerprint");
            hashU64(&hasher, world_timeline_branch_fingerprint_version);
            hashU64(&hasher, self.branch_id);
            hashOptionalU64(&hasher, self.parent_branch_id);
            hashU64(&hasher, self.checkpoint_fingerprint);
            hashU64(&hasher, self.start_event_index);
            if (self.final_event_index) |index| {
                hashBool(&hasher, true);
                hashU64(&hasher, index);
            } else {
                hashBool(&hasher, false);
            }
            hashU64(&hasher, @intFromEnum(self.final_status));
            hashU64(&hasher, self.event_count);
            hashU64(&hasher, self.response_count);
            hashU64(&hasher, self.branch_label.len);
            hashBytes(&hasher, self.branch_label);
            return hasher.final();
        }
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *@This()) void {
        self.events.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn append(self: *@This(), event: Event) !void {
        try self.events.append(self.allocator, event);
    }
};

pub const TranscriptImage = struct {
    format_version: u32 = world_transcript_image_format_version,
    fingerprint_version: u32 = world_transcript_image_fingerprint_version,
    transcript_image_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    events: []EventImage,
    final_status: FinalStatus,
    response_count: usize = 0,
    replay_cursor: usize = 0,
    replay_limit: ?usize = null,

    pub const FinalStatus = enum {
        running,
        completed,
        failed,
    };

    pub const EventImage = struct {
        event_fingerprint: u64,
        kind: EventKind,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: ?u32 = null,
        request_fingerprint: ?u64 = null,
        response_fingerprint: ?u64 = null,
        response_kind: ?ResponseKind = null,
        replay_key: ?u64 = null,
        admission_request_fingerprint: ?u64 = null,
        admission_report_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        turn_index: ?usize = null,
        residual_site_index: ?usize = null,
        residual_site_fingerprint: ?u64 = null,
        status: ?ResponseStatus = null,
        source_run: bool = true,
        request_frame: ?Frame.Request = null,
        response_frame: ?Frame.Response = null,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.request_frame) |*frame| frame.deinit(allocator);
            if (self.response_frame) |*frame| frame.deinit(allocator);
            self.* = undefined;
        }
    };

    pub fn fromTranscript(allocator: std.mem.Allocator, transcript: *const Transcript, policy: ValuePolicy) !@This() {
        const events = try allocator.alloc(EventImage, transcript.events.items.len);
        errdefer allocator.free(events);
        var initialized: usize = 0;
        errdefer {
            for (events[0..initialized]) |*event| event.deinit(allocator);
        }
        var response_count: usize = 0;
        for (transcript.events.items, 0..) |event, index| {
            events[index] = try eventImageFromTranscriptEvent(allocator, event, policy);
            initialized += 1;
            if (events[index].response_frame != null) response_count += 1;
        }
        const world_surface_fingerprint = if (events.len > 0) events[0].world_surface_fingerprint else 0;
        const target_certificate_fingerprint = if (events.len > 0) events[0].target_certificate_fingerprint else 0;
        for (events) |event| {
            if (event.world_surface_fingerprint != world_surface_fingerprint) return error.SurfaceMismatch;
            if (event.target_certificate_fingerprint != target_certificate_fingerprint) return error.TargetCertificateMismatch;
        }
        var image = @This(){
            .transcript_image_fingerprint = 0,
            .world_surface_fingerprint = world_surface_fingerprint,
            .target_certificate_fingerprint = target_certificate_fingerprint,
            .events = events,
            .final_status = finalStatusFromEvents(events),
            .response_count = response_count,
        };
        image.transcript_image_fingerprint = fingerprintTranscriptImage(image);
        return image;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
        self.* = undefined;
    }

    pub fn resetReplay(self: *@This()) void {
        self.replay_cursor = 0;
        self.replay_limit = null;
    }

    pub fn validateReplayRun(self: *@This(), expected_world_surface_fingerprint: u64, expected_target_certificate_fingerprint: u64) !void {
        if (self.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
        if (self.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
        var active_start: ?usize = null;
        var selected_start: ?usize = null;
        var selected_limit: ?usize = null;
        var active_is_source_run = false;
        var active_has_port_event = false;
        var active_has_source_response = false;
        var latest_run_failed = false;
        for (self.events, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_has_port_event = false;
                    active_has_source_response = false;
                    latest_run_failed = true;
                },
                .run_completed => {
                    const start = active_start orelse continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    if (active_is_source_run and (!active_has_port_event or active_has_source_response)) {
                        selected_start = start;
                        selected_limit = index;
                    }
                    active_start = null;
                    latest_run_failed = false;
                },
                .run_failed => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    const failed_source_run = active_is_source_run;
                    active_start = null;
                    active_is_source_run = false;
                    if (failed_source_run) {
                        selected_start = null;
                        selected_limit = null;
                    }
                    latest_run_failed = failed_source_run;
                },
                .port_responded,
                .port_replayed,
                .frame_responded,
                .frame_replayed,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
                .permit_issued,
                .admission_requested,
                .admission_accepted,
                .admission_rejected,
                .module_matched_target,
                .supervision_check,
                .budget_exceeded,
                .supervision_denied,
                .run_interrupted,
                .receipt_recorded,
                => {},
            }
        }
        if (active_start != null or latest_run_failed) return error.ReplayMissing;
        self.replay_cursor = (selected_start orelse return error.ReplayMissing) + 1;
        self.replay_limit = selected_limit orelse return error.ReplayMissing;
    }

    pub fn prepareReplayPrefixForPendingRequest(
        self: *@This(),
        expected_world_surface_fingerprint: u64,
        expected_target_certificate_fingerprint: u64,
        pending_request_frame_fingerprint: u64,
    ) !void {
        if (self.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
        if (self.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
        var active_start: ?usize = null;
        var active_is_source_run = false;
        var active_pending_index: ?usize = null;
        var active_pending_fingerprint: ?u64 = null;
        for (self.events, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_pending_index = null;
                    active_pending_fingerprint = null;
                },
                .run_completed,
                .run_failed,
                => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = null;
                    active_is_source_run = false;
                    active_pending_index = null;
                    active_pending_fingerprint = null;
                },
                .port_requested,
                .frame_requested,
                => {
                    _ = active_start orelse continue;
                    if (!active_is_source_run) continue;
                    const request_frame = event.request_frame orelse return error.ReplayMissing;
                    active_pending_index = index;
                    active_pending_fingerprint = request_frame.frame_fingerprint;
                },
                .port_responded,
                .port_replayed,
                .port_rejected,
                .port_failed,
                .frame_responded,
                .frame_replayed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null and active_is_source_run) {
                        active_pending_index = null;
                        active_pending_fingerprint = null;
                    }
                },
                else => {},
            }
        }
        const start = active_start orelse return error.ReplayMissing;
        const pending_index = active_pending_index orelse return error.ReplayMissing;
        if ((active_pending_fingerprint orelse return error.ReplayMissing) != pending_request_frame_fingerprint) return error.ReplayMissing;
        self.replay_cursor = start + 1;
        self.replay_limit = pending_index;
    }

    pub fn prepareReplayPrefixForInterruptedRun(
        self: *@This(),
        expected_world_surface_fingerprint: u64,
        expected_target_certificate_fingerprint: u64,
    ) !void {
        if (self.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
        if (self.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
        var active_start: ?usize = null;
        var active_is_source_run = false;
        var active_pending_request = false;
        var active_has_source_response = false;
        for (self.events, 0..) |event, index| {
            switch (event.kind) {
                .run_started => {
                    if (active_start != null) return error.ReplayMissing;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = index;
                    active_is_source_run = event.source_run;
                    active_pending_request = false;
                    active_has_source_response = false;
                },
                .run_completed,
                .run_failed,
                => {
                    if (active_start == null) continue;
                    if (event.world_surface_fingerprint != expected_world_surface_fingerprint) return error.ReplaySurfaceMismatch;
                    if (event.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
                    active_start = null;
                    active_is_source_run = false;
                    active_pending_request = false;
                    active_has_source_response = false;
                },
                .port_requested,
                .frame_requested,
                => {
                    _ = active_start orelse continue;
                    if (!active_is_source_run) continue;
                    _ = event.request_frame orelse return error.ReplayMissing;
                    active_pending_request = true;
                },
                .port_responded,
                .port_replayed,
                .frame_responded,
                .frame_replayed,
                => {
                    if (active_start != null and active_is_source_run) {
                        _ = event.response_frame orelse return error.ReplayMissing;
                        active_pending_request = false;
                        active_has_source_response = true;
                    }
                },
                .port_rejected,
                .port_failed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null and active_is_source_run) active_pending_request = false;
                },
                else => {},
            }
        }
        const start = active_start orelse return error.ReplayMissing;
        if (!active_is_source_run or active_pending_request or !active_has_source_response) return error.ReplayMissing;
        self.replay_cursor = start + 1;
        self.replay_limit = self.events.len;
    }

    pub fn validateValuePolicy(self: *const @This(), policy: ValuePolicy) !void {
        for (self.events) |event| {
            if (event.request_frame) |frame| try validateRequestFramePolicy(frame, policy);
            if (event.response_frame) |frame| try validateResponseFramePolicy(frame, policy);
        }
    }

    pub fn nextResponse(
        self: *@This(),
        key: ReplayKeySeed,
        expected_target_certificate_fingerprint: u64,
        expected_response_kind: ResponseKind,
    ) !*const Frame.Response {
        const replay_limit = self.replay_limit orelse self.events.len;
        while (self.replay_cursor < replay_limit) : (self.replay_cursor += 1) {
            const index = self.replay_cursor;
            const event = &self.events[index];
            if (!eventKindIsSourceResponse(event.kind)) continue;
            const frame = if (event.response_frame) |*response_frame| response_frame else return error.ReplayMissing;
            if (frame.status != .responded) return error.ReplayMissing;
            if (frame.world_surface_fingerprint != key.world_surface_fingerprint) return error.ReplaySurfaceMismatch;
            if (frame.target_certificate_fingerprint != expected_target_certificate_fingerprint) return error.ReplayTargetCertificateMismatch;
            if (frame.world_port_id != key.world_port_id) return error.ReplayPortMismatch;
            if (frame.request_fingerprint != key.request_fingerprint) return error.ReplayRequestFingerprintMismatch;
            if (frame.response_kind != expected_response_kind) return error.ReplayResponseKindMismatch;
            const expected_key = key.withResponse(frame.response_fingerprint).fingerprint();
            if (frame.replay_key != expected_key) return error.ReplayMissing;
            self.replay_cursor = index + 1;
            return frame;
        }
        return error.ReplayMissing;
    }

    pub fn assertReplayComplete(self: *const @This()) !void {
        const replay_limit = self.replay_limit orelse self.events.len;
        var index = self.replay_cursor;
        while (index < replay_limit) : (index += 1) {
            if (eventKindIsSourceResponse(self.events[index].kind)) return error.ReplayUnusedEvent;
        }
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try writeU32(&out, allocator, self.format_version);
        try writeU32(&out, allocator, self.fingerprint_version);
        try writeU64(&out, allocator, self.transcript_image_fingerprint);
        try writeU64(&out, allocator, self.world_surface_fingerprint);
        try writeU64(&out, allocator, self.target_certificate_fingerprint);
        try writeU8(&out, allocator, @intFromEnum(self.final_status));
        try writeU64(&out, allocator, self.response_count);
        try writeU64(&out, allocator, self.events.len);
        for (self.events) |event| try encodeTranscriptEventImage(&out, allocator, event, self.format_version);
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        var cursor: usize = 0;
        const format_version = try readU32(bytes, &cursor);
        if (format_version != 2 and format_version != world_transcript_image_format_version) return error.InvalidFrameEncoding;
        const fingerprint_version = try readU32(bytes, &cursor);
        if (fingerprint_version != world_transcript_image_fingerprint_version) return error.InvalidFrameEncoding;
        const transcript_image_fingerprint = try readU64(bytes, &cursor);
        const world_surface_fingerprint = try readU64(bytes, &cursor);
        const target_certificate_fingerprint = try readU64(bytes, &cursor);
        const final_status = try enumFromByte(FinalStatus, try readU8(bytes, &cursor));
        const response_count = try readU64AsUsize(bytes, &cursor);
        const event_count = try readU64AsUsize(bytes, &cursor);
        const min_event_len = if (format_version == 2) world_min_transcript_event_image_encoded_len_v2 else world_min_transcript_event_image_encoded_len;
        if (event_count > (bytes.len - cursor) / min_event_len) return error.InvalidFrameEncoding;
        const events = try allocator.alloc(EventImage, event_count);
        errdefer allocator.free(events);
        var initialized: usize = 0;
        errdefer for (events[0..initialized]) |*event| event.deinit(allocator);
        for (events) |*event| {
            event.* = try decodeTranscriptEventImage(allocator, bytes, &cursor, format_version);
            initialized += 1;
        }
        if (cursor != bytes.len) return error.InvalidFrameEncoding;
        var decoded_response_count: usize = 0;
        for (events) |event| {
            if (event.world_surface_fingerprint != world_surface_fingerprint) return error.InvalidFrameEncoding;
            if (event.target_certificate_fingerprint != target_certificate_fingerprint) return error.InvalidFrameEncoding;
            if (event.response_frame != null) decoded_response_count += 1;
        }
        if (world_surface_fingerprint != (if (events.len > 0) events[0].world_surface_fingerprint else 0)) return error.InvalidFrameEncoding;
        if (target_certificate_fingerprint != (if (events.len > 0) events[0].target_certificate_fingerprint else 0)) return error.InvalidFrameEncoding;
        if (decoded_response_count != response_count) return error.InvalidFrameEncoding;
        if (finalStatusFromEvents(events) != final_status) return error.InvalidFrameEncoding;
        const image = @This(){
            .format_version = format_version,
            .transcript_image_fingerprint = transcript_image_fingerprint,
            .world_surface_fingerprint = world_surface_fingerprint,
            .target_certificate_fingerprint = target_certificate_fingerprint,
            .events = events,
            .final_status = final_status,
            .response_count = response_count,
        };
        if (fingerprintTranscriptImage(image) != transcript_image_fingerprint) return error.InvalidFrameEncoding;
        return image;
    }
};

const TranscriptRunStateEvidence = struct {
    turn_index: usize = 0,
    final_response_fingerprint: ?u64 = null,
    final_value_image_fingerprint: ?u64 = null,
};

fn runStateEvidenceFromTranscriptImage(image: TranscriptImage) TranscriptRunStateEvidence {
    var evidence: TranscriptRunStateEvidence = .{};
    var index = image.replay_cursor;
    const limit = image.replay_limit orelse image.events.len;
    while (index < limit) : (index += 1) {
        const event = image.events[index];
        if (event.turn_index) |turn_index| evidence.turn_index = @max(evidence.turn_index, turn_index);
        if (eventKindIsSourceResponse(event.kind)) {
            if (event.response_frame) |response| {
                if (response.status != .responded) continue;
                evidence.final_response_fingerprint = response.frame_fingerprint;
                evidence.final_value_image_fingerprint = response.response_value_fingerprint;
            } else if (event.response_fingerprint) |fingerprint| {
                evidence.final_response_fingerprint = fingerprint;
            }
            if (event.turn_index) |turn_index| evidence.turn_index = @max(evidence.turn_index, turn_index +| 1);
        }
    }
    return evidence;
}

fn runStateWithTranscriptEvidence(state: RunState, image: TranscriptImage) RunState {
    const evidence = runStateEvidenceFromTranscriptImage(image);
    return RunState.init(.{
        .target_ref_fingerprint = state.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = state.branch_id,
        .checkpoint_fingerprint = state.checkpoint_fingerprint,
        .pending_request_fingerprint = state.pending_request_fingerprint,
        .final_response_fingerprint = evidence.final_response_fingerprint orelse state.final_response_fingerprint,
        .final_value_image_fingerprint = evidence.final_value_image_fingerprint orelse state.final_value_image_fingerprint,
        .turn_index = @max(state.turn_index, evidence.turn_index),
        .status = state.status,
    });
}

fn runStateWithBranch(state: RunState, branch_id: u64) RunState {
    return RunState.init(.{
        .target_ref_fingerprint = state.target_ref_fingerprint,
        .transcript_image_fingerprint = state.transcript_image_fingerprint,
        .branch_id = branch_id,
        .checkpoint_fingerprint = state.checkpoint_fingerprint,
        .pending_request_fingerprint = state.pending_request_fingerprint,
        .final_response_fingerprint = state.final_response_fingerprint,
        .final_value_image_fingerprint = state.final_value_image_fingerprint,
        .turn_index = state.turn_index,
        .status = state.status,
    });
}

fn runImageContainsBranch(image: RunImage, branch_id: u64) bool {
    for (image.branches) |branch| {
        if (branch.branch_id == branch_id) return true;
    }
    return false;
}

fn runImageContainsCheckpoint(image: RunImage, checkpoint_ref: u64) bool {
    for (image.checkpoints) |checkpoint| {
        if (checkpoint.checkpoint_fingerprint == checkpoint_ref) return true;
    }
    return false;
}

fn applySelectedBranchToRunImage(image: *RunImage, selected_branch_id: ?u64) !void {
    const branch_id = selected_branch_id orelse return;
    if (!runImageContainsBranch(image.*, branch_id)) return error.HandoffCheckpointMismatch;
    if (image.current_state.branch_id != 0 and image.current_state.branch_id != branch_id) return error.HandoffCheckpointMismatch;
    if (image.current_state.branch_id == branch_id) return;
    image.current_state = runStateWithBranch(image.current_state, branch_id);
    refreshRunImageFingerprint(image);
    try image.validate(.{});
}

pub const AuditReport = struct {
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    mode: Mode,
    final_status: Status = .running,
    port_request_count: usize = 0,
    fresh_response_count: usize = 0,
    replayed_response_count: usize = 0,
    rejected_count: usize = 0,
    failed_count: usize = 0,
    missing_handler_count: usize = 0,
    replay_mismatch_count: usize = 0,
    per_port_counts: []usize = &.{},

    pub const Status = enum {
        running,
        completed,
        failed,
        parked,
    };
};

pub const AuditImage = struct {
    format_version: u32 = world_audit_image_format_version,
    fingerprint_version: u32 = world_audit_image_fingerprint_version,
    audit_fingerprint: u64,
    world_surface_fingerprint: u64,
    target_certificate_fingerprint: u64,
    mode: Mode,
    final_status: AuditReport.Status,
    request_frame_count: usize = 0,
    response_frame_count: usize = 0,
    replayed_frame_count: usize = 0,
    verified_frame_count: usize = 0,
    failed_frame_count: usize = 0,
    branch_count: usize = 0,
    checkpoint_count: usize = 0,
    missing_portable_value_image_count: usize = 0,
    native_only_value_count: usize = 0,
    transcript_image_fingerprint: ?u64 = null,

    pub fn fromReport(report: AuditReport, transcript_image: ?TranscriptImage) @This() {
        var image = @This(){
            .audit_fingerprint = 0,
            .world_surface_fingerprint = report.world_surface_fingerprint,
            .target_certificate_fingerprint = report.target_certificate_fingerprint,
            .mode = report.mode,
            .final_status = report.final_status,
            .transcript_image_fingerprint = if (transcript_image) |image_source| image_source.transcript_image_fingerprint else null,
        };
        if (transcript_image) |image_source| {
            for (image_source.events) |event| {
                if ((event.kind == .port_requested or event.kind == .frame_requested) and event.request_frame != null) {
                    image.request_frame_count += 1;
                }
                if (eventKindAllowsResponseFrame(event.kind)) {
                    if (event.response_frame) |frame| {
                        image.response_frame_count += 1;
                        if (frame.status == .failed) image.failed_frame_count += 1;
                    }
                }
                if (event.kind == .frame_verified) image.verified_frame_count += 1;
                if (event.kind == .checkpoint_recorded) image.checkpoint_count += 1;
                if (event.kind == .branch_started) image.branch_count += 1;
                if (event.response_frame != null and event.response_frame.?.status == .responded and event.response_frame.?.response_image == null) {
                    if (event.response_frame.?.response_value_fingerprint == null) {
                        image.native_only_value_count += 1;
                    } else {
                        image.missing_portable_value_image_count += 1;
                    }
                }
            }
            image.replayed_frame_count = report.replayed_response_count;
        } else {
            image.request_frame_count = report.port_request_count;
            image.response_frame_count = report.fresh_response_count + report.replayed_response_count;
            image.replayed_frame_count = report.replayed_response_count;
            image.failed_frame_count = report.failed_count;
        }
        image.audit_fingerprint = fingerprintAuditImage(image);
        return image;
    }
};

pub const RunState = struct {
    run_state_fingerprint: u64,
    target_ref_fingerprint: u64,
    transcript_image_fingerprint: ?u64 = null,
    branch_id: u64 = 0,
    checkpoint_fingerprint: ?u64 = null,
    pending_request_fingerprint: ?u64 = null,
    final_response_fingerprint: ?u64 = null,
    final_value_image_fingerprint: ?u64 = null,
    turn_index: usize = 0,
    status: Status = .not_started,

    pub const Status = enum {
        not_started,
        running,
        parked_on_port,
        completed,
        failed,
        parked_on_supervision,
    };

    pub fn init(args: struct {
        target_ref_fingerprint: u64,
        transcript_image_fingerprint: ?u64 = null,
        branch_id: u64 = 0,
        checkpoint_fingerprint: ?u64 = null,
        pending_request_fingerprint: ?u64 = null,
        final_response_fingerprint: ?u64 = null,
        final_value_image_fingerprint: ?u64 = null,
        turn_index: usize = 0,
        status: Status = .not_started,
    }) @This() {
        var result = @This(){
            .run_state_fingerprint = 0,
            .target_ref_fingerprint = args.target_ref_fingerprint,
            .transcript_image_fingerprint = args.transcript_image_fingerprint,
            .branch_id = args.branch_id,
            .checkpoint_fingerprint = args.checkpoint_fingerprint,
            .pending_request_fingerprint = args.pending_request_fingerprint,
            .final_response_fingerprint = args.final_response_fingerprint,
            .final_value_image_fingerprint = args.final_value_image_fingerprint,
            .turn_index = args.turn_index,
            .status = args.status,
        };
        result.run_state_fingerprint = fingerprintRunState(result);
        return result;
    }
};

pub const RunImage = struct {
    format_version: u32 = world_run_image_format_version,
    fingerprint_version: u32 = world_run_image_fingerprint_version,
    run_image_fingerprint: u64,
    kind: Kind,
    target_ref: TargetRef,
    owns_target_ref_bytes: bool = false,
    import_set_fingerprint: u64,
    transcript_image: ?TranscriptImage = null,
    owns_transcript_image: bool = false,
    current_state: RunState,
    checkpoints: []const Timeline.Checkpoint = &.{},
    branches: []Timeline.Branch = &.{},
    owns_checkpoints: bool = false,
    owns_branches: bool = false,
    owns_branch_labels: bool = false,
    pending_request_frame: ?Frame.Request = null,
    owns_pending_request_frame: bool = false,
    final_result_image: ?Frame.ValueImage = null,
    owns_final_result_image: bool = false,
    environment_certificate_fingerprint: ?u64 = null,
    acceptance_report_fingerprint: ?u64 = null,
    audit_image_fingerprint: ?u64 = null,
    prior_run_permit_fingerprint: ?u64 = null,
    prior_run_receipt_fingerprint: ?u64 = null,
    module_ref_fingerprint: ?u64 = null,
    boundary_module_fingerprint: ?u64 = null,
    module_image_fingerprint: ?u64 = null,
    metadata: []const u8 = "",
    owns_metadata: bool = false,

    pub const Kind = enum {
        reference_target_run,
        full_target_run,
        replay_only_run,
        parked_run,
        completed_run,
        branched_run,
    };

    pub const ValidateOptions = struct {
        max_image_bytes: usize = world_max_decoded_byte_field_len,
        max_timeline_events: usize = 1_000_000,
        max_branches: usize = 4096,
        max_checkpoints: usize = 4096,
        require_portable_values: bool = false,
        allow_reference_target: bool = true,
        require_known_target: bool = false,
    };

    pub fn init(args: struct {
        kind: Kind,
        target_ref: TargetRef,
        import_set_fingerprint: u64,
        transcript_image: ?TranscriptImage = null,
        current_state: RunState,
        checkpoints: []const Timeline.Checkpoint = &.{},
        branches: []Timeline.Branch = &.{},
        pending_request_frame: ?Frame.Request = null,
        final_result_image: ?Frame.ValueImage = null,
        environment_certificate_fingerprint: ?u64 = null,
        acceptance_report_fingerprint: ?u64 = null,
        audit_image_fingerprint: ?u64 = null,
        prior_run_permit_fingerprint: ?u64 = null,
        prior_run_receipt_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        boundary_module_fingerprint: ?u64 = null,
        module_image_fingerprint: ?u64 = null,
        metadata: []const u8 = "",
    }) @This() {
        var result = @This(){
            .run_image_fingerprint = 0,
            .kind = args.kind,
            .target_ref = args.target_ref,
            .import_set_fingerprint = args.import_set_fingerprint,
            .transcript_image = args.transcript_image,
            .current_state = args.current_state,
            .checkpoints = args.checkpoints,
            .branches = args.branches,
            .pending_request_frame = args.pending_request_frame,
            .final_result_image = args.final_result_image,
            .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
            .acceptance_report_fingerprint = args.acceptance_report_fingerprint,
            .audit_image_fingerprint = args.audit_image_fingerprint,
            .prior_run_permit_fingerprint = args.prior_run_permit_fingerprint,
            .prior_run_receipt_fingerprint = args.prior_run_receipt_fingerprint,
            .module_ref_fingerprint = args.module_ref_fingerprint,
            .boundary_module_fingerprint = args.boundary_module_fingerprint,
            .module_image_fingerprint = args.module_image_fingerprint,
            .metadata = args.metadata,
        };
        if (result.hasModuleWitness()) {
            result.format_version = world_run_image_format_version;
        }
        if (result.format_version >= 3) {
            result.run_image_fingerprint = fingerprintRunImageV3(result);
        } else {
            result.run_image_fingerprint = fingerprintRunImage(result);
        }
        return result;
    }

    fn hasModuleWitness(self: @This()) bool {
        return self.module_ref_fingerprint != null or
            self.boundary_module_fingerprint != null or
            self.module_image_fingerprint != null;
    }

    pub fn withModuleRef(self: @This(), module_ref: Admission.ModuleRef, module_image_fingerprint: ?u64) @This() {
        var result = self;
        result.owns_target_ref_bytes = false;
        result.owns_transcript_image = false;
        result.owns_checkpoints = false;
        result.owns_branches = false;
        result.owns_branch_labels = false;
        result.owns_pending_request_frame = false;
        result.owns_final_result_image = false;
        result.owns_metadata = false;
        result.format_version = world_run_image_format_version;
        result.module_ref_fingerprint = module_ref.module_ref_fingerprint;
        result.boundary_module_fingerprint = module_ref.boundary_module_fingerprint;
        result.module_image_fingerprint = module_image_fingerprint;
        result.run_image_fingerprint = fingerprintRunImageV3(result);
        return result;
    }

    pub fn fromTranscriptImage(comptime Target: type, image: TranscriptImage, kind: Kind) @This() {
        const target_ref = TargetRef.fromTarget(Target);
        const import_set = ImportSet.fromTarget(Target);
        const transcript_state = runStateEvidenceFromTranscriptImage(image);
        const state = RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .transcript_image_fingerprint = image.transcript_image_fingerprint,
            .final_response_fingerprint = transcript_state.final_response_fingerprint,
            .final_value_image_fingerprint = transcript_state.final_value_image_fingerprint,
            .turn_index = transcript_state.turn_index,
            .status = switch (image.final_status) {
                .running => .running,
                .completed => .completed,
                .failed => .failed,
            },
        });
        return init(.{
            .kind = kind,
            .target_ref = target_ref,
            .import_set_fingerprint = import_set.import_set_fingerprint,
            .transcript_image = image,
            .current_state = state,
        });
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owns_target_ref_bytes) {
            if (self.target_ref.target_label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(self.target_ref.metadata));
        }
        if (self.owns_transcript_image) {
            if (self.transcript_image) |*image| image.deinit(allocator);
        }
        if (self.owns_pending_request_frame) {
            if (self.pending_request_frame) |*frame| frame.deinit(allocator);
        }
        if (self.owns_final_result_image) {
            if (self.final_result_image) |*image| image.deinit(allocator);
        }
        if (self.owns_checkpoints) allocator.free(self.checkpoints);
        if (self.owns_branch_labels) {
            for (self.branches) |branch| allocator.free(@constCast(branch.branch_label));
        }
        if (self.owns_branches) allocator.free(self.branches);
        if (self.owns_metadata) allocator.free(@constCast(self.metadata));
        self.* = undefined;
    }

    pub fn validate(self: @This(), options: ValidateOptions) !void {
        if (!isSupportedRunImageFormatVersion(self.format_version)) return error.InvalidFrameEncoding;
        if (self.fingerprint_version != world_run_image_fingerprint_version) return error.InvalidFrameEncoding;
        try validateTargetRef(self.target_ref);
        if (!options.allow_reference_target and self.kind == .reference_target_run) return error.InvalidFrameEncoding;
        if (options.require_known_target and self.kind == .reference_target_run) return error.InvalidFrameEncoding;
        if (self.metadata.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        if (self.target_ref.target_label) |label| {
            if (label.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        }
        if (self.target_ref.metadata.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        if (self.module_ref_fingerprint != null and self.format_version < 3) return error.InvalidFrameEncoding;
        if (self.boundary_module_fingerprint != null and self.format_version < 3) return error.InvalidFrameEncoding;
        if (self.module_image_fingerprint != null and self.format_version < 3) return error.InvalidFrameEncoding;
        if (self.checkpoints.len > options.max_checkpoints) return error.InvalidFrameEncoding;
        if (self.branches.len > options.max_branches) return error.InvalidFrameEncoding;
        const value_policy = valuePolicyForRunImageValidation(options);
        if (self.transcript_image) |image| {
            if (image.events.len > options.max_timeline_events) return error.InvalidFrameEncoding;
            if (image.world_surface_fingerprint != self.target_ref.world_surface_fingerprint) return error.TranscriptImageSurfaceMismatch;
            if (image.target_certificate_fingerprint != self.target_ref.target_certificate_fingerprint) return error.TargetCertificateMismatch;
            if (self.current_state.transcript_image_fingerprint != image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
            switch (image.final_status) {
                .completed => if (self.current_state.status != .completed) return error.HandoffTargetMismatch,
                .failed => if (self.current_state.status != .failed) return error.HandoffTargetMismatch,
                .running => if (self.current_state.status != .running and self.current_state.status != .parked_on_port and self.current_state.status != .parked_on_supervision) return error.HandoffTargetMismatch,
            }
            try image.validateValuePolicy(value_policy);
        }
        try validateRunImageKindState(self);
        if (self.current_state.target_ref_fingerprint != self.target_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
        if (self.current_state.checkpoint_fingerprint) |checkpoint_fingerprint| {
            var found_checkpoint = false;
            for (self.checkpoints) |checkpoint| {
                if (checkpoint.checkpoint_fingerprint == checkpoint_fingerprint) {
                    found_checkpoint = true;
                    break;
                }
            }
            if (!found_checkpoint and (self.kind == .branched_run or self.checkpoints.len != 0)) return error.HandoffCheckpointMismatch;
        }
        for (self.checkpoints) |checkpoint| {
            if (checkpoint.world_surface_fingerprint != self.target_ref.world_surface_fingerprint) return error.HandoffCheckpointMismatch;
            if (checkpoint.target_certificate_fingerprint != self.target_ref.target_certificate_fingerprint) return error.HandoffCheckpointMismatch;
        }
        if (self.kind == .branched_run and self.current_state.branch_id != 0) {
            var found_branch = false;
            for (self.branches) |branch| {
                if (branch.branch_id == self.current_state.branch_id) {
                    found_branch = true;
                    break;
                }
            }
            if (!found_branch) return error.HandoffCheckpointMismatch;
        }
        for (self.branches) |branch| {
            if (branch.branch_label.len > options.max_image_bytes) return error.InvalidFrameEncoding;
            var found_checkpoint = false;
            for (self.checkpoints) |checkpoint| {
                if (checkpoint.checkpoint_fingerprint == branch.checkpoint_fingerprint) {
                    found_checkpoint = true;
                    break;
                }
            }
            if (!found_checkpoint) return error.HandoffCheckpointMismatch;
        }
        if (self.current_state.status == .parked_on_port and self.pending_request_frame == null) return error.HandoffPendingFrameMismatch;
        if (self.pending_request_frame) |frame| {
            try validateRequestFrameImage(frame);
            try validateRequestFramePolicy(frame, value_policy);
            if (frame.world_surface_fingerprint != self.target_ref.world_surface_fingerprint) return error.FrameSurfaceMismatch;
            if (frame.target_certificate_fingerprint != self.target_ref.target_certificate_fingerprint) return error.FrameTargetCertificateMismatch;
            if (self.current_state.status == .parked_on_port) {
                const fingerprint = self.current_state.pending_request_fingerprint orelse return error.HandoffPendingFrameMismatch;
                if (frame.frame_fingerprint != fingerprint) return error.HandoffPendingFrameMismatch;
                if (frame.turn_index != self.current_state.turn_index) return error.HandoffPendingFrameMismatch;
            } else if (self.current_state.pending_request_fingerprint) |fingerprint| {
                if (frame.frame_fingerprint != fingerprint) return error.HandoffPendingFrameMismatch;
            }
        }
        if (self.final_result_image) |image| {
            try validateValueImage(image);
            try validateValueImagePolicy(image, value_policy);
            if (self.current_state.final_value_image_fingerprint != image.value_image_fingerprint) return error.InvalidFrameEncoding;
        }
        if (fingerprintRunState(self.current_state) != self.current_state.run_state_fingerprint) return error.InvalidFrameEncoding;
        const expected_run_image_fingerprint = if (self.format_version == 1) fingerprintRunImageV1(self) else if (self.format_version >= 3) fingerprintRunImageV3(self) else fingerprintRunImage(self);
        if (expected_run_image_fingerprint != self.run_image_fingerprint) return error.InvalidFrameEncoding;
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try writeU32(&out, allocator, self.format_version);
        try writeU32(&out, allocator, self.fingerprint_version);
        try writeU64(&out, allocator, self.run_image_fingerprint);
        try writeU8(&out, allocator, @intFromEnum(self.kind));
        try encodeTargetRef(&out, allocator, self.target_ref);
        try writeU64(&out, allocator, self.import_set_fingerprint);
        try encodeRunState(&out, allocator, self.current_state);
        try writeOptionalU64(&out, allocator, if (self.transcript_image) |image| image.transcript_image_fingerprint else null);
        if (self.transcript_image) |image| {
            try writeBool(&out, allocator, true);
            const encoded = try image.encode(allocator);
            defer allocator.free(encoded);
            try writeBytes(&out, allocator, encoded);
        } else {
            try writeBool(&out, allocator, false);
        }
        try writeU64(&out, allocator, self.checkpoints.len);
        for (self.checkpoints) |checkpoint| encodeCheckpoint(&out, allocator, checkpoint) catch |err| return err;
        try writeU64(&out, allocator, self.branches.len);
        for (self.branches) |branch| encodeBranch(&out, allocator, branch) catch |err| return err;
        if (self.pending_request_frame) |frame| {
            try writeBool(&out, allocator, true);
            const encoded = try frame.encode(allocator);
            defer allocator.free(encoded);
            try writeBytes(&out, allocator, encoded);
        } else {
            try writeBool(&out, allocator, false);
        }
        try writeOptionalValueImage(&out, allocator, self.final_result_image);
        try writeOptionalU64(&out, allocator, self.environment_certificate_fingerprint);
        try writeOptionalU64(&out, allocator, self.acceptance_report_fingerprint);
        try writeOptionalU64(&out, allocator, self.audit_image_fingerprint);
        if (self.format_version >= 2) {
            try writeOptionalU64(&out, allocator, self.prior_run_permit_fingerprint);
            try writeOptionalU64(&out, allocator, self.prior_run_receipt_fingerprint);
        }
        if (self.format_version >= 3) {
            try writeOptionalU64(&out, allocator, self.module_ref_fingerprint);
            try writeOptionalU64(&out, allocator, self.boundary_module_fingerprint);
            try writeOptionalU64(&out, allocator, self.module_image_fingerprint);
        }
        try writeBytes(&out, allocator, self.metadata);
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        if (bytes.len > world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
        var cursor: usize = 0;
        const format_version = try readU32(bytes, &cursor);
        if (!isSupportedRunImageFormatVersion(format_version)) return error.InvalidFrameEncoding;
        const fingerprint_version = try readU32(bytes, &cursor);
        if (fingerprint_version != world_run_image_fingerprint_version) return error.InvalidFrameEncoding;
        const run_image_fingerprint = try readU64(bytes, &cursor);
        const kind = try enumFromByte(Kind, try readU8(bytes, &cursor));
        const target_ref = try decodeTargetRef(allocator, bytes, &cursor);
        errdefer {
            if (target_ref.target_label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(target_ref.metadata));
        }
        const import_set_fingerprint = try readU64(bytes, &cursor);
        const current_state = try decodeRunState(bytes, &cursor);
        const encoded_transcript_image_fingerprint = try readOptionalU64(bytes, &cursor);
        var transcript_image: ?TranscriptImage = null;
        if (try readBool(bytes, &cursor)) {
            const encoded = try readBytesOwned(allocator, bytes, &cursor);
            defer allocator.free(encoded);
            var decoded_transcript_image = try TranscriptImage.decode(allocator, encoded);
            errdefer decoded_transcript_image.deinit(allocator);
            if (encoded_transcript_image_fingerprint != decoded_transcript_image.transcript_image_fingerprint) return error.InvalidFrameEncoding;
            transcript_image = decoded_transcript_image;
        } else if (encoded_transcript_image_fingerprint != null) {
            return error.InvalidFrameEncoding;
        }
        errdefer if (transcript_image) |*image| image.deinit(allocator);
        const checkpoint_count = try readU64AsUsize(bytes, &cursor);
        if (checkpoint_count > (ValidateOptions{}).max_checkpoints) return error.InvalidFrameEncoding;
        if (checkpoint_count > (bytes.len - cursor) / 8) return error.InvalidFrameEncoding;
        const checkpoints = try allocator.alloc(Timeline.Checkpoint, checkpoint_count);
        errdefer allocator.free(checkpoints);
        for (checkpoints) |*checkpoint| checkpoint.* = try decodeCheckpoint(bytes, &cursor);
        const branch_count = try readU64AsUsize(bytes, &cursor);
        if (branch_count > (ValidateOptions{}).max_branches) return error.InvalidFrameEncoding;
        if (branch_count > (bytes.len - cursor) / 8) return error.InvalidFrameEncoding;
        const branches = try allocator.alloc(Timeline.Branch, branch_count);
        errdefer allocator.free(branches);
        var initialized_branches: usize = 0;
        errdefer for (branches[0..initialized_branches]) |branch| allocator.free(@constCast(branch.branch_label));
        for (branches) |*branch| {
            branch.* = try decodeBranch(allocator, bytes, &cursor);
            initialized_branches += 1;
        }
        var pending_request_frame: ?Frame.Request = null;
        if (try readBool(bytes, &cursor)) {
            const encoded = try readBytesOwned(allocator, bytes, &cursor);
            defer allocator.free(encoded);
            pending_request_frame = try Frame.Request.decode(allocator, encoded);
        }
        errdefer if (pending_request_frame) |*frame| frame.deinit(allocator);
        var final_result_image = try readOptionalValueImage(allocator, bytes, &cursor);
        errdefer if (final_result_image) |*image| image.deinit(allocator);
        const environment_certificate_fingerprint = try readOptionalU64(bytes, &cursor);
        const acceptance_report_fingerprint = try readOptionalU64(bytes, &cursor);
        const audit_image_fingerprint = try readOptionalU64(bytes, &cursor);
        const prior_run_permit_fingerprint = if (format_version >= 2) try readOptionalU64(bytes, &cursor) else null;
        const prior_run_receipt_fingerprint = if (format_version >= 2) try readOptionalU64(bytes, &cursor) else null;
        const module_ref_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, &cursor) else null;
        const boundary_module_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, &cursor) else null;
        const module_image_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, &cursor) else null;
        const metadata = try readBytesOwned(allocator, bytes, &cursor);
        errdefer allocator.free(metadata);
        if (cursor != bytes.len) return error.InvalidFrameEncoding;
        var result = @This(){
            .format_version = format_version,
            .run_image_fingerprint = run_image_fingerprint,
            .kind = kind,
            .target_ref = target_ref,
            .owns_target_ref_bytes = true,
            .import_set_fingerprint = import_set_fingerprint,
            .transcript_image = transcript_image,
            .owns_transcript_image = transcript_image != null,
            .current_state = current_state,
            .checkpoints = checkpoints,
            .branches = branches,
            .owns_checkpoints = true,
            .owns_branches = true,
            .owns_branch_labels = true,
            .pending_request_frame = pending_request_frame,
            .owns_pending_request_frame = pending_request_frame != null,
            .final_result_image = final_result_image,
            .owns_final_result_image = final_result_image != null,
            .environment_certificate_fingerprint = environment_certificate_fingerprint,
            .acceptance_report_fingerprint = acceptance_report_fingerprint,
            .audit_image_fingerprint = audit_image_fingerprint,
            .prior_run_permit_fingerprint = prior_run_permit_fingerprint,
            .prior_run_receipt_fingerprint = prior_run_receipt_fingerprint,
            .module_ref_fingerprint = module_ref_fingerprint,
            .boundary_module_fingerprint = boundary_module_fingerprint,
            .module_image_fingerprint = module_image_fingerprint,
            .metadata = metadata,
            .owns_metadata = true,
        };
        result.validate(.{}) catch |err| return err;
        transcript_image = null;
        pending_request_frame = null;
        final_result_image = null;
        return result;
    }
};

pub const RunHandle = struct {
    format_version: u32 = world_run_handle_format_version,
    fingerprint_version: u32 = world_run_handle_fingerprint_version,
    handle_fingerprint: u64,
    runspace_fingerprint: u64,
    local_run_id: u64,
    target_ref_fingerprint: u64,
    admission_receipt_fingerprint: ?u64 = null,
    permit_fingerprint: ?u64 = null,
    branch_id: ?u64 = null,
    generation: u64 = 0,

    pub fn init(args: struct {
        runspace_fingerprint: u64,
        local_run_id: u64,
        target_ref_fingerprint: u64,
        admission_receipt_fingerprint: ?u64 = null,
        permit_fingerprint: ?u64 = null,
        branch_id: ?u64 = null,
        generation: u64 = 0,
    }) @This() {
        var result = @This(){
            .handle_fingerprint = 0,
            .runspace_fingerprint = args.runspace_fingerprint,
            .local_run_id = args.local_run_id,
            .target_ref_fingerprint = args.target_ref_fingerprint,
            .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
            .permit_fingerprint = args.permit_fingerprint,
            .branch_id = args.branch_id,
            .generation = args.generation,
        };
        result.handle_fingerprint = fingerprintRunHandle(result);
        return result;
    }

    pub fn validate(self: @This()) !void {
        if (self.format_version != world_run_handle_format_version) return error.InvalidFrameEncoding;
        if (self.fingerprint_version != world_run_handle_fingerprint_version) return error.InvalidFrameEncoding;
        if (fingerprintRunHandle(self) != self.handle_fingerprint) return error.StaleRunHandle;
    }

    pub fn validateForRunspace(self: @This(), runspace_fingerprint: u64) !void {
        try self.validate();
        if (self.runspace_fingerprint != runspace_fingerprint) return error.StaleRunHandle;
    }

    pub fn matchesSlot(self: @This(), slot: Runspace.RunSlot) bool {
        return self.handle_fingerprint == slot.handle.handle_fingerprint and
            self.generation == slot.handle.generation and
            self.local_run_id == slot.handle.local_run_id and
            self.runspace_fingerprint == slot.handle.runspace_fingerprint;
    }
};

pub const Runspace = struct {
    allocator: std.mem.Allocator,
    config: Config,
    runspace_fingerprint: u64,
    next_run_id: u64 = 0,
    next_mailbox_id: u64 = 0,
    next_event_index: u64 = 0,
    slots: std.ArrayList(@This().RunSlot) = .empty,
    events: std.ArrayList(@This().RunspaceEvent) = .empty,
    mailbox: @This().Mailbox,

    pub const Policy = enum {
        deterministic,
    };

    pub const Config = struct {
        policy: Policy = .deterministic,
        max_runs: ?usize = null,
        max_pending_ports: ?usize = null,
        max_events: ?usize = null,
        preserve_completed_runs: bool = true,
        require_supervision: bool = false,
        require_admission: bool = false,
        allow_direct_target_install: bool = true,
        allow_handoff_install: bool = true,
        allow_replay_install: bool = true,
        auto_dispatch: bool = false,
    };

    pub const RunStatus = enum {
        admitted,
        runnable,
        running,
        parked_on_port,
        parked_on_supervision,
        completed,
        failed,
        exported,
        rejected,
    };

    pub const PendingStatus = enum {
        pending,
        responded,
        cancelled,
        exported,
        failed,
    };

    pub const EventKind = enum {
        run_installed,
        run_admitted,
        run_started,
        run_stepped,
        run_parked_on_port,
        run_parked_on_supervision,
        port_enqueued,
        port_responded,
        port_rejected,
        port_failed,
        run_resumed,
        run_completed,
        run_failed,
        run_exported,
        run_branch_created,
        checkpoint_created,
        handoff_created,
    };

    const DriverStep = union(enum) {
        done,
        port_request: Frame.Request,
        failed,
    };

    const ResponseEvidence = struct {
        response_fingerprint: u64,
        response_frame_fingerprint: ?u64 = null,
        response_value_image_fingerprint: ?u64 = null,
    };

    const SlotDriver = struct {
        ptr: *anyopaque,
        vtable: *const VTable,

        const VTable = struct {
            nextFrame: *const fn (*anyopaque) anyerror!DriverStep,
            resumeFrame: *const fn (*anyopaque, Frame.Response) anyerror!ResponseEvidence,
            beforeResponse: *const fn (*anyopaque, u32, ResponseStatus, usize, usize) anyerror!void,
            beforeTerminalResponse: *const fn (*anyopaque, u32, ResponseStatus, usize, usize) anyerror!void,
            resumeTerminalFrame: *const fn (*anyopaque, Frame.Response) anyerror!void,
            dispatch: *const fn (*anyopaque) anyerror!?ResponseEvidence,
            snapshotRunImage: *const fn (*anyopaque) anyerror!RunImage,
            beforeHandoffExport: *const fn (*anyopaque) anyerror!void,
            beforeInterruptedHandoffExport: *const fn (*anyopaque) anyerror!void,
            beforeCheckpoint: *const fn (*anyopaque, usize) anyerror!void,
            beforeBranch: *const fn (*anyopaque, usize) anyerror!void,
            cloneSupervisor: *const fn (*anyopaque, std.mem.Allocator) anyerror!?Supervision.Supervisor,
            restoreSupervisor: *const fn (*anyopaque, std.mem.Allocator, ?Supervision.Supervisor) void,
            hasSupervisor: *const fn (*anyopaque) bool,
            supervisorWarningCount: *const fn (*anyopaque) usize,
            supervisorBlockerCount: *const fn (*anyopaque) usize,
            supervisionInterrupted: *const fn (*anyopaque) bool,
            failed: *const fn (*anyopaque) bool,
            deinit: *const fn (*anyopaque, std.mem.Allocator) void,
        };

        fn nextFrame(self: @This()) !DriverStep {
            return self.vtable.nextFrame(self.ptr);
        }

        fn resumeFrame(self: @This(), response: Frame.Response) !ResponseEvidence {
            return self.vtable.resumeFrame(self.ptr, response);
        }

        fn beforeResponse(self: @This(), world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) !void {
            return self.vtable.beforeResponse(self.ptr, world_port_id, status, response_bytes, value_image_bytes);
        }

        fn beforeTerminalResponse(self: @This(), world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) !void {
            return self.vtable.beforeTerminalResponse(self.ptr, world_port_id, status, response_bytes, value_image_bytes);
        }

        fn resumeTerminalFrame(self: @This(), response: Frame.Response) !void {
            return self.vtable.resumeTerminalFrame(self.ptr, response);
        }

        fn dispatch(self: @This()) !?ResponseEvidence {
            return self.vtable.dispatch(self.ptr);
        }

        fn snapshotRunImage(self: @This()) !RunImage {
            return self.vtable.snapshotRunImage(self.ptr);
        }

        fn beforeHandoffExport(self: @This()) !void {
            return self.vtable.beforeHandoffExport(self.ptr);
        }

        fn beforeInterruptedHandoffExport(self: @This()) !void {
            return self.vtable.beforeInterruptedHandoffExport(self.ptr);
        }

        fn beforeCheckpoint(self: @This(), value_image_bytes: usize) !void {
            return self.vtable.beforeCheckpoint(self.ptr, value_image_bytes);
        }

        fn beforeBranch(self: @This(), depth: usize) !void {
            return self.vtable.beforeBranch(self.ptr, depth);
        }

        fn cloneSupervisor(self: @This(), allocator: std.mem.Allocator) !?Supervision.Supervisor {
            return self.vtable.cloneSupervisor(self.ptr, allocator);
        }

        fn restoreSupervisor(self: @This(), allocator: std.mem.Allocator, supervisor: ?Supervision.Supervisor) void {
            self.vtable.restoreSupervisor(self.ptr, allocator, supervisor);
        }

        fn hasSupervisor(self: @This()) bool {
            return self.vtable.hasSupervisor(self.ptr);
        }

        fn supervisorWarningCount(self: @This()) usize {
            return self.vtable.supervisorWarningCount(self.ptr);
        }

        fn supervisorBlockerCount(self: @This()) usize {
            return self.vtable.supervisorBlockerCount(self.ptr);
        }

        fn supervisionInterrupted(self: @This()) bool {
            return self.vtable.supervisionInterrupted(self.ptr);
        }

        fn failed(self: @This()) bool {
            return self.vtable.failed(self.ptr);
        }

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            self.vtable.deinit(self.ptr, allocator);
        }

        fn forRun(comptime RunType: type, run: *RunType) @This() {
            const Impl = struct {
                fn runNextFrame(ptr: *anyopaque) anyerror!DriverStep {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    const frame_step = try active.nextFrame();
                    return switch (frame_step) {
                        .done => |value| {
                            discardRunspaceDoneValue(RunType, active, value);
                            return .done;
                        },
                        .port_request => |request| .{ .port_request = request },
                        .failed => .failed,
                    };
                }

                fn discardRunspaceDoneValue(comptime ActiveRunType: type, active: *ActiveRunType, value: anytype) void {
                    if (@hasField(ActiveRunType, "done_value_present") and @hasField(ActiveRunType, "done_value") and @hasField(ActiveRunType, "allocator")) {
                        if (active.done_value_present) {
                            deinitRunValue(active.allocator, active.done_value);
                            active.done_value_present = false;
                            return;
                        }
                        deinitRunValue(active.allocator, value);
                    }
                }

                fn runResumeFrame(ptr: *anyopaque, response: Frame.Response) anyerror!ResponseEvidence {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "runspaceResumeFrame")) return active.runspaceResumeFrame(response);
                    try active.resumeFrame(response);
                    return .{
                        .response_fingerprint = response.response_fingerprint,
                        .response_frame_fingerprint = response.frame_fingerprint,
                        .response_value_image_fingerprint = response.response_value_fingerprint,
                    };
                }

                fn runBeforeResponse(ptr: *anyopaque, world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceResponse")) return active.beforeRunspaceResponse(world_port_id, status, response_bytes, value_image_bytes);
                }

                fn runBeforeTerminalResponse(ptr: *anyopaque, world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceTerminalResponse")) return active.beforeRunspaceTerminalResponse(world_port_id, status, response_bytes, value_image_bytes);
                }

                fn runResumeTerminalFrame(ptr: *anyopaque, response: Frame.Response) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "runspaceResumeTerminalFrame")) return active.runspaceResumeTerminalFrame(response);
                    return active.resumeFrame(response);
                }

                fn runDispatch(ptr: *anyopaque) anyerror!?ResponseEvidence {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "runspaceDispatch")) return active.runspaceDispatch();
                    try active.dispatch();
                    return null;
                }

                fn runSnapshotRunImage(ptr: *anyopaque) anyerror!RunImage {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    return active.snapshotRunImage();
                }

                fn runBeforeHandoffExport(ptr: *anyopaque) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceHandoffExport")) return active.beforeRunspaceHandoffExport();
                }

                fn runBeforeInterruptedHandoffExport(ptr: *anyopaque) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceInterruptedHandoffExport")) return active.beforeRunspaceInterruptedHandoffExport();
                    if (@hasDecl(RunType, "beforeRunspaceHandoffExport")) return active.beforeRunspaceHandoffExport();
                }

                fn runBeforeCheckpoint(ptr: *anyopaque, value_image_bytes: usize) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceCheckpoint")) return active.beforeRunspaceCheckpoint(value_image_bytes);
                }

                fn runBeforeBranch(ptr: *anyopaque, depth: usize) anyerror!void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasDecl(RunType, "beforeRunspaceBranch")) return active.beforeRunspaceBranch(depth);
                }

                fn runCloneSupervisor(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!?Supervision.Supervisor {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) {
                        if (active.supervisor) |supervisor| return try supervisor.clone(allocator);
                    }
                    return null;
                }

                fn runRestoreSupervisor(ptr: *anyopaque, allocator: std.mem.Allocator, supervisor: ?Supervision.Supervisor) void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) {
                        if (active.supervisor) |*current| current.deinit();
                        active.supervisor = supervisor;
                    } else if (supervisor) |owned| {
                        var mutable = owned;
                        mutable.deinit();
                    }
                    _ = allocator;
                }

                fn runHasSupervisor(ptr: *anyopaque) bool {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) return active.supervisor != null;
                    return false;
                }

                fn runSupervisorWarningCount(ptr: *anyopaque) usize {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) {
                        if (active.supervisor) |supervisor| return supervisor.warning_count;
                    }
                    return 0;
                }

                fn runSupervisorBlockerCount(ptr: *anyopaque) usize {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) {
                        if (active.supervisor) |supervisor| return if (supervisor.blocker == null) 0 else 1;
                    }
                    return 0;
                }

                fn runSupervisionInterrupted(ptr: *anyopaque) bool {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "supervisor")) {
                        if (active.supervisor) |*supervisor| return supervisor.interrupted;
                    }
                    return false;
                }

                fn runFailed(ptr: *anyopaque) bool {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    if (@hasField(RunType, "audit")) return active.audit.final_status == .failed;
                    return false;
                }

                fn runDeinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                    const active: *RunType = @ptrCast(@alignCast(ptr));
                    active.deinit();
                    allocator.destroy(active);
                }

                const vtable = VTable{
                    .nextFrame = runNextFrame,
                    .resumeFrame = runResumeFrame,
                    .beforeResponse = runBeforeResponse,
                    .beforeTerminalResponse = runBeforeTerminalResponse,
                    .resumeTerminalFrame = runResumeTerminalFrame,
                    .dispatch = runDispatch,
                    .snapshotRunImage = runSnapshotRunImage,
                    .beforeHandoffExport = runBeforeHandoffExport,
                    .beforeInterruptedHandoffExport = runBeforeInterruptedHandoffExport,
                    .beforeCheckpoint = runBeforeCheckpoint,
                    .beforeBranch = runBeforeBranch,
                    .cloneSupervisor = runCloneSupervisor,
                    .restoreSupervisor = runRestoreSupervisor,
                    .hasSupervisor = runHasSupervisor,
                    .supervisorWarningCount = runSupervisorWarningCount,
                    .supervisorBlockerCount = runSupervisorBlockerCount,
                    .supervisionInterrupted = runSupervisionInterrupted,
                    .failed = runFailed,
                    .deinit = runDeinit,
                };
            };
            return .{
                .ptr = @ptrCast(run),
                .vtable = &Impl.vtable,
            };
        }
    };

    pub fn canTransition(from: RunStatus, to: RunStatus) bool {
        return switch (from) {
            .admitted => switch (to) {
                .runnable, .rejected, .failed => true,
                else => false,
            },
            .runnable => switch (to) {
                .running, .parked_on_port, .parked_on_supervision, .completed, .failed => true,
                else => false,
            },
            .running => switch (to) {
                .parked_on_port, .parked_on_supervision, .completed, .failed => true,
                else => false,
            },
            .parked_on_port, .parked_on_supervision => switch (to) {
                .runnable, .failed, .exported => true,
                else => false,
            },
            .completed => to == .exported,
            .failed, .exported, .rejected => false,
        };
    }

    pub const RunSlot = struct {
        handle: RunHandle,
        target_ref: TargetRef,
        current_state: RunState,
        status: RunStatus,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        run_receipt_fingerprint: ?u64 = null,
        pending_mailbox_id: ?u64 = null,
        branch_id: ?u64 = null,
        parent_run_handle_fingerprint: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
        driver: ?SlotDriver = null,
        driver_world_port_count: usize = 0,
        supervisor: ?Supervision.Supervisor = null,
        installed_run_image: ?RunImage = null,
        owns_installed_run_image: bool = false,

        pub const Status = RunStatus;
        pub const Transition = enum {
            step,
            park_on_port,
            park_on_supervision,
            resume_from_port,
            complete,
            fail,
            @"export",
            reject,
        };

        pub fn init(handle: RunHandle) @This() {
            const state = RunState.init(.{
                .target_ref_fingerprint = handle.target_ref_fingerprint,
                .status = .not_started,
            });
            return .{
                .handle = handle,
                .target_ref = .{
                    .target_ref_fingerprint = handle.target_ref_fingerprint,
                    .world_surface_fingerprint = 0,
                    .target_certificate_fingerprint = 0,
                },
                .current_state = state,
                .status = .admitted,
                .admission_receipt_fingerprint = handle.admission_receipt_fingerprint,
                .run_permit_fingerprint = handle.permit_fingerprint,
                .branch_id = handle.branch_id,
            };
        }

        pub fn fromState(args: struct {
            handle: RunHandle,
            target_ref: TargetRef,
            current_state: RunState,
            status: RunStatus = .admitted,
            admission_receipt_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            run_receipt_fingerprint: ?u64 = null,
            pending_mailbox_id: ?u64 = null,
            branch_id: ?u64 = null,
            parent_run_handle_fingerprint: ?u64 = null,
            checkpoint_fingerprint: ?u64 = null,
            target_match_fingerprint: ?u64 = null,
            module_ref_fingerprint: ?u64 = null,
            driver: ?SlotDriver = null,
            driver_world_port_count: usize = 0,
            supervisor: ?Supervision.Supervisor = null,
            installed_run_image: ?RunImage = null,
            owns_installed_run_image: bool = false,
        }) @This() {
            return .{
                .handle = args.handle,
                .target_ref = args.target_ref,
                .current_state = args.current_state,
                .status = args.status,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .run_receipt_fingerprint = args.run_receipt_fingerprint,
                .pending_mailbox_id = args.pending_mailbox_id,
                .branch_id = args.branch_id,
                .parent_run_handle_fingerprint = args.parent_run_handle_fingerprint,
                .checkpoint_fingerprint = args.checkpoint_fingerprint,
                .target_match_fingerprint = args.target_match_fingerprint,
                .module_ref_fingerprint = args.module_ref_fingerprint,
                .driver = args.driver,
                .driver_world_port_count = args.driver_world_port_count,
                .supervisor = args.supervisor,
                .installed_run_image = args.installed_run_image,
                .owns_installed_run_image = args.owns_installed_run_image,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.driver) |driver| {
                driver.deinit(allocator);
                self.driver = null;
            }
            if (self.supervisor) |*supervisor| {
                supervisor.deinit();
                self.supervisor = null;
            }
            if (self.owns_installed_run_image) {
                if (self.installed_run_image) |*image| image.deinit(allocator);
            }
            self.* = undefined;
        }

        pub fn toHandle(self: @This()) RunHandle {
            return self.handle;
        }

        fn transitionState(self: @This(), status: RunState.Status, turn_index: usize, pending_request_fingerprint: ?u64) RunState {
            return RunState.init(.{
                .target_ref_fingerprint = self.handle.target_ref_fingerprint,
                .transcript_image_fingerprint = self.current_state.transcript_image_fingerprint,
                .branch_id = self.current_state.branch_id,
                .checkpoint_fingerprint = self.current_state.checkpoint_fingerprint,
                .pending_request_fingerprint = pending_request_fingerprint,
                .final_response_fingerprint = self.current_state.final_response_fingerprint,
                .final_value_image_fingerprint = self.current_state.final_value_image_fingerprint,
                .turn_index = turn_index,
                .status = status,
            });
        }

        fn resumeFromPortState(self: @This(), response_frame_fingerprint: u64, response_value_image_fingerprint: ?u64) RunState {
            return RunState.init(.{
                .target_ref_fingerprint = self.handle.target_ref_fingerprint,
                .transcript_image_fingerprint = self.current_state.transcript_image_fingerprint,
                .branch_id = self.current_state.branch_id,
                .checkpoint_fingerprint = self.current_state.checkpoint_fingerprint,
                .final_response_fingerprint = response_frame_fingerprint,
                .final_value_image_fingerprint = response_value_image_fingerprint,
                .turn_index = self.current_state.turn_index + 1,
                .status = .running,
            });
        }

        pub fn transition(self: *@This(), transition_kind: Transition, mailbox_id: ?u64) !void {
            switch (transition_kind) {
                .step => switch (self.status) {
                    .admitted, .runnable => {
                        self.status = .runnable;
                        self.current_state = self.transitionState(.running, self.current_state.turn_index, null);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .park_on_port => switch (self.status) {
                    .runnable, .running => {
                        const pending_mailbox_id = mailbox_id orelse return error.InvalidRunspaceTransition;
                        self.status = .parked_on_port;
                        self.pending_mailbox_id = pending_mailbox_id;
                        self.current_state = self.transitionState(.parked_on_port, self.current_state.turn_index, self.current_state.pending_request_fingerprint);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .park_on_supervision => switch (self.status) {
                    .runnable, .running => {
                        self.status = .parked_on_supervision;
                        self.pending_mailbox_id = null;
                        self.current_state = self.transitionState(.parked_on_supervision, self.current_state.turn_index, null);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .resume_from_port => switch (self.status) {
                    .parked_on_port => {
                        if (mailbox_id) |expected| {
                            if (self.pending_mailbox_id != expected) return error.StaleRunHandle;
                        }
                        self.status = .runnable;
                        self.pending_mailbox_id = null;
                        self.current_state = self.transitionState(.running, self.current_state.turn_index + 1, null);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .complete => switch (self.status) {
                    .runnable, .running => {
                        self.status = .completed;
                        self.current_state = self.transitionState(.completed, self.current_state.turn_index, null);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .fail => switch (self.status) {
                    .admitted, .runnable, .running, .parked_on_port, .parked_on_supervision => {
                        self.status = .failed;
                        self.pending_mailbox_id = null;
                        self.current_state = self.transitionState(.failed, self.current_state.turn_index, null);
                    },
                    else => return error.InvalidRunspaceTransition,
                },
                .@"export" => switch (self.status) {
                    .parked_on_port, .parked_on_supervision, .completed => self.status = .exported,
                    else => return error.InvalidRunspaceTransition,
                },
                .reject => switch (self.status) {
                    .admitted => self.status = .rejected,
                    else => return error.InvalidRunspaceTransition,
                },
            }
        }

        pub fn resumeFromPort(self: *@This(), mailbox_id: ?u64, response_frame_fingerprint: u64, response_value_image_fingerprint: ?u64) !void {
            switch (self.status) {
                .parked_on_port => {
                    if (mailbox_id) |expected| {
                        if (self.pending_mailbox_id != expected) return error.StaleRunHandle;
                    }
                    self.status = .runnable;
                    self.pending_mailbox_id = null;
                    self.current_state = self.resumeFromPortState(response_frame_fingerprint, response_value_image_fingerprint);
                },
                else => return error.InvalidRunspaceTransition,
            }
        }

        pub fn summary(self: @This()) RunSlotSummary {
            return .{
                .handle = self.handle,
                .target_ref_fingerprint = self.target_ref.target_ref_fingerprint,
                .run_state_fingerprint = self.current_state.run_state_fingerprint,
                .status = self.status,
                .admission_receipt_fingerprint = self.admission_receipt_fingerprint,
                .run_permit_fingerprint = self.run_permit_fingerprint,
                .run_receipt_fingerprint = self.run_receipt_fingerprint,
                .pending_mailbox_id = self.pending_mailbox_id,
                .branch_id = self.branch_id,
                .parent_run_handle_fingerprint = self.parent_run_handle_fingerprint,
                .checkpoint_fingerprint = self.checkpoint_fingerprint,
                .target_match_fingerprint = self.target_match_fingerprint,
                .module_ref_fingerprint = self.module_ref_fingerprint,
            };
        }
    };

    pub const RunSlotSummary = struct {
        handle: RunHandle,
        target_ref_fingerprint: u64,
        run_state_fingerprint: u64,
        status: RunStatus,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        run_receipt_fingerprint: ?u64 = null,
        pending_mailbox_id: ?u64 = null,
        branch_id: ?u64 = null,
        parent_run_handle_fingerprint: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        target_match_fingerprint: ?u64 = null,
        module_ref_fingerprint: ?u64 = null,
    };

    pub const PendingPort = struct {
        format_version: u32 = world_pending_port_format_version,
        fingerprint_version: u32 = world_pending_port_fingerprint_version,
        pending_port_fingerprint: u64,
        handle: RunHandle,
        mailbox_id: u64,
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        request_fingerprint: u64,
        request_frame_fingerprint: u64,
        request_frame: ?Frame.Request = null,
        owns_request_frame: bool = false,
        expected_response_kind: ResponseKind = .@"resume",
        expected_response_value_table_id: ?u32 = null,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        target_ref_fingerprint: u64,
        environment_certificate_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        turn_index: usize,
        inserted_event_index: u64,
        status: PendingStatus = .pending,

        pub const Status = PendingStatus;

        pub fn init(args: struct {
            handle: RunHandle,
            mailbox_id: u64,
            request: Frame.Request,
            target_ref_fingerprint: u64 = 0,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            inserted_event_index: u64 = 0,
        }) @This() {
            var result = @This(){
                .pending_port_fingerprint = 0,
                .handle = args.handle,
                .mailbox_id = args.mailbox_id,
                .world_surface_fingerprint = args.request.world_surface_fingerprint,
                .target_certificate_fingerprint = args.request.target_certificate_fingerprint,
                .world_port_id = args.request.world_port_id,
                .request_fingerprint = args.request.request_fingerprint,
                .request_frame_fingerprint = args.request.frame_fingerprint,
                .request_frame = args.request,
                .owns_request_frame = true,
                .expected_response_value_table_id = args.request.expected_response_value_table_id,
                .residual_site_index = args.request.residual_site_index,
                .residual_site_fingerprint = args.request.residual_site_fingerprint,
                .target_ref_fingerprint = if (args.target_ref_fingerprint != 0) args.target_ref_fingerprint else args.handle.target_ref_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .turn_index = args.request.turn_index,
                .inserted_event_index = args.inserted_event_index,
            };
            result.pending_port_fingerprint = fingerprintPendingPort(result);
            return result;
        }

        pub fn withStatus(self: @This(), status: PendingStatus) @This() {
            var result = self;
            result.status = status;
            result.pending_port_fingerprint = fingerprintPendingPort(result);
            return result;
        }

        pub fn borrowed(self: @This()) @This() {
            var result = self;
            result.owns_request_frame = false;
            return result;
        }

        pub fn transition(self: *@This(), status: PendingStatus) !void {
            if (self.status != .pending) return error.InvalidPendingPortTransition;
            if (status == .pending) return error.InvalidPendingPortTransition;
            self.status = status;
            self.pending_port_fingerprint = fingerprintPendingPort(self.*);
        }

        pub fn validateResponse(self: @This(), response: Frame.Response) !void {
            if (self.status != .pending) return error.PendingPortConsumed;
            if (response.world_surface_fingerprint != self.world_surface_fingerprint) return error.FrameSurfaceMismatch;
            if (response.target_certificate_fingerprint != self.target_certificate_fingerprint) return error.FrameTargetCertificateMismatch;
            if (response.world_port_id != self.world_port_id) return error.FramePortMismatch;
            if (response.request_fingerprint != self.request_fingerprint) return error.FrameRequestFingerprintMismatch;
            if (response.response_kind != self.expected_response_kind) return error.VerifyResponseKindMismatch;
            if (response.status == .responded and response.response_value_table_id != self.expected_response_value_table_id) return error.FrameValueTableMismatch;
            if (!response.responseFingerprintDeferred()) {
                if (self.request_frame) |request| {
                    const expected_replay_key = request.replay_key_seed.withResponse(response.response_fingerprint).fingerprint();
                    if (response.replay_key != expected_replay_key) return error.ReplayMissing;
                }
            }
            try validateResponseFrameImage(response);
        }

        pub fn validate(self: @This()) !void {
            if (self.format_version != world_pending_port_format_version) return error.InvalidFrameEncoding;
            if (self.fingerprint_version != world_pending_port_fingerprint_version) return error.InvalidFrameEncoding;
            try self.handle.validate();
            if (fingerprintPendingPort(self) != self.pending_port_fingerprint) return error.InvalidFrameEncoding;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_request_frame) {
                if (self.request_frame) |*frame| frame.deinit(allocator);
            }
            self.* = undefined;
        }
    };

    pub const Mailbox = struct {
        allocator: std.mem.Allocator,
        pending: std.ArrayList(Runspace.PendingPort) = .empty,
        max_pending_ports: ?usize = null,

        pub fn init(allocator: std.mem.Allocator, max_pending_ports: ?usize) @This() {
            return .{
                .allocator = allocator,
                .max_pending_ports = max_pending_ports,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.pending.items) |*pending_port| pending_port.deinit(self.allocator);
            self.pending.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn push(self: *@This(), args: struct {
            run_handle: RunHandle,
            mailbox_id: u64,
            request: Frame.Request,
            target_ref_fingerprint: u64,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            inserted_event_index: u64,
        }) !Runspace.PendingPort {
            if (self.max_pending_ports) |max| {
                if (self.pendingCount() >= max) return error.BudgetExceeded;
            }
            try self.assertMailboxIdAvailable(args.mailbox_id);
            try self.assertNoDuplicateRequestFingerprint(args.run_handle, args.request.request_fingerprint);
            var request = try cloneRequestFrame(self.allocator, args.request);
            var request_owned = true;
            errdefer if (request_owned) request.deinit(self.allocator);
            const pending_port = Runspace.PendingPort.init(.{
                .handle = args.run_handle,
                .mailbox_id = args.mailbox_id,
                .request = request,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .inserted_event_index = args.inserted_event_index,
            });
            try self.pending.append(self.allocator, pending_port);
            request_owned = false;
            return self.pending.items[self.pending.items.len - 1].borrowed();
        }

        pub fn get(self: *const @This(), mailbox_id: u64) !Runspace.PendingPort {
            const index = try self.indexOf(mailbox_id);
            return self.pending.items[index].borrowed();
        }

        pub fn listPending(self: *const @This(), allocator: std.mem.Allocator) ![]Runspace.PendingPort {
            const count = self.pendingCount();
            const result = try allocator.alloc(Runspace.PendingPort, count);
            var out_index: usize = 0;
            for (self.pending.items) |pending_port| {
                if (pending_port.status != .pending) continue;
                result[out_index] = pending_port.borrowed();
                out_index += 1;
            }
            return result;
        }

        fn respond(self: *@This(), mailbox_id: u64, response: Frame.Response) !Runspace.PendingPort {
            const index = try self.indexOf(mailbox_id);
            const current = self.pending.items[index];
            try current.validateResponse(response);
            const responded = current.withStatus(.responded);
            self.pending.items[index] = responded;
            return self.pending.items[index].borrowed();
        }

        fn markResponded(self: *@This(), mailbox_id: u64) !Runspace.PendingPort {
            const index = try self.indexOf(mailbox_id);
            const current = self.pending.items[index];
            if (current.status != .pending) return error.PendingPortConsumed;
            const responded = current.withStatus(.responded);
            self.pending.items[index] = responded;
            return self.pending.items[index].borrowed();
        }

        fn cancel(self: *@This(), mailbox_id: u64, reason: []const u8) !Runspace.PendingPort {
            _ = reason;
            const index = try self.indexOf(mailbox_id);
            const current = self.pending.items[index];
            if (current.status != .pending) return error.PendingPortConsumed;
            const cancelled = current.withStatus(.cancelled);
            self.pending.items[index] = cancelled;
            return self.pending.items[index].borrowed();
        }

        fn markExported(self: *@This(), mailbox_id: u64) !Runspace.PendingPort {
            const index = try self.indexOf(mailbox_id);
            const current = self.pending.items[index];
            if (current.status != .pending) return error.PendingPortConsumed;
            const exported = current.withStatus(.exported);
            self.pending.items[index] = exported;
            return self.pending.items[index].borrowed();
        }

        fn fail(self: *@This(), mailbox_id: u64, reason: []const u8) !Runspace.PendingPort {
            _ = reason;
            const index = try self.indexOf(mailbox_id);
            const current = self.pending.items[index];
            if (current.status != .pending) return error.PendingPortConsumed;
            const failed = current.withStatus(.failed);
            self.pending.items[index] = failed;
            return self.pending.items[index].borrowed();
        }

        pub fn assertNoDuplicateRequestFingerprint(self: *const @This(), run_handle: RunHandle, request_fingerprint: u64) !void {
            for (self.pending.items) |pending_port| {
                if (pending_port.status == .pending and
                    pending_port.handle.handle_fingerprint == run_handle.handle_fingerprint and
                    pending_port.request_fingerprint == request_fingerprint)
                {
                    return error.InvalidPendingPortTransition;
                }
            }
        }

        pub fn pendingCount(self: *const @This()) usize {
            var count: usize = 0;
            for (self.pending.items) |pending_port| {
                if (pending_port.status == .pending) count += 1;
            }
            return count;
        }

        pub fn ensurePendingCapacity(self: *const @This()) !void {
            if (self.max_pending_ports) |max| {
                if (self.pendingCount() >= max) return error.BudgetExceeded;
            }
        }

        fn indexOf(self: *const @This(), mailbox_id: u64) !usize {
            for (self.pending.items, 0..) |pending_port, index| {
                if (pending_port.mailbox_id == mailbox_id) return index;
            }
            return error.InvalidPendingPortTransition;
        }

        fn assertMailboxIdAvailable(self: *const @This(), mailbox_id: u64) !void {
            for (self.pending.items) |pending_port| {
                if (pending_port.mailbox_id == mailbox_id) return error.InvalidPendingPortTransition;
            }
        }
    };

    pub const RunspaceEvent = struct {
        event_fingerprint: u64,
        kind: Runspace.EventKind,
        runspace_fingerprint: u64,
        event_index: u64,
        run_handle: RunHandle,
        pending_port_fingerprint: ?u64 = null,
        request_frame_fingerprint: ?u64 = null,
        response_frame_fingerprint: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        run_state_fingerprint: u64,
        run_receipt_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        summary: []const u8 = "",
        owns_summary: bool = false,

        pub fn init(args: struct {
            kind: Runspace.EventKind,
            runspace_fingerprint: u64,
            event_index: u64,
            run_handle: RunHandle,
            pending_port_fingerprint: ?u64 = null,
            request_frame_fingerprint: ?u64 = null,
            response_frame_fingerprint: ?u64 = null,
            checkpoint_fingerprint: ?u64 = null,
            run_state_fingerprint: u64,
            run_receipt_fingerprint: ?u64 = null,
            admission_receipt_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            summary: []const u8 = "",
            owns_summary: bool = false,
        }) @This() {
            var result = @This(){
                .event_fingerprint = 0,
                .kind = args.kind,
                .runspace_fingerprint = args.runspace_fingerprint,
                .event_index = args.event_index,
                .run_handle = args.run_handle,
                .pending_port_fingerprint = args.pending_port_fingerprint,
                .request_frame_fingerprint = args.request_frame_fingerprint,
                .response_frame_fingerprint = args.response_frame_fingerprint,
                .checkpoint_fingerprint = args.checkpoint_fingerprint,
                .run_state_fingerprint = args.run_state_fingerprint,
                .run_receipt_fingerprint = args.run_receipt_fingerprint,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .summary = args.summary,
                .owns_summary = args.owns_summary,
            };
            result.event_fingerprint = fingerprintRunspaceEvent(result);
            return result;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_summary) allocator.free(@constCast(self.summary));
            self.* = undefined;
        }

        pub fn borrowed(self: @This()) @This() {
            var result = self;
            result.owns_summary = false;
            return result;
        }
    };

    pub const RunspaceReport = struct {
        runspace_fingerprint: u64,
        event_count: usize,
        run_count: usize,
        runnable_count: usize,
        parked_count: usize,
        completed_count: usize,
        failed_count: usize,
        pending_port_count: usize,
        emitted_events: []const Runspace.RunspaceEvent = &.{},
        blocker_count: usize = 0,
        warning_count: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) @This() {
        const runspace_instance_id = next_runspace_instance_id.fetchAdd(1, .monotonic);
        const runspace_fingerprint = fingerprintRunspaceConfig(config, runspace_instance_id);
        return .{
            .allocator = allocator,
            .config = config,
            .runspace_fingerprint = runspace_fingerprint,
            .mailbox = Runspace.Mailbox.init(allocator, config.max_pending_ports),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.slots.items) |*slot| {
            slot.deinit(self.allocator);
        }
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.slots.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.mailbox.deinit();
        self.* = undefined;
    }

    fn supervisorPortCountForPermit(permit: RunPermit) usize {
        var count: usize = 0;
        for (permit.budget.per_port_budgets) |budget| {
            count = @max(count, @as(usize, budget.world_port_id) + 1);
        }
        for (permit.cost_model.per_port_costs) |cost| {
            count = @max(count, @as(usize, cost.world_port_id) + 1);
        }
        for (permit.port_rules) |rule| {
            count = @max(count, @as(usize, rule.world_port_id) + 1);
        }
        return count;
    }

    fn validateAdmittedRunPermit(admitted_run: Admission.AdmittedRun, permit: RunPermit) !void {
        const target_ref = admitted_run.target_ref;
        if (permit.target_ref_fingerprint != target_ref.target_ref_fingerprint) return error.SupervisionDenied;
        if (permit.world_surface_fingerprint != target_ref.world_surface_fingerprint) return error.SupervisionDenied;
        if (permit.target_certificate_fingerprint != target_ref.target_certificate_fingerprint) return error.SupervisionDenied;
        if (permit.mode != admissionModeToRunMode(admitted_run.mode)) return error.SupervisionDenied;
        if (permit.admission_receipt_fingerprint) |receipt_fingerprint| {
            if (receipt_fingerprint != admitted_run.admission_receipt_fingerprint) return error.SupervisionDenied;
        }
        if (permit.module_ref_fingerprint) |permit_module_ref| {
            const admitted_module_ref = admitted_run.module_ref_fingerprint orelse if (admitted_run.run_image) |image| image.module_ref_fingerprint else null;
            if (admitted_module_ref == null or admitted_module_ref.? != permit_module_ref) return error.SupervisionDenied;
        }
        if (admitted_run.environment_certificate_fingerprint) |certificate_fingerprint| {
            if (permit.environment_certificate_fingerprint != certificate_fingerprint) return error.SupervisionDenied;
        } else if (permit.policy.require_environment_certificate) {
            return error.SupervisionDenied;
        }
        const transcript_available = admitted_run.transcript_image != null or
            (admitted_run.run_image != null and admitted_run.run_image.?.transcript_image != null);
        const replays_transcript_prefix = if (admitted_run.run_image) |image|
            runImageIsInterruptedSupervisionExport(image) and image.current_state.turn_index != 0
        else
            false;
        const consumes_admitted_transcript = modeConsumesTranscript(permit.mode) or replays_transcript_prefix;
        if (consumes_admitted_transcript) {
            if (permit.policy.require_transcript_image_for_replay and !transcript_available) return error.SupervisionDenied;
            if (permit.policy.require_transcript_image_for_replay and !permit.transcript_image_available) return error.SupervisionDenied;
            if (transcript_available and !permit.transcript_image_available) return error.SupervisionDenied;
        }
    }

    fn runImageFromAdmittedTranscript(allocator: std.mem.Allocator, target_ref: TargetRef, import_set_fingerprint: u64, module_ref_fingerprint: ?u64, transcript_image: TranscriptImage) !RunImage {
        var replay_validation = transcript_image;
        try replay_validation.validateReplayRun(target_ref.world_surface_fingerprint, target_ref.target_certificate_fingerprint);
        var cloned_transcript = try cloneTranscriptImage(allocator, transcript_image);
        errdefer cloned_transcript.deinit(allocator);
        const evidence = runStateEvidenceFromTranscriptImage(replay_validation);
        const state = RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .transcript_image_fingerprint = transcript_image.transcript_image_fingerprint,
            .final_response_fingerprint = evidence.final_response_fingerprint,
            .final_value_image_fingerprint = evidence.final_value_image_fingerprint,
            .turn_index = evidence.turn_index,
            .status = switch (transcript_image.final_status) {
                .running => .running,
                .completed => .completed,
                .failed => .failed,
            },
        });
        var image = RunImage.init(.{
            .kind = .replay_only_run,
            .target_ref = target_ref,
            .import_set_fingerprint = import_set_fingerprint,
            .transcript_image = cloned_transcript,
            .current_state = state,
            .module_ref_fingerprint = module_ref_fingerprint,
        });
        image.owns_transcript_image = true;
        return image;
    }

    fn validateAdmittedRunReceipt(admitted_run: Admission.AdmittedRun) !void {
        const receipt = admitted_run.admission_receipt orelse return;
        if (receipt.receipt_fingerprint != admitted_run.admission_receipt_fingerprint) return error.InvalidFrameEncoding;
        if (fingerprintAdmissionReceipt(receipt) != receipt.receipt_fingerprint) return error.InvalidFrameEncoding;
        const admitted_run_fingerprint = receipt.admitted_run_fingerprint orelse return error.InvalidFrameEncoding;
        if (admitted_run_fingerprint != admitted_run.admitted_run_fingerprint) return error.InvalidFrameEncoding;
        const receipt_local_target_ref = receipt.local_target_ref_fingerprint orelse receipt.target_ref_fingerprint;
        if (receipt_local_target_ref != admitted_run.target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
        if (receipt.module_ref_fingerprint != admitted_run.module_ref_fingerprint) return error.InvalidFrameEncoding;
        if (receipt.environment_certificate_fingerprint != admitted_run.environment_certificate_fingerprint) return error.InvalidFrameEncoding;
        if (receipt.run_permit_fingerprint != if (admitted_run.run_permit) |permit| permit.permit_fingerprint else null) return error.InvalidFrameEncoding;
        if (receipt.accepted_mode != admitted_run.mode) return error.InvalidFrameEncoding;
    }

    pub fn installAdmitted(self: *@This(), admitted_run: Admission.AdmittedRun) !RunHandle {
        if (admitted_run.admitted_run_fingerprint != fingerprintAdmittedRun(admitted_run)) return error.InvalidFrameEncoding;
        if (self.config.require_admission and admitted_run.admission_receipt == null) return error.InvalidFrameEncoding;
        try validateAdmittedRunReceipt(admitted_run);
        if (self.config.require_supervision and admitted_run.run_permit == null) return error.SupervisionDenied;
        const target_ref = admitted_run.target_ref;
        try validateTargetRef(target_ref);
        if (admissionModeNeedsRunImage(admitted_run.mode)) {
            _ = admitted_run.run_image orelse return error.InvalidFrameEncoding;
        }
        if (admitted_run.mode == .branch_resume and admitted_run.selected_branch_id == null) return error.HandoffCheckpointMismatch;
        if (modeConsumesTranscript(admissionModeToRunMode(admitted_run.mode)) and !self.config.allow_replay_install) return error.RunspaceInstallDenied;
        const transcript_only_replay_install = admitted_run.run_image == null and
            modeConsumesTranscript(admissionModeToRunMode(admitted_run.mode)) and
            admitted_run.transcript_image != null;
        if (admitted_run.run_image == null and
            modeConsumesTranscript(admissionModeToRunMode(admitted_run.mode)) and
            !transcript_only_replay_install)
        {
            return error.RunspaceInstallDenied;
        }
        if (admitted_run.run_image) |image| {
            if ((admissionModeNeedsRunImage(admitted_run.mode) or admitted_run.mode == .replay_only or admitted_run.mode == .verify_only) and
                !runImageFitsAdmissionMode(image, admitted_run.mode))
            {
                return error.InvalidFrameEncoding;
            }
            if (!self.config.allow_handoff_install) return error.RunspaceInstallDenied;
            if (image.kind == .replay_only_run and !self.config.allow_replay_install) return error.RunspaceInstallDenied;
            try image.validate(.{});
            if (image.target_ref.target_ref_fingerprint != target_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
            if (image.target_ref.world_surface_fingerprint != target_ref.world_surface_fingerprint) return error.HandoffTargetMismatch;
            if (image.target_ref.target_certificate_fingerprint != target_ref.target_certificate_fingerprint) return error.HandoffTargetMismatch;
            if (image.current_state.target_ref_fingerprint != target_ref.target_ref_fingerprint) return error.HandoffTargetMismatch;
            if (admitted_run.module_ref_fingerprint) |module_ref_fingerprint| {
                const image_module_ref = image.module_ref_fingerprint orelse return error.InvalidFrameEncoding;
                if (image_module_ref != module_ref_fingerprint) return error.InvalidFrameEncoding;
            }
            if (admitted_run.selected_checkpoint_ref) |selected_checkpoint_ref| {
                const image_checkpoint = image.current_state.checkpoint_fingerprint orelse return error.HandoffCheckpointMismatch;
                if (image_checkpoint != selected_checkpoint_ref) return error.HandoffCheckpointMismatch;
                if (!runImageContainsCheckpoint(image, selected_checkpoint_ref)) return error.HandoffCheckpointMismatch;
            }
        } else if (admitted_run.selected_branch_id != null or admitted_run.selected_checkpoint_ref != null) {
            return error.HandoffCheckpointMismatch;
        }
        const current_state = if (admitted_run.run_image) |image| image.current_state else RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .transcript_image_fingerprint = if (admitted_run.transcript_image) |image| image.transcript_image_fingerprint else null,
            .branch_id = admitted_run.selected_branch_id orelse 0,
            .checkpoint_fingerprint = admitted_run.selected_checkpoint_ref,
            .status = .not_started,
        });
        const pending_frame = if (admitted_run.run_image) |image|
            if (image.current_state.status == .parked_on_port)
                image.pending_request_frame orelse return error.HandoffPendingFrameMismatch
            else
                null
        else
            null;
        const next_run_id_before = self.next_run_id;
        var installed_image: ?RunImage = null;
        var installed_image_owned = false;
        errdefer if (installed_image_owned) {
            if (installed_image) |*image| image.deinit(self.allocator);
        };
        if (admitted_run.run_image) |image| {
            installed_image = try cloneRunImage(self.allocator, image);
            installed_image_owned = true;
            if (admitted_run.transcript_image) |transcript_image| {
                if (admitted_run.mode == .replay_only or admitted_run.mode == .verify_only) {
                    var replay_validation = transcript_image;
                    try replay_validation.validateReplayRun(target_ref.world_surface_fingerprint, target_ref.target_certificate_fingerprint);
                    try attachTranscriptToInstalledRunImage(self.allocator, &installed_image.?, replay_validation);
                } else {
                    try attachTranscriptToInstalledRunImage(self.allocator, &installed_image.?, transcript_image);
                }
                try installed_image.?.validate(.{});
            }
            try applySelectedBranchToRunImage(&installed_image.?, admitted_run.selected_branch_id);
        } else if (transcript_only_replay_install) {
            installed_image = try runImageFromAdmittedTranscript(
                self.allocator,
                target_ref,
                admitted_run.import_set_fingerprint orelse return error.InvalidFrameEncoding,
                admitted_run.module_ref_fingerprint,
                admitted_run.transcript_image.?,
            );
            installed_image_owned = true;
            try installed_image.?.validate(.{});
        }
        var supervisor: ?Supervision.Supervisor = null;
        var supervisor_owned = false;
        errdefer if (supervisor_owned) {
            if (supervisor) |*owned| owned.deinit();
        };
        var installed_permit_fingerprint: ?u64 = if (installed_image) |image| image.prior_run_permit_fingerprint else null;
        if (admitted_run.run_permit) |permit| {
            try validateAdmittedRunPermit(admitted_run, permit);
            const scoped_permit = scopePermitToAdmission(permit, admitted_run.admission_receipt_fingerprint);
            installed_permit_fingerprint = scoped_permit.permit_fingerprint;
            const port_count = blk: {
                var count = supervisorPortCountForPermit(scoped_permit);
                if (pending_frame) |frame| count = @max(count, @as(usize, frame.world_port_id) + 1);
                if (installed_image) |image| {
                    if (image.transcript_image) |transcript_image| count = @max(count, transcriptPortCount(transcript_image));
                }
                break :blk count;
            };
            supervisor = try Supervision.Supervisor.init(self.allocator, scoped_permit, port_count);
            supervisor_owned = true;
            try supervisor.?.beforeHandoffAccept();
            if (installed_image) |image| {
                if (image.transcript_image) |transcript_image| {
                    var replay_image = transcript_image;
                    if (admitted_run.mode == .replay_only or admitted_run.mode == .verify_only) {
                        try replay_image.validateReplayRun(
                            replay_image.world_surface_fingerprint,
                            replay_image.target_certificate_fingerprint,
                        );
                        try self.accountPreparedTranscriptReplayWithSupervisor(replay_image, admissionModeToRunMode(admitted_run.mode), &supervisor.?, .completed_run);
                    } else if (runImageIsInterruptedSupervisionExport(image) and image.current_state.turn_index != 0) {
                        try replay_image.prepareReplayPrefixForInterruptedRun(
                            replay_image.world_surface_fingerprint,
                            replay_image.target_certificate_fingerprint,
                        );
                        try self.accountPreparedTranscriptReplayWithSupervisor(replay_image, .replay, &supervisor.?, .interrupted_prefix);
                    }
                }
            }
        }
        const slot_current_state = if (installed_image) |image| image.current_state else current_state;
        const slot_branch_id: ?u64 = if (slot_current_state.branch_id == 0)
            admitted_run.selected_branch_id
        else
            slot_current_state.branch_id;
        const handle = try self.nextHandle(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .admission_receipt_fingerprint = admitted_run.admission_receipt_fingerprint,
            .permit_fingerprint = installed_permit_fingerprint,
            .branch_id = slot_branch_id,
        });
        const slot = Runspace.RunSlot.fromState(.{
            .handle = handle,
            .target_ref = target_ref,
            .current_state = slot_current_state,
            .status = if (installed_image == null) .admitted else try statusFromInstallableRunImageState(slot_current_state),
            .admission_receipt_fingerprint = admitted_run.admission_receipt_fingerprint,
            .run_permit_fingerprint = installed_permit_fingerprint,
            .run_receipt_fingerprint = if (installed_image) |image| image.prior_run_receipt_fingerprint else null,
            .pending_mailbox_id = null,
            .branch_id = slot_branch_id,
            .checkpoint_fingerprint = slot_current_state.checkpoint_fingerprint,
            .module_ref_fingerprint = admitted_run.module_ref_fingerprint orelse if (installed_image) |image| image.module_ref_fingerprint else null,
            .supervisor = supervisor,
            .installed_run_image = installed_image,
            .owns_installed_run_image = installed_image != null,
        });
        const slot_count_before = self.slots.items.len;
        const event_count_before = self.events.items.len;
        const mailbox_count_before = self.mailbox.pending.items.len;
        const next_mailbox_id_before = self.next_mailbox_id;
        const next_event_index_before = self.next_event_index;
        var installed = false;
        errdefer if (!installed) self.rollbackRunspaceMutation(slot_count_before, event_count_before, mailbox_count_before, next_run_id_before, next_mailbox_id_before, next_event_index_before);
        try self.prepareInstallSlot();
        installed_image_owned = false;
        supervisor_owned = false;
        try self.installPreparedSlot(slot, .run_admitted, "admitted run installed");
        if (pending_frame) |frame| {
            try self.enqueueInstalledPending(self.slots.items.len - 1, frame);
        }
        installed = true;
        return handle;
    }

    pub fn installRunImage(self: *@This(), image: RunImage) !RunHandle {
        if (self.config.require_admission) return error.RunspaceAdmissionRequired;
        if (!self.config.allow_handoff_install) return error.RunspaceInstallDenied;
        if (image.kind == .replay_only_run and !self.config.allow_replay_install) return error.RunspaceInstallDenied;
        if (self.config.require_supervision) return error.SupervisionDenied;
        try image.validate(.{});
        const run_status = try statusFromInstallableRunImageState(image.current_state);
        if (image.current_state.status == .parked_on_supervision) {
            if (!runImageIsInterruptedSupervisionExport(image)) return error.InvalidFrameEncoding;
            if (image.current_state.turn_index != 0) {
                var transcript_image = image.transcript_image orelse return error.InvalidFrameEncoding;
                try transcript_image.prepareReplayPrefixForInterruptedRun(
                    transcript_image.world_surface_fingerprint,
                    transcript_image.target_certificate_fingerprint,
                );
            }
        }
        const pending_frame = if (image.current_state.status == .parked_on_port)
            image.pending_request_frame orelse return error.HandoffPendingFrameMismatch
        else
            null;
        const next_run_id_before = self.next_run_id;
        const slot_count_before = self.slots.items.len;
        const event_count_before = self.events.items.len;
        const mailbox_count_before = self.mailbox.pending.items.len;
        const next_mailbox_id_before = self.next_mailbox_id;
        const next_event_index_before = self.next_event_index;
        var installed = false;
        errdefer if (!installed) self.rollbackRunspaceMutation(slot_count_before, event_count_before, mailbox_count_before, next_run_id_before, next_mailbox_id_before, next_event_index_before);
        const handle = try self.nextHandle(.{
            .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
            .permit_fingerprint = image.prior_run_permit_fingerprint,
            .branch_id = if (image.current_state.branch_id == 0) null else image.current_state.branch_id,
        });
        var installed_image = try cloneRunImage(self.allocator, image);
        var installed_image_owned = true;
        errdefer if (installed_image_owned) installed_image.deinit(self.allocator);
        const installed_target_ref = installed_image.target_ref;
        const installed_state = installed_image.current_state;
        const slot = Runspace.RunSlot.fromState(.{
            .handle = handle,
            .target_ref = installed_target_ref,
            .current_state = installed_state,
            .status = run_status,
            .run_permit_fingerprint = image.prior_run_permit_fingerprint,
            .run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
            .branch_id = if (installed_state.branch_id == 0) null else installed_state.branch_id,
            .checkpoint_fingerprint = installed_state.checkpoint_fingerprint,
            .module_ref_fingerprint = image.module_ref_fingerprint,
            .installed_run_image = installed_image,
            .owns_installed_run_image = true,
        });
        try self.prepareInstallSlot();
        installed_image_owned = false;
        try self.installPreparedSlot(slot, .run_installed, "run image installed");
        if (pending_frame) |frame| {
            try self.enqueueInstalledPending(self.slots.items.len - 1, frame);
        }
        installed = true;
        return handle;
    }

    pub fn installTarget(self: *@This(), comptime Target: type, env: anytype, permit: ?RunPermit, args: anytype) !RunHandle {
        if (self.config.require_admission) return error.RunspaceAdmissionRequired;
        if (!self.config.allow_direct_target_install) return error.RunspaceInstallDenied;
        if (self.config.require_supervision and permit == null) return error.SupervisionDenied;
        const target_ref = TargetRef.fromTarget(Target);
        const next_run_id_before = self.next_run_id;
        var installed = false;
        errdefer if (!installed) {
            self.next_run_id = next_run_id_before;
        };
        const handle = try self.nextHandle(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .permit_fingerprint = if (permit) |run_permit| run_permit.permit_fingerprint else null,
        });
        const state = RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .not_started,
        });
        var supervisor: ?Supervision.Supervisor = null;
        var supervisor_owned = false;
        errdefer if (supervisor_owned) {
            if (supervisor) |*owned| owned.deinit();
        };
        if (permit) |run_permit| {
            try validateInstallTargetPermit(Target, env, run_permit, args);
            supervisor = try Supervision.Supervisor.init(self.allocator, run_permit, Target.WorldPortTable.entries.len);
            supervisor_owned = true;
        }
        const slot = Runspace.RunSlot.fromState(.{
            .handle = handle,
            .target_ref = target_ref,
            .current_state = state,
            .status = .admitted,
            .run_permit_fingerprint = if (permit) |run_permit| run_permit.permit_fingerprint else null,
            .supervisor = supervisor,
        });
        try self.prepareInstallSlot();
        supervisor_owned = false;
        try self.installPreparedSlot(slot, .run_installed, "direct target installed");
        installed = true;
        return handle;
    }

    fn validateInstallTargetPermit(comptime Target: type, env: anytype, permit: RunPermit, args: anytype) !void {
        const Args = @TypeOf(args);
        const expected_mode: Mode = if (@hasField(Args, "mode")) @field(args, "mode") else .fresh;
        if (permit.target_ref_fingerprint != TargetRef.fromTarget(Target).target_ref_fingerprint) return error.SupervisionDenied;
        if (permit.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return error.SupervisionDenied;
        if (permit.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return error.SupervisionDenied;
        if (permit.mode != expected_mode) return error.SupervisionDenied;
        if (permit.admission_receipt_fingerprint != null or permit.module_ref_fingerprint != null) return error.SupervisionDenied;
        const transcript_available: bool = if (@hasField(Args, "transcript_image_available")) @field(args, "transcript_image_available") else false;
        const Env = if (@TypeOf(env) == type) env else @TypeOf(env);
        if (@hasDecl(Env, "certificate")) {
            const cert = Env.certificate(expected_mode, transcript_available);
            if (permit.environment_certificate_fingerprint != cert.certificate_fingerprint) return error.SupervisionDenied;
            if (permit.binding_plan_fingerprint != cert.binding_plan_fingerprint) return error.SupervisionDenied;
        } else if (permit.policy.require_environment_certificate) {
            return error.SupervisionDenied;
        }
    }

    pub fn installMachineRun(self: *@This(), comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !RunHandle {
        if (self.config.require_admission) return error.RunspaceAdmissionRequired;
        if (!self.config.allow_direct_target_install) return error.RunspaceInstallDenied;
        const Options = @TypeOf(options);
        const requested_mode: Mode = if (comptime @hasField(Options, "mode")) @field(options, "mode") else .fresh;
        if (modeConsumesTranscript(requested_mode) and !self.config.allow_replay_install) return error.RunspaceInstallDenied;
        if (modeConsumesTranscript(requested_mode) and !self.config.auto_dispatch) return error.RunspaceInstallDenied;
        const maybe_permit: ?RunPermit = if (comptime @hasField(Options, "permit")) @field(options, "permit") else null;
        if (self.config.require_supervision and maybe_permit == null) return error.SupervisionDenied;
        const MachineType = Machine(Target, Env.machine_config);
        const RunType = MachineType.Run(@TypeOf(runtime), @TypeOf(args), Options);
        const target_ref = TargetRef.fromTarget(Target);
        const next_run_id_before = self.next_run_id;
        var installed = false;
        errdefer if (!installed) {
            self.next_run_id = next_run_id_before;
        };
        const handle = try self.nextHandle(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .permit_fingerprint = if (maybe_permit) |permit| permit.permit_fingerprint else null,
        });
        try self.prepareInstallSlot();
        const event_summary = try self.prepareEventSummary("machine run installed");
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary);
        const run_ptr = try self.allocator.create(RunType);
        var run_ptr_owned = true;
        errdefer if (run_ptr_owned) self.allocator.destroy(run_ptr);
        var run = try MachineType.start(runtime, args, options);
        var run_owned = true;
        errdefer if (run_owned) run.deinit();
        run_ptr.* = run;
        run_owned = false;
        var driver = SlotDriver.forRun(RunType, run_ptr);
        run_ptr_owned = false;
        var driver_owned = true;
        errdefer if (driver_owned) driver.deinit(self.allocator);
        const state = RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .not_started,
        });
        const slot = Runspace.RunSlot.fromState(.{
            .handle = handle,
            .target_ref = target_ref,
            .current_state = state,
            .status = .runnable,
            .run_permit_fingerprint = if (maybe_permit) |permit| permit.permit_fingerprint else null,
            .driver = driver,
            .driver_world_port_count = Target.WorldPortTable.entries.len,
        });
        driver_owned = false;
        self.slots.appendAssumeCapacity(slot);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_installed,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_summary,
        });
        summary_owned = false;
        installed = true;
        return handle;
    }

    pub fn installReplay(self: *@This(), comptime Target: type, transcript_image: TranscriptImage, permit: ?RunPermit) !RunHandle {
        if (self.config.require_admission) return error.RunspaceAdmissionRequired;
        if (!self.config.allow_replay_install) return error.RunspaceInstallDenied;
        if (self.config.require_supervision and permit == null) return error.SupervisionDenied;
        var replay_validation = transcript_image;
        try replay_validation.validateReplayRun(Target.WorldSurface.surface_fingerprint, Target.Certificate.certificate_fingerprint);
        if (permit) |run_permit| try validateInstallReplayPermit(Target, replay_validation, run_permit);
        var image = RunImage.fromTranscriptImage(Target, replay_validation, .replay_only_run);
        image.prior_run_permit_fingerprint = if (permit) |run_permit| run_permit.permit_fingerprint else null;
        image.run_image_fingerprint = fingerprintRunImageV3(image);
        var installed_image = try cloneRunImage(self.allocator, image);
        var installed_image_owned = true;
        errdefer if (installed_image_owned) installed_image.deinit(self.allocator);
        var supervisor: ?Supervision.Supervisor = null;
        var supervisor_owned = false;
        errdefer if (supervisor_owned) {
            if (supervisor) |*owned| owned.deinit();
        };
        if (permit) |run_permit| {
            supervisor = try Supervision.Supervisor.init(self.allocator, run_permit, @max(Target.WorldPortTable.entries.len, transcriptPortCount(transcript_image)));
            supervisor_owned = true;
            try self.accountPreparedTranscriptReplayWithSupervisor(replay_validation, .replay, &supervisor.?, .completed_run);
        }
        const next_run_id_before = self.next_run_id;
        var installed = false;
        errdefer if (!installed) {
            self.next_run_id = next_run_id_before;
        };
        const handle = try self.nextHandle(.{
            .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
            .permit_fingerprint = image.prior_run_permit_fingerprint,
            .branch_id = if (image.current_state.branch_id == 0) null else image.current_state.branch_id,
        });
        const installed_target_ref = installed_image.target_ref;
        const installed_state = installed_image.current_state;
        const slot = Runspace.RunSlot.fromState(.{
            .handle = handle,
            .target_ref = installed_target_ref,
            .current_state = installed_state,
            .status = statusFromRunState(installed_state),
            .run_permit_fingerprint = image.prior_run_permit_fingerprint,
            .branch_id = if (installed_state.branch_id == 0) null else installed_state.branch_id,
            .checkpoint_fingerprint = installed_state.checkpoint_fingerprint,
            .supervisor = supervisor,
            .installed_run_image = installed_image,
            .owns_installed_run_image = true,
        });
        try self.prepareInstallSlot();
        installed_image_owned = false;
        supervisor_owned = false;
        try self.installPreparedSlot(slot, .run_installed, "replay run installed");
        installed = true;
        return handle;
    }

    fn validateInstallReplayPermit(comptime Target: type, transcript_image: TranscriptImage, permit: RunPermit) !void {
        if (permit.target_ref_fingerprint != TargetRef.fromTarget(Target).target_ref_fingerprint) return error.SupervisionDenied;
        if (permit.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return error.SupervisionDenied;
        if (permit.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return error.SupervisionDenied;
        if (permit.mode != .replay) return error.SupervisionDenied;
        if (permit.admission_receipt_fingerprint != null or permit.module_ref_fingerprint != null) return error.SupervisionDenied;
        if (permit.policy.require_environment_certificate) return error.SupervisionDenied;
        if (!permit.transcript_image_available) {
            if (permit.policy.require_transcript_image_for_replay) return error.TranscriptImageRequired;
            return error.SupervisionDenied;
        }
        if (transcript_image.world_surface_fingerprint != permit.world_surface_fingerprint) return error.SupervisionDenied;
        if (transcript_image.target_certificate_fingerprint != permit.target_certificate_fingerprint) return error.SupervisionDenied;
    }

    pub fn installVerifyRun(self: *@This(), comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !RunHandle {
        return self.installMachineRun(Target, Env, runtime, args, options);
    }

    pub fn getSlotSummary(self: *const @This(), handle: RunHandle) !Runspace.RunSlotSummary {
        return self.slots.items[try self.slotIndex(handle)].summary();
    }

    pub fn listRunSummaries(self: *const @This(), allocator: std.mem.Allocator) ![]Runspace.RunSlotSummary {
        const summaries = try allocator.alloc(Runspace.RunSlotSummary, self.slots.items.len);
        for (self.slots.items, 0..) |slot, index| {
            summaries[index] = slot.summary();
        }
        return summaries;
    }

    pub fn poll(self: *const @This()) Runspace.RunspaceReport {
        return self.report();
    }

    const ResponseFrameAccounting = struct {
        response_bytes: usize = 0,
        value_image_bytes: usize = 0,
    };

    fn responseFrameAccounting(self: *@This(), response: Frame.Response) !ResponseFrameAccounting {
        const encoded_response = try response.encode(self.allocator);
        defer self.allocator.free(encoded_response);
        return .{
            .response_bytes = encoded_response.len,
            .value_image_bytes = if (response.response_image) |image| image.bytes.len else 0,
        };
    }

    fn transcriptPortCount(image: TranscriptImage) usize {
        var count: usize = 0;
        for (image.events) |event| {
            if (event.world_port_id) |world_port_id| {
                count = @max(count, @as(usize, world_port_id) + 1);
            }
            if (event.request_frame) |frame| {
                count = @max(count, @as(usize, frame.world_port_id) + 1);
            }
            if (event.response_frame) |frame| {
                count = @max(count, @as(usize, frame.world_port_id) + 1);
            }
        }
        return count;
    }

    const TranscriptReplayAccounting = enum {
        interrupted_prefix,
        completed_run,
    };

    fn accountPreparedTranscriptReplayWithSupervisor(self: *@This(), image: TranscriptImage, replay_mode: Mode, supervisor: *Supervision.Supervisor, accounting: TranscriptReplayAccounting) !void {
        var index = image.replay_cursor;
        const limit = image.replay_limit orelse image.events.len;
        while (index < limit) : (index += 1) {
            const event = image.events[index];
            switch (event.kind) {
                .port_requested,
                .frame_requested,
                => {
                    const request_frame = event.request_frame orelse return error.ReplayMissing;
                    try supervisor.beforeSessionStep();
                    try supervisor.beforePortRequest(request_frame.world_port_id, 0, 0);
                    const request_bytes = bytes: {
                        const encoded = try request_frame.encode(self.allocator);
                        defer self.allocator.free(encoded);
                        break :bytes encoded.len;
                    };
                    try supervisor.accountPortRequestBytes(
                        request_frame.world_port_id,
                        request_bytes,
                        if (request_frame.payload_image) |image_value| image_value.bytes.len else 0,
                    );
                },
                else => {},
            }
            if (eventKindIsSourceResponse(event.kind)) {
                const response_frame = event.response_frame orelse return error.ReplayMissing;
                try supervisor.beforeAdapterCall(.{
                    .world_port_id = response_frame.world_port_id,
                    .mode = replay_mode,
                    .adapter_kind = if (replay_mode == .verify) .native else .replay,
                    .authority_kind = if (replay_mode == .verify) PortAuthority.native_function.authority_kind else PortAuthority.replay_source.authority_kind,
                    .value_policy = if (replay_mode == .verify) .native_compatible else .portable,
                });
                const response_bytes = bytes: {
                    const encoded = try response_frame.encode(self.allocator);
                    defer self.allocator.free(encoded);
                    break :bytes encoded.len;
                };
                try supervisor.afterAdapterResponse(.{
                    .world_port_id = response_frame.world_port_id,
                    .status = response_frame.status,
                    .response_bytes = response_bytes,
                    .value_image_bytes = if (response_frame.response_image) |image_value| image_value.bytes.len else 0,
                });
                if (accounting == .completed_run and replay_mode == .verify) {
                    try supervisor.afterAdapterResponse(.{
                        .world_port_id = response_frame.world_port_id,
                        .status = .responded,
                    });
                }
            }
        }
        if (accounting == .completed_run) try supervisor.beforeSessionStep();
    }

    pub fn tick(self: *@This()) !Runspace.RunspaceReport {
        const initial_len = self.slots.items.len;
        var index: usize = 0;
        while (index < initial_len) : (index += 1) {
            switch (self.slots.items[index].status) {
                .runnable => _ = try self.stepAt(index),
                else => {},
            }
        }
        return self.report();
    }

    pub fn stepOne(self: *@This()) !Runspace.RunspaceEvent {
        for (self.slots.items, 0..) |slot, index| {
            switch (slot.status) {
                .runnable => return self.stepAt(index),
                else => {},
            }
        }
        return error.InvalidRunspaceTransition;
    }

    pub fn step(self: *@This(), handle: RunHandle) !Runspace.RunspaceEvent {
        return self.stepAt(try self.slotIndex(handle));
    }

    pub fn respond(self: *@This(), mailbox_id: u64, response: Frame.Response) !Runspace.RunspaceEvent {
        const pending = try self.mailbox.get(mailbox_id);
        try pending.validateResponse(response);
        const index = try self.slotIndex(pending.handle);
        var slot = &self.slots.items[index];
        if (slot.pending_mailbox_id != mailbox_id or slot.status != .parked_on_port) return error.StaleRunHandle;
        var responded_summary: []u8 = "";
        var responded_summary_owned = false;
        defer if (responded_summary_owned) self.allocator.free(responded_summary);
        var resumed_summary: []u8 = "";
        var resumed_summary_owned = false;
        defer if (resumed_summary_owned) self.allocator.free(resumed_summary);
        var failed_response_summary: []u8 = "";
        var failed_response_summary_owned = false;
        defer if (failed_response_summary_owned) self.allocator.free(failed_response_summary);
        var failed_run_summary: []u8 = "";
        var failed_run_summary_owned = false;
        defer if (failed_run_summary_owned) self.allocator.free(failed_run_summary);
        switch (response.status) {
            .responded => {
                try self.ensureEventCapacity(2);
                try self.events.ensureUnusedCapacity(self.allocator, 2);
                responded_summary = try self.allocator.dupe(u8, "port responded");
                responded_summary_owned = true;
                resumed_summary = try self.allocator.dupe(u8, "run resumed");
                resumed_summary_owned = true;
                failed_response_summary = try self.allocator.dupe(u8, "port response failed");
                failed_response_summary_owned = true;
                failed_run_summary = try self.allocator.dupe(u8, "run failed after response");
                failed_run_summary_owned = true;
                const accounting = try self.responseFrameAccounting(response);
                if (slot.driver) |driver| {
                    driver.beforeResponse(pending.world_port_id, .responded, accounting.response_bytes, accounting.value_image_bytes) catch |err| {
                        if (err == error.HandlerPending and driver.supervisionInterrupted()) {
                            return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual response parked on supervision");
                        }
                        if (err == error.BudgetExceeded and driver.supervisionInterrupted()) {
                            return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual response parked on supervision");
                        }
                        if (err == error.BudgetExceeded) {
                            try self.failPendingPortAndSlot(
                                mailbox_id,
                                slot,
                                response,
                                "manual response supervision failed",
                                failed_response_summary,
                                failed_run_summary,
                            );
                            failed_response_summary_owned = false;
                            failed_run_summary_owned = false;
                        }
                        return err;
                    };
                }
            },
            .pending => {
                const accounting = try self.responseFrameAccounting(response);
                if (slot.driver) |driver| {
                    try self.ensureEventCapacity(1);
                    try self.events.ensureUnusedCapacity(self.allocator, 1);
                    driver.beforeResponse(pending.world_port_id, .pending, accounting.response_bytes, accounting.value_image_bytes) catch |err| {
                        if (err == error.HandlerPending and driver.supervisionInterrupted()) {
                            return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual pending response parked on supervision");
                        }
                        if (err == error.BudgetExceeded and driver.supervisionInterrupted()) {
                            return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual pending response parked on supervision");
                        }
                        return err;
                    };
                    return error.HandlerPending;
                }
                if (slot.supervisor) |*supervisor| {
                    try self.ensureEventCapacity(1);
                    try self.events.ensureUnusedCapacity(self.allocator, 1);
                    supervisor.afterAdapterResponse(.{
                        .world_port_id = pending.world_port_id,
                        .status = .pending,
                        .response_bytes = accounting.response_bytes,
                        .value_image_bytes = accounting.value_image_bytes,
                    }) catch |err| {
                        if ((err == error.HandlerPending or err == error.BudgetExceeded) and supervisor.interrupted) {
                            return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual pending response parked on supervision");
                        }
                        return err;
                    };
                    return error.HandlerPending;
                }
                if (self.config.require_supervision) return error.SupervisionDenied;
                return error.HandlerPending;
            },
            .rejected => return self.finishTerminalResponse(index, mailbox_id, pending, slot, response, .rejected),
            .failed => return self.finishTerminalResponse(index, mailbox_id, pending, slot, response, .failed),
        }
        const response_evidence = if (slot.driver) |driver|
            driver.resumeFrame(response) catch |err| {
                if (err == error.HandlerPending) {
                    if (driver.supervisionInterrupted()) {
                        return self.parkPendingOnSupervision(index, pending, mailbox_id, "manual response parked on supervision");
                    }
                    return err;
                }
                if (driver.failed()) {
                    const failed = try self.mailbox.fail(mailbox_id, "resume failed");
                    try slot.transition(.fail, null);
                    _ = self.appendPreparedEventAssumeCapacity(.{
                        .kind = .port_failed,
                        .run_handle = slot.handle,
                        .pending_port_fingerprint = failed.pending_port_fingerprint,
                        .response_frame_fingerprint = response.frame_fingerprint,
                        .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                        .run_permit_fingerprint = slot.run_permit_fingerprint,
                        .summary = failed_response_summary,
                    });
                    failed_response_summary_owned = false;
                    _ = self.appendPreparedEventAssumeCapacity(.{
                        .kind = .run_failed,
                        .run_handle = slot.handle,
                        .pending_port_fingerprint = failed.pending_port_fingerprint,
                        .response_frame_fingerprint = response.frame_fingerprint,
                        .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                        .run_permit_fingerprint = slot.run_permit_fingerprint,
                        .summary = failed_run_summary,
                    });
                    failed_run_summary_owned = false;
                }
                return err;
            }
        else
            return error.InvalidRunspaceTransition;
        if (response.status == .pending) return error.HandlerPending;
        const effective_response_frame_fingerprint = response_evidence.response_frame_fingerprint orelse response_evidence.response_fingerprint;
        try slot.resumeFromPort(mailbox_id, effective_response_frame_fingerprint, response_evidence.response_value_image_fingerprint);
        const responded = try self.mailbox.markResponded(mailbox_id);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_responded,
            .run_handle = slot.handle,
            .pending_port_fingerprint = responded.pending_port_fingerprint,
            .request_frame_fingerprint = responded.request_frame_fingerprint,
            .response_frame_fingerprint = effective_response_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = responded_summary,
        });
        responded_summary_owned = false;
        const event = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_resumed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = responded.pending_port_fingerprint,
            .request_frame_fingerprint = responded.request_frame_fingerprint,
            .response_frame_fingerprint = effective_response_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = resumed_summary,
        });
        resumed_summary_owned = false;
        return event;
    }

    pub fn respondValue(self: *@This(), mailbox_id: u64, value: anytype) !Runspace.RunspaceEvent {
        const pending = try self.mailbox.get(mailbox_id);
        const request = pending.request_frame orelse return error.InvalidPendingPortTransition;
        var response = try Frame.Response.fromPortableValue(self.allocator, request, pending.expected_response_value_table_id, pending.expected_response_kind, value, .portable);
        defer response.deinit(self.allocator);
        return self.respond(mailbox_id, response);
    }

    fn failPendingPortAndSlot(
        self: *@This(),
        mailbox_id: u64,
        slot: *Runspace.RunSlot,
        response: Frame.Response,
        failure_summary: []const u8,
        port_summary: []u8,
        run_summary: []u8,
    ) !void {
        const failed = try self.mailbox.fail(mailbox_id, failure_summary);
        try slot.transition(.fail, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = failed.request_frame_fingerprint,
            .response_frame_fingerprint = response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = port_summary,
        });
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = failed.request_frame_fingerprint,
            .response_frame_fingerprint = response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = run_summary,
        });
    }

    fn terminalResponseForPending(pending: Runspace.PendingPort, status: ResponseStatus, reason: []const u8) !Frame.Response {
        if (status != .rejected and status != .failed) return error.InvalidPendingPortTransition;
        const request = pending.request_frame orelse return error.InvalidPendingPortTransition;
        const status_seed: u64 = switch (status) {
            .rejected => 0x7275_6e73_7061_6365,
            .failed => 0x6661_696c_706f_7274,
            else => unreachable,
        };
        const response_fingerprint = pending.request_fingerprint ^ pending.request_frame_fingerprint ^ status_seed;
        return Frame.Response.init(.{
            .world_surface_fingerprint = request.world_surface_fingerprint,
            .target_certificate_fingerprint = request.target_certificate_fingerprint,
            .world_port_id = request.world_port_id,
            .request_fingerprint = request.request_fingerprint,
            .response_kind = pending.expected_response_kind,
            .response_value_table_id = pending.expected_response_value_table_id,
            .response_fingerprint = response_fingerprint,
            .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
            .status = status,
            .reason = reason,
        });
    }

    fn routeTerminalResponse(self: *@This(), index: usize, mailbox_id: u64, pending: Runspace.PendingPort, slot: *Runspace.RunSlot, response: Frame.Response, status: ResponseStatus) !?Runspace.RunspaceEvent {
        if (status != .rejected and status != .failed) return error.InvalidPendingPortTransition;
        if (response.status != status) return error.InvalidPendingPortTransition;
        try pending.validateResponse(response);
        var failed_event_pair = try self.prepareEventPair(
            2,
            "terminal port response failed",
            "run failed after terminal port response",
        );
        defer failed_event_pair.deinit(self.allocator);
        const accounting = try self.responseFrameAccounting(response);
        if (slot.driver) |driver| {
            driver.beforeTerminalResponse(pending.world_port_id, status, accounting.response_bytes, accounting.value_image_bytes) catch |err| {
                if ((err == error.HandlerPending or err == error.BudgetExceeded) and driver.supervisionInterrupted()) {
                    return try self.parkPendingOnSupervision(index, pending, mailbox_id, "terminal response parked on supervision");
                }
                if (err == error.BudgetExceeded) {
                    try self.failPendingPortAndSlot(
                        mailbox_id,
                        slot,
                        response,
                        "terminal response supervision failed",
                        failed_event_pair.takeFirst(),
                        failed_event_pair.takeSecond(),
                    );
                }
                return err;
            };
            driver.resumeTerminalFrame(response) catch |err| {
                if ((err == error.HandlerPending or err == error.BudgetExceeded) and driver.supervisionInterrupted()) {
                    return try self.parkPendingOnSupervision(index, pending, mailbox_id, "terminal response parked on supervision");
                }
                try self.failPendingPortAndSlot(
                    mailbox_id,
                    slot,
                    response,
                    "terminal response failed",
                    failed_event_pair.takeFirst(),
                    failed_event_pair.takeSecond(),
                );
                return err;
            };
        } else if (slot.supervisor) |*supervisor| {
            supervisor.afterAdapterResponse(.{
                .world_port_id = pending.world_port_id,
                .status = status,
                .response_bytes = accounting.response_bytes,
                .value_image_bytes = accounting.value_image_bytes,
            }) catch |err| {
                if ((err == error.HandlerPending or err == error.BudgetExceeded) and supervisor.interrupted) {
                    return try self.parkPendingOnSupervision(index, pending, mailbox_id, "terminal response parked on supervision");
                }
                return err;
            };
        } else if (self.config.require_supervision) {
            return error.SupervisionDenied;
        }
        return null;
    }

    fn terminalPortEventKind(status: ResponseStatus) Runspace.EventKind {
        return switch (status) {
            .rejected => .port_rejected,
            .failed => .port_failed,
            else => unreachable,
        };
    }

    fn terminalPortSummary(status: ResponseStatus) []const u8 {
        return switch (status) {
            .rejected => "port rejected",
            .failed => "port failed",
            else => unreachable,
        };
    }

    fn terminalRunSummary(status: ResponseStatus) []const u8 {
        return switch (status) {
            .rejected => "run failed after port rejection",
            .failed => "run failed after port failure",
            else => unreachable,
        };
    }

    fn consumeTerminalMailbox(self: *@This(), mailbox_id: u64, status: ResponseStatus, reason: []const u8) !Runspace.PendingPort {
        return switch (status) {
            .rejected => self.mailbox.cancel(mailbox_id, reason),
            .failed => self.mailbox.fail(mailbox_id, reason),
            else => unreachable,
        };
    }

    fn finishTerminalResponse(self: *@This(), index: usize, mailbox_id: u64, pending: Runspace.PendingPort, slot: *Runspace.RunSlot, response: Frame.Response, status: ResponseStatus) !Runspace.RunspaceEvent {
        var event_pair = try self.prepareEventPair(
            2,
            terminalPortSummary(status),
            terminalRunSummary(status),
        );
        defer event_pair.deinit(self.allocator);
        if (try self.routeTerminalResponse(index, mailbox_id, pending, slot, response, status)) |event| return event;
        const consumed = try self.consumeTerminalMailbox(mailbox_id, status, response.reason orelse "");
        try slot.transition(.fail, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = terminalPortEventKind(status),
            .run_handle = slot.handle,
            .pending_port_fingerprint = consumed.pending_port_fingerprint,
            .request_frame_fingerprint = consumed.request_frame_fingerprint,
            .response_frame_fingerprint = response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeFirst(),
        });
        return self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = consumed.pending_port_fingerprint,
            .request_frame_fingerprint = consumed.request_frame_fingerprint,
            .response_frame_fingerprint = response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeSecond(),
        });
    }

    const TerminalPendingRoute = struct {
        response: Frame.Response,
        parked_event: ?Runspace.RunspaceEvent = null,
    };

    fn routeTerminalPending(self: *@This(), index: usize, mailbox_id: u64, pending: Runspace.PendingPort, slot: *Runspace.RunSlot, status: ResponseStatus, reason: []const u8) !TerminalPendingRoute {
        var response = try terminalResponseForPending(pending, status, reason);
        errdefer response.deinit(self.allocator);
        const parked_event = try self.routeTerminalResponse(index, mailbox_id, pending, slot, response, status);
        return .{
            .response = response,
            .parked_event = parked_event,
        };
    }

    fn parkPendingOnSupervision(self: *@This(), index: usize, pending: Runspace.PendingPort, mailbox_id: u64, event_summary: []const u8) !Runspace.RunspaceEvent {
        const event_summary_bytes = try self.prepareEventSummary(event_summary);
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary_bytes);
        var slot = &self.slots.items[index];
        slot.status = .parked_on_supervision;
        slot.pending_mailbox_id = mailbox_id;
        slot.current_state = slot.transitionState(.parked_on_port, pending.turn_index, pending.request_frame_fingerprint);
        const event = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_parked_on_supervision,
            .run_handle = slot.handle,
            .pending_port_fingerprint = pending.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_summary_bytes,
        });
        summary_owned = false;
        return event;
    }

    pub fn reject(self: *@This(), mailbox_id: u64, reason: []const u8) !Runspace.RunspaceEvent {
        const pending = try self.mailbox.get(mailbox_id);
        if (pending.status != .pending) return error.PendingPortConsumed;
        const index = try self.slotIndex(pending.handle);
        var slot = &self.slots.items[index];
        if (slot.pending_mailbox_id != mailbox_id or slot.status != .parked_on_port) return error.StaleRunHandle;
        var event_pair = try self.prepareEventPair(2, "port rejected", "run failed after port rejection");
        defer event_pair.deinit(self.allocator);
        var routed = try self.routeTerminalPending(index, mailbox_id, pending, slot, .rejected, reason);
        defer routed.response.deinit(self.allocator);
        if (routed.parked_event) |event| return event;
        const cancelled = try self.mailbox.cancel(mailbox_id, reason);
        try slot.transition(.fail, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_rejected,
            .run_handle = slot.handle,
            .pending_port_fingerprint = cancelled.pending_port_fingerprint,
            .request_frame_fingerprint = cancelled.request_frame_fingerprint,
            .response_frame_fingerprint = routed.response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeFirst(),
        });
        return self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = cancelled.pending_port_fingerprint,
            .request_frame_fingerprint = cancelled.request_frame_fingerprint,
            .response_frame_fingerprint = routed.response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeSecond(),
        });
    }

    pub fn fail(self: *@This(), mailbox_id: u64, reason: []const u8) !Runspace.RunspaceEvent {
        const pending = try self.mailbox.get(mailbox_id);
        if (pending.status != .pending) return error.PendingPortConsumed;
        const index = try self.slotIndex(pending.handle);
        var slot = &self.slots.items[index];
        if (slot.pending_mailbox_id != mailbox_id or slot.status != .parked_on_port) return error.StaleRunHandle;
        var event_pair = try self.prepareEventPair(2, "port failed", "run failed after port failure");
        defer event_pair.deinit(self.allocator);
        var routed = try self.routeTerminalPending(index, mailbox_id, pending, slot, .failed, reason);
        defer routed.response.deinit(self.allocator);
        if (routed.parked_event) |event| return event;
        const failed = try self.mailbox.fail(mailbox_id, reason);
        try slot.transition(.fail, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = failed.request_frame_fingerprint,
            .response_frame_fingerprint = routed.response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeFirst(),
        });
        return self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = failed.request_frame_fingerprint,
            .response_frame_fingerprint = routed.response.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeSecond(),
        });
    }

    pub fn exportRun(self: *@This(), handle: RunHandle) !RunImage {
        const index = try self.slotIndex(handle);
        var slot = &self.slots.items[index];
        if (!Runspace.canTransition(slot.status, .exported)) return error.InvalidRunspaceTransition;
        const pending = if (slot.status == .parked_on_port) pending: {
            const mailbox_id = slot.pending_mailbox_id orelse return error.HandoffPendingFrameMismatch;
            const pending_port = try self.mailbox.get(mailbox_id);
            if (pending_port.request_frame == null) return error.HandoffPendingFrameMismatch;
            break :pending pending_port;
        } else if (slot.status == .parked_on_supervision) pending: {
            const mailbox_id = slot.pending_mailbox_id orelse break :pending null;
            const pending_port = try self.mailbox.get(mailbox_id);
            if (pending_port.request_frame == null) return error.HandoffPendingFrameMismatch;
            break :pending pending_port;
        } else null;
        const event_summary = try self.prepareEventSummary("run exported");
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary);
        var supervisor_snapshot = try self.snapshotSlotSupervisor(index);
        defer supervisor_snapshot.deinit(self.allocator);
        try self.beforeSlotHandoffExport(index);
        const image = self.snapshotSlotImage(index) catch |err| {
            supervisor_snapshot.restore(self, index);
            return err;
        };
        errdefer {
            var owned = image;
            owned.deinit(self.allocator);
        }
        const exported = if (pending) |pending_port| try self.mailbox.markExported(pending_port.mailbox_id) else null;
        try slot.transition(.@"export", null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_exported,
            .run_handle = slot.handle,
            .pending_port_fingerprint = if (exported) |pending_port| pending_port.pending_port_fingerprint else null,
            .request_frame_fingerprint = if (pending) |pending_port| pending_port.request_frame_fingerprint else null,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
            .summary = event_summary,
        });
        summary_owned = false;
        return image;
    }

    fn previewExportRun(self: *@This(), handle: RunHandle) !RunImage {
        const index = try self.slotIndex(handle);
        const slot = &self.slots.items[index];
        if (!Runspace.canTransition(slot.status, .exported)) return error.InvalidRunspaceTransition;
        if (slot.status == .parked_on_port) {
            const mailbox_id = slot.pending_mailbox_id orelse return error.HandoffPendingFrameMismatch;
            const pending_port = try self.mailbox.get(mailbox_id);
            if (pending_port.request_frame == null) return error.HandoffPendingFrameMismatch;
        } else if (slot.status == .parked_on_supervision) {
            if (slot.pending_mailbox_id) |mailbox_id| {
                const pending_port = try self.mailbox.get(mailbox_id);
                if (pending_port.request_frame == null) return error.HandoffPendingFrameMismatch;
            }
        }
        var supervisor_snapshot = try self.snapshotSlotSupervisor(index);
        defer supervisor_snapshot.deinit(self.allocator);
        errdefer supervisor_snapshot.restore(self, index);
        try self.beforeSlotHandoffExport(index);
        const image = try self.snapshotSlotImage(index);
        supervisor_snapshot.restore(self, index);
        return image;
    }

    fn previewResultRun(self: *@This(), handle: RunHandle) !RunImage {
        const index = try self.slotIndex(handle);
        const slot = &self.slots.items[index];
        if (slot.status != .completed) return error.InvalidRunspaceTransition;
        return self.snapshotSlotImage(index);
    }

    pub fn exportPending(self: *@This(), mailbox_id: u64) !RunImage {
        const pending = try self.mailbox.get(mailbox_id);
        if (pending.status != .pending) return error.PendingPortConsumed;
        const index = try self.slotIndex(pending.handle);
        var slot = &self.slots.items[index];
        if (slot.pending_mailbox_id != mailbox_id or (slot.status != .parked_on_port and slot.status != .parked_on_supervision)) return error.StaleRunHandle;
        const event_summary = try self.prepareEventSummary("pending run exported");
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary);
        var supervisor_snapshot = try self.snapshotSlotSupervisor(index);
        defer supervisor_snapshot.deinit(self.allocator);
        try self.beforeSlotHandoffExport(index);
        var image = self.snapshotSlotImage(index) catch |err| {
            supervisor_snapshot.restore(self, index);
            return err;
        };
        errdefer image.deinit(self.allocator);
        const exported = try self.mailbox.markExported(mailbox_id);
        try slot.transition(.@"export", null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_exported,
            .run_handle = slot.handle,
            .pending_port_fingerprint = exported.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
            .summary = event_summary,
        });
        summary_owned = false;
        return image;
    }

    pub fn exportHandoff(self: *@This(), handle: RunHandle) !RunImage {
        return self.exportRun(handle);
    }

    const SlotSupervisorSnapshot = struct {
        supervisor: ?Supervision.Supervisor = null,
        from_driver: bool = false,
        owns_supervisor: bool = false,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            _ = allocator;
            if (self.owns_supervisor) {
                if (self.supervisor) |*supervisor| supervisor.deinit();
            }
            self.supervisor = null;
            self.owns_supervisor = false;
        }

        fn restore(self: *@This(), runspace: *Runspace, index: usize) void {
            if (!self.owns_supervisor) return;
            var slot = &runspace.slots.items[index];
            if (self.from_driver) {
                if (slot.driver) |driver| {
                    driver.restoreSupervisor(runspace.allocator, self.supervisor);
                    self.supervisor = null;
                    self.owns_supervisor = false;
                    return;
                }
            } else if (slot.supervisor != null) {
                slot.supervisor.?.deinit();
                slot.supervisor = self.supervisor;
                self.supervisor = null;
                self.owns_supervisor = false;
                return;
            }
        }
    };

    fn snapshotSlotSupervisor(self: *@This(), index: usize) !SlotSupervisorSnapshot {
        const slot = &self.slots.items[index];
        if (slot.driver) |driver| {
            if (try driver.cloneSupervisor(self.allocator)) |supervisor| {
                return .{
                    .supervisor = supervisor,
                    .from_driver = true,
                    .owns_supervisor = true,
                };
            }
        }
        if (slot.supervisor) |supervisor| {
            return .{
                .supervisor = try supervisor.clone(self.allocator),
                .from_driver = false,
                .owns_supervisor = true,
            };
        }
        return .{};
    }

    fn beforeSlotHandoffExport(self: *@This(), index: usize) !void {
        var slot = &self.slots.items[index];
        const interrupted_export = slot.status == .parked_on_supervision;
        if (slot.driver) |driver| {
            if (interrupted_export and driver.supervisionInterrupted()) {
                try driver.beforeInterruptedHandoffExport();
            } else {
                try driver.beforeHandoffExport();
            }
            if (driver.hasSupervisor()) return;
        }
        if (slot.supervisor) |*supervisor| {
            if (interrupted_export and supervisor.interrupted) {
                try supervisor.beforeInterruptedHandoffExport();
            } else {
                try supervisor.beforeHandoffExport();
            }
            return;
        }
        if (self.config.require_supervision) return error.SupervisionDenied;
    }

    fn beforeSlotCheckpoint(self: *@This(), index: usize, value_image_bytes: usize) !void {
        var slot = &self.slots.items[index];
        if (slot.driver) |driver| {
            try driver.beforeCheckpoint(value_image_bytes);
            if (driver.hasSupervisor()) return;
        }
        if (slot.supervisor) |*supervisor| {
            try supervisor.beforeCheckpoint(value_image_bytes);
            return;
        }
        if (self.config.require_supervision) return error.SupervisionDenied;
    }

    fn beforeSlotBranch(self: *@This(), index: usize, depth: usize) !void {
        var slot = &self.slots.items[index];
        if (slot.driver) |driver| {
            try driver.beforeBranch(depth);
            if (driver.hasSupervisor()) return;
        }
        if (slot.supervisor) |*supervisor| {
            try supervisor.beforeBranch(depth);
            return;
        }
        if (self.config.require_supervision) return error.SupervisionDenied;
    }

    fn cloneSlotSupervisorForBranch(self: *@This(), slot: Runspace.RunSlot, depth: usize) !?Supervision.Supervisor {
        var branch_supervisor: ?Supervision.Supervisor = if (slot.driver) |driver|
            try driver.cloneSupervisor(self.allocator)
        else if (slot.supervisor) |supervisor|
            try supervisor.clone(self.allocator)
        else
            null;
        errdefer if (branch_supervisor) |*supervisor| supervisor.deinit();
        if (branch_supervisor) |*supervisor| try supervisor.beforeBranch(depth);
        return branch_supervisor;
    }

    fn slotIndexByHandleFingerprint(self: *const @This(), handle_fingerprint: u64) ?usize {
        for (self.slots.items, 0..) |slot, index| {
            if (slot.handle.handle_fingerprint == handle_fingerprint) return index;
        }
        return null;
    }

    fn branchDepthForIndex(self: *const @This(), index: usize) !usize {
        var depth: usize = 0;
        var current_index = index;
        var guard: usize = 0;
        while (self.slots.items[current_index].parent_run_handle_fingerprint) |parent_fingerprint| {
            guard += 1;
            if (guard > self.slots.items.len) return error.InvalidRunspaceTransition;
            current_index = self.slotIndexByHandleFingerprint(parent_fingerprint) orelse return error.StaleRunHandle;
            depth += 1;
        }
        return depth;
    }

    fn childBranchDepthForIndex(self: *const @This(), index: usize) !usize {
        const depth = try self.branchDepthForIndex(index);
        return if (depth == std.math.maxInt(usize)) depth else depth + 1;
    }

    pub fn checkpoint(self: *@This(), handle: RunHandle) !Timeline.Checkpoint {
        const index = try self.slotIndex(handle);
        const slot = &self.slots.items[index];
        const checkpoint_status = checkpointStatusForSlot(slot.*);
        const checkpoint_value = Timeline.Checkpoint.init(.{
            .world_surface_fingerprint = slot.target_ref.world_surface_fingerprint,
            .target_certificate_fingerprint = slot.target_ref.target_certificate_fingerprint,
            .event_index = self.events.items.len,
            .turn_index = slot.current_state.turn_index,
            .current_request_fingerprint = slot.current_state.pending_request_fingerprint,
            .last_response_fingerprint = slot.current_state.final_response_fingerprint,
            .transcript_prefix_fingerprint = slot.current_state.transcript_image_fingerprint orelse slot.current_state.run_state_fingerprint,
            .branch_id = slot.branch_id orelse 0,
            .status = checkpoint_status,
        });
        const event_summary = try self.prepareEventSummary("checkpoint created");
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary);
        try self.beforeSlotCheckpoint(index, 0);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .checkpoint_created,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .checkpoint_fingerprint = checkpoint_value.checkpoint_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_summary,
        });
        summary_owned = false;
        return checkpoint_value;
    }

    pub fn branch(self: *@This(), handle: RunHandle, checkpoint_value: Timeline.Checkpoint, options: anytype) !RunHandle {
        const index = try self.slotIndex(handle);
        const parent = self.slots.items[index];
        try self.validateSlotCheckpoint(parent, checkpoint_value);
        try self.ensureEventCapacity(1);
        const branch_depth = try self.childBranchDepthForIndex(index);
        var branch_supervisor = self.cloneSlotSupervisorForBranch(parent, branch_depth) catch |err| {
            switch (err) {
                error.BranchDenied, error.BudgetExceeded => {
                    self.beforeSlotBranch(index, branch_depth) catch |live_err| return live_err;
                },
                else => {},
            }
            return err;
        };
        var branch_supervisor_owned = branch_supervisor != null;
        errdefer if (branch_supervisor_owned) {
            if (branch_supervisor) |*supervisor| supervisor.deinit();
        };
        const next_run_id_before = self.next_run_id;
        var installed = false;
        errdefer if (!installed) {
            self.next_run_id = next_run_id_before;
        };
        const branch_id = self.next_run_id;
        const branch_handle = try self.nextHandle(.{
            .target_ref_fingerprint = parent.target_ref.target_ref_fingerprint,
            .admission_receipt_fingerprint = parent.admission_receipt_fingerprint,
            .permit_fingerprint = parent.run_permit_fingerprint,
            .branch_id = branch_id,
        });
        var branch_state = parent.current_state;
        branch_state.branch_id = branch_id;
        branch_state.checkpoint_fingerprint = checkpoint_value.checkpoint_fingerprint;
        branch_state.run_state_fingerprint = fingerprintRunState(branch_state);
        const slot = Runspace.RunSlot.fromState(.{
            .handle = branch_handle,
            .target_ref = parent.target_ref,
            .current_state = branch_state,
            .status = .admitted,
            .admission_receipt_fingerprint = parent.admission_receipt_fingerprint,
            .run_permit_fingerprint = parent.run_permit_fingerprint,
            .run_receipt_fingerprint = parent.run_receipt_fingerprint,
            .branch_id = branch_id,
            .parent_run_handle_fingerprint = parent.handle.handle_fingerprint,
            .checkpoint_fingerprint = checkpoint_value.checkpoint_fingerprint,
            .target_match_fingerprint = parent.target_match_fingerprint,
            .module_ref_fingerprint = parent.module_ref_fingerprint,
            .supervisor = branch_supervisor,
        });
        const summary_text = if (@hasField(@TypeOf(options), "summary")) @field(options, "summary") else "run branch created";
        try self.prepareInstallSlot();
        const event_summary = try self.prepareEventSummary(summary_text);
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(event_summary);
        try self.beforeSlotBranch(index, branch_depth);
        self.slots.appendAssumeCapacity(slot);
        branch_supervisor_owned = false;
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_branch_created,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .checkpoint_fingerprint = slot.checkpoint_fingerprint,
            .admission_receipt_fingerprint = slot.admission_receipt_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_summary,
        });
        summary_owned = false;
        installed = true;
        return branch_handle;
    }

    fn checkpointStatusForSlot(slot: Runspace.RunSlot) Timeline.Checkpoint.Status {
        return switch (slot.status) {
            .admitted, .runnable, .running => .running,
            .parked_on_port, .parked_on_supervision => .parked_on_port,
            .completed => .completed,
            .exported => switch (slot.current_state.status) {
                .not_started, .running => .running,
                .parked_on_port => .parked_on_port,
                .completed => .completed,
                .failed => .failed,
                .parked_on_supervision => .parked_on_port,
            },
            .failed, .rejected => .failed,
        };
    }

    fn receiptFinalStatusForRunState(state: RunState) RunReceipt.FinalStatus {
        return switch (state.status) {
            .not_started, .running => .interrupted,
            .parked_on_port => .parked,
            .completed => .completed,
            .failed => .failed,
            .parked_on_supervision => .interrupted,
        };
    }

    fn slotTranscriptPrefixFingerprint(slot: Runspace.RunSlot) u64 {
        return slot.current_state.transcript_image_fingerprint orelse slot.current_state.run_state_fingerprint;
    }

    fn validateSlotCheckpoint(self: *const @This(), slot: Runspace.RunSlot, checkpoint_value: Timeline.Checkpoint) !void {
        if (fingerprintCheckpoint(checkpoint_value) != checkpoint_value.checkpoint_fingerprint) return error.HandoffCheckpointMismatch;
        if (slot.target_ref.world_surface_fingerprint != checkpoint_value.world_surface_fingerprint) return error.HandoffCheckpointMismatch;
        if (slot.target_ref.target_certificate_fingerprint != checkpoint_value.target_certificate_fingerprint) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.event_index > self.events.items.len) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.turn_index != slot.current_state.turn_index) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.current_request_fingerprint != slot.current_state.pending_request_fingerprint) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.last_response_fingerprint != slot.current_state.final_response_fingerprint) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.transcript_prefix_fingerprint != slotTranscriptPrefixFingerprint(slot)) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.branch_id != (slot.branch_id orelse 0)) return error.HandoffCheckpointMismatch;
        if (checkpoint_value.status != checkpointStatusForSlot(slot)) return error.HandoffCheckpointMismatch;
        if (!self.hasCheckpointWitness(slot.handle, checkpoint_value.checkpoint_fingerprint)) return error.HandoffCheckpointMismatch;
    }

    fn hasCheckpointWitness(self: *const @This(), handle: RunHandle, checkpoint_fingerprint: u64) bool {
        for (self.events.items) |event| {
            if (event.kind == .checkpoint_created and
                event.run_handle.handle_fingerprint == handle.handle_fingerprint and
                event.checkpoint_fingerprint != null and
                event.checkpoint_fingerprint.? == checkpoint_fingerprint)
            {
                return true;
            }
        }
        return false;
    }

    pub fn listBranches(self: *const @This(), handle: RunHandle, allocator: std.mem.Allocator) ![]RunHandle {
        const index = try self.slotIndex(handle);
        const parent = self.slots.items[index];
        var branches: std.ArrayList(RunHandle) = .empty;
        errdefer branches.deinit(allocator);
        for (self.slots.items) |slot| {
            if (slot.handle.handle_fingerprint == parent.handle.handle_fingerprint) continue;
            if (slot.target_ref.target_ref_fingerprint != parent.target_ref.target_ref_fingerprint) continue;
            if (slot.parent_run_handle_fingerprint == parent.handle.handle_fingerprint and slot.branch_id != null) try branches.append(allocator, slot.handle);
        }
        return branches.toOwnedSlice(allocator);
    }

    pub fn summary(self: *const @This()) Runspace.RunspaceReport {
        return self.report();
    }

    pub fn report(self: *const @This()) Runspace.RunspaceReport {
        var result = Runspace.RunspaceReport{
            .runspace_fingerprint = self.runspace_fingerprint,
            .event_count = self.events.items.len,
            .run_count = self.slots.items.len,
            .runnable_count = 0,
            .parked_count = 0,
            .completed_count = 0,
            .failed_count = 0,
            .pending_port_count = self.mailbox.pendingCount(),
            .emitted_events = self.events.items,
        };
        for (self.slots.items) |slot| {
            switch (slot.status) {
                .runnable, .running => result.runnable_count += 1,
                .parked_on_port, .parked_on_supervision => result.parked_count += 1,
                .completed => result.completed_count += 1,
                .exported => switch (slot.current_state.status) {
                    .completed => result.completed_count += 1,
                    .parked_on_port, .parked_on_supervision => result.parked_count += 1,
                    .failed => result.failed_count += 1,
                    .not_started, .running => {},
                },
                .failed, .rejected => result.failed_count += 1,
                .admitted => {},
            }
            if (slot.supervisor) |supervisor| {
                result.warning_count += supervisor.warning_count;
                if (supervisor.blocker != null) result.blocker_count += 1;
            }
            if (slot.driver) |driver| {
                result.warning_count += driver.supervisorWarningCount();
                result.blocker_count += driver.supervisorBlockerCount();
            }
        }
        return result;
    }

    fn nextHandle(self: *@This(), args: struct {
        target_ref_fingerprint: u64,
        admission_receipt_fingerprint: ?u64 = null,
        permit_fingerprint: ?u64 = null,
        branch_id: ?u64 = null,
    }) !RunHandle {
        if (self.config.max_runs) |max| {
            if (self.activeRunCountForCapacity() >= max) return error.BudgetExceeded;
        }
        const handle = RunHandle.init(.{
            .runspace_fingerprint = self.runspace_fingerprint,
            .local_run_id = self.next_run_id,
            .target_ref_fingerprint = args.target_ref_fingerprint,
            .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
            .permit_fingerprint = args.permit_fingerprint,
            .branch_id = args.branch_id,
            .generation = 0,
        });
        self.next_run_id += 1;
        return handle;
    }

    fn activeRunCountForCapacity(self: *const @This()) usize {
        var count: usize = 0;
        for (self.slots.items) |slot| {
            if (!self.slotCountsAgainstMaxRuns(slot)) continue;
            count += 1;
        }
        return count;
    }

    fn slotCountsAgainstMaxRuns(self: *const @This(), slot: Runspace.RunSlot) bool {
        if (self.config.preserve_completed_runs) return true;
        return switch (slot.status) {
            .completed => false,
            .exported => slot.current_state.status != .completed,
            else => true,
        };
    }

    fn prepareInstallSlot(self: *@This()) !void {
        if (self.config.max_events) |max| {
            if (self.events.items.len >= max) return error.BudgetExceeded;
        }
        try self.slots.ensureUnusedCapacity(self.allocator, 1);
    }

    fn installSlot(self: *@This(), slot: Runspace.RunSlot, event_kind: Runspace.EventKind, summary_text: []const u8) !void {
        try self.prepareInstallSlot();
        try self.installPreparedSlot(slot, event_kind, summary_text);
    }

    fn installPreparedSlot(self: *@This(), slot: Runspace.RunSlot, event_kind: Runspace.EventKind, summary_text: []const u8) !void {
        self.slots.appendAssumeCapacity(slot);
        var slot_appended = true;
        errdefer if (slot_appended) {
            var appended_slot = &self.slots.items[self.slots.items.len - 1];
            appended_slot.deinit(self.allocator);
            self.slots.shrinkRetainingCapacity(self.slots.items.len - 1);
        };
        _ = try self.appendEvent(.{
            .kind = event_kind,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .admission_receipt_fingerprint = slot.admission_receipt_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = summary_text,
        });
        slot_appended = false;
    }

    fn appendEvent(self: *@This(), args: struct {
        kind: Runspace.EventKind,
        run_handle: RunHandle,
        pending_port_fingerprint: ?u64 = null,
        request_frame_fingerprint: ?u64 = null,
        response_frame_fingerprint: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        run_state_fingerprint: u64,
        run_receipt_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        summary: []const u8 = "",
    }) !Runspace.RunspaceEvent {
        if (self.config.max_events) |max| {
            if (self.events.items.len >= max) return error.BudgetExceeded;
        }
        const summary_bytes = try self.allocator.dupe(u8, args.summary);
        var summary_owned = true;
        errdefer if (summary_owned) self.allocator.free(summary_bytes);
        const event = Runspace.RunspaceEvent.init(.{
            .kind = args.kind,
            .runspace_fingerprint = self.runspace_fingerprint,
            .event_index = self.next_event_index,
            .run_handle = args.run_handle,
            .pending_port_fingerprint = args.pending_port_fingerprint,
            .request_frame_fingerprint = args.request_frame_fingerprint,
            .response_frame_fingerprint = args.response_frame_fingerprint,
            .checkpoint_fingerprint = args.checkpoint_fingerprint,
            .run_state_fingerprint = args.run_state_fingerprint,
            .run_receipt_fingerprint = args.run_receipt_fingerprint,
            .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
            .run_permit_fingerprint = args.run_permit_fingerprint,
            .summary = summary_bytes,
            .owns_summary = true,
        });
        try self.events.append(self.allocator, event);
        summary_owned = false;
        self.next_event_index += 1;
        return event.borrowed();
    }

    fn prepareEventSummary(self: *@This(), summary_text: []const u8) ![]u8 {
        try self.ensureEventCapacity(1);
        try self.events.ensureUnusedCapacity(self.allocator, 1);
        return self.allocator.dupe(u8, summary_text);
    }

    const PreparedEventPair = struct {
        first: []u8,
        second: []u8,
        owns_first: bool = true,
        owns_second: bool = true,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_first) allocator.free(self.first);
            if (self.owns_second) allocator.free(self.second);
        }

        fn takeFirst(self: *@This()) []u8 {
            self.owns_first = false;
            return self.first;
        }

        fn takeSecond(self: *@This()) []u8 {
            self.owns_second = false;
            return self.second;
        }
    };

    fn prepareEventPair(self: *@This(), additional_events: usize, first_summary: []const u8, second_summary: []const u8) !PreparedEventPair {
        try self.ensureEventCapacity(additional_events);
        try self.events.ensureUnusedCapacity(self.allocator, additional_events);
        const first = try self.allocator.dupe(u8, first_summary);
        errdefer self.allocator.free(first);
        const second = try self.allocator.dupe(u8, second_summary);
        return .{
            .first = first,
            .second = second,
        };
    }

    const PreparedAutoDispatchEvents = struct {
        supervision: []u8,
        failed: PreparedEventPair,
        responded: PreparedEventPair,
        owns_supervision: bool = true,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_supervision) allocator.free(self.supervision);
            self.failed.deinit(allocator);
            self.responded.deinit(allocator);
        }

        fn takeSupervision(self: *@This()) []u8 {
            self.owns_supervision = false;
            return self.supervision;
        }
    };

    fn prepareAutoDispatchEvents(self: *@This()) !PreparedAutoDispatchEvents {
        try self.ensureEventCapacity(4);
        try self.events.ensureUnusedCapacity(self.allocator, 4);
        const supervision = try self.allocator.dupe(u8, "auto-dispatch parked on supervision");
        errdefer self.allocator.free(supervision);
        var failed = try self.prepareEventPair(4, "auto-dispatch port failed", "auto-dispatch failed");
        errdefer failed.deinit(self.allocator);
        const responded = try self.prepareEventPair(4, "port auto-dispatched", "run resumed by auto-dispatch");
        return .{
            .supervision = supervision,
            .failed = failed,
            .responded = responded,
        };
    }

    fn appendPreparedEventAssumeCapacity(self: *@This(), args: struct {
        kind: Runspace.EventKind,
        run_handle: RunHandle,
        pending_port_fingerprint: ?u64 = null,
        request_frame_fingerprint: ?u64 = null,
        response_frame_fingerprint: ?u64 = null,
        checkpoint_fingerprint: ?u64 = null,
        run_state_fingerprint: u64,
        run_receipt_fingerprint: ?u64 = null,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        summary: []u8,
    }) Runspace.RunspaceEvent {
        const event = Runspace.RunspaceEvent.init(.{
            .kind = args.kind,
            .runspace_fingerprint = self.runspace_fingerprint,
            .event_index = self.next_event_index,
            .run_handle = args.run_handle,
            .pending_port_fingerprint = args.pending_port_fingerprint,
            .request_frame_fingerprint = args.request_frame_fingerprint,
            .response_frame_fingerprint = args.response_frame_fingerprint,
            .checkpoint_fingerprint = args.checkpoint_fingerprint,
            .run_state_fingerprint = args.run_state_fingerprint,
            .run_receipt_fingerprint = args.run_receipt_fingerprint,
            .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
            .run_permit_fingerprint = args.run_permit_fingerprint,
            .summary = args.summary,
            .owns_summary = true,
        });
        self.events.appendAssumeCapacity(event);
        self.next_event_index += 1;
        return event.borrowed();
    }

    fn ensureEventCapacity(self: *const @This(), additional_events: usize) !void {
        if (self.config.max_events) |max| {
            if (self.events.items.len + additional_events > max) return error.BudgetExceeded;
        }
    }

    fn rollbackRunspaceMutation(
        self: *@This(),
        slot_count: usize,
        event_count: usize,
        mailbox_count: usize,
        next_run_id: u64,
        next_mailbox_id: u64,
        next_event_index: u64,
    ) void {
        for (self.slots.items[slot_count..]) |*slot| slot.deinit(self.allocator);
        for (self.events.items[event_count..]) |*event| event.deinit(self.allocator);
        for (self.mailbox.pending.items[mailbox_count..]) |*pending_port| pending_port.deinit(self.allocator);
        self.slots.shrinkRetainingCapacity(slot_count);
        self.events.shrinkRetainingCapacity(event_count);
        self.mailbox.pending.shrinkRetainingCapacity(mailbox_count);
        self.next_run_id = next_run_id;
        self.next_mailbox_id = next_mailbox_id;
        self.next_event_index = next_event_index;
    }

    fn snapshotSlotImage(self: *@This(), index: usize) !RunImage {
        const slot = &self.slots.items[index];
        if (slot.driver) |driver| return driver.snapshotRunImage();
        const run_receipt_fingerprint = if (slot.supervisor) |*supervisor|
            supervisor.receipt(
                receiptFinalStatusForRunState(slot.current_state),
                slot.current_state.run_state_fingerprint,
                slot.current_state.transcript_image_fingerprint,
                null,
            ).receipt_fingerprint
        else
            slot.run_receipt_fingerprint;
        if (slot.installed_run_image) |installed_image| {
            var image = try cloneRunImage(self.allocator, installed_image);
            image.current_state = slot.current_state;
            image.prior_run_permit_fingerprint = slot.run_permit_fingerprint;
            image.prior_run_receipt_fingerprint = run_receipt_fingerprint;
            image.module_ref_fingerprint = slot.module_ref_fingerprint;
            refreshRunImageFingerprint(&image);
            return image;
        }
        var pending_frame: ?Frame.Request = null;
        var owns_pending_frame = false;
        errdefer if (owns_pending_frame) {
            if (pending_frame) |*frame| frame.deinit(self.allocator);
        };
        if (slot.pending_mailbox_id) |mailbox_id| {
            const pending = try self.mailbox.get(mailbox_id);
            if (pending.request_frame) |request| {
                pending_frame = try cloneRequestFrame(self.allocator, request);
                owns_pending_frame = true;
            }
        }
        var image = RunImage.init(.{
            .kind = switch (slot.status) {
                .parked_on_port => .parked_run,
                .parked_on_supervision => if (slot.current_state.status == .parked_on_port) .parked_run else .full_target_run,
                .completed, .exported => .completed_run,
                .failed, .rejected => .replay_only_run,
                .admitted, .runnable, .running => .full_target_run,
            },
            .target_ref = slot.target_ref,
            .import_set_fingerprint = 0,
            .current_state = slot.current_state,
            .pending_request_frame = pending_frame,
            .prior_run_permit_fingerprint = slot.run_permit_fingerprint,
            .prior_run_receipt_fingerprint = run_receipt_fingerprint,
            .module_ref_fingerprint = slot.module_ref_fingerprint,
        });
        image.owns_pending_request_frame = owns_pending_frame;
        owns_pending_frame = false;
        return image;
    }

    fn enqueueInstalledPending(self: *@This(), index: usize, request: Frame.Request) !void {
        var slot = &self.slots.items[index];
        var event_pair = try self.prepareEventPair(
            2,
            "installed port enqueued",
            "installed run parked on port",
        );
        defer event_pair.deinit(self.allocator);
        const mailbox_id = self.next_mailbox_id;
        const pending = try self.mailbox.push(.{
            .run_handle = slot.handle,
            .mailbox_id = mailbox_id,
            .request = request,
            .target_ref_fingerprint = slot.target_ref.target_ref_fingerprint,
            .environment_certificate_fingerprint = null,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .inserted_event_index = self.next_event_index,
        });
        self.next_mailbox_id += 1;
        slot.status = .parked_on_port;
        slot.pending_mailbox_id = mailbox_id;
        slot.current_state.pending_request_fingerprint = request.frame_fingerprint;
        slot.current_state.turn_index = request.turn_index;
        slot.current_state.status = .parked_on_port;
        slot.current_state.run_state_fingerprint = fingerprintRunState(slot.current_state);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_enqueued,
            .run_handle = slot.handle,
            .pending_port_fingerprint = pending.pending_port_fingerprint,
            .request_frame_fingerprint = request.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeFirst(),
        });
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_parked_on_port,
            .run_handle = slot.handle,
            .pending_port_fingerprint = pending.pending_port_fingerprint,
            .request_frame_fingerprint = request.frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = event_pair.takeSecond(),
        });
    }

    fn stepAt(self: *@This(), index: usize) !Runspace.RunspaceEvent {
        var slot = &self.slots.items[index];
        if (slot.driver == null) return error.InvalidRunspaceTransition;
        const step_event_capacity: usize = if (slot.driver_world_port_count == 0)
            2
        else if (slot.current_state.final_response_fingerprint != null and slot.current_state.turn_index >= slot.driver_world_port_count)
            2
        else if (self.config.auto_dispatch)
            5
        else
            3;
        try self.ensureEventCapacity(step_event_capacity);
        try self.events.ensureUnusedCapacity(self.allocator, step_event_capacity);
        const stepped_summary = try self.allocator.dupe(u8, "run stepped");
        var stepped_summary_owned = true;
        errdefer if (stepped_summary_owned) self.allocator.free(stepped_summary);
        const completed_summary = try self.allocator.dupe(u8, "run completed");
        var completed_summary_owned = true;
        defer if (completed_summary_owned) self.allocator.free(completed_summary);
        const failed_summary = try self.allocator.dupe(u8, "run failed");
        var failed_summary_owned = true;
        defer if (failed_summary_owned) self.allocator.free(failed_summary);
        try slot.transition(.step, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_stepped,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = stepped_summary,
        });
        stepped_summary_owned = false;
        const driver = slot.driver.?;
        const step_result = driver.nextFrame() catch |err| {
            if (err == error.HandlerPending and driver.supervisionInterrupted()) {
                const supervision_summary = try self.prepareEventSummary("run parked on supervision");
                var supervision_summary_owned = true;
                errdefer if (supervision_summary_owned) self.allocator.free(supervision_summary);
                try slot.transition(.park_on_supervision, null);
                const event = self.appendPreparedEventAssumeCapacity(.{
                    .kind = .run_parked_on_supervision,
                    .run_handle = slot.handle,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = supervision_summary,
                });
                supervision_summary_owned = false;
                return event;
            }
            slot.transition(.fail, null) catch {};
            _ = self.appendPreparedEventAssumeCapacity(.{
                .kind = .run_failed,
                .run_handle = slot.handle,
                .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                .run_permit_fingerprint = slot.run_permit_fingerprint,
                .summary = failed_summary,
            });
            failed_summary_owned = false;
            return err;
        };
        switch (step_result) {
            .done => {
                try slot.transition(.complete, null);
                const event = self.appendPreparedEventAssumeCapacity(.{
                    .kind = .run_completed,
                    .run_handle = slot.handle,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = completed_summary,
                });
                completed_summary_owned = false;
                return event;
            },
            .failed => {
                try slot.transition(.fail, null);
                const event = self.appendPreparedEventAssumeCapacity(.{
                    .kind = .run_failed,
                    .run_handle = slot.handle,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = failed_summary,
                });
                failed_summary_owned = false;
                return event;
            },
            .port_request => |request| {
                var owned_request = request;
                defer owned_request.deinit(self.allocator);
                var event_pair = self.prepareEventPair(
                    if (self.config.auto_dispatch) 4 else 2,
                    "port enqueued",
                    "run parked on port",
                ) catch |err| {
                    return self.failSteppedRunBeforePort(slot, err);
                };
                defer event_pair.deinit(self.allocator);
                var auto_events: ?PreparedAutoDispatchEvents = null;
                defer if (auto_events) |*events| events.deinit(self.allocator);
                if (self.config.auto_dispatch) {
                    auto_events = self.prepareAutoDispatchEvents() catch |err| {
                        return self.failSteppedRunBeforePort(slot, err);
                    };
                }
                self.mailbox.ensurePendingCapacity() catch |err| {
                    return self.failSteppedRunBeforePort(slot, err);
                };
                const mailbox_id = self.next_mailbox_id;
                const pending = self.mailbox.push(.{
                    .run_handle = slot.handle,
                    .mailbox_id = mailbox_id,
                    .request = owned_request,
                    .target_ref_fingerprint = slot.target_ref.target_ref_fingerprint,
                    .environment_certificate_fingerprint = null,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .inserted_event_index = self.next_event_index,
                }) catch |err| {
                    return self.failSteppedRunBeforePort(slot, err);
                };
                self.next_mailbox_id += 1;
                slot.status = .parked_on_port;
                slot.pending_mailbox_id = mailbox_id;
                slot.current_state = slot.transitionState(.parked_on_port, owned_request.turn_index, owned_request.frame_fingerprint);
                _ = self.appendPreparedEventAssumeCapacity(.{
                    .kind = .port_enqueued,
                    .run_handle = slot.handle,
                    .pending_port_fingerprint = pending.pending_port_fingerprint,
                    .request_frame_fingerprint = owned_request.frame_fingerprint,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = event_pair.takeFirst(),
                });
                const parked_event = self.appendPreparedEventAssumeCapacity(.{
                    .kind = .run_parked_on_port,
                    .run_handle = slot.handle,
                    .pending_port_fingerprint = pending.pending_port_fingerprint,
                    .request_frame_fingerprint = owned_request.frame_fingerprint,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = event_pair.takeSecond(),
                });
                if (self.config.auto_dispatch) return self.autoDispatchPending(index, pending, mailbox_id, &auto_events.?);
                return parked_event;
            },
        }
    }

    fn failSteppedRunBeforePort(self: *@This(), slot: *Runspace.RunSlot, err: anyerror) !Runspace.RunspaceEvent {
        slot.transition(.fail, null) catch {};
        _ = self.appendEvent(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = "run failed before port enqueue",
        }) catch {};
        return err;
    }

    fn failAutoDispatchPending(self: *@This(), slot: *Runspace.RunSlot, pending: Runspace.PendingPort, mailbox_id: u64, events: *PreparedAutoDispatchEvents) !void {
        const failed = try self.mailbox.fail(mailbox_id, "auto-dispatch failed");
        try slot.transition(.fail, null);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = events.failed.takeFirst(),
        });
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_failed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = failed.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = events.failed.takeSecond(),
        });
    }

    fn autoDispatchPending(self: *@This(), index: usize, pending: Runspace.PendingPort, mailbox_id: u64, events: *PreparedAutoDispatchEvents) !Runspace.RunspaceEvent {
        var slot = &self.slots.items[index];
        const driver = slot.driver orelse return error.InvalidRunspaceTransition;
        const response_evidence = driver.dispatch() catch |err| {
            if (err == error.HandlerPending and driver.supervisionInterrupted()) {
                slot.status = .parked_on_supervision;
                slot.pending_mailbox_id = mailbox_id;
                slot.current_state = slot.transitionState(.parked_on_port, pending.turn_index, pending.request_frame_fingerprint);
                return self.appendPreparedEventAssumeCapacity(.{
                    .kind = .run_parked_on_supervision,
                    .run_handle = slot.handle,
                    .pending_port_fingerprint = pending.pending_port_fingerprint,
                    .request_frame_fingerprint = pending.request_frame_fingerprint,
                    .run_state_fingerprint = slot.current_state.run_state_fingerprint,
                    .run_permit_fingerprint = slot.run_permit_fingerprint,
                    .summary = events.takeSupervision(),
                });
            }
            try self.failAutoDispatchPending(slot, pending, mailbox_id, events);
            return err;
        };
        const evidence = response_evidence orelse {
            try self.failAutoDispatchPending(slot, pending, mailbox_id, events);
            return error.InvalidRunspaceTransition;
        };
        const responded = try self.mailbox.markResponded(mailbox_id);
        const effective_response_frame_fingerprint = evidence.response_frame_fingerprint orelse evidence.response_fingerprint;
        try slot.resumeFromPort(mailbox_id, effective_response_frame_fingerprint, evidence.response_value_image_fingerprint);
        _ = self.appendPreparedEventAssumeCapacity(.{
            .kind = .port_responded,
            .run_handle = slot.handle,
            .pending_port_fingerprint = responded.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .response_frame_fingerprint = effective_response_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = events.responded.takeFirst(),
        });
        return self.appendPreparedEventAssumeCapacity(.{
            .kind = .run_resumed,
            .run_handle = slot.handle,
            .pending_port_fingerprint = responded.pending_port_fingerprint,
            .request_frame_fingerprint = pending.request_frame_fingerprint,
            .response_frame_fingerprint = effective_response_frame_fingerprint,
            .run_state_fingerprint = slot.current_state.run_state_fingerprint,
            .run_permit_fingerprint = slot.run_permit_fingerprint,
            .summary = events.responded.takeSecond(),
        });
    }

    fn slotIndex(self: *const @This(), handle: RunHandle) !usize {
        try handle.validateForRunspace(self.runspace_fingerprint);
        for (self.slots.items, 0..) |slot, index| {
            if (handle.matchesSlot(slot)) return index;
        }
        return error.StaleRunHandle;
    }

    fn statusFromRunState(state: RunState) RunStatus {
        return switch (state.status) {
            .not_started, .running => .runnable,
            .parked_on_port => .parked_on_port,
            .parked_on_supervision => .parked_on_supervision,
            .completed => .completed,
            .failed => .failed,
        };
    }

    fn statusFromInstallableRunImageState(state: RunState) !RunStatus {
        return switch (state.status) {
            .parked_on_port => .parked_on_port,
            .parked_on_supervision => .parked_on_supervision,
            .completed => .completed,
            .failed => .failed,
            .not_started, .running => error.InvalidRunspaceTransition,
        };
    }
};

pub const Guest = struct {
    pub const Status = enum(u32) {
        ok = 0,
        initialized = 1,
        running = 2,
        parked = 3,
        done = 4,
        failed = 5,
        buffer_too_small = 6,
        invalid_frame = 7,
        invalid_state = 8,
        unknown_pending = 9,
        stale_pending = 10,
        supervision_denied = 11,
        target_mismatch = 12,
        admission_failed = 13,

        pub fn code(self: @This()) u32 {
            return @intFromEnum(self);
        }
    };

    pub const Buffer = struct {
        pub const max_request_bytes: usize = 64 * 1024;
        pub const max_response_bytes: usize = 64 * 1024;
        pub const max_result_bytes: usize = 256 * 1024;
        pub const max_receipt_bytes: usize = 8 * 1024;
        pub const max_transcript_bytes: usize = 256 * 1024;
        pub const max_error_bytes: usize = 1024;
        pub const max_pending_ports: usize = 16;
    };

    pub const Abi = struct {
        pub const version = world_guest_abi_version;
        pub const required_exports = [_][]const u8{
            "world_abi_version",
            "world_init",
            "world_tick",
            "world_status",
            "world_pending_count",
            "world_pending_request_len",
            "world_read_pending_request",
            "world_submit_response",
            "world_result_len",
            "world_read_result",
            "world_receipt_len",
            "world_read_receipt",
            "world_transcript_len",
            "world_read_transcript",
            "world_last_error_len",
            "world_read_last_error",
        };
        pub const optional_exports = [_][]const u8{
            "world_alloc",
            "world_free",
        };
        pub const forbidden_import_fragments = [_][]const u8{
            "wasi",
            "fd_",
            "path_",
            "sock_",
            "random",
            "clock",
            "sched",
            "treaty",
            "provider",
            "handler",
            "boundary",
        };

        pub const Contract = struct {
            abi_version: u32 = version,
            fingerprint_version: u32 = world_guest_abi_contract_fingerprint_version,
            required_export_count: usize = required_exports.len,
            max_request_bytes: usize = Buffer.max_request_bytes,
            max_response_bytes: usize = Buffer.max_response_bytes,
            max_result_bytes: usize = Buffer.max_result_bytes,
            max_receipt_bytes: usize = Buffer.max_receipt_bytes,
            max_transcript_bytes: usize = Buffer.max_transcript_bytes,
            max_error_bytes: usize = Buffer.max_error_bytes,
            max_pending_ports: usize = Buffer.max_pending_ports,

            pub fn fingerprint(self: @This()) u64 {
                var hasher = std.hash.Wyhash.init(0x776f_726c_645f_6775);
                hashU64(&hasher, self.abi_version);
                hashU64(&hasher, self.fingerprint_version);
                inline for (std.meta.fields(Status)) |field| {
                    hashU64(&hasher, @as(u32, @intCast(field.value)));
                }
                hashU64(&hasher, self.required_export_count);
                for (required_exports) |name| {
                    hashU64(&hasher, name.len);
                    hashBytes(&hasher, name);
                }
                hashU64(&hasher, optional_exports.len);
                for (optional_exports) |name| {
                    hashU64(&hasher, name.len);
                    hashBytes(&hasher, name);
                }
                hashU64(&hasher, forbidden_import_fragments.len);
                for (forbidden_import_fragments) |fragment| {
                    hashU64(&hasher, fragment.len);
                    hashBytes(&hasher, fragment);
                }
                hashU64(&hasher, self.max_request_bytes);
                hashU64(&hasher, self.max_response_bytes);
                hashU64(&hasher, self.max_result_bytes);
                hashU64(&hasher, self.max_receipt_bytes);
                hashU64(&hasher, self.max_transcript_bytes);
                hashU64(&hasher, self.max_error_bytes);
                hashU64(&hasher, self.max_pending_ports);
                return hasher.final();
            }
        };
    };

    pub const Core = struct {
        allocator: std.mem.Allocator,
        runspace: Runspace,
        handle: ?RunHandle = null,
        state: Status = .initialized,
        result_bytes: []const u8 = &.{},
        receipt_bytes: [8]u8 = [_]u8{0} ** 8,
        receipt_len_value: usize = 0,
        transcript_bytes: []const u8 = &.{},
        last_error: [Buffer.max_error_bytes]u8 = [_]u8{0} ** Buffer.max_error_bytes,
        last_error_len_value: usize = 0,

        pub fn init(allocator: std.mem.Allocator, config: Runspace.Config) @This() {
            var runspace_config = config;
            runspace_config.auto_dispatch = false;
            runspace_config.max_pending_ports = if (runspace_config.max_pending_ports) |max|
                @min(max, Buffer.max_pending_ports)
            else
                Buffer.max_pending_ports;
            return .{
                .allocator = allocator,
                .runspace = Runspace.init(allocator, runspace_config),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.result_bytes);
            self.allocator.free(self.transcript_bytes);
            self.runspace.deinit();
            self.* = undefined;
        }

        pub fn resetSession(self: *@This()) void {
            self.allocator.free(self.result_bytes);
            self.result_bytes = &.{};
            self.allocator.free(self.transcript_bytes);
            self.transcript_bytes = &.{};
            self.receipt_bytes = [_]u8{0} ** self.receipt_bytes.len;
            self.receipt_len_value = 0;
            const runspace_config = self.runspace.config;
            self.runspace.deinit();
            self.runspace = Runspace.init(self.allocator, runspace_config);
            self.handle = null;
            self.state = .initialized;
            self.clearError();
        }

        pub fn initSession(self: *@This()) void {
            if (self.state == .done or self.state == .failed or self.installedRunIsTerminal()) {
                self.resetSession();
                return;
            }
            self.state = .initialized;
            self.clearError();
        }

        fn installedRunIsTerminal(self: *const @This()) bool {
            const handle = self.handle orelse return false;
            const summary = self.runspace.getSlotSummary(handle) catch return false;
            return switch (summary.status) {
                .completed, .failed, .exported => true,
                else => false,
            };
        }

        pub fn installMachineRun(self: *@This(), comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !void {
            if (self.handle != null) return self.failStatus(.invalid_state, "guest core already has an installed run");
            self.handle = try self.runspace.installMachineRun(Target, Env, runtime, args, options);
            self.state = .initialized;
            self.clearError();
        }

        pub fn installAdmitted(self: *@This(), admitted_run: Admission.AdmittedRun) !void {
            if (self.handle != null) return self.failStatus(.invalid_state, "guest core already has an installed run");
            self.handle = try self.runspace.installAdmitted(admitted_run);
            _ = self.refreshStatus();
        }

        pub fn installRunImage(self: *@This(), image: RunImage) !void {
            if (self.handle != null) return self.failStatus(.invalid_state, "guest core already has an installed run");
            const image_status = image.current_state.status;
            self.handle = try self.runspace.installRunImage(image);
            switch (image_status) {
                .parked_on_port, .parked_on_supervision, .completed, .failed => _ = self.refreshStatus(),
                else => {
                    self.state = .initialized;
                    self.clearError();
                },
            }
        }

        pub fn tick(self: *@This()) Status {
            if (self.handle == null) return self.setStatus(.invalid_state, "guest core has no installed run");
            _ = self.runspace.tick() catch |err| return self.mapRunspaceError(err);
            return self.refreshStatus();
        }

        pub fn status(self: *const @This()) Status {
            return self.state;
        }

        pub fn pendingCount(self: *const @This()) usize {
            if (self.installedRunParkedOnSupervision()) return 0;
            return self.runspace.mailbox.pendingCount();
        }

        pub fn pendingRequestLen(self: *@This(), index: u32) usize {
            const bytes = self.pendingRequestBytes(index) catch return 0;
            defer self.allocator.free(bytes);
            return bytes.len;
        }

        pub fn readPendingRequest(self: *@This(), index: u32, out: []u8) usize {
            const bytes = self.pendingRequestBytes(index) catch return 0;
            defer self.allocator.free(bytes);
            return self.copyToGuestBuffer(bytes, out);
        }

        fn pendingRequestBytes(self: *@This(), index: u32) ![]const u8 {
            const pending = self.pendingByIndex(index) catch |err| {
                _ = self.mapPendingLookupError(err);
                return err;
            };
            const request = pending.request_frame orelse {
                _ = self.setStatus(.unknown_pending, "pending port has no request frame");
                return error.InvalidPendingPortTransition;
            };
            const bytes = request.encode(self.allocator) catch |err| {
                _ = self.mapRunspaceError(err);
                return err;
            };
            errdefer self.allocator.free(bytes);
            if (bytes.len > Buffer.max_request_bytes) {
                _ = self.setStatus(.buffer_too_small, "pending request frame exceeds guest request byte cap");
                return error.OutOfMemory;
            }
            _ = self.refreshStatus();
            return bytes;
        }

        pub fn submitResponse(self: *@This(), bytes: []const u8) Status {
            if (bytes.len > Buffer.max_response_bytes) return self.setStatus(.buffer_too_small, "response frame exceeds guest response byte cap");
            if (self.handle == null) return self.setStatus(.invalid_state, "guest core has no installed run");
            if (self.runspace.mailbox.pending.items.len == 0) return self.setStatus(.invalid_state, "guest core is not parked on a pending port");
            var response = Frame.Response.decode(self.allocator, bytes) catch return self.setStatus(.invalid_frame, "response bytes do not decode as Frame.Response");
            defer response.deinit(self.allocator);
            const mailbox_id = self.matchPendingMailbox(response) catch |err| return self.mapPendingLookupError(err);
            _ = self.runspace.respond(mailbox_id, response) catch |err| {
                if (err == error.HandlerPending) return self.refreshStatus();
                return self.mapRunspaceError(err);
            };
            return self.refreshStatus();
        }

        pub fn resultLen(self: *@This()) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.result_bytes.len;
        }

        pub fn readResult(self: *@This(), out: []u8) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.copyToGuestBuffer(self.result_bytes, out);
        }

        pub fn receiptLen(self: *@This()) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.receipt_len_value;
        }

        pub fn readReceipt(self: *@This(), out: []u8) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.copyToGuestBuffer(self.receipt_bytes[0..self.receipt_len_value], out);
        }

        pub fn transcriptLen(self: *@This()) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.transcript_bytes.len;
        }

        pub fn readTranscript(self: *@This(), out: []u8) usize {
            self.ensureResultBytes() catch |err| {
                _ = self.mapRunspaceError(err);
                return 0;
            };
            return self.copyToGuestBuffer(self.transcript_bytes, out);
        }

        pub fn lastErrorLen(self: *const @This()) usize {
            return self.last_error_len_value;
        }

        pub fn readLastError(self: *@This(), out: []u8) usize {
            return copyToGuestBufferNoStatus(self.last_error[0..self.last_error_len_value], out);
        }

        fn refreshStatus(self: *@This()) Status {
            const report = self.runspace.report();
            if (report.failed_count != 0) return self.setStatus(.failed, "guest run failed");
            if (report.completed_count != 0) return self.setStatus(.done, "");
            if (self.installedRunParkedOnSupervision()) return self.setStatus(.supervision_denied, "guest run parked on supervision");
            if (report.pending_port_count != 0) return self.setStatus(.parked, "");
            if (report.parked_count != 0) return self.setStatus(.supervision_denied, "guest run parked on supervision without a pending port");
            if (report.runnable_count != 0) return self.setStatus(.running, "");
            if (report.run_count != 0) return self.setStatus(.initialized, "");
            return self.setStatus(.initialized, "");
        }

        fn ensureResultBytes(self: *@This()) !void {
            if (self.result_bytes.len != 0 or self.state != .done) return;
            const handle = self.handle orelse return error.InvalidRunspaceTransition;
            var preview = try self.runspace.previewResultRun(handle);
            defer preview.deinit(self.allocator);
            const encoded = try preview.encode(self.allocator);
            var encoded_owned = true;
            errdefer if (encoded_owned) self.allocator.free(encoded);
            if (encoded.len > Buffer.max_result_bytes) return error.GuestBufferTooSmall;
            var transcript_bytes: []const u8 = &.{};
            var transcript_owned = false;
            errdefer if (transcript_owned) self.allocator.free(transcript_bytes);
            if (preview.transcript_image) |transcript| {
                transcript_bytes = try transcript.encode(self.allocator);
                transcript_owned = true;
                if (transcript_bytes.len > Buffer.max_transcript_bytes) return error.GuestBufferTooSmall;
            }
            if (preview.prior_run_receipt_fingerprint) |receipt_fingerprint| {
                std.mem.writeInt(u64, &self.receipt_bytes, receipt_fingerprint, .little);
                self.receipt_len_value = 8;
            }
            self.transcript_bytes = transcript_bytes;
            transcript_owned = false;
            self.result_bytes = encoded;
            encoded_owned = false;
        }

        fn pendingByIndex(self: *const @This(), index: u32) !PendingPort {
            if (self.installedRunParkedOnSupervision()) return error.SupervisionDenied;
            var current: u32 = 0;
            for (self.runspace.mailbox.pending.items) |pending_port| {
                if (pending_port.status != .pending) continue;
                if (current == index) return pending_port.borrowed();
                current += 1;
            }
            return error.InvalidPendingPortTransition;
        }

        fn matchPendingMailbox(self: *const @This(), response: Frame.Response) !u64 {
            if (self.installedRunParkedOnSupervision()) return error.SupervisionDenied;
            var stale = false;
            for (self.runspace.mailbox.pending.items) |pending_port| {
                if (pending_port.request_fingerprint != response.request_fingerprint) continue;
                if (pending_port.status != .pending) {
                    stale = true;
                    continue;
                }
                pending_port.borrowed().validateResponse(response) catch |err| {
                    if (err == error.PendingPortConsumed) stale = true;
                    return err;
                };
                return pending_port.mailbox_id;
            }
            return if (stale) error.PendingPortConsumed else error.InvalidPendingPortTransition;
        }

        fn installedRunParkedOnSupervision(self: *const @This()) bool {
            const handle = self.handle orelse return false;
            for (self.runspace.slots.items) |slot| {
                if (slot.handle.handle_fingerprint == handle.handle_fingerprint and slot.status == .parked_on_supervision) return true;
            }
            return false;
        }

        fn copyToGuestBuffer(self: *@This(), bytes: []const u8, out: []u8) usize {
            if (out.len < bytes.len) {
                _ = self.setStatus(.buffer_too_small, "guest buffer is too small");
                return bytes.len;
            }
            @memcpy(out[0..bytes.len], bytes);
            _ = self.refreshStatus();
            return bytes.len;
        }

        fn copyToGuestBufferNoStatus(bytes: []const u8, out: []u8) usize {
            if (out.len < bytes.len) return bytes.len;
            @memcpy(out[0..bytes.len], bytes);
            return bytes.len;
        }

        fn mapPendingLookupError(self: *@This(), err: anyerror) Status {
            return switch (err) {
                error.PendingPortConsumed => self.setStatus(.stale_pending, "pending request has already been consumed"),
                error.StaleRunHandle => self.setStatus(.stale_pending, "pending request is stale for this run"),
                error.SupervisionDenied => self.setStatus(.supervision_denied, "guest run parked on supervision"),
                error.FrameSurfaceMismatch,
                error.FrameTargetCertificateMismatch,
                error.FramePortMismatch,
                error.FrameRequestFingerprintMismatch,
                error.FrameValueTableMismatch,
                error.VerifyResponseKindMismatch,
                error.ReplayMissing,
                => self.setStatus(.invalid_frame, "response frame does not match pending request"),
                else => self.setStatus(.unknown_pending, "pending request was not found"),
            };
        }

        fn mapRunspaceError(self: *@This(), err: anyerror) Status {
            return switch (err) {
                error.SupervisionDenied, error.HandoffDenied, error.BudgetExceeded, error.SupervisionBudgetExceeded, error.SupervisionPortRuleDenied => self.setStatus(.supervision_denied, "supervision denied guest run"),
                error.RunspaceAdmissionRequired, error.AdmissionRejected => self.setStatus(.admission_failed, "runspace admission failed"),
                error.FrameSurfaceMismatch, error.FrameTargetCertificateMismatch => self.setStatus(.target_mismatch, "frame target does not match guest run"),
                error.InvalidFrameEncoding, error.VerifyValueImageMismatch, error.FramePortMismatch, error.FrameRequestFingerprintMismatch, error.FrameValueTableMismatch => self.setStatus(.invalid_frame, "invalid canonical frame bytes"),
                error.StaleRunHandle, error.PendingPortConsumed => self.setStatus(.stale_pending, "pending request is stale"),
                error.InvalidRunspaceTransition, error.InvalidPendingPortTransition => self.setStatus(.invalid_state, "invalid guest state transition"),
                error.GuestBufferTooSmall => self.setStatus(.buffer_too_small, "guest ABI byte cap exceeded"),
                else => self.setStatus(.failed, @errorName(err)),
            };
        }

        fn setStatus(self: *@This(), status_value: Status, message: []const u8) Status {
            self.state = status_value;
            if (message.len == 0) {
                self.clearError();
            } else {
                const len = @min(message.len, self.last_error.len);
                @memcpy(self.last_error[0..len], message[0..len]);
                self.last_error_len_value = len;
            }
            return self.state;
        }

        fn failStatus(self: *@This(), status_value: Status, message: []const u8) !void {
            _ = self.setStatus(status_value, message);
            return error.InvalidRunspaceTransition;
        }

        fn clearError(self: *@This()) void {
            self.last_error_len_value = 0;
        }
    };

    pub const NativeGuest = struct {
        core: Core,

        pub fn init(allocator: std.mem.Allocator, config: Runspace.Config) @This() {
            return .{ .core = Core.init(allocator, config) };
        }

        pub fn deinit(self: *@This()) void {
            self.core.deinit();
        }

        pub fn world_abi_version(_: *@This()) u32 {
            return Abi.version;
        }

        pub fn world_init(self: *@This()) u32 {
            self.core.initSession();
            return self.core.state.code();
        }

        pub fn installMachineRun(self: *@This(), comptime Target: type, comptime Env: type, runtime: anytype, args: anytype, options: anytype) !void {
            return self.core.installMachineRun(Target, Env, runtime, args, options);
        }

        pub fn world_tick(self: *@This()) u32 {
            return self.core.tick().code();
        }

        pub fn world_status(self: *const @This()) u32 {
            return self.core.status().code();
        }

        pub fn world_pending_count(self: *const @This()) u32 {
            return @intCast(self.core.pendingCount());
        }

        pub fn world_pending_request_len(self: *@This(), index: u32) usize {
            return self.core.pendingRequestLen(index);
        }

        pub fn world_read_pending_request(self: *@This(), index: u32, out: []u8) usize {
            return self.core.readPendingRequest(index, out);
        }

        pub fn world_submit_response(self: *@This(), bytes: []const u8) u32 {
            return self.core.submitResponse(bytes).code();
        }

        pub fn world_result_len(self: *@This()) usize {
            return self.core.resultLen();
        }

        pub fn world_read_result(self: *@This(), out: []u8) usize {
            return self.core.readResult(out);
        }

        pub fn world_receipt_len(self: *@This()) usize {
            return self.core.receiptLen();
        }

        pub fn world_read_receipt(self: *@This(), out: []u8) usize {
            return self.core.readReceipt(out);
        }

        pub fn world_transcript_len(self: *@This()) usize {
            return self.core.transcriptLen();
        }

        pub fn world_read_transcript(self: *@This(), out: []u8) usize {
            return self.core.readTranscript(out);
        }

        pub fn world_last_error_len(self: *const @This()) usize {
            return self.core.lastErrorLen();
        }

        pub fn world_read_last_error(self: *@This(), out: []u8) usize {
            return self.core.readLastError(out);
        }
    };

    pub const VectorKind = enum {
        one_port,
        agent,
        supervised_denial,
        parked_handoff,
        replay,
    };

    pub const ConformanceVector = struct {
        fingerprint_version: u32 = world_guest_conformance_vector_fingerprint_version,
        vector_fingerprint: u64 = 0,
        name: []const u8,
        kind: VectorKind,
        target_ref_fingerprint: u64,
        admission_receipt_fingerprint: ?u64 = null,
        run_permit_fingerprint: ?u64 = null,
        input_fingerprints: []const u64 = &.{},
        expected_pending_frame_fingerprints: []const u64 = &.{},
        response_frame_fingerprints: []const u64 = &.{},
        expected_final_result_fingerprint: ?u64 = null,
        expected_transcript_fingerprint: ?u64 = null,
        expected_receipt_fingerprint: ?u64 = null,
        expected_status_sequence: []const Status = &.{},

        pub fn init(args: struct {
            name: []const u8,
            kind: VectorKind,
            target_ref_fingerprint: u64,
            admission_receipt_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            input_fingerprints: []const u64 = &.{},
            expected_pending_frame_fingerprints: []const u64 = &.{},
            response_frame_fingerprints: []const u64 = &.{},
            expected_final_result_fingerprint: ?u64 = null,
            expected_transcript_fingerprint: ?u64 = null,
            expected_receipt_fingerprint: ?u64 = null,
            expected_status_sequence: []const Status = &.{},
        }) @This() {
            var result = @This(){
                .name = args.name,
                .kind = args.kind,
                .target_ref_fingerprint = args.target_ref_fingerprint,
                .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                .run_permit_fingerprint = args.run_permit_fingerprint,
                .input_fingerprints = args.input_fingerprints,
                .expected_pending_frame_fingerprints = args.expected_pending_frame_fingerprints,
                .response_frame_fingerprints = args.response_frame_fingerprints,
                .expected_final_result_fingerprint = args.expected_final_result_fingerprint,
                .expected_transcript_fingerprint = args.expected_transcript_fingerprint,
                .expected_receipt_fingerprint = args.expected_receipt_fingerprint,
                .expected_status_sequence = args.expected_status_sequence,
            };
            result.vector_fingerprint = fingerprintVector(result);
            return result;
        }

        pub fn fingerprint(self: @This()) u64 {
            return fingerprintVector(self);
        }
    };

    pub const RunResultSummary = struct {
        status: Status,
        result_fingerprint: ?u64 = null,
        transcript_fingerprint: ?u64 = null,
        receipt_fingerprint: ?u64 = null,
        pending_frame_fingerprints: []const u64 = &.{},
    };

    pub const ConformanceReport = struct {
        fingerprint_version: u32 = world_guest_conformance_report_fingerprint_version,
        report_fingerprint: u64 = 0,
        vector_fingerprint: u64,
        native_run_result: RunResultSummary,
        native_abi_result: RunResultSummary,
        wasm_inspection_passed: bool = false,
        wasm_runtime_result: ?RunResultSummary = null,
        status_sequence_match: bool = false,
        pending_frame_match: bool = false,
        final_result_match: bool = false,
        transcript_match: bool = false,
        receipt_match: bool = false,
        blockers: []const []const u8 = &.{},
        warnings: []const []const u8 = &.{},

        pub fn init(args: struct {
            vector_fingerprint: u64,
            native_run_result: RunResultSummary,
            native_abi_result: RunResultSummary,
            wasm_inspection_passed: bool = false,
            wasm_runtime_result: ?RunResultSummary = null,
            status_sequence_match: bool = false,
            pending_frame_match: bool = false,
            final_result_match: bool = false,
            transcript_match: bool = false,
            receipt_match: bool = false,
            blockers: []const []const u8 = &.{},
            warnings: []const []const u8 = &.{},
        }) @This() {
            var result = @This(){
                .vector_fingerprint = args.vector_fingerprint,
                .native_run_result = args.native_run_result,
                .native_abi_result = args.native_abi_result,
                .wasm_inspection_passed = args.wasm_inspection_passed,
                .wasm_runtime_result = args.wasm_runtime_result,
                .status_sequence_match = args.status_sequence_match,
                .pending_frame_match = args.pending_frame_match,
                .final_result_match = args.final_result_match,
                .transcript_match = args.transcript_match,
                .receipt_match = args.receipt_match,
                .blockers = args.blockers,
                .warnings = args.warnings,
            };
            result.report_fingerprint = fingerprintReport(result);
            return result;
        }
    };

    pub const Wasm = struct {
        const ExpectedSignature = struct {
            param_count: u32,
            result_count: u32,
        };

        pub const Inspection = struct {
            abi_version: u32 = 0,
            export_count: usize = 0,
            import_count: usize = 0,
            function_import_count: u32 = 0,
            forbidden_import_count: usize = 0,
            required_exports_present: bool = false,
            memory_export_present: bool = false,
            alloc_export_present: bool = false,
            free_export_present: bool = false,
            optional_helper_exports_valid: bool = true,

            pub fn passed(self: @This()) bool {
                return self.abi_version == Abi.version and
                    self.required_exports_present and
                    self.memory_export_present and
                    self.import_count == 0 and
                    self.forbidden_import_count == 0 and
                    self.optional_helper_exports_valid;
            }
        };

        pub fn inspect(bytes: []const u8) !Inspection {
            if (bytes.len < 8) return error.InvalidFrameEncoding;
            if (!std.mem.eql(u8, bytes[0..4], "\x00asm")) return error.InvalidFrameEncoding;
            if (std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidFrameEncoding;
            var inspection: Inspection = .{};
            var required_mask: u64 = 0;
            var type_section: []const u8 = &.{};
            var function_section: []const u8 = &.{};
            var code_section: []const u8 = &.{};
            var table_count: u32 = 0;
            var memory_count: u32 = 0;
            var global_count: u32 = 0;
            var abi_defined_function_index: ?u32 = null;
            var last_non_custom_section_rank: u8 = 0;
            var cursor: usize = 8;
            while (cursor < bytes.len) {
                const section_id = bytes[cursor];
                cursor += 1;
                const section_len = try readWasmU32(bytes, &cursor);
                if (cursor + section_len > bytes.len) return error.InvalidFrameEncoding;
                const section_end = cursor + section_len;
                if (section_id != 0) {
                    const section_rank = try wasmSectionOrderRank(section_id);
                    if (section_rank <= last_non_custom_section_rank) return error.InvalidFrameEncoding;
                    last_non_custom_section_rank = section_rank;
                    if (section_id == 8) return error.InvalidFrameEncoding;
                }
                switch (section_id) {
                    1 => type_section = bytes[cursor..section_end],
                    2 => inspection.function_import_count = try inspectImportSection(bytes[cursor..section_end], &inspection),
                    3 => function_section = bytes[cursor..section_end],
                    4 => table_count = try inspectTableSection(bytes[cursor..section_end]),
                    5 => memory_count = try inspectMemorySection(bytes[cursor..section_end]),
                    6 => global_count = try inspectGlobalSection(bytes[cursor..section_end]),
                    7 => try inspectExportSection(bytes[cursor..section_end], type_section, function_section, table_count, memory_count, global_count, inspection.function_import_count, &inspection, &required_mask, &abi_defined_function_index),
                    10 => code_section = bytes[cursor..section_end],
                    else => {},
                }
                cursor = section_end;
            }
            const all_required = if (Abi.required_exports.len == 64)
                std.math.maxInt(u64)
            else
                (@as(u64, 1) << @intCast(Abi.required_exports.len)) - 1;
            inspection.required_exports_present = (required_mask & all_required) == all_required;
            if (abi_defined_function_index) |defined_index| {
                const defined_function_count = try functionCount(function_section);
                inspection.abi_version = try inspectCodeSection(code_section, defined_index, defined_function_count);
            }
            return inspection;
        }

        fn wasmSectionOrderRank(section_id: u8) !u8 {
            return switch (section_id) {
                1 => 1,
                2 => 2,
                3 => 3,
                4 => 4,
                5 => 5,
                6 => 6,
                7 => 7,
                8 => 8,
                9 => 9,
                12 => 10,
                10 => 11,
                11 => 12,
                else => error.InvalidFrameEncoding,
            };
        }

        fn inspectImportSection(section: []const u8, inspection: *Inspection) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            var function_import_count: u32 = 0;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const module = try readWasmName(section, &cursor);
                const name = try readWasmName(section, &cursor);
                const kind = try readWasmU8(section, &cursor);
                try skipWasmImportDesc(section, &cursor);
                inspection.import_count += 1;
                if (kind == 0) function_import_count += 1;
                if (forbiddenImport(module) or forbiddenImport(name)) inspection.forbidden_import_count += 1;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return function_import_count;
        }

        fn inspectMemorySection(section: []const u8) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) try skipWasmLimits(section, &cursor);
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return count;
        }

        fn inspectTableSection(section: []const u8) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const element_type = try readWasmU8(section, &cursor);
                if (element_type != 0x70 and element_type != 0x6f) return error.InvalidFrameEncoding;
                try skipWasmLimits(section, &cursor);
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return count;
        }

        fn inspectGlobalSection(section: []const u8) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const value_type = try readWasmU8(section, &cursor);
                if (!validWasmValueType(value_type)) return error.InvalidFrameEncoding;
                const mutable = try readWasmU8(section, &cursor);
                if (mutable > 1) return error.InvalidFrameEncoding;
                try skipWasmInitExpr(section, &cursor);
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return count;
        }

        fn inspectExportSection(section: []const u8, type_section: []const u8, function_section: []const u8, table_count: u32, memory_count: u32, global_count: u32, function_import_count: u32, inspection: *Inspection, required_mask: *u64, abi_defined_function_index: *?u32) !void {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            const defined_function_count = try functionCount(function_section);
            if (function_import_count > std.math.maxInt(u32) - defined_function_count) return error.InvalidFrameEncoding;
            const function_count = function_import_count + defined_function_count;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const entry_start = cursor;
                const name = try readWasmName(section, &cursor);
                const kind = try readWasmU8(section, &cursor);
                const export_index = try readWasmU32(section, &cursor);
                if (try exportNameAppeared(section, entry_start, name)) return error.InvalidFrameEncoding;
                try validateExportDescriptor(kind, export_index, function_count, table_count, memory_count, global_count);
                inspection.export_count += 1;
                if (kind == 2 and std.mem.eql(u8, name, "memory") and export_index < memory_count) inspection.memory_export_present = true;
                if (std.mem.eql(u8, name, "world_alloc")) {
                    if (kind == 0 and try functionSignatureMatches(type_section, function_section, function_import_count, export_index, .{ .param_count = 1, .result_count = 1 })) {
                        inspection.alloc_export_present = true;
                    } else {
                        inspection.optional_helper_exports_valid = false;
                    }
                }
                if (std.mem.eql(u8, name, "world_free")) {
                    if (kind == 0 and try functionSignatureMatches(type_section, function_section, function_import_count, export_index, .{ .param_count = 2, .result_count = 0 })) {
                        inspection.free_export_present = true;
                    } else {
                        inspection.optional_helper_exports_valid = false;
                    }
                }
                for (Abi.required_exports, 0..) |required, required_index| {
                    if (kind == 0 and std.mem.eql(u8, name, required) and try functionSignatureMatches(type_section, function_section, function_import_count, export_index, requiredSignature(required_index))) {
                        required_mask.* |= @as(u64, 1) << @intCast(required_index);
                        if (required_index == 0) abi_defined_function_index.* = export_index - function_import_count;
                    }
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
        }

        fn validateExportDescriptor(kind: u8, export_index: u32, function_count: u32, table_count: u32, memory_count: u32, global_count: u32) !void {
            const limit = switch (kind) {
                0 => function_count,
                1 => table_count,
                2 => memory_count,
                3 => global_count,
                else => return error.InvalidFrameEncoding,
            };
            if (export_index >= limit) return error.InvalidFrameEncoding;
        }

        fn exportNameAppeared(section: []const u8, end: usize, name: []const u8) !bool {
            var cursor: usize = 0;
            _ = try readWasmU32(section, &cursor);
            while (cursor < end) {
                const previous = try readWasmName(section, &cursor);
                _ = try readWasmU8(section, &cursor);
                _ = try readWasmU32(section, &cursor);
                if (std.mem.eql(u8, previous, name)) return true;
            }
            if (cursor != end) return error.InvalidFrameEncoding;
            return false;
        }

        fn inspectCodeSection(section: []const u8, abi_defined_index: u32, expected_defined_function_count: u32) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            if (count != expected_defined_function_count) return error.InvalidFrameEncoding;
            if (abi_defined_index >= count) return error.InvalidFrameEncoding;
            var abi_version: ?u32 = null;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const body_len = try readWasmU32(section, &cursor);
                if (cursor + body_len > section.len) return error.InvalidFrameEncoding;
                const body = section[cursor .. cursor + body_len];
                cursor += body_len;
                if (index == abi_defined_index) abi_version = try inspectAbiVersionBody(body);
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return abi_version orelse error.InvalidFrameEncoding;
        }

        fn functionCount(section: []const u8) !u32 {
            if (section.len == 0) return 0;
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) _ = try readWasmU32(section, &cursor);
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return count;
        }

        fn inspectAbiVersionBody(body: []const u8) !u32 {
            var cursor: usize = 0;
            const local_decl_count = try readWasmU32(body, &cursor);
            var local_decl_index: u32 = 0;
            while (local_decl_index < local_decl_count) : (local_decl_index += 1) {
                _ = try readWasmU32(body, &cursor);
                _ = try readWasmU8(body, &cursor);
            }
            if (try readWasmU8(body, &cursor) != 0x41) return error.InvalidFrameEncoding;
            const abi_version = try readWasmI32NonNegative(body, &cursor);
            const terminator = try readWasmU8(body, &cursor);
            if (terminator == 0x0f) {
                if (try readWasmU8(body, &cursor) != 0x0b) return error.InvalidFrameEncoding;
            } else if (terminator != 0x0b) {
                return error.InvalidFrameEncoding;
            }
            if (cursor != body.len) return error.InvalidFrameEncoding;
            return abi_version;
        }

        fn forbiddenImport(name: []const u8) bool {
            for (Abi.forbidden_import_fragments) |fragment| {
                if (std.mem.indexOf(u8, name, fragment) != null) return true;
            }
            return false;
        }

        fn requiredSignature(required_index: usize) ExpectedSignature {
            return switch (required_index) {
                5 => .{ .param_count = 1, .result_count = 1 },
                6 => .{ .param_count = 3, .result_count = 1 },
                7 => .{ .param_count = 2, .result_count = 1 },
                9, 11, 13, 15 => .{ .param_count = 2, .result_count = 1 },
                else => .{ .param_count = 0, .result_count = 1 },
            };
        }

        fn functionSignatureMatches(type_section: []const u8, function_section: []const u8, function_import_count: u32, function_index: u32, expected: ExpectedSignature) !bool {
            if (function_index < function_import_count) return false;
            const defined_index = function_index - function_import_count;
            const type_index = try functionTypeIndex(function_section, defined_index);
            return try typeSignatureMatches(type_section, type_index, expected);
        }

        fn functionTypeIndex(section: []const u8, defined_index: u32) !u32 {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            if (defined_index >= count) return error.InvalidFrameEncoding;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const type_index = try readWasmU32(section, &cursor);
                if (index == defined_index) return type_index;
            }
            return error.InvalidFrameEncoding;
        }

        fn typeSignatureMatches(section: []const u8, type_index: u32, expected: ExpectedSignature) !bool {
            var cursor: usize = 0;
            const count = try readWasmU32(section, &cursor);
            if (type_index >= count) return error.InvalidFrameEncoding;
            var matched = false;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const tag = try readWasmU8(section, &cursor);
                if (tag != 0x60) return error.InvalidFrameEncoding;
                const param_count = try readWasmU32(section, &cursor);
                var param_index: u32 = 0;
                var params_i32 = true;
                while (param_index < param_count) : (param_index += 1) {
                    if (try readWasmU8(section, &cursor) != 0x7f) params_i32 = false;
                }
                const result_count = try readWasmU32(section, &cursor);
                var result_index: u32 = 0;
                var results_i32 = true;
                while (result_index < result_count) : (result_index += 1) {
                    if (try readWasmU8(section, &cursor) != 0x7f) results_i32 = false;
                }
                if (index == type_index) matched = params_i32 and results_i32 and param_count == expected.param_count and result_count == expected.result_count;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return matched;
        }

        fn skipWasmImportDesc(bytes: []const u8, cursor: *usize) !void {
            const kind = bytes[cursor.* - 1];
            switch (kind) {
                0 => {
                    _ = try readWasmU32(bytes, cursor);
                },
                1 => try skipWasmLimits(bytes, cursor),
                2 => try skipWasmLimits(bytes, cursor),
                3 => {
                    _ = try readWasmU8(bytes, cursor);
                    _ = try readWasmU8(bytes, cursor);
                },
                else => return error.InvalidFrameEncoding,
            }
        }

        fn skipWasmLimits(bytes: []const u8, cursor: *usize) !void {
            const tag = try readWasmU8(bytes, cursor);
            if (tag == 2 or tag > 3) return error.InvalidFrameEncoding;
            _ = try readWasmU32(bytes, cursor);
            if (tag == 1 or tag == 3) _ = try readWasmU32(bytes, cursor);
        }

        fn validWasmValueType(value: u8) bool {
            return switch (value) {
                0x7f, 0x7e, 0x7d, 0x7c, 0x7b, 0x70, 0x6f => true,
                else => false,
            };
        }

        fn skipWasmInitExpr(bytes: []const u8, cursor: *usize) !void {
            while (true) {
                const opcode = try readWasmU8(bytes, cursor);
                switch (opcode) {
                    0x0b => return,
                    0x23, 0xd2 => _ = try readWasmU32(bytes, cursor),
                    0x41 => try skipWasmLeb128(bytes, cursor, 5),
                    0x42 => try skipWasmLeb128(bytes, cursor, 10),
                    0x43 => try skipWasmBytes(bytes, cursor, 4),
                    0x44 => try skipWasmBytes(bytes, cursor, 8),
                    0xd0 => _ = try readWasmU8(bytes, cursor),
                    else => return error.InvalidFrameEncoding,
                }
            }
        }

        fn skipWasmLeb128(bytes: []const u8, cursor: *usize, max_bytes: usize) !void {
            var read_count: usize = 0;
            while (read_count < max_bytes) : (read_count += 1) {
                const byte = try readWasmU8(bytes, cursor);
                if ((byte & 0x80) == 0) return;
            }
            return error.InvalidFrameEncoding;
        }

        fn skipWasmBytes(bytes: []const u8, cursor: *usize, count: usize) !void {
            if (cursor.* + count > bytes.len) return error.InvalidFrameEncoding;
            cursor.* += count;
        }

        fn readWasmName(bytes: []const u8, cursor: *usize) ![]const u8 {
            const len = try readWasmU32(bytes, cursor);
            if (cursor.* + len > bytes.len) return error.InvalidFrameEncoding;
            const value = bytes[cursor.* .. cursor.* + len];
            cursor.* += len;
            return value;
        }

        fn readWasmU8(bytes: []const u8, cursor: *usize) !u8 {
            if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
            const value = bytes[cursor.*];
            cursor.* += 1;
            return value;
        }

        fn readWasmU32(bytes: []const u8, cursor: *usize) !u32 {
            var result: u32 = 0;
            var shift: u5 = 0;
            while (true) {
                if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
                const byte = bytes[cursor.*];
                cursor.* += 1;
                const payload = byte & 0x7f;
                if (shift == 28 and payload > 0x0f) return error.InvalidFrameEncoding;
                result |= @as(u32, payload) << shift;
                if ((byte & 0x80) == 0) return result;
                if (shift == 28) return error.InvalidFrameEncoding;
                shift += 7;
            }
        }

        fn readWasmI32NonNegative(bytes: []const u8, cursor: *usize) !u32 {
            const value = try readWasmU32(bytes, cursor);
            if ((value & 0x8000_0000) != 0) return error.InvalidFrameEncoding;
            return value;
        }
    };

    fn fingerprintVector(vector: ConformanceVector) u64 {
        var hasher = std.hash.Wyhash.init(0x6775_6573_745f_7665);
        hashU64(&hasher, vector.fingerprint_version);
        hashU64(&hasher, vector.name.len);
        hashBytes(&hasher, vector.name);
        hashU64(&hasher, @intFromEnum(vector.kind));
        hashU64(&hasher, vector.target_ref_fingerprint);
        hashOptionalU64(&hasher, vector.admission_receipt_fingerprint);
        hashOptionalU64(&hasher, vector.run_permit_fingerprint);
        hashU64Slice(&hasher, vector.input_fingerprints);
        hashU64Slice(&hasher, vector.expected_pending_frame_fingerprints);
        hashU64Slice(&hasher, vector.response_frame_fingerprints);
        hashOptionalU64(&hasher, vector.expected_final_result_fingerprint);
        hashOptionalU64(&hasher, vector.expected_transcript_fingerprint);
        hashOptionalU64(&hasher, vector.expected_receipt_fingerprint);
        for (vector.expected_status_sequence) |status_value| hashU64(&hasher, @intFromEnum(status_value));
        return hasher.final();
    }

    fn fingerprintReport(report: ConformanceReport) u64 {
        var hasher = std.hash.Wyhash.init(0x6775_6573_745f_7265);
        hashU64(&hasher, report.fingerprint_version);
        hashU64(&hasher, report.vector_fingerprint);
        fingerprintResultSummary(&hasher, report.native_run_result);
        fingerprintResultSummary(&hasher, report.native_abi_result);
        hashBool(&hasher, report.wasm_inspection_passed);
        hashBool(&hasher, report.wasm_runtime_result != null);
        if (report.wasm_runtime_result) |summary| fingerprintResultSummary(&hasher, summary);
        hashBool(&hasher, report.status_sequence_match);
        hashBool(&hasher, report.pending_frame_match);
        hashBool(&hasher, report.final_result_match);
        hashBool(&hasher, report.transcript_match);
        hashBool(&hasher, report.receipt_match);
        hashStringSlice(&hasher, report.blockers);
        hashStringSlice(&hasher, report.warnings);
        return hasher.final();
    }

    fn fingerprintResultSummary(hasher: *std.hash.Wyhash, summary: RunResultSummary) void {
        hashU64(hasher, @intFromEnum(summary.status));
        hashOptionalU64(hasher, summary.result_fingerprint);
        hashOptionalU64(hasher, summary.transcript_fingerprint);
        hashOptionalU64(hasher, summary.receipt_fingerprint);
        hashU64Slice(hasher, summary.pending_frame_fingerprints);
    }

    fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
        hashU64(hasher, values.len);
        for (values) |value| hashU64(hasher, value);
    }

    fn hashStringSlice(hasher: *std.hash.Wyhash, values: []const []const u8) void {
        hashU64(hasher, values.len);
        for (values) |value| {
            hashU64(hasher, value.len);
            hashBytes(hasher, value);
        }
    }
};

pub const RunSlot = Runspace.RunSlot;
pub const Mailbox = Runspace.Mailbox;
pub const PendingPort = Runspace.PendingPort;
pub const RunspaceEvent = Runspace.RunspaceEvent;
pub const RunspaceReport = Runspace.RunspaceReport;

fn isSupportedRunImageFormatVersion(format_version: u32) bool {
    return format_version == 1 or format_version == 2 or format_version == world_run_image_format_version;
}

fn isSupportedTargetRefFormatVersion(format_version: u32) bool {
    return format_version == 1 or format_version == world_target_ref_format_version;
}

fn validateTargetRef(target_ref: TargetRef) !void {
    if (!isSupportedTargetRefFormatVersion(target_ref.format_version)) return error.InvalidFrameEncoding;
    if (target_ref.fingerprint_version != world_target_ref_fingerprint_version) return error.InvalidFrameEncoding;
    if (target_ref.target_ref_fingerprint != fingerprintTargetRef(target_ref)) return error.InvalidFrameEncoding;
}

test "RunImage decoder accepts v1 layout without prior receipt refs" {
    const allocator = std.testing.allocator;
    var target_ref = TargetRef{
        .target_ref_fingerprint = 0,
        .world_surface_fingerprint = 11,
        .target_certificate_fingerprint = 22,
        .metadata = "target",
    };
    target_ref.target_ref_fingerprint = fingerprintTargetRef(target_ref);
    const state = RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    var image = RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = 33,
        .current_state = state,
        .environment_certificate_fingerprint = 44,
        .metadata = "legacy",
    });
    image.format_version = 1;
    image.run_image_fingerprint = fingerprintRunImageV1(image);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try writeU32(&out, allocator, 1);
    try writeU32(&out, allocator, image.fingerprint_version);
    try writeU64(&out, allocator, image.run_image_fingerprint);
    try writeU8(&out, allocator, @intFromEnum(image.kind));
    try encodeTargetRef(&out, allocator, image.target_ref);
    try writeU64(&out, allocator, image.import_set_fingerprint);
    try encodeRunState(&out, allocator, image.current_state);
    try writeOptionalU64(&out, allocator, null);
    try writeBool(&out, allocator, false);
    try writeU64(&out, allocator, 0);
    try writeU64(&out, allocator, 0);
    try writeBool(&out, allocator, false);
    try writeOptionalValueImage(&out, allocator, null);
    try writeOptionalU64(&out, allocator, image.environment_certificate_fingerprint);
    try writeOptionalU64(&out, allocator, image.acceptance_report_fingerprint);
    try writeOptionalU64(&out, allocator, image.audit_image_fingerprint);
    try writeBytes(&out, allocator, image.metadata);

    var decoded = try RunImage.decode(allocator, out.items);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), decoded.format_version);
    try std.testing.expectEqual(@as(u32, 1), decoded.target_ref.format_version);
    try std.testing.expectEqual(@as(?u64, null), decoded.prior_run_permit_fingerprint);
    try std.testing.expectEqual(@as(?u64, null), decoded.prior_run_receipt_fingerprint);
    try std.testing.expectEqualStrings("legacy", decoded.metadata);
    try decoded.validate(.{});

    const reencoded = try decoded.encode(allocator);
    defer allocator.free(reencoded);
    var redecode = try RunImage.decode(allocator, reencoded);
    defer redecode.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), redecode.format_version);
    try std.testing.expectEqual(@as(u32, 1), redecode.target_ref.format_version);
    try std.testing.expectEqualStrings("legacy", redecode.metadata);
}

test "TargetRef decoder accepts v1 boundary module slot layouts" {
    const allocator = std.testing.allocator;
    var legacy_ref = TargetRef{
        .format_version = 1,
        .target_ref_fingerprint = 0,
        .world_surface_fingerprint = 11,
        .target_certificate_fingerprint = 22,
        .metadata = "legacy-target",
    };
    legacy_ref.target_ref_fingerprint = fingerprintTargetRef(legacy_ref);
    var legacy_out: std.ArrayList(u8) = .empty;
    defer legacy_out.deinit(allocator);
    try writeU32(&legacy_out, allocator, legacy_ref.format_version);
    try writeU32(&legacy_out, allocator, legacy_ref.fingerprint_version);
    try writeU64(&legacy_out, allocator, legacy_ref.target_ref_fingerprint);
    try writeOptionalBytes(&legacy_out, allocator, legacy_ref.target_label);
    try writeU64(&legacy_out, allocator, legacy_ref.world_surface_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.world_surface_replay_scope_fingerprint);
    try writeU64(&legacy_out, allocator, legacy_ref.target_certificate_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.residual_program_plan_hash);
    try writeU8(&legacy_out, allocator, @intFromEnum(legacy_ref.normal_form_kind));
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.world_port_table_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.world_value_table_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.world_dispatch_table_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.surface_profile_fingerprint);
    try writeOptionalU64(&legacy_out, allocator, legacy_ref.boundary_module_fingerprint);
    try writeBytes(&legacy_out, allocator, legacy_ref.metadata);
    var legacy_cursor: usize = 0;
    const decoded_legacy = try decodeTargetRef(allocator, legacy_out.items, &legacy_cursor);
    defer allocator.free(@constCast(decoded_legacy.metadata));
    try std.testing.expectEqual(legacy_out.items.len, legacy_cursor);
    try std.testing.expectEqual(legacy_ref.target_ref_fingerprint, decoded_legacy.target_ref_fingerprint);
    try std.testing.expectEqual(@as(?u64, null), decoded_legacy.boundary_module_fingerprint);

    var boundary_ref = legacy_ref;
    boundary_ref.boundary_module_fingerprint = 33;
    boundary_ref.target_ref_fingerprint = fingerprintTargetRef(boundary_ref);
    var boundary_out: std.ArrayList(u8) = .empty;
    defer boundary_out.deinit(allocator);
    try encodeTargetRef(&boundary_out, allocator, boundary_ref);
    var boundary_cursor: usize = 0;
    const decoded_boundary = try decodeTargetRef(allocator, boundary_out.items, &boundary_cursor);
    defer allocator.free(@constCast(decoded_boundary.metadata));
    try std.testing.expectEqual(boundary_out.items.len, boundary_cursor);
    try std.testing.expectEqual(boundary_ref.target_ref_fingerprint, decoded_boundary.target_ref_fingerprint);
    try std.testing.expectEqual(boundary_ref.boundary_module_fingerprint, decoded_boundary.boundary_module_fingerprint);
}

fn validateRunImageKindState(image: RunImage) !void {
    switch (image.kind) {
        .completed_run => {
            if (image.current_state.status != .completed) return error.HandoffTargetMismatch;
        },
        .replay_only_run => switch (image.current_state.status) {
            .completed, .failed => {},
            else => return error.HandoffTargetMismatch,
        },
        .parked_run => {
            if (image.current_state.status != .parked_on_port) return error.HandoffPendingFrameMismatch;
        },
        else => {},
    }
}

pub const HandoffMode = enum {
    accept_fresh,
    accept_replay,
    accept_verify,
    inspect_only,
};

pub const Handoff = struct {
    allocator: std.mem.Allocator,
    run_image: RunImage,

    pub fn fromRunImage(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        var image = try RunImage.decode(allocator, bytes);
        errdefer image.deinit(allocator);
        try image.validate(.{});
        return .{ .allocator = allocator, .run_image = image };
    }

    pub fn deinit(self: *@This()) void {
        self.run_image.deinit(self.allocator);
        self.* = undefined;
    }

    fn transcriptAvailableForFreshHandoff(self: *@This(), mode: HandoffMode, fresh_transcript_sink_available: bool) bool {
        return self.run_image.transcript_image != null or (mode == .accept_fresh and fresh_transcript_sink_available);
    }

    pub fn preflight(self: *@This(), comptime Target: type, comptime Env: type, mode: HandoffMode) AcceptanceReport {
        return self.preflightWithFreshTranscriptSink(Target, Env, mode, false);
    }

    fn preflightWithFreshTranscriptSink(self: *@This(), comptime Target: type, comptime Env: type, mode: HandoffMode, fresh_transcript_sink_available: bool) AcceptanceReport {
        if (!self.run_image.target_ref.matchesTarget(Target)) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffTargetMismatch});
        }
        if (self.run_image.import_set_fingerprint != Env.import_set.import_set_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffTargetMismatch});
        }
        const has_transcript = self.transcriptAvailableForFreshHandoff(mode, fresh_transcript_sink_available);
        const report = Env.acceptanceReport(modeToRunMode(mode), has_transcript);
        if (!report.accepted) return report;
        const interrupted_export = runImageIsInterruptedSupervisionExport(self.run_image);
        if (mode == .accept_fresh and interrupted_export and self.run_image.current_state.turn_index != 0) {
            const image = if (self.run_image.transcript_image) |*image|
                image
            else
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.TranscriptImageRequired});
            validateTranscriptImageForEnvironment(Env, image) catch |err| {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{environmentValidationBlocker(err)});
            };
            image.prepareReplayPrefixForInterruptedRun(
                Target.WorldSurface.surface_fingerprint,
                Target.Certificate.certificate_fingerprint,
            ) catch {
                image.resetReplay();
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.ReplaySourceMissing});
            };
            image.resetReplay();
        }
        if (mode == .accept_fresh and
            !interrupted_export and
            (self.run_image.current_state.status != .parked_on_port or self.run_image.pending_request_frame == null))
        {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffPendingFrameMismatch});
        }
        if (mode == .accept_fresh and !interrupted_export) {
            const pending_frame = self.run_image.pending_request_frame.?;
            const pending_policy = valuePolicyForEnvironmentPort(Env, pending_frame.world_port_id, .request) catch |err| {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{environmentValidationBlocker(err)});
            };
            validateTransferredRequestFramePolicy(pending_frame, pending_policy) catch |err| {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{environmentValidationBlocker(err)});
            };
            if (self.run_image.transcript_image) |*image| {
                validateTranscriptImageForEnvironment(Env, image) catch |err| {
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{environmentValidationBlocker(err)});
                };
                image.prepareReplayPrefixForPendingRequest(
                    Target.WorldSurface.surface_fingerprint,
                    Target.Certificate.certificate_fingerprint,
                    pending_frame.frame_fingerprint,
                ) catch {
                    image.resetReplay();
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.ReplaySourceMissing});
                };
                image.resetReplay();
            } else if (pending_frame.turn_index != 0) {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.TranscriptImageRequired});
            }
        }
        if (mode == .accept_replay or mode == .accept_verify) {
            const image = if (self.run_image.transcript_image) |*image|
                image
            else
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.TranscriptImageRequired});
            validateTranscriptImageForEnvironment(Env, image) catch |err| {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{environmentValidationBlocker(err)});
            };
            image.resetReplay();
            image.validateReplayRun(
                Target.WorldSurface.surface_fingerprint,
                Target.Certificate.certificate_fingerprint,
            ) catch {
                image.resetReplay();
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.ReplaySourceMissing});
            };
            image.resetReplay();
        }
        return report;
    }

    pub fn preflightWithPermit(self: *@This(), comptime Target: type, comptime Env: type, mode: HandoffMode, permit: RunPermit) AcceptanceReport {
        return self.preflightWithPermitFreshTranscriptSink(Target, Env, mode, permit, false);
    }

    fn preflightWithPermitFreshTranscriptSink(self: *@This(), comptime Target: type, comptime Env: type, mode: HandoffMode, permit: RunPermit, fresh_transcript_sink_available: bool) AcceptanceReport {
        const accepting = mode != .inspect_only;
        const has_transcript = self.transcriptAvailableForFreshHandoff(mode, fresh_transcript_sink_available);
        if (permit.mode != modeToRunMode(mode)) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        Supervision.Supervisor.validatePermitForRun(permit, Target.WorldPortTable.entries.len) catch {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        };
        if (permit.target_ref_fingerprint != TargetRef.fromTarget(Target).target_ref_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffTargetMismatch});
        }
        if (permit.module_ref_fingerprint) |permit_module_ref_fingerprint| {
            const run_module_ref_fingerprint = self.run_image.module_ref_fingerprint orelse {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
            };
            if (run_module_ref_fingerprint != permit_module_ref_fingerprint) {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
            }
        }
        const cert = Env.certificate(modeToRunMode(mode), has_transcript);
        if (permit.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (permit.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (permit.environment_certificate_fingerprint != cert.certificate_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (permit.binding_plan_fingerprint != cert.binding_plan_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (accepting and !permit.policy.allow_handoff_accept) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (accepting and permit.handoff_policy == .deny) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        }
        if (accepting and permit.handoff_policy == .require_new_permit) {
            if (self.run_image.prior_run_permit_fingerprint) |prior_permit_fingerprint| {
                if (prior_permit_fingerprint == permit.permit_fingerprint) {
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
                }
            }
        }
        const supervision_report = Env.acceptanceReportWithPermit(modeToRunMode(mode), has_transcript, permit);
        if (!supervision_report.accepted) return supervision_report;
        const report = self.preflightWithFreshTranscriptSink(Target, Env, mode, fresh_transcript_sink_available);
        if (!report.accepted) return report;
        if (!accepting) return report;
        var supervisor = Supervision.Supervisor.init(self.allocator, permit, Target.WorldPortTable.entries.len) catch {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.SupervisionPolicyMismatch});
        };
        defer supervisor.deinit();
        supervisor.beforeHandoffAccept() catch |err| {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{supervisionPreflightBlocker(err)});
        };
        switch (mode) {
            .accept_fresh => if (runImageIsInterruptedSupervisionExport(self.run_image)) {
                self.preflightInterruptedReplayPrefixWithSupervisor(Target, &supervisor) catch |err| {
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{supervisionPreflightBlocker(err)});
                };
            } else {
                self.preflightReplayPrefixWithSupervisor(Target, Env, &supervisor) catch |err| {
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{supervisionPreflightBlocker(err)});
                };
            },
            .accept_replay, .accept_verify => self.preflightReplayRunWithSupervisor(Target, Env, modeToRunMode(mode), &supervisor) catch |err| {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{supervisionPreflightBlocker(err)});
            },
            .inspect_only => {},
        }
        return report;
    }

    fn preflightRequestFrameWithSupervisor(self: *@This(), supervisor: *Supervision.Supervisor, frame: Frame.Request) !void {
        try supervisor.beforeSessionStep();
        try supervisor.beforePortRequest(frame.world_port_id, 0, 0);
        const request_bytes = bytes: {
            const encoded = try frame.encode(self.allocator);
            defer self.allocator.free(encoded);
            break :bytes encoded.len;
        };
        try supervisor.accountPortRequestBytes(
            frame.world_port_id,
            request_bytes,
            if (frame.payload_image) |image| image.bytes.len else 0,
        );
    }

    fn preflightReplayPrefixWithSupervisor(self: *@This(), comptime Target: type, comptime Env: type, supervisor: *Supervision.Supervisor) !void {
        const pending_frame = self.run_image.pending_request_frame orelse return error.HandoffPendingFrameMismatch;
        const image = if (self.run_image.transcript_image) |*image| image else {
            if (pending_frame.turn_index != 0) return error.TranscriptImageRequired;
            try self.preflightRequestFrameWithSupervisor(supervisor, pending_frame);
            try supervisor.beforeAdapterCall(.{
                .world_port_id = pending_frame.world_port_id,
                .mode = .fresh,
                .adapter_kind = try adapterKindForEnvironmentPort(Env, pending_frame.world_port_id),
                .authority_kind = try authorityKindForEnvironmentPort(Env, pending_frame.world_port_id),
                .value_policy = try valuePolicyForEnvironmentPort(Env, pending_frame.world_port_id, .request),
            });
            return;
        };
        try image.prepareReplayPrefixForPendingRequest(
            Target.WorldSurface.surface_fingerprint,
            Target.Certificate.certificate_fingerprint,
            pending_frame.frame_fingerprint,
        );
        defer image.resetReplay();
        var index = image.replay_cursor;
        const limit = image.replay_limit orelse image.events.len;
        while (index < limit) : (index += 1) {
            const event = image.events[index];
            switch (event.kind) {
                .port_requested,
                .frame_requested,
                => {
                    const request_frame = event.request_frame orelse return error.ReplayMissing;
                    try self.preflightRequestFrameWithSupervisor(supervisor, request_frame);
                    try supervisor.beforeAdapterCall(.{
                        .world_port_id = request_frame.world_port_id,
                        .mode = .replay,
                        .adapter_kind = .replay,
                        .authority_kind = PortAuthority.replay_source.authority_kind,
                        .value_policy = .portable,
                    });
                },
                else => {},
            }
            if (eventKindIsSourceResponse(event.kind)) {
                const response_frame = event.response_frame orelse return error.ReplayMissing;
                const response_bytes = bytes: {
                    const encoded = try response_frame.encode(self.allocator);
                    defer self.allocator.free(encoded);
                    break :bytes encoded.len;
                };
                try supervisor.afterAdapterResponse(.{
                    .world_port_id = response_frame.world_port_id,
                    .status = response_frame.status,
                    .response_bytes = response_bytes,
                    .value_image_bytes = if (response_frame.response_image) |image_value| image_value.bytes.len else 0,
                });
            }
        }
        try self.preflightRequestFrameWithSupervisor(supervisor, pending_frame);
        try supervisor.beforeAdapterCall(.{
            .world_port_id = pending_frame.world_port_id,
            .mode = .fresh,
            .adapter_kind = try adapterKindForEnvironmentPort(Env, pending_frame.world_port_id),
            .authority_kind = try authorityKindForEnvironmentPort(Env, pending_frame.world_port_id),
            .value_policy = try valuePolicyForEnvironmentPort(Env, pending_frame.world_port_id, .request),
        });
    }

    fn preflightReplayRunWithSupervisor(self: *@This(), comptime Target: type, comptime Env: type, run_mode: Mode, supervisor: *Supervision.Supervisor) !void {
        const image = if (self.run_image.transcript_image) |*image| image else return error.TranscriptImageRequired;
        try image.validateReplayRun(
            Target.WorldSurface.surface_fingerprint,
            Target.Certificate.certificate_fingerprint,
        );
        defer image.resetReplay();
        var index = image.replay_cursor;
        const limit = image.replay_limit orelse image.events.len;
        while (index < limit) : (index += 1) {
            const event = image.events[index];
            switch (event.kind) {
                .port_requested,
                .frame_requested,
                => {
                    const request_frame = event.request_frame orelse return error.ReplayMissing;
                    try self.preflightRequestFrameWithSupervisor(supervisor, request_frame);
                    try supervisor.beforeAdapterCall(.{
                        .world_port_id = request_frame.world_port_id,
                        .mode = run_mode,
                        .adapter_kind = try adapterKindForEnvironmentPort(Env, request_frame.world_port_id),
                        .authority_kind = try authorityKindForEnvironmentPort(Env, request_frame.world_port_id),
                        .value_policy = try valuePolicyForEnvironmentPort(Env, request_frame.world_port_id, .request),
                    });
                },
                else => {},
            }
            if (eventKindIsSourceResponse(event.kind)) {
                const response_frame = event.response_frame orelse return error.ReplayMissing;
                const response_bytes = bytes: {
                    const encoded = try response_frame.encode(self.allocator);
                    defer self.allocator.free(encoded);
                    break :bytes encoded.len;
                };
                try supervisor.afterAdapterResponse(.{
                    .world_port_id = response_frame.world_port_id,
                    .status = response_frame.status,
                    .response_bytes = response_bytes,
                    .value_image_bytes = if (response_frame.response_image) |image_value| image_value.bytes.len else 0,
                });
                if (run_mode == .verify) {
                    try supervisor.afterAdapterResponse(.{
                        .world_port_id = response_frame.world_port_id,
                        .status = .responded,
                    });
                }
            }
        }
        try supervisor.beforeSessionStep();
    }

    fn preflightInterruptedReplayPrefixWithSupervisor(self: *@This(), comptime Target: type, supervisor: *Supervision.Supervisor) !void {
        if (self.run_image.current_state.turn_index == 0) return;
        const image = if (self.run_image.transcript_image) |*image| image else return error.TranscriptImageRequired;
        try image.prepareReplayPrefixForInterruptedRun(
            Target.WorldSurface.surface_fingerprint,
            Target.Certificate.certificate_fingerprint,
        );
        defer image.resetReplay();
        var index = image.replay_cursor;
        const limit = image.replay_limit orelse image.events.len;
        while (index < limit) : (index += 1) {
            const event = image.events[index];
            switch (event.kind) {
                .port_requested,
                .frame_requested,
                => {
                    const request_frame = event.request_frame orelse return error.ReplayMissing;
                    try self.preflightRequestFrameWithSupervisor(supervisor, request_frame);
                    try supervisor.beforeAdapterCall(.{
                        .world_port_id = request_frame.world_port_id,
                        .mode = .replay,
                        .adapter_kind = .replay,
                        .authority_kind = PortAuthority.replay_source.authority_kind,
                        .value_policy = .portable,
                    });
                },
                else => {},
            }
            if (eventKindIsSourceResponse(event.kind)) {
                const response_frame = event.response_frame orelse return error.ReplayMissing;
                const response_bytes = bytes: {
                    const encoded = try response_frame.encode(self.allocator);
                    defer self.allocator.free(encoded);
                    break :bytes encoded.len;
                };
                try supervisor.afterAdapterResponse(.{
                    .world_port_id = response_frame.world_port_id,
                    .status = response_frame.status,
                    .response_bytes = response_bytes,
                    .value_image_bytes = if (response_frame.response_image) |image_value| image_value.bytes.len else 0,
                });
            }
        }
    }

    pub fn inspectPriorReceipts(self: *@This()) struct {
        prior_run_permit_fingerprint: ?u64,
        prior_run_receipt_fingerprint: ?u64,
    } {
        return .{
            .prior_run_permit_fingerprint = self.run_image.prior_run_permit_fingerprint,
            .prior_run_receipt_fingerprint = self.run_image.prior_run_receipt_fingerprint,
        };
    }

    pub fn validatePendingFrame(self: *@This(), frame: Frame.Request) !void {
        const expected = self.run_image.pending_request_frame orelse return error.HandoffPendingFrameMismatch;
        if (expected.frame_fingerprint != frame.frame_fingerprint) return error.HandoffPendingFrameMismatch;
    }

    pub fn @"resume"(
        self: *@This(),
        comptime Target: type,
        comptime Env: type,
        runtime: anytype,
        args: anytype,
        options: anytype,
        mode: HandoffMode,
    ) !Machine(Target, Env.machine_config).Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
        return self.resumeWithSupervisorPermit(Target, Env, runtime, args, options, mode, null);
    }

    fn resumeWithSupervisorPermit(
        self: *@This(),
        comptime Target: type,
        comptime Env: type,
        runtime: anytype,
        args: anytype,
        options: anytype,
        mode: HandoffMode,
        permit_override: ?RunPermit,
    ) !Machine(Target, Env.machine_config).Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
        if (mode != .accept_fresh) return Error.InvalidMode;
        const Options = @TypeOf(options);
        const options_permit: ?RunPermit = if (comptime @hasField(Options, "permit")) @field(options, "permit") else null;
        const effective_permit = permit_override orelse options_permit;
        const fresh_transcript_sink_available = comptime @hasField(Options, "transcript") and Env.policy_decl.allow_native_adapters;
        const report = if (effective_permit) |permit|
            self.preflightWithPermitFreshTranscriptSink(Target, Env, mode, permit, fresh_transcript_sink_available)
        else
            self.preflightWithFreshTranscriptSink(Target, Env, mode, fresh_transcript_sink_available);
        if (!report.accepted) return acceptanceError(report);
        const MachineType = Machine(Target, Env.machine_config);
        const interrupted_export = runImageIsInterruptedSupervisionExport(self.run_image);
        if (interrupted_export) {
            if (effective_permit) |permit| {
                var accept_supervisor = try Supervision.Supervisor.init(@field(options, "allocator"), permit, Target.WorldPortTable.entries.len);
                defer accept_supervisor.deinit();
                try accept_supervisor.beforeHandoffAccept();
            }
            var run = if (permit_override) |permit|
                if (self.run_image.transcript_image) |*image|
                    try MachineType.startWithAdmittedTranscriptPermit(runtime, args, options, permit, image)
                else
                    try MachineType.startWithPermit(runtime, args, options, permit)
            else if (self.run_image.transcript_image) |*image|
                try MachineType.startWithAdmittedTranscript(runtime, args, options, image)
            else
                try MachineType.start(runtime, args, options);
            errdefer run.deinit();
            if (run.supervisor) |*supervisor| {
                supervisor.beforeHandoffAccept() catch |err| {
                    try run.handleSupervisionError(err);
                    unreachable;
                };
            }
            if (self.run_image.current_state.turn_index != 0) {
                const image = if (self.run_image.transcript_image) |*image| image else return error.TranscriptImageRequired;
                try image.prepareReplayPrefixForInterruptedRun(
                    Target.WorldSurface.surface_fingerprint,
                    Target.Certificate.certificate_fingerprint,
                );
                defer image.resetReplay();
                run.handoff_pending_frame_fingerprint = self.run_image.current_state.run_state_fingerprint;
                var resume_committed = false;
                errdefer if (!resume_committed) run.markRunFailed() catch {};
                replay_prefix: while (true) {
                    const step = run.nextFrame() catch |err| {
                        if (err == Error.HandlerPending) {
                            image.assertReplayComplete() catch |replay_err| {
                                run.audit.replay_mismatch_count += 1;
                                return replay_err;
                            };
                            run.handoff_pending_frame_fingerprint = null;
                            break :replay_prefix;
                        }
                        return err;
                    };
                    switch (step) {
                        .port_request => |request_frame| {
                            var request = request_frame;
                            defer request.deinit(run.allocator);
                            const response = image.nextResponse(request.replay_key_seed, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                                if (err == error.ReplayMissing) {
                                    image.assertReplayComplete() catch |replay_err| {
                                        run.audit.replay_mismatch_count += 1;
                                        return replay_err;
                                    };
                                    try run.accountPendingAdapterCall(request.world_port_id);
                                    run.handoff_pending_frame_fingerprint = null;
                                    break :replay_prefix;
                                }
                                run.audit.replay_mismatch_count += 1;
                                return err;
                            };
                            try run.accountReplayPrefixAdapterCall(request.world_port_id);
                            try run.resumeReplayedFrame(response.*);
                        },
                        else => return error.HandoffPendingFrameMismatch,
                    }
                }
                resume_committed = true;
            }
            return run;
        }
        if (self.run_image.current_state.status != .parked_on_port) return error.HandoffPendingFrameMismatch;
        const pending_frame = self.run_image.pending_request_frame orelse return error.HandoffPendingFrameMismatch;
        if (effective_permit) |permit| {
            var accept_supervisor = try Supervision.Supervisor.init(@field(options, "allocator"), permit, Target.WorldPortTable.entries.len);
            defer accept_supervisor.deinit();
            try accept_supervisor.beforeHandoffAccept();
        }
        var run = if (permit_override) |permit|
            try MachineType.startWithHandoffTranscriptPermit(runtime, args, options, permit)
        else
            try MachineType.startWithHandoffTranscript(runtime, args, options);
        errdefer run.deinit();
        run.handoff_pending_frame_fingerprint = pending_frame.frame_fingerprint;
        var resume_committed = false;
        errdefer if (!resume_committed) run.markRunFailed() catch {};
        if (run.supervisor) |*supervisor| {
            supervisor.beforeHandoffAccept() catch |err| {
                try run.handleSupervisionError(err);
                unreachable;
            };
        }
        if (self.run_image.transcript_image) |*image| {
            try image.prepareReplayPrefixForPendingRequest(
                Target.WorldSurface.surface_fingerprint,
                Target.Certificate.certificate_fingerprint,
                pending_frame.frame_fingerprint,
            );
        }
        while (true) {
            const step = try run.nextFrame();
            switch (step) {
                .port_request => |request_frame| {
                    var request = request_frame;
                    defer request.deinit(run.allocator);
                    if (pending_frame.frame_fingerprint == request.frame_fingerprint) {
                        if (self.run_image.transcript_image) |*image| {
                            image.assertReplayComplete() catch |err| {
                                run.audit.replay_mismatch_count += 1;
                                return err;
                            };
                        }
                        try self.validatePendingFrame(request);
                        try run.accountPendingAdapterCall(request.world_port_id);
                        run.handoff_pending_frame_fingerprint = null;
                        break;
                    }
                    const response = if (self.run_image.transcript_image) |*image|
                        image.nextResponse(request.replay_key_seed, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            run.audit.replay_mismatch_count += 1;
                            return err;
                        }
                    else
                        return error.HandoffPendingFrameMismatch;
                    try run.accountReplayPrefixAdapterCall(request.world_port_id);
                    try run.resumeReplayedFrame(response.*);
                },
                else => return error.HandoffPendingFrameMismatch,
            }
        }
        resume_committed = true;
        return run;
    }

    pub fn resumeWithPermit(
        self: *@This(),
        comptime Target: type,
        comptime Env: type,
        runtime: anytype,
        args: anytype,
        options: anytype,
        mode: HandoffMode,
        permit: RunPermit,
    ) !Machine(Target, Env.machine_config).Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
        const report = self.preflightWithPermit(Target, Env, mode, permit);
        if (!report.accepted) return acceptanceError(report);
        return self.resumeWithSupervisorPermit(Target, Env, runtime, args, options, mode, permit);
    }
};

pub fn PortRequest(comptime Target: type, comptime Descriptor: type) type {
    const world_port_id = descriptorWorldPortId(Target, Descriptor);
    return struct {
        world_surface_fingerprint: u64,
        target_certificate_fingerprint: u64,
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        request_fingerprint: u64,
        replay_key: ReplayKeySeed,
        turn_index: usize,
        value_table_payload_id: ?u32,
        value_table_response_id: ?u32,
        source_ref: @TypeOf(Target.WorldPortTable.entries[world_port_id].source_ref),
        world_port_ref: @TypeOf(Target.WorldPortTable.entries[world_port_id].world_port_ref),
        payload_value: Descriptor.Payload,

        pub fn payload(self: @This(), comptime Expected: type) !Expected.Payload {
            if (descriptorWorldPortId(Target, Expected) != self.world_port_id) return Error.PortMismatch;
            return self.payload_value;
        }

        pub fn expectPort(self: @This(), comptime Expected: type) !void {
            if (descriptorWorldPortId(Target, Expected) != self.world_port_id) return Error.PortMismatch;
        }

        pub fn summary(self: @This(), writer: anytype) !void {
            try writer.print(
                "surface={x} target={x} port={d} site={d} request={x} replay_scope={x}",
                .{
                    self.world_surface_fingerprint,
                    self.target_certificate_fingerprint,
                    self.world_port_id,
                    self.residual_site_index,
                    self.request_fingerprint,
                    self.replay_key.world_surface_scope_fingerprint,
                },
            );
        }
    };
}

pub fn PortResponse(comptime Target: type, comptime Descriptor: type) type {
    _ = Target;
    return struct {
        world_port_id: u32 = Descriptor.world_port_id,
        request_fingerprint: u64,
        response_kind: ResponseKind = .@"resume",
        value: ?Descriptor.Response = null,
        response_fingerprint: ?u64 = null,
        replay_key: ReplayKey,
        status: ResponseStatus = .responded,
    };
}

pub fn port(comptime Target: type, comptime Site: type, comptime handler_fn: anytype) type {
    return portWithOptions(Target, Site, handler_fn, .{});
}

pub fn portWithOptions(comptime Target: type, comptime Site: type, comptime handler_fn: anytype, comptime options: anytype) type {
    const id = comptime worldPortIdForSite(Target, Site) orelse
        @compileError("World port descriptor does not match target WorldPortTable");
    const entry = Target.WorldPortTable.entries[id];
    if (entry.residual_site_fingerprint != Site.fingerprint) {
        @compileError("World port site fingerprint mismatch");
    }
    if (!Site.may_resume) {
        @compileError("World v0 only supports resumable world ports");
    }
    return struct {
        pub const TargetType = Target;
        pub const SiteType = Site;
        pub const Payload = Site.Payload;
        pub const Response = Site.Resume;
        pub const Result = Site.Result;
        pub const world_port_id: u32 = id;
        pub const residual_site_index: usize = Site.index;
        pub const residual_site_fingerprint: u64 = Site.fingerprint;
        pub const payload_ref = Site.payload_ref;
        pub const response_ref = Site.resume_ref;
        pub const result_ref = Site.result_ref;
        pub const source_ref = entry.source_ref;
        pub const world_port_ref = entry.world_port_ref;
        pub const suggested_name = if (entry.semantic_label) |label| label else entry.op_name;
        pub const handler = handler_fn;
        pub const response_deinit = if (@hasField(@TypeOf(options), "response_deinit"))
            options.response_deinit
        else
            noopResponseDeinit;

        pub fn replayKey(request_fingerprint: u64) ReplayKeySeed {
            return .{
                .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                .world_surface_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                .world_port_id = world_port_id,
                .request_fingerprint = request_fingerprint,
            };
        }
    };
}

pub fn portById(comptime Target: type, comptime id: u32, comptime Site: type, comptime handler_fn: anytype) type {
    return portByIdWithOptions(Target, id, Site, handler_fn, .{});
}

pub fn portByIdWithOptions(comptime Target: type, comptime id: u32, comptime Site: type, comptime handler_fn: anytype, comptime options: anytype) type {
    if (id >= Target.WorldPortTable.entries.len) @compileError("world_port_id out of range");
    const entry = Target.WorldPortTable.entries[id];
    if (entry.residual_site_index != Site.index or entry.residual_site_fingerprint != Site.fingerprint) {
        @compileError("world_port_id does not point at Site");
    }
    const Descriptor = portWithOptions(Target, Site, handler_fn, options);
    if (Descriptor.world_port_id != id) @compileError("world_port_id does not point at Site");
    return Descriptor;
}

pub fn Machine(comptime Target: type, comptime Config: anytype) type {
    comptime validateTarget(Target);
    comptime validateConfig(Target, Config);
    const ConfigPorts = machineConfigPorts(Config);
    return struct {
        pub const target_world_surface_fingerprint = Target.WorldSurface.surface_fingerprint;
        pub const target_certificate_fingerprint = Target.Certificate.certificate_fingerprint;
        pub const port_count = Target.WorldPortTable.entries.len;

        pub fn assertAllPortsHandled() void {
            comptime assertAllPortsHandledFor(Target, Config);
        }

        pub fn assertNoExtraHandlers() void {
            comptime validateConfig(Target, Config);
        }

        pub fn assertSurfaceMatches(comptime expected: u64) void {
            if (expected != Target.WorldSurface.surface_fingerprint) @compileError("WorldSurface fingerprint mismatch");
        }

        pub fn assertNoSearchHotPath() void {
            Target.assertNoSearchHotPath();
        }

        pub fn assertReplayComplete(transcript: *const Transcript) !void {
            try transcript.assertReplayComplete();
        }

        pub fn start(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).start(runtime, args, options);
        }

        fn startWithPermit(runtime: anytype, args: anytype, options: anytype, permit: RunPermit) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailablePermit(runtime, args, options, false, permit, null);
        }

        fn startWithHandoffTranscript(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailable(runtime, args, options, true);
        }

        fn startWithHandoffTranscriptPermit(runtime: anytype, args: anytype, options: anytype, permit: RunPermit) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailablePermit(runtime, args, options, true, permit, null);
        }

        fn startWithAdmittedTranscript(runtime: anytype, args: anytype, options: anytype, transcript_image: *TranscriptImage) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailablePermit(runtime, args, options, false, null, transcript_image);
        }

        fn startWithAdmittedTranscriptPermit(runtime: anytype, args: anytype, options: anytype, permit: RunPermit, transcript_image: *TranscriptImage) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailablePermit(runtime, args, options, false, permit, transcript_image);
        }

        pub fn run(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).Result {
            var run_state = try start(runtime, args, options);
            defer run_state.deinit();
            while (true) {
                const step = try run_state.next();
                switch (step) {
                    .done => |value| {
                        const audit = try run_state.snapshotAudit();
                        const receipt = run_state.snapshotReceipt(.completed);
                        run_state.done_value_present = false;
                        return .{ .value = value, .audit = audit, .receipt = receipt };
                    },
                    .port_required => _ = run_state.dispatch() catch |err| {
                        if (run_state.audit.final_status == .parked) return Error.HandlerPending;
                        try run_state.markRunFailed();
                        return err;
                    },
                    .parked => return Error.HandlerPending,
                    .failed => return Error.HandlerFailed,
                }
            }
        }

        pub fn Run(comptime RuntimePtr: type, comptime Args: type, comptime Options: type) type {
            _ = Args;
            return struct {
                const Self = @This();
                const Program = Target.Program;
                const Session = Program.Session;
                const Request = Session.Request;
                const Value = Program.contract.ResultType;

                runtime: RuntimePtr,
                session: Session,
                allocator: std.mem.Allocator,
                mode: Mode,
                effective_mode: Mode,
                options: Options,
                pending_request: ?Request = null,
                pending_port_id: ?u32 = null,
                audit: AuditReport,
                per_port_counts: []usize,
                done_value: Value = undefined,
                done_value_present: bool = false,
                frame_step_request: bool = false,
                handoff_pending_frame_fingerprint: ?u64 = null,
                admitted_transcript_image: ?*TranscriptImage = null,
                pending_adapter_call_accounted: bool = false,
                retained_values: std.ArrayList(StoredValue) = .empty,
                last_response_evidence: ?Runspace.ResponseEvidence = null,
                supervisor: ?Supervision.Supervisor = null,

                pub const Result = struct {
                    value: Value,
                    audit: AuditReport,
                    receipt: ?RunReceipt = null,

                    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                        deinitRunValue(allocator, self.value);
                        allocator.free(self.audit.per_port_counts);
                        self.audit.per_port_counts = &.{};
                    }
                };

                pub const Step = union(enum) {
                    done: Value,
                    port_required,
                    parked,
                    failed,
                };

                fn snapshotAudit(self: *const Self) !AuditReport {
                    const counts = try self.allocator.dupe(usize, self.audit.per_port_counts);
                    var audit = self.audit;
                    audit.per_port_counts = counts;
                    return audit;
                }

                fn snapshotReceipt(self: *Self, final_status: RunReceipt.FinalStatus) ?RunReceipt {
                    if (self.supervisor) |*supervisor| {
                        const run_state = RunState.init(.{
                            .target_ref_fingerprint = TargetRef.fromTarget(Target).target_ref_fingerprint,
                            .transcript_image_fingerprint = if (comptime @hasField(Options, "transcript_image"))
                                @field(self.options, "transcript_image").transcript_image_fingerprint
                            else if (self.admitted_transcript_image) |image|
                                image.transcript_image_fingerprint
                            else
                                null,
                            .turn_index = self.audit.port_request_count,
                            .status = switch (final_status) {
                                .completed => .completed,
                                .failed, .rejected => .failed,
                                .parked, .interrupted => .parked_on_port,
                            },
                        });
                        return supervisor.receipt(final_status, run_state.run_state_fingerprint, run_state.transcript_image_fingerprint, null);
                    }
                    return null;
                }

                fn parkIfSupervisorInterrupted(self: *Self) bool {
                    if (self.supervisor) |*supervisor| {
                        if (supervisor.interrupted) {
                            self.audit.final_status = .parked;
                            return true;
                        }
                    }
                    return false;
                }

                fn handleSupervisionStepError(self: *Self, err: anyerror) !Step {
                    if (self.parkIfSupervisorInterrupted()) return .parked;
                    try self.markRunFailed();
                    return err;
                }

                fn handleSupervisionError(self: *Self, err: anyerror) !void {
                    if (self.parkIfSupervisorInterrupted()) return Error.HandlerPending;
                    try self.markRunFailed();
                    return err;
                }

                fn handlerErrorStatus(err: anyerror) ResponseStatus {
                    return switch (err) {
                        error.HandlerPending => .pending,
                        error.HandlerRejected => .rejected,
                        else => .failed,
                    };
                }

                fn accountNativeHandlerError(self: *Self, world_port_id: u32, err: anyerror) !void {
                    if (self.supervisor) |*supervisor| {
                        supervisor.afterAdapterResponse(.{
                            .world_port_id = world_port_id,
                            .status = handlerErrorStatus(err),
                        }) catch |supervision_err| {
                            try self.handleSupervisionError(supervision_err);
                            unreachable;
                        };
                    }
                }

                const ResponseAccounting = struct {
                    response_bytes: usize = 0,
                    value_image_bytes: usize = 0,
                    value_image_fingerprint: ?u64 = null,
                };

                fn responseFrameAccounting(self: *Self, frame: Frame.Response) !ResponseAccounting {
                    const encoded_response = try frame.encode(self.allocator);
                    defer self.allocator.free(encoded_response);
                    return .{
                        .response_bytes = encoded_response.len,
                        .value_image_bytes = if (frame.response_image) |image| image.bytes.len else 0,
                        .value_image_fingerprint = frame.response_value_fingerprint,
                    };
                }

                fn nativeResponseAccounting(self: *Self, comptime Decl: type, trace: anytype, response_fingerprint: u64, response: Decl.Response) !ResponseAccounting {
                    const value_policy: ValuePolicy = if (comptime @hasDecl(Decl, "value_policy")) Decl.value_policy else .native_compatible;
                    var response_image: ?Frame.ValueImage = Frame.ValueImage.fromValue(
                        self.allocator,
                        valueIdForRuntime(Target, Decl.world_port_id, .@"resume"),
                        response_fingerprint,
                        null,
                        response,
                        value_policy,
                    ) catch |err| switch (err) {
                        error.UnsupportedValueImage => if (value_policy.allow_native_only_values and value_policy.max_value_image_bytes == null) null else return err,
                        else => return err,
                    };
                    defer if (response_image) |*image| image.deinit(self.allocator);
                    const image = response_image orelse return .{};
                    const replay_key = ReplayKey{
                        .world_surface_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                        .world_port_id = Decl.world_port_id,
                        .request_fingerprint = trace.fingerprint,
                        .response_fingerprint = response_fingerprint,
                    };
                    const frame = Frame.Response.init(.{
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = Decl.world_port_id,
                        .request_fingerprint = trace.fingerprint,
                        .response_kind = .@"resume",
                        .response_value_table_id = valueIdForRuntime(Target, Decl.world_port_id, .@"resume"),
                        .response_fingerprint = response_fingerprint,
                        .response_image = image,
                        .replay_key = replay_key.fingerprint(),
                    });
                    return self.responseFrameAccounting(frame);
                }

                fn recordRunEvent(self: *Self, kind: EventKind, status: ?ResponseStatus, source_run: bool) !void {
                    const supervisor = if (self.supervisor) |*active| active else null;
                    try appendRunEventSupervised(self.allocator, Target, self.options, supervisor, kind, status, source_run);
                }

                fn recordPortEvent(
                    self: *Self,
                    kind: EventKind,
                    world_port_id: u32,
                    trace: anytype,
                    response_fingerprint: ?u64,
                    response_kind: ?ResponseKind,
                    value: ?StoredValue,
                    request_frame: ?Frame.Request,
                    response_frame: ?Frame.Response,
                ) !void {
                    const supervisor = if (self.supervisor) |*active| active else null;
                    try appendPortEventSupervised(self.allocator, Target, self.options, supervisor, kind, world_port_id, trace, response_fingerprint, response_kind, value, request_frame, response_frame);
                }

                fn markRunFailed(self: *Self) !void {
                    if (self.audit.final_status == .failed) return;
                    if (self.audit.final_status == .completed) return;
                    if (self.audit.final_status == .parked) return;
                    self.pending_request = null;
                    self.pending_port_id = null;
                    self.audit.final_status = .failed;
                    try self.recordRunEvent(.run_failed, null, false);
                }

                fn start(runtime: RuntimePtr, args: anytype, options: Options) !Self {
                    return startWithTranscriptAvailablePermit(runtime, args, options, false, null, null);
                }

                fn startWithTranscriptAvailable(runtime: RuntimePtr, args: anytype, options: Options, comptime handoff_transcript_available: bool) !Self {
                    return startWithTranscriptAvailablePermit(runtime, args, options, handoff_transcript_available, null, null);
                }

                fn startWithTranscriptAvailablePermit(runtime: RuntimePtr, args: anytype, options: Options, comptime handoff_transcript_available: bool, permit_override: ?RunPermit, admitted_transcript_image: ?*TranscriptImage) !Self {
                    const allocator = @field(options, "allocator");
                    const mode_value: Mode = if (@hasField(Options, "mode")) @field(options, "mode") else .fresh;
                    const effective = if (mode_value == .audit and @hasField(Options, "audit_source"))
                        @field(options, "audit_source")
                    else if (mode_value == .audit)
                        Mode.fresh
                    else
                        mode_value;
                    if (effective == .audit) return Error.InvalidMode;
                    const per_port_counts = try allocator.alloc(usize, Target.WorldPortTable.entries.len);
                    @memset(per_port_counts, 0);
                    errdefer allocator.free(per_port_counts);
                    try validateRuntimeSurfaceOptions(Target, options);
                    if (modeConsumesTranscript(effective) and
                        !@hasField(Options, "transcript") and
                        !@hasField(Options, "transcript_image") and
                        admitted_transcript_image == null)
                    {
                        return Error.ReplayMissing;
                    }
                    if (modeConsumesTranscript(effective) and
                        (@hasField(Options, "transcript_image") or admitted_transcript_image != null) and
                        ConfigPorts.len == 0 and
                        Target.WorldPortTable.entries.len != 0)
                    {
                        return Error.MissingHandler;
                    }
                    if (comptime @hasField(@TypeOf(Config), "environment")) {
                        const transcript_available = handoff_transcript_available or
                            admitted_transcript_image != null or
                            @hasField(Options, "transcript_image") or
                            (@hasField(Options, "transcript") and Config.environment.policy_decl.allow_native_adapters);
                        const report = Config.environment.acceptanceReport(effective, transcript_available);
                        if (!report.accepted) return acceptanceError(report);
                        if (modeConsumesTranscript(effective)) {
                            if (comptime @hasField(Options, "transcript_image")) {
                                try validateTranscriptImageForEnvironment(Config.environment, @field(options, "transcript_image"));
                            }
                            if (admitted_transcript_image) |image| {
                                try validateTranscriptImageForEnvironment(Config.environment, image);
                            }
                            if (comptime @hasField(Options, "transcript")) {
                                try validateTranscriptForEnvironment(Config.environment, @field(options, "transcript"));
                            }
                        }
                    }
                    var supervisor: ?Supervision.Supervisor = null;
                    errdefer if (supervisor) |*owned| owned.deinit();
                    const maybe_permit: ?RunPermit = if (permit_override) |permit|
                        permit
                    else if (comptime @hasField(Options, "permit"))
                        @field(options, "permit")
                    else
                        null;
                    if (maybe_permit) |permit| {
                        if (permit_override == null and (permit.module_ref_fingerprint != null or permit.admission_receipt_fingerprint != null)) return Error.SupervisionDenied;
                        if (permit.target_ref_fingerprint != TargetRef.fromTarget(Target).target_ref_fingerprint) return Error.SupervisionDenied;
                        if (permit.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return Error.SupervisionDenied;
                        if (permit.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return Error.SupervisionDenied;
                        if (permit.mode != mode_value) return Error.SupervisionDenied;
                        if (comptime @hasField(@TypeOf(Config), "environment")) {
                            const transcript_available = handoff_transcript_available or
                                admitted_transcript_image != null or
                                @hasField(Options, "transcript_image") or
                                (@hasField(Options, "transcript") and Config.environment.policy_decl.allow_native_adapters);
                            const supervision_transcript_available = if (permit.policy.require_transcript_image_for_replay and modeConsumesTranscript(effective))
                                @hasField(Options, "transcript_image") or admitted_transcript_image != null
                            else
                                transcript_available;
                            if (permit.policy.require_transcript_image_for_replay and modeConsumesTranscript(effective) and !supervision_transcript_available) return Error.TranscriptImageRequired;
                            const supervision_report = Config.environment.acceptanceReportWithPermit(mode_value, supervision_transcript_available, permit);
                            if (!supervision_report.accepted) return acceptanceError(supervision_report);
                            const cert = Config.environment.certificate(mode_value, transcript_available);
                            if (permit.environment_certificate_fingerprint != cert.certificate_fingerprint) return Error.SupervisionDenied;
                            if (permit.binding_plan_fingerprint != cert.binding_plan_fingerprint) return Error.SupervisionDenied;
                        } else if (permit.policy.require_environment_certificate) {
                            return Error.SupervisionDenied;
                        }
                        supervisor = try Supervision.Supervisor.init(allocator, permit, Target.WorldPortTable.entries.len);
                    }
                    var session = try Program.Session.startWithArgs(runtime, Program.Handlers{}, args);
                    errdefer session.deinit();
                    if (@hasField(Options, "transcript_image") and modeConsumesTranscript(effective)) {
                        @field(options, "transcript_image").resetReplay();
                        try @field(options, "transcript_image").validateReplayRun(
                            Target.WorldSurface.surface_fingerprint,
                            Target.Certificate.certificate_fingerprint,
                        );
                    }
                    if (admitted_transcript_image) |image| {
                        if (modeConsumesTranscript(effective)) {
                            image.resetReplay();
                            try image.validateReplayRun(
                                Target.WorldSurface.surface_fingerprint,
                                Target.Certificate.certificate_fingerprint,
                            );
                        }
                    }
                    if (@hasField(Options, "transcript")) {
                        if (modeConsumesTranscript(effective) and !@hasField(Options, "transcript_image") and admitted_transcript_image == null) {
                            @field(options, "transcript").resetReplay();
                            try @field(options, "transcript").validateReplayRun(
                                Target.WorldSurface.surface_fingerprint,
                                Target.Certificate.certificate_fingerprint,
                            );
                        }
                        const active_supervisor = if (supervisor) |*active| active else null;
                        const startup_event_count = @field(options, "transcript").events.items.len;
                        errdefer @field(options, "transcript").truncateRetainingCapacity(startup_event_count);
                        try appendRunEventSupervised(allocator, Target, options, active_supervisor, .run_started, null, effective == .fresh);
                        if (supervisor) |*active| {
                            try appendRunEventSupervised(allocator, Target, options, active, .permit_issued, null, false);
                            if (active.last_check) |check| {
                                _ = check;
                            }
                        }
                    }
                    const result = Self{
                        .runtime = runtime,
                        .session = session,
                        .allocator = allocator,
                        .mode = mode_value,
                        .effective_mode = effective,
                        .options = options,
                        .audit = .{
                            .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                            .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                            .mode = mode_value,
                            .per_port_counts = per_port_counts,
                        },
                        .per_port_counts = per_port_counts,
                        .supervisor = supervisor,
                        .admitted_transcript_image = admitted_transcript_image,
                    };
                    supervisor = null;
                    return result;
                }

                pub fn deinit(self: *Self) void {
                    if (self.done_value_present) {
                        deinitRunValue(self.allocator, self.done_value);
                        self.done_value_present = false;
                    }
                    self.session.deinit();
                    for (self.retained_values.items) |*value| value.deinit(self.allocator);
                    self.retained_values.deinit(self.allocator);
                    if (self.supervisor) |*supervisor| supervisor.deinit();
                    self.allocator.free(self.per_port_counts);
                }

                pub fn next(self: *Self) !Step {
                    if (self.audit.final_status == .completed) {
                        if (!self.done_value_present) return Error.HandlerFailed;
                        return .{ .done = self.done_value };
                    }
                    if (self.audit.final_status == .failed) return .failed;
                    if (self.audit.final_status == .parked) return .parked;
                    if (self.pending_request != null) return .port_required;
                    if (self.supervisor) |*supervisor| {
                        supervisor.beforeSessionStep() catch |err| {
                            return self.handleSupervisionStepError(err);
                        };
                    }
                    const session_step = self.session.next() catch |err| {
                        self.audit.failed_count += 1;
                        try self.markRunFailed();
                        return err;
                    };
                    switch (session_step) {
                        .done => |done| {
                            var result = done;
                            defer result.deinit();
                            self.done_value = try cloneRunValue(self.allocator, result.value);
                            self.done_value_present = true;
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript") and !@hasField(Options, "transcript_image") and self.admitted_transcript_image == null) {
                                @field(self.options, "transcript").assertReplayComplete() catch |err| {
                                    self.audit.replay_mismatch_count += 1;
                                    try self.markRunFailed();
                                    return err;
                                };
                            }
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript_image")) {
                                @field(self.options, "transcript_image").assertReplayComplete() catch |err| {
                                    self.audit.replay_mismatch_count += 1;
                                    try self.markRunFailed();
                                    return err;
                                };
                            }
                            if (modeConsumesTranscript(self.effective_mode)) {
                                if (self.admitted_transcript_image) |image| {
                                    image.assertReplayComplete() catch |err| {
                                        self.audit.replay_mismatch_count += 1;
                                        try self.markRunFailed();
                                        return err;
                                    };
                                }
                            }
                            self.recordRunEvent(.run_completed, null, self.effective_mode == .fresh) catch |err| {
                                return self.handleSupervisionStepError(err);
                            };
                            self.audit.final_status = .completed;
                            return .{ .done = self.done_value };
                        },
                        .after => {
                            try self.markRunFailed();
                            return Error.UnsupportedAfterRequest;
                        },
                        .request => |request| {
                            const trace = request.trace();
                            const world_port_id = Target.WorldDispatchTable.lookup(trace.operation_site_index) orelse {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.UnknownResidualSite;
                            };
                            if (world_port_id >= Target.WorldPortTable.entries.len) {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.UnknownWorldPort;
                            }
                            const entry = Target.WorldPortTable.entries[world_port_id];
                            if (entry.residual_site_fingerprint != trace.operation_site_fingerprint) {
                                self.audit.failed_count += 1;
                                try self.markRunFailed();
                                return Error.ResidualSiteFingerprintMismatch;
                            }
                            if (self.supervisor) |*supervisor| {
                                supervisor.beforePortRequest(world_port_id, 0, 0) catch |err| {
                                    return self.handleSupervisionStepError(err);
                                };
                            }
                            self.pending_request = request;
                            self.pending_port_id = world_port_id;
                            self.pending_adapter_call_accounted = false;
                            self.audit.port_request_count += 1;
                            self.per_port_counts[world_port_id] += 1;
                            if (!self.frame_step_request) {
                                if (self.supervisor) |*supervisor| {
                                    if (try supervisor.needsPortRequestByteAccounting(world_port_id)) {
                                        var request_frame = try self.pendingRequestFrame(false);
                                        defer request_frame.deinit(self.allocator);
                                        const encoded = try request_frame.encode(self.allocator);
                                        defer self.allocator.free(encoded);
                                        supervisor.accountPortRequestBytes(
                                            world_port_id,
                                            encoded.len,
                                            if (request_frame.payload_image) |image| image.bytes.len else 0,
                                        ) catch |err| {
                                            return self.handleSupervisionStepError(err);
                                        };
                                    }
                                }
                            }
                            if (self.effective_mode == .fresh) {
                                if (!self.frame_step_request) {
                                    try self.recordPortEvent(.port_requested, world_port_id, trace, null, null, null, null, null);
                                }
                            }
                            return .port_required;
                        },
                    }
                }

                pub fn dispatch(self: *Self) !void {
                    _ = try self.runspaceDispatch();
                }

                pub fn runspaceDispatch(self: *Self) !?Runspace.ResponseEvidence {
                    if (self.audit.final_status == .failed) return Error.HandlerFailed;
                    const request = self.pending_request orelse return Error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return Error.UnknownWorldPort;
                    const trace = request.trace();
                    if (Target.WorldPortTable.entries.len == 0) {
                        try self.markMissingHandler(world_port_id, trace);
                        return null;
                    }
                    self.last_response_evidence = null;
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                self.dispatchDecl(Decl, request) catch |err| {
                                    if (self.audit.final_status == .parked) return err;
                                    self.audit.failed_count += 1;
                                    try self.recordPortEvent(.port_failed, world_port_id, trace, null, null, null, null, null);
                                    try self.markRunFailed();
                                    return err;
                                };
                                self.pending_request = null;
                                self.pending_port_id = null;
                                self.pending_adapter_call_accounted = false;
                                return self.last_response_evidence;
                            }
                            try self.markMissingHandler(world_port_id, trace);
                            return null;
                        },
                        else => return Error.UnknownWorldPort,
                    }
                }

                pub const FrameStep = union(enum) {
                    done: Value,
                    port_request: Frame.Request,
                    failed,
                };

                pub fn nextFrame(self: *Self) !FrameStep {
                    self.frame_step_request = true;
                    defer self.frame_step_request = false;
                    const had_pending_request = self.pending_request != null;
                    const step = try self.next();
                    return switch (step) {
                        .done => |value| .{ .done = value },
                        .failed => .failed,
                        .parked => error.HandlerPending,
                        .port_required => request: {
                            var frame = try self.pendingRequestFrame(!had_pending_request);
                            errdefer frame.deinit(self.allocator);
                            if (self.handoff_pending_frame_fingerprint == null and !self.pending_adapter_call_accounted) {
                                try self.accountPendingAdapterCall(frame.world_port_id);
                            }
                            break :request .{ .port_request = frame };
                        },
                    };
                }

                pub fn resumeFrame(self: *Self, response_frame: Frame.Response) !void {
                    _ = try self.resumeFrameWithProvenance(response_frame, false, true);
                }

                pub fn runspaceResumeFrame(self: *Self, response_frame: Frame.Response) !Runspace.ResponseEvidence {
                    const response_frame_fingerprint = try self.resumeFrameWithProvenance(response_frame, false, false);
                    return self.last_response_evidence orelse .{
                        .response_fingerprint = response_frame.response_fingerprint,
                        .response_frame_fingerprint = response_frame_fingerprint,
                        .response_value_image_fingerprint = response_frame.response_value_fingerprint,
                    };
                }

                pub fn beforeRunspaceResponse(self: *Self, world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) !void {
                    if (self.supervisor) |*supervisor| {
                        try supervisor.afterAdapterResponse(.{
                            .world_port_id = world_port_id,
                            .status = status,
                            .response_bytes = response_bytes,
                            .value_image_bytes = value_image_bytes,
                        });
                    }
                }

                pub fn beforeRunspaceTerminalResponse(self: *Self, world_port_id: u32, status: ResponseStatus, response_bytes: usize, value_image_bytes: usize) !void {
                    if (status != .rejected and status != .failed) return error.InvalidPendingPortTransition;
                    if (self.supervisor) |*supervisor| {
                        try supervisor.afterAdapterResponse(.{
                            .world_port_id = world_port_id,
                            .status = status,
                            .response_bytes = response_bytes,
                            .value_image_bytes = value_image_bytes,
                        });
                    }
                }

                pub fn runspaceResumeTerminalFrame(self: *Self, response_frame: Frame.Response) !void {
                    switch (response_frame.status) {
                        .rejected => {
                            _ = self.resumeFrameWithProvenance(response_frame, false, false) catch |err| switch (err) {
                                Error.HandlerRejected => {},
                                else => return err,
                            };
                        },
                        .failed => {
                            _ = self.resumeFrameWithProvenance(response_frame, false, false) catch |err| switch (err) {
                                Error.HandlerFailed => {},
                                else => return err,
                            };
                        },
                        else => {
                            _ = try self.resumeFrameWithProvenance(response_frame, false, true);
                        },
                    }
                }

                pub fn snapshotRunImage(self: *Self) !RunImage {
                    const target_ref = TargetRef.fromTarget(Target);
                    var transcript_image: ?TranscriptImage = null;
                    var owns_transcript_image = false;
                    errdefer if (owns_transcript_image) {
                        if (transcript_image) |*image| image.deinit(self.allocator);
                    };
                    if (comptime @hasField(Options, "transcript")) {
                        transcript_image = try @field(self.options, "transcript").toImage(self.allocator, .{ .value_policy = ValuePolicy.portable });
                        owns_transcript_image = true;
                    } else if (comptime @hasField(Options, "transcript_image")) {
                        transcript_image = try cloneTranscriptImage(self.allocator, @field(self.options, "transcript_image").*);
                        owns_transcript_image = true;
                    } else if (self.admitted_transcript_image) |image| {
                        transcript_image = try cloneTranscriptImage(self.allocator, image.*);
                        owns_transcript_image = true;
                    }

                    var pending_frame: ?Frame.Request = null;
                    var owns_pending_frame = false;
                    errdefer if (owns_pending_frame) {
                        if (pending_frame) |*frame| frame.deinit(self.allocator);
                    };
                    if (self.pending_request != null) {
                        pending_frame = try self.pendingRequestFrame(false);
                        owns_pending_frame = true;
                    }

                    const status: RunState.Status = if (self.audit.final_status == .completed)
                        .completed
                    else if (self.audit.final_status == .failed)
                        .failed
                    else if (pending_frame != null)
                        .parked_on_port
                    else if (self.audit.final_status == .parked)
                        .parked_on_supervision
                    else
                        .running;
                    const terminal_response_evidence = if (status == .completed or status == .failed) self.last_response_evidence else null;
                    var state = RunState.init(.{
                        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                        .transcript_image_fingerprint = if (transcript_image) |image| image.transcript_image_fingerprint else null,
                        .pending_request_fingerprint = if (pending_frame) |frame| frame.frame_fingerprint else null,
                        .final_response_fingerprint = if (terminal_response_evidence) |evidence| evidence.response_frame_fingerprint orelse evidence.response_fingerprint else null,
                        .final_value_image_fingerprint = if (terminal_response_evidence) |evidence| evidence.response_value_image_fingerprint else null,
                        .turn_index = if (pending_frame) |frame| frame.turn_index else self.audit.port_request_count,
                        .status = status,
                    });
                    if (transcript_image) |image| {
                        state = runStateWithTranscriptEvidence(state, image);
                    }
                    var image = RunImage.init(.{
                        .kind = switch (status) {
                            .parked_on_port => .parked_run,
                            .completed => .completed_run,
                            .failed => .replay_only_run,
                            .not_started, .running, .parked_on_supervision => .full_target_run,
                        },
                        .target_ref = target_ref,
                        .import_set_fingerprint = ImportSet.fromTarget(Target).import_set_fingerprint,
                        .transcript_image = transcript_image,
                        .current_state = state,
                        .pending_request_frame = pending_frame,
                        .environment_certificate_fingerprint = if (comptime @hasField(@TypeOf(Config), "environment"))
                            Config.environment.certificate(self.mode, transcript_image != null).certificate_fingerprint
                        else
                            null,
                        .acceptance_report_fingerprint = if (comptime @hasField(@TypeOf(Config), "environment"))
                            Config.environment.acceptanceReport(self.mode, transcript_image != null).report_fingerprint
                        else
                            null,
                        .audit_image_fingerprint = AuditImage.fromReport(self.audit, transcript_image).audit_fingerprint,
                        .prior_run_permit_fingerprint = if (self.supervisor) |supervisor| supervisor.permit.permit_fingerprint else null,
                        .prior_run_receipt_fingerprint = if (self.supervisor) |*supervisor| blk: {
                            const final_status: RunReceipt.FinalStatus = switch (status) {
                                .completed => .completed,
                                .failed => .failed,
                                .parked_on_port => .parked,
                                .not_started, .running, .parked_on_supervision => .interrupted,
                            };
                            break :blk supervisor.receipt(final_status, state.run_state_fingerprint, state.transcript_image_fingerprint, null).receipt_fingerprint;
                        } else null,
                    });
                    image.owns_transcript_image = owns_transcript_image;
                    image.owns_pending_request_frame = owns_pending_frame;
                    owns_transcript_image = false;
                    owns_pending_frame = false;
                    return image;
                }

                pub fn beforeRunspaceHandoffExport(self: *Self) !void {
                    if (self.supervisor) |*supervisor| try supervisor.beforeHandoffExport();
                }

                pub fn beforeRunspaceInterruptedHandoffExport(self: *Self) !void {
                    if (self.supervisor) |*supervisor| try supervisor.beforeInterruptedHandoffExport();
                }

                pub fn beforeRunspaceCheckpoint(self: *Self, value_image_bytes: usize) !void {
                    if (self.supervisor) |*supervisor| try supervisor.beforeCheckpoint(value_image_bytes);
                }

                pub fn beforeRunspaceBranch(self: *Self, depth: usize) !void {
                    if (self.supervisor) |*supervisor| try supervisor.beforeBranch(depth);
                }

                fn resumeReplayedFrame(self: *Self, response_frame: Frame.Response) !void {
                    _ = try self.resumeFrameWithProvenance(response_frame, true, true);
                }

                fn resumeFrameWithProvenance(self: *Self, response_frame: Frame.Response, comptime replayed: bool, comptime account_supervisor: bool) !u64 {
                    const request = self.pending_request orelse return error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return error.UnknownWorldPort;
                    var frame = try self.pendingRequestFrame(false);
                    defer frame.deinit(self.allocator);
                    if (response_frame.world_surface_fingerprint != frame.world_surface_fingerprint) return error.FrameSurfaceMismatch;
                    if (response_frame.target_certificate_fingerprint != frame.target_certificate_fingerprint) return error.FrameTargetCertificateMismatch;
                    if (response_frame.world_port_id != world_port_id) return error.FramePortMismatch;
                    if (response_frame.request_fingerprint != frame.request_fingerprint) return error.FrameRequestFingerprintMismatch;
                    if (response_frame.status == .pending) {
                        if (account_supervisor) {
                            if (self.supervisor) |*supervisor| {
                                try validateResponseFrameImage(response_frame);
                                const accounting = try self.responseFrameAccounting(response_frame);
                                supervisor.afterAdapterResponse(.{
                                    .world_port_id = world_port_id,
                                    .status = response_frame.status,
                                    .response_bytes = accounting.response_bytes,
                                    .value_image_bytes = accounting.value_image_bytes,
                                }) catch |err| {
                                    try self.handleSupervisionError(err);
                                    return Error.HandlerPending;
                                };
                            }
                        }
                        return error.HandlerPending;
                    }
                    if (self.effective_mode != .fresh) return Error.InvalidMode;
                    if (response_frame.status == .responded and response_frame.response_value_table_id != frame.expected_response_value_table_id) return error.FrameValueTableMismatch;
                    try validateResponseFrameImage(response_frame);
                    const deferred_response_fingerprint = response_frame.responseFingerprintDeferred();
                    if (!deferred_response_fingerprint and response_frame.replay_key != frame.replay_key_seed.withResponse(response_frame.response_fingerprint).fingerprint()) return error.ReplayMissing;
                    if (account_supervisor) {
                        if (self.supervisor) |*supervisor| {
                            try validateResponseFrameImage(response_frame);
                            const accounting = try self.responseFrameAccounting(response_frame);
                            supervisor.afterAdapterResponse(.{
                                .world_port_id = world_port_id,
                                .status = response_frame.status,
                                .response_bytes = accounting.response_bytes,
                                .value_image_bytes = accounting.value_image_bytes,
                            }) catch |err| {
                                try self.handleSupervisionError(err);
                                return Error.HandlerPending;
                            };
                        }
                    }
                    if (response_frame.status == .rejected) {
                        self.audit.rejected_count += 1;
                        try self.recordPortEvent(.frame_rejected, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerRejected;
                    }
                    if (response_frame.status == .failed) {
                        self.audit.failed_count += 1;
                        try self.recordPortEvent(.frame_failed, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerFailed;
                    }
                    if (Target.WorldPortTable.entries.len == 0) {
                        try self.markMissingHandler(world_port_id, request.trace());
                        unreachable;
                    }
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                const effective_frame_fingerprint = try self.resumeFrameDecl(Decl, request, frame, response_frame, replayed);
                                self.pending_request = null;
                                self.pending_port_id = null;
                                self.pending_adapter_call_accounted = false;
                                return effective_frame_fingerprint;
                            }
                            try self.markMissingHandler(world_port_id, request.trace());
                            unreachable;
                        },
                        else => return error.UnknownWorldPort,
                    }
                }

                fn pendingRequestFrame(self: *Self, record_event: bool) !Frame.Request {
                    const request = self.pending_request orelse return error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return error.UnknownWorldPort;
                    const trace = request.trace();
                    if (Target.WorldPortTable.entries.len == 0) return self.markMissingHandlerFrame(world_port_id, trace);
                    if (Target.WorldPortTable.entries.len != 0) {
                        switch (world_port_id) {
                            inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                                const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                                if (Handler) |Decl| return try self.pendingRequestFrameDecl(Decl, request, world_port_id, record_event);
                                return self.markMissingHandlerFrame(world_port_id, trace);
                            },
                            else => return error.UnknownWorldPort,
                        }
                    }
                    return error.UnknownWorldPort;
                }

                fn pendingRequestFrameDecl(self: *Self, comptime Decl: type, request: Request, world_port_id: u32, record_event: bool) !Frame.Request {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    var payload_image: ?Frame.ValueImage = try Frame.ValueImage.fromValue(
                        self.allocator,
                        valueIdForRuntime(Target, world_port_id, .payload),
                        null,
                        null,
                        payload,
                        .portable,
                    );
                    errdefer if (payload_image) |*image| image.deinit(self.allocator);
                    const trace = request.trace();
                    var frame = Frame.Request.init(.{
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = world_port_id,
                        .residual_site_index = trace.operation_site_index,
                        .residual_site_fingerprint = trace.operation_site_fingerprint,
                        .request_fingerprint = trace.fingerprint,
                        .turn_index = trace.turn_index,
                        .payload_value_table_id = valueIdForRuntime(Target, world_port_id, .payload),
                        .expected_response_value_table_id = valueIdForRuntime(Target, world_port_id, .@"resume"),
                        .payload_image = payload_image,
                    });
                    payload_image = null;
                    errdefer frame.deinit(self.allocator);
                    if (record_event) {
                        if (self.supervisor) |*supervisor| {
                            const encoded = try frame.encode(self.allocator);
                            defer self.allocator.free(encoded);
                            supervisor.accountPortRequestBytes(
                                world_port_id,
                                encoded.len,
                                if (frame.payload_image) |image| image.bytes.len else 0,
                            ) catch |err| {
                                try self.handleSupervisionError(err);
                                return Error.HandlerPending;
                            };
                        }
                    }
                    if (record_event and self.effective_mode == .fresh) {
                        try self.recordPortEvent(.frame_requested, world_port_id, trace, null, null, null, frame, null);
                    }
                    return frame;
                }

                fn resumeFrameDecl(self: *Self, comptime Decl: type, request: Request, request_frame: Frame.Request, response_frame: Frame.Response, comptime replayed: bool) !u64 {
                    const typed_request = try request.as(Decl.SiteType);
                    if (response_frame.response_kind != .@"resume") return error.VerifyResponseKindMismatch;
                    const value = try response_frame.decodeValue(self.allocator, Decl.Response);
                    defer deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    var resolved_response_frame: ?Frame.Response = null;
                    if (response_frame.responseFingerprintDeferred()) {
                        resolved_response_frame = try response_frame.bindDeferredResponseFingerprint(self.allocator, request_frame, response_trace.fingerprint);
                    } else if (response_trace.fingerprint != response_frame.response_fingerprint) return error.VerifyResponseFingerprintMismatch;
                    defer if (resolved_response_frame) |*frame| frame.deinit(self.allocator);
                    const effective_response_frame = if (resolved_response_frame) |frame| frame else response_frame;
                    var stored: ?StoredValue = null;
                    if (comptime !replayed and @hasField(Options, "transcript")) {
                        stored = try StoredValue.init(@field(self.options, "transcript").allocator, value);
                    }
                    defer if (stored) |*owned| {
                        if (comptime @hasField(Options, "transcript")) {
                            owned.deinit(@field(self.options, "transcript").allocator);
                        }
                    };
                    var run_value = try StoredValue.init(self.allocator, value);
                    var run_value_owned = true;
                    errdefer if (run_value_owned) run_value.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, run_value);
                    run_value_owned = false;
                    var retained_committed = false;
                    errdefer if (!retained_committed) {
                        var retained = self.retained_values.pop().?;
                        retained.deinit(self.allocator);
                    };
                    const retained_value = try self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                    try self.recordPortEvent(
                        if (replayed) .frame_replayed else .frame_responded,
                        Decl.world_port_id,
                        request.trace(),
                        response_trace.fingerprint,
                        effective_response_frame.response_kind,
                        stored,
                        null,
                        effective_response_frame,
                    );
                    stored = null;
                    if (replayed) {
                        self.audit.replayed_response_count += 1;
                    } else {
                        self.audit.fresh_response_count += 1;
                    }
                    self.session.resumeTyped(typed_request, retained_value) catch |err| {
                        self.audit.failed_count += 1;
                        const failed_response_frame = Frame.Response.init(.{
                            .world_surface_fingerprint = effective_response_frame.world_surface_fingerprint,
                            .target_certificate_fingerprint = effective_response_frame.target_certificate_fingerprint,
                            .world_port_id = effective_response_frame.world_port_id,
                            .request_fingerprint = effective_response_frame.request_fingerprint,
                            .response_kind = effective_response_frame.response_kind,
                            .response_value_table_id = effective_response_frame.response_value_table_id,
                            .response_fingerprint = effective_response_frame.response_fingerprint,
                            .replay_key = effective_response_frame.replay_key,
                            .status = .failed,
                        });
                        try self.recordPortEvent(.frame_failed, Decl.world_port_id, request.trace(), response_trace.fingerprint, effective_response_frame.response_kind, null, null, failed_response_frame);
                        try self.markRunFailed();
                        return err;
                    };
                    retained_committed = true;
                    self.last_response_evidence = .{
                        .response_fingerprint = response_trace.fingerprint,
                        .response_frame_fingerprint = effective_response_frame.frame_fingerprint,
                        .response_value_image_fingerprint = effective_response_frame.response_value_fingerprint,
                    };
                    return effective_response_frame.frame_fingerprint;
                }

                fn markMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    try self.recordMissingHandler(world_port_id, trace);
                    return Error.MissingHandler;
                }

                fn markMissingHandlerFrame(self: *Self, world_port_id: u32, trace: anytype) !Frame.Request {
                    try self.recordMissingHandler(world_port_id, trace);
                    return Error.MissingHandler;
                }

                fn accountPendingAdapterCall(self: *Self, world_port_id: u32) !void {
                    if (Target.WorldPortTable.entries.len == 0) return Error.UnknownWorldPort;
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                try self.accountPendingAdapterCallDecl(Decl);
                                return;
                            }
                            return Error.MissingHandler;
                        },
                        else => return Error.UnknownWorldPort,
                    }
                }

                fn accountPendingAdapterCallDecl(self: *Self, comptime Decl: type) !void {
                    if (self.pending_adapter_call_accounted) return;
                    if (self.supervisor) |*supervisor| {
                        supervisor.beforeAdapterCall(.{
                            .world_port_id = Decl.world_port_id,
                            .mode = self.mode,
                            .accounting_mode = if (self.mode == .audit and self.effective_mode != .fresh) self.effective_mode else null,
                            .adapter_kind = comptime adapterKindForDecl(Decl),
                            .authority_kind = comptime authorityKindForDecl(Decl),
                            .value_policy = if (comptime @hasDecl(Decl, "value_policy")) Decl.value_policy else .native_compatible,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    self.pending_adapter_call_accounted = true;
                }

                fn accountReplayPrefixAdapterCall(self: *Self, world_port_id: u32) !void {
                    if (self.pending_adapter_call_accounted) return;
                    if (self.supervisor) |*supervisor| {
                        supervisor.beforeAdapterCall(.{
                            .world_port_id = world_port_id,
                            .mode = .replay,
                            .adapter_kind = .replay,
                            .authority_kind = PortAuthority.replay_source.authority_kind,
                            .value_policy = .portable,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    self.pending_adapter_call_accounted = true;
                }

                fn recordMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    self.audit.missing_handler_count += 1;
                    self.audit.failed_count += 1;
                    try self.recordPortEvent(.port_failed, world_port_id, trace, null, null, null, null, null);
                    try self.markRunFailed();
                }

                fn dispatchDecl(self: *Self, comptime Decl: type, request: Request) !void {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    const trace = request.trace();
                    const replay_key = Decl.replayKey(trace.fingerprint);
                    try self.accountPendingAdapterCallDecl(Decl);
                    const public_request = PortRequest(Target, Decl.SiteType){
                        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
                        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
                        .world_port_id = Decl.world_port_id,
                        .residual_site_index = trace.operation_site_index,
                        .residual_site_fingerprint = trace.operation_site_fingerprint,
                        .request_fingerprint = trace.fingerprint,
                        .replay_key = replay_key,
                        .turn_index = trace.turn_index,
                        .value_table_payload_id = valueIdFor(Target, Decl.world_port_id, .payload),
                        .value_table_response_id = valueIdFor(Target, Decl.world_port_id, .@"resume"),
                        .source_ref = Decl.source_ref,
                        .world_port_ref = Decl.world_port_ref,
                        .payload_value = payload,
                    };
                    switch (self.effective_mode) {
                        .fresh, .audit => {
                            if (comptime adapterKindForDecl(Decl) != .native) return Error.MissingHandler;
                            const value = try self.callFresh(Decl, public_request);
                            try self.session.resumeTyped(typed_request, value);
                        },
                        .verify => {
                            if (comptime adapterKindForDecl(Decl) != .native) return Error.MissingHandler;
                            const value = try self.callVerify(Decl, public_request, typed_request, replay_key);
                            try self.session.resumeTyped(typed_request, value);
                        },
                        .replay => {
                            const value = try self.callReplay(Decl, typed_request, replay_key, trace);
                            try self.session.resumeTyped(typed_request, value);
                        },
                    }
                }

                fn callFresh(self: *Self, comptime Decl: type, request: PortRequest(Target, Decl.SiteType)) !Decl.Response {
                    if (!@hasField(Options, "ctx")) return Error.MissingHandler;
                    const response = callHandler(Decl, @field(self.options, "ctx"), request) catch |err| {
                        try self.accountNativeHandlerError(Decl.world_port_id, err);
                        return err;
                    };
                    defer Decl.response_deinit(@field(self.options, "ctx"), response);
                    const typed = try (self.pending_request orelse return Error.UnknownResidualSite).as(Decl.SiteType);
                    const trace = (self.pending_request orelse return Error.UnknownResidualSite).trace();
                    const response_trace = try typed.responseTrace(.@"resume", response);
                    const accounting = try self.nativeResponseAccounting(Decl, trace, response_trace.fingerprint, response);
                    if (self.supervisor) |*supervisor| {
                        supervisor.afterAdapterResponse(.{
                            .world_port_id = Decl.world_port_id,
                            .status = .responded,
                            .response_bytes = accounting.response_bytes,
                            .value_image_bytes = accounting.value_image_bytes,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    var stored: ?StoredValue = null;
                    if (comptime @hasField(Options, "transcript")) {
                        stored = try StoredValue.init(@field(self.options, "transcript").allocator, response);
                    }
                    defer if (stored) |*owned| {
                        if (comptime @hasField(Options, "transcript")) {
                            owned.deinit(@field(self.options, "transcript").allocator);
                        }
                    };
                    try self.recordPortEvent(
                        .port_responded,
                        Decl.world_port_id,
                        (self.pending_request orelse return Error.UnknownResidualSite).trace(),
                        response_trace.fingerprint,
                        .@"resume",
                        stored,
                        null,
                        null,
                    );
                    stored = null;
                    self.last_response_evidence = .{
                        .response_fingerprint = response_trace.fingerprint,
                        .response_value_image_fingerprint = accounting.value_image_fingerprint,
                    };
                    self.audit.fresh_response_count += 1;
                    return try self.retainResponse(Decl.Response, response);
                }

                fn callReplay(
                    self: *Self,
                    comptime Decl: type,
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                    trace: anytype,
                ) !Decl.Response {
                    if (comptime @hasField(Options, "transcript_image")) {
                        return self.callReplayImage(Decl, typed_request, replay_key, trace, @field(self.options, "transcript_image"));
                    }
                    if (self.admitted_transcript_image) |image| {
                        return self.callReplayImage(Decl, typed_request, replay_key, trace, image);
                    }
                    if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    var replay_response_frame: ?Frame.Response = null;
                    const value = if (event.value) |stored|
                        try stored.as(self.allocator, Decl.Response)
                    else if (event.response_frame) |frame| value: {
                        if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                        try validateResponseFrameImage(frame);
                        replay_response_frame = frame;
                        break :value try frame.decodeValue(self.allocator, Decl.Response);
                    } else return Error.ReplayMissing;
                    var value_owned = true;
                    errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.ReplayResponseKindMismatch;
                    }
                    if (self.supervisor) |*supervisor| {
                        const response_bytes = if (replay_response_frame) |frame| bytes: {
                            const encoded_response = try frame.encode(self.allocator);
                            defer self.allocator.free(encoded_response);
                            break :bytes encoded_response.len;
                        } else 0;
                        supervisor.afterAdapterResponse(.{
                            .world_port_id = Decl.world_port_id,
                            .status = .responded,
                            .response_bytes = response_bytes,
                            .value_image_bytes = if (replay_response_frame) |frame| if (frame.response_image) |image| image.bytes.len else 0 else 0,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    try self.recordPortEvent(.port_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, replay_response_frame);
                    self.last_response_evidence = .{
                        .response_fingerprint = response_trace.fingerprint,
                        .response_frame_fingerprint = if (replay_response_frame) |frame| frame.frame_fingerprint else null,
                        .response_value_image_fingerprint = if (replay_response_frame) |frame| frame.response_value_fingerprint else null,
                    };
                    self.audit.replayed_response_count += 1;
                    var run_value = try StoredValue.initOwned(self.allocator, value);
                    value_owned = false;
                    var run_value_owned = true;
                    errdefer if (run_value_owned) run_value.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, run_value);
                    run_value_owned = false;
                    return self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                }

                fn callReplayImage(
                    self: *Self,
                    comptime Decl: type,
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                    trace: anytype,
                    image: *TranscriptImage,
                ) !Decl.Response {
                    const frame = image.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                    try validateResponseFrameImage(frame.*);
                    const value = try frame.decodeValue(self.allocator, Decl.Response);
                    var value_owned = true;
                    errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != frame.response_fingerprint) {
                        self.audit.replay_mismatch_count += 1;
                        return error.VerifyResponseFingerprintMismatch;
                    }
                    if (self.supervisor) |*supervisor| {
                        const encoded_response = try frame.encode(self.allocator);
                        defer self.allocator.free(encoded_response);
                        supervisor.afterAdapterResponse(.{
                            .world_port_id = Decl.world_port_id,
                            .status = .responded,
                            .response_bytes = encoded_response.len,
                            .value_image_bytes = if (frame.response_image) |value_image| value_image.bytes.len else 0,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    try self.recordPortEvent(.frame_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, frame.*);
                    self.last_response_evidence = .{
                        .response_fingerprint = response_trace.fingerprint,
                        .response_frame_fingerprint = frame.frame_fingerprint,
                        .response_value_image_fingerprint = frame.response_value_fingerprint,
                    };
                    self.audit.replayed_response_count += 1;
                    var run_value = try StoredValue.initOwned(self.allocator, value);
                    value_owned = false;
                    var run_value_owned = true;
                    errdefer if (run_value_owned) run_value.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, run_value);
                    run_value_owned = false;
                    return self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                }

                fn callVerify(
                    self: *Self,
                    comptime Decl: type,
                    request: PortRequest(Target, Decl.SiteType),
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                ) !Decl.Response {
                    if (!@hasField(Options, "ctx")) return Error.MissingHandler;
                    var expected_response_fingerprint: u64 = undefined;
                    var expected_value_image_fingerprint: ?u64 = null;
                    var expected_value_table_id: ?u32 = null;
                    var expected_boundary_value_fingerprint: ?u64 = null;
                    var expected_codec_schema_descriptor_fingerprint: ?u64 = null;
                    var expected_value_policy = ValuePolicy.portable;
                    var expected_response_frame: ?Frame.Response = null;
                    if (comptime @hasField(Options, "transcript_image")) {
                        try self.loadVerifyExpectationsFromImage(
                            Decl,
                            typed_request,
                            replay_key,
                            @field(self.options, "transcript_image"),
                            &expected_response_fingerprint,
                            &expected_value_image_fingerprint,
                            &expected_value_table_id,
                            &expected_boundary_value_fingerprint,
                            &expected_codec_schema_descriptor_fingerprint,
                            &expected_value_policy,
                            &expected_response_frame,
                        );
                    } else if (self.admitted_transcript_image) |image| {
                        try self.loadVerifyExpectationsFromImage(
                            Decl,
                            typed_request,
                            replay_key,
                            image,
                            &expected_response_fingerprint,
                            &expected_value_image_fingerprint,
                            &expected_value_table_id,
                            &expected_boundary_value_fingerprint,
                            &expected_codec_schema_descriptor_fingerprint,
                            &expected_value_policy,
                            &expected_response_frame,
                        );
                    } else {
                        if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                        const transcript = @field(self.options, "transcript");
                        const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            self.audit.replay_mismatch_count += 1;
                            return err;
                        };
                        expected_response_fingerprint = event.response_fingerprint orelse return Error.ReplayMissing;
                        const replay_value = if (event.value) |stored|
                            stored.as(self.allocator, Decl.Response) catch |err| {
                                self.audit.replay_mismatch_count += 1;
                                return err;
                            }
                        else if (event.response_frame) |frame| value: {
                            expected_response_frame = frame;
                            if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                            try validateResponseFrameImage(frame);
                            if (frame.response_image) |response_image| {
                                expected_value_image_fingerprint = response_image.value_image_fingerprint;
                                expected_value_table_id = response_image.value_table_id;
                                expected_boundary_value_fingerprint = response_image.boundary_value_fingerprint;
                                expected_codec_schema_descriptor_fingerprint = response_image.codec_schema_descriptor_fingerprint;
                                if (response_image.diagnostic_type_label != null) expected_value_policy = ValuePolicy.native_compatible;
                            } else {
                                expected_value_image_fingerprint = frame.response_value_fingerprint;
                            }
                            break :value frame.decodeValue(self.allocator, Decl.Response) catch |err| {
                                self.audit.replay_mismatch_count += 1;
                                return err;
                            };
                        } else return Error.ReplayMissing;
                        defer deinitOwnedValue(self.allocator, replay_value);
                        const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                        if (replay_trace.fingerprint != expected_response_fingerprint) {
                            self.audit.replay_mismatch_count += 1;
                            return Error.VerifyDivergence;
                        }
                    }
                    self.audit.replayed_response_count += 1;
                    if (self.supervisor) |*supervisor| {
                        if (expected_response_frame) |frame| {
                            const expected_accounting = try self.responseFrameAccounting(frame);
                            supervisor.afterAdapterResponse(.{
                                .world_port_id = Decl.world_port_id,
                                .status = .responded,
                                .response_bytes = expected_accounting.response_bytes,
                                .value_image_bytes = expected_accounting.value_image_bytes,
                            }) catch |err| {
                                try self.handleSupervisionError(err);
                                return Error.HandlerPending;
                            };
                        } else {
                            supervisor.afterAdapterResponse(.{
                                .world_port_id = Decl.world_port_id,
                                .status = .responded,
                            }) catch |err| {
                                try self.handleSupervisionError(err);
                                return Error.HandlerPending;
                            };
                        }
                    }
                    const fresh = callHandler(Decl, @field(self.options, "ctx"), request) catch |err| {
                        try self.accountNativeHandlerError(Decl.world_port_id, err);
                        return err;
                    };
                    defer Decl.response_deinit(@field(self.options, "ctx"), fresh);
                    const response_trace = try typed_request.responseTrace(.@"resume", fresh);
                    const fresh_accounting = try self.nativeResponseAccounting(Decl, (self.pending_request orelse return Error.UnknownResidualSite).trace(), response_trace.fingerprint, fresh);
                    if (self.supervisor) |*supervisor| {
                        supervisor.afterAdapterResponse(.{
                            .world_port_id = Decl.world_port_id,
                            .status = .responded,
                            .response_bytes = fresh_accounting.response_bytes,
                            .value_image_bytes = fresh_accounting.value_image_bytes,
                        }) catch |err| {
                            try self.handleSupervisionError(err);
                            return Error.HandlerPending;
                        };
                    }
                    if (response_trace.fingerprint != expected_response_fingerprint) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.VerifyDivergence;
                    }
                    if (expected_value_image_fingerprint) |expected_image_fingerprint| {
                        var fresh_image = try Frame.ValueImage.fromValue(
                            self.allocator,
                            expected_value_table_id,
                            expected_boundary_value_fingerprint,
                            expected_codec_schema_descriptor_fingerprint,
                            fresh,
                            expected_value_policy,
                        );
                        defer fresh_image.deinit(self.allocator);
                        if (fresh_image.value_image_fingerprint != expected_image_fingerprint) return error.VerifyValueImageMismatch;
                    }
                    if (expected_response_frame) |frame| {
                        try self.recordPortEvent(.frame_verified, Decl.world_port_id, (self.pending_request orelse return Error.UnknownResidualSite).trace(), expected_response_fingerprint, .@"resume", null, null, frame);
                    }
                    self.last_response_evidence = .{
                        .response_fingerprint = expected_response_fingerprint,
                        .response_frame_fingerprint = if (expected_response_frame) |frame| frame.frame_fingerprint else null,
                        .response_value_image_fingerprint = expected_value_image_fingerprint,
                    };
                    self.audit.fresh_response_count += 1;
                    return try self.retainResponse(Decl.Response, fresh);
                }

                fn loadVerifyExpectationsFromImage(
                    self: *Self,
                    comptime Decl: type,
                    typed_request: anytype,
                    replay_key: ReplayKeySeed,
                    image: *TranscriptImage,
                    expected_response_fingerprint: *u64,
                    expected_value_image_fingerprint: *?u64,
                    expected_value_table_id: *?u32,
                    expected_boundary_value_fingerprint: *?u64,
                    expected_codec_schema_descriptor_fingerprint: *?u64,
                    expected_value_policy: *ValuePolicy,
                    expected_response_frame: *?Frame.Response,
                ) !void {
                    const frame = image.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    try validateResponseFrameImage(frame.*);
                    expected_response_frame.* = frame.*;
                    expected_response_fingerprint.* = frame.response_fingerprint;
                    if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                    if (frame.response_image) |response_image| {
                        expected_value_image_fingerprint.* = response_image.value_image_fingerprint;
                        expected_value_table_id.* = response_image.value_table_id;
                        expected_boundary_value_fingerprint.* = response_image.boundary_value_fingerprint;
                        expected_codec_schema_descriptor_fingerprint.* = response_image.codec_schema_descriptor_fingerprint;
                        if (response_image.diagnostic_type_label != null) expected_value_policy.* = ValuePolicy.native_compatible;
                    } else {
                        expected_value_image_fingerprint.* = frame.response_value_fingerprint;
                    }
                    const replay_value = try frame.decodeValue(self.allocator, Decl.Response);
                    defer deinitOwnedValue(self.allocator, replay_value);
                    const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                    if (replay_trace.fingerprint != expected_response_fingerprint.*) {
                        self.audit.replay_mismatch_count += 1;
                        return error.VerifyDivergence;
                    }
                }

                fn retainResponse(self: *Self, comptime Response: type, value: Response) !Response {
                    var retained = try StoredValue.init(self.allocator, value);
                    var retained_owned = true;
                    errdefer if (retained_owned) retained.deinit(self.allocator);
                    try self.retained_values.append(self.allocator, retained);
                    retained_owned = false;
                    return self.retained_values.items[self.retained_values.items.len - 1].borrow(Response);
                }
            };
        }
    };
}

fn validateTarget(comptime Target: type) void {
    const required = .{
        "Program",
        "WorldSurface",
        "WorldPortTable",
        "WorldValueTable",
        "WorldDispatchTable",
        "Certificate",
    };
    inline for (required) |decl| {
        if (!@hasDecl(Target, decl)) @compileError("Boundary Target missing " ++ decl);
    }
    Target.assertWorldSurfaceReady();
    Target.assertNoSearchHotPath();
}

fn machineConfigPorts(comptime Config: anytype) @TypeOf(if (@hasField(@TypeOf(Config), "environment")) Config.environment.ports else Config.ports) {
    return if (@hasField(@TypeOf(Config), "environment")) Config.environment.ports else Config.ports;
}

fn boundPorts(comptime bindings: anytype) [bindings.len]type {
    var result: [bindings.len]type = undefined;
    inline for (bindings, 0..) |BindingDecl, index| result[index] = BindingDecl;
    return result;
}

fn bindingPlanEntryCount(comptime Target: type, comptime bindings: anytype) comptime_int {
    var count: usize = 0;
    inline for (bindings) |BindingDecl| {
        if (BindingDecl.TargetType == Target and BindingDecl.world_port_id < Target.WorldPortTable.entries.len) count += 1;
    }
    return count;
}

fn bindingPlanEntries(comptime Target: type, comptime bindings: anytype) [bindingPlanEntryCount(Target, bindings)]BindingPlan.Entry {
    var result: [bindingPlanEntryCount(Target, bindings)]BindingPlan.Entry = undefined;
    var out_index: usize = 0;
    inline for (0..Target.WorldPortTable.entries.len) |world_port_id| {
        inline for (bindings, 0..) |BindingDecl, binding_index| {
            if (BindingDecl.TargetType == Target and BindingDecl.world_port_id == world_port_id) {
                result[out_index] = bindingPlanEntryFor(Target, BindingDecl, binding_index);
                out_index += 1;
            }
        }
    }
    return result;
}

fn bindingPlanEntryFor(comptime Target: type, comptime BindingDecl: type, comptime binding_index: usize) BindingPlan.Entry {
    const record = bindingRecordFor(Target, BindingDecl);
    return .{
        .world_port_id = BindingDecl.world_port_id,
        .adapter_slot = binding_index,
        .binding_fingerprint = record.binding_fingerprint,
        .adapter_kind = if (@hasDecl(BindingDecl, "adapter_kind")) BindingDecl.adapter_kind else .native,
        .value_policy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible,
        .authority_fingerprint = if (@hasDecl(BindingDecl, "authority")) BindingDecl.authority.authority_fingerprint else null,
        .adapter_descriptor_fingerprint = record.adapter_descriptor_fingerprint,
    };
}

fn bindingPlanFor(
    comptime Target: type,
    comptime bindings: anytype,
    policy: EnvironmentPolicy,
    entries: []const BindingPlan.Entry,
    accepted: bool,
) BindingPlan {
    const target_ref = TargetRef.fromTarget(Target);
    var plan = BindingPlan{
        .plan_fingerprint = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .binding_count = bindings.len,
        .dense_entries = entries,
        .accepted = accepted,
    };
    _ = policy;
    plan.plan_fingerprint = fingerprintBindingPlan(plan);
    return plan;
}

fn acceptanceReportFor(
    comptime Target: type,
    comptime bindings: anytype,
    policy: EnvironmentPolicy,
    requested_mode: Mode,
    transcript_image_available: bool,
) AcceptanceReport {
    const target_ref = TargetRef.fromTarget(Target);
    var report = AcceptanceReport{
        .report_fingerprint = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .requested_mode = requested_mode,
        .accepted = true,
        .required_port_count = Target.WorldPortTable.entries.len,
        .bound_port_count = bindings.len,
        .summary = "accepted",
    };
    if (policy.max_world_ports) |max| {
        if (Target.WorldPortTable.entries.len > max) return rejectedReport(report, &.{.SurfaceProfileIncompatible});
    }
    if (policy.max_bindings) |max| {
        if (bindings.len > max) return rejectedReport(report, &.{.ExtraBinding});
    }
    inline for (bindings, 0..) |BindingDecl, index| {
        if (BindingDecl.TargetType != Target) return rejectedReport(report, &.{.HandoffTargetMismatch});
        if (BindingDecl.world_port_id >= Target.WorldPortTable.entries.len) return rejectedReport(report, &.{.WrongPortId});
        if (bindingRecordBlockerFor(Target, BindingDecl, policy)) |blocker| return rejectedReportForBindingRecordBlocker(report, blocker);
        inline for (bindings, 0..) |Other, other_index| {
            if (other_index > index and BindingDecl.world_port_id == Other.world_port_id) return rejectedReport(report, &.{.ExtraBinding});
        }
        const kind: AdapterKind = if (@hasDecl(BindingDecl, "adapter_kind")) BindingDecl.adapter_kind else .native;
        switch (kind) {
            .native => report.native_port_count += 1,
            .replay => report.replay_only_port_count += 1,
            .byte => report.byte_adapter_port_count += 1,
            else => {},
        }
        if (kind == .native and !policy.allow_native_adapters) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (kind == .byte and !policy.allow_byte_adapters) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (kind == .pending_stub and !policy.allow_pending_adapters) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (kind == .null_reject and !policy.allow_reject_adapters) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if ((requested_mode == .fresh or requested_mode == .audit) and kind != .native) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (kind == .replay and requested_mode != .replay) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (requested_mode == .verify and kind != .native) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (kind == .replay and !policy.allow_replay_without_handlers) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        if (@hasDecl(BindingDecl, "authority") and !authorityAllowsMode(BindingDecl.authority, requested_mode)) return rejectedReport(report, &.{.AdapterModeNotAllowed});
        const value_policy: ValuePolicy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible;
        if (value_policy.require_portable_values) report.portable_value_compatible_count += 1 else report.native_only_value_count += 1;
        if (@hasDecl(BindingDecl, "authority")) {
            if (BindingDecl.authority.requires_portable_values and !value_policy.require_portable_values) return rejectedReport(report, &.{.PortableValuesRequired});
            if (!BindingDecl.authority.allows_native_only_values and value_policy.allow_native_only_values) return rejectedReport(report, &.{.NativeOnlyValueRejected});
            if (BindingDecl.authority.max_payload_image_bytes) |max| {
                const policy_max = value_policy.max_value_image_bytes orelse return rejectedReport(report, &.{.PayloadValueMismatch});
                if (policy_max > max) return rejectedReport(report, &.{.PayloadValueMismatch});
            }
            if (BindingDecl.authority.max_response_image_bytes) |max| {
                const policy_max = value_policy.max_value_image_bytes orelse return rejectedReport(report, &.{.ResponseValueMismatch});
                if (policy_max > max) return rejectedReport(report, &.{.ResponseValueMismatch});
            }
        }
        if (policy.require_portable_values and !value_policy.require_portable_values) return rejectedReport(report, &.{.PortableValuesRequired});
        if (!policy.allow_native_only_values and value_policy.allow_native_only_values) return rejectedReport(report, &.{.NativeOnlyValueRejected});
    }
    if ((policy.require_all_required_ports_bound or requested_mode != .audit) and bindings.len < Target.WorldPortTable.entries.len) {
        report.missing_port_count = Target.WorldPortTable.entries.len - bindings.len;
        return rejectedReport(report, &.{.MissingBinding});
    }
    if (policy.reject_extra_bindings and bindings.len > Target.WorldPortTable.entries.len) {
        report.extra_binding_count = bindings.len - Target.WorldPortTable.entries.len;
        return rejectedReport(report, &.{.ExtraBinding});
    }
    if (requested_mode == .fresh and !transcript_image_available and !policy.allow_fresh_without_transcript) return rejectedReport(report, &.{.TranscriptImageRequired});
    if (requested_mode == .replay and !transcript_image_available and policy.require_frame_images_for_replay) return rejectedReport(report, &.{.TranscriptImageRequired});
    if (requested_mode == .verify and !transcript_image_available and !policy.allow_verify_without_transcript) return rejectedReport(report, &.{.VerifyTranscriptMissing});
    report.report_fingerprint = fingerprintAcceptanceReport(report);
    return report;
}

fn bindingRecordBlockerFor(comptime Target: type, comptime BindingDecl: type, policy: EnvironmentPolicy) ?AcceptanceBlocker {
    const target_ref = TargetRef.fromTarget(Target);
    const requirement = ImportRequirement.fromTargetPort(Target, BindingDecl.world_port_id);
    const record = bindingRecordFor(Target, BindingDecl);
    if (record.binding_fingerprint != fingerprintBinding(record)) return .HandoffTargetMismatch;
    if (record.target_ref_fingerprint != target_ref.target_ref_fingerprint) return .HandoffTargetMismatch;
    if (policy.reject_wrong_surface and record.world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return .WrongWorldSurface;
    if (policy.require_target_certificate_match and record.target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return .WrongTargetCertificate;
    if (record.world_port_id != BindingDecl.world_port_id) return .WrongPortId;
    if (record.import_requirement_fingerprint != requirement.requirement_fingerprint) return .HandoffTargetMismatch;
    if (record.world_port_ref_fingerprint != requirement.world_port_ref_fingerprint) return .HandoffTargetMismatch;
    if (record.source_effect_shape_ref_fingerprint != requirement.source_effect_shape_ref_fingerprint) return .HandoffTargetMismatch;
    if (record.payload_value_table_id != requirement.payload_value_table_id) return .PayloadValueMismatch;
    if (record.response_value_table_id != requirement.response_value_table_id) return .ResponseValueMismatch;
    const declared_kind: AdapterKind = if (@hasDecl(BindingDecl, "adapter_kind")) BindingDecl.adapter_kind else .native;
    const declared_value_policy: ValuePolicy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible;
    const declared_authority_fingerprint = if (@hasDecl(BindingDecl, "authority")) BindingDecl.authority.authority_fingerprint else null;
    if (record.adapter_kind != declared_kind) return .AdapterModeNotAllowed;
    if (!std.meta.eql(record.value_policy, declared_value_policy)) return .HandoffTargetMismatch;
    if (record.authority_fingerprint != declared_authority_fingerprint) return .HandoffTargetMismatch;
    if (record.adapter_descriptor_fingerprint != adapterDescriptorFingerprintForBindingDecl(Target, BindingDecl)) return .HandoffTargetMismatch;
    return null;
}

fn rejectedReportForBindingRecordBlocker(base: AcceptanceReport, blocker: AcceptanceBlocker) AcceptanceReport {
    return switch (blocker) {
        .HandoffTargetMismatch => rejectedReport(base, &.{.HandoffTargetMismatch}),
        .WrongWorldSurface => rejectedReport(base, &.{.WrongWorldSurface}),
        .WrongTargetCertificate => rejectedReport(base, &.{.WrongTargetCertificate}),
        .WrongPortId => rejectedReport(base, &.{.WrongPortId}),
        .PayloadValueMismatch => rejectedReport(base, &.{.PayloadValueMismatch}),
        .ResponseValueMismatch => rejectedReport(base, &.{.ResponseValueMismatch}),
        .AdapterModeNotAllowed => rejectedReport(base, &.{.AdapterModeNotAllowed}),
        else => unreachable,
    };
}

fn adapterDescriptorFingerprintForBindingDecl(comptime Target: type, comptime BindingDecl: type) u64 {
    const target_ref = TargetRef.fromTarget(Target);
    const declared_kind: AdapterKind = if (@hasDecl(BindingDecl, "adapter_kind")) BindingDecl.adapter_kind else .native;
    const declared_value_policy: ValuePolicy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible;
    const declared_authority_fingerprint = if (@hasDecl(BindingDecl, "authority")) BindingDecl.authority.authority_fingerprint else null;
    const label = if (@hasDecl(BindingDecl, "suggested_name")) BindingDecl.suggested_name else "";
    return AdapterDescriptor.init(.{
        .adapter_kind = declared_kind,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .world_port_id = BindingDecl.world_port_id,
        .value_policy = declared_value_policy,
        .authority_fingerprint = declared_authority_fingerprint,
        .label = label,
        .replay_source_fingerprint = if (@hasDecl(BindingDecl, "replay_source_fingerprint")) BindingDecl.replay_source_fingerprint else null,
        .byte_adapter_protocol_label = if (@hasDecl(BindingDecl, "byte_adapter_protocol_label")) BindingDecl.byte_adapter_protocol_label else null,
    }).descriptor_fingerprint;
}

fn acceptedModeMask(report: AcceptanceReport) EnvironmentCertificate.ModeMask {
    if (!report.accepted) return .none;
    return switch (report.requested_mode) {
        .fresh => .fresh,
        .replay => .replay,
        .verify => .verify,
        .audit => .audit,
    };
}

fn authorityAllowsMode(authority: PortAuthority, requested_mode: Mode) bool {
    if (!portAuthorityModeMaskAllows(authority.allowed_modes, requested_mode)) return false;
    return switch (requested_mode) {
        .fresh => authority.allows_fresh_calls,
        .replay => authority.allows_replay,
        .verify => authority.allows_verify,
        .audit => true,
    };
}

fn portAuthorityModeMaskAllows(mask: PortAuthority.ModeMask, requested_mode: Mode) bool {
    return switch (mask) {
        .fresh => requested_mode == .fresh,
        .replay => requested_mode == .replay,
        .verify => requested_mode == .verify,
        .audit => requested_mode == .audit,
        .fresh_and_replay => requested_mode == .fresh or requested_mode == .replay,
        .all => true,
    };
}

fn supervisionModeAcceptanceBlocker(requested_mode: Mode) AcceptanceBlocker {
    return switch (requested_mode) {
        .fresh, .audit => .FreshCallDenied,
        .replay => .ReplayCallDenied,
        .verify => .VerifyCallDenied,
    };
}

fn rejectedReport(base: AcceptanceReport, blockers: []const AcceptanceBlocker) AcceptanceReport {
    var report = base;
    report.accepted = false;
    report.blockers = blockers;
    report.summary = "rejected";
    report.report_fingerprint = fingerprintAcceptanceReport(report);
    return report;
}

fn rejectedAcceptance(target_ref: TargetRef, mode: Mode, blockers: []const AcceptanceBlocker) AcceptanceReport {
    var report = AcceptanceReport{
        .report_fingerprint = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .requested_mode = mode,
        .accepted = false,
        .blockers = blockers,
        .summary = "rejected",
    };
    report.report_fingerprint = fingerprintAcceptanceReport(report);
    return report;
}

fn acceptanceError(report: AcceptanceReport) Error {
    if (report.blockers.len == 0) return Error.InvalidMode;
    return switch (report.blockers[0]) {
        .MissingBinding => Error.MissingBinding,
        .ExtraBinding => Error.ExtraBinding,
        .WrongWorldSurface => Error.WrongWorldSurface,
        .WrongTargetCertificate => Error.WrongTargetCertificate,
        .WrongPortId => Error.WrongPortId,
        .AdapterModeNotAllowed => Error.AdapterModeNotAllowed,
        .PortableValuesRequired => Error.PortableValuesRequired,
        .NativeOnlyValueRejected => Error.NativeOnlyValueRejected,
        .ReplaySourceMissing => Error.ReplaySourceMissing,
        .VerifyTranscriptMissing => Error.VerifyTranscriptMissing,
        .TranscriptImageRequired => Error.TranscriptImageRequired,
        .TranscriptImageSurfaceMismatch => Error.TranscriptImageSurfaceMismatch,
        .HandoffTargetMismatch => Error.HandoffTargetMismatch,
        .HandoffCheckpointMismatch => Error.HandoffCheckpointMismatch,
        .HandoffPendingFrameMismatch => Error.HandoffPendingFrameMismatch,
        .SupervisionPolicyMismatch => Error.SupervisionDenied,
        .SupervisionBudgetExceeded => Error.BudgetExceeded,
        .SupervisionPortRuleDenied => Error.PortRuleDenied,
        .FreshCallDenied => Error.FreshCallDenied,
        .ReplayCallDenied => Error.ReplayCallDenied,
        .VerifyCallDenied => Error.SupervisionDenied,
        .SurfaceProfileIncompatible => Error.SurfaceProfileIncompatible,
        .PayloadValueMismatch => Error.FrameValueTableMismatch,
        .ResponseValueMismatch => Error.FrameValueTableMismatch,
    };
}

fn supervisionPreflightBlocker(err: anyerror) AcceptanceBlocker {
    return switch (err) {
        Error.BudgetExceeded => .SupervisionBudgetExceeded,
        Error.PortRuleDenied => .SupervisionPortRuleDenied,
        Error.FreshCallDenied => .FreshCallDenied,
        Error.ReplayCallDenied => .ReplayCallDenied,
        Error.TranscriptImageRequired => .TranscriptImageRequired,
        Error.HandoffPendingFrameMismatch => .HandoffPendingFrameMismatch,
        Error.ReplayMissing,
        Error.ReplayPortMismatch,
        Error.ReplayRequestFingerprintMismatch,
        Error.ReplayResponseKindMismatch,
        Error.ReplayTargetCertificateMismatch,
        Error.ReplayUnusedEvent,
        Error.ReplaySurfaceMismatch,
        Error.ReplaySourceMissing,
        => .ReplaySourceMissing,
        else => .SupervisionPolicyMismatch,
    };
}

fn bindingRecordFor(comptime Target: type, comptime BindingDecl: type) Binding {
    if (@hasDecl(BindingDecl, "bindingRecord")) return BindingDecl.bindingRecord();
    const target_ref = TargetRef.fromTarget(Target);
    const requirement = ImportRequirement.fromTargetPort(Target, BindingDecl.world_port_id);
    const authority = PortAuthority.native_function;
    const descriptor = AdapterDescriptor.init(.{
        .adapter_kind = .native,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .world_port_id = BindingDecl.world_port_id,
        .authority_fingerprint = authority.authority_fingerprint,
        .label = BindingDecl.suggested_name,
    });
    return Binding.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .world_port_id = BindingDecl.world_port_id,
        .import_requirement_fingerprint = requirement.requirement_fingerprint,
        .world_port_ref_fingerprint = requirement.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = requirement.source_effect_shape_ref_fingerprint,
        .payload_value_table_id = requirement.payload_value_table_id,
        .response_value_table_id = requirement.response_value_table_id,
        .adapter_kind = .native,
        .authority_fingerprint = authority.authority_fingerprint,
        .adapter_descriptor_fingerprint = descriptor.descriptor_fingerprint,
        .label = BindingDecl.suggested_name,
    });
}

fn validateConfig(comptime Target: type, comptime Config: anytype) void {
    if (!@hasField(@TypeOf(Config), "ports") and !@hasField(@TypeOf(Config), "environment")) {
        @compileError("world.Machine config requires .ports or .environment");
    }
    const ports = comptime machineConfigPorts(Config);
    inline for (ports, 0..) |Decl, index| {
        if (Decl.TargetType != Target) @compileError("World port handler bound to wrong Target");
        if (Decl.world_port_id >= Target.WorldPortTable.entries.len) @compileError("World port handler id out of range");
        validatePortDescriptorMetadata(Target, Decl);
        inline for (ports, 0..) |Other, other_index| {
            if (other_index > index and Decl.world_port_id == Other.world_port_id) {
                @compileError("World port handler id duplicated");
            }
        }
    }
    if (comptime @hasField(@TypeOf(Config), "strict_handler_coverage") and Config.strict_handler_coverage) {
        assertAllPortsHandledFor(Target, Config);
    }
}

fn validatePortDescriptorMetadata(comptime Target: type, comptime Decl: type) void {
    const entry = Target.WorldPortTable.entries[Decl.world_port_id];
    if (Decl.residual_site_index != entry.residual_site_index or
        Decl.residual_site_fingerprint != entry.residual_site_fingerprint or
        !boundaryValueRefMatches(Decl.payload_ref, entry.payload_ref) or
        !boundaryValueRefMatches(Decl.response_ref, entry.resume_ref) or
        !boundaryValueRefMatches(Decl.result_ref, entry.result_ref) or
        !Decl.source_ref.eql(entry.source_ref) or
        !Decl.world_port_ref.eql(entry.world_port_ref))
    {
        @compileError("World port descriptor metadata does not match target WorldPortTable");
    }
}

fn boundaryValueRefMatches(comptime descriptor_ref: anytype, comptime target_ref: anytype) bool {
    return std.mem.eql(u8, @tagName(descriptor_ref.codec), target_ref.codec) and
        descriptor_ref.schema_index == target_ref.schema_index;
}

fn assertAllPortsHandledFor(comptime Target: type, comptime Config: anytype) void {
    const ports = comptime machineConfigPorts(Config);
    inline for (Target.WorldPortTable.entries) |entry| {
        comptime var found = false;
        inline for (ports) |Decl| {
            if (Decl.world_port_id == entry.world_port_id) found = true;
        }
        if (!found) @compileError("World port missing handler");
    }
}

fn handlerForWorldPortId(comptime Target: type, comptime Config: anytype, comptime world_port_id: u32) ?type {
    _ = Target;
    const ports = comptime machineConfigPorts(Config);
    inline for (ports) |Decl| {
        if (Decl.world_port_id == world_port_id) return Decl;
    }
    return null;
}

fn worldPortIdForSite(comptime Target: type, comptime Site: type) ?u32 {
    for (Target.WorldPortTable.entries) |entry| {
        if (entry.residual_site_index == Site.index and entry.residual_site_fingerprint == Site.fingerprint) {
            return entry.world_port_id;
        }
    }
    return null;
}

fn valueIdFor(comptime Target: type, comptime world_port_id: u32, comptime kind: anytype) ?u32 {
    inline for (Target.WorldValueTable.entries) |entry| {
        if (entry.world_port_id == world_port_id and entry.kind == kind) return entry.value_id;
    }
    return null;
}

fn valueIdForRuntime(comptime Target: type, world_port_id: u32, comptime kind: anytype) ?u32 {
    for (Target.WorldValueTable.entries) |entry| {
        if (entry.world_port_id == world_port_id and entry.kind == kind) return entry.value_id;
    }
    return null;
}

fn descriptorWorldPortId(comptime Target: type, comptime Descriptor: type) u32 {
    if (comptime @hasDecl(Descriptor, "world_port_id")) return Descriptor.world_port_id;
    return comptime worldPortIdForSite(Target, Descriptor) orelse
        @compileError("World port request type does not match target WorldPortTable");
}

fn callHandler(comptime Decl: type, ctx: anytype, request_value: PortRequest(Decl.TargetType, Decl.SiteType)) !Decl.Response {
    const Handler = @TypeOf(Decl.handler);
    const info = @typeInfo(Handler).@"fn";
    if (info.params.len != 2) @compileError("World port handler must take ctx plus payload or PortRequest");
    const Second = info.params[1].type orelse @compileError("World port handler second parameter must be typed");
    if (Second == @TypeOf(request_value)) {
        return Decl.handler(ctx, request_value);
    }
    return Decl.handler(ctx, request_value.payload_value);
}

fn noopResponseDeinit(_: anytype, _: anytype) void {}

fn cloneOwnedValue(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const Value = @TypeOf(value);
    return switch (@typeInfo(Value)) {
        .void,
        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .@"enum",
        .error_set,
        => value,
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                break :blk try allocator.dupe(u8, value);
            }
            if (comptime isStringList(Value)) {
                break :blk try cloneOwnedStringList(allocator, value);
            }
            @compileError("World transcript/result storage only supports owned cloning for byte slices and string lists");
        },
        .optional => |optional| if (value) |payload|
            try cloneOwnedValue(allocator, @as(optional.child, payload))
        else
            null,
        .@"struct" => |info| blk: {
            var result: Value = undefined;
            var initialized_fields: usize = 0;
            errdefer inline for (info.fields, 0..) |field, field_index| {
                if (field_index < initialized_fields) {
                    deinitOwnedValue(allocator, @field(result, field.name));
                }
            };
            inline for (info.fields) |field| {
                @field(result, field.name) = try cloneOwnedValue(allocator, @field(value, field.name));
                initialized_fields += 1;
            }
            break :blk result;
        },
        .@"union" => |union_info| blk: {
            const Tag = union_info.tag_type orelse
                @compileError("World transcript/result storage requires tagged unions");
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type == void) break :blk @unionInit(Value, field.name, {});
                    const cloned = try cloneOwnedValue(allocator, @field(value, field.name));
                    break :blk @unionInit(Value, field.name, cloned);
                }
            }
            unreachable;
        },
        else => @compileError("World transcript/result storage cannot own-clone " ++ @typeName(Value)),
    };
}

fn deinitOwnedValue(allocator: std.mem.Allocator, value: anytype) void {
    const Value = @TypeOf(value);
    switch (@typeInfo(Value)) {
        .void,
        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .@"enum",
        .error_set,
        => {},
        .pointer => |pointer| {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                allocator.free(@constCast(value));
                return;
            }
            if (comptime isStringList(Value)) {
                for (value) |item| allocator.free(@constCast(item));
                allocator.free(@constCast(value));
                return;
            }
        },
        .optional => if (value) |payload| deinitOwnedValue(allocator, payload),
        .@"struct" => |info| inline for (info.fields) |field| {
            deinitOwnedValue(allocator, @field(value, field.name));
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type != void) deinitOwnedValue(allocator, @field(value, field.name));
                    return;
                }
            }
        },
        else => {},
    }
}

fn isByteSlice(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice and pointer.child == u8,
        else => false,
    };
}

fn isStringList(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice and isByteSlice(pointer.child),
        else => false,
    };
}

fn cloneOwnedStringList(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const Value = @TypeOf(value);
    const Child = @typeInfo(Value).pointer.child;
    const result = try allocator.alloc(Child, value.len);
    errdefer allocator.free(result);
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |item| allocator.free(@constCast(item));
    for (value, 0..) |item, index| {
        result[index] = try allocator.dupe(u8, item);
        initialized += 1;
    }
    return result;
}

fn cloneRunValue(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    return cloneOwnedValue(allocator, value);
}

fn deinitRunValue(allocator: std.mem.Allocator, value: anytype) void {
    deinitOwnedValue(allocator, value);
}

fn validateRuntimeSurfaceOptions(comptime Target: type, options: anytype) !void {
    if (@hasField(@TypeOf(options), "expected_world_surface_fingerprint")) {
        if (options.expected_world_surface_fingerprint != Target.WorldSurface.surface_fingerprint) return Error.SurfaceMismatch;
    }
    if (@hasField(@TypeOf(options), "expected_target_certificate_fingerprint")) {
        if (options.expected_target_certificate_fingerprint != Target.Certificate.certificate_fingerprint) return Error.TargetCertificateMismatch;
    }
}

fn modeConsumesTranscript(mode: Mode) bool {
    return mode == .replay or mode == .verify;
}

fn eventKindIsSourceResponse(kind: EventKind) bool {
    return kind == .port_responded or kind == .frame_responded or kind == .port_replayed or kind == .frame_replayed;
}

fn eventKindAllowsResponseFrame(kind: EventKind) bool {
    return switch (kind) {
        .port_responded,
        .port_replayed,
        .port_rejected,
        .port_failed,
        .frame_responded,
        .frame_replayed,
        .frame_verified,
        .frame_rejected,
        .frame_failed,
        => true,
        else => false,
    };
}

fn eventKindRequiresAdmissionWitness(kind: EventKind) bool {
    return switch (kind) {
        .admission_requested,
        .admission_accepted,
        .admission_rejected,
        .module_matched_target,
        => true,
        else => false,
    };
}

fn validateAdmissionEventWitness(event: TranscriptImage.EventImage) !void {
    switch (event.kind) {
        .admission_requested => {
            if (event.admission_request_fingerprint == null) return error.InvalidFrameEncoding;
        },
        .admission_accepted => {
            if (event.admission_request_fingerprint == null) return error.InvalidFrameEncoding;
            if (event.admission_report_fingerprint == null) return error.InvalidFrameEncoding;
            if (event.admission_receipt_fingerprint == null) return error.InvalidFrameEncoding;
        },
        .admission_rejected => {
            if (event.admission_request_fingerprint == null) return error.InvalidFrameEncoding;
            if (event.admission_report_fingerprint == null) return error.InvalidFrameEncoding;
        },
        .module_matched_target => {
            if (event.target_match_fingerprint == null) return error.InvalidFrameEncoding;
        },
        else => {},
    }
}

fn validateResponseFrameImage(frame: Frame.Response) !void {
    if (frame.format_version != world_frame_response_format_version) return error.InvalidFrameEncoding;
    if (frame.fingerprint_version != world_frame_response_fingerprint_version) return error.InvalidFrameEncoding;
    if (fingerprintResponse(frame) != frame.frame_fingerprint) return error.InvalidFrameEncoding;
    const deferred_response_fingerprint = frame.responseFingerprintDeferred();
    if (deferred_response_fingerprint) {
        if (frame.status != .responded) return error.InvalidFrameEncoding;
        if (frame.response_fingerprint != 0) return error.InvalidFrameEncoding;
        if (frame.replay_key != 0) return error.InvalidFrameEncoding;
        if (frame.response_image == null) return error.MissingValueImage;
    }
    if (frame.response_image) |image| {
        try validateValueImage(image);
        if (frame.response_value_fingerprint != image.value_image_fingerprint) return error.InvalidFrameEncoding;
        if (image.value_table_id != frame.response_value_table_id) return error.InvalidFrameEncoding;
        if (deferred_response_fingerprint) {
            if (image.boundary_value_fingerprint != null) return error.InvalidFrameEncoding;
        } else if (image.boundary_value_fingerprint != frame.response_fingerprint) {
            return error.InvalidFrameEncoding;
        }
    } else if (frame.response_value_fingerprint != null) {
        return error.InvalidFrameEncoding;
    }
}

fn validateValueImage(image: Frame.ValueImage) !void {
    if (image.format_version != world_frame_value_image_format_version) return error.InvalidFrameEncoding;
    if (image.fingerprint_version != world_frame_value_image_fingerprint_version) return error.InvalidFrameEncoding;
    const expected = fingerprintValueImage(
        image.value_table_id,
        image.boundary_value_fingerprint,
        image.codec_schema_descriptor_fingerprint,
        image.dynamic_size,
        image.diagnostic_type_label,
        image.bytes,
    );
    if (expected != image.value_image_fingerprint) return error.InvalidFrameEncoding;
}

fn validateRequestFrameImage(frame: Frame.Request) !void {
    if (frame.format_version != world_frame_request_format_version) return error.InvalidFrameEncoding;
    if (frame.fingerprint_version != world_frame_request_fingerprint_version) return error.InvalidFrameEncoding;
    if (fingerprintRequest(frame) != frame.frame_fingerprint) return error.InvalidFrameEncoding;
    if (frame.payload_image) |image| {
        try validateValueImage(image);
        if (frame.payload_value_fingerprint != image.value_image_fingerprint) return error.InvalidFrameEncoding;
        if (image.value_table_id != frame.payload_value_table_id) return error.InvalidFrameEncoding;
        if (image.boundary_value_fingerprint != null) return error.InvalidFrameEncoding;
    } else if (frame.payload_value_fingerprint != null) {
        return error.InvalidFrameEncoding;
    }
}

fn cloneRequestFrame(allocator: std.mem.Allocator, frame: Frame.Request) !Frame.Request {
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);
    return Frame.Request.decode(allocator, encoded);
}

fn validateValueImagePolicy(image: Frame.ValueImage, policy: ValuePolicy) !void {
    if (policy.max_value_image_bytes) |max| {
        if (image.bytes.len > max) return error.UnsupportedValueImage;
    }
    if (!policy.allow_diagnostic_type_labels and image.diagnostic_type_label != null) return error.UnsupportedValueImage;
}

fn validateRequestFramePolicy(frame: Frame.Request, policy: ValuePolicy) !void {
    if (frame.payload_image) |image| try validateValueImagePolicy(image, policy);
}

fn validateTransferredRequestFramePolicy(frame: Frame.Request, policy: ValuePolicy) !void {
    try validateRequestFramePolicy(frame, policy);
    if (frame.payload_image == null and (policy.require_portable_values or !policy.allow_native_only_values)) return error.MissingValueImage;
}

fn validateResponseFramePolicy(frame: Frame.Response, policy: ValuePolicy) !void {
    if (frame.status != .responded) return;
    const image = frame.response_image orelse {
        if (policy.require_response_images_for_replay) return error.MissingValueImage;
        if (!policy.allow_native_only_values) return error.NativeOnlyValue;
        return;
    };
    try validateValueImagePolicy(image, policy);
}

fn validateTranscriptEventFrameBindings(event: TranscriptImage.EventImage) !void {
    if (event.request_frame) |frame| {
        try validateRequestFrameImage(frame);
        if (frame.world_surface_fingerprint != event.world_surface_fingerprint) return error.InvalidFrameEncoding;
        if (frame.target_certificate_fingerprint != event.target_certificate_fingerprint) return error.InvalidFrameEncoding;
        if (event.world_port_id) |world_port_id| {
            if (frame.world_port_id != world_port_id) return error.InvalidFrameEncoding;
        }
        if (event.request_fingerprint) |request_fingerprint| {
            if (frame.request_fingerprint != request_fingerprint) return error.InvalidFrameEncoding;
        }
        if (event.turn_index) |turn_index| {
            if (frame.turn_index != turn_index) return error.InvalidFrameEncoding;
        }
        if (event.residual_site_index) |residual_site_index| {
            if (frame.residual_site_index != residual_site_index) return error.InvalidFrameEncoding;
        }
        if (event.residual_site_fingerprint) |residual_site_fingerprint| {
            if (frame.residual_site_fingerprint != residual_site_fingerprint) return error.InvalidFrameEncoding;
        }
    }
    if (event.response_frame) |frame| {
        if (!eventKindAllowsResponseFrame(event.kind)) return error.InvalidFrameEncoding;
        try validateResponseFrameImage(frame);
        if (frame.responseFingerprintDeferred()) return error.InvalidFrameEncoding;
        if (frame.world_surface_fingerprint != event.world_surface_fingerprint) return error.InvalidFrameEncoding;
        if (frame.target_certificate_fingerprint != event.target_certificate_fingerprint) return error.InvalidFrameEncoding;
        if (event.world_port_id) |world_port_id| {
            if (frame.world_port_id != world_port_id) return error.InvalidFrameEncoding;
        }
        if (event.request_fingerprint) |request_fingerprint| {
            if (frame.request_fingerprint != request_fingerprint) return error.InvalidFrameEncoding;
        }
        if (event.response_fingerprint) |response_fingerprint| {
            if (frame.response_fingerprint != response_fingerprint) return error.InvalidFrameEncoding;
        }
        if (event.response_kind) |response_kind| {
            if (frame.response_kind != response_kind) return error.InvalidFrameEncoding;
        }
        if (event.replay_key) |replay_key| {
            if (frame.replay_key != replay_key) return error.InvalidFrameEncoding;
        }
        if (event.status) |status| {
            if (frame.status != status) return error.InvalidFrameEncoding;
        }
    }
}

fn superviseTranscriptAppendForEvent(allocator: std.mem.Allocator, transcript: *const Transcript, supervisor: *Supervision.Supervisor, event: Transcript.Event) !void {
    const event_count_after_append = supervisor.ledger.total_transcript_events + 1;
    var transcript_image_bytes: usize = 0;
    if (supervisor.permit.budget.max_transcript_image_bytes != null) {
        var projected = Transcript.init(allocator);
        defer projected.deinit();
        for (transcript.events.items) |existing| try projected.append(existing);
        try projected.append(event);
        var image = try projected.toImage(allocator, .{ .value_policy = ValuePolicy.portable });
        defer image.deinit(allocator);
        const encoded = try image.encode(allocator);
        defer allocator.free(encoded);
        transcript_image_bytes = encoded.len;
    }
    try supervisor.beforeTranscriptAppend(event_count_after_append, transcript_image_bytes);
}

fn appendRunEventSupervised(allocator: std.mem.Allocator, comptime Target: type, options: anytype, supervisor: ?*Supervision.Supervisor, kind: EventKind, status: ?ResponseStatus, source_run: bool) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    const transcript = @field(options, "transcript");
    const event = Transcript.Event{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .status = status,
        .source_run = source_run,
    };
    if (supervisor) |active| try superviseTranscriptAppendForEvent(allocator, transcript, active, event);
    try transcript.append(event);
}

fn appendPortEventSupervised(
    allocator: std.mem.Allocator,
    comptime Target: type,
    options: anytype,
    supervisor: ?*Supervision.Supervisor,
    kind: EventKind,
    world_port_id: u32,
    trace: anytype,
    response_fingerprint: ?u64,
    response_kind: ?ResponseKind,
    value: ?StoredValue,
    request_frame: ?Frame.Request,
    response_frame: ?Frame.Response,
) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    const transcript = @field(options, "transcript");
    const replay_key = if (response_fingerprint) |fingerprint| ReplayKey{
        .world_surface_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_fingerprint = fingerprint,
    } else null;
    var cloned_request_frame: ?Frame.Request = null;
    if (request_frame) |frame| {
        cloned_request_frame = try frame.clone(transcript.allocator);
    }
    errdefer if (cloned_request_frame) |*frame| frame.deinit(transcript.allocator);
    var cloned_response_frame: ?Frame.Response = null;
    if (response_frame) |frame| {
        cloned_response_frame = try frame.clone(transcript.allocator);
    }
    errdefer if (cloned_response_frame) |*frame| frame.deinit(transcript.allocator);
    var event = Transcript.Event{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .world_port_id = world_port_id,
        .request_fingerprint = trace.fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = response_kind,
        .replay_key = if (replay_key) |key| key.fingerprint() else null,
        .world_surface_replay_scope_fingerprint = Target.WorldSurface.replayScopeRef().fingerprint,
        .payload_value_table_id = valueIdForRuntime(Target, world_port_id, .payload),
        .expected_response_value_table_id = valueIdForRuntime(Target, world_port_id, .@"resume"),
        .turn_index = trace.turn_index,
        .residual_site_index = trace.operation_site_index,
        .residual_site_fingerprint = trace.operation_site_fingerprint,
        .status = switch (kind) {
            .port_responded,
            .port_replayed,
            .frame_responded,
            .frame_replayed,
            .frame_verified,
            => .responded,
            .port_rejected,
            .frame_rejected,
            => .rejected,
            .port_failed,
            .frame_failed,
            => .failed,
            else => null,
        },
        .value = value,
        .request_frame = cloned_request_frame,
        .response_frame = cloned_response_frame,
    };
    cloned_request_frame = null;
    cloned_response_frame = null;
    errdefer if (event.request_frame) |*frame| frame.deinit(transcript.allocator);
    errdefer if (event.response_frame) |*frame| frame.deinit(transcript.allocator);
    if (supervisor) |active| try superviseTranscriptAppendForEvent(allocator, transcript, active, event);
    try transcript.appendOwned(&event);
}

fn eventImageFromTranscriptEvent(allocator: std.mem.Allocator, event: Transcript.Event, policy: ValuePolicy) !TranscriptImage.EventImage {
    var request_frame: ?Frame.Request = if (event.request_frame) |frame|
        try frame.clone(allocator)
    else
        null;
    if (request_frame == null) {
        if (event.world_port_id) |world_port_id| {
            if (event.request_fingerprint) |request_fingerprint| {
                if (event.residual_site_index != null and event.residual_site_fingerprint != null and event.turn_index != null) {
                    request_frame = Frame.Request.init(.{
                        .world_surface_fingerprint = event.world_surface_fingerprint,
                        .world_surface_replay_scope_fingerprint = event.world_surface_replay_scope_fingerprint,
                        .target_certificate_fingerprint = event.target_certificate_fingerprint,
                        .world_port_id = world_port_id,
                        .residual_site_index = event.residual_site_index.?,
                        .residual_site_fingerprint = event.residual_site_fingerprint.?,
                        .request_fingerprint = request_fingerprint,
                        .turn_index = event.turn_index.?,
                        .payload_value_table_id = event.payload_value_table_id,
                        .expected_response_value_table_id = event.expected_response_value_table_id,
                    });
                }
            }
        }
    }
    errdefer if (request_frame) |*frame| frame.deinit(allocator);
    if (request_frame) |frame| try validateRequestFramePolicy(frame, policy);

    var response_frame: ?Frame.Response = if (event.response_frame) |frame|
        try frame.clone(allocator)
    else
        null;
    errdefer if (response_frame) |*frame| frame.deinit(allocator);
    const response_status = event.status orelse if (event.kind == .port_rejected or event.kind == .frame_rejected)
        ResponseStatus.rejected
    else if (event.kind == .port_failed or event.kind == .frame_failed)
        ResponseStatus.failed
    else
        null;
    if (response_frame) |frame| {
        try validateResponseFrameImage(frame);
        try validateResponseFramePolicy(frame, policy);
    }
    const source_response_event = switch (event.kind) {
        .port_responded,
        .frame_responded,
        .port_rejected,
        .frame_rejected,
        .port_failed,
        .frame_failed,
        => true,
        else => false,
    };
    if (response_frame == null and source_response_event and event.world_port_id != null and event.request_fingerprint != null and event.response_fingerprint != null and event.response_kind != null and event.replay_key != null) {
        const frame_status = response_status orelse .responded;
        var response_image: ?Frame.ValueImage = null;
        if (event.value) |stored| {
            response_image = stored.valueImage(
                allocator,
                event.expected_response_value_table_id,
                event.response_fingerprint,
                null,
                policy,
            ) catch |err| switch (err) {
                error.UnsupportedValueImage => if (policy.allow_native_only_values and policy.max_value_image_bytes == null) null else return err,
                else => return err,
            };
        }
        errdefer if (response_image) |*image| image.deinit(allocator);
        if (frame_status == .responded) {
            if (response_image == null and policy.require_response_images_for_replay) return error.MissingValueImage;
            if (response_image == null and policy.require_portable_values and !policy.allow_native_only_values) return error.NativeOnlyValue;
        }
        response_frame = Frame.Response.init(.{
            .world_surface_fingerprint = event.world_surface_fingerprint,
            .target_certificate_fingerprint = event.target_certificate_fingerprint,
            .world_port_id = event.world_port_id.?,
            .request_fingerprint = event.request_fingerprint.?,
            .response_kind = event.response_kind.?,
            .response_value_table_id = event.expected_response_value_table_id,
            .response_fingerprint = event.response_fingerprint.?,
            .response_image = response_image,
            .replay_key = event.replay_key.?,
            .status = frame_status,
        });
        response_image = null;
    }
    var image = TranscriptImage.EventImage{
        .event_fingerprint = 0,
        .kind = event.kind,
        .world_surface_fingerprint = event.world_surface_fingerprint,
        .target_certificate_fingerprint = event.target_certificate_fingerprint,
        .world_port_id = event.world_port_id,
        .request_fingerprint = event.request_fingerprint,
        .response_fingerprint = event.response_fingerprint,
        .response_kind = event.response_kind,
        .replay_key = event.replay_key,
        .admission_request_fingerprint = event.admission_request_fingerprint,
        .admission_report_fingerprint = event.admission_report_fingerprint,
        .admission_receipt_fingerprint = event.admission_receipt_fingerprint,
        .module_ref_fingerprint = event.module_ref_fingerprint,
        .target_match_fingerprint = event.target_match_fingerprint,
        .turn_index = event.turn_index,
        .residual_site_index = event.residual_site_index,
        .residual_site_fingerprint = event.residual_site_fingerprint,
        .status = response_status,
        .source_run = event.source_run,
        .request_frame = request_frame,
        .response_frame = response_frame,
    };
    try validateTranscriptEventFrameBindings(image);
    try validateAdmissionEventWitness(image);
    image.event_fingerprint = fingerprintTranscriptEventImage(image);
    return image;
}

fn finalStatusFromEvents(events: []const TranscriptImage.EventImage) TranscriptImage.FinalStatus {
    var status: TranscriptImage.FinalStatus = .running;
    for (events) |event| {
        switch (event.kind) {
            .run_started => status = .running,
            .run_completed => status = .completed,
            .run_failed => status = .failed,
            else => {},
        }
    }
    return status;
}

fn encodeTranscriptEventImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, event: TranscriptImage.EventImage, format_version: u32) !void {
    try writeU64(out, allocator, event.event_fingerprint);
    try writeU8(out, allocator, @intFromEnum(event.kind));
    try writeU64(out, allocator, event.world_surface_fingerprint);
    try writeU64(out, allocator, event.target_certificate_fingerprint);
    try writeOptionalU32(out, allocator, event.world_port_id);
    try writeOptionalU64(out, allocator, event.request_fingerprint);
    try writeOptionalU64(out, allocator, event.response_fingerprint);
    if (event.response_kind) |kind| {
        try writeBool(out, allocator, true);
        try writeU8(out, allocator, @intFromEnum(kind));
    } else {
        try writeBool(out, allocator, false);
    }
    try writeOptionalU64(out, allocator, event.replay_key);
    if (format_version >= 3) {
        try writeOptionalU64(out, allocator, event.admission_request_fingerprint);
        try writeOptionalU64(out, allocator, event.admission_report_fingerprint);
        try writeOptionalU64(out, allocator, event.admission_receipt_fingerprint);
        try writeOptionalU64(out, allocator, event.module_ref_fingerprint);
        try writeOptionalU64(out, allocator, event.target_match_fingerprint);
    }
    try writeOptionalU64(out, allocator, event.turn_index);
    try writeOptionalU64(out, allocator, event.residual_site_index);
    try writeOptionalU64(out, allocator, event.residual_site_fingerprint);
    if (event.status) |status| {
        try writeBool(out, allocator, true);
        try writeU8(out, allocator, @intFromEnum(status));
    } else {
        try writeBool(out, allocator, false);
    }
    try writeBool(out, allocator, event.source_run);
    if (event.request_frame) |frame| {
        try writeBool(out, allocator, true);
        const encoded = try frame.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
    if (event.response_frame) |frame| {
        try writeBool(out, allocator, true);
        const encoded = try frame.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn decodeTranscriptEventImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, format_version: u32) !TranscriptImage.EventImage {
    var event = TranscriptImage.EventImage{
        .event_fingerprint = try readU64(bytes, cursor),
        .kind = try enumFromByte(EventKind, try readU8(bytes, cursor)),
        .world_surface_fingerprint = try readU64(bytes, cursor),
        .target_certificate_fingerprint = try readU64(bytes, cursor),
        .world_port_id = try readOptionalU32(bytes, cursor),
        .request_fingerprint = try readOptionalU64(bytes, cursor),
        .response_fingerprint = try readOptionalU64(bytes, cursor),
        .response_kind = if (try readBool(bytes, cursor)) try enumFromByte(ResponseKind, try readU8(bytes, cursor)) else null,
        .replay_key = try readOptionalU64(bytes, cursor),
        .admission_request_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, cursor) else null,
        .admission_report_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, cursor) else null,
        .admission_receipt_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, cursor) else null,
        .module_ref_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, cursor) else null,
        .target_match_fingerprint = if (format_version >= 3) try readOptionalU64(bytes, cursor) else null,
        .turn_index = try readOptionalUsize(bytes, cursor),
        .residual_site_index = try readOptionalUsize(bytes, cursor),
        .residual_site_fingerprint = try readOptionalU64(bytes, cursor),
        .status = if (try readBool(bytes, cursor)) try enumFromByte(ResponseStatus, try readU8(bytes, cursor)) else null,
        .source_run = try readBool(bytes, cursor),
        .request_frame = null,
        .response_frame = null,
    };
    errdefer event.deinit(allocator);
    if (format_version < 3 and eventKindRequiresAdmissionWitness(event.kind)) return error.InvalidFrameEncoding;
    if (format_version >= 3) try validateAdmissionEventWitness(event);
    if (try readBool(bytes, cursor)) {
        const encoded = try readBytesOwned(allocator, bytes, cursor);
        defer allocator.free(encoded);
        event.request_frame = try Frame.Request.decode(allocator, encoded);
    }
    if (try readBool(bytes, cursor)) {
        const encoded = try readBytesOwned(allocator, bytes, cursor);
        defer allocator.free(encoded);
        event.response_frame = try Frame.Response.decode(allocator, encoded);
    }
    try validateTranscriptEventFrameBindings(event);
    if (fingerprintTranscriptEventImageForFormat(format_version, event) != event.event_fingerprint) return error.InvalidFrameEncoding;
    return event;
}

fn admissionModeToRunMode(mode: Admission.AdmissionMode) Mode {
    return switch (mode) {
        .inspect_only, .local_target_match_only => .audit,
        .replay_only, .completed_replay => .replay,
        .verify_only => .verify,
        .resume_parked, .continue_fresh, .branch_resume => .fresh,
    };
}

fn admissionModeNeedsRunImage(mode: Admission.AdmissionMode) bool {
    return switch (mode) {
        .inspect_only, .local_target_match_only, .continue_fresh, .replay_only, .verify_only => false,
        .resume_parked, .branch_resume, .completed_replay => true,
    };
}

fn effectiveAdmissionModeMatchesPackage(requested: Admission.AdmissionMode, effective: Admission.AdmissionMode) bool {
    if (requested == effective) return true;
    return requested == .replay_only and effective == .verify_only;
}

fn validateTargetRegistryEntry(entry: Admission.TargetRegistry.Entry) !void {
    if (entry.target_ref.target_ref_fingerprint != fingerprintTargetRef(entry.target_ref)) return error.TargetRegistryConflict;
    if (entry.world_surface_fingerprint != entry.target_ref.world_surface_fingerprint) return error.TargetRegistryConflict;
    if (entry.target_certificate_fingerprint != entry.target_ref.target_certificate_fingerprint) return error.TargetRegistryConflict;
    if (entry.program_plan_hash != entry.target_ref.residual_program_plan_hash) return error.TargetRegistryConflict;
    if (entry.world_port_table_fingerprint != entry.target_ref.world_port_table_fingerprint) return error.TargetRegistryConflict;
    if (entry.world_value_table_fingerprint != entry.target_ref.world_value_table_fingerprint) return error.TargetRegistryConflict;
    if (entry.world_dispatch_table_fingerprint != entry.target_ref.world_dispatch_table_fingerprint) return error.TargetRegistryConflict;
    if (entry.normal_form_kind != entry.target_ref.normal_form_kind) return error.TargetRegistryConflict;
}

fn runImageHasModuleWitness(image: RunImage) bool {
    return image.module_ref_fingerprint != null or
        image.boundary_module_fingerprint != null or
        image.module_image_fingerprint != null;
}

fn transferPackageKindMatchesRunImage(kind: Admission.PackageKind, image_kind: RunImage.Kind, requested_mode: Admission.AdmissionMode) bool {
    return switch (kind) {
        .run_reference => image_kind == .reference_target_run or image_kind == .full_target_run,
        .parked_run => image_kind == .parked_run,
        .completed_run => image_kind == .completed_run or image_kind == .branched_run,
        .replay_run => image_kind == .replay_only_run or image_kind == .branched_run,
        .branch_run => image_kind == .parked_run,
        .target_reference_only => image_kind == .reference_target_run,
        .inspect_only => requested_mode == .inspect_only,
        .module_reference, .full_module => false,
    };
}

fn refreshRunImageFingerprint(image: *RunImage) void {
    image.run_image_fingerprint = if (image.format_version == 1)
        fingerprintRunImageV1(image.*)
    else if (image.format_version >= 3)
        fingerprintRunImageV3(image.*)
    else
        fingerprintRunImage(image.*);
}

fn attachPackageModuleWitnessToRunImage(image: *RunImage, package: Admission.TransferPackage, module_ref: ?Admission.ModuleRef) void {
    if (image.module_ref_fingerprint != null) return;
    const module = module_ref orelse return;
    image.format_version = world_run_image_format_version;
    image.module_ref_fingerprint = module.module_ref_fingerprint;
    image.boundary_module_fingerprint = module.boundary_module_fingerprint;
    if (image.module_image_fingerprint == null) {
        image.module_image_fingerprint = if (package.module_image_bytes) |bytes| moduleImageFingerprint(bytes) else null;
    }
    refreshRunImageFingerprint(image);
}

fn admissionModeToHandoffMode(mode: Admission.AdmissionMode) ?HandoffMode {
    return switch (mode) {
        .resume_parked, .branch_resume => .accept_fresh,
        .replay_only, .completed_replay => .accept_replay,
        .verify_only => .accept_verify,
        else => null,
    };
}

fn boundaryModuleKindFromName(name: []const u8) Admission.BoundaryModuleKind {
    if (std.mem.eql(u8, name, "reference_only")) return .reference_only;
    if (std.mem.eql(u8, name, "full_module")) return .full_module;
    return .partial_module;
}

fn normalFormKindFromName(name: []const u8) NormalFormKind {
    if (std.mem.eql(u8, name, "strict_closed")) return .strict_closed;
    if (std.mem.eql(u8, name, "world_ports_only")) return .world_ports_only;
    if (std.mem.eql(u8, name, "boundary_normal_form")) return .boundary_normal_form;
    return .unknown;
}

fn targetRefFromModuleManifest(manifest: anytype) TargetRef {
    var target_ref = TargetRef{
        .target_ref_fingerprint = 0,
        .target_label = manifest.target_label,
        .world_surface_fingerprint = manifest.world_surface_fingerprint,
        .target_certificate_fingerprint = manifest.target_certificate_fingerprint,
        .residual_program_plan_hash = manifest.program_plan_hash,
        .normal_form_kind = normalFormKindFromName(@tagName(manifest.normal_form)),
        .boundary_module_fingerprint = manifest.module_fingerprint,
    };
    target_ref.target_ref_fingerprint = fingerprintTargetRef(target_ref);
    return target_ref;
}

fn moduleImageFingerprint(bytes: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.module_image.bytes.fingerprint");
    hashU64(&hasher, bytes.len);
    hashBytes(&hasher, bytes);
    return hasher.final();
}

fn manifestForTransferPackage(package: Admission.TransferPackage) Admission.PackageManifest {
    return Admission.PackageManifest.init(.{
        .package_fingerprint = package.package_fingerprint,
        .package_kind = package.kind,
        .target_ref_fingerprint = if (package.target_ref) |target_ref| target_ref.target_ref_fingerprint else if (package.run_image) |run_image| run_image.target_ref.target_ref_fingerprint else null,
        .module_ref_fingerprint = if (package.module_ref) |module_ref| module_ref.module_ref_fingerprint else null,
        .module_image_fingerprint = if (package.module_image_bytes) |bytes| moduleImageFingerprint(bytes) else null,
        .run_image_fingerprint = if (package.run_image) |run_image| run_image.run_image_fingerprint else null,
        .transcript_image_fingerprint = if (package.transcript_image) |transcript| transcript.transcript_image_fingerprint else if (package.run_image) |run_image| if (run_image.transcript_image) |transcript| transcript.transcript_image_fingerprint else null else null,
        .checkpoint_count = package.checkpoint_refs.len + if (package.run_image) |run_image| run_image.checkpoints.len else 0,
        .branch_count = package.branch_refs.len + if (package.run_image) |run_image| run_image.branches.len else 0,
        .prior_receipt_count = package.prior_run_receipt_refs.len + package.prior_run_permit_refs.len,
        .requested_mode = package.requested_mode,
        .summary_metadata = package.metadata,
    });
}

fn packageManifestEquals(actual: Admission.PackageManifest, expected: Admission.PackageManifest) bool {
    return actual.format_version == expected.format_version and
        actual.fingerprint_version == expected.fingerprint_version and
        actual.manifest_fingerprint == expected.manifest_fingerprint and
        actual.package_fingerprint == expected.package_fingerprint and
        actual.package_kind == expected.package_kind and
        actual.target_ref_fingerprint == expected.target_ref_fingerprint and
        actual.module_ref_fingerprint == expected.module_ref_fingerprint and
        actual.module_image_fingerprint == expected.module_image_fingerprint and
        actual.run_image_fingerprint == expected.run_image_fingerprint and
        actual.transcript_image_fingerprint == expected.transcript_image_fingerprint and
        actual.checkpoint_count == expected.checkpoint_count and
        actual.branch_count == expected.branch_count and
        actual.prior_receipt_count == expected.prior_receipt_count and
        actual.requested_mode == expected.requested_mode and
        std.mem.eql(u8, actual.summary_metadata, expected.summary_metadata);
}

fn cloneRunImage(allocator: std.mem.Allocator, image: RunImage) !RunImage {
    const encoded = try image.encode(allocator);
    defer allocator.free(encoded);
    return try RunImage.decode(allocator, encoded);
}

fn cloneTranscriptImage(allocator: std.mem.Allocator, image: TranscriptImage) !TranscriptImage {
    const encoded = try image.encode(allocator);
    defer allocator.free(encoded);
    return try TranscriptImage.decode(allocator, encoded);
}

fn attachTranscriptToInstalledRunImage(allocator: std.mem.Allocator, image: *RunImage, transcript_image: TranscriptImage) !void {
    if (image.current_state.transcript_image_fingerprint) |fingerprint| {
        if (fingerprint != transcript_image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
    }
    if (image.transcript_image) |embedded| {
        if (embedded.transcript_image_fingerprint != transcript_image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
        image.current_state = runStateWithTranscriptEvidence(image.current_state, transcript_image);
        refreshRunImageFingerprint(image);
        return;
    }
    var cloned_transcript = try cloneTranscriptImage(allocator, transcript_image);
    errdefer cloned_transcript.deinit(allocator);
    image.transcript_image = cloned_transcript;
    image.owns_transcript_image = true;
    image.current_state = runStateWithTranscriptEvidence(image.current_state, transcript_image);
    refreshRunImageFingerprint(image);
}

fn attachBorrowedTranscriptToRunImage(image: *RunImage, transcript_image: TranscriptImage) !void {
    if (image.current_state.transcript_image_fingerprint) |fingerprint| {
        if (fingerprint != transcript_image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
    }
    if (image.transcript_image) |embedded| {
        if (embedded.transcript_image_fingerprint != transcript_image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
    } else {
        image.transcript_image = transcript_image;
        image.owns_transcript_image = false;
    }
    image.current_state = runStateWithTranscriptEvidence(image.current_state, transcript_image);
    refreshRunImageFingerprint(image);
}

fn mismatchSlice(mismatch: ?Admission.MatchMismatch) []const Admission.MatchMismatch {
    return switch (mismatch orelse return &.{}) {
        .WorldSurface => &.{.WorldSurface},
        .TargetCertificate => &.{.TargetCertificate},
        .ProgramPlanHash => &.{.ProgramPlanHash},
        .BoundaryModule => &.{.BoundaryModule},
        .WorldPortTable => &.{.WorldPortTable},
        .WorldValueTable => &.{.WorldValueTable},
        .WorldDispatchTable => &.{.WorldDispatchTable},
        .NormalForm => &.{.NormalForm},
        .ImportSet => &.{.ImportSet},
        .ExportSet => &.{.ExportSet},
    };
}

fn providedFingerprintMatches(provided: ?u64, expected: ?u64) bool {
    const actual = provided orelse return true;
    return expected != null and expected.? == actual;
}

fn runImageIsInterruptedSupervisionExport(image: RunImage) bool {
    return image.kind == .full_target_run and
        image.checkpoints.len == 0 and
        image.branches.len == 0 and
        image.current_state.status == .parked_on_supervision and
        image.current_state.branch_id == 0 and
        image.current_state.checkpoint_fingerprint == null and
        image.current_state.pending_request_fingerprint == null and
        interruptedRunStateMatchesTranscriptEvidence(image) and
        image.pending_request_frame == null;
}

fn interruptedRunStateMatchesTranscriptEvidence(image: RunImage) bool {
    const transcript_image = image.transcript_image orelse {
        return image.current_state.turn_index == 0 and
            image.current_state.final_response_fingerprint == null and
            image.current_state.final_value_image_fingerprint == null;
    };
    const evidence = runStateEvidenceFromTranscriptImage(transcript_image);
    return image.current_state.turn_index == evidence.turn_index and
        image.current_state.final_response_fingerprint == evidence.final_response_fingerprint and
        image.current_state.final_value_image_fingerprint == evidence.final_value_image_fingerprint;
}

fn runImageFitsAdmissionMode(image: RunImage, mode: Admission.AdmissionMode) bool {
    return switch (mode) {
        .inspect_only, .local_target_match_only, .continue_fresh => false,
        .resume_parked => (image.kind == .parked_run and image.current_state.status == .parked_on_port) or
            runImageIsInterruptedSupervisionExport(image),
        .branch_resume => image.kind == .parked_run and image.current_state.status == .parked_on_port and image.branches.len != 0,
        .completed_replay => (image.kind == .completed_run or image.kind == .branched_run) and image.current_state.status == .completed,
        .replay_only, .verify_only => switch (image.kind) {
            .completed_run => image.current_state.status == .completed,
            .replay_only_run => image.current_state.status == .completed or image.current_state.status == .failed,
            .branched_run => image.current_state.status == .completed,
            else => false,
        },
    };
}

fn addSatEncodedSize(a: usize, b: usize) usize {
    return std.math.add(usize, a, b) catch std.math.maxInt(usize);
}

fn transcriptImageEncodedByteSize(image: TranscriptImage) usize {
    var size: usize = 4 + 4 + 8 + 8 + 8 + 1 + 8 + 8;
    for (image.events) |event| size = addSatEncodedSize(size, transcriptEventImageEncodedByteSizeForFormat(image.format_version, event));
    return size;
}

fn transferPackageEncodedByteSize(package: Admission.TransferPackage) usize {
    var size: usize = 4 + 4 + 8;
    size = addSatEncodedSize(size, packageManifestEncodedByteSize(package.manifest));
    size = addSatEncodedSize(size, 1 + 1);
    size = addSatEncodedSize(size, optionalTargetRefEncodedByteSize(package.target_ref));
    size = addSatEncodedSize(size, optionalModuleRefEncodedByteSize(package.module_ref));
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(package.module_image_bytes));
    size = addSatEncodedSize(size, optionalRunImageEncodedByteSize(package.run_image));
    size = addSatEncodedSize(size, optionalTranscriptImageEncodedByteSize(package.transcript_image));
    size = addSatEncodedSize(size, u64SliceEncodedByteSize(package.checkpoint_refs));
    size = addSatEncodedSize(size, u64SliceEncodedByteSize(package.branch_refs));
    size = addSatEncodedSize(size, u64SliceEncodedByteSize(package.prior_run_permit_refs));
    size = addSatEncodedSize(size, u64SliceEncodedByteSize(package.prior_run_receipt_refs));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(package.requested_supervision_hint_fingerprint));
    size = addSatEncodedSize(size, bytesEncodedByteSize(package.metadata));
    return size;
}

fn packageManifestEncodedByteSize(manifest: Admission.PackageManifest) usize {
    var size: usize = 4 + 4 + 8 + 8 + 1;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(manifest.target_ref_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(manifest.module_ref_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(manifest.module_image_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(manifest.run_image_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(manifest.transcript_image_fingerprint));
    size = addSatEncodedSize(size, 8 + 8 + 8 + 1);
    size = addSatEncodedSize(size, bytesEncodedByteSize(manifest.summary_metadata));
    return size;
}

fn optionalTargetRefEncodedByteSize(target_ref: ?TargetRef) usize {
    return 1 + if (target_ref) |present| targetRefEncodedByteSize(present) else 0;
}

fn targetRefEncodedByteSize(target_ref: TargetRef) usize {
    var size: usize = 4 + 4 + 8;
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(target_ref.target_label));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.world_surface_replay_scope_fingerprint));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.residual_program_plan_hash));
    size = addSatEncodedSize(size, 1);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.world_port_table_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.world_value_table_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.world_dispatch_table_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.surface_profile_fingerprint));
    if (targetRefEncodesBoundaryModule(target_ref)) size = addSatEncodedSize(size, optionalU64EncodedByteSize(target_ref.boundary_module_fingerprint));
    size = addSatEncodedSize(size, bytesEncodedByteSize(target_ref.metadata));
    return size;
}

fn optionalModuleRefEncodedByteSize(module_ref: ?Admission.ModuleRef) usize {
    return 1 + if (module_ref) |present| moduleRefEncodedByteSize(present) else 0;
}

fn moduleRefEncodedByteSize(module_ref: Admission.ModuleRef) usize {
    var size: usize = 4 + 4 + 8 + 8 + 1 + 8 + 8 + 8;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.residual_program_plan_hash));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.import_surface_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.export_surface_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.module_graph_fingerprint));
    size = addSatEncodedSize(size, 1 + 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.world_port_table_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.world_value_table_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(module_ref.world_dispatch_table_fingerprint));
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(module_ref.label));
    size = addSatEncodedSize(size, bytesEncodedByteSize(module_ref.metadata));
    return size;
}

fn optionalRunImageEncodedByteSize(image: ?RunImage) usize {
    return 1 + if (image) |present| bytesFieldEncodedByteSize(runImageEncodedByteSize(present)) else 0;
}

fn runImageEncodedByteSize(image: RunImage) usize {
    var size: usize = 4 + 4 + 8 + 1;
    size = addSatEncodedSize(size, targetRefEncodedByteSize(image.target_ref));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, runStateEncodedByteSize(image.current_state));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(if (image.transcript_image) |transcript| transcript.transcript_image_fingerprint else null));
    size = addSatEncodedSize(size, optionalTranscriptImagePayloadEncodedByteSize(image.transcript_image));
    size = addSatEncodedSize(size, 8);
    for (image.checkpoints) |checkpoint| size = addSatEncodedSize(size, checkpointEncodedByteSize(checkpoint));
    size = addSatEncodedSize(size, 8);
    for (image.branches) |branch| size = addSatEncodedSize(size, branchEncodedByteSize(branch));
    size = addSatEncodedSize(size, optionalRequestFramePayloadEncodedByteSize(image.pending_request_frame));
    size = addSatEncodedSize(size, optionalValueImageEncodedByteSize(image.final_result_image));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.environment_certificate_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.acceptance_report_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.audit_image_fingerprint));
    if (image.format_version >= 2) {
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.prior_run_permit_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.prior_run_receipt_fingerprint));
    }
    if (image.format_version >= 3) {
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.module_ref_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.boundary_module_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.module_image_fingerprint));
    }
    size = addSatEncodedSize(size, bytesEncodedByteSize(image.metadata));
    return size;
}

fn optionalTranscriptImageEncodedByteSize(image: ?TranscriptImage) usize {
    return 1 + if (image) |present| bytesFieldEncodedByteSize(transcriptImageEncodedByteSize(present)) else 0;
}

fn optionalTranscriptImagePayloadEncodedByteSize(image: ?TranscriptImage) usize {
    return 1 + if (image) |present| bytesFieldEncodedByteSize(transcriptImageEncodedByteSize(present)) else 0;
}

fn u64SliceEncodedByteSize(values: []const u64) usize {
    var size: usize = 8;
    for (values) |_| size = addSatEncodedSize(size, 8);
    return size;
}

fn runStateEncodedByteSize(state: RunState) usize {
    var size: usize = 8 + 8;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(state.transcript_image_fingerprint));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(state.checkpoint_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(state.pending_request_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(state.final_response_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(state.final_value_image_fingerprint));
    size = addSatEncodedSize(size, 8 + 1);
    return size;
}

fn checkpointEncodedByteSize(checkpoint: Timeline.Checkpoint) usize {
    var size: usize = 4 + 4 + 8 + 8 + 8 + 8 + 8;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(checkpoint.current_request_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(checkpoint.last_response_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(checkpoint.capsule_image_fingerprint));
    size = addSatEncodedSize(size, 8 + 8 + 1);
    return size;
}

fn branchEncodedByteSize(branch: Timeline.Branch) usize {
    var size: usize = 4 + 4 + 8;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(branch.parent_branch_id));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, bytesEncodedByteSize(branch.branch_label));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(branch.final_event_index));
    size = addSatEncodedSize(size, 1 + 8 + 8 + 8);
    return size;
}

fn optionalRequestFramePayloadEncodedByteSize(frame: ?Frame.Request) usize {
    return 1 + if (frame) |present| bytesFieldEncodedByteSize(requestFrameEncodedByteSize(present)) else 0;
}

fn validateTranscriptImageFingerprint(image: TranscriptImage) !void {
    if (image.format_version != 2 and image.format_version != world_transcript_image_format_version) return error.InvalidFrameEncoding;
    if (image.fingerprint_version != world_transcript_image_fingerprint_version) return error.InvalidFrameEncoding;
    if (image.final_status != finalStatusFromEvents(image.events)) return error.InvalidFrameEncoding;
    var response_count: usize = 0;
    for (image.events) |event| {
        if (image.format_version < 3 and eventKindRequiresAdmissionWitness(event.kind)) return error.InvalidFrameEncoding;
        if (image.format_version >= 3) try validateAdmissionEventWitness(event);
        if (event.world_surface_fingerprint != image.world_surface_fingerprint) return error.InvalidFrameEncoding;
        if (event.target_certificate_fingerprint != image.target_certificate_fingerprint) return error.InvalidFrameEncoding;
        try validateTranscriptEventFrameBindings(event);
        if (fingerprintTranscriptEventImageForFormat(image.format_version, event) != event.event_fingerprint) return error.InvalidFrameEncoding;
        if (event.response_frame != null) response_count += 1;
    }
    if (image.response_count != response_count) return error.InvalidFrameEncoding;
    if (fingerprintTranscriptImage(image) != image.transcript_image_fingerprint) return error.InvalidFrameEncoding;
}

fn transcriptEventImageEncodedByteSizeForFormat(format_version: u32, event: TranscriptImage.EventImage) usize {
    var size: usize = 8 + 1 + 8 + 8;
    size = addSatEncodedSize(size, optionalU32EncodedByteSize(event.world_port_id));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.request_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.response_fingerprint));
    size = addSatEncodedSize(size, optionalEnumByteEncodedByteSize(event.response_kind));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.replay_key));
    if (format_version >= 3) {
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.admission_request_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.admission_report_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.admission_receipt_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.module_ref_fingerprint));
        size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.target_match_fingerprint));
    }
    size = addSatEncodedSize(size, optionalUsizeEncodedByteSize(event.turn_index));
    size = addSatEncodedSize(size, optionalUsizeEncodedByteSize(event.residual_site_index));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(event.residual_site_fingerprint));
    size = addSatEncodedSize(size, optionalEnumByteEncodedByteSize(event.status));
    size = addSatEncodedSize(size, 1);
    size = addSatEncodedSize(size, optionalRequestFrameEncodedByteSize(event.request_frame));
    size = addSatEncodedSize(size, optionalResponseFrameEncodedByteSize(event.response_frame));
    return size;
}

fn transcriptEventImageEncodedByteSize(event: TranscriptImage.EventImage) usize {
    return transcriptEventImageEncodedByteSizeForFormat(world_transcript_image_format_version, event);
}

fn optionalU32EncodedByteSize(value: ?u32) usize {
    return 1 + if (value == null) @as(usize, 0) else 4;
}

fn optionalU64EncodedByteSize(value: ?u64) usize {
    return 1 + if (value == null) @as(usize, 0) else 8;
}

fn optionalUsizeEncodedByteSize(value: ?usize) usize {
    return 1 + if (value == null) @as(usize, 0) else 8;
}

fn optionalEnumByteEncodedByteSize(value: anytype) usize {
    return 1 + if (value == null) @as(usize, 0) else 1;
}

fn bytesEncodedByteSize(bytes: []const u8) usize {
    return bytesFieldEncodedByteSize(bytes.len);
}

fn bytesFieldEncodedByteSize(len: usize) usize {
    return 8 + len;
}

fn optionalBytesEncodedByteSize(bytes: ?[]const u8) usize {
    return 1 + if (bytes) |present| bytesEncodedByteSize(present) else 0;
}

fn optionalValueImageEncodedByteSize(image: ?Frame.ValueImage) usize {
    return 1 + if (image) |present| bytesFieldEncodedByteSize(valueImageEncodedByteSize(present)) else 0;
}

fn valueImageEncodedByteSize(image: Frame.ValueImage) usize {
    var size: usize = 4 + 4 + 8;
    size = addSatEncodedSize(size, optionalU32EncodedByteSize(image.value_table_id));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.boundary_value_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(image.codec_schema_descriptor_fingerprint));
    size = addSatEncodedSize(size, 1);
    size = addSatEncodedSize(size, bytesEncodedByteSize(image.bytes));
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(image.diagnostic_type_label));
    return size;
}

fn optionalRequestFrameEncodedByteSize(frame: ?Frame.Request) usize {
    return 1 + if (frame) |present| bytesFieldEncodedByteSize(requestFrameEncodedByteSize(present)) else 0;
}

fn optionalResponseFrameEncodedByteSize(frame: ?Frame.Response) usize {
    return 1 + if (frame) |present| bytesFieldEncodedByteSize(responseFrameEncodedByteSize(present)) else 0;
}

fn requestFrameEncodedByteSize(frame: Frame.Request) usize {
    var size: usize = 4 + 4 + 8 + 8;
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.world_surface_replay_scope_fingerprint));
    size = addSatEncodedSize(size, 8 + 4 + 8 + 8 + 8 + 8);
    size = addSatEncodedSize(size, optionalU32EncodedByteSize(frame.payload_value_table_id));
    size = addSatEncodedSize(size, optionalU32EncodedByteSize(frame.expected_response_value_table_id));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.payload_value_fingerprint));
    size = addSatEncodedSize(size, optionalValueImageEncodedByteSize(frame.payload_image));
    size = addSatEncodedSize(size, 8 + 8 + 4 + 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.source_effect_shape_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.world_port_ref_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.trace_ref_fingerprint));
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.evidence_ref_fingerprint));
    size = addSatEncodedSize(size, 4);
    return size;
}

fn responseFrameEncodedByteSize(frame: Frame.Response) usize {
    var size: usize = 4 + 4 + 8 + 8 + 8 + 4 + 8 + 1;
    size = addSatEncodedSize(size, optionalU32EncodedByteSize(frame.response_value_table_id));
    size = addSatEncodedSize(size, 8);
    size = addSatEncodedSize(size, optionalU64EncodedByteSize(frame.response_value_fingerprint));
    size = addSatEncodedSize(size, optionalValueImageEncodedByteSize(frame.response_image));
    size = addSatEncodedSize(size, 8 + 1);
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(frame.error_tag));
    size = addSatEncodedSize(size, optionalBytesEncodedByteSize(frame.reason));
    size = addSatEncodedSize(size, 4);
    return size;
}

fn containsU64(values: []const u64, needle: u64) bool {
    for (values) |value| {
        if (value == needle) return true;
    }
    return false;
}

fn packageContainsBranch(package: Admission.TransferPackage, branch_id: u64) bool {
    if (containsU64(package.branch_refs, branch_id)) return true;
    if (package.run_image) |image| {
        for (image.branches) |branch| {
            if (branch.branch_id == branch_id) return true;
        }
    }
    return false;
}

fn packageContainsCheckpoint(package: Admission.TransferPackage, checkpoint_ref: u64) bool {
    if (containsU64(package.checkpoint_refs, checkpoint_ref)) return true;
    if (package.run_image) |image| {
        for (image.checkpoints) |checkpoint| {
            if (checkpoint.checkpoint_fingerprint == checkpoint_ref) return true;
        }
    }
    return false;
}

fn handoffPreflightBlockers(has_permit: bool) []const Admission.AdmissionBlocker {
    return if (has_permit) &.{.PermitRejected} else &.{.EnvironmentRejected};
}

fn scopePermitToAdmission(permit: RunPermit, admission_receipt_fingerprint: u64) RunPermit {
    var scoped = permit;
    scoped.permit_fingerprint = 0;
    scoped.admission_receipt_fingerprint = admission_receipt_fingerprint;
    scoped.permit_fingerprint = fingerprintRunPermit(scoped);
    return scoped;
}

fn writeOptionalTargetRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?TargetRef) !void {
    if (value) |target_ref| {
        try writeBool(out, allocator, true);
        try encodeTargetRef(out, allocator, target_ref);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readOptionalTargetRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?TargetRef {
    if (!try readBool(bytes, cursor)) return null;
    return try decodeTargetRef(allocator, bytes, cursor);
}

fn encodeModuleRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, module_ref: Admission.ModuleRef) !void {
    try writeU32(out, allocator, module_ref.format_version);
    try writeU32(out, allocator, module_ref.fingerprint_version);
    try writeU64(out, allocator, module_ref.module_ref_fingerprint);
    try writeU64(out, allocator, module_ref.boundary_module_fingerprint);
    try writeU8(out, allocator, @intFromEnum(module_ref.module_kind));
    try writeU64(out, allocator, module_ref.target_ref_fingerprint);
    try writeU64(out, allocator, module_ref.world_surface_fingerprint);
    try writeU64(out, allocator, module_ref.target_certificate_fingerprint);
    try writeOptionalU64(out, allocator, module_ref.residual_program_plan_hash);
    try writeOptionalU64(out, allocator, module_ref.import_surface_fingerprint);
    try writeOptionalU64(out, allocator, module_ref.export_surface_fingerprint);
    try writeOptionalU64(out, allocator, module_ref.module_graph_fingerprint);
    try writeU8(out, allocator, @intFromEnum(module_ref.normal_form_kind));
    try writeU64(out, allocator, module_ref.world_port_count);
    try writeOptionalU64(out, allocator, module_ref.world_port_table_fingerprint);
    try writeOptionalU64(out, allocator, module_ref.world_value_table_fingerprint);
    try writeOptionalU64(out, allocator, module_ref.world_dispatch_table_fingerprint);
    try writeOptionalBytes(out, allocator, module_ref.label);
    try writeBytes(out, allocator, module_ref.metadata);
}

fn decodeModuleRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Admission.ModuleRef {
    const format_version = try readU32(bytes, cursor);
    if (format_version != world_module_ref_format_version) return error.InvalidFrameEncoding;
    const fingerprint_version = try readU32(bytes, cursor);
    if (fingerprint_version != world_module_ref_fingerprint_version) return error.InvalidFrameEncoding;
    const module_ref_fingerprint = try readU64(bytes, cursor);
    const boundary_module_fingerprint = try readU64(bytes, cursor);
    const module_kind = try enumFromByte(Admission.BoundaryModuleKind, try readU8(bytes, cursor));
    const target_ref_fingerprint = try readU64(bytes, cursor);
    const world_surface_fingerprint = try readU64(bytes, cursor);
    const target_certificate_fingerprint = try readU64(bytes, cursor);
    const residual_program_plan_hash = try readOptionalU64(bytes, cursor);
    const import_surface_fingerprint = try readOptionalU64(bytes, cursor);
    const export_surface_fingerprint = try readOptionalU64(bytes, cursor);
    const module_graph_fingerprint = try readOptionalU64(bytes, cursor);
    const normal_form_kind = try enumFromByte(NormalFormKind, try readU8(bytes, cursor));
    const world_port_count = try readU64AsUsize(bytes, cursor);
    const world_port_table_fingerprint = try readOptionalU64(bytes, cursor);
    const world_value_table_fingerprint = try readOptionalU64(bytes, cursor);
    const world_dispatch_table_fingerprint = try readOptionalU64(bytes, cursor);
    const label = try readOptionalBytesOwned(allocator, bytes, cursor);
    errdefer if (label) |owned| allocator.free(@constCast(owned));
    const metadata = try readBytesOwned(allocator, bytes, cursor);
    errdefer allocator.free(@constCast(metadata));
    const result = Admission.ModuleRef{
        .format_version = format_version,
        .fingerprint_version = fingerprint_version,
        .module_ref_fingerprint = module_ref_fingerprint,
        .boundary_module_fingerprint = boundary_module_fingerprint,
        .module_kind = module_kind,
        .target_ref_fingerprint = target_ref_fingerprint,
        .world_surface_fingerprint = world_surface_fingerprint,
        .target_certificate_fingerprint = target_certificate_fingerprint,
        .residual_program_plan_hash = residual_program_plan_hash,
        .import_surface_fingerprint = import_surface_fingerprint,
        .export_surface_fingerprint = export_surface_fingerprint,
        .module_graph_fingerprint = module_graph_fingerprint,
        .normal_form_kind = normal_form_kind,
        .world_port_count = world_port_count,
        .world_port_table_fingerprint = world_port_table_fingerprint,
        .world_value_table_fingerprint = world_value_table_fingerprint,
        .world_dispatch_table_fingerprint = world_dispatch_table_fingerprint,
        .label = label,
        .metadata = metadata,
    };
    if (result.module_ref_fingerprint != fingerprintModuleRef(result)) return error.InvalidFrameEncoding;
    return result;
}

fn writeOptionalModuleRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?Admission.ModuleRef) !void {
    if (value) |module_ref| {
        try writeBool(out, allocator, true);
        try encodeModuleRef(out, allocator, module_ref);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readOptionalModuleRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?Admission.ModuleRef {
    if (!try readBool(bytes, cursor)) return null;
    return try decodeModuleRef(allocator, bytes, cursor);
}

fn encodePackageManifest(out: *std.ArrayList(u8), allocator: std.mem.Allocator, manifest: Admission.PackageManifest) !void {
    try writeU32(out, allocator, manifest.format_version);
    try writeU32(out, allocator, manifest.fingerprint_version);
    try writeU64(out, allocator, manifest.manifest_fingerprint);
    try writeU64(out, allocator, manifest.package_fingerprint);
    try writeU8(out, allocator, @intFromEnum(manifest.package_kind));
    try writeOptionalU64(out, allocator, manifest.target_ref_fingerprint);
    try writeOptionalU64(out, allocator, manifest.module_ref_fingerprint);
    try writeOptionalU64(out, allocator, manifest.module_image_fingerprint);
    try writeOptionalU64(out, allocator, manifest.run_image_fingerprint);
    try writeOptionalU64(out, allocator, manifest.transcript_image_fingerprint);
    try writeU64(out, allocator, manifest.checkpoint_count);
    try writeU64(out, allocator, manifest.branch_count);
    try writeU64(out, allocator, manifest.prior_receipt_count);
    try writeU8(out, allocator, @intFromEnum(manifest.requested_mode));
    try writeBytes(out, allocator, manifest.summary_metadata);
}

fn decodePackageManifest(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Admission.PackageManifest {
    const result = Admission.PackageManifest{
        .format_version = try readU32(bytes, cursor),
        .fingerprint_version = try readU32(bytes, cursor),
        .manifest_fingerprint = try readU64(bytes, cursor),
        .package_fingerprint = try readU64(bytes, cursor),
        .package_kind = try enumFromByte(Admission.PackageKind, try readU8(bytes, cursor)),
        .target_ref_fingerprint = try readOptionalU64(bytes, cursor),
        .module_ref_fingerprint = try readOptionalU64(bytes, cursor),
        .module_image_fingerprint = try readOptionalU64(bytes, cursor),
        .run_image_fingerprint = try readOptionalU64(bytes, cursor),
        .transcript_image_fingerprint = try readOptionalU64(bytes, cursor),
        .checkpoint_count = try readU64AsUsize(bytes, cursor),
        .branch_count = try readU64AsUsize(bytes, cursor),
        .prior_receipt_count = try readU64AsUsize(bytes, cursor),
        .requested_mode = try enumFromByte(Admission.AdmissionMode, try readU8(bytes, cursor)),
        .summary_metadata = try readBytesOwned(allocator, bytes, cursor),
    };
    errdefer allocator.free(@constCast(result.summary_metadata));
    if (result.format_version != world_package_manifest_format_version) return error.InvalidFrameEncoding;
    if (result.fingerprint_version != world_package_manifest_fingerprint_version) return error.InvalidFrameEncoding;
    if (result.manifest_fingerprint != fingerprintPackageManifest(result)) return error.InvalidFrameEncoding;
    return result;
}

fn writeOptionalRunImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?RunImage) !void {
    if (value) |image| {
        try writeBool(out, allocator, true);
        const encoded = try image.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readOptionalRunImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?RunImage {
    if (!try readBool(bytes, cursor)) return null;
    const encoded = try readBytesOwned(allocator, bytes, cursor);
    defer allocator.free(encoded);
    return try RunImage.decode(allocator, encoded);
}

fn writeOptionalTranscriptImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?TranscriptImage) !void {
    if (value) |image| {
        try writeBool(out, allocator, true);
        const encoded = try image.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readOptionalTranscriptImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?TranscriptImage {
    if (!try readBool(bytes, cursor)) return null;
    const encoded = try readBytesOwned(allocator, bytes, cursor);
    defer allocator.free(encoded);
    return try TranscriptImage.decode(allocator, encoded);
}

fn writeU64Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u64) !void {
    try writeU64(out, allocator, values.len);
    for (values) |value| try writeU64(out, allocator, value);
}

fn readU64SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_count: usize) ![]u64 {
    const count = try readU64AsUsize(bytes, cursor);
    if (count > max_count) return error.InvalidFrameEncoding;
    if (count > (bytes.len - cursor.*) / 8) return error.InvalidFrameEncoding;
    const values = try allocator.alloc(u64, count);
    errdefer allocator.free(values);
    for (values) |*value| value.* = try readU64(bytes, cursor);
    return values;
}

fn targetLabel(comptime Target: type) ?[]const u8 {
    if (@hasDecl(Target, "Certificate")) {
        if (@TypeOf(Target.Certificate) == type) {
            if (@hasDecl(Target.Certificate, "target_label")) return Target.Certificate.target_label;
        } else if (@hasField(@TypeOf(Target.Certificate), "target_label")) return Target.Certificate.target_label;
    }
    if (@TypeOf(Target.Program.contract) == type) {
        if (@hasDecl(Target.Program.contract, "label")) return Target.Program.contract.label;
    } else if (@hasField(@TypeOf(Target.Program.contract), "label")) return Target.Program.contract.label;
    return null;
}

fn residualProgramPlanHash(comptime Target: type) ?u64 {
    if (@hasDecl(Target.Program, "compiled_plan") and @hasDecl(@TypeOf(Target.Program.compiled_plan), "hash")) {
        return Target.Program.compiled_plan.hash();
    }
    return null;
}

fn normalFormKind(comptime Target: type) NormalFormKind {
    if (@hasDecl(Target, "NormalForm")) {
        if (@TypeOf(Target.NormalForm) == type) {
            if (@hasDecl(Target.NormalForm, "kind")) {
                const name = @tagName(Target.NormalForm.kind);
                if (std.mem.eql(u8, name, "strict_closed")) return .strict_closed;
                if (std.mem.eql(u8, name, "world_ports_only")) return .world_ports_only;
            }
        } else if (@hasField(@TypeOf(Target.NormalForm), "kind")) {
            const name = @tagName(Target.NormalForm.kind);
            if (std.mem.eql(u8, name, "strict_closed")) return .strict_closed;
            if (std.mem.eql(u8, name, "world_ports_only")) return .world_ports_only;
        }
    }
    return .boundary_normal_form;
}

fn tableFingerprint(comptime table: anytype) ?u64 {
    if (@TypeOf(table) == type) {
        if (@hasDecl(table, "fingerprint")) return table.fingerprint;
        if (@hasDecl(table, "surface_fingerprint")) return table.surface_fingerprint;
        if (@hasDecl(table, "certificate_fingerprint")) return table.certificate_fingerprint;
    } else {
        const Table = @TypeOf(table);
        if (@hasField(Table, "fingerprint")) return table.fingerprint;
        if (@hasField(Table, "surface_fingerprint")) return table.surface_fingerprint;
        if (@hasField(Table, "certificate_fingerprint")) return table.certificate_fingerprint;
        if (@hasDecl(Table, "fingerprint")) return table.fingerprint;
        if (@hasDecl(Table, "surface_fingerprint")) return table.surface_fingerprint;
        if (@hasDecl(Table, "certificate_fingerprint")) return table.certificate_fingerprint;
    }
    return null;
}

fn refFingerprint(ref: anytype) ?u64 {
    const Ref = @TypeOf(ref);
    if (@hasField(Ref, "fingerprint")) return ref.fingerprint;
    return null;
}

fn replayKeyRecipeFingerprint(comptime Target: type) ?u64 {
    if (@hasDecl(Target, "replay_key_recipe")) return refFingerprint(Target.replay_key_recipe.evidenceRef());
    if (@TypeOf(Target.WorldSurface) == type) {
        if (@hasDecl(Target.WorldSurface, "replay_key_recipe_ref")) return refFingerprint(Target.WorldSurface.replay_key_recipe_ref);
    } else if (@hasField(@TypeOf(Target.WorldSurface), "replay_key_recipe_ref")) return refFingerprint(Target.WorldSurface.replay_key_recipe_ref);
    return Target.WorldSurface.replayScopeRef().fingerprint;
}

fn modeToRunMode(mode: HandoffMode) Mode {
    return switch (mode) {
        .accept_fresh => .fresh,
        .accept_replay => .replay,
        .accept_verify => .verify,
        .inspect_only => .audit,
    };
}

fn valuePolicyForEnvironment(comptime Env: type) ValuePolicy {
    return .{
        .require_portable_values = Env.policy_decl.require_portable_values,
        .allow_native_only_values = Env.policy_decl.allow_native_only_values,
        .require_response_images_for_replay = Env.policy_decl.require_frame_images_for_replay,
        .allow_diagnostic_type_labels = Env.policy_decl.allow_native_only_values,
    };
}

fn validateTranscriptForEnvironment(comptime Env: type, transcript: *const Transcript) !void {
    for (transcript.events.items) |event| {
        if (event.request_frame) |frame| try validateRequestFramePolicy(frame, try valuePolicyForEnvironmentPort(Env, frame.world_port_id, .request));
        if (event.response_frame) |frame| try validateResponseFramePolicy(frame, try valuePolicyForEnvironmentPort(Env, frame.world_port_id, .response));
    }
}

fn validateTranscriptImageForEnvironment(comptime Env: type, image: *const TranscriptImage) !void {
    for (image.events) |event| {
        if (event.request_frame) |frame| try validateRequestFramePolicy(frame, try valuePolicyForEnvironmentPort(Env, frame.world_port_id, .request));
        if (event.response_frame) |frame| try validateResponseFramePolicy(frame, try replayImageValuePolicyForEnvironmentPort(Env, frame.world_port_id));
    }
}

const FrameValuePolicyKind = enum { request, response };

fn replayImageValuePolicyForEnvironmentPort(comptime Env: type, world_port_id: u32) !ValuePolicy {
    var policy = try valuePolicyForEnvironmentPort(Env, world_port_id, .response);
    policy.require_response_images_for_replay = true;
    return policy;
}

fn valuePolicyForEnvironmentPort(comptime Env: type, world_port_id: u32, comptime kind: FrameValuePolicyKind) !ValuePolicy {
    if (world_port_id >= Env.TargetType.WorldPortTable.entries.len) return error.WrongPortId;
    var policy = valuePolicyForEnvironment(Env);
    var found = false;
    inline for (Env.bindings_decl) |BindingDecl| {
        if (comptime BindingDecl.TargetType == Env.TargetType) {
            if (BindingDecl.world_port_id == world_port_id) {
                found = true;
                const binding_policy: ValuePolicy = if (@hasDecl(BindingDecl, "value_policy")) BindingDecl.value_policy else .native_compatible;
                if (binding_policy.require_portable_values) policy.require_portable_values = true;
                if (!binding_policy.allow_native_only_values) policy.allow_native_only_values = false;
                if (binding_policy.require_response_images_for_replay) policy.require_response_images_for_replay = true;
                if (!binding_policy.allow_diagnostic_type_labels) policy.allow_diagnostic_type_labels = false;
                tightenValuePolicyMax(&policy, binding_policy.max_value_image_bytes);
                if (@hasDecl(BindingDecl, "authority")) {
                    if (BindingDecl.authority.requires_portable_values) policy.require_portable_values = true;
                    if (!BindingDecl.authority.allows_native_only_values) policy.allow_native_only_values = false;
                    switch (kind) {
                        .request => tightenValuePolicyMax(&policy, BindingDecl.authority.max_payload_image_bytes),
                        .response => tightenValuePolicyMax(&policy, BindingDecl.authority.max_response_image_bytes),
                    }
                }
            }
        }
    }
    if (!found) return error.MissingBinding;
    return policy;
}

fn adapterKindForEnvironmentPort(comptime Env: type, world_port_id: u32) !AdapterKind {
    if (world_port_id >= Env.TargetType.WorldPortTable.entries.len) return error.WrongPortId;
    inline for (Env.bindings_decl) |BindingDecl| {
        if (comptime BindingDecl.TargetType == Env.TargetType) {
            if (BindingDecl.world_port_id == world_port_id) return adapterKindForDecl(BindingDecl);
        }
    }
    return error.MissingBinding;
}

fn authorityKindForEnvironmentPort(comptime Env: type, world_port_id: u32) !?PortAuthority.Kind {
    if (world_port_id >= Env.TargetType.WorldPortTable.entries.len) return error.WrongPortId;
    inline for (Env.bindings_decl) |BindingDecl| {
        if (comptime BindingDecl.TargetType == Env.TargetType) {
            if (BindingDecl.world_port_id == world_port_id) return authorityKindForDecl(BindingDecl);
        }
    }
    return error.MissingBinding;
}

fn environmentValidationBlocker(err: anyerror) AcceptanceBlocker {
    return switch (err) {
        error.WrongPortId => .WrongPortId,
        error.MissingBinding => .MissingBinding,
        else => .NativeOnlyValueRejected,
    };
}

fn tightenValuePolicyMax(policy: *ValuePolicy, limit: ?usize) void {
    if (limit) |max| {
        if (policy.max_value_image_bytes == null or policy.max_value_image_bytes.? > max) {
            policy.max_value_image_bytes = max;
        }
    }
}

fn valuePolicyForRunImageValidation(options: RunImage.ValidateOptions) ValuePolicy {
    var policy = if (options.require_portable_values) ValuePolicy.portable else ValuePolicy.native_compatible;
    policy.max_value_image_bytes = options.max_image_bytes;
    return policy;
}

fn adapterKindForDecl(comptime Decl: type) AdapterKind {
    return if (@hasDecl(Decl, "adapter_kind")) Decl.adapter_kind else .native;
}

fn authorityKindForDecl(comptime Decl: type) ?PortAuthority.Kind {
    if (@hasDecl(Decl, "authority")) return Decl.authority.authority_kind;
    return if (adapterKindForDecl(Decl) == .native) PortAuthority.native_function.authority_kind else null;
}

fn authoritySetFingerprint(entries: []const BindingPlan.Entry) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.environment.authority_set.fingerprint");
    for (entries) |entry| {
        if (entry.authority_fingerprint) |fingerprint| hashU64(&hasher, fingerprint);
    }
    return hasher.final();
}

fn adapterSetFingerprint(entries: []const BindingPlan.Entry) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.environment.adapter_set.fingerprint");
    for (entries) |entry| hashU64(&hasher, entry.adapter_descriptor_fingerprint);
    return hasher.final();
}

fn encodeTargetRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, target_ref: TargetRef) !void {
    try writeU32(out, allocator, target_ref.format_version);
    try writeU32(out, allocator, target_ref.fingerprint_version);
    try writeU64(out, allocator, target_ref.target_ref_fingerprint);
    try writeOptionalBytes(out, allocator, target_ref.target_label);
    try writeU64(out, allocator, target_ref.world_surface_fingerprint);
    try writeOptionalU64(out, allocator, target_ref.world_surface_replay_scope_fingerprint);
    try writeU64(out, allocator, target_ref.target_certificate_fingerprint);
    try writeOptionalU64(out, allocator, target_ref.residual_program_plan_hash);
    try writeU8(out, allocator, @intFromEnum(target_ref.normal_form_kind));
    try writeOptionalU64(out, allocator, target_ref.world_port_table_fingerprint);
    try writeOptionalU64(out, allocator, target_ref.world_value_table_fingerprint);
    try writeOptionalU64(out, allocator, target_ref.world_dispatch_table_fingerprint);
    try writeOptionalU64(out, allocator, target_ref.surface_profile_fingerprint);
    if (targetRefEncodesBoundaryModule(target_ref)) try writeOptionalU64(out, allocator, target_ref.boundary_module_fingerprint);
    try writeBytes(out, allocator, target_ref.metadata);
}

const DecodedTargetRefHead = struct {
    format_version: u32,
    fingerprint_version: u32,
    target_ref_fingerprint: u64,
    target_label: ?[]const u8,
    world_surface_fingerprint: u64,
    world_surface_replay_scope_fingerprint: ?u64,
    target_certificate_fingerprint: u64,
    residual_program_plan_hash: ?u64,
    normal_form_kind: NormalFormKind,
    world_port_table_fingerprint: ?u64,
    world_value_table_fingerprint: ?u64,
    world_dispatch_table_fingerprint: ?u64,
    surface_profile_fingerprint: ?u64,
};

fn decodeTargetRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TargetRef {
    const format_version = try readU32(bytes, cursor);
    if (format_version != 1 and format_version != world_target_ref_format_version) return error.InvalidFrameEncoding;
    const fingerprint_version = try readU32(bytes, cursor);
    if (fingerprint_version != world_target_ref_fingerprint_version) return error.InvalidFrameEncoding;
    const target_ref_fingerprint = try readU64(bytes, cursor);
    const target_label = try readOptionalBytesOwned(allocator, bytes, cursor);
    errdefer if (target_label) |label| allocator.free(@constCast(label));
    const world_surface_fingerprint = try readU64(bytes, cursor);
    const world_surface_replay_scope_fingerprint = try readOptionalU64(bytes, cursor);
    const target_certificate_fingerprint = try readU64(bytes, cursor);
    const residual_program_plan_hash = try readOptionalU64(bytes, cursor);
    const kind = try enumFromByte(NormalFormKind, try readU8(bytes, cursor));
    const world_port_table_fingerprint = try readOptionalU64(bytes, cursor);
    const world_value_table_fingerprint = try readOptionalU64(bytes, cursor);
    const world_dispatch_table_fingerprint = try readOptionalU64(bytes, cursor);
    const surface_profile_fingerprint = try readOptionalU64(bytes, cursor);
    const head = DecodedTargetRefHead{
        .format_version = format_version,
        .fingerprint_version = fingerprint_version,
        .target_ref_fingerprint = target_ref_fingerprint,
        .target_label = target_label,
        .world_surface_fingerprint = world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = target_certificate_fingerprint,
        .residual_program_plan_hash = residual_program_plan_hash,
        .normal_form_kind = kind,
        .world_port_table_fingerprint = world_port_table_fingerprint,
        .world_value_table_fingerprint = world_value_table_fingerprint,
        .world_dispatch_table_fingerprint = world_dispatch_table_fingerprint,
        .surface_profile_fingerprint = surface_profile_fingerprint,
    };
    return try decodeTargetRefTail(allocator, bytes, cursor, head, true);
}

fn decodeTargetRefTail(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, head: DecodedTargetRefHead, include_boundary_module: bool) !TargetRef {
    const boundary_module_fingerprint = if (include_boundary_module) try readOptionalU64(bytes, cursor) else null;
    const metadata = try readBytesOwned(allocator, bytes, cursor);
    errdefer allocator.free(metadata);
    const result = TargetRef{
        .format_version = head.format_version,
        .fingerprint_version = head.fingerprint_version,
        .target_ref_fingerprint = head.target_ref_fingerprint,
        .target_label = head.target_label,
        .world_surface_fingerprint = head.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = head.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = head.target_certificate_fingerprint,
        .residual_program_plan_hash = head.residual_program_plan_hash,
        .normal_form_kind = head.normal_form_kind,
        .world_port_table_fingerprint = head.world_port_table_fingerprint,
        .world_value_table_fingerprint = head.world_value_table_fingerprint,
        .world_dispatch_table_fingerprint = head.world_dispatch_table_fingerprint,
        .surface_profile_fingerprint = head.surface_profile_fingerprint,
        .boundary_module_fingerprint = boundary_module_fingerprint,
        .metadata = metadata,
    };
    if (fingerprintTargetRef(result) != head.target_ref_fingerprint) return error.InvalidFrameEncoding;
    return result;
}

fn encodeRunState(out: *std.ArrayList(u8), allocator: std.mem.Allocator, state: RunState) !void {
    try writeU64(out, allocator, state.run_state_fingerprint);
    try writeU64(out, allocator, state.target_ref_fingerprint);
    try writeOptionalU64(out, allocator, state.transcript_image_fingerprint);
    try writeU64(out, allocator, state.branch_id);
    try writeOptionalU64(out, allocator, state.checkpoint_fingerprint);
    try writeOptionalU64(out, allocator, state.pending_request_fingerprint);
    try writeOptionalU64(out, allocator, state.final_response_fingerprint);
    try writeOptionalU64(out, allocator, state.final_value_image_fingerprint);
    try writeU64(out, allocator, state.turn_index);
    try writeU8(out, allocator, @intFromEnum(state.status));
}

fn decodeRunState(bytes: []const u8, cursor: *usize) !RunState {
    const state = RunState{
        .run_state_fingerprint = try readU64(bytes, cursor),
        .target_ref_fingerprint = try readU64(bytes, cursor),
        .transcript_image_fingerprint = try readOptionalU64(bytes, cursor),
        .branch_id = try readU64(bytes, cursor),
        .checkpoint_fingerprint = try readOptionalU64(bytes, cursor),
        .pending_request_fingerprint = try readOptionalU64(bytes, cursor),
        .final_response_fingerprint = try readOptionalU64(bytes, cursor),
        .final_value_image_fingerprint = try readOptionalU64(bytes, cursor),
        .turn_index = try readU64AsUsize(bytes, cursor),
        .status = try enumFromByte(RunState.Status, try readU8(bytes, cursor)),
    };
    if (fingerprintRunState(state) != state.run_state_fingerprint) return error.InvalidFrameEncoding;
    return state;
}

fn encodeCheckpoint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, checkpoint: Timeline.Checkpoint) !void {
    try writeU32(out, allocator, checkpoint.format_version);
    try writeU32(out, allocator, checkpoint.fingerprint_version);
    try writeU64(out, allocator, checkpoint.checkpoint_fingerprint);
    try writeU64(out, allocator, checkpoint.world_surface_fingerprint);
    try writeU64(out, allocator, checkpoint.target_certificate_fingerprint);
    try writeU64(out, allocator, checkpoint.event_index);
    try writeU64(out, allocator, checkpoint.turn_index);
    try writeOptionalU64(out, allocator, checkpoint.current_request_fingerprint);
    try writeOptionalU64(out, allocator, checkpoint.last_response_fingerprint);
    try writeOptionalU64(out, allocator, checkpoint.capsule_image_fingerprint);
    try writeU64(out, allocator, checkpoint.transcript_prefix_fingerprint);
    try writeU64(out, allocator, checkpoint.branch_id);
    try writeU8(out, allocator, @intFromEnum(checkpoint.status));
}

fn decodeCheckpoint(bytes: []const u8, cursor: *usize) !Timeline.Checkpoint {
    const format_version = try readU32(bytes, cursor);
    if (format_version != world_timeline_checkpoint_format_version) return error.InvalidFrameEncoding;
    const fingerprint_version = try readU32(bytes, cursor);
    if (fingerprint_version != world_timeline_checkpoint_fingerprint_version) return error.InvalidFrameEncoding;
    const checkpoint = Timeline.Checkpoint{
        .checkpoint_fingerprint = try readU64(bytes, cursor),
        .world_surface_fingerprint = try readU64(bytes, cursor),
        .target_certificate_fingerprint = try readU64(bytes, cursor),
        .event_index = try readU64AsUsize(bytes, cursor),
        .turn_index = try readU64AsUsize(bytes, cursor),
        .current_request_fingerprint = try readOptionalU64(bytes, cursor),
        .last_response_fingerprint = try readOptionalU64(bytes, cursor),
        .capsule_image_fingerprint = try readOptionalU64(bytes, cursor),
        .transcript_prefix_fingerprint = try readU64(bytes, cursor),
        .branch_id = try readU64(bytes, cursor),
        .status = try enumFromByte(Timeline.Checkpoint.Status, try readU8(bytes, cursor)),
    };
    if (fingerprintCheckpoint(checkpoint) != checkpoint.checkpoint_fingerprint) return error.InvalidFrameEncoding;
    return checkpoint;
}

fn encodeBranch(out: *std.ArrayList(u8), allocator: std.mem.Allocator, branch: Timeline.Branch) !void {
    try writeU32(out, allocator, branch.format_version);
    try writeU32(out, allocator, branch.fingerprint_version);
    try writeU64(out, allocator, branch.branch_id);
    try writeOptionalU64(out, allocator, branch.parent_branch_id);
    try writeU64(out, allocator, branch.checkpoint_fingerprint);
    try writeBytes(out, allocator, branch.branch_label);
    try writeU64(out, allocator, branch.start_event_index);
    try writeOptionalU64(out, allocator, branch.final_event_index);
    try writeU8(out, allocator, @intFromEnum(branch.final_status));
    try writeU64(out, allocator, branch.event_count);
    try writeU64(out, allocator, branch.response_count);
    try writeU64(out, allocator, branch.fingerprint());
}

fn decodeBranch(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Timeline.Branch {
    const format_version = try readU32(bytes, cursor);
    if (format_version != world_timeline_branch_format_version) return error.InvalidFrameEncoding;
    const fingerprint_version = try readU32(bytes, cursor);
    if (fingerprint_version != world_timeline_branch_fingerprint_version) return error.InvalidFrameEncoding;
    const branch_id = try readU64(bytes, cursor);
    const parent_branch_id = try readOptionalU64(bytes, cursor);
    const checkpoint_fingerprint = try readU64(bytes, cursor);
    const label = try readBytesOwned(allocator, bytes, cursor);
    errdefer allocator.free(label);
    const branch = Timeline.Branch{
        .branch_id = branch_id,
        .parent_branch_id = parent_branch_id,
        .checkpoint_fingerprint = checkpoint_fingerprint,
        .branch_label = label,
        .start_event_index = try readU64AsUsize(bytes, cursor),
        .final_event_index = try readOptionalUsize(bytes, cursor),
        .final_status = try enumFromByte(Timeline.Checkpoint.Status, try readU8(bytes, cursor)),
        .event_count = try readU64AsUsize(bytes, cursor),
        .response_count = try readU64AsUsize(bytes, cursor),
    };
    if (try readU64(bytes, cursor) != branch.fingerprint()) return error.InvalidFrameEncoding;
    return branch;
}

fn targetRefEncodesBoundaryModule(target_ref: TargetRef) bool {
    return target_ref.format_version >= 1;
}

fn fingerprintTargetRef(target_ref: TargetRef) u64 {
    if (!targetRefEncodesBoundaryModule(target_ref)) return fingerprintTargetRefWithoutBoundaryModule(target_ref);
    return fingerprintTargetRefWithBoundaryModule(target_ref);
}

fn fingerprintTargetRefWithoutBoundaryModule(target_ref: TargetRef) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.target_ref.fingerprint");
    hashU64(&hasher, world_target_ref_fingerprint_version);
    hashOptionalBytes(&hasher, target_ref.target_label);
    hashU64(&hasher, target_ref.world_surface_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_surface_replay_scope_fingerprint);
    hashU64(&hasher, target_ref.target_certificate_fingerprint);
    hashOptionalU64(&hasher, target_ref.residual_program_plan_hash);
    hashU64(&hasher, @intFromEnum(target_ref.normal_form_kind));
    hashOptionalU64(&hasher, target_ref.world_port_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_value_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_dispatch_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.surface_profile_fingerprint);
    hashU64(&hasher, target_ref.metadata.len);
    hashBytes(&hasher, target_ref.metadata);
    return hasher.final();
}

fn fingerprintTargetRefWithBoundaryModule(target_ref: TargetRef) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.target_ref.fingerprint");
    hashU64(&hasher, world_target_ref_fingerprint_version);
    hashOptionalBytes(&hasher, target_ref.target_label);
    hashU64(&hasher, target_ref.world_surface_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_surface_replay_scope_fingerprint);
    hashU64(&hasher, target_ref.target_certificate_fingerprint);
    hashOptionalU64(&hasher, target_ref.residual_program_plan_hash);
    hashU64(&hasher, @intFromEnum(target_ref.normal_form_kind));
    hashOptionalU64(&hasher, target_ref.world_port_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_value_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.world_dispatch_table_fingerprint);
    hashOptionalU64(&hasher, target_ref.surface_profile_fingerprint);
    hashOptionalU64(&hasher, target_ref.boundary_module_fingerprint);
    hashU64(&hasher, target_ref.metadata.len);
    hashBytes(&hasher, target_ref.metadata);
    return hasher.final();
}

fn fingerprintImportRequirement(requirement: ImportRequirement) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.import_requirement.fingerprint");
    hashU64(&hasher, world_import_requirement_fingerprint_version);
    hashU64(&hasher, requirement.world_surface_fingerprint);
    hashU64(&hasher, requirement.world_port_id);
    hashOptionalU64(&hasher, requirement.world_port_ref_fingerprint);
    hashOptionalU64(&hasher, requirement.source_effect_shape_ref_fingerprint);
    hashU64(&hasher, requirement.residual_site_index);
    hashU64(&hasher, requirement.residual_site_fingerprint);
    hashOptionalU32(&hasher, requirement.payload_value_table_id);
    hashOptionalU32(&hasher, requirement.response_value_table_id);
    hashU64(&hasher, @intFromEnum(requirement.mode));
    hashU64(&hasher, @intFromEnum(requirement.allowed_response_kinds));
    hashOptionalU64(&hasher, requirement.replay_key_recipe_fingerprint);
    hashOptionalBytes(&hasher, requirement.suggested_symbolic_name);
    hashBool(&hasher, requirement.required);
    hashU64(&hasher, requirement.tags.len);
    for (requirement.tags) |tag| {
        hashU64(&hasher, tag.len);
        hashBytes(&hasher, tag);
    }
    hashU64(&hasher, requirement.metadata.len);
    hashBytes(&hasher, requirement.metadata);
    return hasher.final();
}

fn fingerprintImportSet(import_set: ImportSet) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.import_set.fingerprint");
    hashU64(&hasher, world_import_set_fingerprint_version);
    hashU64(&hasher, import_set.target_ref_fingerprint);
    hashU64(&hasher, import_set.required_count);
    hashU64(&hasher, import_set.optional_count);
    hashU64(&hasher, import_set.world_port_count);
    hashU64(&hasher, import_set.value_table_entry_count);
    hashOptionalU64(&hasher, import_set.surface_profile_fingerprint);
    return hasher.final();
}

fn fingerprintPortAuthority(authority: PortAuthority) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.port_authority.fingerprint");
    hashU64(&hasher, world_port_authority_fingerprint_version);
    hashU64(&hasher, authority.authority_label.len);
    hashBytes(&hasher, authority.authority_label);
    hashU64(&hasher, @intFromEnum(authority.authority_kind));
    hashU64(&hasher, @intFromEnum(authority.allowed_modes));
    hashBool(&hasher, authority.allows_fresh_calls);
    hashBool(&hasher, authority.allows_replay);
    hashBool(&hasher, authority.allows_verify);
    hashBool(&hasher, authority.requires_portable_values);
    hashBool(&hasher, authority.allows_native_only_values);
    hashOptionalU64(&hasher, authority.max_payload_image_bytes);
    hashOptionalU64(&hasher, authority.max_response_image_bytes);
    hashU64(&hasher, authority.metadata.len);
    hashBytes(&hasher, authority.metadata);
    return hasher.final();
}

fn fingerprintAdapterDescriptor(descriptor: AdapterDescriptor) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.adapter_descriptor.fingerprint");
    hashU64(&hasher, world_adapter_descriptor_fingerprint_version);
    hashU64(&hasher, @intFromEnum(descriptor.adapter_kind));
    hashU64(&hasher, descriptor.target_ref_fingerprint);
    hashU64(&hasher, descriptor.world_surface_fingerprint);
    hashU64(&hasher, descriptor.world_port_id);
    hashValuePolicy(&hasher, descriptor.value_policy);
    hashOptionalU64(&hasher, descriptor.authority_fingerprint);
    hashU64(&hasher, descriptor.label.len);
    hashBytes(&hasher, descriptor.label);
    hashU64(&hasher, descriptor.metadata.len);
    hashBytes(&hasher, descriptor.metadata);
    hashOptionalU64(&hasher, descriptor.replay_source_fingerprint);
    hashOptionalBytes(&hasher, descriptor.byte_adapter_protocol_label);
    return hasher.final();
}

fn fingerprintBinding(binding: Binding) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.binding.fingerprint");
    hashU64(&hasher, world_binding_fingerprint_version);
    hashU64(&hasher, binding.target_ref_fingerprint);
    hashU64(&hasher, binding.world_surface_fingerprint);
    hashU64(&hasher, binding.target_certificate_fingerprint);
    hashU64(&hasher, binding.world_port_id);
    hashU64(&hasher, binding.import_requirement_fingerprint);
    hashOptionalU64(&hasher, binding.world_port_ref_fingerprint);
    hashOptionalU64(&hasher, binding.source_effect_shape_ref_fingerprint);
    hashOptionalU32(&hasher, binding.payload_value_table_id);
    hashOptionalU32(&hasher, binding.response_value_table_id);
    hashU64(&hasher, @intFromEnum(binding.adapter_kind));
    hashU64(&hasher, @intFromEnum(binding.binding_mode_policy));
    hashValuePolicy(&hasher, binding.value_policy);
    hashOptionalU64(&hasher, binding.authority_fingerprint);
    hashU64(&hasher, binding.adapter_descriptor_fingerprint);
    hashU64(&hasher, binding.label.len);
    hashBytes(&hasher, binding.label);
    hashU64(&hasher, binding.tags.len);
    for (binding.tags) |tag| {
        hashU64(&hasher, tag.len);
        hashBytes(&hasher, tag);
    }
    hashU64(&hasher, binding.metadata.len);
    hashBytes(&hasher, binding.metadata);
    return hasher.final();
}

fn fingerprintEnvironmentPolicy(policy: EnvironmentPolicy) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.environment.policy.fingerprint");
    hashU64(&hasher, world_environment_policy_fingerprint_version);
    hashBool(&hasher, policy.require_all_required_ports_bound);
    hashBool(&hasher, policy.reject_extra_bindings);
    hashBool(&hasher, policy.reject_wrong_surface);
    hashBool(&hasher, policy.require_target_certificate_match);
    hashBool(&hasher, policy.allow_replay_without_handlers);
    hashBool(&hasher, policy.allow_fresh_without_transcript);
    hashBool(&hasher, policy.allow_verify_without_transcript);
    hashBool(&hasher, policy.require_portable_values);
    hashBool(&hasher, policy.allow_native_only_values);
    hashBool(&hasher, policy.require_frame_images_for_replay);
    hashBool(&hasher, policy.allow_pending_adapters);
    hashBool(&hasher, policy.allow_reject_adapters);
    hashBool(&hasher, policy.allow_byte_adapters);
    hashBool(&hasher, policy.allow_native_adapters);
    hashOptionalU64(&hasher, policy.max_world_ports);
    hashOptionalU64(&hasher, policy.max_bindings);
    return hasher.final();
}

fn fingerprintBindingPlan(plan: BindingPlan) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.binding_plan.fingerprint");
    hashU64(&hasher, world_binding_plan_fingerprint_version);
    hashU64(&hasher, plan.target_ref_fingerprint);
    hashU64(&hasher, plan.world_surface_fingerprint);
    hashU64(&hasher, plan.target_certificate_fingerprint);
    hashU64(&hasher, plan.binding_count);
    for (plan.dense_entries) |entry| {
        hashU64(&hasher, entry.world_port_id);
        hashU64(&hasher, entry.adapter_slot);
        hashU64(&hasher, entry.binding_fingerprint);
        hashU64(&hasher, @intFromEnum(entry.adapter_kind));
        hashValuePolicy(&hasher, entry.value_policy);
        hashOptionalU64(&hasher, entry.authority_fingerprint);
    }
    hashBool(&hasher, plan.accepted);
    return hasher.final();
}

fn fingerprintAcceptanceReport(report: AcceptanceReport) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.acceptance_report.fingerprint");
    hashU64(&hasher, world_acceptance_report_fingerprint_version);
    hashU64(&hasher, report.target_ref_fingerprint);
    hashU64(&hasher, report.world_surface_fingerprint);
    hashU64(&hasher, report.target_certificate_fingerprint);
    hashU64(&hasher, @intFromEnum(report.requested_mode));
    hashBool(&hasher, report.accepted);
    hashU64(&hasher, report.required_port_count);
    hashU64(&hasher, report.bound_port_count);
    hashU64(&hasher, report.missing_port_count);
    hashU64(&hasher, report.extra_binding_count);
    hashU64(&hasher, report.replay_only_port_count);
    hashU64(&hasher, report.native_port_count);
    hashU64(&hasher, report.byte_adapter_port_count);
    hashU64(&hasher, report.portable_value_compatible_count);
    hashU64(&hasher, report.native_only_value_count);
    hashU64(&hasher, report.blockers.len);
    for (report.blockers) |blocker| hashU64(&hasher, @intFromEnum(blocker));
    hashU64(&hasher, report.warnings.len);
    for (report.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
    hashU64(&hasher, report.summary.len);
    hashBytes(&hasher, report.summary);
    return hasher.final();
}

fn fingerprintEnvironmentCertificate(cert: EnvironmentCertificate) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.environment_certificate.fingerprint");
    hashU64(&hasher, world_environment_certificate_fingerprint_version);
    hashU64(&hasher, cert.target_ref_fingerprint);
    hashU64(&hasher, cert.world_surface_fingerprint);
    hashU64(&hasher, cert.target_certificate_fingerprint);
    hashU64(&hasher, cert.import_set_fingerprint);
    hashU64(&hasher, cert.binding_plan_fingerprint);
    hashU64(&hasher, cert.acceptance_report_fingerprint);
    hashU64(&hasher, cert.policy_fingerprint);
    hashU64(&hasher, cert.authority_descriptor_fingerprint);
    hashU64(&hasher, cert.adapter_descriptor_fingerprint);
    hashU64(&hasher, @intFromEnum(cert.accepted_modes));
    hashU64(&hasher, cert.blocker_count);
    return hasher.final();
}

fn fingerprintSupervisionPolicy(policy: SupervisionPolicy) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.supervision.policy.fingerprint");
    hashU64(&hasher, world_supervision_policy_fingerprint_version);
    hashBool(&hasher, policy.allow_fresh_calls);
    hashBool(&hasher, policy.allow_replay_calls);
    hashBool(&hasher, policy.allow_verify_calls);
    hashBool(&hasher, policy.allow_audit_only);
    hashBool(&hasher, policy.allow_native_adapters);
    hashBool(&hasher, policy.allow_byte_adapters);
    hashBool(&hasher, policy.allow_replay_adapters);
    hashBool(&hasher, policy.allow_pending_responses);
    hashBool(&hasher, policy.allow_rejected_responses);
    hashBool(&hasher, policy.allow_failed_responses);
    hashBool(&hasher, policy.allow_branching);
    hashBool(&hasher, policy.allow_checkpoints);
    hashBool(&hasher, policy.allow_handoff_export);
    hashBool(&hasher, policy.allow_handoff_accept);
    hashBool(&hasher, policy.require_portable_value_images);
    hashBool(&hasher, policy.reject_native_only_values);
    hashBool(&hasher, policy.require_environment_certificate);
    hashBool(&hasher, policy.require_transcript_image_for_replay);
    hashBool(&hasher, policy.fail_on_budget_exceeded);
    hashBool(&hasher, policy.park_on_budget_exceeded);
    hashBool(&hasher, policy.audit_only_on_budget_exceeded);
    hashOptionalU64(&hasher, policy.max_supervision_events);
    return hasher.final();
}

fn fingerprintBudget(budget: Budget) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.budget.fingerprint");
    hashU64(&hasher, world_budget_fingerprint_version);
    hashOptionalU64(&hasher, budget.max_session_steps);
    hashOptionalU64(&hasher, budget.max_port_requests);
    hashOptionalU64(&hasher, budget.max_port_responses);
    hashOptionalU64(&hasher, budget.max_fresh_calls);
    hashOptionalU64(&hasher, budget.max_replay_calls);
    hashOptionalU64(&hasher, budget.max_verify_calls);
    hashOptionalU64(&hasher, budget.max_failed_calls);
    hashOptionalU64(&hasher, budget.max_rejected_calls);
    hashOptionalU64(&hasher, budget.max_pending_calls);
    hashOptionalU64(&hasher, budget.max_frame_request_bytes);
    hashOptionalU64(&hasher, budget.max_frame_response_bytes);
    hashOptionalU64(&hasher, budget.max_value_image_bytes);
    hashOptionalU64(&hasher, budget.max_transcript_events);
    hashOptionalU64(&hasher, budget.max_transcript_image_bytes);
    hashOptionalU64(&hasher, budget.max_checkpoints);
    hashOptionalU64(&hasher, budget.max_branches);
    hashOptionalU64(&hasher, budget.max_branch_depth);
    hashOptionalU64(&hasher, budget.max_handoff_exports);
    hashOptionalU64(&hasher, budget.max_handoff_accepts);
    hashOptionalU64(&hasher, budget.max_total_cost_units);
    hashU64(&hasher, budget.per_port_budgets.len);
    for (budget.per_port_budgets) |per_port| {
        hashU64(&hasher, per_port.world_port_id);
        hashOptionalU64(&hasher, per_port.max_requests);
        hashOptionalU64(&hasher, per_port.max_fresh_calls);
        hashOptionalU64(&hasher, per_port.max_replay_calls);
        hashOptionalU64(&hasher, per_port.max_response_bytes);
        hashOptionalU64(&hasher, per_port.max_value_image_bytes);
        hashOptionalU64(&hasher, per_port.max_cost_units);
    }
    return hasher.final();
}

fn fingerprintCostModel(model: CostModel) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.cost_model.fingerprint");
    hashU64(&hasher, world_cost_model_fingerprint_version);
    hashU64(&hasher, model.session_step_cost);
    hashU64(&hasher, model.port_request_base_cost);
    hashU64(&hasher, model.port_response_base_cost);
    hashU64(&hasher, model.fresh_call_cost);
    hashU64(&hasher, model.replay_call_cost);
    hashU64(&hasher, model.verify_call_cost);
    hashU64(&hasher, model.failed_call_cost);
    hashU64(&hasher, model.rejected_call_cost);
    hashU64(&hasher, model.pending_call_cost);
    hashU64(&hasher, model.frame_byte_cost);
    hashU64(&hasher, model.value_image_byte_cost);
    hashU64(&hasher, model.checkpoint_cost);
    hashU64(&hasher, model.branch_cost);
    hashU64(&hasher, model.handoff_export_cost);
    hashU64(&hasher, model.handoff_accept_cost);
    hashU64(&hasher, model.per_port_costs.len);
    for (model.per_port_costs) |cost| {
        hashU64(&hasher, cost.world_port_id);
        hashOptionalU64(&hasher, cost.port_request_base_cost);
        hashOptionalU64(&hasher, cost.port_response_base_cost);
        hashOptionalU64(&hasher, cost.fresh_call_cost);
        hashOptionalU64(&hasher, cost.replay_call_cost);
        hashOptionalU64(&hasher, cost.verify_call_cost);
        hashOptionalU64(&hasher, cost.failed_call_cost);
        hashOptionalU64(&hasher, cost.rejected_call_cost);
        hashOptionalU64(&hasher, cost.pending_call_cost);
        hashOptionalU64(&hasher, cost.frame_byte_cost);
        hashOptionalU64(&hasher, cost.value_image_byte_cost);
    }
    return hasher.final();
}

fn fingerprintAllowedAdapterKinds(kinds: Supervision.AllowedAdapterKinds) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBool(&hasher, kinds.native);
    hashBool(&hasher, kinds.replay);
    hashBool(&hasher, kinds.verify);
    hashBool(&hasher, kinds.byte);
    hashBool(&hasher, kinds.null_reject);
    hashBool(&hasher, kinds.pending_stub);
    hashBool(&hasher, kinds.custom);
    return hasher.final();
}

fn fingerprintAllowedAuthorityKinds(kinds: Supervision.AllowedAuthorityKinds) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBool(&hasher, kinds.fixture);
    hashBool(&hasher, kinds.replay_source);
    hashBool(&hasher, kinds.native_function);
    hashBool(&hasher, kinds.byte_adapter);
    hashBool(&hasher, kinds.model_like);
    hashBool(&hasher, kinds.tool_like);
    hashBool(&hasher, kinds.file_like);
    hashBool(&hasher, kinds.human_like);
    hashBool(&hasher, kinds.custom);
    return hasher.final();
}

fn fingerprintAllowedModes(modes: Supervision.AllowedModes) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBool(&hasher, modes.fresh);
    hashBool(&hasher, modes.replay);
    hashBool(&hasher, modes.verify);
    hashBool(&hasher, modes.audit);
    return hasher.final();
}

fn fingerprintPortRule(rule: PortRule) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.port_rule.fingerprint");
    hashU64(&hasher, world_port_rule_fingerprint_version);
    hashU64(&hasher, rule.world_surface_fingerprint);
    hashU64(&hasher, rule.world_port_id);
    hashU64(&hasher, fingerprintAllowedAdapterKinds(rule.allowed_adapter_kinds));
    hashU64(&hasher, fingerprintAllowedAuthorityKinds(rule.allowed_authority_kinds));
    hashU64(&hasher, fingerprintAllowedModes(rule.allowed_modes));
    hashBool(&hasher, rule.allow_fresh);
    hashBool(&hasher, rule.allow_replay);
    hashBool(&hasher, rule.allow_verify);
    hashBool(&hasher, rule.allow_pending);
    hashBool(&hasher, rule.allow_reject);
    hashBool(&hasher, rule.allow_fail);
    hashBool(&hasher, rule.require_portable_values);
    hashOptionalU64(&hasher, rule.max_payload_image_bytes);
    hashOptionalU64(&hasher, rule.max_response_image_bytes);
    hashOptionalU64(&hasher, rule.max_requests);
    hashOptionalU64(&hasher, rule.max_cost_units);
    return hasher.final();
}

fn fingerprintRunPermit(permit: RunPermit) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.run_permit.fingerprint");
    hashU64(&hasher, world_run_permit_fingerprint_version);
    hashU64(&hasher, permit.target_ref_fingerprint);
    hashU64(&hasher, permit.world_surface_fingerprint);
    hashU64(&hasher, permit.target_certificate_fingerprint);
    hashU64(&hasher, permit.environment_certificate_fingerprint);
    hashU64(&hasher, permit.binding_plan_fingerprint);
    hashU64(&hasher, @intFromEnum(permit.mode));
    hashBool(&hasher, permit.transcript_image_available);
    if (permit.admission_receipt_fingerprint) |fingerprint| {
        hashBytes(&hasher, "admission_receipt_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    if (permit.module_ref_fingerprint) |fingerprint| {
        hashBytes(&hasher, "module_ref_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    hashU64(&hasher, permit.supervision_policy_fingerprint);
    hashU64(&hasher, permit.budget_fingerprint);
    hashU64(&hasher, permit.cost_model_fingerprint);
    hashU64(&hasher, @intFromEnum(permit.branch_policy));
    hashU64(&hasher, @intFromEnum(permit.handoff_policy));
    hashU64(&hasher, permit.metadata.len);
    hashBytes(&hasher, permit.metadata);
    hashU64(&hasher, permit.label.len);
    hashBytes(&hasher, permit.label);
    hashU64(&hasher, permit.port_rules.len);
    for (permit.port_rules) |rule| hashU64(&hasher, rule.rule_fingerprint);
    return hasher.final();
}

fn fingerprintUsageLedger(ledger: UsageLedger) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.usage_ledger.fingerprint");
    hashU64(&hasher, world_usage_ledger_fingerprint_version);
    hashU64(&hasher, ledger.run_permit_fingerprint);
    hashU64(&hasher, ledger.target_ref_fingerprint);
    hashU64(&hasher, ledger.environment_certificate_fingerprint);
    hashU64(&hasher, ledger.total_session_steps);
    hashU64(&hasher, ledger.total_port_requests);
    hashU64(&hasher, ledger.total_port_responses);
    hashU64(&hasher, ledger.total_fresh_calls);
    hashU64(&hasher, ledger.total_replay_calls);
    hashU64(&hasher, ledger.total_verify_calls);
    hashU64(&hasher, ledger.total_failed_calls);
    hashU64(&hasher, ledger.total_rejected_calls);
    hashU64(&hasher, ledger.total_pending_calls);
    hashU64(&hasher, ledger.total_frame_request_bytes);
    hashU64(&hasher, ledger.total_frame_response_bytes);
    hashU64(&hasher, ledger.total_value_image_bytes);
    hashU64(&hasher, ledger.total_transcript_events);
    hashU64(&hasher, ledger.total_transcript_image_bytes);
    hashU64(&hasher, ledger.total_checkpoints);
    hashU64(&hasher, ledger.total_branches);
    hashU64(&hasher, ledger.total_handoff_exports);
    hashU64(&hasher, ledger.total_handoff_accepts);
    hashU64(&hasher, ledger.total_cost_units);
    hashU64(&hasher, ledger.per_port_usage.len);
    for (ledger.per_port_usage) |usage| {
        hashU64(&hasher, usage.world_port_id);
        hashU64(&hasher, usage.requests);
        hashU64(&hasher, usage.responses);
        hashU64(&hasher, usage.fresh_calls);
        hashU64(&hasher, usage.replay_calls);
        hashU64(&hasher, usage.verify_calls);
        hashU64(&hasher, usage.failed_calls);
        hashU64(&hasher, usage.rejected_calls);
        hashU64(&hasher, usage.pending_calls);
        hashU64(&hasher, usage.response_bytes);
        hashU64(&hasher, usage.value_image_bytes);
        hashU64(&hasher, usage.cost_units);
    }
    if (ledger.exceeded_budget) |exceeded| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(exceeded));
    } else {
        hashBool(&hasher, false);
    }
    return hasher.final();
}

fn fingerprintSupervisionCheck(check: SupervisionCheck) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.supervision_check.fingerprint");
    hashU64(&hasher, world_supervision_check_fingerprint_version);
    hashU64(&hasher, check.run_permit_fingerprint);
    hashU64(&hasher, @intFromEnum(check.event_kind));
    hashOptionalU32(&hasher, check.world_port_id);
    hashU64(&hasher, check.usage_before_fingerprint);
    hashU64(&hasher, check.usage_after_fingerprint);
    hashBool(&hasher, check.allowed);
    if (check.blocker) |blocker| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(blocker));
    } else {
        hashBool(&hasher, false);
    }
    if (check.budget_exceeded) |exceeded| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(exceeded));
    } else {
        hashBool(&hasher, false);
    }
    hashOptionalU64(&hasher, check.rule_fingerprint);
    hashOptionalU64(&hasher, check.budget_fingerprint);
    hashU64(&hasher, check.summary.len);
    hashBytes(&hasher, check.summary);
    return hasher.final();
}

fn fingerprintRunReceipt(receipt: RunReceipt) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.run_receipt.fingerprint");
    hashU64(&hasher, world_run_receipt_fingerprint_version);
    hashU64(&hasher, receipt.run_permit_fingerprint);
    hashU64(&hasher, receipt.environment_certificate_fingerprint);
    hashU64(&hasher, receipt.target_ref_fingerprint);
    hashOptionalU64(&hasher, receipt.run_image_fingerprint);
    hashOptionalU64(&hasher, receipt.transcript_image_fingerprint);
    if (receipt.admission_receipt_fingerprint) |fingerprint| {
        hashBytes(&hasher, "admission_receipt_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    if (receipt.module_ref_fingerprint) |fingerprint| {
        hashBytes(&hasher, "module_ref_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    hashU64(&hasher, receipt.usage_ledger_fingerprint);
    hashU64(&hasher, receipt.final_run_state_fingerprint);
    hashU64(&hasher, @intFromEnum(receipt.final_status));
    if (receipt.exceeded_budget) |exceeded| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(exceeded));
    } else {
        hashBool(&hasher, false);
    }
    if (receipt.blocker) |blocker| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(blocker));
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, receipt.warning_count);
    hashU64(&hasher, receipt.total_session_steps);
    hashU64(&hasher, receipt.total_port_requests);
    hashU64(&hasher, receipt.total_port_responses);
    hashU64(&hasher, receipt.total_cost_units);
    hashU64(&hasher, receipt.branch_count);
    hashU64(&hasher, receipt.checkpoint_count);
    hashU64(&hasher, receipt.handoff_export_count);
    hashU64(&hasher, receipt.handoff_accept_count);
    return hasher.final();
}

fn fingerprintRunState(state: RunState) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.run_state.fingerprint");
    hashU64(&hasher, world_run_state_fingerprint_version);
    hashU64(&hasher, state.target_ref_fingerprint);
    hashOptionalU64(&hasher, state.transcript_image_fingerprint);
    hashU64(&hasher, state.branch_id);
    hashOptionalU64(&hasher, state.checkpoint_fingerprint);
    hashOptionalU64(&hasher, state.pending_request_fingerprint);
    hashOptionalU64(&hasher, state.final_response_fingerprint);
    hashOptionalU64(&hasher, state.final_value_image_fingerprint);
    hashU64(&hasher, state.turn_index);
    hashU64(&hasher, @intFromEnum(state.status));
    return hasher.final();
}

fn fingerprintRunHandle(handle: RunHandle) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.run_handle.fingerprint");
    hashU64(&hasher, world_run_handle_fingerprint_version);
    hashU64(&hasher, handle.runspace_fingerprint);
    hashU64(&hasher, handle.local_run_id);
    hashU64(&hasher, handle.target_ref_fingerprint);
    hashOptionalU64(&hasher, handle.admission_receipt_fingerprint);
    hashOptionalU64(&hasher, handle.permit_fingerprint);
    hashOptionalU64(&hasher, handle.branch_id);
    hashU64(&hasher, handle.generation);
    return hasher.final();
}

fn fingerprintRunspaceConfig(config: Runspace.Config, runspace_instance_id: u64) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.runspace.config.fingerprint");
    hashU64(&hasher, world_runspace_config_fingerprint_version);
    hashU64(&hasher, runspace_instance_id);
    hashU64(&hasher, @intFromEnum(config.policy));
    hashOptionalU64(&hasher, config.max_runs);
    hashOptionalU64(&hasher, config.max_pending_ports);
    hashOptionalU64(&hasher, config.max_events);
    hashBool(&hasher, config.preserve_completed_runs);
    hashBool(&hasher, config.require_supervision);
    hashBool(&hasher, config.require_admission);
    hashBool(&hasher, config.allow_direct_target_install);
    hashBool(&hasher, config.allow_handoff_install);
    hashBool(&hasher, config.allow_replay_install);
    hashBool(&hasher, config.auto_dispatch);
    return hasher.final();
}

fn fingerprintPendingPort(pending_port: PendingPort) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.pending_port.fingerprint");
    hashU64(&hasher, world_pending_port_fingerprint_version);
    hashU64(&hasher, pending_port.handle.handle_fingerprint);
    hashU64(&hasher, pending_port.mailbox_id);
    hashU64(&hasher, pending_port.world_surface_fingerprint);
    hashU64(&hasher, pending_port.target_certificate_fingerprint);
    hashU64(&hasher, pending_port.world_port_id);
    hashU64(&hasher, pending_port.request_fingerprint);
    hashU64(&hasher, pending_port.request_frame_fingerprint);
    hashU64(&hasher, @intFromEnum(pending_port.expected_response_kind));
    hashOptionalU32(&hasher, pending_port.expected_response_value_table_id);
    hashU64(&hasher, pending_port.residual_site_index);
    hashU64(&hasher, pending_port.residual_site_fingerprint);
    hashU64(&hasher, pending_port.target_ref_fingerprint);
    hashOptionalU64(&hasher, pending_port.environment_certificate_fingerprint);
    hashOptionalU64(&hasher, pending_port.run_permit_fingerprint);
    hashU64(&hasher, pending_port.turn_index);
    hashU64(&hasher, pending_port.inserted_event_index);
    hashU64(&hasher, @intFromEnum(pending_port.status));
    return hasher.final();
}

fn fingerprintRunspaceEvent(event: RunspaceEvent) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.runspace.event.fingerprint");
    hashU64(&hasher, world_runspace_event_fingerprint_version);
    hashU64(&hasher, @intFromEnum(event.kind));
    hashU64(&hasher, event.runspace_fingerprint);
    hashU64(&hasher, event.event_index);
    hashU64(&hasher, event.run_handle.handle_fingerprint);
    hashOptionalU64(&hasher, event.pending_port_fingerprint);
    hashOptionalU64(&hasher, event.request_frame_fingerprint);
    hashOptionalU64(&hasher, event.response_frame_fingerprint);
    hashOptionalU64(&hasher, event.checkpoint_fingerprint);
    hashU64(&hasher, event.run_state_fingerprint);
    hashOptionalU64(&hasher, event.run_receipt_fingerprint);
    hashOptionalU64(&hasher, event.admission_receipt_fingerprint);
    hashOptionalU64(&hasher, event.run_permit_fingerprint);
    hashU64(&hasher, event.summary.len);
    hashBytes(&hasher, event.summary);
    return hasher.final();
}

fn fingerprintRunImage(image: RunImage) u64 {
    return fingerprintRunImageVersioned(image, true);
}

fn fingerprintRunImageV1(image: RunImage) u64 {
    return fingerprintRunImageVersioned(image, false);
}

fn fingerprintRunImageV3(image: RunImage) u64 {
    return fingerprintRunImageVersionedWithModule(image, true, true);
}

fn fingerprintRunImageVersioned(image: RunImage, comptime include_prior_receipts: bool) u64 {
    return fingerprintRunImageVersionedWithModule(image, include_prior_receipts, false);
}

fn fingerprintRunImageVersionedWithModule(image: RunImage, comptime include_prior_receipts: bool, comptime include_module_refs: bool) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.run_image.fingerprint");
    hashU64(&hasher, world_run_image_fingerprint_version);
    hashU64(&hasher, @intFromEnum(image.kind));
    hashU64(&hasher, image.target_ref.target_ref_fingerprint);
    hashU64(&hasher, image.import_set_fingerprint);
    hashOptionalU64(&hasher, if (image.transcript_image) |transcript| transcript.transcript_image_fingerprint else null);
    hashU64(&hasher, image.current_state.run_state_fingerprint);
    hashU64(&hasher, image.checkpoints.len);
    for (image.checkpoints) |checkpoint| hashU64(&hasher, checkpoint.checkpoint_fingerprint);
    hashU64(&hasher, image.branches.len);
    for (image.branches) |branch| hashU64(&hasher, branch.fingerprint());
    hashOptionalU64(&hasher, if (image.pending_request_frame) |frame| frame.frame_fingerprint else null);
    hashOptionalU64(&hasher, if (image.final_result_image) |value| value.value_image_fingerprint else null);
    hashOptionalU64(&hasher, image.environment_certificate_fingerprint);
    hashOptionalU64(&hasher, image.acceptance_report_fingerprint);
    hashOptionalU64(&hasher, image.audit_image_fingerprint);
    if (include_prior_receipts) {
        hashOptionalU64(&hasher, image.prior_run_permit_fingerprint);
        hashOptionalU64(&hasher, image.prior_run_receipt_fingerprint);
    }
    if (include_module_refs) {
        hashOptionalU64(&hasher, image.module_ref_fingerprint);
        hashOptionalU64(&hasher, image.boundary_module_fingerprint);
        hashOptionalU64(&hasher, image.module_image_fingerprint);
    }
    hashU64(&hasher, image.metadata.len);
    hashBytes(&hasher, image.metadata);
    return hasher.final();
}

fn fingerprintModuleRef(module_ref: Admission.ModuleRef) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.module_ref.fingerprint");
    hashU64(&hasher, world_module_ref_fingerprint_version);
    hashU64(&hasher, module_ref.boundary_module_fingerprint);
    hashU64(&hasher, @intFromEnum(module_ref.module_kind));
    hashU64(&hasher, module_ref.target_ref_fingerprint);
    hashU64(&hasher, module_ref.world_surface_fingerprint);
    hashU64(&hasher, module_ref.target_certificate_fingerprint);
    hashOptionalU64(&hasher, module_ref.residual_program_plan_hash);
    hashOptionalU64(&hasher, module_ref.import_surface_fingerprint);
    hashOptionalU64(&hasher, module_ref.export_surface_fingerprint);
    hashOptionalU64(&hasher, module_ref.module_graph_fingerprint);
    hashU64(&hasher, @intFromEnum(module_ref.normal_form_kind));
    hashU64(&hasher, module_ref.world_port_count);
    hashOptionalU64(&hasher, module_ref.world_port_table_fingerprint);
    hashOptionalU64(&hasher, module_ref.world_value_table_fingerprint);
    hashOptionalU64(&hasher, module_ref.world_dispatch_table_fingerprint);
    hashOptionalBytes(&hasher, module_ref.label);
    hashU64(&hasher, module_ref.metadata.len);
    hashBytes(&hasher, module_ref.metadata);
    return hasher.final();
}

fn fingerprintPackageManifest(manifest: Admission.PackageManifest) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.package_manifest.fingerprint");
    hashU64(&hasher, world_package_manifest_fingerprint_version);
    hashU64(&hasher, manifest.package_fingerprint);
    hashU64(&hasher, @intFromEnum(manifest.package_kind));
    hashOptionalU64(&hasher, manifest.target_ref_fingerprint);
    hashOptionalU64(&hasher, manifest.module_ref_fingerprint);
    hashOptionalU64(&hasher, manifest.module_image_fingerprint);
    hashOptionalU64(&hasher, manifest.run_image_fingerprint);
    hashOptionalU64(&hasher, manifest.transcript_image_fingerprint);
    hashU64(&hasher, manifest.checkpoint_count);
    hashU64(&hasher, manifest.branch_count);
    hashU64(&hasher, manifest.prior_receipt_count);
    hashU64(&hasher, @intFromEnum(manifest.requested_mode));
    hashU64(&hasher, manifest.summary_metadata.len);
    hashBytes(&hasher, manifest.summary_metadata);
    return hasher.final();
}

fn fingerprintTransferPackageContent(package: Admission.TransferPackage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.transfer_package.fingerprint");
    hashU64(&hasher, world_transfer_package_fingerprint_version);
    hashU64(&hasher, @intFromEnum(package.kind));
    hashU64(&hasher, @intFromEnum(package.requested_mode));
    hashOptionalU64(&hasher, if (package.target_ref) |target_ref| target_ref.target_ref_fingerprint else null);
    hashOptionalU64(&hasher, if (package.module_ref) |module_ref| module_ref.module_ref_fingerprint else null);
    hashOptionalU64(&hasher, if (package.module_image_bytes) |bytes| moduleImageFingerprint(bytes) else null);
    hashOptionalU64(&hasher, if (package.run_image) |image| image.run_image_fingerprint else null);
    hashOptionalU64(&hasher, if (package.transcript_image) |image| image.transcript_image_fingerprint else null);
    hashU64(&hasher, package.checkpoint_refs.len);
    for (package.checkpoint_refs) |fingerprint| hashU64(&hasher, fingerprint);
    hashU64(&hasher, package.branch_refs.len);
    for (package.branch_refs) |fingerprint| hashU64(&hasher, fingerprint);
    hashU64(&hasher, package.prior_run_permit_refs.len);
    for (package.prior_run_permit_refs) |fingerprint| hashU64(&hasher, fingerprint);
    hashU64(&hasher, package.prior_run_receipt_refs.len);
    for (package.prior_run_receipt_refs) |fingerprint| hashU64(&hasher, fingerprint);
    hashOptionalU64(&hasher, package.requested_supervision_hint_fingerprint);
    hashU64(&hasher, package.metadata.len);
    hashBytes(&hasher, package.metadata);
    return hasher.final();
}

fn fingerprintTargetRegistryEntry(entry: Admission.TargetRegistry.Entry) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.target_registry.entry.fingerprint");
    hashU64(&hasher, world_target_registry_entry_fingerprint_version);
    hashU64(&hasher, entry.target_ref.target_ref_fingerprint);
    hashU64(&hasher, entry.world_surface_fingerprint);
    hashU64(&hasher, entry.target_certificate_fingerprint);
    hashOptionalU64(&hasher, entry.program_plan_hash);
    hashOptionalU64(&hasher, entry.import_surface_fingerprint);
    hashOptionalU64(&hasher, entry.export_surface_fingerprint);
    hashU64(&hasher, entry.import_set_fingerprint);
    hashU64(&hasher, entry.world_port_count);
    hashOptionalU64(&hasher, entry.world_port_table_fingerprint);
    hashOptionalU64(&hasher, entry.world_value_table_fingerprint);
    hashOptionalU64(&hasher, entry.world_dispatch_table_fingerprint);
    hashU64(&hasher, @intFromEnum(entry.normal_form_kind));
    hashOptionalBytes(&hasher, entry.label);
    hashU64(&hasher, entry.metadata.len);
    hashBytes(&hasher, entry.metadata);
    return hasher.final();
}

fn fingerprintTargetRegistry(registry: Admission.TargetRegistry) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.target_registry.fingerprint");
    hashU64(&hasher, world_target_registry_fingerprint_version);
    hashU64(&hasher, registry.entries.len);
    for (registry.entries) |entry| hashU64(&hasher, entry.entry_fingerprint);
    return hasher.final();
}

fn fingerprintTargetMatch(match: Admission.TargetMatch) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.target_match.fingerprint");
    hashU64(&hasher, world_target_match_fingerprint_version);
    hashOptionalU64(&hasher, match.transferred_target_ref_fingerprint);
    hashOptionalU64(&hasher, match.local_target_ref_fingerprint);
    hashBool(&hasher, match.matched);
    hashU64(&hasher, @intFromEnum(match.match_mode));
    hashU64(&hasher, match.mismatches.len);
    for (match.mismatches) |mismatch| hashU64(&hasher, @intFromEnum(mismatch));
    hashU64(&hasher, match.diagnostics.len);
    hashBytes(&hasher, match.diagnostics);
    return hasher.final();
}

fn fingerprintExportSummary(summary: Admission.ExportSummary) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.export_summary.fingerprint");
    hashU64(&hasher, world_export_summary_fingerprint_version);
    hashU64(&hasher, summary.target_ref_fingerprint);
    hashOptionalU64(&hasher, summary.module_ref_fingerprint);
    hashBool(&hasher, summary.main_export_present);
    hashOptionalU64(&hasher, summary.result_value_ref_fingerprint);
    hashU64(&hasher, summary.argument_value_ref_count);
    hashU64(&hasher, @intFromEnum(summary.normal_form_kind));
    hashOptionalBytes(&hasher, summary.target_label);
    hashBool(&hasher, summary.loaded_execution_supported);
    hashOptionalBytes(&hasher, summary.loaded_execution_unsupported_reason);
    return hasher.final();
}

fn fingerprintAdmissionPolicy(policy: Admission.AdmissionPolicy) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.admission_policy.fingerprint");
    hashU64(&hasher, world_admission_policy_fingerprint_version);
    hashBool(&hasher, policy.allow_reference_targets);
    hashBool(&hasher, policy.allow_full_modules);
    hashBool(&hasher, policy.allow_inspect_only_full_modules);
    hashBool(&hasher, policy.require_local_target_for_execution);
    hashBool(&hasher, policy.require_environment_preflight);
    hashBool(&hasher, policy.require_supervision_permit);
    hashBool(&hasher, policy.allow_continue_fresh);
    hashBool(&hasher, policy.allow_replay_without_environment);
    hashBool(&hasher, policy.allow_verify_without_fresh_environment);
    hashBool(&hasher, policy.allow_parked_resume);
    hashBool(&hasher, policy.allow_branch_resume);
    hashBool(&hasher, policy.allow_completed_replay);
    hashBool(&hasher, policy.reject_target_mismatch);
    hashBool(&hasher, policy.reject_module_mismatch);
    hashBool(&hasher, policy.reject_transcript_mismatch);
    hashBool(&hasher, policy.reject_prior_receipt_mismatch);
    hashU64(&hasher, policy.max_package_bytes);
    hashU64(&hasher, policy.max_module_bytes);
    hashU64(&hasher, policy.max_transcript_bytes);
    hashU64(&hasher, policy.max_branches);
    hashU64(&hasher, policy.max_checkpoints);
    return hasher.final();
}

fn fingerprintAdmissionRequest(request: Admission.AdmissionRequest) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.admission_request.fingerprint");
    hashU64(&hasher, world_admission_request_fingerprint_version);
    hashU64(&hasher, request.package_fingerprint);
    hashU64(&hasher, @intFromEnum(request.mode));
    hashU64(&hasher, request.policy_fingerprint);
    hashOptionalU64(&hasher, request.target_registry_fingerprint);
    hashOptionalU64(&hasher, request.environment_certificate_fingerprint);
    hashOptionalU64(&hasher, request.run_permit_fingerprint);
    hashOptionalU64(&hasher, request.requested_branch_id);
    hashOptionalU64(&hasher, request.requested_checkpoint_ref);
    hashU64(&hasher, request.metadata.len);
    hashBytes(&hasher, request.metadata);
    return hasher.final();
}

fn fingerprintAdmissionReport(report: Admission.AdmissionReport) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.admission_report.fingerprint");
    hashU64(&hasher, world_admission_report_fingerprint_version);
    hashBool(&hasher, report.accepted);
    hashU64(&hasher, @intFromEnum(report.mode));
    hashU64(&hasher, report.package_fingerprint);
    hashU64(&hasher, report.manifest_fingerprint);
    hashOptionalU64(&hasher, report.target_ref_fingerprint);
    hashOptionalU64(&hasher, report.module_ref_fingerprint);
    hashOptionalU64(&hasher, report.target_match_fingerprint);
    hashOptionalU64(&hasher, report.import_set_fingerprint);
    hashOptionalU64(&hasher, report.environment_acceptance_report_fingerprint);
    hashOptionalU64(&hasher, report.run_permit_fingerprint);
    hashOptionalU64(&hasher, report.handoff_preflight_report_fingerprint);
    hashU64(&hasher, report.blockers.len);
    for (report.blockers) |blocker| hashU64(&hasher, @intFromEnum(blocker));
    hashU64(&hasher, report.warnings.len);
    for (report.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
    hashU64(&hasher, report.summary.len);
    hashBytes(&hasher, report.summary);
    return hasher.final();
}

fn fingerprintAdmissionReceipt(receipt: Admission.AdmissionReceipt) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.admission_receipt.fingerprint");
    hashU64(&hasher, world_admission_receipt_fingerprint_version);
    hashU64(&hasher, receipt.admission_request_fingerprint);
    hashU64(&hasher, receipt.admission_report_fingerprint);
    hashU64(&hasher, receipt.package_fingerprint);
    hashU64(&hasher, receipt.target_ref_fingerprint);
    hashOptionalU64(&hasher, receipt.module_ref_fingerprint);
    hashOptionalU64(&hasher, receipt.local_target_ref_fingerprint);
    hashOptionalU64(&hasher, receipt.target_match_fingerprint);
    hashOptionalU64(&hasher, receipt.environment_certificate_fingerprint);
    hashOptionalU64(&hasher, receipt.run_permit_fingerprint);
    hashOptionalU64(&hasher, receipt.admitted_run_fingerprint);
    hashU64(&hasher, @intFromEnum(receipt.accepted_mode));
    hashU64(&hasher, receipt.warnings.len);
    for (receipt.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
    hashU64(&hasher, receipt.metadata.len);
    hashBytes(&hasher, receipt.metadata);
    return hasher.final();
}

fn fingerprintAdmittedRun(run: Admission.AdmittedRun) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.admitted_run.fingerprint");
    hashU64(&hasher, world_admitted_run_fingerprint_version);
    hashU64(&hasher, run.target_ref.target_ref_fingerprint);
    hashOptionalU64(&hasher, run.module_ref_fingerprint);
    hashOptionalU64(&hasher, run.import_set_fingerprint);
    hashOptionalU64(&hasher, run.environment_certificate_fingerprint);
    hashOptionalU64(&hasher, if (run.run_permit) |permit| permit.permit_fingerprint else null);
    hashOptionalU64(&hasher, if (run.run_image) |image| image.run_image_fingerprint else null);
    hashOptionalU64(&hasher, if (run.transcript_image) |image| image.transcript_image_fingerprint else null);
    hashOptionalU64(&hasher, run.selected_branch_id);
    hashOptionalU64(&hasher, run.selected_checkpoint_ref);
    hashU64(&hasher, @intFromEnum(run.mode));
    return hasher.final();
}

fn fingerprintValueImage(
    value_table_id: ?u32,
    boundary_value_fingerprint: ?u64,
    codec_schema_descriptor_fingerprint: ?u64,
    dynamic_size: bool,
    diagnostic_type_label: ?[]const u8,
    bytes: []const u8,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.value_image.fingerprint");
    hashU64(&hasher, world_frame_value_image_fingerprint_version);
    hashOptionalU32(&hasher, value_table_id);
    hashOptionalU64(&hasher, boundary_value_fingerprint);
    hashOptionalU64(&hasher, codec_schema_descriptor_fingerprint);
    hashBool(&hasher, dynamic_size);
    hashOptionalBytes(&hasher, diagnostic_type_label);
    hashU64(&hasher, bytes.len);
    hashBytes(&hasher, bytes);
    return hasher.final();
}

fn fingerprintTranscriptEventImage(event: TranscriptImage.EventImage) u64 {
    return fingerprintTranscriptEventImageForFormat(world_transcript_image_format_version, event);
}

fn fingerprintTranscriptEventImageForFormat(format_version: u32, event: TranscriptImage.EventImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.transcript.event_image.fingerprint");
    hashU64(&hasher, world_timeline_event_fingerprint_version);
    hashU64(&hasher, @intFromEnum(event.kind));
    hashU64(&hasher, event.world_surface_fingerprint);
    hashU64(&hasher, event.target_certificate_fingerprint);
    hashOptionalU32(&hasher, event.world_port_id);
    hashOptionalU64(&hasher, event.request_fingerprint);
    hashOptionalU64(&hasher, event.response_fingerprint);
    if (event.response_kind) |kind| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(kind));
    } else {
        hashBool(&hasher, false);
    }
    hashOptionalU64(&hasher, event.replay_key);
    if (format_version >= 3) {
        hashOptionalU64(&hasher, event.admission_request_fingerprint);
        hashOptionalU64(&hasher, event.admission_report_fingerprint);
        hashOptionalU64(&hasher, event.admission_receipt_fingerprint);
        hashOptionalU64(&hasher, event.module_ref_fingerprint);
        hashOptionalU64(&hasher, event.target_match_fingerprint);
    }
    if (event.turn_index) |turn| {
        hashBool(&hasher, true);
        hashU64(&hasher, turn);
    } else {
        hashBool(&hasher, false);
    }
    if (event.residual_site_index) |site| {
        hashBool(&hasher, true);
        hashU64(&hasher, site);
    } else {
        hashBool(&hasher, false);
    }
    hashOptionalU64(&hasher, event.residual_site_fingerprint);
    if (event.status) |status| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(status));
    } else {
        hashBool(&hasher, false);
    }
    hashBool(&hasher, event.source_run);
    if (event.request_frame) |frame| {
        hashBool(&hasher, true);
        hashU64(&hasher, frame.frame_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    if (event.response_frame) |frame| {
        hashBool(&hasher, true);
        hashU64(&hasher, frame.frame_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    return hasher.final();
}

fn fingerprintTranscriptImage(image: TranscriptImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.transcript.image.fingerprint");
    hashU64(&hasher, world_transcript_image_fingerprint_version);
    hashU64(&hasher, image.world_surface_fingerprint);
    hashU64(&hasher, image.target_certificate_fingerprint);
    hashU64(&hasher, @intFromEnum(image.final_status));
    hashU64(&hasher, image.response_count);
    hashU64(&hasher, image.events.len);
    for (image.events) |event| hashU64(&hasher, event.event_fingerprint);
    return hasher.final();
}

fn fingerprintTimelineEvent(event: Timeline.Event) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.timeline.event.fingerprint");
    hashU64(&hasher, world_timeline_event_fingerprint_version);
    hashU64(&hasher, @intFromEnum(event.kind));
    hashU64(&hasher, event.world_surface_fingerprint);
    hashU64(&hasher, event.target_certificate_fingerprint);
    hashOptionalU64(&hasher, event.request_frame_fingerprint);
    hashOptionalU64(&hasher, event.response_frame_fingerprint);
    hashOptionalU64(&hasher, event.replay_key);
    hashOptionalU64(&hasher, event.checkpoint_fingerprint);
    hashOptionalU64(&hasher, event.branch_id);
    hashOptionalU64(&hasher, event.run_permit_fingerprint);
    hashOptionalU64(&hasher, event.supervision_check_fingerprint);
    hashOptionalU64(&hasher, event.usage_ledger_fingerprint);
    hashOptionalU64(&hasher, event.run_receipt_fingerprint);
    if (event.admission_receipt_fingerprint) |fingerprint| {
        hashBytes(&hasher, "admission_receipt_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    if (event.module_ref_fingerprint) |fingerprint| {
        hashBytes(&hasher, "module_ref_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    if (event.target_match_fingerprint) |fingerprint| {
        hashBytes(&hasher, "target_match_fingerprint");
        hashU64(&hasher, fingerprint);
    }
    if (event.blocker_tag) |blocker| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(blocker));
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, event.turn_index);
    if (event.status) |status| {
        hashBool(&hasher, true);
        hashU64(&hasher, @intFromEnum(status));
    } else {
        hashBool(&hasher, false);
    }
    return hasher.final();
}

fn fingerprintCheckpoint(checkpoint: Timeline.Checkpoint) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.timeline.checkpoint.fingerprint");
    hashU64(&hasher, world_timeline_checkpoint_fingerprint_version);
    hashU64(&hasher, checkpoint.world_surface_fingerprint);
    hashU64(&hasher, checkpoint.target_certificate_fingerprint);
    hashU64(&hasher, checkpoint.event_index);
    hashU64(&hasher, checkpoint.turn_index);
    hashOptionalU64(&hasher, checkpoint.current_request_fingerprint);
    hashOptionalU64(&hasher, checkpoint.last_response_fingerprint);
    hashOptionalU64(&hasher, checkpoint.capsule_image_fingerprint);
    hashU64(&hasher, checkpoint.transcript_prefix_fingerprint);
    hashU64(&hasher, checkpoint.branch_id);
    hashU64(&hasher, @intFromEnum(checkpoint.status));
    return hasher.final();
}

fn fingerprintAuditImage(image: AuditImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.audit.image.fingerprint");
    hashU64(&hasher, world_audit_image_fingerprint_version);
    hashU64(&hasher, image.world_surface_fingerprint);
    hashU64(&hasher, image.target_certificate_fingerprint);
    hashU64(&hasher, @intFromEnum(image.mode));
    hashU64(&hasher, @intFromEnum(image.final_status));
    hashU64(&hasher, image.request_frame_count);
    hashU64(&hasher, image.response_frame_count);
    hashU64(&hasher, image.replayed_frame_count);
    hashU64(&hasher, image.verified_frame_count);
    hashU64(&hasher, image.failed_frame_count);
    hashU64(&hasher, image.branch_count);
    hashU64(&hasher, image.checkpoint_count);
    hashU64(&hasher, image.missing_portable_value_image_count);
    hashU64(&hasher, image.native_only_value_count);
    hashOptionalU64(&hasher, image.transcript_image_fingerprint);
    return hasher.final();
}

fn fingerprintRequest(frame: Frame.Request) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.request.fingerprint");
    hashU64(&hasher, world_frame_request_fingerprint_version);
    hashU64(&hasher, frame.world_surface_fingerprint);
    hashOptionalU64(&hasher, frame.world_surface_replay_scope_fingerprint);
    hashU64(&hasher, frame.target_certificate_fingerprint);
    hashU64(&hasher, frame.world_port_id);
    hashU64(&hasher, frame.residual_site_index);
    hashU64(&hasher, frame.residual_site_fingerprint);
    hashU64(&hasher, frame.request_fingerprint);
    hashU64(&hasher, frame.turn_index);
    hashOptionalU32(&hasher, frame.payload_value_table_id);
    hashOptionalU32(&hasher, frame.expected_response_value_table_id);
    hashOptionalU64(&hasher, frame.payload_value_fingerprint);
    if (frame.payload_image) |image| {
        hashBool(&hasher, true);
        hashU64(&hasher, image.value_image_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, frame.replay_key_seed.world_surface_fingerprint);
    hashU64(&hasher, frame.replay_key_seed.world_surface_scope_fingerprint);
    hashU64(&hasher, frame.replay_key_seed.world_port_id);
    hashU64(&hasher, frame.replay_key_seed.request_fingerprint);
    hashOptionalU64(&hasher, frame.source_effect_shape_fingerprint);
    hashOptionalU64(&hasher, frame.world_port_ref_fingerprint);
    hashOptionalU64(&hasher, frame.trace_ref_fingerprint);
    hashOptionalU64(&hasher, frame.evidence_ref_fingerprint);
    hashU64(&hasher, frame.flags);
    return hasher.final();
}

fn fingerprintResponse(frame: Frame.Response) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.frame.response.fingerprint");
    hashU64(&hasher, world_frame_response_fingerprint_version);
    hashU64(&hasher, frame.world_surface_fingerprint);
    hashU64(&hasher, frame.target_certificate_fingerprint);
    hashU64(&hasher, frame.world_port_id);
    hashU64(&hasher, frame.request_fingerprint);
    hashU64(&hasher, @intFromEnum(frame.response_kind));
    hashOptionalU32(&hasher, frame.response_value_table_id);
    hashU64(&hasher, frame.response_fingerprint);
    hashOptionalU64(&hasher, frame.response_value_fingerprint);
    if (frame.response_image) |image| {
        hashBool(&hasher, true);
        hashU64(&hasher, image.value_image_fingerprint);
    } else {
        hashBool(&hasher, false);
    }
    hashU64(&hasher, frame.replay_key);
    hashU64(&hasher, @intFromEnum(frame.status));
    hashOptionalBytes(&hasher, frame.error_tag);
    hashOptionalBytes(&hasher, frame.reason);
    hashU64(&hasher, frame.flags);
    return hasher.final();
}

fn portableValueDynamicByteLowerBound(comptime Value: type, value: Value) usize {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) break :blk value.len;
            if (comptime isStringList(Value)) {
                var total: usize = 0;
                for (value) |item| total += item.len;
                break :blk total;
            }
            break :blk 0;
        },
        .optional => |optional| if (value) |payload|
            portableValueDynamicByteLowerBound(optional.child, payload)
        else
            0,
        .@"struct" => |info| blk: {
            var total: usize = 0;
            inline for (info.fields) |field| {
                total += portableValueDynamicByteLowerBound(field.type, @field(value, field.name));
            }
            break :blk total;
        },
        .@"union" => |union_info| blk: {
            const Tag = union_info.tag_type orelse break :blk 0;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type == void) break :blk 0;
                    break :blk portableValueDynamicByteLowerBound(field.type, @field(value, field.name));
                }
            }
            break :blk 0;
        },
        else => 0,
    };
}

fn encodePortableValue(comptime Value: type, allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: Value) !void {
    switch (@typeInfo(Value)) {
        .void => {},
        .bool => try writeBool(out, allocator, value),
        .int => {
            const info = @typeInfo(Value).int;
            if (info.bits > 64) return error.UnsupportedValueImage;
            if (info.signedness == .signed) {
                try writeI64(out, allocator, @intCast(value));
            } else {
                try writeU64(out, allocator, @intCast(value));
            }
        },
        .comptime_int => {
            if (value < 0) {
                try writeI64(out, allocator, @as(i64, value));
            } else {
                try writeU64(out, allocator, @as(u64, value));
            }
        },
        .float, .comptime_float => {
            if (Value == f32) {
                try writeU32(out, allocator, @as(u32, @bitCast(value)));
            } else if (Value == f64) {
                try writeU64(out, allocator, @as(u64, @bitCast(value)));
            } else {
                return error.UnsupportedValueImage;
            }
        },
        .@"enum" => |info| {
            const Tag = info.tag_type;
            if (@bitSizeOf(Tag) > 64) return error.UnsupportedValueImage;
            if (@typeInfo(Tag).int.signedness == .signed) {
                try writeI64(out, allocator, @as(i64, @intCast(@intFromEnum(value))));
            } else {
                try writeU64(out, allocator, @as(u64, @intCast(@intFromEnum(value))));
            }
        },
        .pointer => |pointer| {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                try writeBytes(out, allocator, value);
                return;
            }
            if (comptime isStringList(Value)) {
                try writeU64(out, allocator, value.len);
                for (value) |item| try writeBytes(out, allocator, item);
                return;
            }
            return error.UnsupportedValueImage;
        },
        .optional => |optional| {
            if (value) |payload| {
                try writeBool(out, allocator, true);
                try encodePortableValue(optional.child, allocator, out, payload);
            } else {
                try writeBool(out, allocator, false);
            }
        },
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                try encodePortableValue(field.type, allocator, out, @field(value, field.name));
            }
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return error.UnsupportedValueImage;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields, 0..) |field, field_index| {
                if (active_tag == @field(Tag, field.name)) {
                    try writeU32(out, allocator, @as(u32, @intCast(field_index)));
                    if (field.type != void) {
                        try encodePortableValue(field.type, allocator, out, @field(value, field.name));
                    }
                    return;
                }
            }
            unreachable;
        },
        else => return error.UnsupportedValueImage,
    }
}

fn decodePortableValue(comptime Value: type, allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Value {
    return switch (@typeInfo(Value)) {
        .void => {},
        .bool => try readBool(bytes, cursor),
        .int => blk: {
            const info = @typeInfo(Value).int;
            if (info.bits > 64) return error.UnsupportedValueImage;
            if (info.signedness == .signed) {
                const raw = try readI64(bytes, cursor);
                break :blk std.math.cast(Value, raw) orelse return error.InvalidFrameEncoding;
            }
            const raw = try readU64(bytes, cursor);
            break :blk std.math.cast(Value, raw) orelse return error.InvalidFrameEncoding;
        },
        .comptime_int => return error.UnsupportedValueImage,
        .float, .comptime_float => blk: {
            if (Value == f32) {
                break :blk @as(f32, @bitCast(try readU32(bytes, cursor)));
            } else if (Value == f64) {
                break :blk @as(f64, @bitCast(try readU64(bytes, cursor)));
            }
            return error.UnsupportedValueImage;
        },
        .@"enum" => |info| blk: {
            const Tag = info.tag_type;
            if (@typeInfo(Tag).int.signedness == .signed) {
                const raw = try readI64(bytes, cursor);
                inline for (info.fields) |field| {
                    if (field.value == raw) break :blk @as(Value, @enumFromInt(raw));
                }
            } else {
                const raw = try readU64(bytes, cursor);
                inline for (info.fields) |field| {
                    if (field.value == raw) break :blk @as(Value, @enumFromInt(raw));
                }
            }
            return error.InvalidFrameEncoding;
        },
        .pointer => |pointer| blk: {
            if (comptime pointer.size == .slice and pointer.child == u8) {
                break :blk try readBytesOwned(allocator, bytes, cursor);
            }
            if (comptime isStringList(Value)) {
                const len = try readU64AsUsize(bytes, cursor);
                if (len > (bytes.len - cursor.*) / 8) return error.InvalidFrameEncoding;
                const Child = @typeInfo(Value).pointer.child;
                const result = try allocator.alloc(Child, len);
                errdefer allocator.free(result);
                var initialized: usize = 0;
                errdefer for (result[0..initialized]) |item| allocator.free(@constCast(item));
                for (result) |*item| {
                    item.* = try readBytesOwned(allocator, bytes, cursor);
                    initialized += 1;
                }
                break :blk result;
            }
            return error.UnsupportedValueImage;
        },
        .optional => |optional| blk: {
            if (!try readBool(bytes, cursor)) break :blk null;
            const payload = try decodePortableValue(optional.child, allocator, bytes, cursor);
            break :blk payload;
        },
        .@"struct" => |info| blk: {
            var result: Value = undefined;
            var initialized_fields: usize = 0;
            errdefer inline for (info.fields, 0..) |field, field_index| {
                if (field_index < initialized_fields) {
                    deinitOwnedValue(allocator, @field(result, field.name));
                }
            };
            inline for (info.fields) |field| {
                @field(result, field.name) = try decodePortableValue(field.type, allocator, bytes, cursor);
                initialized_fields += 1;
            }
            break :blk result;
        },
        .@"union" => |union_info| blk: {
            _ = union_info.tag_type orelse return error.UnsupportedValueImage;
            const field_index = try readU32(bytes, cursor);
            inline for (union_info.fields, 0..) |field, index| {
                if (field_index == index) {
                    if (field.type == void) break :blk @unionInit(Value, field.name, {});
                    const payload = try decodePortableValue(field.type, allocator, bytes, cursor);
                    errdefer deinitOwnedValue(allocator, payload);
                    break :blk @unionInit(Value, field.name, payload);
                }
            }
            return error.InvalidFrameEncoding;
        },
        else => return error.UnsupportedValueImage,
    };
}

fn valueIsDynamic(comptime Value: type) bool {
    return switch (@typeInfo(Value)) {
        .pointer => |pointer| pointer.size == .slice,
        .optional => |optional| valueIsDynamic(optional.child),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (valueIsDynamic(field.type)) return true;
            }
            return false;
        },
        .@"union" => |info| {
            inline for (info.fields) |field| {
                if (valueIsDynamic(field.type)) return true;
            }
            return false;
        },
        else => false,
    };
}

fn writeU8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
    try out.append(allocator, value);
}

fn writeBool(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: bool) !void {
    try writeU8(out, allocator, if (value) 1 else 0);
}

fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, @intCast(value), .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeI64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i64) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(i64, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}

fn writeOptionalU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u32) !void {
    if (value) |present| {
        try writeBool(out, allocator, true);
        try writeU32(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    if (value) |present| {
        try writeBool(out, allocator, true);
        try writeU64(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    if (bytes.len > world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
    try writeU64(out, allocator, bytes.len);
    try out.appendSlice(allocator, bytes);
}

fn writeOptionalBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: ?[]const u8) !void {
    if (bytes) |present| {
        try writeBool(out, allocator, true);
        try writeBytes(out, allocator, present);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn writeOptionalValueImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, image: ?Frame.ValueImage) !void {
    if (image) |present| {
        try writeBool(out, allocator, true);
        const encoded = try present.encode(allocator);
        defer allocator.free(encoded);
        try writeBytes(out, allocator, encoded);
    } else {
        try writeBool(out, allocator, false);
    }
}

fn readU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn readBool(bytes: []const u8, cursor: *usize) !bool {
    return switch (try readU8(bytes, cursor)) {
        0 => false,
        1 => true,
        else => error.InvalidFrameEncoding,
    };
}

fn readU32(bytes: []const u8, cursor: *usize) !u32 {
    if (bytes.len - cursor.* < 4) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u32, bytes[cursor.*..][0..4], .little);
    cursor.* += 4;
    return value;
}

fn readU64(bytes: []const u8, cursor: *usize) !u64 {
    if (bytes.len - cursor.* < 8) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(u64, bytes[cursor.*..][0..8], .little);
    cursor.* += 8;
    return value;
}

fn readI64(bytes: []const u8, cursor: *usize) !i64 {
    if (bytes.len - cursor.* < 8) return error.InvalidFrameEncoding;
    const value = std.mem.readInt(i64, bytes[cursor.*..][0..8], .little);
    cursor.* += 8;
    return value;
}

fn readU64AsUsize(bytes: []const u8, cursor: *usize) !usize {
    return std.math.cast(usize, try readU64(bytes, cursor)) orelse error.InvalidFrameEncoding;
}

fn readOptionalU32(bytes: []const u8, cursor: *usize) !?u32 {
    if (!try readBool(bytes, cursor)) return null;
    return try readU32(bytes, cursor);
}

fn readOptionalU64(bytes: []const u8, cursor: *usize) !?u64 {
    if (!try readBool(bytes, cursor)) return null;
    return try readU64(bytes, cursor);
}

fn readOptionalUsize(bytes: []const u8, cursor: *usize) !?usize {
    if (!try readBool(bytes, cursor)) return null;
    return try readU64AsUsize(bytes, cursor);
}

fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]u8 {
    const len = try readU64AsUsize(bytes, cursor);
    if (len > world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
    if (len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
    const result = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + len]);
    cursor.* += len;
    return result;
}

fn readOptionalBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?[]const u8 {
    if (!try readBool(bytes, cursor)) return null;
    return try readBytesOwned(allocator, bytes, cursor);
}

fn readOptionalValueImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?Frame.ValueImage {
    if (!try readBool(bytes, cursor)) return null;
    const encoded = try readBytesOwned(allocator, bytes, cursor);
    defer allocator.free(encoded);
    return try Frame.ValueImage.decode(allocator, encoded);
}

fn enumFromByte(comptime Enum: type, value: u8) !Enum {
    inline for (@typeInfo(Enum).@"enum".fields) |field| {
        if (field.value == value) return @as(Enum, @enumFromInt(value));
    }
    return error.InvalidFrameEncoding;
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    hasher.update(&buffer);
}

fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
    hashU64(hasher, @as(u8, if (value) 1 else 0));
}

fn hashOptionalU32(hasher: *std.hash.Wyhash, value: ?u32) void {
    if (value) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

fn hashOptionalU64(hasher: *std.hash.Wyhash, value: anytype) void {
    if (value) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

fn hashOptionalBytes(hasher: *std.hash.Wyhash, bytes: ?[]const u8) void {
    if (bytes) |present| {
        hashBool(hasher, true);
        hashU64(hasher, present.len);
        hashBytes(hasher, present);
    } else {
        hashBool(hasher, false);
    }
}

fn hashValuePolicy(hasher: *std.hash.Wyhash, policy: ValuePolicy) void {
    hashBool(hasher, policy.require_portable_values);
    hashBool(hasher, policy.allow_native_only_values);
    hashBool(hasher, policy.require_response_images_for_replay);
    hashBool(hasher, policy.allow_diagnostic_type_labels);
    hashOptionalU64(hasher, policy.max_value_image_bytes);
}

test {
    _ = Mode;
    _ = Transcript;
    _ = Machine;
}
