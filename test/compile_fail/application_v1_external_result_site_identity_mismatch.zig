const std = @import("std");
const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const App = world.v1.application(.{
    .name = "external-result-site-identity-mismatch",
    .version = "2.0.0",
    .root = fixtures.RootMachine,
    .external = .{world.v1.external(fixtures.RootMachine, 0, .{
        .site_identity = fixtures.RootMachine.EffectRow.site(0).semantic_identity,
        .interface = "test.external-result-site-identity-mismatch.v1",
    })},
});

test {
    _ = try App.encodeExternalResult(
        std.testing.allocator,
        fixtures.RootMachine,
        0,
        "world.test.wrong-site.v2",
        @as(u32, 41),
    );
}
