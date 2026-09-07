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

/// Logical cardinality is independent of the amount of storage. Exportable
/// collections retain their canonical element bytes; internal values retain
/// the store's owned field records.
const Collection = struct {
    element: p.Id,
    count: u64,
    storage: union(enum) { encoded: []const u8, fields: []const g.Value },

    fn slice(self: Collection, values: *Values, start: u64, count: u64) Error!Collection {
        if (start > self.count or count > self.count - start) return error.InvalidLength;
        if (start == 0 and count == self.count) return self;
        const storage: @FieldType(Collection, "storage") = switch (self.storage) {
            .fields => |fields| .{ .fields = fields[@intCast(start)..][0..@intCast(count)] },
            .encoded => |encoded| blk: {
                const facts = try values.schemaFacts();
                // A zero minimum denotes one empty encoding only for public
                // data. Internal schemas can also have a zero minimum.
                const element: usize = @intCast(self.element);
                if (facts.exportable[element] and facts.minimum[element] == 0)
                    break :blk .{ .encoded = &.{} };
                var reader: data.wire.Reader = .{ .input = encoded };
                var remaining = start;
                while (remaining != 0) : (remaining -= 1)
                    _ = try data.admission.readValue(
                        values.allocator,
                        values.program.schemas,
                        facts,
                        self.element,
                        &reader,
                    );
                const offset = reader.position;
                remaining = count;
                while (remaining != 0) : (remaining -= 1)
                    _ = try data.admission.readValue(
                        values.allocator,
                        values.program.schemas,
                        facts,
                        self.element,
                        &reader,
                    );
                break :blk .{ .encoded = encoded[offset..reader.position] };
            },
        };
        return .{ .element = self.element, .count = count, .storage = storage };
    }

    fn get(self: Collection, values: *Values, index: u64) Error!g.Value {
        const item = try self.slice(values, index, 1);
        return switch (item.storage) {
            .fields => |fields| fields[0],
            .encoded => |encoded| values.store.literal(values.program, .{
                .schema = self.element,
                .bytes = encoded,
            }),
        };
    }

    fn write(self: Collection, values: *Values, writer: *data.wire.Writer) Error!void {
        switch (self.storage) {
            .encoded => |encoded| try writer.put(encoded),
            .fields => |fields| for (fields) |*field| try writer.put(try values.bytes(field)),
        }
    }
};

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
                const ref = if (value.body == .reference)
                    value.body.reference
                else
                    value.body.owned.node;
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
            else => return error.TypeMismatch,
        };
        const fields = try self.allocator.alloc(g.Value, count);
        const facts = try self.schemaFacts();
        for (fields, 0..) |*field, index| {
            const schema = switch (shape) {
                .product => |types| types[index],
                .sum => |types| types[@intCast(tag)],
                else => unreachable,
            };
            const encoded = try data.admission.readValue(
                self.allocator,
                self.program.schemas,
                facts,
                schema,
                &reader,
            );
            field.* = try self.store.literal(self.program, .{ .schema = schema, .bytes = encoded });
        }
        try reader.finish();
        return .{ .tag = tag, .fields = fields };
    }

    fn collection(self: *Values, value: g.Value) Error!Collection {
        const shape = self.program.schemas[@intCast(value.schema)];
        const element = switch (shape) {
            .seq => |id| id,
            .vector => |vector| vector.element,
            .array => |array| array.element,
            else => return error.TypeMismatch,
        };
        switch (value.body) {
            .reference, .owned => {
                const ref = if (value.body == .reference)
                    value.body.reference
                else
                    value.body.owned.node;
                const fields = (try self.store.get(ref)).aggregate.fields;
                return .{
                    .element = element,
                    .count = fields.len,
                    .storage = .{ .fields = fields },
                };
            },
            else => {},
        }
        var reader: data.wire.Reader = .{ .input = try self.bytes(&value) };
        const count = if (shape == .array) shape.array.length else try reader.natural();
        return .{
            .element = element,
            .count = count,
            .storage = .{ .encoded = reader.input[reader.position..] },
        };
    }

    fn writeCollection(
        self: *Values,
        writer: *data.wire.Writer,
        schema: p.Id,
        count: u64,
        segments: []const Collection,
    ) Error!void {
        if (self.program.schemas[@intCast(schema)] != .array) try writer.natural(count);
        for (segments) |segment| try segment.write(self, writer);
    }

    fn rebuildCollection(
        self: *Values,
        schema: p.Id,
        segments: []const Collection,
    ) EvaluationError!g.Value {
        const shape = self.program.schemas[@intCast(schema)];
        var count: u64 = 0;
        for (segments) |segment| {
            if (shape == .vector and segment.count > shape.vector.maximum - count)
                return error.CollectionCapacity;
            count = std.math.add(u64, count, segment.count) catch return error.InvalidLength;
        }
        if ((try self.schemaFacts()).exportable[@intCast(schema)]) {
            var measure: data.wire.Writer = .{};
            try self.writeCollection(&measure, schema, count, segments);
            const buffer = try self.allocator.alloc(u8, measure.position);
            var writer: data.wire.Writer = .{ .output = buffer };
            try self.writeCollection(&writer, schema, count, segments);
            return self.store.literal(self.program, .{ .schema = schema, .bytes = buffer });
        }
        const physical_count = std.math.cast(usize, count) orelse return error.OutOfMemory;
        const fields = try self.allocator.alloc(g.Value, physical_count);
        var offset: usize = 0;
        for (segments) |segment| {
            const source = switch (segment.storage) {
                .fields => |source| source,
                .encoded => return error.InvalidValue,
            };
            @memcpy(fields[offset..][0..source.len], source);
            offset += source.len;
        }
        return self.aggregate(schema, .{ .fields = fields });
    }

    pub fn evaluate(
        self: *Values,
        instruction: p.Instruction,
        slots: []const g.Value,
    ) EvaluationError!g.Value {
        const result = instruction.result_type;
        if (instruction.opcode == .select) {
            const condition = slots[@intCast(instruction.operands[0])].body.scalar[0] == 1;
            return slots[@intCast(instruction.operands[if (condition) @as(usize, 1) else 2])];
        }
        switch (instruction.opcode) {
            .product, .variant, .sequence => {
                const fields = try self.allocator.alloc(g.Value, instruction.operands.len);
                for (fields, instruction.operands) |*field, slot| field.* = slots[@intCast(slot)];
                return self.aggregate(result, .{ .tag = instruction.immediate, .fields = fields });
            },
            else => {},
        }
        const source = slots[@intCast(instruction.operands[0])];
        switch (instruction.opcode) {
            .field, .variant_tag, .variant_payload => {
                const parts = try self.split(source);
                if (instruction.opcode == .field)
                    return parts.fields[@intCast(instruction.immediate)];
                if (instruction.opcode == .variant_tag) return natural(result, parts.tag);
                if (parts.tag != instruction.immediate) return error.WrongVariant;
                return parts.fields[0];
            },
            else => {},
        }
        return self.evaluateCollection(instruction, slots);
    }

    fn evaluateCollection(
        self: *Values,
        instruction: p.Instruction,
        slots: []const g.Value,
    ) EvaluationError!g.Value {
        const result = instruction.result_type;
        const source = slots[@intCast(instruction.operands[0])];
        const items = try self.collection(source);
        switch (instruction.opcode) {
            .sequence_length => return natural(result, items.count),
            .sequence_get => {
                const index_value = slots[@intCast(instruction.operands[1])];
                const index = std.mem.readInt(u64, index_value.body.scalar[0..8], .little);
                const shape = self.program.schemas[@intCast(result)].sum;
                const found = index < items.count;
                const payload = if (found) try items.get(self, index) else natural(shape[0], 0);
                return self.aggregate(result, .{
                    .tag = @intFromBool(found),
                    .fields = &.{payload},
                });
            },
            .sequence_append, .sequence_concat => {
                const second = slots[@intCast(instruction.operands[1])];
                const right: Collection = if (instruction.opcode == .sequence_concat)
                    try self.collection(second)
                else
                    .{
                        .element = items.element,
                        .count = 1,
                        .storage = .{ .fields = &.{second} },
                    };
                return self.rebuildCollection(result, &.{ items, right });
            },
            .sequence_set, .sequence_take => {
                const operand = slots[@intCast(instruction.operands[1])].body.scalar;
                const index = std.mem.readInt(u64, &operand, .little);
                if (instruction.opcode == .sequence_take) {
                    const prefix = try items.slice(self, 0, @min(index, items.count));
                    return self.rebuildCollection(result, &.{prefix});
                }
                if (index >= items.count) return error.ElementIndex;
                const replacement: Collection = .{
                    .element = items.element,
                    .count = 1,
                    .storage = .{ .fields = &.{slots[@intCast(instruction.operands[2])]} },
                };
                return self.rebuildCollection(result, &.{
                    try items.slice(self, 0, index),
                    replacement,
                    try items.slice(self, index + 1, items.count - index - 1),
                });
            },
            .sequence_pop, .sequence_pop_last => {
                return self.popCollection(instruction, source.schema, items);
            },
            else => return error.UnsupportedTransition,
        }
    }

    fn popCollection(
        self: *Values,
        instruction: p.Instruction,
        source: p.Id,
        items: Collection,
    ) EvaluationError!g.Value {
        const result = instruction.result_type;
        const present = items.count != 0;
        switch (instruction.opcode) {
            .sequence_pop => {
                const shape = self.program.schemas[@intCast(result)].sum;
                const payload: g.Value = if (!present) natural(shape[0], 0) else blk: {
                    const remaining = try items.slice(self, 1, items.count - 1);
                    const tail = try self.rebuildCollection(source, &.{remaining});
                    const first = try items.get(self, 0);
                    break :blk try self.aggregate(shape[1], .{ .fields = &.{ first, tail } });
                };
                return self.aggregate(result, .{
                    .tag = @intFromBool(present),
                    .fields = &.{payload},
                });
            },
            .sequence_pop_last => {
                const shape = self.program.schemas[@intCast(result)].product;
                const optional = self.program.schemas[@intCast(shape[1])].sum;
                const count = items.count;
                const remaining = try items.slice(self, 0, if (count == 0) 0 else count - 1);
                const remainder = try self.rebuildCollection(source, &.{remaining});
                const item = if (present)
                    try items.get(self, count - 1)
                else
                    natural(optional[0], 0);
                const last = try self.aggregate(shape[1], .{
                    .tag = @intFromBool(present),
                    .fields = &.{item},
                });
                return self.aggregate(result, .{ .fields = &.{ remainder, last } });
            },
            else => return error.UnsupportedTransition,
        }
    }
};
