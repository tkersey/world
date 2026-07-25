const std = @import("std");
const boundary = @import("boundary");
const protocol = @import("application_v1.zig");

pub const Authority = enum(u6) {
    model = 0,
    file_read = 1,
    file_write = 2,
    network = 3,
    human = 4,
    clock = 5,
    randomness = 6,
    database = 7,
    child_agent = 8,
};

pub const ResponseMode = enum {
    @"resume",
    return_now,
};

const BindingKind = enum {
    internal_machine,
    external_effect,
};

pub fn handle(comptime SiteType: type, comptime ProviderType: type) type {
    requireOperationSite(SiteType);
    requireStaticMachine(ProviderType);
    return struct {
        pub const binding_kind = BindingKind.internal_machine;
        pub const Site = SiteType;
        pub const Provider = ProviderType;
    };
}

pub fn external(comptime SiteType: type, comptime config: anytype) type {
    @setEvalBranchQuota(1_000_000);
    requireOperationSite(SiteType);
    if (!@hasField(@TypeOf(config), "interface")) {
        @compileError("world.external requires an interface label");
    }
    const interface_label: []const u8 = config.interface;
    if (interface_label.len == 0) @compileError("world.external interface labels must be non-empty");
    const mode: ResponseMode = if (@hasField(@TypeOf(config), "response_mode")) config.response_mode else .@"resume";
    const statuses: protocol.AllowedStatuses = if (@hasField(@TypeOf(config), "allowed_statuses")) config.allowed_statuses else .{};
    const requirements: u64 = if (@hasField(@TypeOf(config), "authority_requirements"))
        config.authority_requirements
    else if (@hasField(@TypeOf(config), "authority"))
        authorityMask(@as(Authority, config.authority))
    else
        0;
    const maximum_attempt_count: u32 = if (@hasField(@TypeOf(config), "maximum_attempts")) config.maximum_attempts else 3;
    const maximum_result_bytes: ?u32 = if (@hasField(@TypeOf(config), "maximum_result_bytes")) config.maximum_result_bytes else null;

    return struct {
        pub const binding_kind = BindingKind.external_effect;
        pub const Site = SiteType;
        pub const interface = interface_label;
        pub const interface_id = blk: {
            @setEvalBranchQuota(1_000_000);
            break :blk protocol.digestLabel("world.effect-interface.v1", interface_label);
        };
        pub const response_mode = mode;
        pub const allowed_statuses = statuses;
        pub const authority_requirements = requirements;
        pub const maximum_attempts = maximum_attempt_count;
        pub const configured_maximum_result_bytes = maximum_result_bytes;
        pub const Response = responseType(SiteType, mode);
    };
}

fn authorityMask(authority: Authority) u64 {
    return @as(u64, 1) << @intFromEnum(authority);
}

fn responseType(comptime Site: type, comptime mode: ResponseMode) type {
    return switch (mode) {
        .@"resume" => Site.Resume,
        .return_now => Site.Result,
    };
}

fn requireOperationSite(comptime Site: type) void {
    if (!@hasDecl(Site, "kind") or Site.kind != .operation or
        !@hasDecl(Site, "Owner") or !@hasDecl(Site, "index") or
        !@hasDecl(Site, "canonical_fingerprint") or !@hasDecl(Site, "Payload") or
        !@hasDecl(Site, "Resume") or !@hasDecl(Site, "Result"))
    {
        @compileError("World application bindings require a Boundary StaticMachine operation site");
    }
}

fn requireStaticMachine(comptime Machine: type) void {
    if (!@hasDecl(Machine, "abi_version") or Machine.abi_version != 1 or
        !@hasDecl(Machine, "State") or !@hasDecl(Machine, "InitialArgs") or
        !@hasDecl(Machine, "Result") or !@hasDecl(Machine, "EffectRow") or
        !@hasDecl(Machine, "Manifest") or !@hasDecl(Machine, "initialState") or
        !@hasDecl(Machine, "reduce") or !@hasDecl(Machine, "encodeState") or
        !@hasDecl(Machine, "decodeState"))
    {
        @compileError("world.application requires Boundary StaticMachine ABI v1 types");
    }
}

fn bindingTargets(comptime Binding: type, comptime Site: type) bool {
    return Binding.Site.Owner == Site.Owner and
        Binding.Site.index == Site.index and
        Binding.Site.canonical_fingerprint == Site.canonical_fingerprint;
}

fn externalBindingForSite(comptime Site: type, comptime bindings: anytype) type {
    inline for (bindings) |Binding| {
        if (bindingTargets(Binding, Site)) return Binding;
    }
    @compileError("World application has no external binding for this site");
}

fn machineOwnsSite(comptime Machine: type, comptime Site: type) bool {
    if (Machine.EffectRow.Owner != Site.Owner) return false;
    if (Site.index >= Machine.EffectRow.operation_site_count) return false;
    const owned = Machine.EffectRow.siteByIndex(Site.index);
    return owned.canonical_fingerprint == Site.canonical_fingerprint;
}

fn validateProviderCompatibility(comptime Binding: type) void {
    const Site = Binding.Site;
    const Provider = Binding.Provider;
    if (!Site.may_resume) {
        @compileError("World StaticMachine providers require a resumable parent operation site");
    }
    const args = @typeInfo(Provider.InitialArgs).@"struct";
    if (!args.is_tuple or args.fields.len != 1 or args.fields[0].type != Site.Payload) {
        @compileError("World StaticMachine provider InitialArgs must be exactly one parent payload value");
    }
    if (Provider.Result != Site.Resume) {
        @compileError("World StaticMachine provider Result must exactly match the parent resume type");
    }
}

fn validateExternalCompatibility(
    comptime Binding: type,
    comptime limits: protocol.Limits,
) void {
    switch (Binding.response_mode) {
        .@"resume" => if (!Binding.Site.may_resume) {
            @compileError("World external resume binding targets an operation that cannot resume");
        },
        .return_now => if (!Binding.Site.may_return_now) {
            @compileError("World external return_now binding targets an operation that cannot return immediately");
        },
    }
    if (Binding.maximum_attempts == 0) @compileError("World external maximum_attempts must be positive");
    if (Binding.configured_maximum_result_bytes) |maximum| {
        if (maximum == 0) {
            @compileError("World external maximum_result_bytes must be positive");
        }
        if (maximum > limits.maximum_result_bytes) {
            @compileError("World external maximum_result_bytes exceeds the application maximum_result_bytes");
        }
    }
    if (!Binding.allowed_statuses.ok and !Binding.allowed_statuses.rejected and
        !Binding.allowed_statuses.failed and !Binding.allowed_statuses.deferred and
        !Binding.allowed_statuses.cancelled)
    {
        @compileError("World external bindings must allow at least one result status");
    }
}

