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
    VerifyMissingExpected,
    VerifyResponseKindMismatch,
    VerifyResponseFingerprintMismatch,
    VerifyValueImageMismatch,
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
};

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
pub const world_transcript_image_format_version: u32 = 1;
pub const world_transcript_image_fingerprint_version: u32 = 1;
pub const world_timeline_event_format_version: u32 = 1;
pub const world_timeline_event_fingerprint_version: u32 = 1;
pub const world_timeline_checkpoint_format_version: u32 = 1;
pub const world_timeline_checkpoint_fingerprint_version: u32 = 1;
pub const world_timeline_branch_format_version: u32 = 1;
pub const world_timeline_branch_fingerprint_version: u32 = 1;
pub const world_audit_image_format_version: u32 = 1;
pub const world_audit_image_fingerprint_version: u32 = 1;
pub const world_target_ref_format_version: u32 = 1;
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
pub const world_run_image_format_version: u32 = 1;
pub const world_run_image_fingerprint_version: u32 = 1;
pub const world_max_decoded_byte_field_len: usize = 16 * 1024 * 1024;
const frame_response_deferred_fingerprint_flag: u32 = 1 << 0;
const world_min_transcript_event_image_encoded_len: usize = 8 + 1 + 8 + 8 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1;

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
            if (event.kind != .port_responded and event.kind != .frame_responded) continue;
            if (event.status) |status| {
                if (status != .responded) return Error.ReplayMissing;
            }
            if (event.kind == .frame_responded and event.response_frame == null) return Error.ReplayMissing;
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
            if (self.events.items[index].kind == .port_responded or self.events.items[index].kind == .frame_responded) return Error.ReplayUnusedEvent;
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
                .frame_responded,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_replayed,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_replayed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
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
                .frame_responded,
                => {
                    if (active_start != null) {
                        active_has_port_event = true;
                        active_has_source_response = true;
                    }
                },
                .port_requested,
                .port_replayed,
                .port_rejected,
                .port_failed,
                .frame_requested,
                .frame_replayed,
                .frame_verified,
                .frame_rejected,
                .frame_failed,
                => {
                    if (active_start != null) active_has_port_event = true;
                },
                .checkpoint_recorded,
                .branch_started,
                .branch_joined,
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
        for (self.events) |event| try encodeTranscriptEventImage(&out, allocator, event);
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        var cursor: usize = 0;
        const format_version = try readU32(bytes, &cursor);
        if (format_version != world_transcript_image_format_version) return error.InvalidFrameEncoding;
        const fingerprint_version = try readU32(bytes, &cursor);
        if (fingerprint_version != world_transcript_image_fingerprint_version) return error.InvalidFrameEncoding;
        const transcript_image_fingerprint = try readU64(bytes, &cursor);
        const world_surface_fingerprint = try readU64(bytes, &cursor);
        const target_certificate_fingerprint = try readU64(bytes, &cursor);
        const final_status = try enumFromByte(FinalStatus, try readU8(bytes, &cursor));
        const response_count = try readU64AsUsize(bytes, &cursor);
        const event_count = try readU64AsUsize(bytes, &cursor);
        if (event_count > (bytes.len - cursor) / world_min_transcript_event_image_encoded_len) return error.InvalidFrameEncoding;
        const events = try allocator.alloc(EventImage, event_count);
        errdefer allocator.free(events);
        var initialized: usize = 0;
        errdefer for (events[0..initialized]) |*event| event.deinit(allocator);
        for (events) |*event| {
            event.* = try decodeTranscriptEventImage(allocator, bytes, &cursor);
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
            .metadata = args.metadata,
        };
        result.run_image_fingerprint = fingerprintRunImage(result);
        return result;
    }

    pub fn fromTranscriptImage(comptime Target: type, image: TranscriptImage, kind: Kind) @This() {
        const target_ref = TargetRef.fromTarget(Target);
        const import_set = ImportSet.fromTarget(Target);
        const state = RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .transcript_image_fingerprint = image.transcript_image_fingerprint,
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
        if (!options.allow_reference_target and self.kind == .reference_target_run) return error.InvalidFrameEncoding;
        if (self.metadata.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        if (self.target_ref.target_label) |label| {
            if (label.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        }
        if (self.target_ref.metadata.len > options.max_image_bytes) return error.InvalidFrameEncoding;
        if (self.checkpoints.len > options.max_checkpoints) return error.InvalidFrameEncoding;
        if (self.branches.len > options.max_branches) return error.InvalidFrameEncoding;
        const value_policy = valuePolicyForRunImageValidation(options);
        if (self.transcript_image) |image| {
            if (image.events.len > options.max_timeline_events) return error.InvalidFrameEncoding;
            if (image.world_surface_fingerprint != self.target_ref.world_surface_fingerprint) return error.TranscriptImageSurfaceMismatch;
            if (image.target_certificate_fingerprint != self.target_ref.target_certificate_fingerprint) return error.TargetCertificateMismatch;
            if (self.current_state.transcript_image_fingerprint != image.transcript_image_fingerprint) return error.HandoffTargetMismatch;
            switch (image.final_status) {
                .completed => if (self.current_state.status != .completed and self.current_state.status != .parked_on_port) return error.HandoffTargetMismatch,
                .failed => if (self.current_state.status != .failed and self.current_state.status != .parked_on_port) return error.HandoffTargetMismatch,
                .running => if (self.current_state.status != .running and self.current_state.status != .parked_on_port) return error.HandoffTargetMismatch,
            }
            try image.validateValuePolicy(value_policy);
        }
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
                if (frame.frame_fingerprint != fingerprint and frame.request_fingerprint != fingerprint) return error.HandoffPendingFrameMismatch;
            }
        }
        if (self.final_result_image) |image| {
            try validateValueImage(image);
            try validateValueImagePolicy(image, value_policy);
            if (self.current_state.final_value_image_fingerprint != image.value_image_fingerprint) return error.InvalidFrameEncoding;
        }
        if (fingerprintRunState(self.current_state) != self.current_state.run_state_fingerprint) return error.InvalidFrameEncoding;
        if (fingerprintRunImage(self) != self.run_image_fingerprint) return error.InvalidFrameEncoding;
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
        try writeBytes(&out, allocator, self.metadata);
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        if (bytes.len > world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
        var cursor: usize = 0;
        const format_version = try readU32(bytes, &cursor);
        if (format_version != world_run_image_format_version) return error.InvalidFrameEncoding;
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
        const metadata = try readBytesOwned(allocator, bytes, &cursor);
        errdefer allocator.free(metadata);
        if (cursor != bytes.len) return error.InvalidFrameEncoding;
        var result = @This(){
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

    pub fn preflight(self: *@This(), comptime Target: type, comptime Env: type, mode: HandoffMode) AcceptanceReport {
        if (!self.run_image.target_ref.matchesTarget(Target)) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffTargetMismatch});
        }
        if (self.run_image.import_set_fingerprint != Env.import_set.import_set_fingerprint) {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffTargetMismatch});
        }
        const has_transcript = self.run_image.transcript_image != null;
        const report = Env.acceptanceReport(modeToRunMode(mode), has_transcript);
        if (!report.accepted) return report;
        if (mode == .accept_fresh and
            (self.run_image.current_state.status != .parked_on_port or self.run_image.pending_request_frame == null))
        {
            return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.HandoffPendingFrameMismatch});
        }
        if (mode == .accept_fresh) {
            const pending_frame = self.run_image.pending_request_frame.?;
            validateRequestFramePolicy(pending_frame, valuePolicyForEnvironmentPort(Env, pending_frame.world_port_id, .request)) catch {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.NativeOnlyValueRejected});
            };
            if (self.run_image.transcript_image) |*image| {
                validateTranscriptImageForEnvironment(Env, image) catch {
                    return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.NativeOnlyValueRejected});
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
            validateTranscriptImageForEnvironment(Env, image) catch {
                return rejectedAcceptance(TargetRef.fromTarget(Target), modeToRunMode(mode), &.{.NativeOnlyValueRejected});
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
        if (mode != .accept_fresh) return Error.InvalidMode;
        const report = self.preflight(Target, Env, mode);
        if (!report.accepted) return acceptanceError(report);
        if (self.run_image.current_state.status != .parked_on_port) return error.HandoffPendingFrameMismatch;
        const pending_frame = self.run_image.pending_request_frame orelse return error.HandoffPendingFrameMismatch;
        const MachineType = Machine(Target, Env.machine_config);
        var run = try MachineType.startWithHandoffTranscript(runtime, args, options);
        errdefer run.deinit();
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
                        break;
                    }
                    const response = if (self.run_image.transcript_image) |*image|
                        image.nextResponse(request.replay_key_seed, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            run.audit.replay_mismatch_count += 1;
                            return err;
                        }
                    else
                        return error.HandoffPendingFrameMismatch;
                    try run.resumeReplayedFrame(response.*);
                },
                else => return error.HandoffPendingFrameMismatch,
            }
        }
        return run;
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

        pub fn startWithHandoffTranscript(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)) {
            return Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).startWithTranscriptAvailable(runtime, args, options, true);
        }

        pub fn run(runtime: anytype, args: anytype, options: anytype) !Run(@TypeOf(runtime), @TypeOf(args), @TypeOf(options)).Result {
            var run_state = try start(runtime, args, options);
            defer run_state.deinit();
            while (true) {
                const step = try run_state.next();
                switch (step) {
                    .done => |value| {
                        const audit = try run_state.snapshotAudit();
                        run_state.done_value_present = false;
                        return .{ .value = value, .audit = audit };
                    },
                    .port_required => run_state.dispatch() catch |err| {
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
                retained_values: std.ArrayList(StoredValue) = .empty,

                pub const Result = struct {
                    value: Value,
                    audit: AuditReport,

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

                fn markRunFailed(self: *Self) !void {
                    if (self.audit.final_status == .failed) return;
                    if (self.audit.final_status == .completed) return;
                    self.pending_request = null;
                    self.pending_port_id = null;
                    self.audit.final_status = .failed;
                    try appendRunEvent(Target, self.options, .run_failed, null, false);
                }

                fn start(runtime: RuntimePtr, args: anytype, options: Options) !Self {
                    return startWithTranscriptAvailable(runtime, args, options, false);
                }

                fn startWithTranscriptAvailable(runtime: RuntimePtr, args: anytype, options: Options, comptime handoff_transcript_available: bool) !Self {
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
                        !@hasField(Options, "transcript_image"))
                    {
                        return Error.ReplayMissing;
                    }
                    if (modeConsumesTranscript(effective) and
                        @hasField(Options, "transcript_image") and
                        ConfigPorts.len == 0 and
                        Target.WorldPortTable.entries.len != 0)
                    {
                        return Error.MissingHandler;
                    }
                    if (comptime @hasField(@TypeOf(Config), "environment")) {
                        const transcript_available = comptime handoff_transcript_available or
                            @hasField(Options, "transcript_image") or
                            (@hasField(Options, "transcript") and Config.environment.policy_decl.allow_native_adapters);
                        const report = Config.environment.acceptanceReport(effective, transcript_available);
                        if (!report.accepted) return acceptanceError(report);
                        if (modeConsumesTranscript(effective)) {
                            if (comptime @hasField(Options, "transcript_image")) {
                                try validateTranscriptImageForEnvironment(Config.environment, @field(options, "transcript_image"));
                            }
                            if (comptime @hasField(Options, "transcript")) {
                                try validateTranscriptForEnvironment(Config.environment, @field(options, "transcript"));
                            }
                        }
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
                    if (@hasField(Options, "transcript")) {
                        if (modeConsumesTranscript(effective) and !@hasField(Options, "transcript_image")) {
                            @field(options, "transcript").resetReplay();
                            try @field(options, "transcript").validateReplayRun(
                                Target.WorldSurface.surface_fingerprint,
                                Target.Certificate.certificate_fingerprint,
                            );
                        }
                        try appendRunEvent(Target, options, .run_started, null, effective == .fresh);
                    }
                    return .{
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
                    };
                }

                pub fn deinit(self: *Self) void {
                    if (self.done_value_present) {
                        deinitRunValue(self.allocator, self.done_value);
                        self.done_value_present = false;
                    }
                    self.session.deinit();
                    for (self.retained_values.items) |*value| value.deinit(self.allocator);
                    self.retained_values.deinit(self.allocator);
                    self.allocator.free(self.per_port_counts);
                }

                pub fn next(self: *Self) !Step {
                    if (self.audit.final_status == .completed) {
                        if (!self.done_value_present) return Error.HandlerFailed;
                        return .{ .done = self.done_value };
                    }
                    if (self.audit.final_status == .failed) return .failed;
                    if (self.pending_request != null) return .port_required;
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
                            if (modeConsumesTranscript(self.effective_mode) and @hasField(Options, "transcript") and !@hasField(Options, "transcript_image")) {
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
                            self.audit.final_status = .completed;
                            try appendRunEvent(Target, self.options, .run_completed, null, self.effective_mode == .fresh);
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
                            self.pending_request = request;
                            self.pending_port_id = world_port_id;
                            self.audit.port_request_count += 1;
                            self.per_port_counts[world_port_id] += 1;
                            if (self.effective_mode == .fresh) {
                                if (!self.frame_step_request) {
                                    try appendPortEvent(Target, self.options, .port_requested, world_port_id, trace, null, null, null, null, null);
                                }
                            }
                            return .port_required;
                        },
                    }
                }

                pub fn dispatch(self: *Self) !void {
                    if (self.audit.final_status == .failed) return Error.HandlerFailed;
                    const request = self.pending_request orelse return Error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return Error.UnknownWorldPort;
                    const trace = request.trace();
                    if (Target.WorldPortTable.entries.len == 0) return self.markMissingHandler(world_port_id, trace);
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                self.dispatchDecl(Decl, request) catch |err| {
                                    self.audit.failed_count += 1;
                                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null, null, null);
                                    try self.markRunFailed();
                                    return err;
                                };
                                self.pending_request = null;
                                self.pending_port_id = null;
                                return;
                            }
                            return self.markMissingHandler(world_port_id, trace);
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
                        .port_required => .{ .port_request = try self.pendingRequestFrame(!had_pending_request) },
                    };
                }

                pub fn resumeFrame(self: *Self, response_frame: Frame.Response) !void {
                    try self.resumeFrameWithProvenance(response_frame, false);
                }

                fn resumeReplayedFrame(self: *Self, response_frame: Frame.Response) !void {
                    try self.resumeFrameWithProvenance(response_frame, true);
                }

                fn resumeFrameWithProvenance(self: *Self, response_frame: Frame.Response, comptime replayed: bool) !void {
                    if (response_frame.status == .pending) return error.HandlerPending;
                    const request = self.pending_request orelse return error.UnknownResidualSite;
                    const world_port_id = self.pending_port_id orelse return error.UnknownWorldPort;
                    if (self.effective_mode != .fresh) return Error.InvalidMode;
                    var frame = try self.pendingRequestFrame(false);
                    defer frame.deinit(self.allocator);
                    if (response_frame.world_surface_fingerprint != frame.world_surface_fingerprint) return error.FrameSurfaceMismatch;
                    if (response_frame.target_certificate_fingerprint != frame.target_certificate_fingerprint) return error.FrameTargetCertificateMismatch;
                    if (response_frame.world_port_id != world_port_id) return error.FramePortMismatch;
                    if (response_frame.request_fingerprint != frame.request_fingerprint) return error.FrameRequestFingerprintMismatch;
                    if (response_frame.status == .responded and response_frame.response_value_table_id != frame.expected_response_value_table_id) return error.FrameValueTableMismatch;
                    try validateResponseFrameImage(response_frame);
                    const deferred_response_fingerprint = response_frame.responseFingerprintDeferred();
                    if (!deferred_response_fingerprint and response_frame.replay_key != frame.replay_key_seed.withResponse(response_frame.response_fingerprint).fingerprint()) return error.ReplayMissing;
                    if (response_frame.status == .rejected) {
                        self.audit.rejected_count += 1;
                        try appendPortEvent(Target, self.options, .frame_rejected, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerRejected;
                    }
                    if (response_frame.status == .failed) {
                        self.audit.failed_count += 1;
                        try appendPortEvent(Target, self.options, .frame_failed, world_port_id, request.trace(), response_frame.response_fingerprint, response_frame.response_kind, null, null, response_frame);
                        try self.markRunFailed();
                        return error.HandlerFailed;
                    }
                    if (Target.WorldPortTable.entries.len == 0) return self.markMissingHandler(world_port_id, request.trace());
                    switch (world_port_id) {
                        inline 0...Target.WorldPortTable.entries.len - 1 => |id| {
                            const Handler = comptime handlerForWorldPortId(Target, Config, @intCast(id));
                            if (Handler) |Decl| {
                                try self.resumeFrameDecl(Decl, request, frame, response_frame, replayed);
                                self.pending_request = null;
                                self.pending_port_id = null;
                                return;
                            }
                            return self.markMissingHandler(world_port_id, request.trace());
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
                    if (record_event and self.effective_mode == .fresh) {
                        try appendPortEvent(Target, self.options, .frame_requested, world_port_id, trace, null, null, null, frame, null);
                    }
                    return frame;
                }

                fn resumeFrameDecl(self: *Self, comptime Decl: type, request: Request, request_frame: Frame.Request, response_frame: Frame.Response, comptime replayed: bool) !void {
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
                    try appendPortEvent(
                        Target,
                        self.options,
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
                        try appendPortEvent(Target, self.options, .frame_failed, Decl.world_port_id, request.trace(), response_trace.fingerprint, effective_response_frame.response_kind, null, null, failed_response_frame);
                        try self.markRunFailed();
                        return err;
                    };
                    retained_committed = true;
                }

                fn markMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    try self.recordMissingHandler(world_port_id, trace);
                    return Error.MissingHandler;
                }

                fn markMissingHandlerFrame(self: *Self, world_port_id: u32, trace: anytype) !Frame.Request {
                    try self.recordMissingHandler(world_port_id, trace);
                    return Error.MissingHandler;
                }

                fn recordMissingHandler(self: *Self, world_port_id: u32, trace: anytype) !void {
                    self.audit.missing_handler_count += 1;
                    self.audit.failed_count += 1;
                    try appendPortEvent(Target, self.options, .port_failed, world_port_id, trace, null, null, null, null, null);
                    try self.markRunFailed();
                }

                fn dispatchDecl(self: *Self, comptime Decl: type, request: Request) !void {
                    const typed_request = try request.as(Decl.SiteType);
                    const payload = try typed_request.payload();
                    const trace = request.trace();
                    const replay_key = Decl.replayKey(trace.fingerprint);
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
                    const response = try callHandler(Decl, @field(self.options, "ctx"), request);
                    defer Decl.response_deinit(@field(self.options, "ctx"), response);
                    const typed = try (self.pending_request orelse return Error.UnknownResidualSite).as(Decl.SiteType);
                    const response_trace = try typed.responseTrace(.@"resume", response);
                    var stored: ?StoredValue = null;
                    if (comptime @hasField(Options, "transcript")) {
                        stored = try StoredValue.init(@field(self.options, "transcript").allocator, response);
                    }
                    defer if (stored) |*owned| {
                        if (comptime @hasField(Options, "transcript")) {
                            owned.deinit(@field(self.options, "transcript").allocator);
                        }
                    };
                    try appendPortEvent(
                        Target,
                        self.options,
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
                        const image = @field(self.options, "transcript_image");
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
                        try appendPortEvent(Target, self.options, .frame_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, frame.*);
                        self.audit.replayed_response_count += 1;
                        var run_value = try StoredValue.initOwned(self.allocator, value);
                        value_owned = false;
                        var run_value_owned = true;
                        errdefer if (run_value_owned) run_value.deinit(self.allocator);
                        try self.retained_values.append(self.allocator, run_value);
                        run_value_owned = false;
                        return self.retained_values.items[self.retained_values.items.len - 1].borrow(Decl.Response);
                    }
                    if (!@hasField(Options, "transcript")) return Error.ReplayMissing;
                    const transcript = @field(self.options, "transcript");
                    const event = transcript.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                        self.audit.replay_mismatch_count += 1;
                        return err;
                    };
                    const value = if (event.value) |stored|
                        try stored.as(self.allocator, Decl.Response)
                    else if (event.response_frame) |frame| value: {
                        if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                        try validateResponseFrameImage(frame);
                        break :value try frame.decodeValue(self.allocator, Decl.Response);
                    } else return Error.ReplayMissing;
                    var value_owned = true;
                    errdefer if (value_owned) deinitOwnedValue(self.allocator, value);
                    const response_trace = try typed_request.responseTrace(.@"resume", value);
                    if (response_trace.fingerprint != (event.response_fingerprint orelse return Error.ReplayMissing)) {
                        self.audit.replay_mismatch_count += 1;
                        return Error.ReplayResponseKindMismatch;
                    }
                    try appendPortEvent(Target, self.options, .port_replayed, Decl.world_port_id, trace, response_trace.fingerprint, .@"resume", null, null, if (event.response_frame) |frame| frame else null);
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
                        const image = @field(self.options, "transcript_image");
                        const frame = image.nextResponse(replay_key, Target.Certificate.certificate_fingerprint, .@"resume") catch |err| {
                            self.audit.replay_mismatch_count += 1;
                            return err;
                        };
                        try validateResponseFrameImage(frame.*);
                        expected_response_frame = frame.*;
                        expected_response_fingerprint = frame.response_fingerprint;
                        if (frame.response_value_table_id != valueIdForRuntime(Target, Decl.world_port_id, .@"resume")) return error.FrameValueTableMismatch;
                        if (frame.response_image) |response_image| {
                            expected_value_image_fingerprint = response_image.value_image_fingerprint;
                            expected_value_table_id = response_image.value_table_id;
                            expected_boundary_value_fingerprint = response_image.boundary_value_fingerprint;
                            expected_codec_schema_descriptor_fingerprint = response_image.codec_schema_descriptor_fingerprint;
                            if (response_image.diagnostic_type_label != null) expected_value_policy = ValuePolicy.native_compatible;
                        } else {
                            expected_value_image_fingerprint = frame.response_value_fingerprint;
                        }
                        const replay_value = try frame.decodeValue(self.allocator, Decl.Response);
                        defer deinitOwnedValue(self.allocator, replay_value);
                        const replay_trace = try typed_request.responseTrace(.@"resume", replay_value);
                        if (replay_trace.fingerprint != expected_response_fingerprint) {
                            self.audit.replay_mismatch_count += 1;
                            return error.VerifyDivergence;
                        }
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
                    const fresh = try callHandler(Decl, @field(self.options, "ctx"), request);
                    defer Decl.response_deinit(@field(self.options, "ctx"), fresh);
                    const response_trace = try typed_request.responseTrace(.@"resume", fresh);
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
                        try appendPortEvent(Target, self.options, .frame_verified, Decl.world_port_id, (self.pending_request orelse return Error.UnknownResidualSite).trace(), expected_response_fingerprint, .@"resume", null, null, frame);
                    }
                    self.audit.fresh_response_count += 1;
                    return try self.retainResponse(Decl.Response, fresh);
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
    if (policy.require_all_required_ports_bound and bindings.len < Target.WorldPortTable.entries.len) {
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
        .SurfaceProfileIncompatible => Error.SurfaceProfileIncompatible,
        .PayloadValueMismatch => Error.FrameValueTableMismatch,
        .ResponseValueMismatch => Error.FrameValueTableMismatch,
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

fn validateValueImagePolicy(image: Frame.ValueImage, policy: ValuePolicy) !void {
    if (policy.max_value_image_bytes) |max| {
        if (image.bytes.len > max) return error.UnsupportedValueImage;
    }
    if (!policy.allow_diagnostic_type_labels and image.diagnostic_type_label != null) return error.UnsupportedValueImage;
}

fn validateRequestFramePolicy(frame: Frame.Request, policy: ValuePolicy) !void {
    if (frame.payload_image) |image| try validateValueImagePolicy(image, policy);
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

fn appendRunEvent(comptime Target: type, options: anytype, kind: EventKind, status: ?ResponseStatus, source_run: bool) !void {
    if (!@hasField(@TypeOf(options), "transcript")) return;
    try @field(options, "transcript").append(.{
        .kind = kind,
        .world_surface_fingerprint = Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = Target.Certificate.certificate_fingerprint,
        .status = status,
        .source_run = source_run,
    });
}

fn appendPortEvent(
    comptime Target: type,
    options: anytype,
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
        .turn_index = event.turn_index,
        .residual_site_index = event.residual_site_index,
        .residual_site_fingerprint = event.residual_site_fingerprint,
        .status = response_status,
        .source_run = event.source_run,
        .request_frame = request_frame,
        .response_frame = response_frame,
    };
    try validateTranscriptEventFrameBindings(image);
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

fn encodeTranscriptEventImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, event: TranscriptImage.EventImage) !void {
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

fn decodeTranscriptEventImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TranscriptImage.EventImage {
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
        .turn_index = try readOptionalUsize(bytes, cursor),
        .residual_site_index = try readOptionalUsize(bytes, cursor),
        .residual_site_fingerprint = try readOptionalU64(bytes, cursor),
        .status = if (try readBool(bytes, cursor)) try enumFromByte(ResponseStatus, try readU8(bytes, cursor)) else null,
        .source_run = try readBool(bytes, cursor),
        .request_frame = null,
        .response_frame = null,
    };
    errdefer event.deinit(allocator);
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
    if (fingerprintTranscriptEventImage(event) != event.event_fingerprint) return error.InvalidFrameEncoding;
    return event;
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
        if (event.request_frame) |frame| try validateRequestFramePolicy(frame, valuePolicyForEnvironmentPort(Env, frame.world_port_id, .request));
        if (event.response_frame) |frame| try validateResponseFramePolicy(frame, valuePolicyForEnvironmentPort(Env, frame.world_port_id, .response));
    }
}

fn validateTranscriptImageForEnvironment(comptime Env: type, image: *const TranscriptImage) !void {
    for (image.events) |event| {
        if (event.request_frame) |frame| try validateRequestFramePolicy(frame, valuePolicyForEnvironmentPort(Env, frame.world_port_id, .request));
        if (event.response_frame) |frame| try validateResponseFramePolicy(frame, valuePolicyForEnvironmentPort(Env, frame.world_port_id, .response));
    }
}

const FrameValuePolicyKind = enum { request, response };

fn valuePolicyForEnvironmentPort(comptime Env: type, world_port_id: u32, comptime kind: FrameValuePolicyKind) ValuePolicy {
    var policy = valuePolicyForEnvironment(Env);
    inline for (Env.bindings_decl) |BindingDecl| {
        if (comptime BindingDecl.TargetType == Env.TargetType) {
            if (BindingDecl.world_port_id == world_port_id) {
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
    return policy;
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
    try writeOptionalU64(out, allocator, target_ref.boundary_module_fingerprint);
    try writeBytes(out, allocator, target_ref.metadata);
}

fn decodeTargetRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TargetRef {
    const format_version = try readU32(bytes, cursor);
    if (format_version != world_target_ref_format_version) return error.InvalidFrameEncoding;
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
    const boundary_module_fingerprint = try readOptionalU64(bytes, cursor);
    const metadata = try readBytesOwned(allocator, bytes, cursor);
    errdefer allocator.free(metadata);
    // TargetRef labels/metadata are intentionally leaked into the owning RunImage lifetime;
    // RunImage does not currently expose a separate TargetRef deinit path.
    const result = TargetRef{
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
        .boundary_module_fingerprint = boundary_module_fingerprint,
        .metadata = metadata,
    };
    if (fingerprintTargetRef(result) != target_ref_fingerprint) return error.InvalidFrameEncoding;
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

fn fingerprintTargetRef(target_ref: TargetRef) u64 {
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

fn fingerprintRunImage(image: RunImage) u64 {
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
    hashU64(&hasher, image.metadata.len);
    hashBytes(&hasher, image.metadata);
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
