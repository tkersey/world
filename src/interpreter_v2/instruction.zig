// Copyright (c) 2026 World contributors. MIT license.
//! One instruction implementation shared during executable-layout migration.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const read = @import("operands.zig").read;
pub const Result = union(enum) { value: g.Value, failed: g.Value };

pub fn execute(machine: anytype, instruction: p.Instruction, slots: anytype, aggregate_values: *@import("values.zig").Values) @TypeOf(machine.*).ExecutionError!Result {
    const value: g.Value = switch (instruction.opcode) {
        .constant => try machine.store.literal(machine.program.schemas, machine.program.constants[@intCast(instruction.immediate)]),
        .move => (try read(slots, instruction.operands[0])),
        .integer_add, .integer_sub, .integer_mul, .integer_div, .integer_rem, .integer_bit_and, .integer_bit_or, .integer_bit_xor, .equal, .less => blk: {
            const left = &(try read(slots, instruction.operands[0]));
            const right = &(try read(slots, instruction.operands[1]));
            const shape = machine.program.schemas[@intCast(left.schema)];
            const a = try data.scalar.fromBytes(shape, try machine.bytes(left));
            const b = try data.scalar.fromBytes(shape, try machine.bytes(right));
            switch (try data.scalar.binary(instruction.opcode, shape, a, b)) {
                .fault => |fault| {
                    const failure = try machine.instructionFailure(instruction, fault);
                    return .{ .failed = failure };
                },
                .value => |value| break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } },
            }
        },
        .integer_bit_not, .integer_convert, .enum_tag => blk: {
            const source = (try read(slots, instruction.operands[0]));
            switch (try data.scalar.unary(instruction.opcode, machine.program.schemas[@intCast(source.schema)], machine.program.schemas[@intCast(instruction.result_type)], source.body.scalar)) {
                .value => |value| break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } },
                .fault => |fault| {
                    return .{ .failed = try machine.instructionFailure(instruction, fault) };
                },
            }
        },
        .boolean_not => blk: {
            var value = [_]u8{0} ** 8;
            value[0] = 1 - (try machine.bytes(&(try read(slots, instruction.operands[0]))))[0];
            break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } };
        },
        .computation => blk: {
            const environment = try captureEnvironment(machine, slots, instruction.operands);
            const closure = try machine.store.add(.{ .computation = .{ .constructor = instruction.immediate, .environment = environment } });
            const use = machine.program.schemas[@intCast(instruction.result_type)].internal.computation.use;
            break :blk .{ .schema = instruction.result_type, .body = if (use == .reusable or use == .multi) .{ .reference = closure } else .{ .owned = .{ .node = closure } } };
        },
        .product, .field, .variant, .variant_tag, .variant_payload, .select, .sequence, .sequence_length, .sequence_get, .sequence_append, .sequence_concat, .sequence_pop, .sequence_set, .sequence_take, .sequence_pop_last => aggregate_values.evaluate(instruction, slots) catch |err| {
            const fault: p.Fault = switch (err) {
                error.CollectionCapacity => .capacity_exceeded,
                error.ElementIndex => .invalid_index,
                error.WrongVariant => .invalid_variant,
                else => |other| return other,
            };
            return .{ .failed = try machine.instructionFailure(instruction, fault) };
        },
        .blob_length, .blob_concat, .blob_slice, .blob_compare, .blob_byte, .text_scalar, .text_integer, .blob_from_byte => blk: {
            switch (try @import("blobs.zig").evaluate(aggregate_values, instruction, slots)) {
                .value => |value| break :blk value,
                .fault => |fault| {
                    return .{ .failed = try machine.instructionFailure(instruction, fault) };
                },
            }
        },
        .cell_new => blk: {
            const region = valueRef((try read(slots, instruction.operands[0])));
            const cell = try machine.store.add(.{ .cell = .{ .schema = instruction.result_type, .region = region, .value = (try read(slots, instruction.operands[1])) } });
            break :blk .{ .schema = instruction.result_type, .body = .{ .reference = cell } };
        },
        .cell_get => (try machine.store.get(valueRef((try read(slots, instruction.operands[0]))))).cell.value orelse return error.InvalidState,
        .cell_set => blk: {
            const reference = valueRef((try read(slots, instruction.operands[0])));
            var cell = (try machine.store.get(reference)).cell;
            cell.value = (try read(slots, instruction.operands[1]));
            try machine.store.replace(reference, .{ .cell = cell });
            break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = [_]u8{0} ** 8 } };
        },
        .package => blk: {
            const package = try machine.store.add(.{ .package = .{ .schema = instruction.result_type, .continuation = (try read(slots, instruction.operands[0])) } });
            break :blk .{ .schema = instruction.result_type, .body = .{ .owned = .{ .node = package } } };
        },
        .unpack => (try machine.store.get(valueRef((try read(slots, instruction.operands[0]))))).package.continuation,
        .clone_resumption => blk: {
            var captured = try machine.takeCapture((try read(slots, instruction.operands[0])));
            captured.schema = instruction.result_type;
            const template = try machine.store.add(.{ .multi_template = captured });
            if (machine.statistics) |statistics| statistics.multi_templates +|= 1;
            break :blk .{ .schema = instruction.result_type, .body = .{ .reference = template } };
        },
        .resource_pack => blk: {
            const resource = try machine.store.add(.{ .resource = .{ .schema = instruction.result_type, .value = (try read(slots, instruction.operands[0])) } });
            break :blk .{ .schema = instruction.result_type, .body = .{ .owned = .{ .node = resource } } };
        },
        .resource_unpack => blk: {
            const record = try machine.store.get(valueRef((try read(slots, instruction.operands[0]))));
            break :blk (if (record == .borrow) (try machine.store.get(record.borrow.resource)).resource else record.resource).value;
        },
    };
    return .{ .value = value };
}

fn captureEnvironment(machine: anytype, slots: anytype, operands: []const p.Id) @TypeOf(machine.*).ExecutionError!g.NodeRef {
    const values = try machine.allocator.alloc(g.Value, operands.len);
    errdefer machine.allocator.free(values);
    for (values, operands) |*value, slot| value.* = try read(slots, slot);
    return machine.store.addOwned(.{ .environment = .{ .values = values, .tail = null } });
}

fn valueRef(value: g.Value) g.NodeRef {
    return switch (value.body) {
        .reference => |reference| reference,
        .owned => |owned| owned.node,
        else => unreachable,
    };
}
