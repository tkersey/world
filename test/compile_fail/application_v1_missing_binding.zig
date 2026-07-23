const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "missing-binding",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
});

test {
    _ = App;
}
