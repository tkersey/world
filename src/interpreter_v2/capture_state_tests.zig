const std = @import("std");
const data = @import("boundary_data_v2");
const process = @import("process.zig");
const p = data.program;
const g = data.graph;

pub const Witness = struct {
    program: data.canonical.Normalized,
    state: data.snapshot.Owned,
    pub fn deinit(self: *Witness) void {
        self.state.deinit();
        self.program.deinit();
    }
};

fn image(allocator: std.mem.Allocator, multi: bool, allowed: bool) !data.canonical.Normalized {
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    const a = temporary.allocator();
    var program = @import("choice_tests.zig").all;
    const wide = program.schemas.len;
    const schemas = try a.alloc(p.Schema, wide + 2);
    @memcpy(schemas[0..wide], program.schemas);
    schemas[wide] = .u16;
    schemas[wide + 1] = .{ .internal = .{ .computation = .{ .parameters = &.{}, .result = 2 } } };
    schemas[6].internal.resumption.use = if (multi) .multi else .linear;
    if (allowed) schemas[6].internal.resumption.capture_bound = &.{ 1, 4, wide };
    program.schemas = schemas;
    const constants = try a.alloc(p.Literal, program.constants.len + 1);
    @memcpy(constants[0..program.constants.len], program.constants);
    constants[program.constants.len] = .{ .schema = wide, .bytes = &.{ 0, 0 } };
    program.constants = constants;
    const blocks = try a.alloc(p.Block, 14);
    @memcpy(blocks[0..9], program.blocks);
    blocks[9] = blocks[0];
    blocks[0] = .{
        .function = 0,
        .parameters = &.{},
        .instructions = &.{.{ .opcode = .constant, .result_type = 1, .immediate = 1 }},
        .terminator = .{ .branch = .{
            .condition = 0,
            .when_true = .{ .block = 10, .arguments = &.{} },
            .when_false = .{ .block = 9, .arguments = &.{} },
        } },
    };
    try addAlternateHandler(a, &program, blocks, wide);
    if (!multi) {
        blocks[6].terminator.resume_value.next = .{
            .block = 8,
            .arguments = &.{ .returned, .returned },
        };
        blocks[8].instructions = &.{};
        blocks[8].terminator = .{ .return_value = 0 };
    }
    program.blocks = blocks;
    return data.canonical.normalize(allocator, program);
}

fn addAlternateHandler(
    a: std.mem.Allocator,
    program: *p.Program,
    blocks: []p.Block,
    wide: p.Id,
) !void {
    const functions = try a.alloc(p.Function, 6);
    @memcpy(functions[0..4], program.functions);
    const state_parameters = try a.dupe(p.Id, &.{ wide, 2 });
    functions[4] = .{ .entry = 11, .parameters = state_parameters, .result = 2 };
    functions[5] = .{ .entry = 12, .parameters = &.{}, .result = 2 };
    program.functions = functions;
    const handlers = try a.alloc(p.Handler, 2);
    handlers[0] = program.handlers[0];
    handlers[1] = .{
        .mode = .deep,
        .input = 2,
        .answer = 2,
        .return_function = 4,
        .state = try a.dupe(p.Id, &.{wide}),
        .clauses = &.{},
    };
    program.handlers = handlers;
    const constructors = try a.alloc(p.Constructor, 2);
    constructors[0] = program.constructors[0];
    constructors[1] = .{ .function = 5, .capture = 0, .schema = wide + 1 };
    program.constructors = constructors;
    blocks[10] = .{
        .function = 0,
        .parameters = &.{},
        .instructions = try a.dupe(p.Instruction, &.{
            .{ .opcode = .computation, .result_type = wide + 1, .immediate = 1 },
            .{ .opcode = .constant, .result_type = wide, .immediate = 3 },
        }),
        .terminator = .{ .handle = .{
            .handler = 1,
            .body = 0,
            .arguments = &.{},
            .state = &.{1},
            .next = .{ .block = 13, .arguments = &.{.returned} },
        } },
    };
    blocks[11] = .{
        .function = 4,
        .parameters = state_parameters,
        .instructions = &.{},
        .terminator = .{ .return_value = 1 },
    };
    blocks[12] = .{
        .function = 5,
        .parameters = &.{},
        .instructions = &.{
            .{ .opcode = .constant, .result_type = 1, .immediate = 1 },
            .{ .opcode = .product, .result_type = 2, .operands = &.{ 0, 0 } },
        },
        .terminator = .{ .return_value = 1 },
    };
    blocks[13] = .{
        .function = 0,
        .parameters = &.{2},
        .instructions = &.{.{ .opcode = .sequence, .result_type = 3, .operands = &.{0} }},
        .terminator = .{ .return_value = 1 },
    };
}

