const std = @import("std");

pub fn Appliance(comptime World: type) type {
    return struct {
        pub const abi_version: u32 = World.world_appliance_abi_version;

        pub const Define = define;

        pub const Config = struct {
            profile: Profile = Profile.wasm_small,
            capacity: Capacity = Capacity.wasm_small,
            metadata: []const u8 = "",
        };

        pub const DefinitionReport = struct {
            root_world_port_count: usize,
            provider_count: usize,
            actuation_binding_count: usize,
            strict_closed_world: bool,
            accepted: bool,
        };

        pub const ProfileKind = enum(u8) {
            minimal = 0,
            wasm_small = 1,
            wasm_agent = 2,
            native_debug = 3,
            replay_only = 4,
            full_evidence = 5,
        };

        pub const Profile = struct {
            kind: ProfileKind,
            enable_fabric: bool,
            enable_actuation: bool,
            enable_capsules: bool,
            enable_archive_append: bool,
            enable_transcripts: bool,
            enable_guest_reports: bool,
            enable_verify: bool,
            emit_checkpoint_every_turn: bool,
            require_archive_ack_before_continue: bool,
            allow_manual_port_fallback: bool,
            retain_diagnostic_metadata: bool,
            strict_closed_world: bool,

            pub const minimal = init(.minimal);
            pub const wasm_small = init(.wasm_small);
            pub const wasm_agent = init(.wasm_agent);
            pub const native_debug = init(.native_debug);
            pub const replay_only = init(.replay_only);
            pub const full_evidence = init(.full_evidence);

            pub fn init(kind: ProfileKind) @This() {
                return switch (kind) {
                    .minimal => .{
                        .kind = kind,
                        .enable_fabric = false,
                        .enable_actuation = false,
                        .enable_capsules = true,
                        .enable_archive_append = false,
                        .enable_transcripts = false,
                        .enable_guest_reports = false,
                        .enable_verify = false,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = false,
                        .allow_manual_port_fallback = false,
                        .retain_diagnostic_metadata = false,
                        .strict_closed_world = true,
                    },
                    .wasm_small => .{
                        .kind = kind,
                        .enable_fabric = true,
                        .enable_actuation = true,
                        .enable_capsules = true,
                        .enable_archive_append = true,
                        .enable_transcripts = true,
                        .enable_guest_reports = false,
                        .enable_verify = false,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = false,
                        .allow_manual_port_fallback = false,
                        .retain_diagnostic_metadata = false,
                        .strict_closed_world = true,
                    },
                    .wasm_agent => .{
                        .kind = kind,
                        .enable_fabric = true,
                        .enable_actuation = true,
                        .enable_capsules = true,
                        .enable_archive_append = true,
                        .enable_transcripts = true,
                        .enable_guest_reports = true,
                        .enable_verify = true,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = false,
                        .allow_manual_port_fallback = false,
                        .retain_diagnostic_metadata = true,
                        .strict_closed_world = true,
                    },
                    .native_debug => .{
                        .kind = kind,
                        .enable_fabric = true,
                        .enable_actuation = true,
                        .enable_capsules = true,
                        .enable_archive_append = true,
                        .enable_transcripts = true,
                        .enable_guest_reports = true,
                        .enable_verify = true,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = false,
                        .allow_manual_port_fallback = true,
                        .retain_diagnostic_metadata = true,
                        .strict_closed_world = true,
                    },
                    .replay_only => .{
                        .kind = kind,
                        .enable_fabric = true,
                        .enable_actuation = true,
                        .enable_capsules = true,
                        .enable_archive_append = true,
                        .enable_transcripts = true,
                        .enable_guest_reports = true,
                        .enable_verify = true,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = false,
                        .allow_manual_port_fallback = false,
                        .retain_diagnostic_metadata = false,
                        .strict_closed_world = true,
                    },
                    .full_evidence => .{
                        .kind = kind,
                        .enable_fabric = true,
                        .enable_actuation = true,
                        .enable_capsules = true,
                        .enable_archive_append = true,
                        .enable_transcripts = true,
                        .enable_guest_reports = true,
                        .enable_verify = true,
                        .emit_checkpoint_every_turn = true,
                        .require_archive_ack_before_continue = true,
                        .allow_manual_port_fallback = false,
                        .retain_diagnostic_metadata = true,
                        .strict_closed_world = true,
                    },
                };
            }

            pub fn fingerprint(self: @This()) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashU64(&hasher, @intFromEnum(self.kind));
                hashBool(&hasher, self.enable_fabric);
                hashBool(&hasher, self.enable_actuation);
                hashBool(&hasher, self.enable_capsules);
                hashBool(&hasher, self.enable_archive_append);
                hashBool(&hasher, self.enable_transcripts);
                hashBool(&hasher, self.enable_guest_reports);
                hashBool(&hasher, self.enable_verify);
                hashBool(&hasher, self.emit_checkpoint_every_turn);
                hashBool(&hasher, self.require_archive_ack_before_continue);
                hashBool(&hasher, self.allow_manual_port_fallback);
                hashBool(&hasher, self.retain_diagnostic_metadata);
                hashBool(&hasher, self.strict_closed_world);
                return nonzero(hasher.final());
            }
        };

        pub const Capacity = struct {
            max_runs: usize,
            max_provider_runs: usize,
            max_pending_ports: usize,
            max_host_requests_per_turn: usize,
            max_host_replies_per_turn: usize,
            max_internal_ticks_per_turn: usize,
            max_runspace_events: usize,
            max_fabric_invocations: usize,
            max_actuation_records: usize,
            max_capsule_bytes: usize,
            max_archive_append_bytes: usize,
            max_command_bytes: usize,
            max_output_bytes: usize,
            max_error_bytes: usize,
            max_metadata_bytes: usize,

            pub const tiny_one_port = init(.{
                .max_runs = 1,
                .max_provider_runs = 0,
                .max_pending_ports = 1,
                .max_host_requests_per_turn = 1,
                .max_host_replies_per_turn = 1,
                .max_internal_ticks_per_turn = 16,
                .max_runspace_events = 32,
                .max_fabric_invocations = 0,
                .max_actuation_records = 2,
                .max_capsule_bytes = 4096,
                .max_archive_append_bytes = 4096,
                .max_command_bytes = 2048,
                .max_output_bytes = 4096,
                .max_error_bytes = 1024,
                .max_metadata_bytes = 512,
            });
            pub const wasm_small = init(.{
                .max_runs = 4,
                .max_provider_runs = 2,
                .max_pending_ports = 8,
                .max_host_requests_per_turn = 8,
                .max_host_replies_per_turn = 8,
                .max_internal_ticks_per_turn = 128,
                .max_runspace_events = 256,
                .max_fabric_invocations = 32,
                .max_actuation_records = 32,
                .max_capsule_bytes = 64 * 1024,
                .max_archive_append_bytes = 64 * 1024,
                .max_command_bytes = 16 * 1024,
                .max_output_bytes = 64 * 1024,
                .max_error_bytes = 4096,
                .max_metadata_bytes = 2048,
            });
            pub const wasm_agent = init(.{
                .max_runs = 16,
                .max_provider_runs = 8,
                .max_pending_ports = 32,
                .max_host_requests_per_turn = 16,
                .max_host_replies_per_turn = 16,
                .max_internal_ticks_per_turn = 1024,
                .max_runspace_events = 2048,
                .max_fabric_invocations = 256,
                .max_actuation_records = 128,
                .max_capsule_bytes = 256 * 1024,
                .max_archive_append_bytes = 256 * 1024,
                .max_command_bytes = 64 * 1024,
                .max_output_bytes = 256 * 1024,
                .max_error_bytes = 16 * 1024,
                .max_metadata_bytes = 8192,
            });
            pub const large_native_test = init(.{
                .max_runs = 64,
                .max_provider_runs = 32,
                .max_pending_ports = 128,
                .max_host_requests_per_turn = 64,
                .max_host_replies_per_turn = 64,
                .max_internal_ticks_per_turn = 16 * 1024,
                .max_runspace_events = 32 * 1024,
                .max_fabric_invocations = 4096,
                .max_actuation_records = 4096,
                .max_capsule_bytes = 4 * 1024 * 1024,
                .max_archive_append_bytes = 4 * 1024 * 1024,
                .max_command_bytes = 1024 * 1024,
                .max_output_bytes = 4 * 1024 * 1024,
                .max_error_bytes = 64 * 1024,
                .max_metadata_bytes = 64 * 1024,
            });
            pub const archive_decode = init(.{
                .max_runs = large_native_test.max_runs,
                .max_provider_runs = large_native_test.max_provider_runs,
                .max_pending_ports = World.world_max_decoded_byte_field_len,
                .max_host_requests_per_turn = World.world_max_decoded_byte_field_len,
                .max_host_replies_per_turn = World.world_max_decoded_byte_field_len,
                .max_internal_ticks_per_turn = large_native_test.max_internal_ticks_per_turn,
                .max_runspace_events = large_native_test.max_runspace_events,
                .max_fabric_invocations = large_native_test.max_fabric_invocations,
                .max_actuation_records = World.world_max_decoded_byte_field_len / @sizeOf(u64),
                .max_capsule_bytes = World.world_max_decoded_byte_field_len,
                .max_archive_append_bytes = World.world_max_decoded_byte_field_len,
                .max_command_bytes = World.world_max_decoded_byte_field_len,
                .max_output_bytes = World.world_max_decoded_byte_field_len,
                .max_error_bytes = World.world_max_decoded_byte_field_len,
                .max_metadata_bytes = World.world_max_decoded_byte_field_len,
            });

            pub fn init(args: @This()) @This() {
                return args;
            }

            pub fn validate(self: @This()) !void {
                if (self.max_runs == 0) return error.CapacityExceeded;
                if (self.max_provider_runs > self.max_runs) return error.CapacityExceeded;
                if (self.max_host_requests_per_turn > self.max_pending_ports) return error.CapacityExceeded;
                if (self.max_host_replies_per_turn > self.max_pending_ports) return error.CapacityExceeded;
                if (self.max_command_bytes == 0 or self.max_output_bytes == 0 or self.max_error_bytes == 0) return error.CapacityExceeded;
                if (self.max_metadata_bytes < "core-shell.host-request".len) return error.CapacityExceeded;
                if (self.max_metadata_bytes > World.world_max_decoded_byte_field_len) return error.CapacityExceeded;
                _ = MemoryPlan.deriveChecked(self, Profile.wasm_small) catch return error.CapacityExceeded;
            }

            pub fn validateForProfile(self: @This(), profile: Profile) !void {
                try self.validate();
                if (profile.enable_archive_append and self.max_archive_append_bytes == 0) return error.CapacityExceeded;
            }

            pub fn fingerprint(self: @This()) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashU64(&hasher, self.max_runs);
                hashU64(&hasher, self.max_provider_runs);
                hashU64(&hasher, self.max_pending_ports);
                hashU64(&hasher, self.max_host_requests_per_turn);
                hashU64(&hasher, self.max_host_replies_per_turn);
                hashU64(&hasher, self.max_internal_ticks_per_turn);
                hashU64(&hasher, self.max_runspace_events);
                hashU64(&hasher, self.max_fabric_invocations);
                hashU64(&hasher, self.max_actuation_records);
                hashU64(&hasher, self.max_capsule_bytes);
                hashU64(&hasher, self.max_archive_append_bytes);
                hashU64(&hasher, self.max_command_bytes);
                hashU64(&hasher, self.max_output_bytes);
                hashU64(&hasher, self.max_error_bytes);
                hashU64(&hasher, self.max_metadata_bytes);
                return nonzero(hasher.final());
            }
        };

        pub const MemoryPlan = struct {
            plan_fingerprint: u64,
            persistent_core_bytes: usize,
            scratch_bytes: usize,
            input_buffer_bytes: usize,
            output_buffer_bytes: usize,
            checkpoint_buffer_bytes: usize,
            archive_append_buffer_bytes: usize,
            maximum_linear_memory_bytes: usize,
            maximum_linear_memory_pages: usize,
            alignment: usize,
            enabled_feature_summary: FeatureSet,

            pub fn derive(capacity: Capacity, profile: Profile) @This() {
                capacity.validateForProfile(profile) catch unreachable;
                return deriveChecked(capacity, profile) catch unreachable;
            }

            fn deriveChecked(capacity: Capacity, profile: Profile) !@This() {
                const persistent = try alignBytesChecked(try checkedAdd(try checkedAdd(try checkedAdd(1024, try checkedMul(capacity.max_runs, 256)), try checkedMul(capacity.max_pending_ports, 192)), try checkedMul(capacity.max_actuation_records, 128)));
                const scratch = try alignBytesChecked(try checkedAdd(try checkedAdd(2048, try checkedMul(capacity.max_runspace_events, 32)), try checkedMul(capacity.max_fabric_invocations, 64)));
                const checkpoint = try alignBytesChecked(capacity.max_capsule_bytes);
                const archive = try alignBytesChecked(capacity.max_archive_append_bytes);
                const input = try alignBytesChecked(capacity.max_command_bytes);
                const output = try alignBytesChecked(capacity.max_output_bytes);
                const maximum = try alignPageChecked(try checkedAdd(try checkedAdd(try checkedAdd(try checkedAdd(try checkedAdd(try checkedAdd(try checkedAdd(persistent, scratch), input), output), checkpoint), archive), capacity.max_error_bytes), capacity.max_metadata_bytes));
                var result = @This(){
                    .plan_fingerprint = 0,
                    .persistent_core_bytes = persistent,
                    .scratch_bytes = scratch,
                    .input_buffer_bytes = input,
                    .output_buffer_bytes = output,
                    .checkpoint_buffer_bytes = checkpoint,
                    .archive_append_buffer_bytes = archive,
                    .maximum_linear_memory_bytes = maximum,
                    .maximum_linear_memory_pages = maximum / wasm_page_size,
                    .alignment = default_alignment,
                    .enabled_feature_summary = FeatureSet.fromProfile(profile),
                };
                result.plan_fingerprint = fingerprintMemoryPlan(result);
                return result;
            }
        };

        pub const HostCapabilityFlags = packed struct(u8) {
            actuation: bool = false,
            archive_retention_acknowledgment: bool = false,
            manual_port_fallback: bool = false,
            capsule_retention: bool = false,
            replay_evidence: bool = false,
            _reserved: u3 = 0,

            pub fn fromProfile(profile: Profile) @This() {
                return .{
                    .actuation = profile.enable_actuation,
                    .archive_retention_acknowledgment = profile.enable_archive_append and profile.require_archive_ack_before_continue,
                    .manual_port_fallback = profile.allow_manual_port_fallback,
                    .capsule_retention = profile.enable_capsules,
                    .replay_evidence = profile.enable_transcripts or profile.enable_archive_append,
                };
            }

            pub fn forManifest(profile: Profile, actuation_binding_count: usize) @This() {
                var flags = fromProfile(profile);
                flags.actuation = actuation_binding_count != 0;
                if (actuation_binding_count != 0) flags.replay_evidence = false;
                return flags;
            }
        };

        pub const FeatureSet = packed struct(u16) {
            fabric: bool = false,
            actuation: bool = false,
            capsules: bool = false,
            archive_append: bool = false,
            transcripts: bool = false,
            guest_reports: bool = false,
            verify: bool = false,
            checkpoint_every_turn: bool = false,
            archive_ack_gate: bool = false,
            manual_port_fallback: bool = false,
            diagnostic_metadata: bool = false,
            strict_closed_world: bool = true,
            _reserved: u4 = 0,

            pub fn fromProfile(profile: Profile) @This() {
                return .{
                    .fabric = profile.enable_fabric,
                    .actuation = profile.enable_actuation,
                    .capsules = profile.enable_capsules,
                    .archive_append = profile.enable_archive_append,
                    .transcripts = profile.enable_transcripts,
                    .guest_reports = profile.enable_guest_reports,
                    .verify = profile.enable_verify,
                    .checkpoint_every_turn = profile.emit_checkpoint_every_turn,
                    .archive_ack_gate = profile.require_archive_ack_before_continue,
                    .manual_port_fallback = profile.allow_manual_port_fallback,
                    .diagnostic_metadata = profile.retain_diagnostic_metadata,
                    .strict_closed_world = profile.strict_closed_world,
                };
            }
        };

        pub const ExecutionModeSet = packed struct(u8) {
            fresh: bool = true,
            replay: bool = true,
            verify: bool = false,
            audit: bool = false,
            _reserved: u4 = 0,

            pub fn fromProfile(profile: Profile) @This() {
                return .{
                    .fresh = profile.kind != .replay_only,
                    .replay = profile.enable_transcripts or profile.enable_archive_append or profile.kind == .replay_only,
                    .verify = profile.enable_verify,
                    .audit = profile.enable_verify and profile.retain_diagnostic_metadata,
                };
            }

            pub fn forManifest(profile: Profile, actuation_binding_count: usize) @This() {
                var modes = fromProfile(profile);
                if (actuation_binding_count != 0) {
                    if (profile.kind != .replay_only) {
                        modes.fresh = true;
                        modes.replay = false;
                        modes.verify = false;
                        modes.audit = false;
                    }
                }
                return modes;
            }

            pub fn supports(self: @This(), mode: ExecutionMode) bool {
                return switch (mode) {
                    .fresh => self.fresh,
                    .replay => self.replay,
                    .verify => self.verify,
                    .audit => self.audit,
                };
            }
        };

        pub const Manifest = struct {
            manifest_format_version: u32 = World.world_appliance_manifest_format_version,
            manifest_fingerprint_version: u32 = World.world_appliance_manifest_fingerprint_version,
            manifest_fingerprint: u64,
            appliance_abi_version: u32 = World.world_appliance_abi_version,
            root_target_ref_fingerprint: u64,
            root_world_surface_fingerprint: u64,
            root_target_certificate_fingerprint: u64,
            link_plan_fingerprint: u64 = 0,
            link_certificate_fingerprint: u64 = 0,
            assembly_fingerprint: u64 = 0,
            provider_target_ref_fingerprints: []const u64 = &.{},
            fabric_plan_fingerprints: []const u64 = &.{},
            residual_import_set_fingerprint: u64 = 0,
            actuation_descriptor_fingerprints: []const u64 = &.{},
            actuation_binding_fingerprints: []const u64 = &.{},
            actuation_actuator_ref_fingerprints: []const u64 = &.{},
            actuation_world_port_ids: []const u64 = &.{},
            actuation_classes: []const World.Actuation.Class = &.{},
            actuation_allowed_response_statuses: []const World.Actuation.ResponseStatusSet = &.{},
            supervision_policy_fingerprint: u64 = 0,
            default_permit_requirement_fingerprints: []const u64 = &.{},
            capsule_profile_fingerprint: u64 = 0,
            archive_profile_fingerprint: u64 = 0,
            supported_execution_modes: ExecutionModeSet = .{},
            enabled_features: FeatureSet,
            capacity_fingerprint: u64,
            memory_plan_fingerprint: u64,
            required_host_capabilities: HostCapabilityFlags,
            metadata: []const u8 = "",
            owns_payloads: bool = false,

            pub fn init(args: struct {
                root_target_ref_fingerprint: u64,
                root_world_surface_fingerprint: u64,
                root_target_certificate_fingerprint: u64,
                link_plan_fingerprint: u64 = 0,
                link_certificate_fingerprint: u64 = 0,
                assembly_fingerprint: u64 = 0,
                provider_target_ref_fingerprints: []const u64 = &.{},
                fabric_plan_fingerprints: []const u64 = &.{},
                residual_import_set_fingerprint: u64 = 0,
                actuation_descriptor_fingerprints: []const u64 = &.{},
                actuation_binding_fingerprints: []const u64 = &.{},
                actuation_actuator_ref_fingerprints: []const u64 = &.{},
                actuation_world_port_ids: []const u64 = &.{},
                actuation_classes: []const World.Actuation.Class = &.{},
                actuation_allowed_response_statuses: []const World.Actuation.ResponseStatusSet = &.{},
                supervision_policy_fingerprint: u64 = 0,
                default_permit_requirement_fingerprints: []const u64 = &.{},
                capsule_profile_fingerprint: u64 = 0,
                archive_profile_fingerprint: u64 = 0,
                supported_execution_modes: ExecutionModeSet = .{},
                enabled_features: FeatureSet,
                capacity_fingerprint: u64,
                memory_plan_fingerprint: u64,
                required_host_capabilities: HostCapabilityFlags,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .manifest_fingerprint = 0,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .root_world_surface_fingerprint = args.root_world_surface_fingerprint,
                    .root_target_certificate_fingerprint = args.root_target_certificate_fingerprint,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .link_certificate_fingerprint = args.link_certificate_fingerprint,
                    .assembly_fingerprint = args.assembly_fingerprint,
                    .provider_target_ref_fingerprints = args.provider_target_ref_fingerprints,
                    .fabric_plan_fingerprints = args.fabric_plan_fingerprints,
                    .residual_import_set_fingerprint = args.residual_import_set_fingerprint,
                    .actuation_descriptor_fingerprints = args.actuation_descriptor_fingerprints,
                    .actuation_binding_fingerprints = args.actuation_binding_fingerprints,
                    .actuation_actuator_ref_fingerprints = args.actuation_actuator_ref_fingerprints,
                    .actuation_world_port_ids = args.actuation_world_port_ids,
                    .actuation_classes = args.actuation_classes,
                    .actuation_allowed_response_statuses = args.actuation_allowed_response_statuses,
                    .supervision_policy_fingerprint = args.supervision_policy_fingerprint,
                    .default_permit_requirement_fingerprints = args.default_permit_requirement_fingerprints,
                    .capsule_profile_fingerprint = args.capsule_profile_fingerprint,
                    .archive_profile_fingerprint = args.archive_profile_fingerprint,
                    .supported_execution_modes = args.supported_execution_modes,
                    .enabled_features = args.enabled_features,
                    .capacity_fingerprint = args.capacity_fingerprint,
                    .memory_plan_fingerprint = args.memory_plan_fingerprint,
                    .required_host_capabilities = args.required_host_capabilities,
                    .metadata = args.metadata,
                };
                result.manifest_fingerprint = fingerprintManifest(result);
                return result;
            }

            pub fn validate(self: @This()) !void {
                if (self.manifest_format_version != World.world_appliance_manifest_format_version) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint_version != World.world_appliance_manifest_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.appliance_abi_version != World.world_appliance_abi_version) return error.InvalidFrameEncoding;
                if (self.root_target_ref_fingerprint == 0 or self.root_world_surface_fingerprint == 0 or self.root_target_certificate_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.capacity_fingerprint == 0 or self.memory_plan_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.supported_execution_modes._reserved != 0) return error.InvalidFrameEncoding;
                if (self.enabled_features._reserved != 0) return error.InvalidFrameEncoding;
                if (self.required_host_capabilities._reserved != 0) return error.InvalidFrameEncoding;
                if (self.actuation_descriptor_fingerprints.len != self.actuation_binding_fingerprints.len) return error.InvalidFrameEncoding;
                if (self.actuation_descriptor_fingerprints.len != self.actuation_actuator_ref_fingerprints.len) return error.InvalidFrameEncoding;
                if (self.actuation_descriptor_fingerprints.len != self.actuation_world_port_ids.len) return error.InvalidFrameEncoding;
                if (self.actuation_descriptor_fingerprints.len != self.actuation_classes.len) return error.InvalidFrameEncoding;
                if (self.actuation_descriptor_fingerprints.len != self.actuation_allowed_response_statuses.len) return error.InvalidFrameEncoding;
                if (self.actuation_binding_fingerprints.len != 0 and (!self.enabled_features.actuation or !self.required_host_capabilities.actuation or !self.supported_execution_modes.fresh or self.supported_execution_modes.replay or self.supported_execution_modes.verify or self.supported_execution_modes.audit or self.required_host_capabilities.replay_evidence)) return error.InvalidFrameEncoding;
                for (self.provider_target_ref_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.fabric_plan_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.actuation_descriptor_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.actuation_binding_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.actuation_actuator_ref_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.actuation_world_port_ids, 0..) |world_port_id, index| {
                    if (world_port_id > std.math.maxInt(u32)) return error.InvalidFrameEncoding;
                    for (self.actuation_world_port_ids[index + 1 ..]) |other| {
                        if (world_port_id == other) return error.InvalidFrameEncoding;
                    }
                }
                for (self.actuation_classes) |class| {
                    if (class == .unknown_effect) return error.InvalidFrameEncoding;
                }
                for (self.actuation_allowed_response_statuses) |statuses| {
                    if (!responseStatusSetAllowsAny(statuses)) return error.InvalidFrameEncoding;
                }
                for (self.default_permit_requirement_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                if (self.metadata.len > World.world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != fingerprintManifest(self)) return error.InvalidFrameEncoding;
            }

            pub fn encodedLen(self: @This()) usize {
                return manifestEncodedLen(self);
            }

            pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                try self.validate();
                const bytes = try allocator.alloc(u8, self.encodedLen());
                errdefer allocator.free(bytes);
                _ = try self.writeCanonicalBytes(bytes);
                return bytes;
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var manifest = try readManifestOwned(allocator, bytes, &cursor);
                errdefer manifest.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try manifest.validate();
                return manifest;
            }

            pub fn writeCanonicalBytes(self: @This(), dest: []u8) !usize {
                try self.validate();
                return writeManifestCanonicalBytes(self, dest);
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_payloads) {
                    allocator.free(self.provider_target_ref_fingerprints);
                    allocator.free(self.fabric_plan_fingerprints);
                    allocator.free(self.actuation_descriptor_fingerprints);
                    allocator.free(self.actuation_binding_fingerprints);
                    allocator.free(self.actuation_actuator_ref_fingerprints);
                    allocator.free(self.actuation_world_port_ids);
                    allocator.free(self.actuation_classes);
                    allocator.free(self.actuation_allowed_response_statuses);
                    allocator.free(self.default_permit_requirement_fingerprints);
                    allocator.free(self.metadata);
                }
                self.* = undefined;
            }
        };

        pub const CommandKind = enum(u8) { boot = 0, restore = 1, @"continue" = 2, inspect = 3, cancel = 4, reset = 5 };
        pub const ExecutionMode = enum(u8) { fresh = 0, replay = 1, verify = 2, audit = 3 };
        pub const HostOutcomeStatus = enum(u8) { responded = 0, rejected = 1, failed = 2, pending = 3, deferred = 4, cancelled = 5 };
        pub const HostResponseKind = enum(u8) { none = 0, frame_value_image = 1, bytes = 2 };
        pub const TurnStatus = enum(u8) { needs_host = 0, completed = 1, failed = 2, blocked = 3, cancelled = 4, inspected = 5 };
        pub const CoreState = enum(u8) { uninitialized = 0, runnable = 1, waiting_host = 2, completed = 3, failed = 4, cancelled = 5 };
        pub const ConformanceVectorKind = enum(u8) {
            one_port = 0,
            agent = 1,
            linked_provider = 2,
            supervised_denial = 3,
            replay_only = 4,
            pending_actuation = 5,
            deferred_actuation = 6,
            reconstruction = 7,
            archive_acknowledged = 8,
            archive_unacknowledged = 9,
        };

        pub const Command = struct {
            command_format_version: u32 = World.world_appliance_command_format_version,
            command_fingerprint_version: u32 = World.world_appliance_command_fingerprint_version,
            command_fingerprint: u64 = 0,
            kind: CommandKind,
            manifest_fingerprint: u64,
            turn_sequence_number: u64,
            previous_turn_receipt_fingerprint: ?u64 = null,
            execution_mode: ExecutionMode = .fresh,
            receiver_permit_fingerprint: ?u64 = null,
            receiver_evidence_fingerprints: []const u64 = &.{},
            root_argument_image: []const u8 = "",
            host_replies: []const HostReply = &.{},
            retention_ack: ?RetentionAck = null,
            restore_checkpoint: ?Checkpoint = null,
            metadata: []const u8 = "",
            owns_root_argument_image: bool = false,
            owns_receiver_evidence_fingerprints: bool = false,
            owns_host_replies: bool = false,
            owns_retention_ack_metadata: bool = false,
            owns_restore_checkpoint_payloads: bool = false,
            owns_metadata: bool = false,

            pub fn init(args: struct {
                kind: CommandKind,
                manifest_fingerprint: u64,
                turn_sequence_number: u64,
                previous_turn_receipt_fingerprint: ?u64 = null,
                execution_mode: ExecutionMode = .fresh,
                receiver_permit_fingerprint: ?u64 = null,
                receiver_evidence_fingerprints: []const u64 = &.{},
                root_argument_image: []const u8 = "",
                host_replies: []const HostReply = &.{},
                retention_ack: ?RetentionAck = null,
                restore_checkpoint: ?Checkpoint = null,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .kind = args.kind,
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .turn_sequence_number = args.turn_sequence_number,
                    .previous_turn_receipt_fingerprint = args.previous_turn_receipt_fingerprint,
                    .execution_mode = args.execution_mode,
                    .receiver_permit_fingerprint = args.receiver_permit_fingerprint,
                    .receiver_evidence_fingerprints = args.receiver_evidence_fingerprints,
                    .root_argument_image = args.root_argument_image,
                    .host_replies = args.host_replies,
                    .retention_ack = args.retention_ack,
                    .restore_checkpoint = args.restore_checkpoint,
                    .metadata = args.metadata,
                };
                result.command_fingerprint = fingerprintCommand(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64, capacity: Capacity) !void {
                if (self.command_format_version != World.world_appliance_command_format_version) return error.InvalidFrameEncoding;
                if (self.command_fingerprint_version != World.world_appliance_command_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                try validateOptionalFingerprint(self.receiver_permit_fingerprint);
                if (self.receiver_evidence_fingerprints.len > capacity.max_metadata_bytes / @sizeOf(u64)) return error.CapacityExceeded;
                for (self.receiver_evidence_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                if (self.root_argument_image.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.kind != .boot and self.root_argument_image.len != 0) return error.InvalidFrameEncoding;
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                if (self.host_replies.len > capacity.max_host_replies_per_turn) return error.CapacityExceeded;
                if (self.kind != .@"continue" and self.kind != .restore and self.host_replies.len != 0) return error.InvalidFrameEncoding;
                if (self.host_replies.len != 0 and self.execution_mode != .fresh) return error.InvalidMode;
                for (self.host_replies) |reply| {
                    try reply.validateShape(capacity);
                    if (reply.outcome.status == .responded and reply.outcome.response_kind != .frame_value_image) return error.InvalidFrameEncoding;
                    if (reply.outcome.host_request_fingerprint != reply.target_host_request_fingerprint) return error.InvalidFrameEncoding;
                }
                try validateDistinctHostReplyTargets(self.host_replies);
                if (self.retention_ack) |ack| {
                    if (self.kind != .@"continue" and self.kind != .restore) return error.InvalidFrameEncoding;
                    try ack.validate(null, capacity);
                }
                _ = try effectiveRetentionAck(self);
                if (self.restore_checkpoint) |checkpoint| {
                    if (self.kind != .restore) return error.InvalidFrameEncoding;
                    try checkpoint.validate(expected_manifest_fingerprint, capacity);
                    if (checkpoint.core_state == .runnable or checkpoint.core_state == .uninitialized) return error.InvalidFrameEncoding;
                    if (checkpoint.turn_sequence_number == std.math.maxInt(u64)) return error.InvalidFrameEncoding;
                    if (self.turn_sequence_number != checkpoint.turn_sequence_number + 1) return error.InvalidFrameEncoding;
                    if (self.previous_turn_receipt_fingerprint != checkpoint.previous_turn_receipt_fingerprint) return error.InvalidFrameEncoding;
                    if (self.host_replies.len != 0 and checkpoint.outstanding_host_requests.len == 0) return error.InvalidFrameEncoding;
                    for (self.host_replies) |reply| try reply.validate(checkpoint.outstanding_host_requests, capacity);
                    if (try effectiveRetentionAck(self)) |ack| {
                        try ack.validate(checkpoint.pending_archive_append_batch_fingerprint orelse return error.ArchiveParentMismatch, capacity);
                    }
                } else if (self.kind == .restore) {
                    return error.RestoreRejected;
                }
                if (self.kind == .boot and (self.previous_turn_receipt_fingerprint != null or self.turn_sequence_number != 0)) return error.InvalidFrameEncoding;
                if (self.kind == .@"continue" and self.previous_turn_receipt_fingerprint == null) return error.InvalidFrameEncoding;
                if (self.previous_turn_receipt_fingerprint != null and self.previous_turn_receipt_fingerprint.? == 0) return error.InvalidFrameEncoding;
                if (self.command_fingerprint != fingerprintCommand(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
                var out: std.ArrayList(u8) = .empty;
                errdefer out.deinit(allocator);
                try writeU32(&out, allocator, self.command_format_version);
                try writeU32(&out, allocator, self.command_fingerprint_version);
                try writeU64(&out, allocator, self.command_fingerprint);
                try writeU8(&out, allocator, @intFromEnum(self.kind));
                try writeU64(&out, allocator, self.manifest_fingerprint);
                try writeU64(&out, allocator, self.turn_sequence_number);
                try writeOptionalU64(&out, allocator, self.previous_turn_receipt_fingerprint);
                try writeU8(&out, allocator, @intFromEnum(self.execution_mode));
                try writeOptionalU64(&out, allocator, self.receiver_permit_fingerprint);
                try writeU64Slice(&out, allocator, self.receiver_evidence_fingerprints);
                try writeBytes(&out, allocator, self.root_argument_image);
                try writeHostRepliesCanonical(&out, allocator, self.host_replies);
                try writeOptionalRetentionAck(&out, allocator, self.retention_ack);
                try writeOptionalCheckpoint(&out, allocator, self.restore_checkpoint);
                try writeBytes(&out, allocator, self.metadata);
                return out.toOwnedSlice(allocator);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                const command_format_version = try readU32(bytes, &cursor);
                const command_fingerprint_version = try readU32(bytes, &cursor);
                const command_fingerprint = try readU64(bytes, &cursor);
                const kind = try enumFromByte(CommandKind, try readU8(bytes, &cursor));
                const manifest_fingerprint = try readU64(bytes, &cursor);
                const turn_sequence_number = try readU64(bytes, &cursor);
                const previous_turn_receipt_fingerprint = try readOptionalU64(bytes, &cursor);
                const execution_mode = try enumFromByte(ExecutionMode, try readU8(bytes, &cursor));
                const receiver_permit_fingerprint = try readOptionalU64(bytes, &cursor);
                const receiver_evidence_fingerprints = try readU64SliceOwned(allocator, bytes, &cursor);
                errdefer allocator.free(receiver_evidence_fingerprints);
                const root_argument_image = try readBytesOwned(allocator, bytes, &cursor);
                errdefer allocator.free(root_argument_image);
                const host_replies = try readHostRepliesOwned(allocator, bytes, &cursor);
                errdefer freeHostReplies(allocator, host_replies);
                const retention_ack = try readOptionalRetentionAckOwned(allocator, bytes, &cursor);
                errdefer if (retention_ack) |ack| {
                    var cleanup = ack;
                    freeRetentionAck(allocator, &cleanup);
                };
                const restore_checkpoint = try readOptionalCheckpointOwned(allocator, bytes, &cursor);
                errdefer if (restore_checkpoint) |checkpoint| {
                    var cleanup = checkpoint;
                    freeCheckpoint(allocator, &cleanup);
                };
                const metadata = try readBytesOwned(allocator, bytes, &cursor);
                errdefer allocator.free(metadata);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                return .{
                    .command_format_version = command_format_version,
                    .command_fingerprint_version = command_fingerprint_version,
                    .command_fingerprint = command_fingerprint,
                    .kind = kind,
                    .manifest_fingerprint = manifest_fingerprint,
                    .turn_sequence_number = turn_sequence_number,
                    .previous_turn_receipt_fingerprint = previous_turn_receipt_fingerprint,
                    .execution_mode = execution_mode,
                    .receiver_permit_fingerprint = receiver_permit_fingerprint,
                    .receiver_evidence_fingerprints = receiver_evidence_fingerprints,
                    .root_argument_image = root_argument_image,
                    .host_replies = host_replies,
                    .retention_ack = retention_ack,
                    .restore_checkpoint = restore_checkpoint,
                    .metadata = metadata,
                    .owns_root_argument_image = true,
                    .owns_receiver_evidence_fingerprints = true,
                    .owns_host_replies = true,
                    .owns_retention_ack_metadata = retention_ack != null,
                    .owns_restore_checkpoint_payloads = restore_checkpoint != null,
                    .owns_metadata = true,
                };
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_root_argument_image) allocator.free(self.root_argument_image);
                if (self.owns_receiver_evidence_fingerprints) allocator.free(self.receiver_evidence_fingerprints);
                if (self.owns_host_replies) freeHostReplies(allocator, self.host_replies);
                if (self.owns_retention_ack_metadata) {
                    if (self.retention_ack) |ack| {
                        var cleanup = ack;
                        freeRetentionAck(allocator, &cleanup);
                    }
                }
                if (self.owns_restore_checkpoint_payloads) {
                    if (self.restore_checkpoint) |checkpoint| {
                        var cleanup = checkpoint;
                        freeCheckpoint(allocator, &cleanup);
                    }
                }
                if (self.owns_metadata) allocator.free(self.metadata);
                self.* = undefined;
            }
        };

        pub const HostRequest = struct {
            request_format_version: u32 = World.world_appliance_host_request_format_version,
            request_fingerprint_version: u32 = World.world_appliance_host_request_fingerprint_version,
            request_fingerprint: u64 = 0,
            turn_sequence_number: u64,
            request_ordinal: u32,
            run_handle_fingerprint: u64,
            pending_port_fingerprint: u64,
            world_port_id: u32,
            target_ref_fingerprint: u64,
            world_surface_fingerprint: u64,
            actuator_ref_fingerprint: u64,
            actuation_class: World.Actuation.Class,
            allowed_response_statuses: World.Actuation.ResponseStatusSet,
            intent_fingerprint: u64,
            envelope_fingerprint: u64,
            decision_fingerprint: u64,
            expected_response_descriptor_fingerprint: u64,
            idempotency_key_fingerprint: u64,
            supervision_ref_fingerprint: ?u64 = null,
            metadata: []const u8 = "",
            owns_metadata: bool = false,
            frame_request_bytes: []const u8 = "",
            payload_value_image_bytes: []const u8 = "",
            payload_value_ref_fingerprint: ?u64 = null,
            payload_schema_ref_fingerprint: ?u64 = null,
            expected_response_value_ref_fingerprint: ?u64 = null,
            expected_response_schema_ref_fingerprint: ?u64 = null,
            prepared_actuation_evidence_bytes: []const u8 = "",
            idempotency_key_bytes: []const u8 = "",
            owns_byte_payloads: bool = false,

            pub fn init(args: anytype) @This() {
                var result = @This(){
                    .turn_sequence_number = args.turn_sequence_number,
                    .request_ordinal = args.request_ordinal,
                    .run_handle_fingerprint = args.run_handle_fingerprint,
                    .pending_port_fingerprint = args.pending_port_fingerprint,
                    .world_port_id = args.world_port_id,
                    .target_ref_fingerprint = args.target_ref_fingerprint,
                    .world_surface_fingerprint = args.world_surface_fingerprint,
                    .actuator_ref_fingerprint = args.actuator_ref_fingerprint,
                    .actuation_class = args.actuation_class,
                    .allowed_response_statuses = args.allowed_response_statuses,
                    .intent_fingerprint = args.intent_fingerprint,
                    .envelope_fingerprint = args.envelope_fingerprint,
                    .decision_fingerprint = args.decision_fingerprint,
                    .expected_response_descriptor_fingerprint = args.expected_response_descriptor_fingerprint,
                    .idempotency_key_fingerprint = args.idempotency_key_fingerprint,
                    .supervision_ref_fingerprint = if (@hasField(@TypeOf(args), "supervision_ref_fingerprint")) args.supervision_ref_fingerprint else null,
                    .metadata = if (@hasField(@TypeOf(args), "metadata")) args.metadata else "",
                    .frame_request_bytes = if (@hasField(@TypeOf(args), "frame_request_bytes")) args.frame_request_bytes else "",
                    .payload_value_image_bytes = if (@hasField(@TypeOf(args), "payload_value_image_bytes")) args.payload_value_image_bytes else "",
                    .payload_value_ref_fingerprint = if (@hasField(@TypeOf(args), "payload_value_ref_fingerprint")) args.payload_value_ref_fingerprint else null,
                    .payload_schema_ref_fingerprint = if (@hasField(@TypeOf(args), "payload_schema_ref_fingerprint")) args.payload_schema_ref_fingerprint else null,
                    .expected_response_value_ref_fingerprint = if (@hasField(@TypeOf(args), "expected_response_value_ref_fingerprint")) args.expected_response_value_ref_fingerprint else null,
                    .expected_response_schema_ref_fingerprint = if (@hasField(@TypeOf(args), "expected_response_schema_ref_fingerprint")) args.expected_response_schema_ref_fingerprint else null,
                    .prepared_actuation_evidence_bytes = if (@hasField(@TypeOf(args), "prepared_actuation_evidence_bytes")) args.prepared_actuation_evidence_bytes else "",
                    .idempotency_key_bytes = if (@hasField(@TypeOf(args), "idempotency_key_bytes")) args.idempotency_key_bytes else "",
                    .owns_byte_payloads = if (@hasField(@TypeOf(args), "owns_byte_payloads")) args.owns_byte_payloads else false,
                };
                result.request_fingerprint = fingerprintHostRequest(result);
                return result;
            }

            pub fn validate(self: @This(), capacity: Capacity) !void {
                if (self.request_format_version != World.world_appliance_host_request_format_version) return error.InvalidFrameEncoding;
                if (self.request_fingerprint_version != World.world_appliance_host_request_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.request_ordinal >= capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                if (self.run_handle_fingerprint == 0 or self.pending_port_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.target_ref_fingerprint == 0 or self.world_surface_fingerprint == 0 or self.actuator_ref_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.actuation_class == .unknown_effect) return error.InvalidFrameEncoding;
                if (!responseStatusSetAllowsAny(self.allowed_response_statuses)) return error.InvalidFrameEncoding;
                if (self.intent_fingerprint == 0 or self.envelope_fingerprint == 0 or self.decision_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.expected_response_descriptor_fingerprint == 0 or self.idempotency_key_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.supervision_ref_fingerprint);
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                try validateOptionalFingerprint(self.payload_value_ref_fingerprint);
                try validateOptionalFingerprint(self.payload_schema_ref_fingerprint);
                try validateOptionalFingerprint(self.expected_response_value_ref_fingerprint);
                try validateOptionalFingerprint(self.expected_response_schema_ref_fingerprint);
                if (self.frame_request_bytes.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.payload_value_image_bytes.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.prepared_actuation_evidence_bytes.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.idempotency_key_bytes.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.request_fingerprint != fingerprintHostRequest(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU32(out, allocator, self.request_format_version);
                try writeU32(out, allocator, self.request_fingerprint_version);
                try writeU64(out, allocator, self.request_fingerprint);
                try writeU64(out, allocator, self.turn_sequence_number);
                try writeU32(out, allocator, self.request_ordinal);
                try writeU64(out, allocator, self.run_handle_fingerprint);
                try writeU64(out, allocator, self.pending_port_fingerprint);
                try writeU32(out, allocator, self.world_port_id);
                try writeU64(out, allocator, self.target_ref_fingerprint);
                try writeU64(out, allocator, self.world_surface_fingerprint);
                try writeU64(out, allocator, self.actuator_ref_fingerprint);
                try writeU8(out, allocator, @intFromEnum(self.actuation_class));
                try writeResponseStatusSet(out, allocator, self.allowed_response_statuses);
                try writeU64(out, allocator, self.intent_fingerprint);
                try writeU64(out, allocator, self.envelope_fingerprint);
                try writeU64(out, allocator, self.decision_fingerprint);
                try writeU64(out, allocator, self.expected_response_descriptor_fingerprint);
                try writeU64(out, allocator, self.idempotency_key_fingerprint);
                try writeOptionalU64(out, allocator, self.supervision_ref_fingerprint);
                try writeBytes(out, allocator, self.metadata);
                try writeBytes(out, allocator, self.frame_request_bytes);
                try writeBytes(out, allocator, self.payload_value_image_bytes);
                try writeOptionalU64(out, allocator, self.payload_value_ref_fingerprint);
                try writeOptionalU64(out, allocator, self.payload_schema_ref_fingerprint);
                try writeOptionalU64(out, allocator, self.expected_response_value_ref_fingerprint);
                try writeOptionalU64(out, allocator, self.expected_response_schema_ref_fingerprint);
                try writeBytes(out, allocator, self.prepared_actuation_evidence_bytes);
                try writeBytes(out, allocator, self.idempotency_key_bytes);
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var request = try readHostRequestOwned(allocator, bytes, &cursor);
                errdefer request.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try request.validate(Capacity.archive_decode);
                return request;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_metadata) allocator.free(self.metadata);
                if (self.owns_byte_payloads) {
                    allocator.free(self.frame_request_bytes);
                    allocator.free(self.payload_value_image_bytes);
                    allocator.free(self.prepared_actuation_evidence_bytes);
                    allocator.free(self.idempotency_key_bytes);
                }
                self.* = undefined;
            }
        };

        pub const HostOutcome = struct {
            outcome_format_version: u32 = World.world_appliance_host_outcome_format_version,
            outcome_fingerprint_version: u32 = World.world_appliance_host_outcome_fingerprint_version,
            outcome_fingerprint: u64 = 0,
            host_request_fingerprint: u64,
            intent_fingerprint: u64,
            envelope_fingerprint: u64,
            idempotency_key_fingerprint: u64,
            status: HostOutcomeStatus,
            response_fingerprint: ?u64 = null,
            response_kind: HostResponseKind = .none,
            response_bytes: []const u8 = "",
            host_evidence_fingerprint: ?u64 = null,
            host_evidence_bytes: []const u8 = "",
            attempt_number: u32 = 0,
            metadata: []const u8 = "",
            owns_payloads: bool = false,

            pub fn init(args: struct {
                host_request_fingerprint: u64,
                intent_fingerprint: u64,
                envelope_fingerprint: u64,
                idempotency_key_fingerprint: u64,
                status: HostOutcomeStatus,
                response_fingerprint: ?u64 = null,
                response_kind: HostResponseKind = .none,
                response_bytes: []const u8 = "",
                host_evidence_fingerprint: ?u64 = null,
                host_evidence_bytes: []const u8 = "",
                attempt_number: u32 = 0,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .host_request_fingerprint = args.host_request_fingerprint,
                    .intent_fingerprint = args.intent_fingerprint,
                    .envelope_fingerprint = args.envelope_fingerprint,
                    .idempotency_key_fingerprint = args.idempotency_key_fingerprint,
                    .status = args.status,
                    .response_fingerprint = args.response_fingerprint,
                    .response_kind = args.response_kind,
                    .response_bytes = args.response_bytes,
                    .host_evidence_fingerprint = args.host_evidence_fingerprint,
                    .host_evidence_bytes = args.host_evidence_bytes,
                    .attempt_number = args.attempt_number,
                    .metadata = args.metadata,
                };
                result.outcome_fingerprint = fingerprintHostOutcome(result);
                return result;
            }

            pub fn validate(self: @This(), expected_request: ?HostRequest, capacity: Capacity) !void {
                if (self.outcome_format_version != World.world_appliance_host_outcome_format_version) return error.InvalidFrameEncoding;
                if (self.outcome_fingerprint_version != World.world_appliance_host_outcome_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.host_request_fingerprint == 0 or self.intent_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.envelope_fingerprint == 0 or self.idempotency_key_fingerprint == 0) return error.InvalidFrameEncoding;
                if (expected_request) |request| {
                    try request.validate(capacity);
                    if (self.host_request_fingerprint != request.request_fingerprint) return error.UnknownRequest;
                    if (self.intent_fingerprint != request.intent_fingerprint) return error.InvalidFrameEncoding;
                    if (self.envelope_fingerprint != request.envelope_fingerprint) return error.InvalidFrameEncoding;
                    if (self.idempotency_key_fingerprint != request.idempotency_key_fingerprint) return error.InvalidFrameEncoding;
                }
                try validateOptionalFingerprint(self.response_fingerprint);
                try validateOptionalFingerprint(self.host_evidence_fingerprint);
                switch (self.status) {
                    .responded => {
                        if (self.response_fingerprint == null) return error.InvalidFrameEncoding;
                        if (self.response_kind == .none) return error.InvalidFrameEncoding;
                        if (expected_request != null and self.response_kind != .frame_value_image) return error.InvalidFrameEncoding;
                    },
                    .pending, .deferred, .rejected, .failed, .cancelled => {
                        if (self.response_fingerprint != null) return error.InvalidFrameEncoding;
                        if (self.response_kind != .none) return error.InvalidFrameEncoding;
                        if (self.response_bytes.len != 0) return error.InvalidFrameEncoding;
                    },
                }
                if (self.response_kind == .none and self.response_bytes.len != 0) return error.InvalidFrameEncoding;
                if (self.response_bytes.len > capacity.max_command_bytes) return error.CapacityExceeded;
                if (self.host_evidence_bytes.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                if (self.outcome_fingerprint != fingerprintHostOutcome(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU32(out, allocator, self.outcome_format_version);
                try writeU32(out, allocator, self.outcome_fingerprint_version);
                try writeU64(out, allocator, self.outcome_fingerprint);
                try writeU64(out, allocator, self.host_request_fingerprint);
                try writeU64(out, allocator, self.intent_fingerprint);
                try writeU64(out, allocator, self.envelope_fingerprint);
                try writeU64(out, allocator, self.idempotency_key_fingerprint);
                try writeU8(out, allocator, @intFromEnum(self.status));
                try writeOptionalU64(out, allocator, self.response_fingerprint);
                try writeU8(out, allocator, @intFromEnum(self.response_kind));
                try writeBytes(out, allocator, self.response_bytes);
                try writeOptionalU64(out, allocator, self.host_evidence_fingerprint);
                try writeBytes(out, allocator, self.host_evidence_bytes);
                try writeU32(out, allocator, self.attempt_number);
                try writeBytes(out, allocator, self.metadata);
            }
        };

        pub const HostReply = struct {
            reply_format_version: u32 = World.world_appliance_host_reply_format_version,
            reply_fingerprint_version: u32 = World.world_appliance_host_reply_fingerprint_version,
            reply_fingerprint: u64 = 0,
            target_host_request_fingerprint: u64,
            outcome: HostOutcome,
            retention_ack_fingerprint: ?u64 = null,
            retention_ack: ?RetentionAck = null,
            metadata: []const u8 = "",
            owns_payloads: bool = false,

            pub fn init(args: struct {
                target_host_request_fingerprint: u64,
                outcome: HostOutcome,
                retention_ack_fingerprint: ?u64 = null,
                retention_ack: ?RetentionAck = null,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .target_host_request_fingerprint = args.target_host_request_fingerprint,
                    .outcome = args.outcome,
                    .retention_ack_fingerprint = if (args.retention_ack) |ack| ack.ack_fingerprint else args.retention_ack_fingerprint,
                    .retention_ack = args.retention_ack,
                    .metadata = args.metadata,
                };
                result.reply_fingerprint = fingerprintHostReply(result);
                return result;
            }

            pub fn validate(self: @This(), outstanding_requests: []const HostRequest, capacity: Capacity) !void {
                try self.validateShape(capacity);
                const request = findHostRequest(outstanding_requests, self.target_host_request_fingerprint) orelse return error.UnknownRequest;
                if (self.outcome.host_request_fingerprint != self.target_host_request_fingerprint) return error.UnknownRequest;
                try self.outcome.validate(request, capacity);
                if (!request.allowed_response_statuses.allows(actuationStatusForHostOutcome(self.outcome.status))) return error.PortRuleDenied;
            }

            pub fn validateShape(self: @This(), capacity: Capacity) !void {
                if (self.reply_format_version != World.world_appliance_host_reply_format_version) return error.InvalidFrameEncoding;
                if (self.reply_fingerprint_version != World.world_appliance_host_reply_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.target_host_request_fingerprint == 0) return error.InvalidFrameEncoding;
                try self.outcome.validate(null, capacity);
                try validateOptionalFingerprint(self.retention_ack_fingerprint);
                if (self.retention_ack) |ack| {
                    try ack.validate(null, capacity);
                    if (self.retention_ack_fingerprint == null or self.retention_ack_fingerprint.? != ack.ack_fingerprint) return error.InvalidFrameEncoding;
                }
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                if (self.reply_fingerprint != fingerprintHostReply(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU32(out, allocator, self.reply_format_version);
                try writeU32(out, allocator, self.reply_fingerprint_version);
                try writeU64(out, allocator, self.reply_fingerprint);
                try writeU64(out, allocator, self.target_host_request_fingerprint);
                try self.outcome.encode(out, allocator);
                try writeOptionalU64(out, allocator, self.retention_ack_fingerprint);
                try writeOptionalRetentionAck(out, allocator, self.retention_ack);
                try writeBytes(out, allocator, self.metadata);
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var reply = try readHostReplyOwned(allocator, bytes, &cursor);
                errdefer reply.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try reply.validateShape(Capacity.archive_decode);
                if (reply.outcome.host_request_fingerprint != reply.target_host_request_fingerprint) return error.InvalidFrameEncoding;
                return reply;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                freeHostReply(allocator, self);
                self.* = undefined;
            }
        };

        pub const QuiescenceReport = struct {
            report_fingerprint: u64 = 0,
            quiescent: bool = false,
            runnable_run_count: usize = 0,
            parked_run_count: usize = 0,
            pending_host_request_count: usize = 0,
            active_fabric_count: usize = 0,
            prepared_actuation_count: usize = 0,
            completed_run_count: usize = 0,
            failed_run_count: usize = 0,
            blocker_count: usize = 0,
            warning_count: usize = 0,

            pub fn init(args: struct {
                quiescent: bool = false,
                runnable_run_count: usize = 0,
                parked_run_count: usize = 0,
                pending_host_request_count: usize = 0,
                active_fabric_count: usize = 0,
                prepared_actuation_count: usize = 0,
                completed_run_count: usize = 0,
                failed_run_count: usize = 0,
                blocker_count: usize = 0,
                warning_count: usize = 0,
            }) @This() {
                var result = @This(){
                    .quiescent = args.quiescent,
                    .runnable_run_count = args.runnable_run_count,
                    .parked_run_count = args.parked_run_count,
                    .pending_host_request_count = args.pending_host_request_count,
                    .active_fabric_count = args.active_fabric_count,
                    .prepared_actuation_count = args.prepared_actuation_count,
                    .completed_run_count = args.completed_run_count,
                    .failed_run_count = args.failed_run_count,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                };
                result.report_fingerprint = fingerprintQuiescenceReport(result);
                return result;
            }

            pub fn validate(self: @This()) !void {
                if (self.report_fingerprint == 0) return error.InvalidFrameEncoding;
                if (!self.quiescent and self.runnable_run_count == 0 and self.pending_host_request_count == 0 and self.active_fabric_count == 0) return error.InvalidFrameEncoding;
                if (self.report_fingerprint != fingerprintQuiescenceReport(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU64(out, allocator, self.report_fingerprint);
                try writeU8(out, allocator, @intFromBool(self.quiescent));
                try writeU64(out, allocator, self.runnable_run_count);
                try writeU64(out, allocator, self.parked_run_count);
                try writeU64(out, allocator, self.pending_host_request_count);
                try writeU64(out, allocator, self.active_fabric_count);
                try writeU64(out, allocator, self.prepared_actuation_count);
                try writeU64(out, allocator, self.completed_run_count);
                try writeU64(out, allocator, self.failed_run_count);
                try writeU64(out, allocator, self.blocker_count);
                try writeU64(out, allocator, self.warning_count);
            }
        };

        pub const Checkpoint = struct {
            checkpoint_format_version: u32 = World.world_appliance_checkpoint_format_version,
            checkpoint_fingerprint_version: u32 = World.world_appliance_checkpoint_fingerprint_version,
            checkpoint_fingerprint: u64 = 0,
            manifest_fingerprint: u64,
            turn_sequence_number: u64,
            capsule_fingerprint: u64,
            capsule_image_ref_fingerprint: ?u64 = null,
            capsule_image_bytes: []const u8 = "",
            latest_archive_moment_fingerprint: ?u64 = null,
            latest_archive_seal_fingerprint: ?u64 = null,
            latest_chronicle_cursor_fingerprint: ?u64 = null,
            pending_archive_append_batch_fingerprint: ?u64 = null,
            pending_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor = null,
            latest_archive_cursor: ?World.Continuity.Chronicle.Cursor = null,
            core_state: CoreState = .completed,
            previous_turn_receipt_fingerprint: ?u64 = null,
            outstanding_host_requests: []const HostRequest = &.{},
            execution_mode: ExecutionMode = .fresh,
            metadata: []const u8 = "",
            owns_payloads: bool = false,

            pub fn init(args: struct {
                manifest_fingerprint: u64,
                turn_sequence_number: u64,
                capsule_fingerprint: u64,
                capsule_image_ref_fingerprint: ?u64 = null,
                capsule_image_bytes: []const u8 = "",
                latest_archive_moment_fingerprint: ?u64 = null,
                latest_archive_seal_fingerprint: ?u64 = null,
                latest_chronicle_cursor_fingerprint: ?u64 = null,
                pending_archive_append_batch_fingerprint: ?u64 = null,
                pending_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor = null,
                latest_archive_cursor: ?World.Continuity.Chronicle.Cursor = null,
                core_state: ?CoreState = null,
                previous_turn_receipt_fingerprint: ?u64 = null,
                outstanding_host_requests: []const HostRequest = &.{},
                execution_mode: ExecutionMode = .fresh,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .turn_sequence_number = args.turn_sequence_number,
                    .capsule_fingerprint = args.capsule_fingerprint,
                    .capsule_image_ref_fingerprint = args.capsule_image_ref_fingerprint orelse defaultCapsuleImageRef(args.capsule_fingerprint),
                    .capsule_image_bytes = args.capsule_image_bytes,
                    .latest_archive_moment_fingerprint = args.latest_archive_moment_fingerprint,
                    .latest_archive_seal_fingerprint = args.latest_archive_seal_fingerprint,
                    .latest_chronicle_cursor_fingerprint = args.latest_chronicle_cursor_fingerprint,
                    .pending_archive_append_batch_fingerprint = args.pending_archive_append_batch_fingerprint,
                    .pending_archive_resulting_cursor = args.pending_archive_resulting_cursor,
                    .latest_archive_cursor = args.latest_archive_cursor,
                    .core_state = args.core_state orelse if (args.outstanding_host_requests.len != 0) .waiting_host else .completed,
                    .previous_turn_receipt_fingerprint = args.previous_turn_receipt_fingerprint,
                    .outstanding_host_requests = args.outstanding_host_requests,
                    .execution_mode = args.execution_mode,
                    .metadata = args.metadata,
                };
                result.checkpoint_fingerprint = fingerprintCheckpoint(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64, capacity: Capacity) !void {
                if (self.checkpoint_format_version != World.world_appliance_checkpoint_format_version) return error.InvalidFrameEncoding;
                if (self.checkpoint_fingerprint_version != World.world_appliance_checkpoint_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.capsule_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.capsule_image_ref_fingerprint);
                if (self.capsule_image_ref_fingerprint) |ref| {
                    if (ref != defaultCapsuleImageRef(self.capsule_fingerprint)) return error.InvalidFrameEncoding;
                }
                if (self.capsule_image_ref_fingerprint == null and self.capsule_image_bytes.len == 0) return error.InvalidFrameEncoding;
                if (self.capsule_image_bytes.len > capacity.max_capsule_bytes) return error.CapacityExceeded;
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                try validateOptionalFingerprint(self.latest_archive_moment_fingerprint);
                try validateOptionalFingerprint(self.latest_archive_seal_fingerprint);
                try validateOptionalFingerprint(self.latest_chronicle_cursor_fingerprint);
                try validateArchiveAnchorTuple(self.latest_archive_moment_fingerprint, self.latest_archive_seal_fingerprint, self.latest_chronicle_cursor_fingerprint);
                try validateOptionalFingerprint(self.pending_archive_append_batch_fingerprint);
                if (self.pending_archive_append_batch_fingerprint != null and self.pending_archive_resulting_cursor == null) return error.InvalidFrameEncoding;
                if (self.pending_archive_resulting_cursor) |cursor| {
                    try cursor.validate();
                    if (cursor.metadata_bytes.len != 0) return error.InvalidFrameEncoding;
                    if (self.pending_archive_append_batch_fingerprint == null) return error.InvalidFrameEncoding;
                }
                if (self.latest_archive_cursor) |cursor| {
                    try cursor.validate();
                    if (cursor.metadata_bytes.len != 0) return error.InvalidFrameEncoding;
                    if (self.latest_chronicle_cursor_fingerprint == null) return error.InvalidFrameEncoding;
                    if (self.latest_chronicle_cursor_fingerprint) |fingerprint| {
                        if (cursor.cursor_fingerprint != fingerprint) return error.InvalidFrameEncoding;
                    }
                }
                if (self.latest_chronicle_cursor_fingerprint != null and self.latest_archive_cursor == null) return error.InvalidFrameEncoding;
                if (self.core_state == .uninitialized and (self.turn_sequence_number != 0 or self.previous_turn_receipt_fingerprint != null or self.outstanding_host_requests.len != 0)) return error.InvalidFrameEncoding;
                if (self.core_state != .uninitialized and self.previous_turn_receipt_fingerprint == null) return error.InvalidFrameEncoding;
                if (self.outstanding_host_requests.len != 0 and self.core_state != .waiting_host) return error.InvalidFrameEncoding;
                if (self.core_state == .waiting_host and self.outstanding_host_requests.len == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.previous_turn_receipt_fingerprint);
                if (self.outstanding_host_requests.len > capacity.max_pending_ports) return error.CapacityExceeded;
                for (self.outstanding_host_requests, 0..) |request, index| {
                    try request.validate(capacity);
                    if (request.turn_sequence_number > self.turn_sequence_number) return error.InvalidFrameEncoding;
                    for (self.outstanding_host_requests[0..index]) |prior| {
                        if (request.request_ordinal == prior.request_ordinal) return error.InvalidFrameEncoding;
                        if (request.request_fingerprint == prior.request_fingerprint) return error.InvalidFrameEncoding;
                    }
                }
                if (self.checkpoint_fingerprint != fingerprintCheckpoint(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU32(out, allocator, self.checkpoint_format_version);
                try writeU32(out, allocator, self.checkpoint_fingerprint_version);
                try writeU64(out, allocator, self.checkpoint_fingerprint);
                try writeU64(out, allocator, self.manifest_fingerprint);
                try writeU64(out, allocator, self.turn_sequence_number);
                try writeU64(out, allocator, self.capsule_fingerprint);
                try writeOptionalU64(out, allocator, self.capsule_image_ref_fingerprint);
                try writeBytes(out, allocator, self.capsule_image_bytes);
                try writeOptionalU64(out, allocator, self.latest_archive_moment_fingerprint);
                try writeOptionalU64(out, allocator, self.latest_archive_seal_fingerprint);
                try writeOptionalU64(out, allocator, self.latest_chronicle_cursor_fingerprint);
                try writeOptionalU64(out, allocator, self.pending_archive_append_batch_fingerprint);
                try writeOptionalCursor(out, allocator, self.pending_archive_resulting_cursor);
                try writeOptionalCursor(out, allocator, self.latest_archive_cursor);
                try writeU8(out, allocator, @intFromEnum(self.core_state));
                try writeOptionalU64(out, allocator, self.previous_turn_receipt_fingerprint);
                try writeU64(out, allocator, self.outstanding_host_requests.len);
                for (self.outstanding_host_requests) |request| try request.encode(out, allocator);
                try writeU8(out, allocator, @intFromEnum(self.execution_mode));
                try writeBytes(out, allocator, self.metadata);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, expected_manifest_fingerprint: u64, capacity: Capacity) !@This() {
                var cursor: usize = 0;
                var checkpoint = try readCheckpointOwned(allocator, bytes, &cursor);
                errdefer checkpoint.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try checkpoint.validate(expected_manifest_fingerprint, capacity);
                return checkpoint;
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var checkpoint = try readCheckpointOwned(allocator, bytes, &cursor);
                errdefer checkpoint.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try checkpoint.validate(checkpoint.manifest_fingerprint, Capacity.archive_decode);
                if (checkpoint.core_state == .runnable) return error.InvalidFrameEncoding;
                return checkpoint;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                freeCheckpoint(allocator, self);
            }
        };

        pub const TurnReceipt = struct {
            receipt_format_version: u32 = World.world_appliance_turn_receipt_format_version,
            receipt_fingerprint_version: u32 = World.world_appliance_turn_receipt_fingerprint_version,
            receipt_fingerprint: u64 = 0,
            manifest_fingerprint: u64,
            turn_sequence_number: u64,
            command_fingerprint: u64,
            prior_checkpoint_fingerprint: ?u64 = null,
            applied_host_reply_fingerprints: []const u64 = &.{},
            emitted_host_request_fingerprints: []const u64 = &.{},
            source_capsule_fingerprint: ?u64 = null,
            resulting_capsule_fingerprint: u64,
            archive_append_batch_fingerprint: ?u64 = null,
            resulting_archive_moment_fingerprint: ?u64 = null,
            resulting_archive_seal_fingerprint: ?u64 = null,
            resulting_chronicle_cursor_fingerprint: ?u64 = null,
            root_result_fingerprint: ?u64 = null,
            status: TurnStatus,
            run_receipt_fingerprint: ?u64 = null,
            blocker_count: usize = 0,
            warning_count: usize = 0,
            owns_payloads: bool = false,

            pub fn init(args: struct {
                manifest_fingerprint: u64,
                turn_sequence_number: u64,
                command_fingerprint: u64,
                prior_checkpoint_fingerprint: ?u64 = null,
                applied_host_reply_fingerprints: []const u64 = &.{},
                emitted_host_request_fingerprints: []const u64 = &.{},
                source_capsule_fingerprint: ?u64 = null,
                resulting_capsule_fingerprint: u64,
                archive_append_batch_fingerprint: ?u64 = null,
                resulting_archive_moment_fingerprint: ?u64 = null,
                resulting_archive_seal_fingerprint: ?u64 = null,
                resulting_chronicle_cursor_fingerprint: ?u64 = null,
                root_result_fingerprint: ?u64 = null,
                status: TurnStatus,
                run_receipt_fingerprint: ?u64 = null,
                blocker_count: usize = 0,
                warning_count: usize = 0,
            }) @This() {
                var result = @This(){
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .turn_sequence_number = args.turn_sequence_number,
                    .command_fingerprint = args.command_fingerprint,
                    .prior_checkpoint_fingerprint = args.prior_checkpoint_fingerprint,
                    .applied_host_reply_fingerprints = args.applied_host_reply_fingerprints,
                    .emitted_host_request_fingerprints = args.emitted_host_request_fingerprints,
                    .source_capsule_fingerprint = args.source_capsule_fingerprint,
                    .resulting_capsule_fingerprint = args.resulting_capsule_fingerprint,
                    .archive_append_batch_fingerprint = args.archive_append_batch_fingerprint,
                    .resulting_archive_moment_fingerprint = args.resulting_archive_moment_fingerprint,
                    .resulting_archive_seal_fingerprint = args.resulting_archive_seal_fingerprint,
                    .resulting_chronicle_cursor_fingerprint = args.resulting_chronicle_cursor_fingerprint,
                    .root_result_fingerprint = args.root_result_fingerprint,
                    .status = args.status,
                    .run_receipt_fingerprint = args.run_receipt_fingerprint,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                };
                result.receipt_fingerprint = fingerprintTurnReceipt(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64, capacity: Capacity) !void {
                if (self.receipt_format_version != World.world_appliance_turn_receipt_format_version) return error.InvalidFrameEncoding;
                if (self.receipt_fingerprint_version != World.world_appliance_turn_receipt_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.command_fingerprint == 0 or self.resulting_capsule_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.prior_checkpoint_fingerprint);
                try validateOptionalFingerprint(self.source_capsule_fingerprint);
                if (self.prior_checkpoint_fingerprint != null and self.source_capsule_fingerprint == null) return error.InvalidFrameEncoding;
                if (self.applied_host_reply_fingerprints.len > capacity.max_host_replies_per_turn) return error.CapacityExceeded;
                if (self.emitted_host_request_fingerprints.len > capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                for (self.applied_host_reply_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.emitted_host_request_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                if (self.status != .needs_host and self.emitted_host_request_fingerprints.len != 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.archive_append_batch_fingerprint);
                try validateOptionalFingerprint(self.resulting_archive_moment_fingerprint);
                try validateOptionalFingerprint(self.resulting_archive_seal_fingerprint);
                try validateOptionalFingerprint(self.resulting_chronicle_cursor_fingerprint);
                try validateArchiveAnchorTuple(self.resulting_archive_moment_fingerprint, self.resulting_archive_seal_fingerprint, self.resulting_chronicle_cursor_fingerprint);
                try validateOptionalFingerprint(self.root_result_fingerprint);
                if (self.status == .completed) {
                    if (self.root_result_fingerprint == null) return error.InvalidFrameEncoding;
                } else if (self.root_result_fingerprint != null) {
                    return error.InvalidFrameEncoding;
                }
                try validateOptionalFingerprint(self.run_receipt_fingerprint);
                if (self.receipt_fingerprint != fingerprintTurnReceipt(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU32(out, allocator, self.receipt_format_version);
                try writeU32(out, allocator, self.receipt_fingerprint_version);
                try writeU64(out, allocator, self.receipt_fingerprint);
                try writeU64(out, allocator, self.manifest_fingerprint);
                try writeU64(out, allocator, self.turn_sequence_number);
                try writeU64(out, allocator, self.command_fingerprint);
                try writeOptionalU64(out, allocator, self.prior_checkpoint_fingerprint);
                try writeU64(out, allocator, @intCast(self.applied_host_reply_fingerprints.len));
                for (self.applied_host_reply_fingerprints) |fingerprint| try writeU64(out, allocator, fingerprint);
                try writeU64(out, allocator, @intCast(self.emitted_host_request_fingerprints.len));
                for (self.emitted_host_request_fingerprints) |fingerprint| try writeU64(out, allocator, fingerprint);
                try writeOptionalU64(out, allocator, self.source_capsule_fingerprint);
                try writeU64(out, allocator, self.resulting_capsule_fingerprint);
                try writeOptionalU64(out, allocator, self.archive_append_batch_fingerprint);
                try writeOptionalU64(out, allocator, self.resulting_archive_moment_fingerprint);
                try writeOptionalU64(out, allocator, self.resulting_archive_seal_fingerprint);
                try writeOptionalU64(out, allocator, self.resulting_chronicle_cursor_fingerprint);
                try writeOptionalU64(out, allocator, self.root_result_fingerprint);
                try writeU8(out, allocator, @intFromEnum(self.status));
                try writeOptionalU64(out, allocator, self.run_receipt_fingerprint);
                try writeU64(out, allocator, self.blocker_count);
                try writeU64(out, allocator, self.warning_count);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, expected_manifest_fingerprint: u64) !@This() {
                var cursor: usize = 0;
                var receipt = try readTurnReceiptOwned(allocator, bytes, &cursor);
                errdefer receipt.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try receipt.validate(expected_manifest_fingerprint, Capacity.large_native_test);
                return receipt;
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var receipt = try readTurnReceiptOwned(allocator, bytes, &cursor);
                errdefer receipt.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try receipt.validate(receipt.manifest_fingerprint, Capacity.archive_decode);
                return receipt;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                freeTurnReceipt(allocator, self);
            }
        };

        pub const TurnOutput = struct {
            output_format_version: u32 = World.world_appliance_turn_output_format_version,
            output_fingerprint_version: u32 = World.world_appliance_turn_output_fingerprint_version,
            output_fingerprint: u64 = 0,
            manifest_fingerprint: u64,
            turn_sequence_number: u64,
            source_state_fingerprint: u64,
            resulting_state_fingerprint: u64,
            quiescence: QuiescenceReport,
            status: TurnStatus,
            host_requests: []const HostRequest = &.{},
            finalized_actuation_receipt_fingerprints: []const u64 = &.{},
            root_result_fingerprint: ?u64 = null,
            root_result_value_image_bytes: []const u8 = "",
            root_result_value_ref_fingerprint: ?u64 = null,
            run_receipt_fingerprint: ?u64 = null,
            run_receipt_bytes: []const u8 = "",
            archive_append_batch_fingerprint: ?u64 = null,
            archive_append_batch_ref_fingerprint: ?u64 = null,
            checkpoint_bytes: []const u8 = "",
            archive_append_batch_bytes: []const u8 = "",
            checkpoint: Checkpoint,
            turn_receipt: TurnReceipt,
            blocker_count: usize = 0,
            warning_count: usize = 0,
            diagnostic_metadata: []const u8 = "",
            owns_host_requests: bool = false,
            owns_finalized_actuation_receipt_fingerprints: bool = false,
            owns_checkpoint_payloads: bool = false,
            owns_turn_receipt_payloads: bool = false,
            owns_diagnostic_metadata: bool = false,
            owns_byte_payloads: bool = false,

            pub fn init(args: struct {
                manifest_fingerprint: u64,
                turn_sequence_number: u64,
                source_state_fingerprint: u64,
                resulting_state_fingerprint: u64,
                quiescence: QuiescenceReport,
                status: TurnStatus,
                host_requests: []const HostRequest = &.{},
                finalized_actuation_receipt_fingerprints: []const u64 = &.{},
                root_result_fingerprint: ?u64 = null,
                root_result_value_image_bytes: []const u8 = "",
                root_result_value_ref_fingerprint: ?u64 = null,
                run_receipt_fingerprint: ?u64 = null,
                run_receipt_bytes: []const u8 = "",
                archive_append_batch_fingerprint: ?u64 = null,
                archive_append_batch_ref_fingerprint: ?u64 = null,
                checkpoint_bytes: []const u8 = "",
                archive_append_batch_bytes: []const u8 = "",
                checkpoint: Checkpoint,
                turn_receipt: TurnReceipt,
                blocker_count: usize = 0,
                warning_count: usize = 0,
                diagnostic_metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .turn_sequence_number = args.turn_sequence_number,
                    .source_state_fingerprint = args.source_state_fingerprint,
                    .resulting_state_fingerprint = args.resulting_state_fingerprint,
                    .quiescence = args.quiescence,
                    .status = args.status,
                    .host_requests = args.host_requests,
                    .finalized_actuation_receipt_fingerprints = args.finalized_actuation_receipt_fingerprints,
                    .root_result_fingerprint = args.root_result_fingerprint,
                    .root_result_value_image_bytes = args.root_result_value_image_bytes,
                    .root_result_value_ref_fingerprint = args.root_result_value_ref_fingerprint,
                    .run_receipt_fingerprint = args.run_receipt_fingerprint,
                    .run_receipt_bytes = args.run_receipt_bytes,
                    .archive_append_batch_fingerprint = args.archive_append_batch_fingerprint,
                    .archive_append_batch_ref_fingerprint = args.archive_append_batch_ref_fingerprint orelse defaultArchiveAppendBatchRef(args.archive_append_batch_fingerprint),
                    .checkpoint_bytes = args.checkpoint_bytes,
                    .archive_append_batch_bytes = args.archive_append_batch_bytes,
                    .checkpoint = args.checkpoint,
                    .turn_receipt = args.turn_receipt,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                    .diagnostic_metadata = args.diagnostic_metadata,
                };
                result.output_fingerprint = fingerprintTurnOutput(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64, capacity: Capacity) !void {
                if (self.output_format_version != World.world_appliance_turn_output_format_version) return error.InvalidFrameEncoding;
                if (self.output_fingerprint_version != World.world_appliance_turn_output_fingerprint_version) return error.InvalidFrameEncoding;
                if (expected_manifest_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.source_state_fingerprint == 0 or self.resulting_state_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.root_result_fingerprint);
                try self.quiescence.validate();
                if (!self.quiescence.quiescent or self.quiescence.runnable_run_count != 0 or self.quiescence.parked_run_count != 0 or self.quiescence.active_fabric_count != 0) return error.InvalidFrameEncoding;
                if (self.host_requests.len > capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                if (self.status == .needs_host and self.host_requests.len == 0) return error.InvalidFrameEncoding;
                if (self.status != .needs_host and self.host_requests.len != 0) return error.InvalidFrameEncoding;
                if (self.quiescence.pending_host_request_count != self.checkpoint.outstanding_host_requests.len) return error.InvalidFrameEncoding;
                if (self.quiescence.prepared_actuation_count != self.host_requests.len) return error.InvalidFrameEncoding;
                if (self.quiescence.completed_run_count != if (self.status == .completed) @as(usize, 1) else @as(usize, 0)) return error.InvalidFrameEncoding;
                if (self.quiescence.failed_run_count != if (self.status == .failed) @as(usize, 1) else @as(usize, 0)) return error.InvalidFrameEncoding;
                for (self.host_requests, 0..) |request, index| {
                    try request.validate(capacity);
                    if (request.turn_sequence_number > self.turn_sequence_number) return error.InvalidFrameEncoding;
                    for (self.host_requests[0..index]) |prior| {
                        if (request.request_ordinal == prior.request_ordinal) return error.InvalidFrameEncoding;
                        if (request.request_fingerprint == prior.request_fingerprint) return error.InvalidFrameEncoding;
                    }
                }
                if (self.finalized_actuation_receipt_fingerprints.len > capacity.max_actuation_records) return error.CapacityExceeded;
                for (self.finalized_actuation_receipt_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                if (self.status == .needs_host) {
                    if (self.finalized_actuation_receipt_fingerprints.len > self.turn_receipt.applied_host_reply_fingerprints.len) return error.InvalidFrameEncoding;
                } else if (self.finalized_actuation_receipt_fingerprints.len != self.turn_receipt.applied_host_reply_fingerprints.len) {
                    return error.InvalidFrameEncoding;
                }
                try validateOptionalFingerprint(self.run_receipt_fingerprint);
                try validateOptionalFingerprint(self.archive_append_batch_fingerprint);
                try validateOptionalFingerprint(self.archive_append_batch_ref_fingerprint);
                if (self.archive_append_batch_fingerprint == null and self.archive_append_batch_ref_fingerprint != null) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_fingerprint != null and self.archive_append_batch_ref_fingerprint == null) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_ref_fingerprint != defaultArchiveAppendBatchRef(self.archive_append_batch_fingerprint)) return error.InvalidFrameEncoding;
                if (self.diagnostic_metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                try self.checkpoint.validate(expected_manifest_fingerprint, capacity);
                try self.turn_receipt.validate(expected_manifest_fingerprint, capacity);
                if (self.turn_sequence_number != self.checkpoint.turn_sequence_number and !(self.checkpoint.core_state == .uninitialized and self.checkpoint.turn_sequence_number == 0)) return error.InvalidFrameEncoding;
                if (self.turn_sequence_number != self.turn_receipt.turn_sequence_number) return error.InvalidFrameEncoding;
                if (self.checkpoint.capsule_fingerprint != self.turn_receipt.resulting_capsule_fingerprint) return error.InvalidFrameEncoding;
                if (self.status != self.turn_receipt.status) return error.InvalidFrameEncoding;
                if (self.status == .inspected and self.checkpoint.core_state == .runnable) return error.InvalidFrameEncoding;
                if (self.status == .inspected) {
                    const checkpoint_state_fingerprint = stateFingerprintFor(self.checkpoint.core_state, self.checkpoint.turn_sequence_number, self.checkpoint.previous_turn_receipt_fingerprint);
                    if (checkpoint_state_fingerprint != self.source_state_fingerprint) return error.InvalidFrameEncoding;
                } else if (self.checkpoint.core_state != stateForStatus(self.status)) {
                    if (!(self.status == .cancelled and self.checkpoint.core_state == .uninitialized)) return error.InvalidFrameEncoding;
                }
                if (self.root_result_fingerprint != self.turn_receipt.root_result_fingerprint) return error.InvalidFrameEncoding;
                if (self.status == .completed) {
                    if (self.root_result_fingerprint == null) return error.InvalidFrameEncoding;
                } else if (self.root_result_fingerprint != null) {
                    return error.InvalidFrameEncoding;
                } else if (self.root_result_value_image_bytes.len != 0 or self.root_result_value_ref_fingerprint != null) {
                    return error.InvalidFrameEncoding;
                }
                try validateOptionalFingerprint(self.root_result_value_ref_fingerprint);
                if (self.run_receipt_fingerprint != self.turn_receipt.run_receipt_fingerprint) return error.InvalidFrameEncoding;
                if (self.run_receipt_fingerprint == null and self.run_receipt_bytes.len != 0) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_fingerprint != self.turn_receipt.archive_append_batch_fingerprint) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_fingerprint != null and self.archive_append_batch_fingerprint != self.checkpoint.pending_archive_append_batch_fingerprint) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_fingerprint == null and self.archive_append_batch_bytes.len != 0) return error.InvalidFrameEncoding;
                if (self.root_result_value_image_bytes.len > capacity.max_output_bytes) return error.CapacityExceeded;
                if (self.run_receipt_bytes.len > capacity.max_output_bytes) return error.CapacityExceeded;
                if (self.checkpoint_bytes.len > capacity.max_output_bytes) return error.CapacityExceeded;
                if (self.archive_append_batch_bytes.len > capacity.max_archive_append_bytes) return error.CapacityExceeded;
                if (self.blocker_count != self.turn_receipt.blocker_count or self.blocker_count != self.quiescence.blocker_count) return error.InvalidFrameEncoding;
                if (self.warning_count != self.turn_receipt.warning_count or self.warning_count != self.quiescence.warning_count) return error.InvalidFrameEncoding;
                if (self.status == .blocked and self.blocker_count == 0) return error.InvalidFrameEncoding;
                if (self.turn_receipt.emitted_host_request_fingerprints.len != self.host_requests.len) return error.InvalidFrameEncoding;
                for (self.host_requests, self.turn_receipt.emitted_host_request_fingerprints) |request, receipt_fingerprint| {
                    if (request.request_fingerprint != receipt_fingerprint) return error.InvalidFrameEncoding;
                }
                if (self.status == .needs_host) {
                    if (self.checkpoint.outstanding_host_requests.len != self.host_requests.len) return error.InvalidFrameEncoding;
                    for (self.host_requests, self.checkpoint.outstanding_host_requests) |request, checkpoint_request| {
                        if (request.request_fingerprint != checkpoint_request.request_fingerprint) return error.InvalidFrameEncoding;
                    }
                }
                const expected_resulting_state_fingerprint = if (self.status == .inspected)
                    self.source_state_fingerprint
                else if (self.checkpoint.core_state == .uninitialized)
                    stateFingerprintFor(.uninitialized, 0, null)
                else blk: {
                    if (self.checkpoint.previous_turn_receipt_fingerprint != self.turn_receipt.receipt_fingerprint) return error.InvalidFrameEncoding;
                    break :blk stateFingerprintFor(self.checkpoint.core_state, self.turn_sequence_number, self.turn_receipt.receipt_fingerprint);
                };
                if (self.resulting_state_fingerprint != expected_resulting_state_fingerprint) return error.InvalidFrameEncoding;
                if (self.output_fingerprint != fingerprintTurnOutput(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
                var out: std.ArrayList(u8) = .empty;
                errdefer out.deinit(allocator);
                try writeU32(&out, allocator, self.output_format_version);
                try writeU32(&out, allocator, self.output_fingerprint_version);
                try writeU64(&out, allocator, self.output_fingerprint);
                try writeU64(&out, allocator, self.manifest_fingerprint);
                try writeU64(&out, allocator, self.turn_sequence_number);
                try writeU64(&out, allocator, self.source_state_fingerprint);
                try writeU64(&out, allocator, self.resulting_state_fingerprint);
                try self.quiescence.encode(&out, allocator);
                try writeU8(&out, allocator, @intFromEnum(self.status));
                try writeU64(&out, allocator, @intCast(self.host_requests.len));
                for (self.host_requests) |request| try request.encode(&out, allocator);
                try writeU64Slice(&out, allocator, self.finalized_actuation_receipt_fingerprints);
                try writeOptionalU64(&out, allocator, self.root_result_fingerprint);
                try writeBytes(&out, allocator, self.root_result_value_image_bytes);
                try writeOptionalU64(&out, allocator, self.root_result_value_ref_fingerprint);
                try writeOptionalU64(&out, allocator, self.run_receipt_fingerprint);
                try writeBytes(&out, allocator, self.run_receipt_bytes);
                try writeOptionalU64(&out, allocator, self.archive_append_batch_fingerprint);
                try writeOptionalU64(&out, allocator, self.archive_append_batch_ref_fingerprint);
                try writeBytes(&out, allocator, self.checkpoint_bytes);
                try writeBytes(&out, allocator, self.archive_append_batch_bytes);
                try self.checkpoint.encode(&out, allocator);
                try self.turn_receipt.encode(&out, allocator);
                try writeU64(&out, allocator, self.blocker_count);
                try writeU64(&out, allocator, self.warning_count);
                try writeBytes(&out, allocator, self.diagnostic_metadata);
                return out.toOwnedSlice(allocator);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, expected_manifest_fingerprint: u64, capacity: Capacity) !@This() {
                var cursor: usize = 0;
                var output = try readTurnOutputOwned(allocator, bytes, &cursor);
                errdefer output.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try output.validate(expected_manifest_fingerprint, capacity);
                return output;
            }

            pub fn decodeArchivePayload(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var cursor: usize = 0;
                var output = try readTurnOutputOwned(allocator, bytes, &cursor);
                errdefer output.deinit(allocator);
                if (cursor != bytes.len) return error.InvalidFrameEncoding;
                try output.validate(output.manifest_fingerprint, Capacity.archive_decode);
                return output;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                freeTurnOutput(allocator, self);
            }
        };

        pub const RetentionAck = struct {
            append_batch_fingerprint: u64,
            resulting_moment_fingerprint: u64,
            resulting_seal_fingerprint: u64,
            resulting_chronicle_cursor_fingerprint: u64,
            host_claim_status: HostOutcomeStatus,
            metadata: []const u8 = "",
            ack_fingerprint: u64 = 0,

            pub fn init(args: struct {
                append_batch_fingerprint: u64,
                resulting_moment_fingerprint: u64,
                resulting_seal_fingerprint: u64,
                resulting_chronicle_cursor_fingerprint: u64,
                host_claim_status: HostOutcomeStatus,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .append_batch_fingerprint = args.append_batch_fingerprint,
                    .resulting_moment_fingerprint = args.resulting_moment_fingerprint,
                    .resulting_seal_fingerprint = args.resulting_seal_fingerprint,
                    .resulting_chronicle_cursor_fingerprint = args.resulting_chronicle_cursor_fingerprint,
                    .host_claim_status = args.host_claim_status,
                    .metadata = args.metadata,
                };
                result.ack_fingerprint = fingerprintRetentionAck(result);
                return result;
            }

            pub fn validate(self: @This(), expected_append_batch_fingerprint: ?u64, capacity: Capacity) !void {
                if (self.append_batch_fingerprint == 0 or self.resulting_moment_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.resulting_seal_fingerprint == 0 or self.resulting_chronicle_cursor_fingerprint == 0) return error.InvalidFrameEncoding;
                if (expected_append_batch_fingerprint) |expected| {
                    if (self.append_batch_fingerprint != expected) return error.ArchiveParentMismatch;
                }
                if (self.host_claim_status != .responded) return error.ArchiveParentMismatch;
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
                if (self.ack_fingerprint != fingerprintRetentionAck(self)) return error.InvalidFrameEncoding;
            }

            pub fn encode(self: @This(), out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
                try writeU64(out, allocator, self.append_batch_fingerprint);
                try writeU64(out, allocator, self.resulting_moment_fingerprint);
                try writeU64(out, allocator, self.resulting_seal_fingerprint);
                try writeU64(out, allocator, self.resulting_chronicle_cursor_fingerprint);
                try writeU8(out, allocator, @intFromEnum(self.host_claim_status));
                try writeBytes(out, allocator, self.metadata);
                try writeU64(out, allocator, self.ack_fingerprint);
            }
        };

        pub const ArchivePlan = struct {
            allocator: std.mem.Allocator,
            parent_cursor: World.Continuity.Chronicle.Cursor,
            resulting_cursor: World.Continuity.Chronicle.Cursor,
            objects: []World.Continuity.ObjectEnvelope,
            object_refs: []World.Continuity.ObjectRef,
            events: []World.Continuity.Chronicle.Event,
            event_fingerprints: []u64,
            commit: World.Continuity.Chronicle.Commit,
            append_batch: World.Archive.AppendBatch,

            pub fn initForTurnOutput(
                allocator: std.mem.Allocator,
                parent_cursor: World.Continuity.Chronicle.Cursor,
                output: TurnOutput,
                capacity: Capacity,
            ) !@This() {
                try output.validate(output.manifest_fingerprint, capacity);
                try parent_cursor.validate();
                const archive_output = archiveNeutralTurnOutput(output);
                try archive_output.validate(output.manifest_fingerprint, capacity);

                const checkpoint_payload = try encodeCheckpointOwned(allocator, archive_output.checkpoint);
                defer allocator.free(checkpoint_payload);
                const receipt_payload = try encodeTurnReceiptOwned(allocator, archive_output.turn_receipt);
                defer allocator.free(receipt_payload);
                const output_payload = try archive_output.encode(allocator);
                defer allocator.free(output_payload);

                var objects = try allocator.alloc(World.Continuity.ObjectEnvelope, 3);
                var object_count: usize = 0;
                errdefer {
                    for (objects[0..object_count]) |*object| object.deinit(allocator);
                    allocator.free(objects);
                }

                objects[0] = try cloneEnvelope(allocator, World.Continuity.ObjectEnvelope.init(.{
                    .kind = .appliance_checkpoint,
                    .payload_bytes = checkpoint_payload,
                    .label = "appliance.checkpoint",
                }));
                object_count += 1;

                objects[1] = try cloneEnvelope(allocator, World.Continuity.ObjectEnvelope.init(.{
                    .kind = .appliance_turn_receipt,
                    .payload_bytes = receipt_payload,
                    .label = "appliance.turn_receipt",
                }));
                object_count += 1;

                var refs = try allocator.alloc(World.Continuity.ObjectRef, 3);
                errdefer allocator.free(refs);
                refs[0] = objects[0].objectRef();
                refs[1] = objects[1].objectRef();

                var output_probe = try cloneEnvelope(allocator, World.Continuity.ObjectEnvelope.init(.{
                    .kind = .appliance_turn_output,
                    .dependency_refs = &.{},
                    .payload_bytes = output_payload,
                    .label = "appliance.turn_output",
                }));
                defer output_probe.deinit(allocator);
                const output_deps = try World.Continuity.objectEnvelopeRequiredDependencyRefs(allocator, output_probe);
                defer allocator.free(output_deps);
                objects[2] = try cloneEnvelope(allocator, World.Continuity.ObjectEnvelope.init(.{
                    .kind = .appliance_turn_output,
                    .dependency_refs = output_deps,
                    .payload_bytes = output_payload,
                    .label = "appliance.turn_output",
                }));
                object_count += 1;
                refs[2] = objects[2].objectRef();

                var events = try allocator.alloc(World.Continuity.Chronicle.Event, 1);
                errdefer allocator.free(events);
                var event_fingerprints = try allocator.alloc(u64, 1);
                errdefer allocator.free(event_fingerprints);

                const transaction_fingerprint = fingerprintArchiveTransaction(parent_cursor, archive_output, refs);
                events[0] = World.Continuity.Chronicle.Event.init(.{
                    .kind = .object_committed,
                    .transaction_fingerprint = transaction_fingerprint,
                    .object_refs = refs,
                    .target_ref = refs[2],
                    .metadata_bytes = "appliance.turn",
                });
                try events[0].validate();
                event_fingerprints[0] = events[0].event_fingerprint;

                const resulting_cursor = parent_cursor.advance(event_fingerprints, refs.len, 1);
                const commit = World.Continuity.Chronicle.Commit.init(.{
                    .transaction_fingerprint = transaction_fingerprint,
                    .parent_cursor_fingerprint = parent_cursor.cursor_fingerprint,
                    .resulting_cursor_fingerprint = resulting_cursor.cursor_fingerprint,
                    .committed_object_refs = refs,
                    .committed_event_fingerprints = event_fingerprints,
                    .metadata_bytes = "appliance.turn",
                });
                try commit.validate();

                const append_batch = World.Archive.AppendBatch.init(.{
                    .parent_cursor = parent_cursor,
                    .commit = commit,
                    .events = events,
                    .objects = objects,
                    .diagnostic_metadata_bytes = "appliance.turn",
                });
                try append_batch.validate();
                const append_batch_byte_len = try World.Archive.appendBatchSerializedByteLen(allocator, append_batch);
                if (append_batch_byte_len > capacity.max_archive_append_bytes) return error.CapacityExceeded;

                return .{
                    .allocator = allocator,
                    .parent_cursor = parent_cursor,
                    .resulting_cursor = resulting_cursor,
                    .objects = objects,
                    .object_refs = refs,
                    .events = events,
                    .event_fingerprints = event_fingerprints,
                    .commit = commit,
                    .append_batch = append_batch,
                };
            }

            pub fn deinit(self: *@This()) void {
                for (self.objects) |*object| object.deinit(self.allocator);
                self.allocator.free(self.objects);
                self.allocator.free(self.object_refs);
                self.allocator.free(self.events);
                self.allocator.free(self.event_fingerprints);
                self.* = undefined;
            }
        };

        pub const ReconstructionReport = struct {
            report_fingerprint: u64 = 0,
            manifest_fingerprint: u64,
            resident_turn_output_fingerprint: u64,
            reconstructed_turn_output_fingerprint: u64,
            equivalent: bool,
            mismatch_count: usize = 0,

            pub fn init(args: struct {
                manifest_fingerprint: u64,
                resident_turn_output_fingerprint: u64,
                reconstructed_turn_output_fingerprint: u64,
            }) @This() {
                const equivalent = args.resident_turn_output_fingerprint == args.reconstructed_turn_output_fingerprint;
                var result = @This(){
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .resident_turn_output_fingerprint = args.resident_turn_output_fingerprint,
                    .reconstructed_turn_output_fingerprint = args.reconstructed_turn_output_fingerprint,
                    .equivalent = equivalent,
                    .mismatch_count = if (equivalent) 0 else 1,
                };
                result.report_fingerprint = fingerprintReconstructionReport(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64) !void {
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.resident_turn_output_fingerprint == 0 or self.reconstructed_turn_output_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.equivalent != (self.resident_turn_output_fingerprint == self.reconstructed_turn_output_fingerprint)) return error.InvalidFrameEncoding;
                if (self.equivalent and self.mismatch_count != 0) return error.InvalidFrameEncoding;
                if (!self.equivalent and self.mismatch_count == 0) return error.InvalidFrameEncoding;
                if (self.report_fingerprint != fingerprintReconstructionReport(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const ConformanceVector = struct {
            vector_fingerprint_version: u32 = World.world_appliance_conformance_vector_fingerprint_version,
            vector_fingerprint: u64 = 0,
            kind: ConformanceVectorKind = .one_port,
            name: []const u8,
            manifest_fingerprint: u64,
            initial_command_fingerprint: u64 = 0,
            expected_turn_output_fingerprint: ?u64 = null,
            host_reply_sequence_fingerprints: []const u64 = &.{},
            expected_status_sequence: []const TurnStatus = &.{},
            expected_status_fingerprint: u64 = 0,
            expected_host_request_fingerprints: []const u64 = &.{},
            expected_checkpoint_fingerprints: []const u64 = &.{},
            expected_archive_append_fingerprint: ?u64 = null,
            expected_archive_append_fingerprints: []const u64 = &.{},
            expected_final_result_fingerprint: ?u64 = null,
            expected_resident_reconstructed_equivalence: bool = true,

            pub fn init(args: struct {
                kind: ConformanceVectorKind = .one_port,
                name: []const u8,
                manifest_fingerprint: u64,
                initial_command_fingerprint: u64 = 0,
                expected_turn_output_fingerprint: ?u64 = null,
                host_reply_sequence_fingerprints: []const u64 = &.{},
                expected_status_sequence: []const TurnStatus = &.{},
                expected_status_fingerprint: u64 = 0,
                expected_host_request_fingerprints: []const u64 = &.{},
                expected_checkpoint_fingerprints: []const u64 = &.{},
                expected_archive_append_fingerprint: ?u64 = null,
                expected_archive_append_fingerprints: []const u64 = &.{},
                expected_final_result_fingerprint: ?u64 = null,
                expected_resident_reconstructed_equivalence: bool = true,
            }) @This() {
                var result = @This(){
                    .kind = args.kind,
                    .name = args.name,
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .initial_command_fingerprint = args.initial_command_fingerprint,
                    .expected_turn_output_fingerprint = args.expected_turn_output_fingerprint,
                    .host_reply_sequence_fingerprints = args.host_reply_sequence_fingerprints,
                    .expected_status_sequence = args.expected_status_sequence,
                    .expected_status_fingerprint = args.expected_status_fingerprint,
                    .expected_host_request_fingerprints = args.expected_host_request_fingerprints,
                    .expected_checkpoint_fingerprints = args.expected_checkpoint_fingerprints,
                    .expected_archive_append_fingerprint = args.expected_archive_append_fingerprint,
                    .expected_archive_append_fingerprints = args.expected_archive_append_fingerprints,
                    .expected_final_result_fingerprint = args.expected_final_result_fingerprint,
                    .expected_resident_reconstructed_equivalence = args.expected_resident_reconstructed_equivalence,
                };
                result.vector_fingerprint = fingerprintConformanceVector(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64) !void {
                if (self.vector_fingerprint_version != World.world_appliance_conformance_vector_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.name.len == 0) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                try validateOptionalFingerprint(self.expected_turn_output_fingerprint);
                try validateFingerprintSlice(self.host_reply_sequence_fingerprints);
                if (self.expected_status_sequence.len == 0 and self.expected_status_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateFingerprintSlice(self.expected_host_request_fingerprints);
                try validateFingerprintSlice(self.expected_checkpoint_fingerprints);
                try validateOptionalFingerprint(self.expected_archive_append_fingerprint);
                try validateFingerprintSlice(self.expected_archive_append_fingerprints);
                try validateOptionalFingerprint(self.expected_final_result_fingerprint);
                if (self.vector_fingerprint != fingerprintConformanceVector(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const ConformanceReport = struct {
            report_fingerprint_version: u32 = World.world_appliance_conformance_report_fingerprint_version,
            report_fingerprint: u64 = 0,
            vector_fingerprint: u64,
            manifest_fingerprint: u64,
            direct_native_owner_output_fingerprint: ?u64 = null,
            appliance_native_output_fingerprint: ?u64 = null,
            native_core_output_fingerprint: u64,
            resident_core_output_fingerprint: u64,
            reconstructed_core_output_fingerprint: u64,
            wasm_manifest_fingerprint: ?u64 = null,
            wasm_required_exports_present: bool = false,
            wasm_forbidden_import_count: usize = 0,
            wasm_inspection_passed: bool = false,
            external_runtime_output_fingerprint: ?u64 = null,
            replay_output_fingerprint: ?u64 = null,
            archive_append_batch_fingerprint: ?u64 = null,
            archive_replay_projection_fingerprint: ?u64 = null,
            equivalence_trace_digest: u64 = 0,
            passed: bool = false,

            pub fn init(args: struct {
                vector_fingerprint: u64,
                manifest_fingerprint: u64,
                direct_native_owner_output_fingerprint: ?u64 = null,
                appliance_native_output_fingerprint: ?u64 = null,
                native_core_output_fingerprint: u64,
                resident_core_output_fingerprint: u64,
                reconstructed_core_output_fingerprint: u64,
                wasm_manifest_fingerprint: ?u64 = null,
                wasm_required_exports_present: bool = false,
                wasm_forbidden_import_count: usize = 0,
                wasm_inspection_passed: bool = false,
                external_runtime_output_fingerprint: ?u64 = null,
                replay_output_fingerprint: ?u64 = null,
                archive_append_batch_fingerprint: ?u64 = null,
                archive_replay_projection_fingerprint: ?u64 = null,
            }) @This() {
                var result = @This(){
                    .vector_fingerprint = args.vector_fingerprint,
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .direct_native_owner_output_fingerprint = args.direct_native_owner_output_fingerprint,
                    .appliance_native_output_fingerprint = args.appliance_native_output_fingerprint,
                    .native_core_output_fingerprint = args.native_core_output_fingerprint,
                    .resident_core_output_fingerprint = args.resident_core_output_fingerprint,
                    .reconstructed_core_output_fingerprint = args.reconstructed_core_output_fingerprint,
                    .wasm_manifest_fingerprint = args.wasm_manifest_fingerprint,
                    .wasm_required_exports_present = args.wasm_required_exports_present,
                    .wasm_forbidden_import_count = args.wasm_forbidden_import_count,
                    .wasm_inspection_passed = args.wasm_inspection_passed,
                    .external_runtime_output_fingerprint = args.external_runtime_output_fingerprint,
                    .replay_output_fingerprint = args.replay_output_fingerprint,
                    .archive_append_batch_fingerprint = args.archive_append_batch_fingerprint,
                    .archive_replay_projection_fingerprint = args.archive_replay_projection_fingerprint,
                };
                result.equivalence_trace_digest = fingerprintConformanceTrace(result);
                result.passed =
                    (result.direct_native_owner_output_fingerprint == null or result.direct_native_owner_output_fingerprint.? == result.native_core_output_fingerprint) and
                    (result.appliance_native_output_fingerprint == null or result.appliance_native_output_fingerprint.? == result.native_core_output_fingerprint) and
                    result.native_core_output_fingerprint == result.resident_core_output_fingerprint and
                    result.native_core_output_fingerprint == result.reconstructed_core_output_fingerprint and
                    (result.wasm_manifest_fingerprint == null or (result.wasm_manifest_fingerprint.? == result.manifest_fingerprint and result.wasm_required_exports_present and result.wasm_forbidden_import_count == 0 and result.wasm_inspection_passed)) and
                    (result.external_runtime_output_fingerprint == null or result.external_runtime_output_fingerprint.? == result.native_core_output_fingerprint) and
                    (result.replay_output_fingerprint == null or result.replay_output_fingerprint.? == result.native_core_output_fingerprint) and
                    (result.archive_append_batch_fingerprint == null or result.archive_append_batch_fingerprint.? != 0) and
                    (result.archive_replay_projection_fingerprint == null or result.archive_replay_projection_fingerprint.? != 0);
                result.report_fingerprint = fingerprintConformanceReport(result);
                return result;
            }

            pub fn validate(self: @This(), expected_manifest_fingerprint: u64) !void {
                if (self.report_fingerprint_version != World.world_appliance_conformance_report_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.vector_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.native_core_output_fingerprint == 0 or self.resident_core_output_fingerprint == 0 or self.reconstructed_core_output_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.direct_native_owner_output_fingerprint);
                try validateOptionalFingerprint(self.appliance_native_output_fingerprint);
                try validateOptionalFingerprint(self.wasm_manifest_fingerprint);
                if (self.wasm_manifest_fingerprint == null and (self.wasm_required_exports_present or self.wasm_forbidden_import_count != 0 or self.wasm_inspection_passed)) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.replay_output_fingerprint);
                try validateOptionalFingerprint(self.external_runtime_output_fingerprint);
                try validateOptionalFingerprint(self.archive_append_batch_fingerprint);
                try validateOptionalFingerprint(self.archive_replay_projection_fingerprint);
                if (self.equivalence_trace_digest != fingerprintConformanceTrace(self)) return error.InvalidFrameEncoding;
                if (self.report_fingerprint != fingerprintConformanceReport(self)) return error.InvalidFrameEncoding;
                if (self.passed != ConformanceReport.init(.{
                    .vector_fingerprint = self.vector_fingerprint,
                    .manifest_fingerprint = self.manifest_fingerprint,
                    .direct_native_owner_output_fingerprint = self.direct_native_owner_output_fingerprint,
                    .appliance_native_output_fingerprint = self.appliance_native_output_fingerprint,
                    .native_core_output_fingerprint = self.native_core_output_fingerprint,
                    .resident_core_output_fingerprint = self.resident_core_output_fingerprint,
                    .reconstructed_core_output_fingerprint = self.reconstructed_core_output_fingerprint,
                    .wasm_manifest_fingerprint = self.wasm_manifest_fingerprint,
                    .wasm_required_exports_present = self.wasm_required_exports_present,
                    .wasm_forbidden_import_count = self.wasm_forbidden_import_count,
                    .wasm_inspection_passed = self.wasm_inspection_passed,
                    .external_runtime_output_fingerprint = self.external_runtime_output_fingerprint,
                    .replay_output_fingerprint = self.replay_output_fingerprint,
                    .archive_append_batch_fingerprint = self.archive_append_batch_fingerprint,
                    .archive_replay_projection_fingerprint = self.archive_replay_projection_fingerprint,
                }).passed) return error.InvalidFrameEncoding;
            }
        };

        pub const Core = struct {
            state: CoreState = .uninitialized,
            allocator: std.mem.Allocator = std.heap.page_allocator,
            manifest_value: Manifest,
            memory_plan_value: MemoryPlan,
            capacity_value: Capacity = Capacity.wasm_small,
            pending_command: ?Command = null,
            last_output_bytes: []const u8 = "",
            last_output_owned: bool = false,
            last_output_status: ?TurnStatus = null,
            last_turn_status: ?TurnStatus = null,
            current_turn_sequence_number: u64 = 0,
            previous_turn_receipt_fingerprint: ?u64 = null,
            outstanding_host_request: ?HostRequest = null,
            outstanding_host_requests: []const HostRequest = &.{},
            outstanding_host_requests_owned: bool = false,
            pending_archive_append_batch_fingerprint: ?u64 = null,
            pending_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor = null,
            latest_archive_cursor: World.Continuity.Chronicle.Cursor = World.Continuity.Chronicle.Cursor.initial(),
            latest_archive_moment_fingerprint: ?u64 = null,
            latest_archive_seal_fingerprint: ?u64 = null,
            latest_chronicle_cursor_fingerprint: ?u64 = null,

            const ContinuationSnapshot = struct {
                state: CoreState,
                current_turn_sequence_number: u64,
                previous_turn_receipt_fingerprint: ?u64,
                outstanding_host_requests: []const HostRequest,
                snapshot_requests_owned: bool = false,
                pending_archive_append_batch_fingerprint: ?u64,
                pending_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor,
                latest_archive_cursor: World.Continuity.Chronicle.Cursor,
                latest_archive_moment_fingerprint: ?u64,
                latest_archive_seal_fingerprint: ?u64,
                latest_chronicle_cursor_fingerprint: ?u64,
                last_output_status: ?TurnStatus,
                last_turn_status: ?TurnStatus,

                fn capture(core: *Core) !@This() {
                    const requests = if (core.outstanding_host_requests.len != 0)
                        try cloneHostRequestsOwned(core.allocator, core.outstanding_host_requests)
                    else if (core.outstanding_host_request) |request|
                        try cloneHostRequestsOwned(core.allocator, &.{request})
                    else
                        try cloneHostRequestsOwned(core.allocator, &.{});
                    return .{
                        .state = core.state,
                        .current_turn_sequence_number = core.current_turn_sequence_number,
                        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
                        .outstanding_host_requests = requests,
                        .snapshot_requests_owned = true,
                        .pending_archive_append_batch_fingerprint = core.pending_archive_append_batch_fingerprint,
                        .pending_archive_resulting_cursor = core.pending_archive_resulting_cursor,
                        .latest_archive_cursor = core.latest_archive_cursor,
                        .latest_archive_moment_fingerprint = core.latest_archive_moment_fingerprint,
                        .latest_archive_seal_fingerprint = core.latest_archive_seal_fingerprint,
                        .latest_chronicle_cursor_fingerprint = core.latest_chronicle_cursor_fingerprint,
                        .last_output_status = core.last_output_status,
                        .last_turn_status = core.last_turn_status,
                    };
                }

                fn restore(self: *@This(), core: *Core) void {
                    core.clearOutstandingHostRequests();
                    core.state = self.state;
                    core.current_turn_sequence_number = self.current_turn_sequence_number;
                    core.previous_turn_receipt_fingerprint = self.previous_turn_receipt_fingerprint;
                    core.outstanding_host_requests = self.outstanding_host_requests;
                    core.outstanding_host_requests_owned = self.snapshot_requests_owned;
                    core.outstanding_host_request = if (self.outstanding_host_requests.len == 0) null else self.outstanding_host_requests[0];
                    core.pending_archive_append_batch_fingerprint = self.pending_archive_append_batch_fingerprint;
                    core.pending_archive_resulting_cursor = self.pending_archive_resulting_cursor;
                    core.latest_archive_cursor = self.latest_archive_cursor;
                    core.latest_archive_moment_fingerprint = self.latest_archive_moment_fingerprint;
                    core.latest_archive_seal_fingerprint = self.latest_archive_seal_fingerprint;
                    core.latest_chronicle_cursor_fingerprint = self.latest_chronicle_cursor_fingerprint;
                    core.last_output_status = self.last_output_status;
                    core.last_turn_status = self.last_turn_status;
                    self.outstanding_host_requests = &.{};
                    self.snapshot_requests_owned = false;
                }

                fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                    if (self.snapshot_requests_owned) freeHostRequests(allocator, self.outstanding_host_requests);
                    self.outstanding_host_requests = &.{};
                    self.snapshot_requests_owned = false;
                }
            };

            pub fn initWithCapacity(allocator: std.mem.Allocator, manifest: Manifest, memory_plan: MemoryPlan, capacity: Capacity) @This() {
                return .{
                    .allocator = allocator,
                    .manifest_value = manifest,
                    .memory_plan_value = memory_plan,
                    .capacity_value = capacity,
                };
            }

            pub fn initExecutable(
                allocator: std.mem.Allocator,
                image: World.Executable.Image,
                options: struct {
                    profile: Profile = .wasm_agent,
                    capacity: ?Capacity = null,
                    metadata: []const u8 = "world-executable-image",
                },
            ) !@This() {
                const compatibility = try image.validate(World.Executable.RuntimeProfile.universal_v1);
                if (!compatibility.compatible) return error.ExecutableLoadRejected;
                const capacity = options.capacity orelse capacityFromExecutableMemoryPlan(image.memory_plan, options.profile);
                try capacity.validateForProfile(options.profile);
                if (image.external_bindings.len > capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                if (image.external_bindings.len > capacity.max_host_replies_per_turn) return error.CapacityExceeded;
                if (image.external_bindings.len > capacity.max_actuation_records) return error.CapacityExceeded;
                var manifest = try manifestFromExecutableImage(allocator, image, options.profile, capacity, options.metadata);
                errdefer manifest.deinit(allocator);
                const memory_plan = MemoryPlan.derive(capacity, options.profile);
                return initWithCapacity(allocator, manifest, memory_plan, capacity);
            }

            pub fn deinit(self: *@This()) void {
                self.clearContinuationState();
                if (self.pending_command) |*command| command.deinit(self.allocator);
                self.pending_command = null;
                if (self.last_output_owned) self.allocator.free(self.last_output_bytes);
                self.last_output_bytes = "";
                self.last_output_owned = false;
                self.manifest_value.deinit(self.allocator);
                self.* = undefined;
            }

            pub fn submit(self: *@This(), command_bytes: []const u8) !void {
                try self.validateRuntimeContract();
                if (command_bytes.len > self.capacity_value.max_command_bytes) return error.CapacityExceeded;
                var command = try Command.decode(self.allocator, command_bytes);
                errdefer command.deinit(self.allocator);
                try command.validate(self.manifest_value.manifest_fingerprint, self.capacity_value);
                try self.validateCommandExecutionMode(command);
                try self.validateCommandSequence(command);
                try self.validateCommandReplies(command);
                try self.validateCommandRetentionAck(command);
                if (self.pending_command) |*pending| pending.deinit(self.allocator);
                self.pending_command = command;
            }

            pub fn executeTurn(self: *@This()) !void {
                const command = self.pending_command orelse return error.InvalidCommand;
                var rollback = try ContinuationSnapshot.capture(self);
                errdefer rollback.restore(self);
                if (command.kind == .restore) try self.applyCheckpointState(command.restore_checkpoint.?);
                const source_state_fingerprint = self.stateFingerprint();
                self.state = switch (command.kind) {
                    .inspect => self.state,
                    .cancel => .cancelled,
                    .reset => .uninitialized,
                    else => .runnable,
                };
                const status = self.statusForCommand(command);
                const retention_ack = try effectiveRetentionAck(command);
                const turn_sequence_number = if (command.kind == .inspect) self.current_turn_sequence_number else command.turn_sequence_number;
                const capsule_fingerprint = fingerprintCoreCapsule(self.manifest_value.manifest_fingerprint, command, status);
                const resets_core = command.kind == .reset;
                const acknowledged_archive_moment = if (resets_core) null else if (retention_ack) |ack| ack.resulting_moment_fingerprint else self.latest_archive_moment_fingerprint;
                const acknowledged_archive_seal = if (resets_core) null else if (retention_ack) |ack| ack.resulting_seal_fingerprint else self.latest_archive_seal_fingerprint;
                const acknowledged_chronicle_cursor = if (resets_core) null else if (retention_ack) |ack| ack.resulting_chronicle_cursor_fingerprint else self.latest_chronicle_cursor_fingerprint;
                const acknowledged_archive_cursor_value = if (retention_ack != null)
                    self.pending_archive_resulting_cursor orelse self.latest_archive_cursor
                else
                    self.latest_archive_cursor;
                const resulting_core_state = switch (command.kind) {
                    .inspect => self.state,
                    .reset => .uninitialized,
                    else => stateForStatus(status),
                };
                var archive_append_batch_fingerprint: ?u64 = null;
                var planned_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor = null;
                var host_requests_owned = false;
                var legacy_outstanding_host_request_storage: [1]HostRequest = undefined;
                const current_outstanding_host_requests = if (self.outstanding_host_requests.len != 0)
                    self.outstanding_host_requests
                else if (self.outstanding_host_request) |request| blk: {
                    legacy_outstanding_host_request_storage[0] = request;
                    break :blk legacy_outstanding_host_request_storage[0..1];
                } else &.{};
                const host_requests = if (status == .needs_host) blk: {
                    if (self.capacity_value.max_host_requests_per_turn == 0) return error.CapacityExceeded;
                    if (command.kind == .@"continue" and command.host_replies.len != 0 and commandLeavesOutstandingHostRequests(current_outstanding_host_requests, command)) {
                        const retained = try remainingHostRequestsAfterRepliesOwned(self.allocator, current_outstanding_host_requests, command);
                        host_requests_owned = true;
                        break :blk retained;
                    }
                    if (command.kind == .restore) {
                        if (current_outstanding_host_requests.len != 0) break :blk current_outstanding_host_requests;
                    }
                    const request_count = self.manifest_value.actuation_binding_fingerprints.len;
                    if (request_count == 0) break :blk &.{};
                    if (request_count > self.capacity_value.max_host_requests_per_turn) return error.CapacityExceeded;
                    const generated = try self.allocator.alloc(HostRequest, request_count);
                    host_requests_owned = true;
                    var generated_initialized: usize = 0;
                    errdefer {
                        for (generated[0..generated_initialized]) |*request| freeHostRequest(self.allocator, request);
                        self.allocator.free(generated);
                    }
                    for (generated, 0..) |*request, index| {
                        request.* = try self.hostRequestFor(command, turn_sequence_number, capsule_fingerprint, @intCast(index));
                        generated_initialized += 1;
                    }
                    break :blk generated;
                } else &.{};
                defer if (host_requests_owned) freeHostRequests(self.allocator, host_requests);
                const checkpoint_outstanding_host_requests = if (host_requests.len != 0)
                    host_requests
                else if (resulting_core_state == .waiting_host)
                    if (current_outstanding_host_requests.len != 0) current_outstanding_host_requests else return error.InvalidFrameEncoding
                else
                    &.{};
                const applied_host_reply_fingerprints = try hostReplyFingerprintsOwned(self.allocator, command.host_replies);
                defer self.allocator.free(applied_host_reply_fingerprints);
                const finalized_actuation_receipt_fingerprints = try finalizedActuationReceiptFingerprintsFor(
                    current_outstanding_host_requests,
                    command,
                    self.allocator,
                );
                defer self.allocator.free(finalized_actuation_receipt_fingerprints);
                const emitted_host_request_fingerprints = try hostRequestFingerprintsOwned(self.allocator, host_requests);
                defer self.allocator.free(emitted_host_request_fingerprints);
                const prior_checkpoint_fingerprint = if (command.restore_checkpoint) |checkpoint|
                    checkpoint.checkpoint_fingerprint
                else
                    null;
                const source_capsule_fingerprint = if (command.restore_checkpoint) |checkpoint|
                    checkpoint.capsule_fingerprint
                else
                    null;
                const root_result_fingerprint = if (status == .completed)
                    fingerprintCoreRootResult(self.manifest_value.manifest_fingerprint, command, capsule_fingerprint)
                else
                    null;
                const warning_count = self.warningCountForCommand(command);
                const checkpoint_turn_sequence_number = if (resets_core) @as(u64, 0) else turn_sequence_number;
                var output_archive_append_batch_fingerprint: ?u64 = null;
                const output_pending_archive_resulting_cursor = if (output_archive_append_batch_fingerprint != null)
                    self.pending_archive_resulting_cursor
                else
                    planned_archive_resulting_cursor;
                const diagnostic_metadata = self.diagnosticMetadata();
                const quiescence = QuiescenceReport.init(.{
                    .quiescent = true,
                    .pending_host_request_count = checkpoint_outstanding_host_requests.len,
                    .prepared_actuation_count = host_requests.len,
                    .completed_run_count = if (status == .completed) 1 else 0,
                    .failed_run_count = if (status == .failed) 1 else 0,
                    .blocker_count = if (status == .blocked) 1 else 0,
                    .warning_count = warning_count,
                });
                var turn_receipt = TurnReceipt.init(.{
                    .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                    .turn_sequence_number = turn_sequence_number,
                    .command_fingerprint = command.command_fingerprint,
                    .prior_checkpoint_fingerprint = prior_checkpoint_fingerprint,
                    .applied_host_reply_fingerprints = applied_host_reply_fingerprints,
                    .emitted_host_request_fingerprints = emitted_host_request_fingerprints,
                    .source_capsule_fingerprint = source_capsule_fingerprint,
                    .resulting_capsule_fingerprint = capsule_fingerprint,
                    .archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                    .resulting_archive_moment_fingerprint = acknowledged_archive_moment,
                    .resulting_archive_seal_fingerprint = acknowledged_archive_seal,
                    .resulting_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                    .root_result_fingerprint = root_result_fingerprint,
                    .status = status,
                    .blocker_count = if (status == .blocked) 1 else 0,
                    .warning_count = warning_count,
                });
                var checkpoint = Checkpoint.init(.{
                    .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                    .turn_sequence_number = checkpoint_turn_sequence_number,
                    .capsule_fingerprint = capsule_fingerprint,
                    .latest_archive_moment_fingerprint = acknowledged_archive_moment,
                    .latest_archive_seal_fingerprint = acknowledged_archive_seal,
                    .latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                    .pending_archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                    .pending_archive_resulting_cursor = output_pending_archive_resulting_cursor,
                    .latest_archive_cursor = if (acknowledged_chronicle_cursor != null) acknowledged_archive_cursor_value else null,
                    .core_state = resulting_core_state,
                    .previous_turn_receipt_fingerprint = if (command.kind == .inspect)
                        self.previous_turn_receipt_fingerprint
                    else if (resets_core)
                        null
                    else
                        turn_receipt.receipt_fingerprint,
                    .outstanding_host_requests = checkpoint_outstanding_host_requests,
                    .execution_mode = command.execution_mode,
                    .metadata = "core-shell",
                });
                var resulting_state_fingerprint = if (command.kind == .inspect)
                    source_state_fingerprint
                else if (command.kind == .reset)
                    stateFingerprintFor(.uninitialized, 0, null)
                else
                    stateFingerprintFor(resulting_core_state, turn_sequence_number, turn_receipt.receipt_fingerprint);
                const root_result_value_image_bytes = if (root_result_fingerprint) |fingerprint|
                    try encodeFingerprintImageOwned(self.allocator, "world.appliance.root_result.value_image", fingerprint)
                else
                    "";
                defer if (root_result_fingerprint != null) self.allocator.free(root_result_value_image_bytes);
                var checkpoint_bytes = try encodeCheckpointOwned(self.allocator, checkpoint);
                defer self.allocator.free(checkpoint_bytes);
                var archive_append_batch_bytes: []const u8 = "";
                defer if (archive_append_batch_bytes.len != 0) self.allocator.free(archive_append_batch_bytes);
                var output = TurnOutput.init(.{
                    .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                    .turn_sequence_number = turn_sequence_number,
                    .source_state_fingerprint = source_state_fingerprint,
                    .resulting_state_fingerprint = resulting_state_fingerprint,
                    .quiescence = quiescence,
                    .status = status,
                    .host_requests = host_requests,
                    .finalized_actuation_receipt_fingerprints = finalized_actuation_receipt_fingerprints,
                    .root_result_fingerprint = root_result_fingerprint,
                    .root_result_value_image_bytes = root_result_value_image_bytes,
                    .root_result_value_ref_fingerprint = root_result_fingerprint,
                    .archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                    .checkpoint_bytes = checkpoint_bytes,
                    .checkpoint = checkpoint,
                    .turn_receipt = turn_receipt,
                    .blocker_count = if (status == .blocked) 1 else 0,
                    .warning_count = warning_count,
                    .diagnostic_metadata = diagnostic_metadata,
                });
                if (self.shouldPlanArchiveAppend(command) and output_archive_append_batch_fingerprint == null) {
                    const archive_planning_cursor = if (retention_ack == null)
                        self.pending_archive_resulting_cursor orelse acknowledged_archive_cursor_value
                    else
                        acknowledged_archive_cursor_value;
                    var archive_plan = try ArchivePlan.initForTurnOutput(self.allocator, archive_planning_cursor, output, self.capacity_value);
                    defer archive_plan.deinit();
                    archive_append_batch_fingerprint = archive_plan.append_batch.append_batch_fingerprint;
                    output_archive_append_batch_fingerprint = archive_append_batch_fingerprint;
                    planned_archive_resulting_cursor = archive_plan.resulting_cursor;
                    turn_receipt = TurnReceipt.init(.{
                        .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                        .turn_sequence_number = turn_sequence_number,
                        .command_fingerprint = command.command_fingerprint,
                        .prior_checkpoint_fingerprint = prior_checkpoint_fingerprint,
                        .applied_host_reply_fingerprints = applied_host_reply_fingerprints,
                        .emitted_host_request_fingerprints = emitted_host_request_fingerprints,
                        .source_capsule_fingerprint = source_capsule_fingerprint,
                        .resulting_capsule_fingerprint = capsule_fingerprint,
                        .archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                        .resulting_archive_moment_fingerprint = acknowledged_archive_moment,
                        .resulting_archive_seal_fingerprint = acknowledged_archive_seal,
                        .resulting_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                        .root_result_fingerprint = root_result_fingerprint,
                        .status = status,
                        .blocker_count = if (status == .blocked) 1 else 0,
                        .warning_count = warning_count,
                    });
                    resulting_state_fingerprint = if (command.kind == .inspect)
                        source_state_fingerprint
                    else if (command.kind == .reset)
                        stateFingerprintFor(.uninitialized, 0, null)
                    else
                        stateFingerprintFor(resulting_core_state, turn_sequence_number, turn_receipt.receipt_fingerprint);
                    checkpoint = Checkpoint.init(.{
                        .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                        .turn_sequence_number = checkpoint_turn_sequence_number,
                        .capsule_fingerprint = capsule_fingerprint,
                        .latest_archive_moment_fingerprint = acknowledged_archive_moment,
                        .latest_archive_seal_fingerprint = acknowledged_archive_seal,
                        .latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                        .pending_archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                        .pending_archive_resulting_cursor = planned_archive_resulting_cursor,
                        .latest_archive_cursor = if (acknowledged_chronicle_cursor != null) acknowledged_archive_cursor_value else null,
                        .core_state = resulting_core_state,
                        .previous_turn_receipt_fingerprint = if (command.kind == .inspect)
                            self.previous_turn_receipt_fingerprint
                        else if (resets_core)
                            null
                        else
                            turn_receipt.receipt_fingerprint,
                        .outstanding_host_requests = checkpoint_outstanding_host_requests,
                        .execution_mode = command.execution_mode,
                        .metadata = "core-shell",
                    });
                    const updated_checkpoint_bytes = try encodeCheckpointOwned(self.allocator, checkpoint);
                    self.allocator.free(checkpoint_bytes);
                    checkpoint_bytes = updated_checkpoint_bytes;
                    archive_append_batch_bytes = try encodeArchiveAppendBatchFingerprintOwned(self.allocator, output_archive_append_batch_fingerprint.?);
                    output = TurnOutput.init(.{
                        .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                        .turn_sequence_number = turn_sequence_number,
                        .source_state_fingerprint = source_state_fingerprint,
                        .resulting_state_fingerprint = resulting_state_fingerprint,
                        .quiescence = quiescence,
                        .status = status,
                        .host_requests = host_requests,
                        .finalized_actuation_receipt_fingerprints = finalized_actuation_receipt_fingerprints,
                        .root_result_fingerprint = root_result_fingerprint,
                        .root_result_value_image_bytes = root_result_value_image_bytes,
                        .root_result_value_ref_fingerprint = root_result_fingerprint,
                        .archive_append_batch_fingerprint = output_archive_append_batch_fingerprint,
                        .checkpoint_bytes = checkpoint_bytes,
                        .archive_append_batch_bytes = archive_append_batch_bytes,
                        .checkpoint = checkpoint,
                        .turn_receipt = turn_receipt,
                        .blocker_count = if (status == .blocked) 1 else 0,
                        .warning_count = warning_count,
                        .diagnostic_metadata = diagnostic_metadata,
                    });
                }
                try output.validate(self.manifest_value.manifest_fingerprint, self.capacity_value);
                const output_bytes = try output.encode(self.allocator);
                errdefer self.allocator.free(output_bytes);
                if (output_bytes.len > self.capacity_value.max_output_bytes) return error.CapacityExceeded;
                if (self.last_output_owned) self.allocator.free(self.last_output_bytes);
                self.last_output_bytes = output_bytes;
                self.last_output_owned = true;
                if (command.kind == .reset) {
                    self.clearContinuationState();
                } else if (command.kind != .inspect) {
                    self.current_turn_sequence_number = turn_sequence_number;
                    self.previous_turn_receipt_fingerprint = turn_receipt.receipt_fingerprint;
                    if (status == .needs_host and host_requests.len != 0) {
                        if (!hostRequestSlicesMatch(self.outstanding_host_requests, host_requests)) try self.setOutstandingHostRequests(host_requests);
                    } else {
                        self.clearOutstandingHostRequests();
                    }
                    if (retention_ack != null) self.latest_archive_cursor = acknowledged_archive_cursor_value;
                    if (output_archive_append_batch_fingerprint == null or retention_ack != null or self.pending_archive_append_batch_fingerprint != output_archive_append_batch_fingerprint) {
                        self.pending_archive_append_batch_fingerprint = output_archive_append_batch_fingerprint;
                        self.pending_archive_resulting_cursor = planned_archive_resulting_cursor;
                    }
                    self.latest_archive_moment_fingerprint = acknowledged_archive_moment;
                    self.latest_archive_seal_fingerprint = acknowledged_archive_seal;
                    self.latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor;
                }
                self.state = resulting_core_state;
                self.last_output_status = status;
                if (status != .inspected) self.last_turn_status = status;
                if (self.pending_command) |*pending| pending.deinit(self.allocator);
                self.pending_command = null;
                rollback.deinit(self.allocator);
            }

            pub fn readOutput(self: *@This()) []const u8 {
                return self.last_output_bytes;
            }

            pub fn readManifest(self: *@This()) Manifest {
                return self.manifest_value;
            }

            pub fn reset(self: *@This()) void {
                if (self.pending_command) |*pending| pending.deinit(self.allocator);
                self.pending_command = null;
                if (self.last_output_owned) self.allocator.free(self.last_output_bytes);
                self.last_output_bytes = "";
                self.last_output_owned = false;
                self.last_output_status = null;
                self.last_turn_status = null;
                self.state = .uninitialized;
                self.clearContinuationState();
            }

            pub fn restore(self: *@This(), checkpoint: Checkpoint) !void {
                try checkpoint.validate(self.manifest_value.manifest_fingerprint, self.capacity_value);
                if (checkpoint.core_state == .runnable) return error.InvalidFrameEncoding;
                try self.validateRestoreCheckpointManifestBindings(checkpoint);
                var rollback = try ContinuationSnapshot.capture(self);
                errdefer rollback.restore(self);
                try self.applyCheckpointState(checkpoint);
                if (self.last_output_owned) self.allocator.free(self.last_output_bytes);
                self.last_output_bytes = "";
                self.last_output_owned = false;
                self.last_output_status = null;
                if (self.pending_command) |*pending| pending.deinit(self.allocator);
                self.pending_command = null;
                rollback.deinit(self.allocator);
            }

            fn validateCommandSequence(self: @This(), command: Command) !void {
                switch (command.kind) {
                    .boot => {
                        if (self.state != .uninitialized) return error.StaleTurn;
                        if (command.turn_sequence_number != 0) return error.StaleTurn;
                        if (command.previous_turn_receipt_fingerprint != null) return error.StaleTurn;
                    },
                    .restore => {
                        const checkpoint = command.restore_checkpoint orelse return error.RestoreRejected;
                        if (checkpoint.turn_sequence_number == std.math.maxInt(u64)) return error.StaleTurn;
                        if (command.turn_sequence_number != checkpoint.turn_sequence_number + 1) return error.StaleTurn;
                        if (command.previous_turn_receipt_fingerprint != checkpoint.previous_turn_receipt_fingerprint) return error.StaleTurn;
                        try self.validateRestoreCheckpointManifestBindings(checkpoint);
                        if (self.state != .uninitialized) {
                            if (checkpoint.turn_sequence_number != self.current_turn_sequence_number) return error.StaleTurn;
                            if (checkpoint.previous_turn_receipt_fingerprint != self.previous_turn_receipt_fingerprint) return error.StaleTurn;
                            try self.validateResidentRestoreCheckpoint(checkpoint);
                        }
                    },
                    .@"continue" => {
                        if (self.last_turn_status) |last_status| {
                            if (last_status == .failed or last_status == .blocked or last_status == .cancelled) return error.StaleTurn;
                            if (last_status == .completed) {
                                if (self.pending_archive_append_batch_fingerprint == null) return error.StaleTurn;
                                if (!self.commandIsTerminalArchiveAckOnly(command)) return error.StaleTurn;
                            }
                        }
                        if (self.current_turn_sequence_number == std.math.maxInt(u64)) return error.StaleTurn;
                        if (command.turn_sequence_number != self.current_turn_sequence_number + 1) return error.StaleTurn;
                        if (command.previous_turn_receipt_fingerprint == null) return error.StaleTurn;
                        if (command.previous_turn_receipt_fingerprint != self.previous_turn_receipt_fingerprint) return error.StaleTurn;
                    },
                    .inspect => {
                        if (command.turn_sequence_number != self.current_turn_sequence_number) return error.StaleTurn;
                    },
                    .cancel, .reset => {
                        if (self.previous_turn_receipt_fingerprint == null) {
                            if (command.turn_sequence_number != self.current_turn_sequence_number) return error.StaleTurn;
                            if (command.previous_turn_receipt_fingerprint != null) return error.StaleTurn;
                        } else {
                            if (self.current_turn_sequence_number == std.math.maxInt(u64)) return error.StaleTurn;
                            if (command.turn_sequence_number != self.current_turn_sequence_number + 1) return error.StaleTurn;
                            if (command.previous_turn_receipt_fingerprint != self.previous_turn_receipt_fingerprint) return error.StaleTurn;
                        }
                    },
                }
            }

            fn validateCommandExecutionMode(self: @This(), command: Command) !void {
                if (!self.manifest_value.supported_execution_modes.supports(command.execution_mode)) return error.InvalidCommand;
            }

            fn validateCommandReplies(self: @This(), command: Command) !void {
                if (command.kind != .@"continue" and command.kind != .restore) return;
                if (command.host_replies.len != 0 and command.execution_mode != .fresh) return error.InvalidMode;
                var legacy_outstanding_host_request_storage: [1]HostRequest = undefined;
                const current_outstanding_host_requests = if (self.outstanding_host_requests.len != 0)
                    self.outstanding_host_requests
                else if (self.outstanding_host_request) |request| blk: {
                    legacy_outstanding_host_request_storage[0] = request;
                    break :blk legacy_outstanding_host_request_storage[0..1];
                } else &.{};
                const outstanding = if (command.kind == .restore) blk: {
                    const checkpoint = command.restore_checkpoint orelse return error.RestoreRejected;
                    if (checkpoint.outstanding_host_requests.len == 0) {
                        if (command.host_replies.len != 0) return error.UnknownRequest;
                        return;
                    }
                    if (command.host_replies.len == 0) return;
                    break :blk checkpoint.outstanding_host_requests;
                } else if (current_outstanding_host_requests.len != 0) current_outstanding_host_requests else {
                    if (command.host_replies.len != 0) return error.UnknownRequest;
                    return;
                };
                if (command.kind == .@"continue" and command.host_replies.len == 0 and !commandHasRetentionAck(command)) return error.UnknownRequest;
                for (command.host_replies) |reply| try reply.validate(outstanding, self.capacity_value);
            }

            fn validateCommandRetentionAck(self: @This(), command: Command) !void {
                const pending_archive_append_batch_fingerprint = if (command.kind == .restore)
                    command.restore_checkpoint.?.pending_archive_append_batch_fingerprint
                else
                    self.pending_archive_append_batch_fingerprint;
                const pending_archive_resulting_cursor = if (command.kind == .restore)
                    command.restore_checkpoint.?.pending_archive_resulting_cursor
                else
                    self.pending_archive_resulting_cursor;
                const retention_ack = try effectiveRetentionAck(command);
                if (retention_ack) |ack| {
                    if (command.kind == .inspect or command.kind == .reset) return error.InvalidFrameEncoding;
                    try ack.validate(pending_archive_append_batch_fingerprint orelse return error.ArchiveParentMismatch, self.capacity_value);
                    const pending_cursor = pending_archive_resulting_cursor orelse return error.ArchiveParentMismatch;
                    if (ack.resulting_chronicle_cursor_fingerprint != pending_cursor.cursor_fingerprint) return error.ArchiveParentMismatch;
                } else if (self.manifest_value.enabled_features.archive_ack_gate and pending_archive_append_batch_fingerprint != null and command.kind != .inspect and command.kind != .reset) {
                    return error.ArchiveParentMismatch;
                }
            }

            fn validateRuntimeContract(self: @This()) !void {
                try self.manifest_value.validate();
                if (self.capacity_value.fingerprint() != self.manifest_value.capacity_fingerprint) return error.InvalidCommand;
                if (self.memory_plan_value.plan_fingerprint != self.manifest_value.memory_plan_fingerprint) return error.InvalidCommand;
            }

            fn shouldPlanArchiveAppend(self: @This(), command: Command) bool {
                if (self.commandIsTerminalArchiveAckOnly(command)) return false;
                return self.manifest_value.enabled_features.archive_append and command.kind != .inspect and command.kind != .reset;
            }

            fn commandIsTerminalArchiveAckOnly(self: @This(), command: Command) bool {
                return (command.kind == .@"continue" or command.kind == .restore) and
                    self.last_turn_status == .completed and
                    command.host_replies.len == 0 and
                    commandHasRetentionAck(command);
            }

            fn warningCountForCommand(self: @This(), command: Command) usize {
                if (command.kind == .inspect or command.kind == .reset) return 0;
                if (!self.manifest_value.enabled_features.archive_append) return 0;
                if (self.manifest_value.enabled_features.archive_ack_gate) return 0;
                if (self.pending_archive_append_batch_fingerprint == null) return 0;
                if ((effectiveRetentionAck(command) catch null) != null) return 0;
                return 1;
            }

            fn validateResidentRestoreCheckpoint(self: @This(), checkpoint: Checkpoint) !void {
                if (checkpoint.core_state != self.state) return error.StaleTurn;
                if (checkpoint.pending_archive_append_batch_fingerprint != self.pending_archive_append_batch_fingerprint) return error.StaleTurn;
                if (!optionalCursorMatches(checkpoint.pending_archive_resulting_cursor, self.pending_archive_resulting_cursor)) return error.StaleTurn;
                if (checkpoint.latest_archive_moment_fingerprint != self.latest_archive_moment_fingerprint) return error.StaleTurn;
                if (checkpoint.latest_archive_seal_fingerprint != self.latest_archive_seal_fingerprint) return error.StaleTurn;
                if (checkpoint.latest_chronicle_cursor_fingerprint != self.latest_chronicle_cursor_fingerprint) return error.StaleTurn;
                if (checkpoint.latest_chronicle_cursor_fingerprint != null and !optionalCursorMatches(checkpoint.latest_archive_cursor, self.latest_archive_cursor)) return error.StaleTurn;

                var legacy_outstanding_host_request_storage: [1]HostRequest = undefined;
                const current_outstanding_host_requests = if (self.outstanding_host_requests.len != 0)
                    self.outstanding_host_requests
                else if (self.outstanding_host_request) |request| blk: {
                    legacy_outstanding_host_request_storage[0] = request;
                    break :blk legacy_outstanding_host_request_storage[0..1];
                } else &.{};
                if (!hostRequestSlicesMatch(checkpoint.outstanding_host_requests, current_outstanding_host_requests)) return error.StaleTurn;
            }

            fn validateRestoreCheckpointManifestBindings(self: @This(), checkpoint: Checkpoint) !void {
                if (checkpoint.core_state == .waiting_host and self.manifest_value.actuation_binding_fingerprints.len == 0) return error.InvalidFrameEncoding;
            }

            fn applyCheckpointState(self: *@This(), checkpoint: Checkpoint) !void {
                self.current_turn_sequence_number = checkpoint.turn_sequence_number;
                self.previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint;
                try self.setOutstandingHostRequests(checkpoint.outstanding_host_requests);
                self.pending_archive_append_batch_fingerprint = checkpoint.pending_archive_append_batch_fingerprint;
                self.pending_archive_resulting_cursor = if (checkpoint.pending_archive_resulting_cursor) |cursor| blk: {
                    var resident_cursor = cursor;
                    resident_cursor.metadata_bytes = "";
                    break :blk resident_cursor;
                } else null;
                self.latest_archive_cursor = if (checkpoint.latest_archive_cursor) |cursor| blk: {
                    var resident_cursor = cursor;
                    resident_cursor.metadata_bytes = "";
                    break :blk resident_cursor;
                } else World.Continuity.Chronicle.Cursor.initial();
                self.latest_archive_moment_fingerprint = checkpoint.latest_archive_moment_fingerprint;
                self.latest_archive_seal_fingerprint = checkpoint.latest_archive_seal_fingerprint;
                self.latest_chronicle_cursor_fingerprint = checkpoint.latest_chronicle_cursor_fingerprint;
                self.state = checkpoint.core_state;
                self.last_turn_status = switch (checkpoint.core_state) {
                    .uninitialized, .runnable => null,
                    .waiting_host => .needs_host,
                    .completed => .completed,
                    .failed => .failed,
                    .cancelled => .cancelled,
                };
            }

            fn clearContinuationState(self: *@This()) void {
                self.current_turn_sequence_number = 0;
                self.previous_turn_receipt_fingerprint = null;
                self.clearOutstandingHostRequests();
                self.pending_archive_append_batch_fingerprint = null;
                self.pending_archive_resulting_cursor = null;
                self.latest_archive_cursor = World.Continuity.Chronicle.Cursor.initial();
                self.latest_archive_moment_fingerprint = null;
                self.latest_archive_seal_fingerprint = null;
                self.latest_chronicle_cursor_fingerprint = null;
            }

            fn clearOutstandingHostRequests(self: *@This()) void {
                if (self.outstanding_host_requests_owned) freeHostRequests(self.allocator, self.outstanding_host_requests);
                self.outstanding_host_request = null;
                self.outstanding_host_requests = &.{};
                self.outstanding_host_requests_owned = false;
            }

            fn setOutstandingHostRequests(self: *@This(), requests: []const HostRequest) !void {
                const cloned = try cloneHostRequestsOwned(self.allocator, requests);
                errdefer freeHostRequests(self.allocator, cloned);
                self.clearOutstandingHostRequests();
                self.outstanding_host_requests = cloned;
                self.outstanding_host_requests_owned = true;
                self.outstanding_host_request = if (cloned.len == 0) null else cloned[0];
            }

            fn statusForCommand(self: @This(), command: Command) TurnStatus {
                return switch (command.kind) {
                    .boot, .restore, .@"continue" => self.statusForAdvancingCommand(command),
                    .inspect => .inspected,
                    .cancel => .cancelled,
                    .reset => .cancelled,
                };
            }

            fn statusForAdvancingCommand(self: @This(), command: Command) TurnStatus {
                if (command.kind == .restore) {
                    const checkpoint = command.restore_checkpoint orelse return .blocked;
                    switch (checkpoint.core_state) {
                        .completed => return .completed,
                        .failed => return .failed,
                        .cancelled => return .cancelled,
                        .uninitialized, .runnable, .waiting_host => {},
                    }
                }
                var legacy_outstanding_host_request_storage: [1]HostRequest = undefined;
                const current_outstanding_host_requests = if (self.outstanding_host_requests.len != 0)
                    self.outstanding_host_requests
                else if (self.outstanding_host_request) |request| blk: {
                    legacy_outstanding_host_request_storage[0] = request;
                    break :blk legacy_outstanding_host_request_storage[0..1];
                } else &.{};
                if (commandLeavesOutstandingHostRequests(current_outstanding_host_requests, command)) return .needs_host;
                if (command.host_replies.len != 0) return turnStatusForHostReplies(command.host_replies);
                if (self.commandIsTerminalArchiveAckOnly(command)) return .completed;
                if (self.manifest_value.actuation_binding_fingerprints.len == 0) return .completed;
                if (command.execution_mode == .fresh) return .needs_host;
                if (self.commandHasReplayEvidence(command)) return .completed;
                return .blocked;
            }

            fn commandHasReplayEvidence(self: @This(), command: Command) bool {
                if (command.receiver_evidence_fingerprints.len == 0) return false;
                return command.receiver_evidence_fingerprints.len >= 1 + self.manifest_value.actuation_binding_fingerprints.len;
            }

            fn diagnosticMetadata(self: @This()) []const u8 {
                return if (self.manifest_value.enabled_features.diagnostic_metadata) "core-shell" else "";
            }

            fn turnStatusForHostOutcome(status: HostOutcomeStatus) TurnStatus {
                return switch (status) {
                    .responded => .completed,
                    .failed => .failed,
                    .cancelled => .cancelled,
                    .rejected => .blocked,
                    .pending, .deferred => .needs_host,
                };
            }

            fn turnStatusForHostReplies(replies: []const HostReply) TurnStatus {
                var saw_rejected = false;
                for (replies) |reply| {
                    switch (turnStatusForHostOutcome(reply.outcome.status)) {
                        .needs_host => return .needs_host,
                        .failed => return .failed,
                        .cancelled => return .cancelled,
                        .blocked => saw_rejected = true,
                        .completed => {},
                        .inspected => unreachable,
                    }
                }
                return if (saw_rejected) .blocked else .completed;
            }

            fn hostRequestFor(self: @This(), command: Command, turn_sequence_number: u64, capsule_fingerprint: u64, binding_index: usize) !HostRequest {
                const descriptor_fingerprint = self.manifest_value.actuation_descriptor_fingerprints[binding_index];
                const binding_fingerprint = self.manifest_value.actuation_binding_fingerprints[binding_index];
                const world_port_id: u32 = @intCast(self.manifest_value.actuation_world_port_ids[binding_index]);
                const intent_fingerprint = fingerprintCoreHostIntent(self.manifest_value.manifest_fingerprint, command.command_fingerprint, binding_fingerprint, turn_sequence_number);
                const envelope_fingerprint = fingerprintCoreHostEnvelope(intent_fingerprint, capsule_fingerprint);
                const idempotency_key_fingerprint = fingerprintCoreHostIdempotencyKey(self.manifest_value.manifest_fingerprint, command.command_fingerprint, binding_fingerprint, turn_sequence_number);
                const decision_fingerprint = fingerprintCoreHostDecision(intent_fingerprint, descriptor_fingerprint);
                const frame_request_bytes = try encodeHostFrameRequestOwned(self.allocator, .{
                    .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                    .command_fingerprint = command.command_fingerprint,
                    .turn_sequence_number = turn_sequence_number,
                    .request_ordinal = @as(u32, @intCast(binding_index)),
                    .world_port_id = world_port_id,
                    .binding_fingerprint = binding_fingerprint,
                    .descriptor_fingerprint = descriptor_fingerprint,
                    .intent_fingerprint = intent_fingerprint,
                    .envelope_fingerprint = envelope_fingerprint,
                });
                errdefer self.allocator.free(frame_request_bytes);
                const payload_value_image_bytes = try encodeHostPayloadValueImageOwned(self.allocator, command, binding_fingerprint, world_port_id);
                errdefer self.allocator.free(payload_value_image_bytes);
                const prepared_actuation_evidence_bytes = try encodePreparedActuationEvidenceOwned(self.allocator, .{
                    .descriptor_fingerprint = descriptor_fingerprint,
                    .binding_fingerprint = binding_fingerprint,
                    .actuator_ref_fingerprint = self.manifest_value.actuation_actuator_ref_fingerprints[binding_index],
                    .world_port_id = world_port_id,
                    .decision_fingerprint = decision_fingerprint,
                });
                errdefer self.allocator.free(prepared_actuation_evidence_bytes);
                const idempotency_key_bytes = try encodeIdempotencyKeyImageOwned(self.allocator, .{
                    .manifest_fingerprint = self.manifest_value.manifest_fingerprint,
                    .command_fingerprint = command.command_fingerprint,
                    .binding_fingerprint = binding_fingerprint,
                    .turn_sequence_number = turn_sequence_number,
                    .idempotency_key_fingerprint = idempotency_key_fingerprint,
                });
                errdefer self.allocator.free(idempotency_key_bytes);
                return HostRequest.init(.{
                    .turn_sequence_number = turn_sequence_number,
                    .request_ordinal = @as(u32, @intCast(binding_index)),
                    .run_handle_fingerprint = stateFingerprintFor(self.state, self.current_turn_sequence_number, self.previous_turn_receipt_fingerprint),
                    .pending_port_fingerprint = capsule_fingerprint,
                    .world_port_id = world_port_id,
                    .target_ref_fingerprint = self.manifest_value.root_target_ref_fingerprint,
                    .world_surface_fingerprint = self.manifest_value.root_world_surface_fingerprint,
                    .actuator_ref_fingerprint = self.manifest_value.actuation_actuator_ref_fingerprints[binding_index],
                    .actuation_class = self.manifest_value.actuation_classes[binding_index],
                    .allowed_response_statuses = self.manifest_value.actuation_allowed_response_statuses[binding_index],
                    .intent_fingerprint = intent_fingerprint,
                    .envelope_fingerprint = envelope_fingerprint,
                    .decision_fingerprint = decision_fingerprint,
                    .expected_response_descriptor_fingerprint = descriptor_fingerprint,
                    .idempotency_key_fingerprint = idempotency_key_fingerprint,
                    .supervision_ref_fingerprint = if (self.manifest_value.supervision_policy_fingerprint == 0) null else self.manifest_value.supervision_policy_fingerprint,
                    .metadata = "core-shell.host-request",
                    .frame_request_bytes = frame_request_bytes,
                    .payload_value_image_bytes = payload_value_image_bytes,
                    .payload_value_ref_fingerprint = descriptor_fingerprint,
                    .payload_schema_ref_fingerprint = binding_fingerprint,
                    .expected_response_value_ref_fingerprint = descriptor_fingerprint,
                    .expected_response_schema_ref_fingerprint = binding_fingerprint,
                    .prepared_actuation_evidence_bytes = prepared_actuation_evidence_bytes,
                    .idempotency_key_bytes = idempotency_key_bytes,
                    .owns_byte_payloads = true,
                });
            }

            fn stateFingerprint(self: @This()) u64 {
                return stateFingerprintFor(self.state, self.current_turn_sequence_number, self.previous_turn_receipt_fingerprint);
            }
        };

        pub const Native = struct {
            core: Core,
            last_error_storage: [native_last_error_storage_bytes]u8 = [_]u8{0} ** native_last_error_storage_bytes,
            last_error_len: usize = 0,

            const native_last_error_storage_bytes: usize = 256;

            pub fn init(core: Core) @This() {
                return .{ .core = core };
            }

            pub fn submitCommand(self: *@This(), command_bytes: []const u8) Abi.Status {
                self.core.submit(command_bytes) catch |err| return self.setErrorStatus(Abi.statusForError(err));
                self.core.executeTurn() catch |err| return self.setErrorStatus(Abi.statusForError(err));
                const status = if (self.core.last_output_status) |turn_status|
                    Abi.statusForTurnStatus(turn_status)
                else
                    Abi.statusForCoreState(self.core.state);
                self.clearLastError();
                return status;
            }

            pub fn manifestLen(self: @This()) usize {
                return self.core.manifest_value.encodedLen();
            }

            pub fn readManifest(self: @This(), dest: []u8) usize {
                const required = self.core.manifest_value.encodedLen();
                if (dest.len >= required) {
                    _ = self.core.manifest_value.writeCanonicalBytes(dest[0..required]) catch return required;
                }
                return required;
            }

            pub fn outputLen(self: *@This()) usize {
                return self.core.readOutput().len;
            }

            pub fn readOutput(self: *@This(), dest: []u8) usize {
                const output = self.core.readOutput();
                if (dest.len >= output.len) @memcpy(dest[0..output.len], output);
                return output.len;
            }

            pub fn lastErrorLen(self: @This()) usize {
                return self.last_error_len;
            }

            pub fn lastErrorBytes(self: @This()) []const u8 {
                return self.last_error_storage[0..self.last_error_len];
            }

            pub fn readLastError(self: @This(), dest: []u8) usize {
                if (dest.len >= self.last_error_len) @memcpy(dest[0..self.last_error_len], self.last_error_storage[0..self.last_error_len]);
                return self.last_error_len;
            }

            pub fn reset(self: *@This()) Abi.Status {
                self.core.reset();
                self.clearLastError();
                return .ok;
            }

            fn setErrorStatus(self: *@This(), status: Abi.Status) Abi.Status {
                self.setLastError(Abi.statusName(status));
                return status;
            }

            fn setLastError(self: *@This(), message: []const u8) void {
                self.last_error_len = @min(message.len, self.last_error_storage.len);
                @memcpy(self.last_error_storage[0..self.last_error_len], message[0..self.last_error_len]);
            }

            fn clearLastError(self: *@This()) void {
                self.last_error_len = 0;
            }
        };

        pub const Abi = struct {
            pub const version: u32 = World.world_appliance_abi_version;
            pub const universal_version: u32 = 2;
            pub const Status = enum(u32) {
                ok = 0,
                output_ready = 1,
                needs_host = 2,
                completed = 3,
                failed = 4,
                blocked = 5,
                cancelled = 6,
                invalid_command = 7,
                stale_turn = 8,
                unknown_request = 9,
                duplicate_reply = 10,
                supervision_denied = 11,
                capacity_exceeded = 12,
                restore_rejected = 13,
                archive_parent_mismatch = 14,
                buffer_too_small = 15,
            };

            pub fn statusForCoreState(state: CoreState) Status {
                return switch (state) {
                    .uninitialized, .runnable => .output_ready,
                    .waiting_host => .needs_host,
                    .completed => .completed,
                    .failed => .failed,
                    .cancelled => .cancelled,
                };
            }

            pub fn statusForTurnStatus(status: TurnStatus) Status {
                return switch (status) {
                    .needs_host => .needs_host,
                    .completed => .completed,
                    .failed => .failed,
                    .blocked => .blocked,
                    .cancelled => .cancelled,
                    .inspected => .output_ready,
                };
            }

            pub fn statusHasTurnOutput(status: Status) bool {
                return switch (status) {
                    .output_ready,
                    .needs_host,
                    .completed,
                    .failed,
                    .blocked,
                    .cancelled,
                    => true,
                    .ok,
                    .invalid_command,
                    .stale_turn,
                    .unknown_request,
                    .duplicate_reply,
                    .supervision_denied,
                    .capacity_exceeded,
                    .restore_rejected,
                    .archive_parent_mismatch,
                    .buffer_too_small,
                    => false,
                };
            }

            pub fn statusForError(err: anyerror) Status {
                return switch (err) {
                    error.StaleTurn => .stale_turn,
                    error.UnknownRequest => .unknown_request,
                    error.DuplicateReply => .duplicate_reply,
                    error.SupervisionDenied => .supervision_denied,
                    error.CapacityExceeded, error.OutOfMemory => .capacity_exceeded,
                    error.RestoreRejected => .restore_rejected,
                    error.ArchiveParentMismatch => .archive_parent_mismatch,
                    else => .invalid_command,
                };
            }

            pub fn statusName(status: Status) []const u8 {
                return switch (status) {
                    .ok => "ok",
                    .output_ready => "output_ready",
                    .needs_host => "needs_host",
                    .completed => "completed",
                    .failed => "failed",
                    .blocked => "blocked",
                    .cancelled => "cancelled",
                    .invalid_command => "invalid_command",
                    .stale_turn => "stale_turn",
                    .unknown_request => "unknown_request",
                    .duplicate_reply => "duplicate_reply",
                    .supervision_denied => "supervision_denied",
                    .capacity_exceeded => "capacity_exceeded",
                    .restore_rejected => "restore_rejected",
                    .archive_parent_mismatch => "archive_parent_mismatch",
                    .buffer_too_small => "buffer_too_small",
                };
            }

            pub const required_exports = [_][]const u8{
                "world_appliance_abi_version",
                "world_appliance_manifest_len",
                "world_appliance_read_manifest",
                "world_appliance_submit_command",
                "world_appliance_output_len",
                "world_appliance_read_output",
                "world_appliance_last_error_len",
                "world_appliance_read_last_error",
                "world_appliance_reset",
            };
            pub const universal_required_exports = [_][]const u8{
                "world_appliance_abi_version",
                "world_appliance_runtime_manifest_len",
                "world_appliance_read_runtime_manifest",
                "world_appliance_load_executable",
                "world_appliance_unload_executable",
                "world_appliance_manifest_len",
                "world_appliance_read_manifest",
                "world_appliance_submit_command",
                "world_appliance_output_len",
                "world_appliance_read_output",
                "world_appliance_last_error_len",
                "world_appliance_read_last_error",
                "world_appliance_reset",
                "world_appliance_alloc",
                "world_appliance_free",
            };
            pub const metadata_exports = [_][]const u8{
                "world_appliance_manifest_fingerprint_lo",
                "world_appliance_manifest_fingerprint_hi",
                "world_appliance_capacity_fingerprint_lo",
                "world_appliance_capacity_fingerprint_hi",
                "world_appliance_memory_plan_fingerprint_lo",
                "world_appliance_memory_plan_fingerprint_hi",
                "world_appliance_required_memory_bytes",
                "world_appliance_max_linear_memory_pages",
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
                "storage",
                "actuator",
            };

            pub const WasmInspection = struct {
                abi_version: u32 = 0,
                export_count: usize = 0,
                import_count: usize = 0,
                import_function_count: usize = 0,
                forbidden_import_count: usize = 0,
                required_exports_present: bool = false,
                metadata_exports_present: bool = false,
                required_export_signatures_valid: bool = false,
                required_export_bodies_valid: bool = false,
                metadata_export_signatures_valid: bool = false,
                metadata_export_values: [Abi.metadata_exports.len]u32 = [_]u32{0} ** Abi.metadata_exports.len,
                metadata_export_values_valid: bool = false,
                manifest_fingerprint: u64 = 0,
                capacity_fingerprint: u64 = 0,
                memory_plan_fingerprint: u64 = 0,
                required_memory_bytes: u64 = 0,
                max_linear_memory_pages: u32 = 0,
                memory_count: u32 = 0,
                memory_export_present: bool = false,
                memory_initial_pages: u32 = 0,
                memory_max_pages: ?u32 = null,
                alloc_export_present: bool = false,
                free_export_present: bool = false,
                optional_helper_exports_valid: bool = true,

                pub fn passed(self: @This()) bool {
                    return self.abi_version == Abi.version and
                        self.required_exports_present and
                        self.metadata_exports_present and
                        self.required_export_signatures_valid and
                        self.required_export_bodies_valid and
                        self.metadata_export_signatures_valid and
                        self.metadata_export_values_valid and
                        self.required_memory_bytes <= @as(u64, self.max_linear_memory_pages) * wasm_page_size and
                        self.memory_count == 1 and
                        self.memory_export_present and
                        self.max_linear_memory_pages > 0 and
                        self.memory_initial_pages == self.max_linear_memory_pages and
                        self.memory_max_pages != null and
                        self.memory_max_pages.? == self.max_linear_memory_pages and
                        self.import_count == 0 and
                        self.forbidden_import_count == 0 and
                        self.optional_helper_exports_valid;
                }
            };

            pub fn inspectWasm(bytes: []const u8) !WasmInspection {
                if (bytes.len < 8) return error.InvalidFrameEncoding;
                if (!std.mem.eql(u8, bytes[0..4], "\x00asm")) return error.InvalidFrameEncoding;
                if (std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidFrameEncoding;

                var inspection: WasmInspection = .{};
                var required_mask: u64 = 0;
                var required_signature_mask: u64 = 0;
                var metadata_mask: u64 = 0;
                var metadata_signature_mask: u64 = 0;
                var metadata_value_mask: u64 = 0;
                var memory_count: u32 = 0;
                var memory_section: WasmMemorySection = .{};
                var table_section: WasmTableSection = .{};
                var global_section: WasmGlobalSection = .{};
                var data_count_section: ?u32 = null;
                var data_segment_count: ?u32 = null;
                var type_sigs: [wasm_max_inspected_types]WasmFuncSignature = undefined;
                var type_count: usize = 0;
                var function_type_indices: [wasm_max_inspected_functions]u32 = undefined;
                var function_count: usize = 0;
                var abi_export_function_index: ?u32 = null;
                var required_export_function_indices: [required_exports.len]?u32 = [_]?u32{null} ** required_exports.len;
                var metadata_export_function_indices: [metadata_exports.len]?u32 = [_]?u32{null} ** metadata_exports.len;
                var cursor: usize = 8;
                var seen_standard_sections: u16 = 0;
                var last_section_order: u8 = 0;
                while (cursor < bytes.len) {
                    const section_id = try wasmReadU8(bytes, &cursor);
                    const section_len = try wasmReadU32(bytes, &cursor);
                    if (section_len > bytes.len - cursor) return error.InvalidFrameEncoding;
                    const section = bytes[cursor .. cursor + section_len];
                    try inspectWasmSectionOrder(section_id, &seen_standard_sections, &last_section_order);
                    switch (section_id) {
                        1 => type_count = try inspectWasmTypes(section, &type_sigs),
                        2 => try inspectWasmImports(section, &inspection),
                        3 => function_count = try inspectWasmFunctions(section, &function_type_indices, type_count),
                        5 => {
                            const memory = try inspectWasmMemory(section);
                            memory_section = memory;
                            memory_count = memory.count;
                            inspection.memory_count = memory.count;
                            inspection.memory_initial_pages = memory.initial_pages;
                            inspection.memory_max_pages = memory.max_pages;
                        },
                        6 => global_section = try inspectWasmGlobals(section),
                        7 => try inspectWasmExports(
                            section,
                            memory_count,
                            memory_section,
                            type_sigs[0..type_count],
                            function_type_indices[0..function_count],
                            &inspection,
                            &required_mask,
                            &required_signature_mask,
                            &metadata_mask,
                            &metadata_signature_mask,
                            &abi_export_function_index,
                            &required_export_function_indices,
                            &metadata_export_function_indices,
                        ),
                        10 => try inspectWasmCode(
                            section,
                            function_count,
                            inspection.import_function_count,
                            type_sigs[0..type_count],
                            function_type_indices[0..function_count],
                            table_section,
                            global_section,
                            memory_count,
                            abi_export_function_index,
                            &required_export_function_indices,
                            &metadata_export_function_indices,
                            &metadata_value_mask,
                            &inspection,
                        ),
                        0 => {},
                        4 => table_section = try inspectWasmTables(section),
                        9 => _ = try validateIgnoredWasmSection(section_id, section, memory_count, table_section, inspection.import_function_count + function_count),
                        11 => data_segment_count = try validateIgnoredWasmSection(section_id, section, memory_count, table_section, inspection.import_function_count + function_count),
                        12 => data_count_section = try validateIgnoredWasmSection(section_id, section, memory_count, table_section, inspection.import_function_count + function_count),
                        else => return error.InvalidFrameEncoding,
                    }
                    cursor += section_len;
                }
                if (data_count_section) |expected_data_segments| {
                    if (expected_data_segments != (data_segment_count orelse 0)) return error.InvalidFrameEncoding;
                }
                const all_required = if (required_exports.len == 64)
                    std.math.maxInt(u64)
                else
                    (@as(u64, 1) << @intCast(required_exports.len)) - 1;
                inspection.required_exports_present = (required_mask & all_required) == all_required;
                inspection.required_export_signatures_valid = (required_signature_mask & all_required) == all_required;
                const all_metadata = if (metadata_exports.len == 64)
                    std.math.maxInt(u64)
                else
                    (@as(u64, 1) << @intCast(metadata_exports.len)) - 1;
                inspection.metadata_exports_present = (metadata_mask & all_metadata) == all_metadata;
                inspection.metadata_export_signatures_valid = (metadata_signature_mask & all_metadata) == all_metadata;
                inspection.metadata_export_values_valid = (metadata_value_mask & all_metadata) == all_metadata;
                if (inspection.metadata_export_values_valid) {
                    inspection.manifest_fingerprint = combineWasmU64(
                        inspection.metadata_export_values[0],
                        inspection.metadata_export_values[1],
                    );
                    inspection.capacity_fingerprint = combineWasmU64(
                        inspection.metadata_export_values[2],
                        inspection.metadata_export_values[3],
                    );
                    inspection.memory_plan_fingerprint = combineWasmU64(
                        inspection.metadata_export_values[4],
                        inspection.metadata_export_values[5],
                    );
                    inspection.required_memory_bytes = inspection.metadata_export_values[6];
                    inspection.max_linear_memory_pages = inspection.metadata_export_values[7];
                }
                return inspection;
            }

            fn combineWasmU64(lo: u32, hi: u32) u64 {
                return @as(u64, lo) | (@as(u64, hi) << 32);
            }

            fn inspectWasmSectionOrder(section_id: u8, seen: *u16, last_order: *u8) !void {
                if (section_id == 0) return;
                if (section_id == 8 or section_id > 12) return error.InvalidFrameEncoding;

                const mask = @as(u16, 1) << @intCast(section_id);
                if ((seen.* & mask) != 0) return error.InvalidFrameEncoding;
                seen.* |= mask;

                const order = wasmSectionOrder(section_id);
                if (order < last_order.*) return error.InvalidFrameEncoding;
                last_order.* = order;
            }

            fn wasmSectionOrder(section_id: u8) u8 {
                return switch (section_id) {
                    12 => 10,
                    10 => 11,
                    11 => 12,
                    else => section_id,
                };
            }
        };

        pub fn memoryPlan(capacity: Capacity, profile: Profile) MemoryPlan {
            return MemoryPlan.derive(capacity, profile);
        }

        pub fn requiredMemoryBytes(capacity: Capacity, profile: Profile) usize {
            return memoryPlan(capacity, profile).maximum_linear_memory_bytes;
        }

        pub fn coreStateFingerprint(state: CoreState, turn_sequence_number: u64, previous_turn_receipt_fingerprint: ?u64) u64 {
            return stateFingerprintFor(state, turn_sequence_number, previous_turn_receipt_fingerprint);
        }

        fn inspectWasmImports(section: []const u8, inspection: *Abi.WasmInspection) !void {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const module = try wasmReadName(section, &cursor);
                const name = try wasmReadName(section, &cursor);
                const kind = try wasmReadU8(section, &cursor);
                try wasmSkipImportDesc(section, &cursor, kind);
                inspection.import_count += 1;
                if (kind == 0) inspection.import_function_count += 1;
                if (wasmForbiddenImport(module) or wasmForbiddenImport(name)) {
                    inspection.forbidden_import_count += 1;
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
        }

        const wasm_max_inspected_types = 512;
        const wasm_max_inspected_functions = 8192;
        const wasm_max_inspected_signature_values = 64;

        const WasmValueType = enum {
            i32,
            i64,
            f32,
            f64,
            v128,
            funcref,
            externref,
        };

        const WasmFuncSignature = struct {
            param_count: u32 = 0,
            result_count: u32 = 0,
            i32_param_count: u32 = 0,
            i32_result_count: u32 = 0,
            param_types: [wasm_max_inspected_signature_values]WasmValueType = [_]WasmValueType{.i32} ** wasm_max_inspected_signature_values,
            result_types: [wasm_max_inspected_signature_values]WasmValueType = [_]WasmValueType{.i32} ** wasm_max_inspected_signature_values,
            all_params_i32: bool = true,
            all_results_i32: bool = true,

            fn matches(self: @This(), expected_params: u32, expected_results: u32) bool {
                return self.param_count == expected_params and
                    self.result_count == expected_results and
                    self.all_params_i32 and
                    self.all_results_i32;
            }
        };

        fn inspectWasmTypes(section: []const u8, out: *[wasm_max_inspected_types]WasmFuncSignature) !usize {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > out.len) return error.CapacityExceeded;
            var index: usize = 0;
            while (index < count) : (index += 1) {
                const tag = try wasmReadU8(section, &cursor);
                if (tag != 0x60) return error.InvalidFrameEncoding;
                const param_count = try wasmReadU32(section, &cursor);
                if (param_count > wasm_max_inspected_signature_values) return error.CapacityExceeded;
                var param_types = [_]WasmValueType{.i32} ** wasm_max_inspected_signature_values;
                var all_params_i32 = true;
                var i32_param_count: u32 = 0;
                var param_index: u32 = 0;
                while (param_index < param_count) : (param_index += 1) {
                    const param_type = try wasmReadValueType(section, &cursor);
                    param_types[@intCast(param_index)] = param_type;
                    if (param_type == .i32) {
                        i32_param_count += 1;
                    } else {
                        all_params_i32 = false;
                    }
                }
                const result_count = try wasmReadU32(section, &cursor);
                if (result_count > wasm_max_inspected_signature_values) return error.CapacityExceeded;
                var result_types = [_]WasmValueType{.i32} ** wasm_max_inspected_signature_values;
                var all_results_i32 = true;
                var i32_result_count: u32 = 0;
                var result_index: u32 = 0;
                while (result_index < result_count) : (result_index += 1) {
                    const result_type = try wasmReadValueType(section, &cursor);
                    result_types[@intCast(result_index)] = result_type;
                    if (result_type == .i32) {
                        i32_result_count += 1;
                    } else {
                        all_results_i32 = false;
                    }
                }
                out[index] = .{
                    .param_count = param_count,
                    .result_count = result_count,
                    .i32_param_count = i32_param_count,
                    .i32_result_count = i32_result_count,
                    .param_types = param_types,
                    .result_types = result_types,
                    .all_params_i32 = all_params_i32,
                    .all_results_i32 = all_results_i32,
                };
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return @intCast(count);
        }

        fn inspectWasmValueTypeIsI32(section: []const u8, cursor: *usize) !bool {
            return (try wasmReadValueType(section, cursor)) == .i32;
        }

        fn wasmReadValueType(section: []const u8, cursor: *usize) !WasmValueType {
            return switch (try wasmReadU8(section, cursor)) {
                0x7f => .i32,
                0x7e => .i64,
                0x7d => .f32,
                0x7c => .f64,
                0x7b => .v128,
                0x70 => .funcref,
                0x6f => .externref,
                else => error.InvalidFrameEncoding,
            };
        }

        fn inspectWasmFunctions(section: []const u8, out: *[wasm_max_inspected_functions]u32, type_count: usize) !usize {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > out.len) return error.CapacityExceeded;
            var index: usize = 0;
            while (index < count) : (index += 1) {
                const type_index = try wasmReadU32(section, &cursor);
                if (type_index >= type_count) return error.InvalidFrameEncoding;
                out[index] = type_index;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return @intCast(count);
        }

        const WasmMemorySection = struct {
            count: u32 = 0,
            initial_pages: u32 = 0,
            max_pages: ?u32 = null,
            limits: [wasm_max_inspected_memories]WasmLimits = [_]WasmLimits{.{ .min = 0 }} ** wasm_max_inspected_memories,
        };

        const wasm_max_inspected_memories = 16;
        const wasm_max_inspected_tables = 16;
        const wasm_max_inspected_globals = 512;
        const wasm_max_inspected_body_locals = 1024;

        const WasmTableSection = struct {
            count: u32 = 0,
            ref_types: [wasm_max_inspected_tables]WasmValueType = [_]WasmValueType{.funcref} ** wasm_max_inspected_tables,
        };

        const WasmGlobalSection = struct {
            count: u32 = 0,
            is_i32: [wasm_max_inspected_globals]bool = [_]bool{false} ** wasm_max_inspected_globals,
            is_mutable: [wasm_max_inspected_globals]bool = [_]bool{false} ** wasm_max_inspected_globals,
        };

        const WasmBodyLocals = struct {
            count: u32 = 0,
            is_i32: [wasm_max_inspected_body_locals]bool = [_]bool{false} ** wasm_max_inspected_body_locals,
            value_types: [wasm_max_inspected_body_locals]WasmValueType = [_]WasmValueType{.i32} ** wasm_max_inspected_body_locals,
        };

        const WasmLimits = struct {
            min: u32,
            max: ?u32 = null,
        };

        fn inspectWasmMemory(section: []const u8) !WasmMemorySection {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > wasm_max_inspected_memories) return error.CapacityExceeded;
            var index: u32 = 0;
            var initial_pages: u32 = 0;
            var max_pages: ?u32 = null;
            var limits_by_index: [wasm_max_inspected_memories]WasmLimits = [_]WasmLimits{.{ .min = 0 }} ** wasm_max_inspected_memories;
            while (index < count) : (index += 1) {
                const limits = try wasmReadLimits(section, &cursor);
                limits_by_index[index] = limits;
                if (index == 0) {
                    initial_pages = limits.min;
                    max_pages = limits.max;
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return .{
                .count = count,
                .initial_pages = initial_pages,
                .max_pages = max_pages,
                .limits = limits_by_index,
            };
        }

        fn inspectWasmTables(section: []const u8) !WasmTableSection {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > wasm_max_inspected_tables) return error.CapacityExceeded;
            var tables: WasmTableSection = .{ .count = count };
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                tables.ref_types[index] = try wasmReadRefType(section, &cursor);
                _ = try wasmReadLimits(section, &cursor);
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return tables;
        }

        fn inspectWasmGlobals(section: []const u8) !WasmGlobalSection {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > wasm_max_inspected_globals) return error.CapacityExceeded;
            var globals: WasmGlobalSection = .{ .count = count };
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                globals.is_i32[index] = try inspectWasmValueTypeIsI32(section, &cursor);
                const mutability = try wasmReadU8(section, &cursor);
                if (mutability > 1) return error.InvalidFrameEncoding;
                globals.is_mutable[index] = mutability == 1;
                try wasmSkipConstExpr(section, &cursor, if (globals.is_i32[index]) .i32 else null, null);
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return globals;
        }

        fn validateIgnoredWasmSection(section_id: u8, section: []const u8, memory_count: u32, table_section: WasmTableSection, total_function_count: usize) !u32 {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (section_id == 12) {
                if (cursor != section.len) return error.InvalidFrameEncoding;
                return count;
            }
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                switch (section_id) {
                    6 => try wasmSkipGlobal(section, &cursor),
                    9 => try wasmSkipElement(section, &cursor, table_section, total_function_count),
                    11 => try wasmSkipData(section, &cursor, memory_count),
                    else => return error.InvalidFrameEncoding,
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return count;
        }

        fn wasmSkipGlobal(section: []const u8, cursor: *usize) !void {
            const is_i32 = try inspectWasmValueTypeIsI32(section, cursor);
            const mutability = try wasmReadU8(section, cursor);
            if (mutability > 1) return error.InvalidFrameEncoding;
            try wasmSkipConstExpr(section, cursor, if (is_i32) .i32 else null, null);
        }

        fn wasmSkipElement(section: []const u8, cursor: *usize, table_section: WasmTableSection, total_function_count: usize) !void {
            const flags = try wasmReadU32(section, cursor);
            switch (flags) {
                0 => {
                    try wasmValidateTableRefType(table_section, 0, .funcref);
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                    try wasmSkipElementFuncIndices(section, cursor, total_function_count);
                },
                1 => {
                    const elem_kind = try wasmReadU8(section, cursor);
                    if (elem_kind != 0) return error.InvalidFrameEncoding;
                    try wasmSkipElementFuncIndices(section, cursor, total_function_count);
                },
                2 => {
                    try wasmValidateTableRefType(table_section, try wasmReadU32(section, cursor), .funcref);
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                    const elem_kind = try wasmReadU8(section, cursor);
                    if (elem_kind != 0) return error.InvalidFrameEncoding;
                    try wasmSkipElementFuncIndices(section, cursor, total_function_count);
                },
                3 => {
                    const elem_kind = try wasmReadU8(section, cursor);
                    if (elem_kind != 0) return error.InvalidFrameEncoding;
                    try wasmSkipElementFuncIndices(section, cursor, total_function_count);
                },
                4 => {
                    try wasmValidateTableIndex(table_section, 0);
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                    try wasmSkipElementConstExprs(section, cursor, table_section.ref_types[0], total_function_count);
                },
                5 => {
                    const ref_type = try wasmReadRefType(section, cursor);
                    try wasmSkipElementConstExprs(section, cursor, ref_type, total_function_count);
                },
                6 => {
                    const table_index = try wasmReadU32(section, cursor);
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                    const ref_type = try wasmReadRefType(section, cursor);
                    try wasmValidateTableRefType(table_section, table_index, ref_type);
                    try wasmSkipElementConstExprs(section, cursor, ref_type, total_function_count);
                },
                7 => {
                    const ref_type = try wasmReadRefType(section, cursor);
                    try wasmSkipElementConstExprs(section, cursor, ref_type, total_function_count);
                },
                else => return error.InvalidFrameEncoding,
            }
        }

        fn wasmSkipElementFuncIndices(section: []const u8, cursor: *usize, total_function_count: usize) !void {
            const count = try wasmReadU32(section, cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                if (try wasmReadU32(section, cursor) >= total_function_count) return error.InvalidFrameEncoding;
            }
        }

        fn wasmSkipElementConstExprs(section: []const u8, cursor: *usize, expected_type: WasmValueType, total_function_count: usize) !void {
            const count = try wasmReadU32(section, cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) try wasmSkipConstExpr(section, cursor, expected_type, total_function_count);
        }

        fn wasmReadRefType(section: []const u8, cursor: *usize) !WasmValueType {
            return switch (try wasmReadU8(section, cursor)) {
                0x70 => .funcref,
                0x6f => .externref,
                else => error.InvalidFrameEncoding,
            };
        }

        fn wasmValidateTableIndex(tables: WasmTableSection, table_index: u32) !void {
            if (table_index >= tables.count) return error.InvalidFrameEncoding;
        }

        fn wasmValidateTableRefType(tables: WasmTableSection, table_index: u32, expected_type: WasmValueType) !void {
            try wasmValidateTableIndex(tables, table_index);
            if (tables.ref_types[table_index] != expected_type) return error.InvalidFrameEncoding;
        }

        fn wasmSkipData(section: []const u8, cursor: *usize, memory_count: u32) !void {
            const flags = try wasmReadU32(section, cursor);
            switch (flags) {
                0 => {
                    if (memory_count == 0) return error.InvalidFrameEncoding;
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                },
                1 => {},
                2 => {
                    if (try wasmReadU32(section, cursor) >= memory_count) return error.InvalidFrameEncoding;
                    try wasmSkipConstExpr(section, cursor, .i32, null);
                },
                else => return error.InvalidFrameEncoding,
            }
            const len = try wasmReadU32(section, cursor);
            if (len > section.len - cursor.*) return error.InvalidFrameEncoding;
            cursor.* += len;
        }

        fn wasmSkipConstExpr(section: []const u8, cursor: *usize, expected_type: ?WasmValueType, total_function_count: ?usize) !void {
            var actual_type: ?WasmValueType = null;
            while (true) {
                const opcode = try wasmReadU8(section, cursor);
                switch (opcode) {
                    0x0b => {
                        const actual = actual_type orelse return error.InvalidFrameEncoding;
                        if (expected_type) |expected| {
                            if (actual != expected) return error.InvalidFrameEncoding;
                        }
                        return;
                    },
                    0x41 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        _ = try wasmReadI32Bits(section, cursor);
                        actual_type = .i32;
                    },
                    0x42 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        _ = try wasmReadI64(section, cursor);
                        actual_type = .i64;
                    },
                    0x43 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        if (4 > section.len - cursor.*) return error.InvalidFrameEncoding;
                        cursor.* += 4;
                        actual_type = .f32;
                    },
                    0x44 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        if (8 > section.len - cursor.*) return error.InvalidFrameEncoding;
                        cursor.* += 8;
                        actual_type = .f64;
                    },
                    0x23 => return error.InvalidFrameEncoding,
                    0xd0 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        actual_type = try wasmReadRefType(section, cursor);
                    },
                    0xd2 => {
                        if (actual_type != null) return error.InvalidFrameEncoding;
                        if (try wasmReadU32(section, cursor) >= (total_function_count orelse return error.InvalidFrameEncoding)) return error.InvalidFrameEncoding;
                        actual_type = .funcref;
                    },
                    else => return error.InvalidFrameEncoding,
                }
            }
        }

        fn wasmReadI64(bytes: []const u8, cursor: *usize) !i64 {
            var shift: u7 = 0;
            var result: i128 = 0;
            var count: u8 = 0;
            var byte: u8 = 0;
            while (true) {
                if (cursor.* >= bytes.len or count == 10) return error.InvalidFrameEncoding;
                byte = bytes[cursor.*];
                cursor.* += 1;
                result |= @as(i128, @intCast(byte & 0x7f)) << shift;
                count += 1;
                if ((byte & 0x80) == 0) break;
                shift += 7;
            }
            const sign_shift = shift + 7;
            if ((byte & 0x40) != 0) result |= -(@as(i128, 1) << sign_shift);
            if (result < std.math.minInt(i64) or result > std.math.maxInt(i64)) return error.InvalidFrameEncoding;
            return @intCast(result);
        }

        fn inspectWasmExports(
            section: []const u8,
            memory_count: u32,
            memory_section: WasmMemorySection,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
            inspection: *Abi.WasmInspection,
            required_mask: *u64,
            required_signature_mask: *u64,
            metadata_mask: *u64,
            metadata_signature_mask: *u64,
            abi_export_function_index: *?u32,
            required_export_function_indices: *[Abi.required_exports.len]?u32,
            metadata_export_function_indices: *[Abi.metadata_exports.len]?u32,
        ) !void {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const entry_start = cursor;
                const name = try wasmReadName(section, &cursor);
                const kind = try wasmReadU8(section, &cursor);
                const export_index = try wasmReadU32(section, &cursor);
                if (try applianceExportNameAppeared(section, entry_start, name)) return error.InvalidFrameEncoding;
                try validateWasmExportDescriptor(kind, export_index, memory_count, inspection.import_function_count, function_type_indices.len);
                inspection.export_count += 1;
                if (kind == 2 and export_index < memory_count and std.mem.eql(u8, name, "memory")) {
                    const exported_memory = memory_section.limits[export_index];
                    inspection.memory_export_present = true;
                    inspection.memory_initial_pages = exported_memory.min;
                    inspection.memory_max_pages = exported_memory.max;
                }
                if (std.mem.eql(u8, name, "world_alloc")) {
                    if (kind == 0 and applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, 1, 1)) {
                        inspection.alloc_export_present = true;
                    } else {
                        inspection.optional_helper_exports_valid = false;
                    }
                }
                if (std.mem.eql(u8, name, "world_free")) {
                    if (kind == 0 and applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, 2, 0)) {
                        inspection.free_export_present = true;
                    } else {
                        inspection.optional_helper_exports_valid = false;
                    }
                }
                if (kind == 0) {
                    for (Abi.required_exports, 0..) |required, required_index| {
                        if (std.mem.eql(u8, name, required)) {
                            required_mask.* |= @as(u64, 1) << @intCast(required_index);
                            if (applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, applianceRequiredExportParamCount(required_index), 1)) {
                                required_signature_mask.* |= @as(u64, 1) << @intCast(required_index);
                            }
                            if (required_index == 0) abi_export_function_index.* = export_index;
                            required_export_function_indices[required_index] = export_index;
                        }
                    }
                    for (Abi.metadata_exports, 0..) |metadata_export, metadata_index| {
                        if (std.mem.eql(u8, name, metadata_export)) {
                            metadata_mask.* |= @as(u64, 1) << @intCast(metadata_index);
                            if (applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, 0, 1)) {
                                metadata_signature_mask.* |= @as(u64, 1) << @intCast(metadata_index);
                                metadata_export_function_indices[metadata_index] = export_index;
                            }
                        }
                    }
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
        }

        fn validateWasmExportDescriptor(
            kind: u8,
            export_index: u32,
            memory_count: u32,
            import_function_count: usize,
            function_count: usize,
        ) !void {
            switch (kind) {
                0 => {
                    const total_functions = import_function_count + function_count;
                    if (export_index >= total_functions) return error.InvalidFrameEncoding;
                },
                2 => {
                    if (export_index >= memory_count) return error.InvalidFrameEncoding;
                },
                else => return error.InvalidFrameEncoding,
            }
        }

        fn applianceExportNameAppeared(section: []const u8, end: usize, name: []const u8) !bool {
            var cursor: usize = 0;
            _ = try wasmReadU32(section, &cursor);
            while (cursor < end) {
                const previous = try wasmReadName(section, &cursor);
                _ = try wasmReadU8(section, &cursor);
                _ = try wasmReadU32(section, &cursor);
                if (std.mem.eql(u8, previous, name)) return true;
            }
            if (cursor != end) return error.InvalidFrameEncoding;
            return false;
        }

        fn applianceRequiredExportParamCount(required_index: usize) u32 {
            return switch (required_index) {
                2, 3, 5, 7 => 2,
                else => 0,
            };
        }

        fn applianceExportSignatureMatches(
            export_index: u32,
            import_function_count: usize,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
            expected_params: u32,
            expected_results: u32,
        ) bool {
            if (export_index < import_function_count) return false;
            const defined_index = export_index - @as(u32, @intCast(import_function_count));
            if (defined_index >= function_type_indices.len) return false;
            const type_index = function_type_indices[@intCast(defined_index)];
            if (type_index >= type_sigs.len) return false;
            return type_sigs[@intCast(type_index)].matches(expected_params, expected_results);
        }

        fn inspectWasmCode(
            section: []const u8,
            function_count: usize,
            import_function_count: usize,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
            table_section: WasmTableSection,
            global_section: WasmGlobalSection,
            memory_count: u32,
            abi_export_function_index: ?u32,
            required_export_function_indices: *const [Abi.required_exports.len]?u32,
            metadata_export_function_indices: *const [Abi.metadata_exports.len]?u32,
            metadata_value_mask: *u64,
            inspection: *Abi.WasmInspection,
        ) !void {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count != function_count) return error.InvalidFrameEncoding;
            const abi_defined_index = wasmDefinedFunctionIndex(abi_export_function_index, import_function_count);
            var required_defined_indices: [Abi.required_exports.len]?u32 = [_]?u32{null} ** Abi.required_exports.len;
            for (required_export_function_indices.*, 0..) |function_index, required_index| {
                required_defined_indices[required_index] = wasmDefinedFunctionIndex(function_index, import_function_count);
            }
            var metadata_defined_indices: [Abi.metadata_exports.len]?u32 = [_]?u32{null} ** Abi.metadata_exports.len;
            for (metadata_export_function_indices.*, 0..) |function_index, metadata_index| {
                metadata_defined_indices[metadata_index] = wasmDefinedFunctionIndex(function_index, import_function_count);
            }
            var required_body_mask: u64 = 0;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const body_len = try wasmReadU32(section, &cursor);
                if (body_len > section.len - cursor) return error.InvalidFrameEncoding;
                const body = section[cursor .. cursor + body_len];
                var required_body_index: ?usize = null;
                for (required_defined_indices, 0..) |defined_index, required_index| {
                    if (defined_index != null and index == defined_index.?) {
                        required_body_index = required_index;
                        break;
                    }
                }
                const function_signature = wasmFunctionSignature(index + @as(u32, @intCast(import_function_count)), import_function_count, type_sigs, function_type_indices) orelse return error.InvalidFrameEncoding;
                try validateApplianceWasmFunctionBody(
                    body,
                    import_function_count,
                    type_sigs,
                    function_type_indices,
                    function_signature,
                    table_section,
                    global_section,
                    memory_count,
                    required_body_index != null,
                );
                if (required_body_index) |required_index| {
                    required_body_mask |= @as(u64, 1) << @intCast(required_index);
                }
                var metadata_body_index: ?usize = null;
                for (metadata_defined_indices, 0..) |defined_index, metadata_index| {
                    if (defined_index != null and index == defined_index.?) {
                        metadata_body_index = metadata_index;
                        break;
                    }
                }
                if ((abi_defined_index != null and index == abi_defined_index.?) or metadata_body_index != null) {
                    const value = try readWasmConstantU32FunctionBody(body);
                    if (abi_defined_index != null and index == abi_defined_index.?) {
                        inspection.abi_version = value;
                    }
                    if (metadata_body_index) |metadata_index| {
                        inspection.metadata_export_values[metadata_index] = value;
                        metadata_value_mask.* |= @as(u64, 1) << @intCast(metadata_index);
                    }
                }
                cursor += body_len;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            const all_required = if (Abi.required_exports.len == 64)
                std.math.maxInt(u64)
            else
                (@as(u64, 1) << @intCast(Abi.required_exports.len)) - 1;
            inspection.required_export_bodies_valid = (required_body_mask & all_required) == all_required;
        }

        fn wasmDefinedFunctionIndex(function_index: ?u32, import_function_count: usize) ?u32 {
            const index = function_index orelse return null;
            if (index < import_function_count) return null;
            return index - @as(u32, @intCast(import_function_count));
        }

        fn readWasmConstantU32FunctionBody(body: []const u8) !u32 {
            var cursor: usize = 0;
            try skipApplianceWasmLocals(body, &cursor);
            const opcode = try wasmReadU8(body, &cursor);
            if (opcode != 0x41) return error.InvalidFrameEncoding;
            const value = try wasmReadI32Bits(body, &cursor);
            const terminator = try wasmReadU8(body, &cursor);
            if (terminator == 0x0f) {
                if ((try wasmReadU8(body, &cursor)) != 0x0b) return error.InvalidFrameEncoding;
            } else if (terminator != 0x0b) {
                return error.InvalidFrameEncoding;
            }
            if (cursor != body.len) return error.InvalidFrameEncoding;
            return value;
        }

        fn validateApplianceWasmFunctionBody(
            body: []const u8,
            import_function_count: usize,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
            function_signature: WasmFuncSignature,
            table_section: WasmTableSection,
            global_section: WasmGlobalSection,
            memory_count: u32,
            strict_stack: bool,
        ) !void {
            const expected_result_count = function_signature.result_count;
            var cursor: usize = 0;
            const locals = try inspectApplianceWasmLocals(body, &cursor);
            var depth: u32 = 0;
            var control_frames: [wasm_max_inspected_control_depth]WasmControlFrame = undefined;
            var i32_stack_depth: u32 = 0;
            var non_i32_stack_depth: u32 = 0;
            var exact_stack: WasmOperandStack = .{};
            var last_value_type: ?WasmValueType = null;
            var exact_stack_reliable = true;
            var returned = false;
            while (cursor < body.len) {
                const opcode = try wasmReadU8(body, &cursor);
                exact_stack_reliable = exact_stack_reliable and switch (opcode) {
                    0x0b, 0x10, 0x11, 0x1a, 0x20, 0x41, 0x42, 0x43, 0x44, 0x45...0x4f, 0x67...0x78 => true,
                    else => false,
                };
                switch (opcode) {
                    0x00 => {
                        if (depth > 0) control_frames[depth - 1].polymorphic_stack = true;
                        last_value_type = null;
                    },
                    0x01 => {},
                    0x0f => {
                        try wasmConsumeI32ForMode(&i32_stack_depth, expected_result_count, strict_stack);
                        i32_stack_depth = expected_result_count;
                        non_i32_stack_depth = 0;
                        if (depth > 0) control_frames[depth - 1].polymorphic_stack = true;
                        returned = true;
                        last_value_type = null;
                    },
                    0x1a => {
                        if (strict_stack and exact_stack_reliable) try exact_stack.popAny();
                        try wasmConsumeAnyForMode(&i32_stack_depth, &non_i32_stack_depth, strict_stack);
                        last_value_type = null;
                    },
                    0x1b => {
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.pop(.i32);
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 3, strict_stack and exact_stack_reliable);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x02, 0x03 => {
                        const shape = try wasmReadBlockShape(body, &cursor, type_sigs, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, shape.param_count, strict_stack);
                        last_value_type = null;
                        try wasmPushControlFrame(&control_frames, &depth, .{
                            .kind = if (opcode == 0x03) .loop else .block_or_if,
                            .param_count = shape.param_count,
                            .result_count = shape.result_count,
                            .base_i32_stack_depth = i32_stack_depth,
                            .base_non_i32_stack_depth = non_i32_stack_depth,
                        });
                    },
                    0x04 => {
                        const shape = try wasmReadBlockShape(body, &cursor, type_sigs, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, shape.param_count, strict_stack);
                        last_value_type = null;
                        try wasmPushControlFrame(&control_frames, &depth, .{
                            .kind = .if_then,
                            .param_count = shape.param_count,
                            .result_count = shape.result_count,
                            .base_i32_stack_depth = i32_stack_depth,
                            .base_non_i32_stack_depth = non_i32_stack_depth,
                        });
                    },
                    0x05 => {
                        if (depth == 0) return error.InvalidFrameEncoding;
                        const frame_index = depth - 1;
                        if (control_frames[frame_index].kind != .if_then) return error.InvalidFrameEncoding;
                        if (strict_stack and exact_stack_reliable) try wasmValidateControlFrameStack(control_frames[frame_index], i32_stack_depth, non_i32_stack_depth);
                        i32_stack_depth = control_frames[frame_index].base_i32_stack_depth;
                        non_i32_stack_depth = control_frames[frame_index].base_non_i32_stack_depth;
                        control_frames[frame_index].kind = .if_else;
                        last_value_type = null;
                    },
                    0x0b => {
                        if (depth == 0) {
                            if (cursor != body.len) return error.InvalidFrameEncoding;
                            if (strict_stack) {
                                if (exact_stack_reliable and non_i32_stack_depth != 0) return error.InvalidFrameEncoding;
                                if (i32_stack_depth != expected_result_count and !returned) return error.InvalidFrameEncoding;
                            } else if (!returned and exact_stack_reliable) {
                                if (i32_stack_depth != function_signature.i32_result_count) return error.InvalidFrameEncoding;
                                if (non_i32_stack_depth != function_signature.result_count - function_signature.i32_result_count) return error.InvalidFrameEncoding;
                            } else if (i32_stack_depth < function_signature.i32_result_count and !returned) {
                                return error.InvalidFrameEncoding;
                            }
                            return;
                        }
                        const frame = control_frames[depth - 1];
                        if (strict_stack and frame.kind == .if_then and frame.result_count > 0) return error.InvalidFrameEncoding;
                        if (strict_stack and exact_stack_reliable) {
                            try wasmValidateControlFrameStack(frame, i32_stack_depth, non_i32_stack_depth);
                        } else if (strict_stack and i32_stack_depth < frame.result_count) {
                            return error.InvalidFrameEncoding;
                        }
                        if (frame.polymorphic_stack) {
                            i32_stack_depth = std.math.add(u32, frame.base_i32_stack_depth, frame.result_count) catch return error.CapacityExceeded;
                            non_i32_stack_depth = frame.base_non_i32_stack_depth;
                        }
                        depth -= 1;
                    },
                    0x0c => {
                        const result_count = try wasmBranchResultCount(try wasmReadU32(body, &cursor), depth, &control_frames, expected_result_count);
                        try wasmConsumeI32ForMode(&i32_stack_depth, result_count, strict_stack);
                        if (depth > 0) control_frames[depth - 1].polymorphic_stack = true;
                        last_value_type = null;
                    },
                    0x0d => {
                        const result_count = try wasmBranchResultCount(try wasmReadU32(body, &cursor), depth, &control_frames, expected_result_count);
                        const required_i32_depth = std.math.add(u32, result_count, 1) catch return error.CapacityExceeded;
                        if (strict_stack and i32_stack_depth < required_i32_depth) return error.InvalidFrameEncoding;
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        last_value_type = null;
                    },
                    0x0e => {
                        const target_count = try wasmReadU32(body, &cursor);
                        var branch_result_count: ?u32 = null;
                        var target_index: u32 = 0;
                        while (target_index <= target_count) : (target_index += 1) {
                            const result_count = try wasmBranchResultCount(try wasmReadU32(body, &cursor), depth, &control_frames, expected_result_count);
                            if (branch_result_count) |expected| {
                                if (result_count != expected) return error.InvalidFrameEncoding;
                            } else {
                                branch_result_count = result_count;
                            }
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, branch_result_count orelse 0, strict_stack);
                        if (depth > 0) control_frames[depth - 1].polymorphic_stack = true;
                        last_value_type = null;
                    },
                    0x10 => {
                        const function_index = try wasmReadU32(body, &cursor);
                        const signature = wasmFunctionSignature(function_index, import_function_count, type_sigs, function_type_indices) orelse return error.InvalidFrameEncoding;
                        if (strict_stack and exact_stack_reliable) {
                            try wasmExactConsumeSignatureParams(&exact_stack, signature);
                            try wasmExactPushSignatureResults(&exact_stack, signature);
                        }
                        try wasmConsumeSignatureParams(&i32_stack_depth, &non_i32_stack_depth, signature, strict_stack);
                        i32_stack_depth += signature.i32_result_count;
                        non_i32_stack_depth += signature.result_count - signature.i32_result_count;
                        last_value_type = if (signature.result_count == 1 and signature.all_results_i32) .i32 else null;
                    },
                    0x11 => {
                        const type_index = try wasmReadU32(body, &cursor);
                        const table_index = try wasmReadU32(body, &cursor);
                        if (type_index >= type_sigs.len) return error.InvalidFrameEncoding;
                        try wasmValidateTableRefType(table_section, table_index, .funcref);
                        const signature = type_sigs[@intCast(type_index)];
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try wasmExactConsumeSignatureParams(&exact_stack, signature);
                            try wasmExactPushSignatureResults(&exact_stack, signature);
                        }
                        try wasmConsumeSignatureParams(&i32_stack_depth, &non_i32_stack_depth, signature, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += signature.i32_result_count;
                        non_i32_stack_depth += signature.result_count - signature.i32_result_count;
                        last_value_type = if (signature.result_count == 1 and signature.all_results_i32) .i32 else null;
                    },
                    0x20 => {
                        const local_type = try wasmLocalType(function_signature, locals, try wasmReadU32(body, &cursor));
                        if (local_type == .i32) {
                            i32_stack_depth += 1;
                        } else {
                            non_i32_stack_depth += 1;
                        }
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(local_type);
                        last_value_type = local_type;
                    },
                    0x21 => {
                        const local_type = try wasmLocalType(function_signature, locals, try wasmReadU32(body, &cursor));
                        if (local_type == .i32) {
                            try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        } else {
                            try wasmValidateKnownLocalValueType(local_type, last_value_type, strict_stack);
                            try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        }
                        last_value_type = null;
                    },
                    0x22 => {
                        const local_type = try wasmLocalType(function_signature, locals, try wasmReadU32(body, &cursor));
                        if (local_type == .i32) {
                            try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                            i32_stack_depth += 1;
                        } else {
                            try wasmValidateKnownLocalValueType(local_type, last_value_type, strict_stack);
                            try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                            non_i32_stack_depth += 1;
                        }
                        last_value_type = local_type;
                    },
                    0x23 => {
                        try wasmValidateGlobalIndex(global_section, try wasmReadU32(body, &cursor));
                        i32_stack_depth += 1;
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(.i32);
                        last_value_type = .i32;
                    },
                    0x24 => {
                        try wasmValidateMutableGlobalIndex(global_section, try wasmReadU32(body, &cursor));
                        if (strict_stack and exact_stack_reliable) try exact_stack.pop(.i32);
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        last_value_type = null;
                    },
                    0x28, 0x2c, 0x2d, 0x2e, 0x2f => {
                        try wasmReadMemoryImmediate(body, &cursor, wasmNaturalMemoryAlignment(opcode));
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x36, 0x3a, 0x3b => {
                        try wasmReadMemoryImmediate(body, &cursor, wasmNaturalMemoryAlignment(opcode));
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.pop(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 2, strict_stack);
                        last_value_type = null;
                    },
                    0x29, 0x2a, 0x2b, 0x30...0x35 => {
                        try wasmReadMemoryImmediate(body, &cursor, wasmNaturalMemoryAlignment(opcode));
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0x37...0x39, 0x3c...0x3e => {
                        try wasmReadMemoryImmediate(body, &cursor, wasmNaturalMemoryAlignment(opcode));
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        last_value_type = null;
                    },
                    0x3f, 0x40 => {
                        const memory_index = try wasmReadU32(body, &cursor);
                        if (memory_index >= memory_count) return error.InvalidFrameEncoding;
                        if (opcode == 0x3f) {
                            i32_stack_depth += 1;
                            if (strict_stack and exact_stack_reliable) try exact_stack.push(.i32);
                            last_value_type = .i32;
                        } else {
                            if (strict_stack and exact_stack_reliable) {
                                try exact_stack.pop(.i32);
                                try exact_stack.push(.i32);
                            }
                            try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                            i32_stack_depth += 1;
                            last_value_type = .i32;
                        }
                    },
                    0x41 => {
                        _ = try wasmReadI32Bits(body, &cursor);
                        i32_stack_depth += 1;
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(.i32);
                        last_value_type = .i32;
                    },
                    0x42 => {
                        _ = try wasmReadI64(body, &cursor);
                        non_i32_stack_depth += 1;
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(.i64);
                        last_value_type = .i64;
                    },
                    0x43 => {
                        if (4 > body.len - cursor) return error.InvalidFrameEncoding;
                        cursor += 4;
                        non_i32_stack_depth += 1;
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(.f32);
                        last_value_type = .f32;
                    },
                    0x44 => {
                        if (8 > body.len - cursor) return error.InvalidFrameEncoding;
                        cursor += 8;
                        non_i32_stack_depth += 1;
                        if (strict_stack and exact_stack_reliable) try exact_stack.push(.f64);
                        last_value_type = .f64;
                    },
                    0x45 => {
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x46...0x4f => {
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 2, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x50 => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x51...0x66 => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 2, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x67...0x69 => {
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x6a...0x78 => {
                        if (strict_stack and exact_stack_reliable) {
                            try exact_stack.pop(.i32);
                            try exact_stack.pop(.i32);
                            try exact_stack.push(.i32);
                        }
                        try wasmConsumeI32ForMode(&i32_stack_depth, 2, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0x79...0x7b, 0x8b...0x91, 0x99...0x9f => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0x7c...0x8a, 0x92...0x98, 0xa0...0xa6 => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 2, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xa7...0xab => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0xac, 0xad => {
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xae...0xb1 => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xb2, 0xb3 => {
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xb4...0xbb => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xbc => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        i32_stack_depth += 1;
                        last_value_type = .i32;
                    },
                    0xbd => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xbe => {
                        try wasmConsumeI32ForMode(&i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = .i64;
                    },
                    0xbf => {
                        try wasmConsumeNonI32ForMode(&non_i32_stack_depth, 1, strict_stack);
                        non_i32_stack_depth += 1;
                        last_value_type = null;
                    },
                    0xd0...0xd2 => return error.InvalidFrameEncoding,
                    0xfc => {
                        try wasmSkipPrefixedInstruction(body, &cursor, &i32_stack_depth, &non_i32_stack_depth, memory_count, strict_stack);
                        last_value_type = null;
                    },
                    else => return error.InvalidFrameEncoding,
                }
            }
            return error.InvalidFrameEncoding;
        }

        fn wasmFunctionSignature(
            function_index: u32,
            import_function_count: usize,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
        ) ?WasmFuncSignature {
            if (function_index < import_function_count) return null;
            const defined_index = function_index - @as(u32, @intCast(import_function_count));
            if (defined_index >= function_type_indices.len) return null;
            const type_index = function_type_indices[@intCast(defined_index)];
            if (type_index >= type_sigs.len) return null;
            return type_sigs[@intCast(type_index)];
        }

        const wasm_max_inspected_control_depth = 1024;
        const wasm_max_inspected_operand_stack = 4096;
        const wasm_nonstrict_stack_budget = 1 << 20;

        const WasmOperandStack = struct {
            len: u32 = 0,
            values: [wasm_max_inspected_operand_stack]WasmValueType = undefined,

            fn push(self: *@This(), value_type: WasmValueType) !void {
                if (self.len >= self.values.len) return error.CapacityExceeded;
                self.values[self.len] = value_type;
                self.len += 1;
            }

            fn pop(self: *@This(), expected_type: WasmValueType) !void {
                if (self.len == 0) return error.InvalidFrameEncoding;
                self.len -= 1;
                if (self.values[self.len] != expected_type) return error.InvalidFrameEncoding;
            }

            fn popAny(self: *@This()) !void {
                if (self.len == 0) return error.InvalidFrameEncoding;
                self.len -= 1;
            }
        };

        fn wasmExactConsumeSignatureParams(stack: *WasmOperandStack, signature: WasmFuncSignature) !void {
            var remaining = signature.param_count;
            while (remaining > 0) {
                remaining -= 1;
                try stack.pop(signature.param_types[@intCast(remaining)]);
            }
        }

        fn wasmExactPushSignatureResults(stack: *WasmOperandStack, signature: WasmFuncSignature) !void {
            var index: u32 = 0;
            while (index < signature.result_count) : (index += 1) {
                try stack.push(signature.result_types[@intCast(index)]);
            }
        }

        const WasmControlKind = enum {
            block_or_if,
            loop,
            if_then,
            if_else,
        };

        const WasmControlFrame = struct {
            kind: WasmControlKind,
            param_count: u32 = 0,
            result_count: u32 = 0,
            base_i32_stack_depth: u32 = 0,
            base_non_i32_stack_depth: u32 = 0,
            polymorphic_stack: bool = false,
        };

        const WasmBlockShape = struct {
            param_count: u32 = 0,
            result_count: u32 = 0,
        };

        fn wasmPushControlFrame(frames: *[wasm_max_inspected_control_depth]WasmControlFrame, depth: *u32, frame: WasmControlFrame) !void {
            if (depth.* >= frames.len) return error.CapacityExceeded;
            frames[depth.*] = frame;
            depth.* += 1;
        }

        fn wasmReadBlockShape(body: []const u8, cursor: *usize, type_sigs: []const WasmFuncSignature, strict_stack: bool) !WasmBlockShape {
            const first = try wasmReadU8(body, cursor);
            if (first == 0x40) return .{};
            if (first == 0x7f) return .{ .result_count = 1 };
            if (validApplianceWasmLocalType(first)) {
                if (strict_stack) return error.InvalidFrameEncoding;
                return .{};
            }
            var type_index: u32 = first & 0x7f;
            var shift: u5 = 7;
            if ((first & 0x80) == 0) {
                if (type_index >= type_sigs.len) return error.InvalidFrameEncoding;
                const signature = type_sigs[@intCast(type_index)];
                if (!signature.all_params_i32 or !signature.all_results_i32 or signature.result_count > 1) {
                    if (strict_stack) return error.InvalidFrameEncoding;
                    return .{};
                }
                return .{ .param_count = signature.param_count, .result_count = signature.result_count };
            }
            var count: u8 = 1;
            var byte = first;
            while ((byte & 0x80) != 0) {
                if (count == 5 or cursor.* >= body.len) return error.InvalidFrameEncoding;
                byte = body[cursor.*];
                cursor.* += 1;
                type_index |= @as(u32, byte & 0x7f) << shift;
                if (shift >= 28 and (byte & 0xf0) != 0) return error.InvalidFrameEncoding;
                if ((byte & 0x80) != 0) shift += 7;
                count += 1;
            }
            if (type_index >= type_sigs.len) return error.InvalidFrameEncoding;
            const signature = type_sigs[@intCast(type_index)];
            if (!signature.all_params_i32 or !signature.all_results_i32 or signature.result_count > 1) {
                if (strict_stack) return error.InvalidFrameEncoding;
                return .{};
            }
            return .{ .param_count = signature.param_count, .result_count = signature.result_count };
        }

        fn inspectApplianceWasmLocals(body: []const u8, cursor: *usize) !WasmBodyLocals {
            const local_group_count = try wasmReadU32(body, cursor);
            var local_group_index: u32 = 0;
            var locals: WasmBodyLocals = .{};
            while (local_group_index < local_group_count) : (local_group_index += 1) {
                const group_count = try wasmReadU32(body, cursor);
                const value_type = try wasmReadValueType(body, cursor);
                const next_count = std.math.add(u32, locals.count, group_count) catch return error.CapacityExceeded;
                if (next_count > wasm_max_inspected_body_locals) return error.CapacityExceeded;
                while (locals.count < next_count) : (locals.count += 1) {
                    locals.is_i32[locals.count] = value_type == .i32;
                    locals.value_types[locals.count] = value_type;
                }
            }
            return locals;
        }

        fn wasmLocalIsI32(signature: WasmFuncSignature, locals: WasmBodyLocals, local_index: u32) !bool {
            return (try wasmLocalType(signature, locals, local_index)) == .i32;
        }

        fn wasmLocalType(signature: WasmFuncSignature, locals: WasmBodyLocals, local_index: u32) !WasmValueType {
            if (local_index < signature.param_count) return signature.param_types[@intCast(local_index)];
            const body_local_index = local_index - signature.param_count;
            if (body_local_index >= locals.count) return error.InvalidFrameEncoding;
            return locals.value_types[body_local_index];
        }

        fn wasmValidateKnownLocalValueType(expected_type: WasmValueType, actual_type: ?WasmValueType, strict_stack: bool) !void {
            if (!strict_stack) return;
            if (actual_type) |actual| {
                if (actual != expected_type) return error.InvalidFrameEncoding;
            }
        }

        fn wasmValidateGlobalIndex(globals: WasmGlobalSection, global_index: u32) !void {
            if (global_index >= globals.count) return error.InvalidFrameEncoding;
            if (!globals.is_i32[global_index]) return error.InvalidFrameEncoding;
        }

        fn wasmValidateMutableGlobalIndex(globals: WasmGlobalSection, global_index: u32) !void {
            try wasmValidateGlobalIndex(globals, global_index);
            if (!globals.is_mutable[global_index]) return error.InvalidFrameEncoding;
        }

        fn wasmBranchResultCount(
            target_depth: u32,
            depth: u32,
            frames: *const [wasm_max_inspected_control_depth]WasmControlFrame,
            function_result_count: u32,
        ) !u32 {
            if (target_depth > depth) return error.InvalidFrameEncoding;
            if (target_depth == depth) return function_result_count;
            const frame = frames[depth - 1 - target_depth];
            return if (frame.kind == .loop) frame.param_count else frame.result_count;
        }

        fn wasmValidateControlFrameStack(frame: WasmControlFrame, i32_stack_depth: u32, non_i32_stack_depth: u32) !void {
            const required_i32_depth = std.math.add(u32, frame.base_i32_stack_depth, frame.result_count) catch return error.CapacityExceeded;
            if (frame.polymorphic_stack) return;
            if (non_i32_stack_depth != frame.base_non_i32_stack_depth) return error.InvalidFrameEncoding;
            if (i32_stack_depth != required_i32_depth) return error.InvalidFrameEncoding;
        }

        fn wasmReadMemoryImmediate(body: []const u8, cursor: *usize, max_alignment_exponent: u32) !void {
            const alignment_exponent = try wasmReadU32(body, cursor);
            if (alignment_exponent > max_alignment_exponent) return error.InvalidFrameEncoding;
            _ = try wasmReadU32(body, cursor);
        }

        fn wasmNaturalMemoryAlignment(opcode: u8) u32 {
            return switch (opcode) {
                0x28, 0x2a, 0x34, 0x35, 0x36, 0x38, 0x3e => 2,
                0x29, 0x2b, 0x37, 0x39 => 3,
                0x2c, 0x2d, 0x30, 0x31, 0x3a, 0x3c => 0,
                0x2e, 0x2f, 0x32, 0x33, 0x3b, 0x3d => 1,
                else => unreachable,
            };
        }

        fn wasmSkipPrefixedInstruction(
            body: []const u8,
            cursor: *usize,
            i32_stack_depth: *u32,
            non_i32_stack_depth: *u32,
            memory_count: u32,
            strict_stack: bool,
        ) !void {
            const opcode = try wasmReadU32(body, cursor);
            switch (opcode) {
                0, 1, 2, 3 => {
                    try wasmConsumeNonI32ForMode(non_i32_stack_depth, 1, strict_stack);
                    i32_stack_depth.* += 1;
                },
                4, 5 => {
                    try wasmConsumeI32ForMode(i32_stack_depth, 1, strict_stack);
                    i32_stack_depth.* += 1;
                },
                6, 7 => {
                    try wasmConsumeNonI32ForMode(non_i32_stack_depth, 1, strict_stack);
                    i32_stack_depth.* += 1;
                },
                8 => {
                    _ = try wasmReadU32(body, cursor);
                    if (try wasmReadU32(body, cursor) >= memory_count) return error.InvalidFrameEncoding;
                    try wasmConsumeI32ForMode(i32_stack_depth, 3, strict_stack);
                },
                9 => {
                    _ = try wasmReadU32(body, cursor);
                },
                10 => {
                    if (try wasmReadU32(body, cursor) >= memory_count) return error.InvalidFrameEncoding;
                    if (try wasmReadU32(body, cursor) >= memory_count) return error.InvalidFrameEncoding;
                    try wasmConsumeI32ForMode(i32_stack_depth, 3, strict_stack);
                },
                11 => {
                    if (try wasmReadU32(body, cursor) >= memory_count) return error.InvalidFrameEncoding;
                    try wasmConsumeI32ForMode(i32_stack_depth, 3, strict_stack);
                },
                else => return error.InvalidFrameEncoding,
            }
        }

        fn wasmConsumeI32(stack_depth: *u32, count: u32) !void {
            if (stack_depth.* < count) return error.InvalidFrameEncoding;
            stack_depth.* -= count;
        }

        fn wasmConsumeNonI32(stack_depth: *u32, count: u32) !void {
            if (stack_depth.* < count) return error.InvalidFrameEncoding;
            stack_depth.* -= count;
        }

        fn wasmConsumeAny(i32_stack_depth: *u32, non_i32_stack_depth: *u32) !void {
            if (non_i32_stack_depth.* > 0) {
                non_i32_stack_depth.* -= 1;
                return;
            }
            if (i32_stack_depth.* > 0) {
                i32_stack_depth.* -= 1;
                return;
            }
            return error.InvalidFrameEncoding;
        }

        fn wasmConsumeAnyLenient(i32_stack_depth: *u32, non_i32_stack_depth: *u32) void {
            wasmConsumeAny(i32_stack_depth, non_i32_stack_depth) catch {};
        }

        fn wasmConsumeI32ForMode(stack_depth: *u32, count: u32, strict_stack: bool) !void {
            if (strict_stack) return wasmConsumeI32(stack_depth, count);
            wasmDiscardPossibleI32(stack_depth, count);
        }

        fn wasmConsumeNonI32ForMode(stack_depth: *u32, count: u32, strict_stack: bool) !void {
            if (strict_stack) return wasmConsumeNonI32(stack_depth, count);
            stack_depth.* = if (stack_depth.* > count) stack_depth.* - count else 0;
        }

        fn wasmConsumeAnyForMode(i32_stack_depth: *u32, non_i32_stack_depth: *u32, strict_stack: bool) !void {
            if (strict_stack) return wasmConsumeAny(i32_stack_depth, non_i32_stack_depth);
            wasmConsumeAnyLenient(i32_stack_depth, non_i32_stack_depth);
        }

        fn wasmConsumeSignatureParams(
            i32_stack_depth: *u32,
            non_i32_stack_depth: *u32,
            signature: WasmFuncSignature,
            strict_stack: bool,
        ) !void {
            if (strict_stack) {
                try wasmConsumeI32(i32_stack_depth, signature.i32_param_count);
                try wasmConsumeNonI32(non_i32_stack_depth, signature.param_count - signature.i32_param_count);
                return;
            }
            var param_index: u32 = 0;
            while (param_index < signature.param_count) : (param_index += 1) {
                wasmConsumeAnyLenient(i32_stack_depth, non_i32_stack_depth);
            }
        }

        fn wasmDiscardPossibleI32(stack_depth: *u32, count: u32) void {
            stack_depth.* = if (stack_depth.* > count) stack_depth.* - count else 0;
        }

        fn skipApplianceWasmLocals(body: []const u8, cursor: *usize) !void {
            const local_group_count = try wasmReadU32(body, cursor);
            var local_group_index: u32 = 0;
            while (local_group_index < local_group_count) : (local_group_index += 1) {
                _ = try wasmReadU32(body, cursor);
                const value_type = try wasmReadU8(body, cursor);
                if (!validApplianceWasmLocalType(value_type)) return error.InvalidFrameEncoding;
            }
        }

        fn validApplianceWasmLocalType(value_type: u8) bool {
            return switch (value_type) {
                0x7f, 0x7e, 0x7d, 0x7c, 0x7b, 0x70, 0x6f => true,
                else => false,
            };
        }

        fn wasmReadI32Bits(bytes: []const u8, cursor: *usize) !u32 {
            var result: i64 = 0;
            var shift: u6 = 0;
            var count: u8 = 0;
            var byte: u8 = 0;
            while (true) {
                if (cursor.* >= bytes.len or count == 5) return error.InvalidFrameEncoding;
                byte = bytes[cursor.*];
                cursor.* += 1;
                result |= @as(i64, byte & 0x7f) << shift;
                count += 1;
                if ((byte & 0x80) == 0) break;
                shift += 7;
            }
            if (shift < 32 and (byte & 0x40) != 0) {
                result |= -(@as(i64, 1) << (shift + 7));
            }
            if (result < std.math.minInt(i32) or result > std.math.maxInt(i32)) return error.InvalidFrameEncoding;
            return @bitCast(@as(i32, @intCast(result)));
        }

        fn wasmSkipImportDesc(section: []const u8, cursor: *usize, kind: u8) !void {
            switch (kind) {
                0 => _ = try wasmReadU32(section, cursor),
                1 => {
                    _ = try wasmReadU8(section, cursor);
                    try wasmSkipLimits(section, cursor);
                },
                2 => try wasmSkipLimits(section, cursor),
                3 => {
                    _ = try wasmReadU8(section, cursor);
                    const mutable = try wasmReadU8(section, cursor);
                    if (mutable > 1) return error.InvalidFrameEncoding;
                },
                else => return error.InvalidFrameEncoding,
            }
        }

        fn wasmSkipLimits(section: []const u8, cursor: *usize) !void {
            _ = try wasmReadLimits(section, cursor);
        }

        fn wasmReadLimits(section: []const u8, cursor: *usize) !WasmLimits {
            const flags = try wasmReadU32(section, cursor);
            const min = try wasmReadU32(section, cursor);
            const max = if ((flags & 1) != 0) try wasmReadU32(section, cursor) else null;
            if ((flags & ~@as(u32, 1)) != 0) return error.InvalidFrameEncoding;
            if (max != null and max.? < min) return error.InvalidFrameEncoding;
            return .{
                .min = min,
                .max = max,
            };
        }

        fn wasmForbiddenImport(bytes: []const u8) bool {
            for (Abi.forbidden_import_fragments) |fragment| {
                if (std.mem.indexOf(u8, bytes, fragment) != null) return true;
            }
            return false;
        }

        fn wasmReadName(bytes: []const u8, cursor: *usize) ![]const u8 {
            const len = try wasmReadU32(bytes, cursor);
            if (len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const start = cursor.*;
            cursor.* += len;
            const name = bytes[start..cursor.*];
            if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidFrameEncoding;
            return name;
        }

        fn wasmReadU8(bytes: []const u8, cursor: *usize) !u8 {
            if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
            const value = bytes[cursor.*];
            cursor.* += 1;
            return value;
        }

        fn wasmReadU32(bytes: []const u8, cursor: *usize) !u32 {
            var result: u32 = 0;
            var shift: u5 = 0;
            var count: u8 = 0;
            while (true) {
                if (cursor.* >= bytes.len or count == 5) return error.InvalidFrameEncoding;
                const byte = bytes[cursor.*];
                cursor.* += 1;
                const payload = byte & 0x7f;
                if (count == 4 and payload > 0x0f) return error.InvalidFrameEncoding;
                result |= @as(u32, payload) << shift;
                count += 1;
                if ((byte & 0x80) == 0) return result;
                if (shift >= 28) return error.InvalidFrameEncoding;
                shift += 7;
            }
        }

        fn define(comptime RootTarget: type, comptime config: anytype) type {
            @setEvalBranchQuota(2_000_000);
            const profile = configProfile(config);
            const capacity = configCapacity(config);
            capacity.validateForProfile(profile) catch @compileError("World Appliance capacity is invalid for profile");
            const metadata = configMetadata(config);
            const providers = if (@hasField(@TypeOf(config), "providers")) config.providers else .{};
            const actuation_bindings = if (@hasField(@TypeOf(config), "actuation_bindings")) config.actuation_bindings else .{};
            const covered_world_ports = assemblyCoveredWorldPorts(config);
            const fabric_plan_fingerprints = assemblyFabricPlanFingerprints(config);
            validateClosedWorldDefinition(RootTarget, profile, capacity, actuation_bindings, covered_world_ports, fabric_plan_fingerprints, providers, config);
            const root_ref = World.TargetRef.fromTarget(RootTarget);
            const import_set = World.ImportSet.fromTarget(RootTarget);
            const provider_target_refs = providerTargetRefFingerprints(providers);
            const actuation_descriptor_fingerprints = actuationDescriptorFingerprints(actuation_bindings);
            const actuation_binding_fingerprints = actuationBindingFingerprints(actuation_bindings);
            const actuation_actuator_ref_fingerprints = actuationActuatorRefFingerprints(actuation_bindings);
            const actuation_world_port_ids = actuationWorldPortIds(actuation_bindings);
            const actuation_classes = actuationClasses(actuation_bindings);
            const actuation_allowed_response_statuses = actuationAllowedResponseStatuses(actuation_bindings);
            const plan = MemoryPlan.derive(capacity, profile);
            const manifest_value = Manifest.init(.{
                .root_target_ref_fingerprint = root_ref.target_ref_fingerprint,
                .root_world_surface_fingerprint = root_ref.world_surface_fingerprint,
                .root_target_certificate_fingerprint = root_ref.target_certificate_fingerprint,
                .link_plan_fingerprint = assemblyLinkPlanFingerprint(config),
                .link_certificate_fingerprint = assemblyLinkCertificateFingerprint(config),
                .assembly_fingerprint = assemblyFingerprint(config),
                .provider_target_ref_fingerprints = &provider_target_refs,
                .fabric_plan_fingerprints = &fabric_plan_fingerprints,
                .residual_import_set_fingerprint = assemblyResidualImportSetFingerprint(config) orelse import_set.import_set_fingerprint,
                .actuation_descriptor_fingerprints = &actuation_descriptor_fingerprints,
                .actuation_binding_fingerprints = &actuation_binding_fingerprints,
                .actuation_actuator_ref_fingerprints = &actuation_actuator_ref_fingerprints,
                .actuation_world_port_ids = &actuation_world_port_ids,
                .actuation_classes = &actuation_classes,
                .actuation_allowed_response_statuses = &actuation_allowed_response_statuses,
                .supported_execution_modes = ExecutionModeSet.forManifest(profile, actuation_bindings.len),
                .enabled_features = FeatureSet.fromProfile(profile),
                .capacity_fingerprint = capacity.fingerprint(),
                .memory_plan_fingerprint = plan.plan_fingerprint,
                .required_host_capabilities = HostCapabilityFlags.forManifest(profile, actuation_bindings.len),
                .metadata = metadata,
            });
            const definition_report = DefinitionReport{
                .root_world_port_count = RootTarget.WorldPortTable.entries.len,
                .provider_count = providers.len,
                .actuation_binding_count = actuation_bindings.len,
                .strict_closed_world = profile.strict_closed_world,
                .accepted = true,
            };
            return struct {
                pub const Root = RootTarget;
                pub const profile_value = profile;
                pub const capacity_value = capacity;
                pub const memory_plan_value = plan;
                pub const manifest_value_const = manifest_value;
                pub const definition_report_value = definition_report;

                pub fn manifest() Manifest {
                    return manifest_value_const;
                }

                pub fn definitionReport() DefinitionReport {
                    return definition_report_value;
                }

                pub fn memoryPlan() MemoryPlan {
                    return memory_plan_value;
                }

                pub fn requiredMemoryBytes() usize {
                    return memory_plan_value.maximum_linear_memory_bytes;
                }
            };
        }

        fn validateClosedWorldDefinition(
            comptime RootTarget: type,
            comptime profile: Profile,
            comptime capacity: Capacity,
            comptime actuation_bindings: anytype,
            comptime covered_world_ports: anytype,
            comptime fabric_plan_fingerprints: anytype,
            comptime providers: anytype,
            comptime config: anytype,
        ) void {
            comptime {
                _ = World.TargetRef.fromTarget(RootTarget);
                if (!profile.enable_actuation and actuation_bindings.len != 0) @compileError("World Appliance actuation bindings require a profile with actuation enabled");
                if (profile.kind == .replay_only and actuation_bindings.len != 0) @compileError("World Appliance replay-only profile does not support external Actuation bindings");
                if (actuation_bindings.len > capacity.max_host_requests_per_turn) @compileError("World Appliance external Actuation bindings exceed Capacity.max_host_requests_per_turn");
                if (actuation_bindings.len > capacity.max_host_replies_per_turn) @compileError("World Appliance external Actuation bindings exceed Capacity.max_host_replies_per_turn");
                if (actuation_bindings.len > capacity.max_actuation_records) @compileError("World Appliance external Actuation bindings exceed Capacity.max_actuation_records");
                for (actuation_bindings) |BindingDecl| {
                    if (BindingDecl.TargetType != RootTarget) @compileError("World Appliance actuation binding target does not match root Target");
                    if (BindingDecl.world_port_id >= RootTarget.WorldPortTable.entries.len) @compileError("World Appliance actuation binding world_port_id is out of range");
                    const binding = BindingDecl.actuationBindingRecord();
                    binding.validate() catch @compileError("World Appliance actuation binding record failed validation");
                }
                if (profile.strict_closed_world) {
                    if (providers.len > capacity.max_provider_runs) @compileError("World Appliance provider targets exceed Capacity.max_provider_runs");
                    if (covered_world_ports.len != 0) {
                        if (providers.len == 0) @compileError("World Appliance assembly-covered ports require explicit provider targets");
                        if (assemblyLinkPlanFingerprint(config) == 0) @compileError("World Appliance assembly-covered ports require LinkPlan evidence");
                        if (assemblyLinkCertificateFingerprint(config) == 0) @compileError("World Appliance assembly-covered ports require LinkCertificate evidence");
                        if (assemblyFingerprint(config) == 0) @compileError("World Appliance assembly-covered ports require Assembly evidence");
                        if (fabric_plan_fingerprints.len == 0) @compileError("World Appliance assembly-covered ports require Fabric.Plan evidence");
                        for (fabric_plan_fingerprints) |fingerprint| {
                            if (fingerprint == 0) @compileError("World Appliance Fabric.Plan fingerprint evidence must be nonzero");
                        }
                    }
                    for (covered_world_ports, 0..) |covered_port_id, index| {
                        if (covered_port_id >= RootTarget.WorldPortTable.entries.len) @compileError("World Appliance assembly-covered world_port_id is out of range");
                        for (covered_world_ports[index + 1 ..]) |other_port_id| {
                            if (covered_port_id == other_port_id) @compileError("World Appliance assembly-covered world_port_id appears more than once");
                        }
                    }
                    for (0..RootTarget.WorldPortTable.entries.len) |world_port_index| {
                        const port_id: u32 = @intCast(world_port_index);
                        const covered = assemblyCoversPort(covered_world_ports, port_id);
                        const count = actuationBindingCountForPort(RootTarget, actuation_bindings, port_id);
                        if (!covered and count == 0) @compileError("World Appliance strict closed-world definition requires explicit actuation binding for every unresolved external port");
                        if (covered and count != 0) @compileError("World Appliance assembly-covered port must not also be exposed as external Actuation");
                        if (count > 1) @compileError("World Appliance strict closed-world definition rejects duplicate actuation bindings for a port");
                    }
                }
            }
        }

        fn assemblyCoversPort(comptime covered_world_ports: anytype, comptime world_port_id: u32) bool {
            inline for (covered_world_ports) |covered_port_id| {
                if (covered_port_id == world_port_id) return true;
            }
            return false;
        }

        fn actuationBindingCountForPort(comptime RootTarget: type, comptime actuation_bindings: anytype, comptime world_port_id: u32) usize {
            var count: usize = 0;
            inline for (actuation_bindings) |BindingDecl| {
                if (BindingDecl.TargetType == RootTarget and BindingDecl.world_port_id == world_port_id) count += 1;
            }
            return count;
        }

        fn providerTargetRefFingerprints(comptime providers: anytype) [providers.len]u64 {
            var values: [providers.len]u64 = undefined;
            inline for (providers, 0..) |ProviderTarget, index| {
                values[index] = World.TargetRef.fromTarget(ProviderTarget).target_ref_fingerprint;
            }
            return values;
        }

        fn actuationDescriptorFingerprints(comptime actuation_bindings: anytype) [actuation_bindings.len]u64 {
            var values: [actuation_bindings.len]u64 = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.actuationDescriptor().descriptor_fingerprint;
            }
            return values;
        }

        fn actuationBindingFingerprints(comptime actuation_bindings: anytype) [actuation_bindings.len]u64 {
            var values: [actuation_bindings.len]u64 = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.actuationBindingRecord().binding_fingerprint;
            }
            return values;
        }

        fn actuationActuatorRefFingerprints(comptime actuation_bindings: anytype) [actuation_bindings.len]u64 {
            var values: [actuation_bindings.len]u64 = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.actuator_ref.ref_fingerprint;
            }
            return values;
        }

        fn actuationWorldPortIds(comptime actuation_bindings: anytype) [actuation_bindings.len]u64 {
            var values: [actuation_bindings.len]u64 = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.world_port_id;
            }
            return values;
        }

        fn actuationClasses(comptime actuation_bindings: anytype) [actuation_bindings.len]World.Actuation.Class {
            var values: [actuation_bindings.len]World.Actuation.Class = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.actuator_ref.class;
            }
            return values;
        }

        fn actuationAllowedResponseStatuses(comptime actuation_bindings: anytype) [actuation_bindings.len]World.Actuation.ResponseStatusSet {
            var values: [actuation_bindings.len]World.Actuation.ResponseStatusSet = undefined;
            inline for (actuation_bindings, 0..) |BindingDecl, index| {
                values[index] = BindingDecl.actuationDescriptor().allowed_response_kinds;
            }
            return values;
        }

        fn assemblyCoveredPortCount(comptime config: anytype) usize {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return 0;
                if (!@hasField(@TypeOf(config.assembly_recipe), "covered_world_ports")) return 0;
                return config.assembly_recipe.covered_world_ports.len;
            }
        }

        fn assemblyCoveredWorldPorts(comptime config: anytype) [assemblyCoveredPortCount(config)]u32 {
            const count = assemblyCoveredPortCount(config);
            var values: [count]u32 = undefined;
            if (count == 0) return values;
            inline for (config.assembly_recipe.covered_world_ports, 0..) |world_port_id, index| {
                values[index] = world_port_id;
            }
            return values;
        }

        fn assemblyFabricPlanCount(comptime config: anytype) usize {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return 0;
                if (!@hasField(@TypeOf(config.assembly_recipe), "fabric_plan_fingerprints")) return 0;
                return config.assembly_recipe.fabric_plan_fingerprints.len;
            }
        }

        fn assemblyFabricPlanFingerprints(comptime config: anytype) [assemblyFabricPlanCount(config)]u64 {
            const count = assemblyFabricPlanCount(config);
            var values: [count]u64 = undefined;
            if (count == 0) return values;
            inline for (config.assembly_recipe.fabric_plan_fingerprints, 0..) |fingerprint, index| {
                values[index] = fingerprint;
            }
            return values;
        }

        fn assemblyLinkPlanFingerprint(comptime config: anytype) u64 {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return 0;
                if (!@hasField(@TypeOf(config.assembly_recipe), "link_plan_fingerprint")) return 0;
                return config.assembly_recipe.link_plan_fingerprint;
            }
        }

        fn assemblyLinkCertificateFingerprint(comptime config: anytype) u64 {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return 0;
                if (!@hasField(@TypeOf(config.assembly_recipe), "link_certificate_fingerprint")) return 0;
                return config.assembly_recipe.link_certificate_fingerprint;
            }
        }

        fn assemblyFingerprint(comptime config: anytype) u64 {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return 0;
                if (!@hasField(@TypeOf(config.assembly_recipe), "assembly_fingerprint")) return 0;
                return config.assembly_recipe.assembly_fingerprint;
            }
        }

        fn assemblyResidualImportSetFingerprint(comptime config: anytype) ?u64 {
            comptime {
                if (!@hasField(@TypeOf(config), "assembly_recipe")) return null;
                if (!@hasField(@TypeOf(config.assembly_recipe), "residual_import_set_fingerprint")) return null;
                return config.assembly_recipe.residual_import_set_fingerprint;
            }
        }

        fn configProfile(comptime config: anytype) Profile {
            if (@hasField(@TypeOf(config), "profile")) return config.profile;
            return (Config{}).profile;
        }

        fn configCapacity(comptime config: anytype) Capacity {
            if (@hasField(@TypeOf(config), "capacity")) return config.capacity;
            return (Config{}).capacity;
        }

        fn configMetadata(comptime config: anytype) []const u8 {
            if (@hasField(@TypeOf(config), "metadata")) return config.metadata;
            return (Config{}).metadata;
        }

        const default_alignment: usize = 16;
        const wasm_page_size: usize = 64 * 1024;

        fn alignBytes(value: usize) usize {
            return std.mem.alignForward(usize, value, default_alignment);
        }

        fn alignPage(value: usize) usize {
            return std.mem.alignForward(usize, value, wasm_page_size);
        }

        fn checkedAdd(a: usize, b: usize) !usize {
            const result = @addWithOverflow(a, b);
            if (result[1] != 0) return error.CapacityExceeded;
            return result[0];
        }

        fn checkedMul(a: usize, b: usize) !usize {
            const result = @mulWithOverflow(a, b);
            if (result[1] != 0) return error.CapacityExceeded;
            return result[0];
        }

        fn alignBytesChecked(value: usize) !usize {
            const remainder = value % default_alignment;
            if (remainder == 0) return value;
            return checkedAdd(value, default_alignment - remainder);
        }

        fn alignPageChecked(value: usize) !usize {
            const remainder = value % wasm_page_size;
            if (remainder == 0) return value;
            return checkedAdd(value, wasm_page_size - remainder);
        }

        fn fingerprintMemoryPlan(plan: MemoryPlan) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashU64(&hasher, World.world_appliance_memory_plan_fingerprint_version);
            hashU64(&hasher, plan.persistent_core_bytes);
            hashU64(&hasher, plan.scratch_bytes);
            hashU64(&hasher, plan.input_buffer_bytes);
            hashU64(&hasher, plan.output_buffer_bytes);
            hashU64(&hasher, plan.checkpoint_buffer_bytes);
            hashU64(&hasher, plan.archive_append_buffer_bytes);
            hashU64(&hasher, plan.maximum_linear_memory_bytes);
            hashU64(&hasher, plan.maximum_linear_memory_pages);
            hashU64(&hasher, plan.alignment);
            hashU64(&hasher, @as(u16, @bitCast(plan.enabled_feature_summary)));
            return nonzero(hasher.final());
        }

        fn fingerprintManifest(manifest: Manifest) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashU64(&hasher, manifest.manifest_format_version);
            hashU64(&hasher, manifest.manifest_fingerprint_version);
            hashU64(&hasher, manifest.appliance_abi_version);
            hashU64(&hasher, manifest.root_target_ref_fingerprint);
            hashU64(&hasher, manifest.root_world_surface_fingerprint);
            hashU64(&hasher, manifest.root_target_certificate_fingerprint);
            hashU64(&hasher, manifest.link_plan_fingerprint);
            hashU64(&hasher, manifest.link_certificate_fingerprint);
            hashU64(&hasher, manifest.assembly_fingerprint);
            hashU64Slice(&hasher, manifest.provider_target_ref_fingerprints);
            hashU64Slice(&hasher, manifest.fabric_plan_fingerprints);
            hashU64(&hasher, manifest.residual_import_set_fingerprint);
            hashU64Slice(&hasher, manifest.actuation_descriptor_fingerprints);
            hashU64Slice(&hasher, manifest.actuation_binding_fingerprints);
            hashU64Slice(&hasher, manifest.actuation_actuator_ref_fingerprints);
            hashU64Slice(&hasher, manifest.actuation_world_port_ids);
            hashActuationClassSlice(&hasher, manifest.actuation_classes);
            hashResponseStatusSetSlice(&hasher, manifest.actuation_allowed_response_statuses);
            hashU64(&hasher, manifest.supervision_policy_fingerprint);
            hashU64Slice(&hasher, manifest.default_permit_requirement_fingerprints);
            hashU64(&hasher, manifest.capsule_profile_fingerprint);
            hashU64(&hasher, manifest.archive_profile_fingerprint);
            hashU64(&hasher, @as(u8, @bitCast(manifest.supported_execution_modes)));
            hashU64(&hasher, @as(u16, @bitCast(manifest.enabled_features)));
            hashU64(&hasher, manifest.capacity_fingerprint);
            hashU64(&hasher, manifest.memory_plan_fingerprint);
            hashU64(&hasher, @as(u8, @bitCast(manifest.required_host_capabilities)));
            hashBytes(&hasher, manifest.metadata);
            return nonzero(hasher.final());
        }

        fn readManifestOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Manifest {
            const manifest_format_version = try readU32(bytes, cursor);
            const manifest_fingerprint_version = try readU32(bytes, cursor);
            const manifest_fingerprint = try readU64(bytes, cursor);
            const appliance_abi_version = try readU32(bytes, cursor);
            const root_target_ref_fingerprint = try readU64(bytes, cursor);
            const root_world_surface_fingerprint = try readU64(bytes, cursor);
            const root_target_certificate_fingerprint = try readU64(bytes, cursor);
            const link_plan_fingerprint = try readU64(bytes, cursor);
            const link_certificate_fingerprint = try readU64(bytes, cursor);
            const assembly_fingerprint = try readU64(bytes, cursor);
            const provider_target_ref_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(provider_target_ref_fingerprints);
            const fabric_plan_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(fabric_plan_fingerprints);
            const residual_import_set_fingerprint = try readU64(bytes, cursor);
            const actuation_descriptor_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_descriptor_fingerprints);
            const actuation_binding_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_binding_fingerprints);
            const actuation_actuator_ref_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_actuator_ref_fingerprints);
            const actuation_world_port_ids = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_world_port_ids);
            const actuation_classes = try readActuationClassSliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_classes);
            const actuation_allowed_response_statuses = try readResponseStatusSetSliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(actuation_allowed_response_statuses);
            const supervision_policy_fingerprint = try readU64(bytes, cursor);
            const default_permit_requirement_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(default_permit_requirement_fingerprints);
            const capsule_profile_fingerprint = try readU64(bytes, cursor);
            const archive_profile_fingerprint = try readU64(bytes, cursor);
            const supported_execution_modes: ExecutionModeSet = @bitCast(try readU8(bytes, cursor));
            const enabled_features: FeatureSet = @bitCast(try readU16(bytes, cursor));
            const capacity_fingerprint = try readU64(bytes, cursor);
            const memory_plan_fingerprint = try readU64(bytes, cursor);
            const required_host_capabilities: HostCapabilityFlags = @bitCast(try readU8(bytes, cursor));
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            return .{
                .manifest_format_version = manifest_format_version,
                .manifest_fingerprint_version = manifest_fingerprint_version,
                .manifest_fingerprint = manifest_fingerprint,
                .appliance_abi_version = appliance_abi_version,
                .root_target_ref_fingerprint = root_target_ref_fingerprint,
                .root_world_surface_fingerprint = root_world_surface_fingerprint,
                .root_target_certificate_fingerprint = root_target_certificate_fingerprint,
                .link_plan_fingerprint = link_plan_fingerprint,
                .link_certificate_fingerprint = link_certificate_fingerprint,
                .assembly_fingerprint = assembly_fingerprint,
                .provider_target_ref_fingerprints = provider_target_ref_fingerprints,
                .fabric_plan_fingerprints = fabric_plan_fingerprints,
                .residual_import_set_fingerprint = residual_import_set_fingerprint,
                .actuation_descriptor_fingerprints = actuation_descriptor_fingerprints,
                .actuation_binding_fingerprints = actuation_binding_fingerprints,
                .actuation_actuator_ref_fingerprints = actuation_actuator_ref_fingerprints,
                .actuation_world_port_ids = actuation_world_port_ids,
                .actuation_classes = actuation_classes,
                .actuation_allowed_response_statuses = actuation_allowed_response_statuses,
                .supervision_policy_fingerprint = supervision_policy_fingerprint,
                .default_permit_requirement_fingerprints = default_permit_requirement_fingerprints,
                .capsule_profile_fingerprint = capsule_profile_fingerprint,
                .archive_profile_fingerprint = archive_profile_fingerprint,
                .supported_execution_modes = supported_execution_modes,
                .enabled_features = enabled_features,
                .capacity_fingerprint = capacity_fingerprint,
                .memory_plan_fingerprint = memory_plan_fingerprint,
                .required_host_capabilities = required_host_capabilities,
                .metadata = metadata,
                .owns_payloads = true,
            };
        }

        fn manifestEncodedLen(manifest: Manifest) usize {
            return @sizeOf(u32) + @sizeOf(u32) + @sizeOf(u64) + @sizeOf(u32) +
                (6 * @sizeOf(u64)) +
                u64SliceEncodedLen(manifest.provider_target_ref_fingerprints) +
                u64SliceEncodedLen(manifest.fabric_plan_fingerprints) +
                @sizeOf(u64) +
                u64SliceEncodedLen(manifest.actuation_descriptor_fingerprints) +
                u64SliceEncodedLen(manifest.actuation_binding_fingerprints) +
                u64SliceEncodedLen(manifest.actuation_actuator_ref_fingerprints) +
                u64SliceEncodedLen(manifest.actuation_world_port_ids) +
                actuationClassSliceEncodedLen(manifest.actuation_classes) +
                responseStatusSetSliceEncodedLen(manifest.actuation_allowed_response_statuses) +
                @sizeOf(u64) +
                u64SliceEncodedLen(manifest.default_permit_requirement_fingerprints) +
                @sizeOf(u64) +
                @sizeOf(u64) +
                @sizeOf(u8) +
                @sizeOf(u16) +
                @sizeOf(u64) +
                @sizeOf(u64) +
                @sizeOf(u8) +
                byteFieldEncodedLen(manifest.metadata);
        }

        fn u64SliceEncodedLen(values: []const u64) usize {
            return @sizeOf(u64) + values.len * @sizeOf(u64);
        }

        fn actuationClassSliceEncodedLen(values: []const World.Actuation.Class) usize {
            return @sizeOf(u64) + values.len * @sizeOf(u8);
        }

        fn responseStatusSetSliceEncodedLen(values: []const World.Actuation.ResponseStatusSet) usize {
            return @sizeOf(u64) + values.len * @sizeOf(u8);
        }

        fn byteFieldEncodedLen(bytes: []const u8) usize {
            return @sizeOf(u32) + bytes.len;
        }

        fn writeManifestCanonicalBytes(manifest: Manifest, dest: []u8) !usize {
            const required = manifestEncodedLen(manifest);
            if (dest.len < required) return error.BufferTooSmall;
            var cursor: usize = 0;
            try putU32(dest, &cursor, manifest.manifest_format_version);
            try putU32(dest, &cursor, manifest.manifest_fingerprint_version);
            try putU64(dest, &cursor, manifest.manifest_fingerprint);
            try putU32(dest, &cursor, manifest.appliance_abi_version);
            try putU64(dest, &cursor, manifest.root_target_ref_fingerprint);
            try putU64(dest, &cursor, manifest.root_world_surface_fingerprint);
            try putU64(dest, &cursor, manifest.root_target_certificate_fingerprint);
            try putU64(dest, &cursor, manifest.link_plan_fingerprint);
            try putU64(dest, &cursor, manifest.link_certificate_fingerprint);
            try putU64(dest, &cursor, manifest.assembly_fingerprint);
            try putU64Slice(dest, &cursor, manifest.provider_target_ref_fingerprints);
            try putU64Slice(dest, &cursor, manifest.fabric_plan_fingerprints);
            try putU64(dest, &cursor, manifest.residual_import_set_fingerprint);
            try putU64Slice(dest, &cursor, manifest.actuation_descriptor_fingerprints);
            try putU64Slice(dest, &cursor, manifest.actuation_binding_fingerprints);
            try putU64Slice(dest, &cursor, manifest.actuation_actuator_ref_fingerprints);
            try putU64Slice(dest, &cursor, manifest.actuation_world_port_ids);
            try putActuationClassSlice(dest, &cursor, manifest.actuation_classes);
            try putResponseStatusSetSlice(dest, &cursor, manifest.actuation_allowed_response_statuses);
            try putU64(dest, &cursor, manifest.supervision_policy_fingerprint);
            try putU64Slice(dest, &cursor, manifest.default_permit_requirement_fingerprints);
            try putU64(dest, &cursor, manifest.capsule_profile_fingerprint);
            try putU64(dest, &cursor, manifest.archive_profile_fingerprint);
            try putU8(dest, &cursor, @as(u8, @bitCast(manifest.supported_execution_modes)));
            try putU16(dest, &cursor, @as(u16, @bitCast(manifest.enabled_features)));
            try putU64(dest, &cursor, manifest.capacity_fingerprint);
            try putU64(dest, &cursor, manifest.memory_plan_fingerprint);
            try putU8(dest, &cursor, @as(u8, @bitCast(manifest.required_host_capabilities)));
            try putBytes(dest, &cursor, manifest.metadata);
            if (cursor != required) return error.InvalidFrameEncoding;
            return required;
        }

        fn putU8(dest: []u8, cursor: *usize, value: u8) !void {
            if (cursor.* + @sizeOf(u8) > dest.len) return error.BufferTooSmall;
            dest[cursor.*] = value;
            cursor.* += @sizeOf(u8);
        }

        fn putU16(dest: []u8, cursor: *usize, value: u16) !void {
            if (cursor.* + @sizeOf(u16) > dest.len) return error.BufferTooSmall;
            std.mem.writeInt(u16, dest[cursor.*..][0..@sizeOf(u16)], value, .little);
            cursor.* += @sizeOf(u16);
        }

        fn putU32(dest: []u8, cursor: *usize, value: u32) !void {
            if (cursor.* + @sizeOf(u32) > dest.len) return error.BufferTooSmall;
            std.mem.writeInt(u32, dest[cursor.*..][0..@sizeOf(u32)], value, .little);
            cursor.* += @sizeOf(u32);
        }

        fn putU64(dest: []u8, cursor: *usize, value: u64) !void {
            if (cursor.* + @sizeOf(u64) > dest.len) return error.BufferTooSmall;
            std.mem.writeInt(u64, dest[cursor.*..][0..@sizeOf(u64)], value, .little);
            cursor.* += @sizeOf(u64);
        }

        fn putU64Slice(dest: []u8, cursor: *usize, values: []const u64) !void {
            try putU64(dest, cursor, @intCast(values.len));
            for (values) |value| try putU64(dest, cursor, value);
        }

        fn putActuationClassSlice(dest: []u8, cursor: *usize, values: []const World.Actuation.Class) !void {
            try putU64(dest, cursor, @intCast(values.len));
            for (values) |value| try putU8(dest, cursor, @intFromEnum(value));
        }

        fn putResponseStatusSetSlice(dest: []u8, cursor: *usize, values: []const World.Actuation.ResponseStatusSet) !void {
            try putU64(dest, cursor, @intCast(values.len));
            for (values) |value| try putU8(dest, cursor, responseStatusSetByte(value));
        }

        fn putBytes(dest: []u8, cursor: *usize, bytes: []const u8) !void {
            if (bytes.len > std.math.maxInt(u32)) return error.CapacityExceeded;
            try putU32(dest, cursor, @intCast(bytes.len));
            if (cursor.* + bytes.len > dest.len) return error.BufferTooSmall;
            @memcpy(dest[cursor.* .. cursor.* + bytes.len], bytes);
            cursor.* += bytes.len;
        }

        fn fingerprintCommand(command: Command) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashU64(&hasher, command.command_format_version);
            hashU64(&hasher, command.command_fingerprint_version);
            hashU64(&hasher, @intFromEnum(command.kind));
            hashU64(&hasher, command.manifest_fingerprint);
            hashU64(&hasher, command.turn_sequence_number);
            hashOptionalU64(&hasher, command.previous_turn_receipt_fingerprint);
            hashU64(&hasher, @intFromEnum(command.execution_mode));
            if (command.receiver_permit_fingerprint) |fingerprint| {
                hashBytes(&hasher, "world.appliance.command.receiver_permit_fingerprint");
                hashU64(&hasher, fingerprint);
            }
            if (command.receiver_evidence_fingerprints.len != 0) {
                hashBytes(&hasher, "world.appliance.command.receiver_evidence_fingerprints");
                hashU64Slice(&hasher, command.receiver_evidence_fingerprints);
            }
            if (command.root_argument_image.len != 0) {
                hashBytes(&hasher, "world.appliance.command.root_argument_image");
                hashBytes(&hasher, command.root_argument_image);
            }
            if (command.host_replies.len != 0) {
                hashBytes(&hasher, "world.appliance.command.host_replies");
                hashHostRepliesCanonical(&hasher, command.host_replies);
            }
            if (command.retention_ack) |ack| {
                hashBool(&hasher, true);
                hashU64(&hasher, ack.ack_fingerprint);
            } else {
                hashBool(&hasher, false);
            }
            if (command.restore_checkpoint) |checkpoint| {
                hashBool(&hasher, true);
                hashU64(&hasher, checkpoint.checkpoint_fingerprint);
            } else {
                hashBool(&hasher, false);
            }
            hashBytes(&hasher, command.metadata);
            return nonzero(hasher.final());
        }

        fn fingerprintQuiescenceReport(report: QuiescenceReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.quiescence_report.fingerprint");
            hashBool(&hasher, report.quiescent);
            hashU64(&hasher, report.runnable_run_count);
            hashU64(&hasher, report.parked_run_count);
            hashU64(&hasher, report.pending_host_request_count);
            hashU64(&hasher, report.active_fabric_count);
            hashU64(&hasher, report.prepared_actuation_count);
            hashU64(&hasher, report.completed_run_count);
            hashU64(&hasher, report.failed_run_count);
            hashU64(&hasher, report.blocker_count);
            hashU64(&hasher, report.warning_count);
            return nonzero(hasher.final());
        }

        fn fingerprintCheckpoint(checkpoint: Checkpoint) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.checkpoint.fingerprint");
            hashU64(&hasher, checkpoint.checkpoint_format_version);
            hashU64(&hasher, checkpoint.checkpoint_fingerprint_version);
            hashU64(&hasher, checkpoint.manifest_fingerprint);
            hashU64(&hasher, checkpoint.turn_sequence_number);
            hashU64(&hasher, checkpoint.capsule_fingerprint);
            hashOptionalU64(&hasher, checkpoint.capsule_image_ref_fingerprint);
            hashBytes(&hasher, checkpoint.capsule_image_bytes);
            hashOptionalU64(&hasher, checkpoint.latest_archive_moment_fingerprint);
            hashOptionalU64(&hasher, checkpoint.latest_archive_seal_fingerprint);
            hashOptionalU64(&hasher, checkpoint.latest_chronicle_cursor_fingerprint);
            hashOptionalU64(&hasher, checkpoint.pending_archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, if (checkpoint.pending_archive_resulting_cursor) |cursor| cursor.cursor_fingerprint else null);
            hashOptionalU64(&hasher, if (checkpoint.latest_archive_cursor) |cursor| cursor.cursor_fingerprint else null);
            hashU64(&hasher, @intFromEnum(checkpoint.core_state));
            hashOptionalU64(&hasher, checkpoint.previous_turn_receipt_fingerprint);
            for (checkpoint.outstanding_host_requests) |request| hashU64(&hasher, request.request_fingerprint);
            hashU64(&hasher, @intFromEnum(checkpoint.execution_mode));
            hashBytes(&hasher, checkpoint.metadata);
            return nonzero(hasher.final());
        }

        fn fingerprintTurnReceipt(receipt: TurnReceipt) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.turn_receipt.fingerprint");
            hashU64(&hasher, receipt.receipt_format_version);
            hashU64(&hasher, receipt.receipt_fingerprint_version);
            hashU64(&hasher, receipt.manifest_fingerprint);
            hashU64(&hasher, receipt.turn_sequence_number);
            hashU64(&hasher, receipt.command_fingerprint);
            hashOptionalU64(&hasher, receipt.prior_checkpoint_fingerprint);
            hashU64(&hasher, receipt.applied_host_reply_fingerprints.len);
            for (receipt.applied_host_reply_fingerprints) |fingerprint| hashU64(&hasher, fingerprint);
            hashU64(&hasher, receipt.emitted_host_request_fingerprints.len);
            for (receipt.emitted_host_request_fingerprints) |fingerprint| hashU64(&hasher, fingerprint);
            hashOptionalU64(&hasher, receipt.source_capsule_fingerprint);
            hashU64(&hasher, receipt.resulting_capsule_fingerprint);
            hashOptionalU64(&hasher, receipt.archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, receipt.resulting_archive_moment_fingerprint);
            hashOptionalU64(&hasher, receipt.resulting_archive_seal_fingerprint);
            hashOptionalU64(&hasher, receipt.resulting_chronicle_cursor_fingerprint);
            hashOptionalU64(&hasher, receipt.root_result_fingerprint);
            hashU64(&hasher, @intFromEnum(receipt.status));
            hashOptionalU64(&hasher, receipt.run_receipt_fingerprint);
            hashU64(&hasher, receipt.blocker_count);
            hashU64(&hasher, receipt.warning_count);
            return nonzero(hasher.final());
        }

        fn fingerprintTurnOutput(output: TurnOutput) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.turn_output.fingerprint");
            hashU64(&hasher, output.output_format_version);
            hashU64(&hasher, output.output_fingerprint_version);
            hashU64(&hasher, output.manifest_fingerprint);
            hashU64(&hasher, output.turn_sequence_number);
            hashU64(&hasher, output.source_state_fingerprint);
            hashU64(&hasher, output.resulting_state_fingerprint);
            hashU64(&hasher, output.quiescence.report_fingerprint);
            hashU64(&hasher, @intFromEnum(output.status));
            for (output.host_requests) |request| hashU64(&hasher, request.request_fingerprint);
            hashU64Slice(&hasher, output.finalized_actuation_receipt_fingerprints);
            hashOptionalU64(&hasher, output.root_result_fingerprint);
            hashBytes(&hasher, output.root_result_value_image_bytes);
            hashOptionalU64(&hasher, output.root_result_value_ref_fingerprint);
            hashOptionalU64(&hasher, output.run_receipt_fingerprint);
            hashBytes(&hasher, output.run_receipt_bytes);
            hashOptionalU64(&hasher, output.archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, output.archive_append_batch_ref_fingerprint);
            hashBytes(&hasher, output.checkpoint_bytes);
            hashBytes(&hasher, output.archive_append_batch_bytes);
            hashU64(&hasher, output.checkpoint.checkpoint_fingerprint);
            hashU64(&hasher, output.turn_receipt.receipt_fingerprint);
            hashU64(&hasher, output.blocker_count);
            hashU64(&hasher, output.warning_count);
            hashBytes(&hasher, output.diagnostic_metadata);
            return nonzero(hasher.final());
        }

        fn fingerprintHostRequest(request: HostRequest) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.host_request.fingerprint");
            hashU64(&hasher, request.request_format_version);
            hashU64(&hasher, request.request_fingerprint_version);
            hashU64(&hasher, request.turn_sequence_number);
            hashU64(&hasher, request.request_ordinal);
            hashU64(&hasher, request.run_handle_fingerprint);
            hashU64(&hasher, request.pending_port_fingerprint);
            hashU64(&hasher, request.world_port_id);
            hashU64(&hasher, request.target_ref_fingerprint);
            hashU64(&hasher, request.world_surface_fingerprint);
            hashU64(&hasher, request.actuator_ref_fingerprint);
            hashU64(&hasher, @intFromEnum(request.actuation_class));
            hashResponseStatusSet(&hasher, request.allowed_response_statuses);
            hashU64(&hasher, request.intent_fingerprint);
            hashU64(&hasher, request.envelope_fingerprint);
            hashU64(&hasher, request.decision_fingerprint);
            hashU64(&hasher, request.expected_response_descriptor_fingerprint);
            hashU64(&hasher, request.idempotency_key_fingerprint);
            hashOptionalU64(&hasher, request.supervision_ref_fingerprint);
            hashBytes(&hasher, request.metadata);
            hashBytes(&hasher, request.frame_request_bytes);
            hashBytes(&hasher, request.payload_value_image_bytes);
            hashOptionalU64(&hasher, request.payload_value_ref_fingerprint);
            hashOptionalU64(&hasher, request.payload_schema_ref_fingerprint);
            hashOptionalU64(&hasher, request.expected_response_value_ref_fingerprint);
            hashOptionalU64(&hasher, request.expected_response_schema_ref_fingerprint);
            hashBytes(&hasher, request.prepared_actuation_evidence_bytes);
            hashBytes(&hasher, request.idempotency_key_bytes);
            return nonzero(hasher.final());
        }

        fn fingerprintHostOutcome(outcome: HostOutcome) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.host_outcome.fingerprint");
            hashU64(&hasher, outcome.outcome_format_version);
            hashU64(&hasher, outcome.outcome_fingerprint_version);
            hashU64(&hasher, outcome.host_request_fingerprint);
            hashU64(&hasher, outcome.intent_fingerprint);
            hashU64(&hasher, outcome.envelope_fingerprint);
            hashU64(&hasher, outcome.idempotency_key_fingerprint);
            hashU64(&hasher, @intFromEnum(outcome.status));
            hashOptionalU64(&hasher, outcome.response_fingerprint);
            hashU64(&hasher, @intFromEnum(outcome.response_kind));
            hashBytes(&hasher, outcome.response_bytes);
            hashOptionalU64(&hasher, outcome.host_evidence_fingerprint);
            hashBytes(&hasher, outcome.host_evidence_bytes);
            hashU64(&hasher, outcome.attempt_number);
            hashBytes(&hasher, outcome.metadata);
            return nonzero(hasher.final());
        }

        fn fingerprintHostReply(reply: HostReply) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.host_reply.fingerprint");
            hashU64(&hasher, reply.reply_format_version);
            hashU64(&hasher, reply.reply_fingerprint_version);
            hashU64(&hasher, reply.target_host_request_fingerprint);
            hashU64(&hasher, reply.outcome.outcome_fingerprint);
            hashOptionalU64(&hasher, reply.retention_ack_fingerprint);
            if (reply.retention_ack) |ack| {
                hashBool(&hasher, true);
                hashU64(&hasher, ack.ack_fingerprint);
            } else {
                hashBool(&hasher, false);
            }
            hashBytes(&hasher, reply.metadata);
            return nonzero(hasher.final());
        }

        fn findHostRequest(requests: []const HostRequest, request_fingerprint: u64) ?HostRequest {
            for (requests) |request| {
                if (request.request_fingerprint == request_fingerprint) return request;
            }
            return null;
        }

        fn effectiveRetentionAck(command: Command) !?RetentionAck {
            var ack = command.retention_ack;
            var ack_fingerprint: ?u64 = if (ack) |existing| existing.ack_fingerprint else null;
            for (command.host_replies) |reply| {
                if (reply.retention_ack_fingerprint) |reply_ack_fingerprint| {
                    if (ack_fingerprint) |existing_fingerprint| {
                        if (existing_fingerprint != reply_ack_fingerprint) return error.InvalidFrameEncoding;
                    } else {
                        ack_fingerprint = reply_ack_fingerprint;
                    }
                }
                const reply_ack = reply.retention_ack orelse continue;
                if (ack_fingerprint) |existing_fingerprint| {
                    if (existing_fingerprint != reply_ack.ack_fingerprint) return error.InvalidFrameEncoding;
                } else {
                    ack_fingerprint = reply_ack.ack_fingerprint;
                }
                if (ack) |existing| {
                    if (existing.ack_fingerprint != reply_ack.ack_fingerprint) return error.InvalidFrameEncoding;
                } else {
                    ack = reply_ack;
                }
            }
            if (ack_fingerprint != null and ack == null) return error.InvalidFrameEncoding;
            return ack;
        }

        fn readHostRepliesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]HostReply {
            const count = try readU64(bytes, cursor);
            if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            if (count > bytes.len) return error.InvalidFrameEncoding;
            if (count > World.world_max_decoded_byte_field_len / @sizeOf(HostReply)) return error.InvalidFrameEncoding;
            const reply_count: usize = @intCast(count);
            const replies = try allocator.alloc(HostReply, reply_count);
            errdefer allocator.free(replies);
            var initialized: usize = 0;
            errdefer {
                for (replies[0..initialized]) |*reply| freeHostReply(allocator, reply);
            }
            while (initialized < reply_count) : (initialized += 1) {
                replies[initialized] = try readHostReplyOwned(allocator, bytes, cursor);
            }
            sortHostRepliesInPlace(replies);
            return replies;
        }

        fn writeHostRepliesCanonical(out: *std.ArrayList(u8), allocator: std.mem.Allocator, replies: []const HostReply) !void {
            try writeU64(out, allocator, @intCast(replies.len));
            var rank: usize = 0;
            while (rank < replies.len) : (rank += 1) {
                const index = hostReplyIndexForRank(replies, rank) orelse return error.InvalidFrameEncoding;
                try replies[index].encode(out, allocator);
            }
        }

        fn hashHostRepliesCanonical(hasher: *std.hash.Wyhash, replies: []const HostReply) void {
            hashU64(hasher, replies.len);
            var rank: usize = 0;
            while (rank < replies.len) : (rank += 1) {
                const index = hostReplyIndexForRank(replies, rank) orelse return;
                hashU64(hasher, replies[index].reply_fingerprint);
            }
        }

        fn hostReplyIndexForRank(replies: []const HostReply, rank: usize) ?usize {
            for (replies, 0..) |_, index| {
                var less: usize = 0;
                for (replies, 0..) |_, other_index| {
                    if (hostReplyOrderLess(replies, other_index, index)) less += 1;
                }
                if (less == rank) return index;
            }
            return null;
        }

        fn hostReplyOrderLess(replies: []const HostReply, lhs_index: usize, rhs_index: usize) bool {
            const lhs = replies[lhs_index];
            const rhs = replies[rhs_index];
            if (lhs.target_host_request_fingerprint != rhs.target_host_request_fingerprint) {
                return lhs.target_host_request_fingerprint < rhs.target_host_request_fingerprint;
            }
            if (lhs.reply_fingerprint != rhs.reply_fingerprint) {
                return lhs.reply_fingerprint < rhs.reply_fingerprint;
            }
            return lhs_index < rhs_index;
        }

        fn sortHostRepliesInPlace(replies: []HostReply) void {
            var index: usize = 1;
            while (index < replies.len) : (index += 1) {
                var cursor = index;
                while (cursor > 0 and hostReplyLess(replies[cursor], replies[cursor - 1])) : (cursor -= 1) {
                    std.mem.swap(HostReply, &replies[cursor], &replies[cursor - 1]);
                }
            }
        }

        fn hostReplyLess(lhs: HostReply, rhs: HostReply) bool {
            if (lhs.target_host_request_fingerprint != rhs.target_host_request_fingerprint) {
                return lhs.target_host_request_fingerprint < rhs.target_host_request_fingerprint;
            }
            return lhs.reply_fingerprint < rhs.reply_fingerprint;
        }

        fn commandHasTerminalHostReply(command: Command) bool {
            for (command.host_replies) |reply| {
                if (hostOutcomeStatusIsTerminal(reply.outcome.status)) return true;
            }
            return false;
        }

        fn commandHasNonTerminalHostReply(command: Command) bool {
            for (command.host_replies) |reply| {
                if (!hostOutcomeStatusIsTerminal(reply.outcome.status)) return true;
            }
            return false;
        }

        fn commandLeavesOutstandingHostRequests(requests: []const HostRequest, command: Command) bool {
            for (requests) |request| {
                if (!commandHasTerminalHostReplyForRequest(command, request.request_fingerprint)) return true;
            }
            return false;
        }

        fn commandHasTerminalHostReplyForRequest(command: Command, request_fingerprint: u64) bool {
            for (command.host_replies) |reply| {
                if (reply.target_host_request_fingerprint == request_fingerprint and hostOutcomeStatusIsTerminal(reply.outcome.status)) return true;
            }
            return false;
        }

        fn remainingHostRequestsAfterRepliesOwned(allocator: std.mem.Allocator, requests: []const HostRequest, command: Command) ![]HostRequest {
            var retained_count: usize = 0;
            for (requests) |request| {
                if (!commandHasTerminalHostReplyForRequest(command, request.request_fingerprint)) retained_count += 1;
            }
            if (retained_count == 0) return error.UnknownRequest;
            const retained = try allocator.alloc(HostRequest, retained_count);
            errdefer allocator.free(retained);
            var retained_index: usize = 0;
            for (requests) |request| {
                if (commandHasTerminalHostReplyForRequest(command, request.request_fingerprint)) continue;
                retained[retained_index] = request;
                retained_index += 1;
            }
            const cloned = try cloneHostRequestsOwned(allocator, retained);
            allocator.free(retained);
            return cloned;
        }

        fn commandHasRetentionAck(command: Command) bool {
            if (command.retention_ack != null) return true;
            for (command.host_replies) |reply| {
                if (reply.retention_ack != null) return true;
            }
            return false;
        }

        fn hostReplyFingerprintsOwned(allocator: std.mem.Allocator, replies: []const HostReply) ![]u64 {
            const fingerprints = try allocator.alloc(u64, replies.len);
            errdefer allocator.free(fingerprints);
            for (replies, 0..) |reply, index| fingerprints[index] = reply.reply_fingerprint;
            return fingerprints;
        }

        fn hostRequestFingerprintsOwned(allocator: std.mem.Allocator, requests: []const HostRequest) ![]u64 {
            const fingerprints = try allocator.alloc(u64, requests.len);
            errdefer allocator.free(fingerprints);
            for (requests, 0..) |request, index| fingerprints[index] = request.request_fingerprint;
            return fingerprints;
        }

        fn finalizedActuationReceiptFingerprintsFor(requests: []const HostRequest, command: Command, allocator: std.mem.Allocator) ![]u64 {
            var finalized_count: usize = 0;
            for (command.host_replies) |reply| {
                if (hostOutcomeStatusIsTerminal(reply.outcome.status)) finalized_count += 1;
            }
            const fingerprints = try allocator.alloc(u64, finalized_count);
            errdefer allocator.free(fingerprints);
            var index: usize = 0;
            for (command.host_replies) |reply| {
                if (!hostOutcomeStatusIsTerminal(reply.outcome.status)) continue;
                const finalized_request = findHostRequest(requests, reply.target_host_request_fingerprint) orelse return error.UnknownRequest;
                fingerprints[index] = try finalizedActuationReceiptFingerprintFor(finalized_request, reply);
                index += 1;
            }
            return fingerprints;
        }

        fn finalizedActuationReceiptFingerprintFor(request: HostRequest, reply: HostReply) !u64 {
            const status = actuationStatusForHostOutcome(reply.outcome.status);
            const commit_value = World.Actuation.Commit.init(.{
                .intent_fingerprint = request.intent_fingerprint,
                .decision_fingerprint = request.decision_fingerprint,
                .envelope_fingerprint = request.envelope_fingerprint,
                .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
                .attempt_number = reply.outcome.attempt_number,
                .status = actuationCommitStatusForHostOutcome(reply.outcome.status),
                .fresh_called = status != .cancelled,
            });
            try commit_value.validate();
            const response = World.Actuation.Response.init(.{
                .intent_fingerprint = request.intent_fingerprint,
                .commit_fingerprint = commit_value.commit_fingerprint,
                .actuator_ref_fingerprint = request.actuator_ref_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .status = status,
                .response_kind = .@"resume",
                .frame_response_fingerprint = if (status == .responded) reply.outcome.response_fingerprint orelse return error.InvalidFrameEncoding else null,
            });
            const receipt = World.Actuation.Receipt.init(.{
                .intent_fingerprint = request.intent_fingerprint,
                .envelope_fingerprint = request.envelope_fingerprint,
                .decision_fingerprint = request.decision_fingerprint,
                .commit_fingerprint = commit_value.commit_fingerprint,
                .response_fingerprint = response.response_fingerprint,
                .response_kind = response.response_kind,
                .frame_response_fingerprint = response.frame_response_fingerprint,
                .response_value_image_fingerprint = response.value_image_fingerprint,
                .recorded_response_fingerprint = response.recorded_response_fingerprint,
                .actuator_ref_fingerprint = request.actuator_ref_fingerprint,
                .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
                .request_fingerprint = request.request_fingerprint,
                .target_ref_fingerprint = request.target_ref_fingerprint,
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .world_port_id = request.world_port_id,
                .class = request.actuation_class,
                .mode = .fresh,
                .fresh_called = commit_value.fresh_called,
                .rejected = status == .rejected,
                .failed = status == .failed,
                .cancelled = status == .cancelled,
                .attempt_number = commit_value.attempt_number,
            });
            const finalized = World.Actuation.Finalized.init(.{
                .commit_value = commit_value,
                .response = response,
                .receipt = receipt,
            });
            try finalized.validate();
            return finalized.receipt.receipt_fingerprint;
        }

        fn hostOutcomeStatusIsTerminal(status: HostOutcomeStatus) bool {
            return switch (status) {
                .responded, .rejected, .failed, .cancelled => true,
                .pending, .deferred => false,
            };
        }

        fn actuationStatusForHostOutcome(status: HostOutcomeStatus) World.Actuation.ResponseStatus {
            return switch (status) {
                .responded => .responded,
                .rejected => .rejected,
                .failed => .failed,
                .pending => .pending,
                .deferred => .deferred,
                .cancelled => .cancelled,
            };
        }

        fn actuationCommitStatusForHostOutcome(status: HostOutcomeStatus) World.Actuation.CommitStatus {
            return switch (status) {
                .responded => .committed,
                .rejected => .rejected,
                .failed => .commit_failed,
                .pending, .deferred => .commit_pending,
                .cancelled => .cancelled,
            };
        }

        fn validateDistinctHostReplyTargets(replies: []const HostReply) !void {
            for (replies, 0..) |reply, index| {
                for (replies[index + 1 ..]) |other| {
                    if (reply.target_host_request_fingerprint == other.target_host_request_fingerprint) {
                        return error.DuplicateReply;
                    }
                }
            }
        }

        fn writeU64Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u64) !void {
            try writeU64(out, allocator, @intCast(values.len));
            for (values) |value| try writeU64(out, allocator, value);
        }

        fn writeResponseStatusSet(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: World.Actuation.ResponseStatusSet) !void {
            try writeU8(out, allocator, responseStatusSetByte(value));
        }

        fn readU64SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]u64 {
            const count = try readU64(bytes, cursor);
            if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            if (count > bytes.len) return error.InvalidFrameEncoding;
            if (count > World.world_max_decoded_byte_field_len / @sizeOf(u64)) return error.InvalidFrameEncoding;
            const value_count: usize = @intCast(count);
            const values = try allocator.alloc(u64, value_count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try readU64(bytes, cursor);
            return values;
        }

        fn readActuationClassSliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]World.Actuation.Class {
            const count = try readU64(bytes, cursor);
            if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            if (count > bytes.len) return error.InvalidFrameEncoding;
            if (count > World.world_max_decoded_byte_field_len / @sizeOf(World.Actuation.Class)) return error.InvalidFrameEncoding;
            const value_count: usize = @intCast(count);
            const values = try allocator.alloc(World.Actuation.Class, value_count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try enumFromByte(World.Actuation.Class, try readU8(bytes, cursor));
            return values;
        }

        fn readResponseStatusSetSliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]World.Actuation.ResponseStatusSet {
            const count = try readU64(bytes, cursor);
            if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            if (count > bytes.len) return error.InvalidFrameEncoding;
            if (count > World.world_max_decoded_byte_field_len / @sizeOf(u8)) return error.InvalidFrameEncoding;
            const value_count: usize = @intCast(count);
            const values = try allocator.alloc(World.Actuation.ResponseStatusSet, value_count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try readResponseStatusSet(bytes, cursor);
            return values;
        }

        fn readHostRequestsOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]HostRequest {
            const count = try readU64(bytes, cursor);
            if (count > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            if (count > bytes.len) return error.InvalidFrameEncoding;
            if (count > World.world_max_decoded_byte_field_len / @sizeOf(HostRequest)) return error.InvalidFrameEncoding;
            const request_count: usize = @intCast(count);
            const requests = try allocator.alloc(HostRequest, request_count);
            errdefer allocator.free(requests);
            var initialized: usize = 0;
            errdefer {
                for (requests[0..initialized]) |*request| freeHostRequest(allocator, request);
            }
            while (initialized < request_count) : (initialized += 1) {
                requests[initialized] = try readHostRequestOwned(allocator, bytes, cursor);
            }
            return requests;
        }

        fn readHostRequestOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !HostRequest {
            const request_format_version = try readU32(bytes, cursor);
            const request_fingerprint_version = try readU32(bytes, cursor);
            const request_fingerprint = try readU64(bytes, cursor);
            const turn_sequence_number = try readU64(bytes, cursor);
            const request_ordinal = try readU32(bytes, cursor);
            const run_handle_fingerprint = try readU64(bytes, cursor);
            const pending_port_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const target_ref_fingerprint = try readU64(bytes, cursor);
            const world_surface_fingerprint = try readU64(bytes, cursor);
            const actuator_ref_fingerprint = try readU64(bytes, cursor);
            const actuation_class = try enumFromByte(World.Actuation.Class, try readU8(bytes, cursor));
            const allowed_response_statuses = try readResponseStatusSet(bytes, cursor);
            const intent_fingerprint = try readU64(bytes, cursor);
            const envelope_fingerprint = try readU64(bytes, cursor);
            const decision_fingerprint = try readU64(bytes, cursor);
            const expected_response_descriptor_fingerprint = try readU64(bytes, cursor);
            const idempotency_key_fingerprint = try readU64(bytes, cursor);
            const supervision_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            const frame_request_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(frame_request_bytes);
            const payload_value_image_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(payload_value_image_bytes);
            const payload_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const payload_schema_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const expected_response_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const expected_response_schema_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const prepared_actuation_evidence_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(prepared_actuation_evidence_bytes);
            const idempotency_key_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(idempotency_key_bytes);
            return .{
                .request_format_version = request_format_version,
                .request_fingerprint_version = request_fingerprint_version,
                .request_fingerprint = request_fingerprint,
                .turn_sequence_number = turn_sequence_number,
                .request_ordinal = request_ordinal,
                .run_handle_fingerprint = run_handle_fingerprint,
                .pending_port_fingerprint = pending_port_fingerprint,
                .world_port_id = world_port_id,
                .target_ref_fingerprint = target_ref_fingerprint,
                .world_surface_fingerprint = world_surface_fingerprint,
                .actuator_ref_fingerprint = actuator_ref_fingerprint,
                .actuation_class = actuation_class,
                .allowed_response_statuses = allowed_response_statuses,
                .intent_fingerprint = intent_fingerprint,
                .envelope_fingerprint = envelope_fingerprint,
                .decision_fingerprint = decision_fingerprint,
                .expected_response_descriptor_fingerprint = expected_response_descriptor_fingerprint,
                .idempotency_key_fingerprint = idempotency_key_fingerprint,
                .supervision_ref_fingerprint = supervision_ref_fingerprint,
                .metadata = metadata,
                .owns_metadata = true,
                .frame_request_bytes = frame_request_bytes,
                .payload_value_image_bytes = payload_value_image_bytes,
                .payload_value_ref_fingerprint = payload_value_ref_fingerprint,
                .payload_schema_ref_fingerprint = payload_schema_ref_fingerprint,
                .expected_response_value_ref_fingerprint = expected_response_value_ref_fingerprint,
                .expected_response_schema_ref_fingerprint = expected_response_schema_ref_fingerprint,
                .prepared_actuation_evidence_bytes = prepared_actuation_evidence_bytes,
                .idempotency_key_bytes = idempotency_key_bytes,
                .owns_byte_payloads = true,
            };
        }

        fn readHostReplyOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !HostReply {
            const reply_format_version = try readU32(bytes, cursor);
            const reply_fingerprint_version = try readU32(bytes, cursor);
            const reply_fingerprint = try readU64(bytes, cursor);
            const target_host_request_fingerprint = try readU64(bytes, cursor);
            const outcome = try readHostOutcomeOwned(allocator, bytes, cursor);
            errdefer {
                var cleanup = outcome;
                freeHostOutcome(allocator, &cleanup);
            }
            const retention_ack_fingerprint = try readOptionalU64(bytes, cursor);
            const retention_ack = try readOptionalRetentionAckOwned(allocator, bytes, cursor);
            errdefer if (retention_ack) |ack| {
                var cleanup = ack;
                freeRetentionAck(allocator, &cleanup);
            };
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            return .{
                .reply_format_version = reply_format_version,
                .reply_fingerprint_version = reply_fingerprint_version,
                .reply_fingerprint = reply_fingerprint,
                .target_host_request_fingerprint = target_host_request_fingerprint,
                .outcome = outcome,
                .retention_ack_fingerprint = retention_ack_fingerprint,
                .retention_ack = retention_ack,
                .metadata = metadata,
                .owns_payloads = true,
            };
        }

        fn readHostOutcomeOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !HostOutcome {
            const outcome_format_version = try readU32(bytes, cursor);
            const outcome_fingerprint_version = try readU32(bytes, cursor);
            const outcome_fingerprint = try readU64(bytes, cursor);
            const host_request_fingerprint = try readU64(bytes, cursor);
            const intent_fingerprint = try readU64(bytes, cursor);
            const envelope_fingerprint = try readU64(bytes, cursor);
            const idempotency_key_fingerprint = try readU64(bytes, cursor);
            const status = try enumFromByte(HostOutcomeStatus, try readU8(bytes, cursor));
            const response_fingerprint = try readOptionalU64(bytes, cursor);
            const response_kind = try enumFromByte(HostResponseKind, try readU8(bytes, cursor));
            const response_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(response_bytes);
            const host_evidence_fingerprint = try readOptionalU64(bytes, cursor);
            const host_evidence_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(host_evidence_bytes);
            const attempt_number = try readU32(bytes, cursor);
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            return .{
                .outcome_format_version = outcome_format_version,
                .outcome_fingerprint_version = outcome_fingerprint_version,
                .outcome_fingerprint = outcome_fingerprint,
                .host_request_fingerprint = host_request_fingerprint,
                .intent_fingerprint = intent_fingerprint,
                .envelope_fingerprint = envelope_fingerprint,
                .idempotency_key_fingerprint = idempotency_key_fingerprint,
                .status = status,
                .response_fingerprint = response_fingerprint,
                .response_kind = response_kind,
                .response_bytes = response_bytes,
                .host_evidence_fingerprint = host_evidence_fingerprint,
                .host_evidence_bytes = host_evidence_bytes,
                .attempt_number = attempt_number,
                .metadata = metadata,
                .owns_payloads = true,
            };
        }

        fn writeOptionalRetentionAck(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ack: ?RetentionAck) !void {
            if (ack) |actual| {
                try writeU8(out, allocator, 1);
                try actual.encode(out, allocator);
            } else {
                try writeU8(out, allocator, 0);
            }
        }

        fn writeOptionalCursor(out: *std.ArrayList(u8), allocator: std.mem.Allocator, cursor: ?World.Continuity.Chronicle.Cursor) !void {
            if (cursor) |actual| {
                try writeU8(out, allocator, 1);
                try actual.validate();
                try writeU32(out, allocator, actual.cursor_fingerprint_version);
                try writeU64(out, allocator, actual.cursor_fingerprint);
                try writeU64(out, allocator, actual.event_index);
                try writeOptionalU64(out, allocator, actual.last_event_fingerprint);
                try writeU64(out, allocator, actual.cumulative_prefix_fingerprint);
                try writeU64(out, allocator, actual.committed_object_count);
                try writeU64(out, allocator, actual.committed_transaction_count);
                try writeBytes(out, allocator, actual.metadata_bytes);
            } else {
                try writeU8(out, allocator, 0);
            }
        }

        fn readOptionalRetentionAckOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?RetentionAck {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readRetentionAckOwned(allocator, bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn readOptionalCursorOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?World.Continuity.Chronicle.Cursor {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readCursorOwned(allocator, bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn readCursorOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !World.Continuity.Chronicle.Cursor {
            const cursor_fingerprint_version = try readU32(bytes, cursor);
            const cursor_fingerprint = try readU64(bytes, cursor);
            const event_index = try readU64(bytes, cursor);
            const last_event_fingerprint = try readOptionalU64(bytes, cursor);
            const cumulative_prefix_fingerprint = try readU64(bytes, cursor);
            const committed_object_count = try readU64(bytes, cursor);
            const committed_transaction_count = try readU64(bytes, cursor);
            const metadata_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata_bytes);
            const result = World.Continuity.Chronicle.Cursor{
                .cursor_fingerprint_version = cursor_fingerprint_version,
                .cursor_fingerprint = cursor_fingerprint,
                .event_index = event_index,
                .last_event_fingerprint = last_event_fingerprint,
                .cumulative_prefix_fingerprint = cumulative_prefix_fingerprint,
                .committed_object_count = committed_object_count,
                .committed_transaction_count = committed_transaction_count,
                .metadata_bytes = metadata_bytes,
            };
            try result.validate();
            return result;
        }

        fn readRetentionAckOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !RetentionAck {
            const append_batch_fingerprint = try readU64(bytes, cursor);
            const resulting_moment_fingerprint = try readU64(bytes, cursor);
            const resulting_seal_fingerprint = try readU64(bytes, cursor);
            const resulting_chronicle_cursor_fingerprint = try readU64(bytes, cursor);
            const host_claim_status = try enumFromByte(HostOutcomeStatus, try readU8(bytes, cursor));
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            const ack_fingerprint = try readU64(bytes, cursor);
            return .{
                .append_batch_fingerprint = append_batch_fingerprint,
                .resulting_moment_fingerprint = resulting_moment_fingerprint,
                .resulting_seal_fingerprint = resulting_seal_fingerprint,
                .resulting_chronicle_cursor_fingerprint = resulting_chronicle_cursor_fingerprint,
                .host_claim_status = host_claim_status,
                .metadata = metadata,
                .ack_fingerprint = ack_fingerprint,
            };
        }

        fn writeOptionalCheckpoint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, checkpoint: ?Checkpoint) !void {
            if (checkpoint) |actual| {
                try writeU8(out, allocator, 1);
                try actual.encode(out, allocator);
            } else {
                try writeU8(out, allocator, 0);
            }
        }

        fn readOptionalCheckpointOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?Checkpoint {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readCheckpointOwned(allocator, bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn readQuiescenceReport(bytes: []const u8, cursor: *usize) !QuiescenceReport {
            return .{
                .report_fingerprint = try readU64(bytes, cursor),
                .quiescent = try readBool(bytes, cursor),
                .runnable_run_count = try readUsize(bytes, cursor),
                .parked_run_count = try readUsize(bytes, cursor),
                .pending_host_request_count = try readUsize(bytes, cursor),
                .active_fabric_count = try readUsize(bytes, cursor),
                .prepared_actuation_count = try readUsize(bytes, cursor),
                .completed_run_count = try readUsize(bytes, cursor),
                .failed_run_count = try readUsize(bytes, cursor),
                .blocker_count = try readUsize(bytes, cursor),
                .warning_count = try readUsize(bytes, cursor),
            };
        }

        fn readTurnReceiptOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TurnReceipt {
            const receipt_format_version = try readU32(bytes, cursor);
            const receipt_fingerprint_version = try readU32(bytes, cursor);
            const receipt_fingerprint = try readU64(bytes, cursor);
            const manifest_fingerprint = try readU64(bytes, cursor);
            const turn_sequence_number = try readU64(bytes, cursor);
            const command_fingerprint = try readU64(bytes, cursor);
            const prior_checkpoint_fingerprint = try readOptionalU64(bytes, cursor);
            const applied_host_reply_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(applied_host_reply_fingerprints);
            const emitted_host_request_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(emitted_host_request_fingerprints);
            const source_capsule_fingerprint = try readOptionalU64(bytes, cursor);
            const resulting_capsule_fingerprint = try readU64(bytes, cursor);
            const archive_append_batch_fingerprint = try readOptionalU64(bytes, cursor);
            const resulting_archive_moment_fingerprint = try readOptionalU64(bytes, cursor);
            const resulting_archive_seal_fingerprint = try readOptionalU64(bytes, cursor);
            const resulting_chronicle_cursor_fingerprint = try readOptionalU64(bytes, cursor);
            const root_result_fingerprint = try readOptionalU64(bytes, cursor);
            const status = try enumFromByte(TurnStatus, try readU8(bytes, cursor));
            const run_receipt_fingerprint = try readOptionalU64(bytes, cursor);
            const blocker_count = try readUsize(bytes, cursor);
            const warning_count = try readUsize(bytes, cursor);
            return .{
                .receipt_format_version = receipt_format_version,
                .receipt_fingerprint_version = receipt_fingerprint_version,
                .receipt_fingerprint = receipt_fingerprint,
                .manifest_fingerprint = manifest_fingerprint,
                .turn_sequence_number = turn_sequence_number,
                .command_fingerprint = command_fingerprint,
                .prior_checkpoint_fingerprint = prior_checkpoint_fingerprint,
                .applied_host_reply_fingerprints = applied_host_reply_fingerprints,
                .emitted_host_request_fingerprints = emitted_host_request_fingerprints,
                .source_capsule_fingerprint = source_capsule_fingerprint,
                .resulting_capsule_fingerprint = resulting_capsule_fingerprint,
                .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                .resulting_archive_moment_fingerprint = resulting_archive_moment_fingerprint,
                .resulting_archive_seal_fingerprint = resulting_archive_seal_fingerprint,
                .resulting_chronicle_cursor_fingerprint = resulting_chronicle_cursor_fingerprint,
                .root_result_fingerprint = root_result_fingerprint,
                .status = status,
                .run_receipt_fingerprint = run_receipt_fingerprint,
                .blocker_count = blocker_count,
                .warning_count = warning_count,
                .owns_payloads = true,
            };
        }

        fn readTurnOutputOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !TurnOutput {
            const output_format_version = try readU32(bytes, cursor);
            const output_fingerprint_version = try readU32(bytes, cursor);
            const output_fingerprint = try readU64(bytes, cursor);
            const manifest_fingerprint = try readU64(bytes, cursor);
            const turn_sequence_number = try readU64(bytes, cursor);
            const source_state_fingerprint = try readU64(bytes, cursor);
            const resulting_state_fingerprint = try readU64(bytes, cursor);
            const quiescence = try readQuiescenceReport(bytes, cursor);
            const status = try enumFromByte(TurnStatus, try readU8(bytes, cursor));
            const host_requests = try readHostRequestsOwned(allocator, bytes, cursor);
            errdefer freeHostRequests(allocator, host_requests);
            const finalized_actuation_receipt_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(finalized_actuation_receipt_fingerprints);
            const root_result_fingerprint = try readOptionalU64(bytes, cursor);
            const root_result_value_image_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(root_result_value_image_bytes);
            const root_result_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const run_receipt_fingerprint = try readOptionalU64(bytes, cursor);
            const run_receipt_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(run_receipt_bytes);
            const archive_append_batch_fingerprint = try readOptionalU64(bytes, cursor);
            const archive_append_batch_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const checkpoint_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(checkpoint_bytes);
            const archive_append_batch_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(archive_append_batch_bytes);
            const checkpoint = try readCheckpointOwned(allocator, bytes, cursor);
            errdefer {
                var cleanup = checkpoint;
                freeCheckpoint(allocator, &cleanup);
            }
            const turn_receipt = try readTurnReceiptOwned(allocator, bytes, cursor);
            errdefer {
                var cleanup = turn_receipt;
                freeTurnReceipt(allocator, &cleanup);
            }
            const blocker_count = try readUsize(bytes, cursor);
            const warning_count = try readUsize(bytes, cursor);
            const diagnostic_metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(diagnostic_metadata);
            return .{
                .output_format_version = output_format_version,
                .output_fingerprint_version = output_fingerprint_version,
                .output_fingerprint = output_fingerprint,
                .manifest_fingerprint = manifest_fingerprint,
                .turn_sequence_number = turn_sequence_number,
                .source_state_fingerprint = source_state_fingerprint,
                .resulting_state_fingerprint = resulting_state_fingerprint,
                .quiescence = quiescence,
                .status = status,
                .host_requests = host_requests,
                .finalized_actuation_receipt_fingerprints = finalized_actuation_receipt_fingerprints,
                .root_result_fingerprint = root_result_fingerprint,
                .root_result_value_image_bytes = root_result_value_image_bytes,
                .root_result_value_ref_fingerprint = root_result_value_ref_fingerprint,
                .run_receipt_fingerprint = run_receipt_fingerprint,
                .run_receipt_bytes = run_receipt_bytes,
                .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                .archive_append_batch_ref_fingerprint = archive_append_batch_ref_fingerprint,
                .checkpoint_bytes = checkpoint_bytes,
                .archive_append_batch_bytes = archive_append_batch_bytes,
                .checkpoint = checkpoint,
                .turn_receipt = turn_receipt,
                .blocker_count = blocker_count,
                .warning_count = warning_count,
                .diagnostic_metadata = diagnostic_metadata,
                .owns_host_requests = true,
                .owns_finalized_actuation_receipt_fingerprints = true,
                .owns_checkpoint_payloads = true,
                .owns_turn_receipt_payloads = true,
                .owns_diagnostic_metadata = true,
                .owns_byte_payloads = true,
            };
        }

        fn readCheckpointOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Checkpoint {
            const checkpoint_format_version = try readU32(bytes, cursor);
            const checkpoint_fingerprint_version = try readU32(bytes, cursor);
            const checkpoint_fingerprint = try readU64(bytes, cursor);
            const manifest_fingerprint = try readU64(bytes, cursor);
            const turn_sequence_number = try readU64(bytes, cursor);
            const capsule_fingerprint = try readU64(bytes, cursor);
            const capsule_image_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const capsule_image_bytes = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(capsule_image_bytes);
            const latest_archive_moment_fingerprint = try readOptionalU64(bytes, cursor);
            const latest_archive_seal_fingerprint = try readOptionalU64(bytes, cursor);
            const latest_chronicle_cursor_fingerprint = try readOptionalU64(bytes, cursor);
            const pending_archive_append_batch_fingerprint = try readOptionalU64(bytes, cursor);
            const pending_archive_resulting_cursor = try readOptionalCursorOwned(allocator, bytes, cursor);
            errdefer if (pending_archive_resulting_cursor) |pending_cursor| allocator.free(pending_cursor.metadata_bytes);
            const latest_archive_cursor = try readOptionalCursorOwned(allocator, bytes, cursor);
            errdefer if (latest_archive_cursor) |latest_cursor| allocator.free(latest_cursor.metadata_bytes);
            const core_state = try enumFromByte(CoreState, try readU8(bytes, cursor));
            const previous_turn_receipt_fingerprint = try readOptionalU64(bytes, cursor);
            const outstanding_host_requests = try readHostRequestsOwned(allocator, bytes, cursor);
            errdefer freeHostRequests(allocator, outstanding_host_requests);
            const execution_mode = try enumFromByte(ExecutionMode, try readU8(bytes, cursor));
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            return .{
                .checkpoint_format_version = checkpoint_format_version,
                .checkpoint_fingerprint_version = checkpoint_fingerprint_version,
                .checkpoint_fingerprint = checkpoint_fingerprint,
                .manifest_fingerprint = manifest_fingerprint,
                .turn_sequence_number = turn_sequence_number,
                .capsule_fingerprint = capsule_fingerprint,
                .capsule_image_ref_fingerprint = capsule_image_ref_fingerprint,
                .capsule_image_bytes = capsule_image_bytes,
                .latest_archive_moment_fingerprint = latest_archive_moment_fingerprint,
                .latest_archive_seal_fingerprint = latest_archive_seal_fingerprint,
                .latest_chronicle_cursor_fingerprint = latest_chronicle_cursor_fingerprint,
                .pending_archive_append_batch_fingerprint = pending_archive_append_batch_fingerprint,
                .pending_archive_resulting_cursor = pending_archive_resulting_cursor,
                .latest_archive_cursor = latest_archive_cursor,
                .core_state = core_state,
                .previous_turn_receipt_fingerprint = previous_turn_receipt_fingerprint,
                .outstanding_host_requests = outstanding_host_requests,
                .execution_mode = execution_mode,
                .metadata = metadata,
                .owns_payloads = true,
            };
        }

        fn freeHostReplies(allocator: std.mem.Allocator, replies: []const HostReply) void {
            for (replies) |reply| {
                var cleanup = reply;
                freeHostReply(allocator, &cleanup);
            }
            allocator.free(replies);
        }

        fn freeHostRequests(allocator: std.mem.Allocator, requests: []const HostRequest) void {
            for (requests) |request| {
                var cleanup = request;
                freeHostRequest(allocator, &cleanup);
            }
            allocator.free(requests);
        }

        fn cloneHostRequestsOwned(allocator: std.mem.Allocator, requests: []const HostRequest) ![]HostRequest {
            const cloned = try allocator.alloc(HostRequest, requests.len);
            errdefer allocator.free(cloned);
            var initialized: usize = 0;
            errdefer {
                for (cloned[0..initialized]) |*request| freeHostRequest(allocator, request);
            }
            for (requests, 0..) |request, index| {
                cloned[index] = request;
                if (request.owns_metadata) {
                    cloned[index].metadata = try allocator.dupe(u8, request.metadata);
                    cloned[index].owns_metadata = true;
                } else {
                    cloned[index].owns_metadata = false;
                }
                if (request.owns_byte_payloads) {
                    cloned[index].owns_byte_payloads = false;
                    const frame_request_bytes = try allocator.dupe(u8, request.frame_request_bytes);
                    errdefer allocator.free(frame_request_bytes);
                    const payload_value_image_bytes = try allocator.dupe(u8, request.payload_value_image_bytes);
                    errdefer allocator.free(payload_value_image_bytes);
                    const prepared_actuation_evidence_bytes = try allocator.dupe(u8, request.prepared_actuation_evidence_bytes);
                    errdefer allocator.free(prepared_actuation_evidence_bytes);
                    const idempotency_key_bytes = try allocator.dupe(u8, request.idempotency_key_bytes);
                    cloned[index].frame_request_bytes = frame_request_bytes;
                    cloned[index].payload_value_image_bytes = payload_value_image_bytes;
                    cloned[index].prepared_actuation_evidence_bytes = prepared_actuation_evidence_bytes;
                    cloned[index].idempotency_key_bytes = idempotency_key_bytes;
                    cloned[index].owns_byte_payloads = true;
                } else {
                    cloned[index].owns_byte_payloads = false;
                }
                initialized += 1;
            }
            return cloned;
        }

        fn hostRequestSlicesMatch(lhs: []const HostRequest, rhs: []const HostRequest) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (left.request_fingerprint != right.request_fingerprint) return false;
            }
            return true;
        }

        fn freeHostRequest(allocator: std.mem.Allocator, request: *HostRequest) void {
            if (request.owns_metadata) allocator.free(request.metadata);
            if (request.owns_byte_payloads) {
                allocator.free(request.frame_request_bytes);
                allocator.free(request.payload_value_image_bytes);
                allocator.free(request.prepared_actuation_evidence_bytes);
                allocator.free(request.idempotency_key_bytes);
                request.owns_byte_payloads = false;
            }
        }

        fn freeHostReply(allocator: std.mem.Allocator, reply: *HostReply) void {
            if (reply.owns_payloads) {
                freeHostOutcome(allocator, &reply.outcome);
                if (reply.retention_ack) |ack| {
                    var cleanup = ack;
                    freeRetentionAck(allocator, &cleanup);
                }
                allocator.free(reply.metadata);
            }
        }

        fn freeHostOutcome(allocator: std.mem.Allocator, outcome: *HostOutcome) void {
            if (outcome.owns_payloads) {
                allocator.free(outcome.response_bytes);
                allocator.free(outcome.host_evidence_bytes);
                allocator.free(outcome.metadata);
            }
        }

        fn freeRetentionAck(allocator: std.mem.Allocator, ack: *RetentionAck) void {
            allocator.free(ack.metadata);
        }

        fn freeCheckpoint(allocator: std.mem.Allocator, checkpoint: *Checkpoint) void {
            if (!checkpoint.owns_payloads) return;
            allocator.free(checkpoint.capsule_image_bytes);
            if (checkpoint.pending_archive_resulting_cursor) |cursor| allocator.free(cursor.metadata_bytes);
            if (checkpoint.latest_archive_cursor) |cursor| allocator.free(cursor.metadata_bytes);
            freeHostRequests(allocator, checkpoint.outstanding_host_requests);
            allocator.free(checkpoint.metadata);
            checkpoint.owns_payloads = false;
        }

        fn freeTurnReceipt(allocator: std.mem.Allocator, receipt: *TurnReceipt) void {
            if (!receipt.owns_payloads) return;
            allocator.free(receipt.applied_host_reply_fingerprints);
            allocator.free(receipt.emitted_host_request_fingerprints);
            receipt.owns_payloads = false;
        }

        fn freeTurnOutput(allocator: std.mem.Allocator, output: *TurnOutput) void {
            if (output.owns_host_requests) freeHostRequests(allocator, output.host_requests);
            if (output.owns_finalized_actuation_receipt_fingerprints) allocator.free(output.finalized_actuation_receipt_fingerprints);
            if (output.owns_checkpoint_payloads) freeCheckpoint(allocator, &output.checkpoint);
            if (output.owns_turn_receipt_payloads) freeTurnReceipt(allocator, &output.turn_receipt);
            if (output.owns_diagnostic_metadata) allocator.free(output.diagnostic_metadata);
            if (output.owns_byte_payloads) {
                allocator.free(output.root_result_value_image_bytes);
                allocator.free(output.run_receipt_bytes);
                allocator.free(output.checkpoint_bytes);
                allocator.free(output.archive_append_batch_bytes);
                output.owns_byte_payloads = false;
            }
        }

        fn fingerprintCoreHostIntent(manifest_fingerprint: u64, command_fingerprint: u64, binding_fingerprint: u64, turn_sequence_number: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.host_intent.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command_fingerprint);
            hashU64(&hasher, binding_fingerprint);
            hashU64(&hasher, turn_sequence_number);
            return nonzero(hasher.final());
        }

        fn fingerprintCoreHostEnvelope(intent_fingerprint: u64, capsule_fingerprint: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.host_envelope.fingerprint");
            hashU64(&hasher, intent_fingerprint);
            hashU64(&hasher, capsule_fingerprint);
            return nonzero(hasher.final());
        }

        fn fingerprintCoreHostIdempotencyKey(manifest_fingerprint: u64, command_fingerprint: u64, binding_fingerprint: u64, turn_sequence_number: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.host_idempotency_key.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command_fingerprint);
            hashU64(&hasher, binding_fingerprint);
            hashU64(&hasher, turn_sequence_number);
            return nonzero(hasher.final());
        }

        fn fingerprintCoreHostDecision(intent_fingerprint: u64, descriptor_fingerprint: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.host_decision.fingerprint");
            hashU64(&hasher, intent_fingerprint);
            hashU64(&hasher, descriptor_fingerprint);
            return nonzero(hasher.final());
        }

        fn fingerprintCoreArchiveAppend(manifest_fingerprint: u64, command: Command, capsule_fingerprint: u64, status: TurnStatus) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.archive_append.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command.command_fingerprint);
            hashU64(&hasher, capsule_fingerprint);
            hashU64(&hasher, @intFromEnum(status));
            return nonzero(hasher.final());
        }

        fn fingerprintCoreRootResult(manifest_fingerprint: u64, command: Command, capsule_fingerprint: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.root_result.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command.command_fingerprint);
            hashU64(&hasher, capsule_fingerprint);
            return nonzero(hasher.final());
        }

        fn defaultCapsuleImageRef(capsule_fingerprint: u64) ?u64 {
            if (capsule_fingerprint == 0) return null;
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.checkpoint.capsule_image_ref.fingerprint");
            hashU64(&hasher, capsule_fingerprint);
            return nonzero(hasher.final());
        }

        fn defaultArchiveAppendBatchRef(archive_append_batch_fingerprint: ?u64) ?u64 {
            const actual = archive_append_batch_fingerprint orelse return null;
            if (actual == 0) return null;
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.turn_output.archive_append_batch_ref.fingerprint");
            hashU64(&hasher, actual);
            return nonzero(hasher.final());
        }

        fn validateArchiveAnchorTuple(moment_fingerprint: ?u64, seal_fingerprint: ?u64, cursor_fingerprint: ?u64) !void {
            var archive_anchor_count: usize = 0;
            if (moment_fingerprint != null) archive_anchor_count += 1;
            if (seal_fingerprint != null) archive_anchor_count += 1;
            if (cursor_fingerprint != null) archive_anchor_count += 1;
            if (archive_anchor_count != 0 and archive_anchor_count != 3) return error.InvalidFrameEncoding;
        }

        fn encodeCheckpointOwned(allocator: std.mem.Allocator, checkpoint: Checkpoint) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try checkpoint.encode(&out, allocator);
            return out.toOwnedSlice(allocator);
        }

        fn encodeTurnReceiptOwned(allocator: std.mem.Allocator, receipt: TurnReceipt) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try receipt.encode(&out, allocator);
            return out.toOwnedSlice(allocator);
        }

        fn encodeFingerprintImageOwned(allocator: std.mem.Allocator, label: []const u8, fingerprint: u64) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeBytes(&out, allocator, label);
            try writeU64(&out, allocator, fingerprint);
            return out.toOwnedSlice(allocator);
        }

        fn encodeHostFrameRequestOwned(allocator: std.mem.Allocator, args: anytype) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeBytes(&out, allocator, "world.appliance.frame_request.v1");
            try writeU64(&out, allocator, args.manifest_fingerprint);
            try writeU64(&out, allocator, args.command_fingerprint);
            try writeU64(&out, allocator, args.turn_sequence_number);
            try writeU64(&out, allocator, args.request_ordinal);
            try writeU32(&out, allocator, args.world_port_id);
            try writeU64(&out, allocator, args.binding_fingerprint);
            try writeU64(&out, allocator, args.descriptor_fingerprint);
            try writeU64(&out, allocator, args.intent_fingerprint);
            try writeU64(&out, allocator, args.envelope_fingerprint);
            return out.toOwnedSlice(allocator);
        }

        fn encodeHostPayloadValueImageOwned(allocator: std.mem.Allocator, command: Command, binding_fingerprint: u64, world_port_id: u32) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeBytes(&out, allocator, "world.appliance.payload_value_image.v1");
            try writeU64(&out, allocator, command.command_fingerprint);
            try writeU64(&out, allocator, binding_fingerprint);
            try writeU32(&out, allocator, world_port_id);
            try writeBytes(&out, allocator, command.root_argument_image);
            return out.toOwnedSlice(allocator);
        }

        fn encodePreparedActuationEvidenceOwned(allocator: std.mem.Allocator, args: anytype) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeBytes(&out, allocator, "world.appliance.prepared_actuation.v1");
            try writeU64(&out, allocator, args.descriptor_fingerprint);
            try writeU64(&out, allocator, args.binding_fingerprint);
            try writeU64(&out, allocator, args.actuator_ref_fingerprint);
            try writeU32(&out, allocator, args.world_port_id);
            try writeU64(&out, allocator, args.decision_fingerprint);
            return out.toOwnedSlice(allocator);
        }

        fn encodeIdempotencyKeyImageOwned(allocator: std.mem.Allocator, args: anytype) ![]const u8 {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeBytes(&out, allocator, "world.appliance.idempotency_key.v1");
            try writeU64(&out, allocator, args.manifest_fingerprint);
            try writeU64(&out, allocator, args.command_fingerprint);
            try writeU64(&out, allocator, args.binding_fingerprint);
            try writeU64(&out, allocator, args.turn_sequence_number);
            try writeU64(&out, allocator, args.idempotency_key_fingerprint);
            return out.toOwnedSlice(allocator);
        }

        fn encodeArchiveAppendBatchFingerprintOwned(allocator: std.mem.Allocator, append_batch_fingerprint: u64) ![]const u8 {
            return encodeFingerprintImageOwned(allocator, "world.appliance.archive_append_batch.ref", append_batch_fingerprint);
        }

        fn capacityFromExecutableMemoryPlan(plan: World.Executable.MemoryPlan, profile: Profile) Capacity {
            var capacity = switch (profile.kind) {
                .minimal, .wasm_small => Capacity.wasm_small,
                .wasm_agent, .native_debug, .replay_only, .full_evidence => Capacity.wasm_agent,
            };
            capacity.max_provider_runs = @max(capacity.max_provider_runs, plan.max_provider_runs);
            capacity.max_pending_ports = @max(capacity.max_pending_ports, plan.max_mailbox_entries);
            capacity.max_host_requests_per_turn = @max(capacity.max_host_requests_per_turn, plan.max_host_requests_per_turn);
            capacity.max_host_replies_per_turn = @max(capacity.max_host_replies_per_turn, plan.max_host_requests_per_turn);
            capacity.max_capsule_bytes = @max(capacity.max_capsule_bytes, plan.max_capsule_bytes);
            capacity.max_archive_append_bytes = @max(capacity.max_archive_append_bytes, plan.max_archive_append_bytes);
            capacity.max_command_bytes = @max(capacity.max_command_bytes, plan.max_command_bytes);
            capacity.max_output_bytes = @max(capacity.max_output_bytes, plan.max_output_bytes);
            return capacity;
        }

        fn manifestFromExecutableImage(
            allocator: std.mem.Allocator,
            image: World.Executable.Image,
            profile: Profile,
            capacity: Capacity,
            metadata: []const u8,
        ) !Manifest {
            const root = image.module_set.root() orelse return error.ExecutableLoadRejected;
            const provider_count = blk: {
                var count: usize = 0;
                for (image.module_set.modules) |module| {
                    if (module.role == .provider) count += 1;
                }
                break :blk count;
            };
            const provider_target_ref_fingerprints = try allocator.alloc(u64, provider_count);
            errdefer allocator.free(provider_target_ref_fingerprints);
            var provider_index: usize = 0;
            for (image.module_set.modules) |module| {
                if (module.role != .provider) continue;
                provider_target_ref_fingerprints[provider_index] = module.target_ref.target_ref_fingerprint;
                provider_index += 1;
            }

            const fabric_plan_fingerprints = try allocator.dupe(u64, image.dispatch_image.fabric_plan_fingerprints);
            errdefer allocator.free(fabric_plan_fingerprints);
            const binding_count = image.external_bindings.len;
            const descriptor_fingerprints = try allocator.alloc(u64, binding_count);
            errdefer allocator.free(descriptor_fingerprints);
            const binding_fingerprints = try allocator.alloc(u64, binding_count);
            errdefer allocator.free(binding_fingerprints);
            const actuator_ref_fingerprints = try allocator.alloc(u64, binding_count);
            errdefer allocator.free(actuator_ref_fingerprints);
            const world_port_ids = try allocator.alloc(u64, binding_count);
            errdefer allocator.free(world_port_ids);
            const classes = try allocator.alloc(World.Actuation.Class, binding_count);
            errdefer allocator.free(classes);
            const statuses = try allocator.alloc(World.Actuation.ResponseStatusSet, binding_count);
            errdefer allocator.free(statuses);
            for (image.external_bindings, 0..) |binding, index| {
                try binding.validate();
                descriptor_fingerprints[index] = binding.descriptor.descriptor_fingerprint;
                binding_fingerprints[index] = binding.binding_fingerprint;
                actuator_ref_fingerprints[index] = binding.actuator_ref.ref_fingerprint;
                world_port_ids[index] = binding.world_port_id;
                classes[index] = binding.actuation_class;
                statuses[index] = binding.allowed_response_statuses;
            }
            const metadata_owned = try allocator.dupe(u8, metadata);
            errdefer allocator.free(metadata_owned);
            var manifest = Manifest.init(.{
                .root_target_ref_fingerprint = root.target_ref.target_ref_fingerprint,
                .root_world_surface_fingerprint = root.target_ref.world_surface_fingerprint,
                .root_target_certificate_fingerprint = root.target_ref.target_certificate_fingerprint,
                .link_plan_fingerprint = image.link_plan_fingerprint,
                .link_certificate_fingerprint = image.linker_certificate_fingerprint,
                .assembly_fingerprint = image.assembly_fingerprint,
                .provider_target_ref_fingerprints = provider_target_ref_fingerprints,
                .fabric_plan_fingerprints = fabric_plan_fingerprints,
                .residual_import_set_fingerprint = image.dispatch_image.dispatch_fingerprint,
                .actuation_descriptor_fingerprints = descriptor_fingerprints,
                .actuation_binding_fingerprints = binding_fingerprints,
                .actuation_actuator_ref_fingerprints = actuator_ref_fingerprints,
                .actuation_world_port_ids = world_port_ids,
                .actuation_classes = classes,
                .actuation_allowed_response_statuses = statuses,
                .supported_execution_modes = ExecutionModeSet.forManifest(profile, binding_count),
                .enabled_features = FeatureSet.fromProfile(profile),
                .capacity_fingerprint = capacity.fingerprint(),
                .memory_plan_fingerprint = MemoryPlan.derive(capacity, profile).plan_fingerprint,
                .required_host_capabilities = HostCapabilityFlags.forManifest(profile, binding_count),
                .metadata = metadata_owned,
            });
            manifest.owns_payloads = true;
            try manifest.validate();
            return manifest;
        }

        fn cloneEnvelope(
            allocator: std.mem.Allocator,
            envelope: World.Continuity.ObjectEnvelope,
        ) !World.Continuity.ObjectEnvelope {
            try envelope.validate();
            return envelope.clone(allocator);
        }

        fn archiveNeutralTurnOutput(output: TurnOutput) TurnOutput {
            const neutral_receipt = TurnReceipt.init(.{
                .manifest_fingerprint = output.turn_receipt.manifest_fingerprint,
                .turn_sequence_number = output.turn_receipt.turn_sequence_number,
                .command_fingerprint = output.turn_receipt.command_fingerprint,
                .prior_checkpoint_fingerprint = output.turn_receipt.prior_checkpoint_fingerprint,
                .applied_host_reply_fingerprints = output.turn_receipt.applied_host_reply_fingerprints,
                .emitted_host_request_fingerprints = output.turn_receipt.emitted_host_request_fingerprints,
                .source_capsule_fingerprint = output.turn_receipt.source_capsule_fingerprint,
                .resulting_capsule_fingerprint = output.turn_receipt.resulting_capsule_fingerprint,
                .archive_append_batch_fingerprint = null,
                .resulting_archive_moment_fingerprint = output.turn_receipt.resulting_archive_moment_fingerprint,
                .resulting_archive_seal_fingerprint = output.turn_receipt.resulting_archive_seal_fingerprint,
                .resulting_chronicle_cursor_fingerprint = output.turn_receipt.resulting_chronicle_cursor_fingerprint,
                .root_result_fingerprint = output.turn_receipt.root_result_fingerprint,
                .status = output.turn_receipt.status,
                .run_receipt_fingerprint = output.turn_receipt.run_receipt_fingerprint,
                .blocker_count = output.turn_receipt.blocker_count,
                .warning_count = output.turn_receipt.warning_count,
            });
            const neutral_pending_append = if (output.checkpoint.pending_archive_append_batch_fingerprint != output.archive_append_batch_fingerprint)
                output.checkpoint.pending_archive_append_batch_fingerprint
            else
                null;
            const neutral_pending_cursor = if (neutral_pending_append != null)
                output.checkpoint.pending_archive_resulting_cursor
            else
                null;
            const neutral_checkpoint = Checkpoint.init(.{
                .manifest_fingerprint = output.checkpoint.manifest_fingerprint,
                .turn_sequence_number = output.checkpoint.turn_sequence_number,
                .capsule_fingerprint = output.checkpoint.capsule_fingerprint,
                .capsule_image_ref_fingerprint = output.checkpoint.capsule_image_ref_fingerprint,
                .capsule_image_bytes = output.checkpoint.capsule_image_bytes,
                .latest_archive_moment_fingerprint = output.checkpoint.latest_archive_moment_fingerprint,
                .latest_archive_seal_fingerprint = output.checkpoint.latest_archive_seal_fingerprint,
                .latest_chronicle_cursor_fingerprint = output.checkpoint.latest_chronicle_cursor_fingerprint,
                .pending_archive_append_batch_fingerprint = neutral_pending_append,
                .pending_archive_resulting_cursor = neutral_pending_cursor,
                .latest_archive_cursor = output.checkpoint.latest_archive_cursor,
                .core_state = output.checkpoint.core_state,
                .previous_turn_receipt_fingerprint = if (output.checkpoint.previous_turn_receipt_fingerprint == output.turn_receipt.receipt_fingerprint)
                    neutral_receipt.receipt_fingerprint
                else
                    output.checkpoint.previous_turn_receipt_fingerprint,
                .outstanding_host_requests = output.checkpoint.outstanding_host_requests,
                .execution_mode = output.checkpoint.execution_mode,
                .metadata = output.checkpoint.metadata,
            });
            const neutral_resulting_state_fingerprint = if (output.status == .inspected)
                output.source_state_fingerprint
            else if (neutral_checkpoint.core_state == .uninitialized)
                stateFingerprintFor(.uninitialized, 0, null)
            else
                stateFingerprintFor(neutral_checkpoint.core_state, output.turn_sequence_number, neutral_receipt.receipt_fingerprint);
            return TurnOutput.init(.{
                .manifest_fingerprint = output.manifest_fingerprint,
                .turn_sequence_number = output.turn_sequence_number,
                .source_state_fingerprint = output.source_state_fingerprint,
                .resulting_state_fingerprint = neutral_resulting_state_fingerprint,
                .quiescence = output.quiescence,
                .status = output.status,
                .host_requests = output.host_requests,
                .finalized_actuation_receipt_fingerprints = output.finalized_actuation_receipt_fingerprints,
                .root_result_fingerprint = output.root_result_fingerprint,
                .run_receipt_fingerprint = output.run_receipt_fingerprint,
                .archive_append_batch_fingerprint = null,
                .checkpoint = neutral_checkpoint,
                .turn_receipt = neutral_receipt,
                .blocker_count = output.blocker_count,
                .warning_count = output.warning_count,
                .diagnostic_metadata = output.diagnostic_metadata,
            });
        }

        fn fingerprintArchiveTransaction(
            parent_cursor: World.Continuity.Chronicle.Cursor,
            output: TurnOutput,
            refs: []const World.Continuity.ObjectRef,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.archive_transaction.fingerprint");
            hashU64(&hasher, parent_cursor.cursor_fingerprint);
            hashU64(&hasher, output.output_fingerprint);
            for (refs) |ref| hashU64(&hasher, ref.ref_fingerprint);
            return nonzero(hasher.final());
        }

        fn fingerprintRetentionAck(ack: RetentionAck) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.retention_ack.fingerprint");
            hashU64(&hasher, ack.append_batch_fingerprint);
            hashU64(&hasher, ack.resulting_moment_fingerprint);
            hashU64(&hasher, ack.resulting_seal_fingerprint);
            hashU64(&hasher, ack.resulting_chronicle_cursor_fingerprint);
            hashU64(&hasher, @intFromEnum(ack.host_claim_status));
            hashBytes(&hasher, ack.metadata);
            return nonzero(hasher.final());
        }

        fn fingerprintReconstructionReport(report: ReconstructionReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.reconstruction_report.fingerprint");
            hashU64(&hasher, World.world_appliance_reconstruction_report_fingerprint_version);
            hashU64(&hasher, report.manifest_fingerprint);
            hashU64(&hasher, report.resident_turn_output_fingerprint);
            hashU64(&hasher, report.reconstructed_turn_output_fingerprint);
            hashBool(&hasher, report.equivalent);
            hashU64(&hasher, report.mismatch_count);
            return nonzero(hasher.final());
        }

        fn fingerprintConformanceVector(vector: ConformanceVector) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.conformance_vector.fingerprint");
            hashU64(&hasher, vector.vector_fingerprint_version);
            hashU64(&hasher, @intFromEnum(vector.kind));
            hashBytes(&hasher, vector.name);
            hashU64(&hasher, vector.manifest_fingerprint);
            hashU64(&hasher, vector.initial_command_fingerprint);
            hashOptionalU64(&hasher, vector.expected_turn_output_fingerprint);
            hashU64Slice(&hasher, vector.host_reply_sequence_fingerprints);
            hashTurnStatusSlice(&hasher, vector.expected_status_sequence);
            hashU64(&hasher, vector.expected_status_fingerprint);
            hashU64Slice(&hasher, vector.expected_host_request_fingerprints);
            hashU64Slice(&hasher, vector.expected_checkpoint_fingerprints);
            hashOptionalU64(&hasher, vector.expected_archive_append_fingerprint);
            hashU64Slice(&hasher, vector.expected_archive_append_fingerprints);
            hashOptionalU64(&hasher, vector.expected_final_result_fingerprint);
            hashBool(&hasher, vector.expected_resident_reconstructed_equivalence);
            return nonzero(hasher.final());
        }

        fn fingerprintConformanceTrace(report: ConformanceReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.conformance_trace.fingerprint");
            hashU64(&hasher, report.manifest_fingerprint);
            hashOptionalU64(&hasher, report.direct_native_owner_output_fingerprint);
            hashOptionalU64(&hasher, report.appliance_native_output_fingerprint);
            hashU64(&hasher, report.native_core_output_fingerprint);
            hashU64(&hasher, report.resident_core_output_fingerprint);
            hashU64(&hasher, report.reconstructed_core_output_fingerprint);
            hashOptionalU64(&hasher, report.wasm_manifest_fingerprint);
            hashBool(&hasher, report.wasm_required_exports_present);
            hashU64(&hasher, report.wasm_forbidden_import_count);
            hashBool(&hasher, report.wasm_inspection_passed);
            hashOptionalU64(&hasher, report.external_runtime_output_fingerprint);
            hashOptionalU64(&hasher, report.replay_output_fingerprint);
            hashOptionalU64(&hasher, report.archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, report.archive_replay_projection_fingerprint);
            return nonzero(hasher.final());
        }

        fn fingerprintConformanceReport(report: ConformanceReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.conformance_report.fingerprint");
            hashU64(&hasher, report.report_fingerprint_version);
            hashU64(&hasher, report.vector_fingerprint);
            hashU64(&hasher, report.manifest_fingerprint);
            hashOptionalU64(&hasher, report.direct_native_owner_output_fingerprint);
            hashOptionalU64(&hasher, report.appliance_native_output_fingerprint);
            hashU64(&hasher, report.native_core_output_fingerprint);
            hashU64(&hasher, report.resident_core_output_fingerprint);
            hashU64(&hasher, report.reconstructed_core_output_fingerprint);
            hashOptionalU64(&hasher, report.wasm_manifest_fingerprint);
            hashBool(&hasher, report.wasm_required_exports_present);
            hashU64(&hasher, report.wasm_forbidden_import_count);
            hashBool(&hasher, report.wasm_inspection_passed);
            hashOptionalU64(&hasher, report.external_runtime_output_fingerprint);
            hashOptionalU64(&hasher, report.replay_output_fingerprint);
            hashOptionalU64(&hasher, report.archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, report.archive_replay_projection_fingerprint);
            hashU64(&hasher, report.equivalence_trace_digest);
            hashBool(&hasher, report.passed);
            return nonzero(hasher.final());
        }

        fn fingerprintCoreCapsule(manifest_fingerprint: u64, command: Command, status: TurnStatus) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.capsule.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command.command_fingerprint);
            hashU64(&hasher, @intFromEnum(status));
            return nonzero(hasher.final());
        }

        fn stateFingerprintFor(state: CoreState, turn_sequence_number: u64, previous_turn_receipt_fingerprint: ?u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_state.fingerprint");
            hashU64(&hasher, @intFromEnum(state));
            hashU64(&hasher, turn_sequence_number);
            hashOptionalU64(&hasher, previous_turn_receipt_fingerprint);
            return nonzero(hasher.final());
        }

        fn stateForStatus(status: TurnStatus) CoreState {
            return switch (status) {
                .needs_host => .waiting_host,
                .completed, .inspected => .completed,
                .failed, .blocked => .failed,
                .cancelled => .cancelled,
            };
        }

        fn optionalCursorMatches(a: ?World.Continuity.Chronicle.Cursor, b: ?World.Continuity.Chronicle.Cursor) bool {
            if (a == null or b == null) return a == null and b == null;
            return a.?.cursor_fingerprint == b.?.cursor_fingerprint;
        }

        fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
            hashU64(hasher, values.len);
            for (values) |value| hashU64(hasher, value);
        }

        fn hashTurnStatusSlice(hasher: *std.hash.Wyhash, values: []const TurnStatus) void {
            hashU64(hasher, values.len);
            for (values) |value| hashU64(hasher, @intFromEnum(value));
        }

        fn validateOptionalFingerprint(value: ?u64) !void {
            if (value != null and value.? == 0) return error.InvalidFrameEncoding;
        }

        fn validateFingerprintSlice(values: []const u64) !void {
            for (values) |value| {
                if (value == 0) return error.InvalidFrameEncoding;
            }
        }

        fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
            hashU64(hasher, bytes.len);
            hasher.update(bytes);
        }

        fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
            hashU64(hasher, @intFromBool(value));
        }

        fn hashActuationClassSlice(hasher: *std.hash.Wyhash, values: []const World.Actuation.Class) void {
            hashU64(hasher, values.len);
            for (values) |value| hashU64(hasher, @intFromEnum(value));
        }

        fn hashResponseStatusSet(hasher: *std.hash.Wyhash, value: World.Actuation.ResponseStatusSet) void {
            hashU64(hasher, responseStatusSetByte(value));
        }

        fn hashResponseStatusSetSlice(hasher: *std.hash.Wyhash, values: []const World.Actuation.ResponseStatusSet) void {
            hashU64(hasher, values.len);
            for (values) |value| hashResponseStatusSet(hasher, value);
        }

        fn responseStatusSetAllowsAny(value: World.Actuation.ResponseStatusSet) bool {
            return value.responded or value.rejected or value.failed or value.pending or value.deferred or value.cancelled;
        }

        fn responseStatusSetByte(value: World.Actuation.ResponseStatusSet) u8 {
            return (@as(u8, @intFromBool(value.responded)) << 0) |
                (@as(u8, @intFromBool(value.rejected)) << 1) |
                (@as(u8, @intFromBool(value.failed)) << 2) |
                (@as(u8, @intFromBool(value.pending)) << 3) |
                (@as(u8, @intFromBool(value.deferred)) << 4) |
                (@as(u8, @intFromBool(value.cancelled)) << 5);
        }

        fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
            if (value) |actual| {
                hashBool(hasher, true);
                hashU64(hasher, actual);
            } else {
                hashBool(hasher, false);
            }
        }

        fn hashU64(hasher: *std.hash.Wyhash, value: anytype) void {
            const casted: u64 = @intCast(value);
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, casted, .little);
            hasher.update(&bytes);
        }

        fn writeU8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
            try out.append(allocator, value);
        }

        fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, value, .little);
            try out.appendSlice(allocator, &bytes);
        }

        fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, value, .little);
            try out.appendSlice(allocator, &bytes);
        }

        fn writeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u64) !void {
            if (value) |actual| {
                try writeU8(out, allocator, 1);
                try writeU64(out, allocator, actual);
            } else {
                try writeU8(out, allocator, 0);
            }
        }

        fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
            if (bytes.len > std.math.maxInt(u32)) return error.CapacityExceeded;
            try writeU32(out, allocator, @intCast(bytes.len));
            try out.appendSlice(allocator, bytes);
        }

        fn readU8(bytes: []const u8, cursor: *usize) !u8 {
            if (cursor.* > bytes.len or 1 > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const value = bytes[cursor.*];
            cursor.* += 1;
            return value;
        }

        fn readU16(bytes: []const u8, cursor: *usize) !u16 {
            if (cursor.* > bytes.len or 2 > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const value = std.mem.readInt(u16, bytes[cursor.*..][0..2], .little);
            cursor.* += 2;
            return value;
        }

        fn readU32(bytes: []const u8, cursor: *usize) !u32 {
            if (cursor.* > bytes.len or 4 > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const value = std.mem.readInt(u32, bytes[cursor.*..][0..4], .little);
            cursor.* += 4;
            return value;
        }

        fn readU64(bytes: []const u8, cursor: *usize) !u64 {
            if (cursor.* > bytes.len or 8 > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const value = std.mem.readInt(u64, bytes[cursor.*..][0..8], .little);
            cursor.* += 8;
            return value;
        }

        fn readBool(bytes: []const u8, cursor: *usize) !bool {
            return switch (try readU8(bytes, cursor)) {
                0 => false,
                1 => true,
                else => error.InvalidFrameEncoding,
            };
        }

        fn readResponseStatusSet(bytes: []const u8, cursor: *usize) !World.Actuation.ResponseStatusSet {
            const bits = try readU8(bytes, cursor);
            if (bits & 0b1100_0000 != 0) return error.InvalidFrameEncoding;
            return .{
                .responded = bits & (1 << 0) != 0,
                .rejected = bits & (1 << 1) != 0,
                .failed = bits & (1 << 2) != 0,
                .pending = bits & (1 << 3) != 0,
                .deferred = bits & (1 << 4) != 0,
                .cancelled = bits & (1 << 5) != 0,
            };
        }

        fn readUsize(bytes: []const u8, cursor: *usize) !usize {
            const value = try readU64(bytes, cursor);
            if (value > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            return @intCast(value);
        }

        fn readOptionalU64(bytes: []const u8, cursor: *usize) !?u64 {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readU64(bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]const u8 {
            const len = try readU32(bytes, cursor);
            if (len > World.world_max_decoded_byte_field_len) return error.InvalidFrameEncoding;
            if (cursor.* > bytes.len or len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
            const result = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + len]);
            cursor.* += len;
            return result;
        }

        fn enumFromByte(comptime T: type, value: u8) !T {
            inline for (std.meta.fields(T)) |field| {
                if (field.value == value) return @enumFromInt(value);
            }
            return error.InvalidFrameEncoding;
        }

        fn nonzero(value: u64) u64 {
            return if (value == 0) 1 else value;
        }
    };
}
