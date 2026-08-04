const boundary = @import("boundary");
const world = @import("world");

const Value = boundary.Text(16);
const value_type: boundary.ir.ValueType = .{ .schema = 0 };
const continuation_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

fn Effect(comptime source_id: u32) type {
    return struct {
        pub const id = source_id;
        pub const semantic_identity = "duplicate.site.v1";
        pub const Payload = Value;
        pub const Resume = Value;
    };
}

const blocks = [_]boundary.ir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{ .target = 1, .arguments = &continuation_arguments },
            .resume_type = value_type,
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 1,
            .request_values = &.{1},
            .continuation = .{ .target = 2, .arguments = &continuation_arguments },
            .resume_type = value_type,
        } },
    },
    .{ .id = 2, .parameters = &.{2}, .terminator = .{ .return_value = 2 } },
};

const Body = struct {
    pub const InitialArgs = Value;
    pub const Result = Value;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ Effect(0), Effect(1) };
    pub const schema_types = .{Value};
    pub const control_ir: boundary.ir.Program = .{
        .label = "duplicate-site-identity",
        .value_types = &.{ value_type, value_type, value_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = value_type,
    };
};

const Machine = boundary.program("duplicate-site-identity", Body).compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 16 * 1024,
    .maximum_machine_fuel = 4096,
});

const App = world.v1.application(.{
    .name = "duplicate-site-identity",
    .version = "2.0.0",
    .root = Machine,
    .external = .{
        world.v1.external(Machine, 0, .{
            .site_identity = "duplicate.site.v1",
            .interface = "duplicate.first.v1",
        }),
        world.v1.external(Machine, 1, .{
            .site_identity = "duplicate.site.v1",
            .interface = "duplicate.second.v1",
        }),
    },
});

test {
    _ = App;
}
