// Copyright (c) 2026 World contributors. MIT license.
//! Immutable aggregate evaluation. Exportable data has one canonical blob form.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const Store = @import("store.zig").Store;
const Error = @import("process.zig").Error;
pub const Parts = struct { tag: p.Id = 0, fields: []const g.Value };
pub const EvaluationError = Error || error{ CollectionCapacity, ElementIndex, WrongVariant };

pub const Values = struct {
    allocator: std.mem.Allocator,
    program: p.Program,
    store: *Store,
    facts: ?data.admission.SchemaFacts = null,
    traits: ?data.traits.Facts = null,

    fn schemaFacts(self: *Values) Error!data.admission.SchemaFacts {
        if (self.facts == null) self.facts = try data.admission.schemas(self.allocator, self.program.schemas);
        return self.facts.?;
    }
    pub fn bytes(self: Values, value: *const g.Value) Error![]const u8 {
        return switch (value.body) {
            .scalar => |*scalar| scalar[0..data.scalar.width(self.program.schemas[@intCast(value.schema)]).?],
            .blob => |ref| self.store.blobs.items[@intCast(ref.id)].bytes,
            else => error.InvalidValue,
        };
    }
    pub fn natural(schema: p.Id, n: u64) g.Value {
        var bytes_value: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes_value, n, .little);
        return .{ .schema = schema, .body = .{ .scalar = bytes_value } };
    }
    fn write(self: Values, writer: *data.wire.Writer, schema: p.Id, parts: Parts) Error!void {
        switch (self.program.schemas[@intCast(schema)]) {
            .product, .array => {},
            .sum => try writer.natural(parts.tag),
            .seq, .vector => try writer.natural(parts.fields.len),
            else => return error.TypeMismatch,
        }
        for (parts.fields) |*field| try writer.put(try self.bytes(field));
    }
    pub fn aggregate(self: *Values, schema: p.Id, parts: Parts) Error!g.Value {
        if ((try self.schemaFacts()).exportable[@intCast(schema)]) {
            var measure: data.wire.Writer = .{};
            try self.write(&measure, schema, parts);
            const buffer = try self.allocator.alloc(u8, measure.position);
            var writer: data.wire.Writer = .{ .output = buffer };
            try self.write(&writer, schema, parts);
            return self.store.literal(self.program, .{ .schema = schema, .bytes = buffer });
        }
        if (self.traits == null) self.traits = try data.traits.derive(self.allocator, self.program.schemas);
        const reference = try self.store.add(.{ .aggregate = .{ .schema = schema, .tag = parts.tag, .fields = parts.fields } });
        return .{ .schema = schema, .body = if (self.traits.?.copy[@intCast(schema)]) .{ .reference = reference } else .{ .owned = .{ .node = reference } } };
    }
    pub fn split(self: *Values, value: g.Value) Error!Parts {
        switch (value.body) {
            .reference, .owned => {
                const ref = if (value.body == .reference) value.body.reference else value.body.owned.node;
                const record = (try self.store.get(ref)).aggregate;
                return .{ .tag = record.tag, .fields = record.fields };
            },
            else => {},
        }
        var reader: data.wire.Reader = .{ .input = try self.bytes(&value) };
        const shape = self.program.schemas[@intCast(value.schema)];
        var tag: p.Id = 0;
        const count = switch (shape) {
            .product => |fields| fields.len,
            .sum => blk: {
                tag = try reader.natural();
                break :blk 1;
            },
            .seq, .vector => try reader.count(),
            .array => |array| std.math.cast(usize, array.length) orelse return error.OutOfMemory,
            else => return error.TypeMismatch,
        };
        const fields = try self.allocator.alloc(g.Value, count);
        const facts = try self.schemaFacts();
        for (fields, 0..) |*field, index| {
            const schema = switch (shape) {
                .product => |types| types[index],
                .sum => |types| types[@intCast(tag)],
                .seq => |ty| ty,
                .vector => |vector| vector.element,
                .array => |array| array.element,
                else => unreachable,
            };
            const encoded = try data.admission.readValue(self.allocator, self.program.schemas, facts, schema, &reader);
            field.* = try self.store.literal(self.program, .{ .schema = schema, .bytes = encoded });
        }
        try reader.finish();
        return .{ .tag = tag, .fields = fields };
    }
    pub fn evaluate(self: *Values, instruction: p.Instruction, slots: []const g.Value) EvaluationError!g.Value {
        const result = instruction.result_type;
        if (instruction.opcode == .select) return slots[@intCast(instruction.operands[if (slots[@intCast(instruction.operands[0])].body.scalar[0] == 1) @as(usize, 1) else 2])];
        switch (instruction.opcode) {
            .product, .variant, .sequence => {
                const fields = try self.allocator.alloc(g.Value, instruction.operands.len);
                for (fields, instruction.operands) |*field, slot| field.* = slots[@intCast(slot)];
                return self.aggregate(result, .{ .tag = instruction.immediate, .fields = fields });
            },
            else => {},
        }
        const source = slots[@intCast(instruction.operands[0])];
        const parts = try self.split(source);
        switch (instruction.opcode) {
            .field => return parts.fields[@intCast(instruction.immediate)],
            .variant_tag => return natural(result, parts.tag),
            .variant_payload => {
                if (parts.tag != instruction.immediate) return error.WrongVariant;
                return parts.fields[0];
            },
            .sequence_length => return natural(result, parts.fields.len),
            .sequence_get => {
                const index_value = slots[@intCast(instruction.operands[1])];
                const index = std.mem.readInt(u64, index_value.body.scalar[0..8], .little);
                const shape = self.program.schemas[@intCast(result)].sum;
                const payload: g.Value = if (index < parts.fields.len) parts.fields[@intCast(index)] else .{ .schema = shape[0], .body = .{ .scalar = [_]u8{0} ** 8 } };
                return self.aggregate(result, .{ .tag = if (index < parts.fields.len) 1 else 0, .fields = &.{payload} });
            },
            .sequence_append, .sequence_concat => {
                const second = slots[@intCast(instruction.operands[1])];
                const right = if (instruction.opcode == .sequence_concat) (try self.split(second)).fields else &[_]g.Value{second};
                const count = std.math.add(usize, parts.fields.len, right.len) catch return error.InvalidLength;
                const shape = self.program.schemas[@intCast(result)];
                if (shape == .vector and count > shape.vector.maximum) return error.CollectionCapacity;
                const fields = try self.allocator.alloc(g.Value, count);
                @memcpy(fields[0..parts.fields.len], parts.fields);
                @memcpy(fields[parts.fields.len..], right);
                return self.aggregate(result, .{ .fields = fields });
            },
            .sequence_set => {
                const index = std.mem.readInt(u64, slots[@intCast(instruction.operands[1])].body.scalar[0..8], .little);
                if (index >= parts.fields.len) return error.ElementIndex;
                const fields = try self.allocator.dupe(g.Value, parts.fields);
                fields[@intCast(index)] = slots[@intCast(instruction.operands[2])];
                return self.aggregate(result, .{ .fields = fields });
            },
            .sequence_take => {
                const length = std.mem.readInt(u64, slots[@intCast(instruction.operands[1])].body.scalar[0..8], .little);
                return self.aggregate(result, .{ .fields = parts.fields[0..@intCast(@min(length, parts.fields.len))] });
            },
            .sequence_pop => {
                const shape = self.program.schemas[@intCast(result)].sum;
                const payload: g.Value = if (parts.fields.len == 0) .{ .schema = shape[0], .body = .{ .scalar = [_]u8{0} ** 8 } } else blk: {
                    const tail = try self.aggregate(source.schema, .{ .fields = parts.fields[1..] });
                    break :blk try self.aggregate(shape[1], .{ .fields = &.{ parts.fields[0], tail } });
                };
                return self.aggregate(result, .{ .tag = if (parts.fields.len == 0) 0 else 1, .fields = &.{payload} });
            },
            .sequence_pop_last => {
                const shape = self.program.schemas[@intCast(result)].product;
                const optional = self.program.schemas[@intCast(shape[1])].sum;
                const count = parts.fields.len;
                const remainder = try self.aggregate(source.schema, .{ .fields = parts.fields[0..if (count == 0) 0 else count - 1] });
                const item = if (count == 0) natural(optional[0], 0) else parts.fields[count - 1];
                const last = try self.aggregate(shape[1], .{ .tag = @intFromBool(count != 0), .fields = &.{item} });
                return self.aggregate(result, .{ .fields = &.{ remainder, last } });
            },
            else => return error.UnsupportedTransition,
        }
    }
};
