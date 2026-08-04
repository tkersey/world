const boundary = @import("boundary");
const effects = @import("effects.zig");

const cir = boundary.ir;

const ResearchLookup = struct {
    pub const id: u32 = 0;
    pub const semantic_identity = "research.lookup.v2";
    pub const Payload = effects.ResearchRequest;
    pub const Resume = effects.ResearchResponse;
};

const value_types = [_]cir.ValueType{
    .{ .schema = 0 }, // v0  entry request
    .{ .schema = 6 }, // v1  lookup response
    .{ .schema = 5 }, // v2  response items
    .{ .scalar = .u32 }, // v3  item count
    .{ .scalar = .u32 }, // v4  initial index
    .{ .schema = 7 }, // v5  initial digest
    .{ .schema = 5 }, // v6  loop items
    .{ .scalar = .u32 }, // v7  loop count
    .{ .scalar = .u32 }, // v8  loop index
    .{ .schema = 7 }, // v9  loop digest
    .{ .scalar = .boolean }, // v10 loop condition
    .{ .schema = 5 }, // v11 body items
    .{ .scalar = .u32 }, // v12 body count
    .{ .scalar = .u32 }, // v13 body index
    .{ .schema = 7 }, // v14 body digest
    .{ .schema = 2 }, // v15 current item
    .{ .schema = 3 }, // v16 title
    .{ .schema = 4 }, // v17 summary
    .{ .schema = 7 }, // v18 digest after title
    .{ .schema = 8 }, // v19 separator
    .{ .schema = 7 }, // v20 digest after separator
    .{ .schema = 7 }, // v21 digest after summary
    .{ .schema = 7 }, // v22 completed item digest
    .{ .scalar = .u32 }, // v23 one
    .{ .scalar = .u32 }, // v24 next index
    .{ .schema = 7 }, // v25 result digest
    .{ .scalar = .u32 }, // v26 result count
    .{ .schema = 9 }, // v27 result
    .{ .scalar = .u32 }, // v28 request maximum items
    .{ .scalar = .boolean }, // v29 response length is below request maximum
    .{ .scalar = .u32 }, // v30 bounded item count
    .{ .scalar = .u32 }, // v31 resumed request maximum items
};

const lookup_continuation_arguments = [_]cir.EdgeArgument{
    .@"resume",
    .{ .value = 28 },
};
const initial_loop_arguments = [_]cir.EdgeArgument{
    .{ .value = 2 },
    .{ .value = 30 },
    .{ .value = 4 },
    .{ .value = 5 },
};
const loop_body_arguments = [_]cir.EdgeArgument{
    .{ .value = 6 },
    .{ .value = 7 },
    .{ .value = 8 },
    .{ .value = 9 },
};
const loop_exit_arguments = [_]cir.EdgeArgument{
    .{ .value = 9 },
    .{ .value = 7 },
};
const loop_back_arguments = [_]cir.EdgeArgument{
    .{ .value = 11 },
    .{ .value = 12 },
    .{ .value = 24 },
    .{ .value = 22 },
};

const entry_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 28,
    .operands = &.{0},
    .operation = .{ .product_extract = 1 },
}};

const response_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 2,
        .operands = &.{1},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 3,
        .operands = &.{2},
        .operation = .vector_length,
    },
    .{
        .kind = .pure,
        .result = 29,
        .operands = &.{ 3, 31 },
        .operation = .integer_less_than,
    },
    .{
        .kind = .pure,
        .result = 30,
        .operands = &.{ 29, 3, 31 },
        .operation = .select,
    },
    .{
        .kind = .constant,
        .result = 4,
        .operation = .{ .constant = 0 },
    },
    .{
        .kind = .pure,
        .result = 5,
        .operation = .text_empty,
    },
};

const loop_header_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 10,
    .operands = &.{ 8, 7 },
    .operation = .integer_less_than,
}};

