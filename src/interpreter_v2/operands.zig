// Copyright (c) 2026 World contributors. MIT license.
//! One operand access boundary for temporary call arrays and stable activations.
const std = @import("std");
const data = @import("boundary_data_v2");
const Error = @import("process.zig").Error;

pub fn read(storage: anytype, id: data.program.Id) Error!data.graph.Value {
    const slot = std.math.cast(usize, id) orelse return error.InvalidState;
    const info = @typeInfo(@TypeOf(storage));
    const array = info == .array or (info == .pointer and
        (info.pointer.size == .slice or @typeInfo(info.pointer.child) == .array));
    if (comptime array) {
        if (slot >= storage.len) return error.InvalidState;
        return storage[slot];
    }
    return storage.at(slot) catch |err| switch (err) {
        error.InvalidHandle, error.InvalidSlot, error.UninitializedSlot => error.InvalidState,
    };
}