fn normalizedLimits(comptime spec: anytype) protocol.Limits {
    var result: protocol.Limits = .{};
    if (!@hasField(@TypeOf(spec), "limits")) return result;
    const configured = spec.limits;
    inline for (@typeInfo(protocol.Limits).@"struct".fields) |field| {
        if (@hasField(@TypeOf(configured), field.name)) {
            @field(result, field.name) = @field(configured, field.name);
        }
    }
    if (@hasField(@TypeOf(configured), "maximum_effects_per_frame") and configured.maximum_effects_per_frame != 1) {
        @compileError("World Application ABI v1 supports exactly one pending effect per Frame");
    }
    return result;
}

fn validateApplicationSpec(
    comptime Root: type,
    comptime handlers: anytype,
    comptime externals: anytype,
    comptime limits: protocol.Limits,
) void {
    requireStaticMachine(Root);
    limits.validate() catch @compileError("World application limits are invalid");
    validateMachine(Root, handlers, externals, limits, 0, .{});
    inline for (handlers) |Binding| {
        if (Binding.binding_kind != .internal_machine) @compileError("World handlers contains a non-handler binding");
        validateProviderCompatibility(Binding);
        if (!siteReachable(Root, Binding.Site, handlers, limits, 0, .{})) {
            @compileError("World handler binding targets a site unreachable from the root machine");
        }
    }
    inline for (externals) |Binding| {
        if (Binding.binding_kind != .external_effect) @compileError("World external contains a non-external binding");
        validateExternalCompatibility(Binding, limits);
        if (!siteReachable(Root, Binding.Site, handlers, limits, 0, .{})) {
            @compileError("World external binding targets a site unreachable from the root machine");
        }
    }
    const maximum_runtime_state_bytes =
        runtime_state_header_bytes + maximumMachineStackBytes(Root, handlers);
    if (maximum_runtime_state_bytes > limits.maximum_state_bytes) {
        @compileError("World application provider stack exceeds maximum_state_bytes");
    }
}

const runtime_state_header_bytes: u128 = 8 + 4 + protocol.zero_digest.len + 4;
const runtime_machine_frame_overhead: u128 = 4 + 4 + 4;

fn maximumMachineStackBytes(
    comptime Machine: type,
    comptime handlers: anytype,
) u128 {
    comptime var maximum_child_bytes: u128 = 0;
    inline for (Machine.EffectRow.operation_site_metadata) |metadata| {
        const Site = Machine.EffectRow.siteByIndex(metadata.index);
        inline for (handlers) |Binding| {
            if (bindingTargets(Binding, Site)) {
                const child_bytes = maximumMachineStackBytes(Binding.Provider, handlers);
                maximum_child_bytes = @max(maximum_child_bytes, child_bytes);
            }
        }
    }
    return runtime_machine_frame_overhead +
        @as(u128, Machine.Manifest.maximum_state_bytes) +
        maximum_child_bytes;
}

fn validateMachine(
    comptime Machine: type,
    comptime handlers: anytype,
    comptime externals: anytype,
    comptime limits: protocol.Limits,
    comptime depth: usize,
    comptime path: anytype,
) void {
    requireStaticMachine(Machine);
    inline for (path) |Ancestor| {
        if (Ancestor == Machine) @compileError("World application internal provider graph contains a static cycle");
    }
    if (depth > limits.maximum_provider_depth) {
        @compileError("World application internal provider graph exceeds maximum_provider_depth");
    }
    if (Machine.Manifest.maximum_frame_depth > limits.maximum_frame_depth) {
        @compileError("Boundary StaticMachine frame depth exceeds World application maximum_frame_depth");
    }
    if (Machine.Manifest.maximum_state_bytes > limits.maximum_state_bytes) {
        @compileError("Boundary StaticMachine state bound exceeds World application maximum_state_bytes");
    }
    if (Machine.EffectRow.after_site_count != 0) {
        @compileError("World Application v1 requires Boundary-local after continuations to be closed before World application closure");
    }

    const next_path = path ++ .{Machine};
    inline for (Machine.EffectRow.operation_site_metadata) |metadata| {
        const Site = Machine.EffectRow.siteByIndex(metadata.index);
        comptime var internal_count: usize = 0;
        comptime var external_count: usize = 0;
        inline for (handlers) |Binding| {
            if (bindingTargets(Binding, Site)) internal_count += 1;
        }
        inline for (externals) |Binding| {
            if (bindingTargets(Binding, Site)) external_count += 1;
        }
        if (internal_count + external_count == 0) {
            @compileError("World application has an unhandled operation site; declare an internal handler or explicit external effect");
        }
        if (internal_count + external_count != 1) {
            @compileError("World application operation site has ambiguous handler ownership");
        }
        inline for (handlers) |Binding| {
            if (bindingTargets(Binding, Site)) {
                validateProviderCompatibility(Binding);
                validateMachine(Binding.Provider, handlers, externals, limits, depth + 1, next_path);
            }
        }
    }
}

fn siteReachable(
    comptime Machine: type,
    comptime target: type,
    comptime handlers: anytype,
    comptime limits: protocol.Limits,
    comptime depth: usize,
    comptime path: anytype,
) bool {
    if (depth > limits.maximum_provider_depth) return false;
    inline for (path) |Ancestor| if (Ancestor == Machine) return false;
    if (machineOwnsSite(Machine, target)) return true;
    const next_path = path ++ .{Machine};
    inline for (Machine.EffectRow.operation_site_metadata) |metadata| {
        const Site = Machine.EffectRow.siteByIndex(metadata.index);
        inline for (handlers) |Binding| {
            if (bindingTargets(Binding, Site) and
                siteReachable(Binding.Provider, target, handlers, limits, depth + 1, next_path))
            {
                return true;
            }
        }
    }
    return false;
}

fn schemaHashType(hasher: *std.crypto.hash.sha2.Sha256, comptime T: type) void {
    if (T == usize) {
        // Boundary canonical state represents usize through a target-neutral
        // u64 word. Keep native and wasm32 application schema identities equal.
        hasher.update("usize-u64");
        return;
    }
    switch (@typeInfo(T)) {
        .void => hasher.update("unit"),
        .bool => hasher.update("bool"),
        .int => |info| {
            hasher.update(if (info.signedness == .signed) "signed-int" else "unsigned-int");
            var bits: [2]u8 = undefined;
            std.mem.writeInt(u16, &bits, info.bits, .little);
            hasher.update(&bits);
        },
        .pointer => |info| {
            if (T == []const u8) {
                hasher.update("string");
            } else if (T == []const []const u8) {
                hasher.update("string-list");
            } else {
                _ = info;
                @compileError("World value codec does not support this pointer type");
            }
        },
        .optional => |info| {
            hasher.update("optional");
            schemaHashType(hasher, info.child);
        },
        .@"enum" => |info| {
            hasher.update("enum");
            inline for (info.fields) |field| {
                hashLenBytes(hasher, field.name);
                var value: [8]u8 = undefined;
                std.mem.writeInt(u64, &value, field.value, .little);
                hasher.update(&value);
            }
        },
        .@"struct" => |info| {
            hasher.update(if (info.is_tuple) "tuple" else "product");
            inline for (info.fields) |field| {
                hashLenBytes(hasher, field.name);
                schemaHashType(hasher, field.type);
            }
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("World value codec requires tagged unions");
            hasher.update("sum");
            schemaHashType(hasher, info.tag_type.?);
            inline for (info.fields) |field| {
                hashLenBytes(hasher, field.name);
                schemaHashType(hasher, field.type);
            }
        },
        else => @compileError("World value codec does not support this Boundary value type"),
    }
}

