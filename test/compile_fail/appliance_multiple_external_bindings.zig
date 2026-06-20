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
    .label = "multi-external",
    .value_policy = world.ValuePolicy.portable,
});

const BadAppliance = world.Appliance.Define(fixtures.Agent.Target, .{
    .profile = world.Appliance.Profile.wasm_agent,
    .capacity = world.Appliance.Capacity.wasm_agent,
    .actuation_bindings = .{
        world.bindActuator(DecidePort, Actuator),
        world.bindActuator(ToolPort, Actuator),
    },
});

test "multiple external actuation bindings are rejected until Core can drive them" {
    _ = BadAppliance;
}
