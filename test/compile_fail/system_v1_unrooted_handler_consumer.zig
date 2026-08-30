const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "unrooted-handler-consumer",
    .root = fixtures.InertHandlerProvider,
    .handlers = .{world.systemHandle(.{
        .consumer = fixtures.RootProgram,
        .site = fixtures.InternalPolicy,
        .provider = fixtures.ProviderProgram,
    })},
    .morphisms = .{},
    .external = .{},
});

comptime {
    _ = Invalid.Program;
}
