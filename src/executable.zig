const std = @import("std");
const boundary = @import("boundary");

const evidence_semantic = boundary.ir.builder.semantic;
const evidence_compiled = evidence_semantic.finish(.{
    .label = "world-executable-evidence",
    .ir_hash = 0x7778_6578_6563_0001,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{},
        .locals = .{evidence_semantic.local("result", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{evidence_semantic.constI32("result", 0)},
            .terminator = evidence_semantic.returnValue("result"),
        }},
    }},
}) catch |err| @compileError("invalid World Executable evidence program: " ++ @errorName(err));
const BoundaryEvidenceProgram = boundary.program("world-executable-evidence", struct {}, struct {
    pub const compiled_plan = evidence_compiled.plan;
});
const BoundaryEvidence = BoundaryEvidenceProgram.Evidence;

pub fn Executable(comptime W: type) type {
    const BoundaryModule = BoundaryEvidence.BoundaryTargetModule;

    return struct {
        pub const Boundary = struct {
            pub const ModuleImage = BoundaryModule;
            pub const LoadedModule = BoundaryModule.LoadedModule;
            pub const LoadedExecutionProfile = BoundaryModule.LoadedExecutionProfile;
            pub const LoadedExecution = BoundaryModule.LoadedExecution;
        };

        pub const Module = struct {
            module_id: u32,
            role: Role,
            module_ref: W.Admission.ModuleRef,
            target_ref: W.TargetRef,
            import_set: W.ImportSet,
            imports: []const W.ImportRequirement = &.{},
            export_summary: W.Admission.ExportSummary,
            executable_plan_fingerprint: u64,
            validation_report_fingerprint: u64,
            compatibility_report_fingerprint: u64,
            canonical_bytes: []const u8 = &.{},

            pub const Role = enum(u8) {
                root = 0,
                provider = 1,
            };

            pub fn validate(self: @This()) !void {
                if (self.module_ref.module_kind != .full_module) return error.InvalidFrameEncoding;
                try self.module_ref.validate();
                try self.target_ref.validate();
                if (self.target_ref.boundary_module_fingerprint == null or
                    self.target_ref.boundary_module_fingerprint.? != self.module_ref.boundary_module_fingerprint)
                {
                    return error.InvalidFrameEncoding;
                }
                if (self.import_set.target_ref_fingerprint != self.target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
                const import_counts = importRequirementCounts(self.imports);
                if (self.import_set.required_count != import_counts.required) return error.InvalidFrameEncoding;
                if (self.import_set.optional_count != import_counts.optional) return error.InvalidFrameEncoding;
                if (self.import_set.required_count + self.import_set.optional_count != self.imports.len) return error.InvalidFrameEncoding;
                if (self.executable_plan_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.validation_report_fingerprint == 0 or self.compatibility_report_fingerprint == 0) return error.InvalidFrameEncoding;
                if (self.canonical_bytes.len == 0) return error.InvalidFrameEncoding;
                for (self.imports) |requirement| {
                    if (requirement.requirement_fingerprint == 0) return error.InvalidFrameEncoding;
                    const canonical_requirement = W.ImportRequirement.init(.{
                        .target_ref_fingerprint = requirement.target_ref_fingerprint,
                        .world_value_table_fingerprint = requirement.world_value_table_fingerprint,
                        .world_surface_fingerprint = requirement.world_surface_fingerprint,
                        .world_port_id = requirement.world_port_id,
                        .world_port_ref_fingerprint = requirement.world_port_ref_fingerprint,
                        .source_effect_shape_ref_fingerprint = requirement.source_effect_shape_ref_fingerprint,
                        .residual_site_index = requirement.residual_site_index,
                        .residual_site_fingerprint = requirement.residual_site_fingerprint,
                        .payload_value_table_id = requirement.payload_value_table_id,
                        .payload_value_ref_fingerprint = requirement.payload_value_ref_fingerprint,
                        .response_value_table_id = requirement.response_value_table_id,
                        .response_value_ref_fingerprint = requirement.response_value_ref_fingerprint,
                        .mode = requirement.mode,
                        .allowed_response_kinds = requirement.allowed_response_kinds,
                        .replay_key_recipe_fingerprint = requirement.replay_key_recipe_fingerprint,
                        .suggested_symbolic_name = requirement.suggested_symbolic_name,
                        .required = requirement.required,
                        .tags = requirement.tags,
                        .metadata = requirement.metadata,
                    });
                    if (requirement.requirement_fingerprint != canonical_requirement.requirement_fingerprint) return error.InvalidFrameEncoding;
                    if (requirement.target_ref_fingerprint == null or requirement.target_ref_fingerprint.? != self.target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
                    if (requirement.world_surface_fingerprint != self.target_ref.world_surface_fingerprint) return error.InvalidFrameEncoding;
                }
            }

            pub fn validateForRuntimeProfile(self: @This(), profile: RuntimeProfile) !void {
                try self.validate();
                try validateModuleCanonicalBytes(std.heap.page_allocator, self, profile);
            }
        };

        pub const ModuleSet = struct {
            modules: []const Module = &.{},
            root_module_id: u32 = 0,
            module_set_fingerprint: u64 = 0,

            pub fn init(modules: []const Module, root_module_id: u32) @This() {
                var result = @This(){
                    .modules = modules,
                    .root_module_id = root_module_id,
                    .module_set_fingerprint = 0,
                };
                result.module_set_fingerprint = fingerprintModuleSet(result);
                return result;
            }

            pub fn root(self: @This()) ?Module {
                for (self.modules) |module| {
                    if (module.module_id == self.root_module_id and module.role == .root) return module;
                }
                return null;
            }

            pub fn validate(self: @This()) !void {
                if (self.module_set_fingerprint != fingerprintModuleSet(self)) return error.InvalidFrameEncoding;
                var root_count: usize = 0;
                for (self.modules, 0..) |module, index| {
                    try module.validate();
                    if (module.role == .root) root_count += 1;
                    for (self.modules[index + 1 ..]) |other| {
                        if (module.module_id == other.module_id) return error.InvalidFrameEncoding;
                        if (module.module_ref.boundary_module_fingerprint == other.module_ref.boundary_module_fingerprint and
                            !std.mem.eql(u8, module.canonical_bytes, other.canonical_bytes))
                        {
                            return error.InvalidFrameEncoding;
                        }
                    }
                }
                if (root_count != 1 or self.root() == null) return error.InvalidFrameEncoding;
            }
        };

        pub const RuntimeProfile = struct {
            profile_fingerprint: u64 = 0,
            supports_loaded_execution: bool = true,
            supports_internal_providers: bool = true,
            supports_external_actuation: bool = true,
            max_modules: usize = 64,
            max_provider_depth: usize = 8,
            max_external_bindings: usize = 1024,
            max_module_bytes: usize = 16 * 1024 * 1024,
            max_image_bytes: usize = 64 * 1024 * 1024,
            max_command_bytes: usize = 1024 * 1024,
            max_output_bytes: usize = 1024 * 1024,
            max_linear_memory_pages: usize = 65,
            metadata: []const u8 = "",

            pub const universal_v1 = init(.{});

            pub fn init(args: struct {
                supports_loaded_execution: bool = true,
                supports_internal_providers: bool = true,
                supports_external_actuation: bool = true,
                max_modules: usize = 64,
                max_provider_depth: usize = 8,
                max_external_bindings: usize = 1024,
                max_module_bytes: usize = 16 * 1024 * 1024,
                max_image_bytes: usize = 64 * 1024 * 1024,
                max_command_bytes: usize = 1024 * 1024,
                max_output_bytes: usize = 1024 * 1024,
                max_linear_memory_pages: usize = 65,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .profile_fingerprint = 0,
                    .supports_loaded_execution = args.supports_loaded_execution,
                    .supports_internal_providers = args.supports_internal_providers,
                    .supports_external_actuation = args.supports_external_actuation,
                    .max_modules = args.max_modules,
                    .max_provider_depth = args.max_provider_depth,
                    .max_external_bindings = args.max_external_bindings,
                    .max_module_bytes = args.max_module_bytes,
                    .max_image_bytes = args.max_image_bytes,
                    .max_command_bytes = args.max_command_bytes,
                    .max_output_bytes = args.max_output_bytes,
                    .max_linear_memory_pages = args.max_linear_memory_pages,
                    .metadata = args.metadata,
                };
                result.profile_fingerprint = fingerprintRuntimeProfile(result);
                return result;
            }

            pub fn supports(self: @This(), required: @This()) bool {
                return (!required.supports_loaded_execution or self.supports_loaded_execution) and
                    (!required.supports_internal_providers or self.supports_internal_providers) and
                    (!required.supports_external_actuation or self.supports_external_actuation) and
                    self.max_modules >= required.max_modules and
                    (!required.supports_internal_providers or self.max_provider_depth >= required.max_provider_depth) and
                    (!required.supports_external_actuation or self.max_external_bindings >= required.max_external_bindings) and
                    self.max_module_bytes >= required.max_module_bytes and
                    self.max_image_bytes >= required.max_image_bytes and
                    self.max_command_bytes >= required.max_command_bytes and
                    self.max_output_bytes >= required.max_output_bytes and
                    self.max_linear_memory_pages >= required.max_linear_memory_pages;
            }

            pub fn validate(self: @This()) !void {
                if (self.profile_fingerprint == 0 or self.profile_fingerprint != fingerprintRuntimeProfile(self)) return error.InvalidFrameEncoding;
                if (self.max_modules == 0 or self.max_external_bindings == 0 or self.max_module_bytes == 0) return error.InvalidFrameEncoding;
                if (self.max_image_bytes == 0 or self.max_command_bytes == 0 or self.max_output_bytes == 0) return error.InvalidFrameEncoding;
                if (self.max_linear_memory_pages == 0) return error.InvalidFrameEncoding;
            }
        };

        pub const ExternalBinding = struct {
            binding_fingerprint: u64,
            parent_module_fingerprint: u64,
            world_port_id: u32,
            world_port_ref_fingerprint: ?u64 = null,
            payload_value_table_id: ?u32 = null,
            payload_value_ref_fingerprint: ?u64 = null,
            response_value_table_id: ?u32 = null,
            response_value_ref_fingerprint: ?u64 = null,
            actuator_ref: W.Actuation.Ref,
            descriptor: W.Actuation.Descriptor,
            allowed_response_statuses: W.Actuation.ResponseStatusSet = .terminal_with_errors,
            actuation_class: W.Actuation.Class,
            value_policy: W.ValuePolicy = .portable,
            supervision_rule_ref: ?u64 = null,
            authority_descriptor_ref: ?u64 = null,
            label: []const u8 = "",
            metadata: []const u8 = "",

            pub fn init(args: struct {
                parent_module_fingerprint: u64,
                world_port_id: u32,
                world_port_ref_fingerprint: ?u64 = null,
                payload_value_table_id: ?u32 = null,
                payload_value_ref_fingerprint: ?u64 = null,
                response_value_table_id: ?u32 = null,
                response_value_ref_fingerprint: ?u64 = null,
                actuator_ref: W.Actuation.Ref,
                descriptor: W.Actuation.Descriptor,
                allowed_response_statuses: W.Actuation.ResponseStatusSet = .terminal_with_errors,
                value_policy: W.ValuePolicy = .portable,
                supervision_rule_ref: ?u64 = null,
                authority_descriptor_ref: ?u64 = null,
                label: []const u8 = "",
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .binding_fingerprint = 0,
                    .parent_module_fingerprint = args.parent_module_fingerprint,
                    .world_port_id = args.world_port_id,
                    .world_port_ref_fingerprint = args.world_port_ref_fingerprint,
                    .payload_value_table_id = args.payload_value_table_id,
                    .payload_value_ref_fingerprint = args.payload_value_ref_fingerprint,
                    .response_value_table_id = args.response_value_table_id,
                    .response_value_ref_fingerprint = args.response_value_ref_fingerprint,
                    .actuator_ref = args.actuator_ref,
                    .descriptor = args.descriptor,
                    .allowed_response_statuses = args.allowed_response_statuses,
                    .actuation_class = args.actuator_ref.class,
                    .value_policy = args.value_policy,
                    .supervision_rule_ref = args.supervision_rule_ref,
                    .authority_descriptor_ref = args.authority_descriptor_ref,
                    .label = args.label,
                    .metadata = args.metadata,
                };
                result.binding_fingerprint = fingerprintExternalBinding(result);
                return result;
            }

            pub fn validate(self: @This()) !void {
                if (self.binding_fingerprint != fingerprintExternalBinding(self)) return error.InvalidFrameEncoding;
                if (self.parent_module_fingerprint == 0) return error.InvalidFrameEncoding;
                try self.actuator_ref.validate();
                try self.descriptor.validate();
                if (self.descriptor.actuator_ref_fingerprint != self.actuator_ref.ref_fingerprint) return error.InvalidFrameEncoding;
                if (self.actuation_class != self.actuator_ref.class or self.actuation_class != self.descriptor.class) return error.InvalidFrameEncoding;
                if (!responseStatusSetSubset(self.allowed_response_statuses, self.actuator_ref.supported_response_statuses)) return error.InvalidFrameEncoding;
                if (!responseStatusSetSubset(self.allowed_response_statuses, self.descriptor.allowed_response_kinds)) return error.InvalidFrameEncoding;
                if (self.descriptor.world_port_id != null and self.descriptor.world_port_id.? != self.world_port_id) return error.InvalidFrameEncoding;
                if (self.descriptor.world_port_ref_fingerprint != null and self.world_port_ref_fingerprint != null and
                    self.descriptor.world_port_ref_fingerprint.? != self.world_port_ref_fingerprint.?)
                {
                    return error.InvalidFrameEncoding;
                }
                if (self.supervision_rule_ref != null and self.supervision_rule_ref.? == 0) return error.InvalidFrameEncoding;
                if (self.authority_descriptor_ref != null and self.authority_descriptor_ref.? == 0) return error.InvalidFrameEncoding;
            }

            pub fn matchesRequirement(self: @This(), module: Module, requirement: W.ImportRequirement) bool {
                if (self.parent_module_fingerprint != module.module_ref.boundary_module_fingerprint) return false;
                if (self.world_port_id != requirement.world_port_id) return false;
                if (self.descriptor.world_surface_fingerprint != module.target_ref.world_surface_fingerprint) return false;
                if (self.descriptor.target_ref_fingerprint) |target_ref_fingerprint| {
                    if (target_ref_fingerprint != module.target_ref.target_ref_fingerprint) return false;
                }
                if (requirement.allowed_response_kinds == .return_now_only) return false;
                if (!bindingRefSatisfiesRequirement(self.descriptor.source_effect_shape_ref_fingerprint, requirement.source_effect_shape_ref_fingerprint)) return false;
                if (!descriptorSupportsRequirementMode(self.descriptor.supported_modes, requirement.mode)) return false;
                if (!optionalU32Matches(self.descriptor.payload_value_table_id, requirement.payload_value_table_id)) return false;
                if (!optionalU32Matches(self.descriptor.response_value_table_id, requirement.response_value_table_id)) return false;
                if (!bindingRefSatisfiesRequirement(self.world_port_ref_fingerprint, requirement.world_port_ref_fingerprint)) return false;
                if (!optionalU32Matches(self.payload_value_table_id, requirement.payload_value_table_id)) return false;
                if (!bindingRefSatisfiesRequirement(self.payload_value_ref_fingerprint, requirement.payload_value_ref_fingerprint)) return false;
                if (!optionalU32Matches(self.response_value_table_id, requirement.response_value_table_id)) return false;
                if (!bindingRefSatisfiesRequirement(self.response_value_ref_fingerprint, requirement.response_value_ref_fingerprint)) return false;
                return true;
            }
        };

        pub const DispatchImage = struct {
            format_version: u32 = W.world_executable_dispatch_image_format_version,
            fingerprint_version: u32 = W.world_executable_dispatch_image_fingerprint_version,
            dispatch_fingerprint: u64,
            root_module_id: u32,
            module_fingerprints: []const u64 = &.{},
            external_binding_fingerprints: []const u64 = &.{},
            residual_request_order: []const u64 = &.{},
            fabric_plan_fingerprints: []const u64 = &.{},
            route_ids: []const u64 = &.{},
            route_kinds: []const W.Fabric.RouteKind = &.{},
            route_parent_world_port_ids: []const u32 = &.{},
            route_requirement_fingerprints: []const u64 = &.{},
            route_provider_module_fingerprints: []const u64 = &.{},
            linker_policy: W.Linker.Policy = .allow_external_ports,
            link_plan_fingerprint: u64 = 0,
            linker_certificate_fingerprint: u64 = 0,
            assembly_fingerprint: u64 = 0,

            pub fn init(args: struct {
                root_module_id: u32,
                module_fingerprints: []const u64 = &.{},
                external_binding_fingerprints: []const u64 = &.{},
                residual_request_order: []const u64 = &.{},
                fabric_plan_fingerprints: []const u64 = &.{},
                route_ids: []const u64 = &.{},
                route_kinds: []const W.Fabric.RouteKind = &.{},
                route_parent_world_port_ids: []const u32 = &.{},
                route_requirement_fingerprints: []const u64 = &.{},
                route_provider_module_fingerprints: []const u64 = &.{},
                linker_policy: W.Linker.Policy = .allow_external_ports,
                link_plan_fingerprint: u64 = 0,
                linker_certificate_fingerprint: u64 = 0,
                assembly_fingerprint: u64 = 0,
            }) @This() {
                var result = @This(){
                    .dispatch_fingerprint = 0,
                    .root_module_id = args.root_module_id,
                    .module_fingerprints = args.module_fingerprints,
                    .external_binding_fingerprints = args.external_binding_fingerprints,
                    .residual_request_order = args.residual_request_order,
                    .fabric_plan_fingerprints = args.fabric_plan_fingerprints,
                    .route_ids = args.route_ids,
                    .route_kinds = args.route_kinds,
                    .route_parent_world_port_ids = args.route_parent_world_port_ids,
                    .route_requirement_fingerprints = args.route_requirement_fingerprints,
                    .route_provider_module_fingerprints = args.route_provider_module_fingerprints,
                    .linker_policy = args.linker_policy,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .linker_certificate_fingerprint = args.linker_certificate_fingerprint,
                    .assembly_fingerprint = args.assembly_fingerprint,
                };
                result.dispatch_fingerprint = fingerprintDispatchImage(result);
                return result;
            }
        };

        pub const MemoryPlan = struct {
            memory_plan_fingerprint: u64,
            decoded_module_bytes: usize = 0,
            dispatch_table_entries: usize = 0,
            schema_table_entries: usize = 0,
            max_session_frames: usize = 64,
            max_runspace_slots: usize = 64,
            max_mailbox_entries: usize = 1024,
            max_provider_runs: usize = 32,
            max_host_requests_per_turn: usize = 1024,
            max_command_bytes: usize = 1024 * 1024,
            max_output_bytes: usize = 1024 * 1024,
            max_capsule_bytes: usize = 4 * 1024 * 1024,
            max_archive_append_bytes: usize = 4 * 1024 * 1024,
            max_linear_memory_pages: usize = 65,

            pub fn derive(profile: RuntimeProfile, modules: []const Module, residual_count: usize) @This() {
                return deriveForDispatch(profile, modules, residual_count, 0);
            }

            pub fn deriveForDispatch(profile: RuntimeProfile, modules: []const Module, residual_count: usize, route_count: usize) @This() {
                var module_bytes: usize = 0;
                var schema_entries: usize = 0;
                for (modules) |module| {
                    module_bytes = module_bytes +| module.canonical_bytes.len;
                    schema_entries = schema_entries +| module.import_set.value_table_entry_count;
                }
                var result = @This(){
                    .memory_plan_fingerprint = 0,
                    .decoded_module_bytes = module_bytes,
                    .dispatch_table_entries = modules.len +| residual_count +| route_count,
                    .schema_table_entries = schema_entries,
                    .max_provider_runs = @min(profile.max_modules, profile.max_external_bindings),
                    .max_host_requests_per_turn = @min(profile.max_external_bindings, residual_count),
                    .max_command_bytes = profile.max_command_bytes,
                    .max_output_bytes = profile.max_output_bytes,
                    .max_linear_memory_pages = profile.max_linear_memory_pages,
                };
                result.memory_plan_fingerprint = fingerprintMemoryPlan(result);
                return result;
            }
        };

        pub const CompatibilityReport = struct {
            report_fingerprint: u64,
            compatible: bool,
            image_format_compatible: bool = true,
            boundary_module_compatible: bool = true,
            executable_plan_compatible: bool = true,
            instruction_feature_compatible: bool = true,
            value_codec_compatible: bool = true,
            profile_compatible: bool = true,
            capacity_compatible: bool = true,
            memory_compatible: bool = true,
            missing_optional_features: usize = 0,
            hard_blockers: usize = 0,
            warnings: usize = 0,
            summary: []const u8 = "",

            pub fn init(args: struct {
                compatible: bool,
                boundary_module_compatible: bool = true,
                executable_plan_compatible: bool = true,
                profile_compatible: bool = true,
                capacity_compatible: bool = true,
                memory_compatible: bool = true,
                hard_blockers: usize = 0,
                warnings: usize = 0,
                summary: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .report_fingerprint = 0,
                    .compatible = args.compatible,
                    .boundary_module_compatible = args.boundary_module_compatible,
                    .executable_plan_compatible = args.executable_plan_compatible,
                    .profile_compatible = args.profile_compatible,
                    .capacity_compatible = args.capacity_compatible,
                    .memory_compatible = args.memory_compatible,
                    .hard_blockers = args.hard_blockers,
                    .warnings = args.warnings,
                    .summary = args.summary,
                };
                result.report_fingerprint = fingerprintCompatibilityReport(result);
                return result;
            }

            pub fn validate(self: @This()) !void {
                if (self.report_fingerprint == 0 or self.report_fingerprint != fingerprintCompatibilityReport(self)) return error.InvalidFrameEncoding;
                const all_compatible = self.image_format_compatible and
                    self.boundary_module_compatible and
                    self.executable_plan_compatible and
                    self.instruction_feature_compatible and
                    self.value_codec_compatible and
                    self.profile_compatible and
                    self.capacity_compatible and
                    self.memory_compatible;
                if (self.compatible != (all_compatible and self.hard_blockers == 0)) return error.InvalidFrameEncoding;
                if (!self.compatible and self.hard_blockers == 0) return error.InvalidFrameEncoding;
            }
        };

        pub const Certificate = struct {
            format_version: u32 = W.world_executable_certificate_format_version,
            fingerprint_version: u32 = W.world_executable_certificate_fingerprint_version,
            certificate_fingerprint: u64,
            image_fingerprint: u64,
            module_set_fingerprint: u64,
            runtime_profile_fingerprint: u64,
            dispatch_fingerprint: u64,
            memory_plan_fingerprint: u64,
            compatibility_report_fingerprint: u64,
            link_plan_fingerprint: u64 = 0,
            linker_certificate_fingerprint: u64 = 0,
            assembly_fingerprint: u64 = 0,
            module_count: usize = 0,
            residual_external_binding_count: usize = 0,
            blocker_count: usize = 0,
            warning_count: usize = 0,

            pub fn init(args: struct {
                image_fingerprint: u64,
                module_set_fingerprint: u64,
                runtime_profile_fingerprint: u64,
                dispatch_fingerprint: u64,
                memory_plan_fingerprint: u64,
                compatibility_report_fingerprint: u64,
                link_plan_fingerprint: u64 = 0,
                linker_certificate_fingerprint: u64 = 0,
                assembly_fingerprint: u64 = 0,
                module_count: usize = 0,
                residual_external_binding_count: usize = 0,
                blocker_count: usize = 0,
                warning_count: usize = 0,
            }) @This() {
                var result = @This(){
                    .certificate_fingerprint = 0,
                    .image_fingerprint = args.image_fingerprint,
                    .module_set_fingerprint = args.module_set_fingerprint,
                    .runtime_profile_fingerprint = args.runtime_profile_fingerprint,
                    .dispatch_fingerprint = args.dispatch_fingerprint,
                    .memory_plan_fingerprint = args.memory_plan_fingerprint,
                    .compatibility_report_fingerprint = args.compatibility_report_fingerprint,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .linker_certificate_fingerprint = args.linker_certificate_fingerprint,
                    .assembly_fingerprint = args.assembly_fingerprint,
                    .module_count = args.module_count,
                    .residual_external_binding_count = args.residual_external_binding_count,
                    .blocker_count = args.blocker_count,
                    .warning_count = args.warning_count,
                };
                result.certificate_fingerprint = fingerprintCertificate(result);
                return result;
            }
        };

        pub const Plan = struct {
            plan_fingerprint: u64,
            module_set: ModuleSet,
            runtime_profile: RuntimeProfile,
            link_plan: W.Linker.Plan,
            linker_certificate: W.Linker.Certificate,
            assembly: W.Assembly,
            dispatch_image: DispatchImage,
            memory_plan: MemoryPlan,
            external_bindings: []const ExternalBinding = &.{},
            compatibility_report: CompatibilityReport,
            metadata: []const u8 = "",

            pub fn init(args: struct {
                module_set: ModuleSet,
                runtime_profile: RuntimeProfile,
                link_plan: W.Linker.Plan,
                linker_certificate: W.Linker.Certificate,
                assembly: W.Assembly,
                dispatch_image: DispatchImage,
                memory_plan: MemoryPlan,
                external_bindings: []const ExternalBinding = &.{},
                compatibility_report: CompatibilityReport,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .plan_fingerprint = 0,
                    .module_set = args.module_set,
                    .runtime_profile = args.runtime_profile,
                    .link_plan = args.link_plan,
                    .linker_certificate = args.linker_certificate,
                    .assembly = args.assembly,
                    .dispatch_image = args.dispatch_image,
                    .memory_plan = args.memory_plan,
                    .external_bindings = args.external_bindings,
                    .compatibility_report = args.compatibility_report,
                    .metadata = args.metadata,
                };
                result.plan_fingerprint = fingerprintPlan(result);
                return result;
            }

            pub fn seal(self: @This(), allocator: std.mem.Allocator) !Image {
                if (!self.compatibility_report.compatible) return error.ExecutableSealingBlocked;
                try self.module_set.validate();
                if (self.dispatch_image.dispatch_fingerprint != fingerprintDispatchImage(self.dispatch_image)) return error.InvalidFrameEncoding;
                const modules = try cloneModuleSlice(allocator, self.module_set.modules);
                errdefer freeModuleSlice(allocator, modules);
                const bindings = try cloneExternalBindingSlice(allocator, self.external_bindings);
                errdefer freeExternalBindingSlice(allocator, bindings);
                const dispatch_image = try cloneDispatchImage(allocator, self.dispatch_image);
                errdefer freeDispatchImage(allocator, dispatch_image);
                var runtime_profile = self.runtime_profile;
                runtime_profile.metadata = try allocator.dupe(u8, self.runtime_profile.metadata);
                errdefer allocator.free(runtime_profile.metadata);
                var compatibility_report = self.compatibility_report;
                compatibility_report.summary = try allocator.dupe(u8, self.compatibility_report.summary);
                errdefer allocator.free(compatibility_report.summary);
                const image_metadata = try allocator.dupe(u8, self.metadata);
                errdefer allocator.free(image_metadata);
                var image = Image.init(.{
                    .required_runtime_profile = runtime_profile,
                    .module_set = ModuleSet.init(modules, self.module_set.root_module_id),
                    .link_plan_fingerprint = self.link_plan.plan_fingerprint,
                    .linker_certificate_fingerprint = self.linker_certificate.certificate_fingerprint,
                    .assembly_fingerprint = self.assembly.assembly_fingerprint,
                    .dispatch_image = dispatch_image,
                    .external_bindings = bindings,
                    .memory_plan = self.memory_plan,
                    .compatibility_report = compatibility_report,
                    .metadata = image_metadata,
                });
                try validateImageFitsRuntimeProfile(image);
                const cert = Certificate.init(.{
                    .image_fingerprint = image.image_fingerprint,
                    .module_set_fingerprint = image.module_set.module_set_fingerprint,
                    .runtime_profile_fingerprint = image.required_runtime_profile.profile_fingerprint,
                    .dispatch_fingerprint = image.dispatch_image.dispatch_fingerprint,
                    .memory_plan_fingerprint = image.memory_plan.memory_plan_fingerprint,
                    .compatibility_report_fingerprint = image.compatibility_report.report_fingerprint,
                    .link_plan_fingerprint = image.link_plan_fingerprint,
                    .linker_certificate_fingerprint = image.linker_certificate_fingerprint,
                    .assembly_fingerprint = image.assembly_fingerprint,
                    .module_count = image.module_set.modules.len,
                    .residual_external_binding_count = image.external_bindings.len,
                    .blocker_count = image.compatibility_report.hard_blockers,
                    .warning_count = image.compatibility_report.warnings,
                });
                image.certificate = cert;
                image.owns_memory = true;
                image.image_fingerprint = fingerprintImage(image);
                image.certificate = Certificate.init(.{
                    .image_fingerprint = image.image_fingerprint,
                    .module_set_fingerprint = image.module_set.module_set_fingerprint,
                    .runtime_profile_fingerprint = image.required_runtime_profile.profile_fingerprint,
                    .dispatch_fingerprint = image.dispatch_image.dispatch_fingerprint,
                    .memory_plan_fingerprint = image.memory_plan.memory_plan_fingerprint,
                    .compatibility_report_fingerprint = image.compatibility_report.report_fingerprint,
                    .link_plan_fingerprint = image.link_plan_fingerprint,
                    .linker_certificate_fingerprint = image.linker_certificate_fingerprint,
                    .assembly_fingerprint = image.assembly_fingerprint,
                    .module_count = image.module_set.modules.len,
                    .residual_external_binding_count = image.external_bindings.len,
                    .blocker_count = image.compatibility_report.hard_blockers,
                    .warning_count = image.compatibility_report.warnings,
                });
                return image;
            }
        };

        pub const Image = struct {
            format_version: u32 = W.world_executable_image_format_version,
            fingerprint_version: u32 = W.world_executable_image_fingerprint_version,
            image_fingerprint: u64,
            required_runtime_profile: RuntimeProfile,
            module_set: ModuleSet,
            link_plan_fingerprint: u64,
            linker_certificate_fingerprint: u64,
            assembly_fingerprint: u64,
            dispatch_image: DispatchImage,
            external_bindings: []const ExternalBinding = &.{},
            memory_plan: MemoryPlan,
            compatibility_report: CompatibilityReport,
            certificate: Certificate = undefined,
            metadata: []const u8 = "",
            owns_memory: bool = false,

            pub const DecodeLimits = struct {
                max_image_bytes: usize = RuntimeProfile.universal_v1.max_image_bytes,
                max_modules: usize = RuntimeProfile.universal_v1.max_modules,
                max_imports_per_module: usize = 4096,
                max_external_bindings: usize = RuntimeProfile.universal_v1.max_external_bindings,
                max_dispatch_entries: usize = 8192,
                max_metadata_bytes: usize = 1024 * 1024,
                max_module_bytes: usize = RuntimeProfile.universal_v1.max_module_bytes,
            };
            pub const ValidateOptions = struct {
                require_certificate: bool = true,
            };

            pub fn init(args: struct {
                required_runtime_profile: RuntimeProfile,
                module_set: ModuleSet,
                link_plan_fingerprint: u64,
                linker_certificate_fingerprint: u64,
                assembly_fingerprint: u64,
                dispatch_image: DispatchImage,
                external_bindings: []const ExternalBinding = &.{},
                memory_plan: MemoryPlan,
                compatibility_report: CompatibilityReport,
                metadata: []const u8 = "",
            }) @This() {
                var result = @This(){
                    .image_fingerprint = 0,
                    .required_runtime_profile = args.required_runtime_profile,
                    .module_set = args.module_set,
                    .link_plan_fingerprint = args.link_plan_fingerprint,
                    .linker_certificate_fingerprint = args.linker_certificate_fingerprint,
                    .assembly_fingerprint = args.assembly_fingerprint,
                    .dispatch_image = args.dispatch_image,
                    .external_bindings = args.external_bindings,
                    .memory_plan = args.memory_plan,
                    .compatibility_report = args.compatibility_report,
                    .metadata = args.metadata,
                };
                result.image_fingerprint = fingerprintImage(result);
                result.certificate = Certificate.init(.{
                    .image_fingerprint = result.image_fingerprint,
                    .module_set_fingerprint = result.module_set.module_set_fingerprint,
                    .runtime_profile_fingerprint = result.required_runtime_profile.profile_fingerprint,
                    .dispatch_fingerprint = result.dispatch_image.dispatch_fingerprint,
                    .memory_plan_fingerprint = result.memory_plan.memory_plan_fingerprint,
                    .compatibility_report_fingerprint = result.compatibility_report.report_fingerprint,
                    .link_plan_fingerprint = result.link_plan_fingerprint,
                    .linker_certificate_fingerprint = result.linker_certificate_fingerprint,
                    .assembly_fingerprint = result.assembly_fingerprint,
                    .module_count = result.module_set.modules.len,
                    .residual_external_binding_count = result.external_bindings.len,
                    .blocker_count = result.compatibility_report.hard_blockers,
                    .warning_count = result.compatibility_report.warnings,
                });
                return result;
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.owns_memory) {
                    freeModuleSlice(allocator, @constCast(self.module_set.modules.ptr)[0..self.module_set.modules.len]);
                    freeDispatchImage(allocator, self.dispatch_image);
                    freeExternalBindingSlice(allocator, self.external_bindings);
                    allocator.free(self.required_runtime_profile.metadata);
                    allocator.free(self.compatibility_report.summary);
                    allocator.free(self.metadata);
                }
                self.* = undefined;
            }

            pub fn encodedLen(self: @This()) usize {
                return imageEncodedLen(self) catch std.math.maxInt(usize);
            }

            pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                return encodeExecutableImage(allocator, self);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, limits: DecodeLimits) !@This() {
                return decodeExecutableImage(allocator, bytes, limits);
            }

            pub fn validationReport(bytes: []const u8, supported_profile: RuntimeProfile, limits: DecodeLimits) !CompatibilityReport {
                var image = try Image.decode(std.heap.page_allocator, bytes, limits);
                defer image.deinit(std.heap.page_allocator);
                return image.validate(supported_profile);
            }

            pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
                const bytes = try self.encode(allocator);
                defer allocator.free(bytes);
                return Image.decode(allocator, bytes, .{
                    .max_image_bytes = bytes.len,
                    .max_modules = @max(self.module_set.modules.len, RuntimeProfile.universal_v1.max_modules),
                    .max_external_bindings = @max(self.external_bindings.len, RuntimeProfile.universal_v1.max_external_bindings),
                    .max_dispatch_entries = @max(dispatchEntryCount(self.dispatch_image), 8192),
                    .max_module_bytes = @max(maxCanonicalModuleBytes(self.module_set.modules), RuntimeProfile.universal_v1.max_module_bytes),
                });
            }

            pub fn validate(self: @This(), supported_profile: RuntimeProfile) !CompatibilityReport {
                return self.validateWithOptions(supported_profile, .{});
            }

            pub fn validateWithAllocator(self: @This(), allocator: std.mem.Allocator, supported_profile: RuntimeProfile) !CompatibilityReport {
                return self.validateWithOptionsWithAllocator(allocator, supported_profile, .{});
            }

            pub fn ownedByteFootprint(self: @This()) usize {
                return imageOwnedByteFootprint(.{
                    .required_runtime_profile = self.required_runtime_profile,
                    .modules = self.module_set.modules,
                    .dispatch_image = self.dispatch_image,
                    .external_bindings = self.external_bindings,
                    .compatibility_report_summary = self.compatibility_report.summary,
                    .image_metadata = self.metadata,
                });
            }

            pub fn validateWithOptions(self: @This(), supported_profile: RuntimeProfile, options: ValidateOptions) !CompatibilityReport {
                return self.validateWithOptionsWithAllocator(std.heap.page_allocator, supported_profile, options);
            }

            fn validateWithOptionsWithAllocator(self: @This(), allocator: std.mem.Allocator, supported_profile: RuntimeProfile, options: ValidateOptions) !CompatibilityReport {
                if (self.format_version != W.world_executable_image_format_version) return error.InvalidFrameEncoding;
                if (self.fingerprint_version != W.world_executable_image_fingerprint_version) return error.InvalidFrameEncoding;
                try supported_profile.validate();
                try self.required_runtime_profile.validate();
                if (!self.required_runtime_profile.supports_loaded_execution) return error.InvalidFrameEncoding;
                try self.module_set.validate();
                for (self.module_set.modules) |module| {
                    try module.validate();
                    try validateModuleCanonicalBytes(allocator, module, self.required_runtime_profile);
                }
                if (self.dispatch_image.format_version != W.world_executable_dispatch_image_format_version) return error.InvalidFrameEncoding;
                if (self.dispatch_image.fingerprint_version != W.world_executable_dispatch_image_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.dispatch_image.dispatch_fingerprint != fingerprintDispatchImage(self.dispatch_image)) return error.InvalidFrameEncoding;
                if (self.dispatch_image.link_plan_fingerprint != self.link_plan_fingerprint or
                    self.dispatch_image.linker_certificate_fingerprint != self.linker_certificate_fingerprint or
                    self.dispatch_image.assembly_fingerprint != self.assembly_fingerprint)
                {
                    return error.InvalidFrameEncoding;
                }
                try validateDispatchTablesForImage(allocator, self);
                if (self.memory_plan.memory_plan_fingerprint != fingerprintMemoryPlan(self.memory_plan)) return error.InvalidFrameEncoding;
                const expected_memory_plan = MemoryPlan.deriveForDispatch(
                    self.required_runtime_profile,
                    self.module_set.modules,
                    self.external_bindings.len,
                    self.dispatch_image.route_ids.len,
                );
                if (self.memory_plan.memory_plan_fingerprint != expected_memory_plan.memory_plan_fingerprint) return error.InvalidFrameEncoding;
                try self.compatibility_report.validate();
                if (self.image_fingerprint != fingerprintImage(self)) return error.InvalidFrameEncoding;
                if (options.require_certificate) {
                    if (self.certificate.format_version != W.world_executable_certificate_format_version) return error.InvalidFrameEncoding;
                    if (self.certificate.fingerprint_version != W.world_executable_certificate_fingerprint_version) return error.InvalidFrameEncoding;
                    if (self.certificate.image_fingerprint != self.image_fingerprint or
                        self.certificate.certificate_fingerprint != fingerprintCertificate(self.certificate))
                    {
                        return error.InvalidFrameEncoding;
                    }
                    if (self.certificate.module_set_fingerprint != self.module_set.module_set_fingerprint or
                        self.certificate.runtime_profile_fingerprint != self.required_runtime_profile.profile_fingerprint or
                        self.certificate.dispatch_fingerprint != self.dispatch_image.dispatch_fingerprint or
                        self.certificate.memory_plan_fingerprint != self.memory_plan.memory_plan_fingerprint or
                        self.certificate.compatibility_report_fingerprint != self.compatibility_report.report_fingerprint or
                        self.certificate.link_plan_fingerprint != self.link_plan_fingerprint or
                        self.certificate.linker_certificate_fingerprint != self.linker_certificate_fingerprint or
                        self.certificate.assembly_fingerprint != self.assembly_fingerprint or
                        self.certificate.module_count != self.module_set.modules.len or
                        self.certificate.residual_external_binding_count != self.external_bindings.len or
                        self.certificate.blocker_count != self.compatibility_report.hard_blockers or
                        self.certificate.warning_count != self.compatibility_report.warnings)
                    {
                        return error.InvalidFrameEncoding;
                    }
                }
                try validateImageFitsRuntimeProfile(self);
                try validateExternalBindingsForImage(self);
                if (!supported_profile.supports(self.required_runtime_profile)) return CompatibilityReport.init(.{
                    .compatible = false,
                    .profile_compatible = false,
                    .hard_blockers = 1,
                    .summary = "runtime profile unsupported",
                });
                return self.compatibility_report;
            }
        };

        pub const LoadReport = struct {
            report_fingerprint: u64,
            image_fingerprint: u64,
            accepted: bool,
            runtime_profile_fingerprint: u64,
            executable_manifest_available: bool = false,
            hard_blockers: usize = 0,
            warnings: usize = 0,

            pub fn init(args: struct {
                image_fingerprint: u64,
                accepted: bool,
                runtime_profile_fingerprint: u64,
                executable_manifest_available: bool = false,
                hard_blockers: usize = 0,
                warnings: usize = 0,
            }) @This() {
                var result = @This(){
                    .report_fingerprint = 0,
                    .image_fingerprint = args.image_fingerprint,
                    .accepted = args.accepted,
                    .runtime_profile_fingerprint = args.runtime_profile_fingerprint,
                    .executable_manifest_available = args.executable_manifest_available,
                    .hard_blockers = args.hard_blockers,
                    .warnings = args.warnings,
                };
                result.report_fingerprint = fingerprintLoadReport(result);
                return result;
            }
        };

        pub const SessionRef = struct {
            executable_image_fingerprint: u64,
            root_module_fingerprint: u64,
            dispatch_fingerprint: u64,
            session_fingerprint: u64,
        };

        pub const Builder = struct {
            allocator: std.mem.Allocator,
            options: Options,
            modules: std.ArrayList(Module) = .empty,
            external_bindings: std.ArrayList(ExternalBinding) = .empty,
            root_added: bool = false,

            pub const Options = struct {
                runtime_profile: RuntimeProfile = RuntimeProfile.universal_v1,
                linker_policy: W.Linker.Policy = .allow_external_ports,
                strict_external_bindings: bool = true,
                metadata: []const u8 = "",
            };

            pub fn init(allocator: std.mem.Allocator, options: Options) @This() {
                return .{ .allocator = allocator, .options = options };
            }

            pub fn deinit(self: *@This()) void {
                for (self.modules.items) |module| {
                    self.allocator.free(module.imports);
                    self.allocator.free(module.canonical_bytes);
                }
                self.modules.deinit(self.allocator);
                self.external_bindings.deinit(self.allocator);
                self.* = undefined;
            }

            pub fn addRootModule(self: *@This(), bytes: []const u8) !void {
                if (self.root_added) return error.ExecutableSealingBlocked;
                const module = try moduleFromBytes(self.allocator, bytes, .root, 0, self.options.runtime_profile);
                errdefer {
                    self.allocator.free(module.imports);
                    self.allocator.free(module.canonical_bytes);
                }
                try self.modules.append(self.allocator, module);
                self.root_added = true;
            }

            pub fn addProviderModule(self: *@This(), bytes: []const u8) !void {
                const module = try moduleFromBytes(self.allocator, bytes, .provider, @intCast(self.modules.items.len), self.options.runtime_profile);
                errdefer {
                    self.allocator.free(module.imports);
                    self.allocator.free(module.canonical_bytes);
                }
                for (self.modules.items) |existing| {
                    if (existing.module_ref.boundary_module_fingerprint != module.module_ref.boundary_module_fingerprint) continue;
                    if (!std.mem.eql(u8, existing.canonical_bytes, module.canonical_bytes)) return error.ExecutableSealingBlocked;
                    self.allocator.free(module.imports);
                    self.allocator.free(module.canonical_bytes);
                    return;
                }
                try self.modules.append(self.allocator, module);
            }

            pub fn addExternalBinding(self: *@This(), binding: ExternalBinding) !void {
                try binding.validate();
                try self.external_bindings.append(self.allocator, binding);
            }

            pub fn prepare(self: *@This()) !Prepared {
                if (!self.root_added) return error.ExecutableSealingBlocked;
                if (self.modules.items.len > self.options.runtime_profile.max_modules) return error.ExecutableSealingBlocked;
                if (self.external_bindings.items.len > self.options.runtime_profile.max_external_bindings) return error.ExecutableSealingBlocked;
                const modules = try cloneModuleSlice(self.allocator, self.modules.items);
                errdefer freeModuleSlice(self.allocator, modules);
                const supplied_external_bindings = try self.allocator.dupe(ExternalBinding, self.external_bindings.items);
                defer self.allocator.free(supplied_external_bindings);
                const module_set = ModuleSet.init(modules, 0);
                try module_set.validate();
                const root = module_set.root() orelse return error.ExecutableSealingBlocked;
                const catalog_entries = try self.allocator.alloc(W.Linker.Catalog.Entry, modules.len - 1);
                errdefer self.allocator.free(catalog_entries);
                var catalog_index: usize = 0;
                for (modules) |module| {
                    if (module.role != .provider) continue;
                    if (module.imports.len != 0) return error.ExecutableSealingBlocked;
                    catalog_entries[catalog_index] = catalogEntryForModule(root, module);
                    catalog_index += 1;
                }
                var link_result = try W.Linker.link(self.allocator, .{
                    .root_target_ref = root.target_ref,
                    .root_module_ref = root.module_ref,
                    .root_import_set = root.import_set,
                    .root_imports = root.imports,
                    .catalog = W.Linker.Catalog.init(catalog_entries),
                    .policy = self.options.linker_policy,
                    .max_depth = self.options.runtime_profile.max_provider_depth,
                    .max_provider_candidates = self.options.runtime_profile.max_modules,
                    .max_routes = self.options.runtime_profile.max_modules,
                });
                errdefer link_result.deinit();
                const residual_count = link_result.plan.external_environment_requirements.len;
                const binding_report = checkExternalBindings(self.options.strict_external_bindings, root, link_result.plan.external_environment_requirements, supplied_external_bindings);
                const hard_blockers = link_result.plan.blockers.len + binding_report.missing + binding_report.unused + binding_report.duplicates;
                const compatible = hard_blockers == 0;
                const external_bindings = try matchedExternalBindingsSlice(self.allocator, root, link_result.plan.external_environment_requirements, supplied_external_bindings);
                errdefer self.allocator.free(external_bindings);
                const module_fingerprints = try moduleFingerprintSlice(self.allocator, modules);
                errdefer self.allocator.free(module_fingerprints);
                const binding_fingerprints = try bindingFingerprintSlice(self.allocator, external_bindings);
                errdefer self.allocator.free(binding_fingerprints);
                const residual_order = try residualOrderSlice(self.allocator, link_result.plan.external_environment_requirements);
                errdefer self.allocator.free(residual_order);
                const dispatch_routes = try dispatchRouteSlices(self.allocator, link_result.plan);
                errdefer dispatch_routes.deinit(self.allocator);
                const dispatch = DispatchImage.init(.{
                    .root_module_id = module_set.root_module_id,
                    .module_fingerprints = module_fingerprints,
                    .external_binding_fingerprints = binding_fingerprints,
                    .residual_request_order = residual_order,
                    .fabric_plan_fingerprints = link_result.certificate.fabric_plan_fingerprints,
                    .route_ids = dispatch_routes.route_ids,
                    .route_kinds = dispatch_routes.route_kinds,
                    .route_parent_world_port_ids = dispatch_routes.route_parent_world_port_ids,
                    .route_requirement_fingerprints = dispatch_routes.route_requirement_fingerprints,
                    .route_provider_module_fingerprints = dispatch_routes.route_provider_module_fingerprints,
                    .linker_policy = self.options.linker_policy,
                    .link_plan_fingerprint = link_result.plan.plan_fingerprint,
                    .linker_certificate_fingerprint = link_result.certificate.certificate_fingerprint,
                    .assembly_fingerprint = link_result.assembly.assembly_fingerprint,
                });
                const memory_plan = MemoryPlan.deriveForDispatch(
                    self.options.runtime_profile,
                    modules,
                    residual_count,
                    dispatch_routes.route_ids.len,
                );
                const memory_fits_profile = imageOwnedByteFootprint(.{
                    .required_runtime_profile = self.options.runtime_profile,
                    .modules = modules,
                    .dispatch_image = dispatch,
                    .external_bindings = external_bindings,
                    .compatibility_report_summary = "executable image prepared",
                    .image_metadata = self.options.metadata,
                }) <= self.options.runtime_profile.max_image_bytes;
                const report = CompatibilityReport.init(.{
                    .compatible = compatible and memory_fits_profile,
                    .boundary_module_compatible = true,
                    .executable_plan_compatible = true,
                    .profile_compatible = true,
                    .capacity_compatible = compatible,
                    .memory_compatible = memory_fits_profile,
                    .hard_blockers = hard_blockers + @intFromBool(!memory_fits_profile),
                    .warnings = link_result.plan.warnings.len,
                    .summary = if (compatible and memory_fits_profile) "executable image prepared" else "executable image blocked",
                });
                const plan = Plan.init(.{
                    .module_set = module_set,
                    .runtime_profile = self.options.runtime_profile,
                    .link_plan = link_result.plan,
                    .linker_certificate = link_result.certificate,
                    .assembly = link_result.assembly,
                    .dispatch_image = dispatch,
                    .memory_plan = memory_plan,
                    .external_bindings = external_bindings,
                    .compatibility_report = report,
                    .metadata = self.options.metadata,
                });
                return .{
                    .allocator = self.allocator,
                    .plan = plan,
                    .link_result = link_result,
                    .owned_modules = modules,
                    .owned_external_bindings = external_bindings,
                    .owned_catalog_entries = catalog_entries,
                    .owned_module_fingerprints = module_fingerprints,
                    .owned_binding_fingerprints = binding_fingerprints,
                    .owned_residual_order = residual_order,
                    .owned_dispatch_routes = dispatch_routes,
                };
            }
        };

        pub const Prepared = struct {
            allocator: std.mem.Allocator,
            plan: Plan,
            link_result: W.Linker.Result,
            owned_modules: []Module,
            owned_external_bindings: []ExternalBinding,
            owned_catalog_entries: []W.Linker.Catalog.Entry,
            owned_module_fingerprints: []u64,
            owned_binding_fingerprints: []u64,
            owned_residual_order: []u64,
            owned_dispatch_routes: DispatchRouteSlices,

            pub fn deinit(self: *@This()) void {
                self.link_result.deinit();
                self.allocator.free(self.owned_catalog_entries);
                self.allocator.free(self.owned_module_fingerprints);
                self.allocator.free(self.owned_binding_fingerprints);
                self.allocator.free(self.owned_residual_order);
                self.owned_dispatch_routes.deinit(self.allocator);
                freeModuleSlice(self.allocator, self.owned_modules);
                self.allocator.free(self.owned_external_bindings);
                self.* = undefined;
            }

            pub fn seal(self: @This()) !Image {
                return self.plan.seal(self.allocator);
            }
        };

        fn moduleFromBytes(allocator: std.mem.Allocator, bytes: []const u8, role: Module.Role, module_id: u32, profile: RuntimeProfile) !Module {
            if (bytes.len == 0 or bytes.len > profile.max_module_bytes) return error.ExecutableSealingBlocked;
            var loaded = try BoundaryModule.decode(allocator, bytes, .{
                .require_full_module = true,
                .allow_reference_only = false,
            });
            defer loaded.deinit();
            if (!loaded.isFullModule()) return error.ExecutableSealingBlocked;
            const executable_payload = loaded.executablePlanImagePayload() orelse return error.ExecutableSealingBlocked;
            if (executable_payload.len == 0) return error.ExecutableSealingBlocked;
            const imports = try importsFromLoadedModule(allocator, loaded);
            errdefer allocator.free(imports);
            const canonical_bytes = try allocator.dupe(u8, bytes);
            errdefer allocator.free(canonical_bytes);
            const module_ref = moduleRefFromLoaded(loaded);
            const target_ref = targetRefFromModuleRef(module_ref);
            const import_counts = importRequirementCounts(imports);
            const import_set = W.ImportSet.init(.{
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .required_count = import_counts.required,
                .optional_count = import_counts.optional,
                .world_port_count = loadedWorldPortCount(loaded),
                .value_table_entry_count = loaded.importCount() * 3,
            });
            return .{
                .module_id = module_id,
                .role = role,
                .module_ref = module_ref,
                .target_ref = target_ref,
                .import_set = import_set,
                .imports = imports,
                .export_summary = exportSummaryFromLoaded(loaded, module_ref),
                .executable_plan_fingerprint = hashBytesDomain("world.executable.boundary.executable_plan", executable_payload),
                .validation_report_fingerprint = loaded.validation_report.report_fingerprint,
                .compatibility_report_fingerprint = loaded.validation_report.compatibility.report_fingerprint,
                .canonical_bytes = canonical_bytes,
            };
        }

        fn importsFromLoadedModule(allocator: std.mem.Allocator, loaded: BoundaryModule.LoadedModule) ![]W.ImportRequirement {
            const source = loaded.imports();
            const imports = try allocator.alloc(W.ImportRequirement, source.len);
            errdefer allocator.free(imports);
            const module_ref = moduleRefFromLoaded(loaded);
            const target_ref = targetRefFromModuleRef(module_ref);
            for (source, 0..) |import, index| {
                imports[index] = W.ImportRequirement.init(.{
                    .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                    .world_value_table_fingerprint = target_ref.world_value_table_fingerprint,
                    .world_surface_fingerprint = target_ref.world_surface_fingerprint,
                    .world_port_id = import.world_port_id,
                    .world_port_ref_fingerprint = import.world_port_ref.fingerprint,
                    .source_effect_shape_ref_fingerprint = import.source_effect_shape_ref.fingerprint,
                    .residual_site_index = import.residual_site_index,
                    .residual_site_fingerprint = import.residual_site_fingerprint,
                    .payload_value_table_id = import.payload_value_table_id,
                    .payload_value_ref_fingerprint = boundaryValueRefFingerprint(import.payload_ref),
                    .response_value_table_id = import.response_value_table_id,
                    .response_value_ref_fingerprint = boundaryValueRefFingerprint(import.response_ref),
                    .mode = modeFromBoundary(import.mode),
                    .allowed_response_kinds = if (std.mem.eql(u8, import.response_kind, "return_now")) .return_now_only else .resume_only,
                    .replay_key_recipe_fingerprint = import.replay_key_recipe_ref.fingerprint,
                    .suggested_symbolic_name = null,
                    .required = import.required,
                });
            }
            return imports;
        }

        fn loadedWorldPortCount(loaded: BoundaryModule.LoadedModule) usize {
            var count: usize = 0;
            for (loaded.imports()) |import| {
                count = @max(count, @as(usize, import.world_port_id) + 1);
            }
            return count;
        }

        const ImportRequirementCounts = struct {
            required: usize = 0,
            optional: usize = 0,
        };

        fn importRequirementCounts(imports: []const W.ImportRequirement) ImportRequirementCounts {
            var counts: ImportRequirementCounts = .{};
            for (imports) |import| {
                if (import.required) {
                    counts.required += 1;
                } else {
                    counts.optional += 1;
                }
            }
            return counts;
        }

        fn validateModuleCanonicalBytes(allocator: std.mem.Allocator, module: Module, profile: RuntimeProfile) !void {
            const decoded = moduleFromBytes(allocator, module.canonical_bytes, module.role, module.module_id, profile) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.InvalidFrameEncoding,
            };
            defer {
                allocator.free(decoded.imports);
                allocator.free(decoded.canonical_bytes);
            }
            if (decoded.module_ref.module_ref_fingerprint != module.module_ref.module_ref_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.module_ref.boundary_module_fingerprint != module.module_ref.boundary_module_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.target_ref.target_ref_fingerprint != module.target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.import_set.import_set_fingerprint != module.import_set.import_set_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.imports.len != module.imports.len) return error.InvalidFrameEncoding;
            for (decoded.imports, module.imports) |decoded_import, declared_import| {
                if (decoded_import.requirement_fingerprint != declared_import.requirement_fingerprint) return error.InvalidFrameEncoding;
            }
            if (!exportSummaryMatchesDecoded(decoded.export_summary, module.export_summary)) return error.InvalidFrameEncoding;
            if (decoded.executable_plan_fingerprint != module.executable_plan_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.validation_report_fingerprint != module.validation_report_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.compatibility_report_fingerprint != module.compatibility_report_fingerprint) return error.InvalidFrameEncoding;
        }

        fn exportSummaryMatchesDecoded(decoded: W.Admission.ExportSummary, declared: W.Admission.ExportSummary) bool {
            return decoded.export_summary_fingerprint == declared.export_summary_fingerprint and
                decoded.target_ref_fingerprint == declared.target_ref_fingerprint and
                optionalU64MatchesExact(decoded.module_ref_fingerprint, declared.module_ref_fingerprint) and
                decoded.main_export_present == declared.main_export_present and
                optionalU64MatchesExact(decoded.result_value_ref_fingerprint, declared.result_value_ref_fingerprint) and
                decoded.argument_value_ref_count == declared.argument_value_ref_count and
                decoded.normal_form_kind == declared.normal_form_kind and
                optionalBytesEqual(decoded.target_label, declared.target_label) and
                decoded.loaded_execution_supported == declared.loaded_execution_supported and
                optionalBytesEqual(decoded.loaded_execution_unsupported_reason, declared.loaded_execution_unsupported_reason);
        }

        fn moduleRefFromLoaded(loaded: BoundaryModule.LoadedModule) W.Admission.ModuleRef {
            const manifest = loaded.manifest();
            return W.Admission.ModuleRef.init(.{
                .boundary_module_fingerprint = manifest.module_fingerprint,
                .module_kind = moduleKindFromBoundary(manifest.module_kind),
                .target_ref_fingerprint = targetRefFromLoadedManifest(manifest).target_ref_fingerprint,
                .world_surface_fingerprint = manifest.world_surface_fingerprint,
                .target_certificate_fingerprint = manifest.target_certificate_fingerprint,
                .residual_program_plan_hash = manifest.program_plan_hash,
                .import_surface_fingerprint = manifest.import_surface_fingerprint,
                .export_surface_fingerprint = manifest.export_surface_fingerprint,
                .normal_form_kind = normalFormKindFromBoundary(manifest.normal_form),
                .world_port_count = manifest.world_port_count,
                .label = null,
            });
        }

        fn targetRefFromLoadedManifest(manifest: BoundaryModule.Manifest) W.TargetRef {
            return W.TargetRef.init(.{
                .target_label = null,
                .world_surface_fingerprint = manifest.world_surface_fingerprint,
                .target_certificate_fingerprint = manifest.target_certificate_fingerprint,
                .residual_program_plan_hash = manifest.program_plan_hash,
                .normal_form_kind = normalFormKindFromBoundary(manifest.normal_form),
                .boundary_module_fingerprint = manifest.module_fingerprint,
            });
        }

        fn targetRefFromModuleRef(module_ref: W.Admission.ModuleRef) W.TargetRef {
            return W.TargetRef.init(.{
                .target_label = null,
                .world_surface_fingerprint = module_ref.world_surface_fingerprint,
                .target_certificate_fingerprint = module_ref.target_certificate_fingerprint,
                .residual_program_plan_hash = module_ref.residual_program_plan_hash,
                .normal_form_kind = module_ref.normal_form_kind,
                .world_port_table_fingerprint = module_ref.world_port_table_fingerprint,
                .world_value_table_fingerprint = module_ref.world_value_table_fingerprint,
                .world_dispatch_table_fingerprint = module_ref.world_dispatch_table_fingerprint,
                .boundary_module_fingerprint = module_ref.boundary_module_fingerprint,
            });
        }

        fn exportSummaryFromLoaded(loaded: BoundaryModule.LoadedModule, module_ref: W.Admission.ModuleRef) W.Admission.ExportSummary {
            return W.Admission.ExportSummary.init(.{
                .target_ref_fingerprint = module_ref.target_ref_fingerprint,
                .module_ref_fingerprint = module_ref.module_ref_fingerprint,
                .main_export_present = true,
                .result_value_ref_fingerprint = boundaryValueRefFingerprint(loaded.resultValueRef()),
                .argument_value_ref_count = loaded.argumentValueRefs().len,
                .normal_form_kind = module_ref.normal_form_kind,
                .loaded_execution_supported = true,
                .loaded_execution_unsupported_reason = null,
            });
        }

        fn catalogEntryForModule(root: Module, module: Module) W.Linker.Catalog.Entry {
            const descriptor = W.Linker.ExportDescriptor.init(.{
                .target_ref = module.target_ref,
                .module_ref = module.module_ref,
                .export_ref_fingerprint = module.export_summary.export_summary_fingerprint,
                .result_ref = .{
                    .value_table_id = providerResultValueTableId(root, module),
                    .value_ref_fingerprint = module.export_summary.result_value_ref_fingerprint,
                },
                .normal_form_kind = module.module_ref.normal_form_kind,
                .label = "loaded-module-export",
            });
            return W.Linker.Catalog.Entry.moduleRef(.{
                .module_ref = module.module_ref,
                .target_ref = module.target_ref,
                .export_descriptor = descriptor,
                .import_set = module.import_set,
                .imports = module.imports,
                .label = "loaded-module-provider",
            });
        }

        fn providerResultValueTableId(root: Module, provider: Module) ?u32 {
            const provider_result = provider.export_summary.result_value_ref_fingerprint orelse return null;
            for (root.imports) |requirement| {
                if (requirement.response_value_ref_fingerprint == provider_result) return requirement.response_value_table_id;
            }
            return null;
        }

        const BindingReport = struct { missing: usize = 0, unused: usize = 0, duplicates: usize = 0 };

        fn responseStatusSetSubset(subset: W.Actuation.ResponseStatusSet, superset: W.Actuation.ResponseStatusSet) bool {
            return (!subset.responded or superset.responded) and
                (!subset.rejected or superset.rejected) and
                (!subset.failed or superset.failed) and
                (!subset.pending or superset.pending) and
                (!subset.deferred or superset.deferred) and
                (!subset.cancelled or superset.cancelled);
        }

        fn validateDispatchTablesForImage(allocator: std.mem.Allocator, image: Image) !void {
            if (image.dispatch_image.root_module_id != image.module_set.root_module_id) return error.InvalidFrameEncoding;
            if (image.dispatch_image.module_fingerprints.len != image.module_set.modules.len) return error.InvalidFrameEncoding;
            const route_count = image.dispatch_image.route_ids.len;
            if (image.dispatch_image.route_kinds.len != route_count or
                image.dispatch_image.route_parent_world_port_ids.len != route_count or
                image.dispatch_image.route_requirement_fingerprints.len != route_count or
                image.dispatch_image.route_provider_module_fingerprints.len != route_count)
            {
                return error.InvalidFrameEncoding;
            }
            for (image.module_set.modules) |module| {
                if (countU64(image.dispatch_image.module_fingerprints, module.module_ref.boundary_module_fingerprint) !=
                    countModuleFingerprint(image.module_set.modules, module.module_ref.boundary_module_fingerprint))
                {
                    return error.InvalidFrameEncoding;
                }
            }
            for (image.dispatch_image.module_fingerprints) |fingerprint| {
                if (countModuleFingerprint(image.module_set.modules, fingerprint) != countU64(image.dispatch_image.module_fingerprints, fingerprint)) return error.InvalidFrameEncoding;
            }

            if (image.dispatch_image.external_binding_fingerprints.len != image.external_bindings.len) return error.InvalidFrameEncoding;
            for (image.external_bindings) |binding| {
                if (countU64(image.dispatch_image.external_binding_fingerprints, binding.binding_fingerprint) !=
                    countExternalBindingFingerprint(image.external_bindings, binding.binding_fingerprint))
                {
                    return error.InvalidFrameEncoding;
                }
            }
            for (image.dispatch_image.external_binding_fingerprints) |fingerprint| {
                if (countExternalBindingFingerprint(image.external_bindings, fingerprint) != countU64(image.dispatch_image.external_binding_fingerprints, fingerprint)) return error.InvalidFrameEncoding;
            }
            try validateDispatchRouteRowsAgainstLinkWitness(allocator, image);
        }

        fn validateDispatchRouteRowsAgainstLinkWitness(allocator: std.mem.Allocator, image: Image) !void {
            const root = image.module_set.root() orelse return error.InvalidFrameEncoding;
            const catalog_entries = try allocator.alloc(W.Linker.Catalog.Entry, image.module_set.modules.len);
            defer allocator.free(catalog_entries);
            var catalog_count: usize = 0;
            for (image.module_set.modules) |module| {
                if (module.role != .provider) continue;
                catalog_entries[catalog_count] = catalogEntryForModule(root, module);
                catalog_count += 1;
            }

            if (dispatchRouteRowsMatchPolicy(allocator, image, root, catalog_entries[0..catalog_count], image.dispatch_image.linker_policy) catch false) return;
            return error.InvalidFrameEncoding;
        }

        fn dispatchRouteRowsMatchPolicy(
            allocator: std.mem.Allocator,
            image: Image,
            root: Module,
            catalog_entries: []const W.Linker.Catalog.Entry,
            policy: W.Linker.Policy,
        ) !bool {
            var link_result = try W.Linker.link(allocator, .{
                .root_target_ref = root.target_ref,
                .root_module_ref = root.module_ref,
                .root_import_set = root.import_set,
                .root_imports = root.imports,
                .catalog = W.Linker.Catalog.init(catalog_entries),
                .policy = policy,
                .max_depth = image.required_runtime_profile.max_provider_depth,
                .max_provider_candidates = image.required_runtime_profile.max_modules,
                .max_routes = image.required_runtime_profile.max_modules,
            });
            defer link_result.deinit();
            if (link_result.plan.plan_fingerprint != image.link_plan_fingerprint) return false;
            if (link_result.certificate.certificate_fingerprint != image.linker_certificate_fingerprint) return false;
            if (link_result.assembly.assembly_fingerprint != image.assembly_fingerprint) return false;
            if (!std.mem.eql(u64, link_result.certificate.fabric_plan_fingerprints, image.dispatch_image.fabric_plan_fingerprints)) return false;
            if (!residualOrderMatchesRequirements(image.dispatch_image.residual_request_order, link_result.plan.external_environment_requirements)) return false;
            const routes = try dispatchRouteSlices(allocator, link_result.plan);
            defer routes.deinit(allocator);
            return std.mem.eql(u64, routes.route_ids, image.dispatch_image.route_ids) and
                std.mem.eql(W.Fabric.RouteKind, routes.route_kinds, image.dispatch_image.route_kinds) and
                std.mem.eql(u32, routes.route_parent_world_port_ids, image.dispatch_image.route_parent_world_port_ids) and
                std.mem.eql(u64, routes.route_requirement_fingerprints, image.dispatch_image.route_requirement_fingerprints) and
                std.mem.eql(u64, routes.route_provider_module_fingerprints, image.dispatch_image.route_provider_module_fingerprints);
        }

        fn countU64(values: []const u64, needle: u64) usize {
            var count: usize = 0;
            for (values) |value| {
                if (value == needle) count += 1;
            }
            return count;
        }

        fn countModuleFingerprint(modules: []const Module, fingerprint: u64) usize {
            var count: usize = 0;
            for (modules) |module| {
                if (module.module_ref.boundary_module_fingerprint == fingerprint) count += 1;
            }
            return count;
        }

        fn countExternalBindingFingerprint(bindings: []const ExternalBinding, fingerprint: u64) usize {
            var count: usize = 0;
            for (bindings) |binding| {
                if (binding.binding_fingerprint == fingerprint) count += 1;
            }
            return count;
        }

        fn validateExternalBindingsForImage(image: Image) !void {
            for (image.external_bindings) |binding| try binding.validate();
            const root = image.module_set.root() orelse return error.InvalidFrameEncoding;
            for (root.imports) |requirement| {
                if (!requirement.required) continue;
                if (!dispatchCoversRequirement(image.dispatch_image, requirement)) return error.InvalidFrameEncoding;
            }
            for (image.dispatch_image.residual_request_order, 0..) |requirement_fingerprint, index| {
                for (image.dispatch_image.residual_request_order[0..index]) |prior_requirement_fingerprint| {
                    if (prior_requirement_fingerprint == requirement_fingerprint) return error.InvalidFrameEncoding;
                }
                const requirement = importRequirementForFingerprint(root, requirement_fingerprint) orelse return error.InvalidFrameEncoding;
                var count: usize = 0;
                for (image.external_bindings) |binding| {
                    if (binding.matchesRequirement(root, requirement)) count += 1;
                }
                if (count != 1) return error.InvalidFrameEncoding;
            }
            for (image.external_bindings) |binding| {
                var matched_count: usize = 0;
                for (image.dispatch_image.residual_request_order) |requirement_fingerprint| {
                    const requirement = importRequirementForFingerprint(root, requirement_fingerprint) orelse return error.InvalidFrameEncoding;
                    if (binding.matchesRequirement(root, requirement)) matched_count += 1;
                }
                if (matched_count != 1) return error.InvalidFrameEncoding;
            }
        }

        fn validateImageFitsRuntimeProfile(image: Image) !void {
            const profile = image.required_runtime_profile;
            if (image.module_set.modules.len > profile.max_modules) return error.InvalidFrameEncoding;
            if (image.external_bindings.len > profile.max_external_bindings) return error.InvalidFrameEncoding;
            if (!profile.supports_external_actuation and image.external_bindings.len != 0) return error.InvalidFrameEncoding;
            if (!profile.supports_internal_providers) {
                for (image.module_set.modules) |module| {
                    if (module.role == .provider) return error.InvalidFrameEncoding;
                }
                if (image.dispatch_image.fabric_plan_fingerprints.len != 0 or
                    image.dispatch_image.route_ids.len != 0)
                {
                    return error.InvalidFrameEncoding;
                }
            }
            for (image.module_set.modules) |module| {
                if (module.canonical_bytes.len > profile.max_module_bytes) return error.InvalidFrameEncoding;
            }
            if (image.ownedByteFootprint() > profile.max_image_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_command_bytes > profile.max_command_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_output_bytes > profile.max_output_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_linear_memory_pages > profile.max_linear_memory_pages) return error.InvalidFrameEncoding;
        }

        fn imageOwnedByteFootprint(args: struct {
            required_runtime_profile: RuntimeProfile,
            modules: []const Module,
            dispatch_image: DispatchImage,
            external_bindings: []const ExternalBinding,
            compatibility_report_summary: []const u8 = "",
            image_metadata: []const u8 = "",
        }) usize {
            var total: usize = 0;
            total = total +| args.required_runtime_profile.metadata.len;
            total = total +| args.compatibility_report_summary.len;
            total = total +| args.image_metadata.len;
            for (args.modules) |module| {
                total = total +| module.canonical_bytes.len;
                total = total +| (module.imports.len *| @sizeOf(W.ImportRequirement));
            }
            total = total +| (args.dispatch_image.module_fingerprints.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.external_binding_fingerprints.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.residual_request_order.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.fabric_plan_fingerprints.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.route_ids.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.route_kinds.len *| @sizeOf(W.Fabric.RouteKind));
            total = total +| (args.dispatch_image.route_parent_world_port_ids.len *| @sizeOf(u32));
            total = total +| (args.dispatch_image.route_requirement_fingerprints.len *| @sizeOf(u64));
            total = total +| (args.dispatch_image.route_provider_module_fingerprints.len *| @sizeOf(u64));
            for (args.external_bindings) |binding| {
                total = total +| binding.actuator_ref.label.len;
                total = total +| binding.actuator_ref.metadata.len;
                total = total +| binding.descriptor.label.len;
                total = total +| binding.descriptor.metadata.len;
                total = total +| binding.label.len;
                total = total +| binding.metadata.len;
            }
            return total;
        }

        fn dispatchCoversRequirement(dispatch: DispatchImage, requirement: W.ImportRequirement) bool {
            for (dispatch.residual_request_order) |fingerprint| {
                if (fingerprint == requirement.requirement_fingerprint) return true;
            }
            for (dispatch.route_requirement_fingerprints) |fingerprint| {
                if (fingerprint == requirement.requirement_fingerprint) return true;
            }
            return false;
        }

        fn residualOrderMatchesRequirements(residual_order: []const u64, requirements: []const W.ImportRequirement) bool {
            if (residual_order.len != requirements.len) return false;
            for (residual_order) |fingerprint| {
                if (countU64(residual_order, fingerprint) != countRequirementFingerprint(requirements, fingerprint)) return false;
            }
            return true;
        }

        fn countRequirementFingerprint(requirements: []const W.ImportRequirement, fingerprint: u64) usize {
            var count: usize = 0;
            for (requirements) |requirement| {
                if (requirement.requirement_fingerprint == fingerprint) count += 1;
            }
            return count;
        }

        fn importRequirementForFingerprint(root: Module, requirement_fingerprint: u64) ?W.ImportRequirement {
            for (root.imports) |requirement| {
                if (requirement.requirement_fingerprint == requirement_fingerprint) return requirement;
            }
            return null;
        }

        fn checkExternalBindings(strict: bool, root: Module, residuals: []const W.ImportRequirement, bindings: []const ExternalBinding) BindingReport {
            var report: BindingReport = .{};
            for (residuals) |requirement| {
                var count: usize = 0;
                for (bindings) |binding| {
                    if (binding.matchesRequirement(root, requirement)) count += 1;
                }
                if (count == 0) report.missing += 1;
                if (count > 1) report.duplicates += count - 1;
            }
            for (bindings) |binding| {
                var matched_count: usize = 0;
                for (residuals) |requirement| {
                    if (binding.matchesRequirement(root, requirement)) {
                        matched_count += 1;
                    }
                }
                if (strict and matched_count == 0) report.unused += 1;
                if (matched_count > 1) report.duplicates += matched_count - 1;
            }
            return report;
        }

        fn matchedExternalBindingsSlice(allocator: std.mem.Allocator, root: Module, residuals: []const W.ImportRequirement, bindings: []const ExternalBinding) ![]ExternalBinding {
            var count: usize = 0;
            for (bindings) |binding| {
                if (bindingMatchesAnyRequirement(root, residuals, binding)) count += 1;
            }
            const matched = try allocator.alloc(ExternalBinding, count);
            var index: usize = 0;
            for (bindings) |binding| {
                if (!bindingMatchesAnyRequirement(root, residuals, binding)) continue;
                matched[index] = binding;
                index += 1;
            }
            return matched;
        }

        fn bindingMatchesAnyRequirement(root: Module, residuals: []const W.ImportRequirement, binding: ExternalBinding) bool {
            for (residuals) |requirement| {
                if (binding.matchesRequirement(root, requirement)) return true;
            }
            return false;
        }

        fn moduleFingerprintSlice(allocator: std.mem.Allocator, modules: []const Module) ![]u64 {
            const values = try allocator.alloc(u64, modules.len);
            for (modules, 0..) |module, index| values[index] = module.module_ref.boundary_module_fingerprint;
            std.mem.sort(u64, values, {}, std.sort.asc(u64));
            return values;
        }

        fn cloneModuleSlice(allocator: std.mem.Allocator, modules: []const Module) ![]Module {
            const cloned = try allocator.alloc(Module, modules.len);
            var initialized: usize = 0;
            errdefer freeModuleSlice(allocator, cloned[0..initialized]);
            for (modules, 0..) |module, index| {
                var current = module;
                current.module_ref.label = null;
                current.module_ref.metadata = "";
                current.target_ref.target_label = null;
                current.target_ref.metadata = "";
                current.imports = &.{};
                current.export_summary.target_label = null;
                current.export_summary.loaded_execution_unsupported_reason = null;
                current.canonical_bytes = &.{};
                errdefer {
                    freeModuleOwnedFields(allocator, current);
                    allocator.free(current.canonical_bytes);
                }
                current.module_ref.label = try cloneOptionalBytes(allocator, module.module_ref.label);
                current.module_ref.metadata = try allocator.dupe(u8, module.module_ref.metadata);
                current.target_ref.target_label = try cloneOptionalBytes(allocator, module.target_ref.target_label);
                current.target_ref.metadata = try allocator.dupe(u8, module.target_ref.metadata);
                const cloned_imports = try allocator.alloc(W.ImportRequirement, module.imports.len);
                current.imports = cloned_imports;
                for (cloned_imports) |*cloned_requirement| {
                    cloned_requirement.suggested_symbolic_name = null;
                    cloned_requirement.tags = &.{};
                    cloned_requirement.metadata = "";
                }
                for (cloned_imports, module.imports) |*cloned_requirement, requirement| {
                    cloned_requirement.* = requirement;
                    cloned_requirement.suggested_symbolic_name = null;
                    cloned_requirement.tags = &.{};
                    cloned_requirement.metadata = "";
                    cloned_requirement.suggested_symbolic_name = try cloneOptionalBytes(allocator, requirement.suggested_symbolic_name);
                    cloned_requirement.tags = try cloneStringSlice(allocator, requirement.tags);
                    cloned_requirement.metadata = try allocator.dupe(u8, requirement.metadata);
                }
                current.export_summary.target_label = try cloneOptionalBytes(allocator, module.export_summary.target_label);
                current.export_summary.loaded_execution_unsupported_reason = try cloneOptionalBytes(allocator, module.export_summary.loaded_execution_unsupported_reason);
                current.canonical_bytes = try allocator.dupe(u8, module.canonical_bytes);
                cloned[index] = current;
                initialized += 1;
                current.module_ref.label = null;
                current.module_ref.metadata = "";
                current.target_ref.target_label = null;
                current.target_ref.metadata = "";
                current.imports = &.{};
                current.export_summary.target_label = null;
                current.export_summary.loaded_execution_unsupported_reason = null;
                current.canonical_bytes = &.{};
            }
            return cloned;
        }

        fn freeModuleSlice(allocator: std.mem.Allocator, modules: []Module) void {
            for (modules) |module| {
                freeModuleOwnedFields(allocator, module);
                allocator.free(module.imports);
                allocator.free(module.canonical_bytes);
            }
            allocator.free(modules);
        }

        fn freeModuleOwnedFields(allocator: std.mem.Allocator, module: Module) void {
            if (module.module_ref.label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(module.module_ref.metadata));
            if (module.target_ref.target_label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(module.target_ref.metadata));
            for (module.imports) |requirement| {
                if (requirement.suggested_symbolic_name) |symbol| allocator.free(@constCast(symbol));
                freeStringSlice(allocator, requirement.tags);
                allocator.free(@constCast(requirement.metadata));
            }
            if (module.export_summary.target_label) |label| allocator.free(@constCast(label));
            if (module.export_summary.loaded_execution_unsupported_reason) |reason| allocator.free(@constCast(reason));
        }

        fn bindingFingerprintSlice(allocator: std.mem.Allocator, bindings: []const ExternalBinding) ![]u64 {
            const values = try allocator.alloc(u64, bindings.len);
            for (bindings, 0..) |binding, index| values[index] = binding.binding_fingerprint;
            std.mem.sort(u64, values, {}, std.sort.asc(u64));
            return values;
        }

        fn residualOrderSlice(allocator: std.mem.Allocator, residuals: []const W.ImportRequirement) ![]u64 {
            const values = try allocator.alloc(u64, residuals.len);
            for (residuals, 0..) |requirement, index| values[index] = requirement.requirement_fingerprint;
            std.mem.sort(u64, values, {}, std.sort.asc(u64));
            return values;
        }

        const DispatchRouteSlices = struct {
            route_ids: []u64 = &.{},
            route_kinds: []W.Fabric.RouteKind = &.{},
            route_parent_world_port_ids: []u32 = &.{},
            route_requirement_fingerprints: []u64 = &.{},
            route_provider_module_fingerprints: []u64 = &.{},

            fn deinit(self: @This(), allocator: std.mem.Allocator) void {
                allocator.free(self.route_ids);
                allocator.free(self.route_kinds);
                allocator.free(self.route_parent_world_port_ids);
                allocator.free(self.route_requirement_fingerprints);
                allocator.free(self.route_provider_module_fingerprints);
            }
        };

        fn dispatchRouteSlices(allocator: std.mem.Allocator, plan: W.Linker.Plan) !DispatchRouteSlices {
            var count: usize = 0;
            for (plan.fabric_plans) |fabric_plan| count += fabric_plan.routes.len;
            const route_ids = try allocator.alloc(u64, count);
            errdefer allocator.free(route_ids);
            const route_kinds = try allocator.alloc(W.Fabric.RouteKind, count);
            errdefer allocator.free(route_kinds);
            const route_parent_world_port_ids = try allocator.alloc(u32, count);
            errdefer allocator.free(route_parent_world_port_ids);
            const route_requirement_fingerprints = try allocator.alloc(u64, count);
            errdefer allocator.free(route_requirement_fingerprints);
            const route_provider_module_fingerprints = try allocator.alloc(u64, count);
            errdefer allocator.free(route_provider_module_fingerprints);
            var index: usize = 0;
            for (plan.fabric_plans) |fabric_plan| {
                for (fabric_plan.routes) |route| {
                    route_ids[index] = route.route_id;
                    route_kinds[index] = route.kind;
                    route_parent_world_port_ids[index] = route.parent_world_port_id;
                    route_requirement_fingerprints[index] = routeRequirementFingerprint(plan, route.route_fingerprint);
                    route_provider_module_fingerprints[index] = route.provider_module_fingerprint orelse 0;
                    index += 1;
                }
            }
            return .{
                .route_ids = route_ids,
                .route_kinds = route_kinds,
                .route_parent_world_port_ids = route_parent_world_port_ids,
                .route_requirement_fingerprints = route_requirement_fingerprints,
                .route_provider_module_fingerprints = route_provider_module_fingerprints,
            };
        }

        fn routeRequirementFingerprint(plan: W.Linker.Plan, route_fingerprint: u64) u64 {
            for (plan.route_syntheses) |synthesis| {
                if (synthesis.route_fingerprint == route_fingerprint) return synthesis.import_requirement_fingerprint;
            }
            return 0;
        }

        fn cloneDispatchImage(allocator: std.mem.Allocator, image: DispatchImage) !DispatchImage {
            var result = image;
            result.module_fingerprints = try allocator.dupe(u64, image.module_fingerprints);
            errdefer allocator.free(result.module_fingerprints);
            result.external_binding_fingerprints = try allocator.dupe(u64, image.external_binding_fingerprints);
            errdefer allocator.free(result.external_binding_fingerprints);
            result.residual_request_order = try allocator.dupe(u64, image.residual_request_order);
            errdefer allocator.free(result.residual_request_order);
            result.fabric_plan_fingerprints = try allocator.dupe(u64, image.fabric_plan_fingerprints);
            errdefer allocator.free(result.fabric_plan_fingerprints);
            result.route_ids = try allocator.dupe(u64, image.route_ids);
            errdefer allocator.free(result.route_ids);
            result.route_kinds = try allocator.dupe(W.Fabric.RouteKind, image.route_kinds);
            errdefer allocator.free(result.route_kinds);
            result.route_parent_world_port_ids = try allocator.dupe(u32, image.route_parent_world_port_ids);
            errdefer allocator.free(result.route_parent_world_port_ids);
            result.route_requirement_fingerprints = try allocator.dupe(u64, image.route_requirement_fingerprints);
            errdefer allocator.free(result.route_requirement_fingerprints);
            result.route_provider_module_fingerprints = try allocator.dupe(u64, image.route_provider_module_fingerprints);
            errdefer allocator.free(result.route_provider_module_fingerprints);
            return result;
        }

        fn freeDispatchImage(allocator: std.mem.Allocator, image: DispatchImage) void {
            allocator.free(image.module_fingerprints);
            allocator.free(image.external_binding_fingerprints);
            allocator.free(image.residual_request_order);
            allocator.free(image.fabric_plan_fingerprints);
            allocator.free(image.route_ids);
            allocator.free(image.route_kinds);
            allocator.free(image.route_parent_world_port_ids);
            allocator.free(image.route_requirement_fingerprints);
            allocator.free(image.route_provider_module_fingerprints);
        }

        fn cloneExternalBinding(allocator: std.mem.Allocator, binding: ExternalBinding) !ExternalBinding {
            var result = binding;
            result.actuator_ref.label = try allocator.dupe(u8, binding.actuator_ref.label);
            errdefer allocator.free(result.actuator_ref.label);
            result.actuator_ref.metadata = try allocator.dupe(u8, binding.actuator_ref.metadata);
            errdefer allocator.free(result.actuator_ref.metadata);
            result.descriptor.label = try allocator.dupe(u8, binding.descriptor.label);
            errdefer allocator.free(result.descriptor.label);
            result.descriptor.metadata = try allocator.dupe(u8, binding.descriptor.metadata);
            errdefer allocator.free(result.descriptor.metadata);
            result.label = try allocator.dupe(u8, binding.label);
            errdefer allocator.free(result.label);
            result.metadata = try allocator.dupe(u8, binding.metadata);
            return result;
        }

        fn cloneExternalBindingSlice(allocator: std.mem.Allocator, bindings: []const ExternalBinding) ![]ExternalBinding {
            const result = try allocator.alloc(ExternalBinding, bindings.len);
            errdefer allocator.free(result);
            var index: usize = 0;
            errdefer {
                for (result[0..index]) |binding| freeExternalBinding(allocator, binding);
            }
            while (index < bindings.len) : (index += 1) {
                result[index] = try cloneExternalBinding(allocator, bindings[index]);
            }
            return result;
        }

        fn freeExternalBinding(allocator: std.mem.Allocator, binding: ExternalBinding) void {
            allocator.free(binding.actuator_ref.label);
            allocator.free(binding.actuator_ref.metadata);
            allocator.free(binding.descriptor.label);
            allocator.free(binding.descriptor.metadata);
            allocator.free(binding.label);
            allocator.free(binding.metadata);
        }

        fn freeExternalBindingSlice(allocator: std.mem.Allocator, bindings: []const ExternalBinding) void {
            for (bindings) |binding| freeExternalBinding(allocator, binding);
            allocator.free(bindings);
        }

        const executable_image_magic = "world.Executable.Image.v2\x00";
        const executable_image_total_len_offset = executable_image_magic.len + @sizeOf(u32) + @sizeOf(u32) + @sizeOf(u32);

        fn encodeExecutableImage(allocator: std.mem.Allocator, image: Image) ![]u8 {
            _ = try image.validate(image.required_runtime_profile);
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try writeRawBytes(&out, allocator, executable_image_magic);
            try writeU32(&out, allocator, image.format_version);
            try writeU32(&out, allocator, image.fingerprint_version);
            try writeU32(&out, allocator, W.world_executable_image_codec_version);
            try writeU64(&out, allocator, 0);
            try writeU64(&out, allocator, image.image_fingerprint);
            try writeRuntimeProfile(&out, allocator, image.required_runtime_profile);
            try writeModuleSet(&out, allocator, image.module_set);
            try writeU64(&out, allocator, image.link_plan_fingerprint);
            try writeU64(&out, allocator, image.linker_certificate_fingerprint);
            try writeU64(&out, allocator, image.assembly_fingerprint);
            try writeDispatchImage(&out, allocator, image.dispatch_image);
            try writeExternalBindingSlice(&out, allocator, image.external_bindings);
            try writeMemoryPlan(&out, allocator, image.memory_plan);
            try writeCompatibilityReport(&out, allocator, image.compatibility_report);
            try writeCertificate(&out, allocator, image.certificate);
            try writeBytes(&out, allocator, image.metadata);
            patchU64(out.items, executable_image_total_len_offset, out.items.len);
            return out.toOwnedSlice(allocator);
        }

        fn decodeExecutableImage(allocator: std.mem.Allocator, bytes: []const u8, limits: Image.DecodeLimits) !Image {
            if (bytes.len == 0 or bytes.len > limits.max_image_bytes) return error.InvalidFrameEncoding;
            var cursor: usize = 0;
            try readFixedBytes(bytes, &cursor, executable_image_magic);
            const format_version = try readU32(bytes, &cursor);
            if (format_version != W.world_executable_image_format_version) return error.InvalidFrameEncoding;
            const fingerprint_version = try readU32(bytes, &cursor);
            if (fingerprint_version != W.world_executable_image_fingerprint_version) return error.InvalidFrameEncoding;
            const codec_version = try readU32(bytes, &cursor);
            if (codec_version != W.world_executable_image_codec_version) return error.InvalidFrameEncoding;
            const total_len = try readCount(bytes, &cursor, limits.max_image_bytes);
            if (total_len != bytes.len) return error.InvalidFrameEncoding;
            const image_fingerprint = try readU64(bytes, &cursor);
            const required_runtime_profile = try readRuntimeProfile(allocator, bytes, &cursor, limits);
            errdefer allocator.free(@constCast(required_runtime_profile.metadata));
            const module_set = try readModuleSet(allocator, bytes, &cursor, limits);
            errdefer freeModuleSlice(allocator, @constCast(module_set.modules.ptr)[0..module_set.modules.len]);
            const link_plan_fingerprint = try readU64(bytes, &cursor);
            const linker_certificate_fingerprint = try readU64(bytes, &cursor);
            const assembly_fingerprint = try readU64(bytes, &cursor);
            const dispatch_image = try readDispatchImage(allocator, bytes, &cursor, limits);
            errdefer freeDispatchImage(allocator, dispatch_image);
            const external_bindings = try readExternalBindingSlice(allocator, bytes, &cursor, limits);
            errdefer freeExternalBindingSlice(allocator, external_bindings);
            const memory_plan = try readMemoryPlan(bytes, &cursor);
            const compatibility_report = try readCompatibilityReport(allocator, bytes, &cursor, limits);
            errdefer allocator.free(@constCast(compatibility_report.summary));
            const certificate = try readCertificate(bytes, &cursor);
            const metadata = try readBytesOwned(allocator, bytes, &cursor, limits.max_metadata_bytes);
            errdefer allocator.free(metadata);
            if (cursor != bytes.len) return error.InvalidFrameEncoding;
            var image = Image{
                .format_version = format_version,
                .fingerprint_version = fingerprint_version,
                .image_fingerprint = image_fingerprint,
                .required_runtime_profile = required_runtime_profile,
                .module_set = module_set,
                .link_plan_fingerprint = link_plan_fingerprint,
                .linker_certificate_fingerprint = linker_certificate_fingerprint,
                .assembly_fingerprint = assembly_fingerprint,
                .dispatch_image = dispatch_image,
                .external_bindings = external_bindings,
                .memory_plan = memory_plan,
                .compatibility_report = compatibility_report,
                .certificate = certificate,
                .metadata = metadata,
                .owns_memory = true,
            };
            _ = try image.validateWithAllocator(allocator, image.required_runtime_profile);
            return image;
        }

        fn imageEncodedLen(image: Image) !usize {
            var total: usize = executable_image_magic.len + 4 + 4 + 4 + 8 + 8;
            try addRuntimeProfileLen(&total, image.required_runtime_profile);
            try addModuleSetLen(&total, image.module_set);
            try addChecked(&total, 8 + 8 + 8);
            try addDispatchImageLen(&total, image.dispatch_image);
            try addExternalBindingSliceLen(&total, image.external_bindings);
            try addMemoryPlanLen(&total);
            try addCompatibilityReportLen(&total, image.compatibility_report);
            try addCertificateLen(&total);
            try addBytesLen(&total, image.metadata);
            return total;
        }

        fn dispatchEntryCount(image: DispatchImage) usize {
            return image.module_fingerprints.len +| image.external_binding_fingerprints.len +| image.residual_request_order.len +|
                image.fabric_plan_fingerprints.len +| image.route_ids.len +| image.route_kinds.len +|
                image.route_parent_world_port_ids.len +| image.route_requirement_fingerprints.len +| image.route_provider_module_fingerprints.len;
        }

        fn maxCanonicalModuleBytes(modules: []const Module) usize {
            var max_bytes: usize = 0;
            for (modules) |module| max_bytes = @max(max_bytes, module.canonical_bytes.len);
            return max_bytes;
        }

        fn addChecked(total: *usize, amount: usize) !void {
            total.* = std.math.add(usize, total.*, amount) catch return error.InvalidFrameEncoding;
        }

        fn addBytesLen(total: *usize, bytes: []const u8) !void {
            try addChecked(total, 8);
            try addChecked(total, bytes.len);
        }

        fn addOptionalBytesLen(total: *usize, value: ?[]const u8) !void {
            try addChecked(total, 1);
            if (value) |bytes| try addBytesLen(total, bytes);
        }

        fn addStringSliceLen(total: *usize, values: []const []const u8) !void {
            try addChecked(total, 8);
            for (values) |value| try addBytesLen(total, value);
        }

        fn addRuntimeProfileLen(total: *usize, profile: RuntimeProfile) !void {
            try addChecked(total, 8 + 1 + 1 + 1 + 8 + 8 + 8 + 8 + 8 + 8 + 8 + 8);
            try addBytesLen(total, profile.metadata);
        }

        fn addModuleSetLen(total: *usize, module_set: ModuleSet) !void {
            try addChecked(total, 8 + 8 + 8);
            for (module_set.modules) |module| {
                try addChecked(total, 8 + 1);
                try addModuleRefLen(total, module.module_ref);
                try addTargetRefLen(total, module.target_ref);
                try addImportSetLen(total);
                try addChecked(total, 8);
                for (module.imports) |requirement| try addImportRequirementLen(total, requirement);
                try addExportSummaryLen(total, module.export_summary);
                try addChecked(total, 8 + 8 + 8);
                try addBytesLen(total, module.canonical_bytes);
            }
        }

        fn addModuleRefLen(total: *usize, ref: W.Admission.ModuleRef) !void {
            try addChecked(total, 4 + 4 + 8 + 8 + 1 + 8 + 8 + 8);
            try addOptionalU64Len(total, ref.residual_program_plan_hash);
            try addOptionalU64Len(total, ref.import_surface_fingerprint);
            try addOptionalU64Len(total, ref.export_surface_fingerprint);
            try addOptionalU64Len(total, ref.module_graph_fingerprint);
            try addChecked(total, 1 + 8);
            try addOptionalU64Len(total, ref.world_port_table_fingerprint);
            try addOptionalU64Len(total, ref.world_value_table_fingerprint);
            try addOptionalU64Len(total, ref.world_dispatch_table_fingerprint);
            try addOptionalBytesLen(total, ref.label);
            try addBytesLen(total, ref.metadata);
        }

        fn addTargetRefLen(total: *usize, ref: W.TargetRef) !void {
            try addChecked(total, 4 + 4 + 8);
            try addOptionalBytesLen(total, ref.target_label);
            try addChecked(total, 8);
            try addOptionalU64Len(total, ref.world_surface_replay_scope_fingerprint);
            try addChecked(total, 8);
            try addOptionalU64Len(total, ref.residual_program_plan_hash);
            try addChecked(total, 1);
            try addOptionalU64Len(total, ref.world_port_table_fingerprint);
            try addOptionalU64Len(total, ref.world_value_table_fingerprint);
            try addOptionalU64Len(total, ref.world_dispatch_table_fingerprint);
            try addOptionalU64Len(total, ref.surface_profile_fingerprint);
            try addOptionalU64Len(total, ref.boundary_module_fingerprint);
            try addBytesLen(total, ref.metadata);
        }

        fn addOptionalU64Len(total: *usize, value: ?u64) !void {
            try addChecked(total, 1 + if (value != null) @as(usize, 8) else 0);
        }

        fn addOptionalU32Len(total: *usize, value: ?u32) !void {
            try addChecked(total, 1 + if (value != null) @as(usize, 4) else 0);
        }

        fn addImportSetLen(total: *usize) !void {
            try addChecked(total, 8 + 8 + 8 + 8 + 8 + 8);
            try addOptionalU64Len(total, null);
        }

        fn addImportRequirementLen(total: *usize, requirement: W.ImportRequirement) !void {
            try addChecked(total, 8);
            try addOptionalU64Len(total, requirement.target_ref_fingerprint);
            try addOptionalU64Len(total, requirement.world_value_table_fingerprint);
            try addChecked(total, 8 + 4);
            try addOptionalU64Len(total, requirement.world_port_ref_fingerprint);
            try addOptionalU64Len(total, requirement.source_effect_shape_ref_fingerprint);
            try addChecked(total, 8 + 8);
            try addOptionalU32Len(total, requirement.payload_value_table_id);
            try addOptionalU64Len(total, requirement.payload_value_ref_fingerprint);
            try addOptionalU32Len(total, requirement.response_value_table_id);
            try addOptionalU64Len(total, requirement.response_value_ref_fingerprint);
            try addChecked(total, 1 + 1);
            try addOptionalU64Len(total, requirement.replay_key_recipe_fingerprint);
            try addOptionalBytesLen(total, requirement.suggested_symbolic_name);
            try addChecked(total, 1);
            try addStringSliceLen(total, requirement.tags);
            try addBytesLen(total, requirement.metadata);
        }

        fn addExportSummaryLen(total: *usize, summary: W.Admission.ExportSummary) !void {
            try addChecked(total, 8 + 8);
            try addOptionalU64Len(total, summary.module_ref_fingerprint);
            try addChecked(total, 1);
            try addOptionalU64Len(total, summary.result_value_ref_fingerprint);
            try addChecked(total, 8 + 1);
            try addOptionalBytesLen(total, summary.target_label);
            try addChecked(total, 1);
            try addOptionalBytesLen(total, summary.loaded_execution_unsupported_reason);
        }

        fn addDispatchImageLen(total: *usize, image: DispatchImage) !void {
            try addChecked(total, 4 + 4 + 8 + 4);
            try addU64SliceLen(total, image.module_fingerprints);
            try addU64SliceLen(total, image.external_binding_fingerprints);
            try addU64SliceLen(total, image.residual_request_order);
            try addU64SliceLen(total, image.fabric_plan_fingerprints);
            try addU64SliceLen(total, image.route_ids);
            try addChecked(total, 8 + image.route_kinds.len);
            try addU32SliceLen(total, image.route_parent_world_port_ids);
            try addU64SliceLen(total, image.route_requirement_fingerprints);
            try addU64SliceLen(total, image.route_provider_module_fingerprints);
            try addPolicyLen(total);
            try addChecked(total, 8 + 8 + 8);
        }

        fn addExternalBindingSliceLen(total: *usize, bindings: []const ExternalBinding) !void {
            try addChecked(total, 8);
            for (bindings) |binding| try addExternalBindingLen(total, binding);
        }

        fn addExternalBindingLen(total: *usize, binding: ExternalBinding) !void {
            try addChecked(total, 8 + 8 + 4);
            try addOptionalU64Len(total, binding.world_port_ref_fingerprint);
            try addOptionalU32Len(total, binding.payload_value_table_id);
            try addOptionalU64Len(total, binding.payload_value_ref_fingerprint);
            try addOptionalU32Len(total, binding.response_value_table_id);
            try addOptionalU64Len(total, binding.response_value_ref_fingerprint);
            try addActuatorRefLen(total, binding.actuator_ref);
            try addDescriptorLen(total, binding.descriptor);
            try addChecked(total, 6 + 1);
            try addValuePolicyLen(total, binding.value_policy);
            try addOptionalU64Len(total, binding.supervision_rule_ref);
            try addOptionalU64Len(total, binding.authority_descriptor_ref);
            try addBytesLen(total, binding.label);
            try addBytesLen(total, binding.metadata);
        }

        fn addActuatorRefLen(total: *usize, ref: W.Actuation.Ref) !void {
            try addChecked(total, 4 + 4 + 8 + 1 + 1);
            try addBytesLen(total, ref.label);
            try addChecked(total, 4 + 6 + 8);
            try addOptionalU64Len(total, ref.authority_descriptor_fingerprint);
            try addOptionalU64Len(total, ref.protocol_descriptor_fingerprint);
            try addBytesLen(total, ref.metadata);
        }

        fn addDescriptorLen(total: *usize, descriptor: W.Actuation.Descriptor) !void {
            try addChecked(total, 4 + 4 + 8 + 8 + 8);
            try addOptionalU64Len(total, descriptor.target_ref_fingerprint);
            try addOptionalU32Len(total, descriptor.world_port_id);
            try addOptionalU64Len(total, descriptor.world_port_ref_fingerprint);
            try addOptionalU64Len(total, descriptor.source_effect_shape_ref_fingerprint);
            try addOptionalU32Len(total, descriptor.payload_value_ref);
            try addOptionalU32Len(total, descriptor.payload_value_table_id);
            try addOptionalU32Len(total, descriptor.response_value_ref);
            try addOptionalU32Len(total, descriptor.response_value_table_id);
            try addChecked(total, 4 + 6 + 1 + 1);
            try addValuePolicyLen(total, descriptor.value_policy);
            try addBytesLen(total, descriptor.label);
            try addBytesLen(total, descriptor.metadata);
        }

        fn addValuePolicyLen(total: *usize, policy: W.ValuePolicy) !void {
            _ = policy;
            try addChecked(total, 1 + 1 + 1 + 1);
            try addOptionalU64Len(total, null);
        }

        fn addPolicyLen(total: *usize) !void {
            try addChecked(total, 14 + 8 + 8 + 8 + 8 + 3);
        }

        fn addMemoryPlanLen(total: *usize) !void {
            try addChecked(total, 8 * 14);
        }

        fn addCompatibilityReportLen(total: *usize, report: CompatibilityReport) !void {
            try addChecked(total, 8 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 8 + 8 + 8);
            try addBytesLen(total, report.summary);
        }

        fn addCertificateLen(total: *usize) !void {
            try addChecked(total, 4 + 4 + 8 * 13);
        }

        fn addU64SliceLen(total: *usize, values: []const u64) !void {
            try addChecked(total, 8 + values.len * @sizeOf(u64));
        }

        fn addU32SliceLen(total: *usize, values: []const u32) !void {
            try addChecked(total, 8 + values.len * @sizeOf(u32));
        }

        fn writeRuntimeProfile(out: *std.ArrayList(u8), allocator: std.mem.Allocator, profile: RuntimeProfile) !void {
            try writeU64(out, allocator, profile.profile_fingerprint);
            try writeBool(out, allocator, profile.supports_loaded_execution);
            try writeBool(out, allocator, profile.supports_internal_providers);
            try writeBool(out, allocator, profile.supports_external_actuation);
            try writeCount(out, allocator, profile.max_modules);
            try writeCount(out, allocator, profile.max_provider_depth);
            try writeCount(out, allocator, profile.max_external_bindings);
            try writeCount(out, allocator, profile.max_module_bytes);
            try writeCount(out, allocator, profile.max_image_bytes);
            try writeCount(out, allocator, profile.max_command_bytes);
            try writeCount(out, allocator, profile.max_output_bytes);
            try writeCount(out, allocator, profile.max_linear_memory_pages);
            try writeBytes(out, allocator, profile.metadata);
        }

        fn readRuntimeProfile(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !RuntimeProfile {
            return .{
                .profile_fingerprint = try readU64(bytes, cursor),
                .supports_loaded_execution = try readBool(bytes, cursor),
                .supports_internal_providers = try readBool(bytes, cursor),
                .supports_external_actuation = try readBool(bytes, cursor),
                .max_modules = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_provider_depth = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_external_bindings = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_module_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_image_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_command_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_output_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_linear_memory_pages = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeModuleSet(out: *std.ArrayList(u8), allocator: std.mem.Allocator, set: ModuleSet) !void {
            try writeCount(out, allocator, set.modules.len);
            try writeU32(out, allocator, set.root_module_id);
            try writeU64(out, allocator, set.module_set_fingerprint);
            for (set.modules) |module| try writeModule(out, allocator, module);
        }

        fn readModuleSet(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !ModuleSet {
            const count = try readCount(bytes, cursor, limits.max_modules);
            const root_module_id = try readU32(bytes, cursor);
            const module_set_fingerprint = try readU64(bytes, cursor);
            const modules = try allocator.alloc(Module, count);
            var initialized: usize = 0;
            errdefer freeModuleSlice(allocator, modules[0..initialized]);
            while (initialized < count) : (initialized += 1) {
                modules[initialized] = try readModule(allocator, bytes, cursor, limits);
            }
            return .{
                .modules = modules,
                .root_module_id = root_module_id,
                .module_set_fingerprint = module_set_fingerprint,
            };
        }

        fn writeModule(out: *std.ArrayList(u8), allocator: std.mem.Allocator, module: Module) !void {
            try writeU32(out, allocator, module.module_id);
            try writeU8(out, allocator, @intFromEnum(module.role));
            try writeModuleRef(out, allocator, module.module_ref);
            try writeTargetRef(out, allocator, module.target_ref);
            try writeImportSet(out, allocator, module.import_set);
            try writeCount(out, allocator, module.imports.len);
            for (module.imports) |requirement| try writeImportRequirement(out, allocator, requirement);
            try writeExportSummary(out, allocator, module.export_summary);
            try writeU64(out, allocator, module.executable_plan_fingerprint);
            try writeU64(out, allocator, module.validation_report_fingerprint);
            try writeU64(out, allocator, module.compatibility_report_fingerprint);
            try writeBytes(out, allocator, module.canonical_bytes);
        }

        fn readModule(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !Module {
            const module_id = try readU32(bytes, cursor);
            const role = try readEnum(Module.Role, bytes, cursor);
            const module_ref = try readModuleRef(allocator, bytes, cursor, limits);
            errdefer freeModuleRefFields(allocator, module_ref);
            const target_ref = try readTargetRef(allocator, bytes, cursor, limits);
            errdefer freeTargetRefFields(allocator, target_ref);
            const import_set = try readImportSet(bytes, cursor);
            const import_count = try readCount(bytes, cursor, limits.max_imports_per_module);
            const imports = try allocator.alloc(W.ImportRequirement, import_count);
            var initialized: usize = 0;
            errdefer {
                for (imports[0..initialized]) |requirement| freeImportRequirementFields(allocator, requirement);
                allocator.free(imports);
            }
            while (initialized < import_count) : (initialized += 1) {
                imports[initialized] = try readImportRequirement(allocator, bytes, cursor, limits);
            }
            const export_summary = try readExportSummary(allocator, bytes, cursor, limits);
            errdefer freeExportSummaryFields(allocator, export_summary);
            const executable_plan_fingerprint = try readU64(bytes, cursor);
            const validation_report_fingerprint = try readU64(bytes, cursor);
            const compatibility_report_fingerprint = try readU64(bytes, cursor);
            const canonical_bytes = try readBytesOwned(allocator, bytes, cursor, limits.max_module_bytes);
            errdefer allocator.free(canonical_bytes);
            return .{
                .module_id = module_id,
                .role = role,
                .module_ref = module_ref,
                .target_ref = target_ref,
                .import_set = import_set,
                .imports = imports,
                .export_summary = export_summary,
                .executable_plan_fingerprint = executable_plan_fingerprint,
                .validation_report_fingerprint = validation_report_fingerprint,
                .compatibility_report_fingerprint = compatibility_report_fingerprint,
                .canonical_bytes = canonical_bytes,
            };
        }

        fn writeModuleRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: W.Admission.ModuleRef) !void {
            try writeU32(out, allocator, ref.format_version);
            try writeU32(out, allocator, ref.fingerprint_version);
            try writeU64(out, allocator, ref.module_ref_fingerprint);
            try writeU64(out, allocator, ref.boundary_module_fingerprint);
            try writeU8(out, allocator, @intFromEnum(ref.module_kind));
            try writeU64(out, allocator, ref.target_ref_fingerprint);
            try writeU64(out, allocator, ref.world_surface_fingerprint);
            try writeU64(out, allocator, ref.target_certificate_fingerprint);
            try writeOptionalU64(out, allocator, ref.residual_program_plan_hash);
            try writeOptionalU64(out, allocator, ref.import_surface_fingerprint);
            try writeOptionalU64(out, allocator, ref.export_surface_fingerprint);
            try writeOptionalU64(out, allocator, ref.module_graph_fingerprint);
            try writeU8(out, allocator, @intFromEnum(ref.normal_form_kind));
            try writeCount(out, allocator, ref.world_port_count);
            try writeOptionalU64(out, allocator, ref.world_port_table_fingerprint);
            try writeOptionalU64(out, allocator, ref.world_value_table_fingerprint);
            try writeOptionalU64(out, allocator, ref.world_dispatch_table_fingerprint);
            try writeOptionalBytes(out, allocator, ref.label);
            try writeBytes(out, allocator, ref.metadata);
        }

        fn readModuleRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.Admission.ModuleRef {
            return .{
                .format_version = try readU32(bytes, cursor),
                .fingerprint_version = try readU32(bytes, cursor),
                .module_ref_fingerprint = try readU64(bytes, cursor),
                .boundary_module_fingerprint = try readU64(bytes, cursor),
                .module_kind = try readEnum(W.Admission.BoundaryModuleKind, bytes, cursor),
                .target_ref_fingerprint = try readU64(bytes, cursor),
                .world_surface_fingerprint = try readU64(bytes, cursor),
                .target_certificate_fingerprint = try readU64(bytes, cursor),
                .residual_program_plan_hash = try readOptionalU64(bytes, cursor),
                .import_surface_fingerprint = try readOptionalU64(bytes, cursor),
                .export_surface_fingerprint = try readOptionalU64(bytes, cursor),
                .module_graph_fingerprint = try readOptionalU64(bytes, cursor),
                .normal_form_kind = try readEnum(W.NormalFormKind, bytes, cursor),
                .world_port_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .world_port_table_fingerprint = try readOptionalU64(bytes, cursor),
                .world_value_table_fingerprint = try readOptionalU64(bytes, cursor),
                .world_dispatch_table_fingerprint = try readOptionalU64(bytes, cursor),
                .label = try readOptionalBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
                .metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeTargetRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: W.TargetRef) !void {
            try writeU32(out, allocator, ref.format_version);
            try writeU32(out, allocator, ref.fingerprint_version);
            try writeU64(out, allocator, ref.target_ref_fingerprint);
            try writeOptionalBytes(out, allocator, ref.target_label);
            try writeU64(out, allocator, ref.world_surface_fingerprint);
            try writeOptionalU64(out, allocator, ref.world_surface_replay_scope_fingerprint);
            try writeU64(out, allocator, ref.target_certificate_fingerprint);
            try writeOptionalU64(out, allocator, ref.residual_program_plan_hash);
            try writeU8(out, allocator, @intFromEnum(ref.normal_form_kind));
            try writeOptionalU64(out, allocator, ref.world_port_table_fingerprint);
            try writeOptionalU64(out, allocator, ref.world_value_table_fingerprint);
            try writeOptionalU64(out, allocator, ref.world_dispatch_table_fingerprint);
            try writeOptionalU64(out, allocator, ref.surface_profile_fingerprint);
            try writeOptionalU64(out, allocator, ref.boundary_module_fingerprint);
            try writeBytes(out, allocator, ref.metadata);
        }

        fn readTargetRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.TargetRef {
            return .{
                .format_version = try readU32(bytes, cursor),
                .fingerprint_version = try readU32(bytes, cursor),
                .target_ref_fingerprint = try readU64(bytes, cursor),
                .target_label = try readOptionalBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
                .world_surface_fingerprint = try readU64(bytes, cursor),
                .world_surface_replay_scope_fingerprint = try readOptionalU64(bytes, cursor),
                .target_certificate_fingerprint = try readU64(bytes, cursor),
                .residual_program_plan_hash = try readOptionalU64(bytes, cursor),
                .normal_form_kind = try readEnum(W.NormalFormKind, bytes, cursor),
                .world_port_table_fingerprint = try readOptionalU64(bytes, cursor),
                .world_value_table_fingerprint = try readOptionalU64(bytes, cursor),
                .world_dispatch_table_fingerprint = try readOptionalU64(bytes, cursor),
                .surface_profile_fingerprint = try readOptionalU64(bytes, cursor),
                .boundary_module_fingerprint = try readOptionalU64(bytes, cursor),
                .metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeImportSet(out: *std.ArrayList(u8), allocator: std.mem.Allocator, set: W.ImportSet) !void {
            try writeU64(out, allocator, set.import_set_fingerprint);
            try writeU64(out, allocator, set.target_ref_fingerprint);
            try writeCount(out, allocator, set.required_count);
            try writeCount(out, allocator, set.optional_count);
            try writeCount(out, allocator, set.world_port_count);
            try writeCount(out, allocator, set.value_table_entry_count);
            try writeOptionalU64(out, allocator, set.surface_profile_fingerprint);
        }

        fn readImportSet(bytes: []const u8, cursor: *usize) !W.ImportSet {
            return .{
                .import_set_fingerprint = try readU64(bytes, cursor),
                .target_ref_fingerprint = try readU64(bytes, cursor),
                .required_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .optional_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .world_port_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .value_table_entry_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .surface_profile_fingerprint = try readOptionalU64(bytes, cursor),
            };
        }

        fn writeImportRequirement(out: *std.ArrayList(u8), allocator: std.mem.Allocator, requirement: W.ImportRequirement) !void {
            try writeU64(out, allocator, requirement.requirement_fingerprint);
            try writeOptionalU64(out, allocator, requirement.target_ref_fingerprint);
            try writeOptionalU64(out, allocator, requirement.world_value_table_fingerprint);
            try writeU64(out, allocator, requirement.world_surface_fingerprint);
            try writeU32(out, allocator, requirement.world_port_id);
            try writeOptionalU64(out, allocator, requirement.world_port_ref_fingerprint);
            try writeOptionalU64(out, allocator, requirement.source_effect_shape_ref_fingerprint);
            try writeCount(out, allocator, requirement.residual_site_index);
            try writeU64(out, allocator, requirement.residual_site_fingerprint);
            try writeOptionalU32(out, allocator, requirement.payload_value_table_id);
            try writeOptionalU64(out, allocator, requirement.payload_value_ref_fingerprint);
            try writeOptionalU32(out, allocator, requirement.response_value_table_id);
            try writeOptionalU64(out, allocator, requirement.response_value_ref_fingerprint);
            try writeU8(out, allocator, @intFromEnum(requirement.mode));
            try writeU8(out, allocator, @intFromEnum(requirement.allowed_response_kinds));
            try writeOptionalU64(out, allocator, requirement.replay_key_recipe_fingerprint);
            try writeOptionalBytes(out, allocator, requirement.suggested_symbolic_name);
            try writeBool(out, allocator, requirement.required);
            try writeStringSlice(out, allocator, requirement.tags);
            try writeBytes(out, allocator, requirement.metadata);
        }

        fn readImportRequirement(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.ImportRequirement {
            const requirement_fingerprint = try readU64(bytes, cursor);
            const target_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const world_value_table_fingerprint = try readOptionalU64(bytes, cursor);
            const world_surface_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const world_port_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const source_effect_shape_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const residual_site_index = try readCount(bytes, cursor, std.math.maxInt(usize));
            const residual_site_fingerprint = try readU64(bytes, cursor);
            const payload_value_table_id = try readOptionalU32(bytes, cursor);
            const payload_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const response_value_table_id = try readOptionalU32(bytes, cursor);
            const response_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const mode = try readEnum(W.BindingModePolicy, bytes, cursor);
            const allowed_response_kinds = try readEnum(W.ImportRequirement.ResponseKindMask, bytes, cursor);
            const replay_key_recipe_fingerprint = try readOptionalU64(bytes, cursor);
            const suggested_symbolic_name = try readOptionalBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes);
            errdefer if (suggested_symbolic_name) |symbol| allocator.free(@constCast(symbol));
            const required = try readBool(bytes, cursor);
            const tags = try readStringSliceOwned(allocator, bytes, cursor, limits.max_imports_per_module, limits.max_metadata_bytes);
            errdefer freeStringSlice(allocator, tags);
            const metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes);
            errdefer allocator.free(metadata);
            return .{
                .requirement_fingerprint = requirement_fingerprint,
                .target_ref_fingerprint = target_ref_fingerprint,
                .world_value_table_fingerprint = world_value_table_fingerprint,
                .world_surface_fingerprint = world_surface_fingerprint,
                .world_port_id = world_port_id,
                .world_port_ref_fingerprint = world_port_ref_fingerprint,
                .source_effect_shape_ref_fingerprint = source_effect_shape_ref_fingerprint,
                .residual_site_index = residual_site_index,
                .residual_site_fingerprint = residual_site_fingerprint,
                .payload_value_table_id = payload_value_table_id,
                .payload_value_ref_fingerprint = payload_value_ref_fingerprint,
                .response_value_table_id = response_value_table_id,
                .response_value_ref_fingerprint = response_value_ref_fingerprint,
                .mode = mode,
                .allowed_response_kinds = allowed_response_kinds,
                .replay_key_recipe_fingerprint = replay_key_recipe_fingerprint,
                .suggested_symbolic_name = suggested_symbolic_name,
                .required = required,
                .tags = tags,
                .metadata = metadata,
            };
        }

        fn writeExportSummary(out: *std.ArrayList(u8), allocator: std.mem.Allocator, summary: W.Admission.ExportSummary) !void {
            try writeU64(out, allocator, summary.export_summary_fingerprint);
            try writeU64(out, allocator, summary.target_ref_fingerprint);
            try writeOptionalU64(out, allocator, summary.module_ref_fingerprint);
            try writeBool(out, allocator, summary.main_export_present);
            try writeOptionalU64(out, allocator, summary.result_value_ref_fingerprint);
            try writeCount(out, allocator, summary.argument_value_ref_count);
            try writeU8(out, allocator, @intFromEnum(summary.normal_form_kind));
            try writeOptionalBytes(out, allocator, summary.target_label);
            try writeBool(out, allocator, summary.loaded_execution_supported);
            try writeOptionalBytes(out, allocator, summary.loaded_execution_unsupported_reason);
        }

        fn readExportSummary(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.Admission.ExportSummary {
            return .{
                .export_summary_fingerprint = try readU64(bytes, cursor),
                .target_ref_fingerprint = try readU64(bytes, cursor),
                .module_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .main_export_present = try readBool(bytes, cursor),
                .result_value_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .argument_value_ref_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .normal_form_kind = try readEnum(W.NormalFormKind, bytes, cursor),
                .target_label = try readOptionalBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
                .loaded_execution_supported = try readBool(bytes, cursor),
                .loaded_execution_unsupported_reason = try readOptionalBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeDispatchImage(out: *std.ArrayList(u8), allocator: std.mem.Allocator, image: DispatchImage) !void {
            try writeU32(out, allocator, image.format_version);
            try writeU32(out, allocator, image.fingerprint_version);
            try writeU64(out, allocator, image.dispatch_fingerprint);
            try writeU32(out, allocator, image.root_module_id);
            try writeU64Slice(out, allocator, image.module_fingerprints);
            try writeU64Slice(out, allocator, image.external_binding_fingerprints);
            try writeU64Slice(out, allocator, image.residual_request_order);
            try writeU64Slice(out, allocator, image.fabric_plan_fingerprints);
            try writeU64Slice(out, allocator, image.route_ids);
            try writeCount(out, allocator, image.route_kinds.len);
            for (image.route_kinds) |kind| try writeU8(out, allocator, @intFromEnum(kind));
            try writeU32Slice(out, allocator, image.route_parent_world_port_ids);
            try writeU64Slice(out, allocator, image.route_requirement_fingerprints);
            try writeU64Slice(out, allocator, image.route_provider_module_fingerprints);
            try writePolicy(out, allocator, image.linker_policy);
            try writeU64(out, allocator, image.link_plan_fingerprint);
            try writeU64(out, allocator, image.linker_certificate_fingerprint);
            try writeU64(out, allocator, image.assembly_fingerprint);
        }

        fn readDispatchImage(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !DispatchImage {
            const format_version = try readU32(bytes, cursor);
            const fingerprint_version = try readU32(bytes, cursor);
            const dispatch_fingerprint = try readU64(bytes, cursor);
            const root_module_id = try readU32(bytes, cursor);
            const module_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(module_fingerprints);
            const external_binding_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(external_binding_fingerprints);
            const residual_request_order = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(residual_request_order);
            const fabric_plan_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(fabric_plan_fingerprints);
            const route_ids = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(route_ids);
            const route_kind_count = try readCount(bytes, cursor, limits.max_dispatch_entries);
            const route_kinds = try allocator.alloc(W.Fabric.RouteKind, route_kind_count);
            var initialized_route_kinds: usize = 0;
            errdefer allocator.free(route_kinds);
            while (initialized_route_kinds < route_kind_count) : (initialized_route_kinds += 1) {
                route_kinds[initialized_route_kinds] = try readEnum(W.Fabric.RouteKind, bytes, cursor);
            }
            const route_parent_world_port_ids = try readU32SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(route_parent_world_port_ids);
            const route_requirement_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(route_requirement_fingerprints);
            const route_provider_module_fingerprints = try readU64SliceOwned(allocator, bytes, cursor, limits.max_dispatch_entries);
            errdefer allocator.free(route_provider_module_fingerprints);
            const linker_policy = try readPolicy(bytes, cursor);
            return .{
                .format_version = format_version,
                .fingerprint_version = fingerprint_version,
                .dispatch_fingerprint = dispatch_fingerprint,
                .root_module_id = root_module_id,
                .module_fingerprints = module_fingerprints,
                .external_binding_fingerprints = external_binding_fingerprints,
                .residual_request_order = residual_request_order,
                .fabric_plan_fingerprints = fabric_plan_fingerprints,
                .route_ids = route_ids,
                .route_kinds = route_kinds,
                .route_parent_world_port_ids = route_parent_world_port_ids,
                .route_requirement_fingerprints = route_requirement_fingerprints,
                .route_provider_module_fingerprints = route_provider_module_fingerprints,
                .linker_policy = linker_policy,
                .link_plan_fingerprint = try readU64(bytes, cursor),
                .linker_certificate_fingerprint = try readU64(bytes, cursor),
                .assembly_fingerprint = try readU64(bytes, cursor),
            };
        }

        fn writeExternalBindingSlice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bindings: []const ExternalBinding) !void {
            try writeCount(out, allocator, bindings.len);
            for (bindings) |binding| try writeExternalBinding(out, allocator, binding);
        }

        fn readExternalBindingSlice(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) ![]ExternalBinding {
            const count = try readCount(bytes, cursor, limits.max_external_bindings);
            const bindings = try allocator.alloc(ExternalBinding, count);
            var initialized: usize = 0;
            errdefer freeExternalBindingSlice(allocator, bindings[0..initialized]);
            while (initialized < count) : (initialized += 1) {
                bindings[initialized] = try readExternalBinding(allocator, bytes, cursor, limits);
            }
            return bindings;
        }

        fn writeExternalBinding(out: *std.ArrayList(u8), allocator: std.mem.Allocator, binding: ExternalBinding) !void {
            try writeU64(out, allocator, binding.binding_fingerprint);
            try writeU64(out, allocator, binding.parent_module_fingerprint);
            try writeU32(out, allocator, binding.world_port_id);
            try writeOptionalU64(out, allocator, binding.world_port_ref_fingerprint);
            try writeOptionalU32(out, allocator, binding.payload_value_table_id);
            try writeOptionalU64(out, allocator, binding.payload_value_ref_fingerprint);
            try writeOptionalU32(out, allocator, binding.response_value_table_id);
            try writeOptionalU64(out, allocator, binding.response_value_ref_fingerprint);
            try writeActuatorRef(out, allocator, binding.actuator_ref);
            try writeDescriptor(out, allocator, binding.descriptor);
            try writeResponseStatusSet(out, allocator, binding.allowed_response_statuses);
            try writeU8(out, allocator, @intFromEnum(binding.actuation_class));
            try writeValuePolicy(out, allocator, binding.value_policy);
            try writeOptionalU64(out, allocator, binding.supervision_rule_ref);
            try writeOptionalU64(out, allocator, binding.authority_descriptor_ref);
            try writeBytes(out, allocator, binding.label);
            try writeBytes(out, allocator, binding.metadata);
        }

        fn readExternalBinding(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !ExternalBinding {
            const binding_fingerprint = try readU64(bytes, cursor);
            const parent_module_fingerprint = try readU64(bytes, cursor);
            const world_port_id = try readU32(bytes, cursor);
            const world_port_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const payload_value_table_id = try readOptionalU32(bytes, cursor);
            const payload_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const response_value_table_id = try readOptionalU32(bytes, cursor);
            const response_value_ref_fingerprint = try readOptionalU64(bytes, cursor);
            const actuator_ref = try readActuatorRef(allocator, bytes, cursor, limits);
            errdefer freeActuatorRefFields(allocator, actuator_ref);
            const descriptor = try readDescriptor(allocator, bytes, cursor, limits);
            errdefer freeDescriptorFields(allocator, descriptor);
            const allowed_response_statuses = try readResponseStatusSet(bytes, cursor);
            const actuation_class = try readEnum(W.Actuation.Class, bytes, cursor);
            const value_policy = try readValuePolicy(bytes, cursor);
            const supervision_rule_ref = try readOptionalU64(bytes, cursor);
            const authority_descriptor_ref = try readOptionalU64(bytes, cursor);
            const label = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes);
            errdefer allocator.free(label);
            const metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes);
            errdefer allocator.free(metadata);
            return .{
                .binding_fingerprint = binding_fingerprint,
                .parent_module_fingerprint = parent_module_fingerprint,
                .world_port_id = world_port_id,
                .world_port_ref_fingerprint = world_port_ref_fingerprint,
                .payload_value_table_id = payload_value_table_id,
                .payload_value_ref_fingerprint = payload_value_ref_fingerprint,
                .response_value_table_id = response_value_table_id,
                .response_value_ref_fingerprint = response_value_ref_fingerprint,
                .actuator_ref = actuator_ref,
                .descriptor = descriptor,
                .allowed_response_statuses = allowed_response_statuses,
                .actuation_class = actuation_class,
                .value_policy = value_policy,
                .supervision_rule_ref = supervision_rule_ref,
                .authority_descriptor_ref = authority_descriptor_ref,
                .label = label,
                .metadata = metadata,
            };
        }

        fn writeActuatorRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: W.Actuation.Ref) !void {
            try writeU32(out, allocator, ref.format_version);
            try writeU32(out, allocator, ref.fingerprint_version);
            try writeU64(out, allocator, ref.ref_fingerprint);
            try writeU8(out, allocator, @intFromEnum(ref.kind));
            try writeU8(out, allocator, @intFromEnum(ref.class));
            try writeBytes(out, allocator, ref.label);
            try writeModeSet(out, allocator, ref.supported_modes);
            try writeResponseStatusSet(out, allocator, ref.supported_response_statuses);
            try writeU64(out, allocator, ref.value_policy_fingerprint);
            try writeOptionalU64(out, allocator, ref.authority_descriptor_fingerprint);
            try writeOptionalU64(out, allocator, ref.protocol_descriptor_fingerprint);
            try writeBytes(out, allocator, ref.metadata);
        }

        fn readActuatorRef(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.Actuation.Ref {
            return .{
                .format_version = try readU32(bytes, cursor),
                .fingerprint_version = try readU32(bytes, cursor),
                .ref_fingerprint = try readU64(bytes, cursor),
                .kind = try readEnum(W.Actuation.Kind, bytes, cursor),
                .class = try readEnum(W.Actuation.Class, bytes, cursor),
                .label = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
                .supported_modes = try readModeSet(bytes, cursor),
                .supported_response_statuses = try readResponseStatusSet(bytes, cursor),
                .value_policy_fingerprint = try readU64(bytes, cursor),
                .authority_descriptor_fingerprint = try readOptionalU64(bytes, cursor),
                .protocol_descriptor_fingerprint = try readOptionalU64(bytes, cursor),
                .metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeDescriptor(out: *std.ArrayList(u8), allocator: std.mem.Allocator, descriptor: W.Actuation.Descriptor) !void {
            try writeU32(out, allocator, descriptor.format_version);
            try writeU32(out, allocator, descriptor.fingerprint_version);
            try writeU64(out, allocator, descriptor.descriptor_fingerprint);
            try writeU64(out, allocator, descriptor.actuator_ref_fingerprint);
            try writeU64(out, allocator, descriptor.world_surface_fingerprint);
            try writeOptionalU64(out, allocator, descriptor.target_ref_fingerprint);
            try writeOptionalU32(out, allocator, descriptor.world_port_id);
            try writeOptionalU64(out, allocator, descriptor.world_port_ref_fingerprint);
            try writeOptionalU64(out, allocator, descriptor.source_effect_shape_ref_fingerprint);
            try writeOptionalU32(out, allocator, descriptor.payload_value_ref);
            try writeOptionalU32(out, allocator, descriptor.payload_value_table_id);
            try writeOptionalU32(out, allocator, descriptor.response_value_ref);
            try writeOptionalU32(out, allocator, descriptor.response_value_table_id);
            try writeModeSet(out, allocator, descriptor.supported_modes);
            try writeResponseStatusSet(out, allocator, descriptor.allowed_response_kinds);
            try writeU8(out, allocator, @intFromEnum(descriptor.kind));
            try writeU8(out, allocator, @intFromEnum(descriptor.class));
            try writeValuePolicy(out, allocator, descriptor.value_policy);
            try writeBytes(out, allocator, descriptor.label);
            try writeBytes(out, allocator, descriptor.metadata);
        }

        fn readDescriptor(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !W.Actuation.Descriptor {
            return .{
                .format_version = try readU32(bytes, cursor),
                .fingerprint_version = try readU32(bytes, cursor),
                .descriptor_fingerprint = try readU64(bytes, cursor),
                .actuator_ref_fingerprint = try readU64(bytes, cursor),
                .world_surface_fingerprint = try readU64(bytes, cursor),
                .target_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .world_port_id = try readOptionalU32(bytes, cursor),
                .world_port_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .source_effect_shape_ref_fingerprint = try readOptionalU64(bytes, cursor),
                .payload_value_ref = try readOptionalU32(bytes, cursor),
                .payload_value_table_id = try readOptionalU32(bytes, cursor),
                .response_value_ref = try readOptionalU32(bytes, cursor),
                .response_value_table_id = try readOptionalU32(bytes, cursor),
                .supported_modes = try readModeSet(bytes, cursor),
                .allowed_response_kinds = try readResponseStatusSet(bytes, cursor),
                .kind = try readEnum(W.Actuation.Kind, bytes, cursor),
                .class = try readEnum(W.Actuation.Class, bytes, cursor),
                .value_policy = try readValuePolicy(bytes, cursor),
                .label = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
                .metadata = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeMemoryPlan(out: *std.ArrayList(u8), allocator: std.mem.Allocator, plan: MemoryPlan) !void {
            try writeU64(out, allocator, plan.memory_plan_fingerprint);
            try writeCount(out, allocator, plan.decoded_module_bytes);
            try writeCount(out, allocator, plan.dispatch_table_entries);
            try writeCount(out, allocator, plan.schema_table_entries);
            try writeCount(out, allocator, plan.max_session_frames);
            try writeCount(out, allocator, plan.max_runspace_slots);
            try writeCount(out, allocator, plan.max_mailbox_entries);
            try writeCount(out, allocator, plan.max_provider_runs);
            try writeCount(out, allocator, plan.max_host_requests_per_turn);
            try writeCount(out, allocator, plan.max_command_bytes);
            try writeCount(out, allocator, plan.max_output_bytes);
            try writeCount(out, allocator, plan.max_capsule_bytes);
            try writeCount(out, allocator, plan.max_archive_append_bytes);
            try writeCount(out, allocator, plan.max_linear_memory_pages);
        }

        fn readMemoryPlan(bytes: []const u8, cursor: *usize) !MemoryPlan {
            return .{
                .memory_plan_fingerprint = try readU64(bytes, cursor),
                .decoded_module_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .dispatch_table_entries = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .schema_table_entries = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_session_frames = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_runspace_slots = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_mailbox_entries = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_provider_runs = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_host_requests_per_turn = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_command_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_output_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_capsule_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_archive_append_bytes = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_linear_memory_pages = try readCount(bytes, cursor, std.math.maxInt(usize)),
            };
        }

        fn writeCompatibilityReport(out: *std.ArrayList(u8), allocator: std.mem.Allocator, report: CompatibilityReport) !void {
            try writeU64(out, allocator, report.report_fingerprint);
            try writeBool(out, allocator, report.compatible);
            try writeBool(out, allocator, report.image_format_compatible);
            try writeBool(out, allocator, report.boundary_module_compatible);
            try writeBool(out, allocator, report.executable_plan_compatible);
            try writeBool(out, allocator, report.instruction_feature_compatible);
            try writeBool(out, allocator, report.value_codec_compatible);
            try writeBool(out, allocator, report.profile_compatible);
            try writeBool(out, allocator, report.capacity_compatible);
            try writeBool(out, allocator, report.memory_compatible);
            try writeCount(out, allocator, report.missing_optional_features);
            try writeCount(out, allocator, report.hard_blockers);
            try writeCount(out, allocator, report.warnings);
            try writeBytes(out, allocator, report.summary);
        }

        fn readCompatibilityReport(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, limits: Image.DecodeLimits) !CompatibilityReport {
            return .{
                .report_fingerprint = try readU64(bytes, cursor),
                .compatible = try readBool(bytes, cursor),
                .image_format_compatible = try readBool(bytes, cursor),
                .boundary_module_compatible = try readBool(bytes, cursor),
                .executable_plan_compatible = try readBool(bytes, cursor),
                .instruction_feature_compatible = try readBool(bytes, cursor),
                .value_codec_compatible = try readBool(bytes, cursor),
                .profile_compatible = try readBool(bytes, cursor),
                .capacity_compatible = try readBool(bytes, cursor),
                .memory_compatible = try readBool(bytes, cursor),
                .missing_optional_features = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .hard_blockers = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .warnings = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .summary = try readBytesOwned(allocator, bytes, cursor, limits.max_metadata_bytes),
            };
        }

        fn writeCertificate(out: *std.ArrayList(u8), allocator: std.mem.Allocator, cert: Certificate) !void {
            try writeU32(out, allocator, cert.format_version);
            try writeU32(out, allocator, cert.fingerprint_version);
            try writeU64(out, allocator, cert.certificate_fingerprint);
            try writeU64(out, allocator, cert.image_fingerprint);
            try writeU64(out, allocator, cert.module_set_fingerprint);
            try writeU64(out, allocator, cert.runtime_profile_fingerprint);
            try writeU64(out, allocator, cert.dispatch_fingerprint);
            try writeU64(out, allocator, cert.memory_plan_fingerprint);
            try writeU64(out, allocator, cert.compatibility_report_fingerprint);
            try writeU64(out, allocator, cert.link_plan_fingerprint);
            try writeU64(out, allocator, cert.linker_certificate_fingerprint);
            try writeU64(out, allocator, cert.assembly_fingerprint);
            try writeCount(out, allocator, cert.module_count);
            try writeCount(out, allocator, cert.residual_external_binding_count);
            try writeCount(out, allocator, cert.blocker_count);
            try writeCount(out, allocator, cert.warning_count);
        }

        fn readCertificate(bytes: []const u8, cursor: *usize) !Certificate {
            return .{
                .format_version = try readU32(bytes, cursor),
                .fingerprint_version = try readU32(bytes, cursor),
                .certificate_fingerprint = try readU64(bytes, cursor),
                .image_fingerprint = try readU64(bytes, cursor),
                .module_set_fingerprint = try readU64(bytes, cursor),
                .runtime_profile_fingerprint = try readU64(bytes, cursor),
                .dispatch_fingerprint = try readU64(bytes, cursor),
                .memory_plan_fingerprint = try readU64(bytes, cursor),
                .compatibility_report_fingerprint = try readU64(bytes, cursor),
                .link_plan_fingerprint = try readU64(bytes, cursor),
                .linker_certificate_fingerprint = try readU64(bytes, cursor),
                .assembly_fingerprint = try readU64(bytes, cursor),
                .module_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .residual_external_binding_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .blocker_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .warning_count = try readCount(bytes, cursor, std.math.maxInt(usize)),
            };
        }

        fn writePolicy(out: *std.ArrayList(u8), allocator: std.mem.Allocator, policy: W.Linker.Policy) !void {
            try writeBool(out, allocator, policy.require_closed_graph);
            try writeBool(out, allocator, policy.allow_external_environment_ports);
            try writeBool(out, allocator, policy.allow_adapter_fallback);
            try writeBool(out, allocator, policy.allow_replay_routes);
            try writeBool(out, allocator, policy.allow_guest_routes);
            try writeBool(out, allocator, policy.allow_reject_routes);
            try writeBool(out, allocator, policy.allow_ambiguous_matches);
            try writeBool(out, allocator, policy.require_explicit_hint_for_ambiguous_match);
            try writeBool(out, allocator, policy.require_exact_value_refs);
            try writeBool(out, allocator, policy.allow_same_schema_compatible_refs);
            try writeBool(out, allocator, policy.reject_cross_type_conversion);
            try writeBool(out, allocator, policy.reject_same_target_cycle);
            try writeBool(out, allocator, policy.reject_same_module_cycle);
            try writeBool(out, allocator, policy.reject_recursive_route);
            try writeCount(out, allocator, policy.max_link_depth);
            try writeCount(out, allocator, policy.max_provider_runs);
            try writeCount(out, allocator, policy.max_candidates_per_import);
            try writeCount(out, allocator, policy.max_unresolved_imports);
            try writeBool(out, allocator, policy.require_supervision_compatible_routes);
            try writeBool(out, allocator, policy.require_guest_conformance_for_guest_routes);
            try writeBool(out, allocator, policy.require_admission_for_provider_targets);
        }

        fn readPolicy(bytes: []const u8, cursor: *usize) !W.Linker.Policy {
            return .{
                .require_closed_graph = try readBool(bytes, cursor),
                .allow_external_environment_ports = try readBool(bytes, cursor),
                .allow_adapter_fallback = try readBool(bytes, cursor),
                .allow_replay_routes = try readBool(bytes, cursor),
                .allow_guest_routes = try readBool(bytes, cursor),
                .allow_reject_routes = try readBool(bytes, cursor),
                .allow_ambiguous_matches = try readBool(bytes, cursor),
                .require_explicit_hint_for_ambiguous_match = try readBool(bytes, cursor),
                .require_exact_value_refs = try readBool(bytes, cursor),
                .allow_same_schema_compatible_refs = try readBool(bytes, cursor),
                .reject_cross_type_conversion = try readBool(bytes, cursor),
                .reject_same_target_cycle = try readBool(bytes, cursor),
                .reject_same_module_cycle = try readBool(bytes, cursor),
                .reject_recursive_route = try readBool(bytes, cursor),
                .max_link_depth = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_provider_runs = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_candidates_per_import = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .max_unresolved_imports = try readCount(bytes, cursor, std.math.maxInt(usize)),
                .require_supervision_compatible_routes = try readBool(bytes, cursor),
                .require_guest_conformance_for_guest_routes = try readBool(bytes, cursor),
                .require_admission_for_provider_targets = try readBool(bytes, cursor),
            };
        }

        fn writeValuePolicy(out: *std.ArrayList(u8), allocator: std.mem.Allocator, policy: W.ValuePolicy) !void {
            try writeBool(out, allocator, policy.require_portable_values);
            try writeBool(out, allocator, policy.allow_native_only_values);
            try writeBool(out, allocator, policy.require_response_images_for_replay);
            try writeBool(out, allocator, policy.allow_diagnostic_type_labels);
            try writeOptionalCount(out, allocator, policy.max_value_image_bytes);
        }

        fn readValuePolicy(bytes: []const u8, cursor: *usize) !W.ValuePolicy {
            return .{
                .require_portable_values = try readBool(bytes, cursor),
                .allow_native_only_values = try readBool(bytes, cursor),
                .require_response_images_for_replay = try readBool(bytes, cursor),
                .allow_diagnostic_type_labels = try readBool(bytes, cursor),
                .max_value_image_bytes = try readOptionalCount(bytes, cursor),
            };
        }

        fn writeModeSet(out: *std.ArrayList(u8), allocator: std.mem.Allocator, modes: W.Actuation.ModeSet) !void {
            try writeBool(out, allocator, modes.fresh);
            try writeBool(out, allocator, modes.replay);
            try writeBool(out, allocator, modes.verify);
            try writeBool(out, allocator, modes.audit);
        }

        fn readModeSet(bytes: []const u8, cursor: *usize) !W.Actuation.ModeSet {
            return .{
                .fresh = try readBool(bytes, cursor),
                .replay = try readBool(bytes, cursor),
                .verify = try readBool(bytes, cursor),
                .audit = try readBool(bytes, cursor),
            };
        }

        fn writeResponseStatusSet(out: *std.ArrayList(u8), allocator: std.mem.Allocator, statuses: W.Actuation.ResponseStatusSet) !void {
            try writeBool(out, allocator, statuses.responded);
            try writeBool(out, allocator, statuses.rejected);
            try writeBool(out, allocator, statuses.failed);
            try writeBool(out, allocator, statuses.pending);
            try writeBool(out, allocator, statuses.deferred);
            try writeBool(out, allocator, statuses.cancelled);
        }

        fn readResponseStatusSet(bytes: []const u8, cursor: *usize) !W.Actuation.ResponseStatusSet {
            return .{
                .responded = try readBool(bytes, cursor),
                .rejected = try readBool(bytes, cursor),
                .failed = try readBool(bytes, cursor),
                .pending = try readBool(bytes, cursor),
                .deferred = try readBool(bytes, cursor),
                .cancelled = try readBool(bytes, cursor),
            };
        }

        fn writeU64Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u64) !void {
            try writeCount(out, allocator, values.len);
            for (values) |value| try writeU64(out, allocator, value);
        }

        fn writeU32Slice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const u32) !void {
            try writeCount(out, allocator, values.len);
            for (values) |value| try writeU32(out, allocator, value);
        }

        fn readU64SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_count: usize) ![]u64 {
            const count = try readCount(bytes, cursor, max_count);
            const values = try allocator.alloc(u64, count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try readU64(bytes, cursor);
            return values;
        }

        fn readU32SliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_count: usize) ![]u32 {
            const count = try readCount(bytes, cursor, max_count);
            const values = try allocator.alloc(u32, count);
            errdefer allocator.free(values);
            for (values) |*value| value.* = try readU32(bytes, cursor);
            return values;
        }

        fn writeStringSlice(out: *std.ArrayList(u8), allocator: std.mem.Allocator, values: []const []const u8) !void {
            try writeCount(out, allocator, values.len);
            for (values) |value| try writeBytes(out, allocator, value);
        }

        fn readStringSliceOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_count: usize, max_bytes: usize) ![][]const u8 {
            const count = try readCount(bytes, cursor, max_count);
            const values = try allocator.alloc([]const u8, count);
            var initialized: usize = 0;
            errdefer {
                for (values[0..initialized]) |value| allocator.free(@constCast(value));
                allocator.free(values);
            }
            while (initialized < count) : (initialized += 1) {
                values[initialized] = try readBytesOwned(allocator, bytes, cursor, max_bytes);
            }
            return values;
        }

        fn cloneOptionalBytes(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
            if (value) |bytes| return try allocator.dupe(u8, bytes);
            return null;
        }

        fn cloneStringSlice(allocator: std.mem.Allocator, values: []const []const u8) ![][]const u8 {
            const cloned = try allocator.alloc([]const u8, values.len);
            var initialized: usize = 0;
            errdefer {
                for (cloned[0..initialized]) |value| allocator.free(@constCast(value));
                allocator.free(cloned);
            }
            while (initialized < values.len) : (initialized += 1) {
                cloned[initialized] = try allocator.dupe(u8, values[initialized]);
            }
            return cloned;
        }

        fn freeStringSlice(allocator: std.mem.Allocator, values: []const []const u8) void {
            for (values) |value| allocator.free(@constCast(value));
            allocator.free(values);
        }

        fn freeModuleRefFields(allocator: std.mem.Allocator, ref: W.Admission.ModuleRef) void {
            if (ref.label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(ref.metadata));
        }

        fn freeTargetRefFields(allocator: std.mem.Allocator, ref: W.TargetRef) void {
            if (ref.target_label) |label| allocator.free(@constCast(label));
            allocator.free(@constCast(ref.metadata));
        }

        fn freeImportRequirementFields(allocator: std.mem.Allocator, requirement: W.ImportRequirement) void {
            if (requirement.suggested_symbolic_name) |symbol| allocator.free(@constCast(symbol));
            freeStringSlice(allocator, requirement.tags);
            allocator.free(@constCast(requirement.metadata));
        }

        fn freeExportSummaryFields(allocator: std.mem.Allocator, summary: W.Admission.ExportSummary) void {
            if (summary.target_label) |label| allocator.free(@constCast(label));
            if (summary.loaded_execution_unsupported_reason) |reason| allocator.free(@constCast(reason));
        }

        fn freeActuatorRefFields(allocator: std.mem.Allocator, ref: W.Actuation.Ref) void {
            allocator.free(@constCast(ref.label));
            allocator.free(@constCast(ref.metadata));
        }

        fn freeDescriptorFields(allocator: std.mem.Allocator, descriptor: W.Actuation.Descriptor) void {
            allocator.free(@constCast(descriptor.label));
            allocator.free(@constCast(descriptor.metadata));
        }

        fn writeRawBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
            try out.appendSlice(allocator, bytes);
        }

        fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
            try writeCount(out, allocator, bytes.len);
            try writeRawBytes(out, allocator, bytes);
        }

        fn writeOptionalBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?[]const u8) !void {
            try writeBool(out, allocator, value != null);
            if (value) |bytes| try writeBytes(out, allocator, bytes);
        }

        fn writeBool(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: bool) !void {
            try writeU8(out, allocator, if (value) 1 else 0);
        }

        fn writeU8(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
            try out.append(allocator, value);
        }

        fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
            var buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &buf, value, .little);
            try writeRawBytes(out, allocator, &buf);
        }

        fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
            const casted = std.math.cast(u64, value) orelse return error.InvalidFrameEncoding;
            var buf: [8]u8 = undefined;
            std.mem.writeInt(u64, &buf, casted, .little);
            try writeRawBytes(out, allocator, &buf);
        }

        fn writeCount(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) !void {
            try writeU64(out, allocator, value);
        }

        fn writeOptionalU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u32) !void {
            try writeBool(out, allocator, value != null);
            if (value) |present| try writeU32(out, allocator, present);
        }

        fn writeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u64) !void {
            try writeBool(out, allocator, value != null);
            if (value) |present| try writeU64(out, allocator, present);
        }

        fn writeOptionalCount(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?usize) !void {
            try writeBool(out, allocator, value != null);
            if (value) |present| try writeCount(out, allocator, present);
        }

        fn patchU64(bytes: []u8, offset: usize, value: usize) void {
            std.mem.writeInt(u64, bytes[offset..][0..8], @intCast(value), .little);
        }

        fn readFixedBytes(bytes: []const u8, cursor: *usize, expected: []const u8) !void {
            if (bytes.len - cursor.* < expected.len) return error.InvalidFrameEncoding;
            if (!std.mem.eql(u8, bytes[cursor.* .. cursor.* + expected.len], expected)) return error.InvalidFrameEncoding;
            cursor.* += expected.len;
        }

        fn readBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_len: usize) ![]u8 {
            const len = try readCount(bytes, cursor, max_len);
            if (bytes.len - cursor.* < len) return error.InvalidFrameEncoding;
            const owned = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + len]);
            cursor.* += len;
            return owned;
        }

        fn readOptionalBytesOwned(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize, max_len: usize) !?[]const u8 {
            if (!try readBool(bytes, cursor)) return null;
            return try readBytesOwned(allocator, bytes, cursor, max_len);
        }

        fn readBool(bytes: []const u8, cursor: *usize) !bool {
            return switch (try readU8(bytes, cursor)) {
                0 => false,
                1 => true,
                else => error.InvalidFrameEncoding,
            };
        }

        fn readU8(bytes: []const u8, cursor: *usize) !u8 {
            if (bytes.len - cursor.* < 1) return error.InvalidFrameEncoding;
            const value = bytes[cursor.*];
            cursor.* += 1;
            return value;
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

        fn readCount(bytes: []const u8, cursor: *usize, max: usize) !usize {
            const value = try readU64(bytes, cursor);
            const casted = std.math.cast(usize, value) orelse return error.InvalidFrameEncoding;
            if (casted > max) return error.InvalidFrameEncoding;
            return casted;
        }

        fn readOptionalU32(bytes: []const u8, cursor: *usize) !?u32 {
            if (!try readBool(bytes, cursor)) return null;
            return try readU32(bytes, cursor);
        }

        fn readOptionalU64(bytes: []const u8, cursor: *usize) !?u64 {
            if (!try readBool(bytes, cursor)) return null;
            return try readU64(bytes, cursor);
        }

        fn readOptionalCount(bytes: []const u8, cursor: *usize) !?usize {
            if (!try readBool(bytes, cursor)) return null;
            return try readCount(bytes, cursor, std.math.maxInt(usize));
        }

        fn readEnum(comptime E: type, bytes: []const u8, cursor: *usize) !E {
            const raw = try readU8(bytes, cursor);
            inline for (@typeInfo(E).@"enum".fields) |field| {
                if (field.value == raw) return @enumFromInt(field.value);
            }
            return error.InvalidFrameEncoding;
        }

        fn moduleKindFromBoundary(kind: BoundaryModule.Kind) W.Admission.BoundaryModuleKind {
            return switch (kind) {
                .reference_only => .reference_only,
                .full_module => .full_module,
                .partial_module => .partial_module,
            };
        }

        fn normalFormKindFromBoundary(kind: anytype) W.NormalFormKind {
            const name = @tagName(kind);
            if (std.mem.eql(u8, name, "strict_closed")) return .strict_closed;
            if (std.mem.eql(u8, name, "world_ports_only")) return .world_ports_only;
            return .unknown;
        }

        fn modeFromBoundary(mode: []const u8) W.BindingModePolicy {
            if (std.mem.eql(u8, mode, "fresh")) return .fresh;
            if (std.mem.eql(u8, mode, "replay")) return .replay;
            if (std.mem.eql(u8, mode, "verify")) return .verify;
            if (std.mem.eql(u8, mode, "audit")) return .audit;
            if (std.mem.eql(u8, mode, "fresh_and_replay")) return .fresh_and_replay;
            return .all;
        }

        fn optionalU64Matches(left: ?u64, right: ?u64) bool {
            if (left == null or right == null) return true;
            return left.? == right.?;
        }

        fn optionalU64MatchesExact(left: ?u64, right: ?u64) bool {
            if (left == null or right == null) return left == null and right == null;
            return left.? == right.?;
        }

        fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
            if (left == null or right == null) return left == null and right == null;
            return std.mem.eql(u8, left.?, right.?);
        }

        fn bindingRefSatisfiesRequirement(binding_ref: ?u64, requirement_ref: ?u64) bool {
            if (requirement_ref) |expected| {
                const actual = binding_ref orelse return false;
                return actual == expected;
            }
            return true;
        }

        fn descriptorSupportsRequirementMode(supported_modes: W.Actuation.ModeSet, requirement_mode: W.BindingModePolicy) bool {
            return switch (requirement_mode) {
                .fresh => supported_modes.allows(.fresh),
                .replay => supported_modes.allows(.replay),
                .verify => supported_modes.allows(.verify),
                .audit => supported_modes.allows(.audit),
                .fresh_and_replay => supported_modes.allows(.fresh) and supported_modes.allows(.replay),
                .all => supported_modes.allows(.fresh) and supported_modes.allows(.replay) and supported_modes.allows(.verify) and supported_modes.allows(.audit),
            };
        }

        fn optionalU32Matches(left: ?u32, right: ?u32) bool {
            if (left == null or right == null) return true;
            return left.? == right.?;
        }

        fn boundaryValueRefFingerprint(ref: BoundaryEvidence.BoundaryValueRef) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.boundary.value_ref.v1");
            hashBytesWithLen(&hasher, ref.codec);
            hashOptionalU16(&hasher, ref.schema_index);
            return hasher.final();
        }

        fn fingerprintRuntimeProfile(profile: RuntimeProfile) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.runtime_profile.v1");
            hashU64(&hasher, W.world_executable_runtime_profile_fingerprint_version);
            hashBool(&hasher, profile.supports_loaded_execution);
            hashBool(&hasher, profile.supports_internal_providers);
            hashBool(&hasher, profile.supports_external_actuation);
            hashU64(&hasher, profile.max_modules);
            hashU64(&hasher, profile.max_provider_depth);
            hashU64(&hasher, profile.max_external_bindings);
            hashU64(&hasher, profile.max_module_bytes);
            hashU64(&hasher, profile.max_image_bytes);
            hashU64(&hasher, profile.max_command_bytes);
            hashU64(&hasher, profile.max_output_bytes);
            hashU64(&hasher, profile.max_linear_memory_pages);
            hashBytesWithLen(&hasher, profile.metadata);
            return hasher.final();
        }

        fn fingerprintExternalBinding(binding: ExternalBinding) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.external_binding.v1");
            hashU64(&hasher, W.world_executable_external_binding_fingerprint_version);
            hashU64(&hasher, binding.parent_module_fingerprint);
            hashU64(&hasher, binding.world_port_id);
            hashOptionalU64(&hasher, binding.world_port_ref_fingerprint);
            hashOptionalU32(&hasher, binding.payload_value_table_id);
            hashOptionalU64(&hasher, binding.payload_value_ref_fingerprint);
            hashOptionalU32(&hasher, binding.response_value_table_id);
            hashOptionalU64(&hasher, binding.response_value_ref_fingerprint);
            hashU64(&hasher, binding.actuator_ref.ref_fingerprint);
            hashU64(&hasher, binding.descriptor.descriptor_fingerprint);
            hashResponseStatusSet(&hasher, binding.allowed_response_statuses);
            hashU64(&hasher, @intFromEnum(binding.actuation_class));
            hashU64(&hasher, W.Actuation.valuePolicyFingerprint(binding.value_policy));
            hashOptionalU64(&hasher, binding.supervision_rule_ref);
            hashOptionalU64(&hasher, binding.authority_descriptor_ref);
            hashBytesWithLen(&hasher, binding.label);
            hashBytesWithLen(&hasher, binding.metadata);
            return hasher.final();
        }

        fn fingerprintModuleSet(module_set: ModuleSet) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.module_set.v1");
            hashU64(&hasher, W.world_executable_module_set_fingerprint_version);
            hashU64(&hasher, module_set.root_module_id);
            for (module_set.modules) |module| {
                hashU64(&hasher, module.module_id);
                hashU64(&hasher, @intFromEnum(module.role));
                hashU64(&hasher, module.module_ref.module_ref_fingerprint);
                hashU64(&hasher, module.module_ref.boundary_module_fingerprint);
                hashU64(&hasher, module.import_set.import_set_fingerprint);
                hashU64(&hasher, module.imports.len);
                for (module.imports) |requirement| hashU64(&hasher, requirement.requirement_fingerprint);
                hashU64(&hasher, module.export_summary.export_summary_fingerprint);
                hashU64(&hasher, module.executable_plan_fingerprint);
                hashU64(&hasher, hashBytesDomain("world.executable.module.bytes", module.canonical_bytes));
            }
            return hasher.final();
        }

        fn fingerprintDispatchImage(image: DispatchImage) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.dispatch_image.v1");
            hashU64(&hasher, image.format_version);
            hashU64(&hasher, image.fingerprint_version);
            hashU64(&hasher, image.root_module_id);
            hashU64Slice(&hasher, image.module_fingerprints);
            hashU64Slice(&hasher, image.external_binding_fingerprints);
            hashU64(&hasher, image.residual_request_order.len);
            for (image.residual_request_order) |value| hashU64(&hasher, value);
            hashU64Slice(&hasher, image.fabric_plan_fingerprints);
            hashU64Slice(&hasher, image.route_ids);
            hashU64(&hasher, image.route_kinds.len);
            for (image.route_kinds) |kind| hashU64(&hasher, @intFromEnum(kind));
            hashU64(&hasher, image.route_parent_world_port_ids.len);
            for (image.route_parent_world_port_ids) |value| hashU64(&hasher, value);
            hashU64Slice(&hasher, image.route_requirement_fingerprints);
            hashU64Slice(&hasher, image.route_provider_module_fingerprints);
            hashU64(&hasher, image.linker_policy.fingerprint());
            hashU64(&hasher, image.link_plan_fingerprint);
            hashU64(&hasher, image.linker_certificate_fingerprint);
            hashU64(&hasher, image.assembly_fingerprint);
            return hasher.final();
        }

        fn fingerprintMemoryPlan(plan: MemoryPlan) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.memory_plan.v1");
            hashU64(&hasher, W.world_executable_memory_plan_fingerprint_version);
            hashU64(&hasher, plan.decoded_module_bytes);
            hashU64(&hasher, plan.dispatch_table_entries);
            hashU64(&hasher, plan.schema_table_entries);
            hashU64(&hasher, plan.max_session_frames);
            hashU64(&hasher, plan.max_runspace_slots);
            hashU64(&hasher, plan.max_mailbox_entries);
            hashU64(&hasher, plan.max_provider_runs);
            hashU64(&hasher, plan.max_host_requests_per_turn);
            hashU64(&hasher, plan.max_command_bytes);
            hashU64(&hasher, plan.max_output_bytes);
            hashU64(&hasher, plan.max_capsule_bytes);
            hashU64(&hasher, plan.max_archive_append_bytes);
            hashU64(&hasher, plan.max_linear_memory_pages);
            return hasher.final();
        }

        fn fingerprintCompatibilityReport(report: CompatibilityReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.compatibility_report.v1");
            hashU64(&hasher, W.world_executable_compatibility_report_fingerprint_version);
            hashBool(&hasher, report.compatible);
            hashBool(&hasher, report.image_format_compatible);
            hashBool(&hasher, report.boundary_module_compatible);
            hashBool(&hasher, report.executable_plan_compatible);
            hashBool(&hasher, report.instruction_feature_compatible);
            hashBool(&hasher, report.value_codec_compatible);
            hashBool(&hasher, report.profile_compatible);
            hashBool(&hasher, report.capacity_compatible);
            hashBool(&hasher, report.memory_compatible);
            hashU64(&hasher, report.missing_optional_features);
            hashU64(&hasher, report.hard_blockers);
            hashU64(&hasher, report.warnings);
            hashBytesWithLen(&hasher, report.summary);
            return hasher.final();
        }

        fn fingerprintCertificate(cert: Certificate) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.certificate.v1");
            hashU64(&hasher, cert.format_version);
            hashU64(&hasher, cert.fingerprint_version);
            hashU64(&hasher, cert.image_fingerprint);
            hashU64(&hasher, cert.module_set_fingerprint);
            hashU64(&hasher, cert.runtime_profile_fingerprint);
            hashU64(&hasher, cert.dispatch_fingerprint);
            hashU64(&hasher, cert.memory_plan_fingerprint);
            hashU64(&hasher, cert.compatibility_report_fingerprint);
            hashU64(&hasher, cert.link_plan_fingerprint);
            hashU64(&hasher, cert.linker_certificate_fingerprint);
            hashU64(&hasher, cert.assembly_fingerprint);
            hashU64(&hasher, cert.module_count);
            hashU64(&hasher, cert.residual_external_binding_count);
            hashU64(&hasher, cert.blocker_count);
            hashU64(&hasher, cert.warning_count);
            return hasher.final();
        }

        fn fingerprintPlan(plan: Plan) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.plan.v1");
            hashU64(&hasher, W.world_executable_plan_fingerprint_version);
            hashU64(&hasher, plan.module_set.module_set_fingerprint);
            hashU64(&hasher, plan.runtime_profile.profile_fingerprint);
            hashU64(&hasher, plan.link_plan.plan_fingerprint);
            hashU64(&hasher, plan.linker_certificate.certificate_fingerprint);
            hashU64(&hasher, plan.assembly.assembly_fingerprint);
            hashU64(&hasher, plan.dispatch_image.dispatch_fingerprint);
            hashU64(&hasher, plan.memory_plan.memory_plan_fingerprint);
            for (plan.external_bindings) |binding| hashU64(&hasher, binding.binding_fingerprint);
            hashU64(&hasher, plan.compatibility_report.report_fingerprint);
            return hasher.final();
        }

        fn fingerprintImage(image: Image) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.image.v1");
            hashU64(&hasher, image.format_version);
            hashU64(&hasher, image.fingerprint_version);
            hashU64(&hasher, image.required_runtime_profile.profile_fingerprint);
            hashU64(&hasher, image.module_set.module_set_fingerprint);
            hashU64(&hasher, image.link_plan_fingerprint);
            hashU64(&hasher, image.linker_certificate_fingerprint);
            hashU64(&hasher, image.assembly_fingerprint);
            hashU64(&hasher, image.dispatch_image.dispatch_fingerprint);
            for (image.external_bindings) |binding| hashU64(&hasher, binding.binding_fingerprint);
            hashU64(&hasher, image.memory_plan.memory_plan_fingerprint);
            hashU64(&hasher, image.compatibility_report.report_fingerprint);
            hashBytesWithLen(&hasher, image.metadata);
            return hasher.final();
        }

        fn fingerprintLoadReport(report: LoadReport) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "world.executable.load_report.v1");
            hashU64(&hasher, W.world_executable_load_report_fingerprint_version);
            hashU64(&hasher, report.image_fingerprint);
            hashBool(&hasher, report.accepted);
            hashU64(&hasher, report.runtime_profile_fingerprint);
            hashBool(&hasher, report.executable_manifest_available);
            hashU64(&hasher, report.hard_blockers);
            hashU64(&hasher, report.warnings);
            return hasher.final();
        }

        fn hashBytesDomain(domain: []const u8, bytes: []const u8) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, domain);
            hashBytesWithLen(&hasher, bytes);
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

        fn hashOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
            hashBool(hasher, value != null);
            if (value) |present| hashU64(hasher, present);
        }

        fn hashOptionalU32(hasher: *std.hash.Wyhash, value: ?u32) void {
            hashBool(hasher, value != null);
            if (value) |present| hashU64(hasher, present);
        }

        fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
            hashBool(hasher, value != null);
            if (value) |present| hashU64(hasher, present);
        }

        fn hashU64Slice(hasher: *std.hash.Wyhash, values: []const u64) void {
            hashU64(hasher, values.len);
            for (values) |value| hashU64(hasher, value);
        }

        fn hashResponseStatusSet(hasher: *std.hash.Wyhash, statuses: W.Actuation.ResponseStatusSet) void {
            hashBool(hasher, statuses.responded);
            hashBool(hasher, statuses.rejected);
            hashBool(hasher, statuses.failed);
            hashBool(hasher, statuses.pending);
            hashBool(hasher, statuses.deferred);
            hashBool(hasher, statuses.cancelled);
        }
    };
}
