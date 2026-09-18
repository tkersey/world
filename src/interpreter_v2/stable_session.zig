// Copyright (c) 2026 World contributors. MIT license.
//! Low-level native evaluator. Published mutation runs in a private fresh
//! invocation or through Resident's transaction and lifecycle boundary.
const std = @import("std");
const data = @import("boundary_data");
const p = data.program;
const ir = data.activation;
const g = data.graph;
const heap = @import("store.zig");
const bindings = @import("activation_frames.zig");
const read = @import("operands.zig").read;
const Slots = @import("activation_slots.zig").ActivationSlots;
const protocol = data.invocation;
pub const invocation = @import("invocation.zig");
pub const Prepared = @import("prepared.zig").Prepared;
pub const Resident = @import("resident.zig").Resident;
pub const Workspace = @import("arena.zig").Arena;
pub const AllocationBudget = @import("allocation_budget.zig").Budget;
pub const Error = @import("runtime_types.zig").Error || bindings.Error || data.activation_ownership.Error || data.program_image.Error || protocol.Error;
pub const Pending = struct {
    allocator: std.mem.Allocator,
    state: []u8,
    request: protocol.Request,
    pub fn deinit(self: *Pending) void {
        self.allocator.free(self.state);
        self.allocator.free(self.request.binding.semantic_identity);
        self.allocator.free(self.request.binding.payload_schema);
        self.allocator.free(self.request.binding.resume_schema);
        self.allocator.free(self.request.binding.payload);
        self.* = undefined;
    }
};
pub const Observation = union(enum) {
    progressed,
    yielded,
    requested: struct { effect: p.Id, payload: g.Value },
    completed: g.Value,
    failed: g.Value,
    cancelled: data.invocation.Reason,
};

