const std = @import("std");
const world = @import("world");
const fixtures = @import("world_fixtures");

const AppliancePortsCtx = struct {};

fn applianceApprove(_: *AppliancePortsCtx, _: []const u8) !i32 {
    return 1;
}

fn applianceDecide(_: *AppliancePortsCtx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "final=actuate skeleton complete" };
}

const AppliancePortsDecl = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, applianceApprove);
const ApplianceAgentDecideDecl = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, applianceDecide);
const ApplianceActuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "appliance.model",
    .supported_response_statuses = world.Actuation.ResponseStatusSet.all,
    .value_policy = world.ValuePolicy.portable,
});
const AgentToolImport = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 1);

pub const PortsAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
    .profile = world.Appliance.Profile.wasm_small,
    .capacity = world.Appliance.Capacity.tiny_one_port,
    .actuation_bindings = .{world.bindActuator(AppliancePortsDecl, ApplianceActuator)},
    .metadata = "example-one-port",
});

pub const StrictAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
    .profile = world.Appliance.Profile.wasm_small,
    .capacity = world.Appliance.Capacity.tiny_one_port,
    .metadata = "example-strict",
});

pub const AgentAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .providers = .{fixtures.Strict.Target},
    .assembly_recipe = .{
        .covered_world_ports = .{AgentToolImport.world_port_id},
        .link_plan_fingerprint = 0xA6E7_1001,
        .link_certificate_fingerprint = 0xA6E7_1002,
        .assembly_fingerprint = 0xA6E7_1003,
        .fabric_plan_fingerprints = .{0xA6E7_1004},
        .residual_import_set_fingerprint = 0xA6E7_1005,
    },
    .actuation_bindings = .{world.bindActuator(ApplianceAgentDecideDecl, ApplianceActuator)},
    .metadata = "example-agent",
});

pub const agent_wasm_manifest_fingerprint: u64 = 0xe9c5e72a2d566095;
pub const agent_wasm_capacity_fingerprint: u64 = 0x5fcf964fbaa4a66b;
pub const agent_wasm_memory_plan_fingerprint: u64 = 0xed1c9222ab3bed1d;
pub const agent_wasm_required_memory_bytes: u64 = 4_259_840;
pub const agent_wasm_max_linear_memory_pages: u32 = 65;

pub fn bootCommand(manifest: world.Appliance.Manifest) world.Appliance.Command {
    return world.Appliance.Command.init(.{
        .kind = .boot,
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = 0,
    });
}

pub fn continueCommand(manifest: world.Appliance.Manifest, sequence: u64, previous_receipt: u64) world.Appliance.Command {
    return world.Appliance.Command.init(.{
        .kind = .@"continue",
        .manifest_fingerprint = manifest.manifest_fingerprint,
        .turn_sequence_number = sequence,
        .previous_turn_receipt_fingerprint = previous_receipt,
    });
}

pub fn submit(core: *world.Appliance.Core, allocator: std.mem.Allocator, command: world.Appliance.Command) !void {
    const bytes = try command.encode(allocator);
    defer allocator.free(bytes);
    try core.submit(bytes);
    try core.executeTurn();
}

pub fn decodeOutput(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    output_bytes: []const u8,
) !world.Appliance.TurnOutput {
    return decodeOutputWithCapacity(allocator, manifest, output_bytes, world.Appliance.Capacity.tiny_one_port);
}

pub fn decodeOutputWithCapacity(
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    output_bytes: []const u8,
    capacity: world.Appliance.Capacity,
) !world.Appliance.TurnOutput {
    return world.Appliance.TurnOutput.decode(
        allocator,
        output_bytes,
        manifest.manifest_fingerprint,
        capacity,
    );
}

pub fn submitAndDecode(
    core: *world.Appliance.Core,
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    command: world.Appliance.Command,
) !world.Appliance.TurnOutput {
    try submit(core, allocator, command);
    return decodeOutput(allocator, manifest, core.readOutput());
}

pub fn submitAndDecodeWithCapacity(
    core: *world.Appliance.Core,
    allocator: std.mem.Allocator,
    manifest: world.Appliance.Manifest,
    capacity: world.Appliance.Capacity,
    command: world.Appliance.Command,
) !world.Appliance.TurnOutput {
    try submit(core, allocator, command);
    return decodeOutputWithCapacity(allocator, manifest, core.readOutput(), capacity);
}

pub fn hostReplyFor(request: world.Appliance.HostRequest, response_fingerprint: u64) world.Appliance.HostReply {
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = .responded,
        .response_fingerprint = response_fingerprint,
        .response_kind = .frame_value_image,
        .response_bytes = "frame-value:approved",
        .host_evidence_fingerprint = response_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:example",
        .attempt_number = 1,
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
    });
}

pub fn hostReplyWithStatusFor(
    request: world.Appliance.HostRequest,
    status: world.Appliance.HostOutcomeStatus,
) world.Appliance.HostReply {
    const outcome = world.Appliance.HostOutcome.init(.{
        .host_request_fingerprint = request.request_fingerprint,
        .intent_fingerprint = request.intent_fingerprint,
        .envelope_fingerprint = request.envelope_fingerprint,
        .idempotency_key_fingerprint = request.idempotency_key_fingerprint,
        .status = status,
        .host_evidence_fingerprint = request.request_fingerprint ^ 0xE11D,
        .host_evidence_bytes = "host-claim:example-nonterminal",
        .attempt_number = 1,
    });
    return world.Appliance.HostReply.init(.{
        .target_host_request_fingerprint = request.request_fingerprint,
        .outcome = outcome,
    });
}

pub fn bytesFingerprint(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}
