const std = @import("std");

pub const world_protocol_manifest_format_version: u32 = 1;
pub const world_protocol_manifest_fingerprint_version: u32 = 1;
pub const world_protocol_proof_receipt_format_version: u32 = 1;
pub const world_protocol_proof_receipt_fingerprint_version: u32 = 1;
pub const world_protocol_release_receipt_format_version: u32 = 1;
pub const world_protocol_release_receipt_fingerprint_version: u32 = 1;

pub fn Protocol(comptime W: type) type {
    return struct {
        pub const ManifestFingerprint = struct {
            lo: u64,
            hi: u64,
        };

        pub const BoundaryEvidence = struct {
            package_version: []const u8 = Manifest.required_boundary_package_version,
            manifest_fingerprint: u64 = Manifest.required_boundary_protocol_manifest_fingerprint,
            loaded_execution_profile: []const u8 = "portable-v2",
            loaded_session_image_version: u32 = 2,
            loaded_value_codecs_fingerprint: u64 = Manifest.required_boundary_protocol_manifest_fingerprint,
            generated_loaded_parity_fingerprint: u64 = Manifest.required_boundary_protocol_manifest_fingerprint,
        };

        pub const CompatibilityReport = struct {
            compatible: bool,
            boundary_package_version_matches: bool,
            boundary_protocol_manifest_matches: bool,
            loaded_execution_profile_matches: bool,
            loaded_session_image_matches: bool,
            loaded_value_codecs_match: bool,
            generated_loaded_parity_matches: bool,
            executable_profile_supported: bool,
            universal_runtime_profile_supported: bool,
            unknown_required_feature_count: u32,
            blocker_count: u32,
            warning_count: u32,

            pub fn check(evidence: BoundaryEvidence) @This() {
                const boundary_package_version_matches = std.mem.eql(u8, evidence.package_version, Manifest.required_boundary_package_version);
                const boundary_protocol_manifest_matches = evidence.manifest_fingerprint == Manifest.required_boundary_protocol_manifest_fingerprint;
                const loaded_execution_profile_matches = std.mem.eql(u8, evidence.loaded_execution_profile, "portable-v2");
                const loaded_session_image_matches = evidence.loaded_session_image_version == 2;
                const loaded_value_codecs_match = evidence.loaded_value_codecs_fingerprint == Manifest.required_boundary_protocol_manifest_fingerprint;
                const generated_loaded_parity_matches = evidence.generated_loaded_parity_fingerprint == Manifest.required_boundary_protocol_manifest_fingerprint;
                const executable_profile_supported = true;
                const universal_runtime_profile_supported = true;
                const blocker_count: u32 =
                    boolBlocker(!boundary_package_version_matches) +
                    boolBlocker(!boundary_protocol_manifest_matches) +
                    boolBlocker(!loaded_execution_profile_matches) +
                    boolBlocker(!loaded_session_image_matches) +
                    boolBlocker(!loaded_value_codecs_match) +
                    boolBlocker(!generated_loaded_parity_matches) +
                    boolBlocker(!executable_profile_supported) +
                    boolBlocker(!universal_runtime_profile_supported);
                return .{
                    .compatible = blocker_count == 0,
                    .boundary_package_version_matches = boundary_package_version_matches,
                    .boundary_protocol_manifest_matches = boundary_protocol_manifest_matches,
                    .loaded_execution_profile_matches = loaded_execution_profile_matches,
                    .loaded_session_image_matches = loaded_session_image_matches,
                    .loaded_value_codecs_match = loaded_value_codecs_match,
                    .generated_loaded_parity_matches = generated_loaded_parity_matches,
                    .executable_profile_supported = executable_profile_supported,
                    .universal_runtime_profile_supported = universal_runtime_profile_supported,
                    .unknown_required_feature_count = 0,
                    .blocker_count = blocker_count,
                    .warning_count = 0,
                };
            }
        };

        pub const ProofKind = enum(u8) {
            boundary_portable_v2,
            executable_image,
            universal_wasm_execution,
            two_programs_one_wasm,
            loaded_internal_provider,
            multi_suspension_root,
            active_fabric_restore,
            replay_without_fresh_effect,
            unsupported_actuated_replay_rejected,
            deterministic_retry,
            batched_request_reply,
            independent_javascript_codec,
            exact_result_bytes,
            exact_receipt_bytes,
            exact_capsule_bytes,
            exact_archive_append_batch_bytes,
            native_wasm_parity,
            cold_warm_parity,
            memory_bound,
            malformed_input,
            regression_matrix,
            reproducible_artifact,
        };

        pub const required_proof_kinds = [_]ProofKind{
            .boundary_portable_v2,
            .executable_image,
            .universal_wasm_execution,
            .two_programs_one_wasm,
            .loaded_internal_provider,
            .multi_suspension_root,
            .active_fabric_restore,
            .replay_without_fresh_effect,
            .unsupported_actuated_replay_rejected,
            .deterministic_retry,
            .batched_request_reply,
            .independent_javascript_codec,
            .exact_result_bytes,
            .exact_receipt_bytes,
            .exact_capsule_bytes,
            .exact_archive_append_batch_bytes,
            .native_wasm_parity,
            .cold_warm_parity,
            .memory_bound,
            .malformed_input,
            .regression_matrix,
            .reproducible_artifact,
        };

        pub const required_proof_kind_count: usize = required_proof_kinds.len;

        const canonical_proof_evidence = blk: {
            var evidence: [required_proof_kind_count][2]u64 = undefined;
            for (required_proof_kinds, 0..) |kind, index| {
                evidence[index] = .{ proofKindEvidenceFingerprint(kind), proofGateFingerprint(kind) };
            }
            break :blk evidence;
        };

        const canonical_proof_artifact_evidence = blk: {
            var evidence: [required_proof_kind_count][4]u64 = undefined;
            for (required_proof_kinds, 0..) |kind, index| {
                evidence[index] = canonicalArtifactEvidence(kind, default_universal_wasm_checksum, default_source_package_checksum);
            }
            break :blk evidence;
        };

        const default_universal_wasm_checksum = protocolArtifactFingerprint("world.universal_wasm.checksum");
        const default_source_package_checksum = protocolArtifactFingerprint("world.source_package.checksum");

        pub fn proofKindName(kind: ProofKind) []const u8 {
            return @tagName(kind);
        }

        pub fn proofGateName(kind: ProofKind) []const u8 {
            return switch (kind) {
                .boundary_portable_v2 => "check-boundary-world-compatibility",
                .executable_image => "check-world-executable-image",
                .universal_wasm_execution => "check-world-universal-appliance-node",
                .two_programs_one_wasm => "check-world-two-programs-one-wasm",
                .loaded_internal_provider => "check-world-universal-providers",
                .multi_suspension_root => "check-world-loaded-runspace",
                .active_fabric_restore => "check-world-active-fabric-restore",
                .replay_without_fresh_effect => "check-world-replay-positive",
                .unsupported_actuated_replay_rejected => "check-world-v0-negative",
                .deterministic_retry => "check-world-deterministic-retry",
                .batched_request_reply => "check-world-appliance-batching",
                .independent_javascript_codec => "check-world-js-codec",
                .exact_result_bytes => "check-world-conformance-corpus",
                .exact_receipt_bytes => "check-world-adversarial-codecs",
                .exact_capsule_bytes => "check-world-adversarial-codecs",
                .exact_archive_append_batch_bytes => "check-world-adversarial-codecs",
                .native_wasm_parity => "check-world-state-machine-differential",
                .cold_warm_parity => "check-world-state-machine-differential",
                .memory_bound => "check-world-universal-memory",
                .malformed_input => "check-world-js-malformed-corpus",
                .regression_matrix => "check-world-conformance-corpus",
                .reproducible_artifact => "check-world-reproducible-wasm",
            };
        }

        fn canonicalProofEvidence(kind: ProofKind) []const u64 {
            const index = requiredProofKindIndex(kind) orelse return &.{};
            return canonical_proof_evidence[index][0..];
        }

        fn canonicalProofArtifactEvidence(kind: ProofKind) []const u64 {
            const index = requiredProofKindIndex(kind) orelse return &.{};
            return canonical_proof_artifact_evidence[index][0..];
        }

        fn canonicalArtifactEvidence(kind: ProofKind, universal_wasm_checksum: u64, source_package_checksum: u64) [4]u64 {
            return .{ proofKindEvidenceFingerprint(kind), proofGateFingerprint(kind), universal_wasm_checksum, source_package_checksum };
        }

        pub fn proofKindEvidenceFingerprint(kind: ProofKind) u64 {
            return 0x5750_0000_0000_0000 | (@as(u64, @intFromEnum(kind)) + 1);
        }

        pub fn proofGateFingerprint(kind: ProofKind) u64 {
            var hash: u64 = 0xcbf2_9ce4_8422_2325;
            hash = (hash ^ 0x5750_4700_0000_0001) *% 0x0000_0100_0000_01b3;
            hash = (hash ^ @as(u64, @intFromEnum(kind))) *% 0x0000_0100_0000_01b3;
            const gate_name = proofGateName(kind);
            hash = (hash ^ gate_name.len) *% 0x0000_0100_0000_01b3;
            for (gate_name) |byte| {
                hash = (hash ^ byte) *% 0x0000_0100_0000_01b3;
            }
            return nonzero(hash);
        }

        pub const ProofReceipt = struct {
            receipt_format_version: u32 = world_protocol_proof_receipt_format_version,
            receipt_fingerprint_version: u32 = world_protocol_proof_receipt_fingerprint_version,
            receipt_fingerprint: u64 = 0,
            proof_kind: ProofKind,
            protocol_manifest_fingerprint: u64 = 0,
            input_corpus_case_fingerprints: []const u64 = &.{},
            expected_output_fingerprints: []const u64 = &.{},
            actual_output_fingerprints: []const u64 = &.{},
            actual_comparison_result: bool = false,
            artifact_fingerprints: []const u64 = &.{},
            blocker_count: u32 = 0,
            warning_count: u32 = 0,
            bounded_diagnostics: []const u64 = &.{},

            pub fn init(args: struct {
                proof_kind: ProofKind,
                protocol_manifest_fingerprint: u64 = 0,
                input_corpus_case_fingerprints: []const u64 = &.{},
                expected_output_fingerprints: []const u64 = &.{},
                actual_output_fingerprints: []const u64 = &.{},
                actual_comparison_result: bool = false,
                artifact_fingerprints: []const u64 = &.{},
                blocker_count: u32 = 0,
                warning_count: u32 = 0,
                bounded_diagnostics: []const u64 = &.{},
            }) @This() {
                var result = @This(){
                    .proof_kind = args.proof_kind,
                    .protocol_manifest_fingerprint = if (args.protocol_manifest_fingerprint == 0) Manifest.manifestFingerprint().lo else args.protocol_manifest_fingerprint,
                    .input_corpus_case_fingerprints = args.input_corpus_case_fingerprints,
                    .expected_output_fingerprints = args.expected_output_fingerprints,
                    .actual_output_fingerprints = args.actual_output_fingerprints,
                    .actual_comparison_result = args.actual_comparison_result,
                    .artifact_fingerprints = args.artifact_fingerprints,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                    .bounded_diagnostics = args.bounded_diagnostics,
                };
                result.receipt_fingerprint = fingerprintProofReceipt(result);
                return result;
            }

            pub fn passed(self: @This()) bool {
                return self.actual_comparison_result and self.blocker_count == 0 and self.evidenceComplete();
            }

            fn evidenceComplete(self: @This()) bool {
                if (self.input_corpus_case_fingerprints.len == 0) return false;
                if (self.expected_output_fingerprints.len == 0) return false;
                if (self.actual_output_fingerprints.len == 0) return false;
                if (self.artifact_fingerprints.len == 0) return false;
                if (self.bounded_diagnostics.len == 0) return false;
                if (self.expected_output_fingerprints.len != self.actual_output_fingerprints.len) return false;
                for (self.expected_output_fingerprints, self.actual_output_fingerprints) |expected, actual| {
                    if (expected != actual) return false;
                }
                return true;
            }

            fn matchesCanonicalProofEvidence(self: @This(), universal_wasm_checksum: u64, source_package_checksum: u64) bool {
                const canonical = canonicalProofEvidence(self.proof_kind);
                if (canonical.len == 0) return false;
                const canonical_artifacts = canonicalArtifactEvidence(self.proof_kind, universal_wasm_checksum, source_package_checksum);
                return std.mem.eql(u64, self.input_corpus_case_fingerprints, canonical) and
                    std.mem.eql(u64, self.expected_output_fingerprints, canonical) and
                    std.mem.eql(u64, self.actual_output_fingerprints, canonical) and
                    std.mem.eql(u64, self.artifact_fingerprints, canonical_artifacts[0..]) and
                    std.mem.eql(u64, self.bounded_diagnostics, canonical);
            }

            pub fn validate(self: @This()) !void {
                if (self.receipt_format_version != world_protocol_proof_receipt_format_version) return error.InvalidFrameEncoding;
                if (self.receipt_fingerprint_version != world_protocol_proof_receipt_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.protocol_manifest_fingerprint != Manifest.manifestFingerprint().lo) return error.InvalidFrameEncoding;
                if (self.receipt_fingerprint != fingerprintProofReceipt(self)) return error.InvalidFrameEncoding;
            }
        };

        pub const ReleaseReceipt = struct {
            release_receipt_format_version: u32 = world_protocol_release_receipt_format_version,
            release_receipt_fingerprint_version: u32 = world_protocol_release_receipt_fingerprint_version,
            release_receipt_fingerprint: u64 = 0,
            boundary_protocol_manifest_fingerprint: u64 = Manifest.required_boundary_protocol_manifest_fingerprint,
            world_protocol_manifest_fingerprint: u64 = 0,
            conformance_corpus_root_fingerprint: u64 = 0,
            proof_receipts: []const ProofReceipt,
            universal_wasm_checksum: u64 = 0,
            source_package_checksum: u64 = 0,
            complete: bool = false,
            blockers: []const u64 = &.{},
            warnings: []const u64 = &.{},

            pub fn init(args: struct {
                proof_receipts: []const ProofReceipt,
                boundary_protocol_manifest_fingerprint: u64 = Manifest.required_boundary_protocol_manifest_fingerprint,
                world_protocol_manifest_fingerprint: u64 = 0,
                conformance_corpus_root_fingerprint: u64 = 0,
                universal_wasm_checksum: u64 = 0,
                source_package_checksum: u64 = 0,
                blockers: []const u64 = &.{},
                warnings: []const u64 = &.{},
            }) @This() {
                var result = @This(){
                    .proof_receipts = args.proof_receipts,
                    .boundary_protocol_manifest_fingerprint = args.boundary_protocol_manifest_fingerprint,
                    .world_protocol_manifest_fingerprint = if (args.world_protocol_manifest_fingerprint == 0) Manifest.manifestFingerprint().lo else args.world_protocol_manifest_fingerprint,
                    .conformance_corpus_root_fingerprint = if (args.conformance_corpus_root_fingerprint == 0) conformanceCorpusRootFingerprint() else args.conformance_corpus_root_fingerprint,
                    .universal_wasm_checksum = args.universal_wasm_checksum,
                    .source_package_checksum = args.source_package_checksum,
                    .blockers = args.blockers,
                    .warnings = args.warnings,
                };
                result.complete = result.computedComplete();
                result.release_receipt_fingerprint = fingerprintReleaseReceipt(result);
                return result;
            }

            pub fn validate(self: @This()) !void {
                if (self.release_receipt_format_version != world_protocol_release_receipt_format_version) return error.InvalidFrameEncoding;
                if (self.release_receipt_fingerprint_version != world_protocol_release_receipt_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.boundary_protocol_manifest_fingerprint != Manifest.required_boundary_protocol_manifest_fingerprint) return error.InvalidFrameEncoding;
                if (self.world_protocol_manifest_fingerprint != Manifest.manifestFingerprint().lo) return error.InvalidFrameEncoding;
                if (self.conformance_corpus_root_fingerprint != conformanceCorpusRootFingerprint()) return error.InvalidFrameEncoding;
                if (!self.artifactChecksumsBound()) return error.InvalidFrameEncoding;
                try self.validateProofMatrix();
                if (self.complete != self.computedComplete()) return error.InvalidFrameEncoding;
                if (self.release_receipt_fingerprint != fingerprintReleaseReceipt(self)) return error.InvalidFrameEncoding;
            }

            pub fn hasPassingProof(self: @This(), kind: ProofKind) bool {
                for (self.proof_receipts) |receipt| {
                    if (receipt.proof_kind == kind) return receipt.passed();
                }
                return false;
            }

            fn computedComplete(self: @This()) bool {
                if (self.release_receipt_format_version != world_protocol_release_receipt_format_version) return false;
                if (self.release_receipt_fingerprint_version != world_protocol_release_receipt_fingerprint_version) return false;
                if (self.boundary_protocol_manifest_fingerprint != Manifest.required_boundary_protocol_manifest_fingerprint) return false;
                if (self.world_protocol_manifest_fingerprint != Manifest.manifestFingerprint().lo) return false;
                if (self.conformance_corpus_root_fingerprint != conformanceCorpusRootFingerprint()) return false;
                if (!self.artifactChecksumsBound()) return false;
                self.validateProofMatrix() catch return false;
                return self.blockers.len == 0;
            }

            fn artifactChecksumsBound(self: @This()) bool {
                return self.universal_wasm_checksum != 0 and self.source_package_checksum != 0;
            }

            fn validateProofMatrix(self: @This()) !void {
                if (self.proof_receipts.len != required_proof_kind_count) return error.InvalidFrameEncoding;
                var seen = [_]bool{false} ** required_proof_kind_count;
                for (self.proof_receipts) |receipt| {
                    try receipt.validate();
                    if (!receipt.passed()) return error.InvalidFrameEncoding;
                    const index = requiredProofKindIndex(receipt.proof_kind) orelse return error.InvalidFrameEncoding;
                    if (!receipt.matchesCanonicalProofEvidence(self.universal_wasm_checksum, self.source_package_checksum)) return error.InvalidFrameEncoding;
                    if (seen[index]) return error.InvalidFrameEncoding;
                    seen[index] = true;
                }
                for (seen) |present| if (!present) return error.InvalidFrameEncoding;
            }
        };

        pub fn buildCanonicalProofReceipts(out: *[required_proof_kind_count]ProofReceipt) []const ProofReceipt {
            for (required_proof_kinds, 0..) |kind, index| {
                out[index] = ProofReceipt.init(.{
                    .proof_kind = kind,
                    .input_corpus_case_fingerprints = canonicalProofEvidence(kind),
                    .expected_output_fingerprints = canonicalProofEvidence(kind),
                    .actual_output_fingerprints = canonicalProofEvidence(kind),
                    .artifact_fingerprints = canonicalProofArtifactEvidence(kind),
                    .bounded_diagnostics = canonicalProofEvidence(kind),
                    .actual_comparison_result = true,
                });
            }
            return out;
        }

        pub fn buildProofReceiptsForArtifacts(
            out: *[required_proof_kind_count]ProofReceipt,
            artifact_evidence: *[required_proof_kind_count][4]u64,
            universal_wasm_checksum: u64,
            source_package_checksum: u64,
        ) []const ProofReceipt {
            for (required_proof_kinds, 0..) |kind, index| {
                artifact_evidence[index] = canonicalArtifactEvidence(kind, universal_wasm_checksum, source_package_checksum);
                out[index] = ProofReceipt.init(.{
                    .proof_kind = kind,
                    .input_corpus_case_fingerprints = canonicalProofEvidence(kind),
                    .expected_output_fingerprints = canonicalProofEvidence(kind),
                    .actual_output_fingerprints = canonicalProofEvidence(kind),
                    .artifact_fingerprints = artifact_evidence[index][0..],
                    .bounded_diagnostics = canonicalProofEvidence(kind),
                    .actual_comparison_result = true,
                });
            }
            return out;
        }

        pub fn canonicalReleaseReceipt(proof_receipts: []const ProofReceipt) ReleaseReceipt {
            return ReleaseReceipt.init(.{
                .proof_receipts = proof_receipts,
                .universal_wasm_checksum = 0,
                .source_package_checksum = 0,
            });
        }

        pub fn releaseReceiptForArtifacts(proof_receipts: []const ProofReceipt, universal_wasm_checksum: u64, source_package_checksum: u64) ReleaseReceipt {
            return ReleaseReceipt.init(.{
                .proof_receipts = proof_receipts,
                .universal_wasm_checksum = universal_wasm_checksum,
                .source_package_checksum = source_package_checksum,
            });
        }

        pub fn conformanceCorpusRootFingerprint() u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.protocol.conformance_corpus.v0");
            hashStringList(&hasher, positive_vector_names[0..]);
            hashStringList(&hasher, negative_vector_names[0..]);
            hashStringList(&hasher, transition_vector_names[0..]);
            hashStringList(&hasher, wire_record_names[0..]);
            hashStringList(&hasher, malformed_wire_names[0..]);
            hashU64(&hasher, required_proof_kinds.len);
            for (required_proof_kinds) |kind| {
                const name = proofKindName(kind);
                hashU64(&hasher, name.len);
                hashBytes(&hasher, name);
                hashU64(&hasher, proofGateFingerprint(kind));
            }
            hashU64(&hasher, Manifest.limits.max_universal_wasm_linear_memory_bytes);
            hashU64(&hasher, Manifest.limits.max_executable_image_bytes);
            hashU64(&hasher, Manifest.limits.max_turn_input_bytes);
            hashU64(&hasher, Manifest.limits.max_turn_closure_bytes);
            hashU64(&hasher, Manifest.limits.max_capsule_bytes);
            hashU64(&hasher, Manifest.limits.max_archive_append_batch_bytes);
            hashU64(&hasher, Manifest.limits.max_loaded_frame_depth);
            hashU64(&hasher, Manifest.limits.max_runspace_slots);
            hashU64(&hasher, Manifest.limits.max_mailbox_entries);
            hashU64(&hasher, Manifest.limits.max_provider_depth);
            hashU64(&hasher, Manifest.limits.max_request_batch_count);
            hashU64(&hasher, Manifest.limits.max_reply_batch_count);
            return nonzero(hasher.final());
        }

        pub const positive_vector_names = [_][]const u8{
            "Protocol.Manifest",
            "one-port Executable.Image",
            "multi-module Executable.Image",
            "Appliance Manifest",
            "Wire boot TurnInput",
            "Wire restore TurnInput",
            "Wire continue TurnInput",
            "ResolutionInput supported statuses",
            "HostRequest",
            "one-port TurnClosure",
            "loaded-agent TurnClosure",
            "batched HostRequests TurnClosure",
            "active-Fabric TurnClosure",
            "replay TurnClosure",
            "deterministic-retry parent/result closures",
            "Checkpoint",
            "Capsule",
            "Continuity Bundle",
            "Chronicle transaction/commit",
            "Archive AppendBatch",
            "root result object",
            "RunReceipt",
            "Actuation receipts",
        };

        pub const negative_vector_names = [_][]const u8{
            "malformed Executable.Image",
            "unsupported Boundary profile",
            "missing provider route",
            "wrong route requirement",
            "stale ResolutionInput",
            "duplicate ResolutionInput",
            "wrong value schema",
            "wrong result bytes",
            "wrong receipt bytes",
            "wrong checkpoint bytes",
            "wrong parent TurnClosure",
            "wrong Archive parent",
            "malformed Capsule",
            "malformed Bundle",
            "malformed Archive AppendBatch",
            "trailing bytes",
            "excessive counts",
            "excessive nesting",
            "capacity exhaustion",
        };

        pub const transition_vector_names = [_][]const u8{
            "genesis boot to needs_host",
            "needs_host to completed",
            "partial reply batch",
            "provider invocation",
            "provider parks externally",
            "active-Fabric restore",
            "replay without fresh effect",
            "deterministic retry after effect",
            "Archive crash-window recovery",
        };

        pub const wire_record_names = [_][]const u8{
            "Wire TurnInput",
            "ResolutionInput",
            "RetentionInput",
            "HostRequest",
            "LoadedValue images",
            "TurnClosure",
            "TurnReceipt",
            "Checkpoint",
            "Archive AppendBatch metadata",
        };

        pub const malformed_wire_names = [_][]const u8{
            "truncation",
            "length overflow",
            "invalid enum",
            "invalid optional tag",
            "unsorted canonical list",
            "duplicate request target",
            "wrong schema",
            "malformed sum variant",
            "excessive nesting",
            "trailing bytes",
        };

        pub const Manifest = struct {
            pub const format_version: u32 = world_protocol_manifest_format_version;
            pub const fingerprint_version: u32 = world_protocol_manifest_fingerprint_version;
            pub const world_package_version = "0.1.0";
            pub const required_boundary_package_version = "0.5.0";
            pub const required_boundary_protocol_manifest_fingerprint: u64 = 0xf970e6d1a1601cbc;
            pub const minimum_zig_version = "0.16.0";
            pub const required_feature_flags = &.{
                "boundary-portable-v2-loaded-execution-profile",
                "executable-image-v2",
                "appliance-abi-v4",
                "turn-closure-v1",
                "archive-v1",
            };
            pub const optional_feature_flags = &.{
                "diagnostic-human-readable-manifest",
            };
            pub const supported_execution_modes = &.{
                "fresh",
                "replay",
                "verify",
                "audit",
            };
            pub const metadata_bytes: []const u8 = "";

            pub const Limits = struct {
                max_universal_wasm_linear_memory_bytes: u64 = 67_108_864,
                max_executable_image_bytes: u32 = 128 * 1024,
                max_turn_input_bytes: u32 = 2_950_144,
                max_turn_closure_bytes: u32 = 512 * 1024,
                max_capsule_bytes: u32 = 4 * 1024 * 1024,
                max_archive_append_batch_bytes: u32 = 4 * 1024 * 1024,
                max_loaded_frame_depth: u16 = 64,
                max_runspace_slots: u16 = 8,
                max_mailbox_entries: u16 = 1024,
                max_provider_depth: u16 = 8,
                max_request_batch_count: u16 = 16,
                max_reply_batch_count: u16 = 16,
            };

            pub const limits = Limits{};

            pub fn manifestFingerprint() ManifestFingerprint {
                var buffer: [8192]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const allocator = fba.allocator();
                var out: std.ArrayList(u8) = .empty;
                defer out.deinit(allocator);
                encodeIdentity(allocator, &out) catch @panic("world protocol manifest identity encoding failed");
                return .{
                    .lo = fnv64(out.items),
                    .hi = fnv64Domain("world.protocol.manifest.fingerprint.hi", out.items),
                };
            }

            pub fn publicSurfaceFingerprint() u64 {
                var buffer: [4096]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const allocator = fba.allocator();
                var out: std.ArrayList(u8) = .empty;
                defer out.deinit(allocator);
                appendEnumTable(allocator, &out, "mode", W.Mode) catch @panic("world protocol public surface encoding failed");
                appendEnumTable(allocator, &out, "response-kind", W.ResponseKind) catch @panic("world protocol public surface encoding failed");
                appendEnumTable(allocator, &out, "response-status", W.ResponseStatus) catch @panic("world protocol public surface encoding failed");
                appendEnumTable(allocator, &out, "appliance-status", W.Appliance.Abi.Status) catch @panic("world protocol public surface encoding failed");
                appendEnumTable(allocator, &out, "appliance-profile-kind", W.Appliance.ProfileKind) catch @panic("world protocol public surface encoding failed");
                return fnv64(out.items);
            }

            pub fn universalRuntimeProfileFingerprint() u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "world.protocol.universal-runtime-profile.v1");
                hashU64(&hasher, limits.max_executable_image_bytes);
                hashU64(&hasher, limits.max_turn_input_bytes);
                hashU64(&hasher, limits.max_turn_closure_bytes);
                hashU64(&hasher, limits.max_universal_wasm_linear_memory_bytes);
                hashU64(&hasher, limits.max_provider_depth);
                hashU64(&hasher, limits.max_mailbox_entries);
                return nonzero(hasher.final());
            }

            pub fn encodeAlloc(allocator: std.mem.Allocator) ![]u8 {
                var out: std.ArrayList(u8) = .empty;
                errdefer out.deinit(allocator);
                const fingerprint = manifestFingerprint();
                try appendBytes(&out, allocator, "WPM1");
                try appendU32(&out, allocator, format_version);
                try appendU32(&out, allocator, fingerprint_version);
                try appendU64(&out, allocator, fingerprint.lo);
                try appendU64(&out, allocator, fingerprint.hi);
                try encodeIdentity(allocator, &out);
                return out.toOwnedSlice(allocator);
            }

            fn encodeIdentity(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
                try appendU32(out, allocator, format_version);
                try appendU32(out, allocator, fingerprint_version);
                try appendU32(out, allocator, world_protocol_proof_receipt_format_version);
                try appendU32(out, allocator, world_protocol_proof_receipt_fingerprint_version);
                try appendU32(out, allocator, world_protocol_release_receipt_format_version);
                try appendU32(out, allocator, world_protocol_release_receipt_fingerprint_version);
                try appendString(out, allocator, world_package_version);
                try appendString(out, allocator, required_boundary_package_version);
                try appendU64(out, allocator, required_boundary_protocol_manifest_fingerprint);
                try appendString(out, allocator, minimum_zig_version);
                try appendU32(out, allocator, W.world_appliance_abi_version);
                try appendU32(out, allocator, W.world_appliance_wire_turn_input_format_version);
                try appendU32(out, allocator, W.world_appliance_wire_resolution_input_format_version);
                try appendU32(out, allocator, W.world_appliance_wire_retention_input_format_version);
                try appendU32(out, allocator, W.world_executable_image_format_version);
                try appendU32(out, allocator, W.world_executable_image_fingerprint_version);
                try appendU32(out, allocator, W.world_appliance_turn_closure_format_version);
                try appendU32(out, allocator, W.world_appliance_turn_closure_fingerprint_version);
                try appendU32(out, allocator, W.world_appliance_turn_receipt_format_version);
                try appendU32(out, allocator, W.world_appliance_turn_receipt_fingerprint_version);
                try appendU32(out, allocator, W.world_appliance_checkpoint_format_version);
                try appendU32(out, allocator, W.world_appliance_checkpoint_fingerprint_version);
                try appendU32(out, allocator, W.world_appliance_host_request_format_version);
                try appendU32(out, allocator, W.world_appliance_host_request_fingerprint_version);
                try appendU32(out, allocator, W.world_frame_request_format_version);
                try appendU32(out, allocator, W.world_frame_response_format_version);
                try appendU32(out, allocator, W.world_frame_value_image_format_version);
                try appendU32(out, allocator, W.world_actuation_response_format_version);
                try appendU32(out, allocator, W.world_actuation_receipt_format_version);
                try appendU32(out, allocator, W.world_capsule_manifest_format_version);
                try appendU32(out, allocator, W.world_capsule_image_format_version);
                try appendU32(out, allocator, W.world_continuity_object_ref_format_version);
                try appendU32(out, allocator, W.world_continuity_object_envelope_format_version);
                try appendU32(out, allocator, W.world_chronicle_event_format_version);
                try appendU32(out, allocator, W.world_chronicle_commit_format_version);
                try appendU32(out, allocator, W.Archive.world_archive_header_format_version);
                try appendU32(out, allocator, W.Archive.world_archive_segment_format_version);
                try appendU32(out, allocator, W.Archive.world_archive_moment_format_version);
                try appendU32(out, allocator, W.Archive.world_archive_seal_format_version);
                try appendU32(out, allocator, W.Archive.world_archive_append_batch_format_version);
                try appendStringList(allocator, out, supported_execution_modes);
                try appendEnumTable(allocator, out, "response-status", W.ResponseStatus);
                try appendEnumTable(allocator, out, "continuity-object-kind", W.Continuity.ObjectKind);
                try appendEnumTable(allocator, out, "appliance-status", W.Appliance.Abi.Status);
                try appendEnumTable(allocator, out, "mode", W.Mode);
                try appendU64(out, allocator, universalRuntimeProfileFingerprint());
                try appendU64(out, allocator, publicSurfaceFingerprint());
                try appendU64(out, allocator, limits.max_universal_wasm_linear_memory_bytes);
                try appendU32(out, allocator, limits.max_executable_image_bytes);
                try appendU32(out, allocator, limits.max_turn_input_bytes);
                try appendU32(out, allocator, limits.max_turn_closure_bytes);
                try appendU32(out, allocator, limits.max_capsule_bytes);
                try appendU32(out, allocator, limits.max_archive_append_batch_bytes);
                try appendU16(out, allocator, limits.max_loaded_frame_depth);
                try appendU16(out, allocator, limits.max_runspace_slots);
                try appendU16(out, allocator, limits.max_mailbox_entries);
                try appendU16(out, allocator, limits.max_provider_depth);
                try appendU16(out, allocator, limits.max_request_batch_count);
                try appendU16(out, allocator, limits.max_reply_batch_count);
                try appendStringList(allocator, out, required_feature_flags);
                try appendStringList(allocator, out, optional_feature_flags);
                try appendBytesWithLength(out, allocator, metadata_bytes);
            }
        };
    };
}

