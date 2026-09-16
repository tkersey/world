// Copyright (c) 2026 World contributors. MIT license.
//! Successor native control slice. Not yet the portable/resident public API:
//! prepared lifetimes, protocol binding and whole-Session rollback remain open.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const ir = data.activation;
const g = data.graph;
const heap = @import("store.zig");
const bindings = @import("activation_frames.zig");
const read = @import("operands.zig").read;
const Slots = @import("activation_slots.zig").ActivationSlots;
pub const Error = @import("process.zig").Error || bindings.Error || data.activation_ownership.Error || data.program_image.Error;
pub const Observation = union(enum) {
    progressed,
    yielded,
    requested: struct { effect: p.Id, payload: g.Value },
    completed: g.Value,
    failed: g.Value,
    cancelled: data.protocol.Reason,
};

pub const Session = struct {
    pub const ExecutionError = Error;
    pub const UnwindOutcome = void;
    allocator: std.mem.Allocator,
    program: ir.Program,
    program_identity: [32]u8,
    flow: data.activation_flow.Facts,
    uses: data.traits.Facts,
    value_facts: data.admission.SchemaFacts,
    store: heap.Store,
    frames: bindings.Frames,
    roots: g.Roots = .{},
    status: g.Status = .active,
    terminal: ?Observation = null,
    exit: ?g.Exit = null,
    poisoned: bool = false,
    transitions: usize = 0,
    statistics: ?*@import("process.zig").Statistics = null,

    /// Own all executable records before returning; the image may be released.
    pub fn initImage(allocator: std.mem.Allocator, image: []const u8, arguments: []const u8) (Error || data.program_image.Error)!Session {
        var decoded = try data.program_image.decode(allocator, image);
        defer decoded.deinit();
        return init(allocator, decoded.program, arguments);
    }

    pub fn init(allocator: std.mem.Allocator, input: ir.Program, arguments: []const u8) Error!Session {
        var result = try empty(allocator, input);
        errdefer result.deinit();
        try result.initialize(arguments);
        return result;
    }

    fn empty(allocator: std.mem.Allocator, input: ir.Program) Error!Session {
        const program = try heap.duplicate(ir.Program, allocator, input);
        errdefer heap.release(ir.Program, allocator, program);
        var flow = try data.activation_ownership.analyze(allocator, program);
        errdefer flow.deinit();
        try supported(program);
        const uses = try data.traits.derive(flow.arena.allocator(), program.schemas);
        const value_facts = try data.admission.schemas(flow.arena.allocator(), program.schemas);
        const identity = try data.program_image.identity(allocator, program);
        const frames = try bindings.Frames.init(allocator, flow.pool, program);
        return .{
            .allocator = allocator,
            .program = program,
            .program_identity = identity,
            .flow = flow,
            .uses = uses,
            .value_facts = value_facts,
            .frames = frames,
            .store = .{ .allocator = allocator },
        };
    }

    pub fn restoreImage(allocator: std.mem.Allocator, image: []const u8, checkpoint_bytes: []const u8) Error!Session {
        var decoded = try data.program_image.decode(allocator, image);
        defer decoded.deinit();
        var result = try empty(allocator, decoded.program);
        errdefer result.deinit();
        var incoming = try data.state_image.decodeGraph(allocator, checkpoint_bytes);
        var transferred = false;
        defer if (!transferred) incoming.deinit();
        const state = incoming.state;
        try data.state_admission.validateStable(allocator, result.program, state);
        try result.store.importOwned(&incoming);
        transferred = true;
        for (state.nodes, 0..) |node, id| if (node.activation) |activation| {
            const block = switch (node.record) {
                .control => |control| control.block,
                .continuation => |saved| saved.source_block,
                else => unreachable, // Admitted shape.
            };
            try result.frames.restore(id, result.program.blocks[@intCast(block)].function, activation);
        };
        result.roots = state.roots;
        if (@intFromEnum(state.status) < 4) {
            result.status = @enumFromInt(@intFromEnum(state.status));
        } else {
            const exit = state.nodes[@intCast(state.roots.exit.?.id)].record.exit;
            result.exit = exit;
            result.terminal = switch (state.status) {
                .completed => .{ .completed = exit.reason.normal },
                .failed => .{ .failed = exit.reason.failure },
                .cancelled => .{ .cancelled = exit.cancellation.? },
                else => unreachable,
            };
        }
        return result;
    }

    pub fn deinit(self: *Session) void {
        self.frames.deinit();
        self.store.deinit();
        self.flow.deinit();
        heap.release(ir.Program, self.allocator, self.program);
        self.* = undefined;
    }

    /// Export without advancing, collecting or changing resident custody.
    /// restoreImage checks the matching Program and complete portable State.
    pub fn checkpoint(self: *Session, allocator: std.mem.Allocator) Error![]u8 {
        if (self.poisoned) return error.InvalidState;
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const count = std.math.add(usize, self.store.nodes.items.len, @intFromBool(self.terminal != null)) catch return error.Capacity;
        const nodes = try a.alloc(data.process_state.Node, count);
        for (self.store.nodes.items, self.store.alive.items, 0..) |node, alive, id| {
            // A reachable dead handle must fail graph shape checks, never become
            // a plausible empty semantic object in a checkpoint.
            nodes[id] = if (alive) .{ .record = node, .activation = try self.frames.project(id, a) } else .{ .record = .{ .control = .{ .block = std.math.maxInt(u64), .arguments = &.{} } } };
        }
        var roots = self.roots;
        var status: data.process_state.Status = @enumFromInt(@intFromEnum(self.status));
        if (self.terminal) |terminal| {
            const exit: g.Exit = switch (terminal) {
                .completed => |value| .{ .reason = .{ .normal = value } },
                .failed, .cancelled => self.exit orelse return error.InvalidState,
                else => return error.InvalidState,
            };
            status = switch (terminal) {
                .completed => .completed,
                .failed => .failed,
                .cancelled => .cancelled,
                else => unreachable,
            };
            nodes[count - 1] = .{ .record = .{ .exit = exit } };
            roots = .{ .exit = .{ .id = count - 1 } };
        }
        return data.state_image.emit(allocator, .{
            .program_identity = self.program_identity,
            .status = status,
            .roots = roots,
            .nodes = nodes,
            .blobs = self.store.blobs.items,
        });
    }

    fn supported(program: ir.Program) Error!void {
        for (program.blocks) |block| switch (block.terminator) {
            .forward => return error.UnsupportedTransition,
            else => {},
        };
    }

    pub fn continuation(self: *Session, block: p.Id, _: anytype, control: g.Control) Error!g.NodeRef {
        const current = self.roots.current orelse return error.InvalidState;
        return self.captureContinuation(current, control, try self.frames.get(current.id), nextEdge(self.program.blocks[@intCast(block)].terminator).?);
    }
    pub fn activate(self: *Session, token: g.Capture, after: g.NodeRef) Error!void {
        try @import("resumption.zig").activate(self, token, after);
    }
    pub fn unwindReturnTo(self: *Session, parent: ?g.NodeRef, value: g.Value) Error!?void {
        try self.returnTo(parent, value);
        return if (self.terminal != null) {} else null;
    }
    pub fn finishUnwind(self: *Session, reason: g.Exit) Error!void {
        self.exit = reason;
        self.terminal = switch (reason.reason) {
            .failure => |value| .{ .failed = value },
            .cancellation => .{ .cancelled = reason.cancellation orelse return error.InvalidState },
            else => return error.InvalidState,
        };
        self.roots.current = null;
    }
    fn failCurrent(self: *Session, current: g.NodeRef, value: g.Value) Error!void {
        const control = (try self.store.get(current)).control;
        const values = try self.frames.discards(current.id);
        defer self.allocator.free(values);
        try @import("unwind.zig").failValues(self, value, control.parent, values);
    }
    pub fn cancel(self: *Session, reason: data.protocol.Reason) Error!void {
        if (self.poisoned or self.terminal != null) return error.InvalidState;
        if (reason == .text and !std.unicode.utf8ValidateSlice(reason.text)) return error.InvalidUtf8;
        errdefer self.poisoned = true;
        try @import("unwind.zig").cancel(self, reason);
    }

    fn initialize(self: *Session, input: []const u8) Error!void {
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const scratch = temporary.allocator();
        const facts = try data.admission.schemas(scratch, self.program.schemas);
        const entry = self.program.functions[@intCast(self.program.roots.entry)];
        const values = try scratch.alloc(g.Value, entry.inputs.len);
        var reader: data.wire.Reader = .{ .input = input };
        for (values, entry.inputs) |*value, slot| {
            const schema = entry.layout.slots[@intCast(slot)];
            const encoded = try data.admission.readValue(scratch, self.program.schemas, facts, schema, &reader);
            value.* = try self.store.literal(self.program.schemas, .{ .schema = schema, .bytes = encoded });
        }
        try reader.finish();
        try self.enter(self.program.roots.entry, values, null, null, null);
    }

    pub fn bytes(self: *Session, value: *const g.Value) Error![]const u8 {
        return switch (value.body) {
            .scalar => |*scalar| scalar[0..data.scalar.width(self.program.schemas[@intCast(value.schema)]).?],
            .blob => |reference| self.store.blobs.items[@intCast(reference.id)].bytes,
            else => error.InvalidValue,
        };
    }

    pub fn instructionFailure(self: *Session, instruction: p.Instruction, fault: p.Fault) Error!g.Value {
        for (instruction.failures) |failure| if (failure.kind == fault)
            return self.store.literal(self.program.schemas, self.program.constants[@intCast(failure.value)]);
        return error.InvalidProgram;
    }

    pub fn observe(self: *Session) Error!Observation {
        if (self.poisoned) return error.InvalidState;
        if (self.terminal) |result| return result;
        return switch (self.status) {
            .active => .progressed,
            .yielded => .yielded,
            .parked => blk: {
                const pending = (try self.store.get(self.roots.pending.?)).pending;
                break :blk .{ .requested = .{ .effect = pending.effect, .payload = pending.payload } };
            },
            .unwinding => .progressed,
        };
    }

    pub fn run(self: *Session, quantum: ?usize) Error!Observation {
        var steps: usize = 0;
        while (self.terminal == null and (self.status == .active or self.status == .unwinding) and
            (quantum == null or steps < quantum.?)) : (steps += 1) try self.step();
        return self.observe();
    }

    pub fn resumeYield(self: *Session) Error!void {
        if (self.poisoned or self.status != .yielded) return error.InvalidState;
        self.status = .active;
    }

    pub fn answer(self: *Session, input: []const u8) Error!void {
        if (self.poisoned or self.status != .parked) return error.InvalidState;
        const pending = (try self.store.get(self.roots.pending.?)).pending;
        const effect = self.program.effects[@intCast(pending.effect)];
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const facts = try data.admission.schemas(scratch.allocator(), self.program.schemas);
        const literal: p.Literal = .{ .schema = effect.result, .bytes = input };
        try data.admission.value(scratch.allocator(), self.program.schemas, facts, literal);
        errdefer self.poisoned = true; // Full Session rollback is a later required seam.
        const value = try self.store.literal(self.program.schemas, literal);
        try self.resumeContinuation(pending.continuation, value);
        self.roots.pending = null;
        self.status = .active;
    }

    pub fn step(self: *Session) Error!void {
        if (self.poisoned or self.terminal != null or (self.status != .active and self.status != .unwinding)) return error.InvalidState;
        errdefer self.poisoned = true;
        const current = self.roots.current orelse return error.InvalidState;
        if (self.status == .unwinding) {
            _ = try @import("unwind.zig").step(self);
        } else {
            const control = (try self.store.get(current)).control;
            const code = self.program.blocks[@intCast(control.block)];
            var frame = try self.frames.get(current.id);
            if (frame.position < code.instructions.len) {
                try self.executeInstruction(current, code, &frame);
            } else try self.executeControl(current, control, code, &frame);
        }
        if (self.roots.current == null or self.roots.current.?.id != current.id)
            self.frames.remove(current.id);
        self.transitions += 1;
        if (self.statistics) |statistics| statistics.transitions +|= 1;
        if (self.terminal == null and self.transitions % 256 == 0)
            try self.store.collectWith(self.roots, &self.frames);
    }

    fn executeInstruction(self: *Session, current: g.NodeRef, code: ir.Block, frame: *bindings.Frame) Error!void {
        const source = code.instructions[frame.position];
        const layout = self.program.functions[@intCast(code.function)].layout.slots;
        const operation: p.Instruction = .{
            .opcode = source.opcode,
            .result_type = layout[@intCast(source.destination)],
            .operands = source.operands,
            .immediate = source.immediate,
            .failures = source.failures,
        };
        const reader = try self.frames.slots.reader(frame.view);
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        var values: @import("values.zig").Values = .{
            .allocator = temporary.allocator(),
            .schemas = self.program.schemas,
            .store = &self.store,
            .facts = self.value_facts,
            .traits = self.uses,
        };
        switch (try @import("instruction.zig").execute(self, operation, reader, &values)) {
            .failed => |failure| try self.failCurrent(current, failure),
            .value => |value| {
                if (!source.opcode.borrowsOperands()) for (source.operands) |slot| {
                    if (!self.uses.copy[@intCast(layout[@intCast(slot)])])
                        try self.frames.clear(frame, slot);
                };
                try self.frames.write(frame, source.destination, value);
                frame.position += 1;
                try self.frames.prune(frame, self.flow.live[@intCast((try self.store.get(current)).control.block)][frame.position]);
                self.frames.update(current.id, frame.*);
            },
        }
    }

    fn executeControl(self: *Session, current: g.NodeRef, saved: g.Control, code: ir.Block, frame: *bindings.Frame) Error!void {
        const reader = try self.frames.slots.reader(frame.view);
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const scratch = temporary.allocator();
        switch (code.terminator) {
            .return_value => |slot| try self.returnTo(saved.parent, try read(reader, slot)),
            .fail => |slot| try self.failCurrent(current, try read(reader, slot)),
            .jump => |edge| try self.jump(current, saved, frame, edge, null),
            .yield_value => |edge| {
                try self.jump(current, saved, frame, edge, null);
                self.status = .yielded;
            },
            .branch => |branch| {
                const condition = try read(reader, branch.condition);
                try self.jump(current, saved, frame, if (condition.body.scalar[0] == 1) branch.when_true else branch.when_false, null);
            },
            .call => |call| {
                const arguments = try self.collectArguments(scratch, reader, call.arguments);
                const parent = if (self.isTail(call.next)) saved.parent else try self.captureContinuation(current, saved, frame.*, call.next);
                try self.enter(call.function, arguments, parent, saved.evidence, saved.region);
            },
            .apply => |apply| {
                const computation = try read(reader, apply.computation);
                const arguments = try self.collectArguments(scratch, reader, apply.arguments);
                const parent = try self.captureContinuation(current, saved, frame.*, apply.next);
                try self.applyComputation(computation, arguments, parent, saved.evidence, saved.region);
            },
            .protect => |protection| try @import("unwind.zig").protect(self, protection, reader, saved),
            .dispose => |disposal| try @import("unwind.zig").dispose(self, disposal, reader, saved),
            .handle => |handle| try self.install(current, saved, frame.*, handle, reader, scratch),
            .perform => |perform| try self.performEffect(current, saved, frame.*, perform, reader, scratch),
            .resume_value, .resume_with, .resume_computation => try self.resumeControl(current, saved, frame.*, code.terminator, reader, scratch),
            .switch_variant, .unpack_product => try self.aggregateControl(current, saved, frame, code.terminator, reader, scratch),
            .with_region => |region| {
                const descriptor = try self.store.add(.{ .region = .{
                    .descriptor = region.region,
                    .outer = saved.region,
                    .obligations = &.{},
                } });
                const after = try self.captureContinuation(current, saved, frame.*, region.next);
                const wrapper = try self.store.add(.{ .region_scope = .{
                    .source_block = saved.block,
                    .region = descriptor,
                    .return_to = after,
                } });
                const body = try read(reader, region.body);
                const parameters = self.program.schemas[@intCast(body.schema)].internal.computation.parameters;
                const args = try scratch.alloc(g.Value, region.arguments.len + 1);
                args[0] = .{ .schema = parameters[0], .body = .{ .reference = descriptor } };
                for (args[1..], region.arguments) |*value, slot| value.* = try read(reader, slot);
                try self.applyComputation(body, args, wrapper, saved.evidence, descriptor);
            },
            else => return error.UnsupportedTransition,
        }
    }

    fn resumeControl(self: *Session, current: g.NodeRef, control: g.Control, frame: bindings.Frame, term: ir.Terminator, reader: anytype, scratch: std.mem.Allocator) Error!void {
        switch (term) {
            inline .resume_value, .resume_with, .resume_computation => |operation, kind| {
                const resumption = try read(reader, operation.resumption);
                const token = try self.takeCapture(resumption);
                defer if (self.program.schemas[@intCast(resumption.schema)].internal.resumption.use == .multi)
                    self.allocator.free(token.use_site_capabilities);
                const after = try self.captureContinuation(current, control, frame, operation.next);
                if (comptime kind == .resume_with) {
                    const state = try self.collectArguments(scratch, reader, operation.state);
                    const handler = try self.store.add(.{ .handler = .{
                        .definition = operation.handler,
                        .state = state,
                        .evidence = control.evidence,
                        .region = control.region,
                    } });
                    try self.store.replace(token.delimiter, .{ .attachment = .{
                        .handler = handler,
                        .outer = control.evidence,
                        .return_to = after,
                        .region = control.region,
                    } });
                    try self.resumeContinuation(token.capture.?, try read(reader, operation.argument));
                } else {
                    const evidence = try @import("resumption.zig").prepare(self, token, after);
                    if (comptime kind == .resume_value) {
                        try self.resumeContinuation(token.capture.?, try read(reader, operation.argument));
                    } else {
                        const saved = (try self.store.get(token.capture.?)).continuation;
                        const injection = try self.store.add(.{ .injection = .{ .continuation = token.capture.? } });
                        try self.applyComputation(try read(reader, operation.computation), token.use_site_capabilities, injection, evidence, saved.region);
                    }
                }
            },
            else => unreachable,
        }
    }

    fn collectArguments(_: *Session, allocator: std.mem.Allocator, reader: anytype, operands: []const p.Id) Error![]g.Value {
        const values = try allocator.alloc(g.Value, operands.len);
        for (values, operands) |*value, slot| value.* = try read(reader, slot);
        return values;
    }

    fn isTail(self: *Session, edge: ir.Edge) bool {
        const target = self.program.blocks[@intCast(edge.block)];
        return target.instructions.len == 0 and target.terminator == .return_value and
            edge.assignments.len == 1 and edge.assignments[0].source == .returned and
            edge.assignments[0].destination == target.terminator.return_value;
    }

    fn enter(self: *Session, function: p.Id, args: []const g.Value, parent: ?g.NodeRef, evidence: ?g.NodeRef, region: ?g.NodeRef) Error!void {
        const target = self.program.functions[@intCast(function)];
        if (target.inputs.len != args.len) return error.InvalidState;
        var frame = try self.frames.create(function);
        errdefer self.frames.releaseFrame(frame);
        for (args, target.inputs) |value, slot| try self.frames.write(&frame, slot, value);
        try self.frames.prune(&frame, self.flow.live[@intCast(target.entry)][0]);
        const control = try self.store.add(.{ .control = .{
            .block = target.entry,
            .arguments = &.{},
            .parent = parent,
            .evidence = evidence,
            .region = region,
        } });
        try self.frames.put(control.id, frame);
        self.roots.current = control;
        self.roots.evidence = evidence;
    }

    pub fn applyComputation(self: *Session, value: g.Value, supplied: []const g.Value, parent: ?g.NodeRef, evidence: ?g.NodeRef, region: ?g.NodeRef) Error!void {
        const closure = (try self.store.get(valueRef(value))).computation;
        const definition = self.program.constructors[@intCast(closure.constructor)];
        const captured = (try self.store.get(closure.environment)).environment.values;
        const values = try std.mem.concat(self.allocator, g.Value, &.{ captured, supplied });
        defer self.allocator.free(values);
        try self.enter(definition.function, values, parent, evidence, region);
    }

    fn retainedSlots(self: *Session, edge: ir.Edge) Error!data.analysis_sets.Root {
        const after = self.flow.live[@intCast(edge.block)][0];
        var root = after;
        for (edge.assignments) |assignment| root = try self.flow.pool.remove(root, assignment.destination);
        for (edge.assignments) |assignment| {
            if (assignment.source == .slot and self.flow.pool.contains(after, assignment.destination))
                root = try self.flow.pool.insert(root, assignment.source.slot);
        }
        return root;
    }

    fn captureContinuation(self: *Session, _: g.NodeRef, control: g.Control, original: bindings.Frame, edge: ir.Edge) Error!g.NodeRef {
        var frame = try self.frames.forkFrame(original);
        errdefer self.frames.releaseFrame(frame);
        try self.frames.prune(&frame, try self.retainedSlots(edge));
        const saved = try self.store.add(.{ .continuation = .{
            .source_block = control.block,
            .arguments = &.{},
            .parent = control.parent,
            .evidence = control.evidence,
            .region = control.region,
        } });
        try self.frames.put(saved.id, frame);
        return saved;
    }

    fn assignEdge(self: *Session, frame: *bindings.Frame, next: ir.Edge, returned: ?g.Value) Error!void {
        const values = try self.allocator.alloc(g.Value, next.assignments.len);
        defer self.allocator.free(values);
        const live = self.flow.live[@intCast(next.block)][0];
        for (values, next.assignments) |*value, assignment| {
            if (!self.flow.pool.contains(live, assignment.destination)) continue;
            value.* = switch (assignment.source) {
                .slot => |slot| try self.frames.slots.get(frame.view, @intCast(slot)),
                .returned => returned orelse return error.InvalidState,
            };
        }
        const block = self.program.blocks[@intCast(next.block)];
        const layout = self.program.functions[@intCast(block.function)].layout.slots;
        for (next.assignments) |assignment| if (assignment.source == .slot) {
            const slot = assignment.source.slot;
            if (!self.uses.copy[@intCast(layout[@intCast(slot)])]) try self.frames.clear(frame, slot);
        };
        try self.frames.scope(frame, block.custody);
        for (next.assignments, 0..) |assignment, index| {
            if (self.flow.pool.contains(live, assignment.destination))
                try self.frames.write(frame, assignment.destination, values[index]);
        }
        frame.position = 0;
        try self.frames.prune(frame, self.flow.live[@intCast(next.block)][0]);
    }

    fn jump(self: *Session, current: g.NodeRef, control: g.Control, frame: *bindings.Frame, next: ir.Edge, returned: ?g.Value) Error!void {
        try self.assignEdge(frame, next, returned);
        var changed = control;
        changed.block = next.block;
        try self.store.replace(current, .{ .control = changed });
        self.frames.update(current.id, frame.*);
    }

    pub fn resumeContinuation(self: *Session, reference: g.NodeRef, value: g.Value) Error!void {
        const saved = (try self.store.get(reference)).continuation;
        const next = nextEdge(self.program.blocks[@intCast(saved.source_block)].terminator).?;
        const current = try self.store.add(.{ .control = .{
            .block = next.block,
            .arguments = &.{},
            .parent = saved.parent,
            .evidence = saved.evidence,
            .region = saved.region,
        } });
        var frame = try self.frames.move(reference.id, current.id);
        try self.assignEdge(&frame, next, value);
        self.frames.update(current.id, frame);
        self.roots.current = current;
        self.roots.evidence = saved.evidence;
    }

    fn returnTo(self: *Session, parent: ?g.NodeRef, value: g.Value) Error!void {
        var cursor = parent;
        while (cursor) |reference| {
            switch (try self.store.get(reference)) {
                .region_scope => |region| {
                    cursor = region.return_to;
                    continue;
                },
                .continuation => try self.resumeContinuation(reference, value),
                .injection => |injection| try self.resumeContinuation(injection.continuation, value),
                .protection => |protection| try @import("unwind.zig").begin(self, .{ .normal = value }, reference, protection.return_to, &.{}),
                .cleanup_return => try @import("unwind.zig").returned(self, reference),
                .disposal_return => |disposal| try @import("unwind.zig").returnedDisposal(self, disposal, value),
                .attachment => |attachment| {
                    if (attachment.phase != .active) return error.InvalidState;
                    const handler = (try self.store.get(attachment.handler)).handler;
                    const definition = self.program.handlers[@intCast(handler.definition)];
                    const values = try std.mem.concat(self.allocator, g.Value, &.{ handler.state, &.{value} });
                    defer self.allocator.free(values);
                    try self.enter(definition.return_function, values, attachment.return_to, handler.evidence, handler.region);
                },
                else => return error.UnsupportedTransition,
            }
            return;
        }
        self.terminal = .{ .completed = value };
        self.roots.current = null;
    }

    fn install(self: *Session, current: g.NodeRef, control: g.Control, frame: bindings.Frame, operation: anytype, reader: anytype, scratch: std.mem.Allocator) Error!void {
        const definition = self.program.handlers[@intCast(operation.handler)];
        const state = try self.collectArguments(scratch, reader, operation.state);
        const handler = try self.store.add(.{ .handler = .{
            .definition = operation.handler,
            .state = state,
            .evidence = control.evidence,
            .region = control.region,
        } });
        const after = try self.captureContinuation(current, control, frame, operation.next);
        const attachment = try self.store.add(.{ .attachment = .{
            .handler = handler,
            .outer = control.evidence,
            .return_to = after,
            .region = control.region,
        } });
        const body = try read(reader, operation.body);
        const signature = self.program.schemas[@intCast(body.schema)].internal.computation;
        const args = try scratch.alloc(g.Value, definition.clauses.len + operation.arguments.len);
        for (definition.clauses, 0..) |_, index|
            args[index] = .{ .schema = signature.parameters[index], .body = .{ .reference = attachment } };
        for (args[definition.clauses.len..], operation.arguments) |*value, slot| value.* = try read(reader, slot);
        try self.applyComputation(body, args, attachment, attachment, control.region);
    }

    fn performEffect(self: *Session, current: g.NodeRef, control: g.Control, frame: bindings.Frame, operation: ir.Perform, reader: anytype, scratch: std.mem.Allocator) Error!void {
        const payload = try read(reader, operation.payload);
        const captured = try self.captureContinuation(current, control, frame, operation.next);
        if (operation.capability == null) {
            self.roots.pending = try self.store.add(.{ .pending = .{
                .effect = operation.effect,
                .payload = payload,
                .continuation = captured,
                .source_block = control.block,
            } });
            self.roots.current = null;
            self.status = .parked;
            return;
        }
        const selected = valueRef(try read(reader, operation.capability.?));
        try self.inScope(control.parent, selected);
        const selected_record = try self.store.get(selected);
        if (selected_record != .attachment or selected_record.attachment.phase != .active)
            return error.InvalidScope;
        var attachment = selected_record.attachment;
        const handler = (try self.store.get(attachment.handler)).handler;
        const definition = self.program.handlers[@intCast(handler.definition)];
        var found: ?p.Clause = null;
        for (definition.clauses) |clause| if (clause.effect == operation.effect) {
            found = clause;
            break;
        };
        const clause = found orelse return error.InvalidEffect;
        const use_site = try self.collectArguments(scratch, reader, operation.use_site_capabilities);
        const multi = self.program.schemas[@intCast(clause.resumption)].internal.resumption.use == .multi;
        const capture: g.Capture = .{
            .schema = clause.resumption,
            .capture = captured,
            .delimiter = selected,
            .evidence = control.evidence,
            .use_site_capabilities = use_site,
        };
        const token = try self.store.add(if (multi) .{ .multi_template = capture } else .{ .one_shot = capture });
        const args = try scratch.alloc(g.Value, handler.state.len + operation.bodies.len + 2);
        @memcpy(args[0..handler.state.len], handler.state);
        args[handler.state.len] = payload;
        for (operation.bodies, 0..) |slot, index| args[handler.state.len + 1 + index] = try read(reader, slot);
        args[args.len - 1] = .{ .schema = clause.resumption, .body = if (multi) .{ .reference = token } else .{ .owned = .{ .node = token } } };
        const parent = attachment.return_to;
        attachment.return_to = null;
        attachment.phase = .suspended;
        try self.store.replace(selected, .{ .attachment = attachment });
        try self.enter(clause.function, args, parent, handler.evidence, handler.region);
    }

    pub fn takeCapture(self: *Session, value: g.Value) Error!g.Capture {
        const reference = valueRef(value);
        const record = try self.store.get(reference);
        if (record == .multi_template)
            return @import("clone.zig").instantiateFrames(self.allocator, &self.store, record.multi_template, &self.frames);
        if (record != .one_shot or record.one_shot.capture == null) return error.InvalidOwnership;
        const captured = record.one_shot;
        var consumed = captured;
        consumed.capture = null;
        try self.store.replace(reference, .{ .one_shot = consumed });
        var result = captured;
        result.use_site_capabilities = (try self.store.get(reference)).one_shot.use_site_capabilities;
        return result;
    }

    fn inScope(self: *Session, parent: ?g.NodeRef, target: g.NodeRef) Error!void {
        var cursor = parent;
        while (cursor) |reference| {
            if (reference.id == target.id) return;
            cursor = switch (try self.store.get(reference)) {
                .continuation => |saved| saved.parent,
                .attachment => |attachment| attachment.return_to,
                .region_scope => |region| region.return_to,
                .injection => |injection| injection.continuation,
                .protection => |protection| protection.return_to,
                .cleanup_return => |cleanup| cleanup.parent,
                .disposal_return => |disposal| disposal.parent,
                else => return error.InvalidScope,
            };
        }
        return error.InvalidScope;
    }

    fn aggregateControl(self: *Session, current: g.NodeRef, control: g.Control, frame: *bindings.Frame, term: ir.Terminator, reader: anytype, scratch: std.mem.Allocator) Error!void {
        var values: @import("values.zig").Values = .{
            .allocator = scratch,
            .schemas = self.program.schemas,
            .store = &self.store,
        };
        switch (term) {
            .switch_variant => |selected| {
                const parts = try values.split(try read(reader, selected.value));
                const layout = self.program.functions[@intCast(self.program.blocks[@intCast(control.block)].function)].layout.slots;
                if (!self.uses.copy[@intCast(layout[@intCast(selected.value)])])
                    try self.frames.clear(frame, selected.value);
                try self.jump(current, control, frame, selected.cases[@intCast(parts.tag)], parts.fields[0]);
            },
            .unpack_product => |unpack| {
                const value = try read(reader, unpack.value);
                const parts = try values.split(value);
                if (!self.uses.copy[@intCast(value.schema)]) try self.frames.clear(frame, unpack.value);
                try self.frames.scope(frame, self.program.blocks[@intCast(unpack.next.block)].custody);
                for (parts.fields, unpack.destinations) |field, slot| try self.frames.write(frame, slot, field);
                try self.jump(current, control, frame, unpack.next, null);
            },
            else => unreachable,
        }
    }
};

fn valueRef(value: g.Value) g.NodeRef {
    return switch (value.body) {
        .reference => |reference| reference,
        .owned => |owned| owned.node,
        else => unreachable,
    };
}
fn nextEdge(term: ir.Terminator) ?ir.Edge {
    return switch (term) {
        inline .call, .perform, .apply, .handle, .resume_value, .resume_with, .resume_computation, .with_region, .protect, .dispose => |operation| operation.next,
        else => null,
    };
}
