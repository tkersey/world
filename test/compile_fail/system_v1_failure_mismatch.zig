const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const Invalid = world.system(.{
    .name = "failure-mismatch",
    .root = fixtures.FailureRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = fixtures.FailureRootProgram,
        .site = fixtures.FailureSite,
        .provider = fixtures.FailureProviderProgram,
    })},
    .morphisms = .{},
    .external = .{},
});

comptime {
    _ = Invalid.Program;
}