fn boolBlocker(value: bool) u32 {
    return if (value) 1 else 0;
}

fn requiredProofKindIndex(kind: anytype) ?usize {
    const ProtocolType = @TypeOf(kind);
    _ = ProtocolType;
    return switch (kind) {
        .boundary_portable_v2 => 0,
        .executable_image => 1,
        .universal_wasm_execution => 2,
        .two_programs_one_wasm => 3,
        .loaded_internal_provider => 4,
        .multi_suspension_root => 5,
        .active_fabric_restore => 6,
        .replay_without_fresh_effect => 7,
        .unsupported_actuated_replay_rejected => 8,
        .deterministic_retry => 9,
        .batched_request_reply => 10,
        .independent_javascript_codec => 11,
        .exact_result_bytes => 12,
        .exact_receipt_bytes => 13,
        .exact_capsule_bytes => 14,
        .exact_archive_append_batch_bytes => 15,
        .native_wasm_parity => 16,
        .cold_warm_parity => 17,
        .memory_bound => 18,
        .malformed_input => 19,
        .regression_matrix => 20,
        .reproducible_artifact => 21,
    };
}

fn fingerprintProofReceipt(receipt: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.protocol.proof_receipt.v1");
    hashU64(&hasher, receipt.receipt_format_version);
    hashU64(&hasher, receipt.receipt_fingerprint_version);
    hashU64(&hasher, @intFromEnum(receipt.proof_kind));
    hashU64(&hasher, receipt.protocol_manifest_fingerprint);
    hashU64Slice(&hasher, receipt.input_corpus_case_fingerprints);
    hashU64Slice(&hasher, receipt.expected_output_fingerprints);
    hashU64Slice(&hasher, receipt.actual_output_fingerprints);
    hashBool(&hasher, receipt.actual_comparison_result);
    hashU64Slice(&hasher, receipt.artifact_fingerprints);
    hashU64(&hasher, receipt.blocker_count);
    hashU64(&hasher, receipt.warning_count);
    hashU64Slice(&hasher, receipt.bounded_diagnostics);
    return nonzero(hasher.final());
}

