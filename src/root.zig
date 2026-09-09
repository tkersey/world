// Copyright (c) 2026 World contributors. MIT license.
pub const package_version = "5.0.0";
pub const process_v2 = @import("interpreter_v2/process.zig");

test {
    _ = process_v2;
}
