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
    .label = "zero-host-reply-capacity",
    .value_policy = world.ValuePolicy.portable,
});

const zero_host_reply_capacity = blk: {
    var capacity = world.Appliance.Capacity.tiny_one_port;
    capacity.max_host_replies_per_turn = 0;
    break :blk capacity;
};

const BadAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
    .profile = world.Appliance.Profile.wasm_small,
    .capacity = zero_host_reply_capacity,
    .actuation_bindings = .{world.bindActuator(ApprovalPort, Actuator)},
});

test "external actuation requires host reply capacity" {
    _ = BadAppliance;
}
