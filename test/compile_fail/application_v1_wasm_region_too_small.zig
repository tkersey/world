const fixtures = @import("application_v1_fixtures");
const world = @import("world");

const Abi = world.ApplicationAbiV1(fixtures.OneEffectApp, .{
    .input_capacity = 1024,
    .output_capacity = 1024 * 1024,
    .scratch_capacity = 4 * 1024 * 1024,
});

comptime {
    _ = Abi;
}