fn hashLenBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(bytes.len), .little);
    hasher.update(&length);
    hasher.update(bytes);
}

pub fn valueSchemaId(comptime T: type) protocol.Digest {
    @setEvalBranchQuota(1_000_000);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("world.value-schema.v1");
    hasher.update(&.{0});
    schemaHashType(&hasher, T);
    var digest: protocol.Digest = undefined;
    hasher.final(&digest);
    return digest;
}

fn machineId(comptime Machine: type) protocol.Digest {
    @setEvalBranchQuota(1_000_000);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("world.boundary-static-machine.v1");
    hasher.update(&.{0});
    hashLenBytes(&hasher, Machine.Manifest.program_label);
    var value: [8]u8 = undefined;
    std.mem.writeInt(u64, &value, Machine.Manifest.canonical_plan_fingerprint, .little);
    hasher.update(&value);
    std.mem.writeInt(u64, &value, Machine.Manifest.machine_contract_fingerprint, .little);
    hasher.update(&value);
    var digest: protocol.Digest = undefined;
    hasher.final(&digest);
    return digest;
}

fn internalHandlerId(comptime Binding: type) protocol.Digest {
    @setEvalBranchQuota(1_000_000);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("world.internal-handler.v1");
    hasher.update(&.{0});
    var site: [8]u8 = undefined;
    std.mem.writeInt(u64, &site, Binding.Site.canonical_fingerprint, .little);
    hasher.update(&site);
    const provider_id = machineId(Binding.Provider);
    hasher.update(&provider_id);
    var digest: protocol.Digest = undefined;
    hasher.final(&digest);
    return digest;
}

fn derivedHandlerIds(comptime handlers: anytype) [handlers.len]protocol.Digest {
    var result: [handlers.len]protocol.Digest = undefined;
    inline for (handlers, 0..) |Binding, index| result[index] = internalHandlerId(Binding);
    insertionSortDigests(&result);
    return result;
}

fn insertionSortDigests(values: []protocol.Digest) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and std.mem.order(u8, &value, &values[cursor - 1]) == .lt) : (cursor -= 1) {
            values[cursor] = values[cursor - 1];
        }
        values[cursor] = value;
    }
}

fn derivedResidualEffects(comptime externals: anytype, comptime limits: protocol.Limits) [externals.len]protocol.ResidualEffect {
    var result: [externals.len]protocol.ResidualEffect = undefined;
    inline for (externals, 0..) |Binding, index| {
        result[index] = .{
            .interface_id = Binding.interface_id,
            .site_id = Binding.Site.canonical_fingerprint,
            .payload_schema_id = valueSchemaId(Binding.Site.Payload),
            .result_schema_id = valueSchemaId(Binding.Response),
            .allowed_statuses = Binding.allowed_statuses,
            .authority_requirements = Binding.authority_requirements,
        };
    }
    insertionSortResiduals(&result);
    _ = limits;
    return result;
}

fn residualOrder(lhs: protocol.ResidualEffect, rhs: protocol.ResidualEffect) std.math.Order {
    const interface_order = std.mem.order(u8, &lhs.interface_id, &rhs.interface_id);
    if (interface_order != .eq) return interface_order;
    return std.math.order(lhs.site_id, rhs.site_id);
}

fn insertionSortResiduals(values: []protocol.ResidualEffect) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and residualOrder(value, values[cursor - 1]) == .lt) : (cursor -= 1) {
            values[cursor] = values[cursor - 1];
        }
        values[cursor] = value;
    }
}

fn requiredCapabilities(effects: []const protocol.ResidualEffect) u64 {
    var result: u64 = 0;
    for (effects) |effect| result |= effect.authority_requirements;
    return result;
}

