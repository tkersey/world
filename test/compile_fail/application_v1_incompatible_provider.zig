const boundary = @import("boundary");
const world = @import("world");
const fixtures = @import("application_v1_fixtures");

const value_type: boundary.ir.ValueType = .{ .scalar = .u64 };
const IncompatibleBody = struct {
    const blocks = [_]boundary.ir.Block{.{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .return_value = 0 },
    }};

    pub const InitialArgs = u64;
    pub const Result = u64;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-v2-incompatible-provider",
        .value_types = &.{value_type},
        .blocks = &blocks,
        .entry = 0,
        .result_type = value_type,
    };
};
const IncompatibleMachine = boundary.program(
    "world-v2-incompatible-provider",
    IncompatibleBody,
).compile(.{});

const App = world.application(.{
    .name = "incompatible-provider",
    .version = "1.0.0",
    .root = fixtures.RootMachine,
    .handlers = .{world.handle(
        fixtures.RootMachine,
        0,
        "world.test.root.v2",
        IncompatibleMachine,
    )},
});

test {
    _ = App;
}
