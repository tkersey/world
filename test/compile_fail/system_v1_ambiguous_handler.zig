const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Handler = world.systemHandle(.{
    .consumer = fixtures.RootProgram,
    .site = fixtures.InternalPolicy,
    .provider = fixtures.ProviderProgram,
});
const Invalid = world.system(.{
    .name = "ambiguous",
    .root = fixtures.RootProgram,
    .handlers = .{ Handler, Handler },
    .morphisms = .{},
    .external = .{ fixtures.Observe, fixtures.ProviderObserve },
});

comptime {
    _ = Invalid.Program;
}
