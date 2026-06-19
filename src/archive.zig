const std = @import("std");

pub fn Archive(comptime World: type) type {
    return struct {
        const Self = @This();
        const Continuity = World.Continuity;
        const Chronicle = Continuity.Chronicle;
        const ObjectRef = Continuity.ObjectRef;
        const ObjectEnvelope = Continuity.ObjectEnvelope;
        const Actuation = World.Actuation;
        const Frame = World.Frame;
        const RunImage = World.RunImage;
        const TranscriptImage = World.TranscriptImage;
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
                try validateRefSliceUnique(self.commit.committed_object_refs);
                if (self.commit.bundle_refs.len != 0 and !refSlicesEqual(self.commit.bundle_refs, self.moment.bundle_refs)) return error.InvalidFrameEncoding;
                if (self.commit.capsule_refs.len != 0 and !refSlicesEqual(self.commit.capsule_refs, self.moment.capsule_refs)) return error.InvalidFrameEncoding;
                if (self.commit.actuation_refs.len != 0 and !refSlicesEqual(self.commit.actuation_refs, self.moment.actuation_refs)) return error.InvalidFrameEncoding;
                if (self.events.len != self.moment.committed_event_refs.len) return error.InvalidFrameEncoding;
                if (self.events.len != self.commit.committed_event_fingerprints.len) return error.InvalidFrameEncoding;
                for (self.events, self.moment.committed_event_refs, self.commit.committed_event_fingerprints) |event, moment_expected, commit_expected| {
                    try event.validate();
                    if (event.event_fingerprint != moment_expected or event.event_fingerprint != commit_expected) return error.InvalidFrameEncoding;
                }
                const recomputed_cursor = self.moment.chronicle_parent_cursor.advance(self.commit.committed_event_fingerprints, self.commit.committed_object_refs.len, 1);
                if (!cursorsEqual(recomputed_cursor, self.moment.chronicle_resulting_cursor)) return error.InvalidFrameEncoding;
                var committed_ref_index: usize = 0;
                for (self.events) |event| {
                    if (!eventKindAllowedInCommittedMoment(event.kind)) return error.InvalidFrameEncoding;
                    const transaction_fingerprint = event.transaction_fingerprint orelse return error.InvalidFrameEncoding;
                    if (transaction_fingerprint != self.commit.transaction_fingerprint) return error.InvalidFrameEncoding;
                    if (event.kind != .object_committed) continue;
                    for (event.object_refs) |ref| {
                        if (committed_ref_index >= self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                        if (!ref.eql(self.commit.committed_object_refs[committed_ref_index])) return error.InvalidFrameEncoding;
                        committed_ref_index += 1;
                    }
                }
                if (committed_ref_index != self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                if (self.objects.len != self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                for (self.objects) |envelope| {
                    try envelope.validate();
                    const ref = envelope.objectRef();
                    if (!containsRef(self.commit.committed_object_refs, ref)) return error.InvalidFrameEncoding;
                }
                for (self.commit.committed_object_refs) |ref| {
                    if (!objectSliceContainsRef(self.objects, ref)) return error.InvalidFrameEncoding;
                }
                try rejectConflictingObjectBytes(self.objects);
                if (!dependencyRefsMatchCommittedObjects(self.moment.dependency_refs, self.objects)) return error.InvalidFrameEncoding;
                if (!summaryRefsEmptyOrMatchCommittedObjects(self.commit.committed_object_refs, self.commit.bundle_refs, .bundle)) return error.InvalidFrameEncoding;
                if (!summaryRefsEmptyOrMatchCommittedObjects(self.commit.committed_object_refs, self.commit.capsule_refs, .capsule)) return error.InvalidFrameEncoding;
                if (!summaryRefsEmptyOrMatchCommittedObjects(self.commit.committed_object_refs, self.commit.actuation_refs, .actuation)) return error.InvalidFrameEncoding;
                if (!summaryRefsEmptyOrMatchCommittedObjects(self.commit.committed_object_refs, self.commit.idempotency_key_refs, .idempotency_key)) return error.InvalidFrameEncoding;
                if (!summaryRefsEmptyOrMatchCommittedObjects(self.commit.committed_object_refs, self.commit.validation_report_refs, .validation_report)) return error.InvalidFrameEncoding;
                if (!refSlicesEqual(self.commit.committed_object_refs, self.moment.root_object_refs)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.bundle_refs, .bundle)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.capsule_refs, .capsule)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.actuation_refs, .actuation)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.admission_refs, .admission)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.environment_certificate_refs, .environment_certificate)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.permit_receipt_refs, .permit_receipt)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.link_assembly_refs, .link_assembly)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.fabric_receipt_refs, .fabric_receipt)) return error.InvalidFrameEncoding;
                if (!summaryRefsMatchCommittedObjects(self.commit.committed_object_refs, self.moment.guest_conformance_refs, .guest_conformance)) return error.InvalidFrameEncoding;
            }

            pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() {
                var result = self;
                result.moment = try self.moment.clone(allocator);
                errdefer result.moment.deinit(allocator);
                result.commit = try self.commit.clone(allocator);
                errdefer result.commit.deinit(allocator);
                result.events = try cloneEventSlice(allocator, self.events);
                errdefer freeEventSlice(allocator, result.events);
                result.objects = try cloneEnvelopeSlice(allocator, self.objects);
                errdefer freeEnvelopeSlice(allocator, result.objects);
                result.owns_memory = true;
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
                if (self.objects.len != self.commit.committed_object_refs.len) return error.InvalidFrameEncoding;
                for (self.commit.committed_object_refs) |ref| {
                    if (!objectSliceContainsRef(self.objects, ref)) return error.InvalidFrameEncoding;
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
                        return .{ .image = try self.clonePrefix(index), .moment_index = index };
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
                const upper = if (moment_index) |index| index + 1 else self.moments.len;
                var vault = if (self.usesInitializedGenesis(upper))
                    Continuity.MemoryVault.init(allocator)
                else
                    Continuity.MemoryVault{
                        .allocator = allocator,
                        .ledger = Continuity.Ledger.init(allocator),
                    };
                errdefer vault.deinit();
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

            fn usesInitializedGenesis(self: *const @This(), upper: usize) bool {
                if (upper == 0) return false;
                return self.moments[0].chronicle_parent_cursor.cursor_fingerprint == initializedArchiveCursor().cursor_fingerprint;
            }

            fn findObject(self: *const @This(), ref: ObjectRef) ?ObjectEnvelope {
                for (self.objects) |envelope| {
                    if (envelope.objectRef().eql(ref)) return envelope;
                }
                return null;
            }

            fn clonePrefix(self: *const @This(), moment_index: usize) !@This() {
                const upper = moment_index + 1;
                if (upper > self.moments.len or upper > self.seals.len or upper > self.commits.len) return error.InvalidFrameEncoding;

                var event_count: usize = 0;
                var object_count: usize = 0;
                for (self.moments[0..upper]) |moment| {
                    event_count += moment.committed_event_refs.len;
                    object_count += moment.committed_object_refs.len;
                }
                if (event_count > self.events.len or object_count > self.objects.len) return error.InvalidFrameEncoding;

                const moments_slice = try self.allocator.alloc(Moment, upper);
                errdefer self.allocator.free(moments_slice);
                var moments_cloned: usize = 0;
                errdefer {
                    for (moments_slice[0..moments_cloned]) |*moment| moment.deinit(self.allocator);
                }
                for (self.moments[0..upper], 0..) |moment, index| {
                    moments_slice[index] = try moment.clone(self.allocator);
                    moments_cloned += 1;
                }

                const seals_slice = try self.allocator.dupe(Seal, self.seals[0..upper]);
                errdefer self.allocator.free(seals_slice);

                const commits_slice = try self.allocator.alloc(Chronicle.Commit, upper);
                errdefer self.allocator.free(commits_slice);
                var commits_cloned: usize = 0;
                errdefer {
                    for (commits_slice[0..commits_cloned]) |*commit| commit.deinit(self.allocator);
                }
                for (self.commits[0..upper], 0..) |commit, index| {
                    commits_slice[index] = try commit.clone(self.allocator);
                    commits_cloned += 1;
                }

                const events_slice = try cloneEventSlice(self.allocator, self.events[0..event_count]);
                errdefer freeEventSlice(self.allocator, events_slice);
                const objects_slice = try cloneEnvelopeSlice(self.allocator, self.objects[0..object_count]);
                errdefer freeEnvelopeSlice(self.allocator, objects_slice);

                var image = @This(){
                    .allocator = self.allocator,
                    .header = self.header,
                    .moments = moments_slice,
                    .seals = seals_slice,
                    .commits = commits_slice,
                    .events = events_slice,
                    .objects = objects_slice,
                    .committed_prefix_byte_len = self.seals[upper - 1].committed_prefix_byte_len,
                    .owns_memory = true,
                };
                image.image_fingerprint = fingerprintImage(image);
                return image;
            }
        };

        pub const Snapshot = struct {
            image: Image,
            moment_index: usize,

            pub fn cursor(self: @This()) Chronicle.Cursor {
                return self.image.moments[self.moment_index].chronicle_resulting_cursor;
            }

            pub fn moment(self: @This()) Moment {
                var borrowed = self.image.moments[self.moment_index];
                borrowed.owns_memory = false;
                return borrowed;
            }

            pub fn deinit(self: *@This()) void {
                self.image.deinit();
                self.* = undefined;
            }

            pub fn getObject(self: @This(), ref: ObjectRef) !ObjectEnvelope {
                try ref.validate();
                for (self.image.objects) |envelope| {
                    if (try refMatchesObject(self.image.allocator, envelope, ref) and self.refCommittedAtOrBeforeMoment(envelope.objectRef())) return envelope.clone(self.image.allocator);
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
                    if (containsEquivalentRef(moment_item.committed_object_refs, ref)) return true;
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
                const latest_cursor = if (latest_moment) |moment| moment.chronicle_resulting_cursor else Chronicle.Cursor.initial();
                return .{
                    .latest_moment = latest_moment,
                    .latest_cursor = latest_cursor,
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
                    if (moment_segment.header.segment_kind == .optional_extension) {
                        if (moment_segment.header.required) return error.UnsupportedMapping;
                        continue;
                    }
                    if (moment_segment.header.segment_kind != .moment_data or !moment_segment.header.required) {
                        cursor = moment_segment_start;
                        break;
                    }
                    var data = decodeMomentData(self.allocator, moment_segment.payload, self.limits) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    defer data.deinit(self.allocator);
                    validateTypedObjectPayloads(self.allocator, objects.items, data.objects) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        cursor = moment_segment_start;
                        break;
                    };
                    data.validate() catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (moment_segment.header.sequence_number != expected_sequence or
                        data.moment.sequence_number != expected_sequence or
                        data.moment.parent_moment_fingerprint != parent_moment_fingerprint or
                        data.moment.parent_seal_fingerprint != parent_seal_fingerprint or
                        !validArchiveParentCursor(expected_cursor, expected_sequence, data.moment.chronicle_parent_cursor))
                    {
                        break;
                    }
                    const seal_segment = readSegment(self.bytes, &cursor, self.limits) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        break;
                    };
                    if (seal_segment.header.segment_kind != .moment_seal or !seal_segment.header.required) {
                        cursor = moment_segment_start;
                        break;
                    }
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
                    rejectAlreadyCommittedObjectRefs(objects.items, data.objects) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        cursor = moment_segment_start;
                        break;
                    };
                    validateDomainEventRefsKnown(self.allocator, data.events, objects.items, data.objects) catch |err| {
                        if (!recoverableTailError(err)) return err;
                        cursor = moment_segment_start;
                        break;
                    };
                    validateObjectDependenciesKnown(self.allocator, objects.items, data.objects) catch |err| {
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
                const len_before = self.bytes.items.len;
                const header_written_before = self.header_written;
                errdefer {
                    self.bytes.shrinkRetainingCapacity(len_before);
                    self.header_written = header_written_before;
                }
                try encodeHeader(&self.bytes, self.allocator, header);
                if (self.bytes.items.len > self.limits.max_archive_bytes) return error.InvalidFrameEncoding;
                self.header_written = true;
            }

            pub fn append(self: *@This(), batch: AppendBatch, parent_moment: ?Moment, parent_seal: ?Seal) !Seal {
                const append_start = self.bytes.items.len;
                const header_written_before = self.header_written;
                var append_pending = true;
                errdefer if (append_pending) {
                    self.bytes.shrinkRetainingCapacity(append_start);
                    self.header_written = header_written_before;
                };
                try batch.validate();
                try validateAppendBatchLimits(self.allocator, batch, self.limits);
                try validateTypedObjectPayloads(self.allocator, &.{}, batch.objects);
                if (!self.header_written) try self.writeHeader(Header.init(.{}));
                try self.validateAppendParent(batch, parent_moment, parent_seal);
                try self.rejectObjectConflicts(batch.objects);
                var event_fingerprints: std.ArrayList(u64) = .empty;
                defer event_fingerprints.deinit(self.allocator);
                for (batch.events) |event| try event_fingerprints.append(self.allocator, event.event_fingerprint);
                const committed_refs = try cloneRefSlice(self.allocator, batch.commit.committed_object_refs);
                defer freeRefSlice(self.allocator, committed_refs);
                const dependency_refs = try collectDependencyRefs(self.allocator, batch.objects);
                defer freeRefSlice(self.allocator, dependency_refs);
                const bundle_refs = try collectSummaryRefs(self.allocator, committed_refs, .bundle);
                defer freeRefSlice(self.allocator, bundle_refs);
                const capsule_refs = try collectSummaryRefs(self.allocator, committed_refs, .capsule);
                defer freeRefSlice(self.allocator, capsule_refs);
                const actuation_refs = try collectSummaryRefs(self.allocator, committed_refs, .actuation);
                defer freeRefSlice(self.allocator, actuation_refs);
                const admission_refs = try collectSummaryRefs(self.allocator, committed_refs, .admission);
                defer freeRefSlice(self.allocator, admission_refs);
                const environment_certificate_refs = try collectSummaryRefs(self.allocator, committed_refs, .environment_certificate);
                defer freeRefSlice(self.allocator, environment_certificate_refs);
                const permit_receipt_refs = try collectSummaryRefs(self.allocator, committed_refs, .permit_receipt);
                defer freeRefSlice(self.allocator, permit_receipt_refs);
                const link_assembly_refs = try collectSummaryRefs(self.allocator, committed_refs, .link_assembly);
                defer freeRefSlice(self.allocator, link_assembly_refs);
                const fabric_receipt_refs = try collectSummaryRefs(self.allocator, committed_refs, .fabric_receipt);
                defer freeRefSlice(self.allocator, fabric_receipt_refs);
                const guest_conformance_refs = try collectSummaryRefs(self.allocator, committed_refs, .guest_conformance);
                defer freeRefSlice(self.allocator, guest_conformance_refs);
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
                    .capsule_refs = capsule_refs,
                    .actuation_refs = actuation_refs,
                    .bundle_refs = bundle_refs,
                    .admission_refs = admission_refs,
                    .environment_certificate_refs = environment_certificate_refs,
                    .permit_receipt_refs = permit_receipt_refs,
                    .link_assembly_refs = link_assembly_refs,
                    .fabric_receipt_refs = fabric_receipt_refs,
                    .guest_conformance_refs = guest_conformance_refs,
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
                try encodeSegmentHeader(&self.bytes, self.allocator, data_header);
                try self.bytes.appendSlice(self.allocator, payload.items);
                const committed_prefix_len = self.bytes.items.len + segmentHeaderEncodedLen() + sealEncodedLen(parent_seal != null);
                if (committed_prefix_len > self.limits.max_archive_bytes) return error.InvalidFrameEncoding;
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
                if (self.bytes.items.len != committed_prefix_len or self.bytes.items.len > self.limits.max_archive_bytes) return error.InvalidFrameEncoding;
                append_pending = false;
                return seal;
            }

            fn validateAppendParent(self: *@This(), batch: AppendBatch, parent_moment: ?Moment, parent_seal: ?Seal) !void {
                var reader = Reader.init(self.allocator, self.bytes.items, self.limits);
                var image = try reader.readImage();
                defer image.deinit();

                if (image.committed_prefix_byte_len != self.bytes.items.len) {
                    try validateOptionalExtensionTail(self.bytes.items, image.committed_prefix_byte_len, self.limits);
                }
                if (!validArchiveParentCursor(image.latestCursor(), if (image.latestMoment() == null) 1 else 2, batch.parent_cursor)) return error.StaleProjection;
                if (image.latestMoment()) |latest_moment| {
                    const supplied = parent_moment orelse return error.StaleProjection;
                    if (supplied.moment_fingerprint != latest_moment.moment_fingerprint) return error.StaleProjection;
                } else if (parent_moment != null) {
                    return error.StaleProjection;
                }
                if (image.latestSeal()) |latest_seal| {
                    const supplied = parent_seal orelse return error.StaleProjection;
                    if (supplied.seal_fingerprint != latest_seal.seal_fingerprint) return error.StaleProjection;
                } else if (parent_seal != null) {
                    return error.StaleProjection;
                }
                try validateDomainEventRefsKnown(self.allocator, batch.events, image.objects, batch.objects);
                try validateObjectDependenciesKnown(self.allocator, image.objects, batch.objects);
                try validateTypedObjectPayloads(self.allocator, image.objects, batch.objects);
                try rejectAlreadyCommittedObjectRefs(image.objects, batch.objects);
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
            stable_refs: std.ArrayList(ObjectRef) = .empty,
            stable_moments: std.ArrayList(Moment) = .empty,
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
                    if (self.committed) return error.InvalidFrameEncoding;
                    try envelope.validate();
                    try validateTypedObjectPayload(self.archive.allocator, envelope);
                    try Continuity.validateObjectEnvelopeRequiredDependencies(self.archive.allocator, envelope);
                    const ref = envelope.objectRef();
                    for (self.archive.image.objects) |object| {
                        if (!object.objectRef().eql(ref)) continue;
                        if (object.envelope_fingerprint != envelope.envelope_fingerprint) return error.DuplicateBinding;
                        return try self.archive.stableRef(object.objectRef());
                    }
                    for (self.staged_objects.items) |object| {
                        if (!object.objectRef().eql(ref)) continue;
                        if (object.envelope_fingerprint != envelope.envelope_fingerprint) return error.DuplicateBinding;
                        return try self.archive.stableRef(object.objectRef());
                    }
                    try self.validateDependencies(envelope);
                    const owned = try envelope.clone(self.archive.allocator);
                    var owned_pending = true;
                    errdefer if (owned_pending) {
                        var cleanup = owned;
                        cleanup.deinit(self.archive.allocator);
                    };
                    try self.staged_objects.append(self.archive.allocator, owned);
                    owned_pending = false;
                    var staged_pending = true;
                    errdefer if (staged_pending) {
                        var cleanup = self.staged_objects.pop().?;
                        cleanup.deinit(self.archive.allocator);
                    };
                    const returned_ref = try self.archive.stableRef(self.staged_objects.items[self.staged_objects.items.len - 1].objectRef());
                    staged_pending = false;
                    return returned_ref;
                }

                pub fn addEvent(self: *@This(), event: Chronicle.Event) !void {
                    if (self.committed) return error.InvalidFrameEncoding;
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
                    var idempotency_key_refs: std.ArrayList(ObjectRef) = .empty;
                    defer idempotency_key_refs.deinit(self.archive.allocator);
                    var validation_report_refs: std.ArrayList(ObjectRef) = .empty;
                    defer validation_report_refs.deinit(self.archive.allocator);
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
                            => try actuation_refs.append(self.archive.allocator, ref),
                            .actuation_idempotency_key => {
                                try actuation_refs.append(self.archive.allocator, ref);
                                try idempotency_key_refs.append(self.archive.allocator, ref);
                            },
                            .actuation_verify_report => try validation_report_refs.append(self.archive.allocator, ref),
                            .bundle => try bundle_refs.append(self.archive.allocator, ref),
                            else => {},
                        }
                    }
                    const tx_fingerprint = transactionFingerprint(latest, self.staged_objects.items, self.staged_events.items);
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
                        .idempotency_key_refs = idempotency_key_refs.items,
                        .validation_report_refs = validation_report_refs.items,
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

                fn validateDependencies(self: @This(), envelope: ObjectEnvelope) !void {
                    for (envelope.dependency_refs) |dep| {
                        if (self.archive.hasObject(dep) or try objectSliceContainsSemanticRef(self.archive.allocator, self.staged_objects.items, dep)) continue;
                        if (dep.byte_len == 0 and envelopeKindAllowsUnresolvedSemanticDependency(envelope.kind)) continue;
                        return error.ObjectMissing;
                    }
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
                deinitRefList(&self.stable_refs, self.allocator);
                deinitMomentList(self.allocator, &self.stable_moments);
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
                if (!validArchiveParentCursor(self.currentCursor(), if (self.image.latestMoment() == null) 1 else 2, batch.parent_cursor)) return error.StaleProjection;
                var writer = Writer.init(self.allocator, .{});
                defer writer.deinit();
                try writer.bytes.appendSlice(self.allocator, self.bytes.items[0..self.image.committed_prefix_byte_len]);
                writer.header_written = true;
                _ = try writer.append(batch, self.image.latestMoment(), self.image.latestSeal());
                var reader = Reader.init(self.allocator, writer.bytes.items, .{});
                var next_image = try reader.readImage();
                var next_image_owned = true;
                errdefer if (next_image_owned) next_image.deinit();
                var next_bytes: std.ArrayList(u8) = .empty;
                errdefer next_bytes.deinit(self.allocator);
                try next_bytes.appendSlice(self.allocator, writer.bytes.items);
                const latest = next_image.latestMoment() orelse return error.ObjectMissing;
                const stable_latest = try self.stableMoment(latest);
                self.bytes.deinit(self.allocator);
                self.bytes = next_bytes;
                next_bytes = .empty;
                self.image.deinit();
                self.image = next_image;
                next_image_owned = false;
                return stable_latest;
            }

            pub fn bytesView(self: @This()) []const u8 {
                return self.bytes.items;
            }

            pub fn recover(self: *@This()) !RecoveryReport {
                var reader = Reader.init(self.allocator, self.bytes.items, .{});
                var report = try reader.recover();
                errdefer report.deinit(self.allocator);
                if (report.committed_prefix_byte_len < self.bytes.items.len) {
                    var prefix_reader = Reader.init(self.allocator, self.bytes.items[0..report.committed_prefix_byte_len], .{});
                    var next_image = try prefix_reader.readImage();
                    var next_image_owned = true;
                    errdefer if (next_image_owned) next_image.deinit();
                    self.bytes.shrinkRetainingCapacity(report.committed_prefix_byte_len);
                    self.image.deinit();
                    self.image = next_image;
                    next_image_owned = false;
                    return report;
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
                try ref.validate();
                for (self.image.objects) |envelope| {
                    if (try refMatchesObject(self.allocator, envelope, ref)) return envelope.clone(self.allocator);
                }
                return error.ObjectMissing;
            }

            pub fn hasObject(self: @This(), ref: ObjectRef) bool {
                ref.validate() catch return false;
                for (self.image.objects) |envelope| {
                    if (refMatchesObject(self.allocator, envelope, ref) catch return false) return true;
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
                var image = try reader.readImage();
                errdefer image.deinit();
                return .{ .allocator = allocator, .bytes = bytes, .image = image };
            }

            fn currentCursor(self: @This()) Chronicle.Cursor {
                return self.image.latestCursor();
            }

            fn stableRef(self: *@This(), ref: ObjectRef) !ObjectRef {
                const owned = try ref.clone(self.allocator);
                var owned_pending = true;
                errdefer if (owned_pending) {
                    var cleanup = owned;
                    cleanup.deinit(self.allocator);
                };
                try self.stable_refs.append(self.allocator, owned);
                owned_pending = false;
                var borrowed = self.stable_refs.items[self.stable_refs.items.len - 1];
                borrowed.owns_memory = false;
                return borrowed;
            }

            fn stableMoment(self: *@This(), moment: Moment) !Moment {
                const owned = try moment.clone(self.allocator);
                var owned_pending = true;
                errdefer if (owned_pending) {
                    var cleanup = owned;
                    cleanup.deinit(self.allocator);
                };
                try self.stable_moments.append(self.allocator, owned);
                owned_pending = false;
                var borrowed = self.stable_moments.items[self.stable_moments.items.len - 1];
                borrowed.owns_memory = false;
                return borrowed;
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
                if (readOptionalRef(std.heap.page_allocator, &.{2}, &ref_cursor, .{})) |_| {
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
                defer first_snapshot.deinit();
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
                const key_envelope = try conformanceIdempotencyKeyEnvelope(allocator, "idem-key", 0xA900);
                defer allocator.free(key_envelope.payload_bytes);
                defer allocator.free(key_envelope.dependency_refs);
                const key_commit = try commitMemoryEnvelope(&reopened, key_envelope);
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
            return commitMemoryEnvelope(archive, envelope);
        }

        fn commitMemoryEnvelope(archive: *Memory, envelope: ObjectEnvelope) !CommitResult {
            var tx = try archive.begin(archive.currentCursor(), .{});
            defer tx.deinit();
            const ref = try tx.putObject(envelope);
            const refs = [_]ObjectRef{ref};
            try tx.addEvent(Chronicle.Event.init(.{ .kind = .object_committed, .object_refs = &refs }));
            return .{ .moment = try tx.commit(), .ref = ref };
        }

        fn conformanceIdempotencyKeyEnvelope(allocator: std.mem.Allocator, label: []const u8, seed: u64) !ObjectEnvelope {
            const key = Actuation.IdempotencyKey.init(.{
                .target_ref_fingerprint = seed + 1,
                .world_surface_fingerprint = seed + 2,
                .world_port_id = @intCast(seed % 1024 + 1),
                .request_fingerprint = seed + 3,
                .actuator_ref_fingerprint = seed + 4,
            });
            const payload = try Continuity.encodePortableEvidence(Actuation.IdempotencyKey, allocator, key);
            errdefer allocator.free(payload);
            const seed_envelope = ObjectEnvelope.init(.{
                .kind = .actuation_idempotency_key,
                .object_format_version = key.format_version,
                .payload_bytes = payload,
                .label = label,
            });
            const deps = try Continuity.objectEnvelopeRequiredDependencyRefs(allocator, seed_envelope);
            errdefer allocator.free(deps);
            return ObjectEnvelope.init(.{
                .kind = .actuation_idempotency_key,
                .object_format_version = key.format_version,
                .payload_bytes = payload,
                .label = label,
                .dependency_refs = deps,
            });
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

        fn validateOptionalExtensionTail(bytes: []const u8, start: usize, limits: Limits) !void {
            var cursor = start;
            while (cursor < bytes.len) {
                const segment = try readSegment(bytes, &cursor, limits);
                if (segment.header.segment_kind != .optional_extension or segment.header.required) return error.InvalidFrameEncoding;
            }
        }

        fn encodeMomentData(out: *std.ArrayList(u8), allocator: std.mem.Allocator, data: MomentData) !void {
            try encodeMoment(out, allocator, data.moment);
            try encodeCommit(out, allocator, data.commit);
            try writeU64(out, allocator, data.events.len);
            for (data.events) |event| try encodeEvent(out, allocator, event);
            try writeU64(out, allocator, data.objects.len);
            for (data.objects) |object| try encodeEnvelope(out, allocator, object);
        }

        fn decodeMomentData(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) !MomentData {
            var cursor: usize = 0;
            var moment = try decodeMoment(allocator, bytes, &cursor, limits);
            errdefer moment.deinit(allocator);
            var commit = try decodeCommit(allocator, bytes, &cursor, limits);
            errdefer commit.deinit(allocator);
            const event_count = try readU64AsUsize(bytes, &cursor);
            if (event_count > limits.max_event_count_per_moment) return error.InvalidFrameEncoding;
            var events = try allocator.alloc(Chronicle.Event, event_count);
            errdefer allocator.free(events);
            var event_init: usize = 0;
            errdefer for (events[0..event_init]) |*event| event.deinit(allocator);
            for (events) |*event| {
                event.* = try decodeEvent(allocator, bytes, &cursor, limits);
                event_init += 1;
            }
            const object_count = try readU64AsUsize(bytes, &cursor);
            if (object_count > limits.max_object_count_per_moment) return error.InvalidFrameEncoding;
            var objects = try allocator.alloc(ObjectEnvelope, object_count);
            errdefer allocator.free(objects);
            var object_init: usize = 0;
            errdefer for (objects[0..object_init]) |*object| object.deinit(allocator);
            for (objects) |*object| {
                object.* = try decodeEnvelope(allocator, bytes, &cursor, limits);
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

        fn decodeMoment(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !Moment {
            const moment_format_version = try readU32(bytes, cursor);
            const moment_fingerprint_version = try readU32(bytes, cursor);
            const moment_fingerprint = try readU64(bytes, cursor);
            const sequence_number = try readU64(bytes, cursor);
            const parent_moment_fingerprint = try readOptionalU64(bytes, cursor);
            const parent_seal_fingerprint = try readOptionalU64(bytes, cursor);
            const parent_cursor = try decodeCursor(allocator, bytes, cursor, limits);
            var parent_cursor_pending = true;
            errdefer if (parent_cursor_pending) allocator.free(parent_cursor.metadata_bytes);
            const resulting_cursor = try decodeCursor(allocator, bytes, cursor, limits);
            var resulting_cursor_pending = true;
            errdefer if (resulting_cursor_pending) allocator.free(resulting_cursor.metadata_bytes);

            var moment = Moment{
                .moment_format_version = moment_format_version,
                .moment_fingerprint_version = moment_fingerprint_version,
                .moment_fingerprint = moment_fingerprint,
                .sequence_number = sequence_number,
                .parent_moment_fingerprint = parent_moment_fingerprint,
                .parent_seal_fingerprint = parent_seal_fingerprint,
                .chronicle_parent_cursor = parent_cursor,
                .chronicle_resulting_cursor = resulting_cursor,
                .chronicle_commit_ref = try decodeCommitRef(bytes, cursor),
                .owns_memory = true,
            };
            parent_cursor_pending = false;
            resulting_cursor_pending = false;
            var moment_pending = true;
            errdefer if (moment_pending) moment.deinit(allocator);
            moment.committed_event_refs = try readU64SliceOwned(allocator, bytes, cursor, limits.max_event_count_per_moment);
            moment.committed_object_refs = try readRefSliceOwnedMax(allocator, bytes, cursor, limits, limits.max_object_count_per_moment);
            moment.root_object_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.capsule_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.bundle_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.admission_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.environment_certificate_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.permit_receipt_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.link_assembly_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.fabric_receipt_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.guest_conformance_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.dependency_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            moment.projection_summary_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, max_decoded_byte_field_len / @sizeOf(u64));
            moment.idempotency_registry_summary_fingerprint = try readOptionalU64(bytes, cursor);
            moment.diagnostic_metadata_bytes = try readBytesOwned(allocator, bytes, cursor, limits);
            moment_pending = false;
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

        fn decodeCursor(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !Chronicle.Cursor {
            return .{
                .cursor_fingerprint_version = try readU32(bytes, cursor),
                .cursor_fingerprint = try readU64(bytes, cursor),
                .event_index = try readU64(bytes, cursor),
                .last_event_fingerprint = try readOptionalU64(bytes, cursor),
                .cumulative_prefix_fingerprint = try readU64(bytes, cursor),
                .committed_object_count = try readU64(bytes, cursor),
                .committed_transaction_count = try readU64(bytes, cursor),
                .metadata_bytes = try readBytesOwned(allocator, bytes, cursor, limits),
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

        fn decodeCommit(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !Chronicle.Commit {
            var commit = Chronicle.Commit{
                .commit_format_version = try readU32(bytes, cursor),
                .commit_fingerprint_version = try readU32(bytes, cursor),
                .commit_fingerprint = try readU64(bytes, cursor),
                .transaction_fingerprint = try readU64(bytes, cursor),
                .parent_cursor_fingerprint = try readU64(bytes, cursor),
                .resulting_cursor_fingerprint = try readU64(bytes, cursor),
                .owns_memory = true,
            };
            commit.committed_object_refs = try readRefSliceOwnedMax(allocator, bytes, cursor, limits, limits.max_object_count_per_moment);
            errdefer freeRefSlice(allocator, commit.committed_object_refs);
            commit.committed_event_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_event_count_per_moment);
            errdefer allocator.free(commit.committed_event_fingerprints);
            commit.bundle_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            errdefer freeRefSlice(allocator, commit.bundle_refs);
            commit.capsule_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            errdefer freeRefSlice(allocator, commit.capsule_refs);
            commit.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            errdefer freeRefSlice(allocator, commit.actuation_refs);
            commit.idempotency_key_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            errdefer freeRefSlice(allocator, commit.idempotency_key_refs);
            commit.validation_report_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            errdefer freeRefSlice(allocator, commit.validation_report_refs);
            commit.blocker_summary = try readBytesOwned(allocator, bytes, cursor, limits);
            errdefer allocator.free(commit.blocker_summary);
            commit.warning_summary = try readBytesOwned(allocator, bytes, cursor, limits);
            errdefer allocator.free(commit.warning_summary);
            commit.metadata_bytes = try readBytesOwned(allocator, bytes, cursor, limits);
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

        fn decodeEvent(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !Chronicle.Event {
            var event = Chronicle.Event{
                .event_format_version = try readU32(bytes, cursor),
                .event_fingerprint_version = try readU32(bytes, cursor),
                .event_fingerprint = try readU64(bytes, cursor),
                .kind = try enumFromByte(Chronicle.EventKind, try readU8(bytes, cursor)),
                .owns_memory = true,
            };
            var event_pending = true;
            errdefer if (event_pending) event.deinit(allocator);
            event.parent_event_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_event_count_per_moment);
            event.transaction_fingerprint = try readOptionalU64(bytes, cursor);
            event.object_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            event.root_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            event.capsule_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.actuation_refs = try readRefSliceOwned(allocator, bytes, cursor, limits);
            event.actuation_idempotency_key_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.bundle_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.recovery_plan_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.recovery_report_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.inbox_outbox_item_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.target_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.module_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.assembly_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.run_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.run_permit_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.admission_receipt_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.environment_certificate_ref = try readOptionalRef(allocator, bytes, cursor, limits);
            event.blocker_summary = try readBytesOwned(allocator, bytes, cursor, limits);
            event.warning_summary = try readBytesOwned(allocator, bytes, cursor, limits);
            event.metadata_bytes = try readBytesOwned(allocator, bytes, cursor, limits);
            event_pending = false;
            return event;
        }

        fn encodeEnvelope(out: *std.ArrayList(u8), allocator: std.mem.Allocator, envelope: ObjectEnvelope) !void {
            const encoded = try Continuity.ObjectCodec.encodeEnvelope(envelope, allocator);
            defer allocator.free(encoded);
            try writeBytes(out, allocator, encoded);
        }

        fn decodeEnvelope(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !ObjectEnvelope {
            const encoded = try readBytesOwned(allocator, bytes, cursor, limits);
            defer allocator.free(encoded);
            var envelope = try Continuity.ObjectCodec.decodeEnvelope(allocator, encoded, limits.max_ref_count);
            errdefer envelope.deinit(allocator);
            try validateEnvelopePayloadLimits(envelope, limits);
            return envelope;
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

        fn readRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !ObjectRef {
            var ref = ObjectRef{
                .ref_format_version = try readU32(bytes, cursor),
                .ref_fingerprint_version = try readU32(bytes, cursor),
                .ref_fingerprint = try readU64(bytes, cursor),
                .kind = try enumFromByte(Continuity.ObjectKind, try readU8(bytes, cursor)),
                .object_format_version = try readU32(bytes, cursor),
                .object_fingerprint = try readU64(bytes, cursor),
                .byte_len = try readU64AsUsize(bytes, cursor),
                .label = try readBytesOwned(allocator, bytes, cursor, limits),
                .metadata = "",
                .owns_memory = true,
            };
            var ref_pending = true;
            errdefer if (ref_pending) ref.deinit(allocator);
            ref.metadata = try readBytesOwned(allocator, bytes, cursor, limits);
            try ref.validate();
            ref_pending = false;
            return ref;
        }

        fn writeOptionalRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: ?ObjectRef) !void {
            try writeU8(out, allocator, if (ref == null) 0 else 1);
            if (ref) |value| try writeRef(out, allocator, value);
        }

        fn readOptionalRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) !?ObjectRef {
            return switch (try readU8(bytes, cursor)) {
                0 => null,
                1 => try readRef(allocator, bytes, cursor, limits),
                else => error.InvalidFrameEncoding,
            };
        }

        fn writeRefSlice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, refs: []const ObjectRef) !void {
            try writeU64(out, allocator, refs.len);
            for (refs) |ref| try writeRef(out, allocator, ref);
        }

        fn readRefSliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) ![]ObjectRef {
            return readRefSliceOwnedMax(allocator, bytes, cursor, limits, limits.max_ref_count);
        }

        fn readRefSliceOwnedMax(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits, max_count: usize) ![]ObjectRef {
            const count = try readU64AsUsize(bytes, cursor);
            if (count > limits.max_ref_count) return error.InvalidFrameEncoding;
            if (count > max_count) return error.InvalidFrameEncoding;
            const refs = try allocator.alloc(ObjectRef, count);
            errdefer allocator.free(refs);
            var initialized: usize = 0;
            errdefer for (refs[0..initialized]) |*ref| ref.deinit(allocator);
            for (refs) |*ref| {
                ref.* = try readRef(allocator, bytes, cursor, limits);
                initialized += 1;
            }
            return refs;
        }

        fn writeU64Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u64) !void {
            try writeU64(out, allocator, values.len);
            for (values) |value| try writeU64(out, allocator, value);
        }

        fn readU64SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_count: usize) ![]u64 {
            const count = try readU64AsUsize(bytes, cursor);
            if (count > max_count) return error.InvalidFrameEncoding;
            if (count > max_decoded_byte_field_len / @sizeOf(u64)) return error.InvalidFrameEncoding;
            const values = try allocator.alloc(u64, count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try readU64(bytes, cursor);
            return values;
        }

        fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
            try writeU64(out, allocator, bytes.len);
            try out.appendSlice(allocator, bytes);
        }

        fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Limits) ![]u8 {
            const len = try readU64AsUsize(bytes, cursor);
            if (len > limits.max_payload_bytes) return error.InvalidFrameEncoding;
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
                if (refsEquivalent(object.objectRef(), ref)) return true;
            }
            return false;
        }

        fn objectSliceContainsSemanticRef(allocator: std.mem.Allocator, objects: []const ObjectEnvelope, ref: ObjectRef) !bool {
            for (objects) |object| {
                if (try refMatchesObject(allocator, object, ref)) return true;
            }
            return false;
        }

        fn containsEquivalentRef(refs: []const ObjectRef, ref: ObjectRef) bool {
            for (refs) |candidate| {
                if (refsEquivalent(candidate, ref)) return true;
            }
            return false;
        }

        fn refsEquivalent(lhs: ObjectRef, rhs: ObjectRef) bool {
            return lhs.eql(rhs) or
                (lhs.kind == rhs.kind and
                    lhs.object_format_version == rhs.object_format_version and
                    lhs.object_fingerprint == rhs.object_fingerprint and
                    (lhs.byte_len == 0 or rhs.byte_len == 0));
        }

        fn refMatchesObject(allocator: std.mem.Allocator, object: ObjectEnvelope, ref: ObjectRef) !bool {
            return Continuity.objectEnvelopeRefMatches(allocator, object, ref);
        }

        fn validateAppendBatchLimits(allocator: std.mem.Allocator, batch: AppendBatch, limits: Limits) !void {
            try validateRefSliceLimit(batch.commit.committed_object_refs, limits);
            try validateRefSliceLimit(batch.commit.bundle_refs, limits);
            try validateRefSliceLimit(batch.commit.capsule_refs, limits);
            try validateRefSliceLimit(batch.commit.actuation_refs, limits);
            try validateRefSliceLimit(batch.commit.idempotency_key_refs, limits);
            try validateRefSliceLimit(batch.commit.validation_report_refs, limits);
            try validateCommitPayloadLimits(batch.commit, limits);
            try validateByteFieldPayloadLimit(batch.diagnostic_metadata_bytes, limits);
            if (batch.events.len > limits.max_event_count_per_moment) return error.InvalidFrameEncoding;
            if (batch.objects.len > limits.max_object_count_per_moment) return error.InvalidFrameEncoding;
            for (batch.events) |event| {
                try validateRefSliceLimit(event.object_refs, limits);
                try validateRefSliceLimit(event.root_refs, limits);
                try validateRefSliceLimit(event.actuation_refs, limits);
                try validateEventPayloadLimits(event, limits);
            }
            for (batch.objects) |object| {
                try validateRefSliceLimit(object.dependency_refs, limits);
                {
                    const encoded = try Continuity.ObjectCodec.encodeEnvelope(object, allocator);
                    defer allocator.free(encoded);
                    try validateByteFieldPayloadLimit(encoded, limits);
                }
                try validateEnvelopePayloadLimits(object, limits);
            }
        }

        fn validateRefSliceLimit(refs: []const ObjectRef, limits: Limits) !void {
            if (refs.len > limits.max_ref_count) return error.InvalidFrameEncoding;
        }

        fn validateCommitPayloadLimits(commit: Chronicle.Commit, limits: Limits) !void {
            try validateRefSlicePayloadLimits(commit.committed_object_refs, limits);
            try validateRefSlicePayloadLimits(commit.bundle_refs, limits);
            try validateRefSlicePayloadLimits(commit.capsule_refs, limits);
            try validateRefSlicePayloadLimits(commit.actuation_refs, limits);
            try validateRefSlicePayloadLimits(commit.idempotency_key_refs, limits);
            try validateRefSlicePayloadLimits(commit.validation_report_refs, limits);
            try validateByteFieldPayloadLimit(commit.blocker_summary, limits);
            try validateByteFieldPayloadLimit(commit.warning_summary, limits);
            try validateByteFieldPayloadLimit(commit.metadata_bytes, limits);
        }

        fn validateEventPayloadLimits(event: Chronicle.Event, limits: Limits) !void {
            try validateRefSlicePayloadLimits(event.object_refs, limits);
            try validateRefSlicePayloadLimits(event.root_refs, limits);
            if (event.capsule_ref) |ref| try validateRefPayloadLimits(ref, limits);
            try validateRefSlicePayloadLimits(event.actuation_refs, limits);
            if (event.actuation_idempotency_key_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.bundle_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.recovery_plan_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.recovery_report_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.inbox_outbox_item_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.target_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.module_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.assembly_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.run_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.run_permit_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.admission_receipt_ref) |ref| try validateRefPayloadLimits(ref, limits);
            if (event.environment_certificate_ref) |ref| try validateRefPayloadLimits(ref, limits);
            try validateByteFieldPayloadLimit(event.blocker_summary, limits);
            try validateByteFieldPayloadLimit(event.warning_summary, limits);
            try validateByteFieldPayloadLimit(event.metadata_bytes, limits);
        }

        fn validateEnvelopePayloadLimits(envelope: ObjectEnvelope, limits: Limits) !void {
            try validateByteFieldPayloadLimit(envelope.payload_bytes, limits);
            try validateByteFieldPayloadLimit(envelope.summary_metadata_bytes, limits);
            try validateByteFieldPayloadLimit(envelope.label, limits);
            try validateByteFieldPayloadLimit(envelope.metadata, limits);
            try validateRefSlicePayloadLimits(envelope.dependency_refs, limits);
        }

        fn validateRefSlicePayloadLimits(refs: []const ObjectRef, limits: Limits) !void {
            for (refs) |ref| try validateRefPayloadLimits(ref, limits);
        }

        fn validateRefPayloadLimits(ref: ObjectRef, limits: Limits) !void {
            try validateByteFieldPayloadLimit(ref.label, limits);
            try validateByteFieldPayloadLimit(ref.metadata, limits);
        }

        fn validateByteFieldPayloadLimit(bytes: []const u8, limits: Limits) !void {
            if (bytes.len > limits.max_payload_bytes) return error.InvalidFrameEncoding;
        }

        fn validateTypedObjectPayloads(
            allocator: std.mem.Allocator,
            prior_objects: []const ObjectEnvelope,
            objects: []const ObjectEnvelope,
        ) !void {
            const available = try allocator.alloc(ObjectEnvelope, prior_objects.len + objects.len);
            defer allocator.free(available);
            @memcpy(available[0..prior_objects.len], prior_objects);
            @memcpy(available[prior_objects.len..], objects);
            for (objects) |object| {
                try validateTypedObjectPayload(allocator, object);
                try Continuity.validateObjectEnvelopeRequiredDependencies(allocator, object);
                try Continuity.validateObjectEnvelopeDependencyPayloads(allocator, available, object);
            }
        }

        fn validateTypedObjectPayload(allocator: std.mem.Allocator, envelope: ObjectEnvelope) !void {
            try envelope.validate();
            switch (envelope.kind) {
                .actuation_intent => {
                    var intent = Actuation.Intent.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer intent.deinit(allocator);
                    if (intent.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .actuation_receipt => {
                    var receipt = Actuation.Receipt.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer receipt.deinit(allocator);
                    if (receipt.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .actuation_journal => {
                    var journal = Actuation.Journal.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer journal.deinit(allocator);
                    if (journal.fingerprint_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .value_image => {
                    var image = Frame.ValueImage.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer image.deinit(allocator);
                    if (image.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .transcript_image => {
                    var image = TranscriptImage.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer image.deinit(allocator);
                    if (image.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .run_image => {
                    var image = RunImage.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer image.deinit(allocator);
                    if (image.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .frame_request => {
                    var frame = Frame.Request.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer frame.deinit(allocator);
                    if (frame.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .frame_response => {
                    var frame = Frame.Response.decode(allocator, envelope.payload_bytes) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return error.InvalidFrameEncoding,
                    };
                    defer frame.deinit(allocator);
                    if (frame.format_version != envelope.object_format_version) return error.InvalidFrameEncoding;
                },
                .capsule_image,
                .actuator_ref,
                .actuation_descriptor,
                .actuation_binding,
                .actuation_policy,
                .actuation_idempotency_key,
                .actuation_envelope,
                .actuation_decision,
                .actuation_commit,
                .actuation_response,
                .actuation_verify_report,
                .environment_certificate,
                .run_permit,
                .run_receipt,
                .admission_receipt,
                .fabric_receipt,
                .guest_conformance_report,
                => return Continuity.validateObjectEnvelopeTypedPayload(allocator, envelope),
                else => {},
            }
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

        const SummaryRefKind = enum {
            bundle,
            capsule,
            actuation,
            idempotency_key,
            validation_report,
            admission,
            environment_certificate,
            permit_receipt,
            link_assembly,
            fabric_receipt,
            guest_conformance,
        };

        fn cursorsEqual(a: Chronicle.Cursor, b: Chronicle.Cursor) bool {
            return a.cursor_fingerprint_version == b.cursor_fingerprint_version and
                a.cursor_fingerprint == b.cursor_fingerprint and
                a.event_index == b.event_index and
                a.last_event_fingerprint == b.last_event_fingerprint and
                a.cumulative_prefix_fingerprint == b.cumulative_prefix_fingerprint and
                a.committed_object_count == b.committed_object_count and
                a.committed_transaction_count == b.committed_transaction_count and
                std.mem.eql(u8, a.metadata_bytes, b.metadata_bytes);
        }

        fn initializedArchiveCursor() Chronicle.Cursor {
            const event = Chronicle.Event.init(.{ .kind = .vault_initialized });
            return Chronicle.Cursor.initial().advance(&.{event.event_fingerprint}, 0, 0);
        }

        fn validArchiveParentCursor(expected: Chronicle.Cursor, sequence_number: u64, actual: Chronicle.Cursor) bool {
            if (actual.cursor_fingerprint == expected.cursor_fingerprint) return true;
            return sequence_number == 1 and
                expected.cursor_fingerprint == Chronicle.Cursor.initial().cursor_fingerprint and
                actual.cursor_fingerprint == initializedArchiveCursor().cursor_fingerprint;
        }

        fn summaryRefsEmptyOrMatchCommittedObjects(
            committed_refs: []const ObjectRef,
            summary_refs: []const ObjectRef,
            summary_kind: SummaryRefKind,
        ) bool {
            return summary_refs.len == 0 or summaryRefsMatchCommittedObjects(committed_refs, summary_refs, summary_kind);
        }

        fn summaryRefsMatchCommittedObjects(
            committed_refs: []const ObjectRef,
            summary_refs: []const ObjectRef,
            summary_kind: SummaryRefKind,
        ) bool {
            var summary_index: usize = 0;
            for (committed_refs) |ref| {
                if (!refMatchesSummaryKind(ref, summary_kind)) continue;
                if (summary_index >= summary_refs.len) return false;
                if (!summary_refs[summary_index].eql(ref)) return false;
                summary_index += 1;
            }
            return summary_index == summary_refs.len;
        }

        fn dependencyRefsMatchCommittedObjects(summary_refs: []const ObjectRef, objects: []const ObjectEnvelope) bool {
            var summary_index: usize = 0;
            for (objects, 0..) |object, object_index| {
                for (object.dependency_refs, 0..) |dep, dep_index| {
                    if (dependencyRefSeenBefore(objects, object_index, dep_index, dep)) continue;
                    if (summary_index >= summary_refs.len) return false;
                    if (!summary_refs[summary_index].eql(dep)) return false;
                    summary_index += 1;
                }
            }
            return summary_index == summary_refs.len;
        }

        fn dependencyRefSeenBefore(objects: []const ObjectEnvelope, object_index: usize, dep_index: usize, dep: ObjectRef) bool {
            for (objects[0..object_index]) |object| {
                if (containsRef(object.dependency_refs, dep)) return true;
            }
            return containsRef(objects[object_index].dependency_refs[0..dep_index], dep);
        }

        fn refMatchesSummaryKind(ref: ObjectRef, summary_kind: SummaryRefKind) bool {
            return switch (summary_kind) {
                .bundle => ref.kind == .bundle,
                .capsule => ref.kind == .capsule_image,
                .actuation => switch (ref.kind) {
                    .actuation_intent,
                    .actuation_envelope,
                    .actuation_decision,
                    .actuation_commit,
                    .actuation_response,
                    .actuation_receipt,
                    .actuation_journal,
                    .actuation_idempotency_key,
                    => true,
                    else => false,
                },
                .idempotency_key => ref.kind == .actuation_idempotency_key,
                .validation_report => ref.kind == .actuation_verify_report,
                .admission => ref.kind == .admission_receipt,
                .environment_certificate => ref.kind == .environment_certificate,
                .permit_receipt => ref.kind == .run_permit or ref.kind == .run_receipt,
                .link_assembly => ref.kind == .linker_certificate or ref.kind == .assembly,
                .fabric_receipt => ref.kind == .fabric_receipt,
                .guest_conformance => ref.kind == .guest_conformance_report,
            };
        }

        fn collectSummaryRefs(allocator: std.mem.Allocator, committed_refs: []const ObjectRef, summary_kind: SummaryRefKind) ![]ObjectRef {
            var refs: std.ArrayList(ObjectRef) = .empty;
            errdefer deinitRefList(&refs, allocator);
            for (committed_refs) |ref| {
                if (!refMatchesSummaryKind(ref, summary_kind)) continue;
                const owned = try ref.clone(allocator);
                var owned_pending = true;
                errdefer if (owned_pending) {
                    var cleanup = owned;
                    cleanup.deinit(allocator);
                };
                try refs.append(allocator, owned);
                owned_pending = false;
            }
            return refs.toOwnedSlice(allocator);
        }

        fn validateRefSliceUnique(refs: []const ObjectRef) !void {
            for (refs, 0..) |ref, index| {
                for (refs[0..index]) |prior| {
                    if (ref.eql(prior)) return error.InvalidFrameEncoding;
                }
            }
        }

        fn validateDomainEventRefsKnown(allocator: std.mem.Allocator, events: []const Chronicle.Event, prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope) !void {
            for (events) |event| {
                try validateKnownEventRefSlice(allocator, prior_objects, current_objects, event.object_refs);
                try validateKnownEventRefSlice(allocator, prior_objects, current_objects, event.root_refs);
                if (event.capsule_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .capsule, ref);
                try validateKnownEventRefSlice(allocator, prior_objects, current_objects, event.actuation_refs);
                if (event.actuation_idempotency_key_ref) |ref| try validateKnownActuationIdempotencyKeyRef(allocator, prior_objects, current_objects, event, ref);
                if (event.bundle_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .bundle, ref);
                if (event.recovery_plan_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .recovery_plan, ref);
                if (event.recovery_report_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .recovery_report, ref);
                if (event.inbox_outbox_item_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .inbox_outbox_item, ref);
                if (event.target_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .target, ref);
                if (event.module_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .module, ref);
                if (event.assembly_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .assembly, ref);
                if (event.run_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .run, ref);
                if (event.run_permit_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .run_permit, ref);
                if (event.admission_receipt_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .admission_receipt, ref);
                if (event.environment_certificate_ref) |ref| try validateKnownOrSemanticEventRef(allocator, prior_objects, current_objects, event.kind, .environment_certificate, ref);
            }
        }

        const EventRefRole = enum {
            capsule,
            bundle,
            recovery_plan,
            recovery_report,
            inbox_outbox_item,
            target,
            module,
            assembly,
            run,
            run_permit,
            admission_receipt,
            environment_certificate,
        };

        fn validateKnownOrSemanticEventRef(
            allocator: std.mem.Allocator,
            prior_objects: []const ObjectEnvelope,
            current_objects: []const ObjectEnvelope,
            event_kind: Chronicle.EventKind,
            role: EventRefRole,
            ref: ObjectRef,
        ) !void {
            if (eventKindAllowsSemanticEventRef(event_kind, role) and ref.byte_len == 0) {
                try ref.validate();
                if (!semanticEventRefMatchesRole(role, ref)) return error.InvalidFrameEncoding;
                return;
            }
            return validateKnownEventRef(allocator, prior_objects, current_objects, ref);
        }

        fn eventKindAllowedInCommittedMoment(event_kind: Chronicle.EventKind) bool {
            return switch (event_kind) {
                .vault_initialized => false,
                else => true,
            };
        }

        fn eventKindAllowsSemanticEventRef(event_kind: Chronicle.EventKind, role: EventRefRole) bool {
            return switch (role) {
                .bundle => switch (event_kind) {
                    .bundle_import_started,
                    .bundle_import_validated,
                    .bundle_import_committed,
                    .bundle_import_rejected,
                    .bundle_export_started,
                    .bundle_export_committed,
                    .bundle_export_rejected,
                    => true,
                    else => false,
                },
                .capsule => switch (event_kind) {
                    .bundle_import_committed,
                    .capsule_recovery_planned,
                    .capsule_recovery_rejected,
                    .capsule_recovery_ready,
                    .capsule_restored,
                    .capsule_replay_planned,
                    .capsule_replayed,
                    .recovery_preflighted,
                    .recovery_blocked,
                    .recovery_ready,
                    .recovery_executed,
                    => true,
                    else => false,
                },
                .recovery_plan => switch (event_kind) {
                    .capsule_recovery_planned,
                    .capsule_recovery_rejected,
                    .capsule_recovery_ready,
                    .recovery_preflighted,
                    .recovery_blocked,
                    .recovery_ready,
                    .recovery_executed,
                    => true,
                    else => false,
                },
                .recovery_report => switch (event_kind) {
                    .capsule_restored,
                    .recovery_executed,
                    .recovery_report_stored,
                    => true,
                    else => false,
                },
                .inbox_outbox_item => switch (event_kind) {
                    .inbox_item_created,
                    .inbox_item_validated,
                    .inbox_item_accepted,
                    .inbox_item_rejected,
                    .inbox_item_restored,
                    .outbox_item_created,
                    .outbox_item_exported,
                    .outbox_item_completed,
                    => true,
                    else => false,
                },
                else => false,
            };
        }

        fn semanticEventRefMatchesRole(role: EventRefRole, ref: ObjectRef) bool {
            return switch (role) {
                .bundle => ref.kind == .bundle,
                .capsule => ref.kind == .capsule_image,
                .recovery_plan => ref.kind == .capsule_thaw_plan,
                .recovery_report => ref.kind == .capsule_restore_report,
                .inbox_outbox_item => ref.kind == .handoff_envelope,
                else => false,
            };
        }

        fn validateKnownEventRefSlice(allocator: std.mem.Allocator, prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope, refs: []const ObjectRef) !void {
            for (refs) |ref| try validateKnownEventRef(allocator, prior_objects, current_objects, ref);
        }

        fn validateKnownEventRef(allocator: std.mem.Allocator, prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope, ref: ObjectRef) !void {
            if (try objectSliceContainsSemanticRef(allocator, current_objects, ref) or try objectSliceContainsSemanticRef(allocator, prior_objects, ref)) return;
            return error.InvalidFrameEncoding;
        }

        fn validateKnownActuationIdempotencyKeyRef(
            allocator: std.mem.Allocator,
            prior_objects: []const ObjectEnvelope,
            current_objects: []const ObjectEnvelope,
            event: Chronicle.Event,
            ref: ObjectRef,
        ) !void {
            if (try objectSliceContainsSemanticRef(allocator, current_objects, ref) or try objectSliceContainsSemanticRef(allocator, prior_objects, ref)) return;
            if (event.kind == .actuation_idempotency_registered and ref.kind == .actuation_idempotency_key and event.actuation_refs.len != 0) {
                if (ref.byte_len != 0) return error.InvalidFrameEncoding;
                for (event.actuation_refs) |actuation_ref| {
                    if (try actuationReceiptBindsIdempotencyKey(allocator, current_objects, actuation_ref, ref)) return;
                    if (try actuationReceiptBindsIdempotencyKey(allocator, prior_objects, actuation_ref, ref)) return;
                }
            }
            return error.InvalidFrameEncoding;
        }

        fn actuationReceiptBindsIdempotencyKey(
            allocator: std.mem.Allocator,
            objects: []const ObjectEnvelope,
            actuation_ref: ObjectRef,
            key_ref: ObjectRef,
        ) !bool {
            for (objects) |object| {
                if (object.kind != .actuation_receipt or !try refMatchesObject(allocator, object, actuation_ref)) continue;
                var receipt = Actuation.Receipt.decode(allocator, object.payload_bytes) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return false,
                };
                defer receipt.deinit(allocator);
                return receipt.idempotency_key_fingerprint == key_ref.object_fingerprint;
            }
            return false;
        }

        fn validateObjectDependenciesKnown(allocator: std.mem.Allocator, prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope) !void {
            for (current_objects, 0..) |object, object_index| {
                for (object.dependency_refs) |dep| {
                    if (try objectSliceContainsSemanticRef(allocator, prior_objects, dep) or try objectSliceContainsSemanticRef(allocator, current_objects[0..object_index], dep)) continue;
                    if (dep.byte_len == 0 and envelopeKindAllowsUnresolvedSemanticDependency(object.kind)) continue;
                    return error.ObjectMissing;
                }
            }
            try rejectObjectDependencyCycles(allocator, prior_objects, current_objects);
        }

        const ObjectDependencyVisitState = enum(u2) {
            unvisited,
            visiting,
            visited,
        };

        fn rejectObjectDependencyCycles(allocator: std.mem.Allocator, prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope) !void {
            const objects = try allocator.alloc(ObjectEnvelope, prior_objects.len + current_objects.len);
            defer allocator.free(objects);
            @memcpy(objects[0..prior_objects.len], prior_objects);
            @memcpy(objects[prior_objects.len..], current_objects);

            const states = try allocator.alloc(ObjectDependencyVisitState, objects.len);
            defer allocator.free(states);
            @memset(states, .unvisited);
            for (objects, 0..) |_, index| {
                try visitObjectDependency(allocator, objects, states, index);
            }
        }

        fn visitObjectDependency(allocator: std.mem.Allocator, current_objects: []const ObjectEnvelope, states: []ObjectDependencyVisitState, index: usize) !void {
            switch (states[index]) {
                .visited => return,
                .visiting => return error.InvalidFrameEncoding,
                .unvisited => {},
            }
            states[index] = .visiting;
            for (current_objects[index].dependency_refs) |dep| {
                const dependency_index = (try objectSliceIndexOfRef(allocator, current_objects, dep)) orelse continue;
                try visitObjectDependency(allocator, current_objects, states, dependency_index);
            }
            states[index] = .visited;
        }

        fn objectSliceIndexOfRef(allocator: std.mem.Allocator, objects: []const ObjectEnvelope, ref: ObjectRef) !?usize {
            for (objects, 0..) |object, index| {
                if (try refMatchesObject(allocator, object, ref)) return index;
            }
            return null;
        }

        fn envelopeKindAllowsUnresolvedSemanticDependency(kind: Continuity.ObjectKind) bool {
            return switch (kind) {
                .actuation_descriptor,
                .actuation_binding,
                .actuation_idempotency_key,
                .actuation_intent,
                .actuation_envelope,
                .actuation_decision,
                .actuation_commit,
                .actuation_response,
                .actuation_receipt,
                .actuation_journal,
                .actuation_verify_report,
                .run_permit,
                .run_receipt,
                .admission_receipt,
                .fabric_receipt,
                .frame_response,
                .run_image,
                .guest_conformance_report,
                .capsule_image,
                => true,
                else => false,
            };
        }

        fn rejectAlreadyCommittedObjectRefs(prior_objects: []const ObjectEnvelope, current_objects: []const ObjectEnvelope) !void {
            for (current_objects) |object| {
                if (objectSliceContainsRef(prior_objects, object.objectRef())) return error.DuplicateBinding;
            }
        }

        fn recoverableTailError(err: anyerror) bool {
            return switch (err) {
                error.OutOfMemory => false,
                else => true,
            };
        }

        fn bindEventTransaction(event: Chronicle.Event, transaction_fingerprint: u64) Chronicle.Event {
            return eventWithTransaction(event, transaction_fingerprint);
        }

        fn eventWithTransaction(event: Chronicle.Event, transaction_fingerprint: ?u64) Chronicle.Event {
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

        fn transactionFingerprint(parent: Chronicle.Cursor, staged_objects: []const ObjectEnvelope, staged_events: []const Chronicle.Event) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.archive.transaction");
            hashU64(&hasher, parent.cursor_fingerprint);
            hashU64(&hasher, staged_objects.len);
            for (staged_objects) |object| {
                hashU64(&hasher, object.objectRef().ref_fingerprint);
                hashU64(&hasher, object.envelope_fingerprint);
            }
            var domain_event_count: usize = 0;
            for (staged_events) |event| {
                if (event.kind != .object_committed) domain_event_count += 1;
            }
            hashU64(&hasher, domain_event_count);
            for (staged_events) |event| {
                if (event.kind == .object_committed) continue;
                hashU64(&hasher, eventWithTransaction(event, null).event_fingerprint);
            }
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
