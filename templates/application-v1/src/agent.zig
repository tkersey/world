const boundary = @import("boundary");
const effects = @import("effects.zig");

const cir = boundary.ir;

const DigestFormat = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "research.digest.format.v2";
    pub const Payload = effects.ResearchRequest;
    pub const Resume = effects.DigestResult;
};

const continuation_arguments = [_]cir.EdgeArgument{.@"resume"};
const value_types = [_]cir.ValueType{
    .{ .schema = 0 },
    .{ .schema = 9 },
};
const blocks = [_]cir.Block{
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
            .resume_type = .{ .schema = 9 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{1},
        .terminator = .{ .return_value = 1 },
    },
};

const Body = struct {
    pub const InitialArgs = effects.ResearchRequest;
    pub const Result = effects.DigestResult;
    pub const Failure = enum { rejected };
    pub const contract_bytes = "research-digest-root-v2\x00machine-provider";
    pub const effect_sites = .{DigestFormat};
    pub const schema_types = effects.schema_types;
    pub const control_ir: cir.Program = .{
        .label = "research-digest-root-v2",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 9 },
    };
};

pub const Program = boundary.program("research-digest-root-v2", Body);
pub const Machine = Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 128 * 1024,
    .maximum_machine_fuel = 4096,
});
pub const FormatSite = Machine.EffectRow.site(0);
