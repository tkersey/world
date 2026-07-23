const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "incompatible-provider",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{world.v1.handle(fixtures.RootSite, fixtures.RootMachine)},
});

test {
    _ = App;
}
