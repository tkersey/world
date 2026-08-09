const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.application(.{
    .name = "ambiguous-binding",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .external = .{
        world.external(fixtures.RootMachine, 0, .{
            .site_identity = "world.test.root.v2",
            .interface = "test.first.v1",
        }),
        world.external(fixtures.RootMachine, 0, .{
            .site_identity = "world.test.root.v2",
            .interface = "test.second.v1",
        }),
    },
});

test {
    _ = App;
}
