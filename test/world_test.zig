const boundary = @import("boundary");
const fixtures = @import("world_fixtures");
const std = @import("std");
const world = @import("world");

const PortsCtx = struct {
    calls: usize = 0,
    response: i32 = 7,
};

fn approve(ctx: *PortsCtx, payload: []const u8) !i32 {
    try std.testing.expectEqualStrings("deploy-prod", payload);
    ctx.calls += 1;
    return ctx.response;
}

fn approveRequest(ctx: *PortsCtx, request: world.PortRequest(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest)) !i32 {
    try request.expectPort(fixtures.Ports.ApprovalRequest);
    try std.testing.expectEqual(@as(u32, 0), request.world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.index, request.residual_site_index);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, request.residual_site_fingerprint);
    try std.testing.expectEqual(@as(?u32, 0), request.value_table_payload_id);
    try std.testing.expectEqual(@as(?u32, 1), request.value_table_response_id);
    try std.testing.expectEqualStrings("deploy-prod", try request.payload(fixtures.Ports.ApprovalRequest));
    ctx.calls += 1;
    return ctx.response;
}

fn failApproval(ctx: *PortsCtx, payload: []const u8) !i32 {
    try std.testing.expectEqualStrings("deploy-prod", payload);
    ctx.calls += 1;
    return error.HandlerFailed;
}

const PortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const FailingPortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, failApproval);
const PortsByIdDecl = world.portById(fixtures.Ports.Target, 0, fixtures.Ports.ApprovalRequest, approve);
const PortsRequestDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approveRequest);
const PortsNativeBinding = world.bind(PortsDecl, world.NativeAdapter(approve));
const FailingPortsNativeBinding = world.bind(FailingPortsDecl, world.NativeAdapter(failApproval));
const PortsAltNativeBinding = world.bind(PortsDecl, world.NativeAdapter(approveRequest));
const PortsReplayBinding = world.bind(PortsDecl, world.ReplayAdapter(0x7777_aaaa));
const PortsByteBinding = world.bind(PortsDecl, world.ByteAdapter("test-byte"));
const PortsPendingBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .pending_stub;
    pub const authority = world.PortAuthority.fixture;
    pub const value_policy = world.ValuePolicy.portable;
});
const PortsRejectBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .null_reject;
    pub const authority = world.PortAuthority.fixture;
    pub const value_policy = world.ValuePolicy.portable;
});
const PortsPortableAuthorityBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .native;
    pub const authority = world.PortAuthority.init(.{
        .authority_label = "portable-required",
        .authority_kind = .fixture,
        .requires_portable_values = true,
    });
    pub const value_policy = world.ValuePolicy.native_compatible;
});
const PortsNoNativeAuthorityBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .native;
    pub const authority = world.PortAuthority.init(.{
        .authority_label = "no-native",
        .authority_kind = .fixture,
        .allows_native_only_values = false,
    });
    pub const value_policy = world.ValuePolicy.native_compatible;
});
const PortsPayloadCapAuthorityBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .native;
    pub const authority = world.PortAuthority.init(.{
        .authority_label = "payload-cap",
        .authority_kind = .fixture,
        .max_payload_image_bytes = 1,
    });
    pub const value_policy = world.ValuePolicy.portable;
});
const PortsAcceptedPayloadCapBinding = world.bind(PortsDecl, struct {
    pub const kind: world.AdapterKind = .native;
    pub const authority = world.PortAuthority.init(.{
        .authority_label = "accepted-payload-cap",
        .authority_kind = .fixture,
        .max_payload_image_bytes = 1,
    });
    pub const value_policy = world.ValuePolicy{
        .require_portable_values = true,
        .allow_native_only_values = false,
        .max_value_image_bytes = 1,
    };
});
const PortsWrongPortBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id: u32 = 99;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
};
const PortsBindingRecordMutation = enum {
    wrong_surface,
    wrong_certificate,
    wrong_requirement,
    wrong_adapter,
    wrong_value_policy,
    wrong_authority,
    wrong_descriptor,
};
fn mutatedPortsBindingRecord(comptime mutation: PortsBindingRecordMutation) world.Binding {
    const record = PortsNativeBinding.bindingRecord();
    return world.Binding.init(.{
        .target_ref_fingerprint = record.target_ref_fingerprint,
        .world_surface_fingerprint = if (mutation == .wrong_surface) record.world_surface_fingerprint + 1 else record.world_surface_fingerprint,
        .target_certificate_fingerprint = if (mutation == .wrong_certificate) record.target_certificate_fingerprint + 1 else record.target_certificate_fingerprint,
        .world_port_id = record.world_port_id,
        .import_requirement_fingerprint = if (mutation == .wrong_requirement) record.import_requirement_fingerprint + 1 else record.import_requirement_fingerprint,
        .world_port_ref_fingerprint = record.world_port_ref_fingerprint,
        .source_effect_shape_ref_fingerprint = record.source_effect_shape_ref_fingerprint,
        .payload_value_table_id = record.payload_value_table_id,
        .response_value_table_id = record.response_value_table_id,
        .adapter_kind = if (mutation == .wrong_adapter) .replay else record.adapter_kind,
        .binding_mode_policy = record.binding_mode_policy,
        .value_policy = if (mutation == .wrong_value_policy) world.ValuePolicy.portable else record.value_policy,
        .authority_fingerprint = if (mutation == .wrong_authority) world.PortAuthority.fixture.authority_fingerprint else record.authority_fingerprint,
        .adapter_descriptor_fingerprint = if (mutation == .wrong_descriptor) record.adapter_descriptor_fingerprint + 1 else record.adapter_descriptor_fingerprint,
        .label = record.label,
        .tags = record.tags,
        .metadata = record.metadata,
    });
}
const PortsWrongSurfaceRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_surface);
    }
};
const PortsWrongCertificateRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_certificate);
    }
};
const PortsWrongRequirementRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_requirement);
    }
};
const PortsWrongAdapterRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_adapter);
    }
};
const PortsWrongValuePolicyRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_value_policy);
    }
};
const PortsWrongAuthorityRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_authority);
    }
};
const PortsWrongDescriptorRecordBinding = struct {
    pub const TargetType = fixtures.Ports.Target;
    pub const world_port_id = PortsDecl.world_port_id;
    pub const adapter_kind = world.AdapterKind.native;
    pub const authority = world.PortAuthority.native_function;
    pub const value_policy = world.ValuePolicy.native_compatible;
    pub fn bindingRecord() world.Binding {
        return mutatedPortsBindingRecord(.wrong_descriptor);
    }
};
const PortsEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsNativeBinding},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const FailingPortsEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{FailingPortsNativeBinding},
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const PortsReplayEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsReplayBinding},
    .policy = world.EnvironmentPolicy.strict_replay,
});
const PortsByteEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{PortsByteBinding},
    .policy = world.EnvironmentPolicy.test_fixture,
});
const PortsMissingEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{},
    .policy = world.EnvironmentPolicy.strict_fresh,
});
const PortsDuplicateEnv = world.Environment(fixtures.Ports.Target, .{
    .bindings = .{ PortsNativeBinding, PortsAltNativeBinding },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const PortsMachineEnv = world.Machine(fixtures.Ports.Target, .{
    .environment = PortsEnv,
    .strict_handler_coverage = true,
});
const FailingPortsMachineEnv = world.Machine(fixtures.Ports.Target, .{
    .environment = FailingPortsEnv,
    .strict_handler_coverage = true,
});
const PortsReplayMachineEnv = world.Machine(fixtures.Ports.Target, .{
    .environment = PortsReplayEnv,
});
const PortsMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{PortsDecl},
    .strict_handler_coverage = true,
});
const PortsRequestMachine = world.Machine(fixtures.Ports.Target, .{
    .ports = .{PortsRequestDecl},
    .strict_handler_coverage = true,
});

test "guest abi exposes stable v0 contract and status ordinals" {
    try std.testing.expectEqual(@as(u32, 1), world.world_guest_abi_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_guest_abi_contract_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 2), world.world_guest_conformance_vector_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 1), world.world_guest_conformance_report_fingerprint_version);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(world.Guest.Status.ok));
    try std.testing.expectEqual(@as(u32, 3), @intFromEnum(world.Guest.Status.parked));
    try std.testing.expectEqual(@as(u32, 6), @intFromEnum(world.Guest.Status.buffer_too_small));
    try std.testing.expectEqual(@as(u32, 13), @intFromEnum(world.Guest.Status.admission_failed));
    try std.testing.expectEqual(@as(usize, 16), world.Guest.Abi.required_exports.len);
    try std.testing.expect(world.Guest.Buffer.max_request_bytes > 0);
    try std.testing.expect(world.Guest.Buffer.max_response_bytes > 0);
    const contract = world.Guest.Abi.Contract{};
    try std.testing.expect(contract.fingerprint() != 0);
}

fn appendWasmU32(out: *std.ArrayList(u8), value: u32) !void {
    var remaining = value;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        try out.append(std.testing.allocator, byte);
        if (remaining == 0) break;
    }
}

fn appendWasmName(out: *std.ArrayList(u8), name: []const u8) !void {
    try appendWasmU32(out, @intCast(name.len));
    try out.appendSlice(std.testing.allocator, name);
}

fn appendWasmSection(module: *std.ArrayList(u8), section_id: u8, section: []const u8) !void {
    try module.append(std.testing.allocator, section_id);
    try appendWasmU32(module, @intCast(section.len));
    try module.appendSlice(std.testing.allocator, section);
}

fn appendWasmFuncType(out: *std.ArrayList(u8), param_count: u32, result_count: u32) !void {
    try out.append(std.testing.allocator, 0x60);
    try appendWasmU32(out, param_count);
    var param_index: u32 = 0;
    while (param_index < param_count) : (param_index += 1) try out.append(std.testing.allocator, 0x7f);
    try appendWasmU32(out, result_count);
    var result_index: u32 = 0;
    while (result_index < result_count) : (result_index += 1) try out.append(std.testing.allocator, 0x7f);
}

fn appendGuestWasmTypeSection(module: *std.ArrayList(u8)) !void {
    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(std.testing.allocator);
    try appendWasmU32(&types, 5);
    try appendWasmFuncType(&types, 0, 1);
    try appendWasmFuncType(&types, 1, 1);
    try appendWasmFuncType(&types, 2, 1);
    try appendWasmFuncType(&types, 3, 1);
    try appendWasmFuncType(&types, 2, 0);
    try appendWasmSection(module, 1, types.items);
}

fn appendGuestWasmMalformedTrailingTypeSection(module: *std.ArrayList(u8)) !void {
    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(std.testing.allocator);
    try appendWasmU32(&types, 6);
    try appendWasmFuncType(&types, 0, 1);
    try appendWasmFuncType(&types, 1, 1);
    try appendWasmFuncType(&types, 2, 1);
    try appendWasmFuncType(&types, 3, 1);
    try appendWasmFuncType(&types, 2, 0);
    try types.append(std.testing.allocator, 0x60);
    try appendWasmU32(&types, 1);
    try appendWasmSection(module, 1, types.items);
}

fn guestRequiredSignatureTypeIndex(required_index: usize) u32 {
    return switch (required_index) {
        5 => 1,
        6 => 3,
        7, 9, 11, 13, 15 => 2,
        else => 0,
    };
}

fn appendGuestWasmFunctionSection(module: *std.ArrayList(u8), wrong_signature: bool) !void {
    var functions: std.ArrayList(u8) = .empty;
    defer functions.deinit(std.testing.allocator);
    try appendWasmU32(&functions, @intCast(world.Guest.Abi.required_exports.len));
    for (world.Guest.Abi.required_exports, 0..) |_, index| {
        const type_index: u32 = if (wrong_signature and index == 2) 2 else guestRequiredSignatureTypeIndex(index);
        try appendWasmU32(&functions, type_index);
    }
    try appendWasmSection(module, 3, functions.items);
}

fn appendGuestWasmFunctionSectionWithAlloc(module: *std.ArrayList(u8)) !void {
    var functions: std.ArrayList(u8) = .empty;
    defer functions.deinit(std.testing.allocator);
    try appendWasmU32(&functions, @intCast(world.Guest.Abi.required_exports.len + 2));
    for (world.Guest.Abi.required_exports, 0..) |_, index| {
        try appendWasmU32(&functions, guestRequiredSignatureTypeIndex(index));
    }
    try appendWasmU32(&functions, 1);
    try appendWasmU32(&functions, 4);
    try appendWasmSection(module, 3, functions.items);
}

fn appendGuestWasmMemorySection(module: *std.ArrayList(u8)) !void {
    var memory: std.ArrayList(u8) = .empty;
    defer memory.deinit(std.testing.allocator);
    try appendWasmU32(&memory, 1);
    try memory.append(std.testing.allocator, 0);
    try appendWasmU32(&memory, 1);
    try appendWasmSection(module, 5, memory.items);
}

fn appendGuestWasmInvalidLimitMemorySection(module: *std.ArrayList(u8)) !void {
    var memory: std.ArrayList(u8) = .empty;
    defer memory.deinit(std.testing.allocator);
    try appendWasmU32(&memory, 1);
    try memory.append(std.testing.allocator, 2);
    try appendWasmU32(&memory, 1);
    try appendWasmSection(module, 5, memory.items);
}

fn appendGuestWasmCodeSectionWithAbiReturn(module: *std.ArrayList(u8), defined_function_count: usize, abi_version: u32, explicit_abi_return: bool) !void {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(std.testing.allocator);
    try appendWasmU32(&code, @intCast(defined_function_count));
    var index: usize = 0;
    while (index < defined_function_count) : (index += 1) {
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(std.testing.allocator);
        try appendWasmU32(&body, 0);
        if (index == 0) {
            try body.append(std.testing.allocator, 0x41);
            try appendWasmU32(&body, abi_version);
            if (explicit_abi_return) try body.append(std.testing.allocator, 0x0f);
        } else if (index < world.Guest.Abi.required_exports.len or index == world.Guest.Abi.required_exports.len) {
            try body.append(std.testing.allocator, 0x41);
            try appendWasmU32(&body, 0);
        }
        try body.append(std.testing.allocator, 0x0b);
        try appendWasmU32(&code, @intCast(body.items.len));
        try code.appendSlice(std.testing.allocator, body.items);
    }
    try appendWasmSection(module, 10, code.items);
}

fn appendGuestWasmCodeSection(module: *std.ArrayList(u8), defined_function_count: usize, abi_version: u32) !void {
    return appendGuestWasmCodeSectionWithAbiReturn(module, defined_function_count, abi_version, false);
}

fn appendGuestWasmShortCodeSection(module: *std.ArrayList(u8), abi_version: u32) !void {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(std.testing.allocator);
    try appendWasmU32(&code, 1);
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    try appendWasmU32(&body, 0);
    try body.append(std.testing.allocator, 0x41);
    try appendWasmU32(&body, abi_version);
    try body.append(std.testing.allocator, 0x0b);
    try appendWasmU32(&code, @intCast(body.items.len));
    try code.appendSlice(std.testing.allocator, body.items);
    try appendWasmSection(module, 10, code.items);
}

fn syntheticGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticExplicitReturnAbiGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSectionWithAbiReturn(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version, true);
    return module.toOwnedSlice(allocator);
}

fn syntheticDuplicateExportNameGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 2));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticMalformedTrailingTypeGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmMalformedTrailingTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticDuplicateSectionGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticStartSectionGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    var start: std.ArrayList(u8) = .empty;
    defer start.deinit(allocator);
    try appendWasmU32(&start, @intCast(world.Guest.Abi.required_exports.len + 64));
    try appendWasmSection(&module, 8, start.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticStaleAbiGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version + 1);
    return module.toOwnedSlice(allocator);
}

fn syntheticWrongSignatureGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, true);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticMissingMemoryGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticInvalidLimitGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmInvalidLimitMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticShortCodeGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmShortCodeSection(&module, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticAllocOnlyGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSectionWithAlloc(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 2));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "world_alloc");
    try exports.append(allocator, 0);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len));
    try appendWasmName(&exports, "world_free");
    try exports.append(allocator, 0);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len + 2, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticMalformedAllocGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 2));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmName(&exports, "world_alloc");
    try exports.append(allocator, 0);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticGuestWasmWithImport(allocator: std.mem.Allocator, module_name: []const u8, import_name: []const u8) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    try appendGuestWasmTypeSection(&module);
    var imports: std.ArrayList(u8) = .empty;
    defer imports.deinit(allocator);
    try appendWasmU32(&imports, 1);
    try appendWasmName(&imports, module_name);
    try appendWasmName(&imports, import_name);
    try imports.append(allocator, 0);
    try appendWasmU32(&imports, 0);
    try appendWasmSection(&module, 2, imports.items);
    try appendGuestWasmFunctionSection(&module, false);
    try appendGuestWasmMemorySection(&module);
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 0);
        try appendWasmU32(&exports, @intCast(index + 1));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    try appendGuestWasmCodeSection(&module, world.Guest.Abi.required_exports.len, world.Guest.Abi.version);
    return module.toOwnedSlice(allocator);
}

fn syntheticNonFunctionExportGuestWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    var exports: std.ArrayList(u8) = .empty;
    defer exports.deinit(allocator);
    try appendWasmU32(&exports, @intCast(world.Guest.Abi.required_exports.len + 1));
    for (world.Guest.Abi.required_exports, 0..) |name, index| {
        try appendWasmName(&exports, name);
        try exports.append(allocator, 3);
        try appendWasmU32(&exports, @intCast(index));
    }
    try appendWasmName(&exports, "memory");
    try exports.append(allocator, 2);
    try appendWasmU32(&exports, 0);
    try appendWasmSection(&module, 7, exports.items);
    return module.toOwnedSlice(allocator);
}

fn syntheticForbiddenImportWasm(allocator: std.mem.Allocator) ![]u8 {
    var module: std.ArrayList(u8) = .empty;
    errdefer module.deinit(allocator);
    try module.appendSlice(allocator, "\x00asm\x01\x00\x00\x00");
    var imports: std.ArrayList(u8) = .empty;
    defer imports.deinit(allocator);
    try appendWasmU32(&imports, 1);
    try appendWasmName(&imports, "wasi_snapshot_preview1");
    try appendWasmName(&imports, "fd_read");
    try imports.append(allocator, 0);
    try appendWasmU32(&imports, 0);
    try appendWasmSection(&module, 2, imports.items);
    return module.toOwnedSlice(allocator);
}

test "wasm export inspector validates required exports and forbidden imports" {
    const valid = try syntheticGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(valid);
    const valid_inspection = try world.Guest.Wasm.inspect(valid);
    try std.testing.expectEqual(world.Guest.Abi.version, valid_inspection.abi_version);
    try std.testing.expect(valid_inspection.required_exports_present);
    try std.testing.expect(valid_inspection.memory_export_present);
    try std.testing.expectEqual(@as(usize, 0), valid_inspection.forbidden_import_count);
    try std.testing.expect(valid_inspection.passed());

    const explicit_return_abi = try syntheticExplicitReturnAbiGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(explicit_return_abi);
    const explicit_return_inspection = try world.Guest.Wasm.inspect(explicit_return_abi);
    try std.testing.expectEqual(world.Guest.Abi.version, explicit_return_inspection.abi_version);
    try std.testing.expect(explicit_return_inspection.passed());

    const forbidden = try syntheticForbiddenImportWasm(std.testing.allocator);
    defer std.testing.allocator.free(forbidden);
    const forbidden_inspection = try world.Guest.Wasm.inspect(forbidden);
    try std.testing.expectEqual(@as(usize, 1), forbidden_inspection.import_count);
    try std.testing.expectEqual(@as(usize, 1), forbidden_inspection.forbidden_import_count);
    try std.testing.expect(!forbidden_inspection.passed());

    const arbitrary_import = try syntheticGuestWasmWithImport(std.testing.allocator, "env", "log");
    defer std.testing.allocator.free(arbitrary_import);
    const arbitrary_import_inspection = try world.Guest.Wasm.inspect(arbitrary_import);
    try std.testing.expectEqual(world.Guest.Abi.version, arbitrary_import_inspection.abi_version);
    try std.testing.expect(arbitrary_import_inspection.required_exports_present);
    try std.testing.expectEqual(@as(usize, 1), arbitrary_import_inspection.import_count);
    try std.testing.expectEqual(@as(usize, 0), arbitrary_import_inspection.forbidden_import_count);
    try std.testing.expect(!arbitrary_import_inspection.passed());

    const non_function_exports = try syntheticNonFunctionExportGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(non_function_exports);
    const non_function_inspection = try world.Guest.Wasm.inspect(non_function_exports);
    try std.testing.expect(!non_function_inspection.required_exports_present);
    try std.testing.expect(!non_function_inspection.passed());

    const wrong_signature_exports = try syntheticWrongSignatureGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(wrong_signature_exports);
    const wrong_signature_inspection = try world.Guest.Wasm.inspect(wrong_signature_exports);
    try std.testing.expect(!wrong_signature_inspection.required_exports_present);
    try std.testing.expect(!wrong_signature_inspection.passed());

    const missing_memory = try syntheticMissingMemoryGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(missing_memory);
    const missing_memory_inspection = try world.Guest.Wasm.inspect(missing_memory);
    try std.testing.expect(missing_memory_inspection.required_exports_present);
    try std.testing.expect(!missing_memory_inspection.memory_export_present);
    try std.testing.expect(!missing_memory_inspection.passed());

    const alloc_only = try syntheticAllocOnlyGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(alloc_only);
    const alloc_only_inspection = try world.Guest.Wasm.inspect(alloc_only);
    try std.testing.expect(alloc_only_inspection.required_exports_present);
    try std.testing.expect(alloc_only_inspection.alloc_export_present);
    try std.testing.expect(alloc_only_inspection.free_export_present);
    try std.testing.expect(!alloc_only_inspection.memory_export_present);
    try std.testing.expect(!alloc_only_inspection.passed());

    const malformed_alloc = try syntheticMalformedAllocGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(malformed_alloc);
    const malformed_alloc_inspection = try world.Guest.Wasm.inspect(malformed_alloc);
    try std.testing.expect(malformed_alloc_inspection.required_exports_present);
    try std.testing.expect(malformed_alloc_inspection.memory_export_present);
    try std.testing.expect(!malformed_alloc_inspection.alloc_export_present);
    try std.testing.expect(!malformed_alloc_inspection.passed());

    const stale_abi = try syntheticStaleAbiGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(stale_abi);
    const stale_abi_inspection = try world.Guest.Wasm.inspect(stale_abi);
    try std.testing.expectEqual(world.Guest.Abi.version + 1, stale_abi_inspection.abi_version);
    try std.testing.expect(stale_abi_inspection.required_exports_present);
    try std.testing.expect(!stale_abi_inspection.passed());

    const invalid_limit = try syntheticInvalidLimitGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(invalid_limit);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(invalid_limit));

    const short_code = try syntheticShortCodeGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(short_code);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(short_code));

    const duplicate_export = try syntheticDuplicateExportNameGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(duplicate_export);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(duplicate_export));

    const malformed_trailing_type = try syntheticMalformedTrailingTypeGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(malformed_trailing_type);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(malformed_trailing_type));

    const duplicate_section = try syntheticDuplicateSectionGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(duplicate_section);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(duplicate_section));

    const start_section = try syntheticStartSectionGuestWasm(std.testing.allocator);
    defer std.testing.allocator.free(start_section);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(start_section));

    const overflowing_section_len = [_]u8{
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x80, 0x80, 0x80, 0x80, 0x10,
    };
    try std.testing.expectError(error.InvalidFrameEncoding, world.Guest.Wasm.inspect(&overflowing_section_len));
}

const MissingDispatchTarget = struct {
    pub const Program = fixtures.Ports.Target.Program;
    pub const WorldSurface = fixtures.Ports.Target.WorldSurface;
    pub const WorldPortTable = fixtures.Ports.Target.WorldPortTable;
    pub const WorldValueTable = fixtures.Ports.Target.WorldValueTable;
    pub const Certificate = fixtures.Ports.Target.Certificate;

    pub const WorldDispatchTable = struct {
        pub fn lookup(_: usize) ?u32 {
            return null;
        }
    };

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};
const MissingDispatchMachine = world.Machine(MissingDispatchTarget, .{ .ports = .{} });

const ResumeFailureProgram = struct {
    pub const contract = fixtures.Ports.Target.Program.contract;
    pub const protocol = fixtures.Ports.Target.Program.protocol;
    pub const Handlers = fixtures.Ports.Target.Program.Handlers;
    const InnerSession = fixtures.Ports.Target.Program.Session;

    pub const Session = struct {
        inner: InnerSession,
        pub const Request = InnerSession.Request;

        pub fn startWithArgs(runtime: anytype, handlers: anytype, args: anytype) !@This() {
            return .{ .inner = try InnerSession.startWithArgs(runtime, handlers, args) };
        }

        pub fn deinit(self: *@This()) void {
            self.inner.deinit();
        }

        pub fn next(self: *@This()) @typeInfo(@TypeOf(InnerSession.next)).@"fn".return_type.? {
            return self.inner.next();
        }

        pub fn resumeTyped(_: *@This(), _: anytype, _: anytype) !void {
            return error.TestResumeFailed;
        }
    };
};

const ResumeFailureTarget = struct {
    pub const Program = ResumeFailureProgram;
    pub const WorldSurface = fixtures.Ports.Target.WorldSurface;
    pub const WorldPortTable = fixtures.Ports.Target.WorldPortTable;
    pub const WorldValueTable = fixtures.Ports.Target.WorldValueTable;
    pub const WorldDispatchTable = fixtures.Ports.Target.WorldDispatchTable;
    pub const Certificate = fixtures.Ports.Target.Certificate;

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};
const ResumeFailureRequest = ResumeFailureProgram.protocol.operationSite("approval", "request", 0);
const ResumeFailureDecl = world.port(ResumeFailureTarget, ResumeFailureRequest, approve);
const ResumeFailureBinding = world.bind(ResumeFailureDecl, world.NativeAdapter(approve));
const ResumeFailureEnv = world.Environment(ResumeFailureTarget, .{
    .bindings = .{ResumeFailureBinding},
});
const ResumeFailureMachine = world.Machine(ResumeFailureTarget, .{
    .ports = .{ResumeFailureDecl},
    .strict_handler_coverage = true,
});

const OptionalNullTarget = struct {
    pub const Program = struct {
        pub const Handlers = struct {};
        pub const contract = struct {
            pub const ResultType = ?i32;
        };

        pub const Session = struct {
            value: ?i32,

            pub const Request = struct {
                pub fn trace(_: @This()) struct {
                    operation_site_index: usize,
                    operation_site_fingerprint: u64,
                    fingerprint: u64,
                    turn_index: usize,
                } {
                    return .{
                        .operation_site_index = 0,
                        .operation_site_fingerprint = 0,
                        .fingerprint = 0,
                        .turn_index = 0,
                    };
                }
            };
            const Done = struct {
                value: ?i32,

                pub fn deinit(_: *@This()) void {}
            };

            pub fn startWithArgs(_: anytype, _: Handlers, args: anytype) !@This() {
                return .{ .value = args[0] };
            }

            pub fn deinit(_: *@This()) void {}

            pub fn next(self: *@This()) !union(enum) {
                done: Done,
                after,
                request: Request,
            } {
                return .{ .done = .{ .value = self.value } };
            }
        };
    };

    pub const WorldSurface = struct {
        pub const surface_fingerprint: u64 = 0x7773_6f70_746e_0001;

        pub fn replayScopeRef() struct { fingerprint: u64 } {
            return .{ .fingerprint = surface_fingerprint };
        }
    };
    pub const WorldPortTable = struct {
        pub const entries = &.{};
    };
    pub const WorldValueTable = struct {
        pub const entries = &.{};
    };
    pub const WorldDispatchTable = struct {
        pub fn lookup(_: usize) ?u32 {
            return null;
        }
    };
    pub const Certificate = struct {
        pub const certificate_fingerprint: u64 = 0x7773_6f70_746e_0002;
    };

    pub fn assertWorldSurfaceReady() void {}
    pub fn assertNoSearchHotPath() void {}
};

fn recordPortsTranscript(transcript: *world.Transcript) !void {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = transcript,
    });
    defer result.deinit(std.testing.allocator);
}

fn hashTestBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hasher.update(bytes);
}

fn hashTestU64(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    hasher.update(&buffer);
}

fn hashTestBool(hasher: *std.hash.Wyhash, value: bool) void {
    hashTestU64(hasher, @as(u8, if (value) 1 else 0));
}

fn hashTestOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
    if (value) |present| {
        hashTestBool(hasher, true);
        hashTestU64(hasher, present);
    } else {
        hashTestBool(hasher, false);
    }
}

fn hashTestOptionalU32(hasher: *std.hash.Wyhash, value: ?u32) void {
    if (value) |present| {
        hashTestBool(hasher, true);
        hashTestU64(hasher, present);
    } else {
        hashTestBool(hasher, false);
    }
}

fn testTranscriptEventImageV2Fingerprint(event: world.TranscriptImage.EventImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashTestBytes(&hasher, "world.transcript.event_image.fingerprint");
    hashTestU64(&hasher, world.world_timeline_event_fingerprint_version);
    hashTestU64(&hasher, @intFromEnum(event.kind));
    hashTestU64(&hasher, event.world_surface_fingerprint);
    hashTestU64(&hasher, event.target_certificate_fingerprint);
    hashTestOptionalU32(&hasher, event.world_port_id);
    hashTestOptionalU64(&hasher, event.request_fingerprint);
    hashTestOptionalU64(&hasher, event.response_fingerprint);
    hashTestBool(&hasher, false);
    hashTestOptionalU64(&hasher, event.replay_key);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, false);
    hashTestOptionalU64(&hasher, event.residual_site_fingerprint);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, event.source_run);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, false);
    return hasher.final();
}

fn testTranscriptEventImageFingerprint(event: world.TranscriptImage.EventImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashTestBytes(&hasher, "world.transcript.event_image.fingerprint");
    hashTestU64(&hasher, world.world_timeline_event_fingerprint_version);
    hashTestU64(&hasher, @intFromEnum(event.kind));
    hashTestU64(&hasher, event.world_surface_fingerprint);
    hashTestU64(&hasher, event.target_certificate_fingerprint);
    hashTestOptionalU32(&hasher, event.world_port_id);
    hashTestOptionalU64(&hasher, event.request_fingerprint);
    hashTestOptionalU64(&hasher, event.response_fingerprint);
    if (event.response_kind) |kind| {
        hashTestBool(&hasher, true);
        hashTestU64(&hasher, @intFromEnum(kind));
    } else {
        hashTestBool(&hasher, false);
    }
    hashTestOptionalU64(&hasher, event.replay_key);
    hashTestOptionalU64(&hasher, event.admission_request_fingerprint);
    hashTestOptionalU64(&hasher, event.admission_report_fingerprint);
    hashTestOptionalU64(&hasher, event.admission_receipt_fingerprint);
    hashTestOptionalU64(&hasher, event.module_ref_fingerprint);
    hashTestOptionalU64(&hasher, event.target_match_fingerprint);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, false);
    hashTestOptionalU64(&hasher, event.residual_site_fingerprint);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, event.source_run);
    hashTestBool(&hasher, false);
    hashTestBool(&hasher, false);
    return hasher.final();
}

fn writeLittleU64(bytes: []u8, value: anytype) void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, @intCast(value), .little);
    @memcpy(bytes, &buffer);
}

fn firstDiffAfter(left: []const u8, right: []const u8, start: usize) !usize {
    const limit = @min(left.len, right.len);
    var index = start;
    while (index < limit) : (index += 1) {
        if (left[index] != right[index]) return index;
    }
    return error.MissingDiff;
}

fn nthBytesOffset(haystack: []const u8, needle: []const u8, ordinal: usize) !usize {
    var search_from: usize = 0;
    var seen: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, search_from, needle)) |offset| {
        if (seen == ordinal) return offset;
        seen += 1;
        search_from = offset + 1;
    }
    return error.MissingNeedle;
}

fn testTranscriptImageFingerprint(image: world.TranscriptImage) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashTestBytes(&hasher, "world.transcript.image.fingerprint");
    hashTestU64(&hasher, world.world_transcript_image_fingerprint_version);
    hashTestU64(&hasher, image.world_surface_fingerprint);
    hashTestU64(&hasher, image.target_certificate_fingerprint);
    hashTestU64(&hasher, @intFromEnum(image.final_status));
    hashTestU64(&hasher, image.response_count);
    hashTestU64(&hasher, image.events.len);
    for (image.events) |event| hashTestU64(&hasher, event.event_fingerprint);
    return hasher.final();
}

fn firstRespondedEvent(transcript: *world.Transcript) !*world.Transcript.Event {
    for (transcript.events.items) |*event| {
        if (event.kind == .port_responded) return event;
    }
    return error.MissingResponseEvent;
}

fn firstRunCompletedIndex(transcript: *world.Transcript) !usize {
    for (transcript.events.items, 0..) |event, index| {
        if (event.kind == .run_completed) return index;
    }
    return error.MissingRunCompletedEvent;
}

fn testRunspaceRequestFrame() world.Frame.Request {
    return world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0x1234_5678,
        .turn_index = 3,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
    });
}

fn testRunspaceResponseFrame(request: world.Frame.Request) world.Frame.Response {
    return world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x9876_5432,
        .replay_key = request.replay_key_seed.withResponse(0x9876_5432).fingerprint(),
    });
}

fn appendPortsSourceRun(transcript: *world.Transcript, turn_index: usize, request_fingerprint: u64, response_fingerprint: u64) !world.Frame.Response {
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .source_run = true,
    });
    const request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = request_fingerprint,
        .turn_index = turn_index,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
    });
    try transcript.append(.{
        .kind = .port_requested,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_frame = request,
        .source_run = true,
    });
    const response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = response_fingerprint,
        .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
    });
    try transcript.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .response_frame = response,
        .source_run = true,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .status = .responded,
        .source_run = true,
    });
    return response;
}

test "runspace handle identity binds runspace target and generation" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x51ace,
        .local_run_id = 7,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .admission_receipt_fingerprint = 0xadd1_51,
        .permit_fingerprint = 0x9e2117,
        .branch_id = 2,
        .generation = 4,
    });

    try handle.validateForRunspace(0x51ace);
    try std.testing.expectError(error.StaleRunHandle, handle.validateForRunspace(0x51acf));

    var forged = handle;
    forged.generation += 1;
    try std.testing.expectError(error.StaleRunHandle, forged.validateForRunspace(0x51ace));

    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .running,
    });
    const slot = world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .runnable,
        .admission_receipt_fingerprint = handle.admission_receipt_fingerprint,
        .run_permit_fingerprint = handle.permit_fingerprint,
        .branch_id = handle.branch_id,
    });
    const summary = slot.summary();
    try std.testing.expectEqual(handle.handle_fingerprint, summary.handle.handle_fingerprint);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, summary.target_ref_fingerprint);
    try std.testing.expectEqual(state.run_state_fingerprint, summary.run_state_fingerprint);
    try std.testing.expect(summary.handle.generation != forged.generation);

    const next_generation = world.RunHandle.init(.{
        .runspace_fingerprint = handle.runspace_fingerprint,
        .local_run_id = handle.local_run_id,
        .target_ref_fingerprint = handle.target_ref_fingerprint,
        .admission_receipt_fingerprint = handle.admission_receipt_fingerprint,
        .permit_fingerprint = handle.permit_fingerprint,
        .branch_id = handle.branch_id,
        .generation = handle.generation + 1,
    });
    try std.testing.expect(handle.handle_fingerprint != next_generation.handle_fingerprint);
}

test "runspace slot transition matrix rejects impossible lifecycle states" {
    try std.testing.expect(world.Runspace.canTransition(.admitted, .runnable));
    try std.testing.expect(!world.Runspace.canTransition(.admitted, .parked_on_port));
    try std.testing.expect(world.Runspace.canTransition(.runnable, .running));
    try std.testing.expect(!world.Runspace.canTransition(.runnable, .exported));
    try std.testing.expect(world.Runspace.canTransition(.running, .parked_on_port));
    try std.testing.expect(!world.Runspace.canTransition(.parked_on_port, .completed));
    try std.testing.expect(world.Runspace.canTransition(.parked_on_port, .runnable));
    try std.testing.expect(world.Runspace.canTransition(.parked_on_supervision, .exported));
    try std.testing.expect(world.Runspace.canTransition(.completed, .exported));
    try std.testing.expect(!world.Runspace.canTransition(.completed, .runnable));
    try std.testing.expect(!world.Runspace.canTransition(.failed, .runnable));
    try std.testing.expect(!world.Runspace.canTransition(.exported, .runnable));
    try std.testing.expect(!world.Runspace.canTransition(.rejected, .runnable));

    var slot = world.RunSlot.init(world.RunHandle.init(.{
        .runspace_fingerprint = 0x51ace,
        .local_run_id = 1,
        .target_ref_fingerprint = 0x77,
    }));
    slot.status = .parked_on_supervision;
    try slot.transition(.@"export", null);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, slot.status);

    var lineage_slot = world.RunSlot.init(world.RunHandle.init(.{
        .runspace_fingerprint = 0x51ace,
        .local_run_id = 2,
        .target_ref_fingerprint = 0x88,
    }));
    lineage_slot.status = .runnable;
    lineage_slot.current_state = world.RunState.init(.{
        .target_ref_fingerprint = lineage_slot.handle.target_ref_fingerprint,
        .transcript_image_fingerprint = 0xabc,
        .branch_id = 7,
        .checkpoint_fingerprint = 0xdef,
        .status = .not_started,
    });
    try lineage_slot.transition(.step, null);
    try lineage_slot.transition(.complete, null);
    try std.testing.expectEqual(@as(?u64, 0xabc), lineage_slot.current_state.transcript_image_fingerprint);
    try std.testing.expectEqual(@as(u64, 7), lineage_slot.current_state.branch_id);
    try std.testing.expectEqual(@as(?u64, 0xdef), lineage_slot.current_state.checkpoint_fingerprint);
}

test "runspace pending port validates response identity and consumes once" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x51ace,
        .local_run_id = 3,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const request = testRunspaceRequestFrame();
    var mailbox = world.Runspace.Mailbox.init(std.testing.allocator, 8);
    defer mailbox.deinit();
    const pending = try mailbox.push(.{
        .mailbox_id = 11,
        .run_handle = handle,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 1,
    });

    const response = testRunspaceResponseFrame(request);
    try pending.validateResponse(response);
    const responded = pending.withStatus(.responded);
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, responded.status);
    try std.testing.expect(responded.pending_port_fingerprint != pending.pending_port_fingerprint);
    try std.testing.expectError(error.PendingPortConsumed, responded.validateResponse(response));

    const request_2 = world.Frame.Request.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = request.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_fingerprint = request.request_fingerprint + 1,
        .turn_index = request.turn_index + 1,
        .payload_value_table_id = request.payload_value_table_id,
        .expected_response_value_table_id = request.expected_response_value_table_id,
    });
    _ = try mailbox.push(.{
        .mailbox_id = 12,
        .run_handle = handle,
        .request = request_2,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 2,
    });

    const response_2 = testRunspaceResponseFrame(request_2);
    var wrong_surface = response_2;
    wrong_surface.world_surface_fingerprint += 1;
    try std.testing.expectError(error.FrameSurfaceMismatch, (try mailbox.get(12)).validateResponse(wrong_surface));

    var wrong_port = response_2;
    wrong_port.world_port_id += 1;
    try std.testing.expectError(error.FramePortMismatch, (try mailbox.get(12)).validateResponse(wrong_port));

    var wrong_request = response_2;
    wrong_request.request_fingerprint += 1;
    try std.testing.expectError(error.FrameRequestFingerprintMismatch, (try mailbox.get(12)).validateResponse(wrong_request));

    var wrong_value_table = response_2;
    wrong_value_table.response_value_table_id = 99;
    try std.testing.expectError(error.FrameValueTableMismatch, (try mailbox.get(12)).validateResponse(wrong_value_table));

    var wrong_kind = response_2;
    wrong_kind.response_kind = .return_now;
    try std.testing.expectError(error.VerifyResponseKindMismatch, (try mailbox.get(12)).validateResponse(wrong_kind));

    var wrong_replay_key = response_2;
    wrong_replay_key.replay_key += 1;
    try std.testing.expectError(error.ReplayMissing, (try mailbox.get(12)).validateResponse(wrong_replay_key));
}

test "runspace event fingerprints include kind handle mailbox and status" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x51ace,
        .local_run_id = 5,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .parked_on_port,
    });
    const event = world.RunspaceEvent.init(.{
        .kind = .port_responded,
        .runspace_fingerprint = handle.runspace_fingerprint,
        .event_index = 3,
        .run_handle = handle,
        .pending_port_fingerprint = 0x2222,
        .response_frame_fingerprint = 0x3333,
        .run_state_fingerprint = state.run_state_fingerprint,
        .summary = "responded",
    });
    const same = world.RunspaceEvent.init(.{
        .kind = .port_responded,
        .runspace_fingerprint = handle.runspace_fingerprint,
        .event_index = 3,
        .run_handle = handle,
        .pending_port_fingerprint = 0x2222,
        .response_frame_fingerprint = 0x3333,
        .run_state_fingerprint = state.run_state_fingerprint,
        .summary = "responded",
    });
    const changed_summary = world.RunspaceEvent.init(.{
        .kind = .port_responded,
        .runspace_fingerprint = handle.runspace_fingerprint,
        .event_index = 3,
        .run_handle = handle,
        .pending_port_fingerprint = 0x2222,
        .response_frame_fingerprint = 0x3333,
        .run_state_fingerprint = state.run_state_fingerprint,
        .summary = "failed",
    });

    try std.testing.expectEqual(event.event_fingerprint, same.event_fingerprint);
    try std.testing.expect(event.event_fingerprint != changed_summary.event_fingerprint);
}

test "runspace public event returns are borrowed from log" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    _ = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    var event = try runspace.stepOne();
    defer event.deinit(std.testing.allocator);

    try std.testing.expect(!event.owns_summary);
    const report = runspace.report();
    try std.testing.expect(report.emitted_events.len > 0);
    try std.testing.expect(report.emitted_events[report.emitted_events.len - 1].owns_summary);
    try std.testing.expectEqual(event.event_fingerprint, report.emitted_events[report.emitted_events.len - 1].event_fingerprint);
}

test "world machine accepts strict zero-port certified target" {
    const Machine = world.Machine(fixtures.Strict.Target, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });
    Machine.assertSurfaceMatches(fixtures.Strict.Target.WorldSurface.surface_fingerprint);
    Machine.assertNoSearchHotPath();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var result = try Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
        .expected_world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .expected_target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(usize, 0), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_started);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_completed);

    var checkpointed = world.Transcript.init(std.testing.allocator);
    defer checkpointed.deinit();
    try checkpointed.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try checkpointed.append(.{
        .kind = .checkpoint_recorded,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try checkpointed.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    var replayed = try Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &checkpointed,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 1), replayed.value);

    var frame_run = try Machine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer frame_run.deinit();
    const impossible_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .request_fingerprint = 0,
        .response_fingerprint = 0,
        .replay_key = 0,
    });
    try std.testing.expectError(error.UnknownResidualSite, frame_run.resumeFrame(impossible_response));
}

test "world machine preserves optional null completion values" {
    const Machine = world.Machine(OptionalNullTarget, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var result = try Machine.run(&runtime, .{@as(?i32, null)}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?i32, null), result.value);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().run_completed);
}

test "world step API preserves repeated optional null completion values" {
    const Machine = world.Machine(OptionalNullTarget, .{
        .ports = .{},
        .strict_handler_coverage = true,
    });

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var run = try Machine.start(&runtime, .{@as(?i32, null)}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer run.deinit();

    switch (try run.next()) {
        .done => |value| try std.testing.expectEqual(@as(?i32, null), value),
        else => return error.ExpectedDone,
    }
    switch (try run.next()) {
        .done => |value| try std.testing.expectEqual(@as(?i32, null), value),
        else => return error.ExpectedRepeatedDone,
    }
}

test "world machine rejects mismatched surface fingerprint" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.SurfaceMismatch, Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .expected_world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint + 1,
    }));
}

test "world machine rejects mismatched target certificate fingerprint" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.TargetCertificateMismatch, Machine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .expected_target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint + 1,
    }));
}

test "world port dispatch uses dense dispatch table and records transcript" {
    PortsMachine.assertAllPortsHandled();
    PortsMachine.assertNoExtraHandlers();
    PortsMachine.assertNoSearchHotPath();
    try std.testing.expectEqual(@as(u32, 0), PortsByIdDecl.world_port_id);

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
        .expected_world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.per_port_counts[0]);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_requested);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_responded);
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldDispatchTable.lookup(fixtures.Ports.ApprovalRequest.index).?);
}

test "world fresh port run does not require transcript option" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};

    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world runtime step API parks on port and resumes to done" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var run = try PortsMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try run.dispatch();
    const done = try run.next();
    switch (done) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedDone,
    }
    const repeated = try run.next();
    switch (repeated) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedRepeatedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_completed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_failed);
}

test "world dispatch uses WorldDispatchTable residual site mapping" {
    const site_index = fixtures.Ports.ApprovalRequest.index;
    const world_port_id = fixtures.Ports.Target.WorldDispatchTable.lookup(site_index) orelse return error.MissingDispatch;
    try std.testing.expectEqual(PortsDecl.world_port_id, world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, fixtures.Ports.Target.WorldPortTable.entries[world_port_id].residual_site_fingerprint);
}

test "world handlers can accept constructible PortRequest by site" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{ .response = 11 };

    var result = try PortsRequestMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 11), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world port request includes WorldValueTable payload and response ids" {
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldValueTable.entries[0].world_port_id);
    try std.testing.expectEqual(@as(u32, 0), fixtures.Ports.Target.WorldValueTable.entries[0].value_id);
    try std.testing.expectEqual(@as(u32, 1), fixtures.Ports.Target.WorldValueTable.entries[1].value_id);
    try std.testing.expectEqual(.payload, fixtures.Ports.Target.WorldValueTable.entries[0].kind);
    try std.testing.expectEqual(.@"resume", fixtures.Ports.Target.WorldValueTable.entries[1].kind);
}

test "world replay consumes transcript and does not call handlers" {
    var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var fresh_ctx: PortsCtx = .{};

    var fresh = try PortsMachine.run(&fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(std.testing.allocator);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: PortsCtx = .{ .response = 99 };
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, replayed.value);
    try std.testing.expectEqual(@as(usize, 1), fresh_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);

    var second_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer second_replay_runtime.deinit();
    var second_replay_ctx: PortsCtx = .{ .response = 101 };
    var second_replay = try PortsMachine.run(&second_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &second_replay_ctx,
        .transcript = &transcript,
    });
    defer second_replay.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, second_replay.value);
    try std.testing.expectEqual(@as(usize, 0), second_replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), second_replay.audit.replayed_response_count);

    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{ .response = fresh.value };
    var verified = try PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript = &transcript,
    });
    defer verified.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, verified.value);
    try std.testing.expectEqual(@as(usize, 1), verify_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), verified.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), verified.audit.replayed_response_count);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_requested);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_responded);

    var third_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer third_replay_runtime.deinit();
    var third_replay_ctx: PortsCtx = .{ .response = 103 };
    var third_replay = try PortsMachine.run(&third_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &third_replay_ctx,
        .transcript = &transcript,
    });
    defer third_replay.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, third_replay.value);
    try std.testing.expectEqual(@as(usize, 0), third_replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), third_replay.audit.replayed_response_count);
}

test "world replay selects the latest completed transcript run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{ .response = 7 };
        var result = try PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);
    }
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{ .response = 9 };
        var result = try PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);
    }

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var image_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer image_replay_runtime.deinit();
    var image_replayed = try PortsMachine.run(&image_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    });
    defer image_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 9), image_replayed.value);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: PortsCtx = .{ .response = 99 };
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 9), replayed.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
    try std.testing.expectEqual(@as(usize, 2), transcript.summary().port_responded);
    try std.testing.expectEqual(@as(usize, 1), transcript.summary().port_replayed);

    var image_after_replay = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image_after_replay.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), image_after_replay.response_count);
}

test "world replay missing response fails" {
    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "world replay does not require handler context option" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &transcript,
    }));
}

test "world dispatch failures record failed audit and transcript events" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.MissingHandler, MissingMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    }));

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
}

test "world malformed dispatch lookup records failed run" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    try std.testing.expectError(error.UnknownResidualSite, MissingDispatchMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    }));

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_started);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_completed);
}

test "world step dispatch failure is terminal" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    var run = try MissingMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try std.testing.expectError(error.MissingHandler, run.dispatch());
    switch (try run.next()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }
    try std.testing.expectError(error.HandlerFailed, run.dispatch());

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_completed);
}

test "world frame step rejects missing port descriptor before exposing request" {
    const MissingMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var run = try MissingMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    defer run.deinit();

    try std.testing.expectError(error.MissingHandler, run.nextFrame());
    switch (try run.nextFrame()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }
    try std.testing.expectEqual(@as(usize, 1), run.audit.missing_handler_count);
    try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 0), summary.port_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.port_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.frame_requested);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    try std.testing.expectEqual(@as(usize, 0), summary.run_completed);
}

test "world replay validates zero-port run fingerprints" {
    const Machine = world.Machine(fixtures.Strict.Target, .{ .ports = .{} });
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[0].world_surface_fingerprint += 1;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplaySurfaceMismatch, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_failed,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[1].kind = .run_failed;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
        defer fresh_runtime.deinit();
        var fresh = try Machine.run(&fresh_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer fresh.deinit(std.testing.allocator);
        transcript.events.items[1].kind = .run_started;

        var replay_runtime = boundary.Runtime.init(std.testing.allocator);
        defer replay_runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&replay_runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        try std.testing.expectError(error.ReplayMissing, Machine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript = &transcript,
        }));
    }
}

test "world replay ignores responses outside validated source run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const response_event = (try firstRespondedEvent(&transcript)).*;
    try transcript.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = response_event.world_surface_fingerprint,
        .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        .world_port_id = response_event.world_port_id,
        .request_fingerprint = response_event.request_fingerprint,
        .response_fingerprint = response_event.response_fingerprint,
        .response_kind = response_event.response_kind,
        .replay_key = response_event.replay_key,
    });

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "environment replay and verify accept in-memory transcripts" {
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        var result = try PortsMachineEnv.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(i32, 7), result.value);
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        var result = try PortsMachineEnv.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        });
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(i32, 7), result.value);
        try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    }
}

test "replay-only environment requires transcript image" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.TranscriptImageRequired, PortsReplayMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &transcript,
    }));
}

test "world replay rejects forged transcript dimensions" {
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).world_surface_fingerprint += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplaySurfaceMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayTargetCertificateMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).world_port_id.? += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayPortMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        (try firstRespondedEvent(&transcript)).request_fingerprint.? += 1;

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayRequestFingerprintMismatch, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    }
}

test "world verify rejects forged transcript dimensions before calling handlers" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.ReplayTargetCertificateMismatch, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "world transcript keeps rejected response events unconsumed" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    (try firstRespondedEvent(&transcript)).target_certificate_fingerprint += 1;

    const key = PortsDecl.replayKey((try firstRespondedEvent(&transcript)).request_fingerprint.?);
    try std.testing.expectError(
        error.ReplayTargetCertificateMismatch,
        transcript.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
    );
    try std.testing.expectError(error.ReplayUnusedEvent, transcript.assertReplayComplete());
}

test "world replay and verify reject unused response events" {
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        const response_event = (try firstRespondedEvent(&transcript)).*;
        try transcript.events.insert(transcript.allocator, try firstRunCompletedIndex(&transcript), .{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayUnusedEvent, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        const response_event = (try firstRespondedEvent(&transcript)).*;
        try transcript.events.insert(transcript.allocator, try firstRunCompletedIndex(&transcript), .{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayUnusedEvent, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
        try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    }
}

test "world verify rejects missing or corrupt stored replay values" {
    var recorded = world.Transcript.init(std.testing.allocator);
    defer recorded.deinit();
    try recordPortsTranscript(&recorded);
    const response_event = (try firstRespondedEvent(&recorded)).*;

    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
            .world_port_id = response_event.world_port_id,
            .request_fingerprint = response_event.request_fingerprint,
            .response_fingerprint = response_event.response_fingerprint,
            .response_kind = response_event.response_kind,
            .replay_key = response_event.replay_key,
        });
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
    {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try transcript.append(.{
            .kind = .run_started,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });
        var corrupt_stored = try world.StoredValue.init(std.testing.allocator, @as(i32, 8));
        defer corrupt_stored.deinit(std.testing.allocator);
        try transcript.append(.{
            .kind = .port_responded,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
            .world_port_id = response_event.world_port_id,
            .request_fingerprint = response_event.request_fingerprint,
            .response_fingerprint = response_event.response_fingerprint,
            .response_kind = response_event.response_kind,
            .replay_key = response_event.replay_key,
            .value = corrupt_stored,
        });
        try transcript.append(.{
            .kind = .run_completed,
            .world_surface_fingerprint = response_event.world_surface_fingerprint,
            .target_certificate_fingerprint = response_event.target_certificate_fingerprint,
        });

        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var ctx: PortsCtx = .{};
        try std.testing.expectError(error.VerifyDivergence, PortsMachine.run(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.verify,
            .ctx = &ctx,
            .transcript = &transcript,
        }));
    }
}

test "world verify detects changed handler response" {
    var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var fresh_ctx: PortsCtx = .{ .response = 7 };
    var fresh = try PortsMachine.run(&fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    defer fresh.deinit(std.testing.allocator);

    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{ .response = 8 };
    try std.testing.expectError(error.VerifyDivergence, PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript = &transcript,
    }));

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: PortsCtx = .{ .response = 99 };
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replayed.deinit(std.testing.allocator);

    try std.testing.expectEqual(fresh.value, replayed.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.calls);
}

test "world transcript replay key and summary counts are deterministic" {
    const scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint;
    const key_a = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_b = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint + 1,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_c = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id + 1,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x123,
    };
    const key_d = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabd,
        .response_fingerprint = 0x123,
    };
    const key_e = world.ReplayKey{
        .world_surface_scope_fingerprint = scope_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
        .response_fingerprint = 0x124,
    };
    try std.testing.expect(key_a.fingerprint() != key_b.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_c.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_d.fingerprint());
    try std.testing.expect(key_a.fingerprint() != key_e.fingerprint());

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    });
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.run_started);
    try std.testing.expectEqual(@as(usize, 1), summary.run_completed);
}

fn testRequestFrame() world.Frame.Request {
    return world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 3,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
    });
}

test "request frame fingerprint stable and encodes canonical bytes" {
    const request = testRequestFrame();
    const again = testRequestFrame();
    try std.testing.expectEqual(request.frame_fingerprint, again.frame_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.surface_fingerprint, request.world_surface_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.Certificate.certificate_fingerprint, request.target_certificate_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), request.world_port_id);
    try std.testing.expectEqual(@as(u64, 0xabc0_ffee), request.request_fingerprint);

    const encoded = try request.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Frame.Request.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(request.frame_fingerprint, decoded.frame_fingerprint);

    var wrong_replay_seed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(wrong_replay_seed);
    const replay_seed_world_surface_offset = 89;
    wrong_replay_seed[replay_seed_world_surface_offset] ^= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, wrong_replay_seed));

    const wrong_payload_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as([]const u8, "deploy-prod"), .portable);
    var wrong_payload_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 3,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = wrong_payload_image,
    });
    defer wrong_payload_request.deinit(std.testing.allocator);
    const wrong_payload_encoded = try wrong_payload_request.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_payload_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, wrong_payload_encoded));

    var wrong_request_version = testRequestFrame();
    wrong_request_version.format_version += 1;
    var request_version_transcript = world.Transcript.init(std.testing.allocator);
    defer request_version_transcript.deinit();
    try request_version_transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = wrong_request_version.world_surface_fingerprint,
        .target_certificate_fingerprint = wrong_request_version.target_certificate_fingerprint,
        .world_port_id = wrong_request_version.world_port_id,
        .request_fingerprint = wrong_request_version.request_fingerprint,
        .turn_index = wrong_request_version.turn_index,
        .residual_site_index = wrong_request_version.residual_site_index,
        .residual_site_fingerprint = wrong_request_version.residual_site_fingerprint,
        .request_frame = wrong_request_version,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, request_version_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));

    const with_junk = try std.testing.allocator.alloc(u8, encoded.len + 1);
    defer std.testing.allocator.free(with_junk);
    @memcpy(with_junk[0..encoded.len], encoded);
    with_junk[encoded.len] = 0;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, with_junk));
}

test "response frame status rejected failed and canonical bytes" {
    const request = testRequestFrame();
    const deferred_response_flag: u32 = 1;
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.ResponseStatus.responded, response.status);
    try std.testing.expectEqual(request.request_fingerprint, response.request_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), response.world_port_id);

    const encoded = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Frame.Response.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(response.frame_fingerprint, decoded.frame_fingerprint);
    const decoded_value = try decoded.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 7), decoded_value);

    var tampered = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(tampered);
    const response_value_fingerprint_offset = 4 + 4 + 8 + 8 + 8 + 4 + 8 + 1 + 1 + 4 + 8 + 1;
    tampered[response_value_fingerprint_offset] ^= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, tampered));

    const wrong_table_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, 0xdec1_5100, null, @as(i32, 7), .portable);
    var wrong_table_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0xdec1_5100,
        .response_image = wrong_table_image,
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
    });
    defer wrong_table_response.deinit(std.testing.allocator);
    const wrong_table_encoded = try wrong_table_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_table_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, wrong_table_encoded));

    const deferred_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    var deferred_with_fingerprint = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0xdec1_5100,
        .response_image = deferred_image,
        .replay_key = 0,
        .flags = deferred_response_flag,
    });
    defer deferred_with_fingerprint.deinit(std.testing.allocator);
    const deferred_with_fingerprint_encoded = try deferred_with_fingerprint.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_with_fingerprint_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, deferred_with_fingerprint_encoded));

    const deferred_rejected_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    var deferred_rejected = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_value_table_id = 1,
        .response_fingerprint = 0,
        .response_image = deferred_rejected_image,
        .replay_key = 0,
        .status = .rejected,
        .flags = deferred_response_flag,
    });
    defer deferred_rejected.deinit(std.testing.allocator);
    const deferred_rejected_encoded = try deferred_rejected.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_rejected_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Response.decode(std.testing.allocator, deferred_rejected_encoded));

    const deferred_without_image = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0,
        .replay_key = 0,
        .flags = deferred_response_flag,
    });
    const deferred_without_image_encoded = try deferred_without_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(deferred_without_image_encoded);
    try std.testing.expectError(error.MissingValueImage, world.Frame.Response.decode(std.testing.allocator, deferred_without_image_encoded));

    const rejected = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0,
        .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
        .status = .rejected,
    });
    try std.testing.expectEqual(world.ResponseStatus.rejected, rejected.status);
    const failed = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 1,
        .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
        .status = .failed,
    });
    try std.testing.expectEqual(world.ResponseStatus.failed, failed.status);
}

test "run handle fingerprint stable excludes runtime tokens and generation prevents stale confusion" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 2,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .admission_receipt_fingerprint = 0xa11ce,
        .permit_fingerprint = 0x9e7e,
    });
    const again = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 2,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .admission_receipt_fingerprint = 0xa11ce,
        .permit_fingerprint = 0x9e7e,
    });
    try std.testing.expectEqual(handle.handle_fingerprint, again.handle_fingerprint);
    try handle.validate();

    const next_generation = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 2,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .admission_receipt_fingerprint = 0xa11ce,
        .permit_fingerprint = 0x9e7e,
        .generation = 1,
    });
    try std.testing.expect(handle.handle_fingerprint != next_generation.handle_fingerprint);

    var stale = handle;
    stale.generation = 1;
    try std.testing.expectError(error.StaleRunHandle, stale.validate());
}

test "run slot summary records runnable parked completed and failed states" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 1,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const runnable_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    var slot = world.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = runnable_state,
        .status = .runnable,
    });
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, slot.summary().status);

    const request = testRequestFrame();
    slot.current_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    slot.status = .parked_on_port;
    slot.pending_mailbox_id = 7;
    var summary = slot.summary();
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, summary.status);
    try std.testing.expectEqual(@as(?u64, 7), summary.pending_mailbox_id);

    slot.current_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_response_fingerprint = 0xdec1,
        .status = .completed,
    });
    slot.status = .completed;
    summary = slot.summary();
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, summary.status);

    slot.current_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .failed,
    });
    slot.status = .failed;
    summary = slot.summary();
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, summary.status);
}

test "pending port fingerprint stable and binds run handle request and port" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 3,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const request = testRequestFrame();
    const pending = world.PendingPort.init(.{
        .handle = handle,
        .mailbox_id = 9,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .environment_certificate_fingerprint = 0xecc,
        .run_permit_fingerprint = 0x9e7e,
        .inserted_event_index = 4,
    });
    const again = world.PendingPort.init(.{
        .handle = handle,
        .mailbox_id = 9,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .environment_certificate_fingerprint = 0xecc,
        .run_permit_fingerprint = 0x9e7e,
        .inserted_event_index = 4,
    });
    try std.testing.expectEqual(pending.pending_port_fingerprint, again.pending_port_fingerprint);
    try std.testing.expectEqual(handle.handle_fingerprint, pending.handle.handle_fingerprint);
    try std.testing.expectEqual(request.request_fingerprint, pending.request_fingerprint);
    try std.testing.expectEqual(request.frame_fingerprint, pending.request_frame_fingerprint);
    try std.testing.expectEqual(request.world_port_id, pending.world_port_id);
    try pending.validate();

    const responded = pending.withStatus(.responded);
    try std.testing.expect(pending.pending_port_fingerprint != responded.pending_port_fingerprint);
}

test "mailbox push get list respond and stale response rejection" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 4,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const request = testRequestFrame();
    const duplicate_id_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = request.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_fingerprint = request.request_fingerprint + 1,
        .turn_index = request.turn_index + 1,
        .payload_value_table_id = request.payload_value_table_id,
        .expected_response_value_table_id = request.expected_response_value_table_id,
    });
    var mailbox = world.Mailbox.init(std.testing.allocator, 2);
    defer mailbox.deinit();

    const pending = try mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 1,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    try std.testing.expect(!pending.owns_request_frame);
    const pending_list = try mailbox.listPending(std.testing.allocator);
    defer std.testing.allocator.free(pending_list);
    try std.testing.expectEqual(@as(usize, 1), pending_list.len);
    try std.testing.expect(!pending_list[0].owns_request_frame);
    const fetched = try mailbox.get(1);
    try std.testing.expect(!fetched.owns_request_frame);
    try std.testing.expectEqual(pending.pending_port_fingerprint, fetched.pending_port_fingerprint);

    try std.testing.expectError(error.InvalidPendingPortTransition, mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 1,
        .request = duplicate_id_request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 1,
    }));

    try std.testing.expectError(error.InvalidPendingPortTransition, mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 2,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 2,
    }));

    var wrong_port = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer wrong_port.deinit(std.testing.allocator);
    wrong_port.world_port_id += 1;
    try std.testing.expectError(error.FramePortMismatch, (try mailbox.get(1)).validateResponse(wrong_port));

    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try (try mailbox.get(1)).validateResponse(response);
    const responded = (try mailbox.get(1)).withStatus(.responded);
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, responded.status);
    try std.testing.expect(!responded.owns_request_frame);
    try std.testing.expectEqual(@as(usize, 1), mailbox.pendingCount());
    try std.testing.expectError(error.PendingPortConsumed, responded.validateResponse(response));
}

test "mailbox stale id and pending capacity" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = 0x5150,
        .local_run_id = 5,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const request_a = testRequestFrame();
    const request_b = world.Frame.Request.init(.{
        .world_surface_fingerprint = request_a.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = request_a.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = request_a.target_certificate_fingerprint,
        .world_port_id = request_a.world_port_id,
        .residual_site_index = request_a.residual_site_index,
        .residual_site_fingerprint = request_a.residual_site_fingerprint,
        .request_fingerprint = request_a.request_fingerprint + 1,
        .turn_index = request_a.turn_index + 1,
        .payload_value_table_id = request_a.payload_value_table_id,
        .expected_response_value_table_id = request_a.expected_response_value_table_id,
    });
    const request_c = world.Frame.Request.init(.{
        .world_surface_fingerprint = request_a.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = request_a.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = request_a.target_certificate_fingerprint,
        .world_port_id = request_a.world_port_id,
        .residual_site_index = request_a.residual_site_index,
        .residual_site_fingerprint = request_a.residual_site_fingerprint,
        .request_fingerprint = request_a.request_fingerprint + 2,
        .turn_index = request_a.turn_index + 2,
        .payload_value_table_id = request_a.payload_value_table_id,
        .expected_response_value_table_id = request_a.expected_response_value_table_id,
    });
    var mailbox = world.Mailbox.init(std.testing.allocator, 2);
    defer mailbox.deinit();

    _ = try mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 10,
        .request = request_a,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    _ = try mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 11,
        .request = request_b,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 1,
    });
    try std.testing.expectEqual(@as(usize, 2), mailbox.pendingCount());
    try std.testing.expectError(error.BudgetExceeded, mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 12,
        .request = request_c,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 2,
    }));
    try std.testing.expectError(error.InvalidPendingPortTransition, mailbox.get(99));

    try std.testing.expectEqual(@as(usize, 2), mailbox.pendingCount());
}

test "runspace event fingerprint stable and report counts slots and pending ports" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_pending_ports = 4,
    });
    defer runspace.deinit();

    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    try runspace.slots.append(std.testing.allocator, world.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .runnable,
    }));
    const request = testRequestFrame();
    const pending = try runspace.mailbox.push(.{
        .run_handle = handle,
        .mailbox_id = 0,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });
    try runspace.events.append(std.testing.allocator, world.RunspaceEvent.init(.{
        .kind = .run_parked_on_port,
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .event_index = 0,
        .run_handle = handle,
        .pending_port_fingerprint = pending.pending_port_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .run_state_fingerprint = state.run_state_fingerprint,
        .summary = "parked",
    }));
    try std.testing.expectEqual(runspace.events.items[0].event_fingerprint, world.RunspaceEvent.init(.{
        .kind = .run_parked_on_port,
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .event_index = 0,
        .run_handle = handle,
        .pending_port_fingerprint = pending.pending_port_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .run_state_fingerprint = state.run_state_fingerprint,
        .summary = "parked",
    }).event_fingerprint);

    const report = runspace.report();
    try std.testing.expectEqual(@as(usize, 1), report.event_count);
    try std.testing.expectEqual(@as(usize, 1), report.run_count);
    try std.testing.expectEqual(@as(usize, 1), report.runnable_count);
    try std.testing.expectEqual(@as(usize, 1), report.pending_port_count);
    try std.testing.expectEqual(runspace.runspace_fingerprint, report.runspace_fingerprint);
}

test "runspace install target enforces config gates and deterministic local handles" {
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_runs = 2,
    });
    defer runspace.deinit();

    const first = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    const second = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), first.local_run_id);
    try std.testing.expectEqual(@as(u64, 1), second.local_run_id);
    try std.testing.expect(first.handle_fingerprint != second.handle_fingerprint);
    try std.testing.expectError(error.BudgetExceeded, runspace.installTarget(fixtures.Strict.Target, .{}, null, .{}));

    const summary = try runspace.getSlotSummary(first);
    try std.testing.expectEqual(world.Runspace.RunStatus.admitted, summary.status);
    try std.testing.expectEqual(first.handle_fingerprint, summary.handle.handle_fingerprint);
    const summaries = try runspace.listRunSummaries(std.testing.allocator);
    defer std.testing.allocator.free(summaries);
    try std.testing.expectEqual(@as(usize, 2), summaries.len);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().runnable_count);
    try std.testing.expectError(error.InvalidRunspaceTransition, runspace.step(first));

    var admission_required = world.Runspace.init(std.testing.allocator, .{
        .require_admission = true,
    });
    defer admission_required.deinit();
    try std.testing.expectError(error.RunspaceAdmissionRequired, admission_required.installTarget(fixtures.Strict.Target, .{}, null, .{}));

    var supervision_required = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer supervision_required.deinit();
    try std.testing.expectError(error.SupervisionDenied, supervision_required.installTarget(fixtures.Strict.Target, .{}, null, .{}));

    var direct_denied = world.Runspace.init(std.testing.allocator, .{
        .allow_direct_target_install = false,
    });
    defer direct_denied.deinit();
    try std.testing.expectError(error.RunspaceInstallDenied, direct_denied.installTarget(fixtures.Strict.Target, .{}, null, .{}));
}

test "runspace handles are scoped to each local arena instance" {
    var first_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer first_runspace.deinit();
    var second_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer second_runspace.deinit();

    try std.testing.expect(first_runspace.runspace_fingerprint != second_runspace.runspace_fingerprint);
    const first_handle = try first_runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    _ = try second_runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});

    try std.testing.expectError(error.StaleRunHandle, second_runspace.getSlotSummary(first_handle));
}

test "runspace supervised handoff install requires prior permit fingerprint" {
    var image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = 0,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
    });
    defer image.deinit(std.testing.allocator);

    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    try std.testing.expectError(error.SupervisionDenied, runspace.installRunImage(image));
}

test "runspace imported image slots use owned cloned target refs" {
    const image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
    });
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    const caller_label = decoded.target_ref.target_label orelse return error.TestUnexpectedResult;

    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    _ = try runspace.installRunImage(decoded);

    const slot = runspace.slots.items[0];
    const slot_label = slot.target_ref.target_label orelse return error.TestUnexpectedResult;
    const installed_image = slot.installed_run_image orelse return error.TestUnexpectedResult;
    const owned_label = installed_image.target_ref.target_label orelse return error.TestUnexpectedResult;
    try std.testing.expect(slot_label.ptr != caller_label.ptr);
    try std.testing.expectEqual(owned_label.ptr, slot_label.ptr);
}

test "runspace parked image install rolls back when mailbox enqueue fails" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var source = world.Runspace.init(std.testing.allocator, .{});
    defer source.deinit();
    const source_handle = try source.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try source.tick();
    var image = try source.exportPending(0);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try source.getSlotSummary(source_handle)).status);

    var target = world.Runspace.init(std.testing.allocator, .{
        .max_pending_ports = 0,
    });
    defer target.deinit();

    try std.testing.expectError(error.BudgetExceeded, target.installRunImage(image));
    const report = target.report();
    try std.testing.expectEqual(@as(usize, 0), report.run_count);
    try std.testing.expectEqual(@as(usize, 0), report.event_count);
    try std.testing.expectEqual(@as(usize, 0), report.pending_port_count);
    const next = try target.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), next.local_run_id);
}

test "runspace install slot event allocation failure cleans up appended slot" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 2,
    });
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });

    try std.testing.expectError(error.OutOfMemory, runspace.installTarget(fixtures.Ports.Target, PortsEnv, permit, .{
        .mode = world.Mode.fresh,
    }));
    try std.testing.expect(failing_allocator.has_induced_failure);
    const report = runspace.report();
    try std.testing.expectEqual(@as(usize, 0), report.run_count);
    try std.testing.expectEqual(@as(usize, 0), report.event_count);
}

test "runspace machine install event allocation failure does not mutate transcript" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 2,
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var transcript = world.Transcript.init(failing_allocator.allocator());
    defer transcript.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();

    try std.testing.expectError(error.OutOfMemory, runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    }));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), transcript.events.items.len);
    const report = runspace.report();
    try std.testing.expectEqual(@as(usize, 0), report.run_count);
    try std.testing.expectEqual(@as(usize, 0), report.event_count);
}

test "runspace port parking allocation failure does not leave pending mailbox" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 3);
    try runspace.mailbox.pending.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index + 1;

    try std.testing.expectError(error.OutOfMemory, runspace.tick());
    try std.testing.expect(failing_allocator.has_induced_failure);
    const report = runspace.report();
    try std.testing.expectEqual(@as(usize, 0), report.pending_port_count);
    try std.testing.expect((try runspace.getSlotSummary(handle)).status != .parked_on_port);
}

test "runspace install rejects invalid image and failed direct installs preserve run ids" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var source = world.Runspace.init(std.testing.allocator, .{});
    defer source.deinit();
    const source_handle = try source.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try source.tick();
    var image = try source.exportRun(source_handle);
    defer image.deinit(std.testing.allocator);

    var invalid_image = image;
    invalid_image.run_image_fingerprint += 1;
    var image_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer image_runspace.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, image_runspace.installRunImage(invalid_image));
    const image_next = try image_runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), image_next.local_run_id);

    const parked_without_frame = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
            .pending_request_fingerprint = 0x1234,
            .status = .parked_on_port,
        }),
    });
    try std.testing.expectError(error.HandoffPendingFrameMismatch, image_runspace.installRunImage(parked_without_frame));

    const non_resumable = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .not_started,
        }),
    });
    try std.testing.expectError(error.InvalidRunspaceTransition, image_runspace.installRunImage(non_resumable));
    const non_resumable_next = try image_runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 1), non_resumable_next.local_run_id);

    const ports_target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const detached_completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = ports_target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = ports_target_ref.target_ref_fingerprint,
            .status = .completed,
        }),
    });
    try detached_completed_image.validate(.{});

    var agent_transcript = world.Transcript.init(std.testing.allocator);
    defer agent_transcript.deinit();
    try agent_transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
    });
    try agent_transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .status = .responded,
    });
    var agent_transcript_image = try agent_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer agent_transcript_image.deinit(std.testing.allocator);

    var admitted_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer admitted_runspace.deinit();
    const invalid_attached_transcript = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0x5151,
        .target_ref = ports_target_ref,
        .run_image = detached_completed_image,
        .transcript_image = agent_transcript_image,
        .mode = .completed_replay,
    });
    try std.testing.expectError(error.TranscriptImageSurfaceMismatch, admitted_runspace.installAdmitted(invalid_attached_transcript));
    const admitted_next = try admitted_runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), admitted_next.local_run_id);

    var direct = world.Runspace.init(std.testing.allocator, .{ .max_events = 0 });
    defer direct.deinit();
    try std.testing.expectError(error.BudgetExceeded, direct.installTarget(fixtures.Strict.Target, .{}, null, .{}));
    direct.config.max_events = 1;
    const direct_next = try direct.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), direct_next.local_run_id);

    var machine_runtime = boundary.Runtime.init(std.testing.allocator);
    defer machine_runtime.deinit();
    var machine_transcript = world.Transcript.init(std.testing.allocator);
    defer machine_transcript.deinit();
    var machine = world.Runspace.init(std.testing.allocator, .{ .max_events = 0 });
    defer machine.deinit();
    try std.testing.expectError(error.BudgetExceeded, machine.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &machine_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &machine_transcript,
    }));
    try std.testing.expectEqual(@as(usize, 0), machine_transcript.events.items.len);
    machine.config.max_events = 1;
    const machine_next = try machine.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), machine_next.local_run_id);
}

test "runspace run image clone allocation failure preserves run ids" {
    const image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = 0,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
    });
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();

    failing_allocator.fail_index = failing_allocator.alloc_index;
    try std.testing.expectError(error.OutOfMemory, runspace.installRunImage(image));
    try std.testing.expect(failing_allocator.has_induced_failure);
    failing_allocator.fail_index = std.math.maxInt(usize);

    const next = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 0), next.local_run_id);
}

test "runspace tick only requires mailbox capacity for emitted port requests" {
    var strict_runtime = boundary.Runtime.init(std.testing.allocator);
    defer strict_runtime.deinit();
    var strict_runspace = world.Runspace.init(std.testing.allocator, .{
        .max_pending_ports = 0,
    });
    defer strict_runspace.deinit();

    const strict_handle = try strict_runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &strict_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try strict_runspace.tick();
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try strict_runspace.getSlotSummary(strict_handle)).status);
    try std.testing.expectEqual(@as(usize, 0), strict_runspace.report().pending_port_count);

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_pending_ports = 0,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectError(error.BudgetExceeded, runspace.tick());
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace max runs excludes completed runs when preservation is disabled" {
    var preserved_runtime = boundary.Runtime.init(std.testing.allocator);
    defer preserved_runtime.deinit();
    var preserved = world.Runspace.init(std.testing.allocator, .{
        .max_runs = 1,
        .preserve_completed_runs = true,
    });
    defer preserved.deinit();
    const preserved_first = try preserved.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &preserved_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try preserved.tick();
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try preserved.getSlotSummary(preserved_first)).status);
    try std.testing.expectError(error.BudgetExceeded, preserved.installTarget(fixtures.Strict.Target, .{}, null, .{}));

    var replace_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replace_runtime.deinit();
    var replaceable = world.Runspace.init(std.testing.allocator, .{
        .max_runs = 1,
        .preserve_completed_runs = false,
    });
    defer replaceable.deinit();
    const first = try replaceable.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &replace_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try replaceable.tick();
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try replaceable.getSlotSummary(first)).status);
    const second = try replaceable.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 1), second.local_run_id);
}

test "runspace failed machine install transfers driver ownership once" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_runs = 0,
    });
    defer runspace.deinit();

    try std.testing.expectError(error.BudgetExceeded, runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    }));
}

test "runspace reject and fail consume pending ports through slot state" {
    var reject_runtime = boundary.Runtime.init(std.testing.allocator);
    defer reject_runtime.deinit();
    var reject_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer reject_runspace.deinit();
    const reject_handle = try reject_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &reject_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try reject_runspace.tick();
    const reject_event = try reject_runspace.reject(0, "fixture rejection");
    try std.testing.expectEqual(world.Runspace.EventKind.run_failed, reject_event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.cancelled, (try reject_runspace.mailbox.get(0)).status);
    const reject_summary = try reject_runspace.getSlotSummary(reject_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, reject_summary.status);
    try std.testing.expectEqual(null, reject_summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 0), reject_runspace.report().pending_port_count);

    var fail_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fail_runtime.deinit();
    var fail_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer fail_runspace.deinit();
    const fail_handle = try fail_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &fail_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try fail_runspace.tick();
    const fail_event = try fail_runspace.fail(0, "fixture failure");
    try std.testing.expectEqual(world.Runspace.EventKind.run_failed, fail_event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try fail_runspace.mailbox.get(0)).status);
    const fail_summary = try fail_runspace.getSlotSummary(fail_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, fail_summary.status);
    try std.testing.expectEqual(null, fail_summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 0), fail_runspace.report().pending_port_count);
}

test "runspace terminal event allocation failure preserves pending mailbox" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 2);
    failing_allocator.fail_index = failing_allocator.alloc_index;

    try std.testing.expectError(error.OutOfMemory, runspace.reject(0, "allocation denied"));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, summary.status);
    try std.testing.expectEqual(@as(?u64, 0), summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace terminal port decisions honor supervision before consuming mailbox" {
    const reject_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var reject_runtime = boundary.Runtime.init(std.testing.allocator);
    defer reject_runtime.deinit();
    var reject_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer reject_runspace.deinit();
    const reject_handle = try reject_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &reject_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = reject_permit,
    });
    _ = try reject_runspace.tick();

    try std.testing.expectError(error.HandlerRejected, reject_runspace.reject(0, "strict policy denies reject"));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try reject_runspace.mailbox.get(0)).status);
    const reject_summary = try reject_runspace.getSlotSummary(reject_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, reject_summary.status);
    try std.testing.expectEqual(@as(?u64, 0), reject_summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 1), reject_runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), reject_runspace.report().blocker_count);

    const fail_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var fail_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fail_runtime.deinit();
    var fail_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer fail_runspace.deinit();
    const fail_handle = try fail_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &fail_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = fail_permit,
    });
    _ = try fail_runspace.tick();

    try std.testing.expectError(error.HandlerFailed, fail_runspace.fail(0, "strict policy denies fail"));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try fail_runspace.mailbox.get(0)).status);
    const fail_summary = try fail_runspace.getSlotSummary(fail_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, fail_summary.status);
    try std.testing.expectEqual(@as(?u64, 0), fail_summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 1), fail_runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), fail_runspace.report().blocker_count);

    var source_runtime = boundary.Runtime.init(std.testing.allocator);
    defer source_runtime.deinit();
    var source_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer source_runspace.deinit();
    _ = try source_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &source_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try source_runspace.tick();
    var parked_image = try source_runspace.exportPending(0);
    defer parked_image.deinit(std.testing.allocator);
    const admitted_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = true,
            .allow_handoff_accept = true,
            .require_environment_certificate = true,
        }),
    });
    const admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_7e12,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .environment_certificate_fingerprint = PortsEnv.certificate(.fresh, false).certificate_fingerprint,
        .mode = .continue_fresh,
        .run_image = parked_image,
        .run_permit = admitted_permit,
    });
    var admitted_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer admitted_runspace.deinit();
    const admitted_handle = try admitted_runspace.installAdmitted(admitted);
    try std.testing.expectError(error.HandlerFailed, admitted_runspace.fail(0, "strict policy denies imported fail"));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try admitted_runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try admitted_runspace.getSlotSummary(admitted_handle)).status);
}

test "runspace terminal response byte budget parks without consuming mailbox" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_failed_responses = true,
        .allow_handoff_export = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();

    const event = try runspace.fail(0, "budgeted terminal failure");
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace strict terminal response budget failure consumes mailbox and fails slot" {
    const strict_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_failed_responses = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = strict_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();

    try std.testing.expectError(error.BudgetExceeded, runspace.fail(0, "strict terminal budget failure"));
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().blocker_count);
}

test "runspace terminal response accounting charges allowed failure once" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = true,
            .allow_failed_responses = true,
            .require_environment_certificate = true,
        }),
        .budget = world.Budget.init(.{ .max_failed_calls = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();

    const event = try runspace.fail(0, "single accounted failure");
    try std.testing.expectEqual(world.Runspace.EventKind.run_failed, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace supervision park event allocation failure preserves port state" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_failed_responses = true,
        .allow_handoff_export = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index;

    try std.testing.expectError(error.OutOfMemory, runspace.fail(0, "budgeted terminal failure"));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, summary.status);
    try std.testing.expectEqual(@as(?u64, 0), summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace imported terminal response byte budget parks without consuming mailbox" {
    var source_runtime = boundary.Runtime.init(std.testing.allocator);
    defer source_runtime.deinit();
    var source_transcript = world.Transcript.init(std.testing.allocator);
    defer source_transcript.deinit();
    var source_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer source_runspace.deinit();
    _ = try source_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &source_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &source_transcript,
    });
    _ = try source_runspace.tick();
    var parked_image = try source_runspace.exportPending(0);
    defer parked_image.deinit(std.testing.allocator);
    const parked_transcript_fingerprint = parked_image.current_state.transcript_image_fingerprint orelse return error.ExpectedTranscriptImage;

    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_failed_responses = true,
        .allow_handoff_export = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    const admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b7e5,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .environment_certificate_fingerprint = PortsEnv.certificate(.fresh, false).certificate_fingerprint,
        .mode = .continue_fresh,
        .run_image = parked_image,
        .run_permit = permit,
    });
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installAdmitted(admitted);

    const event = try runspace.fail(0, "budgeted imported failure");
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
    var reexported = try runspace.exportPending(0);
    defer reexported.deinit(std.testing.allocator);
    try std.testing.expectEqual(parked_transcript_fingerprint, reexported.current_state.transcript_image_fingerprint.?);
}

test "runspace event budget failure does not enqueue or park request" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_events = 2,
    });
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });

    try std.testing.expectError(error.BudgetExceeded, runspace.tick());
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().event_count);
}

test "runspace exact event budget allows zero-port completion" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_events = 3,
    });
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });

    _ = try runspace.tick();
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, summary.status);
    try std.testing.expectEqual(@as(usize, 3), runspace.report().event_count);
}

test "runspace exact terminal event budget allows port run completion after response" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });

    _ = try runspace.tick();
    _ = try runspace.respondValue(0, @as(i32, 7));
    runspace.config.max_events = runspace.report().event_count + 2;

    _ = try runspace.tick();
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, summary.status);
    try std.testing.expectEqual(runspace.config.max_events.?, runspace.report().event_count);
}

test "runspace step event allocation failure leaves run runnable" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 2);
    failing_allocator.fail_index = failing_allocator.alloc_index;

    try std.testing.expectError(error.OutOfMemory, runspace.tick());
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().event_count);
}

test "runspace completion event allocation failure leaves run runnable" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 2);
    failing_allocator.fail_index = failing_allocator.alloc_index + 1;

    try std.testing.expectError(error.OutOfMemory, runspace.tick());
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().event_count);
}

test "runspace failure event allocation failure leaves run runnable" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var ctx: PortsCtx = .{ .response = 99 };
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{ .auto_dispatch = true });
    defer runspace.deinit();
    const handle = try runspace.installVerifyRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.verify,
        .ctx = &ctx,
        .transcript_image = &image,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 2);
    failing_allocator.fail_index = failing_allocator.alloc_index + 2;

    try std.testing.expectError(error.OutOfMemory, runspace.tick());
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().event_count);
}

test "runspace response event budget failure does not consume mailbox" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_events = 4,
    });
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();

    try std.testing.expectError(error.BudgetExceeded, runspace.respondValue(0, @as(i32, 7)));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
}

test "runspace auto dispatch event budget failure happens before handler call" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .auto_dispatch = true,
        .max_events = 5,
    });
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });

    try std.testing.expectError(error.BudgetExceeded, runspace.tick());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().event_count);
}

test "runspace install admitted and replay records receipts summaries and events" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(result.report.accepted);
    const admitted = result.admitted_run orelse return error.ExpectedAdmittedRun;
    const admitted_receipt_fingerprint = result.receipt.?.receipt_fingerprint;
    var receiptless_admitted = admitted;
    receiptless_admitted.admission_receipt = null;
    var receiptless_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_admission = true,
    });
    defer receiptless_runspace.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, receiptless_runspace.installAdmitted(receiptless_admitted));
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_admission = true,
    });
    defer runspace.deinit();
    var stale_admitted = admitted;
    stale_admitted.mode = .completed_replay;
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(stale_admitted));
    var invalid_target_ref = target_ref;
    invalid_target_ref.world_surface_fingerprint +%= 1;
    const invalid_target_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5510,
        .target_ref = invalid_target_ref,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(invalid_target_admitted));
    const resume_without_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5520,
        .target_ref = target_ref,
        .mode = .resume_parked,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(resume_without_image));
    const branch_resume_without_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5521,
        .target_ref = target_ref,
        .mode = .branch_resume,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(branch_resume_without_image));
    const completed_replay_without_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5522,
        .target_ref = target_ref,
        .mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(completed_replay_without_image));
    const completed_state_for_resume = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const completed_image_for_resume = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state_for_resume,
    });
    const resume_with_completed_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5523,
        .target_ref = target_ref,
        .run_image = completed_image_for_resume,
        .mode = .resume_parked,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(resume_with_completed_image));
    const fresh_state_for_replay = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const fresh_image_for_replay = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = fresh_state_for_replay,
    });
    const replay_with_fresh_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5524,
        .target_ref = target_ref,
        .run_image = fresh_image_for_replay,
        .mode = .replay_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(replay_with_fresh_image));
    const verify_with_fresh_image = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5525,
        .target_ref = target_ref,
        .run_image = fresh_image_for_replay,
        .mode = .verify_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(verify_with_fresh_image));
    const admitted_handle = try runspace.installAdmitted(admitted);
    const admitted_summary = try runspace.getSlotSummary(admitted_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.admitted, admitted_summary.status);
    try std.testing.expectError(error.InvalidRunspaceTransition, runspace.step(admitted_handle));
    try std.testing.expectEqual(@as(?u64, admitted_receipt_fingerprint), admitted_summary.admission_receipt_fingerprint);
    try std.testing.expectEqual(world.Runspace.EventKind.run_admitted, runspace.events.items[0].kind);

    const ports_cert = PortsEnv.certificate(.fresh, false);
    const accept_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_checkpoints = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
    });
    const valid_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = accept_policy,
    });
    var supervised_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer supervised_runspace.deinit();
    const supervised_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5511,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = valid_permit,
        .mode = .continue_fresh,
    });
    const supervised_handle = try supervised_runspace.installAdmitted(supervised_admitted);
    const scoped_valid_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = accept_policy,
        .admission_receipt_fingerprint = 0xadd1_5511,
    });
    try std.testing.expectEqual(scoped_valid_permit.permit_fingerprint, (try supervised_runspace.getSlotSummary(supervised_handle)).run_permit_fingerprint.?);
    try std.testing.expectEqual(@as(usize, 1), supervised_runspace.slots.items[0].supervisor.?.ledger.total_handoff_accepts);
    const accept_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    const accept_deny_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_550f,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = accept_deny_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.HandoffDenied, supervised_runspace.installAdmitted(accept_deny_admitted));

    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.strict_fresh,
    });
    const wrong_target_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    const wrong_target_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5512,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = wrong_target_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(wrong_target_admitted));

    const wrong_env_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    const wrong_env_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5513,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = wrong_env_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(wrong_env_admitted));

    const wrong_mode_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
    });
    const wrong_mode_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5514,
        .target_ref = target_ref,
        .run_permit = wrong_mode_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(wrong_mode_admitted));

    const stale_receipt_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .admission_receipt_fingerprint = 0xadd1_5515,
    });
    const stale_receipt_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5516,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = stale_receipt_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(stale_receipt_admitted));

    const unwitnessed_module_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .module_ref_fingerprint = 0xfeed_1000,
    });
    const unwitnessed_module_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5517,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = ports_cert.certificate_fingerprint,
        .run_permit = unwitnessed_module_permit,
        .mode = .continue_fresh,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(unwitnessed_module_admitted));
    const fresh_module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const module_scoped_fresh_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = accept_policy,
        .module_ref_fingerprint = fresh_module_ref.module_ref_fingerprint,
    });
    const module_reference_package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = fresh_module_ref,
        .requested_mode = .continue_fresh,
    });
    var module_reference_result = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.init(.{
            .allow_reference_targets = true,
            .require_supervision_permit = true,
        }),
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, module_reference_package, .{ .permit = module_scoped_fresh_permit });
    defer module_reference_result.deinit(std.testing.allocator);
    try std.testing.expect(module_reference_result.report.accepted);
    const module_reference_admitted = module_reference_result.admitted_run orelse return error.ExpectedAdmittedRun;
    try std.testing.expect(module_reference_admitted.run_image == null);
    try std.testing.expectEqual(fresh_module_ref.module_ref_fingerprint, module_reference_admitted.module_ref_fingerprint.?);
    var module_reference_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_admission = true,
        .require_supervision = true,
    });
    defer module_reference_runspace.deinit();
    const module_reference_handle = try module_reference_runspace.installAdmitted(module_reference_admitted);
    try std.testing.expectEqual(fresh_module_ref.module_ref_fingerprint, (try module_reference_runspace.getSlotSummary(module_reference_handle)).module_ref_fingerprint.?);

    const replay_cert = PortsReplayEnv.certificate(.replay, true);
    const module_scoped_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
        .module_ref_fingerprint = 0xfeed_2000,
    });
    const completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const mismatched_module_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
        .module_ref_fingerprint = 0xfeed_2001,
    });
    const mismatched_module_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5518,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = replay_cert.certificate_fingerprint,
        .run_permit = module_scoped_permit,
        .run_image = mismatched_module_image,
        .mode = .completed_replay,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_runspace.installAdmitted(mismatched_module_admitted));

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    var replay_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer replay_runspace.deinit();
    const replay_handle = try replay_runspace.installReplay(fixtures.Strict.Target, image, null);
    const replay_summary = try replay_runspace.getSlotSummary(replay_handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, replay_summary.status);
    try std.testing.expectEqual(world.Runspace.EventKind.run_installed, replay_runspace.events.items[0].kind);
    var replay_export = try replay_runspace.exportRun(replay_handle);
    defer replay_export.deinit(std.testing.allocator);
    try std.testing.expect(replay_export.transcript_image != null);
    try std.testing.expectEqual(world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint, replay_export.import_set_fingerprint);
    const forged_supervised_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = world.RunImage.fromTranscriptImage(fixtures.Strict.Target, image, .completed_run).current_state,
        .prior_run_permit_fingerprint = 0x5150_5150,
    });
    var supervised_direct_image = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer supervised_direct_image.deinit();
    try std.testing.expectError(error.SupervisionDenied, supervised_direct_image.installRunImage(forged_supervised_image));
    const StrictReplayEnv = world.Environment(fixtures.Strict.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.strict_replay,
    });
    const environment_bound_replay_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
    });
    var supervised_replay_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer supervised_replay_runspace.deinit();
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, environment_bound_replay_permit));
    const admission_scoped_replay_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
        .admission_receipt_fingerprint = 0xadd1_5c0e,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, admission_scoped_replay_permit));
    const module_scoped_replay_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
        .module_ref_fingerprint = world.Admission.ModuleRef.fromTarget(fixtures.Strict.Target).module_ref_fingerprint,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, module_scoped_replay_permit));
    const embedded_transcript_unavailable_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
    });
    const embedded_transcript_unavailable_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5c0f,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .mode = .replay_only,
        .run_image = replay_export,
        .run_permit = embedded_transcript_unavailable_permit,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installAdmitted(embedded_transcript_unavailable_admitted));
    const transcript_unattested_replay_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_replay_adapters = true,
        .require_environment_certificate = false,
        .require_transcript_image_for_replay = false,
    });
    const transcript_unattested_replay_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = transcript_unattested_replay_policy,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, transcript_unattested_replay_permit));
    const replay_without_environment_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_replay_adapters = true,
        .allow_handoff_accept = true,
        .require_portable_value_images = true,
        .reject_native_only_values = true,
        .require_environment_certificate = false,
        .require_transcript_image_for_replay = true,
    });
    const replay_export_denied_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = replay_without_environment_policy,
        .transcript_image_available = true,
    });
    const supervised_replay_handle = try supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, replay_export_denied_permit);
    try std.testing.expectError(error.HandoffDenied, supervised_replay_runspace.exportRun(supervised_replay_handle));
    var replay_accounting_transcript = world.Transcript.init(std.testing.allocator);
    defer replay_accounting_transcript.deinit();
    try recordPortsTranscript(&replay_accounting_transcript);
    var replay_accounting_image = try replay_accounting_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer replay_accounting_image.deinit(std.testing.allocator);
    var replay_accounting_export = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, replay_accounting_image, .replay_only_run);
    defer replay_accounting_export.deinit(std.testing.allocator);
    const replay_accounting_denied_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_without_environment_policy,
        .budget = world.Budget.init(.{ .max_replay_calls = 0 }),
        .transcript_image_available = true,
    });
    try std.testing.expectError(error.BudgetExceeded, supervised_replay_runspace.installReplay(fixtures.Ports.Target, replay_accounting_image, replay_accounting_denied_permit));
    const replay_accounting_denied_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5c10,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .replay_only,
        .run_image = replay_accounting_export,
        .run_permit = replay_accounting_denied_permit,
    });
    try std.testing.expectError(error.BudgetExceeded, supervised_replay_runspace.installAdmitted(replay_accounting_denied_admitted));
    const out_of_range_replay_budgets = [_]world.Supervision.PerPortBudget{.{
        .world_port_id = 0,
        .max_replay_calls = 1,
    }};
    const out_of_range_replay_permit = world.Supervision.issue(fixtures.Strict.Target, StrictReplayEnv, .{
        .mode = .replay,
        .policy = replay_without_environment_policy,
        .budget = world.Budget.init(.{ .per_port_budgets = &out_of_range_replay_budgets }),
        .transcript_image_available = true,
    });
    try std.testing.expectError(error.SupervisionDenied, supervised_replay_runspace.installReplay(fixtures.Strict.Target, image, out_of_range_replay_permit));
    const mismatched_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_bad,
        .target_ref = target_ref,
        .mode = .continue_fresh,
        .run_image = replay_export,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(mismatched_admitted));
    try std.testing.expectError(error.ReplaySurfaceMismatch, replay_runspace.installReplay(fixtures.Ports.Target, image, null));
    const wrong_replay_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
    });
    try std.testing.expectError(error.SupervisionDenied, replay_runspace.installReplay(fixtures.Strict.Target, image, wrong_replay_permit));

    var parked_runtime = boundary.Runtime.init(std.testing.allocator);
    defer parked_runtime.deinit();
    var parked_transcript = world.Transcript.init(std.testing.allocator);
    defer parked_transcript.deinit();
    var parked_source = world.Runspace.init(std.testing.allocator, .{});
    defer parked_source.deinit();
    const parked_handle = try parked_source.installMachineRun(fixtures.Ports.Target, PortsEnv, &parked_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &parked_transcript,
    });
    _ = parked_handle;
    _ = try parked_source.tick();
    var parked_export = try parked_source.exportPending(0);
    defer parked_export.deinit(std.testing.allocator);
    const admitted_transcript = parked_export.transcript_image.?;
    const bare_parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = parked_export.target_ref,
        .import_set_fingerprint = parked_export.import_set_fingerprint,
        .current_state = parked_export.current_state,
        .pending_request_frame = parked_export.pending_request_frame.?,
        .prior_run_receipt_fingerprint = 0x5eed_9000,
        .module_ref_fingerprint = 0x9000_5eed,
    });
    const parked_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_9000,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = bare_parked_image,
        .transcript_image = admitted_transcript,
    });
    var parked_target = world.Runspace.init(std.testing.allocator, .{});
    defer parked_target.deinit();
    const parked_installed = try parked_target.installAdmitted(parked_admitted);
    const parked_summary = try parked_target.getSlotSummary(parked_installed);
    try std.testing.expectEqual(parked_export.current_state.run_state_fingerprint, parked_summary.run_state_fingerprint);
    var reexported = try parked_target.exportRun(parked_installed);
    defer reexported.deinit(std.testing.allocator);
    try std.testing.expect(reexported.transcript_image != null);
    try std.testing.expectEqual(admitted_transcript.transcript_image_fingerprint, reexported.transcript_image.?.transcript_image_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x5eed_9000), reexported.prior_run_receipt_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x9000_5eed), reexported.module_ref_fingerprint);
    const reexported_bytes = try reexported.encode(std.testing.allocator);
    defer std.testing.allocator.free(reexported_bytes);
    var decoded_reexported = try world.RunImage.decode(std.testing.allocator, reexported_bytes);
    defer decoded_reexported.deinit(std.testing.allocator);
    try std.testing.expectEqual(reexported.run_image_fingerprint, decoded_reexported.run_image_fingerprint);

    const detached_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .pending_request_fingerprint = parked_export.pending_request_frame.?.frame_fingerprint,
        .turn_index = parked_export.pending_request_frame.?.turn_index,
        .status = .parked_on_port,
    });
    const detached_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = parked_export.target_ref,
        .import_set_fingerprint = parked_export.import_set_fingerprint,
        .current_state = detached_state,
        .pending_request_frame = parked_export.pending_request_frame.?,
    });
    const detached_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_9001,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = detached_image,
        .transcript_image = admitted_transcript,
    });
    var detached_target = world.Runspace.init(std.testing.allocator, .{});
    defer detached_target.deinit();
    const detached_installed = try detached_target.installAdmitted(detached_admitted);
    const detached_summary = try detached_target.getSlotSummary(detached_installed);
    var detached_export = try detached_target.exportRun(detached_installed);
    defer detached_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(admitted_transcript.transcript_image_fingerprint, detached_export.current_state.transcript_image_fingerprint.?);
    try std.testing.expectEqual(detached_export.current_state.run_state_fingerprint, detached_summary.run_state_fingerprint);

    var completed_attach_transcript = world.Transcript.init(std.testing.allocator);
    defer completed_attach_transcript.deinit();
    try recordPortsTranscript(&completed_attach_transcript);
    var completed_attach_image = try completed_attach_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer completed_attach_image.deinit(std.testing.allocator);
    const bare_completed_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .status = .completed,
    });
    const bare_completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = bare_completed_state,
    });
    const completed_attach_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_9002,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = bare_completed_image,
        .transcript_image = completed_attach_image,
    });
    var completed_attach_target = world.Runspace.init(std.testing.allocator, .{});
    defer completed_attach_target.deinit();
    const completed_attach_handle = try completed_attach_target.installAdmitted(completed_attach_admitted);
    const completed_attach_summary = try completed_attach_target.getSlotSummary(completed_attach_handle);
    var completed_attach_export = try completed_attach_target.exportRun(completed_attach_handle);
    defer completed_attach_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(completed_attach_image.transcript_image_fingerprint, completed_attach_export.current_state.transcript_image_fingerprint.?);
    try std.testing.expect(completed_attach_export.current_state.final_response_fingerprint != null);
    try std.testing.expect(completed_attach_export.current_state.final_value_image_fingerprint != null);
    try std.testing.expect(completed_attach_export.current_state.turn_index > bare_completed_state.turn_index);
    try std.testing.expectEqual(completed_attach_export.current_state.run_state_fingerprint, completed_attach_summary.run_state_fingerprint);

    var admitted_handoff_denied = world.Runspace.init(std.testing.allocator, .{
        .allow_handoff_install = false,
    });
    defer admitted_handoff_denied.deinit();
    try std.testing.expectError(error.RunspaceInstallDenied, admitted_handoff_denied.installAdmitted(parked_admitted));

    const branched_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .branch_id = 44,
        .status = .completed,
    });
    const branched_checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = parked_export.target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = parked_export.target_ref.target_certificate_fingerprint,
        .event_index = 0,
        .turn_index = 0,
        .transcript_prefix_fingerprint = 0,
        .branch_id = 44,
        .status = .completed,
    });
    const branched_branch = world.Timeline.Branch{
        .branch_id = 44,
        .checkpoint_fingerprint = branched_checkpoint.checkpoint_fingerprint,
        .start_event_index = 0,
        .final_event_index = 0,
        .final_status = .completed,
    };
    const branched_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = parked_export.target_ref,
        .import_set_fingerprint = parked_export.import_set_fingerprint,
        .current_state = branched_state,
        .checkpoints = &.{branched_checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branched_branch}),
    });
    const branched_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b044,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = branched_image,
    });
    var branched_target = world.Runspace.init(std.testing.allocator, .{});
    defer branched_target.deinit();
    const branched_handle = try branched_target.installAdmitted(branched_admitted);
    const branched_summary = try branched_target.getSlotSummary(branched_handle);
    try std.testing.expectEqual(@as(?u64, 44), branched_handle.branch_id);
    try std.testing.expectEqual(@as(?u64, 44), branched_summary.handle.branch_id);
    try std.testing.expectEqual(@as(?u64, 44), branched_summary.branch_id);
    const selected_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .status = .completed,
    });
    const selected_branch_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = parked_export.target_ref,
        .import_set_fingerprint = parked_export.import_set_fingerprint,
        .current_state = selected_state,
        .checkpoints = &.{branched_checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branched_branch}),
    });
    const selected_branch_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b045,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = selected_branch_image,
        .selected_branch_id = 44,
    });
    var selected_branch_target = world.Runspace.init(std.testing.allocator, .{});
    defer selected_branch_target.deinit();
    const selected_branch_handle = try selected_branch_target.installAdmitted(selected_branch_admitted);
    const selected_branch_checkpoint = try selected_branch_target.checkpoint(selected_branch_handle);
    try std.testing.expectEqual(@as(u64, 44), selected_branch_checkpoint.branch_id);
    var selected_branch_export = try selected_branch_target.exportRun(selected_branch_handle);
    defer selected_branch_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 44), selected_branch_export.current_state.branch_id);
    const branch_resume_missing_selection = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b049,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .branch_resume,
        .run_image = selected_branch_image,
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, selected_branch_target.installAdmitted(branch_resume_missing_selection));
    var selected_missing_branch_target = world.Runspace.init(std.testing.allocator, .{});
    defer selected_missing_branch_target.deinit();
    const selected_missing_branch_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b047,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = selected_branch_image,
        .selected_branch_id = 99,
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, selected_missing_branch_target.installAdmitted(selected_missing_branch_admitted));
    const selected_checkpoint_mismatch_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b046,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = selected_branch_image,
        .selected_checkpoint_ref = branched_checkpoint.checkpoint_fingerprint,
    });
    var selected_checkpoint_target = world.Runspace.init(std.testing.allocator, .{});
    defer selected_checkpoint_target.deinit();
    try std.testing.expectError(error.HandoffCheckpointMismatch, selected_checkpoint_target.installAdmitted(selected_checkpoint_mismatch_admitted));
    const unwitnessed_checkpoint_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .checkpoint_fingerprint = branched_checkpoint.checkpoint_fingerprint,
        .status = .completed,
    });
    const unwitnessed_checkpoint_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = parked_export.target_ref,
        .import_set_fingerprint = parked_export.import_set_fingerprint,
        .current_state = unwitnessed_checkpoint_state,
    });
    const unwitnessed_checkpoint_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_b048,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .mode = .continue_fresh,
        .run_image = unwitnessed_checkpoint_image,
        .selected_checkpoint_ref = branched_checkpoint.checkpoint_fingerprint,
    });
    var unwitnessed_checkpoint_target = world.Runspace.init(std.testing.allocator, .{});
    defer unwitnessed_checkpoint_target.deinit();
    try std.testing.expectError(error.HandoffCheckpointMismatch, unwitnessed_checkpoint_target.installAdmitted(unwitnessed_checkpoint_admitted));

    var replay_denied = world.Runspace.init(std.testing.allocator, .{
        .allow_replay_install = false,
    });
    defer replay_denied.deinit();
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installReplay(fixtures.Strict.Target, image, null));
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installRunImage(replay_export));
    const replay_image_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5517,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .mode = .continue_fresh,
        .run_image = replay_export,
    });
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installAdmitted(replay_image_admitted));
    const transcript_only_replay_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5518,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .mode = .replay_only,
        .transcript_image = image,
    });
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installAdmitted(transcript_only_replay_admitted));
    var replay_denied_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_denied_runtime.deinit();
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installMachineRun(fixtures.Strict.Target, StrictReplayEnv, &replay_denied_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    }));
    try std.testing.expectError(error.RunspaceInstallDenied, replay_denied.installVerifyRun(fixtures.Strict.Target, StrictReplayEnv, &replay_denied_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .transcript_image = &image,
    }));
    var manual_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer manual_replay_runtime.deinit();
    var manual_replay_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer manual_replay_runspace.deinit();
    try std.testing.expectError(error.RunspaceInstallDenied, manual_replay_runspace.installMachineRun(fixtures.Strict.Target, StrictReplayEnv, &manual_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    }));
    try std.testing.expectError(error.RunspaceInstallDenied, manual_replay_runspace.installVerifyRun(fixtures.Strict.Target, StrictReplayEnv, &manual_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .transcript_image = &image,
    }));
}

test "runspace tick parks responds and completes machine run" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    var report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.parked_count);
    try std.testing.expectEqual(@as(usize, 1), report.pending_port_count);
    const pending = try runspace.mailbox.get(0);
    try std.testing.expectEqual(handle.handle_fingerprint, pending.handle.handle_fingerprint);
    try std.testing.expectEqual(PortsDecl.world_port_id, pending.world_port_id);
    const request_frame = pending.request_frame orelse return error.ExpectedFrameRequest;
    var deferred_response = try world.Frame.Response.fromPortableValue(
        std.testing.allocator,
        request_frame,
        pending.expected_response_value_table_id,
        pending.expected_response_kind,
        @as(i32, 7),
        .portable,
    );
    defer deferred_response.deinit(std.testing.allocator);
    try std.testing.expect(deferred_response.responseFingerprintDeferred());

    const response_event = try runspace.respondValue(0, @as(i32, 7));
    try std.testing.expectEqual(world.Runspace.EventKind.run_resumed, response_event.kind);
    report = runspace.poll();
    try std.testing.expectEqual(@as(usize, 1), report.runnable_count);
    try std.testing.expectEqual(@as(usize, 0), report.pending_port_count);
    const pending_after_response = try runspace.mailbox.listPending(std.testing.allocator);
    defer std.testing.allocator.free(pending_after_response);
    try std.testing.expectEqual(@as(usize, 0), pending_after_response.len);
    var transcript_image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer transcript_image.deinit(std.testing.allocator);
    const transcript_response_frame = for (transcript_image.events) |event| {
        if (event.kind == .frame_responded) break event.response_frame.?;
    } else return error.ExpectedResponseFrame;
    try std.testing.expect(transcript_response_frame.frame_fingerprint != deferred_response.frame_fingerprint);
    try std.testing.expectEqual(transcript_response_frame.frame_fingerprint, response_event.response_frame_fingerprint.?);
    try std.testing.expectEqual(request_frame.frame_fingerprint, response_event.request_frame_fingerprint.?);
    const port_responded_event = for (runspace.events.items) |event| {
        if (event.kind == .port_responded) break event;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(transcript_response_frame.frame_fingerprint, port_responded_event.response_frame_fingerprint.?);
    try std.testing.expectEqual(request_frame.frame_fingerprint, port_responded_event.request_frame_fingerprint.?);
    const resumed_checkpoint = try runspace.checkpoint(handle);
    try std.testing.expectEqual(transcript_response_frame.frame_fingerprint, resumed_checkpoint.last_response_fingerprint.?);
    try std.testing.expectEqual(@as(usize, 1), resumed_checkpoint.turn_index);

    report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.completed_count);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
    var exported = try runspace.exportRun(handle);
    defer exported.deinit(std.testing.allocator);
    try std.testing.expectEqual(transcript_response_frame.response_value_fingerprint.?, exported.current_state.final_value_image_fingerprint.?);
}

test "guest core drives one run through canonical request and response bytes" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    try std.testing.expectEqual(world.Guest.Status.initialized, guest.status());
    try std.testing.expectEqual(world.Guest.Status.parked, guest.tick());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), guest.pendingCount());

    const request_len = guest.pendingRequestLen(0);
    try std.testing.expect(request_len > 0);
    var tiny_request: [1]u8 = undefined;
    try std.testing.expectEqual(request_len, guest.readPendingRequest(0, &tiny_request));
    try std.testing.expectEqual(world.Guest.Status.buffer_too_small, guest.status());

    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    try std.testing.expectEqual(request_len, guest.readPendingRequest(0, request_bytes));
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    try std.testing.expectEqual(PortsDecl.world_port_id, request.world_port_id);
    try std.testing.expectEqual(fixtures.Ports.ApprovalRequest.fingerprint, request.residual_site_fingerprint);

    var response = try world.Frame.Response.fromPortableValue(
        std.testing.allocator,
        request,
        1,
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer response.deinit(std.testing.allocator);
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);

    try std.testing.expectEqual(world.Guest.Status.running, guest.submitResponse(response_bytes));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Guest.Status.stale_pending, guest.submitResponse(response_bytes));
    try std.testing.expect(guest.lastErrorLen() > 0);
    try std.testing.expectEqual(world.Guest.Status.done, guest.tick());

    const result_len = guest.resultLen();
    try std.testing.expect(result_len > 0);
    const result_bytes = try std.testing.allocator.alloc(u8, result_len);
    defer std.testing.allocator.free(result_bytes);
    try std.testing.expectEqual(result_len, guest.readResult(result_bytes));
    var image = try world.RunImage.decode(std.testing.allocator, result_bytes);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.completed_run, image.kind);
    try std.testing.expectEqual(world.RunState.Status.completed, image.current_state.status);
    try std.testing.expect(image.current_state.final_value_image_fingerprint != null);

    const transcript_len = guest.transcriptLen();
    try std.testing.expect(transcript_len > 0);
    const transcript_bytes = try std.testing.allocator.alloc(u8, transcript_len);
    defer std.testing.allocator.free(transcript_bytes);
    try std.testing.expectEqual(transcript_len, guest.readTranscript(transcript_bytes));
    var transcript_image = try world.TranscriptImage.decode(std.testing.allocator, transcript_bytes);
    defer transcript_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.completed, transcript_image.final_status);
}

test "guest core result bytes use post-export supervised receipt" {
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const export_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = export_policy,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{ .require_supervision = true });
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Strict.Target, StrictEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    try std.testing.expectEqual(world.Guest.Status.done, guest.tick());

    const result_len = guest.resultLen();
    try std.testing.expect(result_len > 0);
    const result_bytes = try std.testing.allocator.alloc(u8, result_len);
    defer std.testing.allocator.free(result_bytes);
    try std.testing.expectEqual(result_len, guest.readResult(result_bytes));
    var image = try world.RunImage.decode(std.testing.allocator, result_bytes);
    defer image.deinit(std.testing.allocator);
    const receipt = image.prior_run_receipt_fingerprint orelse return error.ExpectedRunReceipt;

    var receipt_bytes: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, receipt_bytes.len), guest.receiptLen());
    try std.testing.expectEqual(@as(usize, receipt_bytes.len), guest.readReceipt(&receipt_bytes));
    try std.testing.expectEqual(receipt, std.mem.readInt(u64, &receipt_bytes, .little));

    const events = guest.runspace.report().emitted_events;
    const exported_event = events[events.len - 1];
    try std.testing.expectEqual(world.Runspace.EventKind.run_exported, exported_event.kind);
    try std.testing.expectEqual(receipt, exported_event.run_receipt_fingerprint.?);
}

test "guest result maps handoff denied to supervision denied" {
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{ .require_supervision = true });
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Strict.Target, StrictEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    try std.testing.expectEqual(world.Guest.Status.done, guest.tick());
    try std.testing.expectEqual(@as(usize, 0), guest.resultLen());
    try std.testing.expectEqual(world.Guest.Status.supervision_denied, guest.status());
    try std.testing.expect(guest.lastErrorLen() > 0);
}

test "guest core clamps explicit pending-port config to ABI cap" {
    var guest = world.Guest.Core.init(std.testing.allocator, .{
        .max_pending_ports = world.Guest.Buffer.max_pending_ports + 10,
    });
    defer guest.deinit();
    try std.testing.expectEqual(@as(?usize, world.Guest.Buffer.max_pending_ports), guest.runspace.mailbox.max_pending_ports);
}

test "guest core submit response refreshes terminal status" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked, guest.tick());
    const request_len = guest.pendingRequestLen(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.readPendingRequest(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    const failed_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x5a1e,
        .replay_key = request.replay_key_seed.withResponse(0x5a1e).fingerprint(),
        .status = .failed,
    });
    const response_bytes = try failed_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);

    try std.testing.expectEqual(world.Guest.Status.failed, guest.submitResponse(response_bytes));
    try std.testing.expectEqual(world.Guest.Status.failed, guest.status());
}

test "native guest world_init clears cached session state" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
    const request_len = guest.world_pending_request_len(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.world_read_pending_request(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    var response = try world.Frame.Response.fromPortableValue(
        std.testing.allocator,
        request,
        request.expected_response_value_table_id,
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer response.deinit(std.testing.allocator);
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);
    try std.testing.expectEqual(world.Guest.Status.running.code(), guest.world_submit_response(response_bytes));
    try std.testing.expectEqual(world.Guest.Status.done.code(), guest.world_tick());
    try std.testing.expect(guest.world_result_len() > 0);

    try std.testing.expectEqual(world.Guest.Status.initialized.code(), guest.world_init());
    try std.testing.expectEqual(@as(usize, 0), guest.world_result_len());
    try std.testing.expectEqual(@as(u32, 0), guest.world_pending_count());
    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
}

test "native guest world_init preserves newly installed run" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.initialized.code(), guest.world_init());
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
    try std.testing.expectEqual(@as(u32, 1), guest.world_pending_count());
}

test "guest install admitted completed image refreshes status" {
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();
    const target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .completed,
        }),
    });
    const admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_6010,
        .target_ref = target_ref,
        .mode = .continue_fresh,
        .run_image = completed_image,
    });

    try guest.installAdmitted(admitted);
    try std.testing.expectEqual(world.Guest.Status.done, guest.status());
    try std.testing.expect(guest.resultLen() > 0);
}

test "native guest world_init clears failed session state" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
    const request_len = guest.world_pending_request_len(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.world_read_pending_request(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    const failed_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x6572_726f_725f_696e,
        .replay_key = request.replay_key_seed.withResponse(0x6572_726f_725f_696e).fingerprint(),
        .status = .failed,
    });
    const failed_response_bytes = try failed_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(failed_response_bytes);
    try std.testing.expectEqual(world.Guest.Status.failed.code(), guest.world_submit_response(failed_response_bytes));
    try std.testing.expectEqual(world.Guest.Status.initialized.code(), guest.world_init());
    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
}

test "native guest pending request length refreshes stale invalid frame status" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
    try std.testing.expectEqual(world.Guest.Status.invalid_frame.code(), guest.world_submit_response(&.{ 0, 1, 2, 3 }));
    try std.testing.expectEqual(world.Guest.Status.invalid_frame.code(), guest.world_status());

    const request_len = guest.world_pending_request_len(0);
    try std.testing.expect(request_len > 0);
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_status());
    try std.testing.expectEqual(@as(usize, 0), guest.world_last_error_len());
}

test "guest core install run image exposes parked handoff immediately" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var source = world.Runspace.init(std.testing.allocator, .{});
    defer source.deinit();
    const handle = try source.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try source.tick();
    var image = try source.exportRun(handle);
    defer image.deinit(std.testing.allocator);

    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();
    try guest.installRunImage(image);

    try std.testing.expectEqual(world.Guest.Status.parked, guest.status());
    try std.testing.expectEqual(@as(usize, 1), guest.pendingCount());
    try std.testing.expect(guest.pendingRequestLen(0) > 0);
}

test "guest core pending response preserves parked request state" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked, guest.tick());
    const request_len = guest.pendingRequestLen(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.readPendingRequest(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_fingerprint = 0x6775_6573_745f_7065,
        .replay_key = request.replay_key_seed.withResponse(0x6775_6573_745f_7065).fingerprint(),
        .status = .pending,
    });
    const pending_response_bytes = try pending_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(pending_response_bytes);

    try std.testing.expectEqual(world.Guest.Status.parked, guest.submitResponse(pending_response_bytes));
    try std.testing.expectEqual(@as(usize, 1), guest.pendingCount());
    try std.testing.expectEqual(@as(usize, request_len), guest.pendingRequestLen(0));
    try std.testing.expectEqual(@as(usize, 0), guest.lastErrorLen());
}

test "guest core supervision-parked pending response does not expose pending work" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_pending_responses = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{ .require_supervision = true });
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    try std.testing.expectEqual(world.Guest.Status.parked, guest.tick());
    const request_len = guest.pendingRequestLen(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.readPendingRequest(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_fingerprint = 0x7375_7065_725f_706b,
        .replay_key = request.replay_key_seed.withResponse(0x7375_7065_725f_706b).fingerprint(),
        .status = .pending,
    });
    const pending_response_bytes = try pending_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(pending_response_bytes);

    try std.testing.expectEqual(world.Guest.Status.supervision_denied, guest.submitResponse(pending_response_bytes));
    try std.testing.expectEqual(@as(usize, 0), guest.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), guest.pendingRequestLen(0));
    try std.testing.expectEqual(world.Guest.Status.supervision_denied, guest.submitResponse(pending_response_bytes));
}

test "guest core reports supervision-only park without exposing pending request" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });

    try std.testing.expectEqual(world.Guest.Status.supervision_denied, guest.tick());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), guest.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), guest.pendingRequestLen(0));
    try std.testing.expect(guest.lastErrorLen() > 0);
}

test "guest core rejects pending request bytes above ABI cap" {
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();
    const oversized_payload = try std.testing.allocator.alloc(u8, world.Guest.Buffer.max_request_bytes + 1);
    defer std.testing.allocator.free(oversized_payload);
    @memset(oversized_payload, 'x');
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const run_handle = world.RunHandle.init(.{
        .runspace_fingerprint = guest.runspace.runspace_fingerprint,
        .local_run_id = 1,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
    });
    var payload_image = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        0,
        null,
        null,
        oversized_payload,
        world.ValuePolicy.portable,
    );
    var request = world.Frame.Request.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .world_surface_replay_scope_fingerprint = target_ref.world_surface_replay_scope_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0x6775_6573_745f_6269,
        .turn_index = 0,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = payload_image,
    });
    payload_image = undefined;
    defer request.deinit(std.testing.allocator);
    _ = try guest.runspace.mailbox.push(.{
        .run_handle = run_handle,
        .mailbox_id = 0,
        .request = request,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .inserted_event_index = 0,
    });

    try std.testing.expectEqual(@as(usize, 0), guest.pendingRequestLen(0));
    try std.testing.expectEqual(world.Guest.Status.buffer_too_small, guest.status());
    var out: [world.Guest.Buffer.max_request_bytes]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 0), guest.readPendingRequest(0, &out));
    try std.testing.expectEqual(world.Guest.Status.buffer_too_small, guest.status());
}

test "guest core oversized result cap does not export run before cap check" {
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();
    const metadata = try std.testing.allocator.alloc(u8, world.Guest.Buffer.max_result_bytes + 1);
    defer std.testing.allocator.free(metadata);
    @memset(metadata, 'r');
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const import_set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = state,
        .metadata = metadata,
    });

    try guest.installRunImage(image);
    try std.testing.expectEqual(world.Guest.Status.done, guest.tick());
    try std.testing.expectEqual(@as(usize, 0), guest.resultLen());
    try std.testing.expectEqual(world.Guest.Status.buffer_too_small, guest.status());
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try guest.runspace.getSlotSummary(guest.handle.?)).status);
    try std.testing.expect(guest.lastErrorLen() > 0);
    guest.initSession();
    try std.testing.expectEqual(world.Guest.Status.initialized, guest.status());
    try guest.installRunImage(image);
    try std.testing.expectEqual(world.Guest.Status.done, guest.status());
    try std.testing.expectEqual(world.Guest.Status.done, guest.tick());
    try std.testing.expectEqual(@as(usize, 0), guest.resultLen());
    try std.testing.expectEqual(world.Guest.Status.buffer_too_small, guest.status());
}

test "guest core rejects invalid and unknown response frames at byte boundary" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();

    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    try std.testing.expectEqual(world.Guest.Status.parked, guest.tick());
    try std.testing.expectEqual(world.Guest.Status.invalid_frame, guest.submitResponse(&.{ 0, 1, 2, 3 }));
    const invalid_error_len = guest.lastErrorLen();
    try std.testing.expect(invalid_error_len > 0);
    const invalid_error = try std.testing.allocator.alloc(u8, invalid_error_len);
    defer std.testing.allocator.free(invalid_error);
    try std.testing.expectEqual(invalid_error_len, guest.readLastError(invalid_error));
    try std.testing.expectEqual(world.Guest.Status.invalid_frame, guest.status());
    try std.testing.expectEqual(invalid_error_len, guest.lastErrorLen());

    const request_len = guest.pendingRequestLen(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.readPendingRequest(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    var wrong_response = try world.Frame.Response.fromPortableValue(
        std.testing.allocator,
        request,
        1,
        .@"resume",
        @as(i32, 7),
        .portable,
    );
    defer wrong_response.deinit(std.testing.allocator);
    wrong_response.request_fingerprint +%= 1;
    wrong_response.frame_fingerprint = 0;
    wrong_response.frame_fingerprint = wrong_response.frame_fingerprint;
    const wrong_response_bytes = try wrong_response.encode(std.testing.allocator);
    defer std.testing.allocator.free(wrong_response_bytes);
    try std.testing.expectEqual(world.Guest.Status.invalid_frame, guest.submitResponse(wrong_response_bytes));

    try std.testing.expectEqual(@as(usize, 0), guest.pendingRequestLen(99));
    try std.testing.expectEqual(world.Guest.Status.unknown_pending, guest.status());
}

test "runspace manual default parks without environment dispatch" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    const report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.parked_count);
    try std.testing.expectEqual(@as(usize, 1), report.pending_port_count);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    const response_event = try runspace.respondValue(0, @as(i32, 7));
    _ = try runspace.tick();
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.completed_run, image.kind);
    try std.testing.expectEqual(response_event.response_frame_fingerprint.?, image.current_state.final_response_fingerprint.?);
    try std.testing.expect(image.current_state.final_value_image_fingerprint != null);
}

test "runspace supervised manual response charges once" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_responses = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    _ = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const response_event = try runspace.respondValue(0, @as(i32, 7));
    try std.testing.expectEqual(world.Runspace.EventKind.run_resumed, response_event.kind);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace failed manual response consumes mailbox and fails slot" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const failed_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x5a1e,
        .replay_key = request.replay_key_seed.withResponse(0x5a1e).fingerprint(),
        .status = .failed,
    });

    const event = try runspace.respond(0, failed_response);
    try std.testing.expectEqual(world.Runspace.EventKind.run_failed, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace typed response validation failure preserves pending mailbox" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    var wrong_fingerprint_response = try world.Frame.Response.fromValue(
        std.testing.allocator,
        request,
        pending.expected_response_value_table_id,
        0xdec1_5100,
        pending.expected_response_kind,
        @as(i32, 7),
        .portable,
    );
    defer wrong_fingerprint_response.deinit(std.testing.allocator);

    try std.testing.expectError(error.VerifyResponseFingerprintMismatch, runspace.respond(0, wrong_fingerprint_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);

    _ = try runspace.respondValue(0, @as(i32, 7));
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
}

test "runspace terminal resume failure consumes pending mailbox and fails slot" {
    var seed_transcript = world.Transcript.init(std.testing.allocator);
    defer seed_transcript.deinit();
    try recordPortsTranscript(&seed_transcript);
    const response_fingerprint = (try firstRespondedEvent(&seed_transcript)).response_fingerprint.?;

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(ResumeFailureTarget, ResumeFailureEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    var response = try world.Frame.Response.fromValue(
        std.testing.allocator,
        request,
        pending.expected_response_value_table_id,
        response_fingerprint,
        pending.expected_response_kind,
        @as(i32, 7),
        .portable,
    );
    defer response.deinit(std.testing.allocator);

    try std.testing.expectError(error.TestResumeFailed, runspace.respond(0, response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().failed_count);
}

test "runspace raw terminal response checks supervision before consuming mailbox" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const failed_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x5a1e_5afe,
        .replay_key = request.replay_key_seed.withResponse(0x5a1e_5afe).fingerprint(),
        .status = .failed,
    });

    var forged_response = failed_response;
    forged_response.frame_fingerprint +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.respond(0, forged_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectError(error.HandlerFailed, runspace.respond(0, failed_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().blocker_count);
}

test "runspace pending manual response checks supervision before preserving mailbox" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x9e1d_5afe,
        .replay_key = request.replay_key_seed.withResponse(0x9e1d_5afe).fingerprint(),
        .status = .pending,
    });

    try std.testing.expectError(error.PendingDenied, runspace.respond(0, pending_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace manual response park-on-budget preserves pending mailbox" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const event = try runspace.respondValue(0, @as(i32, 7));
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
    var image = try runspace.exportPending(0);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.parked_run, image.kind);
    try std.testing.expect(image.pending_request_frame != null);
    try std.testing.expectEqual(world.Runspace.PendingStatus.exported, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try runspace.getSlotSummary(handle)).status);
}

test "runspace strict manual response budget failure consumes mailbox and fails slot" {
    const strict_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = strict_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();

    try std.testing.expectError(error.BudgetExceeded, runspace.respondValue(0, @as(i32, 7)));
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().blocker_count);
}

test "runspace supervision park event budget failure preserves port parked state" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    runspace.config.max_events = runspace.events.items.len;

    try std.testing.expectError(error.BudgetExceeded, runspace.respondValue(0, @as(i32, 7)));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace response event budget failure does not charge supervisor" {
    const response_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = response_policy,
        .budget = world.Budget.init(.{ .max_port_responses = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    runspace.config.max_events = runspace.events.items.len;

    try std.testing.expectError(error.BudgetExceeded, runspace.respondValue(0, @as(i32, 7)));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);

    runspace.config.max_events = null;
    const event = try runspace.respondValue(0, @as(i32, 7));
    try std.testing.expectEqual(world.Runspace.EventKind.run_resumed, event.kind);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace pending manual response byte budget preserves pending mailbox" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_pending_responses = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x9e1d_b7e5,
        .replay_key = request.replay_key_seed.withResponse(0x9e1d_b7e5).fingerprint(),
        .status = .pending,
    });

    const event = try runspace.respond(0, pending_response);
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace pending manual response event budget preflights before supervision accounting" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_pending_responses = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_value_table_id = request.expected_response_value_table_id,
        .response_fingerprint = 0x9e1d_b7e6,
        .replay_key = request.replay_key_seed.withResponse(0x9e1d_b7e6).fingerprint(),
        .status = .pending,
    });
    runspace.config.max_events = runspace.events.items.len;

    try std.testing.expectError(error.BudgetExceeded, runspace.respond(0, pending_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().blocker_count);

    runspace.config.max_events = null;
    const event = try runspace.respond(0, pending_response);
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
}

test "runspace pending manual response preserves parked slot and mailbox" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame.?;
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_kind = .@"resume",
        .response_fingerprint = 0x9e1d,
        .replay_key = request.replay_key_seed.withResponse(0x9e1d).fingerprint(),
        .status = .pending,
    });

    try std.testing.expectError(error.HandlerPending, runspace.respond(0, pending_response));
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace auto dispatch uses environment binding and consumes mailbox" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.runnable_count);
    try std.testing.expectEqual(@as(usize, 0), report.pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);

    report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.completed_count);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.completed_run, image.kind);
    try std.testing.expect(image.transcript_image == null);
    try std.testing.expect(image.current_state.final_response_fingerprint != null);
    try std.testing.expect(image.current_state.final_value_image_fingerprint != null);
}

test "runspace auto dispatch handler failure consumes mailbox and fails slot" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });

    try std.testing.expectError(error.MissingHandler, runspace.tick());
    try std.testing.expectEqual(world.Runspace.PendingStatus.failed, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace auto dispatch event allocation failure happens before handler call" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{ .auto_dispatch = true });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 4);
    try runspace.mailbox.pending.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index + 5;

    try std.testing.expectError(error.OutOfMemory, runspace.tick());
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expect((try runspace.getSlotSummary(handle)).status != .parked_on_port);
}

test "runspace export pending rejects stale mailbox without changing run state" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });

    _ = try runspace.tick();
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    const checkpoint = try runspace.checkpoint(handle);
    try std.testing.expect(checkpoint.last_response_fingerprint != null);
    try std.testing.expectEqual(@as(usize, 1), checkpoint.turn_index);
    const auto_port_responded = for (runspace.events.items) |event| {
        if (event.kind == .port_responded) break event;
    } else return error.ExpectedResponseFrame;
    try std.testing.expect(auto_port_responded.response_frame_fingerprint != null);

    try std.testing.expectError(error.PendingPortConsumed, runspace.exportPending(0));
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(world.Runspace.PendingStatus.responded, (try runspace.mailbox.get(0)).status);
}

test "runspace auto dispatch replay stores frame response witness in state" {
    var seed_runtime = boundary.Runtime.init(std.testing.allocator);
    defer seed_runtime.deinit();
    var seed_ctx: PortsCtx = .{};
    var seed_transcript = world.Transcript.init(std.testing.allocator);
    defer seed_transcript.deinit();
    var seed_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer seed_runspace.deinit();
    _ = try seed_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &seed_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &seed_ctx,
        .transcript = &seed_transcript,
    });
    _ = try seed_runspace.tick();
    _ = try seed_runspace.respondValue(0, @as(i32, 7));
    _ = try seed_runspace.tick();
    var transcript_image = try seed_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer transcript_image.deinit(std.testing.allocator);
    const expected_response_frame_fingerprint = for (transcript_image.events) |event| {
        if (event.kind == .frame_responded) break event.response_frame.?.frame_fingerprint;
    } else return error.ExpectedResponseFrame;

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsReplayEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &transcript_image,
    });

    _ = try runspace.tick();
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    const auto_port_responded = for (runspace.events.items) |event| {
        if (event.kind == .port_responded) break event;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(expected_response_frame_fingerprint, auto_port_responded.response_frame_fingerprint.?);
    const checkpoint = try runspace.checkpoint(handle);
    try std.testing.expectEqual(expected_response_frame_fingerprint, checkpoint.last_response_fingerprint.?);

    _ = try runspace.tick();
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(expected_response_frame_fingerprint, image.current_state.final_response_fingerprint.?);
}

test "runspace export run consumes parked mailbox entry" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .max_pending_ports = 1,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);

    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.parked_run, image.kind);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(world.Runspace.PendingStatus.exported, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    const checkpoint = try runspace.checkpoint(handle);
    try std.testing.expectEqual(world.Timeline.Checkpoint.Status.parked_on_port, checkpoint.status);

    const replacement = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 1), replacement.local_run_id);
}

test "runspace export run event budget failure does not change slot state" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    }), &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    _ = try runspace.tick();
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
    runspace.config.max_events = runspace.events.items.len;

    try std.testing.expectError(error.BudgetExceeded, runspace.exportRun(handle));
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
}

test "runspace supervised export events carry receipt witnesses" {
    const export_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
    });

    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const completed_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = export_policy,
    });
    var completed_runtime = boundary.Runtime.init(std.testing.allocator);
    defer completed_runtime.deinit();
    var completed_runspace = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer completed_runspace.deinit();
    const completed_handle = try completed_runspace.installMachineRun(fixtures.Strict.Target, StrictEnv, &completed_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = completed_permit,
    });
    _ = try completed_runspace.tick();
    var completed_image = try completed_runspace.exportRun(completed_handle);
    defer completed_image.deinit(std.testing.allocator);
    const completed_receipt = completed_image.prior_run_receipt_fingerprint orelse return error.ExpectedRunReceipt;
    const completed_export_event = completed_runspace.report().emitted_events[completed_runspace.report().emitted_events.len - 1];
    try std.testing.expectEqual(world.Runspace.EventKind.run_exported, completed_export_event.kind);
    try std.testing.expectEqual(completed_receipt, completed_export_event.run_receipt_fingerprint.?);

    const parked_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = export_policy,
    });
    var parked_runtime = boundary.Runtime.init(std.testing.allocator);
    defer parked_runtime.deinit();
    var parked_runspace = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer parked_runspace.deinit();
    _ = try parked_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &parked_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = parked_permit,
    });
    _ = try parked_runspace.tick();
    var parked_image = try parked_runspace.exportPending(0);
    defer parked_image.deinit(std.testing.allocator);
    const parked_receipt = parked_image.prior_run_receipt_fingerprint orelse return error.ExpectedRunReceipt;
    const parked_export_event = parked_runspace.report().emitted_events[parked_runspace.report().emitted_events.len - 1];
    try std.testing.expectEqual(world.Runspace.EventKind.run_exported, parked_export_event.kind);
    try std.testing.expectEqual(parked_receipt, parked_export_event.run_receipt_fingerprint.?);

    const sender_receipt_fingerprint: u64 = 0x5eed_cafe;
    const admitted_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = export_policy,
    });
    const admitted_state = world.RunState.init(.{
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
        .status = .completed,
    });
    const admitted_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = admitted_state,
        .prior_run_receipt_fingerprint = sender_receipt_fingerprint,
    });
    const admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_7ece,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .environment_certificate_fingerprint = StrictEnv.certificate(.fresh, false).certificate_fingerprint,
        .mode = .continue_fresh,
        .run_image = admitted_image,
        .run_permit = admitted_permit,
    });
    var admitted_runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer admitted_runspace.deinit();
    const admitted_handle = try admitted_runspace.installAdmitted(admitted);
    var admitted_export = try admitted_runspace.exportRun(admitted_handle);
    defer admitted_export.deinit(std.testing.allocator);
    const admitted_receipt = admitted_export.prior_run_receipt_fingerprint orelse return error.ExpectedRunReceipt;
    const admitted_export_event = admitted_runspace.report().emitted_events[admitted_runspace.report().emitted_events.len - 1];
    try std.testing.expectEqual(world.Runspace.EventKind.run_exported, admitted_export_event.kind);
    try std.testing.expect(admitted_receipt != sender_receipt_fingerprint);
    try std.testing.expectEqual(admitted_receipt, admitted_export_event.run_receipt_fingerprint.?);
}

test "runspace export run event allocation failure does not change slot state" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    const target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const export_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = export_policy,
        .budget = world.Budget.init(.{ .max_handoff_exports = 1 }),
    });
    const supervisor = try world.Supervision.Supervisor.init(failing_allocator.allocator(), permit, 0);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit.permit_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    try runspace.slots.append(failing_allocator.allocator(), world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .completed,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .supervisor = supervisor,
    }));
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index;

    try std.testing.expectError(error.OutOfMemory, runspace.exportRun(handle));
    try std.testing.expect(failing_allocator.has_induced_failure);
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, summary.status);
    try std.testing.expectEqual(@as(usize, 0), runspace.events.items.len);
    failing_allocator.fail_index = std.math.maxInt(usize);
    var image = try runspace.exportRun(handle);
    defer image.deinit(failing_allocator.allocator());
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try runspace.getSlotSummary(handle)).status);
}

test "runspace export checks supervision before snapshotting installed image" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    var transcript = world.Transcript.init(failing_allocator.allocator());
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var transcript_image = try transcript.toImage(failing_allocator.allocator(), .{ .value_policy = world.ValuePolicy.portable });
    var installed_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, transcript_image, .completed_run);
    installed_image.owns_transcript_image = true;
    transcript_image = undefined;
    var installed_image_owned = true;
    errdefer if (installed_image_owned) installed_image.deinit(failing_allocator.allocator());

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const deny_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = deny_policy,
    });
    const supervisor = try world.Supervision.Supervisor.init(failing_allocator.allocator(), permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit.permit_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = installed_image.transcript_image.?.transcript_image_fingerprint,
        .status = .completed,
    });
    try runspace.slots.append(failing_allocator.allocator(), world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .completed,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .supervisor = supervisor,
        .installed_run_image = installed_image,
        .owns_installed_run_image = true,
    }));
    installed_image_owned = false;
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index + 2;

    try std.testing.expectError(error.HandoffDenied, runspace.exportRun(handle));
    try std.testing.expect(!failing_allocator.has_induced_failure);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
}

test "guest result preview failure restores handoff budget" {
    var guest = world.Guest.Core.init(std.testing.allocator, .{});
    defer guest.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var transcript_image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    var installed_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, transcript_image, .completed_run);
    installed_image.owns_transcript_image = true;
    transcript_image = undefined;
    var installed_image_owned = true;
    errdefer if (installed_image_owned) installed_image.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const export_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = export_policy,
        .budget = world.Budget.init(.{ .max_handoff_exports = 0 }),
    });
    const supervisor = try world.Supervision.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = guest.runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit.permit_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = installed_image.transcript_image.?.transcript_image_fingerprint,
        .status = .completed,
    });
    try guest.runspace.slots.append(std.testing.allocator, world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .completed,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .supervisor = supervisor,
        .installed_run_image = installed_image,
        .owns_installed_run_image = true,
    }));
    installed_image_owned = false;
    guest.handle = handle;
    guest.state = .done;

    try std.testing.expectEqual(@as(usize, 0), guest.resultLen());
    try std.testing.expectEqual(world.Guest.Status.supervision_denied, guest.status());
    try std.testing.expectEqual(@as(usize, 0), guest.runspace.slots.items[0].supervisor.?.ledger.total_handoff_exports);
    try std.testing.expect(guest.runspace.slots.items[0].supervisor.?.ledger.exceeded_budget == null);
    try std.testing.expect(guest.runspace.slots.items[0].supervisor.?.last_check == null);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try guest.runspace.getSlotSummary(handle)).status);
}

test "runspace export snapshot failure restores handoff budget" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    var transcript = world.Transcript.init(failing_allocator.allocator());
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var transcript_image = try transcript.toImage(failing_allocator.allocator(), .{ .value_policy = world.ValuePolicy.portable });
    var installed_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, transcript_image, .completed_run);
    installed_image.owns_transcript_image = true;
    transcript_image = undefined;
    var installed_image_owned = true;
    errdefer if (installed_image_owned) installed_image.deinit(failing_allocator.allocator());

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const export_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = export_policy,
        .budget = world.Budget.init(.{ .max_handoff_exports = 1 }),
    });
    const supervisor = try world.Supervision.Supervisor.init(failing_allocator.allocator(), permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit.permit_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = installed_image.transcript_image.?.transcript_image_fingerprint,
        .status = .completed,
    });
    try runspace.slots.append(failing_allocator.allocator(), world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .completed,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .supervisor = supervisor,
        .installed_run_image = installed_image,
        .owns_installed_run_image = true,
    }));
    installed_image_owned = false;
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index + 3;

    try std.testing.expectError(error.OutOfMemory, runspace.exportRun(handle));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), runspace.slots.items[0].supervisor.?.ledger.total_handoff_exports);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);

    failing_allocator.fail_index = std.math.maxInt(usize);
    var image = try runspace.exportRun(handle);
    defer image.deinit(failing_allocator.allocator());
    try std.testing.expectEqual(@as(usize, 1), runspace.slots.items[0].supervisor.?.ledger.total_handoff_exports);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try runspace.getSlotSummary(handle)).status);
}

test "runspace checkpoint and branch allocation failures do not spend supervision budgets" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{});
    defer runspace.deinit();
    const target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target);
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const lifecycle_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_checkpoints = true,
        .allow_branching = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = lifecycle_policy,
        .budget = world.Budget.init(.{
            .max_checkpoints = 1,
            .max_branches = 1,
        }),
    });
    const supervisor = try world.Supervision.Supervisor.init(failing_allocator.allocator(), permit, 0);
    const handle = world.RunHandle.init(.{
        .runspace_fingerprint = runspace.runspace_fingerprint,
        .local_run_id = 0,
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .permit_fingerprint = permit.permit_fingerprint,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    try runspace.slots.append(failing_allocator.allocator(), world.Runspace.RunSlot.fromState(.{
        .handle = handle,
        .target_ref = target_ref,
        .current_state = state,
        .status = .completed,
        .run_permit_fingerprint = permit.permit_fingerprint,
        .supervisor = supervisor,
    }));
    runspace.next_run_id = 1;
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index;

    try std.testing.expectError(error.OutOfMemory, runspace.checkpoint(handle));
    failing_allocator.fail_index = std.math.maxInt(usize);
    const checkpoint = try runspace.checkpoint(handle);
    try std.testing.expectEqual(@as(usize, 1), runspace.events.items.len);

    try runspace.slots.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 1);
    failing_allocator.fail_index = failing_allocator.alloc_index;
    try std.testing.expectError(error.OutOfMemory, runspace.branch(handle, checkpoint, .{}));
    try std.testing.expectEqual(@as(usize, 1), runspace.slots.items.len);
    failing_allocator.fail_index = std.math.maxInt(usize);
    const branch_handle = try runspace.branch(handle, checkpoint, .{});
    try std.testing.expectEqual(@as(u64, 1), branch_handle.local_run_id);
}

test "runspace supervised auto dispatch denial happens before handler call" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_fresh_calls = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .auto_dispatch = true,
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    try std.testing.expectError(error.BudgetExceeded, runspace.tick());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    const report = runspace.report();
    try std.testing.expectEqual(@as(usize, 1), report.blocker_count);
    try std.testing.expectEqual(@as(usize, 0), report.warning_count);
}

test "runspace report aggregates supervised audit-only warnings" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .audit_only_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    _ = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    const tick_report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 3), tick_report.warning_count);
    try std.testing.expectEqual(@as(usize, 0), tick_report.blocker_count);
    try std.testing.expectEqual(@as(usize, 1), tick_report.pending_port_count);
}

test "runspace park-on-budget preserves supervised parked slot" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    const event = try runspace.step(handle);
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    const summary = try runspace.getSlotSummary(handle);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, summary.status);
    try std.testing.expectEqual(@as(?u64, null), summary.pending_mailbox_id);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().parked_count);
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.full_target_run, image.kind);
    try std.testing.expectEqual(world.RunState.Status.parked_on_supervision, image.current_state.status);
    var receiver = world.Runspace.init(std.testing.allocator, .{});
    defer receiver.deinit();
    const installed_handle = try receiver.installRunImage(image);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try receiver.getSlotSummary(installed_handle)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try runspace.getSlotSummary(handle)).status);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .run_image = image,
        .requested_mode = .resume_parked,
    });
    var admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    defer admission.deinit(std.testing.allocator);
    try std.testing.expect(admission.report.accepted);
    var admitted_receiver = world.Runspace.init(std.testing.allocator, .{ .require_admission = true });
    defer admitted_receiver.deinit();
    const admitted_installed = try admitted_receiver.installAdmitted(admission.admitted_run.?);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try admitted_receiver.getSlotSummary(admitted_installed)).status);
    var admitted_resume = admission.admitted_run.?;
    var resume_runtime = boundary.Runtime.init(std.testing.allocator);
    defer resume_runtime.deinit();
    var resume_ctx: PortsCtx = .{};
    var resumed = try admitted_resume.@"resume"(std.testing.allocator, fixtures.Ports.Target, PortsEnv, &resume_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &resume_ctx,
    });
    defer resumed.deinit();
    var resumed_request = switch (try resumed.nextFrame()) {
        .port_request => |request| request,
        else => return error.ExpectedFrameRequest,
    };
    defer resumed_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), resumed_request.world_port_id);
    const contextual_state = world.RunState.init(.{
        .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
        .branch_id = 7,
        .status = .parked_on_supervision,
    });
    const contextual_image = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = image.target_ref,
        .import_set_fingerprint = image.import_set_fingerprint,
        .current_state = contextual_state,
    });
    const contextual_package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .run_image = contextual_image,
        .requested_mode = .resume_parked,
    });
    const contextual_admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, contextual_package, .{});
    try std.testing.expect(!contextual_admission.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.RunImageInvalid, contextual_admission.report.blockers[0]);
}

test "runspace interrupted supervision handoff accepts transcript-bearing exports" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
    });
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
        .transcript = &transcript,
    });
    _ = try runspace.step(handle);
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    try std.testing.expect(image.transcript_image != null);
    try std.testing.expectEqual(world.RunState.Status.parked_on_supervision, image.current_state.status);
    const transcript_image = image.transcript_image.?;

    const later_turn_state = world.RunState.init(.{
        .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = transcript_image.transcript_image_fingerprint,
        .turn_index = 1,
        .status = .parked_on_supervision,
    });
    const later_turn_image = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = image.target_ref,
        .import_set_fingerprint = image.import_set_fingerprint,
        .transcript_image = transcript_image,
        .current_state = later_turn_state,
        .prior_run_permit_fingerprint = image.prior_run_permit_fingerprint,
        .prior_run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
    });
    const later_turn_package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .run_image = later_turn_image,
        .requested_mode = .resume_parked,
    });
    var later_turn_admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, later_turn_package, .{});
    defer later_turn_admission.deinit(std.testing.allocator);
    try std.testing.expect(!later_turn_admission.report.accepted);
    var later_turn_receiver = world.Runspace.init(std.testing.allocator, .{});
    defer later_turn_receiver.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, later_turn_receiver.installRunImage(later_turn_image));

    const unwitnessed_later_turn_state = world.RunState.init(.{
        .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
        .turn_index = 1,
        .status = .parked_on_supervision,
    });
    const unwitnessed_later_turn_image = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = image.target_ref,
        .import_set_fingerprint = image.import_set_fingerprint,
        .current_state = unwitnessed_later_turn_state,
        .prior_run_permit_fingerprint = image.prior_run_permit_fingerprint,
        .prior_run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
    });
    const unwitnessed_later_turn_package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .run_image = unwitnessed_later_turn_image,
        .requested_mode = .resume_parked,
    });
    const unwitnessed_later_turn_admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, unwitnessed_later_turn_package, .{});
    try std.testing.expect(!unwitnessed_later_turn_admission.report.accepted);
    var unwitnessed_receiver = world.Runspace.init(std.testing.allocator, .{});
    defer unwitnessed_receiver.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, unwitnessed_receiver.installRunImage(unwitnessed_later_turn_image));

    const package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .run_image = image,
        .requested_mode = .resume_parked,
    });
    var admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    defer admission.deinit(std.testing.allocator);
    try std.testing.expect(admission.report.accepted);

    var admitted = admission.admitted_run.?;
    var resume_runtime = boundary.Runtime.init(std.testing.allocator);
    defer resume_runtime.deinit();
    var resume_ctx: PortsCtx = .{};
    var resumed = try admitted.@"resume"(std.testing.allocator, fixtures.Ports.Target, PortsEnv, &resume_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &resume_ctx,
    });
    defer resumed.deinit();
    var resumed_request = switch (try resumed.nextFrame()) {
        .port_request => |request| request,
        else => return error.ExpectedFrameRequest,
    };
    defer resumed_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), resumed_request.world_port_id);
}

test "interrupted supervision handoff replays transcript prefix before live request" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 1 }),
    });
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var run = try AgentMachineEnv.start(&runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
        .transcript = &transcript,
    });
    defer run.deinit();
    var model_request = switch (try run.nextFrame()) {
        .port_request => |request| request,
        else => return error.ExpectedFrameRequest,
    };
    defer model_request.deinit(std.testing.allocator);
    try run.dispatch();
    try std.testing.expectError(error.HandlerPending, run.nextFrame());
    try std.testing.expectEqual(@as(usize, 1), ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.tool_calls);

    var image = try run.snapshotRunImage();
    defer image.deinit(std.testing.allocator);
    try std.testing.expect(image.transcript_image != null);
    try std.testing.expectEqual(world.RunState.Status.parked_on_supervision, image.current_state.status);
    try std.testing.expect(image.current_state.turn_index != 0);
    try std.testing.expect(image.current_state.final_response_fingerprint != null);
    try std.testing.expect(image.current_state.final_value_image_fingerprint != null);

    var install_receiver = world.Runspace.init(std.testing.allocator, .{});
    defer install_receiver.deinit();
    const installed_handle = try install_receiver.installRunImage(image);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try install_receiver.getSlotSummary(installed_handle)).status);
    const missing_transcript_availability_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .transcript_image_available = false,
    });
    const missing_transcript_availability_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_6a16,
        .target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target),
        .environment_certificate_fingerprint = AgentEnv.certificate(.fresh, true).certificate_fingerprint,
        .mode = .resume_parked,
        .run_image = image,
        .run_permit = missing_transcript_availability_permit,
    });
    var missing_transcript_availability_receiver = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer missing_transcript_availability_receiver.deinit();
    try std.testing.expectError(error.SupervisionDenied, missing_transcript_availability_receiver.installAdmitted(missing_transcript_availability_admitted));
    const prefix_replay_denied_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_replay_calls = 0 }),
        .transcript_image_available = true,
    });
    const prefix_replay_denied_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_6a17,
        .target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target),
        .environment_certificate_fingerprint = AgentEnv.certificate(.fresh, true).certificate_fingerprint,
        .mode = .resume_parked,
        .run_image = image,
        .run_permit = prefix_replay_denied_permit,
    });
    var prefix_replay_denied_receiver = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer prefix_replay_denied_receiver.deinit();
    try std.testing.expectError(error.BudgetExceeded, prefix_replay_denied_receiver.installAdmitted(prefix_replay_denied_admitted));

    const forged_state = world.RunState.init(.{
        .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image.?.transcript_image_fingerprint,
        .final_response_fingerprint = image.current_state.final_response_fingerprint,
        .final_value_image_fingerprint = image.current_state.final_value_image_fingerprint,
        .turn_index = image.current_state.turn_index + 1,
        .status = .parked_on_supervision,
    });
    const forged_image = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = image.target_ref,
        .import_set_fingerprint = image.import_set_fingerprint,
        .transcript_image = image.transcript_image.?,
        .current_state = forged_state,
        .prior_run_permit_fingerprint = image.prior_run_permit_fingerprint,
        .prior_run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
    });
    var forged_receiver = world.Runspace.init(std.testing.allocator, .{});
    defer forged_receiver.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, forged_receiver.installRunImage(forged_image));
    const forged_package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target),
        .run_image = forged_image,
        .requested_mode = .resume_parked,
    });
    const forged_admission = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Agent.Target)}),
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Agent.Target, AgentEnv, forged_package, .{});
    try std.testing.expect(!forged_admission.report.accepted);

    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();
    const report = handoff.preflight(fixtures.Agent.Target, AgentEnv, .accept_fresh);
    try std.testing.expect(report.accepted);

    var receiver_runtime = boundary.Runtime.init(std.testing.allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var receiver_run = try handoff.@"resume"(fixtures.Agent.Target, AgentEnv, &receiver_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
    }, .accept_fresh);
    defer receiver_run.deinit();
    var live_request = switch (try receiver_run.nextFrame()) {
        .port_request => |request| request,
        else => return error.ExpectedFrameRequest,
    };
    defer live_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(AgentToolDecl.world_port_id, live_request.world_port_id);
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.tool_calls);
    try receiver_run.dispatch();
    try std.testing.expectEqual(@as(usize, 1), receiver_ctx.tool_calls);

    const bare_prefix_state = world.RunState.init(.{
        .target_ref_fingerprint = image.target_ref.target_ref_fingerprint,
        .status = .parked_on_supervision,
    });
    const bare_prefix_image = world.RunImage.init(.{
        .kind = image.kind,
        .target_ref = image.target_ref,
        .import_set_fingerprint = image.import_set_fingerprint,
        .current_state = bare_prefix_state,
        .prior_run_permit_fingerprint = image.prior_run_permit_fingerprint,
        .prior_run_receipt_fingerprint = image.prior_run_receipt_fingerprint,
    });
    var separate_transcript_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_6a18,
        .target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target),
        .environment_certificate_fingerprint = AgentEnv.certificate(.fresh, true).certificate_fingerprint,
        .mode = .resume_parked,
        .run_image = bare_prefix_image,
        .transcript_image = image.transcript_image.?,
    });
    var separate_runtime = boundary.Runtime.init(std.testing.allocator);
    defer separate_runtime.deinit();
    var separate_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var separate_run = try separate_transcript_admitted.@"resume"(std.testing.allocator, fixtures.Agent.Target, AgentEnv, &separate_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &separate_ctx,
    });
    defer separate_run.deinit();
    var separate_live_request = switch (try separate_run.nextFrame()) {
        .port_request => |request| request,
        else => return error.ExpectedFrameRequest,
    };
    defer separate_live_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(AgentToolDecl.world_port_id, separate_live_request.world_port_id);
    try std.testing.expectEqual(@as(usize, 0), separate_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), separate_ctx.tool_calls);
}

test "runspace pre-request supervision park event allocation failure leaves slot runnable" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
    });
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = std.math.maxInt(usize),
    });
    var runtime = boundary.Runtime.init(failing_allocator.allocator());
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(failing_allocator.allocator(), .{
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = failing_allocator.allocator(),
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    try runspace.events.ensureUnusedCapacity(failing_allocator.allocator(), 2);
    failing_allocator.fail_index = failing_allocator.alloc_index + 2;

    try std.testing.expectError(error.OutOfMemory, runspace.step(handle));
    try std.testing.expect(failing_allocator.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Runspace.RunStatus.runnable, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().parked_count);
    try std.testing.expectEqual(@as(usize, 0), runspace.report().pending_port_count);
}

test "runspace auto dispatch park-on-budget preserves pending mailbox" {
    const park_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = park_policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{
        .auto_dispatch = true,
        .require_supervision = true,
    });
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    const event = try runspace.step(handle);
    try std.testing.expectEqual(world.Runspace.EventKind.run_parked_on_supervision, event.kind);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(world.Runspace.PendingStatus.pending, (try runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_supervision, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), runspace.report().pending_port_count);
}

test "runspace enforces lifecycle supervision for direct and imported slots" {
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const branch_denied_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var direct = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer direct.deinit();
    try std.testing.expectError(error.SupervisionDenied, direct.installTarget(fixtures.Strict.Target, StrictEnv, world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    }), .{}));
    const strict_module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Strict.Target);
    try std.testing.expectError(error.SupervisionDenied, direct.installTarget(fixtures.Strict.Target, StrictEnv, world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .module_ref_fingerprint = strict_module_ref.module_ref_fingerprint,
        .policy = world.SupervisionPolicy.strict_fresh,
    }), .{}));
    try std.testing.expectError(error.SupervisionDenied, direct.installTarget(fixtures.Strict.Target, StrictEnv, world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .admission_receipt_fingerprint = 0xadd1_5001,
        .policy = world.SupervisionPolicy.strict_fresh,
    }), .{}));
    const direct_handle = try direct.installTarget(fixtures.Strict.Target, StrictEnv, branch_denied_permit, .{});
    try std.testing.expectError(error.InvalidRunspaceTransition, direct.exportRun(direct_handle));
    try std.testing.expectEqual(@as(usize, 0), direct.slots.items[0].supervisor.?.ledger.total_handoff_exports);
    const checkpoint = try direct.checkpoint(direct_handle);
    try std.testing.expectError(error.BranchDenied, direct.branch(direct_handle, checkpoint, .{}));
    try std.testing.expectEqual(@as(usize, 1), direct.report().blocker_count);
    try std.testing.expectEqual(@as(usize, 2), direct.events.items.len);
    const direct_next = try direct.installTarget(fixtures.Strict.Target, StrictEnv, branch_denied_permit, .{});
    try std.testing.expectEqual(@as(u64, 1), direct_next.local_run_id);

    const checkpoint_budget_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_checkpoints = 0 }),
    });
    var checkpoint_denied = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer checkpoint_denied.deinit();
    const checkpoint_handle = try checkpoint_denied.installTarget(fixtures.Strict.Target, StrictEnv, checkpoint_budget_permit, .{});
    try std.testing.expectError(error.BudgetExceeded, checkpoint_denied.checkpoint(checkpoint_handle));
    try std.testing.expectEqual(@as(usize, 1), checkpoint_denied.events.items.len);

    var imported_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
        .prior_run_permit_fingerprint = branch_denied_permit.permit_fingerprint,
    });
    defer imported_image.deinit(std.testing.allocator);
    var imported = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer imported.deinit();
    try std.testing.expectError(error.SupervisionDenied, imported.installRunImage(imported_image));

    const admitted_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.audit_only,
    });
    const scoped_admitted_permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.audit_only,
        .admission_receipt_fingerprint = 0xadd1_5afe,
    });
    const admitted_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
        .prior_run_permit_fingerprint = branch_denied_permit.permit_fingerprint,
    });
    const supervised_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5afe,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .mode = .continue_fresh,
        .run_image = admitted_image,
        .run_permit = admitted_permit,
    });
    var admitted = world.Runspace.init(std.testing.allocator, .{
        .require_supervision = true,
    });
    defer admitted.deinit();
    const admitted_handle = try admitted.installAdmitted(supervised_admitted);
    const admitted_checkpoint = try admitted.checkpoint(admitted_handle);
    _ = try admitted.branch(admitted_handle, admitted_checkpoint, .{});
    var admitted_export = try admitted.exportRun(admitted_handle);
    defer admitted_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(scoped_admitted_permit.permit_fingerprint, admitted_export.prior_run_permit_fingerprint.?);

    const prior_only_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Strict.Target).import_set_fingerprint,
        .current_state = world.RunState.init(.{
            .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Strict.Target).target_ref_fingerprint,
            .status = .completed,
        }),
        .prior_run_permit_fingerprint = branch_denied_permit.permit_fingerprint,
    });
    const prior_only_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_5aff,
        .target_ref = world.TargetRef.fromTarget(fixtures.Strict.Target),
        .mode = .continue_fresh,
        .run_image = prior_only_image,
    });
    var prior_only = world.Runspace.init(std.testing.allocator, .{});
    defer prior_only.deinit();
    const prior_only_handle = try prior_only.installAdmitted(prior_only_admitted);
    var prior_only_export = try prior_only.exportRun(prior_only_handle);
    defer prior_only_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(branch_denied_permit.permit_fingerprint, prior_only_export.prior_run_permit_fingerprint.?);
}

test "runspace handoff export captures parked pending request and completed transcript" {
    var parked_runtime = boundary.Runtime.init(std.testing.allocator);
    defer parked_runtime.deinit();
    var parked_ctx: PortsCtx = .{};
    var parked_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer parked_runspace.deinit();
    const parked_handle = try parked_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &parked_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &parked_ctx,
    });
    _ = try parked_runspace.tick();
    var parked_image = try parked_runspace.exportPending(0);
    defer parked_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.parked_run, parked_image.kind);
    try std.testing.expect(parked_image.pending_request_frame != null);
    try std.testing.expectEqual(world.Runspace.RunStatus.exported, (try parked_runspace.getSlotSummary(parked_handle)).status);
    try std.testing.expectEqual(world.Runspace.PendingStatus.exported, (try parked_runspace.mailbox.get(0)).status);
    try std.testing.expectEqual(@as(usize, 1), parked_runspace.report().parked_count);
    try std.testing.expectEqual(@as(usize, 0), parked_runspace.report().completed_count);

    var completed_runtime = boundary.Runtime.init(std.testing.allocator);
    defer completed_runtime.deinit();
    var completed_ctx: PortsCtx = .{};
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var completed_runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer completed_runspace.deinit();
    const completed_handle = try completed_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &completed_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &completed_ctx,
        .transcript = &transcript,
    });
    _ = try completed_runspace.tick();
    _ = try completed_runspace.tick();
    var completed_image = try completed_runspace.exportRun(completed_handle);
    defer completed_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.completed_run, completed_image.kind);
    try std.testing.expect(completed_image.transcript_image != null);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.completed, completed_image.transcript_image.?.final_status);
    try std.testing.expect(completed_image.current_state.final_response_fingerprint != null);
    try std.testing.expect(completed_image.current_state.final_value_image_fingerprint != null);
    try std.testing.expect(completed_image.current_state.turn_index > 0);

    var relay_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer relay_runspace.deinit();
    const relayed_handle = try relay_runspace.installRunImage(completed_image);
    var relayed_image = try relay_runspace.exportRun(relayed_handle);
    defer relayed_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(completed_image.import_set_fingerprint, relayed_image.import_set_fingerprint);
    try std.testing.expect(relayed_image.transcript_image != null);
    try std.testing.expectEqual(completed_image.transcript_image.?.transcript_image_fingerprint, relayed_image.transcript_image.?.transcript_image_fingerprint);
    try std.testing.expectEqual(completed_image.current_state.final_response_fingerprint, relayed_image.current_state.final_response_fingerprint);
    try std.testing.expectEqual(completed_image.current_state.final_value_image_fingerprint, relayed_image.current_state.final_value_image_fingerprint);
    try std.testing.expectEqual(completed_image.current_state.turn_index, relayed_image.current_state.turn_index);
}

test "runspace checkpoint branch and replay install are deterministic" {
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    const checkpoint = try runspace.checkpoint(handle);
    const branch_handle = try runspace.branch(handle, checkpoint, .{});
    try std.testing.expect(branch_handle.handle_fingerprint != handle.handle_fingerprint);
    try std.testing.expect(branch_handle.branch_id != null);
    try std.testing.expectEqual(world.Runspace.RunStatus.admitted, (try runspace.getSlotSummary(branch_handle)).status);
    try std.testing.expectError(error.InvalidRunspaceTransition, runspace.step(branch_handle));
    const branches = try runspace.listBranches(handle, std.testing.allocator);
    defer std.testing.allocator.free(branches);
    try std.testing.expectEqual(@as(usize, 1), branches.len);
    try std.testing.expectEqual(branch_handle.handle_fingerprint, branches[0].handle_fingerprint);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const replay_handle = try runspace.installReplay(fixtures.Ports.Target, image, null);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(replay_handle)).status);
    const replay_checkpoint = try runspace.checkpoint(replay_handle);
    try std.testing.expectEqual(image.response_count, replay_checkpoint.turn_index);
    try std.testing.expect(replay_checkpoint.turn_index > 0);
}

test "runspace branch rejects checkpoint with stale self fingerprint" {
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    const witnessed = try runspace.checkpoint(handle);
    var forged = witnessed;
    forged.event_index = runspace.events.items.len;

    try std.testing.expectError(error.HandoffCheckpointMismatch, runspace.branch(handle, forged, .{}));
}

test "runspace branch child preserves supervised branch budget" {
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_branching = true,
            .allow_checkpoints = true,
            .require_environment_certificate = true,
        }),
        .budget = world.Budget.init(.{ .max_branches = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Strict.Target, StrictEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });

    const checkpoint_value = try runspace.checkpoint(handle);
    const branch_handle = try runspace.branch(handle, checkpoint_value, .{});
    const child_checkpoint = try runspace.checkpoint(branch_handle);
    try std.testing.expectError(error.BudgetExceeded, runspace.branch(branch_handle, child_checkpoint, .{}));
    try std.testing.expectEqual(@as(usize, 1), runspace.report().blocker_count);
}

test "runspace branch depth budget rejects grandchildren" {
    const StrictEnv = world.Environment(fixtures.Strict.Target, .{
        .ports = &.{},
    });
    const permit = world.Supervision.issue(fixtures.Strict.Target, StrictEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_branching = true,
            .allow_checkpoints = true,
            .require_environment_certificate = true,
        }),
        .budget = world.Budget.init(.{ .max_branches = 2, .max_branch_depth = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Strict.Target, StrictEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .permit = permit,
    });

    const checkpoint_value = try runspace.checkpoint(handle);
    const branch_handle = try runspace.branch(handle, checkpoint_value, .{});
    const child_checkpoint = try runspace.checkpoint(branch_handle);
    try std.testing.expectError(error.BudgetExceeded, runspace.branch(branch_handle, child_checkpoint, .{}));
}

test "runspace branches list only selected parent lineage" {
    var runtime_a = boundary.Runtime.init(std.testing.allocator);
    defer runtime_a.deinit();
    var runtime_b = boundary.Runtime.init(std.testing.allocator);
    defer runtime_b.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const first = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime_a, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    const second = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime_b, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    const first_checkpoint = try runspace.checkpoint(first);
    try std.testing.expectError(error.HandoffCheckpointMismatch, runspace.branch(second, first_checkpoint, .{}));
    const first_branch = try runspace.branch(first, first_checkpoint, .{});
    const second_branch = try runspace.branch(second, try runspace.checkpoint(second), .{});

    const first_branches = try runspace.listBranches(first, std.testing.allocator);
    defer std.testing.allocator.free(first_branches);
    const second_branches = try runspace.listBranches(second, std.testing.allocator);
    defer std.testing.allocator.free(second_branches);
    try std.testing.expectEqual(@as(usize, 1), first_branches.len);
    try std.testing.expectEqual(@as(usize, 1), second_branches.len);
    try std.testing.expectEqual(first_branch.handle_fingerprint, first_branches[0].handle_fingerprint);
    try std.testing.expectEqual(second_branch.handle_fingerprint, second_branches[0].handle_fingerprint);
}

test "runspace failed branch install preserves deterministic run ids" {
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    const checkpoint = try runspace.checkpoint(handle);
    runspace.config.max_events = runspace.events.items.len;

    try std.testing.expectError(error.BudgetExceeded, runspace.branch(handle, checkpoint, .{}));
    runspace.config.max_events = null;
    const next = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    try std.testing.expectEqual(@as(u64, 1), next.local_run_id);
}

test "runspace event log owns branch summary bytes" {
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installTarget(fixtures.Strict.Target, .{}, null, .{});
    const checkpoint = try runspace.checkpoint(handle);
    var caller_summary = try std.testing.allocator.dupe(u8, "branch-owned");
    defer std.testing.allocator.free(caller_summary);

    _ = try runspace.branch(handle, checkpoint, .{ .summary = caller_summary });
    const event = runspace.events.items[runspace.events.items.len - 1];
    caller_summary[0] = 'X';

    try std.testing.expectEqualStrings("branch-owned", event.summary);
    try std.testing.expectEqual(event.event_fingerprint, world.RunspaceEvent.init(.{
        .kind = event.kind,
        .runspace_fingerprint = event.runspace_fingerprint,
        .event_index = event.event_index,
        .run_handle = event.run_handle,
        .checkpoint_fingerprint = event.checkpoint_fingerprint,
        .run_state_fingerprint = event.run_state_fingerprint,
        .admission_receipt_fingerprint = event.admission_receipt_fingerprint,
        .run_permit_fingerprint = event.run_permit_fingerprint,
        .summary = event.summary,
    }).event_fingerprint);
}

test "runspace verify run detects changed handler" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{ .response = 99 };
    var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
    defer runspace.deinit();
    const handle = try runspace.installVerifyRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ctx,
        .transcript_image = &image,
    });
    try std.testing.expectError(error.VerifyDivergence, runspace.tick());
    try std.testing.expectEqual(world.Runspace.RunStatus.failed, (try runspace.getSlotSummary(handle)).status);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "runspace export owns transcript image supplied to machine options" {
    var exported = blk: {
        var transcript = world.Transcript.init(std.testing.allocator);
        defer transcript.deinit();
        try recordPortsTranscript(&transcript);
        var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
        defer image.deinit(std.testing.allocator);
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var runspace = world.Runspace.init(std.testing.allocator, .{ .auto_dispatch = true });
        defer runspace.deinit();
        const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.replay,
            .transcript_image = &image,
        });
        _ = try runspace.tick();
        _ = try runspace.tick();
        try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
        break :blk try runspace.exportRun(handle);
    };
    defer exported.deinit(std.testing.allocator);

    try std.testing.expect(exported.transcript_image != null);
    const encoded = try exported.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expect(decoded.transcript_image != null);
    try std.testing.expectEqual(exported.transcript_image.?.transcript_image_fingerprint, decoded.transcript_image.?.transcript_image_fingerprint);
}

test "runspace stepOne uses deterministic local run order and parked runs do not step again" {
    var runtime_a = boundary.Runtime.init(std.testing.allocator);
    defer runtime_a.deinit();
    var runtime_b = boundary.Runtime.init(std.testing.allocator);
    defer runtime_b.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const first = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime_a, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    const second = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime_b, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });

    _ = try runspace.stepOne();
    try std.testing.expectEqual(@as(usize, 1), runspace.report().parked_count);
    try std.testing.expectEqual(first.handle_fingerprint, (try runspace.mailbox.get(0)).handle.handle_fingerprint);

    _ = try runspace.stepOne();
    try std.testing.expectEqual(@as(usize, 2), runspace.report().parked_count);
    try std.testing.expectEqual(second.handle_fingerprint, (try runspace.mailbox.get(1)).handle.handle_fingerprint);

    _ = try runspace.respondValue(0, @as(i32, 7));
    _ = try runspace.step(first);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(first)).status);
    try std.testing.expectEqual(world.Runspace.RunStatus.parked_on_port, (try runspace.getSlotSummary(second)).status);
}

test "runspace tick completes zero-port machine run" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();

    const handle = try runspace.installMachineRun(fixtures.Strict.Target, world.Environment(fixtures.Strict.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.strict_fresh,
    }), &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    const report = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 1), report.completed_count);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try runspace.getSlotSummary(handle)).status);
}

test "value image scalar string product sum and policy failures" {
    var scalar = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 42), .portable);
    defer scalar.deinit(std.testing.allocator);
    const scalar_value = try scalar.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 42), scalar_value);
    var literal = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, 42, .portable);
    defer literal.deinit(std.testing.allocator);
    const literal_value = try literal.decodeValue(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 42), literal_value);
    const EnumValue = enum(u8) { ok };
    var enum_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, EnumValue.ok, .portable);
    defer enum_image.deinit(std.testing.allocator);
    const enum_value = try enum_image.decodeValue(std.testing.allocator, EnumValue);
    try std.testing.expectEqual(EnumValue.ok, enum_value);
    const SignedEnumValue = enum(i8) { neg = -1 };
    var signed_enum_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, SignedEnumValue.neg, .portable);
    defer signed_enum_image.deinit(std.testing.allocator);
    const signed_enum_value = try signed_enum_image.decodeValue(std.testing.allocator, SignedEnumValue);
    try std.testing.expectEqual(SignedEnumValue.neg, signed_enum_value);
    var labeled_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as(i32, 42), world.ValuePolicy.native_compatible);
    defer labeled_image.deinit(std.testing.allocator);
    const dynamic_tampered = try labeled_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(dynamic_tampered);
    @constCast(dynamic_tampered)[19] = 1;
    try std.testing.expectError(error.VerifyValueImageMismatch, world.Frame.ValueImage.decode(std.testing.allocator, dynamic_tampered));
    const label_tampered = try labeled_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(label_tampered);
    @constCast(label_tampered)[label_tampered.len - 1] ^= 1;
    try std.testing.expectError(error.VerifyValueImageMismatch, world.Frame.ValueImage.decode(std.testing.allocator, label_tampered));

    var string = try world.Frame.ValueImage.fromValue(std.testing.allocator, 2, null, null, @as([]const u8, "hello"), .portable);
    defer string.deinit(std.testing.allocator);
    const decoded_string = try string.decodeValue(std.testing.allocator, []const u8);
    defer std.testing.allocator.free(decoded_string);
    try std.testing.expectEqualStrings("hello", decoded_string);
    const mutable_bytes = try std.testing.allocator.dupe(u8, "hello");
    defer std.testing.allocator.free(mutable_bytes);
    var mutable_string = try world.Frame.ValueImage.fromValue(std.testing.allocator, 2, null, null, mutable_bytes, .portable);
    defer mutable_string.deinit(std.testing.allocator);
    const decoded_mutable_string = try mutable_string.decodeValue(std.testing.allocator, []u8);
    defer std.testing.allocator.free(decoded_mutable_string);
    decoded_mutable_string[0] = 'H';
    try std.testing.expectEqualStrings("Hello", decoded_mutable_string);

    const Product = struct { count: i32, label: []const u8 };
    var product = try world.Frame.ValueImage.fromValue(std.testing.allocator, 3, null, null, Product{ .count = 2, .label = @as([]const u8, "ok") }, .portable);
    defer product.deinit(std.testing.allocator);
    const decoded_product = try product.decodeValue(std.testing.allocator, Product);
    defer std.testing.allocator.free(decoded_product.label);
    try std.testing.expectEqual(@as(i32, 2), decoded_product.count);
    try std.testing.expectEqualStrings("ok", decoded_product.label);

    var sum = try world.Frame.ValueImage.fromValue(std.testing.allocator, 4, null, null, fixtures.Agent.Action{ .tool = @as([]const u8, "read") }, .portable);
    defer sum.deinit(std.testing.allocator);
    const decoded_sum = try sum.decodeValue(std.testing.allocator, fixtures.Agent.Action);
    switch (decoded_sum) {
        .tool => |tool_name| {
            defer std.testing.allocator.free(tool_name);
            try std.testing.expectEqualStrings("read", tool_name);
        },
        else => return error.ExpectedToolAction,
    }
    const Untagged = union { text: []const u8 };
    const forged_untagged = world.Frame.ValueImage{
        .value_image_fingerprint = 0,
        .bytes = &[_]u8{
            0, 0, 0, 0, // field index 0
            3,   0,   0,   0, 0, 0, 0, 0, // byte-slice length
            'b', 'a', 'd',
        },
        .dynamic_size = true,
    };
    try std.testing.expectError(error.UnsupportedValueImage, forged_untagged.decodeValue(std.testing.allocator, Untagged));
    var string_list = try world.Frame.ValueImage.fromValue(std.testing.allocator, 5, null, null, @as([]const []const u8, &.{"alpha"}), .portable);
    defer string_list.deinit(std.testing.allocator);
    std.mem.writeInt(u64, @constCast(string_list.bytes[0..8]), std.math.maxInt(u64), .little);
    try std.testing.expectError(error.InvalidFrameEncoding, string_list.decodeValue(std.testing.allocator, []const []const u8));

    var native_only: i32 = 1;
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, &native_only, .portable));
    try std.testing.expectError(error.UnsupportedValueImage, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, @as([]const u8, "too-big"), .{ .max_value_image_bytes = 1 }));
    const over_decode_cap = try std.testing.allocator.alloc(u8, world.world_max_decoded_byte_field_len + 1);
    defer std.testing.allocator.free(over_decode_cap);
    @memset(over_decode_cap, 0);
    try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.ValueImage.fromValue(std.testing.allocator, null, null, null, over_decode_cap, .{}));
    var stored_over_decode_cap = try world.StoredValue.init(std.testing.allocator, over_decode_cap);
    defer stored_over_decode_cap.deinit(std.testing.allocator);
    try std.testing.expect(stored_over_decode_cap.portable_image == null);
    try std.testing.expectError(error.InvalidFrameEncoding, stored_over_decode_cap.valueImage(std.testing.allocator, null, null, null, .{}));
    var stored_string = try world.StoredValue.init(std.testing.allocator, @as([]const u8, "lazy"));
    defer stored_string.deinit(std.testing.allocator);
    try std.testing.expect(stored_string.portable_image == null);
}

test "transcript image encode decode round trip stable and image replay works without handler context" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);

    {
        var mixed_surface = world.Transcript.init(std.testing.allocator);
        defer mixed_surface.deinit();
        try recordPortsTranscript(&mixed_surface);
        try mixed_surface.append(.{
            .kind = .checkpoint_recorded,
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint + 1,
            .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        });
        try std.testing.expectError(error.SurfaceMismatch, mixed_surface.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    }
    {
        var mixed_target = world.Transcript.init(std.testing.allocator);
        defer mixed_target.deinit();
        try recordPortsTranscript(&mixed_target);
        try mixed_target.append(.{
            .kind = .checkpoint_recorded,
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
            .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint + 1,
        });
        try std.testing.expectError(error.TargetCertificateMismatch, mixed_target.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    }

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var stale_replay_image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer stale_replay_image.deinit(std.testing.allocator);
    for (stale_replay_image.events) |*event| {
        if (event.response_frame) |*frame| {
            frame.flags = 1;
            break;
        }
    }
    var stale_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer stale_replay_runtime.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, PortsMachine.run(&stale_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &stale_replay_image,
    }));
    const image_request = for (image.events) |event| {
        if (event.request_frame) |request| break request;
    } else return error.ExpectedFrameRequest;
    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint, image_request.world_surface_replay_scope_fingerprint.?);
    try std.testing.expectEqual(@as(?u32, 0), image_request.payload_value_table_id);
    try std.testing.expectEqual(@as(?u32, 1), image_request.expected_response_value_table_id);
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.TranscriptImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(image.transcript_image_fingerprint, decoded.transcript_image_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.response_count);
    var forged_event_scope_image = decoded;
    forged_event_scope_image.events[0].world_surface_fingerprint +%= 1;
    const forged_event_scope_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .transcript_image = forged_event_scope_image,
        .requested_mode = .replay_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, forged_event_scope_package.validate(.{}));
    forged_event_scope_image.events[0].world_surface_fingerprint -%= 1;
    var unsupported_format_image = decoded;
    unsupported_format_image.format_version = world.world_transcript_image_format_version + 1;
    const unsupported_transcript_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target),
        .transcript_image = unsupported_format_image,
        .requested_mode = .replay_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, unsupported_transcript_package.validate(.{}));
    var admission_transcript = world.Transcript.init(std.testing.allocator);
    defer admission_transcript.deinit();
    try admission_transcript.append(.{
        .kind = .admission_accepted,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .admission_request_fingerprint = 0x456,
        .admission_report_fingerprint = 0x789,
        .admission_receipt_fingerprint = 0xabc,
        .module_ref_fingerprint = 0xdef,
        .target_match_fingerprint = 0x123,
    });
    var admission_image = try admission_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer admission_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?u64, 0x456), admission_image.events[0].admission_request_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x789), admission_image.events[0].admission_report_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xabc), admission_image.events[0].admission_receipt_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xdef), admission_image.events[0].module_ref_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x123), admission_image.events[0].target_match_fingerprint);
    const admission_encoded = try admission_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(admission_encoded);
    var decoded_admission_image = try world.TranscriptImage.decode(std.testing.allocator, admission_encoded);
    defer decoded_admission_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?u64, 0x456), decoded_admission_image.events[0].admission_request_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x789), decoded_admission_image.events[0].admission_report_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xabc), decoded_admission_image.events[0].admission_receipt_fingerprint);
    var restored_admission_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded_admission_image);
    defer restored_admission_transcript.deinit();
    try std.testing.expectEqual(@as(?u64, 0x456), restored_admission_transcript.events.items[0].admission_request_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0x789), restored_admission_transcript.events.items[0].admission_report_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xdef), restored_admission_transcript.events.items[0].module_ref_fingerprint);
    var malformed_admission_transcript = world.Transcript.init(std.testing.allocator);
    defer malformed_admission_transcript.deinit();
    try malformed_admission_transcript.append(.{
        .kind = .admission_accepted,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .admission_request_fingerprint = 0x456,
        .admission_report_fingerprint = 0x789,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, malformed_admission_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));

    var v2_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 1);
    var v2_events_owned = true;
    errdefer if (v2_events_owned) std.testing.allocator.free(v2_events);
    v2_events[0] = .{
        .event_fingerprint = 0,
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .source_run = true,
    };
    v2_events[0].event_fingerprint = testTranscriptEventImageV2Fingerprint(v2_events[0]);
    var v2_image = world.TranscriptImage{
        .format_version = 2,
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .events = v2_events,
        .final_status = .running,
    };
    v2_events_owned = false;
    v2_image.transcript_image_fingerprint = testTranscriptImageFingerprint(v2_image);
    const v2_encoded = try v2_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(v2_encoded);
    defer v2_image.deinit(std.testing.allocator);
    var decoded_v2_image = try world.TranscriptImage.decode(std.testing.allocator, v2_encoded);
    defer decoded_v2_image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 2), decoded_v2_image.format_version);
    try std.testing.expectEqual(@as(?u64, null), decoded_v2_image.events[0].admission_receipt_fingerprint);
    var forged_v2_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 1);
    var forged_v2_events_owned = true;
    errdefer if (forged_v2_events_owned) std.testing.allocator.free(forged_v2_events);
    forged_v2_events[0] = .{
        .event_fingerprint = 0,
        .kind = .admission_requested,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    };
    forged_v2_events[0].event_fingerprint = testTranscriptEventImageV2Fingerprint(forged_v2_events[0]);
    var forged_v2_admission_image = world.TranscriptImage{
        .format_version = 2,
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .events = forged_v2_events,
        .final_status = .running,
    };
    forged_v2_events_owned = false;
    forged_v2_admission_image.transcript_image_fingerprint = testTranscriptImageFingerprint(forged_v2_admission_image);
    const forged_v2_admission_encoded = try forged_v2_admission_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_v2_admission_encoded);
    defer forged_v2_admission_image.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, forged_v2_admission_encoded));
    var forged_v3_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 1);
    var forged_v3_events_owned = true;
    errdefer if (forged_v3_events_owned) std.testing.allocator.free(forged_v3_events);
    forged_v3_events[0] = .{
        .event_fingerprint = 0,
        .kind = .admission_accepted,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .admission_request_fingerprint = 0x456,
        .admission_report_fingerprint = 0x789,
    };
    forged_v3_events[0].event_fingerprint = testTranscriptEventImageFingerprint(forged_v3_events[0]);
    var forged_v3_admission_image = world.TranscriptImage{
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .events = forged_v3_events,
        .final_status = .running,
    };
    forged_v3_events_owned = false;
    forged_v3_admission_image.transcript_image_fingerprint = testTranscriptImageFingerprint(forged_v3_admission_image);
    const forged_v3_admission_encoded = try forged_v3_admission_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_v3_admission_encoded);
    defer forged_v3_admission_image.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, forged_v3_admission_encoded));
    var forged_status_image = decoded;
    forged_status_image.final_status = .failed;
    forged_status_image.transcript_image_fingerprint = testTranscriptImageFingerprint(forged_status_image);
    const forged_status_encoded = try forged_status_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_status_encoded);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, forged_status_encoded));
    const decoded_response = for (decoded.events) |event| {
        if (event.response_frame) |response| break response;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(@as(?u32, 1), decoded_response.response_value_table_id);
    const MissingDescriptorMachine = world.Machine(fixtures.Ports.Target, .{ .ports = .{} });
    var missing_descriptor_runtime = boundary.Runtime.init(std.testing.allocator);
    defer missing_descriptor_runtime.deinit();
    try std.testing.expectError(error.MissingHandler, MissingDescriptorMachine.run(&missing_descriptor_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    }));

    var forged_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 1);
    var forged_events_owned = true;
    errdefer if (forged_events_owned) std.testing.allocator.free(forged_events);
    var forged_response = try decoded_response.clone(std.testing.allocator);
    var forged_response_owned = true;
    errdefer if (forged_response_owned) forged_response.deinit(std.testing.allocator);
    forged_events[0] = .{
        .event_fingerprint = 0,
        .kind = .run_started,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .source_run = true,
        .response_frame = forged_response,
    };
    forged_response_owned = false;
    var forged_image = world.TranscriptImage{
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .events = forged_events,
        .final_status = .completed,
        .response_count = 1,
    };
    forged_events_owned = false;
    defer forged_image.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ReplayMissing,
        forged_image.nextResponse(image_request.replay_key_seed, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
    );

    var skipped_events = try std.testing.allocator.alloc(world.TranscriptImage.EventImage, 2);
    errdefer std.testing.allocator.free(skipped_events);
    var skipped_bad_response = try decoded_response.clone(std.testing.allocator);
    var skipped_bad_owned = true;
    errdefer if (skipped_bad_owned) skipped_bad_response.deinit(std.testing.allocator);
    skipped_bad_response.status = .failed;
    var skipped_good_response = try decoded_response.clone(std.testing.allocator);
    var skipped_good_owned = true;
    errdefer if (skipped_good_owned) skipped_good_response.deinit(std.testing.allocator);
    skipped_events[0] = .{
        .event_fingerprint = 0,
        .kind = .frame_responded,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .world_port_id = skipped_bad_response.world_port_id,
        .request_fingerprint = skipped_bad_response.request_fingerprint,
        .response_fingerprint = skipped_bad_response.response_fingerprint,
        .response_kind = skipped_bad_response.response_kind,
        .replay_key = skipped_bad_response.replay_key,
        .response_frame = skipped_bad_response,
    };
    skipped_bad_owned = false;
    skipped_events[1] = skipped_events[0];
    skipped_events[1].response_frame = skipped_good_response;
    skipped_good_owned = false;
    var skipped_image = world.TranscriptImage{
        .transcript_image_fingerprint = 0,
        .world_surface_fingerprint = decoded.world_surface_fingerprint,
        .target_certificate_fingerprint = decoded.target_certificate_fingerprint,
        .events = skipped_events,
        .final_status = .completed,
        .response_count = 2,
    };
    defer skipped_image.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.ReplayMissing,
        skipped_image.nextResponse(image_request.replay_key_seed, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume"),
    );

    var forged_header: [49]u8 = undefined;
    std.mem.writeInt(u32, forged_header[0..4], world.world_transcript_image_format_version, .little);
    std.mem.writeInt(u32, forged_header[4..8], world.world_transcript_image_fingerprint_version, .little);
    std.mem.writeInt(u64, forged_header[8..16], 0, .little);
    std.mem.writeInt(u64, forged_header[16..24], fixtures.Ports.Target.WorldSurface.surface_fingerprint, .little);
    std.mem.writeInt(u64, forged_header[24..32], fixtures.Ports.Target.Certificate.certificate_fingerprint, .little);
    forged_header[32] = @intFromEnum(world.TranscriptImage.FinalStatus.completed);
    std.mem.writeInt(u64, forged_header[33..41], 0, .little);
    std.mem.writeInt(u64, forged_header[41..49], 1, .little);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, &forged_header));

    var capped_event_header = [_]u8{0} ** (49 + 64);
    std.mem.writeInt(u32, capped_event_header[0..4], world.world_transcript_image_format_version, .little);
    std.mem.writeInt(u32, capped_event_header[4..8], world.world_transcript_image_fingerprint_version, .little);
    capped_event_header[32] = @intFromEnum(world.TranscriptImage.FinalStatus.running);
    std.mem.writeInt(u64, capped_event_header[41..49], 64, .little);
    try std.testing.expectError(error.InvalidFrameEncoding, world.TranscriptImage.decode(std.testing.allocator, &capped_event_header));

    var rebuilt_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer rebuilt_transcript.deinit();
    var rebuilt_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rebuilt_runtime.deinit();
    var rebuilt_replayed = try PortsMachine.run(&rebuilt_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &rebuilt_transcript,
    });
    defer rebuilt_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), rebuilt_replayed.value);

    var wrong_table_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer wrong_table_transcript.deinit();
    for (wrong_table_transcript.events.items) |*event| {
        if (event.response_frame) |*frame| {
            frame.response_value_table_id = null;
            break;
        }
    }
    var wrong_table_runtime = boundary.Runtime.init(std.testing.allocator);
    defer wrong_table_runtime.deinit();
    try std.testing.expectError(error.FrameValueTableMismatch, PortsMachine.run(&wrong_table_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &wrong_table_transcript,
    }));

    var failed_response_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer failed_response_transcript.deinit();
    for (failed_response_transcript.events.items) |*event| {
        if (event.response_frame) |response| {
            var failed_response_image = if (response.response_image) |response_image|
                try response_image.clone(std.testing.allocator)
            else
                null;
            errdefer if (failed_response_image) |*response_image| response_image.deinit(std.testing.allocator);
            const failed_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = response.world_surface_fingerprint,
                .target_certificate_fingerprint = response.target_certificate_fingerprint,
                .world_port_id = response.world_port_id,
                .request_fingerprint = response.request_fingerprint,
                .response_kind = response.response_kind,
                .response_value_table_id = response.response_value_table_id,
                .response_fingerprint = response.response_fingerprint,
                .response_image = failed_response_image,
                .replay_key = response.replay_key,
                .status = .failed,
            });
            failed_response_image = null;
            event.response_frame.?.deinit(std.testing.allocator);
            event.response_frame = failed_response;
            event.status = .failed;
            break;
        }
    } else return error.ExpectedResponseFrame;
    var failed_response_runtime = boundary.Runtime.init(std.testing.allocator);
    defer failed_response_runtime.deinit();
    try std.testing.expectError(error.ReplayMissing, PortsMachine.run(&failed_response_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &failed_response_transcript,
    }));

    var rebuilt_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rebuilt_verify_runtime.deinit();
    var rebuilt_verify_ctx: PortsCtx = .{};
    var rebuilt_verified = try PortsMachine.run(&rebuilt_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &rebuilt_verify_ctx,
        .transcript = &rebuilt_transcript,
    });
    defer rebuilt_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), rebuilt_verified.value);
    try std.testing.expectEqual(@as(usize, 1), rebuilt_verify_ctx.calls);

    var both_authorities_transcript = try world.Transcript.fromImage(std.testing.allocator, decoded);
    defer both_authorities_transcript.deinit();
    var both_authorities_runtime = boundary.Runtime.init(std.testing.allocator);
    defer both_authorities_runtime.deinit();
    var both_authorities_replayed = try PortsMachine.run(&both_authorities_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &both_authorities_transcript,
        .transcript_image = &decoded,
    });
    defer both_authorities_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), both_authorities_replayed.value);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &decoded,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);
}

test "step frame nextFrame resumeFrame and verify adapter image path work" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const response_fingerprint = (try firstRespondedEvent(&transcript)).response_fingerprint.?;

    var frame_transcript = world.Transcript.init(std.testing.allocator);
    defer frame_transcript.deinit();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var run = try PortsMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &frame_transcript,
    });
    defer run.deinit();
    var expected_response_frame_fingerprint: u64 = 0;
    const step = try run.nextFrame();
    switch (step) {
        .port_request => |frame| {
            var request = frame;
            defer request.deinit(std.testing.allocator);
            try std.testing.expect(request.payload_image != null);
            const payload = try request.payload_image.?.decodeValue(std.testing.allocator, []const u8);
            defer std.testing.allocator.free(payload);
            try std.testing.expectEqualStrings("deploy-prod", payload);
            const repeated_step = try run.nextFrame();
            switch (repeated_step) {
                .port_request => |again| {
                    var repeated_request = again;
                    defer repeated_request.deinit(std.testing.allocator);
                    try std.testing.expectEqual(request.frame_fingerprint, repeated_request.frame_fingerprint);
                },
                else => return error.ExpectedFrameRequest,
            }
            try std.testing.expectEqual(@as(usize, 1), frame_transcript.summary().frame_requested);
            const encoded_request = try request.encode(std.testing.allocator);
            defer std.testing.allocator.free(encoded_request);
            var tampered_request = try std.testing.allocator.dupe(u8, encoded_request);
            defer std.testing.allocator.free(tampered_request);
            const payload_value_fingerprint_offset = 4 + 4 + 8 + 8 + 1 + 8 + 8 + 4 + 8 + 8 + 8 + 8 + 1 + 4 + 1 + 4 + 1;
            tampered_request[payload_value_fingerprint_offset] ^= 1;
            try std.testing.expectError(error.InvalidFrameEncoding, world.Frame.Request.decode(std.testing.allocator, tampered_request));
            const pending_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint + 1,
                .status = .pending,
                .response_fingerprint = 0,
                .replay_key = 0,
            });
            try std.testing.expectError(error.FrameRequestFingerprintMismatch, run.resumeFrame(pending_response));
            var wrong_value_table_response = try world.Frame.Response.fromValue(std.testing.allocator, request, null, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_value_table_response.deinit(std.testing.allocator);
            try std.testing.expectError(error.FrameValueTableMismatch, run.resumeFrame(wrong_value_table_response));
            const wrong_nested_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, response_fingerprint, null, @as(i32, 7), .portable);
            var wrong_nested_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_value_table_id = 1,
                .response_fingerprint = response_fingerprint,
                .response_image = wrong_nested_image,
                .replay_key = request.replay_key_seed.withResponse(response_fingerprint).fingerprint(),
            });
            defer wrong_nested_response.deinit(std.testing.allocator);
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_nested_response));
            var wrong_response_version = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_response_version.deinit(std.testing.allocator);
            wrong_response_version.format_version += 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_response_version));
            var wrong_response_image_version = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer wrong_response_image_version.deinit(std.testing.allocator);
            wrong_response_image_version.response_image.?.format_version += 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(wrong_response_image_version));
            var stale_image_response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer stale_image_response.deinit(std.testing.allocator);
            @constCast(stale_image_response.response_image.?.bytes)[0] ^= 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(stale_image_response));
            var stale_frame_response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer stale_frame_response.deinit(std.testing.allocator);
            stale_frame_response.flags = 1;
            try std.testing.expectError(error.InvalidFrameEncoding, run.resumeFrame(stale_frame_response));
            var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
            defer response.deinit(std.testing.allocator);
            expected_response_frame_fingerprint = response.frame_fingerprint;
            try run.resumeFrame(response);
        },
        else => return error.ExpectedFrameRequest,
    }
    switch (try run.nextFrame()) {
        .done => |value| try std.testing.expectEqual(@as(i32, 7), value),
        else => return error.ExpectedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), run.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 0), run.audit.replayed_response_count);
    const frame_summary = frame_transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), frame_summary.frame_requested);
    try std.testing.expectEqual(@as(usize, 1), frame_summary.frame_responded);

    var frame_image = try frame_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer frame_image.deinit(std.testing.allocator);
    const image_response = for (frame_image.events) |event| {
        if (event.response_frame) |response| break response;
    } else return error.ExpectedResponseFrame;
    const image_response_event = for (frame_image.events) |event| {
        if (event.kind == .frame_responded) break event;
    } else return error.ExpectedResponseFrame;
    try std.testing.expectEqual(world.ResponseStatus.responded, image_response_event.status.?);
    try std.testing.expectEqual(expected_response_frame_fingerprint, image_response.frame_fingerprint);
    var replay_frame_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_frame_runtime.deinit();
    var replay_frame_run = try PortsMachine.start(&replay_frame_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &frame_image,
    });
    defer replay_frame_run.deinit();
    switch (try replay_frame_run.nextFrame()) {
        .port_request => |frame| {
            var request = frame;
            defer request.deinit(std.testing.allocator);
            const forged_replay_response = world.Frame.Response.init(.{
                .world_surface_fingerprint = request.world_surface_fingerprint,
                .target_certificate_fingerprint = request.target_certificate_fingerprint,
                .world_port_id = request.world_port_id,
                .request_fingerprint = request.request_fingerprint,
                .response_fingerprint = 0,
                .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
            });
            try std.testing.expectError(error.InvalidMode, replay_frame_run.resumeFrame(forged_replay_response));
        },
        else => return error.ExpectedFrameRequest,
    }
    var frame_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_replay_runtime.deinit();
    var frame_replayed = try PortsMachine.run(&frame_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &frame_image,
    });
    defer frame_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_replayed.value);

    var stale_verify_image = try frame_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer stale_verify_image.deinit(std.testing.allocator);
    for (stale_verify_image.events) |*event| {
        if (event.response_frame) |*response_frame| {
            response_frame.flags = 1;
            break;
        }
    }
    var stale_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer stale_verify_runtime.deinit();
    var stale_verify_ctx: PortsCtx = .{};
    try std.testing.expectError(error.InvalidFrameEncoding, PortsMachine.run(&stale_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &stale_verify_ctx,
        .transcript_image = &stale_verify_image,
    }));

    var frame_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_verify_runtime.deinit();
    var frame_verify_ctx: PortsCtx = .{};
    var frame_verified = try PortsMachine.run(&frame_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &frame_verify_ctx,
        .transcript_image = &frame_image,
    });
    defer frame_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_verified.value);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_ctx.calls);

    var native_frame_image = try frame_transcript.toImage(std.testing.allocator, .{});
    defer native_frame_image.deinit(std.testing.allocator);
    var native_frame_verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer native_frame_verify_runtime.deinit();
    var native_frame_verify_ctx: PortsCtx = .{};
    var native_frame_verified = try PortsMachine.run(&native_frame_verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &native_frame_verify_ctx,
        .transcript_image = &native_frame_image,
    });
    defer native_frame_verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), native_frame_verified.value);
    try std.testing.expectEqual(@as(usize, 1), native_frame_verify_ctx.calls);

    var frame_verify_transcript = world.Transcript.init(std.testing.allocator);
    defer frame_verify_transcript.deinit();
    var frame_verify_record_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_verify_record_runtime.deinit();
    var frame_verify_record_ctx: PortsCtx = .{};
    var frame_verify_recorded = try PortsMachine.run(&frame_verify_record_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &frame_verify_record_ctx,
        .transcript_image = &frame_image,
        .transcript = &frame_verify_transcript,
    });
    defer frame_verify_recorded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), frame_verify_recorded.value);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_transcript.summary().frame_verified);
    var frame_verify_record_image = try frame_verify_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer frame_verify_record_image.deinit(std.testing.allocator);
    const frame_verify_audit = world.AuditImage.fromReport(frame_verify_recorded.audit, frame_verify_record_image);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.response_frame_count);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.replayed_frame_count);
    try std.testing.expectEqual(@as(usize, 1), frame_verify_audit.verified_frame_count);
    try std.testing.expectEqual(@as(usize, 0), frame_verify_audit.failed_frame_count);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    var verify_runtime = boundary.Runtime.init(std.testing.allocator);
    defer verify_runtime.deinit();
    var verify_ctx: PortsCtx = .{};
    var verified = try PortsMachine.run(&verify_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &verify_ctx,
        .transcript_image = &image,
    });
    defer verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), verified.value);
    try std.testing.expectEqual(@as(usize, 1), verify_ctx.calls);
}

test "rejected and failed frame responses record terminal transcript state" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var run = try PortsMachine.start(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer run.deinit();

        var request = switch (try run.nextFrame()) {
            .port_request => |frame| frame,
            else => return error.ExpectedFrameRequest,
        };
        defer request.deinit(std.testing.allocator);
        const rejected = world.Frame.Response.init(.{
            .world_surface_fingerprint = request.world_surface_fingerprint,
            .target_certificate_fingerprint = request.target_certificate_fingerprint,
            .world_port_id = request.world_port_id,
            .request_fingerprint = request.request_fingerprint,
            .response_fingerprint = 0,
            .replay_key = request.replay_key_seed.withResponse(0).fingerprint(),
            .status = .rejected,
        });

        try std.testing.expectError(error.HandlerRejected, run.resumeFrame(rejected));
        try std.testing.expectEqual(@as(usize, 1), run.audit.rejected_count);
        switch (try run.nextFrame()) {
            .failed => {},
            else => return error.ExpectedFailed,
        }
    }
    {
        var runtime = boundary.Runtime.init(std.testing.allocator);
        defer runtime.deinit();
        var run = try PortsMachine.start(&runtime, .{}, .{
            .allocator = std.testing.allocator,
            .mode = world.Mode.fresh,
            .transcript = &transcript,
        });
        defer run.deinit();

        var request = switch (try run.nextFrame()) {
            .port_request => |frame| frame,
            else => return error.ExpectedFrameRequest,
        };
        defer request.deinit(std.testing.allocator);
        const failed = world.Frame.Response.init(.{
            .world_surface_fingerprint = request.world_surface_fingerprint,
            .target_certificate_fingerprint = request.target_certificate_fingerprint,
            .world_port_id = request.world_port_id,
            .request_fingerprint = request.request_fingerprint,
            .response_fingerprint = 1,
            .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
            .status = .failed,
        });

        try std.testing.expectError(error.HandlerFailed, run.resumeFrame(failed));
        try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);
        switch (try run.nextFrame()) {
            .failed => {},
            else => return error.ExpectedFailed,
        }
    }
    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.frame_rejected);
    try std.testing.expectEqual(@as(usize, 1), summary.frame_failed);
    try std.testing.expectEqual(@as(usize, 2), summary.run_failed);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), image.response_count);
    const audit = world.AuditImage.fromReport(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .mode = world.Mode.fresh,
        .final_status = .failed,
        .failed_count = 2,
    }, image);
    try std.testing.expectEqual(@as(usize, 2), audit.request_frame_count);
    try std.testing.expectEqual(@as(usize, 2), audit.response_frame_count);
    try std.testing.expectEqual(@as(usize, 1), audit.failed_frame_count);
    try std.testing.expectEqual(@as(usize, 0), audit.missing_portable_value_image_count);
}

test "resume frame terminally fails when session rejects accepted response" {
    var seed_transcript = world.Transcript.init(std.testing.allocator);
    defer seed_transcript.deinit();
    try recordPortsTranscript(&seed_transcript);
    const response_fingerprint = (try firstRespondedEvent(&seed_transcript)).response_fingerprint.?;

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var run = try ResumeFailureMachine.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .transcript = &transcript,
    });
    defer run.deinit();

    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer request.deinit(std.testing.allocator);

    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, response_fingerprint, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);

    try std.testing.expectError(error.TestResumeFailed, run.resumeFrame(response));
    try std.testing.expectEqual(@as(usize, 1), run.audit.failed_count);
    switch (try run.nextFrame()) {
        .failed => {},
        else => return error.ExpectedFailed,
    }

    const summary = transcript.summary();
    try std.testing.expectEqual(@as(usize, 1), summary.frame_responded);
    try std.testing.expectEqual(@as(usize, 1), summary.frame_failed);
    try std.testing.expectEqual(@as(usize, 1), summary.run_failed);
    const failed_event = for (transcript.events.items) |event| {
        if (event.kind == .frame_failed) break event;
    } else return error.ExpectedFrameFailure;
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_event.status.?);
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_event.response_frame.?.status);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const failed_image_event = for (image.events) |event| {
        if (event.kind == .frame_failed) break event;
    } else return error.ExpectedFrameFailure;
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_image_event.status.?);
    try std.testing.expectEqual(world.ResponseStatus.failed, failed_image_event.response_frame.?.status);
}

test "portable transcript image rejects responded frames without value images" {
    const request = testRequestFrame();
    const response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 1,
        .replay_key = request.replay_key_seed.withResponse(1).fingerprint(),
        .status = .responded,
    });
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .response_frame = response,
    });
    try std.testing.expectError(error.MissingValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    try std.testing.expectError(error.NativeOnlyValue, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .allow_native_only_values = false } }));
}

test "transcript image applies value policy to stored response frames" {
    const request = testRequestFrame();
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), world.ValuePolicy.native_compatible);
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(response.response_image.?.diagnostic_type_label != null);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .response_frame = response,
    });
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "transcript image applies value policy to stored request frames" {
    var payload_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 0, null, null, @as([]const u8, "deploy-prod"), world.ValuePolicy.native_compatible);
    var request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 3,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = payload_image,
    });
    payload_image = undefined;
    defer request.deinit(std.testing.allocator);
    try std.testing.expect(request.payload_image.?.diagnostic_type_label != null);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_frame = request,
    });
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "native compatible transcript image omits unsupported response value images" {
    const request = testRequestFrame();
    var stored = try world.StoredValue.init(std.testing.allocator, @as(f16, 1.5));
    defer stored.deinit(std.testing.allocator);
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .source_run = true,
    });
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0xdec1_5100,
        .response_kind = .@"resume",
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .value = stored,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .status = .responded,
        .source_run = true,
    });
    var image = try transcript.toImage(std.testing.allocator, .{});
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), image.response_count);
    const response_frame = image.events[1].response_frame orelse return error.ExpectedResponseFrame;
    try std.testing.expect(response_frame.response_image == null);
    const NativeImageReplayEnv = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNativeBinding},
        .policy = world.EnvironmentPolicy.init(.{ .require_frame_images_for_replay = false }),
    });
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();
    const replay_report = handoff.preflight(fixtures.Ports.Target, NativeImageReplayEnv, .accept_replay);
    try std.testing.expect(!replay_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.NativeOnlyValueRejected, replay_report.blockers[0]);
    const audit = world.AuditImage.fromReport(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .mode = world.Mode.fresh,
        .final_status = .completed,
        .fresh_response_count = 1,
    }, image);
    try std.testing.expectEqual(@as(usize, 0), audit.missing_portable_value_image_count);
    try std.testing.expectEqual(@as(usize, 1), audit.native_only_value_count);
}

test "transcript image enforces byte caps on stored response values" {
    const request = testRequestFrame();
    var stored = try world.StoredValue.init(std.testing.allocator, @as([]const u8, "too-big"));
    defer stored.deinit(std.testing.allocator);
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .response_fingerprint = 0xdec1_5100,
        .response_kind = .@"resume",
        .replay_key = request.replay_key_seed.withResponse(0xdec1_5100).fingerprint(),
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .status = .responded,
        .value = stored,
    });
    try std.testing.expectError(error.UnsupportedValueImage, transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy{ .max_value_image_bytes = 1 } }));
}

test "transcript image final status resets on later run start" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Strict.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Strict.Target.Certificate.certificate_fingerprint,
    });

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.running, image.final_status);

    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.TranscriptImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.TranscriptImage.FinalStatus.running, decoded.final_status);
}

test "timeline event checkpoint branch and audit image fingerprints are stable" {
    const request = testRequestFrame();
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0xdec1_5100, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);

    const event = world.Timeline.Event.init(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .response_frame_fingerprint = response.frame_fingerprint,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .status = .responded,
    });
    const same_event = world.Timeline.Event.init(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .request_frame_fingerprint = request.frame_fingerprint,
        .response_frame_fingerprint = response.frame_fingerprint,
        .replay_key = response.replay_key,
        .turn_index = request.turn_index,
        .status = .responded,
    });
    try std.testing.expectEqual(event.event_fingerprint, same_event.event_fingerprint);

    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.request_fingerprint,
        .last_response_fingerprint = response.response_fingerprint,
        .transcript_prefix_fingerprint = event.event_fingerprint,
        .branch_id = 10,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 11,
        .parent_branch_id = 10,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "alternate approval",
        .start_event_index = 1,
        .final_event_index = 3,
        .final_status = .completed,
        .event_count = 2,
        .response_count = 1,
    };
    try std.testing.expect(branch.fingerprint() != checkpoint.checkpoint_fingerprint);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const audit = world.AuditReport{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .mode = .fresh,
        .final_status = .completed,
        .port_request_count = 1,
        .fresh_response_count = 1,
    };
    const audit_image = world.AuditImage.fromReport(audit, image);
    try std.testing.expectEqual(image.transcript_image_fingerprint, audit_image.transcript_image_fingerprint.?);
    try std.testing.expectEqual(@as(usize, 1), audit_image.request_frame_count);
    try std.testing.expect(audit_image.audit_fingerprint != 0);
}

test "world timeline port frame byte adapter native adapter replay adapter agent timeline agent branch audit counts" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    try std.testing.expect(image.transcript_image_fingerprint != 0);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replayed = try PortsMachine.run(&replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);

    const request = testRequestFrame();
    const request_bytes = try request.encode(std.testing.allocator);
    defer std.testing.allocator.free(request_bytes);
    var decoded_request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer decoded_request.deinit(std.testing.allocator);
    var response = try world.Frame.Response.fromPortableValue(std.testing.allocator, decoded_request, 1, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(response.responseFingerprintDeferred());
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);
    var decoded_response = try world.Frame.Response.decode(std.testing.allocator, response_bytes);
    defer decoded_response.deinit(std.testing.allocator);
    try std.testing.expectEqual(response.frame_fingerprint, decoded_response.frame_fingerprint);

    var deferred_transcript = world.Transcript.init(std.testing.allocator);
    defer deferred_transcript.deinit();
    try deferred_transcript.append(.{
        .kind = .frame_responded,
        .world_surface_fingerprint = response.world_surface_fingerprint,
        .target_certificate_fingerprint = response.target_certificate_fingerprint,
        .world_port_id = response.world_port_id,
        .request_fingerprint = response.request_fingerprint,
        .response_fingerprint = response.response_fingerprint,
        .response_kind = response.response_kind,
        .replay_key = response.replay_key,
        .status = response.status,
        .response_frame = response,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, deferred_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable }));

    var frame_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_runtime.deinit();
    var frame_run = try PortsMachine.start(&frame_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
    });
    defer frame_run.deinit();
    var live_request = switch (try frame_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer live_request.deinit(std.testing.allocator);
    var live_response = try world.Frame.Response.fromPortableValue(std.testing.allocator, live_request, 1, .@"resume", @as(i32, 7), .portable);
    defer live_response.deinit(std.testing.allocator);
    try frame_run.resumeFrame(live_response);
    const frame_result = switch (try frame_run.nextFrame()) {
        .done => |value| value,
        else => return error.ExpectedDone,
    };
    try std.testing.expectEqual(@as(i32, 7), frame_result);

    const audit_image = world.AuditImage.fromReport(replayed.audit, image);
    try std.testing.expectEqual(@as(usize, 1), audit_image.response_frame_count);
    try std.testing.expectEqual(@as(usize, 1), audit_image.replayed_frame_count);
    try std.testing.expect(audit_image.audit_fingerprint != 0);
}

test "world transcript stores string-list values for replay" {
    const response_fingerprint = @as(u64, 0x123);
    const key = world.ReplayKeySeed{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xabc,
    };
    const response: []const []const u8 = &.{ "alpha", "beta" };
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var stored = try world.StoredValue.init(std.testing.allocator, response);
    defer stored.deinit(std.testing.allocator);
    try transcript.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = key.request_fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = .@"resume",
        .replay_key = key.withResponse(response_fingerprint).fingerprint(),
        .value = stored,
    });

    const event = try transcript.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume");
    const event_stored = event.value orelse return error.MissingResponseEvent;
    const cloned = try event_stored.as(std.testing.allocator, []const []const u8);
    defer {
        for (cloned) |item| std.testing.allocator.free(item);
        std.testing.allocator.free(cloned);
    }
    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expectEqualStrings("alpha", cloned[0]);
    try std.testing.expectEqualStrings("beta", cloned[1]);
}

test "world transcript append clones stored values" {
    const response_fingerprint = @as(u64, 0x456);
    const key = world.ReplayKeySeed{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = 0xdef,
    };
    var source = world.Transcript.init(std.testing.allocator);
    var stored = try world.StoredValue.init(std.testing.allocator, @as(i32, 9));
    defer stored.deinit(std.testing.allocator);
    try source.append(.{
        .kind = .port_responded,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = PortsDecl.world_port_id,
        .request_fingerprint = key.request_fingerprint,
        .response_fingerprint = response_fingerprint,
        .response_kind = .@"resume",
        .replay_key = key.withResponse(response_fingerprint).fingerprint(),
        .value = stored,
    });

    var cloned = world.Transcript.init(std.testing.allocator);
    defer cloned.deinit();
    try cloned.append(source.events.items[0]);
    source.deinit();

    const event = try cloned.nextResponse(key, fixtures.Ports.Target.Certificate.certificate_fingerprint, .@"resume");
    const cloned_value = try (event.value orelse return error.MissingResponseEvent).as(std.testing.allocator, i32);
    try std.testing.expectEqual(@as(i32, 9), cloned_value);
}

test "world audit report counts fresh calls and fingerprints" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(fixtures.Ports.Target.WorldSurface.surface_fingerprint, result.audit.world_surface_fingerprint);
    try std.testing.expectEqual(fixtures.Ports.Target.Certificate.certificate_fingerprint, result.audit.target_certificate_fingerprint);
    try std.testing.expectEqual(world.Mode.audit, result.audit.mode);
    try std.testing.expectEqual(@as(usize, 1), result.audit.port_request_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.fresh_response_count);
    try std.testing.expectEqual(@as(usize, 1), result.audit.per_port_counts[0]);
}

test "world audit mode rejects self-referential audit source" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};

    try std.testing.expectError(error.InvalidMode, PortsMachine.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.audit,
        .ctx = &ctx,
        .transcript = &transcript,
    }));
}

test "supervised audit permits authorize requested mode not source mode" {
    const strict_audit_policy = world.SupervisionPolicy.init(.{
        .allow_audit_only = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const audit_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = world.Mode.audit,
        .policy = strict_audit_policy,
    });
    var audit_runtime = boundary.Runtime.init(std.testing.allocator);
    defer audit_runtime.deinit();
    var audit_ctx: PortsCtx = .{};
    var audited = try PortsMachineEnv.run(&audit_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.fresh,
        .ctx = &audit_ctx,
        .permit = audit_permit,
    });
    defer audited.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Mode.audit, audited.audit.mode);
    try std.testing.expectEqual(@as(usize, 1), audit_ctx.calls);
    try std.testing.expect(audited.receipt != null);

    var replay_transcript = world.Transcript.init(std.testing.allocator);
    defer replay_transcript.deinit();
    try recordPortsTranscript(&replay_transcript);
    var replay_image = try replay_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer replay_image.deinit(std.testing.allocator);
    const replay_audit_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = world.Mode.audit,
        .policy = strict_audit_policy,
        .budget = world.Budget.init(.{ .max_fresh_calls = 0, .max_replay_calls = 1 }),
    });
    var replay_audit_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_audit_runtime.deinit();
    var replay_audit_ctx: PortsCtx = .{};
    var replay_audited = try PortsMachineEnv.run(&replay_audit_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.replay,
        .ctx = &replay_audit_ctx,
        .transcript_image = &replay_image,
        .permit = replay_audit_permit,
    });
    defer replay_audited.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.Mode.audit, replay_audited.audit.mode);
    try std.testing.expectEqual(@as(usize, 0), replay_audit_ctx.calls);
    try std.testing.expectEqual(@as(usize, 1), replay_audited.audit.replayed_response_count);
    try std.testing.expect(replay_audited.receipt != null);

    const image_required_audit_policy = world.SupervisionPolicy.init(.{
        .allow_audit_only = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const image_required_audit_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = world.Mode.audit,
        .policy = image_required_audit_policy,
    });
    var mutable_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer mutable_replay_runtime.deinit();
    var mutable_replay_ctx: PortsCtx = .{};
    var mutable_replay_transcript = world.Transcript.init(std.testing.allocator);
    defer mutable_replay_transcript.deinit();
    try recordPortsTranscript(&mutable_replay_transcript);
    try std.testing.expectError(error.TranscriptImageRequired, PortsMachineEnv.run(&mutable_replay_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.replay,
        .ctx = &mutable_replay_ctx,
        .transcript = &mutable_replay_transcript,
        .permit = image_required_audit_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), mutable_replay_ctx.calls);

    const fresh_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = world.Mode.fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: PortsCtx = .{};
    try std.testing.expectError(error.SupervisionDenied, PortsMachineEnv.run(&fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.audit,
        .audit_source = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .permit = fresh_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), fresh_ctx.calls);
}

const AgentCtx = struct {
    allocator: std.mem.Allocator,
    scenario: fixtures.Agent.Scenario,
    model_calls: usize = 0,
    tool_calls: usize = 0,
    event_count: usize = 2,
};

fn decide(ctx: *AgentCtx, observation: []const u8) !fixtures.Agent.Action {
    ctx.model_calls += 1;
    const action = fixtures.Agent.decideAction(ctx.scenario, observation);
    if (action == .tool) ctx.event_count += 2;
    return action;
}

fn tool(ctx: *AgentCtx, command: []const u8) ![]const u8 {
    ctx.tool_calls += 1;
    ctx.event_count += 2;
    return fixtures.Agent.callTool(ctx.allocator, ctx.scenario, command);
}

const AgentDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const AgentToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, tool);
const AgentEnv = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(AgentDecideDecl, world.NativeAdapter(decide)),
        world.bind(AgentToolDecl, world.NativeAdapter(tool)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const AgentEnvTranscriptRequired = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(AgentDecideDecl, world.NativeAdapter(decide)),
        world.bind(AgentToolDecl, world.NativeAdapter(tool)),
    },
    .policy = world.EnvironmentPolicy.init(.{
        .allow_replay_without_handlers = true,
        .allow_fresh_without_transcript = false,
    }),
});
const AgentEnvReordered = world.Environment(fixtures.Agent.Target, .{
    .bindings = .{
        world.bind(AgentToolDecl, world.NativeAdapter(tool)),
        world.bind(AgentDecideDecl, world.NativeAdapter(decide)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const AgentMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ AgentDecideDecl, AgentToolDecl },
    .strict_handler_coverage = true,
});
const AgentMachineEnv = world.Machine(fixtures.Agent.Target, .{
    .environment = AgentEnv,
    .strict_handler_coverage = true,
});
const AgentArgs = struct { usize, []const u8 };
const AgentOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *AgentCtx,
    transcript: *world.Transcript,
};
const AgentResult = AgentMachine.Run(*boundary.Runtime, AgentArgs, AgentOptions).Result;

const GuestConformanceSummary = struct {
    status: world.Guest.Status,
    result_fingerprint: u64,
    pending_fingerprints: [4]u64 = [_]u64{0} ** 4,
    pending_count: usize = 0,
    model_pending: usize = 0,
    tool_pending: usize = 0,
};

fn runNormalOnePortConformance() !GuestConformanceSummary {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    _ = try runspace.tick();
    const pending = try runspace.mailbox.get(0);
    const request = pending.request_frame orelse return error.ExpectedFrameRequest;
    _ = try runspace.respondValue(0, @as(i32, 7));
    _ = try runspace.tick();
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    return .{
        .status = .done,
        .result_fingerprint = image.run_image_fingerprint,
        .pending_fingerprints = .{ request.frame_fingerprint, 0, 0, 0 },
        .pending_count = 1,
    };
}

fn runNativeGuestOnePortConformance() !GuestConformanceSummary {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();
    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    try std.testing.expectEqual(world.Guest.Status.parked.code(), guest.world_tick());
    const request_len = guest.world_pending_request_len(0);
    const request_bytes = try std.testing.allocator.alloc(u8, request_len);
    defer std.testing.allocator.free(request_bytes);
    _ = guest.world_read_pending_request(0, request_bytes);
    var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
    defer request.deinit(std.testing.allocator);
    var response = try world.Frame.Response.fromPortableValue(std.testing.allocator, request, 1, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    const response_bytes = try response.encode(std.testing.allocator);
    defer std.testing.allocator.free(response_bytes);
    try std.testing.expectEqual(world.Guest.Status.running.code(), guest.world_submit_response(response_bytes));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Guest.Status.done.code(), guest.world_tick());
    const result_len = guest.world_result_len();
    const result_bytes = try std.testing.allocator.alloc(u8, result_len);
    defer std.testing.allocator.free(result_bytes);
    _ = guest.world_read_result(result_bytes);
    var image = try world.RunImage.decode(std.testing.allocator, result_bytes);
    defer image.deinit(std.testing.allocator);
    return .{
        .status = .done,
        .result_fingerprint = image.run_image_fingerprint,
        .pending_fingerprints = .{ request.frame_fingerprint, 0, 0, 0 },
        .pending_count = 1,
    };
}

fn respondAgentRequest(request: world.Frame.Request, model_pending: *usize, tool_pending: *usize) !world.Frame.Response {
    if (request.world_port_id == AgentDecideDecl.world_port_id) {
        model_pending.* += 1;
        const action: fixtures.Agent.Action = if (model_pending.* == 1)
            .{ .tool = "actuate" }
        else
            .{ .final = "final=actuate skeleton complete" };
        return world.Frame.Response.fromPortableValue(
            std.testing.allocator,
            request,
            request.expected_response_value_table_id,
            .@"resume",
            action,
            .portable,
        );
    }
    if (request.world_port_id == AgentToolDecl.world_port_id) {
        tool_pending.* += 1;
        return world.Frame.Response.fromPortableValue(
            std.testing.allocator,
            request,
            request.expected_response_value_table_id,
            .@"resume",
            @as([]const u8, "actuate"),
            .portable,
        );
    }
    return error.FramePortMismatch;
}

fn runNormalAgentConformance() !GuestConformanceSummary {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installMachineRun(fixtures.Agent.Target, AgentEnv, &runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var summary: GuestConformanceSummary = .{ .status = .running, .result_fingerprint = 0 };
    while (runspace.report().completed_count == 0) {
        _ = try runspace.tick();
        const pending_ports = try runspace.mailbox.listPending(std.testing.allocator);
        defer std.testing.allocator.free(pending_ports);
        for (pending_ports) |pending| {
            const request = pending.request_frame orelse return error.ExpectedFrameRequest;
            if (summary.pending_count >= summary.pending_fingerprints.len) return error.TooManyPendingPorts;
            summary.pending_fingerprints[summary.pending_count] = request.frame_fingerprint;
            summary.pending_count += 1;
            var response = try respondAgentRequest(request, &summary.model_pending, &summary.tool_pending);
            defer response.deinit(std.testing.allocator);
            _ = try runspace.respond(pending.mailbox_id, response);
        }
    }
    try std.testing.expectEqual(@as(usize, 0), ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.tool_calls);
    var image = try runspace.exportRun(handle);
    defer image.deinit(std.testing.allocator);
    summary.status = .done;
    summary.result_fingerprint = image.run_image_fingerprint;
    return summary;
}

fn runNativeGuestAgentConformance() !GuestConformanceSummary {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();
    try guest.installMachineRun(fixtures.Agent.Target, AgentEnv, &runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    var summary: GuestConformanceSummary = .{ .status = .running, .result_fingerprint = 0 };
    while (guest.world_status() != world.Guest.Status.done.code()) {
        const status = guest.world_tick();
        if (status == world.Guest.Status.done.code()) break;
        try std.testing.expectEqual(world.Guest.Status.parked.code(), status);
        const request_len = guest.world_pending_request_len(0);
        const request_bytes = try std.testing.allocator.alloc(u8, request_len);
        defer std.testing.allocator.free(request_bytes);
        _ = guest.world_read_pending_request(0, request_bytes);
        var request = try world.Frame.Request.decode(std.testing.allocator, request_bytes);
        defer request.deinit(std.testing.allocator);
        if (summary.pending_count >= summary.pending_fingerprints.len) return error.TooManyPendingPorts;
        summary.pending_fingerprints[summary.pending_count] = request.frame_fingerprint;
        summary.pending_count += 1;
        var response = try respondAgentRequest(request, &summary.model_pending, &summary.tool_pending);
        defer response.deinit(std.testing.allocator);
        const response_bytes = try response.encode(std.testing.allocator);
        defer std.testing.allocator.free(response_bytes);
        try std.testing.expectEqual(world.Guest.Status.running.code(), guest.world_submit_response(response_bytes));
    }
    try std.testing.expectEqual(@as(usize, 0), ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.tool_calls);
    const result_len = guest.world_result_len();
    const result_bytes = try std.testing.allocator.alloc(u8, result_len);
    defer std.testing.allocator.free(result_bytes);
    _ = guest.world_read_result(result_bytes);
    var image = try world.RunImage.decode(std.testing.allocator, result_bytes);
    defer image.deinit(std.testing.allocator);
    summary.status = .done;
    summary.result_fingerprint = image.run_image_fingerprint;
    return summary;
}

test "native guest one-port conformance matches normal runspace" {
    const native = try runNormalOnePortConformance();
    const guest = try runNativeGuestOnePortConformance();
    try std.testing.expectEqual(native.status, guest.status);
    try std.testing.expectEqual(native.result_fingerprint, guest.result_fingerprint);
    try std.testing.expectEqual(native.pending_count, guest.pending_count);
    try std.testing.expectEqual(native.pending_fingerprints[0], guest.pending_fingerprints[0]);
    const vector = world.Guest.ConformanceVector.init(.{
        .name = "one-port",
        .kind = .one_port,
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .expected_pending_frame_fingerprints = native.pending_fingerprints[0..native.pending_count],
        .expected_final_result_fingerprint = native.result_fingerprint,
        .expected_status_sequence = &.{ .initialized, .parked, .running, .done },
    });
    const report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = vector.vector_fingerprint,
        .native_run_result = .{ .status = native.status, .result_fingerprint = native.result_fingerprint, .pending_frame_fingerprints = native.pending_fingerprints[0..native.pending_count] },
        .native_abi_result = .{ .status = guest.status, .result_fingerprint = guest.result_fingerprint, .pending_frame_fingerprints = guest.pending_fingerprints[0..guest.pending_count] },
        .status_sequence_match = true,
        .pending_frame_match = true,
        .final_result_match = true,
    });
    try std.testing.expect(vector.vector_fingerprint != 0);
    try std.testing.expect(report.report_fingerprint != 0);
}

test "guest conformance report fingerprint delimits blockers and warnings" {
    const split_blockers = [_][]const u8{ "ab", "c" };
    const merged_blockers = [_][]const u8{ "a", "bc" };
    const split_report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = 0xabc,
        .native_run_result = .{ .status = .failed },
        .native_abi_result = .{ .status = .failed },
        .blockers = &split_blockers,
    });
    const merged_report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = 0xabc,
        .native_run_result = .{ .status = .failed },
        .native_abi_result = .{ .status = .failed },
        .blockers = &merged_blockers,
    });
    try std.testing.expect(split_report.report_fingerprint != merged_report.report_fingerprint);

    const split_warnings = [_][]const u8{ "xy", "z" };
    const merged_warnings = [_][]const u8{ "x", "yz" };
    const split_warning_report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = 0xdef,
        .native_run_result = .{ .status = .failed },
        .native_abi_result = .{ .status = .failed },
        .warnings = &split_warnings,
    });
    const merged_warning_report = world.Guest.ConformanceReport.init(.{
        .vector_fingerprint = 0xdef,
        .native_run_result = .{ .status = .failed },
        .native_abi_result = .{ .status = .failed },
        .warnings = &merged_warnings,
    });
    try std.testing.expect(split_warning_report.report_fingerprint != merged_warning_report.report_fingerprint);
}

test "guest conformance vector fingerprint delimits name before kind" {
    const target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint;
    const name_ending_with_kind_byte = world.Guest.ConformanceVector.init(.{
        .name = "one\x01",
        .kind = .one_port,
        .target_ref_fingerprint = target_ref_fingerprint,
    });
    const shorter_name_next_kind = world.Guest.ConformanceVector.init(.{
        .name = "one",
        .kind = .agent,
        .target_ref_fingerprint = target_ref_fingerprint,
    });
    try std.testing.expect(name_ending_with_kind_byte.vector_fingerprint != shorter_name_next_kind.vector_fingerprint);
}

test "native guest agent conformance matches normal runspace" {
    const native = try runNormalAgentConformance();
    const guest = try runNativeGuestAgentConformance();
    try std.testing.expectEqual(native.status, guest.status);
    try std.testing.expectEqual(native.result_fingerprint, guest.result_fingerprint);
    try std.testing.expectEqual(native.pending_count, guest.pending_count);
    try std.testing.expectEqual(@as(usize, 2), guest.model_pending);
    try std.testing.expectEqual(@as(usize, 1), guest.tool_pending);
    try std.testing.expectEqual(native.model_pending, guest.model_pending);
    try std.testing.expectEqual(native.tool_pending, guest.tool_pending);
    for (native.pending_fingerprints[0..native.pending_count], guest.pending_fingerprints[0..guest.pending_count]) |native_frame, guest_frame| {
        try std.testing.expectEqual(native_frame, guest_frame);
    }
}

test "native guest supervised denial matches normal runspace denial" {
    var native_runtime = boundary.Runtime.init(std.testing.allocator);
    defer native_runtime.deinit();
    var native_ctx: PortsCtx = .{};
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    var native_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer native_runspace.deinit();
    _ = try native_runspace.installMachineRun(fixtures.Ports.Target, PortsEnv, &native_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &native_ctx,
        .permit = permit,
    });
    try std.testing.expectError(error.BudgetExceeded, native_runspace.tick());
    try std.testing.expectEqual(@as(usize, 0), native_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), native_runspace.report().pending_port_count);

    var guest_runtime = boundary.Runtime.init(std.testing.allocator);
    defer guest_runtime.deinit();
    var guest_ctx: PortsCtx = .{};
    var guest = world.Guest.NativeGuest.init(std.testing.allocator, .{});
    defer guest.deinit();
    try guest.installMachineRun(fixtures.Ports.Target, PortsEnv, &guest_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &guest_ctx,
        .permit = permit,
    });
    try std.testing.expectEqual(world.Guest.Status.supervision_denied.code(), guest.world_tick());
    try std.testing.expectEqual(@as(usize, 0), guest_ctx.calls);
    try std.testing.expectEqual(@as(u32, 0), guest.world_pending_count());
}

const BorrowedAgentCtx = struct {
    final_storage: [32]u8 = undefined,
    calls: usize = 0,

    fn init() @This() {
        var ctx: @This() = .{};
        @memcpy(ctx.final_storage[0.."final=borrowed".len], "final=borrowed");
        return ctx;
    }
};

fn decideBorrowed(ctx: *BorrowedAgentCtx, _: []const u8) !fixtures.Agent.Action {
    ctx.calls += 1;
    return .{ .final = ctx.final_storage[0.."final=borrowed".len] };
}

fn unusedTool(_: *BorrowedAgentCtx, _: []const u8) ![]const u8 {
    return error.UnexpectedToolCall;
}

const BorrowedDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decideBorrowed);
const BorrowedToolDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, unusedTool);
const BorrowedMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ BorrowedDecideDecl, BorrowedToolDecl },
    .strict_handler_coverage = true,
});
const BorrowedOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *BorrowedAgentCtx,
    transcript: *world.Transcript,
};

const OwnedResponseCtx = struct {
    allocator: std.mem.Allocator,
    cleanup_calls: usize = 0,
};

fn ownedTool(ctx: *OwnedResponseCtx, _: []const u8) ![]const u8 {
    return try ctx.allocator.dupe(u8, "owned-response");
}

fn deinitOwnedToolResponse(ctx: *OwnedResponseCtx, response: []const u8) void {
    ctx.cleanup_calls += 1;
    ctx.allocator.free(@constCast(response));
}

fn ownedDecide(_: *OwnedResponseCtx, observation: []const u8) !fixtures.Agent.Action {
    if (std.mem.eql(u8, observation, "start")) return .{ .tool = "owned" };
    return .{ .final = observation };
}

const OwnedDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, ownedDecide);
const OwnedToolDecl = world.portWithOptions(fixtures.Agent.Target, fixtures.Agent.Tool, ownedTool, .{
    .response_deinit = deinitOwnedToolResponse,
});
const OwnedMachine = world.Machine(fixtures.Agent.Target, .{
    .ports = .{ OwnedDecideDecl, OwnedToolDecl },
    .strict_handler_coverage = true,
});
const OwnedOptions = struct {
    allocator: std.mem.Allocator,
    mode: world.Mode,
    ctx: *OwnedResponseCtx,
    transcript: *world.Transcript,
};

test "world retains fresh handler responses before resuming boundary" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx = BorrowedAgentCtx.init();

    var run = try BorrowedMachine.start(&runtime, AgentArgs{ @as(usize, 1), "ignored" }, BorrowedOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();

    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try run.dispatch();
    @memcpy(ctx.final_storage[0.."final=mutated!".len], "final=mutated!");

    switch (try run.next()) {
        .done => |value| try std.testing.expectEqualStrings("final=borrowed", value),
        else => return error.ExpectedDone,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world stores transcript values with the transcript allocator" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var run_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = run_arena.deinit();
    var ctx = BorrowedAgentCtx.init();

    var result = try BorrowedMachine.run(&runtime, AgentArgs{ @as(usize, 1), "ignored" }, BorrowedOptions{
        .allocator = run_arena.allocator(),
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(run_arena.allocator());

    try std.testing.expectEqualStrings("final=borrowed", result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "world deinitializes owned handler responses after retaining them" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: OwnedResponseCtx = .{ .allocator = std.testing.allocator };

    var result = try OwnedMachine.run(&runtime, AgentArgs{ @as(usize, 2), "start" }, OwnedOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("owned-response", result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.cleanup_calls);
}

fn runAgentScenario(allocator: std.mem.Allocator, scenario: fixtures.Agent.Scenario) !struct {
    fresh_result: AgentResult,
    replay_result: AgentResult,
    transcript: world.Transcript,
    fresh_ctx: AgentCtx,
    replay_ctx: AgentCtx,
} {
    if (scenario == .fixture) try fixtures.Agent.prepareFixtureWorkspace();

    var transcript = world.Transcript.init(allocator);
    errdefer transcript.deinit();

    var fresh_runtime = boundary.Runtime.init(allocator);
    defer fresh_runtime.deinit();
    var fresh_ctx: AgentCtx = .{ .allocator = allocator, .scenario = scenario };
    const args: AgentArgs = .{ 3, fixtures.Agent.initialObservation(scenario) };
    var fresh_result = try AgentMachine.run(&fresh_runtime, args, AgentOptions{
        .allocator = allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_ctx,
        .transcript = &transcript,
    });
    errdefer fresh_result.deinit(allocator);

    var replay_runtime = boundary.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = allocator, .scenario = scenario };
    var replay_result = try AgentMachine.run(&replay_runtime, args, AgentOptions{
        .allocator = allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    errdefer replay_result.deinit(allocator);

    return .{
        .fresh_result = fresh_result,
        .replay_result = replay_result,
        .transcript = transcript,
        .fresh_ctx = fresh_ctx,
        .replay_ctx = replay_ctx,
    };
}

test "agent loop skeleton scenario final text and accounting match" {
    var run = try runAgentScenario(std.testing.allocator, .skeleton);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();

    try std.testing.expectEqualStrings("final=actuate skeleton complete", run.fresh_result.value);
    try std.testing.expectEqualStrings(run.fresh_result.value, run.replay_result.value);
    try std.testing.expectEqual(@as(usize, 6), run.fresh_ctx.event_count);
    try std.testing.expectEqual(@as(usize, 1), run.fresh_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 3), run.transcript.summary().port_responded);
}

test "agent loop fixture scenario final text and accounting match" {
    var run = try runAgentScenario(std.testing.allocator, .fixture);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();

    try std.testing.expectEqualStrings("final=fixture updated", run.fresh_result.value);
    try std.testing.expectEqualStrings(run.fresh_result.value, run.replay_result.value);
    try std.testing.expectEqual(@as(usize, 10), run.fresh_ctx.event_count);
    try std.testing.expectEqual(@as(usize, 2), run.fresh_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), run.replay_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 5), run.transcript.summary().port_responded);

    const io = std.Io.Threaded.global_single_threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, fixtures.Agent.fixture_output_path, std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("actuate updated the fixture", bytes);
}

test "world replay selects latest zero-port source run after ported run" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();

    var ported_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ported_runtime.deinit();
    var ported_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var ported = try AgentMachine.run(&ported_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ported_ctx,
        .transcript = &transcript,
    });
    defer ported.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), transcript.summary().port_responded);

    var zero_runtime = boundary.Runtime.init(std.testing.allocator);
    defer zero_runtime.deinit();
    var zero_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var zero = try AgentMachine.run(&zero_runtime, AgentArgs{ @as(usize, 0), "ignored" }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &zero_ctx,
        .transcript = &transcript,
    });
    defer zero.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("budget exhausted", zero.value);

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var replay = try AgentMachine.run(&replay_runtime, AgentArgs{ @as(usize, 0), "ignored" }, AgentOptions{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript = &transcript,
    });
    defer replay.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("budget exhausted", replay.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.tool_calls);
}

test "target ref fingerprint stable and rejects wrong WorldSurface or TargetCertificate" {
    const ref_a = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const ref_b = world.TargetRef.fromTarget(fixtures.Ports.Target);
    try std.testing.expectEqual(ref_a.target_ref_fingerprint, ref_b.target_ref_fingerprint);
    try std.testing.expect(ref_a.matchesTarget(fixtures.Ports.Target));

    var wrong_surface = ref_a;
    wrong_surface.world_surface_fingerprint += 1;
    wrong_surface.target_ref_fingerprint += 1;
    try std.testing.expect(!wrong_surface.matchesTarget(fixtures.Ports.Target));

    var wrong_certificate = ref_a;
    wrong_certificate.target_certificate_fingerprint += 1;
    wrong_certificate.target_ref_fingerprint += 1;
    try std.testing.expect(!wrong_certificate.matchesTarget(fixtures.Ports.Target));
    try std.testing.expect(ref_a.residual_program_plan_hash != null);
}

test "import requirement and import set preserve world_port_id scope" {
    const requirement = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    const again = world.ImportRequirement.fromTargetPort(fixtures.Ports.Target, 0);
    try std.testing.expectEqual(requirement.requirement_fingerprint, again.requirement_fingerprint);
    try std.testing.expectEqual(@as(u32, 0), requirement.world_port_id);
    try std.testing.expectEqual(@as(?u32, 0), requirement.payload_value_table_id);
    try std.testing.expectEqual(@as(?u32, 1), requirement.response_value_table_id);

    const set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const ids = try set.requiredPortIds(std.testing.allocator);
    defer std.testing.allocator.free(ids);
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqual(@as(u32, 0), ids[0]);
    try std.testing.expectEqual(requirement.requirement_fingerprint, set.requirementForPort(fixtures.Ports.Target, 0).requirement_fingerprint);
}

test "world environment accepts bindings and reports missing duplicate and replay-only coverage" {
    const fresh_report = PortsEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(fresh_report.accepted);
    try std.testing.expectEqual(@as(usize, 1), fresh_report.required_port_count);
    try std.testing.expectEqual(@as(usize, 1), fresh_report.bound_port_count);

    const missing_report = PortsMissingEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!missing_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, missing_report.blockers[0]);

    const duplicate_report = PortsDuplicateEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!duplicate_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.ExtraBinding, duplicate_report.blockers[0]);

    const wrong_port_env = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongPortBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    });
    const wrong_port_report = wrong_port_env.acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_port_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.WrongPortId, wrong_port_report.blockers[0]);
    const wrong_port_plan = wrong_port_env.bindingPlan();
    try std.testing.expect(!wrong_port_plan.accepted);
    try std.testing.expectEqual(@as(usize, 1), wrong_port_plan.binding_count);
    try std.testing.expectEqual(@as(usize, 0), wrong_port_plan.dense_entries.len);
    const wrong_port_cert = wrong_port_env.certificate(.fresh, false);
    try std.testing.expectEqual(wrong_port_report.report_fingerprint, wrong_port_cert.acceptance_report_fingerprint);
    try std.testing.expectEqual(wrong_port_plan.plan_fingerprint, wrong_port_cert.binding_plan_fingerprint);

    const wrong_surface_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongSurfaceRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_surface_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.WrongWorldSurface, wrong_surface_report.blockers[0]);

    const wrong_certificate_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongCertificateRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_certificate_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.WrongTargetCertificate, wrong_certificate_report.blockers[0]);

    const wrong_requirement_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongRequirementRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_requirement_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, wrong_requirement_report.blockers[0]);

    const wrong_adapter_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongAdapterRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_adapter_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, wrong_adapter_report.blockers[0]);

    const wrong_value_policy_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongValuePolicyRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_value_policy_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, wrong_value_policy_report.blockers[0]);

    const wrong_authority_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongAuthorityRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_authority_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, wrong_authority_report.blockers[0]);

    const wrong_descriptor_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsWrongDescriptorRecordBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!wrong_descriptor_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, wrong_descriptor_report.blockers[0]);

    const authority_portable_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsPortableAuthorityBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!authority_portable_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.PortableValuesRequired, authority_portable_report.blockers[0]);

    const authority_native_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNoNativeAuthorityBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!authority_native_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.NativeOnlyValueRejected, authority_native_report.blockers[0]);

    const authority_payload_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsPayloadCapAuthorityBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!authority_payload_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.PayloadValueMismatch, authority_payload_report.blockers[0]);

    const replay_missing_bindings = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.strict_replay,
    }).acceptanceReport(.replay, true);
    try std.testing.expect(!replay_missing_bindings.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, replay_missing_bindings.blockers[0]);

    const audit_only_missing_env = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{},
        .policy = world.EnvironmentPolicy.audit_only,
    });
    const audit_only_report = audit_only_missing_env.acceptanceReport(.audit, false);
    try std.testing.expect(audit_only_report.accepted);
    const audit_only_fresh_report = audit_only_missing_env.acceptanceReport(.fresh, false);
    try std.testing.expect(!audit_only_fresh_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, audit_only_fresh_report.blockers[0]);
    const audit_only_replay_report = audit_only_missing_env.acceptanceReport(.replay, true);
    try std.testing.expect(!audit_only_replay_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, audit_only_replay_report.blockers[0]);
    const audit_only_verify_report = audit_only_missing_env.acceptanceReport(.verify, true);
    try std.testing.expect(!audit_only_verify_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.MissingBinding, audit_only_verify_report.blockers[0]);

    const replay_fresh_report = PortsReplayEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!replay_fresh_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, replay_fresh_report.blockers[0]);

    const replay_verify_report = PortsReplayEnv.acceptanceReport(.verify, true);
    try std.testing.expect(!replay_verify_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, replay_verify_report.blockers[0]);

    const byte_fresh_report = PortsByteEnv.acceptanceReport(.fresh, false);
    try std.testing.expect(!byte_fresh_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, byte_fresh_report.blockers[0]);

    const byte_verify_report = PortsByteEnv.acceptanceReport(.verify, true);
    try std.testing.expect(!byte_verify_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, byte_verify_report.blockers[0]);

    const replay_without_handlers_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsReplayBinding},
        .policy = world.EnvironmentPolicy.strict_fresh,
    }).acceptanceReport(.replay, true);
    try std.testing.expect(!replay_without_handlers_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, replay_without_handlers_report.blockers[0]);

    const replay_report = PortsReplayEnv.acceptanceReport(.replay, true);
    try std.testing.expect(replay_report.accepted);

    const transcript_required_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNativeBinding},
        .policy = world.EnvironmentPolicy.init(.{ .allow_fresh_without_transcript = false }),
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!transcript_required_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.TranscriptImageRequired, transcript_required_report.blockers[0]);

    const transcript_available_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNativeBinding},
        .policy = world.EnvironmentPolicy.init(.{ .allow_fresh_without_transcript = false }),
    }).acceptanceReport(.fresh, true);
    try std.testing.expect(transcript_available_report.accepted);

    const pending_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsPendingBinding},
        .policy = world.EnvironmentPolicy.fresh_and_replay,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!pending_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, pending_report.blockers[0]);

    const reject_report = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsRejectBinding},
        .policy = world.EnvironmentPolicy.fresh_and_replay,
    }).acceptanceReport(.fresh, false);
    try std.testing.expect(!reject_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.AdapterModeNotAllowed, reject_report.blockers[0]);
}

test "binding plan and binding descriptors exclude native function pointer identity" {
    const native_record = PortsNativeBinding.bindingRecord();
    const alternate_native_record = PortsAltNativeBinding.bindingRecord();
    try std.testing.expectEqual(native_record.binding_fingerprint, alternate_native_record.binding_fingerprint);
    try std.testing.expectEqual(native_record.adapter_descriptor_fingerprint, alternate_native_record.adapter_descriptor_fingerprint);

    const replay_record = PortsReplayBinding.bindingRecord();
    try std.testing.expect(native_record.binding_fingerprint != replay_record.binding_fingerprint);
    try std.testing.expectEqual(world.AdapterKind.replay, replay_record.adapter_kind);

    const plan = PortsEnv.bindingPlan();
    try std.testing.expect(plan.accepted);
    try std.testing.expectEqual(@as(?usize, 0), plan.lookup(0));
    try std.testing.expectEqual(@as(?usize, null), plan.lookup(99));

    const agent_plan = AgentEnv.bindingPlan();
    const reordered_agent_plan = AgentEnvReordered.bindingPlan();
    try std.testing.expectEqual(@as(u32, 0), agent_plan.dense_entries[0].world_port_id);
    try std.testing.expectEqual(@as(u32, 1), agent_plan.dense_entries[1].world_port_id);
    try std.testing.expectEqual(@as(u32, 0), reordered_agent_plan.dense_entries[0].world_port_id);
    try std.testing.expectEqual(@as(u32, 1), reordered_agent_plan.dense_entries[1].world_port_id);
    try std.testing.expectEqual(@as(usize, 0), agent_plan.dense_entries[0].adapter_slot);
    try std.testing.expectEqual(@as(usize, 1), agent_plan.dense_entries[1].adapter_slot);
    try std.testing.expectEqual(@as(usize, 1), reordered_agent_plan.dense_entries[0].adapter_slot);
    try std.testing.expectEqual(@as(usize, 0), reordered_agent_plan.dense_entries[1].adapter_slot);
    try std.testing.expect(agent_plan.plan_fingerprint != reordered_agent_plan.plan_fingerprint);
    const agent_cert = AgentEnv.certificate(.fresh, false);
    const reordered_agent_cert = AgentEnvReordered.certificate(.fresh, false);
    try std.testing.expectEqual(agent_cert.authority_descriptor_fingerprint, reordered_agent_cert.authority_descriptor_fingerprint);
    try std.testing.expectEqual(agent_cert.adapter_descriptor_fingerprint, reordered_agent_cert.adapter_descriptor_fingerprint);
    try std.testing.expect(agent_cert.certificate_fingerprint != reordered_agent_cert.certificate_fingerprint);
}

test "acceptance report port authority adapter descriptor and environment certificate fingerprints are stable" {
    const authority = world.PortAuthority.fixture;
    const same_authority = world.PortAuthority.fixture;
    try std.testing.expectEqual(authority.authority_fingerprint, same_authority.authority_fingerprint);
    try std.testing.expect(authority.allows_fresh_calls);
    try std.testing.expect(world.PortAuthority.replay_source.allows_replay);
    try std.testing.expect(!world.PortAuthority.replay_source.allows_fresh_calls);

    const record = PortsByteBinding.bindingRecord();
    try std.testing.expectEqual(world.AdapterKind.byte, record.adapter_kind);
    const native_record = PortsNativeBinding.bindingRecord();
    try std.testing.expect(native_record.adapter_descriptor_fingerprint != record.adapter_descriptor_fingerprint);

    const report = PortsEnv.acceptanceReport(.fresh, false);
    const report_again = PortsEnv.acceptanceReport(.fresh, false);
    try std.testing.expectEqual(report.report_fingerprint, report_again.report_fingerprint);

    const cert = PortsEnv.certificate(.fresh, false);
    const cert_again = PortsEnv.certificate(.fresh, false);
    try std.testing.expectEqual(cert.certificate_fingerprint, cert_again.certificate_fingerprint);
    try std.testing.expectEqual(PortsEnv.bindingPlan().plan_fingerprint, cert.binding_plan_fingerprint);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.fresh, cert.accepted_modes);

    const missing_cert = PortsMissingEnv.certificate(.fresh, false);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.none, missing_cert.accepted_modes);

    const replay_cert = PortsReplayEnv.certificate(.replay, true);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.replay, replay_cert.accepted_modes);

    const replay_fresh_cert = PortsReplayEnv.certificate(.fresh, false);
    try std.testing.expectEqual(world.EnvironmentCertificate.ModeMask.none, replay_fresh_cert.accepted_modes);
}

test "Machine accepts Environment while legacy ports config remains valid" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var result = try PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    const legacy_plan = PortsMachine.port_count;
    try std.testing.expectEqual(@as(usize, 1), legacy_plan);
}

test "byte adapter environment rejects fresh execution before native dispatch" {
    const PortsByteMachineEnv = world.Machine(fixtures.Ports.Target, .{
        .environment = PortsByteEnv,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.AdapterModeNotAllowed, PortsByteMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "run state fingerprints bind parked and completed state without runtime pointers" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const parked = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = testRequestFrame().frame_fingerprint,
        .turn_index = 3,
        .status = .parked_on_port,
    });
    const parked_again = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = testRequestFrame().frame_fingerprint,
        .turn_index = 3,
        .status = .parked_on_port,
    });
    try std.testing.expectEqual(parked.run_state_fingerprint, parked_again.run_state_fingerprint);

    const completed = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = 0x1234,
        .status = .completed,
    });
    try std.testing.expect(parked.run_state_fingerprint != completed.run_state_fingerprint);
}

test "run image encode decode roundtrip includes TargetRef TranscriptImage branches checkpoints and pending frame" {
    const request = testRequestFrame();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .source_run = true,
    });
    try transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .turn_index = request.turn_index,
        .residual_site_index = request.residual_site_index,
        .residual_site_fingerprint = request.residual_site_fingerprint,
        .request_frame = request,
    });
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const import_set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.frame_fingerprint,
        .transcript_prefix_fingerprint = image.events[0].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 2,
        .parent_branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "receiver",
        .start_event_index = 1,
        .final_event_index = image.events.len,
        .final_status = .running,
        .event_count = image.events.len,
        .response_count = image.response_count,
    };
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = 2,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
        .pending_request_frame = request,
        .environment_certificate_fingerprint = PortsEnv.certificate(.fresh, false).certificate_fingerprint,
        .acceptance_report_fingerprint = PortsEnv.acceptanceReport(.fresh, false).report_fingerprint,
    });
    const running_replay_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .status = .running,
    });
    const contradictory_replay_image = world.RunImage.init(.{
        .kind = .replay_only_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = running_replay_state,
    });
    try std.testing.expectError(error.HandoffTargetMismatch, contradictory_replay_image.validate(.{}));

    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(run_image.run_image_fingerprint, decoded.run_image_fingerprint);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, decoded.target_ref.target_ref_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), decoded.checkpoints.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.branches.len);
    try std.testing.expect(decoded.pending_request_frame != null);

    const PortsPayloadCapEnv = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsAcceptedPayloadCapBinding},
        .policy = world.EnvironmentPolicy.test_fixture,
    });
    try std.testing.expect(PortsPayloadCapEnv.acceptanceReport(.fresh, false).accepted);
    var capped_payload_image: ?world.Frame.ValueImage = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        0,
        null,
        null,
        @as([]const u8, "oversized"),
        world.ValuePolicy.portable,
    );
    errdefer if (capped_payload_image) |*payload| payload.deinit(std.testing.allocator);
    var capped_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 0,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = capped_payload_image,
    });
    capped_payload_image = null;
    defer capped_request.deinit(std.testing.allocator);
    const capped_pending_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = capped_request.frame_fingerprint,
        .turn_index = capped_request.turn_index,
        .status = .parked_on_port,
    });
    const capped_pending_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = capped_pending_state,
        .pending_request_frame = capped_request,
    });
    const capped_pending_encoded = try capped_pending_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(capped_pending_encoded);
    var capped_pending_handoff = try world.Handoff.fromRunImage(std.testing.allocator, capped_pending_encoded);
    defer capped_pending_handoff.deinit();
    const capped_pending_report = capped_pending_handoff.preflight(fixtures.Ports.Target, PortsPayloadCapEnv, .accept_fresh);
    try std.testing.expect(!capped_pending_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.NativeOnlyValueRejected, capped_pending_report.blockers[0]);

    var unknown_payload_image: ?world.Frame.ValueImage = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        0,
        null,
        null,
        @as([]const u8, "portable"),
        world.ValuePolicy.portable,
    );
    errdefer if (unknown_payload_image) |*payload| payload.deinit(std.testing.allocator);
    var unknown_port_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 99,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 0,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = unknown_payload_image,
    });
    unknown_payload_image = null;
    defer unknown_port_request.deinit(std.testing.allocator);
    const unknown_port_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = unknown_port_request.frame_fingerprint,
        .turn_index = unknown_port_request.turn_index,
        .status = .parked_on_port,
    });
    const unknown_port_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = unknown_port_state,
        .pending_request_frame = unknown_port_request,
    });
    const unknown_port_encoded = try unknown_port_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(unknown_port_encoded);
    var unknown_port_handoff = try world.Handoff.fromRunImage(std.testing.allocator, unknown_port_encoded);
    defer unknown_port_handoff.deinit();
    const unknown_port_report = unknown_port_handoff.preflight(fixtures.Ports.Target, PortsEnv, .accept_fresh);
    try std.testing.expect(!unknown_port_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.WrongPortId, unknown_port_report.blockers[0]);

    var cap_handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer cap_handoff.deinit();
    const cap_report = cap_handoff.preflight(fixtures.Ports.Target, PortsPayloadCapEnv, .accept_fresh);
    try std.testing.expect(!cap_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.NativeOnlyValueRejected, cap_report.blockers[0]);

    const missing_pending_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const missing_pending_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = missing_pending_state,
        .pending_request_frame = request,
    });
    try std.testing.expectError(error.HandoffPendingFrameMismatch, missing_pending_image.validate(.{}));

    const stale_pending_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.request_fingerprint,
        .turn_index = request.turn_index,
        .status = .running,
    });
    const stale_pending_image = world.RunImage.init(.{
        .kind = .full_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = stale_pending_state,
        .pending_request_frame = request,
    });
    try std.testing.expectError(error.HandoffPendingFrameMismatch, stale_pending_image.validate(.{}));

    const wrong_turn_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index + 1,
        .status = .parked_on_port,
    });
    const wrong_turn_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = wrong_turn_state,
        .pending_request_frame = request,
    });
    try std.testing.expectError(error.HandoffPendingFrameMismatch, wrong_turn_image.validate(.{}));

    var malformed = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed);
    malformed[8] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed));

    var malformed_target_ref = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed_target_ref);
    malformed_target_ref[25] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed_target_ref));

    var transcript_fingerprint_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &transcript_fingerprint_bytes, image.transcript_image_fingerprint, .little);
    const encoded_transcript_fingerprint_offset = try nthBytesOffset(encoded, &transcript_fingerprint_bytes, 1);
    var malformed_transcript_fingerprint = try std.testing.allocator.dupe(u8, encoded);
    defer std.testing.allocator.free(malformed_transcript_fingerprint);
    malformed_transcript_fingerprint[encoded_transcript_fingerprint_offset] +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(std.testing.allocator, malformed_transcript_fingerprint));

    const stale_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const stale_transcript_binding = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = stale_state,
    });
    try std.testing.expectError(error.HandoffTargetMismatch, stale_transcript_binding.validate(.{}));

    const wrong_status_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .status = .failed,
    });
    const wrong_status_binding = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = image,
        .current_state = wrong_status_state,
    });
    try std.testing.expectError(error.HandoffTargetMismatch, wrong_status_binding.validate(.{}));

    var completed_transcript = world.Transcript.init(std.testing.allocator);
    defer completed_transcript.deinit();
    try recordPortsTranscript(&completed_transcript);
    var native_image = try completed_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.native_compatible });
    defer native_image.deinit(std.testing.allocator);
    const native_image_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = native_image.transcript_image_fingerprint,
        .status = .completed,
    });
    const native_transcript_binding = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .transcript_image = native_image,
        .current_state = native_image_state,
    });
    try std.testing.expectError(error.UnsupportedValueImage, native_transcript_binding.validate(.{ .require_portable_values = true }));
    try std.testing.expectError(error.InvalidFrameEncoding, native_transcript_binding.validate(.{ .max_image_bytes = 1 }));

    var final_image = try world.Frame.ValueImage.fromValue(std.testing.allocator, 1, null, null, @as(i32, 7), .portable);
    defer final_image.deinit(std.testing.allocator);
    const borrowed_final_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = final_image.value_image_fingerprint,
        .status = .completed,
    });
    var borrowed_final_owner = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = borrowed_final_state,
        .final_result_image = final_image,
    });
    borrowed_final_owner.deinit(std.testing.allocator);
    const mismatched_final_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .final_value_image_fingerprint = final_image.value_image_fingerprint + 1,
        .status = .completed,
    });
    const mismatched_final_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = mismatched_final_state,
        .final_result_image = final_image,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_final_image.validate(.{}));

    const wrong_target_checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint + 1,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = request.turn_index,
        .current_request_fingerprint = request.frame_fingerprint,
        .transcript_prefix_fingerprint = image.events[0].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const wrong_checkpoint_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .checkpoint_fingerprint = wrong_target_checkpoint.checkpoint_fingerprint,
        .status = .parked_on_port,
    });
    const wrong_target_checkpoint_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = wrong_checkpoint_state,
        .checkpoints = &.{wrong_target_checkpoint},
        .pending_request_frame = request,
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, wrong_target_checkpoint_image.validate(.{}));
}

test "run image decode rejects oversized timeline counts before allocation" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const import_set = world.ImportSet.fromTarget(fixtures.Ports.Target);
    const base_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const base_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = base_state,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, base_image.validate(.{ .require_known_target = true }));
    const base_encoded = try base_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(base_encoded);

    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 1,
        .turn_index = 1,
        .transcript_prefix_fingerprint = 0,
        .branch_id = 0,
        .status = .running,
    });
    const checkpoint_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = import_set.import_set_fingerprint,
        .current_state = base_state,
        .checkpoints = &.{checkpoint},
    });
    const checkpoint_encoded = try checkpoint_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(checkpoint_encoded);

    const checkpoint_count_offset = try firstDiffAfter(base_encoded, checkpoint_encoded, 17);

    var oversized_checkpoints = try std.testing.allocator.dupe(u8, base_encoded);
    defer std.testing.allocator.free(oversized_checkpoints);
    writeLittleU64(
        oversized_checkpoints[checkpoint_count_offset..][0..8],
        (world.RunImage.ValidateOptions{}).max_checkpoints + 1,
    );
    var fixed_buffer: [1024]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(fixed_allocator.allocator(), oversized_checkpoints));

    var oversized_branches = try std.testing.allocator.dupe(u8, base_encoded);
    defer std.testing.allocator.free(oversized_branches);
    writeLittleU64(
        oversized_branches[checkpoint_count_offset + 8 ..][0..8],
        (world.RunImage.ValidateOptions{}).max_branches + 1,
    );
    var fixed_allocator_again = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    try std.testing.expectError(error.InvalidFrameEncoding, world.RunImage.decode(fixed_allocator_again.allocator(), oversized_branches));
}

test "handoff preflight rejects target mismatch and accepts replay handoff with transcript image" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var borrowed_image_owner = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    borrowed_image_owner.deinit(std.testing.allocator);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    const replay_report = handoff.preflight(fixtures.Ports.Target, PortsReplayEnv, .accept_replay);
    try std.testing.expect(replay_report.accepted);

    const inspect_policy = world.SupervisionPolicy.init(.{
        .allow_audit_only = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const inspect_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .audit,
        .policy = inspect_policy,
        .transcript_image_available = true,
        .handoff_policy = .require_new_permit,
    });
    const inspect_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .inspect_only, inspect_permit);
    try std.testing.expect(inspect_report.accepted);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const parked_completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .status = .parked_on_port,
    });
    const parked_completed_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = parked_completed_state,
    });
    try std.testing.expectError(error.HandoffTargetMismatch, parked_completed_image.validate(.{}));

    var native_image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.native_compatible });
    defer native_image.deinit(std.testing.allocator);
    const native_run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, native_image, .replay_only_run);
    const native_encoded = try native_run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(native_encoded);
    var native_handoff = try world.Handoff.fromRunImage(std.testing.allocator, native_encoded);
    defer native_handoff.deinit();
    const native_compatible_report = native_handoff.preflight(fixtures.Ports.Target, PortsEnv, .accept_replay);
    try std.testing.expect(native_compatible_report.accepted);
    const native_replay_report = native_handoff.preflight(fixtures.Ports.Target, PortsReplayEnv, .accept_replay);
    try std.testing.expect(!native_replay_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.NativeOnlyValueRejected, native_replay_report.blockers[0]);

    const forged_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const forged_import_set = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint + 1,
        .current_state = forged_state,
    });
    const forged_encoded = try forged_import_set.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_encoded);
    var forged_handoff = try world.Handoff.fromRunImage(std.testing.allocator, forged_encoded);
    defer forged_handoff.deinit();
    const import_mismatch = forged_handoff.preflight(fixtures.Ports.Target, PortsEnv, .inspect_only);
    try std.testing.expect(!import_mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, import_mismatch.blockers[0]);

    const EmptyEnv = world.Environment(OptionalNullTarget, .{ .bindings = .{}, .policy = world.EnvironmentPolicy.audit_only });
    const mismatch = handoff.preflight(OptionalNullTarget, EmptyEnv, .inspect_only);
    try std.testing.expect(!mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffTargetMismatch, mismatch.blockers[0]);
}

test "run image transcript evidence saturates response turn advancement" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const response_event = for (image.events) |*event| {
        if (event.response_frame != null or event.kind == .port_responded or event.kind == .frame_responded or event.kind == .port_replayed or event.kind == .frame_replayed) break event;
    } else return error.ExpectedResponseEvent;
    response_event.turn_index = std.math.maxInt(usize);
    response_event.event_fingerprint = testTranscriptEventImageFingerprint(response_event.*);
    image.transcript_image_fingerprint = testTranscriptImageFingerprint(image);

    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    try std.testing.expectEqual(std.math.maxInt(usize), run_image.current_state.turn_index);
}

test "run image transcript evidence ignores non-source response frames" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    var ignored_response_events: usize = 0;
    for (image.events) |*event| {
        switch (event.kind) {
            .port_responded, .frame_responded, .port_replayed, .frame_replayed => {
                if (event.response_frame == null) continue;
                event.kind = .frame_verified;
                event.event_fingerprint = testTranscriptEventImageFingerprint(event.*);
                ignored_response_events += 1;
            },
            else => {},
        }
    }
    try std.testing.expect(ignored_response_events > 0);
    image.transcript_image_fingerprint = testTranscriptImageFingerprint(image);

    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    try std.testing.expectEqual(@as(?u64, null), run_image.current_state.final_response_fingerprint);
    try std.testing.expectEqual(@as(?u64, null), run_image.current_state.final_value_image_fingerprint);
}

test "parked handoff resumes selected pending request on receiver environment" {
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer request.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
    });
    var borrowed_frame_owner = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
    });
    borrowed_frame_owner.deinit(std.testing.allocator);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    var receiver_runtime = boundary.Runtime.init(std.testing.allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: PortsCtx = .{};
    var receiver_run = try handoff.@"resume"(fixtures.Ports.Target, PortsEnv, &receiver_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
    }, .accept_fresh);
    defer receiver_run.deinit();
    var receiver_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer receiver_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(request.frame_fingerprint, receiver_request.frame_fingerprint);
    try receiver_run.dispatch();
    const done = try receiver_run.nextFrame();
    try std.testing.expectEqual(@as(i32, 7), switch (done) {
        .done => |value| value,
        else => return error.ExpectedDone,
    });
}

test "parked handoff replays transcript prefix before selected pending request" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var run = try AgentMachineEnv.start(&runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    });
    defer run.deinit();
    var model_request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer model_request.deinit(std.testing.allocator);
    try run.dispatch();
    var tool_request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer tool_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.tool_calls);

    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .pending_request_fingerprint = tool_request.frame_fingerprint,
        .turn_index = tool_request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .pending_request_frame = tool_request,
    });
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    const accepted_fresh = handoff.preflight(fixtures.Agent.Target, AgentEnv, .accept_fresh);
    try std.testing.expect(accepted_fresh.accepted);

    const strict_transcript_fresh = handoff.preflight(fixtures.Agent.Target, AgentEnvTranscriptRequired, .accept_fresh);
    try std.testing.expect(strict_transcript_fresh.accepted);
    var strict_runtime = boundary.Runtime.init(std.testing.allocator);
    defer strict_runtime.deinit();
    var strict_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var strict_run = try handoff.@"resume"(fixtures.Agent.Target, AgentEnvTranscriptRequired, &strict_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &strict_ctx,
    }, .accept_fresh);
    defer strict_run.deinit();
    var strict_request = switch (try strict_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer strict_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(tool_request.frame_fingerprint, strict_request.frame_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), strict_ctx.model_calls);

    const stale_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .pending_request_fingerprint = model_request.frame_fingerprint,
        .turn_index = model_request.turn_index,
        .status = .parked_on_port,
    });
    const stale_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = stale_state,
        .pending_request_frame = model_request,
    });
    const stale_encoded = try stale_run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(stale_encoded);
    var stale_handoff = try world.Handoff.fromRunImage(std.testing.allocator, stale_encoded);
    defer stale_handoff.deinit();
    const stale_report = stale_handoff.preflight(fixtures.Agent.Target, AgentEnv, .accept_fresh);
    try std.testing.expect(!stale_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.ReplaySourceMissing, stale_report.blockers[0]);

    const missing_prefix_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = tool_request.frame_fingerprint,
        .turn_index = tool_request.turn_index,
        .status = .parked_on_port,
    });
    const missing_prefix_run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .current_state = missing_prefix_state,
        .pending_request_frame = tool_request,
    });
    const missing_prefix_encoded = try missing_prefix_run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(missing_prefix_encoded);
    var missing_prefix_handoff = try world.Handoff.fromRunImage(std.testing.allocator, missing_prefix_encoded);
    defer missing_prefix_handoff.deinit();
    const missing_prefix_report = missing_prefix_handoff.preflight(fixtures.Agent.Target, AgentEnv, .accept_fresh);
    try std.testing.expect(!missing_prefix_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.TranscriptImageRequired, missing_prefix_report.blockers[0]);

    const rejected_replay = handoff.preflight(fixtures.Agent.Target, AgentEnv, .accept_replay);
    try std.testing.expect(!rejected_replay.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.ReplaySourceMissing, rejected_replay.blockers[0]);

    var failed_handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer failed_handoff.deinit();
    var failed_runtime = boundary.Runtime.init(std.testing.allocator);
    defer failed_runtime.deinit();
    var failed_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var failed_transcript = world.Transcript.init(std.testing.allocator);
    defer failed_transcript.deinit();
    if (failed_handoff.@"resume"(fixtures.Agent.Target, AgentEnv, &failed_runtime, AgentArgs{ @as(usize, 3), "goal=mismatch" }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &failed_ctx,
        .transcript = &failed_transcript,
    }, .accept_fresh)) |unexpected_run| {
        var run_to_deinit = unexpected_run;
        run_to_deinit.deinit();
        return error.ExpectedFailure;
    } else |_| {}
    try std.testing.expectEqual(@as(usize, 1), failed_transcript.summary().run_started);
    try std.testing.expectEqual(@as(usize, 1), failed_transcript.summary().run_failed);

    var prefix_image = &handoff.run_image.transcript_image.?;
    try prefix_image.prepareReplayPrefixForPendingRequest(
        fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        fixtures.Agent.Target.Certificate.certificate_fingerprint,
        tool_request.frame_fingerprint,
    );
    const prefix_limit = prefix_image.replay_limit orelse return error.ExpectedReplayLimit;
    try std.testing.expect(prefix_limit < prefix_image.events.len);
    try std.testing.expectEqual(tool_request.frame_fingerprint, prefix_image.events[prefix_limit].request_frame.?.frame_fingerprint);
    prefix_image.resetReplay();

    var replay_denied_handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer replay_denied_handoff.deinit();
    const replay_denied_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_replay_calls = 0 }),
        .handoff_policy = .allow,
    });
    const replay_denied_report = replay_denied_handoff.preflightWithPermit(fixtures.Agent.Target, AgentEnv, .accept_fresh, replay_denied_permit);
    try std.testing.expect(!replay_denied_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, replay_denied_report.blockers[0]);

    const request_denied_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
        .handoff_policy = .allow,
    });
    const request_denied_report = replay_denied_handoff.preflightWithPermit(fixtures.Agent.Target, AgentEnv, .accept_fresh, request_denied_permit);
    try std.testing.expect(!request_denied_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, request_denied_report.blockers[0]);

    const step_denied_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
        .handoff_policy = .allow,
    });
    const step_denied_report = replay_denied_handoff.preflightWithPermit(fixtures.Agent.Target, AgentEnv, .accept_fresh, step_denied_permit);
    try std.testing.expect(!step_denied_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, step_denied_report.blockers[0]);

    var replay_denied_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_denied_runtime.deinit();
    var replay_denied_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    try std.testing.expectError(error.BudgetExceeded, replay_denied_handoff.resumeWithPermit(fixtures.Agent.Target, AgentEnv, &replay_denied_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &replay_denied_ctx,
    }, .accept_fresh, replay_denied_permit));
    try std.testing.expectEqual(@as(usize, 0), replay_denied_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), replay_denied_ctx.tool_calls);

    var fresh_limited_handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer fresh_limited_handoff.deinit();
    const fresh_limited_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_fresh_calls = 1 }),
        .handoff_policy = .allow,
    });
    const fresh_limited_report = fresh_limited_handoff.preflightWithPermit(fixtures.Agent.Target, AgentEnv, .accept_fresh, fresh_limited_permit);
    try std.testing.expect(fresh_limited_report.accepted);
    var fresh_limited_runtime = boundary.Runtime.init(std.testing.allocator);
    defer fresh_limited_runtime.deinit();
    var fresh_limited_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var fresh_limited_run = try fresh_limited_handoff.resumeWithPermit(fixtures.Agent.Target, AgentEnv, &fresh_limited_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &fresh_limited_ctx,
    }, .accept_fresh, fresh_limited_permit);
    defer fresh_limited_run.deinit();
    try fresh_limited_run.dispatch();
    try std.testing.expectEqual(@as(usize, 0), fresh_limited_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 1), fresh_limited_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 1), fresh_limited_run.supervisor.?.ledger.total_fresh_calls);
    try std.testing.expectEqual(@as(usize, 1), fresh_limited_run.supervisor.?.ledger.total_replay_calls);

    var receiver_runtime = boundary.Runtime.init(std.testing.allocator);
    defer receiver_runtime.deinit();
    var receiver_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var receiver_transcript = world.Transcript.init(std.testing.allocator);
    defer receiver_transcript.deinit();
    var receiver_run = try handoff.@"resume"(fixtures.Agent.Target, AgentEnv, &receiver_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &receiver_ctx,
        .transcript = &receiver_transcript,
    }, .accept_fresh);
    defer receiver_run.deinit();
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), receiver_ctx.tool_calls);

    var receiver_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer receiver_request.deinit(std.testing.allocator);
    try std.testing.expectEqual(tool_request.frame_fingerprint, receiver_request.frame_fingerprint);
    try receiver_run.dispatch();
    var final_model_request = switch (try receiver_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedPortRequest,
    };
    defer final_model_request.deinit(std.testing.allocator);
    try receiver_run.dispatch();
    const done = try receiver_run.nextFrame();
    try std.testing.expectEqualStrings("final=actuate skeleton complete", switch (done) {
        .done => |value| value,
        else => return error.ExpectedDone,
    });
    try std.testing.expectEqual(@as(usize, 1), receiver_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 1), receiver_ctx.tool_calls);
    try std.testing.expectEqual(@as(usize, 1), receiver_run.audit.replayed_response_count);
    try std.testing.expectEqual(@as(usize, 1), receiver_transcript.summary().frame_replayed);
    try std.testing.expectEqual(@as(usize, 0), receiver_transcript.summary().frame_responded);

    var receiver_image = try receiver_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer receiver_image.deinit(std.testing.allocator);
    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replayed = try AgentMachineEnv.run(&replay_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &receiver_image,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", replayed.value);
    try std.testing.expectEqual(@as(usize, 3), replayed.audit.replayed_response_count);

    receiver_transcript.resetReplay();
    var transcript_replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer transcript_replay_runtime.deinit();
    var transcript_replayed = try AgentMachineEnv.run(&transcript_replay_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &receiver_transcript,
    });
    defer transcript_replayed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", transcript_replayed.value);
    try std.testing.expectEqual(@as(usize, 3), transcript_replayed.audit.replayed_response_count);
}

test "replay handoff replays completed run without native handler calls" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    const report = handoff.preflight(fixtures.Ports.Target, PortsReplayEnv, .accept_replay);
    try std.testing.expect(report.accepted);
    const replay_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
    });
    const replay_permit_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsReplayEnv, .accept_replay, replay_permit);
    try std.testing.expect(!replay_permit_report.accepted);
    const replay_accept_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_replay_adapters = true,
        .allow_handoff_accept = true,
        .require_portable_value_images = true,
        .reject_native_only_values = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const replay_accept_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_accept_policy,
        .transcript_image_available = true,
        .handoff_policy = .allow,
    });
    const replay_accept_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsReplayEnv, .accept_replay, replay_accept_permit);
    try std.testing.expect(replay_accept_report.accepted);
    const replay_budget_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_accept_policy,
        .budget = world.Budget.init(.{ .max_replay_calls = 0 }),
        .transcript_image_available = true,
        .handoff_policy = .allow,
    });
    const replay_budget_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsReplayEnv, .accept_replay, replay_budget_deny_permit);
    try std.testing.expect(!replay_budget_deny_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, replay_budget_deny_report.blockers[0]);
    const replay_step_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_accept_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 1 }),
        .transcript_image_available = true,
        .handoff_policy = .allow,
    });
    const replay_step_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsReplayEnv, .accept_replay, replay_step_deny_permit);
    try std.testing.expect(!replay_step_deny_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, replay_step_deny_report.blockers[0]);
    const fresh_report = handoff.preflight(fixtures.Ports.Target, PortsEnv, .accept_fresh);
    try std.testing.expect(!fresh_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.HandoffPendingFrameMismatch, fresh_report.blockers[0]);
    var rejected_resume_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rejected_resume_runtime.deinit();
    try std.testing.expectError(error.InvalidMode, handoff.@"resume"(fixtures.Ports.Target, PortsReplayEnv, &rejected_resume_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
    }, .accept_replay));
    var rejected_fresh_runtime = boundary.Runtime.init(std.testing.allocator);
    defer rejected_fresh_runtime.deinit();
    var rejected_fresh_ctx: PortsCtx = .{};
    try std.testing.expectError(error.HandoffPendingFrameMismatch, handoff.@"resume"(fixtures.Ports.Target, PortsEnv, &rejected_fresh_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &rejected_fresh_ctx,
    }, .accept_fresh));
    try std.testing.expectEqual(@as(usize, 0), rejected_fresh_ctx.calls);

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var replayed = try PortsReplayMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replayed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), replayed.value);
    try std.testing.expectEqual(@as(usize, 1), replayed.audit.replayed_response_count);
}

test "verify handoff detects changed fixture handler behavior" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();
    try std.testing.expect(handoff.preflight(fixtures.Ports.Target, PortsEnv, .accept_verify).accepted);
    const verify_accept_policy = world.SupervisionPolicy.init(.{
        .allow_verify_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const verify_response_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .verify,
        .policy = verify_accept_policy,
        .budget = world.Budget.init(.{ .max_port_responses = 1 }),
        .transcript_image_available = true,
        .handoff_policy = .allow,
    });
    const verify_response_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_verify, verify_response_deny_permit);
    try std.testing.expect(!verify_response_deny_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, verify_response_deny_report.blockers[0]);

    var ok_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ok_runtime.deinit();
    var ok_ctx: PortsCtx = .{};
    var verified = try PortsMachineEnv.run(&ok_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ok_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer verified.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), verified.value);

    handoff.run_image.transcript_image.?.resetReplay();
    var bad_runtime = boundary.Runtime.init(std.testing.allocator);
    defer bad_runtime.deinit();
    var bad_ctx: PortsCtx = .{ .response = 99 };
    try std.testing.expectError(error.VerifyDivergence, PortsMachineEnv.run(&bad_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &bad_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    }));
}

test "runspace completed replay installs charge terminal supervision step" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const replay_install_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_replay_adapters = true,
        .require_portable_value_images = true,
        .reject_native_only_values = true,
        .require_environment_certificate = false,
        .require_transcript_image_for_replay = true,
    });
    const terminal_step_limited_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_install_policy,
        .budget = world.Budget.init(.{ .max_session_steps = 1 }),
        .transcript_image_available = true,
    });
    var runspace = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer runspace.deinit();
    try std.testing.expectError(error.BudgetExceeded, runspace.installReplay(fixtures.Ports.Target, image, terminal_step_limited_permit));

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const transcriptless_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const transcriptless_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = transcriptless_state,
        .environment_certificate_fingerprint = PortsReplayEnv.certificate(.replay, true).certificate_fingerprint,
        .acceptance_report_fingerprint = PortsReplayEnv.acceptanceReport(.replay, true).report_fingerprint,
    });
    const admitted_transcript_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_install_policy,
        .transcript_image_available = true,
    });
    const transcriptless_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_7ed1,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = PortsReplayEnv.certificate(.replay, true).certificate_fingerprint,
        .mode = .replay_only,
        .run_image = transcriptless_image,
        .run_permit = admitted_transcript_permit,
    });
    var admitted_runspace = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer admitted_runspace.deinit();
    try std.testing.expectError(error.SupervisionDenied, admitted_runspace.installAdmitted(transcriptless_admitted));
}

test "runspace replay install derives state evidence from selected replay window" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    _ = try appendPortsSourceRun(&transcript, 10, 0xaaa0, 0xaaa1);
    const selected_response = try appendPortsSourceRun(&transcript, 0, 0xbbb0, 0xbbb1);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.native_compatible });
    defer image.deinit(std.testing.allocator);

    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    const handle = try runspace.installReplay(fixtures.Ports.Target, image, null);
    var exported = try runspace.exportRun(handle);
    defer exported.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), exported.current_state.turn_index);
    try std.testing.expectEqual(selected_response.frame_fingerprint, exported.current_state.final_response_fingerprint.?);
}

test "runspace admitted verify installs charge verification response" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);

    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .completed_run);
    const verify_accept_policy = world.SupervisionPolicy.init(.{
        .allow_verify_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const response_limited_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .verify,
        .policy = verify_accept_policy,
        .budget = world.Budget.init(.{ .max_port_responses = 1 }),
        .transcript_image_available = true,
        .handoff_policy = .allow,
    });
    const admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_7ed0,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = PortsEnv.certificate(.verify, true).certificate_fingerprint,
        .mode = .verify_only,
        .run_image = run_image,
        .transcript_image = image,
        .run_permit = response_limited_permit,
    });

    var runspace = world.Runspace.init(std.testing.allocator, .{ .require_supervision = true });
    defer runspace.deinit();
    try std.testing.expectError(error.BudgetExceeded, runspace.installAdmitted(admitted));
}

test "branch handoff metadata roundtrips and parent transcript is not mutated" {
    var baseline = try runAgentScenario(std.testing.allocator, .skeleton);
    defer baseline.fresh_result.deinit(std.testing.allocator);
    defer baseline.replay_result.deinit(std.testing.allocator);
    defer baseline.transcript.deinit();
    var image = try baseline.transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const original_event_count = baseline.transcript.events.items.len;
    const checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .event_index = 2,
        .turn_index = image.events[1].turn_index orelse 0,
        .current_request_fingerprint = image.events[1].request_fingerprint,
        .transcript_prefix_fingerprint = image.events[1].event_fingerprint,
        .branch_id = 1,
        .status = .parked_on_port,
    });
    const branch = world.Timeline.Branch{
        .branch_id = 2,
        .parent_branch_id = 1,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .branch_label = "agent-branch",
        .start_event_index = checkpoint.event_index,
        .final_event_index = image.events.len,
        .final_status = .completed,
        .event_count = image.events.len - checkpoint.event_index,
        .response_count = image.response_count,
    };
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = branch.branch_id,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.branches.len);
    try std.testing.expectEqual(branch.fingerprint(), decoded.branches[0].fingerprint());
    try std.testing.expectEqual(original_event_count, baseline.transcript.events.items.len);

    const invalid_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .branch_id = 99,
        .checkpoint_fingerprint = checkpoint.checkpoint_fingerprint + 1,
        .status = .completed,
    });
    const invalid_branch_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Agent.Target).import_set_fingerprint,
        .transcript_image = image,
        .current_state = invalid_state,
        .checkpoints = &.{checkpoint},
        .branches = @constCast(&[_]world.Timeline.Branch{branch}),
    });
    try std.testing.expectError(error.HandoffCheckpointMismatch, invalid_branch_image.validate(.{}));
}

test "agent handoff replay works without model or tool handler calls" {
    var run = try runAgentScenario(std.testing.allocator, .skeleton);
    defer run.fresh_result.deinit(std.testing.allocator);
    defer run.replay_result.deinit(std.testing.allocator);
    defer run.transcript.deinit();
    var image = try run.transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Agent.Target, image, .replay_only_run);
    const encoded = try run_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();

    var replay_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_runtime.deinit();
    var replay_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    var replay = try AgentMachine.run(&replay_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &replay_ctx,
        .transcript_image = &handoff.run_image.transcript_image.?,
    });
    defer replay.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", replay.value);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), replay_ctx.tool_calls);
}

test "run permit fingerprint stable binds target environment policy budget cost model and excludes runtime tokens" {
    const budget = world.Budget.init(.{ .max_port_requests = 3 });
    const cost_model = world.CostModel.init(.{ .fresh_call_cost = 7 });
    const permit_a = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = budget,
        .cost_model = cost_model,
        .label = "permit-a",
    });
    const permit_b = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = budget,
        .cost_model = cost_model,
        .label = "permit-a",
    });
    const changed_budget = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 4 }),
        .cost_model = cost_model,
        .label = "permit-a",
    });
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const cert = PortsEnv.certificate(.fresh, false);
    try std.testing.expectEqual(permit_a.permit_fingerprint, permit_b.permit_fingerprint);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, permit_a.target_ref_fingerprint);
    try std.testing.expectEqual(cert.certificate_fingerprint, permit_a.environment_certificate_fingerprint);
    try std.testing.expectEqual(world.SupervisionPolicy.strict_fresh.policy_fingerprint, permit_a.supervision_policy_fingerprint);
    try std.testing.expectEqual(budget.budget_fingerprint, permit_a.budget_fingerprint);
    try std.testing.expectEqual(cost_model.cost_model_fingerprint, permit_a.cost_model_fingerprint);
    try std.testing.expect(permit_a.permit_fingerprint != changed_budget.permit_fingerprint);
}

test "run permit validation rejects nested policy budget cost and rule drift" {
    const mode_denied_policy = world.SupervisionPolicy.init(.{ .require_environment_certificate = false });
    const mode_denied_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = mode_denied_policy,
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, mode_denied_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .max_requests = 1,
    })};
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
        .cost_model = world.CostModel.init(.{ .fresh_call_cost = 1 }),
        .port_rules = &rules,
    });

    var forged_budget = permit;
    forged_budget.budget.max_port_requests = 100;
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, forged_budget, fixtures.Ports.Target.WorldPortTable.entries.len));

    var forged_policy = permit;
    forged_policy.policy.allow_native_adapters = false;
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, forged_policy, fixtures.Ports.Target.WorldPortTable.entries.len));

    var forged_cost = permit;
    forged_cost.cost_model.fresh_call_cost = 100;
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, forged_cost, fixtures.Ports.Target.WorldPortTable.entries.len));

    var forged_rules = rules;
    forged_rules[0].max_requests = 10;
    var forged_rule_permit = permit;
    forged_rule_permit.port_rules = &forged_rules;
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, forged_rule_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const replay_without_image_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
    });
    try std.testing.expectError(error.TranscriptImageRequired, world.Supervisor.init(std.testing.allocator, replay_without_image_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const verify_without_image_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .verify,
        .policy = world.SupervisionPolicy.verify_replay,
    });
    try std.testing.expectError(error.TranscriptImageRequired, world.Supervisor.init(std.testing.allocator, verify_without_image_permit, fixtures.Ports.Target.WorldPortTable.entries.len));
}

test "supervision policy denies native fresh calls and pending by default" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.FreshCallDenied, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expect(!world.Supervision.responseAllowedByPolicy(world.SupervisionPolicy.strict_fresh, .pending));
    try std.testing.expect(world.Supervision.adapterAllowedByPolicy(world.SupervisionPolicy.strict_replay, .replay));
}

test "port rules enforce portable values and rule-owned caps" {
    const audit_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .allowed_modes = world.Supervision.AllowedModes{ .audit = true },
        .allow_fresh = false,
    })};
    const audit_policy = world.SupervisionPolicy.init(.{
        .allow_audit_only = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const audit_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .audit,
        .policy = audit_policy,
        .port_rules = &audit_rules,
    });
    var audit_supervisor = try world.Supervisor.init(std.testing.allocator, audit_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer audit_supervisor.deinit();
    try audit_supervisor.beforeAdapterCall(.{ .world_port_id = 0, .mode = .audit, .adapter_kind = .native });

    const portable_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .require_portable_values = true,
    })};
    const portable_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &portable_rules,
    });
    var portable_supervisor = try world.Supervisor.init(std.testing.allocator, portable_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer portable_supervisor.deinit();
    try std.testing.expectError(error.PortableValueRequired, portable_supervisor.beforeAdapterCall(.{
        .world_port_id = 0,
        .mode = .fresh,
        .adapter_kind = .native,
        .value_policy = .native_compatible,
    }));

    const request_cap_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .max_requests = 0,
    })};
    const request_cap_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &request_cap_rules,
    });
    var request_cap_supervisor = try world.Supervisor.init(std.testing.allocator, request_cap_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer request_cap_supervisor.deinit();
    const request_cap_fingerprint = request_cap_supervisor.ledger.ledger_fingerprint;
    try std.testing.expectError(error.PortRuleDenied, request_cap_supervisor.beforePortRequest(0, 0, 0));
    try std.testing.expectEqual(request_cap_fingerprint, request_cap_supervisor.ledger.ledger_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), request_cap_supervisor.ledger.per_port_usage[0].requests);

    const image_cap_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .max_payload_image_bytes = 1,
        .max_response_image_bytes = 1,
    })};
    const image_cap_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &image_cap_rules,
    });
    var payload_cap_supervisor = try world.Supervisor.init(std.testing.allocator, image_cap_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer payload_cap_supervisor.deinit();
    try payload_cap_supervisor.beforePortRequest(0, 0, 0);
    const payload_cap_fingerprint = payload_cap_supervisor.ledger.ledger_fingerprint;
    try std.testing.expectError(error.PortRuleDenied, payload_cap_supervisor.accountPortRequestBytes(0, 8, 2));
    try std.testing.expectEqual(payload_cap_fingerprint, payload_cap_supervisor.ledger.ledger_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), payload_cap_supervisor.ledger.per_port_usage[0].value_image_bytes);

    var response_cap_supervisor = try world.Supervisor.init(std.testing.allocator, image_cap_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer response_cap_supervisor.deinit();
    try std.testing.expectError(error.PortRuleDenied, response_cap_supervisor.afterAdapterResponse(.{
        .world_port_id = 0,
        .status = .responded,
        .value_image_bytes = 2,
    }));

    const authority_deny_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .allowed_authority_kinds = world.Supervision.AllowedAuthorityKinds.fixtures,
    })};
    const authority_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &authority_deny_rules,
    });
    var authority_deny_supervisor = try world.Supervisor.init(std.testing.allocator, authority_deny_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer authority_deny_supervisor.deinit();
    try std.testing.expectError(error.AuthorityDenied, authority_deny_supervisor.beforeAdapterCall(.{
        .world_port_id = 0,
        .mode = .fresh,
        .adapter_kind = .native,
    }));
}

test "supervisor rejects out-of-range port ids before ledger access" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    const invalid_port_id: u32 = fixtures.Ports.Target.WorldPortTable.entries.len;
    const ledger_fingerprint = supervisor.ledger.ledger_fingerprint;

    try std.testing.expectError(error.SupervisionDenied, supervisor.beforePortRequest(invalid_port_id, 0, 0));
    try std.testing.expectError(error.SupervisionDenied, supervisor.accountPortRequestBytes(invalid_port_id, 0, 0));
    try std.testing.expectError(error.SupervisionDenied, supervisor.beforeAdapterCall(.{
        .world_port_id = invalid_port_id,
        .mode = .fresh,
        .adapter_kind = .native,
    }));
    try std.testing.expectError(error.SupervisionDenied, supervisor.afterAdapterResponse(.{
        .world_port_id = invalid_port_id,
        .status = .responded,
    }));
    try std.testing.expectEqual(ledger_fingerprint, supervisor.ledger.ledger_fingerprint);
    try std.testing.expectEqual(@as(?world.SupervisionCheck, null), supervisor.last_check);
}

test "supervised frame request bytes are accounted before frame handoff" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_frame_request_bytes = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    try std.testing.expectError(error.BudgetExceeded, run.nextFrame());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "supervised frame handoff enforces adapter budget before exposing request" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_fresh_calls = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    try std.testing.expectError(error.BudgetExceeded, run.nextFrame());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "supervised direct dispatch accounts request frame bytes before handler" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_frame_request_bytes = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "supervised frame response bytes are accounted before framed resume" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer request.deinit(std.testing.allocator);
    const ledger_before_invalid_frame = run.supervisor.?.ledger.ledger_fingerprint;
    var wrong_value_table_response = try world.Frame.Response.fromValue(std.testing.allocator, request, null, 0x1234, .@"resume", @as(i32, 7), .portable);
    defer wrong_value_table_response.deinit(std.testing.allocator);
    try std.testing.expectError(error.FrameValueTableMismatch, run.resumeFrame(wrong_value_table_response));
    try std.testing.expectEqual(ledger_before_invalid_frame, run.supervisor.?.ledger.ledger_fingerprint);
    try std.testing.expectEqual(@as(?world.Supervision.BudgetExceededKind, null), run.supervisor.?.ledger.exceeded_budget);
    var response = try world.Frame.Response.fromValue(std.testing.allocator, request, 1, 0x1234, .@"resume", @as(i32, 7), .portable);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectError(error.BudgetExceeded, run.resumeFrame(response));
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.frame_response_bytes, run.supervisor.?.ledger.exceeded_budget.?);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "supervised pending frame responses are accounted before parking" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_pending_responses = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer request.deinit(std.testing.allocator);
    const ledger_before_pending = run.supervisor.?.ledger.ledger_fingerprint;
    const pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint + 1,
        .status = .pending,
        .response_fingerprint = 0,
        .replay_key = 0,
    });
    try std.testing.expectError(error.FrameRequestFingerprintMismatch, run.resumeFrame(pending_response));
    try std.testing.expectEqual(ledger_before_pending, run.supervisor.?.ledger.ledger_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), run.supervisor.?.ledger.total_port_responses);

    const valid_pending_response = world.Frame.Response.init(.{
        .world_surface_fingerprint = request.world_surface_fingerprint,
        .target_certificate_fingerprint = request.target_certificate_fingerprint,
        .world_port_id = request.world_port_id,
        .request_fingerprint = request.request_fingerprint,
        .status = .pending,
        .response_fingerprint = 0,
        .replay_key = 0,
    });
    try std.testing.expectError(error.HandlerPending, run.resumeFrame(valid_pending_response));
    try std.testing.expect(run.supervisor.?.ledger.ledger_fingerprint != ledger_before_pending);
    try std.testing.expectEqual(@as(usize, 1), run.supervisor.?.ledger.total_port_responses);
    try std.testing.expectEqual(@as(usize, 1), run.supervisor.?.ledger.total_pending_calls);
    try std.testing.expectEqual(@as(usize, 1), run.supervisor.?.ledger.per_port_usage[0].pending_calls);
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "supervised replay accounts transcript image response frame bytes" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 1 }),
        .transcript_image_available = true,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var run = try PortsReplayMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &image,
        .permit = permit,
    });
    defer run.deinit();
    var request = switch (try run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer request.deinit(std.testing.allocator);
    try std.testing.expectError(error.BudgetExceeded, run.dispatch());
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.frame_response_bytes, run.supervisor.?.ledger.exceeded_budget.?);
}

test "supervised verify accounts transcript image response frame bytes" {
    var live_transcript = world.Transcript.init(std.testing.allocator);
    defer live_transcript.deinit();
    try recordPortsTranscript(&live_transcript);
    const live_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_verify_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = false,
    });
    const live_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .verify,
        .policy = live_policy,
        .budget = world.Budget.init(.{ .max_port_responses = 0 }),
        .transcript_image_available = true,
    });
    var live_runtime = boundary.Runtime.init(std.testing.allocator);
    defer live_runtime.deinit();
    var live_ctx: PortsCtx = .{};
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&live_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &live_ctx,
        .transcript = &live_transcript,
        .permit = live_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), live_ctx.calls);

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_verify_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .verify,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 1 }),
        .transcript_image_available = true,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.verify,
        .ctx = &ctx,
        .transcript_image = &image,
        .permit = permit,
    });
    defer run.deinit();
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try std.testing.expectError(error.BudgetExceeded, run.dispatch());
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.frame_response_bytes, run.supervisor.?.ledger.exceeded_budget.?);
}

test "supervised fresh accounts native transcript response frame bytes" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
        .permit = permit,
    });
    defer run.deinit();
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try std.testing.expectError(error.BudgetExceeded, run.dispatch());
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.frame_response_bytes, run.supervisor.?.ledger.exceeded_budget.?);
}

test "supervised fresh accounts native response frame bytes without transcripts" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_frame_response_bytes = 1 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    }));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}

test "budget zero port budget denies first port and usage ledger records cost model units" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
        .cost_model = world.CostModel.init(.{ .port_request_base_cost = 5 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
}

test "response byte costs are charged to per-port cost budgets" {
    const per_port_budget = [_]world.Supervision.PerPortBudget{.{
        .world_port_id = 0,
        .max_cost_units = 1,
    }};
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .per_port_budgets = &per_port_budget }),
        .cost_model = world.CostModel.init(.{
            .port_request_base_cost = 0,
            .port_response_base_cost = 0,
            .frame_byte_cost = 1,
        }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try std.testing.expectError(error.BudgetExceeded, supervisor.afterAdapterResponse(.{
        .world_port_id = 0,
        .status = .responded,
        .response_bytes = 2,
    }));
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.per_port_cost_units, supervisor.ledger.exceeded_budget.?);
}

test "audit-only budget checks refresh fingerprints after allowing the check" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .audit_only_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforePortRequest(0, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), supervisor.warning_count);
    try std.testing.expectEqual(@as(?world.Supervision.Blocker, null), supervisor.blocker);
    try std.testing.expect(supervisor.last_check.?.allowed);
    try std.testing.expect(supervisor.last_check.?.validateFingerprint());
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const receipt = supervisor.receipt(.completed, state.run_state_fingerprint, null, null);
    try std.testing.expectEqual(@as(?world.Supervision.Blocker, null), receipt.blocker);
    try std.testing.expectEqual(@as(usize, 1), receipt.warning_count);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.port_requests, receipt.exceeded_budget.?);
}

test "cost model and port rule enforce per-port budgets and response status" {
    const per_port_budget = [_]world.Supervision.PerPortBudget{.{
        .world_port_id = 0,
        .max_requests = 1,
        .max_cost_units = 10,
    }};
    const per_port_cost = [_]world.Supervision.PerPortCost{.{
        .world_port_id = 0,
        .port_request_base_cost = 3,
        .fresh_call_cost = 4,
    }};
    const rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .allowed_adapter_kinds = world.Supervision.AllowedAdapterKinds.fresh_native,
        .allowed_modes = world.Supervision.AllowedModes.fresh_only,
        .allow_fail = false,
    })};
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .per_port_budgets = &per_port_budget }),
        .cost_model = world.CostModel.init(.{ .per_port_costs = &per_port_cost }),
        .port_rules = &rules,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforePortRequest(0, 0, 0);
    try supervisor.beforeAdapterCall(.{
        .world_port_id = 0,
        .mode = .fresh,
        .adapter_kind = .native,
        .authority_kind = .native_function,
    });
    try std.testing.expectEqual(@as(u64, 7), supervisor.ledger.per_port_usage[0].cost_units);
    try std.testing.expectError(error.HandlerFailed, supervisor.afterAdapterResponse(.{
        .world_port_id = 0,
        .status = .failed,
    }));
}

test "supervised transcript appends enforce event and image budgets" {
    const event_budget_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_transcript_events = 1 }),
    });
    var event_runtime = boundary.Runtime.init(std.testing.allocator);
    defer event_runtime.deinit();
    var event_ctx: PortsCtx = .{};
    var event_transcript = world.Transcript.init(std.testing.allocator);
    defer event_transcript.deinit();
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&event_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &event_ctx,
        .transcript = &event_transcript,
        .permit = event_budget_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), event_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), event_transcript.events.items.len);
    try std.testing.expectError(error.ReplayMissing, event_transcript.validateReplayRun(
        fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        fixtures.Ports.Target.Certificate.certificate_fingerprint,
    ));

    const image_budget_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_transcript_image_bytes = 1 }),
    });
    var image_runtime = boundary.Runtime.init(std.testing.allocator);
    defer image_runtime.deinit();
    var image_ctx: PortsCtx = .{};
    var image_transcript = world.Transcript.init(std.testing.allocator);
    defer image_transcript.deinit();
    try std.testing.expectError(error.BudgetExceeded, PortsMachineEnv.run(&image_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &image_ctx,
        .transcript = &image_transcript,
        .permit = image_budget_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), image_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), image_transcript.events.items.len);
}

test "park-on-budget returns parked run state instead of failing" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_session_steps = 0 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    switch (try run.next()) {
        .parked => {},
        else => return error.ExpectedParked,
    }
    try std.testing.expectEqual(@as(usize, 0), ctx.calls);
    try std.testing.expectEqual(world.AuditReport.Status.parked, run.audit.final_status);
}

test "park-on-budget preserves parked state when completion transcript exceeds budget" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .park_on_budget_exceeded = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .budget = world.Budget.init(.{ .max_transcript_events = 4 }),
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
        .permit = permit,
    });
    defer run.deinit();
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try run.dispatch();
    switch (try run.next()) {
        .parked => {},
        else => return error.ExpectedParked,
    }
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(world.AuditReport.Status.parked, run.audit.final_status);
    try std.testing.expectEqual(@as(usize, 4), transcript.events.items.len);
}

test "max supervision events is enforced before recording another check" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .max_supervision_events = 1,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforeSessionStep();
    try std.testing.expectEqual(@as(usize, 1), supervisor.supervision_event_count);
    try std.testing.expectEqual(@as(usize, 1), supervisor.ledger.total_session_steps);
    try std.testing.expectError(error.BudgetExceeded, supervisor.beforeSessionStep());
    try std.testing.expectEqual(@as(usize, 1), supervisor.supervision_event_count);
    try std.testing.expectEqual(@as(usize, 1), supervisor.ledger.total_session_steps);
    try std.testing.expectEqual(world.Supervision.Blocker.max_supervision_events_exceeded, supervisor.last_check.?.blocker.?);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.supervision_events, supervisor.last_check.?.budget_exceeded.?);
    try std.testing.expect(supervisor.last_check.?.validateFingerprint());

    try std.testing.expectError(error.BudgetExceeded, supervisor.beforePortRequest(0, 0, 0));
    try std.testing.expectEqual(@as(usize, 0), supervisor.ledger.per_port_usage[0].requests);
}

test "audit-only max supervision events warns and allows checks" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .audit_only_on_budget_exceeded = true,
        .max_supervision_events = 1,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforeSessionStep();
    try supervisor.beforeSessionStep();
    try std.testing.expectEqual(@as(usize, 1), supervisor.supervision_event_count);
    try std.testing.expectEqual(@as(usize, 2), supervisor.ledger.total_session_steps);
    try std.testing.expectEqual(@as(usize, 1), supervisor.warning_count);
    try std.testing.expectEqual(@as(?world.Supervision.Blocker, null), supervisor.blocker);
    try std.testing.expect(supervisor.last_check.?.allowed);
    try std.testing.expectEqual(world.Supervision.Blocker.max_supervision_events_exceeded, supervisor.last_check.?.blocker.?);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.supervision_events, supervisor.last_check.?.budget_exceeded.?);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.supervision_events, supervisor.ledger.exceeded_budget.?);
    try std.testing.expect(supervisor.last_check.?.validateFingerprint());
}

test "permit validation binds port rules to target surface and range" {
    const wrong_surface_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint + 1,
        .world_port_id = 0,
        .max_requests = 1,
    })};
    const wrong_surface_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &wrong_surface_rules,
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, wrong_surface_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const out_of_range_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = @as(u32, @intCast(fixtures.Ports.Target.WorldPortTable.entries.len)),
        .max_requests = 1,
    })};
    const out_of_range_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &out_of_range_rules,
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, out_of_range_permit, fixtures.Ports.Target.WorldPortTable.entries.len));
    const out_of_range_budgets = [_]world.Supervision.PerPortBudget{.{
        .world_port_id = @as(u32, @intCast(fixtures.Ports.Target.WorldPortTable.entries.len)),
        .max_requests = 1,
    }};
    const out_of_range_budget_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .per_port_budgets = &out_of_range_budgets }),
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, out_of_range_budget_permit, fixtures.Ports.Target.WorldPortTable.entries.len));
    const out_of_range_costs = [_]world.Supervision.PerPortCost{.{
        .world_port_id = @as(u32, @intCast(fixtures.Ports.Target.WorldPortTable.entries.len)),
        .fresh_call_cost = 0,
    }};
    const out_of_range_cost_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .cost_model = world.CostModel.init(.{ .per_port_costs = &out_of_range_costs }),
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, out_of_range_cost_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const duplicate_rules = [_]world.PortRule{
        world.PortRule.init(.{
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
            .world_port_id = 0,
            .max_requests = 1,
        }),
        world.PortRule.init(.{
            .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
            .world_port_id = 0,
            .max_requests = 2,
        }),
    };
    const duplicate_rule_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .port_rules = &duplicate_rules,
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, duplicate_rule_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const duplicate_budgets = [_]world.Supervision.PerPortBudget{
        .{ .world_port_id = 0, .max_requests = 1 },
        .{ .world_port_id = 0, .max_requests = 2 },
    };
    const duplicate_budget_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .per_port_budgets = &duplicate_budgets }),
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, duplicate_budget_permit, fixtures.Ports.Target.WorldPortTable.entries.len));

    const duplicate_costs = [_]world.Supervision.PerPortCost{
        .{ .world_port_id = 0, .fresh_call_cost = 1 },
        .{ .world_port_id = 0, .fresh_call_cost = 2 },
    };
    const duplicate_cost_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .cost_model = world.CostModel.init(.{ .per_port_costs = &duplicate_costs }),
    });
    try std.testing.expectError(error.SupervisionDenied, world.Supervisor.init(std.testing.allocator, duplicate_cost_permit, fixtures.Ports.Target.WorldPortTable.entries.len));
}

test "per-port byte and status cost overrides are honored" {
    const per_port_cost = [_]world.Supervision.PerPortCost{.{
        .world_port_id = 0,
        .port_request_base_cost = 0,
        .port_response_base_cost = 0,
        .frame_byte_cost = 2,
        .value_image_byte_cost = 3,
        .pending_call_cost = 4,
    }};
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_pending_responses = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
        .cost_model = world.CostModel.init(.{
            .frame_byte_cost = 1,
            .value_image_byte_cost = 1,
            .pending_call_cost = 1,
            .per_port_costs = &per_port_cost,
        }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforePortRequest(0, 0, 0);
    try supervisor.accountPortRequestBytes(0, 2, 3);
    try std.testing.expectEqual(@as(u64, 13), supervisor.ledger.per_port_usage[0].cost_units);
    try supervisor.afterAdapterResponse(.{
        .world_port_id = 0,
        .status = .pending,
        .response_bytes = 5,
        .value_image_bytes = 7,
    });
    try std.testing.expectEqual(@as(u64, 48), supervisor.ledger.per_port_usage[0].cost_units);
}

test "mode-denied supervision checks preserve requested mode blocker" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = policy,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try std.testing.expectError(error.ReplayCallDenied, supervisor.beforeAdapterCall(.{
        .world_port_id = 0,
        .mode = .replay,
        .adapter_kind = .native,
    }));
    try std.testing.expectEqual(world.Supervision.Blocker.replay_call_denied, supervisor.last_check.?.blocker.?);
    try std.testing.expectError(error.SupervisionDenied, supervisor.beforeAdapterCall(.{
        .world_port_id = 0,
        .mode = .verify,
        .adapter_kind = .native,
    }));
    try std.testing.expectEqual(world.Supervision.Blocker.verify_call_denied, supervisor.last_check.?.blocker.?);
}

test "supervision preflight rejects policies that disable requested mode" {
    const policy = world.SupervisionPolicy.init(.{
        .allow_native_adapters = true,
        .require_environment_certificate = true,
    });
    const report = PortsEnv.acceptanceReportWithSupervision(.fresh, false, policy);
    try std.testing.expect(!report.accepted);
    try std.testing.expectEqual(@as(usize, 1), report.blockers.len);
    try std.testing.expectEqual(world.AcceptanceBlocker.FreshCallDenied, report.blockers[0]);
}

test "permit acceptance report rejects mismatched permit authority" {
    const broad_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_replay_calls = true,
        .allow_native_adapters = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = false,
    });
    const fresh_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = broad_policy,
    });
    const mode_mismatch = PortsEnv.acceptanceReportWithPermit(.replay, false, fresh_permit);
    try std.testing.expect(!mode_mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionPolicyMismatch, mode_mismatch.blockers[0]);

    const replay_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_native_adapters = true,
        .allow_replay_adapters = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = false,
    });
    const replay_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = replay_policy,
    });
    const environment_mismatch = PortsEnv.acceptanceReportWithPermit(.replay, false, replay_permit);
    try std.testing.expect(!environment_mismatch.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionPolicyMismatch, environment_mismatch.blockers[0]);
}

test "supervision replay permits requiring transcript images reject live transcript only runs" {
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .replay,
        .policy = world.SupervisionPolicy.strict_replay,
        .transcript_image_available = true,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.TranscriptImageRequired, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
        .transcript = &transcript,
        .permit = permit,
    }));
}

test "native handler failures are accounted by supervision" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, FailingPortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try FailingPortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer run.deinit();
    switch (try run.next()) {
        .port_required => {},
        else => return error.ExpectedPortRequired,
    }
    try std.testing.expectError(error.HandlerFailed, run.dispatch());
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(world.Supervision.Blocker.failed_denied, run.supervisor.?.last_check.?.blocker.?);
}

test "usage ledger supervision check and run receipt fingerprints are stable" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 2, .max_total_cost_units = 100 }),
        .admission_receipt_fingerprint = 0xabc,
        .module_ref_fingerprint = 0xdef,
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    const before = supervisor.ledger.ledger_fingerprint;
    try supervisor.beforeSessionStep();
    try supervisor.beforePortRequest(0, 0, 0);
    try supervisor.beforeAdapterCall(.{ .world_port_id = 0, .mode = .fresh, .adapter_kind = .native });
    try supervisor.afterAdapterResponse(.{ .world_port_id = 0, .status = .responded });
    const check = supervisor.last_check.?;
    try std.testing.expect(check.allowed);
    try std.testing.expect(check.check_fingerprint != before);
    try std.testing.expectEqual(@as(usize, 1), supervisor.ledger.total_session_steps);
    try std.testing.expectEqual(@as(usize, 1), supervisor.ledger.total_port_requests);
    try std.testing.expectEqual(@as(usize, 1), supervisor.ledger.total_fresh_calls);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = permit.target_ref_fingerprint,
        .status = .completed,
    });
    const receipt_a = supervisor.receipt(.completed, state.run_state_fingerprint, null, null);
    const receipt_b = supervisor.receipt(.completed, state.run_state_fingerprint, null, null);
    try std.testing.expectEqual(receipt_a.receipt_fingerprint, receipt_b.receipt_fingerprint);
    try std.testing.expectEqual(supervisor.ledger.ledger_fingerprint, receipt_a.usage_ledger_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xabc), receipt_a.admission_receipt_fingerprint);
    try std.testing.expectEqual(@as(?u64, 0xdef), receipt_a.module_ref_fingerprint);
    try std.testing.expectEqual(@as(usize, 1), receipt_a.total_port_requests);
}

test "direct machine start rejects scoped permits" {
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const module_scoped_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.SupervisionDenied, PortsMachineEnv.run(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = module_scoped_permit,
    }));

    const admission_scoped_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .admission_receipt_fingerprint = 0xabc,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var admission_runtime = boundary.Runtime.init(std.testing.allocator);
    defer admission_runtime.deinit();
    try std.testing.expectError(error.SupervisionDenied, PortsMachineEnv.run(&admission_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = admission_scoped_permit,
    }));
}

test "supervision cost overflow saturates into budget exceeded" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_total_cost_units = std.math.maxInt(u64) - 1 }),
        .cost_model = world.CostModel.init(.{ .frame_byte_cost = std.math.maxInt(u64) }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try std.testing.expectError(error.BudgetExceeded, supervisor.beforePortRequest(0, 2, 0));
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.total_cost_units, supervisor.ledger.exceeded_budget.?);
    try std.testing.expectEqual(std.math.maxInt(u64), supervisor.ledger.total_cost_units);
}

test "policy membrane prevents fresh handler calls and run receipt is available after permitted run" {
    const ok_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .budget = world.Budget.init(.{ .max_port_requests = 1, .max_fresh_calls = 1 }),
    });
    var ok_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ok_runtime.deinit();
    var ok_ctx: PortsCtx = .{};
    var ok = try PortsMachineEnv.run(&ok_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ok_ctx,
        .permit = ok_permit,
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 7), ok.value);
    try std.testing.expectEqual(@as(usize, 1), ok_ctx.calls);
    try std.testing.expect(ok.receipt != null);
    try std.testing.expectEqual(world.RunReceipt.FinalStatus.completed, ok.receipt.?.final_status);

    const denied_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = false,
            .require_environment_certificate = true,
        }),
    });
    var denied_runtime = boundary.Runtime.init(std.testing.allocator);
    defer denied_runtime.deinit();
    var denied_ctx: PortsCtx = .{};
    try std.testing.expectError(error.SupervisionDenied, PortsMachineEnv.run(&denied_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &denied_ctx,
        .permit = denied_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), denied_ctx.calls);
}

test "supervised handoff receiver can issue stricter permit and inspect prior receipt refs" {
    const sender_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
    });
    const sender_receipt = world.RunReceipt.init(.{
        .run_permit_fingerprint = sender_permit.permit_fingerprint,
        .environment_certificate_fingerprint = sender_permit.environment_certificate_fingerprint,
        .target_ref_fingerprint = sender_permit.target_ref_fingerprint,
        .usage_ledger_fingerprint = 1,
        .final_run_state_fingerprint = 2,
        .final_status = .parked,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var run = try PortsMachineEnv.start(&runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer run.deinit();
    const step = try run.nextFrame();
    var request_frame = switch (step) {
        .port_request => |frame| frame,
        else => return error.HandoffPendingFrameMismatch,
    };
    defer request_frame.deinit(std.testing.allocator);
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .parked_on_port,
        .pending_request_fingerprint = request_frame.frame_fingerprint,
        .turn_index = request_frame.turn_index,
    });
    const image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request_frame,
        .prior_run_permit_fingerprint = sender_permit.permit_fingerprint,
        .prior_run_receipt_fingerprint = sender_receipt.receipt_fingerprint,
    });
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer handoff.deinit();
    const inspected = handoff.inspectPriorReceipts();
    try std.testing.expectEqual(sender_permit.permit_fingerprint, inspected.prior_run_permit_fingerprint.?);
    try std.testing.expectEqual(sender_receipt.receipt_fingerprint, inspected.prior_run_receipt_fingerprint.?);
    const receiver_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    const report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, receiver_permit);
    try std.testing.expect(report.accepted);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const module_image = image.withModuleRef(module_ref, null);
    const module_encoded = try module_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(module_encoded);
    var module_handoff = try world.Handoff.fromRunImage(std.testing.allocator, module_encoded);
    defer module_handoff.deinit();
    var owned_decoded_image = try world.RunImage.decode(std.testing.allocator, encoded);
    defer owned_decoded_image.deinit(std.testing.allocator);
    var borrowed_module_image = owned_decoded_image.withModuleRef(module_ref, null);
    defer borrowed_module_image.deinit(std.testing.allocator);
    try std.testing.expect(!borrowed_module_image.owns_target_ref_bytes);
    try std.testing.expect(!borrowed_module_image.owns_pending_request_frame);
    const borrowed_module_encoded = try borrowed_module_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(borrowed_module_encoded);
    const module_scoped_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    const module_report = module_handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, module_scoped_permit);
    try std.testing.expect(module_report.accepted);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package_level_module_witness = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = image,
        .requested_mode = .resume_parked,
    });
    const package_level_module_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.init(.{
            .require_supervision_permit = true,
        }),
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package_level_module_witness, .{
        .allocator = std.testing.allocator,
        .permit = module_scoped_permit,
    });
    try std.testing.expect(package_level_module_result.report.accepted);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, package_level_module_result.admitted_run.?.run_image.?.module_ref_fingerprint.?);
    const wrong_module_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint +% 1,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1 }),
    });
    const wrong_module_report = module_handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, wrong_module_permit);
    try std.testing.expect(!wrong_module_report.accepted);
    const unwitnessed_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request_frame,
    });
    const unwitnessed_encoded = try unwitnessed_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(unwitnessed_encoded);
    var unwitnessed_handoff = try world.Handoff.fromRunImage(std.testing.allocator, unwitnessed_encoded);
    defer unwitnessed_handoff.deinit();
    const unwitnessed_report = unwitnessed_handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, receiver_permit);
    try std.testing.expect(unwitnessed_report.accepted);
    const unwitnessed_module_report = unwitnessed_handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, module_scoped_permit);
    try std.testing.expect(!unwitnessed_module_report.accepted);
    const reused_permit_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request_frame,
        .prior_run_permit_fingerprint = receiver_permit.permit_fingerprint,
    });
    const reused_permit_encoded = try reused_permit_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(reused_permit_encoded);
    var reused_permit_handoff = try world.Handoff.fromRunImage(std.testing.allocator, reused_permit_encoded);
    defer reused_permit_handoff.deinit();
    const reused_permit_report = reused_permit_handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, receiver_permit);
    try std.testing.expect(!reused_permit_report.accepted);
    var forged_receiver_permit = receiver_permit;
    forged_receiver_permit.budget.max_port_requests = 99;
    const forged_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, forged_receiver_permit);
    try std.testing.expect(!forged_report.accepted);
    const adapter_deny_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = false,
        .allow_handoff_accept = true,
        .require_environment_certificate = true,
    });
    const adapter_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = adapter_deny_policy,
    });
    const adapter_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, adapter_deny_permit);
    try std.testing.expect(!adapter_deny_report.accepted);
    const rule_deny_rules = [_]world.PortRule{world.PortRule.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_port_id = 0,
        .allow_fresh = false,
    })};
    const rule_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .port_rules = &rule_deny_rules,
    });
    const rule_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, rule_deny_permit);
    try std.testing.expect(!rule_deny_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionPortRuleDenied, rule_deny_report.blockers[0]);
    const cert = PortsEnv.certificate(.fresh, false);
    const wrong_surface_permit = world.RunPermit.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint + 1,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .environment_certificate_fingerprint = cert.certificate_fingerprint,
        .binding_plan_fingerprint = cert.binding_plan_fingerprint,
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
    });
    const wrong_surface_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, wrong_surface_permit);
    try std.testing.expect(!wrong_surface_report.accepted);

    const handoff_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .handoff_policy = .deny,
    });
    const handoff_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, handoff_deny_permit);
    try std.testing.expect(!handoff_deny_report.accepted);
    var deny_policy_runtime = boundary.Runtime.init(std.testing.allocator);
    defer deny_policy_runtime.deinit();
    var deny_policy_ctx: PortsCtx = .{};
    try std.testing.expectError(error.SupervisionDenied, handoff.resumeWithPermit(fixtures.Ports.Target, PortsEnv, &deny_policy_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &deny_policy_ctx,
    }, .accept_fresh, handoff_deny_permit));
    try std.testing.expectEqual(@as(usize, 0), deny_policy_ctx.calls);

    const denying_receiver_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    const denying_receiver_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, denying_receiver_permit);
    try std.testing.expect(!denying_receiver_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, denying_receiver_report.blockers[0]);
    var resume_runtime = boundary.Runtime.init(std.testing.allocator);
    defer resume_runtime.deinit();
    var resume_ctx: PortsCtx = .{};
    try std.testing.expectError(error.BudgetExceeded, handoff.resumeWithPermit(fixtures.Ports.Target, PortsEnv, &resume_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &resume_ctx,
    }, .accept_fresh, denying_receiver_permit));
    try std.testing.expectEqual(@as(usize, 0), resume_ctx.calls);

    const handoff_accept_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_port_requests = 1, .max_handoff_accepts = 0 }),
    });
    const handoff_accept_deny_report = handoff.preflightWithPermit(fixtures.Ports.Target, PortsEnv, .accept_fresh, handoff_accept_deny_permit);
    try std.testing.expect(!handoff_accept_deny_report.accepted);
    try std.testing.expectEqual(world.AcceptanceBlocker.SupervisionBudgetExceeded, handoff_accept_deny_report.blockers[0]);
    var accept_runtime = boundary.Runtime.init(std.testing.allocator);
    defer accept_runtime.deinit();
    var accept_ctx: PortsCtx = .{};
    var accept_transcript = world.Transcript.init(std.testing.allocator);
    defer accept_transcript.deinit();
    try std.testing.expectError(error.BudgetExceeded, handoff.resumeWithPermit(fixtures.Ports.Target, PortsEnv, &accept_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &accept_ctx,
        .transcript = &accept_transcript,
    }, .accept_fresh, handoff_accept_deny_permit));
    try std.testing.expectEqual(@as(usize, 0), accept_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), accept_transcript.events.items.len);

    var options_accept_runtime = boundary.Runtime.init(std.testing.allocator);
    defer options_accept_runtime.deinit();
    var options_accept_ctx: PortsCtx = .{};
    var options_accept_transcript = world.Transcript.init(std.testing.allocator);
    defer options_accept_transcript.deinit();
    try std.testing.expectError(error.BudgetExceeded, handoff.@"resume"(fixtures.Ports.Target, PortsEnv, &options_accept_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &options_accept_ctx,
        .transcript = &options_accept_transcript,
        .permit = handoff_accept_deny_permit,
    }, .accept_fresh));
    try std.testing.expectEqual(@as(usize, 0), options_accept_ctx.calls);
    try std.testing.expectEqual(@as(usize, 0), options_accept_transcript.events.items.len);

    const frame_budget_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.handoff_receiver,
        .budget = world.Budget.init(.{ .max_total_cost_units = 4 }),
    });
    var frame_budget_handoff = try world.Handoff.fromRunImage(std.testing.allocator, encoded);
    defer frame_budget_handoff.deinit();
    var frame_budget_runtime = boundary.Runtime.init(std.testing.allocator);
    defer frame_budget_runtime.deinit();
    var frame_budget_ctx: PortsCtx = .{};
    var frame_budget_run = try frame_budget_handoff.resumeWithPermit(fixtures.Ports.Target, PortsEnv, &frame_budget_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &frame_budget_ctx,
    }, .accept_fresh, frame_budget_permit);
    defer frame_budget_run.deinit();
    try std.testing.expectEqual(@as(usize, 1), frame_budget_run.supervisor.?.ledger.total_handoff_accepts);
    try std.testing.expectEqual(@as(usize, 1), frame_budget_run.supervisor.?.ledger.total_fresh_calls);
    var resumed_frame = switch (try frame_budget_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer resumed_frame.deinit(std.testing.allocator);
    var frame_response = try world.Frame.Response.fromValue(std.testing.allocator, resumed_frame, 1, 0x1234, .@"resume", @as(i32, 7), .portable);
    defer frame_response.deinit(std.testing.allocator);
    try std.testing.expectError(error.BudgetExceeded, frame_budget_run.resumeFrame(frame_response));
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.total_cost_units, frame_budget_run.supervisor.?.ledger.exceeded_budget.?);
}

test "supervised handoff export is charged before encoded bytes are returned" {
    const denied_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_handoff_exports = 0 }),
    });
    var denied_runtime = boundary.Runtime.init(std.testing.allocator);
    defer denied_runtime.deinit();
    var denied_ctx: PortsCtx = .{};
    var denied_run = try PortsMachineEnv.start(&denied_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &denied_ctx,
        .permit = denied_permit,
    });
    defer denied_run.deinit();
    var denied_request = switch (try denied_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer denied_request.deinit(std.testing.allocator);
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const denied_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .parked_on_port,
        .pending_request_fingerprint = denied_request.frame_fingerprint,
        .turn_index = denied_request.turn_index,
    });
    const denied_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = denied_state,
        .pending_request_frame = denied_request,
    });
    try std.testing.expectError(error.BudgetExceeded, denied_run.supervisor.?.encodeHandoffExport(denied_image));
    try std.testing.expectEqual(@as(usize, 1), denied_run.supervisor.?.ledger.total_handoff_exports);

    const allowed_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_handoff_exports = 1 }),
    });
    var allowed_runtime = boundary.Runtime.init(std.testing.allocator);
    defer allowed_runtime.deinit();
    var allowed_ctx: PortsCtx = .{};
    var allowed_run = try PortsMachineEnv.start(&allowed_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &allowed_ctx,
        .permit = allowed_permit,
    });
    defer allowed_run.deinit();
    var allowed_request = switch (try allowed_run.nextFrame()) {
        .port_request => |frame| frame,
        else => return error.ExpectedFrameRequest,
    };
    defer allowed_request.deinit(std.testing.allocator);
    const allowed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .parked_on_port,
        .pending_request_fingerprint = allowed_request.frame_fingerprint,
        .turn_index = allowed_request.turn_index,
    });
    const allowed_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = allowed_state,
        .pending_request_frame = allowed_request,
    });
    const encoded = try allowed_run.supervisor.?.encodeHandoffExport(allowed_image);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(encoded.len > 0);
    try std.testing.expectEqual(@as(usize, 1), allowed_run.supervisor.?.ledger.total_handoff_exports);
}

test "interrupted handoff export still enforces export-specific supervision budgets" {
    const total_cost_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.init(.{
            .allow_fresh_calls = true,
            .allow_native_adapters = true,
            .allow_handoff_export = true,
            .park_on_budget_exceeded = true,
        }),
        .budget = world.Budget.init(.{ .max_total_cost_units = 0 }),
        .cost_model = world.CostModel.init(.{ .handoff_export_cost = 1 }),
    });
    var total_cost_supervisor = try world.Supervisor.init(std.testing.allocator, total_cost_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer total_cost_supervisor.deinit();
    total_cost_supervisor.interrupted = true;
    try std.testing.expectError(error.BudgetExceeded, total_cost_supervisor.beforeInterruptedHandoffExport());
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.total_cost_units, total_cost_supervisor.ledger.exceeded_budget.?);

    const event_policy = world.SupervisionPolicy.init(.{
        .allow_fresh_calls = true,
        .allow_native_adapters = true,
        .allow_handoff_export = true,
        .park_on_budget_exceeded = true,
        .max_supervision_events = 0,
    });
    const event_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = event_policy,
    });
    var event_supervisor = try world.Supervisor.init(std.testing.allocator, event_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer event_supervisor.deinit();
    event_supervisor.interrupted = true;
    try std.testing.expectError(error.BudgetExceeded, event_supervisor.beforeInterruptedHandoffExport());
    try std.testing.expectEqual(world.Supervision.Blocker.max_supervision_events_exceeded, event_supervisor.last_check.?.blocker.?);
}

test "supervised branch and checkpoint budgets are enforced" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.branch_limited,
        .budget = world.Budget.init(.{ .max_checkpoints = 1, .max_branches = 1, .max_branch_depth = 1 }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforeCheckpoint(0);
    try supervisor.beforeBranch(1);
    try std.testing.expectError(error.BudgetExceeded, supervisor.beforeBranch(1));
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.branches, supervisor.ledger.exceeded_budget.?);
    const branch_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.branch_limited,
        .branch_policy = .require_new_permit,
    });
    var branch_supervisor = try world.Supervisor.init(std.testing.allocator, branch_permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer branch_supervisor.deinit();
    try std.testing.expectError(error.BranchDenied, branch_supervisor.beforeBranch(1));
    try std.testing.expectEqual(world.Supervision.Blocker.branch_denied, branch_supervisor.last_check.?.blocker.?);
}

test "checkpoint value image bytes are charged to cost budgets" {
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.branch_limited,
        .budget = world.Budget.init(.{ .max_total_cost_units = 4 }),
        .cost_model = world.CostModel.init(.{
            .checkpoint_cost = 1,
            .value_image_byte_cost = 2,
        }),
    });
    var supervisor = try world.Supervisor.init(std.testing.allocator, permit, fixtures.Ports.Target.WorldPortTable.entries.len);
    defer supervisor.deinit();
    try supervisor.beforeSessionStep();
    try std.testing.expectError(error.BudgetExceeded, supervisor.beforeCheckpoint(2));
    try std.testing.expectEqual(@as(usize, 2), supervisor.ledger.total_value_image_bytes);
    try std.testing.expectEqual(@as(u64, 6), supervisor.ledger.total_cost_units);
    try std.testing.expectEqual(world.Supervision.BudgetExceededKind.total_cost_units, supervisor.ledger.exceeded_budget.?);
}

test "supervised agent run completes under budget and over-budget agent is denied" {
    var ok_runtime = boundary.Runtime.init(std.testing.allocator);
    defer ok_runtime.deinit();
    var ok_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    const ok_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_port_requests = 4, .max_fresh_calls = 4, .max_total_cost_units = 20 }),
    });
    var ok = try AgentMachineEnv.run(&ok_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ok_ctx,
        .permit = ok_permit,
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", ok.value);
    try std.testing.expect(ok.receipt != null);
    try std.testing.expect(ok.receipt.?.total_cost_units <= 20);

    var denied_runtime = boundary.Runtime.init(std.testing.allocator);
    defer denied_runtime.deinit();
    var denied_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    const denied_permit = world.Supervision.issue(fixtures.Agent.Target, AgentEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.agent_fixture,
        .budget = world.Budget.init(.{ .max_port_requests = 0 }),
    });
    try std.testing.expectError(error.BudgetExceeded, AgentMachineEnv.run(&denied_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &denied_ctx,
        .permit = denied_permit,
    }));
    try std.testing.expectEqual(@as(usize, 0), denied_ctx.model_calls);
    try std.testing.expectEqual(@as(usize, 0), denied_ctx.tool_calls);
}

test "transfer package encode/decode roundtrip and manifest fingerprint are stable" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .requested_mode = .local_target_match_only,
        .metadata = "admission package fixture",
    });
    try package.validate(.{});
    const encoded = try package.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Admission.TransferPackage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(package.package_fingerprint, decoded.package_fingerprint);
    try std.testing.expectEqual(package.manifest.manifest_fingerprint, decoded.manifest.manifest_fingerprint);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, decoded.module_ref.?.module_ref_fingerprint);
    try std.testing.expectEqualStrings("admission package fixture", decoded.metadata);
}

test "transfer package rejects malformed and oversized packages" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const envelope_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .local_target_match_only,
    });
    const envelope_encoded = try envelope_package.encode(std.testing.allocator);
    defer std.testing.allocator.free(envelope_encoded);
    try envelope_package.validate(.{ .max_package_bytes = envelope_encoded.len });
    try std.testing.expectError(error.InvalidFrameEncoding, envelope_package.validate(.{ .max_package_bytes = envelope_encoded.len - 1 }));
    const empty_module_reference = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, empty_module_reference.validate(.{}));
    var future_module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    future_module_ref.format_version = world.world_module_ref_format_version + 1;
    const future_module_reference = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = future_module_ref,
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, future_module_reference.validate(.{}));
    const empty_inspect = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .requested_mode = .inspect_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, empty_inspect.validate(.{ .allow_inspect_only = true }));
    const stray_module_bytes = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target),
        .module_image_bytes = "not-a-full-module-package",
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, stray_module_bytes.validate(.{ .allow_full_module = true }));
    const empty_replay = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .requested_mode = .replay_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, empty_replay.validate(.{}));
    const completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
    });
    var future_run_image = completed_image;
    future_run_image.format_version = world.world_run_image_format_version + 100;
    const future_run_image_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .run_image = future_run_image,
        .requested_mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, future_run_image_package.validate(.{}));
    const mismatched_run_kind = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .run_image = completed_image,
        .requested_mode = .resume_parked,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_run_kind.validate(.{}));
    var stale_run_target_ref = completed_image;
    stale_run_target_ref.target_ref.world_surface_fingerprint +%= 1;
    const stale_run_target_ref_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .run_image = stale_run_target_ref,
        .requested_mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, stale_run_target_ref_package.validate(.{}));
    const misleading_reference_kind = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .run_image = completed_image,
        .requested_mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, misleading_reference_kind.validate(.{}));
    const inspect_run_image_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .target_ref = target_ref,
        .run_image = completed_image,
        .requested_mode = .inspect_only,
    });
    try inspect_run_image_package.validate(.{ .allow_inspect_only = true });
    const inspect_run_image_encoded = try inspect_run_image_package.encode(std.testing.allocator);
    defer std.testing.allocator.free(inspect_run_image_encoded);
    try inspect_run_image_package.validate(.{
        .allow_inspect_only = true,
        .max_package_bytes = inspect_run_image_encoded.len,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, inspect_run_image_package.validate(.{
        .allow_inspect_only = true,
        .max_package_bytes = inspect_run_image_encoded.len - 1,
    }));
    const branched_image = world.RunImage.init(.{
        .kind = .branched_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
    });
    const branched_replay_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .run_image = branched_image,
        .requested_mode = .completed_replay,
    });
    try branched_replay_package.validate(.{});

    const full_module_bytes = try fixtures.Ports.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(full_module_bytes);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    var loaded_module = try world.Admission.ModuleGateway.decodeBoundaryModule(fixtures.Ports.Target, std.testing.allocator, full_module_bytes);
    defer loaded_module.deinit();
    const full_module_ref = world.Admission.ModuleGateway.refFromBoundaryModule(loaded_module);
    const unwitnessed_full_module_ref_package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .module_ref = full_module_ref,
        .requested_mode = .inspect_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, unwitnessed_full_module_ref_package.validate(.{
        .allow_full_module = true,
        .allow_inspect_only = true,
    }));
    const run_with_module_image = completed_image.withModuleRef(
        module_ref,
        world.Admission.moduleImageFingerprintForBytes(full_module_bytes),
    );
    const run_module_image_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .module_image_bytes = full_module_bytes,
        .run_image = run_with_module_image,
        .requested_mode = .completed_replay,
    });
    try run_module_image_package.validate(.{ .allow_full_module = true });
    const run_module_bytes_witness = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
        .module_image_fingerprint = world.Admission.moduleImageFingerprintForBytes(full_module_bytes),
    });
    const run_module_bytes_witness_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_image_bytes = full_module_bytes,
        .run_image = run_module_bytes_witness,
        .requested_mode = .completed_replay,
    });
    try run_module_bytes_witness_package.validate(.{ .allow_full_module = true });
    const mismatched_run_module_image_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .module_image_bytes = "not-the-bound-module-image",
        .run_image = run_with_module_image,
        .requested_mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, mismatched_run_module_image_package.validate(.{ .allow_full_module = true }));

    var package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .local_target_match_only,
        .metadata = "tiny",
    });
    try std.testing.expectError(error.InvalidFrameEncoding, package.validate(.{ .max_package_bytes = 1 }));
    var oversized_target_ref = target_ref;
    oversized_target_ref.metadata = "target metadata exceeds the narrow package cap";
    const target_metadata_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = oversized_target_ref,
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, target_metadata_package.validate(.{ .max_package_bytes = 8 }));
    const oversized_module_package = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .target_ref = target_ref,
        .module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target),
        .module_image_bytes = "not-a-full-module-package",
        .requested_mode = .inspect_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, oversized_module_package.validate(.{
        .allow_full_module = true,
        .allow_inspect_only = true,
        .max_module_bytes = 8,
    }));
    var stale_manifest = package;
    stale_manifest.manifest.package_kind = .full_module;
    try std.testing.expectError(error.InvalidFrameEncoding, stale_manifest.validate(.{}));
    var stale_manifest_version = package;
    stale_manifest_version.manifest.format_version +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, stale_manifest_version.validate(.{}));
    package.package_fingerprint +%= 1;
    try std.testing.expectError(error.InvalidFrameEncoding, package.validate(.{}));
}

test "transfer package validates module fingerprints and transcript byte limits" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    var module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    module_ref.import_surface_fingerprint = if (module_ref.import_surface_fingerprint) |fingerprint| fingerprint +% 1 else 1;
    const stale_module_package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, stale_module_package.validate(.{}));

    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    const transcript_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .transcript_image = image,
        .requested_mode = .replay_only,
    });
    const transcript_package_encoded = try transcript_package.encode(std.testing.allocator);
    defer std.testing.allocator.free(transcript_package_encoded);
    try transcript_package.validate(.{ .max_transcript_bytes = encoded.len });
    try transcript_package.validate(.{ .max_package_bytes = transcript_package_encoded.len });
    try std.testing.expectError(error.InvalidFrameEncoding, transcript_package.validate(.{ .max_package_bytes = transcript_package_encoded.len - 1 }));
    try std.testing.expectError(error.InvalidFrameEncoding, transcript_package.validate(.{ .max_transcript_bytes = image.events.len }));

    const embedded_run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run);
    const embedded_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .run_image = embedded_run_image,
        .requested_mode = .replay_only,
    });
    try embedded_package.validate(.{ .max_transcript_bytes = encoded.len });
    try std.testing.expectError(error.InvalidFrameEncoding, embedded_package.validate(.{ .max_transcript_bytes = image.events.len }));
}

test "module ref binds target identity and RunImage module refs decode" {
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    }).withModuleRef(module_ref, null);
    const encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.RunImage.decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 3), decoded.format_version);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, decoded.module_ref_fingerprint.?);
    try std.testing.expectEqual(module_ref.boundary_module_fingerprint, decoded.boundary_module_fingerprint.?);

    const direct_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint,
        .boundary_module_fingerprint = module_ref.boundary_module_fingerprint,
    });
    const direct_encoded = try direct_image.encode(std.testing.allocator);
    defer std.testing.allocator.free(direct_encoded);
    var direct_decoded = try world.RunImage.decode(std.testing.allocator, direct_encoded);
    defer direct_decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 3), direct_decoded.format_version);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, direct_decoded.module_ref_fingerprint.?);
}

test "target registry finds targets and matches module refs" {
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{entry});
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    try std.testing.expect(registry.find(target_ref) != null);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const match = registry.match(target_ref, module_ref);
    try std.testing.expect(match.matched);
    try std.testing.expectEqual(entry.target_ref.target_ref_fingerprint, match.local_target_ref_fingerprint.?);
}

test "target registry keeps scanning after coarse module mismatch" {
    const coarse_entry = world.Admission.TargetRegistry.register(MissingDispatchTarget);
    const exact_entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const registry = try world.Admission.TargetRegistry.initChecked(&.{ coarse_entry, exact_entry });
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const match = registry.match(null, module_ref);
    try std.testing.expect(match.matched);
    try std.testing.expectEqual(exact_entry.target_ref.target_ref_fingerprint, match.local_target_ref_fingerprint.?);
}

test "target registry rejects module import and table witness mismatches" {
    var module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);

    module_ref.import_surface_fingerprint = if (module_ref.import_surface_fingerprint) |fingerprint| fingerprint +% 1 else 1;
    const import_mismatch = world.Admission.TargetMatch.matchModule(module_ref, fixtures.Ports.Target);
    try std.testing.expect(!import_mismatch.matched);
    try std.testing.expectEqual(world.Admission.MatchMismatch.ImportSet, import_mismatch.mismatches[0]);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    try std.testing.expect(registry.matchModule(module_ref) == null);

    module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    module_ref.world_value_table_fingerprint = if (module_ref.world_value_table_fingerprint) |fingerprint| fingerprint +% 1 else 1;
    const table_mismatch = world.Admission.TargetMatch.matchModule(module_ref, fixtures.Ports.Target);
    try std.testing.expect(!table_mismatch.matched);
    try std.testing.expectEqual(world.Admission.MatchMismatch.WorldValueTable, table_mismatch.mismatches[0]);

    module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    var stale_target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    stale_target_ref.world_dispatch_table_fingerprint = if (stale_target_ref.world_dispatch_table_fingerprint) |fingerprint| fingerprint +% 1 else 1;
    const stale_target_match = registry.match(stale_target_ref, module_ref);
    try std.testing.expect(!stale_target_match.matched);
    try std.testing.expectEqual(world.Admission.MatchMismatch.WorldDispatchTable, stale_target_match.mismatches[0]);
}

test "target registry rejects duplicate conflicting target" {
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    var stale_entry = entry;
    stale_entry.import_set_fingerprint +%= 1;
    const stale_entry_registry = world.Admission.TargetRegistry.init(&.{stale_entry});
    try std.testing.expectError(error.TargetRegistryConflict, stale_entry_registry.validate());

    var stale_registry = world.Admission.TargetRegistry.init(&.{entry});
    stale_registry.registry_fingerprint +%= 1;
    try std.testing.expectError(error.TargetRegistryConflict, stale_registry.validate());

    var inconsistent_target_ref = entry;
    inconsistent_target_ref.target_ref.world_surface_fingerprint +%= 1;
    const inconsistent_target_ref_registry = world.Admission.TargetRegistry.init(&.{inconsistent_target_ref});
    try std.testing.expectError(error.TargetRegistryConflict, inconsistent_target_ref_registry.validate());

    var conflicting = entry;
    conflicting.import_set_fingerprint +%= 1;
    conflicting.entry_fingerprint +%= 1;
    const registry = world.Admission.TargetRegistry.init(&.{ entry, conflicting });
    try std.testing.expectError(error.TargetRegistryConflict, registry.validate());
    try std.testing.expectError(error.TargetRegistryConflict, world.Admission.TargetRegistry.initChecked(&.{ entry, conflicting }));
}

test "target match diagnostics identify mismatched field" {
    const module_ref = world.Admission.ModuleRef.init(.{
        .boundary_module_fingerprint = 1,
        .module_kind = .reference_only,
        .target_ref_fingerprint = world.TargetRef.fromTarget(fixtures.Ports.Target).target_ref_fingerprint,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint +% 1,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .residual_program_plan_hash = world.TargetRef.fromTarget(fixtures.Ports.Target).residual_program_plan_hash,
        .normal_form_kind = world.TargetRef.fromTarget(fixtures.Ports.Target).normal_form_kind,
        .world_port_count = fixtures.Ports.Target.WorldPortTable.entries.len,
    });
    const match = world.Admission.TargetMatch.matchModule(module_ref, fixtures.Ports.Target);
    try std.testing.expect(!match.matched);
    try std.testing.expectEqual(world.Admission.MatchMismatch.WorldSurface, match.mismatches[0]);

    const base_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const partial_ref = world.Admission.ModuleRef.init(.{
        .boundary_module_fingerprint = base_ref.boundary_module_fingerprint,
        .module_kind = .partial_module,
        .target_ref_fingerprint = base_ref.target_ref_fingerprint,
        .world_surface_fingerprint = base_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = base_ref.target_certificate_fingerprint,
        .residual_program_plan_hash = base_ref.residual_program_plan_hash,
        .import_surface_fingerprint = base_ref.import_surface_fingerprint,
        .export_surface_fingerprint = base_ref.export_surface_fingerprint,
        .normal_form_kind = base_ref.normal_form_kind,
        .world_port_count = base_ref.world_port_count,
        .world_port_table_fingerprint = base_ref.world_port_table_fingerprint,
        .world_value_table_fingerprint = base_ref.world_value_table_fingerprint,
        .world_dispatch_table_fingerprint = base_ref.world_dispatch_table_fingerprint,
    });
    const partial_match = world.Admission.TargetMatch.matchModule(partial_ref, fixtures.Ports.Target);
    try std.testing.expect(!partial_match.matched);

    const stale_boundary_ref = world.Admission.ModuleRef.init(.{
        .boundary_module_fingerprint = base_ref.boundary_module_fingerprint +% 1,
        .module_kind = .reference_only,
        .target_ref_fingerprint = base_ref.target_ref_fingerprint,
        .world_surface_fingerprint = base_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = base_ref.target_certificate_fingerprint,
        .residual_program_plan_hash = base_ref.residual_program_plan_hash,
        .import_surface_fingerprint = base_ref.import_surface_fingerprint,
        .export_surface_fingerprint = base_ref.export_surface_fingerprint,
        .normal_form_kind = base_ref.normal_form_kind,
        .world_port_count = base_ref.world_port_count,
        .world_port_table_fingerprint = base_ref.world_port_table_fingerprint,
        .world_value_table_fingerprint = base_ref.world_value_table_fingerprint,
        .world_dispatch_table_fingerprint = base_ref.world_dispatch_table_fingerprint,
    });
    const stale_boundary_match = world.Admission.TargetMatch.matchModule(stale_boundary_ref, fixtures.Ports.Target);
    try std.testing.expect(!stale_boundary_match.matched);
    try std.testing.expectEqual(world.Admission.MatchMismatch.BoundaryModule, stale_boundary_match.mismatches[0]);
}

test "module gateway validates full module inspect-only and reports unsupported loaded execution" {
    const bytes = try fixtures.Ports.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var loaded = try world.Admission.ModuleGateway.decodeBoundaryModule(fixtures.Ports.Target, std.testing.allocator, bytes);
    defer loaded.deinit();
    const module_ref = world.Admission.ModuleGateway.refFromBoundaryModule(loaded);
    const import_set = world.Admission.ModuleGateway.importSetFromBoundaryModule(loaded);
    const summary = world.Admission.ModuleGateway.exportSummaryFromBoundaryModule(loaded);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const match = registry.match(null, module_ref);
    try std.testing.expectEqual(loaded.manifest().module_fingerprint, module_ref.boundary_module_fingerprint);
    try std.testing.expect(match.matched);
    try std.testing.expectEqual(world.Admission.MatchMode.module_full_to_local_target, match.match_mode);
    try std.testing.expectEqual(@as(usize, 1), import_set.required_count);
    try std.testing.expect(!summary.loaded_execution_supported);
}

test "admission policy request report and receipt fingerprints are stable" {
    const policy = world.Admission.AdmissionPolicy.handoff_receiver;
    const request = world.Admission.AdmissionRequest.init(.{
        .package_fingerprint = 11,
        .mode = .resume_parked,
        .policy_fingerprint = policy.policy_fingerprint,
        .target_registry_fingerprint = 22,
        .environment_certificate_fingerprint = 33,
        .run_permit_fingerprint = 44,
    });
    const report = world.Admission.AdmissionReport.accept(.{
        .request = request,
        .package_fingerprint = 11,
        .manifest_fingerprint = 55,
        .target_ref_fingerprint = 66,
        .run_permit_fingerprint = 44,
    });
    const receipt = world.Admission.AdmissionReceipt.init(.{
        .request = request,
        .report = report,
        .target_ref_fingerprint = 66,
        .environment_certificate_fingerprint = 33,
        .run_permit_fingerprint = 44,
    });
    const receipt_with_admitted_association = world.Admission.AdmissionReceipt.init(.{
        .request = request,
        .report = report,
        .target_ref_fingerprint = 66,
        .environment_certificate_fingerprint = 33,
        .run_permit_fingerprint = 44,
        .admitted_run_fingerprint = 77,
    });
    try std.testing.expect(report.accepted);
    try std.testing.expectEqual(report.report_fingerprint, world.Admission.AdmissionReport.accept(.{
        .request = request,
        .package_fingerprint = 11,
        .manifest_fingerprint = 55,
        .target_ref_fingerprint = 66,
        .run_permit_fingerprint = 44,
    }).report_fingerprint);
    try std.testing.expect(receipt.receipt_fingerprint != 0);
    try std.testing.expect(receipt.receipt_fingerprint != receipt_with_admitted_association.receipt_fingerprint);
}

test "admitter accepts inspect-only full module and rejects missing permit for execution" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const entry = world.Admission.TargetRegistry.register(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{entry});
    const full_module_bytes = try fixtures.Ports.Target.Module.fullImage(std.testing.allocator);
    defer std.testing.allocator.free(full_module_bytes);
    var loaded_module = try world.Admission.ModuleGateway.decodeBoundaryModule(fixtures.Ports.Target, std.testing.allocator, full_module_bytes);
    defer loaded_module.deinit();
    const module_ref = world.Admission.ModuleGateway.refFromBoundaryModule(loaded_module);
    const reference_module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const inspect_package = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .module_ref = module_ref,
        .module_image_bytes = full_module_bytes,
        .requested_mode = .inspect_only,
    });
    const inspect_admitter = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.inspect_modules,
    });
    const inspect = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, inspect_package, .{});
    try std.testing.expect(inspect.report.accepted);
    try std.testing.expect(inspect.admitted_run == null);

    const bytes_only_inspect_package = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .module_image_bytes = full_module_bytes,
        .requested_mode = .inspect_only,
    });
    const bytes_only_inspect = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, bytes_only_inspect_package, .{});
    try std.testing.expect(bytes_only_inspect.report.accepted);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, bytes_only_inspect.report.module_ref_fingerprint.?);

    const module_reference_only = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .module_ref = reference_module_ref,
        .requested_mode = .inspect_only,
    });
    const module_reference_only_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, module_reference_only, .{});
    try std.testing.expect(module_reference_only_result.report.accepted);
    try std.testing.expectEqual(reference_module_ref.module_ref_fingerprint, module_reference_only_result.report.module_ref_fingerprint.?);

    const module_without_target = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Agent.Target),
        .requested_mode = .inspect_only,
    });
    const module_without_target_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, module_without_target, .{});
    try std.testing.expect(!module_without_target_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TargetNotRegistered, module_without_target_result.report.blockers[0]);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, module_without_target_result.report.target_ref_fingerprint.?);

    const stale_ref_package = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target),
        .module_image_bytes = full_module_bytes,
        .requested_mode = .inspect_only,
    });
    const stale_ref_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, stale_ref_package, .{});
    try std.testing.expect(!stale_ref_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.ModuleInvalid, stale_ref_result.report.blockers[0]);

    const inspect_only_full_module_policy = world.Admission.AdmissionPolicy.init(.{
        .allow_reference_targets = true,
        .allow_full_modules = false,
        .allow_inspect_only_full_modules = true,
        .require_supervision_permit = false,
    });
    const executable_full_module = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .module_image_bytes = "fake-full-module-bytes",
        .requested_mode = .continue_fresh,
    });
    const executable_full_module_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = inspect_only_full_module_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, executable_full_module, .{});
    try std.testing.expect(!executable_full_module_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, executable_full_module_result.report.blockers[0]);

    const inspect_target_only = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .target_ref = target_ref,
        .requested_mode = .inspect_only,
    });
    const reference_inspect_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, inspect_target_only, .{});
    try std.testing.expect(reference_inspect_result.report.accepted);
    try std.testing.expect(reference_inspect_result.admitted_run == null);

    const inspect_module_only_policy = world.Admission.AdmissionPolicy.init(.{
        .allow_reference_targets = false,
        .allow_inspect_only_full_modules = true,
        .require_supervision_permit = false,
    });
    const inspect_target_only_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = inspect_module_only_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, inspect_target_only, .{});
    try std.testing.expect(!inspect_target_only_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, inspect_target_only_result.report.blockers[0]);

    const missing_bytes_full_module = world.Admission.TransferPackage.init(.{
        .kind = .full_module,
        .target_ref = target_ref,
        .module_ref = reference_module_ref,
        .requested_mode = .inspect_only,
    });
    const missing_bytes_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, missing_bytes_full_module, .{});
    try std.testing.expect(!missing_bytes_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, missing_bytes_result.report.blockers[0]);

    const unwitnessed_full_module_reference = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .module_ref = module_ref,
        .requested_mode = .inspect_only,
    });
    const unwitnessed_full_module_reference_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, unwitnessed_full_module_reference, .{});
    try std.testing.expect(!unwitnessed_full_module_reference_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, unwitnessed_full_module_reference_result.report.blockers[0]);

    const execute_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .module_ref = reference_module_ref,
        .requested_mode = .continue_fresh,
    });
    const execution_admitter = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.handoff_receiver,
    });
    const rejected = execution_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, execute_package, .{});
    try std.testing.expect(!rejected.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PermitMissing, rejected.report.blockers[0]);

    const completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
    });
    const inspect_run_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .target_ref = target_ref,
        .run_image = completed_image,
        .requested_mode = .inspect_only,
    });
    const inspect_run_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, inspect_run_package, .{});
    try std.testing.expect(inspect_run_result.report.accepted);
    try std.testing.expect(inspect_run_result.admitted_run == null);

    var inspect_transcript = world.Transcript.init(std.testing.allocator);
    defer inspect_transcript.deinit();
    try recordPortsTranscript(&inspect_transcript);
    var inspect_transcript_image = try inspect_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer inspect_transcript_image.deinit(std.testing.allocator);
    const executable_module_bytes_witness = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, inspect_transcript_image, .completed_run);
    const executable_module_bytes_witness_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_image_bytes = full_module_bytes,
        .run_image = world.RunImage.init(.{
            .kind = executable_module_bytes_witness.kind,
            .target_ref = executable_module_bytes_witness.target_ref,
            .import_set_fingerprint = executable_module_bytes_witness.import_set_fingerprint,
            .transcript_image = executable_module_bytes_witness.transcript_image,
            .current_state = executable_module_bytes_witness.current_state,
            .module_image_fingerprint = world.Admission.moduleImageFingerprintForBytes(full_module_bytes),
        }),
        .requested_mode = .completed_replay,
    });
    const executable_module_bytes_witness_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, executable_module_bytes_witness_package, .{});
    try std.testing.expect(executable_module_bytes_witness_result.report.accepted);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, executable_module_bytes_witness_result.report.module_ref_fingerprint.?);
    const stale_run_module_witness_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_image_bytes = full_module_bytes,
        .run_image = world.RunImage.init(.{
            .kind = executable_module_bytes_witness.kind,
            .target_ref = executable_module_bytes_witness.target_ref,
            .import_set_fingerprint = executable_module_bytes_witness.import_set_fingerprint,
            .transcript_image = executable_module_bytes_witness.transcript_image,
            .current_state = executable_module_bytes_witness.current_state,
        }).withModuleRef(
            world.Admission.ModuleRef.fromTarget(fixtures.Agent.Target),
            world.Admission.moduleImageFingerprintForBytes(full_module_bytes),
        ),
        .requested_mode = .completed_replay,
    });
    const stale_run_module_witness_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, stale_run_module_witness_package, .{});
    try std.testing.expect(!stale_run_module_witness_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.ModuleInvalid, stale_run_module_witness_result.report.blockers[0]);

    const unbound_transcript_inspect_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .transcript_image = inspect_transcript_image,
        .requested_mode = .inspect_only,
    });
    const unbound_transcript_result = inspect_admitter.admitForTarget(fixtures.Ports.Target, PortsEnv, unbound_transcript_inspect_package, .{});
    try std.testing.expect(!unbound_transcript_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TargetRefMissing, unbound_transcript_result.report.blockers[0]);

    const malformed_run_module_bytes = "not-a-boundary-module-image";
    const reference_run_module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const malformed_run_with_module_bytes = completed_image.withModuleRef(
        reference_run_module_ref,
        world.Admission.moduleImageFingerprintForBytes(malformed_run_module_bytes),
    );
    const malformed_run_module_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = reference_run_module_ref,
        .module_image_bytes = malformed_run_module_bytes,
        .run_image = malformed_run_with_module_bytes,
        .requested_mode = .completed_replay,
    });
    const malformed_run_module_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, malformed_run_module_package, .{});
    try std.testing.expect(!malformed_run_module_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.ModuleInvalid, malformed_run_module_result.report.blockers[0]);

    const overridden_mode = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, inspect_run_package, .{ .mode = .completed_replay });
    try std.testing.expect(!overridden_mode.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, overridden_mode.report.blockers[0]);
    try std.testing.expect(overridden_mode.receipt == null);
    try std.testing.expect(overridden_mode.admitted_run == null);
}

test "admission rejects bare target reference when reference targets are disabled" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const reference_run_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    });
    const reference_run_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .run_image = reference_run_image,
        .requested_mode = .inspect_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, reference_run_package.validate(.{ .allow_reference_only = false }));

    var future_target_ref = target_ref;
    future_target_ref.format_version = world.world_target_ref_format_version + 1;
    const future_target_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = future_target_ref,
        .requested_mode = .local_target_match_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, future_target_package.validate(.{}));

    var bad_fingerprint_version_ref = target_ref;
    bad_fingerprint_version_ref.fingerprint_version += 1;
    const bad_version_run_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = bad_fingerprint_version_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    });
    const bad_version_run_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .run_image = bad_version_run_image,
        .requested_mode = .inspect_only,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, bad_version_run_package.validate(.{}));

    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const policy = world.Admission.AdmissionPolicy.init(.{
        .allow_reference_targets = false,
        .allow_full_modules = true,
        .require_supervision_permit = false,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(!result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, result.report.blockers[0]);

    const missing_target = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .requested_mode = .local_target_match_only,
    });
    const missing_target_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, missing_target, .{});
    try std.testing.expect(!missing_target_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TargetRefMissing, missing_target_result.report.blockers[0]);
}

test "admission rejects prior receipt mismatch when policy requires it" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .prior_run_receipt_fingerprint = 123,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .completed_replay,
    });
    const policy = world.Admission.AdmissionPolicy.init(.{
        .allow_reference_targets = true,
        .require_supervision_permit = false,
        .allow_completed_replay = true,
        .reject_prior_receipt_mismatch = true,
    });
    const admitted = world.Admission.Admitter.init(.{ .registry = registry, .policy = policy }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(!admitted.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PriorReceiptMismatch, admitted.report.blockers[0]);
}

test "admission target-match-only is non-executable and ignores permit requirement" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .local_target_match_only,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.strict_local_execution,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(result.report.accepted);
    try std.testing.expect(result.receipt != null);
    try std.testing.expect(result.admitted_run == null);

    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .not_started,
    });
    const reference_run_image = world.RunImage.init(.{
        .kind = .reference_target_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    });
    const run_reference_package = world.Admission.TransferPackage.init(.{
        .kind = .run_reference,
        .target_ref = target_ref,
        .run_image = reference_run_image,
        .requested_mode = .local_target_match_only,
    });
    const run_reference_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.strict_local_execution,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, run_reference_package, .{});
    try std.testing.expect(run_reference_result.report.accepted);
    try std.testing.expect(run_reference_result.receipt != null);
    try std.testing.expect(run_reference_result.admitted_run == null);
}

test "replay-only admission policy rejects resume modes" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const policy = world.Admission.AdmissionPolicy.replay_only;
    try std.testing.expect(!policy.allowsMode(.resume_parked));
    try std.testing.expect(!policy.allowsMode(.branch_resume));
    try std.testing.expect(policy.allowsMode(.replay_only));
    const verify_policy = world.Admission.AdmissionPolicy.verify_receiver;
    try std.testing.expect(!verify_policy.allowsMode(.resume_parked));
    try std.testing.expect(!verify_policy.allowsMode(.branch_resume));
    try std.testing.expect(!verify_policy.allowsMode(.completed_replay));
    try std.testing.expect(!verify_policy.allowsMode(.continue_fresh));
    try std.testing.expect(verify_policy.allowsMode(.verify_only));
    const inspect_policy = world.Admission.AdmissionPolicy.inspect_modules;
    try std.testing.expect(!inspect_policy.allowsMode(.resume_parked));
    try std.testing.expect(!inspect_policy.allowsMode(.branch_resume));
    try std.testing.expect(!inspect_policy.allowsMode(.completed_replay));
    try std.testing.expect(!inspect_policy.allowsMode(.continue_fresh));
    try std.testing.expect(!inspect_policy.allowsMode(.replay_only));
    try std.testing.expect(!inspect_policy.allowsMode(.verify_only));

    const fresh_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const verify_fresh_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = verify_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, fresh_package, .{});
    try std.testing.expect(!verify_fresh_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.AdmissionModeNotAllowed, verify_fresh_result.report.blockers[0]);

    var stale_policy = world.Admission.AdmissionPolicy.strict_local_execution;
    stale_policy.allow_continue_fresh = false;
    stale_policy.policy_fingerprint = 0;
    const expected_policy = world.Admission.AdmissionPolicy.init(.{
        .allow_continue_fresh = false,
    });
    const stale_policy_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = stale_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, fresh_package, .{});
    try std.testing.expect(!stale_policy_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.AdmissionModeNotAllowed, stale_policy_result.report.blockers[0]);
    try std.testing.expectEqual(expected_policy.policy_fingerprint, stale_policy_result.request.policy_fingerprint);

    const pending_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 44,
        .turn_index = 0,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = pending_request.frame_fingerprint,
        .status = .parked_on_port,
    });
    const parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = pending_request,
    });
    const parked_package = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .run_image = parked_image,
        .requested_mode = .resume_parked,
    });
    const parked_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = policy,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, parked_package, .{});
    try std.testing.expect(!parked_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.AdmissionModeNotAllowed, parked_result.report.blockers[0]);
    const verify_parked_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = verify_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, parked_package, .{});
    try std.testing.expect(!verify_parked_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.AdmissionModeNotAllowed, verify_parked_result.report.blockers[0]);
    const inspect_parked_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = inspect_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, parked_package, .{});
    try std.testing.expect(!inspect_parked_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.AdmissionModeNotAllowed, inspect_parked_result.report.blockers[0]);
}

test "admission rejects run images that do not fit requested mode" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const completed_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
    }).withModuleRef(module_ref, null);
    const completed_as_parked = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = completed_image,
        .requested_mode = .resume_parked,
    });
    const completed_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, completed_as_parked, .{});
    try std.testing.expect(!completed_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.RunImageInvalid, completed_result.report.blockers[0]);

    const pending_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 1,
        .turn_index = 0,
    });
    const parked_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = pending_request.frame_fingerprint,
        .status = .parked_on_port,
    });
    const parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = parked_state,
        .pending_request_frame = pending_request,
    }).withModuleRef(module_ref, null);
    const parked_as_completed = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = parked_image,
        .requested_mode = .completed_replay,
    });
    const parked_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, parked_as_completed, .{});
    try std.testing.expect(!parked_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.RunImageInvalid, parked_result.report.blockers[0]);
}

test "admission rejects missing branch and checkpoint selections" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .completed_replay,
    });
    const admitter = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    });
    const missing_branch = admitter.admitForTarget(fixtures.Ports.Target, PortsReplayEnv, package, .{ .requested_branch_id = 42 });
    try std.testing.expect(!missing_branch.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.BranchMismatch, missing_branch.report.blockers[0]);
    const missing_checkpoint = admitter.admitForTarget(fixtures.Ports.Target, PortsReplayEnv, package, .{ .requested_checkpoint_ref = 42 });
    try std.testing.expect(!missing_checkpoint.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.CheckpointMismatch, missing_checkpoint.report.blockers[0]);

    const branch_checkpoint = world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 0,
        .turn_index = 0,
        .transcript_prefix_fingerprint = 44,
        .branch_id = 7,
        .status = .parked_on_port,
    });
    var branch_checkpoints = [_]world.Timeline.Checkpoint{branch_checkpoint};
    var branches = [_]world.Timeline.Branch{.{
        .branch_id = 7,
        .checkpoint_fingerprint = branch_checkpoint.checkpoint_fingerprint,
        .start_event_index = 0,
    }};
    const pending_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 45,
        .turn_index = 0,
    });
    const branch_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .branch_id = 7,
        .checkpoint_fingerprint = branch_checkpoint.checkpoint_fingerprint,
        .pending_request_fingerprint = pending_request.frame_fingerprint,
        .status = .parked_on_port,
    });
    const branch_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = branch_state,
        .checkpoints = branch_checkpoints[0..],
        .branches = branches[0..],
        .pending_request_frame = pending_request,
    }).withModuleRef(module_ref, null);
    const branch_run_package = world.Admission.TransferPackage.init(.{
        .kind = .branch_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = branch_image,
        .requested_mode = .branch_resume,
    });
    const branch_run_missing_selection = admitter.admitForTarget(fixtures.Ports.Target, PortsReplayEnv, branch_run_package, .{});
    try std.testing.expect(!branch_run_missing_selection.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.BranchMismatch, branch_run_missing_selection.report.blockers[0]);
}

test "admission rejects parked handoff that fails handoff preflight" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    var payload_image: ?world.Frame.ValueImage = try world.Frame.ValueImage.fromValue(
        std.testing.allocator,
        0,
        null,
        null,
        @as([]const u8, "portable"),
        world.ValuePolicy.portable,
    );
    errdefer if (payload_image) |*payload| payload.deinit(std.testing.allocator);
    var request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 99,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0xabc0_ffee,
        .turn_index = 0,
        .payload_value_table_id = 0,
        .expected_response_value_table_id = 1,
        .payload_image = payload_image,
    });
    payload_image = null;
    defer request.deinit(std.testing.allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = request.frame_fingerprint,
        .turn_index = request.turn_index,
        .status = .parked_on_port,
    });
    const run_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = request,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .resume_parked,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{ .allocator = std.testing.allocator });
    try std.testing.expect(!result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.EnvironmentRejected, result.report.blockers[0]);

    const branch_package = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .branch_resume,
    });
    const missing_branch = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, branch_package, .{ .allocator = std.testing.allocator });
    try std.testing.expect(!missing_branch.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.RunImageInvalid, missing_branch.report.blockers[0]);
}

test "admitted run constructed for accepted local target" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(result.report.accepted);
    try std.testing.expect(result.admitted_run != null);
    try std.testing.expect(result.receipt != null);
    try std.testing.expectEqual(target_ref.target_ref_fingerprint, result.admitted_run.?.target_ref.target_ref_fingerprint);
    try std.testing.expectEqual(result.receipt.?.receipt_fingerprint, result.admitted_run.?.admission_receipt_fingerprint);
    try std.testing.expectEqual(result.receipt.?.admitted_run_fingerprint.?, result.admitted_run.?.admitted_run_fingerprint);
    const forged_receipt = world.Admission.AdmissionReceipt.init(.{
        .request = result.request,
        .report = result.report,
        .target_ref_fingerprint = result.receipt.?.target_ref_fingerprint,
        .module_ref_fingerprint = result.receipt.?.module_ref_fingerprint,
        .local_target_ref_fingerprint = result.receipt.?.local_target_ref_fingerprint,
        .target_match_fingerprint = result.receipt.?.target_match_fingerprint,
        .environment_certificate_fingerprint = result.receipt.?.environment_certificate_fingerprint,
        .run_permit_fingerprint = result.receipt.?.run_permit_fingerprint,
        .admitted_run_fingerprint = result.admitted_run.?.admitted_run_fingerprint +% 1,
        .warnings = result.receipt.?.warnings,
        .metadata = result.receipt.?.metadata,
    });
    try std.testing.expect(forged_receipt.receipt_fingerprint != result.receipt.?.receipt_fingerprint);
    var forged_admitted = result.admitted_run.?;
    forged_admitted.admission_receipt_fingerprint = forged_receipt.receipt_fingerprint;
    var runspace = world.Runspace.init(std.testing.allocator, .{});
    defer runspace.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, runspace.installAdmitted(forged_admitted));
    var receiptless_admitted = result.admitted_run.?;
    receiptless_admitted.admission_receipt = null;
    var admission_gated_runspace = world.Runspace.init(std.testing.allocator, .{ .require_admission = true });
    defer admission_gated_runspace.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, admission_gated_runspace.installAdmitted(receiptless_admitted));
}

test "admission rejects permit mode mismatch before receipt" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const wrong_mode_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .replay,
        .transcript_image_available = true,
        .policy = world.SupervisionPolicy.strict_replay,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.strict_local_execution,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{ .permit = wrong_mode_permit });
    try std.testing.expect(!result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PermitRejected, result.report.blockers[0]);

    const stale_admission_scope_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
        .admission_receipt_fingerprint = 0xabc,
    });
    const stale_admission_scope_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.strict_local_execution,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{ .permit = stale_admission_scope_permit });
    try std.testing.expect(!stale_admission_scope_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PermitRejected, stale_admission_scope_result.report.blockers[0]);

    const module_package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .requested_mode = .continue_fresh,
    });
    const wrong_module_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint +% 1,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    const module_scoped_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.init(.{
            .allow_reference_targets = true,
            .require_supervision_permit = true,
        }),
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, module_package, .{ .permit = wrong_module_permit });
    try std.testing.expect(!module_scoped_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PermitRejected, module_scoped_result.report.blockers[0]);

    const completed_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const run_image_with_module = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = completed_state,
    }).withModuleRef(module_ref, null);
    const missing_module_ref_package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = target_ref,
        .run_image = run_image_with_module,
        .requested_mode = .completed_replay,
    });
    try std.testing.expectError(error.InvalidFrameEncoding, missing_module_ref_package.validate(.{}));
    const module_scoped_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .transcript_image_available = true,
        .module_ref_fingerprint = module_ref.module_ref_fingerprint,
        .policy = world.SupervisionPolicy.handoff_receiver,
    });
    const missing_module_ref_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.init(.{
            .require_environment_preflight = false,
            .require_supervision_permit = true,
        }),
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, missing_module_ref_package, .{ .permit = module_scoped_permit });
    try std.testing.expect(!missing_module_ref_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, missing_module_ref_result.report.blockers[0]);
}

test "admitted run start requires stored permit" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.strict_local_execution,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{ .permit = permit });
    try std.testing.expect(result.report.accepted);
    var admitted = result.admitted_run orelse return error.ExpectedAdmittedRun;
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.SupervisionDenied, admitted.start(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    }));
    var scoped_runtime = boundary.Runtime.init(std.testing.allocator);
    defer scoped_runtime.deinit();
    var scoped_run = try admitted.start(fixtures.Ports.Target, PortsEnv, &scoped_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = permit,
    });
    defer scoped_run.deinit();
    if (scoped_run.supervisor) |*supervisor| {
        try std.testing.expectEqual(result.receipt.?.receipt_fingerprint, supervisor.permit.admission_receipt_fingerprint.?);
        try std.testing.expect(supervisor.permit.permit_fingerprint != permit.permit_fingerprint);
        const run_state = world.RunState.init(.{
            .target_ref_fingerprint = target_ref.target_ref_fingerprint,
            .status = .completed,
        });
        const run_receipt = supervisor.receipt(.completed, run_state.run_state_fingerprint, null, null);
        try std.testing.expectEqual(result.receipt.?.receipt_fingerprint, run_receipt.admission_receipt_fingerprint.?);
    } else {
        return error.ExpectedSupervisor;
    }
}

test "admitted run start enforces admitted target and mode without stored permit" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .continue_fresh,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    var admitted = result.admitted_run orelse return error.ExpectedAdmittedRun;

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.HandoffDenied, admitted.start(fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
    }));

    var agent_runtime = boundary.Runtime.init(std.testing.allocator);
    defer agent_runtime.deinit();
    var agent_ctx: AgentCtx = .{ .allocator = std.testing.allocator, .scenario = .skeleton };
    try std.testing.expectError(error.HandoffTargetMismatch, admitted.start(fixtures.Agent.Target, AgentEnv, &agent_runtime, AgentArgs{ @as(usize, 3), fixtures.Agent.initialObservation(.skeleton) }, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &agent_ctx,
    }));

    var replay_env_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_env_runtime.deinit();
    try std.testing.expectError(error.HandoffDenied, admitted.start(fixtures.Ports.Target, PortsReplayEnv, &replay_env_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    }));

    const TranscriptRequiredPortsEnv = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNativeBinding},
        .policy = world.EnvironmentPolicy.init(.{ .allow_fresh_without_transcript = false }),
    });
    const sink_missing = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, package, .{});
    try std.testing.expect(!sink_missing.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.EnvironmentRejected, sink_missing.report.blockers[0]);

    var old_transcript = world.Transcript.init(std.testing.allocator);
    defer old_transcript.deinit();
    try recordPortsTranscript(&old_transcript);
    var old_image = try old_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer old_image.deinit(std.testing.allocator);
    const package_with_old_transcript = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .transcript_image = old_image,
        .requested_mode = .continue_fresh,
    });
    const old_transcript_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, package_with_old_transcript, .{});
    try std.testing.expect(!old_transcript_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.EnvironmentRejected, old_transcript_result.report.blockers[0]);

    const stale_evidence_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package_with_old_transcript, .{});
    try std.testing.expect(stale_evidence_result.report.accepted);
    var stale_evidence_admitted = stale_evidence_result.admitted_run orelse return error.ExpectedAdmittedRun;
    var stale_evidence_runtime = boundary.Runtime.init(std.testing.allocator);
    defer stale_evidence_runtime.deinit();
    var stale_evidence_run = try stale_evidence_admitted.start(fixtures.Ports.Target, PortsEnv, &stale_evidence_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    });
    defer stale_evidence_run.deinit();

    const sink_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, package, .{ .fresh_transcript_sink_available = true });
    try std.testing.expect(sink_result.report.accepted);
    var sink_admitted = sink_result.admitted_run orelse return error.ExpectedAdmittedRun;
    var sink_runtime = boundary.Runtime.init(std.testing.allocator);
    defer sink_runtime.deinit();
    var sink_transcript = world.Transcript.init(std.testing.allocator);
    defer sink_transcript.deinit();
    var sink_run = try sink_admitted.start(fixtures.Ports.Target, TranscriptRequiredPortsEnv, &sink_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &sink_transcript,
    });
    defer sink_run.deinit();

    var transcript_image_only_runtime = boundary.Runtime.init(std.testing.allocator);
    defer transcript_image_only_runtime.deinit();
    try std.testing.expectError(error.HandoffDenied, sink_admitted.start(fixtures.Ports.Target, TranscriptRequiredPortsEnv, &transcript_image_only_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript_image = &old_image,
    }));
}

test "admission permits parked resume with fresh transcript sink" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const TranscriptRequiredPortsEnv = world.Environment(fixtures.Ports.Target, .{
        .bindings = .{PortsNativeBinding},
        .policy = world.EnvironmentPolicy.init(.{ .allow_fresh_without_transcript = false }),
    });
    const pending_request = world.Frame.Request.init(.{
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .request_fingerprint = 0x51_51,
        .turn_index = 0,
    });
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .pending_request_fingerprint = pending_request.frame_fingerprint,
        .status = .parked_on_port,
    });
    const parked_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
        .pending_request_frame = pending_request,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = parked_image,
        .requested_mode = .resume_parked,
    });
    const admitter = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    });
    const sink_missing = admitter.admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, package, .{ .allocator = std.testing.allocator });
    try std.testing.expect(!sink_missing.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.EnvironmentRejected, sink_missing.report.blockers[0]);

    const sink_result = admitter.admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, package, .{
        .allocator = std.testing.allocator,
        .fresh_transcript_sink_available = true,
    });
    try std.testing.expect(sink_result.report.accepted);
    var admitted = sink_result.admitted_run orelse return error.ExpectedAdmittedRun;
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try std.testing.expectError(error.HandoffPendingFrameMismatch, admitted.@"resume"(std.testing.allocator, fixtures.Ports.Target, TranscriptRequiredPortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .transcript = &transcript,
    }));

    var branch_checkpoints = [_]world.Timeline.Checkpoint{world.Timeline.Checkpoint.init(.{
        .world_surface_fingerprint = target_ref.world_surface_fingerprint,
        .target_certificate_fingerprint = target_ref.target_certificate_fingerprint,
        .event_index = 0,
        .turn_index = 0,
        .transcript_prefix_fingerprint = 0x52_52,
        .branch_id = 7,
        .status = .parked_on_port,
    })};
    var branches = [_]world.Timeline.Branch{.{
        .branch_id = 7,
        .checkpoint_fingerprint = branch_checkpoints[0].checkpoint_fingerprint,
        .start_event_index = 0,
    }};
    const branch_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .branch_id = 7,
        .checkpoint_fingerprint = branch_checkpoints[0].checkpoint_fingerprint,
        .pending_request_fingerprint = pending_request.frame_fingerprint,
        .status = .parked_on_port,
    });
    const branch_image = world.RunImage.init(.{
        .kind = .parked_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = branch_state,
        .checkpoints = branch_checkpoints[0..],
        .branches = branches[0..],
        .pending_request_frame = pending_request,
    }).withModuleRef(module_ref, null);
    const branch_package = world.Admission.TransferPackage.init(.{
        .kind = .branch_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = branch_image,
        .requested_mode = .branch_resume,
    });
    const branch_result = admitter.admitForTarget(fixtures.Ports.Target, TranscriptRequiredPortsEnv, branch_package, .{
        .allocator = std.testing.allocator,
        .fresh_transcript_sink_available = true,
        .requested_branch_id = 7,
    });
    try std.testing.expect(branch_result.report.accepted);
}

test "admitted run start enforces admitted transcript image" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const run_image = world.RunImage.fromTranscriptImage(fixtures.Ports.Target, image, .replay_only_run).withModuleRef(module_ref, null);
    const bare_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .status = .completed,
    });
    const bare_run_image = world.RunImage.init(.{
        .kind = .replay_only_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = bare_state,
    }).withModuleRef(module_ref, null);
    const unbound_state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const unbound_run_image = world.RunImage.init(.{
        .kind = .replay_only_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = unbound_state,
    }).withModuleRef(module_ref, null);
    const unbound_transcript_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = unbound_run_image,
        .transcript_image = image,
        .requested_mode = .replay_only,
    });
    const unbound_transcript_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, unbound_transcript_package, .{});
    try std.testing.expect(!unbound_transcript_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, unbound_transcript_result.report.blockers[0]);

    var mismatched_standalone_image = image;
    mismatched_standalone_image.transcript_image_fingerprint +%= 1;
    const mismatched_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = bare_run_image,
        .transcript_image = mismatched_standalone_image,
        .requested_mode = .replay_only,
    });
    const mismatched_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, mismatched_package, .{});
    try std.testing.expect(!mismatched_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, mismatched_result.report.blockers[0]);

    const missing_transcript_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = bare_run_image,
        .requested_mode = .replay_only,
    });
    const missing_transcript_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, missing_transcript_package, .{});
    try std.testing.expect(!missing_transcript_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.EnvironmentRejected, missing_transcript_result.report.blockers[0]);

    const no_replay_evidence_package = world.Admission.TransferPackage.init(.{
        .kind = .target_reference_only,
        .target_ref = target_ref,
        .requested_mode = .replay_only,
    });
    const no_replay_evidence_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, no_replay_evidence_package, .{});
    try std.testing.expect(!no_replay_evidence_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.RunImageInvalid, no_replay_evidence_result.report.blockers[0]);

    const transcript_target_mismatch_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target),
        .transcript_image = image,
        .requested_mode = .replay_only,
    });
    const transcript_target_mismatch_result = world.Admission.Admitter.init(.{
        .registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Agent.Target)}),
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Agent.Target, AgentEnv, transcript_target_mismatch_package, .{});
    try std.testing.expect(!transcript_target_mismatch_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, transcript_target_mismatch_result.report.blockers[0]);

    var agent_transcript = world.Transcript.init(std.testing.allocator);
    defer agent_transcript.deinit();
    try agent_transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
    });
    try agent_transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Agent.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Agent.Target.Certificate.certificate_fingerprint,
        .status = .responded,
    });
    var agent_image = try agent_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer agent_image.deinit(std.testing.allocator);
    const inspect_mismatch_package = world.Admission.TransferPackage.init(.{
        .kind = .inspect_only,
        .module_ref = module_ref,
        .transcript_image = agent_image,
        .requested_mode = .inspect_only,
    });
    var inspect_mismatch_policy = world.Admission.AdmissionPolicy.inspect_modules;
    inspect_mismatch_policy.reject_transcript_mismatch = false;
    const rejected_inspect_mismatch = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.inspect_modules,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, inspect_mismatch_package, .{});
    try std.testing.expect(!rejected_inspect_mismatch.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TranscriptTargetMismatch, rejected_inspect_mismatch.report.blockers[0]);
    const allowed_inspect_mismatch = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = inspect_mismatch_policy,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, inspect_mismatch_package, .{});
    try std.testing.expect(allowed_inspect_mismatch.report.accepted);
    try std.testing.expect(allowed_inspect_mismatch.admitted_run == null);

    var incomplete_transcript = world.Transcript.init(std.testing.allocator);
    defer incomplete_transcript.deinit();
    try incomplete_transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
    });
    var incomplete_image = try incomplete_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer incomplete_image.deinit(std.testing.allocator);
    const incomplete_transcript_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .transcript_image = incomplete_image,
        .requested_mode = .replay_only,
    });
    const incomplete_transcript_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, incomplete_transcript_package, .{});
    try std.testing.expect(!incomplete_transcript_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TranscriptImageInvalid, incomplete_transcript_result.report.blockers[0]);

    var invalid_env_transcript = world.Transcript.init(std.testing.allocator);
    defer invalid_env_transcript.deinit();
    try invalid_env_transcript.append(.{
        .kind = .run_started,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .source_run = true,
    });
    try invalid_env_transcript.append(.{
        .kind = .frame_requested,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .world_surface_replay_scope_fingerprint = fixtures.Ports.Target.WorldSurface.replayScopeRef().fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .world_port_id = 999,
        .request_fingerprint = 0xdead_999,
        .turn_index = 0,
        .residual_site_index = fixtures.Ports.ApprovalRequest.index,
        .residual_site_fingerprint = fixtures.Ports.ApprovalRequest.fingerprint,
        .source_run = true,
    });
    try invalid_env_transcript.append(.{
        .kind = .run_completed,
        .world_surface_fingerprint = fixtures.Ports.Target.WorldSurface.surface_fingerprint,
        .target_certificate_fingerprint = fixtures.Ports.Target.Certificate.certificate_fingerprint,
        .status = .responded,
        .source_run = true,
    });
    var invalid_env_image = try invalid_env_transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer invalid_env_image.deinit(std.testing.allocator);
    const invalid_env_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .transcript_image = invalid_env_image,
        .requested_mode = .replay_only,
    });
    const invalid_env_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, invalid_env_package, .{});
    try std.testing.expect(!invalid_env_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.TranscriptImageInvalid, invalid_env_result.report.blockers[0]);

    const transcript_only_package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .transcript_image = image,
        .requested_mode = .replay_only,
    });
    const transcript_handoff_policy = world.SupervisionPolicy.init(.{
        .allow_replay_calls = true,
        .allow_replay_adapters = true,
        .allow_handoff_accept = true,
        .require_portable_value_images = true,
        .reject_native_only_values = true,
        .require_environment_certificate = true,
        .require_transcript_image_for_replay = true,
    });
    const transcript_handoff_deny_permit = world.Supervision.issue(fixtures.Ports.Target, PortsReplayEnv, .{
        .mode = .replay,
        .policy = transcript_handoff_policy,
        .transcript_image_available = true,
        .handoff_policy = .deny,
    });
    const transcript_handoff_deny_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.init(.{
            .require_environment_preflight = false,
            .require_supervision_permit = true,
            .allow_replay_without_environment = true,
            .allow_parked_resume = false,
            .allow_branch_resume = false,
        }),
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, transcript_only_package, .{ .permit = transcript_handoff_deny_permit });
    try std.testing.expect(!transcript_handoff_deny_result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PermitRejected, transcript_handoff_deny_result.report.blockers[0]);

    const transcript_only_result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, transcript_only_package, .{});
    try std.testing.expect(transcript_only_result.report.accepted);
    try std.testing.expect(transcript_only_result.report.handoff_preflight_report_fingerprint == null);
    try std.testing.expect(transcript_only_result.admitted_run.?.run_image == null);
    try std.testing.expectEqual(image.transcript_image_fingerprint, transcript_only_result.admitted_run.?.transcript_image.?.transcript_image_fingerprint);
    var transcript_only_admitted = transcript_only_result.admitted_run orelse return error.ExpectedAdmittedRun;
    var transcript_only_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer transcript_only_runspace.deinit();
    const transcript_only_handle = try transcript_only_runspace.installAdmitted(transcript_only_admitted);
    try std.testing.expectEqual(world.Runspace.RunStatus.completed, (try transcript_only_runspace.getSlotSummary(transcript_only_handle)).status);
    var transcript_only_export = try transcript_only_runspace.exportRun(transcript_only_handle);
    defer transcript_only_export.deinit(std.testing.allocator);
    try std.testing.expectEqual(world.RunImage.Kind.replay_only_run, transcript_only_export.kind);
    try std.testing.expectEqual(world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint, transcript_only_export.import_set_fingerprint);
    try std.testing.expectEqual(image.transcript_image_fingerprint, transcript_only_export.transcript_image.?.transcript_image_fingerprint);
    const missing_import_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xadd1_7710,
        .target_ref = target_ref,
        .environment_certificate_fingerprint = PortsReplayEnv.certificate(.replay, true).certificate_fingerprint,
        .mode = .replay_only,
        .transcript_image = image,
    });
    var missing_import_runspace = world.Runspace.init(std.testing.allocator, .{});
    defer missing_import_runspace.deinit();
    try std.testing.expectError(error.InvalidFrameEncoding, missing_import_runspace.installAdmitted(missing_import_admitted));
    var transcript_only_runtime = boundary.Runtime.init(std.testing.allocator);
    defer transcript_only_runtime.deinit();
    var transcript_only_run = try transcript_only_admitted.start(fixtures.Ports.Target, PortsReplayEnv, &transcript_only_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
    });
    defer transcript_only_run.deinit();
    while (true) {
        switch (try transcript_only_run.next()) {
            .done => |value| {
                try std.testing.expectEqual(@as(i32, 7), value);
                break;
            },
            .port_required => _ = try transcript_only_run.dispatch(),
            .parked => return error.ExpectedReplayCompletion,
            .failed => return error.ExpectedReplayCompletion,
        }
    }
    var replay_sink_transcript = world.Transcript.init(std.testing.allocator);
    defer replay_sink_transcript.deinit();
    var replay_sink_runtime = boundary.Runtime.init(std.testing.allocator);
    defer replay_sink_runtime.deinit();
    var replay_sink_run = try transcript_only_admitted.start(fixtures.Ports.Target, PortsReplayEnv, &replay_sink_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript = &replay_sink_transcript,
    });
    defer replay_sink_run.deinit();
    while (true) {
        switch (try replay_sink_run.next()) {
            .done => |value| {
                try std.testing.expectEqual(@as(i32, 7), value);
                break;
            },
            .port_required => _ = try replay_sink_run.dispatch(),
            .parked => return error.ExpectedReplayCompletion,
            .failed => return error.ExpectedReplayCompletion,
        }
    }

    const package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .replay_only,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, package, .{});
    try std.testing.expect(result.report.accepted);
    try std.testing.expect(result.report.handoff_preflight_report_fingerprint != null);
    var admitted = result.admitted_run orelse return error.ExpectedAdmittedRun;

    var wrong_image = image;
    wrong_image.transcript_image_fingerprint +%= 1;
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.HandoffDenied, admitted.start(fixtures.Ports.Target, PortsReplayEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &wrong_image,
    }));
    const forged_encoded = try image.encode(std.testing.allocator);
    defer std.testing.allocator.free(forged_encoded);
    var forged_image = try world.TranscriptImage.decode(std.testing.allocator, forged_encoded);
    defer forged_image.deinit(std.testing.allocator);
    forged_image.events[0].source_run = !forged_image.events[0].source_run;
    try std.testing.expectEqual(image.transcript_image_fingerprint, forged_image.transcript_image_fingerprint);
    var forged_runtime = boundary.Runtime.init(std.testing.allocator);
    defer forged_runtime.deinit();
    try std.testing.expectError(error.HandoffDenied, admitted.start(fixtures.Ports.Target, PortsReplayEnv, &forged_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .transcript_image = &forged_image,
    }));
}

test "admitted run resume rejects non fresh options" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    var admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xabc,
        .target_ref = target_ref,
        .mode = .resume_parked,
    });
    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var ctx: PortsCtx = .{};
    try std.testing.expectError(error.HandoffDenied, admitted.@"resume"(std.testing.allocator, fixtures.Ports.Target, PortsEnv, &runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.replay,
        .ctx = &ctx,
    }));

    const permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var permit_admitted = world.Admission.AdmittedRun.init(.{
        .admission_receipt_fingerprint = 0xdef,
        .target_ref = target_ref,
        .run_permit = permit,
        .mode = .resume_parked,
    });
    var missing_permit_runtime = boundary.Runtime.init(std.testing.allocator);
    defer missing_permit_runtime.deinit();
    try std.testing.expectError(error.SupervisionDenied, permit_admitted.@"resume"(std.testing.allocator, fixtures.Ports.Target, PortsEnv, &missing_permit_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
    }));

    const wrong_permit = world.Supervision.issue(fixtures.Ports.Target, PortsEnv, .{
        .mode = .fresh,
        .admission_receipt_fingerprint = 0x123,
        .policy = world.SupervisionPolicy.strict_fresh,
    });
    var wrong_permit_runtime = boundary.Runtime.init(std.testing.allocator);
    defer wrong_permit_runtime.deinit();
    try std.testing.expectError(error.SupervisionDenied, permit_admitted.@"resume"(std.testing.allocator, fixtures.Ports.Target, PortsEnv, &wrong_permit_runtime, .{}, .{
        .allocator = std.testing.allocator,
        .mode = world.Mode.fresh,
        .ctx = &ctx,
        .permit = wrong_permit,
    }));
}

test "decoded admission owns admitted run images after package deinit" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    var transcript = world.Transcript.init(std.testing.allocator);
    defer transcript.deinit();
    try recordPortsTranscript(&transcript);
    var image = try transcript.toImage(std.testing.allocator, .{ .value_policy = world.ValuePolicy.portable });
    defer image.deinit(std.testing.allocator);
    const state = world.RunState.init(.{
        .target_ref_fingerprint = target_ref.target_ref_fingerprint,
        .transcript_image_fingerprint = image.transcript_image_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .replay_only_run,
        .target_ref = target_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .replay_run,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .transcript_image = image,
        .requested_mode = .replay_only,
    });
    const encoded = try package.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try world.Admission.TransferPackage.decode(std.testing.allocator, encoded);
    const decoded_run_events = decoded.run_image.?.transcript_image;
    try std.testing.expect(decoded_run_events == null);
    const decoded_transcript_events_ptr = decoded.transcript_image.?.events.ptr;

    var result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.replay_only,
    }).admitForTarget(fixtures.Ports.Target, PortsReplayEnv, decoded, .{ .allocator = std.testing.allocator });
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.report.accepted);
    try std.testing.expect(result.admitted_run.?.owns_run_image);
    try std.testing.expect(result.admitted_run.?.owns_transcript_image);
    try std.testing.expect(result.admitted_run.?.transcript_image.?.events.ptr != decoded_transcript_events_ptr);

    decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(image.transcript_image_fingerprint, result.admitted_run.?.transcript_image.?.transcript_image_fingerprint);
}

test "module handoff admission rejects target mismatch" {
    const ports_ref = world.TargetRef.fromTarget(fixtures.Ports.Target);
    const agent_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Ports.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Ports.Target)});
    const state = world.RunState.init(.{
        .target_ref_fingerprint = ports_ref.target_ref_fingerprint,
        .status = .completed,
    });
    const run_image = world.RunImage.init(.{
        .kind = .completed_run,
        .target_ref = ports_ref,
        .import_set_fingerprint = world.ImportSet.fromTarget(fixtures.Ports.Target).import_set_fingerprint,
        .current_state = state,
    }).withModuleRef(module_ref, null);
    const package = world.Admission.TransferPackage.init(.{
        .kind = .completed_run,
        .target_ref = agent_ref,
        .module_ref = module_ref,
        .run_image = run_image,
        .requested_mode = .completed_replay,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Ports.Target, PortsEnv, package, .{});
    try std.testing.expect(!result.report.accepted);
    try std.testing.expectEqual(world.Admission.AdmissionBlocker.PackageInvalid, result.report.blockers[0]);
}

test "agent admission transfer admitted" {
    const target_ref = world.TargetRef.fromTarget(fixtures.Agent.Target);
    const module_ref = world.Admission.ModuleRef.fromTarget(fixtures.Agent.Target);
    const registry = world.Admission.TargetRegistry.init(&.{world.Admission.TargetRegistry.register(fixtures.Agent.Target)});
    const package = world.Admission.TransferPackage.init(.{
        .kind = .module_reference,
        .target_ref = target_ref,
        .module_ref = module_ref,
        .requested_mode = .continue_fresh,
    });
    const result = world.Admission.Admitter.init(.{
        .registry = registry,
        .policy = world.Admission.AdmissionPolicy.test_fixture,
    }).admitForTarget(fixtures.Agent.Target, AgentEnv, package, .{});
    try std.testing.expect(result.report.accepted);
    try std.testing.expect(result.admitted_run != null);
    try std.testing.expectEqual(module_ref.module_ref_fingerprint, result.report.module_ref_fingerprint.?);
}
