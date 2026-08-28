const boundary = @import("boundary");
const world = @import("world");

const Aliased = struct {
    pub const Payload = u32;
    pub const Resume = u32;
    pub const semantic_identity = "generic.aliased.v1";
};
const u32_type: boundary.ir.ValueType = .{ .scalar = .u32 };
const resume_arguments = [_]boundary.ir.EdgeArgument{.@"resume"};
const Body = struct {
    pub const InitialArgs = u32;
    pub const Result = u32;
    pub const Failure = enum { rejected };
    pub const effect_sites = .{ Aliased, Aliased };
    pub const schema_types = .{};
    pub const control_ir: boundary.ir.Program = .{
        .label = "aliased-unreachable-site",
        .value_types = &.{ u32_type, u32_type },
        .blocks = &.{
            .{
                .id = 0,
                .parameters = &.{0},
                .terminator = .{ .@"suspend" = .{
                    .kind = .effect,
                    .site_id = 0,
                    .request_values = &.{0},
                    .continuation = .{
                        .target = 1,
                        .arguments = &resume_arguments,
                    },
                    .resume_type = u32_type,
                } },
            },
            .{
                .id = 1,
                .parameters = &.{1},
                .terminator = .{ .return_value = 1 },
            },
        },
        .entry = 0,
        .result_type = u32_type,
    };
};
const Program = boundary.program("aliased-unreachable-site", Body);
const Invalid = world.system(.{
    .name = "aliased-unreachable-site-system",
    .root = Program,
    .handlers = .{},
    .morphisms = .{},
    .external = .{
        world.systemExternal(.{
            .consumer = Program,
            .site = Aliased,
            .site_ordinal = 0,
        }),
        world.systemExternal(.{
            .consumer = Program,
            .site = Aliased,
            .site_ordinal = 1,
        }),
    },
});

comptime {
    _ = Invalid.Program;
}
