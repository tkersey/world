const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "handler-cycle",
    .root = fixtures.CycleAProgram,
    .handlers = .{
        world.systemHandle(.{
            .consumer = fixtures.CycleAProgram,
            .site = fixtures.CycleASite,
            .provider = fixtures.CycleBProgram,
        }),
        world.systemHandle(.{
            .consumer = fixtures.CycleBProgram,
            .site = fixtures.CycleBSite,
            .provider = fixtures.CycleAProgram,
        }),
    },
    .morphisms = .{},
    .external = .{},
});

comptime {
    _ = Invalid.Program;
}
