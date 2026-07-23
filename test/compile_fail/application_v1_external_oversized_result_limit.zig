const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "oversized-result-limit",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .limits = .{ .maximum_result_bytes = 32 },
    .external = .{world.v1.external(fixtures.RootSite, .{
        .interface = "test.oversized-result-limit.v1",
        .maximum_result_bytes = 33,
    })},
});

test {
    _ = App;
}
