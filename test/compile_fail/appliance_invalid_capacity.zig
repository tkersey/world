const world = @import("world");
const fixtures = @import("world_fixtures");

const invalid_capacity = blk: {
    var capacity = world.Appliance.Capacity.tiny_one_port;
    capacity.max_command_bytes = 0;
    break :blk capacity;
};

const BadAppliance = world.Appliance.Define(fixtures.Strict.Target, .{
    .profile = world.Appliance.Profile.wasm_small,
    .capacity = invalid_capacity,
});

comptime {
    _ = BadAppliance;
}