pub fn application(comptime spec: anytype) type {
    @setEvalBranchQuota(10_000_000);
    if (!@hasField(@TypeOf(spec), "name") or !@hasField(@TypeOf(spec), "version") or !@hasField(@TypeOf(spec), "root")) {
        @compileError("world.application requires name, version, and root fields");
    }
    const name: []const u8 = spec.name;
    const version: []const u8 = spec.version;
    const Root = spec.root;
    const handlers = if (@hasField(@TypeOf(spec), "handlers")) spec.handlers else .{};
    const externals = if (@hasField(@TypeOf(spec), "external")) spec.external else .{};
    const limits = normalizedLimits(spec);
    comptime validateApplicationSpec(Root, handlers, externals, limits);
    const maximum_runtime_state_bytes: u32 = @intCast(
        runtime_state_header_bytes + maximumMachineStackBytes(Root, handlers),
    );
    const handler_ids = derivedHandlerIds(handlers);
    const residual_effects = derivedResidualEffects(externals, limits);
    const boundary_version: []const u8 = if (@hasField(@TypeOf(spec), "boundary_package_version"))
        spec.boundary_package_version
    else
        boundary.Protocol.Manifest.boundary_package_version;
    const world_version: []const u8 = if (@hasField(@TypeOf(spec), "world_package_version")) spec.world_package_version else "1.0.0-rc.2";

    return struct {
        const Self = @This();
        pub const State = []const u8;
        pub const RootMachine = Root;
        pub const StepInput = protocol.StepInput;
        pub const Frame = protocol.Frame;
        pub const EffectRequest = protocol.EffectRequest;
        pub const EffectResult = protocol.EffectResult;
        pub const internal_handler_ids = handler_ids;
        pub const residual_effect_row = residual_effects;
        pub const Limits = limits;
        pub const maximum_encoded_runtime_state_bytes = maximum_runtime_state_bytes;
        pub const Manifest: protocol.ApplicationManifest = blk: {
            var manifest: protocol.ApplicationManifest = .{
                .application_name = name,
                .application_version = version,
                .boundary_package_version = boundary_version,
                .boundary_static_machine_abi_version = Root.abi_version,
                .world_package_version = world_version,
                .root_program_id = machineId(Root),
                .internal_handler_ids = &handler_ids,
                .residual_effects = &residual_effects,
                .limits = limits,
                .required_host_capabilities = requiredCapabilities(&residual_effects),
            };
            manifest.seal(undefined) catch |err| @compileError("World application manifest derivation failed: " ++ @errorName(err));
            break :blk manifest;
        };

        pub fn encodeInitialArgs(allocator: std.mem.Allocator, args: Root.InitialArgs) protocol.Error![]u8 {
            return encodeValueBounded(allocator, args, limits.maximum_initial_args_bytes);
        }

        pub fn encodeFrame(allocator: std.mem.Allocator, frame: Frame) protocol.Error![]u8 {
            if (!std.mem.eql(u8, &frame.application_id, &Manifest.application_id)) return error.ApplicationMismatch;
            return frame.encode(allocator, limits);
        }

        /// Decode a borrowed Frame whose slice storage belongs to `arena`.
        pub fn decodeFrame(arena: *std.heap.ArenaAllocator, bytes: []const u8) protocol.Error!Frame {
            const frame = try Frame.decode(arena, bytes, limits);
            if (!std.mem.eql(u8, &frame.application_id, &Manifest.application_id)) return error.ApplicationMismatch;
            return frame;
        }

        pub fn validateFrame(frame: Frame) protocol.Error!void {
            try frame.validate(limits);
            if (!std.mem.eql(u8, &frame.application_id, &Manifest.application_id)) return error.ApplicationMismatch;
        }

        /// Produce a borrowed Frame whose slice storage belongs to `arena`.
        pub fn step(arena: *std.heap.ArenaAllocator, input: StepInput) protocol.Error!Frame {
            const allocator = arena.allocator();
            try input.validate(limits);
            if (!std.mem.eql(u8, &input.application_id, &Manifest.application_id)) return error.ApplicationMismatch;

            var fuel = input.fuel;
            if (input.prior_frame_bytes == null) {
                var initial_args = try decodeValueBounded(
                    allocator,
                    Root.InitialArgs,
                    input.initial_args_bytes.?,
                    limits.maximum_initial_args_bytes,
                );
                defer initial_args.deinit();
                const machine_state = Root.initialState(allocator, initial_args.value) catch |err| return mapMachineStateError(err);
                defer Root.deinitState(machine_state);
                const encoded_machine = Root.encodeState(allocator, machine_state) catch |err| return mapMachineStateError(err);
                var runtime_state = RuntimeState.init(allocator);
                defer runtime_state.deinit();
                runtime_state.push(.{
                    .machine_id = 0,
                    .parent_binding_index = root_binding_index,
                    .state_bytes = encoded_machine,
                }) catch |err| {
                    allocator.free(encoded_machine);
                    return err;
                };
                var counters: protocol.ResourceCounters = .{};
                return drive(
                    allocator,
                    &runtime_state,
                    null,
                    0,
                    null,
                    &fuel,
                    &counters,
                );
            }

            const prior = try Frame.decode(arena, input.prior_frame_bytes.?, limits);
            if (!std.mem.eql(u8, &prior.application_id, &Manifest.application_id)) return error.ApplicationMismatch;
            if (!std.mem.eql(u8, &prior.frame_id, &input.expected_parent_frame_id.?)) return error.InvalidFrame;
            if (prior.status != .needs_effect and prior.status != .yielded_fuel) return error.InvalidFrame;

            var runtime_state = try RuntimeState.decode(allocator, prior.state_bytes, Manifest.application_id, limits);
            defer runtime_state.deinit();
            try validateRuntimeState(&runtime_state);

            var counters = prior.resource_counters;
            var accepted_result_id: ?protocol.Digest = null;
            const next_sequence = std.math.add(u64, prior.sequence, 1) catch return error.LimitExceeded;
            if (prior.status == .needs_effect) {
                const request = prior.pending_effect orelse return error.InvalidFrame;
                const result = input.effect_result orelse return error.UnexpectedResultTarget;
                try protocol.validateResultForRequest(request, result, limits);
                const apply_result = try applyPendingResult(
                    allocator,
                    &runtime_state,
                    prior,
                    result,
                    &counters,
                );
                if (apply_result == .deferred) return prior;
                accepted_result_id = result.result_id;
                if (apply_result == .terminal_failure) {
                    return failureFrame(
                        allocator,
                        prior.frame_id,
                        next_sequence,
                        accepted_result_id,
                        &counters,
                        effectFailureLabel(result.status),
                    );
                }
            } else if (input.effect_result != null) {
                return error.UnexpectedResultTarget;
            }

            return drive(
                allocator,
                &runtime_state,
                prior.frame_id,
                next_sequence,
                accepted_result_id,
                &fuel,
                &counters,
            );
        }

        pub fn initialFrame(
            arena: *std.heap.ArenaAllocator,
            args_bytes: []const u8,
            fuel: u64,
        ) protocol.Error!Frame {
            return step(arena, .{
                .application_id = Manifest.application_id,
                .initial_args_bytes = args_bytes,
                .fuel = fuel,
            });
        }

        pub fn encodeExternalResult(
            allocator: std.mem.Allocator,
            comptime Site: type,
            value: anytype,
        ) protocol.Error![]u8 {
            const Binding = externalBindingForSite(Site, externals);
            if (@TypeOf(value) != Binding.Response) @compileError("World external result value has the wrong type for this binding");
            return encodeValueBounded(
                allocator,
                value,
                Binding.configured_maximum_result_bytes orelse limits.maximum_result_bytes,
            );
        }

        pub fn decodeFinalResult(
            allocator: std.mem.Allocator,
            frame: Frame,
        ) protocol.Error!DecodedValue(Root.Result) {
            try validateFrame(frame);
            if (frame.status != .completed or frame.final_result_bytes == null or
                !std.mem.eql(u8, &frame.final_result_schema_id.?, &valueSchemaId(Root.Result)))
            {
                return error.InvalidFrame;
            }
            return decodeValueBounded(allocator, Root.Result, frame.final_result_bytes.?, limits.maximum_result_bytes);
        }

        const ApplyResult = enum {
            resumed,
            deferred,
            terminal_failure,
        };

        const DriveOutcome = union(enum) {
            continue_reduction,
            frame: Frame,
        };

        fn mapMachineStateError(err: anyerror) protocol.Error {
            return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFrame;
        }

        fn effectFailureLabel(status: protocol.EffectStatus) []const u8 {
            return switch (status) {
                .ok => "effect result unexpectedly lacked an ok value",
                .rejected => "external effect rejected",
                .failed => "external effect failed",
                .deferred => "external effect deferred",
                .cancelled => "external effect cancelled",
            };
        }

        fn validateRuntimeState(state: *const RuntimeState) protocol.Error!void {
            if (state.frames.items.len == 0 or state.frames.items[0].machine_id != 0 or
                state.frames.items[0].parent_binding_index != root_binding_index)
            {
                return error.InvalidFrame;
            }
            for (state.frames.items[1..]) |frame| {
                if (frame.parent_binding_index >= handlers.len or
                    frame.machine_id != frame.parent_binding_index + 1)
                {
                    return error.InvalidFrame;
                }
            }
        }

        fn addCounter(counter: *u64, amount: u64) protocol.Error!void {
            counter.* = std.math.add(u64, counter.*, amount) catch return error.LimitExceeded;
        }

        fn drive(
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            fuel: *u64,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!Frame {
            while (true) {
                try validateRuntimeState(state);
                const machine_id_value = state.frames.items[state.frames.items.len - 1].machine_id;
                const outcome = if (machine_id_value == 0)
                    try driveMachine(
                        Root,
                        allocator,
                        state,
                        parent_frame_id,
                        sequence,
                        accepted_result_id,
                        fuel,
                        counters,
                    )
                else blk: {
                    inline for (handlers, 0..) |Binding, index| {
                        if (machine_id_value == index + 1) {
                            break :blk try driveMachine(
                                Binding.Provider,
                                allocator,
                                state,
                                parent_frame_id,
                                sequence,
                                accepted_result_id,
                                fuel,
                                counters,
                            );
                        }
                    }
                    return error.InvalidFrame;
                };
                switch (outcome) {
                    .continue_reduction => continue,
                    .frame => |frame| return frame,
                }
            }
        }

        fn driveMachine(
            comptime Machine: type,
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            fuel: *u64,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!DriveOutcome {
            const top = &state.frames.items[state.frames.items.len - 1];
            const machine_state = Machine.decodeState(allocator, top.state_bytes) catch |err| return mapMachineStateError(err);
            defer Machine.deinitState(machine_state);
            const fuel_before = fuel.*;
            const transition = Machine.reduce(machine_state, fuel) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                if (err == error.ProgramContractViolation) return error.InvalidFrame;
                return .{ .frame = try failureFrame(
                    allocator,
                    parent_frame_id,
                    sequence,
                    accepted_result_id,
                    counters,
                    @errorName(err),
                ) };
            };
            if (fuel.* > fuel_before) return error.InvalidFrame;
            try addCounter(&counters.instructions, fuel_before - fuel.*);

            return switch (transition) {
                .yielded_fuel => .{ .frame = try yieldedFrame(
                    Machine,
                    allocator,
                    machine_state,
                    state,
                    parent_frame_id,
                    sequence,
                    accepted_result_id,
                    counters,
                ) },
                .after => error.InvalidFrame,
                .request => |request| try handleMachineRequest(
                    Machine,
                    allocator,
                    machine_state,
                    request,
                    state,
                    parent_frame_id,
                    sequence,
                    accepted_result_id,
                    counters,
                ),
                .done => |raw_result| blk: {
                    var done = raw_result;
                    defer done.deinit();
                    if (state.frames.items.len == 1) {
                        break :blk .{ .frame = try completedFrame(
                            allocator,
                            parent_frame_id,
                            sequence,
                            accepted_result_id,
                            counters,
                            done.value(),
                        ) };
                    }
                    try finishProvider(Machine, allocator, state, done.value(), counters);
                    break :blk .continue_reduction;
                },
            };
        }

        fn handleMachineRequest(
            comptime Machine: type,
            allocator: std.mem.Allocator,
            machine_state: Machine.State,
            request: Machine.Request,
            state: *RuntimeState,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!DriveOutcome {
            inline for (Machine.EffectRow.operation_site_metadata) |metadata| {
                if (request.operation_site_index == metadata.index) {
                    const Site = Machine.EffectRow.siteByIndex(metadata.index);
                    request.expectSite(Site) catch return error.InvalidFrame;
                    inline for (handlers, 0..) |Binding, binding_index| {
                        if (comptime bindingTargets(Binding, Site)) {
                            try beginProvider(
                                Binding,
                                binding_index,
                                Machine,
                                allocator,
                                machine_state,
                                request,
                                state,
                                counters,
                            );
                            return .continue_reduction;
                        }
                    }
                    inline for (externals) |Binding| {
                        if (comptime bindingTargets(Binding, Site)) {
                            return .{ .frame = try externalFrame(
                                Binding,
                                Machine,
                                allocator,
                                machine_state,
                                request,
                                state,
                                parent_frame_id,
                                sequence,
                                accepted_result_id,
                                counters,
                            ) };
                        }
                    }
                    return error.InvalidFrame;
                }
            }
            return error.InvalidFrame;
        }

        fn replaceTopMachineState(
            comptime Machine: type,
            allocator: std.mem.Allocator,
            machine_state: Machine.State,
            state: *RuntimeState,
        ) protocol.Error!void {
            const encoded = Machine.encodeState(allocator, machine_state) catch |err| return mapMachineStateError(err);
            state.replaceTop(encoded) catch |err| {
                allocator.free(encoded);
                return err;
            };
        }

        fn beginProvider(
            comptime Binding: type,
            comptime binding_index: usize,
            comptime ParentMachine: type,
            allocator: std.mem.Allocator,
            parent_state: ParentMachine.State,
            request: ParentMachine.Request,
            state: *RuntimeState,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!void {
            const frame_count = std.math.cast(u64, state.frames.items.len) orelse return error.LimitExceeded;
            const maximum_frame_count = @as(u64, limits.maximum_provider_depth) + 1;
            if (frame_count >= maximum_frame_count) return error.LimitExceeded;
            const payload = request.payload(Binding.Site.Payload) catch return error.InvalidFrame;
            const provider_state = Binding.Provider.initialState(allocator, .{payload}) catch |err| return mapMachineStateError(err);
            defer Binding.Provider.deinitState(provider_state);
            const provider_bytes = Binding.Provider.encodeState(allocator, provider_state) catch |err| return mapMachineStateError(err);
            errdefer allocator.free(provider_bytes);
            try replaceTopMachineState(ParentMachine, allocator, parent_state, state);
            try state.push(.{
                .machine_id = @intCast(binding_index + 1),
                .parent_binding_index = @intCast(binding_index),
                .state_bytes = provider_bytes,
            });
            try addCounter(&counters.internal_handler_calls, 1);
        }

        fn finishProvider(
            comptime Provider: type,
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            value: Provider.Result,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!void {
            const provider_frame = try state.pop();
            defer allocator.free(provider_frame.state_bytes);
            if (state.frames.items.len == 0 or provider_frame.parent_binding_index >= handlers.len) return error.InvalidFrame;
            inline for (handlers, 0..) |Binding, binding_index| {
                if (provider_frame.parent_binding_index == binding_index) {
                    if (comptime Binding.Provider == Provider) {
                        try resumeParent(Binding, allocator, state, value);
                        try addCounter(&counters.continuation_operations, 1);
                        return;
                    } else {
                        return error.InvalidFrame;
                    }
                }
            }
            return error.InvalidFrame;
        }

        fn resumeParent(
            comptime Binding: type,
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            value: Binding.Provider.Result,
        ) protocol.Error!void {
            const parent_machine_id = state.frames.items[state.frames.items.len - 1].machine_id;
            if (parent_machine_id == 0) return resumeParentMachine(Binding, Root, allocator, state, value);
            inline for (handlers, 0..) |ParentBinding, index| {
                if (parent_machine_id == index + 1) {
                    return resumeParentMachine(Binding, ParentBinding.Provider, allocator, state, value);
                }
            }
            return error.InvalidFrame;
        }

        fn resumeParentMachine(
            comptime Binding: type,
            comptime ParentMachine: type,
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            value: Binding.Provider.Result,
        ) protocol.Error!void {
            if (comptime !machineOwnsSite(ParentMachine, Binding.Site)) return error.InvalidFrame;
            const parent_frame = &state.frames.items[state.frames.items.len - 1];
            const parent_state = ParentMachine.decodeState(allocator, parent_frame.state_bytes) catch |err| return mapMachineStateError(err);
            defer ParentMachine.deinitState(parent_state);
            const current = ParentMachine.current(parent_state) catch return error.InvalidFrame;
            const request = switch (current) {
                .request => |request| request,
                else => return error.InvalidFrame,
            };
            request.expectSite(Binding.Site) catch return error.InvalidFrame;
            ParentMachine.@"resume"(parent_state, request, value) catch |err| return mapMachineStateError(err);
            try replaceTopMachineState(ParentMachine, allocator, parent_state, state);
        }

        fn externalFrame(
            comptime Binding: type,
            comptime Machine: type,
            allocator: std.mem.Allocator,
            machine_state: Machine.State,
            request: Machine.Request,
            state: *RuntimeState,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!Frame {
            try replaceTopMachineState(Machine, allocator, machine_state, state);
            const effect_request = try makeEffectRequest(Binding, allocator, request, parent_frame_id, sequence);
            const state_bytes = try state.encode(Manifest.application_id, limits);
            errdefer allocator.free(state_bytes);
            try addCounter(&counters.external_effects, 1);
            try addCounter(&counters.value_bytes, @intCast(effect_request.payload_bytes.len));
            var frame: Frame = .{
                .application_id = Manifest.application_id,
                .parent_frame_id = parent_frame_id,
                .sequence = sequence,
                .state_bytes = state_bytes,
                .pending_effect = effect_request,
                .accepted_effect_result_id = accepted_result_id,
                .status = .needs_effect,
                .resource_counters = counters.*,
            };
            try frame.seal(allocator, limits);
            return frame;
        }

        fn makeEffectRequest(
            comptime Binding: type,
            allocator: std.mem.Allocator,
            request: anytype,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
        ) protocol.Error!protocol.EffectRequest {
            const payload = request.payload(Binding.Site.Payload) catch return error.InvalidFrame;
            const payload_bytes = try encodeValueBounded(allocator, payload, limits.maximum_payload_bytes);
            errdefer allocator.free(payload_bytes);
            var effect_request: protocol.EffectRequest = .{
                .application_id = Manifest.application_id,
                .parent_frame_id = parent_frame_id orelse protocol.zero_digest,
                .sequence = sequence,
                .site_id = Binding.Site.canonical_fingerprint,
                .interface_id = Binding.interface_id,
                .payload_schema_id = valueSchemaId(Binding.Site.Payload),
                .result_schema_id = valueSchemaId(Binding.Response),
                .allowed_statuses = Binding.allowed_statuses,
                .payload_bytes = payload_bytes,
                .authority_requirements = Binding.authority_requirements,
                .limits = .{
                    .maximum_result_bytes = Binding.configured_maximum_result_bytes orelse limits.maximum_result_bytes,
                    .maximum_attempts = Binding.maximum_attempts,
                },
            };
            try effect_request.seal(allocator, limits);
            try effect_request.validate(limits);
            return effect_request;
        }

        fn applyPendingResult(
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            prior: Frame,
            result: protocol.EffectResult,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!ApplyResult {
            const machine_id_value = state.frames.items[state.frames.items.len - 1].machine_id;
            if (machine_id_value == 0) return applyResultForMachine(Root, allocator, state, prior, result, counters);
            inline for (handlers, 0..) |Binding, index| {
                if (machine_id_value == index + 1) {
                    return applyResultForMachine(Binding.Provider, allocator, state, prior, result, counters);
                }
            }
            return error.InvalidFrame;
        }

        fn applyResultForMachine(
            comptime Machine: type,
            allocator: std.mem.Allocator,
            state: *RuntimeState,
            prior: Frame,
            result: protocol.EffectResult,
            counters: *protocol.ResourceCounters,
        ) protocol.Error!ApplyResult {
            const top = &state.frames.items[state.frames.items.len - 1];
            const machine_state = Machine.decodeState(allocator, top.state_bytes) catch |err| return mapMachineStateError(err);
            defer Machine.deinitState(machine_state);
            const current = Machine.current(machine_state) catch return error.InvalidFrame;
            const request = switch (current) {
                .request => |request| request,
                else => return error.InvalidFrame,
            };
            inline for (Machine.EffectRow.operation_site_metadata) |metadata| {
                if (request.operation_site_index == metadata.index) {
                    const Site = Machine.EffectRow.siteByIndex(metadata.index);
                    request.expectSite(Site) catch return error.InvalidFrame;
                    inline for (externals) |Binding| {
                        if (comptime bindingTargets(Binding, Site)) {
                            const expected = try makeEffectRequest(
                                Binding,
                                allocator,
                                request,
                                prior.parent_frame_id,
                                prior.sequence,
                            );
                            if (!std.mem.eql(u8, &expected.request_id, &prior.pending_effect.?.request_id)) return error.InvalidFrame;
                            if (result.status == .deferred) return .deferred;
                            if (result.status != .ok) return .terminal_failure;
                            var decoded = try decodeValueBounded(
                                allocator,
                                Binding.Response,
                                result.result_bytes.?,
                                expected.limits.maximum_result_bytes,
                            );
                            defer decoded.deinit();
                            switch (Binding.response_mode) {
                                .@"resume" => Machine.@"resume"(machine_state, request, decoded.value) catch |err| return mapMachineStateError(err),
                                .return_now => Machine.returnNow(machine_state, request, decoded.value) catch |err| return mapMachineStateError(err),
                            }
                            try replaceTopMachineState(Machine, allocator, machine_state, state);
                            try addCounter(&counters.continuation_operations, 1);
                            try addCounter(&counters.value_bytes, @intCast(result.result_bytes.?.len));
                            return .resumed;
                        }
                    }
                    return error.InvalidFrame;
                }
            }
            return error.InvalidFrame;
        }

        fn yieldedFrame(
            comptime Machine: type,
            allocator: std.mem.Allocator,
            machine_state: Machine.State,
            state: *RuntimeState,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            counters: *const protocol.ResourceCounters,
        ) protocol.Error!Frame {
            try replaceTopMachineState(Machine, allocator, machine_state, state);
            const state_bytes = try state.encode(Manifest.application_id, limits);
            errdefer allocator.free(state_bytes);
            var frame: Frame = .{
                .application_id = Manifest.application_id,
                .parent_frame_id = parent_frame_id,
                .sequence = sequence,
                .state_bytes = state_bytes,
                .accepted_effect_result_id = accepted_result_id,
                .status = .yielded_fuel,
                .resource_counters = counters.*,
            };
            try frame.seal(allocator, limits);
            return frame;
        }

        fn completedFrame(
            allocator: std.mem.Allocator,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            counters: *const protocol.ResourceCounters,
            value: Root.Result,
        ) protocol.Error!Frame {
            const state_bytes = allocator.alloc(u8, 0) catch return error.OutOfMemory;
            errdefer allocator.free(state_bytes);
            const result_bytes = try encodeValueBounded(allocator, value, limits.maximum_result_bytes);
            errdefer allocator.free(result_bytes);
            var frame: Frame = .{
                .application_id = Manifest.application_id,
                .parent_frame_id = parent_frame_id,
                .sequence = sequence,
                .state_bytes = state_bytes,
                .accepted_effect_result_id = accepted_result_id,
                .status = .completed,
                .final_result_schema_id = valueSchemaId(Root.Result),
                .final_result_bytes = result_bytes,
                .resource_counters = counters.*,
            };
            try frame.seal(allocator, limits);
            return frame;
        }

        fn failureFrame(
            allocator: std.mem.Allocator,
            parent_frame_id: ?protocol.Digest,
            sequence: u64,
            accepted_result_id: ?protocol.Digest,
            counters: *const protocol.ResourceCounters,
            failure: []const u8,
        ) protocol.Error!Frame {
            const state_bytes = allocator.alloc(u8, 0) catch return error.OutOfMemory;
            errdefer allocator.free(state_bytes);
            const owned_failure = allocator.dupe(u8, failure) catch return error.OutOfMemory;
            errdefer allocator.free(owned_failure);
            var frame: Frame = .{
                .application_id = Manifest.application_id,
                .parent_frame_id = parent_frame_id,
                .sequence = sequence,
                .state_bytes = state_bytes,
                .accepted_effect_result_id = accepted_result_id,
                .status = .failed,
                .failure = owned_failure,
                .resource_counters = counters.*,
            };
            try frame.seal(allocator, limits);
            return frame;
        }

        comptime {
            _ = Self;
        }
    };
}

const ValueWriter = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *@This()) void {
        self.bytes.deinit(self.allocator);
    }

    fn toOwnedSlice(self: *@This()) protocol.Error![]u8 {
        return self.bytes.toOwnedSlice(self.allocator) catch error.OutOfMemory;
    }

    fn write(self: *@This(), value: []const u8) protocol.Error!void {
        self.bytes.appendSlice(self.allocator, value) catch return error.OutOfMemory;
    }

    fn writeU8(self: *@This(), value: u8) protocol.Error!void {
        self.bytes.append(self.allocator, value) catch return error.OutOfMemory;
    }

    fn writeU32(self: *@This(), value: u32) protocol.Error!void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.write(&bytes);
    }

    fn writeU64(self: *@This(), value: u64) protocol.Error!void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        try self.write(&bytes);
    }

    fn writeLenBytes(self: *@This(), value: []const u8) protocol.Error!void {
        if (value.len > std.math.maxInt(u32)) return error.LimitExceeded;
        try self.writeU32(@intCast(value.len));
        try self.write(value);
    }
};

fn encodeTyped(writer: *ValueWriter, comptime T: type, value: T) protocol.Error!void {
    switch (@typeInfo(T)) {
        .void => {},
        .bool => try writer.writeU8(@intFromBool(value)),
        .int => |info| {
            if (info.bits > 64) @compileError("World value codec supports integers up to 64 bits");
            if (info.signedness == .signed) {
                try writer.writeU64(@bitCast(@as(i64, @intCast(value))));
            } else {
                try writer.writeU64(@intCast(value));
            }
        },
        .pointer => {
            if (T == []const u8) {
                try writer.writeLenBytes(value);
            } else if (T == []const []const u8) {
                if (value.len > std.math.maxInt(u32)) return error.LimitExceeded;
                try writer.writeU32(@intCast(value.len));
                for (value) |item| try writer.writeLenBytes(item);
            } else {
                @compileError("World value codec does not support this pointer type");
            }
        },
        .optional => |info| {
            try writer.writeU8(@intFromBool(value != null));
            if (value) |payload| try encodeTyped(writer, info.child, payload);
        },
        .@"enum" => try writer.writeU64(@intCast(@intFromEnum(value))),
        .@"struct" => |info| inline for (info.fields) |field| {
            try encodeTyped(writer, field.type, @field(value, field.name));
        },
        .@"union" => |info| {
            const Tag = info.tag_type orelse @compileError("World value codec requires tagged unions");
            const tag = std.meta.activeTag(value);
            try writer.writeU64(@intCast(@intFromEnum(tag)));
            inline for (info.fields) |field| {
                if (tag == @field(Tag, field.name)) {
                    try encodeTyped(writer, field.type, @field(value, field.name));
                    return;
                }
            }
            return error.InvalidEncoding;
        },
        else => @compileError("World value codec does not support this type"),
    }
}

fn encodeValueBounded(allocator: std.mem.Allocator, value: anytype, maximum: u32) protocol.Error![]u8 {
    var writer = ValueWriter.init(allocator);
    errdefer writer.deinit();
    try encodeTyped(&writer, @TypeOf(value), value);
    if (writer.bytes.items.len > maximum) return error.LimitExceeded;
    return writer.toOwnedSlice();
}

pub fn encodeValue(allocator: std.mem.Allocator, value: anytype) protocol.Error![]u8 {
    return encodeValueBounded(allocator, value, std.math.maxInt(u32));
}

const ValueReader = struct {
    bytes: []const u8,
    cursor: usize = 0,

    fn init(bytes: []const u8) @This() {
        return .{ .bytes = bytes };
    }

    fn finish(self: @This()) protocol.Error!void {
        if (self.cursor != self.bytes.len) return error.TrailingBytes;
    }

    fn read(self: *@This(), length: usize) protocol.Error![]const u8 {
        const end = std.math.add(usize, self.cursor, length) catch return error.InvalidEncoding;
        if (end > self.bytes.len) return error.InvalidEncoding;
        const value = self.bytes[self.cursor..end];
        self.cursor = end;
        return value;
    }

    fn readU8(self: *@This()) protocol.Error!u8 {
        return (try self.read(1))[0];
    }

    fn readBool(self: *@This()) protocol.Error!bool {
        return switch (try self.readU8()) {
            0 => false,
            1 => true,
            else => error.InvalidEncoding,
        };
    }

    fn readU32(self: *@This()) protocol.Error!u32 {
        return std.mem.readInt(u32, (try self.read(4))[0..4], .little);
    }

    fn readU64(self: *@This()) protocol.Error!u64 {
        return std.mem.readInt(u64, (try self.read(8))[0..8], .little);
    }

    fn readDigest(self: *@This()) protocol.Error!protocol.Digest {
        return (try self.read(protocol.zero_digest.len))[0..protocol.zero_digest.len].*;
    }

    fn readLenBytes(self: *@This(), maximum: u32) protocol.Error![]const u8 {
        const length = try self.readU32();
        if (length > maximum) return error.LimitExceeded;
        return self.read(length);
    }
};

fn DecodedValue(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }
    };
}

