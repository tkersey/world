const std = @import("std");

pub fn Archive(comptime World: type) type {
    return struct {
        const Self = @This();
        const Continuity = World.Continuity;
        const Chronicle = Continuity.Chronicle;
        const ObjectRef = Continuity.ObjectRef;
        const ObjectEnvelope = Continuity.ObjectEnvelope;
        const max_decoded_byte_field_len = World.world_max_decoded_byte_field_len;

        pub const world_archive_format_version: u32 = 1;
        pub const world_archive_fingerprint_version: u32 = 1;
        pub const world_archive_header_format_version: u32 = 1;
        pub const world_archive_header_fingerprint_version: u32 = 1;
        pub const world_archive_segment_format_version: u32 = 1;
        pub const world_archive_segment_fingerprint_version: u32 = 1;
        pub const world_archive_moment_format_version: u32 = 1;
        pub const world_archive_moment_fingerprint_version: u32 = 1;
        pub const world_archive_seal_format_version: u32 = 1;
        pub const world_archive_seal_fingerprint_version: u32 = 1;
        pub const world_archive_append_batch_format_version: u32 = 1;
        pub const world_archive_append_batch_fingerprint_version: u32 = 1;

        pub const archive_magic: [8]u8 = "WRLDARC1".*;
        pub const segment_magic: [8]u8 = "WRLDSEG1".*;
        pub const canonical_byte_order_marker: u64 = 0x0102030405060708;

        pub const DurabilityPosture = enum {
            memory_only,
            clean_close_only,
            best_effort,
            host_defined,
            unknown,
        };

        pub const Capabilities = struct {
            persistent_across_process: bool = false,
            supports_reopen: bool = true,
            supports_historical_moments: bool = true,
            supports_atomic_visibility: bool = true,
            supports_projection_replay: bool = true,
            supports_bundle_import: bool = true,
            supports_idempotency_registry: bool = true,
            supports_valid_prefix_recovery: bool = true,
            supports_compaction: bool = false,
            wasm_memory_compatible: bool = true,
            wasm_file_compatible: bool = false,
            durability_posture: DurabilityPosture = .memory_only,
            blockers: []const []const u8 = &.{},
            warnings: []const []const u8 = &.{},

            pub fn validate(self: @This()) !void {
                for (self.blockers) |blocker| try validateByteField(blocker);
                for (self.warnings) |warning| try validateByteField(warning);
            }
        };

        pub const SafetyReport = struct {
            report_fingerprint: u64 = 0,
            experimental: bool = false,
            production_ready: bool = false,
            durability_posture: DurabilityPosture = .memory_only,
            crash_consistency_posture: []const u8 = "host-retention-defined; archive recovers longest valid sealed prefix",
            corruption_detection_posture: []const u8 = "segment and semantic fingerprints",
            hash_collision_posture: []const u8 = "world-fingerprint-defined; not cryptographic integrity",
            clone_freeze_posture: []const u8 = "world-value-defined",
            compaction_posture: []const u8 = "copy valid sealed prefix to new archive",
            concurrency_posture: []const u8 = "single-writer format; host owns coordination",
            wasm_posture: []const u8 = "byte validation is wasm-memory compatible; host owns storage",
            unsupported_behavior: []const []const u8 = &.{
                "storage engine semantics",
                "distributed coordination",
                "exactly-once host effects",
                "cryptographic integrity",
                "WASM filesystem",
            },
            blockers: []const []const u8 = &.{},
            warnings: []const []const u8 = &.{},

            pub fn init(args: struct {
                experimental: bool = false,
                production_ready: bool = false,
                durability_posture: DurabilityPosture = .memory_only,
                crash_consistency_posture: []const u8 = "host-retention-defined; archive recovers longest valid sealed prefix",
                corruption_detection_posture: []const u8 = "segment and semantic fingerprints",
                hash_collision_posture: []const u8 = "world-fingerprint-defined; not cryptographic integrity",
                clone_freeze_posture: []const u8 = "world-value-defined",
                compaction_posture: []const u8 = "copy valid sealed prefix to new archive",
                concurrency_posture: []const u8 = "single-writer format; host owns coordination",
                wasm_posture: []const u8 = "byte validation is wasm-memory compatible; host owns storage",
                unsupported_behavior: []const []const u8 = &.{
                    "storage engine semantics",
                    "distributed coordination",
                    "exactly-once host effects",
                    "cryptographic integrity",
                    "WASM filesystem",
                },
                blockers: []const []const u8 = &.{},
                warnings: []const []const u8 = &.{},
            }) @This() {
                var report = @This(){
                    .experimental = args.experimental,
                    .production_ready = args.production_ready,
                    .durability_posture = args.durability_posture,
                    .crash_consistency_posture = args.crash_consistency_posture,
                    .corruption_detection_posture = args.corruption_detection_posture,
                    .hash_collision_posture = args.hash_collision_posture,
                    .clone_freeze_posture = args.clone_freeze_posture,
                    .compaction_posture = args.compaction_posture,
                    .concurrency_posture = args.concurrency_posture,
                    .wasm_posture = args.wasm_posture,
                    .unsupported_behavior = args.unsupported_behavior,
                    .blockers = args.blockers,
                    .warnings = args.warnings,
                };
                report.report_fingerprint = fingerprintSafetyReport(report);
                return report;
            }

            pub fn validate(self: @This()) !void {
                if (self.report_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.report_fingerprint != fingerprintSafetyReport(self)) return error.InvalidFrameEncoding;
                try validateByteField(self.crash_consistency_posture);
                try validateByteField(self.corruption_detection_posture);
                try validateByteField(self.hash_collision_posture);
                try validateByteField(self.clone_freeze_posture);
                try validateByteField(self.compaction_posture);
                try validateByteField(self.concurrency_posture);
                try validateByteField(self.wasm_posture);
                for (self.unsupported_behavior) |item| try validateByteField(item);
                for (self.blockers) |blocker| try validateByteField(blocker);
                for (self.warnings) |warning| try validateByteField(warning);
            }
        };

        pub const Limits = struct {
            max_archive_bytes: usize = 128 * 1024 * 1024,
            max_payload_bytes: usize = max_decoded_byte_field_len * 16,
            max_segment_payload_bytes: usize = max_decoded_byte_field_len * 32,
            max_ref_count: usize = max_decoded_byte_field_len / @sizeOf(ObjectRef),
            max_event_count_per_moment: usize = max_decoded_byte_field_len / @sizeOf(u64),
            max_object_count_per_moment: usize = max_decoded_byte_field_len / @sizeOf(ObjectRef),

            pub fn validatePayloadLen(self: @This(), len: usize) !void {
                if (len > self.max_segment_payload_bytes) return error.InvalidFrameEncoding;
            }
        };

        pub const Header = struct {
            magic: [8]u8 = archive_magic,
            header_format_version: u32 = world_archive_header_format_version,
            archive_format_version: u32 = world_archive_format_version,
            archive_fingerprint_version: u32 = world_archive_fingerprint_version,
            byte_order_marker: u64 = canonical_byte_order_marker,
            compatible_chronicle_event_format_version: u32 = World.world_chronicle_event_format_version,
            compatible_chronicle_commit_format_version: u32 = World.world_chronicle_commit_format_version,
            compatible_object_envelope_format_version: u32 = World.world_continuity_object_envelope_format_version,
            genesis_cursor_fingerprint: u64 = Chronicle.Cursor.initial().cursor_fingerprint,
            required_feature_flags: u64 = 0,
            optional_feature_flags: u64 = 0,
            archive_profile_fingerprint: u64 = 0,
            header_fingerprint: u64 = 0,

            pub fn init(args: struct {
                required_feature_flags: u64 = 0,
                optional_feature_flags: u64 = 0,
            }) @This() {
                var header = @This(){
                    .required_feature_flags = args.required_feature_flags,
                    .optional_feature_flags = args.optional_feature_flags,
                };
                header.archive_profile_fingerprint = fingerprintArchiveProfile(header);
                header.header_fingerprint = fingerprintHeader(header);
                return header;
            }

            pub fn validate(self: @This()) !void {
                if (!std.mem.eql(u8, &self.magic, &archive_magic)) return error.InvalidFrameEncoding;
                if (self.header_format_version != world_archive_header_format_version) return error.InvalidFrameEncoding;
                if (self.archive_format_version != world_archive_format_version) return error.InvalidFrameEncoding;
                if (self.archive_fingerprint_version != world_archive_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.byte_order_marker != canonical_byte_order_marker) return error.InvalidFrameEncoding;
                if (self.compatible_chronicle_event_format_version != World.world_chronicle_event_format_version) return error.InvalidFrameEncoding;
                if (self.compatible_chronicle_commit_format_version != World.world_chronicle_commit_format_version) return error.InvalidFrameEncoding;
                if (self.compatible_object_envelope_format_version != World.world_continuity_object_envelope_format_version) return error.InvalidFrameEncoding;
                if (self.genesis_cursor_fingerprint != Chronicle.Cursor.initial().cursor_fingerprint) return error.InvalidFrameEncoding;
                if (self.required_feature_flags != 0) return error.UnsupportedMapping;
                if (self.archive_profile_fingerprint != fingerprintArchiveProfile(self)) return error.InvalidFrameEncoding;
                if (self.header_fingerprint != fingerprintHeader(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const SegmentKind = enum(u8) {
            moment_data = 1,
            moment_seal = 2,
            optional_extension = 3,
        };

        pub const SegmentHeader = struct {
            magic: [8]u8 = segment_magic,
            segment_format_version: u32 = world_archive_segment_format_version,
            segment_kind: SegmentKind,
            required: bool = true,
            sequence_number: u64,
            payload_byte_len: u64,
            payload_fingerprint: u64,
            segment_header_fingerprint: u64 = 0,

            pub fn init(args: struct {
                segment_kind: SegmentKind,
                required: bool = true,
                sequence_number: u64,
                payload: []const u8,
            }) @This() {
                var header = @This(){
                    .segment_kind = args.segment_kind,
                    .required = args.required,
                    .sequence_number = args.sequence_number,
                    .payload_byte_len = args.payload.len,
                    .payload_fingerprint = fingerprintPayloadBytes(args.payload),
                };
                header.segment_header_fingerprint = fingerprintSegmentHeader(header);
                return header;
            }

            pub fn validate(self: @This(), payload: []const u8) !void {
                if (!std.mem.eql(u8, &self.magic, &segment_magic)) return error.InvalidFrameEncoding;
                if (self.segment_format_version != world_archive_segment_format_version) return error.InvalidFrameEncoding;
                if (self.sequence_number == 0) return error.InvalidFrameEncoding;
                if (self.payload_byte_len != payload.len) return error.InvalidFrameEncoding;
                if (self.payload_fingerprint != fingerprintPayloadBytes(payload)) return error.InvalidFrameEncoding;
                if (self.segment_header_fingerprint != fingerprintSegmentHeader(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const CommitRef = struct {
            commit_fingerprint: u64 = 0,
            transaction_fingerprint: u64 = 0,
            parent_cursor_fingerprint: u64 = 0,
            resulting_cursor_fingerprint: u64 = 0,

            pub fn fromCommit(commit: Chronicle.Commit) @This() {
                return .{
                    .commit_fingerprint = commit.commit_fingerprint,
                    .transaction_fingerprint = commit.transaction_fingerprint,
                    .parent_cursor_fingerprint = commit.parent_cursor_fingerprint,
                    .resulting_cursor_fingerprint = commit.resulting_cursor_fingerprint,
                };
            }

            pub fn validate(self: @This()) !void {
                if (self.commit_fingerprint == 0 or
                    self.transaction_fingerprint == 0 or
                    self.parent_cursor_fingerprint == 0 or
                    self.resulting_cursor_fingerprint == 0)
                {
                    return error.InvalidFrameEncoding;
                }
            }
        };

        pub const Moment = struct {
            moment_format_version: u32 = world_archive_moment_format_version,
            moment_fingerprint_version: u32 = world_archive_moment_fingerprint_version,
            moment_fingerprint: u64 = 0,
            sequence_number: u64 = 0,
            parent_moment_fingerprint: ?u64 = null,
            parent_seal_fingerprint: ?u64 = null,
            chronicle_parent_cursor: Chronicle.Cursor = Chronicle.Cursor.initial(),
            chronicle_resulting_cursor: Chronicle.Cursor = Chronicle.Cursor.initial(),
            chronicle_commit_ref: CommitRef = .{},
            committed_event_refs: []const u64 = &.{},
            committed_object_refs: []const ObjectRef = &.{},
            root_object_refs: []const ObjectRef = &.{},
            capsule_refs: []const ObjectRef = &.{},
            actuation_refs: []const ObjectRef = &.{},
            bundle_refs: []const ObjectRef = &.{},
            admission_refs: []const ObjectRef = &.{},
            environment_certificate_refs: []const ObjectRef = &.{},
            permit_receipt_refs: []const ObjectRef = &.{},
            link_assembly_refs: []const ObjectRef = &.{},
            fabric_receipt_refs: []const ObjectRef = &.{},
            guest_conformance_refs: []const ObjectRef = &.{},
            dependency_refs: []const ObjectRef = &.{},
            projection_summary_fingerprints: []const u64 = &.{},
            idempotency_registry_summary_fingerprint: ?u64 = null,
            diagnostic_metadata_bytes: []const u8 = "",
            owns_memory: bool = false,

            pub fn init(args: struct {
                sequence_number: u64,
                parent_moment_fingerprint: ?u64 = null,
                parent_seal_fingerprint: ?u64 = null,
                chronicle_parent_cursor: Chronicle.Cursor,
                chronicle_resulting_cursor: Chronicle.Cursor,
                chronicle_commit_ref: CommitRef,
                committed_event_refs: []const u64 = &.{},
                committed_object_refs: []const ObjectRef = &.{},
                root_object_refs: []const ObjectRef = &.{},
                capsule_refs: []const ObjectRef = &.{},
                actuation_refs: []const ObjectRef = &.{},
                bundle_refs: []const ObjectRef = &.{},
                admission_refs: []const ObjectRef = &.{},
                environment_certificate_refs: []const ObjectRef = &.{},
                permit_receipt_refs: []const ObjectRef = &.{},
                link_assembly_refs: []const ObjectRef = &.{},
                fabric_receipt_refs: []const ObjectRef = &.{},
                guest_conformance_refs: []const ObjectRef = &.{},
                dependency_refs: []const ObjectRef = &.{},
                projection_summary_fingerprints: []const u64 = &.{},
                idempotency_registry_summary_fingerprint: ?u64 = null,
                diagnostic_metadata_bytes: []const u8 = "",
                metadata_bytes: []const u8 = "",
            }) @This() {
                const metadata = if (args.diagnostic_metadata_bytes.len != 0) args.diagnostic_metadata_bytes else args.metadata_bytes;
                var moment = @This(){
                    .sequence_number = args.sequence_number,
                    .parent_moment_fingerprint = args.parent_moment_fingerprint,
                    .parent_seal_fingerprint = args.parent_seal_fingerprint,
                    .chronicle_parent_cursor = args.chronicle_parent_cursor,
                    .chronicle_resulting_cursor = args.chronicle_resulting_cursor,
                    .chronicle_commit_ref = args.chronicle_commit_ref,
                    .committed_event_refs = args.committed_event_refs,
                    .committed_object_refs = args.committed_object_refs,
                    .root_object_refs = args.root_object_refs,
                    .capsule_refs = args.capsule_refs,
                    .actuation_refs = args.actuation_refs,
                    .bundle_refs = args.bundle_refs,
                    .admission_refs = args.admission_refs,
                    .environment_certificate_refs = args.environment_certificate_refs,
                    .permit_receipt_refs = args.permit_receipt_refs,
                    .link_assembly_refs = args.link_assembly_refs,
                    .fabric_receipt_refs = args.fabric_receipt_refs,
                    .guest_conformance_refs = args.guest_conformance_refs,
                    .dependency_refs = args.dependency_refs,
                    .projection_summary_fingerprints = args.projection_summary_fingerprints,
                    .idempotency_registry_summary_fingerprint = args.idempotency_registry_summary_fingerprint,
                    .diagnostic_metadata_bytes = metadata,
                };
                moment.moment_fingerprint = fingerprintMoment(moment);
                return moment;
            }

            pub fn validate(self: @This()) !void {
                if (self.moment_format_version != world_archive_moment_format_version) return error.InvalidFrameEncoding;
                if (self.moment_fingerprint_version != world_archive_moment_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.moment_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.moment_fingerprint != fingerprintMoment(self)) return error.InvalidFrameEncoding;
                if (self.sequence_number == 0) return error.InvalidFrameEncoding;
                if (self.parent_moment_fingerprint != null and self.parent_moment_fingerprint.? == 0) return error.InvalidFrameEncoding;
                if (self.parent_seal_fingerprint != null and self.parent_seal_fingerprint.? == 0) return error.InvalidFrameEncoding;
                try self.chronicle_parent_cursor.validate();
                try self.chronicle_resulting_cursor.validate();
                try self.chronicle_commit_ref.validate();
                if (self.chronicle_commit_ref.parent_cursor_fingerprint != self.chronicle_parent_cursor.cursor_fingerprint) return error.InvalidFrameEncoding;
                if (self.chronicle_commit_ref.resulting_cursor_fingerprint != self.chronicle_resulting_cursor.cursor_fingerprint) return error.InvalidFrameEncoding;
                try validateU64Slice(self.committed_event_refs);
                try validateRefSlice(self.committed_object_refs);
                try validateRefSlice(self.root_object_refs);
                try validateRefSlice(self.capsule_refs);
                try validateRefSlice(self.actuation_refs);
                try validateRefSlice(self.bundle_refs);
                try validateRefSlice(self.admission_refs);
                try validateRefSlice(self.environment_certificate_refs);
                try validateRefSlice(self.permit_receipt_refs);
                try validateRefSlice(self.link_assembly_refs);
                try validateRefSlice(self.fabric_receipt_refs);
                try validateRefSlice(self.guest_conformance_refs);
                try validateRefSlice(self.dependency_refs);
                try validateU64Slice(self.projection_summary_fingerprints);
                if (self.idempotency_registry_summary_fingerprint != null and self.idempotency_registry_summary_fingerprint.? == 0) return error.InvalidFrameEncoding;
                try validateByteField(self.diagnostic_metadata_bytes);
            }

            pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
                var moment = self;
                moment.chronicle_parent_cursor.metadata_bytes = try allocator.dupe(u8, self.chronicle_parent_cursor.metadata_bytes);
                errdefer allocator.free(moment.chronicle_parent_cursor.metadata_bytes);
                moment.chronicle_resulting_cursor.metadata_bytes = try allocator.dupe(u8, self.chronicle_resulting_cursor.metadata_bytes);
                errdefer allocator.free(moment.chronicle_resulting_cursor.metadata_bytes);
                moment.committed_event_refs = try allocator.dupe(u64, self.committed_event_refs);
                errdefer allocator.free(moment.committed_event_refs);
                moment.committed_object_refs = try cloneRefSlice(allocator, self.committed_object_refs);
                errdefer freeRefSlice(allocator, moment.committed_object_refs);
                moment.root_object_refs = try cloneRefSlice(allocator, self.root_object_refs);
                errdefer freeRefSlice(allocator, moment.root_object_refs);
                moment.capsule_refs = try cloneRefSlice(allocator, self.capsule_refs);
                errdefer freeRefSlice(allocator, moment.capsule_refs);
                moment.actuation_refs = try cloneRefSlice(allocator, self.actuation_refs);
                errdefer freeRefSlice(allocator, moment.actuation_refs);
                moment.bundle_refs = try cloneRefSlice(allocator, self.bundle_refs);
                errdefer freeRefSlice(allocator, moment.bundle_refs);
                moment.admission_refs = try cloneRefSlice(allocator, self.admission_refs);
                errdefer freeRefSlice(allocator, moment.admission_refs);
                moment.environment_certificate_refs = try cloneRefSlice(allocator, self.environment_certificate_refs);
                errdefer freeRefSlice(allocator, moment.environment_certificate_refs);
                moment.permit_receipt_refs = try cloneRefSlice(allocator, self.permit_receipt_refs);
                errdefer freeRefSlice(allocator, moment.permit_receipt_refs);
                moment.link_assembly_refs = try cloneRefSlice(allocator, self.link_assembly_refs);
                errdefer freeRefSlice(allocator, moment.link_assembly_refs);
                moment.fabric_receipt_refs = try cloneRefSlice(allocator, self.fabric_receipt_refs);
                errdefer freeRefSlice(allocator, moment.fabric_receipt_refs);
                moment.guest_conformance_refs = try cloneRefSlice(allocator, self.guest_conformance_refs);
                errdefer freeRefSlice(allocator, moment.guest_conformance_refs);
                moment.dependency_refs = try cloneRefSlice(allocator, self.dependency_refs);
                errdefer freeRefSlice(allocator, moment.dependency_refs);
                moment.projection_summary_fingerprints = try allocator.dupe(u64, self.projection_summary_fingerprints);
                errdefer allocator.free(moment.projection_summary_fingerprints);
                moment.diagnostic_metadata_bytes = try allocator.dupe(u8, self.diagnostic_metadata_bytes);
                moment.owns_memory = true;
                return moment;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_memory) {
                    allocator.free(self.chronicle_parent_cursor.metadata_bytes);
                    allocator.free(self.chronicle_resulting_cursor.metadata_bytes);
                    allocator.free(self.committed_event_refs);
                    freeRefSlice(allocator, self.committed_object_refs);
                    freeRefSlice(allocator, self.root_object_refs);
                    freeRefSlice(allocator, self.capsule_refs);
                    freeRefSlice(allocator, self.actuation_refs);
                    freeRefSlice(allocator, self.bundle_refs);
                    freeRefSlice(allocator, self.admission_refs);
                    freeRefSlice(allocator, self.environment_certificate_refs);
                    freeRefSlice(allocator, self.permit_receipt_refs);
                    freeRefSlice(allocator, self.link_assembly_refs);
                    freeRefSlice(allocator, self.fabric_receipt_refs);
                    freeRefSlice(allocator, self.guest_conformance_refs);
                    freeRefSlice(allocator, self.dependency_refs);
                    allocator.free(self.projection_summary_fingerprints);
                    allocator.free(self.diagnostic_metadata_bytes);
                }
                self.* = undefined;
            }
        };

        pub const MomentData = struct {
            moment: Moment,
            commit: Chronicle.Commit,
            events: []const Chronicle.Event = &.{},
            objects: []const ObjectEnvelope = &.{},
            owns_memory: bool = false,

            pub fn validate(self: @This()) !void {
                try self.moment.validate();
                try self.commit.validate();
                if (self.commit.commit_fingerprint != self.moment.chronicle_commit_ref.commit_fingerprint) return error.InvalidFrameEncoding;
                if (self.commit.transaction_fingerprint != self.moment.chronicle_commit_ref.transaction_fingerprint) return error.InvalidFrameEncoding;
                if (self.commit.parent_cursor_fingerprint != self.moment.chronicle_parent_cursor.cursor_fingerprint) return error.InvalidFrameEncoding;
                if (self.commit.resulting_cursor_fingerprint != self.moment.chronicle_resulting_cursor.cursor_fingerprint) return error.InvalidFrameEncoding;
                if (!refSlicesEqual(self.commit.committed_object_refs, self.moment.committed_object_refs)) return error.InvalidFrameEncoding;
                if (self.events.len != self.moment.committed_event_refs.len) return error.InvalidFrameEncoding;
                if (self.events.len != self.commit.committed_event_fingerprints.len) return error.InvalidFrameEncoding;
                for (self.events, self.moment.committed_event_refs, self.commit.committed_event_fingerprints) |event, moment_expected, commit_expected| {
                    try event.validate();
                    if (event.event_fingerprint != moment_expected or event.event_fingerprint != commit_expected) return error.InvalidFrameEncoding;
                }
                var committed_ref_index: usize = 0;
                for (self.events) |event| {
                    if (event.kind != .object_committed) continue;
                    if (event.transaction_fingerprint != self.commit.transaction_fingerprint) return error.InvalidFrameEncoding;
                    for (event.object_refs) |ref| {
                        if (committed_ref_index >= self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                        if (!ref.eql(self.commit.committed_object_refs[committed_ref_index])) return error.InvalidFrameEncoding;
                        committed_ref_index += 1;
                    }
                }
                if (committed_ref_index != self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                for (self.objects) |envelope| {
                    try envelope.validate();
                    const ref = envelope.objectRef();
                    if (!containsRef(self.commit.committed_object_refs, ref)) return error.InvalidFrameEncoding;
                }
                for (self.commit.committed_object_refs) |ref| {
                    if (!objectSliceContainsRef(self.objects, ref)) return error.InvalidFrameEncoding;
                }
                try rejectConflictingObjectBytes(self.objects);
            }

            pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
                var result = @This(){
                    .moment = try self.moment.clone(allocator),
                    .commit = try self.commit.clone(allocator),
                    .events = try cloneEventSlice(allocator, self.events),
                    .objects = try cloneEnvelopeSlice(allocator, self.objects),
                    .owns_memory = true,
                };
                errdefer result.deinit(allocator);
                return result;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_memory) {
                    self.moment.deinit(allocator);
                    self.commit.deinit(allocator);
                    freeEventSlice(allocator, self.events);
                    freeEnvelopeSlice(allocator, self.objects);
                }
                self.* = undefined;
            }
        };

        pub const Seal = struct {
            seal_format_version: u32 = world_archive_seal_format_version,
            seal_fingerprint_version: u32 = world_archive_seal_fingerprint_version,
            seal_fingerprint: u64 = 0,
            sequence_number: u64,
            parent_seal_fingerprint: ?u64 = null,
            moment_fingerprint: u64,
            moment_data_segment_fingerprint: u64,
            chronicle_resulting_cursor_fingerprint: u64,
            committed_prefix_byte_len: u64,
            sealed_prefix_fingerprint: u64 = 0,

            pub fn init(args: struct {
                sequence_number: u64,
                parent_seal_fingerprint: ?u64 = null,
                moment_fingerprint: u64,
                moment_data_segment_fingerprint: u64,
                chronicle_resulting_cursor_fingerprint: u64,
                committed_prefix_byte_len: u64,
            }) @This() {
                var seal = @This(){
                    .sequence_number = args.sequence_number,
                    .parent_seal_fingerprint = args.parent_seal_fingerprint,
                    .moment_fingerprint = args.moment_fingerprint,
                    .moment_data_segment_fingerprint = args.moment_data_segment_fingerprint,
                    .chronicle_resulting_cursor_fingerprint = args.chronicle_resulting_cursor_fingerprint,
                    .committed_prefix_byte_len = args.committed_prefix_byte_len,
                };
                seal.sealed_prefix_fingerprint = fingerprintSealedPrefix(seal);
                seal.seal_fingerprint = fingerprintSeal(seal);
                return seal;
            }

            pub fn validate(self: @This()) !void {
                if (self.seal_format_version != world_archive_seal_format_version) return error.InvalidFrameEncoding;
                if (self.seal_fingerprint_version != world_archive_seal_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.sequence_number == 0 or
                    self.moment_fingerprint == 0 or
                    self.moment_data_segment_fingerprint == 0 or
                    self.chronicle_resulting_cursor_fingerprint == 0 or
                    self.committed_prefix_byte_len == 0)
                {
                    return error.InvalidFrameEncoding;
                }
                if (self.parent_seal_fingerprint != null and self.parent_seal_fingerprint.? == 0) return error.InvalidFrameEncoding;
                if (self.sealed_prefix_fingerprint != fingerprintSealedPrefix(self)) return error.InvalidFrameEncoding;
                if (self.seal_fingerprint != fingerprintSeal(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const AppendBatch = struct {
            append_batch_format_version: u32 = world_archive_append_batch_format_version,
            append_batch_fingerprint_version: u32 = world_archive_append_batch_fingerprint_version,
            append_batch_fingerprint: u64 = 0,
            parent_cursor: Chronicle.Cursor,
            commit: Chronicle.Commit,
            events: []const Chronicle.Event = &.{},
            objects: []const ObjectEnvelope = &.{},
            diagnostic_metadata_bytes: []const u8 = "",

            pub fn init(args: struct {
                parent_cursor: Chronicle.Cursor,
                commit: Chronicle.Commit,
                events: []const Chronicle.Event,
                objects: []const ObjectEnvelope,
                diagnostic_metadata_bytes: []const u8 = "",
            }) @This() {
                var batch = @This(){
                    .parent_cursor = args.parent_cursor,
                    .commit = args.commit,
                    .events = args.events,
                    .objects = args.objects,
                    .diagnostic_metadata_bytes = args.diagnostic_metadata_bytes,
                };
                batch.append_batch_fingerprint = fingerprintAppendBatch(batch);
                return batch;
            }

            pub fn validate(self: @This()) !void {
                if (self.append_batch_format_version != world_archive_append_batch_format_version) return error.InvalidFrameEncoding;
                if (self.append_batch_fingerprint_version != world_archive_append_batch_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.append_batch_fingerprint != fingerprintAppendBatch(self)) return error.InvalidFrameEncoding;
                try self.parent_cursor.validate();
                try self.commit.validate();
                if (self.commit.parent_cursor_fingerprint != self.parent_cursor.cursor_fingerprint) return error.InvalidFrameEncoding;
                if (self.events.len != self.commit.committed_event_fingerprints.len) return error.InvalidFrameEncoding;
                for (self.events, self.commit.committed_event_fingerprints) |event, expected| {
                    try event.validate();
                    if (event.event_fingerprint != expected) return error.InvalidFrameEncoding;
                }
                for (self.objects) |envelope| {
                    try envelope.validate();
                    const ref = envelope.objectRef();
                    if (!containsRef(self.commit.committed_object_refs, ref)) return error.InvalidFrameEncoding;
                }
                try rejectConflictingObjectBytes(self.objects);
                try validateByteField(self.diagnostic_metadata_bytes);
            }
        };

        pub const ScanReport = struct {
            header: ?Header = null,
            committed_moment_count: usize = 0,
            scanned_segment_count: usize = 0,
            committed_prefix_byte_len: usize = 0,
            latest_seal: ?Seal = null,
            discarded_tail_byte_len: usize = 0,
            valid: bool = false,
            recovered: bool = false,
        };

        pub const ValidationReport = struct {
            valid: bool,
            scan: ScanReport,
            blocker: ?[]const u8 = null,
        };

        pub const RecoveryReport = struct {
            latest_moment: ?Moment = null,
            latest_cursor: Chronicle.Cursor = Chronicle.Cursor.initial(),
            recovered_moment_count: usize = 0,
            recovered_commit_count: usize = 0,
            recovered_object_count: usize = 0,
            committed_prefix_byte_len: usize = 0,
            discarded_tail_byte_len: usize = 0,

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.latest_moment) |*moment| moment.deinit(allocator);
                self.* = undefined;
            }
        };

        pub const OpenReport = RecoveryReport;

        pub const ReplayReport = struct {
            report_fingerprint: u64 = 0,
            source_moment: ?Moment = null,
            source_cursor: Chronicle.Cursor = Chronicle.Cursor.initial(),
            chronicle_report: ?Chronicle.ReplayReport = null,
            replayed_commit_count: usize = 0,
            replayed_event_count: usize = 0,
            rebuilt_projection_count: usize = 0,
            mismatch_count: usize = 0,

            pub fn init(args: struct {
                source_moment: ?Moment = null,
                source_cursor: Chronicle.Cursor,
                chronicle_report: ?Chronicle.ReplayReport = null,
                replayed_commit_count: usize = 0,
                replayed_event_count: usize = 0,
                rebuilt_projection_count: usize = 0,
                mismatch_count: usize = 0,
            }) @This() {
                var report = @This(){
                    .source_moment = args.source_moment,
                    .source_cursor = args.source_cursor,
                    .chronicle_report = args.chronicle_report,
                    .replayed_commit_count = args.replayed_commit_count,
                    .replayed_event_count = args.replayed_event_count,
                    .rebuilt_projection_count = args.rebuilt_projection_count,
                    .mismatch_count = args.mismatch_count,
                };
                report.report_fingerprint = fingerprintReplayReport(report);
                return report;
            }

            pub fn validate(self: @This()) !void {
                if (self.report_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.report_fingerprint != fingerprintReplayReport(self)) return error.InvalidFrameEncoding;
                try self.source_cursor.validate();
                if (self.source_moment) |moment| try moment.validate();
                if (self.chronicle_report) |report| try report.validate();
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.source_moment) |*moment| moment.deinit(allocator);
                self.* = undefined;
            }
        };

        pub const Image = struct {
            allocator: std.mem.Allocator,
            header: Header,
            moments: []Moment = &.{},
            seals: []Seal = &.{},
            commits: []Chronicle.Commit = &.{},
            events: []Chronicle.Event = &.{},
            objects: []ObjectEnvelope = &.{},
            committed_prefix_byte_len: usize = 0,
            image_fingerprint: u64 = 0,
            owns_memory: bool = false,

            pub fn latestMoment(self: @This()) ?Moment {
                if (self.moments.len == 0) return null;
                var moment = self.moments[self.moments.len - 1];
                moment.owns_memory = false;
                return moment;
            }

            pub fn latestSeal(self: @This()) ?Seal {
                if (self.seals.len == 0) return null;
                return self.seals[self.seals.len - 1];
            }

            pub fn latestCursor(self: @This()) Chronicle.Cursor {
                if (self.latestMoment()) |moment| return moment.chronicle_resulting_cursor;
                return Chronicle.Cursor.initial();
            }

            pub fn openSnapshot(self: *const @This(), moment_ref: Moment) !Snapshot {
                for (self.moments, 0..) |moment, index| {
                    if (moment.moment_fingerprint == moment_ref.moment_fingerprint) {
                        var borrowed = moment;
                        borrowed.owns_memory = false;
                        return .{ .image = self, .moment_value = borrowed, .moment_index = index };
                    }
                }
                return error.ObjectMissing;
            }

            pub fn replay(self: *const @This(), options: Chronicle.ReplayOptions) !ReplayReport {
                var vault = try self.materializeVault(self.allocator, if (self.moments.len == 0) null else self.moments.len - 1);
                defer vault.deinit();
                const chronicle_report = try Chronicle.replay(&vault, options);
                const source_moment = if (self.latestMoment()) |moment| try moment.clone(self.allocator) else null;
                errdefer if (source_moment) |moment| {
                    var cleanup = moment;
                    cleanup.deinit(self.allocator);
                };
                return ReplayReport.init(.{
                    .source_moment = source_moment,
                    .source_cursor = self.latestCursor(),
                    .chronicle_report = chronicle_report,
                    .replayed_commit_count = self.commits.len,
                    .replayed_event_count = self.events.len,
                    .rebuilt_projection_count = chronicle_report.rebuilt_projection_count,
                    .mismatch_count = chronicle_report.mismatch_count,
                });
            }

            pub fn deinit(self: *@This()) void {
                if (self.owns_memory) {
                    for (self.moments) |*moment| moment.deinit(self.allocator);
                    self.allocator.free(self.moments);
                    self.allocator.free(self.seals);
                    for (self.commits) |*commit| commit.deinit(self.allocator);
                    self.allocator.free(self.commits);
                    freeEventSlice(self.allocator, self.events);
                    freeEnvelopeSlice(self.allocator, self.objects);
                }
                self.* = undefined;
            }

            fn materializeVault(self: *const @This(), allocator: std.mem.Allocator, moment_index: ?usize) !Continuity.MemoryVault {
                var vault = Continuity.MemoryVault{
                    .allocator = allocator,
                    .ledger = Continuity.Ledger.init(allocator),
                };
                errdefer vault.deinit();
                const upper = if (moment_index) |index| index + 1 else self.moments.len;
                var event_limit: usize = 0;
                var object_limit: usize = 0;
                for (self.moments[0..upper]) |moment| {
                    event_limit = @max(event_limit, @as(usize, @intCast(moment.chronicle_resulting_cursor.event_index)));
                    object_limit += moment.committed_object_refs.len;
                }
                for (self.objects[0..@min(object_limit, self.objects.len)]) |object| {
                    const owned = try object.clone(allocator);
                    var owned_pending = true;
                    errdefer if (owned_pending) {
                        var cleanup = owned;
                        cleanup.deinit(allocator);
                    };
                    try vault.objects.append(allocator, owned);
                    owned_pending = false;
                }
                for (self.events[0..@min(event_limit, self.events.len)]) |event| {
                    const owned = try event.clone(allocator);
                    var owned_pending = true;
                    errdefer if (owned_pending) {
                        var cleanup = owned;
                        cleanup.deinit(allocator);
                    };
                    try vault.chronicle_events.append(allocator, owned);
                    owned_pending = false;
                }
                for (self.commits[0..upper]) |commit| {
                    const owned = try commit.clone(allocator);
                    var owned_pending = true;
                    errdefer if (owned_pending) {
                        var cleanup = owned;
                        cleanup.deinit(allocator);
                    };
                    try vault.chronicle_commits.append(allocator, owned);
                    owned_pending = false;
                }
                for (self.moments[0..upper]) |moment| {
                    var backing: std.ArrayList(ObjectEnvelope) = .empty;
                    errdefer deinitEnvelopeList(allocator, &backing);
                    for (moment.committed_object_refs) |ref| {
                        const envelope = self.findObject(ref) orelse return error.ObjectMissing;
                        const owned = try envelope.clone(allocator);
                        var owned_pending = true;
                        errdefer if (owned_pending) {
                            var cleanup = owned;
                            cleanup.deinit(allocator);
                        };
                        try backing.append(allocator, owned);
                        owned_pending = false;
                    }
                    const backing_slice = try backing.toOwnedSlice(allocator);
                    backing = .empty;
                    var backing_slice_pending = true;
                    errdefer if (backing_slice_pending) freeEnvelopeSlice(allocator, backing_slice);
                    try vault.chronicle_commit_backing.append(allocator, backing_slice);
                    backing_slice_pending = false;
                }
                vault.chronicle_cursor = if (upper == 0) Chronicle.Cursor.initial() else self.moments[upper - 1].chronicle_resulting_cursor;
                return vault;
            }

            fn findObject(self: *const @This(), ref: ObjectRef) ?ObjectEnvelope {
                for (self.objects) |envelope| {
                    if (envelope.objectRef().eql(ref)) return envelope;
                }
                return null;
            }
        };

        pub const Snapshot = struct {
            image: *const Image,
            moment_value: Moment,
            moment_index: usize,

            pub fn cursor(self: @This()) Chronicle.Cursor {
                return self.moment_value.chronicle_resulting_cursor;
            }

            pub fn moment(self: @This()) Moment {
                var borrowed = self.moment_value;
                borrowed.owns_memory = false;
                return borrowed;
            }

            pub fn getObject(self: @This(), ref: ObjectRef) !ObjectEnvelope {
                for (self.image.objects) |envelope| {
                    if (envelope.objectRef().eql(ref) and self.refCommittedAtOrBeforeMoment(ref)) return envelope.clone(self.image.allocator);
                }
                return error.ObjectMissing;
            }

            pub fn objectCount(self: @This()) !usize {
                var count: usize = 0;
                for (self.image.moments[0 .. self.moment_index + 1]) |moment_item| count += moment_item.committed_object_refs.len;
                return count;
            }

            pub fn eventCount(self: @This()) !usize {
                return @intCast(self.cursor().event_index);
            }

            pub fn commitCount(self: @This()) !usize {
                return self.moment_index + 1;
            }

            pub fn replayProjection(self: @This(), kind: Chronicle.ProjectionKind) !Chronicle.ProjectionReport {
                var vault = try self.image.materializeVault(self.image.allocator, self.moment_index);
                defer vault.deinit();
                var projection = try Chronicle.Projection.rebuild(&vault, kind);
                defer projection.deinit();
                const refs = try cloneRefSlice(self.image.allocator, projection.report.object_refs_consumed);
                errdefer freeRefSlice(self.image.allocator, refs);
                return Chronicle.ProjectionReport.init(.{
                    .projection_kind = kind,
                    .source_cursor_fingerprint = projection.report.source_cursor_fingerprint,
                    .event_count_consumed = projection.report.event_count_consumed,
                    .object_refs_consumed = refs,
                    .result_summary_fingerprint = projection.report.result_summary_fingerprint,
                    .blockers = projection.report.blockers,
                    .warnings = projection.report.warnings,
                });
            }

            pub fn deinitProjectionReport(self: @This(), report: *Chronicle.ProjectionReport) void {
                freeRefSlice(self.image.allocator, report.object_refs_consumed);
                report.* = undefined;
            }

            pub const RefIndex = struct {
                allocator: std.mem.Allocator,
                source_cursor_fingerprint: u64,
                refs: []const ObjectRef = &.{},
                index_fingerprint: u64,

                pub fn deinit(self: *@This()) void {
                    freeRefSlice(self.allocator, self.refs);
                    self.* = undefined;
                }
            };

            pub const CapsuleIndex = RefIndex;
            pub const ActuationIndex = RefIndex;
            pub const Mailbox = RefIndex;

            pub fn capsuleIndex(self: @This()) !CapsuleIndex {
                return self.refIndex(.capsule_index);
            }

            pub fn actuationIndex(self: @This()) !ActuationIndex {
                return self.refIndex(.actuation_index);
            }

            pub fn inbox(self: @This()) !Mailbox {
                return self.refIndex(.inbox);
            }

            pub fn outbox(self: @This()) !Mailbox {
                return self.refIndex(.outbox);
            }

            fn refIndex(self: @This(), kind: Chronicle.ProjectionKind) !RefIndex {
                var report = try self.replayProjection(kind);
                errdefer self.deinitProjectionReport(&report);
                return .{
                    .allocator = self.image.allocator,
                    .source_cursor_fingerprint = report.source_cursor_fingerprint,
                    .refs = report.object_refs_consumed,
                    .index_fingerprint = report.result_summary_fingerprint,
                };
            }

            fn refCommittedAtOrBeforeMoment(self: @This(), ref: ObjectRef) bool {
                for (self.image.moments[0 .. self.moment_index + 1]) |moment_item| {
                    if (containsRef(moment_item.committed_object_refs, ref)) return true;
                }
                return false;
            }
        };

        pub const Reader = struct {
            allocator: std.mem.Allocator,
            bytes: []const u8,
            limits: Limits = .{},

            pub fn init(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) @This() {
                return .{ .allocator = allocator, .bytes = bytes, .limits = limits };
            }

            pub fn scan(self: @This()) !ScanReport {
                var image = try self.readImage();
                defer image.deinit();
                return .{
                    .header = image.header,
                    .committed_moment_count = image.moments.len,
                    .scanned_segment_count = image.moments.len * 2,
                    .committed_prefix_byte_len = image.committed_prefix_byte_len,
                    .latest_seal = image.latestSeal(),
                    .discarded_tail_byte_len = self.bytes.len - image.committed_prefix_byte_len,
                    .valid = true,
                    .recovered = image.committed_prefix_byte_len != self.bytes.len,
                };
            }

            pub fn validate(self: @This()) ValidationReport {
                const scan_report = self.scan() catch |err| {
                    return .{ .valid = false, .scan = .{}, .blocker = @errorName(err) };
                };
                return .{ .valid = scan_report.discarded_tail_byte_len == 0, .scan = scan_report };
            }

            pub fn recover(self: @This()) !RecoveryReport {
                var image = try self.readImage();
                defer image.deinit();
                const latest_moment = if (image.latestMoment()) |moment| try moment.clone(self.allocator) else null;
                errdefer if (latest_moment) |moment| {
                    var cleanup = moment;
                    cleanup.deinit(self.allocator);
                };
                return .{
                    .latest_moment = latest_moment,
                    .latest_cursor = image.latestCursor(),
                    .recovered_moment_count = image.moments.len,
                    .recovered_commit_count = image.commits.len,
                    .recovered_object_count = image.objects.len,
                    .committed_prefix_byte_len = image.committed_prefix_byte_len,
                    .discarded_tail_byte_len = self.bytes.len - image.committed_prefix_byte_len,
                };
            }

            pub fn readImage(self: @This()) !Image {
                if (self.bytes.len > self.limits.max_archive_bytes) return error.InvalidFrameEncoding;
                var cursor: usize = 0;
                const header = try decodeHeader(self.bytes, &cursor);
                try header.validate();
                var moments: std.ArrayList(Moment) = .empty;
                errdefer deinitMomentList(self.allocator, &moments);
                var seals: std.ArrayList(Seal) = .empty;
                errdefer seals.deinit(self.allocator);
                var commits: std.ArrayList(Chronicle.Commit) = .empty;
                errdefer deinitCommitList(self.allocator, &commits);
                var events: std.ArrayList(Chronicle.Event) = .empty;
                errdefer deinitEventList(self.allocator, &events);
                var objects: std.ArrayList(ObjectEnvelope) = .empty;
                errdefer deinitEnvelopeList(self.allocator, &objects);

                var latest_prefix_len = cursor;
                var parent_seal_fingerprint: ?u64 = null;
                var parent_moment_fingerprint: ?u64 = null;
                var expected_sequence: u64 = 1;
                var expected_cursor = Chronicle.Cursor.initial();

                while (cursor < self.bytes.len) {
                    const moment_segment_start = cursor;
                    const moment_segment = readSegment(self.bytes, &cursor, self.limits) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (moment_segment.header.segment_kind != .moment_data or !moment_segment.header.required) break;
                    var data = decodeMomentData(self.allocator, moment_segment.payload) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    defer data.deinit(self.allocator);
                    data.validate() catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (moment_segment.header.sequence_number != expected_sequence or
                        data.moment.sequence_number != expected_sequence or
                        data.moment.parent_moment_fingerprint != parent_moment_fingerprint or
                        data.moment.parent_seal_fingerprint != parent_seal_fingerprint or
                        data.moment.chronicle_parent_cursor.cursor_fingerprint != expected_cursor.cursor_fingerprint)
                    {
                        break;
                    }
                    const seal_segment = readSegment(self.bytes, &cursor, self.limits) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (seal_segment.header.segment_kind != .moment_seal or !seal_segment.header.required) break;
                    if (seal_segment.header.sequence_number != data.moment.sequence_number) {
                        cursor = moment_segment_start;
                        break;
                    }
                    const seal = decodeSeal(seal_segment.payload) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    seal.validate() catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (seal.sequence_number != data.moment.sequence_number or
                        seal.parent_seal_fingerprint != parent_seal_fingerprint or
                        seal.moment_fingerprint != data.moment.moment_fingerprint or
                        seal.moment_data_segment_fingerprint != moment_segment.header.payload_fingerprint or
                        seal.chronicle_resulting_cursor_fingerprint != data.moment.chronicle_resulting_cursor.cursor_fingerprint or
                        seal.committed_prefix_byte_len != cursor)
                    {
                        cursor = moment_segment_start;
                        break;
                    }
                    rejectConflictingObjectBytesAcross(objects.items, data.objects) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        cursor = moment_segment_start;
                        break;
                    };

                    const owned_moment = try data.moment.clone(self.allocator);
                    var owned_moment_pending = true;
                    errdefer if (owned_moment_pending) {
                        var cleanup = owned_moment;
                        cleanup.deinit(self.allocator);
                    };
                    const owned_commit = try data.commit.clone(self.allocator);
                    var owned_commit_pending = true;
                    errdefer if (owned_commit_pending) {
                        var cleanup = owned_commit;
                        cleanup.deinit(self.allocator);
                    };
                    try moments.append(self.allocator, owned_moment);
                    owned_moment_pending = false;
                    try seals.append(self.allocator, seal);
                    try commits.append(self.allocator, owned_commit);
                    owned_commit_pending = false;
                    for (data.events) |event| {
                        const owned = try event.clone(self.allocator);
                        var owned_pending = true;
                        errdefer if (owned_pending) {
                            var cleanup = owned;
                            cleanup.deinit(self.allocator);
                        };
                        try events.append(self.allocator, owned);
                        owned_pending = false;
                    }
                    for (data.objects) |object| {
                        const owned = try object.clone(self.allocator);
                        var owned_pending = true;
                        errdefer if (owned_pending) {
                            var cleanup = owned;
                            cleanup.deinit(self.allocator);
                        };
                        try objects.append(self.allocator, owned);
                        owned_pending = false;
                    }
                    parent_seal_fingerprint = seal.seal_fingerprint;
                    parent_moment_fingerprint = data.moment.moment_fingerprint;
                    expected_cursor = data.moment.chronicle_resulting_cursor;
                    expected_sequence += 1;
                    latest_prefix_len = cursor;
                }

                const moments_slice = try moments.toOwnedSlice(self.allocator);
                moments = .empty;
                errdefer {
                    for (moments_slice) |*moment| moment.deinit(self.allocator);
                    self.allocator.free(moments_slice);
                }
                const seals_slice = try seals.toOwnedSlice(self.allocator);
                seals = .empty;
                errdefer self.allocator.free(seals_slice);
                const commits_slice = try commits.toOwnedSlice(self.allocator);
                commits = .empty;
                errdefer {
                    for (commits_slice) |*commit| commit.deinit(self.allocator);
                    self.allocator.free(commits_slice);
                }
                const events_slice = try events.toOwnedSlice(self.allocator);
                events = .empty;
                errdefer freeEventSlice(self.allocator, events_slice);
                const objects_slice = try objects.toOwnedSlice(self.allocator);
                objects = .empty;
                errdefer freeEnvelopeSlice(self.allocator, objects_slice);
                var image = Image{
                    .allocator = self.allocator,
                    .header = header,
                    .moments = moments_slice,
                    .seals = seals_slice,
                    .commits = commits_slice,
                    .events = events_slice,
                    .objects = objects_slice,
                    .committed_prefix_byte_len = latest_prefix_len,
                    .owns_memory = true,
                };
                image.image_fingerprint = fingerprintImage(image);
                return image;
            }
        };

        pub const Writer = struct {
            allocator: std.mem.Allocator,
            bytes: std.ArrayList(u8) = .empty,
            limits: Limits = .{},
            header_written: bool = false,

            pub fn init(allocator: std.mem.Allocator, limits: Limits) @This() {
                return .{ .allocator = allocator, .limits = limits };
            }

            pub fn deinit(self: *@This()) void {
                self.bytes.deinit(self.allocator);
                self.* = undefined;
            }

            pub fn writeHeader(self: *@This(), header: Header) !void {
                if (self.header_written or self.bytes.items.len != 0) return error.InvalidFrameEncoding;
                try header.validate();
                try encodeHeader(&self.bytes, self.allocator, header);
                self.header_written = true;
            }

            pub fn append(self: *@This(), batch: AppendBatch, parent_moment: ?Moment, parent_seal: ?Seal) !Seal {
                if (!self.header_written) try self.writeHeader(Header.init(.{}));
                try batch.validate();
                try self.rejectObjectConflicts(batch.objects);
                var event_fingerprints: std.ArrayList(u64) = .empty;
                defer event_fingerprints.deinit(self.allocator);
                for (batch.events) |event| try event_fingerprints.append(self.allocator, event.event_fingerprint);
                const committed_refs = try cloneRefSlice(self.allocator, batch.commit.committed_object_refs);
                defer freeRefSlice(self.allocator, committed_refs);
                const dependency_refs = try collectDependencyRefs(self.allocator, batch.objects);
                defer freeRefSlice(self.allocator, dependency_refs);
                const moment = Moment.init(.{
                    .sequence_number = if (parent_moment) |m| m.sequence_number + 1 else 1,
                    .parent_moment_fingerprint = if (parent_moment) |m| m.moment_fingerprint else null,
                    .parent_seal_fingerprint = if (parent_seal) |s| s.seal_fingerprint else null,
                    .chronicle_parent_cursor = batch.parent_cursor,
                    .chronicle_resulting_cursor = batch.parent_cursor.advance(event_fingerprints.items, batch.commit.committed_object_refs.len, 1),
                    .chronicle_commit_ref = CommitRef.fromCommit(batch.commit),
                    .committed_event_refs = event_fingerprints.items,
                    .committed_object_refs = committed_refs,
                    .root_object_refs = committed_refs,
                    .capsule_refs = batch.commit.capsule_refs,
                    .actuation_refs = batch.commit.actuation_refs,
                    .bundle_refs = batch.commit.bundle_refs,
                    .dependency_refs = dependency_refs,
                    .diagnostic_metadata_bytes = batch.diagnostic_metadata_bytes,
                });
                try moment.validate();
                var data = MomentData{
                    .moment = moment,
                    .commit = batch.commit,
                    .events = batch.events,
                    .objects = batch.objects,
                };
                try data.validate();
                var payload: std.ArrayList(u8) = .empty;
                defer payload.deinit(self.allocator);
                try encodeMomentData(&payload, self.allocator, data);
                try self.limits.validatePayloadLen(payload.items.len);
                const data_header = SegmentHeader.init(.{
                    .segment_kind = .moment_data,
                    .sequence_number = moment.sequence_number,
                    .payload = payload.items,
                });
                const data_segment_start = self.bytes.items.len;
                var append_pending = true;
                errdefer if (append_pending) self.bytes.shrinkRetainingCapacity(data_segment_start);
                try encodeSegmentHeader(&self.bytes, self.allocator, data_header);
                try self.bytes.appendSlice(self.allocator, payload.items);
                const committed_prefix_len = self.bytes.items.len + segmentHeaderEncodedLen() + sealEncodedLen(parent_seal != null);
                const seal = Seal.init(.{
                    .sequence_number = moment.sequence_number,
                    .parent_seal_fingerprint = if (parent_seal) |s| s.seal_fingerprint else null,
                    .moment_fingerprint = moment.moment_fingerprint,
                    .moment_data_segment_fingerprint = data_header.payload_fingerprint,
                    .chronicle_resulting_cursor_fingerprint = moment.chronicle_resulting_cursor.cursor_fingerprint,
                    .committed_prefix_byte_len = committed_prefix_len,
                });
                var seal_payload: std.ArrayList(u8) = .empty;
                defer seal_payload.deinit(self.allocator);
                try encodeSeal(&seal_payload, self.allocator, seal);
                const seal_header = SegmentHeader.init(.{
                    .segment_kind = .moment_seal,
                    .sequence_number = moment.sequence_number,
                    .payload = seal_payload.items,
                });
                if (data_segment_start >= self.bytes.items.len) return error.InvalidFrameEncoding;
                try encodeSegmentHeader(&self.bytes, self.allocator, seal_header);
                try self.bytes.appendSlice(self.allocator, seal_payload.items);
                append_pending = false;
                return seal;
            }

            fn rejectObjectConflicts(self: *@This(), objects: []const ObjectEnvelope) !void {
                var reader = Reader.init(self.allocator, self.bytes.items, self.limits);
                var image = try reader.readImage();
                defer image.deinit();
                try rejectConflictingObjectBytesAcross(image.objects, objects);
            }

            pub fn toOwnedBytes(self: *@This()) ![]u8 {
                return self.bytes.toOwnedSlice(self.allocator);
            }
        };

        pub const Memory = struct {
            allocator: std.mem.Allocator,
            bytes: std.ArrayList(u8) = .empty,
            image: Image,
            closed: bool = false,

            pub const OpenOptions = struct {};
            pub const BeginOptions = struct {};

            pub const WriteTransaction = struct {
                archive: *Memory,
                parent_cursor: Chronicle.Cursor,
                staged_objects: std.ArrayList(ObjectEnvelope) = .empty,
                staged_events: std.ArrayList(Chronicle.Event) = .empty,
                committed: bool = false,

                pub fn putObject(self: *@This(), envelope: ObjectEnvelope) !ObjectRef {
                    try envelope.validate();
                    const ref = envelope.objectRef();
                    for (self.staged_objects.items) |object| {
                        if (!object.objectRef().eql(ref)) continue;
                        if (object.envelope_fingerprint != envelope.envelope_fingerprint) return error.DuplicateBinding;
                        return object.objectRef();
                    }
                    const owned = try envelope.clone(self.archive.allocator);
                    errdefer {
                        var cleanup = owned;
                        cleanup.deinit(self.archive.allocator);
                    }
                    try self.staged_objects.append(self.archive.allocator, owned);
                    return self.staged_objects.items[self.staged_objects.items.len - 1].objectRef();
                }

                pub fn addEvent(self: *@This(), event: Chronicle.Event) !void {
                    try event.validate();
                    const owned = try event.clone(self.archive.allocator);
                    errdefer {
                        var cleanup = owned;
                        cleanup.deinit(self.archive.allocator);
                    }
                    try self.staged_events.append(self.archive.allocator, owned);
                }

                pub fn commit(self: *@This()) !Moment {
                    if (self.committed) return error.InvalidFrameEncoding;
                    const latest = self.archive.currentCursor();
                    if (latest.cursor_fingerprint != self.parent_cursor.cursor_fingerprint) return error.StaleProjection;
                    var object_refs: std.ArrayList(ObjectRef) = .empty;
                    defer object_refs.deinit(self.archive.allocator);
                    var capsule_refs: std.ArrayList(ObjectRef) = .empty;
                    defer capsule_refs.deinit(self.archive.allocator);
                    var actuation_refs: std.ArrayList(ObjectRef) = .empty;
                    defer actuation_refs.deinit(self.archive.allocator);
                    var bundle_refs: std.ArrayList(ObjectRef) = .empty;
                    defer bundle_refs.deinit(self.archive.allocator);
                    for (self.staged_objects.items) |object| {
                        const ref = object.objectRef();
                        try object_refs.append(self.archive.allocator, ref);
                        switch (ref.kind) {
                            .capsule_image => try capsule_refs.append(self.archive.allocator, ref),
                            .actuation_intent,
                            .actuation_envelope,
                            .actuation_decision,
                            .actuation_commit,
                            .actuation_response,
                            .actuation_receipt,
                            .actuation_journal,
                            .actuation_idempotency_key,
                            => try actuation_refs.append(self.archive.allocator, ref),
                            .bundle => try bundle_refs.append(self.archive.allocator, ref),
                            else => {},
                        }
                    }
                    const tx_fingerprint = transactionFingerprint(latest, object_refs.items);
                    var normalized_events: std.ArrayList(Chronicle.Event) = .empty;
                    defer {
                        for (normalized_events.items) |*event| event.deinit(self.archive.allocator);
                        normalized_events.deinit(self.archive.allocator);
                    }
                    var event_fingerprints: std.ArrayList(u64) = .empty;
                    defer event_fingerprints.deinit(self.archive.allocator);
                    for (self.staged_objects.items) |object| {
                        const ref = object.objectRef();
                        const refs = [_]ObjectRef{ref};
                        const event = Chronicle.Event.init(.{
                            .kind = .object_committed,
                            .transaction_fingerprint = tx_fingerprint,
                            .object_refs = &refs,
                            .target_ref = ref,
                        });
                        const owned = try event.clone(self.archive.allocator);
                        var owned_pending = true;
                        errdefer if (owned_pending) {
                            var cleanup = owned;
                            cleanup.deinit(self.archive.allocator);
                        };
                        try normalized_events.append(self.archive.allocator, owned);
                        owned_pending = false;
                        try event_fingerprints.append(self.archive.allocator, owned.event_fingerprint);
                    }
                    for (self.staged_events.items) |event| {
                        if (event.kind == .object_committed) continue;
                        const normalized = bindEventTransaction(event, tx_fingerprint);
                        const owned = try normalized.clone(self.archive.allocator);
                        var owned_pending = true;
                        errdefer if (owned_pending) {
                            var cleanup = owned;
                            cleanup.deinit(self.archive.allocator);
                        };
                        try normalized_events.append(self.archive.allocator, owned);
                        owned_pending = false;
                        try event_fingerprints.append(self.archive.allocator, owned.event_fingerprint);
                    }
                    const resulting_cursor = latest.advance(event_fingerprints.items, object_refs.items.len, 1);
                    const commit_value = Chronicle.Commit.init(.{
                        .transaction_fingerprint = tx_fingerprint,
                        .parent_cursor_fingerprint = latest.cursor_fingerprint,
                        .resulting_cursor_fingerprint = resulting_cursor.cursor_fingerprint,
                        .committed_object_refs = object_refs.items,
                        .committed_event_fingerprints = event_fingerprints.items,
                        .bundle_refs = bundle_refs.items,
                        .capsule_refs = capsule_refs.items,
                        .actuation_refs = actuation_refs.items,
                    });
                    const batch = AppendBatch.init(.{
                        .parent_cursor = latest,
                        .commit = commit_value,
                        .events = normalized_events.items,
                        .objects = self.staged_objects.items,
                    });
                    const moment = try self.archive.appendBatch(batch);
                    self.clearStaged();
                    self.committed = true;
                    return moment;
                }

                pub fn deinit(self: *@This()) void {
                    if (!self.committed) self.clearStaged();
                    self.staged_objects.deinit(self.archive.allocator);
                    self.staged_events.deinit(self.archive.allocator);
                    self.* = undefined;
                }

                fn clearStaged(self: *@This()) void {
                    for (self.staged_objects.items) |*object| object.deinit(self.archive.allocator);
                    for (self.staged_events.items) |*event| event.deinit(self.archive.allocator);
                    self.staged_objects.clearRetainingCapacity();
                    self.staged_events.clearRetainingCapacity();
                }
            };

            pub fn capabilities() Capabilities {
                return .{ .warnings = &.{"host must retain archive bytes for process restart persistence"} };
            }

            pub fn safetyReport() SafetyReport {
                return SafetyReport.init(.{});
            }

            pub fn open(allocator: std.mem.Allocator, options: OpenOptions) !@This() {
                _ = options;
                var writer = Writer.init(allocator, .{});
                defer writer.deinit();
                try writer.writeHeader(Header.init(.{}));
                const bytes = try writer.toOwnedBytes();
                errdefer allocator.free(bytes);
                var reader = Reader.init(allocator, bytes, .{});
                const image = try reader.readImage();
                var list: std.ArrayList(u8) = .empty;
                errdefer list.deinit(allocator);
                try list.appendSlice(allocator, bytes);
                allocator.free(bytes);
                return .{ .allocator = allocator, .bytes = list, .image = image };
            }

            pub fn deinit(self: *@This()) void {
                self.bytes.deinit(self.allocator);
                self.image.deinit();
                self.* = undefined;
            }

            pub fn close(self: *@This()) !void {
                self.closed = true;
            }

            pub fn begin(self: *@This(), parent_cursor: Chronicle.Cursor, options: BeginOptions) !WriteTransaction {
                _ = options;
                if (self.closed) return error.InvalidFrameEncoding;
                if (parent_cursor.cursor_fingerprint != self.currentCursor().cursor_fingerprint) return error.StaleProjection;
                return .{ .archive = self, .parent_cursor = parent_cursor };
            }

            pub fn appendBatch(self: *@This(), batch: AppendBatch) !Moment {
                if (self.closed) return error.InvalidFrameEncoding;
                if (batch.parent_cursor.cursor_fingerprint != self.currentCursor().cursor_fingerprint) return error.StaleProjection;
                var writer = Writer.init(self.allocator, .{});
                defer writer.deinit();
                try writer.bytes.appendSlice(self.allocator, self.bytes.items);
                writer.header_written = true;
                _ = try writer.append(batch, self.image.latestMoment(), self.image.latestSeal());
                var reader = Reader.init(self.allocator, writer.bytes.items, .{});
                var next_image = try reader.readImage();
                var next_image_owned = true;
                errdefer if (next_image_owned) next_image.deinit();
                var next_bytes: std.ArrayList(u8) = .empty;
                errdefer next_bytes.deinit(self.allocator);
                try next_bytes.appendSlice(self.allocator, writer.bytes.items);
                self.bytes.deinit(self.allocator);
                self.bytes = next_bytes;
                next_bytes = .empty;
                self.image.deinit();
                self.image = next_image;
                next_image_owned = false;
                return self.image.latestMoment() orelse error.ObjectMissing;
            }

            pub fn bytesView(self: @This()) []const u8 {
                return self.bytes.items;
            }

            pub fn recover(self: *@This()) !RecoveryReport {
                var reader = Reader.init(self.allocator, self.bytes.items, .{});
                var report = try reader.recover();
                errdefer report.deinit(self.allocator);
                if (report.committed_prefix_byte_len < self.bytes.items.len) {
                    self.bytes.shrinkRetainingCapacity(report.committed_prefix_byte_len);
                }
                try self.refreshImage();
                return report;
            }

            pub fn replay(self: *@This()) !ReplayReport {
                return self.image.replay(.{});
            }

            pub fn latestMoment(self: @This()) !Moment {
                return self.image.latestMoment() orelse error.ObjectMissing;
            }

            pub fn openMoment(self: *const @This(), moment_ref: Moment) !Snapshot {
                return self.image.openSnapshot(moment_ref);
            }

            pub fn getObject(self: @This(), ref: ObjectRef) !ObjectEnvelope {
                for (self.image.objects) |envelope| {
                    if (envelope.objectRef().eql(ref)) return envelope.clone(self.allocator);
                }
                return error.ObjectMissing;
            }

            pub fn hasObject(self: @This(), ref: ObjectRef) bool {
                for (self.image.objects) |envelope| {
                    if (envelope.objectRef().eql(ref)) return true;
                }
                return false;
            }

            pub fn readCommit(self: @This(), ref: CommitRef) !Chronicle.Commit {
                for (self.image.commits) |commit| {
                    if (commitRefMatchesCommit(ref, commit)) return commit.clone(self.allocator);
                }
                return error.ObjectMissing;
            }

            pub fn readEvents(self: @This(), commit_ref: CommitRef) ![]const Chronicle.Event {
                var start: usize = 0;
                for (self.image.commits) |commit| {
                    const end = start + commit.committed_event_fingerprints.len;
                    if (end > self.image.events.len) return error.InvalidFrameEncoding;
                    if (commitRefMatchesCommit(commit_ref, commit)) return self.image.events[start..end];
                    start = end;
                }
                return error.ObjectMissing;
            }

            pub fn assertFreshIdempotencyAllowed(self: @This(), key_ref: ObjectRef) !void {
                try key_ref.validate();
                if (key_ref.kind != .actuation_idempotency_key) return error.InvalidFrameEncoding;
                for (self.image.objects) |envelope| {
                    const existing = envelope.objectRef();
                    if (existing.kind == .actuation_idempotency_key and existing.object_fingerprint == key_ref.object_fingerprint) return error.DuplicateBinding;
                }
                var vault = try self.image.materializeVault(self.allocator, if (self.image.moments.len == 0) null else self.image.moments.len - 1);
                defer vault.deinit();
                var registry = try Chronicle.IdempotencyRegistry.rebuild(&vault);
                defer registry.deinit(registry.allocator);
                try registry.assertFreshCommitAllowed(key_ref);
            }

            pub fn reopenFrom(source: *const @This(), allocator: std.mem.Allocator) !@This() {
                var bytes: std.ArrayList(u8) = .empty;
                errdefer bytes.deinit(allocator);
                try bytes.appendSlice(allocator, source.bytes.items);
                var reader = Reader.init(allocator, bytes.items, .{});
                const image = try reader.readImage();
                errdefer image.deinit();
                return .{ .allocator = allocator, .bytes = bytes, .image = image };
            }

            fn currentCursor(self: @This()) Chronicle.Cursor {
                return self.image.latestCursor();
            }

            fn refreshImage(self: *@This()) !void {
                var reader = Reader.init(self.allocator, self.bytes.items, .{});
                const image = try reader.readImage();
                self.image.deinit();
                self.image = image;
            }
        };

        pub const Conformance = struct {
            pub const Report = struct {
                moment_count: usize = 0,
                object_count: usize = 0,
                replay_mismatch_count: usize = 0,
                historical_snapshot_checked: bool = false,
                reopen_checked: bool = false,
                idempotency_checked: bool = false,

                pub fn validate(self: @This()) !void {
                    if (self.moment_count == 0 or self.object_count == 0) return error.InvalidFrameEncoding;
                    if (self.replay_mismatch_count != 0) return error.InvalidFrameEncoding;
                    if (!self.historical_snapshot_checked or !self.reopen_checked or !self.idempotency_checked) return error.InvalidFrameEncoding;
                }
            };

            pub fn requireMemorySurface() void {
                if (!@hasDecl(Self.Memory, "open") or !@hasDecl(Self.Memory, "bytesView")) @compileError("Archive.Memory byte surface missing");
            }

            pub fn requireCanonicalOptionalTags() !void {
                var absent_cursor: usize = 0;
                if ((try readOptionalU64(&.{0}, &absent_cursor)) != null) return error.InvalidFrameEncoding;
                var u64_cursor: usize = 0;
                if (readOptionalU64(&.{2}, &u64_cursor)) |_| {
                    return error.InvalidFrameEncoding;
                } else |err| switch (err) {
                    error.InvalidFrameEncoding => {},
                }
                var ref_cursor: usize = 0;
                if (readOptionalRef(std.heap.page_allocator, &.{2}, &ref_cursor)) |_| {
                    return error.InvalidFrameEncoding;
                } else |err| switch (err) {
                    error.InvalidFrameEncoding => {},
                    else => return err,
                }
            }

            pub fn runMemory(allocator: std.mem.Allocator) !Report {
                var archive = try Memory.open(allocator, .{});
                defer archive.deinit();
                const first = try commitMemoryObject(&archive, .capsule_manifest, "conformance-capsule", "conformance-capsule");
                const second = try commitMemoryObject(&archive, .capsule_manifest, "conformance-manifest", "conformance-manifest");
                var first_snapshot = try archive.openMoment(first.moment);
                var first_object = try first_snapshot.getObject(first.ref);
                defer first_object.deinit(allocator);
                if (first_snapshot.getObject(second.ref)) |_| return error.InvalidFrameEncoding else |_| {}
                var reopened = try Memory.reopenFrom(&archive, allocator);
                defer reopened.deinit();
                var recovery = try reopened.recover();
                defer recovery.deinit(allocator);
                var replay_report = try reopened.replay();
                defer replay_report.deinit(allocator);
                try replay_report.validate();
                const key_commit = try commitMemoryObject(&reopened, .actuation_idempotency_key, "idem-key", "idem-key");
                var reopened_again = try Memory.reopenFrom(&reopened, allocator);
                defer reopened_again.deinit();
                if (reopened_again.assertFreshIdempotencyAllowed(key_commit.ref)) |_| return error.InvalidFrameEncoding else |err| switch (err) {
                    error.DuplicateBinding => {},
                    else => return err,
                }
                return .{
                    .moment_count = reopened_again.image.moments.len,
                    .object_count = reopened_again.image.objects.len,
                    .replay_mismatch_count = replay_report.mismatch_count,
                    .historical_snapshot_checked = true,
                    .reopen_checked = true,
                    .idempotency_checked = true,
                };
            }
        };

        const CommitResult = struct {
            moment: Moment,
            ref: ObjectRef,
        };

        fn commitMemoryObject(archive: *Memory, kind: Continuity.ObjectKind, payload: []const u8, label: []const u8) !CommitResult {
            const envelope = ObjectEnvelope.init(.{ .kind = kind, .payload_bytes = payload, .label = label });
            var tx = try archive.begin(archive.currentCursor(), .{});
            defer tx.deinit();
            const ref = try tx.putObject(envelope);
            const refs = [_]ObjectRef{ref};
            try tx.addEvent(Chronicle.Event.init(.{ .kind = .object_committed, .object_refs = &refs }));
            return .{ .moment = try tx.commit(), .ref = ref };
        }

        fn encodeHeader(out: *std.ArrayList(u8), allocator: std.mem.Allocator, header: Header) !void {
            try out.appendSlice(allocator, &header.magic);
            try writeU32(out, allocator, header.header_format_version);
            try writeU32(out, allocator, header.archive_format_version);
            try writeU32(out, allocator, header.archive_fingerprint_version);
            try writeU64(out, allocator, header.byte_order_marker);
            try writeU32(out, allocator, header.compatible_chronicle_event_format_version);
            try writeU32(out, allocator, header.compatible_chronicle_commit_format_version);
            try writeU32(out, allocator, header.compatible_object_envelope_format_version);
            try writeU64(out, allocator, header.genesis_cursor_fingerprint);
            try writeU64(out, allocator, header.required_feature_flags);
            try writeU64(out, allocator, header.optional_feature_flags);
            try writeU64(out, allocator, header.archive_profile_fingerprint);
            try writeU64(out, allocator, header.header_fingerprint);
        }

        fn decodeHeader(bytes: []const u8, cursor: *usize) !Header {
            var header = Header{ .archive_profile_fingerprint = 1, .header_fingerprint = 1 };
            try readExact(bytes, cursor, &header.magic);
            header.header_format_version = try readU32(bytes, cursor);
            header.archive_format_version = try readU32(bytes, cursor);
            header.archive_fingerprint_version = try readU32(bytes, cursor);
            header.byte_order_marker = try readU64(bytes, cursor);
            header.compatible_chronicle_event_format_version = try readU32(bytes, cursor);
            header.compatible_chronicle_commit_format_version = try readU32(bytes, cursor);
            header.compatible_object_envelope_format_version = try readU32(bytes, cursor);
            header.genesis_cursor_fingerprint = try readU64(bytes, cursor);
            header.required_feature_flags = try readU64(bytes, cursor);
            header.optional_feature_flags = try readU64(bytes, cursor);
            header.archive_profile_fingerprint = try readU64(bytes, cursor);
            header.header_fingerprint = try readU64(bytes, cursor);
            return header;
        }

        fn encodeSegmentHeader(out: *std.ArrayList(u8), allocator: std.mem.Allocator, header: SegmentHeader) !void {
            try out.appendSlice(allocator, &header.magic);
            try writeU32(out, allocator, header.segment_format_version);
            try writeU8(out, allocator, @intFromEnum(header.segment_kind));
            try writeU8(out, allocator, if (header.required) 1 else 0);
            try writeU64(out, allocator, header.sequence_number);
            try writeU64(out, allocator, header.payload_byte_len);
            try writeU64(out, allocator, header.payload_fingerprint);
            try writeU64(out, allocator, header.segment_header_fingerprint);
        }

        fn decodeSegmentHeader(bytes: []const u8, cursor: *usize) !SegmentHeader {
            var header = SegmentHeader{
                .segment_kind = .optional_extension,
                .sequence_number = 1,
                .payload_byte_len = 0,
                .payload_fingerprint = 1,
                .segment_header_fingerprint = 1,
            };
            try readExact(bytes, cursor, &header.magic);
            header.segment_format_version = try readU32(bytes, cursor);
            header.segment_kind = try enumFromByte(SegmentKind, try readU8(bytes, cursor));
            header.required = switch (try readU8(bytes, cursor)) {
                0 => false,
                1 => true,
                else => return error.InvalidFrameEncoding,
            };
            header.sequence_number = try readU64(bytes, cursor);
            header.payload_byte_len = try readU64(bytes, cursor);
            header.payload_fingerprint = try readU64(bytes, cursor);
            header.segment_header_fingerprint = try readU64(bytes, cursor);
            return header;
        }

        const Segment = struct {
            header: SegmentHeader,
            payload: []const u8,
        };

        fn readSegment(bytes: []const u8, cursor: *usize, limits: Limits) !Segment {
            const header = try decodeSegmentHeader(bytes, cursor);
            const len = try u64ToUsize(header.payload_byte_len);
            try limits.validatePayloadLen(len);
            if (bytes.len - cursor.* < len) return error.InvalidFrameEncoding;
            const payload = bytes[cursor.* .. cursor.* + len];
            cursor.* += len;
            try header.validate(payload);
            return .{ .header = header, .payload = payload };
        }

        fn encodeMomentData(out: *std.ArrayList(u8), allocator: std.mem.Allocator, data: MomentData) !void {
            try encodeMoment(out, allocator, data.moment);
            try encodeCommit(out, allocator, data.commit);
            try writeU64(out, allocator, data.events.len);
            for (data.events) |event| try encodeEvent(out, allocator, event);
            try writeU64(out, allocator, data.objects.len);
            for (data.objects) |object| try encodeEnvelope(out, allocator, object);
        }

        fn decodeMomentData(allocator: std.mem.Allocator, bytes: []const u8) !MomentData {
            var cursor: usize = 0;
            var moment = try decodeMoment(allocator, bytes, &cursor);
            errdefer moment.deinit(allocator);
            var commit = try decodeCommit(allocator, bytes, &cursor);
            errdefer commit.deinit(allocator);
            const event_count = try readU64AsUsize(bytes, &cursor);
            var events = try allocator.alloc(Chronicle.Event, event_count);
            errdefer allocator.free(events);
            var event_init: usize = 0;
            errdefer for (events[0..event_init]) |*event| event.deinit(allocator);
            for (events) |*event| {
                event.* = try decodeEvent(allocator, bytes, &cursor);
                event_init += 1;
            }
            const object_count = try readU64AsUsize(bytes, &cursor);
            var objects = try allocator.alloc(ObjectEnvelope, object_count);
            errdefer allocator.free(objects);
            var object_init: usize = 0;
            errdefer for (objects[0..object_init]) |*object| object.deinit(allocator);
            for (objects) |*object| {
                object.* = try decodeEnvelope(allocator, bytes, &cursor);
                object_init += 1;
            }
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return .{ .moment = moment, .commit = commit, .events = events, .objects = objects, .owns_memory = true };
        }

        fn encodeMoment(out: *std.ArrayList(u8), allocator: std.mem.Allocator, moment: Moment) !void {
            try writeU32(out, allocator, moment.moment_format_version);
            try writeU32(out, allocator, moment.moment_fingerprint_version);
            try writeU64(out, allocator, moment.moment_fingerprint);
            try writeU64(out, allocator, moment.sequence_number);
            try writeOptionalU64(out, allocator, moment.parent_moment_fingerprint);
            try writeOptionalU64(out, allocator, moment.parent_seal_fingerprint);
            try encodeCursor(out, allocator, moment.chronicle_parent_cursor);
            try encodeCursor(out, allocator, moment.chronicle_resulting_cursor);
            try encodeCommitRef(out, allocator, moment.chronicle_commit_ref);
            try writeU64Slice(out, allocator, moment.committed_event_refs);
            try writeRefSlice(out, allocator, moment.committed_object_refs);
            try writeRefSlice(out, allocator, moment.root_object_refs);
            try writeRefSlice(out, allocator, moment.capsule_refs);
            try writeRefSlice(out, allocator, moment.actuation_refs);
            try writeRefSlice(out, allocator, moment.bundle_refs);
            try writeRefSlice(out, allocator, moment.admission_refs);
            try writeRefSlice(out, allocator, moment.environment_certificate_refs);
            try writeRefSlice(out, allocator, moment.permit_receipt_refs);
            try writeRefSlice(out, allocator, moment.link_assembly_refs);
            try writeRefSlice(out, allocator, moment.fabric_receipt_refs);
            try writeRefSlice(out, allocator, moment.guest_conformance_refs);
            try writeRefSlice(out, allocator, moment.dependency_refs);
            try writeU64Slice(out, allocator, moment.projection_summary_fingerprints);
            try writeOptionalU64(out, allocator, moment.idempotency_registry_summary_fingerprint);
            try writeBytes(out, allocator, moment.diagnostic_metadata_bytes);
        }

        fn decodeMoment(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Moment {
            var moment = Moment{
                .moment_format_version = try readU32(bytes, cursor),
                .moment_fingerprint_version = try readU32(bytes, cursor),
                .moment_fingerprint = try readU64(bytes, cursor),
                .sequence_number = try readU64(bytes, cursor),
                .parent_moment_fingerprint = try readOptionalU64(bytes, cursor),
                .parent_seal_fingerprint = try readOptionalU64(bytes, cursor),
                .chronicle_parent_cursor = try decodeCursor(bytes, cursor),
                .chronicle_resulting_cursor = try decodeCursor(bytes, cursor),
                .chronicle_commit_ref = try decodeCommitRef(bytes, cursor),
                .owns_memory = true,
            };
            moment.committed_event_refs = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(moment.committed_event_refs);
            moment.committed_object_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.committed_object_refs);
            moment.root_object_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.root_object_refs);
            moment.capsule_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.capsule_refs);
            moment.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.actuation_refs);
            moment.bundle_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.bundle_refs);
            moment.admission_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.admission_refs);
            moment.environment_certificate_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.environment_certificate_refs);
            moment.permit_receipt_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.permit_receipt_refs);
            moment.link_assembly_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.link_assembly_refs);
            moment.fabric_receipt_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.fabric_receipt_refs);
            moment.guest_conformance_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.guest_conformance_refs);
            moment.dependency_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, moment.dependency_refs);
            moment.projection_summary_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(moment.projection_summary_fingerprints);
            moment.idempotency_registry_summary_fingerprint = try readOptionalU64(bytes, cursor);
            moment.diagnostic_metadata_bytes = try readBytesOwned(allocator, bytes, cursor);
            return moment;
        }

        fn encodeSeal(out: *std.ArrayList(u8), allocator: std.mem.Allocator, seal: Seal) !void {
            try writeU32(out, allocator, seal.seal_format_version);
            try writeU32(out, allocator, seal.seal_fingerprint_version);
            try writeU64(out, allocator, seal.seal_fingerprint);
            try writeU64(out, allocator, seal.sequence_number);
            try writeOptionalU64(out, allocator, seal.parent_seal_fingerprint);
            try writeU64(out, allocator, seal.moment_fingerprint);
            try writeU64(out, allocator, seal.moment_data_segment_fingerprint);
            try writeU64(out, allocator, seal.chronicle_resulting_cursor_fingerprint);
            try writeU64(out, allocator, seal.committed_prefix_byte_len);
            try writeU64(out, allocator, seal.sealed_prefix_fingerprint);
        }

        fn decodeSeal(bytes: []const u8) !Seal {
            var cursor: usize = 0;
            const seal = Seal{
                .seal_format_version = try readU32(bytes, &cursor),
                .seal_fingerprint_version = try readU32(bytes, &cursor),
                .seal_fingerprint = try readU64(bytes, &cursor),
                .sequence_number = try readU64(bytes, &cursor),
                .parent_seal_fingerprint = try readOptionalU64(bytes, &cursor),
                .moment_fingerprint = try readU64(bytes, &cursor),
                .moment_data_segment_fingerprint = try readU64(bytes, &cursor),
                .chronicle_resulting_cursor_fingerprint = try readU64(bytes, &cursor),
                .committed_prefix_byte_len = try readU64(bytes, &cursor),
                .sealed_prefix_fingerprint = try readU64(bytes, &cursor),
            };
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            return seal;
        }

        fn encodeCursor(out: *std.ArrayList(u8), allocator: std.mem.Allocator, cursor: Chronicle.Cursor) !void {
            try writeU32(out, allocator, cursor.cursor_fingerprint_version);
            try writeU64(out, allocator, cursor.cursor_fingerprint);
            try writeU64(out, allocator, cursor.event_index);
            try writeOptionalU64(out, allocator, cursor.last_event_fingerprint);
            try writeU64(out, allocator, cursor.cumulative_prefix_fingerprint);
            try writeU64(out, allocator, cursor.committed_object_count);
            try writeU64(out, allocator, cursor.committed_transaction_count);
            try writeBytes(out, allocator, cursor.metadata_bytes);
        }

        fn decodeCursor(bytes: []const u8, cursor: *usize) !Chronicle.Cursor {
            return .{
                .cursor_fingerprint_version = try readU32(bytes, cursor),
                .cursor_fingerprint = try readU64(bytes, cursor),
                .event_index = try readU64(bytes, cursor),
                .last_event_fingerprint = try readOptionalU64(bytes, cursor),
                .cumulative_prefix_fingerprint = try readU64(bytes, cursor),
                .committed_object_count = try readU64(bytes, cursor),
                .committed_transaction_count = try readU64(bytes, cursor),
                .metadata_bytes = try readBytesBorrowed(bytes, cursor),
            };
        }

        fn encodeCommitRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: CommitRef) !void {
            try writeU64(out, allocator, ref.commit_fingerprint);
            try writeU64(out, allocator, ref.transaction_fingerprint);
            try writeU64(out, allocator, ref.parent_cursor_fingerprint);
            try writeU64(out, allocator, ref.resulting_cursor_fingerprint);
        }

        fn decodeCommitRef(bytes: []const u8, cursor: *usize) !CommitRef {
            return .{
                .commit_fingerprint = try readU64(bytes, cursor),
                .transaction_fingerprint = try readU64(bytes, cursor),
                .parent_cursor_fingerprint = try readU64(bytes, cursor),
                .resulting_cursor_fingerprint = try readU64(bytes, cursor),
            };
        }

        fn encodeCommit(out: *std.ArrayList(u8), allocator: std.mem.Allocator, commit: Chronicle.Commit) !void {
            try writeU32(out, allocator, commit.commit_format_version);
            try writeU32(out, allocator, commit.commit_fingerprint_version);
            try writeU64(out, allocator, commit.commit_fingerprint);
            try writeU64(out, allocator, commit.transaction_fingerprint);
            try writeU64(out, allocator, commit.parent_cursor_fingerprint);
            try writeU64(out, allocator, commit.resulting_cursor_fingerprint);
            try writeRefSlice(out, allocator, commit.committed_object_refs);
            try writeU64Slice(out, allocator, commit.committed_event_fingerprints);
            try writeRefSlice(out, allocator, commit.bundle_refs);
            try writeRefSlice(out, allocator, commit.capsule_refs);
            try writeRefSlice(out, allocator, commit.actuation_refs);
            try writeRefSlice(out, allocator, commit.idempotency_key_refs);
            try writeRefSlice(out, allocator, commit.validation_report_refs);
            try writeBytes(out, allocator, commit.blocker_summary);
            try writeBytes(out, allocator, commit.warning_summary);
            try writeBytes(out, allocator, commit.metadata_bytes);
        }

        fn decodeCommit(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Chronicle.Commit {
            var commit = Chronicle.Commit{
                .commit_format_version = try readU32(bytes, cursor),
                .commit_fingerprint_version = try readU32(bytes, cursor),
                .commit_fingerprint = try readU64(bytes, cursor),
                .transaction_fingerprint = try readU64(bytes, cursor),
                .parent_cursor_fingerprint = try readU64(bytes, cursor),
                .resulting_cursor_fingerprint = try readU64(bytes, cursor),
                .owns_memory = true,
            };
            commit.committed_object_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.committed_object_refs);
            commit.committed_event_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(commit.committed_event_fingerprints);
            commit.bundle_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.bundle_refs);
            commit.capsule_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.capsule_refs);
            commit.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.actuation_refs);
            commit.idempotency_key_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.idempotency_key_refs);
            commit.validation_report_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, commit.validation_report_refs);
            commit.blocker_summary = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(commit.blocker_summary);
            commit.warning_summary = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(commit.warning_summary);
            commit.metadata_bytes = try readBytesOwned(allocator, bytes, cursor);
            return commit;
        }

        fn encodeEvent(out: *std.ArrayList(u8), allocator: std.mem.Allocator, event: Chronicle.Event) !void {
            try writeU32(out, allocator, event.event_format_version);
            try writeU32(out, allocator, event.event_fingerprint_version);
            try writeU64(out, allocator, event.event_fingerprint);
            try writeU8(out, allocator, @intFromEnum(event.kind));
            try writeU64Slice(out, allocator, event.parent_event_fingerprints);
            try writeOptionalU64(out, allocator, event.transaction_fingerprint);
            try writeRefSlice(out, allocator, event.object_refs);
            try writeRefSlice(out, allocator, event.root_refs);
            try writeOptionalRef(out, allocator, event.capsule_ref);
            try writeRefSlice(out, allocator, event.actuation_refs);
            try writeOptionalRef(out, allocator, event.actuation_idempotency_key_ref);
            try writeOptionalRef(out, allocator, event.bundle_ref);
            try writeOptionalRef(out, allocator, event.recovery_plan_ref);
            try writeOptionalRef(out, allocator, event.recovery_report_ref);
            try writeOptionalRef(out, allocator, event.inbox_outbox_item_ref);
            try writeOptionalRef(out, allocator, event.target_ref);
            try writeOptionalRef(out, allocator, event.module_ref);
            try writeOptionalRef(out, allocator, event.assembly_ref);
            try writeOptionalRef(out, allocator, event.run_ref);
            try writeOptionalRef(out, allocator, event.run_permit_ref);
            try writeOptionalRef(out, allocator, event.admission_receipt_ref);
            try writeOptionalRef(out, allocator, event.environment_certificate_ref);
            try writeBytes(out, allocator, event.blocker_summary);
            try writeBytes(out, allocator, event.warning_summary);
            try writeBytes(out, allocator, event.metadata_bytes);
        }

        fn decodeEvent(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Chronicle.Event {
            var event = Chronicle.Event{
                .event_format_version = try readU32(bytes, cursor),
                .event_fingerprint_version = try readU32(bytes, cursor),
                .event_fingerprint = try readU64(bytes, cursor),
                .kind = try enumFromByte(Chronicle.EventKind, try readU8(bytes, cursor)),
                .owns_memory = true,
            };
            event.parent_event_fingerprints = try readU64SliceOwned(allocator, bytes, cursor);
            errdefer allocator.free(event.parent_event_fingerprints);
            event.transaction_fingerprint = try readOptionalU64(bytes, cursor);
            event.object_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, event.object_refs);
            event.root_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, event.root_refs);
            event.capsule_ref = try readOptionalRef(allocator, bytes, cursor);
            event.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor);
            errdefer freeRefSlice(allocator, event.actuation_refs);
            event.actuation_idempotency_key_ref = try readOptionalRef(allocator, bytes, cursor);
            event.bundle_ref = try readOptionalRef(allocator, bytes, cursor);
            event.recovery_plan_ref = try readOptionalRef(allocator, bytes, cursor);
            event.recovery_report_ref = try readOptionalRef(allocator, bytes, cursor);
            event.inbox_outbox_item_ref = try readOptionalRef(allocator, bytes, cursor);
            event.target_ref = try readOptionalRef(allocator, bytes, cursor);
            event.module_ref = try readOptionalRef(allocator, bytes, cursor);
            event.assembly_ref = try readOptionalRef(allocator, bytes, cursor);
            event.run_ref = try readOptionalRef(allocator, bytes, cursor);
            event.run_permit_ref = try readOptionalRef(allocator, bytes, cursor);
            event.admission_receipt_ref = try readOptionalRef(allocator, bytes, cursor);
            event.environment_certificate_ref = try readOptionalRef(allocator, bytes, cursor);
            event.blocker_summary = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(event.blocker_summary);
            event.warning_summary = try readBytesOwned(allocator, bytes, cursor);
            errdefer allocator.free(event.warning_summary);
            event.metadata_bytes = try readBytesOwned(allocator, bytes, cursor);
            return event;
        }

        fn encodeEnvelope(out: *std.ArrayList(u8), allocator: std.mem.Allocator, envelope: ObjectEnvelope) !void {
            const encoded = try Continuity.ObjectCodec.encodeEnvelope(envelope, allocator);
            defer allocator.free(encoded);
            try writeBytes(out, allocator, encoded);
        }

        fn decodeEnvelope(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !ObjectEnvelope {
            const encoded = try readBytesOwned(allocator, bytes, cursor);
            defer allocator.free(encoded);
            return Continuity.ObjectCodec.decodeEnvelope(allocator, encoded, max_decoded_byte_field_len / @sizeOf(ObjectRef));
        }

        fn writeRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: ObjectRef) !void {
            try writeU32(out, allocator, ref.ref_format_version);
            try writeU32(out, allocator, ref.ref_fingerprint_version);
            try writeU64(out, allocator, ref.ref_fingerprint);
            try writeU8(out, allocator, @intFromEnum(ref.kind));
            try writeU32(out, allocator, ref.object_format_version);
            try writeU64(out, allocator, ref.object_fingerprint);
            try writeU64(out, allocator, ref.byte_len);
            try writeBytes(out, allocator, ref.label);
            try writeBytes(out, allocator, ref.metadata);
        }

        fn readRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !ObjectRef {
            var ref = ObjectRef{
                .ref_format_version = try readU32(bytes, cursor),
                .ref_fingerprint_version = try readU32(bytes, cursor),
                .ref_fingerprint = try readU64(bytes, cursor),
                .kind = try enumFromByte(Continuity.ObjectKind, try readU8(bytes, cursor)),
                .object_format_version = try readU32(bytes, cursor),
                .object_fingerprint = try readU64(bytes, cursor),
                .byte_len = try readU64AsUsize(bytes, cursor),
                .label = try readBytesOwned(allocator, bytes, cursor),
                .metadata = "",
                .owns_memory = true,
            };
            errdefer allocator.free(ref.label);
            ref.metadata = try readBytesOwned(allocator, bytes, cursor);
            try ref.validate();
            return ref;
        }

        fn writeOptionalRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: ?ObjectRef) !void {
            try writeU8(out, allocator, if (ref == null) 0 else 1);
            if (ref) |value| try writeRef(out, allocator, value);
        }

        fn readOptionalRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !?ObjectRef {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readRef(allocator, bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn writeRefSlice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, refs: []const ObjectRef) !void {
            try writeU64(out, allocator, refs.len);
            for (refs) |ref| try writeRef(out, allocator, ref);
        }

        fn readRefSliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]ObjectRef {
            const count = try readU64AsUsize(bytes, cursor);
            if (count > max_decoded_byte_field_len / @sizeOf(ObjectRef)) return error.InvalidFrameEncoding;
            const refs = try allocator.alloc(ObjectRef, count);
            errdefer allocator.free(refs);
            var initialized: usize = 0;
            errdefer for (refs[0..initialized]) |*ref| ref.deinit(allocator);
            for (refs) |*ref| {
                ref.* = try readRef(allocator, bytes, cursor);
                initialized += 1;
            }
            return refs;
        }

        fn writeU64Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u64) !void {
            try writeU64(out, allocator, values.len);
            for (values) |value| try writeU64(out, allocator, value);
        }

        fn readU64SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]u64 {
            const count = try readU64AsUsize(bytes, cursor);
            if (count > max_decoded_byte_field_len / @sizeOf(u64)) return error.InvalidFrameEncoding;
            const values = try allocator.alloc(u64, count);
            for (values) |*value| value.* = try readU64(bytes, cursor);
            return values;
        }

        fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
            try writeU64(out, allocator, bytes.len);
            try out.appendSlice(allocator, bytes);
        }

        fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ![]u8 {
            const len = try readU64AsUsize(bytes, cursor);
            if (len > max_decoded_byte_field_len * 32) return error.InvalidFrameEncoding;
            if (bytes.len - cursor.* < len) return error.InvalidFrameEncoding;
            const out = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + len]);
            cursor.* += len;
            return out;
        }

        fn readBytesBorrowed(bytes: []const u8, cursor: *usize) ![]const u8 {
            const len = try readU64AsUsize(bytes, cursor);
            if (len > max_decoded_byte_field_len * 32) return error.InvalidFrameEncoding;
            if (bytes.len - cursor.* < len) return error.InvalidFrameEncoding;
            const out = bytes[cursor.* .. cursor.* + len];
            cursor.* += len;
            return out;
        }

        fn writeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u64) !void {
            try writeU8(out, allocator, if (value == null) 0 else 1);
            if (value) |actual| try writeU64(out, allocator, actual);
        }

        fn readOptionalU64(bytes: []const u8, cursor: *usize) !?u64 {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readU64(bytes, cursor),
                else => error.InvalidFrameEncoding,
            };
        }

        fn writeU8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
            try out.append(allocator, value);
        }

        fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &buf, value, .little);
            try out.appendSlice(allocator, &buf);
        }

        fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, value, .little);
            try out.appendSlice(allocator, &buf);
        }

        fn readU8(bytes: []const u8, cursor: *usize) !u8 {
            if (bytes.len - cursor.* < 1) return error.InvalidFrameEncoding;
            defer cursor.* += 1;
            return bytes[cursor.*];
        }

        fn readU32(bytes: []const u8, cursor: *usize) !u32 {
            if (bytes.len - cursor.* < 4) return error.InvalidFrameEncoding;
            defer cursor.* += 4;
            return std.mem.readInt(u32, bytes[cursor.*..][0..4], .little);
        }

        fn readU64(bytes: []const u8, cursor: *usize) !u64 {
            if (bytes.len - cursor.* < 8) return error.InvalidFrameEncoding;
            defer cursor.* += 8;
            return std.mem.readInt(u64, bytes[cursor.*..][0..8], .little);
        }

        fn readU64AsUsize(bytes: []const u8, cursor: *usize) !usize {
            return try u64ToUsize(try readU64(bytes, cursor));
        }

        fn readExact(bytes: []const u8, cursor: *usize, out: []u8) !void {
            if (bytes.len - cursor.* < out.len) return error.InvalidFrameEncoding;
            @memcpy(out, bytes[cursor.* .. cursor.* + out.len]);
            cursor.* += out.len;
        }

        fn u64ToUsize(value: u64) !usize {
            if (value > std.math.maxInt(usize)) return error.InvalidFrameEncoding;
            return @intCast(value);
        }

        fn segmentHeaderEncodedLen() usize {
            return 8 + 4 + 1 + 1 + 8 + 8 + 8 + 8;
        }

        fn sealEncodedLen(has_parent_seal: bool) usize {
            return @as(usize, 4 + 4 + 8 + 8 + 1) + (if (has_parent_seal) @as(usize, 8) else @as(usize, 0)) + @as(usize, 8 + 8 + 8 + 8 + 8);
        }

        fn enumFromByte(comptime E: type, value: u8) !E {
            inline for (std.meta.fields(E)) |field| {
                if (field.value == value) return @enumFromInt(value);
            }
            return error.InvalidFrameEncoding;
        }

        fn validateByteField(bytes: []const u8) !void {
            if (bytes.len > max_decoded_byte_field_len) return error.InvalidFrameEncoding;
        }

        fn validateU64Slice(values: []const u64) !void {
            if (values.len > max_decoded_byte_field_len / @sizeOf(u64)) return error.InvalidFrameEncoding;
            for (values) |value| if (value == 0) return error.InvalidFrameEncoding;
        }

        fn validateRefSlice(refs: []const ObjectRef) !void {
            if (refs.len > max_decoded_byte_field_len / @sizeOf(ObjectRef)) return error.InvalidFrameEncoding;
            for (refs) |ref| try ref.validate();
        }

        fn cloneRefSlice(allocator: std.mem.Allocator, refs: []const ObjectRef) ![]ObjectRef {
            const cloned = try allocator.alloc(ObjectRef, refs.len);
            errdefer allocator.free(cloned);
            var count: usize = 0;
            errdefer for (cloned[0..count]) |*ref| ref.deinit(allocator);
            for (refs, 0..) |ref, index| {
                cloned[index] = try ref.clone(allocator);
                count += 1;
            }
            return cloned;
        }

        fn freeRefSlice(allocator: std.mem.Allocator, refs: []const ObjectRef) void {
            for (refs) |ref_value| {
                var ref = ref_value;
                ref.deinit(allocator);
            }
            allocator.free(refs);
        }

        fn cloneEventSlice(allocator: std.mem.Allocator, events: []const Chronicle.Event) ![]Chronicle.Event {
            const cloned = try allocator.alloc(Chronicle.Event, events.len);
            errdefer allocator.free(cloned);
            var count: usize = 0;
            errdefer for (cloned[0..count]) |*event| event.deinit(allocator);
            for (events, 0..) |event, index| {
                cloned[index] = try event.clone(allocator);
                count += 1;
            }
            return cloned;
        }

        fn freeEventSlice(allocator: std.mem.Allocator, events: []const Chronicle.Event) void {
            for (events) |event_value| {
                var event = event_value;
                event.deinit(allocator);
            }
            allocator.free(events);
        }

        fn cloneEnvelopeSlice(allocator: std.mem.Allocator, envelopes: []const ObjectEnvelope) ![]ObjectEnvelope {
            const cloned = try allocator.alloc(ObjectEnvelope, envelopes.len);
            errdefer allocator.free(cloned);
            var count: usize = 0;
            errdefer for (cloned[0..count]) |*envelope| envelope.deinit(allocator);
            for (envelopes, 0..) |envelope, index| {
                cloned[index] = try envelope.clone(allocator);
                count += 1;
            }
            return cloned;
        }

        fn freeEnvelopeSlice(allocator: std.mem.Allocator, envelopes: []const ObjectEnvelope) void {
            for (envelopes) |envelope_value| {
                var envelope = envelope_value;
                envelope.deinit(allocator);
            }
            allocator.free(envelopes);
        }

        fn deinitMomentList(allocator: std.mem.Allocator, list: *std.ArrayList(Moment)) void {
            for (list.items) |*moment| moment.deinit(allocator);
            list.deinit(allocator);
        }

        fn deinitCommitList(allocator: std.mem.Allocator, list: *std.ArrayList(Chronicle.Commit)) void {
            for (list.items) |*commit| commit.deinit(allocator);
            list.deinit(allocator);
        }

        fn deinitEventList(allocator: std.mem.Allocator, list: *std.ArrayList(Chronicle.Event)) void {
            for (list.items) |*event| event.deinit(allocator);
            list.deinit(allocator);
        }

        fn deinitEnvelopeList(allocator: std.mem.Allocator, list: *std.ArrayList(ObjectEnvelope)) void {
            for (list.items) |*envelope| envelope.deinit(allocator);
            list.deinit(allocator);
        }

        fn containsRef(refs: []const ObjectRef, ref: ObjectRef) bool {
            for (refs) |candidate| if (candidate.eql(ref)) return true;
            return false;
        }

        fn refSlicesEqual(lhs: []const ObjectRef, rhs: []const ObjectRef) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (!left.eql(right)) return false;
            }
            return true;
        }

        fn objectSliceContainsRef(objects: []const ObjectEnvelope, ref: ObjectRef) bool {
            for (objects) |object| {
                if (object.objectRef().eql(ref)) return true;
            }
            return false;
        }

        fn rejectConflictingObjectBytes(objects: []const ObjectEnvelope) !void {
            for (objects, 0..) |lhs, lhs_index| {
                for (objects[lhs_index + 1 ..]) |rhs| {
                    if (lhs.objectRef().eql(rhs.objectRef()) and lhs.envelope_fingerprint != rhs.envelope_fingerprint) return error.DuplicateBinding;
                }
            }
        }

        fn rejectConflictingObjectBytesAcross(existing: []const ObjectEnvelope, incoming: []const ObjectEnvelope) !void {
            for (incoming) |object| {
                const ref = object.objectRef();
                for (existing) |candidate| {
                    if (candidate.objectRef().eql(ref) and candidate.envelope_fingerprint != object.envelope_fingerprint) return error.DuplicateBinding;
                }
            }
        }

        fn collectDependencyRefs(allocator: std.mem.Allocator, objects: []const ObjectEnvelope) ![]ObjectRef {
            var refs: std.ArrayList(ObjectRef) = .empty;
            errdefer deinitRefList(&refs, allocator);
            for (objects) |object| {
                for (object.dependency_refs) |dep| {
                    if (containsRef(refs.items, dep)) continue;
                    const owned = try dep.clone(allocator);
                    var owned_pending = true;
                    errdefer if (owned_pending) {
                        var cleanup = owned;
                        cleanup.deinit(allocator);
                    };
                    try refs.append(allocator, owned);
                    owned_pending = false;
                }
            }
            return refs.toOwnedSlice(allocator);
        }

        fn deinitRefList(list: *std.ArrayList(ObjectRef), allocator: std.mem.Allocator) void {
            for (list.items) |*ref| ref.deinit(allocator);
            list.deinit(allocator);
        }

        fn commitRefMatchesCommit(ref: CommitRef, commit: Chronicle.Commit) bool {
            return ref.commit_fingerprint == commit.commit_fingerprint and
                ref.transaction_fingerprint == commit.transaction_fingerprint and
                ref.parent_cursor_fingerprint == commit.parent_cursor_fingerprint and
                ref.resulting_cursor_fingerprint == commit.resulting_cursor_fingerprint;
        }

        fn recoverableTailError(err: anyerror) bool {
            return switch (err) {
                error.OutOfMemory => false,
                else => true,
            };
        }

        fn bindEventTransaction(event: Chronicle.Event, transaction_fingerprint: u64) Chronicle.Event {
            return Chronicle.Event.init(.{
                .kind = event.kind,
                .parent_event_fingerprints = event.parent_event_fingerprints,
                .transaction_fingerprint = transaction_fingerprint,
                .object_refs = event.object_refs,
                .root_refs = event.root_refs,
                .capsule_ref = event.capsule_ref,
                .actuation_refs = event.actuation_refs,
                .actuation_idempotency_key_ref = event.actuation_idempotency_key_ref,
                .bundle_ref = event.bundle_ref,
                .recovery_plan_ref = event.recovery_plan_ref,
                .recovery_report_ref = event.recovery_report_ref,
                .inbox_outbox_item_ref = event.inbox_outbox_item_ref,
                .target_ref = event.target_ref,
                .module_ref = event.module_ref,
                .assembly_ref = event.assembly_ref,
                .run_ref = event.run_ref,
                .run_permit_ref = event.run_permit_ref,
                .admission_receipt_ref = event.admission_receipt_ref,
                .environment_certificate_ref = event.environment_certificate_ref,
                .blocker_summary = event.blocker_summary,
                .warning_summary = event.warning_summary,
                .metadata_bytes = event.metadata_bytes,
            });
        }

        fn transactionFingerprint(parent: Chronicle.Cursor, object_refs: []const ObjectRef) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.transaction");
            hashU64(&hasher, parent.cursor_fingerprint);
            hashRefSlice(&hasher, object_refs);
            return hasher.final();
        }

        fn fingerprintPayloadBytes(bytes: []const u8) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.payload");
            hashBytesWithLen(&hasher, bytes);
            return hasher.final();
        }

        fn fingerprintArchiveProfile(header: Header) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.profile");
            hashU64(&hasher, header.archive_format_version);
            hashU64(&hasher, header.archive_fingerprint_version);
            hashU64(&hasher, header.compatible_chronicle_event_format_version);
            hashU64(&hasher, header.compatible_chronicle_commit_format_version);
            hashU64(&hasher, header.compatible_object_envelope_format_version);
            hashU64(&hasher, header.required_feature_flags);
            hashU64(&hasher, header.optional_feature_flags);
            return hasher.final();
        }

        fn fingerprintHeader(header: Header) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.header");
            hashBytes(&hasher, &header.magic);
            hashU64(&hasher, header.header_format_version);
            hashU64(&hasher, header.archive_format_version);
            hashU64(&hasher, header.archive_fingerprint_version);
            hashU64(&hasher, header.byte_order_marker);
            hashU64(&hasher, header.compatible_chronicle_event_format_version);
            hashU64(&hasher, header.compatible_chronicle_commit_format_version);
            hashU64(&hasher, header.compatible_object_envelope_format_version);
            hashU64(&hasher, header.genesis_cursor_fingerprint);
            hashU64(&hasher, header.required_feature_flags);
            hashU64(&hasher, header.optional_feature_flags);
            hashU64(&hasher, header.archive_profile_fingerprint);
            return hasher.final();
        }

        fn fingerprintSegmentHeader(header: SegmentHeader) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.segment.header");
            hashBytes(&hasher, &header.magic);
            hashU64(&hasher, header.segment_format_version);
            hashU64(&hasher, @intFromEnum(header.segment_kind));
            hashBool(&hasher, header.required);
            hashU64(&hasher, header.sequence_number);
            hashU64(&hasher, header.payload_byte_len);
            hashU64(&hasher, header.payload_fingerprint);
            return hasher.final();
        }

        fn fingerprintMoment(moment: Moment) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.moment");
            hashU64(&hasher, moment.moment_format_version);
            hashU64(&hasher, moment.moment_fingerprint_version);
            hashU64(&hasher, moment.sequence_number);
            hashOptionalU64(&hasher, moment.parent_moment_fingerprint);
            hashOptionalU64(&hasher, moment.parent_seal_fingerprint);
            hashU64(&hasher, moment.chronicle_parent_cursor.cursor_fingerprint);
            hashU64(&hasher, moment.chronicle_resulting_cursor.cursor_fingerprint);
            hashU64(&hasher, moment.chronicle_commit_ref.commit_fingerprint);
            hashU64Slice(&hasher, moment.committed_event_refs);
            hashRefSlice(&hasher, moment.committed_object_refs);
            hashRefSlice(&hasher, moment.root_object_refs);
            hashRefSlice(&hasher, moment.capsule_refs);
            hashRefSlice(&hasher, moment.actuation_refs);
            hashRefSlice(&hasher, moment.bundle_refs);
            hashRefSlice(&hasher, moment.admission_refs);
            hashRefSlice(&hasher, moment.environment_certificate_refs);
            hashRefSlice(&hasher, moment.permit_receipt_refs);
            hashRefSlice(&hasher, moment.link_assembly_refs);
            hashRefSlice(&hasher, moment.fabric_receipt_refs);
            hashRefSlice(&hasher, moment.guest_conformance_refs);
            hashRefSlice(&hasher, moment.dependency_refs);
            hashU64Slice(&hasher, moment.projection_summary_fingerprints);
            hashOptionalU64(&hasher, moment.idempotency_registry_summary_fingerprint);
            return hasher.final();
        }

        fn fingerprintSealedPrefix(seal: Seal) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.sealed.prefix");
            hashOptionalU64(&hasher, seal.parent_seal_fingerprint);
            hashU64(&hasher, seal.moment_fingerprint);
            hashU64(&hasher, seal.moment_data_segment_fingerprint);
            hashU64(&hasher, seal.chronicle_resulting_cursor_fingerprint);
            hashU64(&hasher, seal.committed_prefix_byte_len);
            return hasher.final();
        }

        fn fingerprintSeal(seal: Seal) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.seal");
            hashU64(&hasher, seal.seal_format_version);
            hashU64(&hasher, seal.seal_fingerprint_version);
            hashU64(&hasher, seal.sequence_number);
            hashOptionalU64(&hasher, seal.parent_seal_fingerprint);
            hashU64(&hasher, seal.moment_fingerprint);
            hashU64(&hasher, seal.moment_data_segment_fingerprint);
            hashU64(&hasher, seal.chronicle_resulting_cursor_fingerprint);
            hashU64(&hasher, seal.committed_prefix_byte_len);
            hashU64(&hasher, seal.sealed_prefix_fingerprint);
            return hasher.final();
        }

        fn fingerprintAppendBatch(batch: AppendBatch) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.append.batch");
            hashU64(&hasher, batch.append_batch_format_version);
            hashU64(&hasher, batch.append_batch_fingerprint_version);
            hashU64(&hasher, batch.parent_cursor.cursor_fingerprint);
            hashU64(&hasher, batch.commit.commit_fingerprint);
            for (batch.events) |event| hashU64(&hasher, event.event_fingerprint);
            for (batch.objects) |object| hashU64(&hasher, object.envelope_fingerprint);
            hashBytesWithLen(&hasher, batch.diagnostic_metadata_bytes);
            return hasher.final();
        }

        fn fingerprintReplayReport(report: ReplayReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.replay.report");
            if (report.source_moment) |moment| hashU64(&hasher, moment.moment_fingerprint) else hashU64(&hasher, 0);
            hashU64(&hasher, report.source_cursor.cursor_fingerprint);
            if (report.chronicle_report) |chronicle_report| hashU64(&hasher, chronicle_report.report_fingerprint) else hashU64(&hasher, 0);
            hashU64(&hasher, report.replayed_commit_count);
            hashU64(&hasher, report.replayed_event_count);
            hashU64(&hasher, report.rebuilt_projection_count);
            hashU64(&hasher, report.mismatch_count);
            return hasher.final();
        }

        fn fingerprintImage(image: Image) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.image");
            hashU64(&hasher, image.header.header_fingerprint);
            for (image.seals) |seal| hashU64(&hasher, seal.seal_fingerprint);
            hashU64(&hasher, image.committed_prefix_byte_len);
            return hasher.final();
        }

        fn fingerprintSafetyReport(report: SafetyReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.safety.report");
            hashBool(&hasher, report.experimental);
            hashBool(&hasher, report.production_ready);
            hashU64(&hasher, @intFromEnum(report.durability_posture));
            hashBytesWithLen(&hasher, report.crash_consistency_posture);
            hashBytesWithLen(&hasher, report.corruption_detection_posture);
            hashBytesWithLen(&hasher, report.hash_collision_posture);
            hashBytesWithLen(&hasher, report.clone_freeze_posture);
            hashBytesWithLen(&hasher, report.compaction_posture);
            hashBytesWithLen(&hasher, report.concurrency_posture);
            hashBytesWithLen(&hasher, report.wasm_posture);
            for (report.unsupported_behavior) |item| hashBytesWithLen(&hasher, item);
            for (report.blockers) |item| hashBytesWithLen(&hasher, item);
            for (report.warnings) |item| hashBytesWithLen(&hasher, item);
            return hasher.final();
        }

        fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
            hasher.update(bytes);
        }

        fn hashBytesWithLen(hasher: *std.hash.Wyhash, bytes: []const u8) void {
            hashU64(hasher, bytes.len);
            hasher.update(bytes);
        }

        fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
            hashU64(hasher, @as(u64, if (value) 1 else 0));
        }

        fn hashU64(hasher: *std.hash.Wyhash, value: anytype) void {
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, @intCast(value), .little);
            hasher.update(&buf);
        }

        fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
            if (value) |actual| {
                hashBool(hasher, true);
                hashU64(hasher, actual);
            } else {
                hashBool(hasher, false);
            }
        }

        fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
            hashU64(hasher, values.len);
            for (values) |value| hashU64(hasher, value);
        }

        fn hashRefSlice(hasher: *std.hash.Wyhash, refs: []const ObjectRef) void {
            hashU64(hasher, refs.len);
            for (refs) |ref| hashU64(hasher, ref.ref_fingerprint);
        }
    };
}
