// Copyright (c) 2026 World contributors. MIT license.
//! Cleanup runs ordinary authored computations on the same portable control graph.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const g = data.graph;
const Machine = @import("machine.zig").Machine;
const process = @import("process.zig");
const Error = process.Error;
const Outcome = process.Outcome;
const Reason = @FieldType(g.Exit, "reason");

fn position(machine: *Machine, cursor: ?g.NodeRef, values: []const g.Value) Error!void {
    machine.roots.current = try machine.store.add(.{ .unwind = .{ .cursor = cursor, .values = values } });
    machine.roots.pending = null;
    machine.roots.evidence = null;
    machine.status = .unwinding;
}

pub fn begin(machine: *Machine, reason: Reason, cursor: ?g.NodeRef, stop: ?g.NodeRef, values: []const g.Value) Error!void {
    machine.roots.exit = try machine.store.add(.{ .exit = .{ .reason = reason, .stop = stop, .outer = machine.roots.exit } });
    try position(machine, cursor, values);
}

fn outermost(machine: *Machine) Error!g.NodeRef {
    var ref = machine.roots.exit orelse return error.InvalidState;
    while ((try machine.store.get(ref)).exit.outer) |outer| ref = outer;
    return ref;
}

fn rememberFailure(machine: *Machine, value: g.Value) Error!void {
    const ref = try outermost(machine);
    var exit = (try machine.store.get(ref)).exit;
    const failures = try machine.allocator.alloc(g.Value, exit.cleanup_failures.len + 1);
    defer machine.allocator.free(failures);
    @memcpy(failures[0..exit.cleanup_failures.len], exit.cleanup_failures);
    failures[failures.len - 1] = value;
    exit.cleanup_failures = failures;
    const discarded = try discardedNormal(machine, exit);
    defer machine.allocator.free(discarded);
    if (exit.reason == .normal or exit.reason == .abandoned) {
        exit.reason = .{ .failure = value };
        exit.stop = null;
        exit.discarded = discarded;
    }
    try machine.store.replace(ref, .{ .exit = exit });
}

fn discardedNormal(machine: *Machine, exit: g.Exit) Error![]g.Value {
    const extra: usize = if (exit.reason == .normal and exit.reason.normal.body == .owned) 1 else 0;
    const values = try machine.allocator.alloc(g.Value, exit.discarded.len + extra);
    @memcpy(values[0..exit.discarded.len], exit.discarded);
    if (extra != 0) values[values.len - 1] = exit.reason.normal;
    return values;
}

pub fn fail(machine: *Machine, value: g.Value, control: g.Control, slots: []const g.Value, executed: []const p.Instruction) Error!void {
    var scratch = std.heap.ArenaAllocator.init(machine.allocator);
    defer scratch.deinit();
    const used = try scratch.allocator().alloc(bool, slots.len);
    @memset(used, false);
    for (executed) |instruction| {
        if (!instruction.opcode.borrowsOperands()) for (instruction.operands) |operand| {
            used[@intCast(operand)] = true;
        };
    }
    var values: std.ArrayList(g.Value) = .empty;
    for (slots, used) |slot, consumed| if (!consumed and slot.body == .owned) try values.append(scratch.allocator(), slot);
    if (machine.roots.exit != null) try rememberFailure(machine, value);
    try begin(machine, .{ .failure = value }, control.parent, null, values.items);
}

pub fn cancel(machine: *Machine, reason: data.protocol.Reason) Error!void {
    if (reason == .text and !std.unicode.utf8ValidateSlice(reason.text)) return error.InvalidUtf8;
    if (machine.roots.exit == null) {
        const cursor = if (machine.roots.pending) |pending| (try machine.store.get(pending)).pending.continuation else machine.roots.current;
        try begin(machine, .cancellation, cursor, null, &.{});
    }
    const ref = try outermost(machine);
    var exit = (try machine.store.get(ref)).exit;
    if (exit.cancellation != null) return;
    exit.cancellation = reason;
    const discarded = try discardedNormal(machine, exit);
    defer machine.allocator.free(discarded);
    if (exit.reason == .normal or exit.reason == .abandoned) {
        exit.reason = .cancellation;
        exit.stop = null;
        exit.discarded = discarded;
    }
    try machine.store.replace(ref, .{ .exit = exit });
}