fn decodeTyped(
    reader: *ValueReader,
    arena: std.mem.Allocator,
    comptime T: type,
    maximum_collection: u32,
) protocol.Error!T {
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => try reader.readBool(),
        .int => |info| blk: {
            if (info.bits > 64) @compileError("World value codec supports integers up to 64 bits");
            const encoded = try reader.readU64();
            if (info.signedness == .signed) {
                const signed: i64 = @bitCast(encoded);
                break :blk std.math.cast(T, signed) orelse return error.InvalidEncoding;
            }
            break :blk std.math.cast(T, encoded) orelse return error.InvalidEncoding;
        },
        .pointer => blk: {
            if (T == []const u8) {
                const value = try reader.readLenBytes(maximum_collection);
                break :blk arena.dupe(u8, value) catch return error.OutOfMemory;
            }
            if (T == []const []const u8) {
                const count = try reader.readU32();
                if (count > maximum_collection) return error.LimitExceeded;
                const values = arena.alloc([]const u8, count) catch return error.OutOfMemory;
                for (values) |*value| {
                    value.* = arena.dupe(u8, try reader.readLenBytes(maximum_collection)) catch return error.OutOfMemory;
                }
                break :blk values;
            }
            @compileError("World value codec does not support this pointer type");
        },
        .optional => |info| if (try reader.readBool())
            try decodeTyped(reader, arena, info.child, maximum_collection)
        else
            null,
        .@"enum" => |info| blk: {
            const raw = try reader.readU64();
            const tag_value = std.math.cast(info.tag_type, raw) orelse return error.InvalidEncoding;
            break :blk std.meta.intToEnum(T, tag_value) catch return error.InvalidEncoding;
        },
        .@"struct" => |info| blk: {
            var value: T = undefined;
            inline for (info.fields) |field| {
                @field(value, field.name) = try decodeTyped(reader, arena, field.type, maximum_collection);
            }
            break :blk value;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type orelse @compileError("World value codec requires tagged unions");
            const TagInfo = @typeInfo(Tag).@"enum";
            const raw = try reader.readU64();
            const tag_value = std.math.cast(TagInfo.tag_type, raw) orelse return error.InvalidEncoding;
            const tag = std.meta.intToEnum(Tag, tag_value) catch return error.InvalidEncoding;
            inline for (info.fields) |field| {
                if (tag == @field(Tag, field.name)) {
                    const payload = try decodeTyped(reader, arena, field.type, maximum_collection);
                    break :blk @unionInit(T, field.name, payload);
                }
            }
            return error.InvalidEncoding;
        },
        else => @compileError("World value codec does not support this type"),
    };
}

