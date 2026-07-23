const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "provider-state-capacity",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{world.v1.handle(fixtures.RootSite, fixtures.ProviderMachine)},
    .external = .{world.v1.external(fixtures.ProviderSite, .{
        .interface = "test.provider-state-capacity.v1",
    })},
    .limits = .{ .maximum_state_bytes = 20 * 1024 },
});

test {
    _ = App;
}