pub const Session = struct {
    pub const ExecutionError = Error;
    pub const UnwindOutcome = void;
    allocator: std.mem.Allocator,
    program: ir.Program,
    program_identity: [32]u8,
    prepared: *@import("prepared.zig").Core,
    flow: data.program_image.Analysis,
    uses: data.traits.Facts,
    value_facts: data.admission.SchemaFacts,
    store: heap.Store,
    frames: bindings.Frames,
    roots: g.Roots = .{},
    status: g.Status = .active,
    /// Terminal observations are derived from this Store-owned exit node.
    terminal: ?g.NodeRef = null,
    poisoned: bool = false,
    transitions: usize = 0,
    statistics: ?*@import("runtime_types.zig").Statistics = null,

    pub const Transaction = struct {
        frames: bindings.Frames.Backup,
        roots: g.Roots,
        status: g.Status,
        terminal: ?g.NodeRef,
        poisoned: bool,
        transitions: usize,

        pub fn commit(self: *Transaction, session: *Session) void {
            session.store.commit();
            self.frames.discard(&session.frames);
            self.* = undefined;
        }
        pub fn rollback(self: *Transaction, session: *Session) void {
            self.frames.restore(&session.frames);
            session.store.rollback();
            session.roots = self.roots;
            session.status = self.status;
            session.terminal = self.terminal;
            session.poisoned = self.poisoned;
            session.transitions = self.transitions;
            self.* = undefined;
        }
    };

    pub fn begin(self: *Session) Error!Transaction {
        if (self.poisoned) return error.InvalidState;
        try self.store.begin();
        errdefer self.store.rollback();
        return .{
            .frames = try self.frames.backup(),
            .roots = self.roots,
            .status = self.status,
            .terminal = self.terminal,
            .poisoned = self.poisoned,
            .transitions = self.transitions,
        };
    }

    /// The fresh path uses the same prepared owner, releasing its outer handle
    /// once the Session has retained its lease.
    pub fn initImage(allocator: std.mem.Allocator, image: []const u8, arguments: []const u8) Error!Session {
        var prepared = try Prepared.init(allocator, image);
        defer prepared.deinit();
        return start(allocator, &prepared, arguments);
    }

    pub fn start(allocator: std.mem.Allocator, prepared: *const Prepared, arguments: []const u8) Error!Session {
        var result = try empty(allocator, prepared);
        errdefer result.deinit();
        try result.initialize(arguments);
        return result;
    }

    fn empty(allocator: std.mem.Allocator, prepared: *const Prepared) Error!Session {
        const core = try prepared.acquire();
        errdefer core.release();
        var flow = try core.admitted().analysis(allocator);
        errdefer flow.deinit();
        const program = core.admitted().program();
        const frames = try bindings.Frames.init(allocator, flow.facts.pool, program);
        return .{
            .allocator = allocator,
            .prepared = core,
            .program = program,
            .program_identity = core.admitted().identity(),
            .flow = flow,
            .uses = core.admitted().traits(),
            .value_facts = core.admitted().schemaFacts(),
            .frames = frames,
            .store = .{ .allocator = allocator },
        };
    }

    pub fn restoreImage(allocator: std.mem.Allocator, image: []const u8, checkpoint_bytes: []const u8) Error!Session {
        var prepared = try Prepared.init(allocator, image);
        defer prepared.deinit();
        return restore(allocator, &prepared, checkpoint_bytes);
    }

    pub fn restore(allocator: std.mem.Allocator, prepared: *const Prepared, checkpoint_bytes: []const u8) Error!Session {
        var result = try empty(allocator, prepared);
        errdefer result.deinit();
        var incoming = try data.state_image.decodeGraph(allocator, checkpoint_bytes);
        var transferred = false;
        defer if (!transferred) incoming.deinit();
        const state = incoming.state;
        try data.state_admission.validateAdmitted(allocator, result.prepared.admitted(), state);
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
            result.terminal = state.roots.exit;
        }
        return result;
    }

    pub fn deinit(self: *Session) void {
        self.frames.deinit();
        self.store.deinit();
        self.flow.deinit();
        self.prepared.release();
        self.* = undefined;
    }

    /// Export without advancing, collecting or changing resident custody.
    /// restoreImage checks the matching Program and complete portable State.
    pub fn checkpoint(self: *Session, allocator: std.mem.Allocator) Error![]u8 {
        if (self.poisoned) return error.InvalidState;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const count = self.store.nodes.items.len;
        const nodes = try a.alloc(data.process_state.Node, count);
        for (self.store.nodes.items, self.store.alive.items, 0..) |node, alive, id| {
            // A reachable dead handle must fail graph shape checks, never become
            // a plausible empty semantic object in a checkpoint.
            nodes[id] = if (alive) .{ .record = node, .activation = try self.frames.project(id, a) } else .{ .record = .{ .control = .{ .block = std.math.maxInt(u64) } } };
        }
        const roots = self.roots;
        var status: data.process_state.Status = @enumFromInt(@intFromEnum(self.status));
        if (self.terminal != null) {
            status = switch ((try self.terminalExit()).reason) {
                .normal => .completed,
                .failure => .failed,
                .cancellation => .cancelled,
                else => return error.InvalidState,
            };
        }

        const public_state = try @import("value_projection.zig").project(a, self.program.schemas, &self.store, data.process_state.State{
            .program_identity = self.program_identity,
            .status = status,
            .roots = roots,
            .nodes = nodes,
            .blobs = self.store.blobs.items,
        });
        return data.state_image.emitWith(self.allocator, public_state, allocator);
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
    /// The Store owns terminal fields and their transitive values. Keeping only
    /// a handle here allows collection and imported-backing compaction without
    /// invalidating a cached cancellation reason or cleanup-failure slice.
    pub fn terminalExit(self: *const Session) Error!g.Exit {
        const node = try self.store.get(self.terminal orelse return error.InvalidState);
        return switch (node) {
            .exit => |exit| exit,
            else => error.InvalidState,
        };
    }
    fn finishTerminal(self: *Session, reason: g.Exit) Error!void {
        const exit = try self.store.add(.{ .exit = reason });
        self.roots = .{ .exit = exit };
        self.terminal = exit;
    }
    pub fn finishUnwind(self: *Session, reason: g.Exit) Error!void {
        if (reason.reason != .failure and reason.reason != .cancellation) return error.InvalidState;
        if (reason.reason == .cancellation and reason.cancellation == null) return error.InvalidState;
        try self.finishTerminal(reason);
    }
    fn failCurrent(self: *Session, current: g.NodeRef, value: g.Value) Error!void {
        const control = (try self.store.get(current)).control;
        const values = try self.frames.discards(current.id);
        defer self.allocator.free(values);
        try @import("unwind.zig").failValues(self, value, control.parent, values);
    }
    pub fn cancel(self: *Session, reason: data.invocation.Reason) Error!void {
        if (self.poisoned or self.terminal != null) return error.InvalidState;
        if (reason == .text and !std.unicode.utf8ValidateSlice(reason.text)) return error.InvalidUtf8;
        errdefer self.poisoned = true;
        try @import("unwind.zig").cancel(self, reason);
    }

    fn initialize(self: *Session, input: []const u8) Error!void {
        var temporary = std.heap.ArenaAllocator.init(self.allocator);
        defer temporary.deinit();
        const scratch = temporary.allocator();
        const values = try self.store.importArguments(self.prepared.admitted(), input, scratch);
        try self.enter(self.program.roots.entry, values, null, null, null);
        try self.store.compactImported();
    }

    pub fn bytes(self: *Session, value: *const g.Value) Error![]const u8 {
        const values: @import("values.zig").Values = .{
            .allocator = self.allocator,
            .schemas = self.program.schemas,
            .store = &self.store,
        };
        return values.bytes(value);
    }

    pub fn instructionFailure(self: *Session, instruction: ir.Instruction, fault: p.Fault) Error!g.Value {
        for (instruction.failures) |failure| if (failure.kind == fault)
            return self.store.literal(self.program.schemas, self.program.constants[@intCast(failure.value)]);
        return error.InvalidProgram;
    }

    pub fn observe(self: *Session) Error!Observation {
        if (self.poisoned) return error.InvalidState;
        if (self.terminal != null) {
            const exit = try self.terminalExit();
            return switch (exit.reason) {
                .normal => |value| .{ .completed = value },
                .failure => |value| .{ .failed = value },
                .cancellation => .{ .cancelled = exit.cancellation orelse return error.InvalidState },
                else => error.InvalidState,
            };
        }
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

    pub fn run(self: *Session, quantum: ?u64) Error!Observation {
        var steps: u64 = 0;
        while (self.terminal == null and (self.status == .active or self.status == .unwinding) and
            (quantum == null or steps < quantum.?)) : (steps +|= 1) try self.step();
        return self.observe();
    }

    pub fn resumeYield(self: *Session) Error!void {
        if (self.poisoned or self.status != .yielded) return error.InvalidState;
        self.status = .active;
    }

    pub fn pendingRequest(self: *Session, allocator: std.mem.Allocator) Error!Pending {
        if (self.poisoned or self.terminal != null or self.status != .parked) return error.InvalidState;
        const operation = (try self.store.get(self.roots.pending.?)).pending;
        const effect = self.program.effects[@intCast(operation.effect)];
        const state = try self.checkpoint(allocator);
        errdefer allocator.free(state);
        const contract = try self.prepared.contract(operation.effect);
        const payload_schema = try allocator.dupe(u8, contract.payload);
        errdefer allocator.free(payload_schema);
        const resume_schema = try allocator.dupe(u8, contract.resume_value);
        errdefer allocator.free(resume_schema);
        const name = try allocator.dupe(u8, effect.identity);
        errdefer allocator.free(name);
        const payload = try allocator.dupe(u8, try self.bytes(&operation.payload));
        errdefer allocator.free(payload);
        return .{ .allocator = allocator, .state = state, .request = try protocol.request(.{
            .program_identity = self.program_identity,
            .pending_state_digest = protocol.stateDigest(state),
            .effect = operation.effect,
            .semantic_identity = name,
            .payload_schema = payload_schema,
            .resume_schema = resume_schema,
            .payload = payload,
        }) };
    }

    /// Recompute the pending binding before accepting an ERS3 response.
    pub fn answer(self: *Session, input: []const u8) Error!void {
        var expected = try self.pendingRequest(self.allocator);
        defer expected.deinit();
        var response = try protocol.decode(protocol.Result, self.allocator, input);
        defer response.deinit();
        if (!std.mem.eql(u8, &expected.request.request_identity, &response.value.request_identity)) return error.InvalidResult;
        // The expected descriptors are immutable preparation data. The actual
        // Program result schema is checked below with those same admitted facts.
        try self.answerValue(response.value.value);
    }

    fn answerValue(self: *Session, input: []const u8) Error!void {
        if (self.poisoned or self.status != .parked) return error.InvalidState;
        const pending = (try self.store.get(self.roots.pending.?)).pending;
        const effect = self.program.effects[@intCast(pending.effect)];
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const facts = self.value_facts;
        const literal: p.Literal = .{ .schema = effect.result, .bytes = input };
        try data.admission.value(scratch.allocator(), self.program.schemas, facts, literal);
        errdefer self.poisoned = true; // Resident restores its retained entry on error.
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
        if (self.roots.current == null or self.roots.current.?.id != current.id) {
            // A saved continuation keeps custody at the old control-node ID.
            if (try self.store.get(current) == .control) self.frames.remove(current.id);
        }
        self.transitions +%= 1;
        if (self.statistics) |statistics| statistics.transitions +|= 1;
        // A public suspension may last indefinitely. Reclaim its dead backing
        // before publication; checkpoint itself remains a read-only projection.
        if (self.terminal != null or self.status == .yielded or self.status == .parked or self.transitions % 256 == 0)
            try self.store.collectWith(self.roots, &self.frames);
    }

    fn executeInstruction(self: *Session, current: g.NodeRef, code: ir.Block, frame: *bindings.Frame) Error!void {
        const source = code.instructions[frame.position];
        const layout = self.program.functions[@intCast(code.function)].layout.slots;
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
        switch (try @import("instruction.zig").execute(self, source, layout[@intCast(source.destination)], reader, &values)) {
            .failed => |failure| try self.failCurrent(current, failure),
            .value => |value| {
                if (!source.opcode.borrowsOperands()) for (source.operands) |slot| {
                    if (!self.uses.copy[@intCast(layout[@intCast(slot)])])
                        try self.frames.clear(frame, slot);
                };
                frame.position += 1;
                try self.frames.apply(frame, self.flow.facts.live[@intCast((try self.store.get(current)).control.block)][frame.position], @as([]const p.Id, &.{source.destination}), &.{value});
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
                if (call.function == frame.function and self.isTail(call.next) and !frame.custody.initialized) {
                    const entry = self.program.functions[@intCast(call.function)].entry;
                    try self.frames.restart(frame, self.flow.facts.live[@intCast(entry)][0], arguments);
                    var changed = saved;
                    changed.block = entry;
                    try self.store.replace(current, .{ .control = changed });
                    self.frames.update(current.id, frame.*);
                    return;
                }
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
                const body = try read(reader, region.body);
                const parameters = self.program.schemas[@intCast(body.schema)].internal.computation.parameters;
                const args = try scratch.alloc(g.Value, region.arguments.len + 1);
                args[0] = .{ .schema = parameters[0], .body = .{ .reference = descriptor } };
                for (args[1..], region.arguments) |*value, slot| value.* = try read(reader, slot);
                const after = try self.captureContinuation(current, saved, frame.*, region.next);
                const wrapper = try self.store.add(.{ .region_scope = .{
                    .source_block = saved.block,
                    .region = descriptor,
                    .return_to = after,
                } });
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
                const argument = try read(reader, if (comptime kind == .resume_computation)
                    operation.computation
                else
                    operation.argument);
                const state = if (comptime kind == .resume_with)
                    try self.collectArguments(scratch, reader, operation.state)
                else
                    &.{};
                const after = try self.captureContinuation(current, control, frame, operation.next);
                if (comptime kind == .resume_with) {
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
                    try self.resumeContinuation(token.capture.?, argument);
                } else {
                    const evidence = try @import("resumption.zig").prepare(self, token, after);
                    if (comptime kind == .resume_value) {
                        try self.resumeContinuation(token.capture.?, argument);
                    } else {
                        const saved = (try self.store.get(token.capture.?)).continuation;
                        const injection = try self.store.add(.{ .injection = .{ .continuation = token.capture.? } });
                        try self.applyComputation(argument, token.use_site_capabilities, injection, evidence, saved.region);
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
        // Reserve the control record before its activation allocates storage.
        // The current root is published only after both owners are complete.
        const control = try self.store.add(.{ .control = .{
            .block = target.entry,
            .parent = parent,
            .evidence = evidence,
            .region = region,
        } });
        var frame = try self.frames.create(function);
        errdefer self.frames.releaseFrame(frame);
        try self.frames.apply(&frame, self.flow.facts.live[@intCast(target.entry)][0], target.inputs, args);
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
        const after = self.flow.facts.live[@intCast(edge.block)][0];
        var root = after;
        for (edge.assignments) |assignment| root = try self.flow.facts.pool.remove(root, assignment.destination);
        for (edge.assignments) |assignment| {
            if (assignment.source == .slot and self.flow.facts.pool.contains(after, assignment.destination))
                root = try self.flow.facts.pool.insert(root, assignment.source.slot);
        }
        return root;
    }

    // All remaining operands must be gathered before this phase transition.
    // Admission gives the active control one custodian; it becomes the saved
    // continuation in place. Multi-shot activation still clones its template.
    fn captureContinuation(self: *Session, current: g.NodeRef, control: g.Control, original: bindings.Frame, edge: ir.Edge) Error!g.NodeRef {
        var frame = original;
        try self.frames.prune(&frame, try self.retainedSlots(edge));
        try self.store.replace(current, .{ .continuation = .{
            .source_block = control.block,
            .parent = control.parent,
            .evidence = control.evidence,
            .region = control.region,
        } });
        self.frames.update(current.id, frame);
        return current;
    }

    fn assignEdge(self: *Session, frame: *bindings.Frame, next: ir.Edge, returned: ?g.Value) Error!void {
        const values = try self.allocator.alloc(g.Value, next.assignments.len);
        defer self.allocator.free(values);
        const live = self.flow.facts.live[@intCast(next.block)][0];
        for (values, next.assignments) |*value, assignment| {
            if (!self.flow.facts.pool.contains(live, assignment.destination)) continue;
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
        try self.frames.apply(frame, live, next.assignments, values);
        frame.position = 0;
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
        try self.finishTerminal(.{ .reason = .{ .normal = value } });
    }

    fn install(self: *Session, current: g.NodeRef, control: g.Control, frame: bindings.Frame, operation: anytype, reader: anytype, scratch: std.mem.Allocator) Error!void {
        const definition = self.program.handlers[@intCast(operation.handler)];
        // Handler, attachment and callee control; capture reuses the current node.
        try self.store.reserveNodes(3);
        const state = try self.collectArguments(scratch, reader, operation.state);
        const body = try read(reader, operation.body);
        const signature = self.program.schemas[@intCast(body.schema)].internal.computation;
        const args = try scratch.alloc(g.Value, definition.clauses.len + operation.arguments.len);
        for (args[definition.clauses.len..], operation.arguments) |*value, slot| value.* = try read(reader, slot);
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
        for (definition.clauses, 0..) |_, index|
            args[index] = .{ .schema = signature.parameters[index], .body = .{ .reference = attachment } };
        try self.applyComputation(body, args, attachment, attachment, control.region);
    }

    fn performEffect(self: *Session, current: g.NodeRef, control: g.Control, frame: bindings.Frame, operation: ir.Perform, reader: anytype, scratch: std.mem.Allocator) Error!void {
        const payload = try read(reader, operation.payload);
        if (operation.capability == null) {
            const captured = try self.captureContinuation(current, control, frame, operation.next);
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
        var found: ?ir.Clause = null;
        for (definition.clauses) |clause| if (clause.effect == operation.effect) {
            found = clause;
            break;
        };
        const clause = found orelse return error.InvalidEffect;
        if (clause.strategy == .tail) {
            const captured = try self.captureContinuation(current, control, frame, operation.next);
            return self.enterTailClause(scratch, handler, clause.function, payload, captured);
        }
        const use_site = try self.collectArguments(scratch, reader, operation.use_site_capabilities);
        const multi = self.program.schemas[@intCast(clause.resumption)].internal.resumption.use == .multi;
        const args = try scratch.alloc(g.Value, handler.state.len + operation.bodies.len + 2);
        @memcpy(args[0..handler.state.len], handler.state);
        args[handler.state.len] = payload;
        for (operation.bodies, 0..) |slot, index| args[handler.state.len + 1 + index] = try read(reader, slot);
        const captured = try self.captureContinuation(current, control, frame, operation.next);
        const capture: g.Capture = .{
            .schema = clause.resumption,
            .capture = captured,
            .delimiter = selected,
            .evidence = control.evidence,
            .use_site_capabilities = use_site,
        };
        const token = try self.store.add(if (multi) .{ .multi_template = capture } else .{ .one_shot = capture });
        if (self.statistics) |statistics| {
            if (multi) statistics.multi_templates +|= 1 else statistics.one_shot_captures +|= 1;
        }
        args[args.len - 1] = .{ .schema = clause.resumption, .body = if (multi) .{ .reference = token } else .{ .owned = .{ .node = token } } };
        const parent = attachment.return_to;
        attachment.return_to = null;
        attachment.phase = .suspended;
        try self.store.replace(selected, .{ .attachment = attachment });
        try self.enter(clause.function, args, parent, handler.evidence, handler.region);
    }

    fn enterTailClause(
        self: *Session,
        scratch: std.mem.Allocator,
        handler: @FieldType(g.Node, "handler"),
        function: p.Id,
        payload: g.Value,
        captured: g.NodeRef,
    ) Error!void {
        const args = try scratch.alloc(g.Value, handler.state.len + 1);
        @memcpy(args[0..handler.state.len], handler.state);
        args[handler.state.len] = payload;
        // Total copyable code needs no resumption object. The ordinary parent
        // retains the active delimiter, including cancellation/cleanup custody.
        try self.enter(function, args, captured, handler.evidence, handler.region);
        if (self.statistics) |statistics| statistics.direct_clauses +|= 1;
    }

    pub fn takeCapture(self: *Session, value: g.Value) Error!g.Capture {
        const reference = valueRef(value);
        const record = try self.store.get(reference);
        if (record == .multi_template) {
            const branch = try @import("clone.zig").instantiate(self.allocator, &self.store, record.multi_template, &self.frames);
            if (self.statistics) |statistics| statistics.branch_activations +|= 1;
            return branch;
        }
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