pub fn protect(machine: *Machine, protection: anytype, slots: []const g.Value, control: g.Control) Error!void {
    const resource: ?g.Value = if (protection.resource) |slot| slots[@intCast(slot)] else null;
    const obligation = try machine.store.add(.{ .obligation = .{ .source_block = control.block, .cleanup = slots[@intCast(protection.cleanup)], .resource = resource, .status = .pending } });
    const after = try machine.continuation(control.block, slots, control);
    const loan: ?g.NodeRef = if (protection.loan_region) |descriptor| try machine.store.add(.{ .region = .{ .descriptor = descriptor, .outer = control.region, .obligations = &.{} } }) else null;
    const frame = try machine.store.add(.{ .protection = .{ .source_block = control.block, .obligation = .{ .node = obligation }, .return_to = after, .evidence = control.evidence, .region = control.region, .loan = loan } });
    const extra: usize = @intFromBool(resource != null);
    const arguments = try machine.allocator.alloc(g.Value, protection.arguments.len + extra);
    defer machine.allocator.free(arguments);
    if (resource) |owned| {
        const schema = machine.program.schemas[@intCast(slots[@intCast(protection.body)].schema)].internal.computation.parameters[0];
        const borrowed = try machine.store.add(.{ .borrow = .{ .schema = schema, .resource = owned.body.owned.node, .region = loan.? } });
        arguments[0] = .{ .schema = schema, .body = .{ .reference = borrowed } };
    }
    for (arguments[extra..], protection.arguments) |*argument, slot| argument.* = slots[@intCast(slot)];
    try machine.applyComputation(slots[@intCast(protection.body)], arguments, frame, control.evidence, loan orelse control.region);
}

pub fn dispose(machine: *Machine, disposal: anytype, slots: []const g.Value, control: g.Control) Error!void {
    const token = try machine.takeCapture(slots[@intCast(disposal.owned)]);
    const after = try machine.continuation(control.block, slots, control);
    try machine.activate(token, after);
    try begin(machine, .abandoned, token.capture, after, &.{});
}

fn information(machine: *Machine, values: *@import("values.zig").Values, schema: p.Id, exit: g.Exit) Error!g.Value {
    const types = try data.cleanup_contract.types(machine.program, schema);
    const unit: g.Value = .{ .schema = types.unit, .body = .{ .scalar = [_]u8{0} ** 8 } };
    var reason_value = unit;
    if (exit.cancellation) |reason| {
        var measure: data.wire.Writer = .{};
        const bytes = if (reason == .text) reason.text else reason.bytes;
        try measure.bytes(bytes);
        const encoded = try values.allocator.alloc(u8, measure.position);
        var writer: data.wire.Writer = .{ .output = encoded };
        try writer.bytes(bytes);
        const payload = try machine.store.literal(machine.program, .{ .schema = if (reason == .text) types.text else types.bytes, .bytes = encoded });
        reason_value = try values.aggregate(types.reason, .{ .tag = @intFromEnum(std.meta.activeTag(reason)), .fields = &.{payload} });
    }
    const primary = try values.aggregate(types.primary, .{ .tag = @intFromEnum(std.meta.activeTag(exit.reason)), .fields = &.{switch (exit.reason) {
        .normal, .abandoned => unit,
        .failure => |failure| failure,
        .cancellation => reason_value,
    }} });
    const optional = try values.aggregate(types.optional_reason, .{ .tag = if (exit.cancellation != null) 1 else 0, .fields = &.{reason_value} });
    const failures = try values.aggregate(types.failures, .{ .fields = exit.cleanup_failures });
    return values.aggregate(schema, .{ .fields = &.{ primary, optional, failures } });
}

pub fn returned(machine: *Machine, reference: g.NodeRef) Error!void {
    const frame = (try machine.store.get(reference)).cleanup_return;
    var obligation = (try machine.store.get(frame.obligation.node)).obligation;
    obligation.status = .completed;
    try machine.store.replace(frame.obligation.node, .{ .obligation = obligation });
    machine.roots.exit = frame.exit;
    try position(machine, frame.parent, &.{});
}

