const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "site-identity-mismatch",
    .version = "2.0.0",
    .root = fixtures.RootMachine,
    .external = .{world.v1.external(fixtures.RootMachine, 0, .{
        .site_identity = "world.test.wrong-site.v2",
        .interface = "test.site-identity-mismatch.v1",
    })},
});

test {
    _ = App;
}
