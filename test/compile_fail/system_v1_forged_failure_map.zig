const fixtures = @import("system_v1_fixtures");
const world = @import("world");

const ForgedMap = struct {
    pub const SourceFailure = fixtures.DynamicProviderFailure;
    pub const TargetFailure = fixtures.DynamicSystemFailure;
    pub const source_tags = [_]u32{3};
    pub const targets = [_]TargetFailure{.policy_retry};
};
const Invalid = world.system(.{
    .name = "forged-failure-map",
    .root = fixtures.DynamicRootProgram,
    .handlers = .{world.systemHandle(.{
        .consumer = fixtures.DynamicRootProgram,
        .site = fixtures.DynamicFailureSite,
        .provider = fixtures.DynamicProviderProgram,
        .failure_morphism = ForgedMap,
    })},
    .morphisms = .{},
    .external = .{},
});

comptime {
    _ = Invalid.Program;
}
