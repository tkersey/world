const world = @import("world");
const fixtures = @import("world_fixtures");

const BadAppliance = world.Appliance.Define(fixtures.Ports.Target, .{
    .profile = world.Appliance.Profile.wasm_small,
});

test "missing binding rejected at comptime" {
    _ = BadAppliance;
}
