const boundary = @import("boundary");
const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const ProviderBodyA = struct {
    pub const compiled_plan = fixtures.providerEffectPlan("world-v1-provider-depth-a");
};
const ProviderProgramA = boundary.program("world-v1-provider-depth-a", struct {}, ProviderBodyA);
const ProviderMachineA = boundary.staticMachine(ProviderProgramA, .{});
const ProviderSiteA = ProviderMachineA.EffectRow.operationSite("provider", "external", 0);

const ProviderBodyB = struct {
    pub const compiled_plan = fixtures.providerEffectPlan("world-v1-provider-depth-b");
};
const ProviderProgramB = boundary.program("world-v1-provider-depth-b", struct {}, ProviderBodyB);
const ProviderMachineB = boundary.staticMachine(ProviderProgramB, .{});
const ProviderSiteB = ProviderMachineB.EffectRow.operationSite("provider", "external", 0);

const App = world.v1.application(.{
    .name = "provider-depth",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{
        world.v1.handle(fixtures.RootSite, ProviderMachineA),
        world.v1.handle(ProviderSiteA, ProviderMachineB),
    },
    .external = .{world.v1.external(ProviderSiteB, .{ .interface = "test.depth.v1" })},
    .limits = .{ .maximum_provider_depth = 1 },
});

test {
    _ = App;
}
