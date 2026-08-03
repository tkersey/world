const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "provider-cycle",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{
        world.v1.handle(
            fixtures.RootMachine,
            0,
            "world.test.root.v2",
            fixtures.ProviderMachine,
        ),
        world.v1.handle(
            fixtures.ProviderMachine,
            0,
            "world.test.provider.v2",
            fixtures.ProviderMachine,
        ),
    },
});

test {
    _ = App;
}
