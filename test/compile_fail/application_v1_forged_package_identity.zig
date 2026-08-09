const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.application(.{
    .name = "forged-package-identity",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .external = .{world.external(fixtures.RootMachine, 0, .{
        .site_identity = "world.test.root.v2",
        .interface = "test.v1",
    })},
    .boundary_package_version = "forged",
    .world_package_version = "forged",
});

test {
    _ = App;
}