pub fn witness(allocator: std.mem.Allocator, multi: bool, allowed: bool) !Witness {
    var program = try image(allocator, multi, allowed);
    errdefer program.deinit();
    var outcome = try process.advance(allocator, .{
        .program = .{ .records = program.program },
        .instance = .{ .initial_args = &.{} },
    });
    defer outcome.deinit();
    for (0..16) |_| {
        if (outcome.record != .progressed) return error.ExpectedCapture;
        var state = try data.snapshot.decodeGraph(allocator, outcome.record.progressed);
        var token: ?g.Capture = null;
        for (state.state.nodes) |record| switch (record) {
            .one_shot, .multi_template => |capture| {
                token = capture;
                break;
            },
            else => {},
        };
        if (token) |capture| {
            errdefer state.deinit();
            try insertHandler(&state, program.program, capture);
            return .{ .program = program, .state = state };
        }
        state.deinit();
        const next = try process.advance(allocator, .{
            .program = .{ .records = program.program },
            .instance = .{ .snapshot = outcome.record.progressed },
        });
        outcome.deinit();
        outcome = next;
    }
    return error.ExpectedCapture;
}

fn insertHandler(owner: *data.snapshot.Owned, program: p.Program, token: g.Capture) !void {
    const a = owner.arena.allocator();
    const count = owner.state.nodes.len;
    const nodes = try a.alloc(g.Node, count + 2);
    @memcpy(nodes[0..count], owner.state.nodes);
    const saved = &nodes[@intCast(token.capture.?.id)].continuation;
    var definition: ?p.Id = null;
    for (program.handlers, 0..) |handler, id| if (handler.state.len == 1) {
        definition = id;
        break;
    };
    const id = definition orelse return error.ExpectedStatefulHandler;
    const values = try a.alloc(g.Value, 1);
    values[0] = .{
        .schema = program.handlers[@intCast(id)].state[0],
        .body = .{ .scalar = [_]u8{0} ** 8 },
    };
    nodes[count] = .{ .handler = .{
        .definition = id,
        .state = values,
        .evidence = saved.evidence,
        .region = saved.region,
    } };
    nodes[count + 1] = .{ .attachment = .{
        .handler = .{ .id = count },
        .outer = saved.evidence,
        .return_to = saved.parent,
        .region = saved.region,
    } };
    saved.parent = .{ .id = count + 1 };
    owner.state.nodes = nodes;
}

test "captured activation values obey one-shot and multi capture bounds" {
    const allocator = std.testing.allocator;
    for ([_]bool{ false, true }) |multi| {
        var invalid = try witness(allocator, multi, false);
        defer invalid.deinit();
        try std.testing.expectError(error.InvalidOwnership, data.state_admission.validate(
            allocator,
            invalid.program.program,
            invalid.state.state,
        ));
        var valid = try witness(allocator, multi, true);
        defer valid.deinit();
        try data.state_admission.validate(allocator, valid.program.program, valid.state.state);
        var result = try process.run(allocator, .{
            .program = .{ .records = valid.program.program },
            .instance = .{ .records = valid.state.state },
        });
        defer result.deinit();
        const expected: []const u8 = if (multi) &.{ 4, 0, 0, 0, 1, 1, 0, 1, 1 } else &.{ 1, 0, 0 };
        try std.testing.expectEqualSlices(u8, expected, result.record.completed);
    }
}

pub fn wrongHandlerKind(allocator: std.mem.Allocator) !Witness {
    var example = try witness(allocator, false, true);
    errdefer example.deinit();
    try data.state_admission.validate(allocator, example.program.program, example.state.state);
    const nodes = @constCast(example.state.state.nodes);
    const attachment = nodes[nodes.len - 1].attachment;
    nodes[@intCast(attachment.handler.id)] = .{ .environment = .{
        .values = &.{},
        .tail = null,
    } };
    return example;
}

test "captured handler links reject every different node kind before semantic traversal" {
    const allocator = std.testing.allocator;
    var example = try witness(allocator, false, true);
    defer example.deinit();
    const nodes = @constCast(example.state.state.nodes);
    const index: usize = @intCast(nodes[nodes.len - 1].attachment.handler.id);
    const original = nodes[index];
    inline for (@typeInfo(g.Node).@"union".fields) |field| {
        if (comptime !std.mem.eql(u8, field.name, "handler")) {
            nodes[index] = @unionInit(g.Node, field.name, emptyPayload(field.type));
            defer nodes[index] = original;
            if (data.state_admission.validate(allocator, example.program.program, example.state.state)) |_| {
                return error.ExpectedRejection;
            } else |err| if (err == error.OutOfMemory) return err;
        }
    }
    try data.state_admission.validate(allocator, example.program.program, example.state.state);
}

fn emptyPayload(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| blk: {
            var value: T = undefined;
            inline for (info.fields) |field| @field(value, field.name) = emptyPayload(field.type);
            break :blk value;
        },
        .@"union" => |info| @unionInit(T, info.fields[0].name, emptyPayload(info.fields[0].type)),
        else => std.mem.zeroes(T),
    };
}