fn unlinkSuspendedExit(machine: *Machine, retired: g.NodeRef) Error!void {
    const prior = (try machine.store.get(retired)).exit;
    var cursor = machine.roots.exit orelse return error.InvalidState;
    if (cursor.id == retired.id) return;
    for (0..machine.store.nodes.items.len) |_| {
        var record = (try machine.store.get(cursor)).exit;
        const outer = record.outer orelse return error.InvalidState;
        if (outer.id == retired.id) {
            record.outer = prior.outer;
            try machine.store.replace(cursor, .{ .exit = record });
            if (prior.reason == .failure or prior.reason == .cancellation or prior.cancellation != null) {
                const active = machine.roots.exit.?;
                var current = (try machine.store.get(active)).exit;
                var failures: std.ArrayList(g.Value) = .empty;
                defer failures.deinit(machine.allocator);
                try failures.appendSlice(machine.allocator, prior.cleanup_failures);
                try failures.appendSlice(machine.allocator, current.cleanup_failures);
                current.reason = if (prior.reason == .failure) prior.reason else .cancellation;
                current.cancellation = prior.cancellation orelse current.cancellation;
                current.cleanup_failures = failures.items;
                current.stop = null;
                try machine.store.replace(active, .{ .exit = current });
            }
            return;
        }
        cursor = outer;
    }
    return error.InvalidState;
}

pub fn returnedDisposal(machine: *Machine, frame: anytype, value: g.Value) Error!void {
    var remaining: std.ArrayList(g.Value) = .empty;
    defer remaining.deinit(machine.allocator);
    if (value.body == .owned) try remaining.append(machine.allocator, value);
    try remaining.appendSlice(machine.allocator, frame.values);
    try position(machine, frame.parent, remaining.items);
}

fn crossedCleanupReturn(machine: *Machine, frame: anytype, exit: g.Exit) Error!void {
    var obligation = (try machine.store.get(frame.obligation.node)).obligation;
    if (exit.reason == .abandoned) {
        const suspended = (try machine.store.get(frame.exit)).exit;
        const discarded = try discardedNormal(machine, suspended);
        defer machine.allocator.free(discarded);
        try unlinkSuspendedExit(machine, frame.exit);
        obligation.status = .completed;
        try machine.store.replace(frame.obligation.node, .{ .obligation = obligation });
        try position(machine, frame.parent, discarded);
        return;
    }
    if (exit.reason != .failure) return error.InvalidState;
    obligation.status = .{ .failed = exit.reason.failure };
    try machine.store.replace(frame.obligation.node, .{ .obligation = obligation });
    var parent_exit = (try machine.store.get(frame.exit)).exit;
    if (parent_exit.reason == .normal or parent_exit.reason == .abandoned) {
        const discarded = try discardedNormal(machine, parent_exit);
        defer machine.allocator.free(discarded);
        parent_exit.reason = exit.reason;
        parent_exit.stop = null;
        parent_exit.discarded = discarded;
        try machine.store.replace(frame.exit, .{ .exit = parent_exit });
    }
    machine.roots.exit = frame.exit;
    try position(machine, frame.parent, &.{});
}

