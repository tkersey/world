const world = @import("world");
const fixtures = @import("world_fixtures");

const Ctx = struct {};

fn decide(_: *Ctx, _: []const u8) !fixtures.Agent.Action {
    return .{ .final = "done" };
}

fn tool(_: *Ctx, _: []const u8) ![]const u8 {
    return "tool";
}

const DecidePort = world.port(fixtures.Agent.Target, fixtures.Agent.Decide, decide);
const ToolPort = world.port(fixtures.Agent.Target, fixtures.Agent.Tool, tool);
const Actuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "bad-agent",
    .value_policy = world.ValuePolicy.portable,
});
const ToolImport = world.ImportRequirement.fromTargetPort(fixtures.Agent.Target, 1);

const BadAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .providers = .{fixtures.Strict.Target},
    .assembly_recipe = .{
        .covered_world_ports = .{ToolImport.world_port_id},
        .link_plan_fingerprint = 0xBADC_0001,
        .link_certificate_fingerprint = 0xBADC_0002,
        .assembly_fingerprint = 0xBADC_0003,
        .fabric_plan_fingerprints = .{0xBADC_0004},
    },
    .actuation_bindings = .{
        world.bindActuator(DecidePort, Actuator),
        world.bindActuator(ToolPort, Actuator),
    },
});

test "assembly-covered port also bound is rejected" {
    _ = BadAppliance;
}
