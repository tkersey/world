const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "ambiguous-binding",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .external = .{
        world.v1.external(fixtures.RootSite, .{ .interface = "test.first.v1" }),
        world.v1.external(fixtures.RootSite, .{ .interface = "test.second.v1" }),
    },
});

test {
    _ = App;
}