pub fn step(machine: *Machine) Error!?Outcome {
    var scratch = std.heap.ArenaAllocator.init(machine.allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    const current = (try machine.store.get(machine.roots.current.?)).unwind;
    const exit_ref = machine.roots.exit orelse return error.InvalidState;
    const exit = (try machine.store.get(exit_ref)).exit;
    const root_ref = try outermost(machine);
    var root_exit = (try machine.store.get(root_ref)).exit;
    if (root_exit.discarded.len != 0) {
        const values = try temporary.alloc(g.Value, root_exit.discarded.len + current.values.len);
        @memcpy(values[0..root_exit.discarded.len], root_exit.discarded);
        @memcpy(values[root_exit.discarded.len..], current.values);
        root_exit.discarded = &.{};
        try machine.store.replace(root_ref, .{ .exit = root_exit });
        try position(machine, current.cursor, values);
        return null;
    }
    if (current.values.len != 0) {
        const value = current.values[0];
        const rest = current.values[1..];
        const record = try machine.store.get(value.body.owned.node);
        switch (record) {
            .one_shot => {
                const token = try machine.takeCapture(value);
                const after = try machine.store.add(.{ .disposal_return = .{ .schema = value.schema, .parent = current.cursor, .values = rest } });
                try machine.activate(token, after);
                try position(machine, token.capture, &.{});
            },
            .aggregate, .computation, .package => {
                const fields = if (record == .aggregate) record.aggregate.fields else if (record == .package) (&record.package.continuation)[0..1] else (try machine.store.get(record.computation.environment)).environment.values;
                var values: std.ArrayList(g.Value) = .empty;
                for (fields) |field| if (field.body == .owned) try values.append(temporary, field);
                try values.appendSlice(temporary, rest);
                try position(machine, current.cursor, values.items);
            },
            .resource => try position(machine, current.cursor, rest), // No implicit effectful finalizer.
            else => return error.UnsupportedTransition,
        }
        return null;
    }
    if (std.meta.eql(current.cursor, exit.stop) and (exit.reason == .normal or exit.reason == .abandoned)) {
        machine.roots.exit = exit.outer;
        machine.status = .active;
        if (exit.reason == .normal) return machine.returnTo(current.cursor, exit.reason.normal);
        try machine.resumeContinuation(current.cursor orelse return error.InvalidState, .{ .schema = 0, .body = .{ .scalar = [_]u8{0} ** 8 } });
        return null;
    }
    const cursor = current.cursor orelse return try terminal(machine, root_exit);
    switch (try machine.store.get(cursor)) {
        .control => |control| {
            var values: std.ArrayList(g.Value) = .empty;
            for (control.arguments) |value| if (value.body == .owned) try values.append(temporary, value);
            try position(machine, control.parent, values.items);
        },
        .continuation => |saved| {
            var values: std.ArrayList(g.Value) = .empty;
            for (saved.arguments) |argument| if (argument) |value| {
                if (value.body == .owned) try values.append(temporary, value);
            };
            try position(machine, saved.parent, values.items);
        },
        .attachment => |attachment| try position(machine, attachment.return_to, &.{}),
        .region_scope => |scope| try position(machine, scope.return_to, &.{}),
        .injection => |injected| try position(machine, injected.continuation, &.{}),
        .disposal_return => |disposal| try position(machine, disposal.parent, disposal.values),
        .protection => |protection| {
            var obligation = (try machine.store.get(protection.obligation.node)).obligation;
            if (obligation.status != .pending) return error.InvalidState;
            const cleanup = obligation.cleanup orelse return error.InvalidState;
            const resource = obligation.resource;
            const frame = try machine.store.add(.{ .cleanup_return = .{ .obligation = protection.obligation, .parent = protection.return_to, .exit = exit_ref } });
            obligation.cleanup = null;
            obligation.resource = null;
            obligation.status = .{ .running = frame };
            try machine.store.replace(protection.obligation.node, .{ .obligation = obligation });
            var values: @import("values.zig").Values = .{ .allocator = temporary, .program = machine.program, .store = &machine.store };
            const info = try information(machine, &values, machine.program.schemas[@intCast(cleanup.schema)].internal.computation.parameters[0], root_exit);
            machine.status = .active;
            const arguments = if (resource) |owned| &[_]g.Value{ info, owned } else &[_]g.Value{info};
            try machine.applyComputation(cleanup, arguments, frame, protection.evidence, protection.region);
        },
        .cleanup_return => |frame| try crossedCleanupReturn(machine, frame, exit),
        else => return error.InvalidState,
    }
    return null;
}

fn terminal(machine: *Machine, exit: g.Exit) Error!Outcome {
    var arena = std.heap.ArenaAllocator.init(machine.allocator);
    errdefer arena.deinit();
    const output = arena.allocator();
    var measure: data.wire.Writer = .{};
    try measure.natural(exit.cleanup_failures.len);
    for (exit.cleanup_failures) |*value| try measure.bytes(try machine.bytes(value));
    const failures = try output.alloc(u8, measure.position);
    var writer: data.wire.Writer = .{ .output = failures };
    try writer.natural(exit.cleanup_failures.len);
    for (exit.cleanup_failures) |*value| try writer.bytes(try machine.bytes(value));
    const cancellation: ?data.protocol.Reason = if (exit.cancellation) |reason| switch (reason) {
        .text => |bytes| .{ .text = try output.dupe(u8, bytes) },
        .bytes => |bytes| .{ .bytes = try output.dupe(u8, bytes) },
    } else null;
    const record: data.protocol.Outcome = switch (exit.reason) {
        .failure => |value| .{ .failed = .{ .value = try output.dupe(u8, try machine.bytes(&value)), .cleanup_failures = failures, .cancellation = cancellation } },
        .cancellation => .{ .cancelled = .{ .reason = cancellation orelse return error.InvalidState, .cleanup_failures = failures } },
        else => return error.InvalidState,
    };
    return .{ .arena = arena, .record = record };
}
