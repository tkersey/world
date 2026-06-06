const std = @import("std");

pub fn Linker(comptime W: type) type {
    return struct {
        pub const Input = struct {
            root_target_ref: W.TargetRef,
            root_module_ref: ?W.Admission.ModuleRef = null,
            root_import_set: W.ImportSet,
            root_imports: []const W.ImportRequirement = &.{},
            catalog: Catalog = .{},
            environment_bindings: []const EnvironmentBinding = &.{},
            replay_sources: []const ReplaySource = &.{},
            hints: []const Hint = &.{},
            policy: Policy = .strict_closed,
            supervision_policy_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            max_depth: ?usize = null,
            max_provider_candidates: ?usize = null,
            max_routes: ?usize = null,
        };

        pub const Boundary = struct {
            pub const owns_algebra = true;
            pub const linker_calls_handlers = false;
            pub const linker_mutates_runspace_mailbox = false;
            pub const linker_resumes_parent_requests = false;
            pub const linker_discovers_providers = false;
            pub const linker_imports_boundary_algebra = false;
            pub const linker_uses_name_dispatch = false;
        };

        pub const Policy = struct {
            require_closed_graph: bool = true,
            allow_external_environment_ports: bool = false,
            allow_adapter_fallback: bool = false,
            allow_replay_routes: bool = false,
            allow_guest_routes: bool = false,
            allow_reject_routes: bool = false,
            allow_ambiguous_matches: bool = false,
            require_explicit_hint_for_ambiguous_match: bool = true,
            require_exact_value_refs: bool = true,
            allow_same_schema_compatible_refs: bool = false,
            reject_cross_type_conversion: bool = true,
            reject_same_target_cycle: bool = true,
            reject_same_module_cycle: bool = true,
            reject_recursive_route: bool = true,
            max_link_depth: usize = 8,
            max_provider_runs: usize = 32,
            max_candidates_per_import: usize = 8,
            max_unresolved_imports: usize = 0,
            require_supervision_compatible_routes: bool = true,
            require_guest_conformance_for_guest_routes: bool = true,
            require_admission_for_provider_targets: bool = false,

            pub const strict_closed = Policy{};
            pub const world_boundary = Policy{
                .allow_external_environment_ports = true,
                .max_unresolved_imports = 16,
            };
            pub const agent_fixture = Policy{
                .require_closed_graph = false,
                .allow_external_environment_ports = true,
                .max_unresolved_imports = 8,
                .require_admission_for_provider_targets = false,
            };
            pub const audit_only = Policy{
                .require_closed_graph = false,
                .allow_external_environment_ports = true,
                .allow_adapter_fallback = true,
                .allow_replay_routes = true,
                .allow_guest_routes = true,
                .allow_reject_routes = true,
                .allow_ambiguous_matches = true,
                .require_explicit_hint_for_ambiguous_match = false,
                .require_exact_value_refs = false,
                .allow_same_schema_compatible_refs = true,
                .reject_cross_type_conversion = false,
                .reject_same_target_cycle = false,
                .reject_same_module_cycle = false,
                .reject_recursive_route = false,
                .max_unresolved_imports = 1024,
                .require_supervision_compatible_routes = false,
                .require_guest_conformance_for_guest_routes = false,
                .require_admission_for_provider_targets = false,
            };
            pub const allow_external_ports = Policy{
                .require_closed_graph = false,
                .allow_external_environment_ports = true,
                .max_unresolved_imports = 1024,
            };

            pub fn fingerprint(self: Policy) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "world.linker.policy.v1");
                hashU64(&hasher, W.world_linker_policy_fingerprint_version);
                hashBool(&hasher, self.require_closed_graph);
                hashBool(&hasher, self.allow_external_environment_ports);
                hashBool(&hasher, self.allow_adapter_fallback);
                hashBool(&hasher, self.allow_replay_routes);
                hashBool(&hasher, self.allow_guest_routes);
                hashBool(&hasher, self.allow_reject_routes);
                hashBool(&hasher, self.allow_ambiguous_matches);
                hashBool(&hasher, self.require_explicit_hint_for_ambiguous_match);
                hashBool(&hasher, self.require_exact_value_refs);
                hashBool(&hasher, self.allow_same_schema_compatible_refs);
                hashBool(&hasher, self.reject_cross_type_conversion);
                hashBool(&hasher, self.reject_same_target_cycle);
                hashBool(&hasher, self.reject_same_module_cycle);
                hashBool(&hasher, self.reject_recursive_route);
                hashU64(&hasher, self.max_link_depth);
                hashU64(&hasher, self.max_provider_runs);
                hashU64(&hasher, self.max_candidates_per_import);
                hashU64(&hasher, self.max_unresolved_imports);
                hashBool(&hasher, self.require_supervision_compatible_routes);
                hashBool(&hasher, self.require_guest_conformance_for_guest_routes);
                hashBool(&hasher, self.require_admission_for_provider_targets);
                return hasher.final();
            }
        };

        pub const ProviderKind = enum {
            target,
            module_ref,
            admitted_run,
            guest_provider,
            replay_provider,
            reject_route,
            environment_adapter,
        };

        pub const ValueRef = struct {
            value_table_id: ?u32 = null,
            value_ref_fingerprint: ?u64 = null,
            schema_fingerprint: ?u64 = null,

            pub fn compatibleWith(self: ValueRef, other: ValueRef, policy: Policy) bool {
                if (policy.require_exact_value_refs) {
                    if (self.value_table_id != other.value_table_id) return false;
                    if (self.value_ref_fingerprint != null or other.value_ref_fingerprint != null) {
                        return self.value_ref_fingerprint == other.value_ref_fingerprint;
                    }
                    return true;
                }
                if (self.value_table_id != null and other.value_table_id != null and self.value_table_id.? == other.value_table_id.?) return true;
                if (policy.allow_same_schema_compatible_refs and self.schema_fingerprint != null and other.schema_fingerprint != null) {
                    return self.schema_fingerprint.? == other.schema_fingerprint.?;
                }
                return !policy.reject_cross_type_conversion;
            }

            pub fn fingerprint(self: ValueRef) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "world.linker.value.ref.v1");
                hashOptionalU32(&hasher, self.value_table_id);
                hashOptionalU64(&hasher, self.value_ref_fingerprint);
                hashOptionalU64(&hasher, self.schema_fingerprint);
                return hasher.final();
            }
        };

        pub const ExportDescriptor = struct {
            export_fingerprint: u64,
            target_ref: W.TargetRef,
            module_ref: ?W.Admission.ModuleRef = null,
            export_ref_fingerprint: ?u64 = null,
            argument_refs: []const ValueRef = &.{},
            result_ref: ValueRef = .{},
            normal_form_kind: W.NormalFormKind = .unknown,
            label: []const u8 = "",
            metadata: []const u8 = "",

            pub fn init(args: struct {
                target_ref: W.TargetRef,
                module_ref: ?W.Admission.ModuleRef = null,
                export_ref_fingerprint: ?u64 = null,
                argument_refs: []const ValueRef = &.{},
                result_ref: ValueRef = .{},
                normal_form_kind: W.NormalFormKind = .unknown,
                label: []const u8 = "",
                metadata: []const u8 = "",
            }) ExportDescriptor {
                var result = ExportDescriptor{
                    .export_fingerprint = 0,
                    .target_ref = args.target_ref,
                    .module_ref = args.module_ref,
                    .export_ref_fingerprint = args.export_ref_fingerprint,
                    .argument_refs = args.argument_refs,
                    .result_ref = args.result_ref,
                    .normal_form_kind = args.normal_form_kind,
                    .label = args.label,
                    .metadata = args.metadata,
                };
                result.export_fingerprint = fingerprintExportDescriptor(result);
                return result;
            }
        };

        pub const EnvironmentBinding = struct {
            parent_target_ref_fingerprint: u64,
            world_port_id: u32,
            import_requirement_fingerprint: ?u64 = null,
            adapter_descriptor_fingerprint: ?u64 = null,
            label: []const u8 = "",

            pub fn fingerprint(self: EnvironmentBinding) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "world.linker.environment.binding.v1");
                hashU64(&hasher, self.parent_target_ref_fingerprint);
                hashU64(&hasher, self.world_port_id);
                hashOptionalU64(&hasher, self.import_requirement_fingerprint);
                hashOptionalU64(&hasher, self.adapter_descriptor_fingerprint);
                hashBytes(&hasher, self.label);
                return hasher.final();
            }
        };

        pub const ReplaySource = struct {
            parent_target_ref_fingerprint: u64,
            world_port_id: u32,
            transcript_image_fingerprint: u64,
            label: []const u8 = "",

            pub fn fingerprint(self: ReplaySource) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "world.linker.replay.source.v1");
                hashU64(&hasher, self.parent_target_ref_fingerprint);
                hashU64(&hasher, self.world_port_id);
                hashU64(&hasher, self.transcript_image_fingerprint);
                hashBytes(&hasher, self.label);
                return hasher.final();
            }
        };

        pub const Catalog = struct {
            catalog_fingerprint: u64 = fingerprintCatalog(&.{}),
            entries: []const Entry = &.{},

            pub const Entry = struct {
                entry_fingerprint: u64,
                provider_kind: ProviderKind,
                target_ref: ?W.TargetRef = null,
                module_ref: ?W.Admission.ModuleRef = null,
                export_summary: ?W.Admission.ExportSummary = null,
                export_descriptor: ?ExportDescriptor = null,
                import_set: ?W.ImportSet = null,
                imports: []const W.ImportRequirement = &.{},
                admission_receipt_fingerprint: ?u64 = null,
                environment_certificate_fingerprint: ?u64 = null,
                run_permit_fingerprint: ?u64 = null,
                replay_transcript_image_fingerprint: ?u64 = null,
                guest_conformance_report_fingerprint: ?u64 = null,
                label: []const u8 = "",
                metadata: []const u8 = "",

                pub fn init(args: struct {
                    provider_kind: ProviderKind,
                    target_ref: ?W.TargetRef = null,
                    module_ref: ?W.Admission.ModuleRef = null,
                    export_summary: ?W.Admission.ExportSummary = null,
                    export_descriptor: ?ExportDescriptor = null,
                    import_set: ?W.ImportSet = null,
                    imports: []const W.ImportRequirement = &.{},
                    admission_receipt_fingerprint: ?u64 = null,
                    environment_certificate_fingerprint: ?u64 = null,
                    run_permit_fingerprint: ?u64 = null,
                    replay_transcript_image_fingerprint: ?u64 = null,
                    guest_conformance_report_fingerprint: ?u64 = null,
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    var result = Entry{
                        .entry_fingerprint = 0,
                        .provider_kind = args.provider_kind,
                        .target_ref = args.target_ref,
                        .module_ref = args.module_ref,
                        .export_summary = args.export_summary,
                        .export_descriptor = args.export_descriptor,
                        .import_set = args.import_set,
                        .imports = args.imports,
                        .admission_receipt_fingerprint = args.admission_receipt_fingerprint,
                        .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                        .run_permit_fingerprint = args.run_permit_fingerprint,
                        .replay_transcript_image_fingerprint = args.replay_transcript_image_fingerprint,
                        .guest_conformance_report_fingerprint = args.guest_conformance_report_fingerprint,
                        .label = args.label,
                        .metadata = args.metadata,
                    };
                    result.entry_fingerprint = fingerprintCatalogEntry(result);
                    return result;
                }

                pub fn generatedTarget(args: struct {
                    target_ref: W.TargetRef,
                    export_descriptor: ExportDescriptor,
                    import_set: W.ImportSet,
                    imports: []const W.ImportRequirement = &.{},
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    return Entry.init(.{
                        .provider_kind = .target,
                        .target_ref = args.target_ref,
                        .export_descriptor = args.export_descriptor,
                        .import_set = args.import_set,
                        .imports = args.imports,
                        .label = args.label,
                        .metadata = args.metadata,
                    });
                }

                pub fn moduleRef(args: struct {
                    module_ref: W.Admission.ModuleRef,
                    target_ref: ?W.TargetRef = null,
                    export_descriptor: ?ExportDescriptor = null,
                    import_set: ?W.ImportSet = null,
                    imports: []const W.ImportRequirement = &.{},
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    return Entry.init(.{
                        .provider_kind = .module_ref,
                        .target_ref = args.target_ref,
                        .module_ref = args.module_ref,
                        .export_descriptor = args.export_descriptor,
                        .import_set = args.import_set,
                        .imports = args.imports,
                        .label = args.label,
                        .metadata = args.metadata,
                    });
                }

                pub fn admittedRun(args: struct {
                    admitted_run: W.Admission.AdmittedRun,
                    export_descriptor: ExportDescriptor,
                    import_set: W.ImportSet,
                    imports: []const W.ImportRequirement = &.{},
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    return Entry.init(.{
                        .provider_kind = .admitted_run,
                        .target_ref = args.admitted_run.target_ref,
                        .export_descriptor = args.export_descriptor,
                        .import_set = args.import_set,
                        .imports = args.imports,
                        .admission_receipt_fingerprint = args.admitted_run.admission_receipt_fingerprint,
                        .label = args.label,
                        .metadata = args.metadata,
                    });
                }

                pub fn guest(args: struct {
                    target_ref: W.TargetRef,
                    export_descriptor: ExportDescriptor,
                    conformance_report_fingerprint: ?u64 = null,
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    return Entry.init(.{
                        .provider_kind = .guest_provider,
                        .target_ref = args.target_ref,
                        .export_descriptor = args.export_descriptor,
                        .guest_conformance_report_fingerprint = args.conformance_report_fingerprint,
                        .label = args.label,
                        .metadata = args.metadata,
                    });
                }

                pub fn replay(args: struct {
                    transcript_image_fingerprint: u64,
                    label: []const u8 = "",
                    metadata: []const u8 = "",
                }) Entry {
                    return Entry.init(.{
                        .provider_kind = .replay_provider,
                        .replay_transcript_image_fingerprint = args.transcript_image_fingerprint,
                        .label = args.label,
                        .metadata = args.metadata,
                    });
                }

                pub fn fingerprint(self: Entry) u64 {
                    return fingerprintCatalogEntry(self);
                }
            };

            pub fn init(entries: []const Entry) Catalog {
                return .{
                    .catalog_fingerprint = fingerprintCatalog(entries),
                    .entries = entries,
                };
            }

            pub fn fingerprint(self: Catalog) u64 {
                return fingerprintCatalog(self.entries);
            }

            pub fn entryByTargetFingerprint(self: Catalog, target_ref_fingerprint: u64) ?Entry {
                for (self.entries) |entry| {
                    if (entry.target_ref) |target_ref| {
                        if (target_ref.target_ref_fingerprint == target_ref_fingerprint) return entry;
                    }
                }
                return null;
            }
        };

        pub const ImportIndex = struct {
            index_fingerprint: u64,
            root_target_ref_fingerprint: u64,
            root_imports: []const W.ImportRequirement = &.{},
            catalog: Catalog = .{},

            pub fn init(input: Input) ImportIndex {
                var result = ImportIndex{
                    .index_fingerprint = 0,
                    .root_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .root_imports = input.root_imports,
                    .catalog = input.catalog,
                };
                result.index_fingerprint = fingerprintImportIndex(result);
                return result;
            }

            pub fn importsFor(self: ImportIndex, target_ref: W.TargetRef) []const W.ImportRequirement {
                if (target_ref.target_ref_fingerprint == self.root_target_ref_fingerprint) return self.root_imports;
                if (self.catalog.entryByTargetFingerprint(target_ref.target_ref_fingerprint)) |entry| return entry.imports;
                return &.{};
            }
        };

        pub const ExportIndex = struct {
            index_fingerprint: u64,
            catalog: Catalog = .{},

            pub fn init(catalog: Catalog) ExportIndex {
                var result = ExportIndex{
                    .index_fingerprint = 0,
                    .catalog = catalog,
                };
                result.index_fingerprint = fingerprintExportIndex(result);
                return result;
            }

            pub fn exportsFor(self: ExportIndex, allocator: std.mem.Allocator, target_ref: W.TargetRef) ![]ExportDescriptor {
                var exports: std.ArrayList(ExportDescriptor) = .empty;
                if (self.catalog.entryByTargetFingerprint(target_ref.target_ref_fingerprint)) |entry| {
                    if (entry.export_descriptor) |descriptor| try exports.append(allocator, descriptor);
                }
                return exports.toOwnedSlice(allocator);
            }

            pub fn candidateProvidersFor(self: ExportIndex, allocator: std.mem.Allocator, import_requirement: W.ImportRequirement) ![]Catalog.Entry {
                return self.candidateProvidersForPolicy(allocator, import_requirement, .strict_closed);
            }

            pub fn candidateProvidersForPolicy(self: ExportIndex, allocator: std.mem.Allocator, import_requirement: W.ImportRequirement, policy: Policy) ![]Catalog.Entry {
                var candidates: std.ArrayList(Catalog.Entry) = .empty;
                for (self.catalog.entries) |entry| {
                    const descriptor = entry.export_descriptor orelse {
                        if (entry.provider_kind == .replay_provider or entry.provider_kind == .reject_route or entry.provider_kind == .environment_adapter) {
                            try candidates.append(allocator, entry);
                            if (candidates.items.len > policy.max_candidates_per_import) break;
                        }
                        continue;
                    };
                    const expected = ValueRef{ .value_table_id = import_requirement.response_value_table_id };
                    if (expected.compatibleWith(descriptor.result_ref, policy)) {
                        try candidates.append(allocator, entry);
                        if (candidates.items.len > policy.max_candidates_per_import) break;
                    }
                }
                return candidates.toOwnedSlice(allocator);
            }

            pub fn candidateExportsFor(self: ExportIndex, allocator: std.mem.Allocator, import_requirement: W.ImportRequirement, policy: Policy) ![]ExportDescriptor {
                var candidates: std.ArrayList(ExportDescriptor) = .empty;
                for (self.catalog.entries) |entry| {
                    const descriptor = entry.export_descriptor orelse continue;
                    const expected = ValueRef{ .value_table_id = import_requirement.response_value_table_id };
                    if (expected.compatibleWith(descriptor.result_ref, policy)) {
                        try candidates.append(allocator, descriptor);
                    }
                }
                return candidates.toOwnedSlice(allocator);
            }
        };

        pub const MatchKind = enum {
            exact_value_refs,
            same_schema_compatible,
            explicit_hint,
            replay,
            adapter,
            guest,
            reject,
            unsupported,
        };

        pub const MatchConfidence = enum {
            exact,
            hinted,
            ambiguous,
            rejected,
        };

        pub const Blocker = enum {
            PayloadRefMismatch,
            ResponseRefMismatch,
            ArgumentCountMismatch,
            ResultRefMismatch,
            CrossTypeConversionRejected,
            AmbiguousProvider,
            MissingProvider,
            ProviderNotAdmitted,
            ProviderRequiresUnsupportedImports,
            GuestConformanceMissing,
            CycleDetected,
            DepthExceeded,
            ProviderRunLimitExceeded,
            SupervisionIncompatible,
            FabricInvariantViolation,
            UnsupportedRouteKind,
            RootImportSetMismatch,
        };

        pub const Warning = enum {
            ExternalEnvironmentRequired,
            ExplicitHintSelected,
            AuditOnlyAccepted,
            RejectRouteSelected,
            ReplayRouteSelected,
            GuestRouteRequiresConformance,
        };

        pub const Match = struct {
            match_fingerprint: u64,
            parent_import_requirement_fingerprint: u64,
            provider_export_fingerprint: ?u64 = null,
            provider_target_ref_fingerprint: ?u64 = null,
            provider_module_ref_fingerprint: ?u64 = null,
            kind: MatchKind,
            payload_mapping: ?W.Fabric.ValueMapping = null,
            response_mapping: ?W.Fabric.ValueMapping = null,
            confidence: MatchConfidence,
            blockers: []const Blocker = &.{},
            warnings: []const Warning = &.{},

            pub fn init(args: struct {
                parent_import_requirement_fingerprint: u64,
                provider_export_fingerprint: ?u64 = null,
                provider_target_ref_fingerprint: ?u64 = null,
                provider_module_ref_fingerprint: ?u64 = null,
                kind: MatchKind,
                payload_mapping: ?W.Fabric.ValueMapping = null,
                response_mapping: ?W.Fabric.ValueMapping = null,
                confidence: MatchConfidence,
                blockers: []const Blocker = &.{},
                warnings: []const Warning = &.{},
            }) Match {
                var result = Match{
                    .match_fingerprint = 0,
                    .parent_import_requirement_fingerprint = args.parent_import_requirement_fingerprint,
                    .provider_export_fingerprint = args.provider_export_fingerprint,
                    .provider_target_ref_fingerprint = args.provider_target_ref_fingerprint,
                    .provider_module_ref_fingerprint = args.provider_module_ref_fingerprint,
                    .kind = args.kind,
                    .payload_mapping = args.payload_mapping,
                    .response_mapping = args.response_mapping,
                    .confidence = args.confidence,
                    .blockers = args.blockers,
                    .warnings = args.warnings,
                };
                result.match_fingerprint = fingerprintMatch(result);
                return result;
            }

            pub fn accepted(self: Match) bool {
                return self.blockers.len == 0 and self.confidence != .rejected;
            }
        };

        pub const Hint = struct {
            hint_fingerprint: u64,
            parent_target_ref_fingerprint: u64,
            parent_world_port_id: u32,
            provider_target_ref_fingerprint: ?u64 = null,
            provider_module_ref_fingerprint: ?u64 = null,
            provider_export_fingerprint: ?u64 = null,
            route_kind: W.Fabric.RouteKind = .target_export,
            value_mapping: ?W.Fabric.ValueMapping = null,
            label: []const u8 = "",
            metadata: []const u8 = "",

            pub fn init(args: struct {
                parent_target_ref_fingerprint: u64,
                parent_world_port_id: u32,
                provider_target_ref_fingerprint: ?u64 = null,
                provider_module_ref_fingerprint: ?u64 = null,
                provider_export_fingerprint: ?u64 = null,
                route_kind: W.Fabric.RouteKind = .target_export,
                value_mapping: ?W.Fabric.ValueMapping = null,
                label: []const u8 = "",
                metadata: []const u8 = "",
            }) Hint {
                var result = Hint{
                    .hint_fingerprint = 0,
                    .parent_target_ref_fingerprint = args.parent_target_ref_fingerprint,
                    .parent_world_port_id = args.parent_world_port_id,
                    .provider_target_ref_fingerprint = args.provider_target_ref_fingerprint,
                    .provider_module_ref_fingerprint = args.provider_module_ref_fingerprint,
                    .provider_export_fingerprint = args.provider_export_fingerprint,
                    .route_kind = args.route_kind,
                    .value_mapping = args.value_mapping,
                    .label = args.label,
                    .metadata = args.metadata,
                };
                result.hint_fingerprint = fingerprintHint(result);
                return result;
            }

            fn selects(self: Hint, parent_ref: W.TargetRef, requirement: W.ImportRequirement, entry: Catalog.Entry) bool {
                if (self.parent_target_ref_fingerprint != parent_ref.target_ref_fingerprint) return false;
                if (self.parent_world_port_id != requirement.world_port_id) return false;
                if (!self.hasProviderSelector()) return false;
                if (self.provider_target_ref_fingerprint) |expected| {
                    if (entry.target_ref == null or entry.target_ref.?.target_ref_fingerprint != expected) return false;
                }
                if (self.provider_module_ref_fingerprint) |expected| {
                    if (entry.module_ref == null or entry.module_ref.?.module_ref_fingerprint != expected) return false;
                }
                if (self.provider_export_fingerprint) |expected| {
                    if (entry.export_descriptor == null or entry.export_descriptor.?.export_fingerprint != expected) return false;
                }
                return true;
            }

            fn hasProviderSelector(self: Hint) bool {
                return self.provider_target_ref_fingerprint != null or self.provider_module_ref_fingerprint != null or self.provider_export_fingerprint != null;
            }
        };

        pub fn matchEntry(allocator: std.mem.Allocator, policy: Policy, requirement: W.ImportRequirement, entry: Catalog.Entry, hint: ?Hint) !Match {
            var blockers: std.ArrayList(Blocker) = .empty;
            errdefer blockers.deinit(allocator);
            var warnings: std.ArrayList(Warning) = .empty;
            errdefer warnings.deinit(allocator);

            const kind: MatchKind = if (hint != null and providerTargetMatches(hint.?, entry))
                .explicit_hint
            else
                matchKindForEntry(entry);
            var response_mapping: ?W.Fabric.ValueMapping = null;
            if (entry.export_descriptor) |descriptor| {
                if (entry.target_ref) |target_ref| {
                    if (descriptor.target_ref.target_ref_fingerprint != target_ref.target_ref_fingerprint) try blockers.append(allocator, .MissingProvider);
                }
                if (entry.module_ref) |module_ref| {
                    if (descriptor.module_ref) |descriptor_module_ref| {
                        if (descriptor_module_ref.module_ref_fingerprint != module_ref.module_ref_fingerprint) try blockers.append(allocator, .MissingProvider);
                    } else if (descriptor.target_ref.target_ref_fingerprint != module_ref.target_ref_fingerprint or
                        descriptor.target_ref.world_surface_fingerprint != module_ref.world_surface_fingerprint or
                        descriptor.target_ref.target_certificate_fingerprint != module_ref.target_certificate_fingerprint)
                    {
                        try blockers.append(allocator, .MissingProvider);
                    }
                }
                if (descriptor.argument_refs.len != 0) try blockers.append(allocator, .ArgumentCountMismatch);
                const parent_ref = valueRefForRequirement(requirement);
                if (!parent_ref.compatibleWith(descriptor.result_ref, policy)) {
                    try blockers.append(allocator, .ResponseRefMismatch);
                } else if (entry.provider_kind == .target or entry.provider_kind == .module_ref or entry.provider_kind == .admitted_run) {
                    if (parent_ref.value_table_id == null or descriptor.result_ref.value_table_id == null) {
                        try blockers.append(allocator, .ResponseRefMismatch);
                    } else {
                        response_mapping = try synthesizeResponseMapping(requirement, entry);
                    }
                }
            } else switch (entry.provider_kind) {
                .replay_provider, .reject_route, .environment_adapter => {},
                else => try blockers.append(allocator, .MissingProvider),
            }
            if (entry.provider_kind == .guest_provider and (!policy.allow_guest_routes or (policy.require_guest_conformance_for_guest_routes and entry.guest_conformance_report_fingerprint == null))) try blockers.append(allocator, .GuestConformanceMissing);
            if (entry.provider_kind == .replay_provider and !policy.allow_replay_routes) try blockers.append(allocator, .UnsupportedRouteKind);
            if (entry.provider_kind == .reject_route and !policy.allow_reject_routes) try blockers.append(allocator, .UnsupportedRouteKind);
            if (entry.provider_kind == .environment_adapter and !policy.allow_adapter_fallback) try blockers.append(allocator, .UnsupportedRouteKind);
            if (!linkerCanSynthesizeRouteKind(entry)) try blockers.append(allocator, .UnsupportedRouteKind);
            if (hint) |present| {
                if (providerTargetMatches(present, entry) and present.route_kind != routeKindForEntry(entry)) try blockers.append(allocator, .UnsupportedRouteKind);
            }
            if (policy.require_admission_for_provider_targets and (entry.provider_kind == .target or entry.provider_kind == .module_ref) and entry.admission_receipt_fingerprint == null) try blockers.append(allocator, .ProviderNotAdmitted);
            if (kind == .explicit_hint and blockers.items.len == 0) try warnings.append(allocator, .ExplicitHintSelected);

            const owned_blockers = try blockers.toOwnedSlice(allocator);
            errdefer allocator.free(owned_blockers);
            const owned_warnings = try warnings.toOwnedSlice(allocator);
            errdefer allocator.free(owned_warnings);
            return Match.init(.{
                .parent_import_requirement_fingerprint = requirement.requirement_fingerprint,
                .provider_export_fingerprint = if (entry.export_descriptor) |descriptor| descriptor.export_fingerprint else null,
                .provider_target_ref_fingerprint = if (entry.target_ref) |target_ref| target_ref.target_ref_fingerprint else null,
                .provider_module_ref_fingerprint = if (entry.module_ref) |module_ref| module_ref.module_ref_fingerprint else null,
                .kind = kind,
                .response_mapping = response_mapping,
                .confidence = if (owned_blockers.len != 0) .rejected else if (kind == .explicit_hint) .hinted else .exact,
                .blockers = owned_blockers,
                .warnings = owned_warnings,
            });
        }

        pub fn chooseProviderMatch(allocator: std.mem.Allocator, policy: Policy, requirement: W.ImportRequirement, candidates: []const Catalog.Entry, hint: ?Hint) !Match {
            var accepted: std.ArrayList(Match) = .empty;
            var rejected_blockers: std.ArrayList(Blocker) = .empty;
            defer {
                for (accepted.items) |candidate_match| {
                    allocator.free(candidate_match.blockers);
                    allocator.free(candidate_match.warnings);
                }
                accepted.deinit(allocator);
                rejected_blockers.deinit(allocator);
            }
            for (candidates) |candidate| {
                if (hint) |present| {
                    if (present.hasProviderSelector() and !providerTargetMatches(present, candidate)) continue;
                }
                const candidate_match = try matchEntry(allocator, policy, requirement, candidate, hint);
                if (candidate_match.accepted()) {
                    try accepted.append(allocator, candidate_match);
                } else {
                    for (candidate_match.blockers) |blocker| try rejected_blockers.append(allocator, blocker);
                    allocator.free(candidate_match.blockers);
                    allocator.free(candidate_match.warnings);
                }
            }
            if (accepted.items.len == 0) {
                const owned_blockers = if (rejected_blockers.items.len != 0) blk: {
                    const owned = try rejected_blockers.toOwnedSlice(allocator);
                    rejected_blockers = .empty;
                    break :blk owned;
                } else try allocator.dupe(Blocker, &.{.MissingProvider});
                return Match.init(.{
                    .parent_import_requirement_fingerprint = requirement.requirement_fingerprint,
                    .kind = .unsupported,
                    .confidence = .rejected,
                    .blockers = owned_blockers,
                    .warnings = try allocator.dupe(Warning, &.{}),
                });
            }
            if (hint) |present| {
                if (present.hasProviderSelector()) {
                    for (accepted.items, 0..) |candidate_match, index| {
                        const target_ok = present.provider_target_ref_fingerprint == null or present.provider_target_ref_fingerprint == candidate_match.provider_target_ref_fingerprint;
                        const module_ok = present.provider_module_ref_fingerprint == null or present.provider_module_ref_fingerprint == candidate_match.provider_module_ref_fingerprint;
                        const export_ok = present.provider_export_fingerprint == null or present.provider_export_fingerprint == candidate_match.provider_export_fingerprint;
                        if (target_ok and module_ok and export_ok) {
                            var selected = candidate_match;
                            selected.kind = .explicit_hint;
                            selected.confidence = .hinted;
                            selected.match_fingerprint = fingerprintMatch(selected);
                            _ = accepted.orderedRemove(index);
                            return selected;
                        }
                    }
                    const owned_blockers = if (rejected_blockers.items.len != 0) blk: {
                        const owned = try rejected_blockers.toOwnedSlice(allocator);
                        rejected_blockers = .empty;
                        break :blk owned;
                    } else try allocator.dupe(Blocker, &.{.AmbiguousProvider});
                    return Match.init(.{
                        .parent_import_requirement_fingerprint = requirement.requirement_fingerprint,
                        .kind = .unsupported,
                        .confidence = .rejected,
                        .blockers = owned_blockers,
                        .warnings = try allocator.dupe(Warning, &.{}),
                    });
                }
            }
            if (accepted.items.len == 1) {
                const selected = accepted.items[0];
                _ = accepted.orderedRemove(0);
                return selected;
            }
            if (policy.allow_ambiguous_matches and !policy.require_explicit_hint_for_ambiguous_match) {
                var selected = accepted.items[0];
                selected.confidence = .ambiguous;
                selected.match_fingerprint = fingerprintMatch(selected);
                _ = accepted.orderedRemove(0);
                return selected;
            }
            return Match.init(.{
                .parent_import_requirement_fingerprint = requirement.requirement_fingerprint,
                .kind = .unsupported,
                .confidence = .ambiguous,
                .blockers = try allocator.dupe(Blocker, &.{.AmbiguousProvider}),
                .warnings = try allocator.dupe(Warning, &.{}),
            });
        }

        pub const Graph = struct {
            graph_fingerprint: u64,
            root_target_ref_fingerprint: u64,
            nodes: []const Node = &.{},
            edges: []const Edge = &.{},
            blockers: []const Blocker = &.{},
            warnings: []const Warning = &.{},
            max_depth_observed: usize = 0,
            unresolved_required_count: usize = 0,
            ambiguous_match_count: usize = 0,

            pub const NodeKind = enum {
                target,
                import,
                target_module,
                import_requirement,
                export_descriptor,
                fabric_route,
                environment_external,
                replay_source,
                guest_provider,
                unresolved,
            };

            pub const EdgeKind = enum {
                target_requires_import,
                route_satisfies_import,
                route_invokes_provider,
                provider_requires_nested_import,
                environment_satisfies_import,
                replay_satisfies_import,
                guest_satisfies_import,
            };

            pub const Node = struct {
                kind: NodeKind,
                fingerprint: u64,
                node_fingerprint: u64 = 0,
                target_ref_fingerprint: ?u64 = null,
                import_requirement_fingerprint: ?u64 = null,
                label: []const u8 = "",

                pub fn init(args: struct {
                    kind: NodeKind,
                    target_ref_fingerprint: ?u64 = null,
                    import_requirement_fingerprint: ?u64 = null,
                    label: []const u8 = "",
                }) Node {
                    const fingerprint = nodeFingerprint(args.kind, args.target_ref_fingerprint orelse 0, args.import_requirement_fingerprint orelse 0);
                    return .{
                        .kind = args.kind,
                        .fingerprint = fingerprint,
                        .node_fingerprint = fingerprint,
                        .target_ref_fingerprint = args.target_ref_fingerprint,
                        .import_requirement_fingerprint = args.import_requirement_fingerprint,
                        .label = args.label,
                    };
                }
            };

            pub const Edge = struct {
                kind: EdgeKind,
                from_fingerprint: u64,
                to_fingerprint: u64,
                route_fingerprint: ?u64 = null,

                pub fn init(kind: EdgeKind, from_fingerprint: u64, to_fingerprint: u64) Edge {
                    return .{
                        .kind = kind,
                        .from_fingerprint = from_fingerprint,
                        .to_fingerprint = to_fingerprint,
                    };
                }
            };

            pub fn init(args: struct {
                root_target_ref_fingerprint: u64 = 0,
                nodes: []const Node = &.{},
                edges: []const Edge = &.{},
                blockers: []const Blocker = &.{},
                warnings: []const Warning = &.{},
                max_depth_observed: usize = 0,
                unresolved_required_count: usize = 0,
                unresolved_import_count: usize = 0,
                ambiguous_match_count: usize = 0,
            }) Graph {
                var result = Graph{
                    .graph_fingerprint = 0,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .nodes = args.nodes,
                    .edges = args.edges,
                    .blockers = args.blockers,
                    .warnings = args.warnings,
                    .max_depth_observed = args.max_depth_observed,
                    .unresolved_required_count = if (args.unresolved_required_count != 0) args.unresolved_required_count else args.unresolved_import_count,
                    .ambiguous_match_count = args.ambiguous_match_count,
                };
                result.graph_fingerprint = fingerprintGraph(result);
                return result;
            }

            pub fn hasBlocker(self: Graph, expected: Blocker) bool {
                for (self.blockers) |blocker| {
                    if (blocker == expected) return true;
                }
                return false;
            }
        };

        pub const RouteSynthesis = struct {
            synthesis_fingerprint: u64,
            parent_target_ref_fingerprint: u64,
            import_requirement_fingerprint: u64,
            match_fingerprint: u64,
            route_fingerprint: u64,
            value_mapping_fingerprint: ?u64 = null,

            pub fn init(args: struct {
                parent_target_ref_fingerprint: u64,
                import_requirement_fingerprint: u64,
                match_fingerprint: u64,
                route_fingerprint: u64,
                value_mapping_fingerprint: ?u64 = null,
            }) RouteSynthesis {
                var result = RouteSynthesis{
                    .synthesis_fingerprint = 0,
                    .parent_target_ref_fingerprint = args.parent_target_ref_fingerprint,
                    .import_requirement_fingerprint = args.import_requirement_fingerprint,
                    .match_fingerprint = args.match_fingerprint,
                    .route_fingerprint = args.route_fingerprint,
                    .value_mapping_fingerprint = args.value_mapping_fingerprint,
                };
                result.synthesis_fingerprint = fingerprintRouteSynthesis(result);
                return result;
            }
        };

        pub const NormalForm = enum {
            closed_fabric,
            fabric_with_external_ports,
            partial_with_blockers,
            inspect_only,
        };

        pub const Plan = struct {
            format_version: u32 = W.world_linker_plan_format_version,
            fingerprint_version: u32 = W.world_linker_plan_fingerprint_version,
            plan_fingerprint: u64,
            root_target_ref_fingerprint: u64,
            root_module_ref_fingerprint: ?u64 = null,
            policy_fingerprint: u64,
            catalog_fingerprint: u64,
            graph_fingerprint: u64,
            fabric_plans: []const W.Fabric.Plan = &.{},
            route_syntheses: []const RouteSynthesis = &.{},
            unresolved_imports: []const W.ImportRequirement = &.{},
            external_environment_requirements: []const W.ImportRequirement = &.{},
            provider_targets_used: []const u64 = &.{},
            guest_providers_used: []const u64 = &.{},
            replay_routes_used: []const u64 = &.{},
            reject_routes_used: []const u64 = &.{},
            blockers: []const Blocker = &.{},
            warnings: []const Warning = &.{},
            normal_form: NormalForm = .inspect_only,

            pub fn init(args: struct {
                root_target_ref_fingerprint: u64,
                root_module_ref_fingerprint: ?u64 = null,
                policy_fingerprint: u64,
                catalog_fingerprint: u64,
                graph_fingerprint: u64,
                fabric_plans: []const W.Fabric.Plan = &.{},
                route_syntheses: []const RouteSynthesis = &.{},
                unresolved_imports: []const W.ImportRequirement = &.{},
                external_environment_requirements: []const W.ImportRequirement = &.{},
                provider_targets_used: []const u64 = &.{},
                guest_providers_used: []const u64 = &.{},
                replay_routes_used: []const u64 = &.{},
                reject_routes_used: []const u64 = &.{},
                blockers: []const Blocker = &.{},
                warnings: []const Warning = &.{},
                normal_form: NormalForm = .inspect_only,
            }) Plan {
                var result = Plan{
                    .plan_fingerprint = 0,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .root_module_ref_fingerprint = args.root_module_ref_fingerprint,
                    .policy_fingerprint = args.policy_fingerprint,
                    .catalog_fingerprint = args.catalog_fingerprint,
                    .graph_fingerprint = args.graph_fingerprint,
                    .fabric_plans = args.fabric_plans,
                    .route_syntheses = args.route_syntheses,
                    .unresolved_imports = args.unresolved_imports,
                    .external_environment_requirements = args.external_environment_requirements,
                    .provider_targets_used = args.provider_targets_used,
                    .guest_providers_used = args.guest_providers_used,
                    .replay_routes_used = args.replay_routes_used,
                    .reject_routes_used = args.reject_routes_used,
                    .blockers = args.blockers,
                    .warnings = args.warnings,
                    .normal_form = args.normal_form,
                };
                result.plan_fingerprint = fingerprintPlan(result);
                return result;
            }

            pub fn accepted(self: Plan) bool {
                return self.blockers.len == 0 and self.normal_form != .partial_with_blockers;
            }

            pub fn externalImportSet(self: Plan) ResidualImportSet {
                return ResidualImportSet.init(.{
                    .root_target_ref_fingerprint = self.root_target_ref_fingerprint,
                    .requirements = self.external_environment_requirements,
                });
            }
        };

        pub const ResidualImportSet = struct {
            residual_import_set_fingerprint: u64,
            root_target_ref_fingerprint: u64,
            requirements: []const W.ImportRequirement = &.{},
            required_count: usize = 0,

            pub fn init(args: struct {
                root_target_ref_fingerprint: u64,
                requirements: []const W.ImportRequirement = &.{},
            }) ResidualImportSet {
                var result = ResidualImportSet{
                    .residual_import_set_fingerprint = 0,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .requirements = args.requirements,
                    .required_count = args.requirements.len,
                };
                result.residual_import_set_fingerprint = fingerprintResidualImportSet(result);
                return result;
            }
        };

        pub const Report = struct {
            report_fingerprint: u64,
            accepted: bool,
            root_target_ref_fingerprint: u64,
            candidate_count: usize = 0,
            import_count: usize = 0,
            resolved_import_count: usize = 0,
            external_import_count: usize = 0,
            unresolved_import_count: usize = 0,
            ambiguous_import_count: usize = 0,
            route_count: usize = 0,
            fabric_plan_count: usize = 0,
            cycle_blockers: usize = 0,
            value_mismatch_blockers: usize = 0,
            supervision_blockers: usize = 0,
            guest_conformance_blockers: usize = 0,
            summary: []const u8 = "",

            pub fn init(args: struct {
                accepted: bool,
                root_target_ref_fingerprint: u64,
                candidate_count: usize = 0,
                import_count: usize = 0,
                resolved_import_count: usize = 0,
                external_import_count: usize = 0,
                unresolved_import_count: usize = 0,
                ambiguous_import_count: usize = 0,
                route_count: usize = 0,
                fabric_plan_count: usize = 0,
                cycle_blockers: usize = 0,
                value_mismatch_blockers: usize = 0,
                supervision_blockers: usize = 0,
                guest_conformance_blockers: usize = 0,
                summary: []const u8 = "",
            }) Report {
                var result = Report{
                    .report_fingerprint = 0,
                    .accepted = args.accepted,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .candidate_count = args.candidate_count,
                    .import_count = args.import_count,
                    .resolved_import_count = args.resolved_import_count,
                    .external_import_count = args.external_import_count,
                    .unresolved_import_count = args.unresolved_import_count,
                    .ambiguous_import_count = args.ambiguous_import_count,
                    .route_count = args.route_count,
                    .fabric_plan_count = args.fabric_plan_count,
                    .cycle_blockers = args.cycle_blockers,
                    .value_mismatch_blockers = args.value_mismatch_blockers,
                    .supervision_blockers = args.supervision_blockers,
                    .guest_conformance_blockers = args.guest_conformance_blockers,
                    .summary = args.summary,
                };
                result.report_fingerprint = fingerprintReport(result);
                return result;
            }
        };

        pub const Certificate = struct {
            format_version: u32 = W.world_linker_certificate_format_version,
            fingerprint_version: u32 = W.world_linker_certificate_fingerprint_version,
            certificate_fingerprint: u64,
            link_plan_fingerprint: u64,
            link_graph_fingerprint: u64,
            report_fingerprint: u64,
            root_target_ref_fingerprint: u64,
            catalog_fingerprint: u64,
            fabric_plan_fingerprints: []const u64 = &.{},
            route_fingerprints: []const u64 = &.{},
            match_fingerprints: []const u64 = &.{},
            hint_fingerprints: []const u64 = &.{},
            policy_fingerprint: u64,
            blocker_count: usize = 0,
            warning_count: usize = 0,

            pub fn init(args: struct {
                link_plan_fingerprint: u64,
                link_graph_fingerprint: u64,
                report_fingerprint: u64,
                root_target_ref_fingerprint: u64,
                catalog_fingerprint: u64,
                fabric_plan_fingerprints: []const u64 = &.{},
                route_fingerprints: []const u64 = &.{},
                match_fingerprints: []const u64 = &.{},
                hint_fingerprints: []const u64 = &.{},
                policy_fingerprint: u64,
                blocker_count: usize = 0,
                warning_count: usize = 0,
            }) Certificate {
                var result = Certificate{
                    .certificate_fingerprint = 0,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .link_graph_fingerprint = args.link_graph_fingerprint,
                    .report_fingerprint = args.report_fingerprint,
                    .root_target_ref_fingerprint = args.root_target_ref_fingerprint,
                    .catalog_fingerprint = args.catalog_fingerprint,
                    .fabric_plan_fingerprints = args.fabric_plan_fingerprints,
                    .route_fingerprints = args.route_fingerprints,
                    .match_fingerprints = args.match_fingerprints,
                    .hint_fingerprints = args.hint_fingerprints,
                    .policy_fingerprint = args.policy_fingerprint,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                };
                result.certificate_fingerprint = fingerprintCertificate(result);
                return result;
            }
        };

        pub const Assembly = struct {
            assembly_fingerprint: u64,
            root_target_ref: W.TargetRef,
            root_admitted_run_fingerprint: ?u64 = null,
            link_plan_fingerprint: u64,
            linker_certificate_fingerprint: u64,
            environment_certificate_fingerprint: ?u64 = null,
            run_permit_fingerprint: ?u64 = null,
            fabric_plans: []const W.Fabric.Plan = &.{},
            external_import_requirements: []const W.ImportRequirement = &.{},
            admission_receipts_used: []const u64 = &.{},
            provider_run_templates: []const u64 = &.{},
            guest_provider_templates: []const u64 = &.{},

            pub fn init(args: struct {
                root_target_ref: W.TargetRef,
                root_admitted_run_fingerprint: ?u64 = null,
                link_plan_fingerprint: u64,
                linker_certificate_fingerprint: u64,
                environment_certificate_fingerprint: ?u64 = null,
                run_permit_fingerprint: ?u64 = null,
                fabric_plans: []const W.Fabric.Plan = &.{},
                external_import_requirements: []const W.ImportRequirement = &.{},
                admission_receipts_used: []const u64 = &.{},
                provider_run_templates: []const u64 = &.{},
                guest_provider_templates: []const u64 = &.{},
            }) Assembly {
                var result = Assembly{
                    .assembly_fingerprint = 0,
                    .root_target_ref = args.root_target_ref,
                    .root_admitted_run_fingerprint = args.root_admitted_run_fingerprint,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .linker_certificate_fingerprint = args.linker_certificate_fingerprint,
                    .environment_certificate_fingerprint = args.environment_certificate_fingerprint,
                    .run_permit_fingerprint = args.run_permit_fingerprint,
                    .fabric_plans = args.fabric_plans,
                    .external_import_requirements = args.external_import_requirements,
                    .admission_receipts_used = args.admission_receipts_used,
                    .provider_run_templates = args.provider_run_templates,
                    .guest_provider_templates = args.guest_provider_templates,
                };
                result.assembly_fingerprint = fingerprintAssembly(result);
                return result;
            }

            pub fn installIntoRunspace(self: Assembly, runspace: anytype) !void {
                try self.validate();
                for (self.fabric_plans) |fabric_plan| {
                    try runspace.installFabricPlan(self.root_target_ref, fabric_plan);
                }
            }

            pub fn preflightEnvironment(self: Assembly) ResidualImportSet {
                return self.residualImportSet();
            }

            pub fn preflightSupervision(self: Assembly, run_permit_fingerprint: u64) bool {
                return self.run_permit_fingerprint == null or self.run_permit_fingerprint.? == run_permit_fingerprint;
            }

            pub fn validate(self: Assembly) !void {
                if (fingerprintAssembly(self) != self.assembly_fingerprint) return error.InvalidFrameEncoding;
                for (self.fabric_plans) |plan| {
                    if (plan.target_ref_fingerprint != self.root_target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
                    if (plan.world_surface_fingerprint != self.root_target_ref.world_surface_fingerprint) return error.InvalidFrameEncoding;
                    if (plan.target_certificate_fingerprint != self.root_target_ref.target_certificate_fingerprint) return error.InvalidFrameEncoding;
                    if (plan.module_fingerprint != null and self.root_target_ref.boundary_module_fingerprint != null and plan.module_fingerprint.? != self.root_target_ref.boundary_module_fingerprint.?) return error.InvalidFrameEncoding;
                    try assertFabricInvariant(plan);
                }
            }

            pub fn residualImportSet(self: Assembly) ResidualImportSet {
                return ResidualImportSet.init(.{
                    .root_target_ref_fingerprint = self.root_target_ref.target_ref_fingerprint,
                    .requirements = self.external_import_requirements,
                });
            }

            pub fn summary(self: Assembly) Summary {
                return .{
                    .assembly_fingerprint = self.assembly_fingerprint,
                    .link_plan_fingerprint = self.link_plan_fingerprint,
                    .linker_certificate_fingerprint = self.linker_certificate_fingerprint,
                    .fabric_plan_count = self.fabric_plans.len,
                    .external_import_count = self.external_import_requirements.len,
                };
            }

            pub const Summary = struct {
                assembly_fingerprint: u64,
                link_plan_fingerprint: u64,
                linker_certificate_fingerprint: u64,
                fabric_plan_count: usize,
                external_import_count: usize,
            };
        };

        pub const Result = struct {
            allocator: std.mem.Allocator,
            import_index: ImportIndex,
            export_index: ExportIndex,
            matches: []const Match = &.{},
            graph: Graph,
            plan: Plan,
            report: Report,
            certificate: Certificate,
            assembly: Assembly,
            owned_nodes: []Graph.Node = &.{},
            owned_edges: []Graph.Edge = &.{},
            owned_blockers: []Blocker = &.{},
            owned_warnings: []Warning = &.{},
            owned_matches: []Match = &.{},
            owned_fabric_plans: []W.Fabric.Plan = &.{},
            owned_routes: []W.Fabric.Route = &.{},
            owned_bindings: []W.Fabric.Binding = &.{},
            owned_mappings: []W.Fabric.ValueMapping = &.{},
            owned_route_syntheses: []RouteSynthesis = &.{},
            owned_unresolved_imports: []W.ImportRequirement = &.{},
            owned_external_imports: []W.ImportRequirement = &.{},
            owned_provider_targets_used: []u64 = &.{},
            owned_guest_providers_used: []u64 = &.{},
            owned_replay_routes_used: []u64 = &.{},
            owned_reject_routes_used: []u64 = &.{},
            owned_admission_receipts_used: []u64 = &.{},
            owned_fabric_plan_fingerprints: []u64 = &.{},
            owned_route_fingerprints: []u64 = &.{},
            owned_match_fingerprints: []u64 = &.{},
            owned_hint_fingerprints: []u64 = &.{},

            pub fn deinit(self: *Result) void {
                for (self.owned_matches) |match| {
                    self.allocator.free(match.blockers);
                    self.allocator.free(match.warnings);
                }
                self.allocator.free(self.owned_nodes);
                self.allocator.free(self.owned_edges);
                self.allocator.free(self.owned_blockers);
                self.allocator.free(self.owned_warnings);
                self.allocator.free(self.owned_matches);
                self.allocator.free(self.owned_fabric_plans);
                self.allocator.free(self.owned_routes);
                self.allocator.free(self.owned_bindings);
                self.allocator.free(self.owned_mappings);
                self.allocator.free(self.owned_route_syntheses);
                self.allocator.free(self.owned_unresolved_imports);
                self.allocator.free(self.owned_external_imports);
                self.allocator.free(self.owned_provider_targets_used);
                self.allocator.free(self.owned_guest_providers_used);
                self.allocator.free(self.owned_replay_routes_used);
                self.allocator.free(self.owned_reject_routes_used);
                self.allocator.free(self.owned_admission_receipts_used);
                self.allocator.free(self.owned_fabric_plan_fingerprints);
                self.allocator.free(self.owned_route_fingerprints);
                self.allocator.free(self.owned_match_fingerprints);
                self.allocator.free(self.owned_hint_fingerprints);
                self.* = undefined;
            }
        };

        pub fn link(allocator: std.mem.Allocator, input: Input) !Result {
            var policy = input.policy;
            if (input.max_depth) |max_depth| policy.max_link_depth = max_depth;
            if (input.max_provider_candidates) |max| policy.max_candidates_per_import = max;
            const max_routes = input.max_routes orelse policy.max_provider_runs;

            const import_index = ImportIndex.init(input);
            const export_index = ExportIndex.init(input.catalog);
            var routes: std.ArrayList(W.Fabric.Route) = .empty;
            var bindings: std.ArrayList(W.Fabric.Binding) = .empty;
            var mappings: std.ArrayList(W.Fabric.ValueMapping) = .empty;
            var matches: std.ArrayList(Match) = .empty;
            var syntheses: std.ArrayList(RouteSynthesis) = .empty;
            var nodes: std.ArrayList(Graph.Node) = .empty;
            var edges: std.ArrayList(Graph.Edge) = .empty;
            var blockers: std.ArrayList(Blocker) = .empty;
            var warnings: std.ArrayList(Warning) = .empty;
            var unresolved: std.ArrayList(W.ImportRequirement) = .empty;
            var external: std.ArrayList(W.ImportRequirement) = .empty;
            var provider_targets: std.ArrayList(u64) = .empty;
            var guest_targets: std.ArrayList(u64) = .empty;
            var replay_routes: std.ArrayList(u64) = .empty;
            var reject_routes: std.ArrayList(u64) = .empty;
            var admission_receipts: std.ArrayList(u64) = .empty;
            var fabric_plan_fingerprints: std.ArrayList(u64) = .empty;
            var route_fingerprints: std.ArrayList(u64) = .empty;
            var match_fingerprints: std.ArrayList(u64) = .empty;
            var hint_fingerprints: std.ArrayList(u64) = .empty;
            errdefer routes.deinit(allocator);
            errdefer bindings.deinit(allocator);
            errdefer mappings.deinit(allocator);
            errdefer matches.deinit(allocator);
            errdefer syntheses.deinit(allocator);
            errdefer nodes.deinit(allocator);
            errdefer edges.deinit(allocator);
            errdefer blockers.deinit(allocator);
            errdefer warnings.deinit(allocator);
            errdefer unresolved.deinit(allocator);
            errdefer external.deinit(allocator);
            errdefer provider_targets.deinit(allocator);
            errdefer guest_targets.deinit(allocator);
            errdefer replay_routes.deinit(allocator);
            errdefer reject_routes.deinit(allocator);
            errdefer admission_receipts.deinit(allocator);
            errdefer fabric_plan_fingerprints.deinit(allocator);
            errdefer route_fingerprints.deinit(allocator);
            errdefer match_fingerprints.deinit(allocator);
            errdefer hint_fingerprints.deinit(allocator);

            for (input.hints) |hint| try hint_fingerprints.append(allocator, hint.hint_fingerprint);
            const root_node = Graph.Node.init(.{
                .kind = .target_module,
                .target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                .label = input.root_target_ref.target_label orelse "",
            });
            try nodes.append(allocator, root_node);

            var resolved_count: usize = 0;
            var ambiguous_count: usize = 0;
            var max_depth_observed: usize = 0;
            var root_port_coverage = try allocator.alloc(bool, input.root_import_set.required_count);
            defer allocator.free(root_port_coverage);
            @memset(root_port_coverage, false);
            var root_import_set_mismatch =
                input.root_import_set.target_ref_fingerprint != input.root_target_ref.target_ref_fingerprint or
                input.root_imports.len != input.root_import_set.required_count;
            for (input.root_imports) |requirement| {
                if (requirement.world_surface_fingerprint != input.root_target_ref.world_surface_fingerprint or
                    requirement.world_port_id >= input.root_import_set.required_count)
                {
                    root_import_set_mismatch = true;
                    continue;
                }
                if (root_port_coverage[requirement.world_port_id]) {
                    root_import_set_mismatch = true;
                    continue;
                }
                root_port_coverage[requirement.world_port_id] = true;
            }
            for (root_port_coverage) |covered| {
                if (!covered) {
                    root_import_set_mismatch = true;
                    break;
                }
            }
            if (root_import_set_mismatch) {
                try blockers.append(allocator, .RootImportSetMismatch);
            }
            const ordered_root_imports = try allocator.dupe(W.ImportRequirement, input.root_imports);
            defer allocator.free(ordered_root_imports);
            sortImportRequirements(ordered_root_imports);
            for (ordered_root_imports) |requirement| {
                const import_node = Graph.Node.init(.{
                    .kind = .import_requirement,
                    .target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .import_requirement_fingerprint = requirement.requirement_fingerprint,
                    .label = requirement.suggested_symbolic_name orelse "",
                });
                try nodes.append(allocator, import_node);
                try edges.append(allocator, Graph.Edge.init(.target_requires_import, root_node.fingerprint, import_node.fingerprint));

                const candidates = try export_index.candidateProvidersForPolicy(allocator, requirement, policy);
                defer allocator.free(candidates);
                if (candidates.len > policy.max_candidates_per_import) {
                    try unresolved.append(allocator, requirement);
                    try blockers.append(allocator, .ProviderRunLimitExceeded);
                    continue;
                }
                if (candidates.len == 0) {
                    if (policy.allow_external_environment_ports and external.items.len < policy.max_unresolved_imports) {
                        try external.append(allocator, requirement);
                        try warnings.append(allocator, .ExternalEnvironmentRequired);
                    } else {
                        try unresolved.append(allocator, requirement);
                        try blockers.append(allocator, .MissingProvider);
                    }
                    continue;
                }
                var selected_hint: ?Hint = null;
                for (input.hints) |hint| {
                    for (candidates) |candidate| {
                        if (hint.selects(input.root_target_ref, requirement, candidate)) selected_hint = hint;
                    }
                }
                const chosen = try chooseProviderMatch(allocator, policy, requirement, candidates, selected_hint);
                try matches.append(allocator, chosen);
                try match_fingerprints.append(allocator, chosen.match_fingerprint);
                if (!chosen.accepted()) {
                    for (chosen.blockers) |blocker| try blockers.append(allocator, blocker);
                    if (chosen.confidence == .ambiguous) ambiguous_count += 1;
                    continue;
                }
                const entry = entryForMatch(candidates, chosen) orelse {
                    try blockers.append(allocator, .MissingProvider);
                    continue;
                };
                const provider_ref = providerTargetRef(entry) orelse {
                    try blockers.append(allocator, .MissingProvider);
                    continue;
                };
                const provider_import_required_count = if (entry.import_set) |import_set| import_set.required_count else entry.imports.len;
                if (policy.require_closed_graph and provider_import_required_count != entry.imports.len) {
                    try blockers.append(allocator, .ProviderRequiresUnsupportedImports);
                    if (provider_import_required_count != 0) max_depth_observed = @max(max_depth_observed, 2);
                    continue;
                }
                if (entry.imports.len != 0 and policy.require_closed_graph) {
                    const provider_node = Graph.Node.init(.{
                        .kind = .target_module,
                        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
                        .label = provider_ref.target_label orelse "",
                    });
                    try nodes.append(allocator, provider_node);
                    for (entry.imports) |nested_requirement| {
                        const nested_import_node = Graph.Node.init(.{
                            .kind = .import_requirement,
                            .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
                            .import_requirement_fingerprint = nested_requirement.requirement_fingerprint,
                            .label = nested_requirement.suggested_symbolic_name orelse "",
                        });
                        try nodes.append(allocator, nested_import_node);
                        try edges.append(allocator, Graph.Edge.init(.provider_requires_nested_import, provider_node.fingerprint, nested_import_node.fingerprint));
                    }
                    try blockers.append(allocator, .ProviderRequiresUnsupportedImports);
                    max_depth_observed = @max(max_depth_observed, 2);
                    continue;
                }
                if (policy.reject_same_target_cycle and provider_ref.target_ref_fingerprint == input.root_target_ref.target_ref_fingerprint) {
                    try blockers.append(allocator, .CycleDetected);
                    continue;
                }
                if (policy.reject_same_module_cycle and sameModuleFingerprint(input.root_module_ref, input.root_target_ref, entry, provider_ref)) {
                    try blockers.append(allocator, .CycleDetected);
                    continue;
                }
                if (routes.items.len >= max_routes) {
                    try blockers.append(allocator, .ProviderRunLimitExceeded);
                    continue;
                }
                if (policy.max_link_depth < 1) {
                    try unresolved.append(allocator, requirement);
                    try blockers.append(allocator, .DepthExceeded);
                    continue;
                }
                const mapping = chosen.response_mapping orelse try synthesizeResponseMapping(requirement, entry);
                const route_kind = routeKindForEntry(entry);
                const route = W.Fabric.Route.init(.{
                    .route_id = routeIdFor(input.root_target_ref, requirement),
                    .kind = route_kind,
                    .world_port_id = requirement.world_port_id,
                    .parent_world_surface_fingerprint = input.root_target_ref.world_surface_fingerprint,
                    .parent_target_certificate_fingerprint = input.root_target_ref.target_certificate_fingerprint,
                    .parent_world_port_id = requirement.world_port_id,
                    .provider_target_ref_fingerprint = provider_ref.target_ref_fingerprint,
                    .provider_module_fingerprint = if (entry.module_ref) |module_ref| module_ref.module_ref_fingerprint else provider_ref.boundary_module_fingerprint,
                    .provider_world_surface_fingerprint = provider_ref.world_surface_fingerprint,
                    .provider_target_certificate_fingerprint = provider_ref.target_certificate_fingerprint,
                    .provider_admission_receipt_fingerprint = entry.admission_receipt_fingerprint,
                    .provider_transcript_image_fingerprint = entry.replay_transcript_image_fingerprint,
                    .response_value_mapping_fingerprint = mapping.mapping_fingerprint,
                    .response_status = if (route_kind == .reject) .rejected else .responded,
                    .max_depth = policy.max_link_depth,
                    .metadata = "world-linker-route",
                });
                try route.validate();
                const binding = W.Fabric.Binding.init(.{
                    .parent_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .parent_world_surface_fingerprint = input.root_target_ref.world_surface_fingerprint,
                    .parent_target_certificate_fingerprint = input.root_target_ref.target_certificate_fingerprint,
                    .world_port_id = requirement.world_port_id,
                    .import_requirement_fingerprint = requirement.requirement_fingerprint,
                    .route_fingerprint = route.route_fingerprint,
                    .value_mapping_fingerprint = mapping.mapping_fingerprint,
                });
                try routes.append(allocator, route);
                try bindings.append(allocator, binding);
                try mappings.append(allocator, mapping);
                try syntheses.append(allocator, RouteSynthesis.init(.{
                    .parent_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .import_requirement_fingerprint = requirement.requirement_fingerprint,
                    .match_fingerprint = chosen.match_fingerprint,
                    .route_fingerprint = route.route_fingerprint,
                    .value_mapping_fingerprint = mapping.mapping_fingerprint,
                }));
                try provider_targets.append(allocator, provider_ref.target_ref_fingerprint);
                try route_fingerprints.append(allocator, route.route_fingerprint);
                if (route_kind == .guest) try guest_targets.append(allocator, provider_ref.target_ref_fingerprint);
                if (route_kind == .replay) try replay_routes.append(allocator, route.route_fingerprint);
                if (route_kind == .reject) try reject_routes.append(allocator, route.route_fingerprint);
                if (entry.admission_receipt_fingerprint) |receipt| try appendUniqueU64(allocator, &admission_receipts, receipt);
                const route_node = Graph.Node.init(.{
                    .kind = .fabric_route,
                    .target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .import_requirement_fingerprint = route.route_fingerprint,
                    .label = "route",
                });
                try nodes.append(allocator, route_node);
                try edges.append(allocator, .{
                    .kind = .route_satisfies_import,
                    .from_fingerprint = route_node.fingerprint,
                    .to_fingerprint = import_node.fingerprint,
                    .route_fingerprint = route.route_fingerprint,
                });
                max_depth_observed = @max(max_depth_observed, 1);
                if (entry.imports.len != 0) {
                    const nested_depth: usize = 2;
                    max_depth_observed = @max(max_depth_observed, nested_depth);
                    if (nested_depth > policy.max_link_depth) {
                        try blockers.append(allocator, .DepthExceeded);
                    }
                    const provider_node = Graph.Node.init(.{
                        .kind = .target_module,
                        .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
                        .label = provider_ref.target_label orelse "",
                    });
                    try nodes.append(allocator, provider_node);
                    try edges.append(allocator, .{
                        .kind = .route_invokes_provider,
                        .from_fingerprint = route_node.fingerprint,
                        .to_fingerprint = provider_node.fingerprint,
                        .route_fingerprint = route.route_fingerprint,
                    });
                    for (entry.imports) |nested_requirement| {
                        const nested_import_node = Graph.Node.init(.{
                            .kind = .import_requirement,
                            .target_ref_fingerprint = provider_ref.target_ref_fingerprint,
                            .import_requirement_fingerprint = nested_requirement.requirement_fingerprint,
                            .label = nested_requirement.suggested_symbolic_name orelse "",
                        });
                        try nodes.append(allocator, nested_import_node);
                        try edges.append(allocator, Graph.Edge.init(.provider_requires_nested_import, provider_node.fingerprint, nested_import_node.fingerprint));
                    }
                }
                resolved_count += 1;
            }

            const owned_routes = try routes.toOwnedSlice(allocator);
            routes = .empty;
            const owned_bindings = try bindings.toOwnedSlice(allocator);
            bindings = .empty;
            const owned_mappings = try mappings.toOwnedSlice(allocator);
            mappings = .empty;
            const owned_nodes = try nodes.toOwnedSlice(allocator);
            nodes = .empty;
            const owned_edges = try edges.toOwnedSlice(allocator);
            edges = .empty;
            const owned_blockers = try blockers.toOwnedSlice(allocator);
            blockers = .empty;
            const owned_warnings = try warnings.toOwnedSlice(allocator);
            warnings = .empty;
            const owned_matches = try matches.toOwnedSlice(allocator);
            matches = .empty;
            const owned_syntheses = try syntheses.toOwnedSlice(allocator);
            syntheses = .empty;
            const owned_unresolved = try unresolved.toOwnedSlice(allocator);
            unresolved = .empty;
            const owned_external = try external.toOwnedSlice(allocator);
            external = .empty;
            const owned_provider_targets = try provider_targets.toOwnedSlice(allocator);
            provider_targets = .empty;
            const owned_guest_targets = try guest_targets.toOwnedSlice(allocator);
            guest_targets = .empty;
            const owned_replay_routes = try replay_routes.toOwnedSlice(allocator);
            replay_routes = .empty;
            const owned_reject_routes = try reject_routes.toOwnedSlice(allocator);
            reject_routes = .empty;
            const owned_admission_receipts = try admission_receipts.toOwnedSlice(allocator);
            admission_receipts = .empty;
            const owned_route_fingerprints = try route_fingerprints.toOwnedSlice(allocator);
            route_fingerprints = .empty;
            const owned_match_fingerprints = try match_fingerprints.toOwnedSlice(allocator);
            match_fingerprints = .empty;
            const owned_hint_fingerprints = try hint_fingerprints.toOwnedSlice(allocator);
            hint_fingerprints = .empty;

            var fabric_plans: std.ArrayList(W.Fabric.Plan) = .empty;
            if (owned_routes.len != 0 and owned_blockers.len == 0) {
                const fabric_plan = W.Fabric.Plan.init(.{
                    .target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                    .module_fingerprint = input.root_target_ref.boundary_module_fingerprint,
                    .world_surface_fingerprint = input.root_target_ref.world_surface_fingerprint,
                    .target_certificate_fingerprint = input.root_target_ref.target_certificate_fingerprint,
                    .import_set_fingerprint = input.root_import_set.import_set_fingerprint,
                    .routes = owned_routes,
                    .bindings = owned_bindings,
                    .value_mappings = owned_mappings,
                    .max_depth = policy.max_link_depth,
                    .max_provider_runs = max_routes,
                    .metadata = "world-linker-synthesized",
                });
                try assertFabricInvariant(fabric_plan);
                try fabric_plans.append(allocator, fabric_plan);
                try fabric_plan_fingerprints.append(allocator, fabric_plan.plan_fingerprint);
            }
            const owned_fabric_plans = try fabric_plans.toOwnedSlice(allocator);
            fabric_plans = .empty;
            const owned_fabric_plan_fingerprints = try fabric_plan_fingerprints.toOwnedSlice(allocator);
            fabric_plan_fingerprints = .empty;

            const graph = Graph.init(.{
                .root_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                .nodes = owned_nodes,
                .edges = owned_edges,
                .blockers = owned_blockers,
                .warnings = owned_warnings,
                .max_depth_observed = max_depth_observed,
                .unresolved_required_count = owned_unresolved.len,
                .ambiguous_match_count = ambiguous_count,
            });
            const normal_form: NormalForm = if (owned_blockers.len != 0 or (policy.require_closed_graph and owned_external.len != 0))
                .partial_with_blockers
            else if (owned_external.len != 0)
                .fabric_with_external_ports
            else
                .closed_fabric;
            const plan = Plan.init(.{
                .root_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                .root_module_ref_fingerprint = if (input.root_module_ref) |module_ref| module_ref.module_ref_fingerprint else null,
                .policy_fingerprint = policy.fingerprint(),
                .catalog_fingerprint = input.catalog.catalog_fingerprint,
                .graph_fingerprint = graph.graph_fingerprint,
                .fabric_plans = owned_fabric_plans,
                .route_syntheses = owned_syntheses,
                .unresolved_imports = owned_unresolved,
                .external_environment_requirements = owned_external,
                .provider_targets_used = owned_provider_targets,
                .guest_providers_used = owned_guest_targets,
                .replay_routes_used = owned_replay_routes,
                .reject_routes_used = owned_reject_routes,
                .blockers = owned_blockers,
                .warnings = owned_warnings,
                .normal_form = normal_form,
            });
            const report = Report.init(.{
                .accepted = plan.accepted(),
                .root_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                .candidate_count = input.catalog.entries.len,
                .import_count = input.root_imports.len,
                .resolved_import_count = resolved_count,
                .external_import_count = owned_external.len,
                .unresolved_import_count = owned_unresolved.len,
                .ambiguous_import_count = ambiguous_count,
                .route_count = owned_routes.len,
                .fabric_plan_count = owned_fabric_plans.len,
                .cycle_blockers = countBlocker(owned_blockers, .CycleDetected),
                .value_mismatch_blockers = countBlocker(owned_blockers, .ResponseRefMismatch) + countBlocker(owned_blockers, .ResultRefMismatch),
                .supervision_blockers = countBlocker(owned_blockers, .SupervisionIncompatible),
                .guest_conformance_blockers = countBlocker(owned_blockers, .GuestConformanceMissing),
                .summary = if (plan.accepted()) "linked assembly accepted" else "linked assembly blocked",
            });
            const certificate = Certificate.init(.{
                .link_plan_fingerprint = plan.plan_fingerprint,
                .link_graph_fingerprint = graph.graph_fingerprint,
                .report_fingerprint = report.report_fingerprint,
                .root_target_ref_fingerprint = input.root_target_ref.target_ref_fingerprint,
                .catalog_fingerprint = input.catalog.catalog_fingerprint,
                .fabric_plan_fingerprints = owned_fabric_plan_fingerprints,
                .route_fingerprints = owned_route_fingerprints,
                .match_fingerprints = owned_match_fingerprints,
                .hint_fingerprints = owned_hint_fingerprints,
                .policy_fingerprint = policy.fingerprint(),
                .blocker_count = owned_blockers.len,
                .warning_count = owned_warnings.len,
            });
            const assembly_fabric_plans = if (plan.accepted()) owned_fabric_plans else &.{};
            const assembly_external_imports = if (plan.accepted()) owned_external else &.{};
            const assembly_provider_targets = if (plan.accepted()) owned_provider_targets else &.{};
            const assembly_guest_targets = if (plan.accepted()) owned_guest_targets else &.{};
            const assembly_admission_receipts = if (plan.accepted()) owned_admission_receipts else &.{};
            const assembly = Assembly.init(.{
                .root_target_ref = input.root_target_ref,
                .link_plan_fingerprint = plan.plan_fingerprint,
                .linker_certificate_fingerprint = certificate.certificate_fingerprint,
                .run_permit_fingerprint = input.run_permit_fingerprint,
                .fabric_plans = assembly_fabric_plans,
                .external_import_requirements = assembly_external_imports,
                .admission_receipts_used = assembly_admission_receipts,
                .provider_run_templates = assembly_provider_targets,
                .guest_provider_templates = assembly_guest_targets,
            });
            return .{
                .allocator = allocator,
                .import_index = import_index,
                .export_index = export_index,
                .matches = owned_matches,
                .graph = graph,
                .plan = plan,
                .report = report,
                .certificate = certificate,
                .assembly = assembly,
                .owned_nodes = owned_nodes,
                .owned_edges = owned_edges,
                .owned_blockers = owned_blockers,
                .owned_warnings = owned_warnings,
                .owned_matches = owned_matches,
                .owned_fabric_plans = owned_fabric_plans,
                .owned_routes = owned_routes,
                .owned_bindings = owned_bindings,
                .owned_mappings = owned_mappings,
                .owned_route_syntheses = owned_syntheses,
                .owned_unresolved_imports = owned_unresolved,
                .owned_external_imports = owned_external,
                .owned_provider_targets_used = owned_provider_targets,
                .owned_guest_providers_used = owned_guest_targets,
                .owned_replay_routes_used = owned_replay_routes,
                .owned_reject_routes_used = owned_reject_routes,
                .owned_admission_receipts_used = owned_admission_receipts,
                .owned_fabric_plan_fingerprints = owned_fabric_plan_fingerprints,
                .owned_route_fingerprints = owned_route_fingerprints,
                .owned_match_fingerprints = owned_match_fingerprints,
                .owned_hint_fingerprints = owned_hint_fingerprints,
            };
        }

        pub fn assertFabricInvariant(plan: W.Fabric.Plan) !void {
            try plan.validate();
            try plan.assertDeterministicRouteOrder();
            try plan.assertNoCycles();
            try plan.assertExecutableMappings();
            for (plan.routes) |route| {
                try route.validate();
                switch (route.kind) {
                    .target_export, .admitted_run => {
                        if (route.provider_target_ref_fingerprint == null and route.provider_module_fingerprint == null) return error.ProviderRunDenied;
                        if (route.response_value_mapping_fingerprint == null and route.value_mapping_fingerprint == null) return error.UnsupportedMapping;
                    },
                    .reject, .unsupported, .replay => {},
                    .guest, .adapter => return error.UnsupportedMapping,
                }
                if (route.metadata.len == 0) return error.InvalidFrameEncoding;
            }
        }

        fn valueRefForRequirement(requirement: W.ImportRequirement) ValueRef {
            return .{ .value_table_id = requirement.response_value_table_id };
        }

        fn routeKindForEntry(entry: Catalog.Entry) W.Fabric.RouteKind {
            return switch (entry.provider_kind) {
                .target, .module_ref => .target_export,
                .admitted_run => .admitted_run,
                .guest_provider => .guest,
                .replay_provider => .replay,
                .reject_route => .reject,
                .environment_adapter => .adapter,
            };
        }

        fn appendUniqueU64(allocator: std.mem.Allocator, list: *std.ArrayList(u64), value: u64) !void {
            for (list.items) |existing| {
                if (existing == value) return;
            }
            try list.append(allocator, value);
        }

        fn sortImportRequirements(requirements: []W.ImportRequirement) void {
            var index: usize = 1;
            while (index < requirements.len) : (index += 1) {
                var cursor = index;
                while (cursor > 0 and importRequirementLess(requirements[cursor], requirements[cursor - 1])) : (cursor -= 1) {
                    std.mem.swap(W.ImportRequirement, &requirements[cursor], &requirements[cursor - 1]);
                }
            }
        }

        fn importRequirementLess(lhs: W.ImportRequirement, rhs: W.ImportRequirement) bool {
            if (lhs.world_port_id != rhs.world_port_id) return lhs.world_port_id < rhs.world_port_id;
            return lhs.requirement_fingerprint < rhs.requirement_fingerprint;
        }

        fn providerTargetRef(entry: Catalog.Entry) ?W.TargetRef {
            if (entry.target_ref) |target_ref| return target_ref;
            if (entry.module_ref) |module_ref| {
                return W.TargetRef{
                    .target_ref_fingerprint = module_ref.target_ref_fingerprint,
                    .target_label = module_ref.label,
                    .world_surface_fingerprint = module_ref.world_surface_fingerprint,
                    .target_certificate_fingerprint = module_ref.target_certificate_fingerprint,
                    .residual_program_plan_hash = module_ref.residual_program_plan_hash,
                    .normal_form_kind = module_ref.normal_form_kind,
                    .world_port_table_fingerprint = module_ref.world_port_table_fingerprint,
                    .world_value_table_fingerprint = module_ref.world_value_table_fingerprint,
                    .world_dispatch_table_fingerprint = module_ref.world_dispatch_table_fingerprint,
                    .boundary_module_fingerprint = module_ref.boundary_module_fingerprint,
                    .metadata = module_ref.metadata,
                };
            }
            return null;
        }

        fn linkerCanSynthesizeRouteKind(entry: Catalog.Entry) bool {
            return switch (entry.provider_kind) {
                .target, .module_ref, .admitted_run => true,
                .guest_provider, .replay_provider, .reject_route, .environment_adapter => false,
            };
        }

        fn matchKindForEntry(entry: Catalog.Entry) MatchKind {
            return switch (entry.provider_kind) {
                .target, .module_ref, .admitted_run => .exact_value_refs,
                .guest_provider => .guest,
                .replay_provider => .replay,
                .reject_route => .reject,
                .environment_adapter => .adapter,
            };
        }

        fn synthesizeResponseMapping(requirement: W.ImportRequirement, entry: Catalog.Entry) !W.Fabric.ValueMapping {
            const descriptor = entry.export_descriptor orelse return error.MissingProvider;
            const parent_value = requirement.response_value_table_id orelse return error.ResponseRefMismatch;
            const provider_value = descriptor.result_ref.value_table_id orelse return error.ResultRefMismatch;
            return W.Fabric.ValueMapping.init(.{
                .kind = .provider_result_to_parent_response,
                .provider_result_value_table_id = provider_value,
                .provider_result_value_fingerprint = descriptor.result_ref.value_ref_fingerprint,
                .parent_response_value_table_id = parent_value,
                .parent_response_value_fingerprint = descriptor.result_ref.value_ref_fingerprint,
            });
        }

        fn routeIdFor(target_ref: W.TargetRef, requirement: W.ImportRequirement) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.route.id.v1");
            hashU64(&hasher, target_ref.target_ref_fingerprint);
            hashU64(&hasher, requirement.requirement_fingerprint);
            return hasher.final();
        }

        fn nodeFingerprint(kind: Graph.NodeKind, left: u64, right: u64) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.graph.node.v1");
            hashU64(&hasher, @intFromEnum(kind));
            hashU64(&hasher, left);
            hashU64(&hasher, right);
            return hasher.final();
        }

        fn entryForMatch(candidates: []const Catalog.Entry, match: Match) ?Catalog.Entry {
            for (candidates) |candidate| {
                const descriptor = candidate.export_descriptor orelse continue;
                if (match.provider_export_fingerprint != descriptor.export_fingerprint) continue;
                return candidate;
            }
            return null;
        }

        fn providerTargetMatches(self: Hint, entry: Catalog.Entry) bool {
            if (!self.hasProviderSelector()) return false;
            if (self.provider_target_ref_fingerprint) |expected| {
                if (entry.target_ref == null or entry.target_ref.?.target_ref_fingerprint != expected) return false;
            }
            if (self.provider_module_ref_fingerprint) |expected| {
                if (entry.module_ref == null or entry.module_ref.?.module_ref_fingerprint != expected) return false;
            }
            if (self.provider_export_fingerprint) |expected| {
                if (entry.export_descriptor == null or entry.export_descriptor.?.export_fingerprint != expected) return false;
            }
            return true;
        }

        fn sameModuleFingerprint(root_module_ref: ?W.Admission.ModuleRef, root_target_ref: W.TargetRef, entry: Catalog.Entry, provider_ref: W.TargetRef) bool {
            const root_module = if (root_module_ref) |module_ref| module_ref.module_ref_fingerprint else root_target_ref.boundary_module_fingerprint;
            const provider_module = if (entry.module_ref) |module_ref| module_ref.module_ref_fingerprint else provider_ref.boundary_module_fingerprint;
            if (root_module == null or provider_module == null) return false;
            return root_module.? == provider_module.?;
        }

        fn countBlocker(blockers: []const Blocker, expected: Blocker) usize {
            var count: usize = 0;
            for (blockers) |blocker| {
                if (blocker == expected) count += 1;
            }
            return count;
        }

        fn fingerprintExportDescriptor(descriptor: ExportDescriptor) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.export.descriptor.v1");
            hashU64(&hasher, W.world_linker_export_index_fingerprint_version);
            hashU64(&hasher, descriptor.target_ref.target_ref_fingerprint);
            if (descriptor.module_ref) |module_ref| hashU64(&hasher, module_ref.module_ref_fingerprint) else hashU64(&hasher, 0);
            hashOptionalU64(&hasher, descriptor.export_ref_fingerprint);
            hashU64(&hasher, descriptor.argument_refs.len);
            for (descriptor.argument_refs) |value_ref| hashU64(&hasher, value_ref.fingerprint());
            hashU64(&hasher, descriptor.result_ref.fingerprint());
            hashU64(&hasher, @intFromEnum(descriptor.normal_form_kind));
            hashBytes(&hasher, descriptor.label);
            hashBytes(&hasher, descriptor.metadata);
            return hasher.final();
        }

        fn fingerprintCatalogEntry(entry: Catalog.Entry) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.catalog.entry.v1");
            hashU64(&hasher, W.world_linker_catalog_entry_fingerprint_version);
            hashU64(&hasher, @intFromEnum(entry.provider_kind));
            if (entry.target_ref) |target_ref| hashU64(&hasher, target_ref.target_ref_fingerprint) else hashU64(&hasher, 0);
            if (entry.module_ref) |module_ref| hashU64(&hasher, module_ref.module_ref_fingerprint) else hashU64(&hasher, 0);
            if (entry.export_summary) |summary| hashU64(&hasher, summary.export_summary_fingerprint) else hashU64(&hasher, 0);
            if (entry.export_descriptor) |descriptor| hashU64(&hasher, descriptor.export_fingerprint) else hashU64(&hasher, 0);
            if (entry.import_set) |import_set| hashU64(&hasher, import_set.import_set_fingerprint) else hashU64(&hasher, 0);
            hashU64(&hasher, entry.imports.len);
            for (entry.imports) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashOptionalU64(&hasher, entry.admission_receipt_fingerprint);
            hashOptionalU64(&hasher, entry.environment_certificate_fingerprint);
            hashOptionalU64(&hasher, entry.run_permit_fingerprint);
            hashOptionalU64(&hasher, entry.replay_transcript_image_fingerprint);
            hashOptionalU64(&hasher, entry.guest_conformance_report_fingerprint);
            hashBytes(&hasher, entry.label);
            hashBytes(&hasher, entry.metadata);
            return hasher.final();
        }

        fn fingerprintCatalog(entries: []const Catalog.Entry) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.catalog.v1");
            hashU64(&hasher, W.world_linker_catalog_fingerprint_version);
            hashU64(&hasher, entries.len);
            for (entries) |entry| hashU64(&hasher, entry.entry_fingerprint);
            return hasher.final();
        }

        fn fingerprintImportIndex(index: ImportIndex) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.import.index.v1");
            hashU64(&hasher, W.world_linker_import_index_fingerprint_version);
            hashU64(&hasher, index.root_target_ref_fingerprint);
            hashU64(&hasher, index.root_imports.len);
            for (index.root_imports) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashU64(&hasher, index.catalog.catalog_fingerprint);
            return hasher.final();
        }

        fn fingerprintExportIndex(index: ExportIndex) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.export.index.v1");
            hashU64(&hasher, W.world_linker_export_index_fingerprint_version);
            hashU64(&hasher, index.catalog.catalog_fingerprint);
            return hasher.final();
        }

        fn fingerprintMatch(match: Match) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.match.v1");
            hashU64(&hasher, W.world_linker_match_fingerprint_version);
            hashU64(&hasher, match.parent_import_requirement_fingerprint);
            hashOptionalU64(&hasher, match.provider_export_fingerprint);
            hashOptionalU64(&hasher, match.provider_target_ref_fingerprint);
            hashOptionalU64(&hasher, match.provider_module_ref_fingerprint);
            hashU64(&hasher, @intFromEnum(match.kind));
            hashOptionalU64(&hasher, if (match.payload_mapping) |mapping| mapping.mapping_fingerprint else null);
            hashOptionalU64(&hasher, if (match.response_mapping) |mapping| mapping.mapping_fingerprint else null);
            hashU64(&hasher, @intFromEnum(match.confidence));
            hashU64(&hasher, match.blockers.len);
            for (match.blockers) |blocker| hashU64(&hasher, @intFromEnum(blocker));
            hashU64(&hasher, match.warnings.len);
            for (match.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
            return hasher.final();
        }

        fn fingerprintHint(hint: Hint) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.hint.v1");
            hashU64(&hasher, W.world_linker_hint_fingerprint_version);
            hashU64(&hasher, hint.parent_target_ref_fingerprint);
            hashU64(&hasher, hint.parent_world_port_id);
            hashOptionalU64(&hasher, hint.provider_target_ref_fingerprint);
            hashOptionalU64(&hasher, hint.provider_module_ref_fingerprint);
            hashOptionalU64(&hasher, hint.provider_export_fingerprint);
            hashU64(&hasher, @intFromEnum(hint.route_kind));
            hashOptionalU64(&hasher, if (hint.value_mapping) |mapping| mapping.mapping_fingerprint else null);
            hashBytes(&hasher, hint.label);
            hashBytes(&hasher, hint.metadata);
            return hasher.final();
        }

        fn fingerprintGraph(graph: Graph) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.graph.v1");
            hashU64(&hasher, W.world_linker_graph_fingerprint_version);
            hashU64(&hasher, graph.root_target_ref_fingerprint);
            hashU64(&hasher, graph.nodes.len);
            for (graph.nodes) |node| {
                hashU64(&hasher, @intFromEnum(node.kind));
                hashU64(&hasher, node.fingerprint);
                hashOptionalU64(&hasher, node.target_ref_fingerprint);
                hashOptionalU64(&hasher, node.import_requirement_fingerprint);
                hashBytes(&hasher, node.label);
            }
            hashU64(&hasher, graph.edges.len);
            for (graph.edges) |edge| {
                hashU64(&hasher, @intFromEnum(edge.kind));
                hashU64(&hasher, edge.from_fingerprint);
                hashU64(&hasher, edge.to_fingerprint);
                hashOptionalU64(&hasher, edge.route_fingerprint);
            }
            hashU64(&hasher, graph.blockers.len);
            for (graph.blockers) |blocker| hashU64(&hasher, @intFromEnum(blocker));
            hashU64(&hasher, graph.warnings.len);
            for (graph.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
            hashU64(&hasher, graph.max_depth_observed);
            hashU64(&hasher, graph.unresolved_required_count);
            hashU64(&hasher, graph.ambiguous_match_count);
            return hasher.final();
        }

        fn fingerprintRouteSynthesis(synthesis: RouteSynthesis) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.route.synthesis.v1");
            hashU64(&hasher, W.world_linker_route_synthesis_fingerprint_version);
            hashU64(&hasher, synthesis.parent_target_ref_fingerprint);
            hashU64(&hasher, synthesis.import_requirement_fingerprint);
            hashU64(&hasher, synthesis.match_fingerprint);
            hashU64(&hasher, synthesis.route_fingerprint);
            hashOptionalU64(&hasher, synthesis.value_mapping_fingerprint);
            return hasher.final();
        }

        fn fingerprintPlan(plan: Plan) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.plan.v1");
            hashU64(&hasher, plan.format_version);
            hashU64(&hasher, plan.fingerprint_version);
            hashU64(&hasher, plan.root_target_ref_fingerprint);
            hashOptionalU64(&hasher, plan.root_module_ref_fingerprint);
            hashU64(&hasher, plan.policy_fingerprint);
            hashU64(&hasher, plan.catalog_fingerprint);
            hashU64(&hasher, plan.graph_fingerprint);
            hashU64(&hasher, plan.fabric_plans.len);
            for (plan.fabric_plans) |fabric_plan| hashU64(&hasher, fabric_plan.plan_fingerprint);
            hashU64(&hasher, plan.route_syntheses.len);
            for (plan.route_syntheses) |synthesis| hashU64(&hasher, synthesis.synthesis_fingerprint);
            hashU64(&hasher, plan.unresolved_imports.len);
            for (plan.unresolved_imports) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashU64(&hasher, plan.external_environment_requirements.len);
            for (plan.external_environment_requirements) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashU64Slice(&hasher, plan.provider_targets_used);
            hashU64Slice(&hasher, plan.guest_providers_used);
            hashU64Slice(&hasher, plan.replay_routes_used);
            hashU64Slice(&hasher, plan.reject_routes_used);
            hashU64(&hasher, plan.blockers.len);
            for (plan.blockers) |blocker| hashU64(&hasher, @intFromEnum(blocker));
            hashU64(&hasher, plan.warnings.len);
            for (plan.warnings) |warning| hashU64(&hasher, @intFromEnum(warning));
            hashU64(&hasher, @intFromEnum(plan.normal_form));
            return hasher.final();
        }

        fn fingerprintResidualImportSet(set: ResidualImportSet) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.residual.import.set.v1");
            hashU64(&hasher, set.root_target_ref_fingerprint);
            hashU64(&hasher, set.requirements.len);
            for (set.requirements) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashU64(&hasher, set.required_count);
            return hasher.final();
        }

        fn fingerprintReport(report: Report) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.report.v1");
            hashU64(&hasher, W.world_linker_report_fingerprint_version);
            hashBool(&hasher, report.accepted);
            hashU64(&hasher, report.root_target_ref_fingerprint);
            hashU64(&hasher, report.candidate_count);
            hashU64(&hasher, report.import_count);
            hashU64(&hasher, report.resolved_import_count);
            hashU64(&hasher, report.external_import_count);
            hashU64(&hasher, report.unresolved_import_count);
            hashU64(&hasher, report.ambiguous_import_count);
            hashU64(&hasher, report.route_count);
            hashU64(&hasher, report.fabric_plan_count);
            hashU64(&hasher, report.cycle_blockers);
            hashU64(&hasher, report.value_mismatch_blockers);
            hashU64(&hasher, report.supervision_blockers);
            hashU64(&hasher, report.guest_conformance_blockers);
            hashBytes(&hasher, report.summary);
            return hasher.final();
        }

        fn fingerprintCertificate(cert: Certificate) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.linker.certificate.v1");
            hashU64(&hasher, cert.format_version);
            hashU64(&hasher, cert.fingerprint_version);
            hashU64(&hasher, cert.link_plan_fingerprint);
            hashU64(&hasher, cert.link_graph_fingerprint);
            hashU64(&hasher, cert.report_fingerprint);
            hashU64(&hasher, cert.root_target_ref_fingerprint);
            hashU64(&hasher, cert.catalog_fingerprint);
            hashU64Slice(&hasher, cert.fabric_plan_fingerprints);
            hashU64Slice(&hasher, cert.route_fingerprints);
            hashU64Slice(&hasher, cert.match_fingerprints);
            hashU64Slice(&hasher, cert.hint_fingerprints);
            hashU64(&hasher, cert.policy_fingerprint);
            hashU64(&hasher, cert.blocker_count);
            hashU64(&hasher, cert.warning_count);
            return hasher.final();
        }

        fn fingerprintAssembly(assembly: Assembly) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.assembly.v1");
            hashU64(&hasher, W.world_assembly_fingerprint_version);
            hashU64(&hasher, assembly.root_target_ref.target_ref_fingerprint);
            hashOptionalU64(&hasher, assembly.root_admitted_run_fingerprint);
            hashU64(&hasher, assembly.link_plan_fingerprint);
            hashU64(&hasher, assembly.linker_certificate_fingerprint);
            hashOptionalU64(&hasher, assembly.environment_certificate_fingerprint);
            hashOptionalU64(&hasher, assembly.run_permit_fingerprint);
            hashU64(&hasher, assembly.fabric_plans.len);
            for (assembly.fabric_plans) |fabric_plan| hashU64(&hasher, fabric_plan.plan_fingerprint);
            hashU64(&hasher, assembly.external_import_requirements.len);
            for (assembly.external_import_requirements) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
            hashU64Slice(&hasher, assembly.admission_receipts_used);
            hashU64Slice(&hasher, assembly.provider_run_templates);
            hashU64Slice(&hasher, assembly.guest_provider_templates);
            return hasher.final();
        }
    };
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hashU64(hasher, bytes.len);
    hasher.update(bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: anytype) void {
    const as_u64: u64 = switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => @intCast(value),
        .@"enum" => @intCast(@intFromEnum(value)),
        else => @compileError("hashU64 supports integer-like values only"),
    };
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, as_u64, .little);
    hasher.update(&bytes);
}

fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
    hashU64(hasher, @as(u8, if (value) 1 else 0));
}

fn hashOptionalU32(hasher: *std.hash.Wyhash, value: ?u32) void {
    if (value) |present| {
        hashU64(hasher, @as(u8, 1));
        hashU64(hasher, present);
    } else {
        hashU64(hasher, @as(u8, 0));
    }
}

fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
    if (value) |present| {
        hashU64(hasher, @as(u8, 1));
        hashU64(hasher, present);
    } else {
        hashU64(hasher, @as(u8, 0));
    }
}

fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
    hashU64(hasher, values.len);
    for (values) |value| hashU64(hasher, value);
}
