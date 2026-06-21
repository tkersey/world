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
                if (self.import_set.required_count != self.imports.len) return error.InvalidFrameEncoding;
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
                    self.max_provider_depth >= required.max_provider_depth and
                    self.max_external_bindings >= required.max_external_bindings and
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
                if (!optionalU64Matches(self.descriptor.source_effect_shape_ref_fingerprint, requirement.source_effect_shape_ref_fingerprint)) return false;
                if (!optionalU32Matches(self.descriptor.payload_value_table_id, requirement.payload_value_table_id)) return false;
                if (!optionalU32Matches(self.descriptor.response_value_table_id, requirement.response_value_table_id)) return false;
                if (!optionalU64Matches(self.world_port_ref_fingerprint, requirement.world_port_ref_fingerprint)) return false;
                if (!optionalU32Matches(self.payload_value_table_id, requirement.payload_value_table_id)) return false;
                if (!optionalU64Matches(self.payload_value_ref_fingerprint, requirement.payload_value_ref_fingerprint)) return false;
                if (!optionalU32Matches(self.response_value_table_id, requirement.response_value_table_id)) return false;
                if (!optionalU64Matches(self.response_value_ref_fingerprint, requirement.response_value_ref_fingerprint)) return false;
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
            route_provider_module_fingerprints: []const u64 = &.{},
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
                route_provider_module_fingerprints: []const u64 = &.{},
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
                    .route_provider_module_fingerprints = args.route_provider_module_fingerprints,
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
                var module_bytes: usize = 0;
                var schema_entries: usize = 0;
                for (modules) |module| {
                    module_bytes = module_bytes +| module.canonical_bytes.len;
                    schema_entries = schema_entries +| module.import_set.value_table_entry_count;
                }
                var result = @This(){
                    .memory_plan_fingerprint = 0,
                    .decoded_module_bytes = module_bytes,
                    .dispatch_table_entries = modules.len + residual_count,
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
                const bindings = try allocator.dupe(ExternalBinding, self.external_bindings);
                errdefer allocator.free(bindings);
                const dispatch_image = try cloneDispatchImage(allocator, self.dispatch_image);
                errdefer freeDispatchImage(allocator, dispatch_image);
                var image = Image.init(.{
                    .required_runtime_profile = self.runtime_profile,
                    .module_set = ModuleSet.init(modules, self.module_set.root_module_id),
                    .link_plan_fingerprint = self.link_plan.plan_fingerprint,
                    .linker_certificate_fingerprint = self.linker_certificate.certificate_fingerprint,
                    .assembly_fingerprint = self.assembly.assembly_fingerprint,
                    .dispatch_image = dispatch_image,
                    .external_bindings = bindings,
                    .memory_plan = self.memory_plan,
                    .compatibility_report = self.compatibility_report,
                    .metadata = "world-executable-image-v1",
                });
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
                freeModuleSlice(allocator, @constCast(self.module_set.modules.ptr)[0..self.module_set.modules.len]);
                freeDispatchImage(allocator, self.dispatch_image);
                allocator.free(self.external_bindings);
                self.* = undefined;
            }

            pub fn validate(self: @This(), supported_profile: RuntimeProfile) !CompatibilityReport {
                return self.validateWithOptions(supported_profile, .{});
            }

            pub fn validateWithOptions(self: @This(), supported_profile: RuntimeProfile, options: struct {
                require_certificate: bool = true,
            }) !CompatibilityReport {
                if (self.format_version != W.world_executable_image_format_version) return error.InvalidFrameEncoding;
                if (self.fingerprint_version != W.world_executable_image_fingerprint_version) return error.InvalidFrameEncoding;
                try self.required_runtime_profile.validate();
                if (!self.required_runtime_profile.supports_loaded_execution) return error.InvalidFrameEncoding;
                try self.module_set.validate();
                for (self.module_set.modules) |module| try validateModuleCanonicalBytes(module, self.required_runtime_profile);
                if (self.dispatch_image.format_version != W.world_executable_dispatch_image_format_version) return error.InvalidFrameEncoding;
                if (self.dispatch_image.fingerprint_version != W.world_executable_dispatch_image_fingerprint_version) return error.InvalidFrameEncoding;
                if (self.dispatch_image.dispatch_fingerprint != fingerprintDispatchImage(self.dispatch_image)) return error.InvalidFrameEncoding;
                if (self.dispatch_image.link_plan_fingerprint != self.link_plan_fingerprint or
                    self.dispatch_image.linker_certificate_fingerprint != self.linker_certificate_fingerprint or
                    self.dispatch_image.assembly_fingerprint != self.assembly_fingerprint)
                {
                    return error.InvalidFrameEncoding;
                }
                try validateDispatchTablesForImage(self);
                if (self.memory_plan.memory_plan_fingerprint != fingerprintMemoryPlan(self.memory_plan)) return error.InvalidFrameEncoding;
                const expected_memory_plan = MemoryPlan.derive(self.required_runtime_profile, self.module_set.modules, self.external_bindings.len);
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
                    .route_provider_module_fingerprints = dispatch_routes.route_provider_module_fingerprints,
                    .link_plan_fingerprint = link_result.plan.plan_fingerprint,
                    .linker_certificate_fingerprint = link_result.certificate.certificate_fingerprint,
                    .assembly_fingerprint = link_result.assembly.assembly_fingerprint,
                });
                const memory_plan = MemoryPlan.derive(self.options.runtime_profile, modules, residual_count);
                const report = CompatibilityReport.init(.{
                    .compatible = compatible,
                    .boundary_module_compatible = true,
                    .executable_plan_compatible = true,
                    .profile_compatible = true,
                    .capacity_compatible = compatible,
                    .memory_compatible = true,
                    .hard_blockers = hard_blockers,
                    .warnings = link_result.plan.warnings.len,
                    .summary = if (compatible) "executable image prepared" else "executable image blocked",
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
            const import_set = W.ImportSet.init(.{
                .target_ref_fingerprint = target_ref.target_ref_fingerprint,
                .required_count = imports.len,
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

        fn validateModuleCanonicalBytes(module: Module, profile: RuntimeProfile) !void {
            const decoded = moduleFromBytes(std.heap.page_allocator, module.canonical_bytes, module.role, module.module_id, profile) catch
                return error.InvalidFrameEncoding;
            defer {
                std.heap.page_allocator.free(decoded.imports);
                std.heap.page_allocator.free(decoded.canonical_bytes);
            }
            if (decoded.module_ref.module_ref_fingerprint != module.module_ref.module_ref_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.module_ref.boundary_module_fingerprint != module.module_ref.boundary_module_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.target_ref.target_ref_fingerprint != module.target_ref.target_ref_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.import_set.import_set_fingerprint != module.import_set.import_set_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.imports.len != module.imports.len) return error.InvalidFrameEncoding;
            for (decoded.imports, module.imports) |decoded_import, declared_import| {
                if (decoded_import.requirement_fingerprint != declared_import.requirement_fingerprint) return error.InvalidFrameEncoding;
            }
            if (decoded.export_summary.export_summary_fingerprint != module.export_summary.export_summary_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.executable_plan_fingerprint != module.executable_plan_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.validation_report_fingerprint != module.validation_report_fingerprint) return error.InvalidFrameEncoding;
            if (decoded.compatibility_report_fingerprint != module.compatibility_report_fingerprint) return error.InvalidFrameEncoding;
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

        fn validateDispatchTablesForImage(image: Image) !void {
            if (image.dispatch_image.root_module_id != image.module_set.root_module_id) return error.InvalidFrameEncoding;
            if (image.dispatch_image.module_fingerprints.len != image.module_set.modules.len) return error.InvalidFrameEncoding;
            const route_count = image.dispatch_image.route_ids.len;
            if (image.dispatch_image.route_kinds.len != route_count or
                image.dispatch_image.route_parent_world_port_ids.len != route_count or
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
            try validateDispatchRouteRowsAgainstLinkWitness(image);
        }

        fn validateDispatchRouteRowsAgainstLinkWitness(image: Image) !void {
            const allocator = std.heap.page_allocator;
            const root = image.module_set.root() orelse return error.InvalidFrameEncoding;
            const catalog_entries = try allocator.alloc(W.Linker.Catalog.Entry, image.module_set.modules.len);
            defer allocator.free(catalog_entries);
            var catalog_count: usize = 0;
            for (image.module_set.modules) |module| {
                if (module.role != .provider) continue;
                catalog_entries[catalog_count] = catalogEntryForModule(root, module);
                catalog_count += 1;
            }

            const policies = [_]W.Linker.Policy{
                .allow_external_ports,
                .strict_closed,
                .world_boundary,
                .agent_fixture,
            };
            for (policies) |policy| {
                if (dispatchRouteRowsMatchPolicy(allocator, image, root, catalog_entries[0..catalog_count], policy) catch false) return;
            }
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
            const routes = try dispatchRouteSlices(allocator, link_result.plan);
            defer routes.deinit(allocator);
            return std.mem.eql(u64, routes.route_ids, image.dispatch_image.route_ids) and
                std.mem.eql(W.Fabric.RouteKind, routes.route_kinds, image.dispatch_image.route_kinds) and
                std.mem.eql(u32, routes.route_parent_world_port_ids, image.dispatch_image.route_parent_world_port_ids) and
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
            var total_module_bytes: usize = 0;
            for (image.module_set.modules) |module| {
                if (module.canonical_bytes.len > profile.max_module_bytes) return error.InvalidFrameEncoding;
                total_module_bytes = total_module_bytes +| module.canonical_bytes.len;
            }
            if (total_module_bytes > profile.max_image_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_command_bytes > profile.max_command_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_output_bytes > profile.max_output_bytes) return error.InvalidFrameEncoding;
            if (image.memory_plan.max_linear_memory_pages > profile.max_linear_memory_pages) return error.InvalidFrameEncoding;
        }

        fn dispatchCoversRequirement(dispatch: DispatchImage, requirement: W.ImportRequirement) bool {
            for (dispatch.residual_request_order) |fingerprint| {
                if (fingerprint == requirement.requirement_fingerprint) return true;
            }
            for (dispatch.route_parent_world_port_ids) |world_port_id| {
                if (world_port_id == requirement.world_port_id) return true;
            }
            return false;
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
            if (strict) {
                for (bindings) |binding| {
                    var matched_count: usize = 0;
                    for (residuals) |requirement| {
                        if (binding.matchesRequirement(root, requirement)) {
                            matched_count += 1;
                        }
                    }
                    if (matched_count == 0) report.unused += 1;
                    if (matched_count > 1) report.duplicates += matched_count - 1;
                }
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
                current.imports = &.{};
                current.canonical_bytes = &.{};
                errdefer {
                    allocator.free(current.imports);
                    allocator.free(current.canonical_bytes);
                }
                current.imports = try allocator.dupe(W.ImportRequirement, module.imports);
                current.canonical_bytes = try allocator.dupe(u8, module.canonical_bytes);
                cloned[index] = current;
                initialized += 1;
                current.imports = &.{};
                current.canonical_bytes = &.{};
            }
            return cloned;
        }

        fn freeModuleSlice(allocator: std.mem.Allocator, modules: []Module) void {
            for (modules) |module| {
                allocator.free(module.imports);
                allocator.free(module.canonical_bytes);
            }
            allocator.free(modules);
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
            route_provider_module_fingerprints: []u64 = &.{},

            fn deinit(self: @This(), allocator: std.mem.Allocator) void {
                allocator.free(self.route_ids);
                allocator.free(self.route_kinds);
                allocator.free(self.route_parent_world_port_ids);
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
            const route_provider_module_fingerprints = try allocator.alloc(u64, count);
            errdefer allocator.free(route_provider_module_fingerprints);
            var index: usize = 0;
            for (plan.fabric_plans) |fabric_plan| {
                for (fabric_plan.routes) |route| {
                    route_ids[index] = route.route_id;
                    route_kinds[index] = route.kind;
                    route_parent_world_port_ids[index] = route.parent_world_port_id;
                    route_provider_module_fingerprints[index] = route.provider_module_fingerprint orelse 0;
                    index += 1;
                }
            }
            return .{
                .route_ids = route_ids,
                .route_kinds = route_kinds,
                .route_parent_world_port_ids = route_parent_world_port_ids,
                .route_provider_module_fingerprints = route_provider_module_fingerprints,
            };
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
            allocator.free(image.route_provider_module_fingerprints);
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
            hashU64Slice(&hasher, image.route_provider_module_fingerprints);
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
