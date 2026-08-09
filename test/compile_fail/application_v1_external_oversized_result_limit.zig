const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.application(.{
    .name = "oversized-result-limit",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .limits = .{ .maximum_result_bytes = 32 },
    .external = .{world.external(fixtures.RootMachine, 0, .{
        .site_identity = "world.test.root.v2",
        .interface = "test.oversized-result-limit.v1",
        .maximum_result_bytes = 33,
    })},
});

test {
    _ = App;
}
