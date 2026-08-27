const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "incompatible-provider",
    .root = fixtures.RootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = fixtures.RootProgram,
        .site = fixtures.InternalPolicy,
        .provider = fixtures.WrongProviderProgram,
    })},
    .morphisms = .{},
    .external = .{fixtures.Observe},
});

comptime {
    _ = Invalid.Program;
}
