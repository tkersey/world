const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "provider-cycle",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{
        world.v1.handle(fixtures.RootSite, fixtures.ProviderMachine),
        world.v1.handle(fixtures.ProviderSite, fixtures.ProviderMachine),
    },
});

test {
    _ = App;
}