fn decodeValueBounded(
    allocator: std.mem.Allocator,
    comptime T: type,
    bytes: []const u8,
    maximum: u32,
) protocol.Error!DecodedValue(T) {
    if (bytes.len > maximum) return error.LimitExceeded;
    var owned = DecodedValue(T){
        .arena = std.heap.ArenaAllocator.init(allocator),
        .value = undefined,
    };
    errdefer owned.arena.deinit();
    var reader = ValueReader.init(bytes);
    owned.value = try decodeTyped(&reader, owned.arena.allocator(), T, maximum);
    try reader.finish();
    return owned;
}

const application_state_magic = "WRLDAPP1";
const application_state_version: u32 = 1;
const root_binding_index = std.math.maxInt(u32);

const RuntimeMachineFrame = struct {
    machine_id: u32,
    parent_binding_index: u32,
    state_bytes: []u8,
};

const RuntimeState = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(RuntimeMachineFrame) = .empty,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *@This()) void {
        for (self.frames.items) |frame| self.allocator.free(frame.state_bytes);
        self.frames.deinit(self.allocator);
    }

    fn push(self: *@This(), frame: RuntimeMachineFrame) protocol.Error!void {
        self.frames.append(self.allocator, frame) catch return error.OutOfMemory;
    }

    fn replaceTop(self: *@This(), bytes: []u8) protocol.Error!void {
        if (self.frames.items.len == 0) return error.InvalidFrame;
        const top = &self.frames.items[self.frames.items.len - 1];
        self.allocator.free(top.state_bytes);
        top.state_bytes = bytes;
    }

    fn pop(self: *@This()) protocol.Error!RuntimeMachineFrame {
        return self.frames.pop() orelse error.InvalidFrame;
    }

    fn encode(
        self: *const @This(),
        application_id: protocol.Digest,
        limits: protocol.Limits,
    ) protocol.Error![]u8 {
        const frame_count = std.math.cast(u64, self.frames.items.len) orelse return error.LimitExceeded;
        const maximum_frame_count = @as(u64, limits.maximum_provider_depth) + 1;
        if (frame_count == 0 or frame_count > maximum_frame_count) {
            return error.InvalidFrame;
        }
        var writer = ValueWriter.init(self.allocator);
        errdefer writer.deinit();
        try writer.write(application_state_magic);
        try writer.writeU32(application_state_version);
        try writer.write(&application_id);
        if (self.frames.items.len > std.math.maxInt(u32)) return error.LimitExceeded;
        try writer.writeU32(@intCast(self.frames.items.len));
        for (self.frames.items) |frame| {
            try writer.writeU32(frame.machine_id);
            try writer.writeU32(frame.parent_binding_index);
            try writer.writeLenBytes(frame.state_bytes);
        }
        if (writer.bytes.items.len > limits.maximum_state_bytes) return error.LimitExceeded;
        return writer.toOwnedSlice();
    }

    fn decode(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        application_id: protocol.Digest,
        limits: protocol.Limits,
    ) protocol.Error!@This() {
        if (bytes.len == 0 or bytes.len > limits.maximum_state_bytes) return error.InvalidFrame;
        var reader = ValueReader.init(bytes);
        if (!std.mem.eql(u8, try reader.read(application_state_magic.len), application_state_magic)) return error.InvalidEncoding;
        if (try reader.readU32() != application_state_version) return error.UnsupportedVersion;
        const encoded_application_id = try reader.readDigest();
        if (!std.mem.eql(u8, &encoded_application_id, &application_id)) return error.ApplicationMismatch;
        const count = try reader.readU32();
        const maximum_frame_count = @as(u64, limits.maximum_provider_depth) + 1;
        if (count == 0 or @as(u64, count) > maximum_frame_count) return error.InvalidFrame;
        var result = RuntimeState.init(allocator);
        errdefer result.deinit();
        for (0..count) |_| {
            const machine_id = try reader.readU32();
            const parent_binding_index = try reader.readU32();
            const state_slice = try reader.readLenBytes(limits.maximum_state_bytes);
            const state_bytes = allocator.dupe(u8, state_slice) catch return error.OutOfMemory;
            errdefer allocator.free(state_bytes);
            try result.push(.{
                .machine_id = machine_id,
                .parent_binding_index = parent_binding_index,
                .state_bytes = state_bytes,
            });
        }
        try reader.finish();
        return result;
    }
};
