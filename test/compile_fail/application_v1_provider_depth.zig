const boundary = @import("boundary");
const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const value_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

fn Site(comptime identity: []const u8) type {
    return struct {
        pub const id: u32 = 0;
        pub const semantic_identity = identity;
        pub const Payload = u32;
        pub const Resume = u32;
    };
}

fn ProviderBody(comptime identity: []const u8) type {
    return struct {
        const blocks = [_]boundary.ir.Block{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{
                        .target = 1,
                        .arguments = &continuation_arguments,
                    },
                    .resume_type = value_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        };

        pub const InitialArgs = u32;
        pub const Result = u32;
        pub const Failure = enum { rejected };
        pub const effect_sites = .{Site(identity)};
        pub const schema_types = .{};
        pub const control_ir: boundary.ir.Program = .{
            .label = identity,
            .value_types = &.{ value_type, value_type },
            .blocks = &blocks,
            .entry = 0,
            .result_type = value_type,
        };
    };
}

const ProviderMachineA = boundary.program(
    "world-v2-provider-depth-a",
    ProviderBody("world.test.depth.a.v2"),
).compile(.{});
const ProviderMachineB = boundary.program(
    "world-v2-provider-depth-b",
    ProviderBody("world.test.depth.b.v2"),
).compile(.{});

const App = world.v1.application(.{
    .name = "provider-depth",
    .version = "2.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{
        world.v1.handle(
            fixtures.RootMachine,
            0,
            "world.test.root.v2",
            ProviderMachineA,
        ),
        world.v1.handle(
            ProviderMachineA,
            0,
            "world.test.depth.a.v2",
            ProviderMachineB,
        ),
    },
    .external = .{world.v1.external(ProviderMachineB, 0, .{
        .site_identity = "world.test.depth.b.v2",
        .interface = "test.depth.v1",
    })},
    .limits = .{ .maximum_provider_depth = 1 },
});

test {
    _ = App;
}
