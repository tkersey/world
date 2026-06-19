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

            pub fn init(args: @This()) @This() {
                return args;
            }

            pub fn validate(self: @This()) !void {
                if (self.max_runs == 0) return error.CapacityExceeded;
                if (self.max_provider_runs > self.max_runs) return error.CapacityExceeded;
                if (self.max_host_requests_per_turn > self.max_pending_ports) return error.CapacityExceeded;
                if (self.max_host_replies_per_turn > self.max_pending_ports) return error.CapacityExceeded;
                if (self.max_command_bytes == 0 or self.max_output_bytes == 0 or self.max_error_bytes == 0) return error.CapacityExceeded;
                if (self.max_metadata_bytes > World.world_max_decoded_byte_field_len) return error.CapacityExceeded;
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
                const persistent = alignBytes(1024 + capacity.max_runs * 256 + capacity.max_pending_ports * 192 + capacity.max_actuation_records * 128);
                const scratch = alignBytes(2048 + capacity.max_runspace_events * 32 + capacity.max_fabric_invocations * 64);
                const checkpoint = alignBytes(capacity.max_capsule_bytes);
                const archive = alignBytes(capacity.max_archive_append_bytes);
                const input = alignBytes(capacity.max_command_bytes);
                const output = alignBytes(capacity.max_output_bytes);
                const maximum = alignPage(persistent + scratch + input + output + checkpoint + archive + capacity.max_error_bytes + capacity.max_metadata_bytes);
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
                if (self.actuation_descriptor_fingerprints.len != self.actuation_binding_fingerprints.len) return error.InvalidFrameEncoding;
                for (self.actuation_descriptor_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
                }
                for (self.actuation_binding_fingerprints) |fingerprint| {
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

            pub fn writeCanonicalBytes(self: @This(), dest: []u8) !usize {
                try self.validate();
                return writeManifestCanonicalBytes(self, dest);
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
                for (self.host_replies) |reply| {
                    try reply.validateShape(capacity);
                }
                try validateDistinctHostReplyTargets(self.host_replies);
                if (self.retention_ack) |ack| try ack.validate(null, capacity);
                if (self.restore_checkpoint) |checkpoint| {
                    if (self.kind != .restore) return error.InvalidFrameEncoding;
                    try checkpoint.validate(expected_manifest_fingerprint, capacity);
                } else if (self.kind == .restore) {
                    return error.RestoreRejected;
                }
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
            intent_fingerprint: u64,
            envelope_fingerprint: u64,
            decision_fingerprint: u64,
            expected_response_descriptor_fingerprint: u64,
            idempotency_key_fingerprint: u64,
            supervision_ref_fingerprint: ?u64 = null,
            metadata: []const u8 = "",

            pub fn init(args: struct {
                turn_sequence_number: u64,
                request_ordinal: u32,
                run_handle_fingerprint: u64,
                pending_port_fingerprint: u64,
                world_port_id: u32,
                intent_fingerprint: u64,
                envelope_fingerprint: u64,
                decision_fingerprint: u64,
                expected_response_descriptor_fingerprint: u64,
                idempotency_key_fingerprint: u64,
                supervision_ref_fingerprint: ?u64 = null,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .turn_sequence_number = args.turn_sequence_number,
                    .request_ordinal = args.request_ordinal,
                    .run_handle_fingerprint = args.run_handle_fingerprint,
                    .pending_port_fingerprint = args.pending_port_fingerprint,
                    .world_port_id = args.world_port_id,
                    .intent_fingerprint = args.intent_fingerprint,
                    .envelope_fingerprint = args.envelope_fingerprint,
                    .decision_fingerprint = args.decision_fingerprint,
                    .expected_response_descriptor_fingerprint = args.expected_response_descriptor_fingerprint,
                    .idempotency_key_fingerprint = args.idempotency_key_fingerprint,
                    .supervision_ref_fingerprint = args.supervision_ref_fingerprint,
                    .metadata = args.metadata,
                };
                result.request_fingerprint = fingerprintHostRequest(result);
                return result;
            }

            pub fn validate(self: @This(), capacity: Capacity) !void {
                if (self.request_format_version != World.world_appliance_host_request_format_version) return error.InvalidFrameEncoding;
                if (self.request_fingerprint_version != World.world_appliance_host_request_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.request_ordinal >= capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                if (self.run_handle_fingerprint == 0 or self.pending_port_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.intent_fingerprint == 0 or self.envelope_fingerprint == 0 or self.decision_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.expected_response_descriptor_fingerprint == 0 or self.idempotency_key_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.supervision_ref_fingerprint);
                if (self.metadata.len > capacity.max_metadata_bytes) return error.CapacityExceeded;
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
                try writeU64(out, allocator, self.intent_fingerprint);
                try writeU64(out, allocator, self.envelope_fingerprint);
                try writeU64(out, allocator, self.decision_fingerprint);
                try writeU64(out, allocator, self.expected_response_descriptor_fingerprint);
                try writeU64(out, allocator, self.idempotency_key_fingerprint);
                try writeOptionalU64(out, allocator, self.supervision_ref_fingerprint);
                try writeBytes(out, allocator, self.metadata);
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
                    if (self.latest_chronicle_cursor_fingerprint) |fingerprint| {
                        if (cursor.cursor_fingerprint != fingerprint) return error.InvalidFrameEncoding;
                    }
                }
                if (self.latest_chronicle_cursor_fingerprint != null and self.latest_archive_cursor == null) return error.InvalidFrameEncoding;
                if (self.outstanding_host_requests.len != 0 and self.core_state != .waiting_host) return error.InvalidFrameEncoding;
                if (self.core_state == .waiting_host and self.outstanding_host_requests.len == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.previous_turn_receipt_fingerprint);
                if (self.outstanding_host_requests.len > capacity.max_pending_ports) return error.CapacityExceeded;
                for (self.outstanding_host_requests, 0..) |request, index| {
                    try request.validate(capacity);
                    if (request.turn_sequence_number > self.turn_sequence_number) return error.InvalidFrameEncoding;
                    if (request.request_ordinal != index) return error.InvalidFrameEncoding;
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
                try checkpoint.validate(checkpoint.manifest_fingerprint, Capacity.large_native_test);
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
                try validateOptionalFingerprint(self.archive_append_batch_fingerprint);
                try validateOptionalFingerprint(self.resulting_archive_moment_fingerprint);
                try validateOptionalFingerprint(self.resulting_archive_seal_fingerprint);
                try validateOptionalFingerprint(self.resulting_chronicle_cursor_fingerprint);
                try validateArchiveAnchorTuple(self.resulting_archive_moment_fingerprint, self.resulting_archive_seal_fingerprint, self.resulting_chronicle_cursor_fingerprint);
                try validateOptionalFingerprint(self.root_result_fingerprint);
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
                try receipt.validate(receipt.manifest_fingerprint, Capacity.large_native_test);
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
            run_receipt_fingerprint: ?u64 = null,
            archive_append_batch_fingerprint: ?u64 = null,
            archive_append_batch_ref_fingerprint: ?u64 = null,
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
                run_receipt_fingerprint: ?u64 = null,
                archive_append_batch_fingerprint: ?u64 = null,
                archive_append_batch_ref_fingerprint: ?u64 = null,
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
                    .run_receipt_fingerprint = args.run_receipt_fingerprint,
                    .archive_append_batch_fingerprint = args.archive_append_batch_fingerprint,
                    .archive_append_batch_ref_fingerprint = args.archive_append_batch_ref_fingerprint orelse defaultArchiveAppendBatchRef(args.archive_append_batch_fingerprint),
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
                if (self.manifest_fingerprint != expected_manifest_fingerprint) return error.WrongManifest;
                if (self.source_state_fingerprint == 0 or self.resulting_state_fingerprint == 0) return error.InvalidFrameEncoding;
                try validateOptionalFingerprint(self.root_result_fingerprint);
                try self.quiescence.validate();
                if (self.host_requests.len > capacity.max_host_requests_per_turn) return error.CapacityExceeded;
                if (self.status == .needs_host and self.host_requests.len == 0) return error.InvalidFrameEncoding;
                if (self.status != .needs_host and self.host_requests.len != 0) return error.InvalidFrameEncoding;
                if (self.quiescence.pending_host_request_count != self.checkpoint.outstanding_host_requests.len) return error.InvalidFrameEncoding;
                if (self.quiescence.prepared_actuation_count != self.host_requests.len) return error.InvalidFrameEncoding;
                for (self.host_requests, 0..) |request, index| {
                    try request.validate(capacity);
                    if (request.turn_sequence_number > self.turn_sequence_number) return error.InvalidFrameEncoding;
                    if (request.request_ordinal != index) return error.InvalidFrameEncoding;
                }
                if (self.finalized_actuation_receipt_fingerprints.len > capacity.max_actuation_records) return error.CapacityExceeded;
                for (self.finalized_actuation_receipt_fingerprints) |fingerprint| {
                    if (fingerprint == 0) return error.InvalidFrameEncoding;
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
                if (self.turn_sequence_number != self.checkpoint.turn_sequence_number) return error.InvalidFrameEncoding;
                if (self.turn_sequence_number != self.turn_receipt.turn_sequence_number) return error.InvalidFrameEncoding;
                if (self.checkpoint.capsule_fingerprint != self.turn_receipt.resulting_capsule_fingerprint) return error.InvalidFrameEncoding;
                if (self.status != self.turn_receipt.status) return error.InvalidFrameEncoding;
                if (self.root_result_fingerprint != self.turn_receipt.root_result_fingerprint) return error.InvalidFrameEncoding;
                if (self.status == .completed) {
                    if (self.root_result_fingerprint == null) return error.InvalidFrameEncoding;
                } else if (self.root_result_fingerprint != null) {
                    return error.InvalidFrameEncoding;
                }
                if (self.run_receipt_fingerprint != self.turn_receipt.run_receipt_fingerprint) return error.InvalidFrameEncoding;
                if (self.archive_append_batch_fingerprint != self.turn_receipt.archive_append_batch_fingerprint) return error.InvalidFrameEncoding;
                if (self.blocker_count != self.turn_receipt.blocker_count or self.blocker_count != self.quiescence.blocker_count) return error.InvalidFrameEncoding;
                if (self.warning_count != self.turn_receipt.warning_count or self.warning_count != self.quiescence.warning_count) return error.InvalidFrameEncoding;
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
                try writeOptionalU64(&out, allocator, self.run_receipt_fingerprint);
                try writeOptionalU64(&out, allocator, self.archive_append_batch_fingerprint);
                try writeOptionalU64(&out, allocator, self.archive_append_batch_ref_fingerprint);
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
                try output.validate(output.manifest_fingerprint, Capacity.large_native_test);
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

                if (checkpoint_payload.len + receipt_payload.len + output_payload.len > capacity.max_archive_append_bytes) {
                    return error.CapacityExceeded;
                }

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

                const output_deps = [_]World.Continuity.ObjectRef{ refs[0], refs[1] };
                objects[2] = try cloneEnvelope(allocator, World.Continuity.ObjectEnvelope.init(.{
                    .kind = .appliance_turn_output,
                    .dependency_refs = &output_deps,
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
                    (result.wasm_manifest_fingerprint == null or (result.wasm_manifest_fingerprint.? == result.manifest_fingerprint and result.wasm_required_exports_present and result.wasm_forbidden_import_count == 0)) and
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
                if (self.wasm_manifest_fingerprint == null and (self.wasm_required_exports_present or self.wasm_forbidden_import_count != 0)) return error.InvalidFrameEncoding;
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
            last_turn_status: ?TurnStatus = null,
            current_turn_sequence_number: u64 = 0,
            previous_turn_receipt_fingerprint: ?u64 = null,
            outstanding_host_request: ?HostRequest = null,
            outstanding_host_request_metadata_owned: bool = false,
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
                outstanding_host_request: ?HostRequest,
                outstanding_host_request_metadata_owned: bool,
                snapshot_metadata_owned: bool = false,
                pending_archive_append_batch_fingerprint: ?u64,
                pending_archive_resulting_cursor: ?World.Continuity.Chronicle.Cursor,
                latest_archive_cursor: World.Continuity.Chronicle.Cursor,
                latest_archive_moment_fingerprint: ?u64,
                latest_archive_seal_fingerprint: ?u64,
                latest_chronicle_cursor_fingerprint: ?u64,
                last_turn_status: ?TurnStatus,

                fn capture(core: *Core) !@This() {
                    var request = core.outstanding_host_request;
                    var owns_snapshot_metadata = false;
                    if (core.outstanding_host_request_metadata_owned) {
                        if (request) |*captured| {
                            captured.metadata = try core.allocator.dupe(u8, captured.metadata);
                            owns_snapshot_metadata = true;
                        }
                    }
                    return .{
                        .state = core.state,
                        .current_turn_sequence_number = core.current_turn_sequence_number,
                        .previous_turn_receipt_fingerprint = core.previous_turn_receipt_fingerprint,
                        .outstanding_host_request = request,
                        .outstanding_host_request_metadata_owned = core.outstanding_host_request_metadata_owned,
                        .snapshot_metadata_owned = owns_snapshot_metadata,
                        .pending_archive_append_batch_fingerprint = core.pending_archive_append_batch_fingerprint,
                        .pending_archive_resulting_cursor = core.pending_archive_resulting_cursor,
                        .latest_archive_cursor = core.latest_archive_cursor,
                        .latest_archive_moment_fingerprint = core.latest_archive_moment_fingerprint,
                        .latest_archive_seal_fingerprint = core.latest_archive_seal_fingerprint,
                        .latest_chronicle_cursor_fingerprint = core.latest_chronicle_cursor_fingerprint,
                        .last_turn_status = core.last_turn_status,
                    };
                }

                fn restore(self: *@This(), core: *Core) void {
                    core.clearOutstandingHostRequest();
                    core.state = self.state;
                    core.current_turn_sequence_number = self.current_turn_sequence_number;
                    core.previous_turn_receipt_fingerprint = self.previous_turn_receipt_fingerprint;
                    core.outstanding_host_request = self.outstanding_host_request;
                    core.outstanding_host_request_metadata_owned = self.outstanding_host_request_metadata_owned;
                    core.pending_archive_append_batch_fingerprint = self.pending_archive_append_batch_fingerprint;
                    core.pending_archive_resulting_cursor = self.pending_archive_resulting_cursor;
                    core.latest_archive_cursor = self.latest_archive_cursor;
                    core.latest_archive_moment_fingerprint = self.latest_archive_moment_fingerprint;
                    core.latest_archive_seal_fingerprint = self.latest_archive_seal_fingerprint;
                    core.latest_chronicle_cursor_fingerprint = self.latest_chronicle_cursor_fingerprint;
                    core.last_turn_status = self.last_turn_status;
                    self.outstanding_host_request = null;
                    self.snapshot_metadata_owned = false;
                }

                fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                    if (self.snapshot_metadata_owned) {
                        if (self.outstanding_host_request) |request| allocator.free(request.metadata);
                    }
                    self.outstanding_host_request = null;
                    self.snapshot_metadata_owned = false;
                }
            };

            pub fn init(manifest: Manifest, memory_plan: MemoryPlan) @This() {
                return .{ .manifest_value = manifest, .memory_plan_value = memory_plan };
            }

            pub fn initWithCapacity(allocator: std.mem.Allocator, manifest: Manifest, memory_plan: MemoryPlan, capacity: Capacity) @This() {
                return .{
                    .allocator = allocator,
                    .manifest_value = manifest,
                    .memory_plan_value = memory_plan,
                    .capacity_value = capacity,
                };
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
                var host_request_storage: [1]HostRequest = undefined;
                const host_requests = if (status == .needs_host) blk: {
                    if (self.capacity_value.max_host_requests_per_turn == 0) return error.CapacityExceeded;
                    if (commandHasNonTerminalHostReply(command) or command.kind == .restore) {
                        if (self.outstanding_host_request) |request| {
                            host_request_storage[0] = request;
                            break :blk host_request_storage[0..1];
                        }
                    }
                    host_request_storage[0] = self.hostRequestFor(command, turn_sequence_number, capsule_fingerprint);
                    break :blk host_request_storage[0..1];
                } else &.{};
                var checkpoint_outstanding_host_request_storage: [1]HostRequest = undefined;
                const checkpoint_outstanding_host_requests = if (host_requests.len != 0)
                    host_requests
                else if (resulting_core_state == .waiting_host) blk: {
                    if (self.outstanding_host_request) |request| {
                        checkpoint_outstanding_host_request_storage[0] = request;
                        break :blk checkpoint_outstanding_host_request_storage[0..1];
                    }
                    return error.InvalidFrameEncoding;
                } else &.{};
                var applied_host_reply_fingerprint_storage: [1]u64 = undefined;
                const applied_host_reply_fingerprints = if (command.host_replies.len != 0) blk: {
                    applied_host_reply_fingerprint_storage[0] = command.host_replies[0].reply_fingerprint;
                    break :blk applied_host_reply_fingerprint_storage[0..1];
                } else &.{};
                const finalized_actuation_receipt_fingerprints: []const u64 = &.{};
                var emitted_host_request_fingerprint_storage: [1]u64 = undefined;
                const emitted_host_request_fingerprints = if (host_requests.len != 0) blk: {
                    emitted_host_request_fingerprint_storage[0] = host_requests[0].request_fingerprint;
                    break :blk emitted_host_request_fingerprint_storage[0..1];
                } else &.{};
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
                const quiescence = QuiescenceReport.init(.{
                    .quiescent = true,
                    .pending_host_request_count = checkpoint_outstanding_host_requests.len,
                    .prepared_actuation_count = host_requests.len,
                    .completed_run_count = if (status == .completed) 1 else 0,
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
                    .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
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
                    .turn_sequence_number = turn_sequence_number,
                    .capsule_fingerprint = capsule_fingerprint,
                    .latest_archive_moment_fingerprint = acknowledged_archive_moment,
                    .latest_archive_seal_fingerprint = acknowledged_archive_seal,
                    .latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                    .pending_archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                    .pending_archive_resulting_cursor = planned_archive_resulting_cursor,
                    .latest_archive_cursor = acknowledged_archive_cursor_value,
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
                    .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                    .checkpoint = checkpoint,
                    .turn_receipt = turn_receipt,
                    .blocker_count = if (status == .blocked) 1 else 0,
                    .warning_count = warning_count,
                    .diagnostic_metadata = "core-shell",
                });
                if (self.shouldPlanArchiveAppend(command)) {
                    var archive_plan = try ArchivePlan.initForTurnOutput(self.allocator, acknowledged_archive_cursor_value, output, self.capacity_value);
                    defer archive_plan.deinit();
                    archive_append_batch_fingerprint = archive_plan.append_batch.append_batch_fingerprint;
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
                        .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
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
                        .turn_sequence_number = turn_sequence_number,
                        .capsule_fingerprint = capsule_fingerprint,
                        .latest_archive_moment_fingerprint = acknowledged_archive_moment,
                        .latest_archive_seal_fingerprint = acknowledged_archive_seal,
                        .latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor,
                        .pending_archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                        .pending_archive_resulting_cursor = planned_archive_resulting_cursor,
                        .latest_archive_cursor = acknowledged_archive_cursor_value,
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
                        .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                        .checkpoint = checkpoint,
                        .turn_receipt = turn_receipt,
                        .blocker_count = if (status == .blocked) 1 else 0,
                        .warning_count = warning_count,
                        .diagnostic_metadata = "core-shell",
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
                        if (!(self.outstanding_host_request != null and self.outstanding_host_request.?.request_fingerprint == host_requests[0].request_fingerprint)) {
                            self.clearOutstandingHostRequest();
                            self.outstanding_host_request = host_requests[0];
                        }
                    } else {
                        self.clearOutstandingHostRequest();
                    }
                    self.pending_archive_append_batch_fingerprint = archive_append_batch_fingerprint;
                    if (retention_ack != null) self.latest_archive_cursor = acknowledged_archive_cursor_value;
                    self.pending_archive_resulting_cursor = planned_archive_resulting_cursor;
                    self.latest_archive_moment_fingerprint = acknowledged_archive_moment;
                    self.latest_archive_seal_fingerprint = acknowledged_archive_seal;
                    self.latest_chronicle_cursor_fingerprint = acknowledged_chronicle_cursor;
                }
                self.state = resulting_core_state;
                self.last_turn_status = status;
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
                self.last_turn_status = null;
                self.state = .uninitialized;
                self.clearContinuationState();
            }

            pub fn restore(self: *@This(), checkpoint: Checkpoint) !void {
                try checkpoint.validate(self.manifest_value.manifest_fingerprint, self.capacity_value);
                var rollback = try ContinuationSnapshot.capture(self);
                errdefer rollback.restore(self);
                try self.applyCheckpointState(checkpoint);
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
                        if (self.state != .uninitialized) {
                            if (checkpoint.turn_sequence_number != self.current_turn_sequence_number) return error.StaleTurn;
                            if (checkpoint.previous_turn_receipt_fingerprint != self.previous_turn_receipt_fingerprint) return error.StaleTurn;
                        }
                    },
                    .@"continue" => {
                        if (self.last_turn_status) |last_status| {
                            if (last_status == .failed or last_status == .cancelled) return error.StaleTurn;
                            if (last_status == .completed and self.pending_archive_append_batch_fingerprint == null) return error.StaleTurn;
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
                        if (command.turn_sequence_number < self.current_turn_sequence_number) return error.StaleTurn;
                    },
                }
            }

            fn validateCommandExecutionMode(self: @This(), command: Command) !void {
                if (!self.manifest_value.supported_execution_modes.supports(command.execution_mode)) return error.InvalidCommand;
            }

            fn validateCommandReplies(self: @This(), command: Command) !void {
                if (command.kind != .@"continue" and command.kind != .restore) return;
                if (command.host_replies.len != 0 and command.execution_mode != .fresh) return error.InvalidMode;
                const outstanding = if (command.kind == .restore) blk: {
                    const checkpoint = command.restore_checkpoint orelse return error.RestoreRejected;
                    if (checkpoint.outstanding_host_requests.len == 0) {
                        if (command.host_replies.len != 0) return error.UnknownRequest;
                        return;
                    }
                    if (checkpoint.outstanding_host_requests.len != 1) return error.UnknownRequest;
                    if (command.host_replies.len == 0) return;
                    break :blk checkpoint.outstanding_host_requests[0];
                } else self.outstanding_host_request orelse {
                    if (command.host_replies.len != 0) return error.UnknownRequest;
                    return;
                };
                if (command.host_replies.len != 1) return error.UnknownRequest;
                try command.host_replies[0].validate(&.{outstanding}, self.capacity_value);
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
                    if (command.kind == .inspect) return error.InvalidFrameEncoding;
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
                return self.manifest_value.enabled_features.archive_append and command.kind != .inspect and command.kind != .reset;
            }

            fn warningCountForCommand(self: @This(), command: Command) usize {
                if (command.kind == .inspect or command.kind == .reset) return 0;
                if (!self.manifest_value.enabled_features.archive_append) return 0;
                if (self.manifest_value.enabled_features.archive_ack_gate) return 0;
                if (self.pending_archive_append_batch_fingerprint == null) return 0;
                if ((effectiveRetentionAck(command) catch null) != null) return 0;
                return 1;
            }

            fn applyCheckpointState(self: *@This(), checkpoint: Checkpoint) !void {
                if (checkpoint.outstanding_host_requests.len > 1) return error.InvalidFrameEncoding;
                self.current_turn_sequence_number = checkpoint.turn_sequence_number;
                self.previous_turn_receipt_fingerprint = checkpoint.previous_turn_receipt_fingerprint;
                self.clearOutstandingHostRequest();
                if (checkpoint.outstanding_host_requests.len == 1) {
                    self.outstanding_host_request = checkpoint.outstanding_host_requests[0];
                    self.outstanding_host_request.?.metadata = try self.allocator.dupe(u8, checkpoint.outstanding_host_requests[0].metadata);
                    self.outstanding_host_request_metadata_owned = true;
                }
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
            }

            fn clearContinuationState(self: *@This()) void {
                self.current_turn_sequence_number = 0;
                self.previous_turn_receipt_fingerprint = null;
                self.clearOutstandingHostRequest();
                self.pending_archive_append_batch_fingerprint = null;
                self.pending_archive_resulting_cursor = null;
                self.latest_archive_cursor = World.Continuity.Chronicle.Cursor.initial();
                self.latest_archive_moment_fingerprint = null;
                self.latest_archive_seal_fingerprint = null;
                self.latest_chronicle_cursor_fingerprint = null;
            }

            fn clearOutstandingHostRequest(self: *@This()) void {
                if (self.outstanding_host_request_metadata_owned) {
                    if (self.outstanding_host_request) |request| self.allocator.free(request.metadata);
                }
                self.outstanding_host_request = null;
                self.outstanding_host_request_metadata_owned = false;
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
                if (commandHasNonTerminalHostReply(command)) return .needs_host;
                if (command.host_replies.len != 0) return turnStatusForHostOutcome(command.host_replies[0].outcome.status);
                if (self.manifest_value.actuation_binding_fingerprints.len == 0) return .completed;
                if (command.execution_mode == .fresh) return .needs_host;
                if (commandHasReplayEvidence(command)) return .completed;
                return .blocked;
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

            fn hostRequestFor(self: @This(), command: Command, turn_sequence_number: u64, capsule_fingerprint: u64) HostRequest {
                const descriptor_fingerprint = self.manifest_value.actuation_descriptor_fingerprints[0];
                const binding_fingerprint = self.manifest_value.actuation_binding_fingerprints[0];
                const intent_fingerprint = fingerprintCoreHostIntent(self.manifest_value.manifest_fingerprint, command.command_fingerprint, binding_fingerprint, turn_sequence_number);
                const envelope_fingerprint = fingerprintCoreHostEnvelope(intent_fingerprint, capsule_fingerprint);
                const idempotency_key_fingerprint = fingerprintCoreHostIdempotencyKey(self.manifest_value.manifest_fingerprint, command.command_fingerprint, turn_sequence_number);
                const decision_fingerprint = fingerprintCoreHostDecision(intent_fingerprint, descriptor_fingerprint);
                return HostRequest.init(.{
                    .turn_sequence_number = turn_sequence_number,
                    .request_ordinal = 0,
                    .run_handle_fingerprint = stateFingerprintFor(self.state, self.current_turn_sequence_number, self.previous_turn_receipt_fingerprint),
                    .pending_port_fingerprint = capsule_fingerprint,
                    .world_port_id = 0,
                    .intent_fingerprint = intent_fingerprint,
                    .envelope_fingerprint = envelope_fingerprint,
                    .decision_fingerprint = decision_fingerprint,
                    .expected_response_descriptor_fingerprint = descriptor_fingerprint,
                    .idempotency_key_fingerprint = idempotency_key_fingerprint,
                    .supervision_ref_fingerprint = if (self.manifest_value.supervision_policy_fingerprint == 0) null else self.manifest_value.supervision_policy_fingerprint,
                    .metadata = "core-shell.host-request",
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
                const status = if (self.core.last_turn_status) |turn_status|
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
                metadata_export_signatures_valid: bool = false,
                memory_export_present: bool = false,
                memory_initial_pages: u32 = 0,
                alloc_export_present: bool = false,
                free_export_present: bool = false,

                pub fn passed(self: @This()) bool {
                    return self.abi_version == Abi.version and
                        self.required_exports_present and
                        self.metadata_exports_present and
                        self.required_export_signatures_valid and
                        self.metadata_export_signatures_valid and
                        self.memory_export_present and
                        self.memory_initial_pages > 0 and
                        self.import_count == 0 and
                        self.forbidden_import_count == 0;
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
                var memory_count: u32 = 0;
                var type_sigs: [wasm_max_inspected_types]WasmFuncSignature = undefined;
                var type_count: usize = 0;
                var function_type_indices: [wasm_max_inspected_functions]u32 = undefined;
                var function_count: usize = 0;
                var abi_export_function_index: ?u32 = null;
                var cursor: usize = 8;
                while (cursor < bytes.len) {
                    const section_id = try wasmReadU8(bytes, &cursor);
                    const section_len = try wasmReadU32(bytes, &cursor);
                    if (section_len > bytes.len - cursor) return error.InvalidFrameEncoding;
                    const section = bytes[cursor .. cursor + section_len];
                    switch (section_id) {
                        1 => type_count = try inspectWasmTypes(section, &type_sigs),
                        2 => try inspectWasmImports(section, &inspection),
                        3 => function_count = try inspectWasmFunctions(section, &function_type_indices),
                        5 => {
                            const memory = try inspectWasmMemory(section);
                            memory_count = memory.count;
                            inspection.memory_initial_pages = memory.initial_pages;
                        },
                        7 => try inspectWasmExports(
                            section,
                            memory_count,
                            type_sigs[0..type_count],
                            function_type_indices[0..function_count],
                            &inspection,
                            &required_mask,
                            &required_signature_mask,
                            &metadata_mask,
                            &metadata_signature_mask,
                            &abi_export_function_index,
                        ),
                        10 => try inspectWasmCode(section, function_count, inspection.import_function_count, abi_export_function_index, &inspection),
                        else => {},
                    }
                    cursor += section_len;
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
                return inspection;
            }
        };

        pub fn memoryPlan(capacity: Capacity, profile: Profile) MemoryPlan {
            return MemoryPlan.derive(capacity, profile);
        }

        pub fn requiredMemoryBytes(capacity: Capacity, profile: Profile) usize {
            return memoryPlan(capacity, profile).maximum_linear_memory_bytes;
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

        const WasmFuncSignature = struct {
            param_count: u32 = 0,
            result_count: u32 = 0,
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
                var all_params_i32 = true;
                var param_index: u32 = 0;
                while (param_index < param_count) : (param_index += 1) {
                    if ((try wasmReadU8(section, &cursor)) != 0x7f) all_params_i32 = false;
                }
                const result_count = try wasmReadU32(section, &cursor);
                var all_results_i32 = true;
                var result_index: u32 = 0;
                while (result_index < result_count) : (result_index += 1) {
                    if ((try wasmReadU8(section, &cursor)) != 0x7f) all_results_i32 = false;
                }
                out[index] = .{
                    .param_count = param_count,
                    .result_count = result_count,
                    .all_params_i32 = all_params_i32,
                    .all_results_i32 = all_results_i32,
                };
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return @intCast(count);
        }

        fn inspectWasmFunctions(section: []const u8, out: *[wasm_max_inspected_functions]u32) !usize {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count > out.len) return error.CapacityExceeded;
            var index: usize = 0;
            while (index < count) : (index += 1) out[index] = try wasmReadU32(section, &cursor);
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return @intCast(count);
        }

        const WasmMemorySection = struct {
            count: u32 = 0,
            initial_pages: u32 = 0,
        };

        const WasmLimits = struct {
            min: u32,
            max: ?u32 = null,
        };

        fn inspectWasmMemory(section: []const u8) !WasmMemorySection {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            var index: u32 = 0;
            var initial_pages: u32 = 0;
            while (index < count) : (index += 1) {
                const limits = try wasmReadLimits(section, &cursor);
                if (index == 0) initial_pages = limits.min;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
            return .{
                .count = count,
                .initial_pages = initial_pages,
            };
        }

        fn inspectWasmExports(
            section: []const u8,
            memory_count: u32,
            type_sigs: []const WasmFuncSignature,
            function_type_indices: []const u32,
            inspection: *Abi.WasmInspection,
            required_mask: *u64,
            required_signature_mask: *u64,
            metadata_mask: *u64,
            metadata_signature_mask: *u64,
            abi_export_function_index: *?u32,
        ) !void {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const name = try wasmReadName(section, &cursor);
                const kind = try wasmReadU8(section, &cursor);
                const export_index = try wasmReadU32(section, &cursor);
                inspection.export_count += 1;
                if (kind == 2 and export_index < memory_count and std.mem.eql(u8, name, "memory")) {
                    inspection.memory_export_present = true;
                }
                if (kind == 0 and std.mem.eql(u8, name, "world_alloc")) inspection.alloc_export_present = true;
                if (kind == 0 and std.mem.eql(u8, name, "world_free")) inspection.free_export_present = true;
                if (kind == 0) {
                    for (Abi.required_exports, 0..) |required, required_index| {
                        if (std.mem.eql(u8, name, required)) {
                            required_mask.* |= @as(u64, 1) << @intCast(required_index);
                            if (applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, applianceRequiredExportParamCount(required_index), 1)) {
                                required_signature_mask.* |= @as(u64, 1) << @intCast(required_index);
                            }
                            if (required_index == 0) abi_export_function_index.* = export_index;
                        }
                    }
                    for (Abi.metadata_exports, 0..) |metadata_export, metadata_index| {
                        if (std.mem.eql(u8, name, metadata_export)) {
                            metadata_mask.* |= @as(u64, 1) << @intCast(metadata_index);
                            if (applianceExportSignatureMatches(export_index, inspection.import_function_count, type_sigs, function_type_indices, 0, 1)) {
                                metadata_signature_mask.* |= @as(u64, 1) << @intCast(metadata_index);
                            }
                        }
                    }
                }
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
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
            abi_export_function_index: ?u32,
            inspection: *Abi.WasmInspection,
        ) !void {
            var cursor: usize = 0;
            const count = try wasmReadU32(section, &cursor);
            if (count != function_count) return error.InvalidFrameEncoding;
            const abi_defined_index = if (abi_export_function_index) |function_index| blk: {
                if (function_index < import_function_count) break :blk null;
                break :blk function_index - @as(u32, @intCast(import_function_count));
            } else null;
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const body_len = try wasmReadU32(section, &cursor);
                if (body_len > section.len - cursor) return error.InvalidFrameEncoding;
                const body = section[cursor .. cursor + body_len];
                if (abi_defined_index != null and index == abi_defined_index.?) {
                    inspection.abi_version = try readWasmConstantU32FunctionBody(body);
                }
                cursor += body_len;
            }
            if (cursor != section.len) return error.InvalidFrameEncoding;
        }

        fn readWasmConstantU32FunctionBody(body: []const u8) !u32 {
            var cursor: usize = 0;
            const local_group_count = try wasmReadU32(body, &cursor);
            var local_group_index: u32 = 0;
            while (local_group_index < local_group_count) : (local_group_index += 1) {
                _ = try wasmReadU32(body, &cursor);
                _ = try wasmReadU8(body, &cursor);
            }
            const opcode = try wasmReadU8(body, &cursor);
            if (opcode != 0x41) return error.InvalidFrameEncoding;
            const value = try wasmReadU32(body, &cursor);
            const terminator = try wasmReadU8(body, &cursor);
            if (terminator == 0x0f) {
                if ((try wasmReadU8(body, &cursor)) != 0x0b) return error.InvalidFrameEncoding;
            } else if (terminator != 0x0b) {
                return error.InvalidFrameEncoding;
            }
            if (cursor != body.len) return error.InvalidFrameEncoding;
            return value;
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
            capacity.validate() catch @compileError("World Appliance capacity is invalid");
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
                .supported_execution_modes = ExecutionModeSet.fromProfile(profile),
                .enabled_features = FeatureSet.fromProfile(profile),
                .capacity_fingerprint = capacity.fingerprint(),
                .memory_plan_fingerprint = plan.plan_fingerprint,
                .required_host_capabilities = HostCapabilityFlags.fromProfile(profile),
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
                if (actuation_bindings.len > 1) @compileError("World Appliance Core currently supports one external Actuation binding");
                if (actuation_bindings.len == 1 and actuation_bindings[0].world_port_id != 0) @compileError("World Appliance Core currently supports only world_port_id 0 external Actuation");
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

        fn manifestEncodedLen(manifest: Manifest) usize {
            return @sizeOf(u32) + @sizeOf(u32) + @sizeOf(u64) + @sizeOf(u32) +
                (6 * @sizeOf(u64)) +
                u64SliceEncodedLen(manifest.provider_target_ref_fingerprints) +
                u64SliceEncodedLen(manifest.fabric_plan_fingerprints) +
                @sizeOf(u64) +
                u64SliceEncodedLen(manifest.actuation_descriptor_fingerprints) +
                u64SliceEncodedLen(manifest.actuation_binding_fingerprints) +
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
            hashOptionalU64(&hasher, output.run_receipt_fingerprint);
            hashOptionalU64(&hasher, output.archive_append_batch_fingerprint);
            hashOptionalU64(&hasher, output.archive_append_batch_ref_fingerprint);
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
            hashU64(&hasher, request.intent_fingerprint);
            hashU64(&hasher, request.envelope_fingerprint);
            hashU64(&hasher, request.decision_fingerprint);
            hashU64(&hasher, request.expected_response_descriptor_fingerprint);
            hashU64(&hasher, request.idempotency_key_fingerprint);
            hashOptionalU64(&hasher, request.supervision_ref_fingerprint);
            hashBytes(&hasher, request.metadata);
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
            for (command.host_replies) |reply| {
                const reply_ack = reply.retention_ack orelse continue;
                if (ack) |existing| {
                    if (existing.ack_fingerprint != reply_ack.ack_fingerprint) return error.InvalidFrameEncoding;
                } else {
                    ack = reply_ack;
                }
            }
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

        fn commandHasReplayEvidence(command: Command) bool {
            return command.receiver_evidence_fingerprints.len != 0;
        }

        fn hostOutcomeStatusIsTerminal(status: HostOutcomeStatus) bool {
            return switch (status) {
                .responded, .rejected, .failed, .cancelled => true,
                .pending, .deferred => false,
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
            const intent_fingerprint = try readU64(bytes, cursor);
            const envelope_fingerprint = try readU64(bytes, cursor);
            const decision_fingerprint = try readU64(bytes, cursor);
            const expected_response_descriptor_fingerprint = try readU64(bytes, cursor);
            const idempotency_key_fingerprint = try readU64(bytes, cursor);
            const supervision_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const metadata = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(metadata);
            return .{
                .request_format_version = request_format_version,
                .request_fingerprint_version = request_fingerprint_version,
                .request_fingerprint = request_fingerprint,
                .turn_sequence_number = turn_sequence_number,
                .request_ordinal = request_ordinal,
                .run_handle_fingerprint = run_handle_fingerprint,
                .pending_port_fingerprint = pending_port_fingerprint,
                .world_port_id = world_port_id,
                .intent_fingerprint = intent_fingerprint,
                .envelope_fingerprint = envelope_fingerprint,
                .decision_fingerprint = decision_fingerprint,
                .expected_response_descriptor_fingerprint = expected_response_descriptor_fingerprint,
                .idempotency_key_fingerprint = idempotency_key_fingerprint,
                .supervision_ref_fingerprint = supervision_ref_fingerprint,
                .metadata = metadata,
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
            const run_receipt_fingerprint = try readOptionalU64(bytes, cursor);
            const archive_append_batch_fingerprint = try readOptionalU64(bytes, cursor);
            const archive_append_batch_ref_fingerprint = try readOptionalU64(bytes, cursor);
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
                .run_receipt_fingerprint = run_receipt_fingerprint,
                .archive_append_batch_fingerprint = archive_append_batch_fingerprint,
                .archive_append_batch_ref_fingerprint = archive_append_batch_ref_fingerprint,
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

        fn freeHostRequest(allocator: std.mem.Allocator, request: *HostRequest) void {
            allocator.free(request.metadata);
        }

        fn freeHostReply(allocator: std.mem.Allocator, reply: *HostReply) void {
            freeHostOutcome(allocator, &reply.outcome);
            if (reply.retention_ack) |ack| {
                var cleanup = ack;
                freeRetentionAck(allocator, &cleanup);
            }
            allocator.free(reply.metadata);
        }

        fn freeHostOutcome(allocator: std.mem.Allocator, outcome: *HostOutcome) void {
            allocator.free(outcome.response_bytes);
            allocator.free(outcome.host_evidence_bytes);
            allocator.free(outcome.metadata);
        }

        fn freeRetentionAck(allocator: std.mem.Allocator, ack: *RetentionAck) void {
            allocator.free(ack.metadata);
        }

        fn freeCheckpoint(allocator: std.mem.Allocator, checkpoint: *Checkpoint) void {
            allocator.free(checkpoint.capsule_image_bytes);
            if (checkpoint.pending_archive_resulting_cursor) |cursor| allocator.free(cursor.metadata_bytes);
            if (checkpoint.latest_archive_cursor) |cursor| allocator.free(cursor.metadata_bytes);
            freeHostRequests(allocator, checkpoint.outstanding_host_requests);
            allocator.free(checkpoint.metadata);
        }

        fn freeTurnReceipt(allocator: std.mem.Allocator, receipt: *TurnReceipt) void {
            allocator.free(receipt.applied_host_reply_fingerprints);
            allocator.free(receipt.emitted_host_request_fingerprints);
        }

        fn freeTurnOutput(allocator: std.mem.Allocator, output: *TurnOutput) void {
            if (output.owns_host_requests) freeHostRequests(allocator, output.host_requests);
            if (output.owns_finalized_actuation_receipt_fingerprints) allocator.free(output.finalized_actuation_receipt_fingerprints);
            if (output.owns_checkpoint_payloads) freeCheckpoint(allocator, &output.checkpoint);
            if (output.owns_turn_receipt_payloads) freeTurnReceipt(allocator, &output.turn_receipt);
            if (output.owns_diagnostic_metadata) allocator.free(output.diagnostic_metadata);
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

        fn fingerprintCoreHostIdempotencyKey(manifest_fingerprint: u64, command_fingerprint: u64, turn_sequence_number: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.appliance.core_shell.host_idempotency_key.fingerprint");
            hashU64(&hasher, manifest_fingerprint);
            hashU64(&hasher, command_fingerprint);
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
            const neutral_checkpoint = Checkpoint.init(.{
                .manifest_fingerprint = output.checkpoint.manifest_fingerprint,
                .turn_sequence_number = output.checkpoint.turn_sequence_number,
                .capsule_fingerprint = output.checkpoint.capsule_fingerprint,
                .capsule_image_ref_fingerprint = output.checkpoint.capsule_image_ref_fingerprint,
                .capsule_image_bytes = output.checkpoint.capsule_image_bytes,
                .latest_archive_moment_fingerprint = output.checkpoint.latest_archive_moment_fingerprint,
                .latest_archive_seal_fingerprint = output.checkpoint.latest_archive_seal_fingerprint,
                .latest_chronicle_cursor_fingerprint = output.checkpoint.latest_chronicle_cursor_fingerprint,
                .pending_archive_append_batch_fingerprint = null,
                .pending_archive_resulting_cursor = null,
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
            return TurnOutput.init(.{
                .manifest_fingerprint = output.manifest_fingerprint,
                .turn_sequence_number = output.turn_sequence_number,
                .source_state_fingerprint = output.source_state_fingerprint,
                .resulting_state_fingerprint = output.resulting_state_fingerprint,
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
