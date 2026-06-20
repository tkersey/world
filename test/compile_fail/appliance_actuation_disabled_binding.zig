const world = @import("world");
const fixtures = @import("world_fixtures");

const Ctx = struct {};

fn approve(_: *Ctx, _: []const u8) !i32 {
    return 1;
}

const ApprovalPort = world.port(fixtures.Ports.Target, fixtures.Ports.ApprovalRequest, approve);
const Actuator = world.actuator(.{
    .kind = .fixture,
    .class = .deterministic_fixture,
    .label = "actuation-disabled-binding",
    .value_policy = world.ValuePolicy.portable,
});

const BadAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
    .profile = world.Appliance.Profile.minimal,
    .actuation_bindings = .{world.bindActuator(ApprovalPort, Actuator)},
});

test "actuation-disabled profiles reject actuation bindings" {
    _ = BadAppliance;
}
