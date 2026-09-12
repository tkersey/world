// Copyright (c) 2026 World contributors. MIT license.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const process = @import("process.zig");
const Error = process.Error;
const Outcome = process.Outcome;

pub const Machine = struct {
    allocator: std.mem.Allocator,
    program: p.Program,
    identity: [32]u8,
    store: @import("store.zig").Store,
    roots: g.Roots = .{},
    status: g.Status = .active,
    statistics: ?*process.Statistics = null,

    pub fn initialize(self: *Machine, initial: []const u8) Error!void {
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const scratch = temporary.allocator();
        const facts = try data.admission.schemas(scratch, self.program.schemas);
        const entry = self.program.functions[@intCast(self.program.roots.entry)];
        const values = try scratch.alloc(g.Value, entry.parameters.len);
        var reader: data.wire.Reader = .{ .input = initial };
        for (values, entry.parameters) |*value, schema| {
            const encoded = try data.admission.readValue(scratch, self.program.schemas, facts, schema, &reader);
            value.* = try self.store.literal(self.program, .{ .schema = schema, .bytes = encoded });
        }
        try reader.finish();
        self.roots.current = try self.store.add(.{ .control = .{ .block = entry.entry, .arguments = values } });
    }

    fn instructionFailure(self: *Machine, instruction: p.Instruction, fault: p.Fault) Error!g.Value {
        for (instruction.failures) |failure| if (failure.kind == fault) return self.store.literal(self.program, self.program.constants[@intCast(failure.value)]);
        return error.InvalidProgram;
    }

    pub fn bytes(self: *Machine, value: *const g.Value) Error![]const u8 {
        return switch (value.body) {
            .scalar => |*scalar| scalar[0..data.scalar.width(self.program.schemas[@intCast(value.schema)]).?],
            .blob => |ref| self.store.blobs.items[@intCast(ref.id)].bytes,
            else => error.UnsupportedTransition,
        };
    }

    pub fn continuation(self: *Machine, source: p.Id, slots: []const g.Value, control: g.Control) Error!g.NodeRef {
        const edge = data.state_admission.next(self.program.blocks[@intCast(source)].terminator).?;
        const arguments = try self.allocator.alloc(?g.Value, edge.arguments.len);
        defer self.allocator.free(arguments);
        for (arguments, edge.arguments) |*argument, spec| argument.* = switch (spec) {
            .slot => |slot| slots[@intCast(slot)],
            .returned => null,
        };
        return self.store.add(.{ .continuation = .{ .source_block = source, .arguments = arguments, .parent = control.parent, .evidence = control.evidence, .region = control.region } });
    }

    pub fn resumeContinuation(self: *Machine, reference: g.NodeRef, value: g.Value) Error!void {
        const saved = (try self.store.get(reference)).continuation;
        const edge = data.state_admission.next(self.program.blocks[@intCast(saved.source_block)].terminator).?;
        const arguments = try self.allocator.alloc(g.Value, saved.arguments.len);
        defer self.allocator.free(arguments);
        for (arguments, saved.arguments) |*argument, item| argument.* = item orelse value;
        self.roots.current = try self.store.add(.{ .control = .{
            .block = edge.block,
            .arguments = arguments,
            .parent = saved.parent,
            .evidence = saved.evidence,
            .region = saved.region,
        } });
        self.roots.evidence = saved.evidence;
    }

    fn jump(self: *Machine, edge: p.Edge, slots: []const g.Value, control: g.Control) Error!void {
        const arguments = try self.allocator.alloc(g.Value, edge.arguments.len);
        defer self.allocator.free(arguments);
        for (arguments, edge.arguments) |*argument, spec| argument.* = slots[@intCast(spec.slot)];
        self.roots.current = try self.store.add(.{ .control = .{
            .block = edge.block,
            .arguments = arguments,
            .parent = control.parent,
            .evidence = control.evidence,
            .region = control.region,
        } });
    }

    fn evaluateBlock(self: *Machine, block: p.Block, arguments: []const g.Value, control: g.Control) Error!?[]g.Value {
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        var aggregate_values: @import("values.zig").Values = .{ .allocator = scratch.allocator(), .program = self.program, .store = &self.store };
        const count = std.math.add(usize, arguments.len, block.instructions.len) catch return error.InvalidLength;
        const slots = try self.allocator.alloc(g.Value, count);
        var returned_slots = false;
        defer if (!returned_slots) self.allocator.free(slots);
        @memcpy(slots[0..arguments.len], arguments);
        for (block.instructions, 0..) |instruction, index| {
            const target = arguments.len + index;
            slots[target] = switch (instruction.opcode) {
                .constant => try self.store.literal(self.program, self.program.constants[@intCast(instruction.immediate)]),
                .move => slots[@intCast(instruction.operands[0])],
                .integer_add, .integer_sub, .integer_mul, .integer_div, .integer_rem, .integer_bit_and, .integer_bit_or, .integer_bit_xor, .equal, .less => blk: {
                    const left = &slots[@intCast(instruction.operands[0])];
                    const right = &slots[@intCast(instruction.operands[1])];
                    const shape = self.program.schemas[@intCast(left.schema)];
                    const a = try data.scalar.fromBytes(shape, try self.bytes(left));
                    const b = try data.scalar.fromBytes(shape, try self.bytes(right));
                    switch (try data.scalar.binary(instruction.opcode, shape, a, b)) {
                        .fault => |fault| {
                            const failure = try self.instructionFailure(instruction, fault);
                            try @import("unwind.zig").fail(self, failure, control, slots[0..target], block.instructions[0..index]);
                            return null;
                        },
                        .value => |value| break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } },
                    }
                },
                .integer_bit_not, .integer_convert, .enum_tag => blk: {
                    const source = slots[@intCast(instruction.operands[0])];
                    switch (try data.scalar.unary(instruction.opcode, self.program.schemas[@intCast(source.schema)], self.program.schemas[@intCast(instruction.result_type)], source.body.scalar)) {
                        .value => |value| break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } },
                        .fault => |fault| {
                            try @import("unwind.zig").fail(self, try self.instructionFailure(instruction, fault), control, slots[0..target], block.instructions[0..index]);
                            return null;
                        },
                    }
                },
                .boolean_not => blk: {
                    var value = [_]u8{0} ** 8;
                    value[0] = 1 - (try self.bytes(&slots[@intCast(instruction.operands[0])]))[0];
                    break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = value } };
                },
                .computation => blk: {
                    const values = try self.allocator.alloc(g.Value, instruction.operands.len);
                    defer self.allocator.free(values);
                    for (values, instruction.operands) |*value, operand| value.* = slots[@intCast(operand)];
                    const environment = try self.store.add(.{ .environment = .{ .values = values, .tail = null } });
                    const closure = try self.store.add(.{ .computation = .{ .constructor = instruction.immediate, .environment = environment } });
                    const use = self.program.schemas[@intCast(instruction.result_type)].internal.computation.use;
                    break :blk .{ .schema = instruction.result_type, .body = if (use == .reusable or use == .multi) .{ .reference = closure } else .{ .owned = .{ .node = closure } } };
                },
                .product, .field, .variant, .variant_tag, .variant_payload, .select, .sequence, .sequence_length, .sequence_get, .sequence_append, .sequence_concat, .sequence_pop, .sequence_set, .sequence_take, .sequence_pop_last => aggregate_values.evaluate(instruction, slots) catch |err| {
                    const fault: p.Fault = switch (err) {
                        error.CollectionCapacity => .capacity_exceeded,
                        error.ElementIndex => .invalid_index,
                        error.WrongVariant => .invalid_variant,
                        else => |other| return other,
                    };
                    try @import("unwind.zig").fail(self, try self.instructionFailure(instruction, fault), control, slots[0..target], block.instructions[0..index]);
                    return null;
                },
                .blob_length, .blob_concat, .blob_slice, .blob_compare, .blob_byte, .text_scalar, .text_integer, .blob_from_byte => blk: {
                    switch (try @import("blobs.zig").evaluate(&aggregate_values, instruction, slots)) {
                        .value => |value| break :blk value,
                        .fault => |fault| {
                            try @import("unwind.zig").fail(self, try self.instructionFailure(instruction, fault), control, slots[0..target], block.instructions[0..index]);
                            return null;
                        },
                    }
                },
                .cell_new => blk: {
                    const region = valueRef(slots[@intCast(instruction.operands[0])]);
                    const cell = try self.store.add(.{ .cell = .{ .schema = instruction.result_type, .region = region, .value = slots[@intCast(instruction.operands[1])] } });
                    break :blk .{ .schema = instruction.result_type, .body = .{ .reference = cell } };
                },
                .cell_get => (try self.store.get(valueRef(slots[@intCast(instruction.operands[0])]))).cell.value orelse return error.InvalidState,
                .cell_set => blk: {
                    const reference = valueRef(slots[@intCast(instruction.operands[0])]);
                    var cell = (try self.store.get(reference)).cell;
                    cell.value = slots[@intCast(instruction.operands[1])];
                    try self.store.replace(reference, .{ .cell = cell });
                    break :blk .{ .schema = instruction.result_type, .body = .{ .scalar = [_]u8{0} ** 8 } };
                },
                .package => blk: {
                    const package = try self.store.add(.{ .package = .{ .schema = instruction.result_type, .continuation = slots[@intCast(instruction.operands[0])] } });
                    break :blk .{ .schema = instruction.result_type, .body = .{ .owned = .{ .node = package } } };
                },
                .unpack => (try self.store.get(valueRef(slots[@intCast(instruction.operands[0])]))).package.continuation,
                .clone_resumption => blk: {
                    var captured = try self.takeCapture(slots[@intCast(instruction.operands[0])]);
                    captured.schema = instruction.result_type;
                    const template = try self.store.add(.{ .multi_template = captured });
                    if (self.statistics) |statistics| statistics.multi_templates +|= 1;
                    break :blk .{ .schema = instruction.result_type, .body = .{ .reference = template } };
                },
                .resource_pack => blk: {
                    const resource = try self.store.add(.{ .resource = .{ .schema = instruction.result_type, .value = slots[@intCast(instruction.operands[0])] } });
                    break :blk .{ .schema = instruction.result_type, .body = .{ .owned = .{ .node = resource } } };
                },
                .resource_unpack => blk: {
                    const record = try self.store.get(valueRef(slots[@intCast(instruction.operands[0])]));
                    break :blk (if (record == .borrow) (try self.store.get(record.borrow.resource)).resource else record.resource).value;
                },
            };
        }
        returned_slots = true;
        return slots;
    }

    pub fn step(self: *Machine) Error!?Outcome {
        if (self.statistics) |statistics| statistics.transitions +|= 1;
        if (self.status == .unwinding) return @import("unwind.zig").step(self);
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        var aggregate_values: @import("values.zig").Values = .{ .allocator = scratch.allocator(), .program = self.program, .store = &self.store };
        const control = (try self.store.get(self.roots.current.?)).control;
        const block = self.program.blocks[@intCast(control.block)];
        const slots = (try self.evaluateBlock(block, control.arguments, control)) orelse return null;
        defer self.allocator.free(slots);
        switch (block.terminator) {
            .return_value => |slot| {
                return self.returnTo(control.parent, slots[@intCast(slot)]);
            },
            .fail => |slot| try @import("unwind.zig").fail(self, slots[@intCast(slot)], control, slots, block.instructions),
            .jump => |edge| try self.jump(edge, slots, control),
            .yield_value => |edge| {
                try self.jump(edge, slots, control);
                self.status = .yielded;
            },
            .branch => |branch| try self.jump(if ((try self.bytes(&slots[@intCast(branch.condition)]))[0] == 1) branch.when_true else branch.when_false, slots, control),
            .switch_variant => |selected| {
                const parts = try aggregate_values.split(slots[@intCast(selected.value)]);
                const edge = selected.cases[@intCast(parts.tag)];
                const arguments = try scratch.allocator().alloc(g.Value, edge.arguments.len);
                for (arguments, edge.arguments) |*argument, spec| argument.* = switch (spec) {
                    .slot => |slot| slots[@intCast(slot)],
                    .returned => parts.fields[0],
                };
                self.roots.current = try self.store.add(.{ .control = .{ .block = edge.block, .arguments = arguments, .parent = control.parent, .evidence = control.evidence, .region = control.region } });
            },
            .unpack_product => |unpack| {
                const parts = try aggregate_values.split(slots[@intCast(unpack.value)]);
                const arguments = try scratch.allocator().alloc(g.Value, parts.fields.len + unpack.arguments.len);
                @memcpy(arguments[0..parts.fields.len], parts.fields);
                for (arguments[parts.fields.len..], unpack.arguments) |*argument, slot| argument.* = slots[@intCast(slot)];
                self.roots.current = try self.store.add(.{ .control = .{ .block = unpack.block, .arguments = arguments, .parent = control.parent, .evidence = control.evidence, .region = control.region } });
            },
            .call => |call| {
                const arguments = try self.allocator.alloc(g.Value, call.arguments.len);
                defer self.allocator.free(arguments);
                for (arguments, call.arguments) |*argument, slot| argument.* = slots[@intCast(slot)];
                // A return edge needs no frame, including recursive call sites.
                const target = self.program.blocks[@intCast(call.next.block)];
                const tail = target.instructions.len == 0 and target.terminator == .return_value and
                    call.next.arguments[@intCast(target.terminator.return_value)] == .returned;
                const parent = if (tail) control.parent else try self.continuation(control.block, slots, control);
                self.roots.current = try self.store.add(.{ .control = .{
                    .block = self.program.functions[@intCast(call.function)].entry,
                    .arguments = arguments,
                    .parent = parent,
                    .evidence = control.evidence,
                    .region = control.region,
                } });
            },
            .perform => |perform| {
                if (perform.capability != null) {
                    try self.performHandled(perform, slots, control);
                    return null;
                }
                const saved = try self.continuation(control.block, slots, control);
                self.roots.pending = try self.store.add(.{ .pending = .{
                    .effect = perform.effect,
                    .payload = slots[@intCast(perform.payload)],
                    .continuation = saved,
                    .source_block = control.block,
                } });
                self.roots.current = null;
                self.status = .parked;
            },
            .apply => |apply| {
                const values = try self.allocator.alloc(g.Value, apply.arguments.len);
                defer self.allocator.free(values);
                for (values, apply.arguments) |*value, operand| value.* = slots[@intCast(operand)];
                const parent = try self.continuation(control.block, slots, control);
                try self.applyComputation(slots[@intCast(apply.computation)], values, parent, control.evidence, control.region);
            },
            .handle => |handle| try self.installHandler(handle, slots, control),
            .resume_value => |resuming| try self.resumeValue(resuming.resumption, resuming.argument, slots, control),
            .resume_with => |resuming| {
                const value = slots[@intCast(resuming.resumption)];
                const token = try self.takeCapture(value);
                defer if (self.isMulti(value)) self.allocator.free(token.use_site_capabilities);
                const state = try scratch.allocator().alloc(g.Value, resuming.state.len);
                for (state, resuming.state) |*item, slot| item.* = slots[@intCast(slot)];
                const activation = try self.store.add(.{ .handler = .{ .definition = resuming.handler, .state = state, .evidence = control.evidence, .region = control.region } });
                const after = try self.continuation(control.block, slots, control);
                try self.store.replace(token.delimiter, .{ .attachment = .{ .handler = activation, .outer = control.evidence, .return_to = after, .region = control.region } });
                try self.resumeContinuation(token.capture.?, slots[@intCast(resuming.argument)]);
            },
            .resume_computation => |resuming| {
                const value = slots[@intCast(resuming.resumption)];
                const token = try self.takeCapture(value);
                defer if (self.isMulti(value)) self.allocator.free(token.use_site_capabilities);
                const after = try self.continuation(control.block, slots, control);
                const evidence = try self.prepareResumption(token, after);
                const captured = (try self.store.get(token.capture.?)).continuation;
                const injected = try self.store.add(.{ .injection = .{ .continuation = token.capture.? } });
                try self.applyComputation(
                    slots[@intCast(resuming.computation)],
                    token.use_site_capabilities,
                    injected,
                    evidence,
                    captured.region,
                );
            },
            .with_region => |scope| {
                const region = try self.store.add(.{ .region = .{ .descriptor = scope.region, .outer = control.region, .obligations = &.{} } });
                const after = try self.continuation(control.block, slots, control);
                const frame = try self.store.add(.{ .region_scope = .{ .source_block = control.block, .region = region, .return_to = after } });
                const body = slots[@intCast(scope.body)];
                const signature = self.program.schemas[@intCast(body.schema)].internal.computation;
                const arguments = try scratch.allocator().alloc(g.Value, scope.arguments.len + 1);
                arguments[0] = .{ .schema = signature.parameters[0], .body = .{ .reference = region } };
                for (arguments[1..], scope.arguments) |*argument, slot| argument.* = slots[@intCast(slot)];
                try self.applyComputation(body, arguments, frame, control.evidence, region);
            },
            .protect => |protection| try @import("unwind.zig").protect(self, protection, slots, control),
            .dispose => |disposal| try @import("unwind.zig").dispose(self, disposal, slots, control),
            else => return error.UnsupportedTransition,
        }
        return null;
    }

    pub fn valueRef(value: g.Value) g.NodeRef {
        return switch (value.body) {
            .reference => |ref| ref,
            .owned => |owned| owned.node,
            else => unreachable,
        };
    }

    fn enter(self: *Machine, function: p.Id, arguments: []const g.Value, parent: ?g.NodeRef, evidence: ?g.NodeRef, region: ?g.NodeRef) Error!void {
        self.roots.current = try self.store.add(.{ .control = .{
            .block = self.program.functions[@intCast(function)].entry,
            .arguments = arguments,
            .parent = parent,
            .evidence = evidence,
            .region = region,
        } });
        self.roots.evidence = evidence;
    }

    pub fn applyComputation(self: *Machine, value: g.Value, supplied: []const g.Value, parent: ?g.NodeRef, evidence: ?g.NodeRef, region: ?g.NodeRef) Error!void {
        const closure = (try self.store.get(valueRef(value))).computation;
        const constructor = self.program.constructors[@intCast(closure.constructor)];
        const environment = (try self.store.get(closure.environment)).environment;
        const arguments = try self.allocator.alloc(g.Value, environment.values.len + supplied.len);
        defer self.allocator.free(arguments);
        @memcpy(arguments[0..environment.values.len], environment.values);
        @memcpy(arguments[environment.values.len..], supplied);
        try self.enter(constructor.function, arguments, parent, evidence, region);
    }

    fn installHandler(self: *Machine, installation: anytype, slots: []const g.Value, control: g.Control) Error!void {
        const definition = self.program.handlers[@intCast(installation.handler)];
        const state = try self.allocator.alloc(g.Value, installation.state.len);
        defer self.allocator.free(state);
        for (state, installation.state) |*value, slot| value.* = slots[@intCast(slot)];
        const activation = try self.store.add(.{ .handler = .{ .definition = installation.handler, .state = state, .evidence = control.evidence, .region = control.region } });
        const after = try self.continuation(control.block, slots, control);
        const attachment = try self.store.add(.{ .attachment = .{ .handler = activation, .outer = control.evidence, .return_to = after, .region = control.region } });
        const body = slots[@intCast(installation.body)];
        const parameters = self.program.schemas[@intCast(body.schema)].internal.computation.parameters;
        const arguments = try self.allocator.alloc(g.Value, definition.clauses.len + installation.arguments.len);
        defer self.allocator.free(arguments);
        for (definition.clauses, 0..) |_, index| arguments[index] = .{ .schema = parameters[index], .body = .{ .reference = attachment } };
        for (installation.arguments, 0..) |slot, index| arguments[definition.clauses.len + index] = slots[@intCast(slot)];
        try self.applyComputation(body, arguments, attachment, attachment, control.region);
    }

    pub fn returnTo(self: *Machine, parent: ?g.NodeRef, value: g.Value) Error!?Outcome {
        var cursor = parent;
        while (cursor) |ref| {
            const frame = try self.store.get(ref);
            // Closing empty lexical region wrappers is a finite graph walk.
            // It never executes a second authored block or recurses in Zig.
            if (frame == .region_scope) {
                cursor = frame.region_scope.return_to;
                continue;
            }
            switch (frame) {
                .continuation => try self.resumeContinuation(ref, value),
                .attachment => |attachment| {
                    if (attachment.phase != .active) return error.InvalidState;
                    const activation = (try self.store.get(attachment.handler)).handler;
                    const definition = self.program.handlers[@intCast(activation.definition)];
                    const arguments = try self.allocator.alloc(g.Value, activation.state.len + 1);
                    defer self.allocator.free(arguments);
                    @memcpy(arguments[0..activation.state.len], activation.state);
                    arguments[activation.state.len] = value;
                    try self.enter(definition.return_function, arguments, attachment.return_to, activation.evidence, activation.region);
                },
                .injection => |injected| try self.resumeContinuation(injected.continuation, value),
                .protection => |protection| try @import("unwind.zig").begin(self, .{ .normal = value }, ref, protection.return_to, &.{}),
                .cleanup_return => try @import("unwind.zig").returned(self, ref),
                .disposal_return => |disposal| try @import("unwind.zig").returnedDisposal(self, disposal, value),
                else => return error.InvalidState,
            }
            return null;
        }
        return try self.terminal(.completed, value);
    }

    fn performHandled(self: *Machine, operation: p.Perform, slots: []const g.Value, control: g.Control) Error!void {
        const selected = valueRef(slots[@intCast(operation.capability.?)]);
        var position = control.parent;
        while (position) |cursor| {
            if (cursor.id == selected.id) break;
            position = switch (try self.store.get(cursor)) {
                .continuation => |saved| saved.parent,
                .attachment => |attachment| attachment.return_to,
                .region_scope => |scope| scope.return_to,
                .injection => |injected| injected.continuation,
                .protection => |protection| protection.return_to,
                .cleanup_return => |cleanup| cleanup.parent,
                .disposal_return => |disposal| disposal.parent,
                else => return error.InvalidScope,
            };
        }
        if (position == null) return error.InvalidScope;
        var attachment = (try self.store.get(selected)).attachment;
        const activation = (try self.store.get(attachment.handler)).handler;
        const definition = self.program.handlers[@intCast(activation.definition)];
        var selected_clause: ?p.Clause = null;
        for (definition.clauses) |clause| if (clause.effect == operation.effect) {
            selected_clause = clause;
            break;
        };
        const clause = selected_clause orelse return error.InvalidEffect;
        if (clause.direct) {
            const arguments = try self.allocator.alloc(g.Value, activation.state.len + 1);
            defer self.allocator.free(arguments);
            @memcpy(arguments[0..activation.state.len], activation.state);
            arguments[activation.state.len] = slots[@intCast(operation.payload)];
            const body = self.program.blocks[@intCast(self.program.functions[@intCast(clause.function)].entry)];
            const evaluated = (try self.evaluateBlock(body, arguments, control)) orelse return error.InvalidState;
            defer self.allocator.free(evaluated);
            const value = evaluated[@intCast(body.terminator.return_value)];
            const successor = try self.allocator.alloc(g.Value, operation.next.arguments.len);
            defer self.allocator.free(successor);
            for (successor, operation.next.arguments) |*argument, spec| argument.* = switch (spec) {
                .slot => |slot| slots[@intCast(slot)],
                .returned => value,
            };
            self.roots.current = try self.store.add(.{ .control = .{
                .block = operation.next.block,
                .arguments = successor,
                .parent = control.parent,
                .evidence = control.evidence,
                .region = control.region,
            } });
            if (self.statistics) |statistics| statistics.direct_clauses +|= 1;
            return;
        }
        const signature = self.program.schemas[@intCast(clause.resumption)].internal.resumption;
        const captured = try self.continuation(control.block, slots, control);
        const use_site = try self.allocator.alloc(g.Value, operation.use_site_capabilities.len);
        defer self.allocator.free(use_site);
        for (use_site, operation.use_site_capabilities) |*value, slot| value.* = slots[@intCast(slot)];
        const capture: g.Capture = .{
            .schema = clause.resumption,
            .capture = captured,
            .delimiter = selected,
            .evidence = control.evidence,
            .use_site_capabilities = use_site,
        };
        const token = try self.store.add(if (signature.use == .multi) .{ .multi_template = capture } else .{ .one_shot = capture });
        if (self.statistics) |statistics| {
            if (signature.use == .multi) statistics.multi_templates +|= 1 else statistics.one_shot_captures +|= 1;
        }
        const parent = attachment.return_to;
        attachment.return_to = null;
        attachment.phase = .suspended;
        try self.store.replace(selected, .{ .attachment = attachment });
        const arguments = try self.allocator.alloc(g.Value, activation.state.len + operation.bodies.len + 2);
        defer self.allocator.free(arguments);
        @memcpy(arguments[0..activation.state.len], activation.state);
        arguments[activation.state.len] = slots[@intCast(operation.payload)];
        for (operation.bodies, 0..) |slot, index| arguments[activation.state.len + 1 + index] = slots[@intCast(slot)];
        arguments[arguments.len - 1] = .{ .schema = clause.resumption, .body = if (signature.use == .multi) .{ .reference = token } else .{ .owned = .{ .node = token } } };
        try self.enter(clause.function, arguments, parent, activation.evidence, activation.region);
    }

    fn resumeValue(self: *Machine, resumption_slot: p.Id, argument_slot: p.Id, slots: []const g.Value, control: g.Control) Error!void {
        const value = slots[@intCast(resumption_slot)];
        const token = try self.takeCapture(value);
        defer if (self.isMulti(value)) self.allocator.free(token.use_site_capabilities);
        const after = try self.continuation(control.block, slots, control);
        _ = try self.prepareResumption(token, after);
        try self.resumeContinuation(token.capture.?, slots[@intCast(argument_slot)]);
    }

    fn isMulti(self: Machine, value: g.Value) bool {
        return self.program.schemas[@intCast(value.schema)].internal.resumption.use == .multi;
    }
    pub fn takeCapture(self: *Machine, value: g.Value) Error!g.Capture {
        const reference_id = valueRef(value);
        if (self.isMulti(value)) {
            const branch = try @import("clone.zig").instantiate(self.allocator, &self.store, (try self.store.get(reference_id)).multi_template);
            if (self.statistics) |statistics| statistics.branch_activations +|= 1;
            return branch;
        }
        var token = (try self.store.get(reference_id)).one_shot;
        if (token.capture == null) return error.InvalidOwnership;
        // Consumption precedes entering the captured computation.
        var consumed = token;
        consumed.capture = null;
        try self.store.replace(reference_id, .{ .one_shot = consumed });
        token.use_site_capabilities = (try self.store.get(reference_id)).one_shot.use_site_capabilities;
        return token;
    }
    fn prepareResumption(self: *Machine, token: g.Capture, after: g.NodeRef) Error!?g.NodeRef {
        const signature = self.program.schemas[@intCast(token.schema)].internal.resumption;
        if (signature.mode == .deep) {
            try self.activate(token, after);
            return token.evidence;
        }
        const outer = (try self.store.get(token.delimiter)).attachment.outer;
        // Plug the caller into the captured hole. The old handler and its return
        // clause are absent from plain shallow resumption.
        try self.store.replace(token.delimiter, try self.store.get(after));
        for (self.store.nodes.items, self.store.alive.items) |*record, live| {
            if (!live) continue;
            const evidence: ?*?g.NodeRef = switch (record.*) {
                .control => |*v| &v.evidence,
                .continuation => |*v| &v.evidence,
                .handler => |*v| &v.evidence,
                .attachment => |*v| &v.outer,
                .protection => |*v| &v.evidence,
                .one_shot, .multi_template => |*v| &v.evidence,
                else => null,
            };
            // These are lexical-context links, not capability values. Explicit
            // capabilities keep selecting their original attachment identities.
            if (evidence) |link| if (link.*) |ref| {
                if (ref.id == token.delimiter.id) link.* = outer;
            };
        }
        return if (token.evidence != null and token.evidence.?.id == token.delimiter.id)
            outer
        else
            token.evidence;
    }

    pub fn activate(self: *Machine, token: g.Capture, after: g.NodeRef) Error!void {
        var attachment = (try self.store.get(token.delimiter)).attachment;
        attachment.return_to = after;
        attachment.phase = .active;
        try self.store.replace(token.delimiter, .{ .attachment = attachment });
    }

    fn terminal(self: *Machine, comptime kind: enum { completed }, value: g.Value) Error!Outcome {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const output = try arena.allocator().dupe(u8, try self.bytes(&value));
        return .{ .arena = arena, .record = @unionInit(data.protocol.Outcome, @tagName(kind), output) };
    }

    pub fn finish(self: *Machine) Error!Outcome {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const output = arena.allocator();
        const measurement = if (self.statistics) |s| &s.snapshot else null;
        var emission = try data.snapshot.emit(self.allocator, self.store.state(self.identity, self.status, self.roots), output, measurement);
        defer emission.normalized.deinit();
        const normalized = emission.normalized;
        try data.state_admission.validate(self.allocator, self.program, normalized.state);
        const snapshot = emission.bytes;
        const outcome: data.protocol.Outcome = switch (self.status) {
            .active, .unwinding => .{ .progressed = snapshot },
            .yielded => .{ .yielded = snapshot },
            .parked => blk: {
                const pending = normalized.state.nodes[@intCast(normalized.state.roots.pending.?.id)].pending;
                const effect = self.program.effects[@intCast(pending.effect)];
                const payload_schema = try data.schema.encodeOwned(output, self.program.schemas, effect.payload);
                const resume_schema = try data.schema.encodeOwned(output, self.program.schemas, effect.result);
                const payload = switch (pending.payload.body) {
                    .scalar => |*scalar| scalar[0..data.scalar.width(self.program.schemas[@intCast(effect.payload)]).?],
                    .blob => |ref| normalized.state.blobs[@intCast(ref.id)].bytes,
                    else => return error.InvalidValue,
                };
                var request: data.protocol.Request = .{
                    .program_identity = self.identity,
                    .pending_state_digest = data.wire.digest(snapshot),
                    .residual_contract_digest = data.protocol.contractIdentity(effect.identity, payload_schema, resume_schema),
                    .continuation_binding_digest = data.protocol.continuationIdentity(self.identity, data.wire.digest(snapshot), pending.source_block, data.wire.digest(resume_schema)),
                    .semantic_identity = effect.identity,
                    .payload_schema = payload_schema,
                    .resume_schema = resume_schema,
                    .payload = payload,
                    .request_identity = undefined,
                };
                request.request_identity = data.protocol.requestIdentity(request);
                const encoded = try output.alloc(u8, try data.protocol.encodedLength(data.protocol.Request, request));
                _ = try data.protocol.encode(data.protocol.Request, self.allocator, request, encoded);
                break :blk .{ .requested = .{ .state = snapshot, .request = encoded } };
            },
        };
        return .{ .arena = arena, .record = outcome };
    }
};