const loop_body_instructions = [_]cir.Instruction{
    .{
        .kind = .pure,
        .result = 15,
        .operands = &.{ 11, 13 },
        .operation = .vector_get,
    },
    .{
        .kind = .pure,
        .result = 16,
        .operands = &.{15},
        .operation = .{ .product_extract = 0 },
    },
    .{
        .kind = .pure,
        .result = 17,
        .operands = &.{15},
        .operation = .{ .product_extract = 1 },
    },
    .{
        .kind = .pure,
        .result = 18,
        .operands = &.{ 14, 16 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 19,
        .operation = .{ .constant = 1 },
    },
    .{
        .kind = .pure,
        .result = 20,
        .operands = &.{ 18, 19 },
        .operation = .text_append,
    },
    .{
        .kind = .pure,
        .result = 21,
        .operands = &.{ 20, 17 },
        .operation = .text_append,
    },
    .{
        .kind = .pure,
        .result = 22,
        .operands = &.{ 21, 19 },
        .operation = .text_append,
    },
    .{
        .kind = .constant,
        .result = 23,
        .operation = .{ .constant = 2 },
    },
    .{
        .kind = .pure,
        .result = 24,
        .operands = &.{ 13, 23 },
        .operation = .integer_add,
    },
};

const result_instructions = [_]cir.Instruction{.{
    .kind = .pure,
    .result = 27,
    .operands = &.{ 25, 26 },
    .operation = .product_construct,
}};

const blocks = [_]cir.Block{
    .{
        .id = 0,
        .parameters = &.{0},
        .instructions = &entry_instructions,
        .terminator = .{ .@"suspend" = .{
            .kind = .effect,
            .site_id = 0,
            .request_values = &.{0},
            .continuation = .{
                .target = 1,
                .arguments = &lookup_continuation_arguments,
            },
            .resume_type = .{ .schema = 6 },
        } },
    },
    .{
        .id = 1,
        .parameters = &.{ 1, 31 },
        .instructions = &response_instructions,
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &initial_loop_arguments,
        } },
    },
    .{
        .id = 2,
        .role = .loop_header,
        .parameters = &.{ 6, 7, 8, 9 },
        .instructions = &loop_header_instructions,
        .terminator = .{ .branch = .{
            .condition = 10,
            .then_edge = .{
                .target = 3,
                .arguments = &loop_body_arguments,
            },
            .else_edge = .{
                .target = 4,
                .arguments = &loop_exit_arguments,
            },
        } },
    },
    .{
        .id = 3,
        .parameters = &.{ 11, 12, 13, 14 },
        .instructions = &loop_body_instructions,
        .terminator = .{ .jump = .{
            .target = 2,
            .arguments = &loop_back_arguments,
        } },
    },
    .{
        .id = 4,
        .role = .terminal_handoff,
        .parameters = &.{ 25, 26 },
        .instructions = &result_instructions,
        .terminator = .{ .return_value = 27 },
    },
};

const Body = struct {
    pub const InitialArgs = effects.ResearchRequest;
    pub const Result = effects.DigestResult;
    pub const Failure = enum {
        arithmetic_overflow,
        capacity_exceeded,
        invalid_index,
    };
    pub const contract_bytes = "research-digest-provider-v2\x00machine-owned";
    pub const constants = .{
        @as(u32, 0),
        effects.Separator.fromSlice("\n") catch unreachable,
        @as(u32, 1),
    };
    pub const effect_sites = .{ResearchLookup};
    pub const schema_types = effects.schema_types;
    pub const control_ir: cir.Program = .{
        .label = "research-digest-provider-v2",
        .value_types = &value_types,
        .blocks = &blocks,
        .entry = 0,
        .result_type = .{ .schema = 9 },
    };
};

pub const Program = boundary.program("research-digest-provider-v2", Body);
pub const Machine = Program.compile(.{
    .maximum_frames = 8,
    .maximum_state_bytes = 128 * 1024,
    .maximum_machine_fuel = 1_000_000,
});
pub const LookupSite = Machine.EffectRow.site(0);
