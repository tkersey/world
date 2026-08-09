const boundary = @import("boundary");

const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const continuation_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};

const Effect = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "world.parity.one-effect.v1";
    pub const Payload = u32;
    pub const Resume = u32;
};

const Body = struct {
    const blocks = [_]boundary.ir.Block{
        .{
            .id = 0,
            .parameters = &.{0},
            .terminator = .{ .@"suspend" = .{
                .kind = .effect,
                .site_id = 0,
                .request_values = &.{0},
                .continuation = .{ .target = 1, .arguments = &continuation_arguments },
                .resume_type = u32_type,
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
    pub const effect_sites = .{Effect};
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "world-parity-one-effect",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &blocks,
        .entry = 0,
        .result_type = u32_type,
    };
};

const Machine = boundary.program("world-parity-one-effect", Body).compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 16 * 1024,
    .maximum_machine_fuel = 1024,
});

pub fn App(comptime world: type) type {
    return world.application(.{
        .name = "world-parity-one-effect",
        .version = "1.0.0",
        .boundary_package_version = "1.0.0",
        .world_package_version = "2.0.0",
        .root = Machine,
        .limits = .{
            .maximum_initial_args_bytes = 64 * 1024,
            .maximum_state_bytes = 64 * 1024,
            .maximum_payload_bytes = 64 * 1024,
            .maximum_result_bytes = 64 * 1024,
            .maximum_host_claim_bytes = 8 * 1024,
            .maximum_host_metadata_bytes = 8 * 1024,
            .maximum_failure_bytes = 8 * 1024,
        },
        .external = .{world.external(Machine, 0, .{
            .site_identity = "world.parity.one-effect.v1",
            .interface = "world.parity.one-effect.v1",
            .authority = world.Authority.model,
        })},
    });
}