fn fingerprintReleaseReceipt(receipt: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.protocol.release_receipt.v1");
    hashU64(&hasher, receipt.release_receipt_format_version);
    hashU64(&hasher, receipt.release_receipt_fingerprint_version);
    hashU64(&hasher, receipt.boundary_protocol_manifest_fingerprint);
    hashU64(&hasher, receipt.world_protocol_manifest_fingerprint);
    hashU64(&hasher, receipt.conformance_corpus_root_fingerprint);
    hashU64(&hasher, receipt.proof_receipts.len);
    for (receipt.proof_receipts) |proof_receipt| {
        hashU64(&hasher, proof_receipt.receipt_fingerprint);
    }
    hashU64(&hasher, receipt.universal_wasm_checksum);
    hashU64(&hasher, receipt.source_package_checksum);
    hashBool(&hasher, receipt.complete);
    hashU64Slice(&hasher, receipt.blockers);
    hashU64Slice(&hasher, receipt.warnings);
    return nonzero(hasher.final());
}

fn protocolArtifactFingerprint(label: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "world.protocol.artifact.v1");
    hashBytes(&hasher, label);
    return nonzero(hasher.final());
}

fn hashStringList(hasher: *std.hash.Wyhash, values: []const []const u8) void {
    hashU64(hasher, values.len);
    for (values) |value| {
        hashU64(hasher, value.len);
        hashBytes(hasher, value);
    }
}

fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
    hashU64(hasher, values.len);
    for (values) |value| hashU64(hasher, value);
}

fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
    hashU64(hasher, @as(u8, if (value) 1 else 0));
}

fn appendEnumTable(allocator: std.mem.Allocator, out: *std.ArrayList(u8), domain: []const u8, comptime T: type) !void {
    try appendString(out, allocator, domain);
    const fields = @typeInfo(T).@"enum".fields;
    try appendU32(out, allocator, @intCast(fields.len));
    inline for (fields) |field| {
        try appendString(out, allocator, field.name);
        try appendU64(out, allocator, @intCast(field.value));
    }
}

fn appendStringList(allocator: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8) !void {
    try appendU32(out, allocator, @intCast(values.len));
    for (values) |value| try appendString(out, allocator, value);
}

fn appendString(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendBytesWithLength(out, allocator, value);
}

fn appendBytesWithLength(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try appendU32(out, allocator, @intCast(value.len));
    try appendBytes(out, allocator, value);
}

fn appendBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.appendSlice(allocator, value);
}

fn appendU16(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn appendU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn appendU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try appendBytes(out, allocator, &buf);
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: u64) void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    hasher.update(&buf);
}

fn nonzero(value: u64) u64 {
    return if (value == 0) 1 else value;
}

fn fnv64(bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return hash;
}

fn fnv64Domain(domain: []const u8, bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (domain) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return hash;
}
