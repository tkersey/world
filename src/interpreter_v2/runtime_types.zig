// Copyright (c) 2026 World contributors. MIT license.
//! Error and observation vocabulary shared by the current execution machinery.
const data = @import("boundary_data");

pub const Error = data.program_image.Error || data.state_admission.Error ||
    data.invocation.Error || data.scalar.Error || error{UnsupportedTransition};

/// Work counters are observations, never serialized state or execution limits.
pub const Statistics = struct {
    transitions: u64 = 0,
    direct_clauses: u64 = 0,
    one_shot_captures: u64 = 0,
    multi_templates: u64 = 0,
    branch_activations: u64 = 0,
    storage: @import("store.zig").Statistics = .{},
    snapshot: data.graph_order.Statistics = .{},
};
