const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.application(.{
    .name = "provider-cycle",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{
        world.handle(
            fixtures.RootMachine,
            0,
            "world.test.root.v2",
            fixtures.ProviderMachine,
        ),
        world.handle(
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
