const std = @import("std");
const world = @import("world");

const expected_exports = world.Appliance.Abi.universal_required_exports;
const max_types = 256;
const max_functions = 4096;
const wasm_page_size = 64 * 1024;

const Signature = struct {
    params: u32 = 0,
    results: u32 = 0,
    all_i32: bool = true,

    fn matches(self: @This(), params: u32, results: u32) bool {
        return self.params == params and self.results == results and self.all_i32;
    }
};

const Inspection = struct {
    abi_version: u32 = 0,
    import_count: usize = 0,
    export_count: usize = 0,
    required_mask: u32 = 0,
    signature_mask: u32 = 0,
    memory_export_present: bool = false,
    memory_count: u32 = 0,
    memory_initial_pages: u32 = 0,
    memory_max_pages: ?u32 = null,

    fn passed(self: @This()) bool {
        const all_required = (@as(u32, 1) << expected_exports.len) - 1;
        return self.abi_version == world.Appliance.Abi.universal_version and
            self.import_count == 0 and
            self.memory_count == 1 and
            self.memory_export_present and
            self.memory_initial_pages > 0 and
            self.memory_initial_pages <= 1024 and
            self.memory_max_pages != null and
            self.memory_max_pages.? == self.memory_initial_pages and
            (self.required_mask & all_required) == all_required and
            (self.signature_mask & all_required) == all_required;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const allocator = std.heap.page_allocator;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const artifact_path = args.next() orelse return error.MissingWasmArtifactPath;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, artifact_path, allocator, .limited(world.world_max_decoded_byte_field_len));
    defer allocator.free(bytes);

    const inspection = try inspect(bytes);
    try stdout.print("universal_appliance_wasm={s}\n", .{artifact_path});
    try stdout.print("abi_version={d}\n", .{inspection.abi_version});
    try stdout.print("export_count={d}\n", .{inspection.export_count});
    try stdout.print("required_exports={d}\n", .{expected_exports.len});
    try stdout.print("required_mask={x}\n", .{inspection.required_mask});
    try stdout.print("signature_mask={x}\n", .{inspection.signature_mask});
    try stdout.print("imports={d}\n", .{inspection.import_count});
    try stdout.print("memory_pages={d}\n", .{inspection.memory_initial_pages});
    try stdout.print("memory_bytes={d}\n", .{@as(u64, inspection.memory_initial_pages) * wasm_page_size});
    try stdout.flush();
    if (!inspection.passed()) return error.UniversalWasmInspectionFailed;
}

fn inspect(bytes: []const u8) !Inspection {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..4], "\x00asm")) return error.InvalidFrameEncoding;
    if (std.mem.readInt(u32, bytes[4..8], .little) != 1) return error.InvalidFrameEncoding;

    var cursor: usize = 8;
    var type_sigs: [max_types]Signature = undefined;
    var type_count: usize = 0;
    var function_type_indices: [max_functions]u32 = undefined;
    var function_count: usize = 0;
    var function_import_count: usize = 0;
    var inspection: Inspection = .{};
    var abi_function_index: ?u32 = null;
    var seen_sections: u16 = 0;
    var last_order: u8 = 0;

    while (cursor < bytes.len) {
        const section_id = try readU8(bytes, &cursor);
        const section_len = try readU32(bytes, &cursor);
        if (section_len > bytes.len - cursor) return error.InvalidFrameEncoding;
        const section = bytes[cursor .. cursor + section_len];
        try checkSectionOrder(section_id, &seen_sections, &last_order);
        switch (section_id) {
            0 => {},
            1 => type_count = try inspectTypes(section, &type_sigs),
            2 => function_import_count = try inspectImports(section, &inspection),
            3 => function_count = try inspectFunctions(section, &function_type_indices, type_count),
            5 => try inspectMemory(section, &inspection),
            7 => try inspectExports(section, type_sigs[0..type_count], function_type_indices[0..function_count], function_import_count, &inspection, &abi_function_index),
            10 => try inspectCode(section, function_count, function_import_count, abi_function_index, &inspection),
            4, 6, 9, 11, 12 => {},
            else => return error.InvalidFrameEncoding,
        }
        cursor += section_len;
    }
    if (cursor != bytes.len) return error.InvalidFrameEncoding;
    return inspection;
}

fn inspectTypes(section: []const u8, out: *[max_types]Signature) !usize {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    if (count > out.len) return error.CapacityExceeded;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        if (try readU8(section, &cursor) != 0x60) return error.InvalidFrameEncoding;
        const params = try readU32(section, &cursor);
        var all_i32 = true;
        var param_index: u32 = 0;
        while (param_index < params) : (param_index += 1) {
            if (try readU8(section, &cursor) != 0x7f) all_i32 = false;
        }
        const results = try readU32(section, &cursor);
        var result_index: u32 = 0;
        while (result_index < results) : (result_index += 1) {
            if (try readU8(section, &cursor) != 0x7f) all_i32 = false;
        }
        out[index] = .{ .params = params, .results = results, .all_i32 = all_i32 };
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return @intCast(count);
}

fn inspectImports(section: []const u8, inspection: *Inspection) !usize {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    var function_imports: usize = 0;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        _ = try readName(section, &cursor);
        _ = try readName(section, &cursor);
        const kind = try readU8(section, &cursor);
        switch (kind) {
            0 => {
                _ = try readU32(section, &cursor);
                function_imports += 1;
            },
            1 => {
                _ = try readU8(section, &cursor);
                try skipLimits(section, &cursor);
            },
            2 => try skipLimits(section, &cursor),
            3 => {
                _ = try readU8(section, &cursor);
                _ = try readU8(section, &cursor);
            },
            else => return error.InvalidFrameEncoding,
        }
        inspection.import_count += 1;
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return function_imports;
}

fn inspectFunctions(section: []const u8, out: *[max_functions]u32, type_count: usize) !usize {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    if (count > out.len) return error.CapacityExceeded;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const type_index = try readU32(section, &cursor);
        if (type_index >= type_count) return error.InvalidFrameEncoding;
        out[index] = type_index;
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
    return @intCast(count);
}

fn inspectMemory(section: []const u8, inspection: *Inspection) !void {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    inspection.memory_count = count;
    if (count != 1) return error.InvalidFrameEncoding;
    const min = try readU32(section, &cursor);
    const has_max = try readLimitsTail(section, &cursor, min, inspection);
    if (!has_max) return error.InvalidFrameEncoding;
    if (cursor != section.len) return error.InvalidFrameEncoding;
}

fn inspectExports(
    section: []const u8,
    type_sigs: []const Signature,
    function_type_indices: []const u32,
    function_import_count: usize,
    inspection: *Inspection,
    abi_function_index: *?u32,
) !void {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const name = try readName(section, &cursor);
        const kind = try readU8(section, &cursor);
        const export_index = try readU32(section, &cursor);
        inspection.export_count += 1;
        if (kind == 2 and std.mem.eql(u8, name, "memory")) inspection.memory_export_present = true;
        if (kind != 0) continue;
        for (expected_exports, 0..) |expected, expected_index| {
            if (!std.mem.eql(u8, name, expected)) continue;
            inspection.required_mask |= @as(u32, 1) << @intCast(expected_index);
            if (signatureMatches(export_index, function_import_count, type_sigs, function_type_indices, expectedParamCount(expected_index), expectedResultCount(expected_index))) {
                inspection.signature_mask |= @as(u32, 1) << @intCast(expected_index);
            }
            if (expected_index == 0) abi_function_index.* = export_index;
        }
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
}

fn inspectCode(section: []const u8, function_count: usize, function_import_count: usize, abi_function_index: ?u32, inspection: *Inspection) !void {
    var cursor: usize = 0;
    const count = try readU32(section, &cursor);
    if (count != function_count) return error.InvalidFrameEncoding;
    const abi_defined_index: ?u32 = if (abi_function_index) |idx| blk: {
        if (@as(usize, idx) < function_import_count) return error.InvalidFrameEncoding;
        const defined_index = @as(usize, idx) - function_import_count;
        if (defined_index > std.math.maxInt(u32)) return error.InvalidFrameEncoding;
        break :blk @intCast(defined_index);
    } else null;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const body_len = try readU32(section, &cursor);
        if (body_len > section.len - cursor) return error.InvalidFrameEncoding;
        const body = section[cursor .. cursor + body_len];
        if (abi_defined_index != null and index == abi_defined_index.?) {
            inspection.abi_version = try readConstantU32Body(body);
        }
        cursor += body_len;
    }
    if (cursor != section.len) return error.InvalidFrameEncoding;
}

fn signatureMatches(function_index: u32, function_import_count: usize, type_sigs: []const Signature, function_type_indices: []const u32, params: u32, results: u32) bool {
    if (function_index < function_import_count) return false;
    const defined_index = function_index - @as(u32, @intCast(function_import_count));
    if (defined_index >= function_type_indices.len) return false;
    const type_index = function_type_indices[@intCast(defined_index)];
    if (type_index >= type_sigs.len) return false;
    return type_sigs[@intCast(type_index)].matches(params, results);
}

fn expectedParamCount(index: usize) u32 {
    return switch (index) {
        2, 3 => 2,
        6 => 2,
        7 => 2,
        9 => 2,
        11 => 2,
        13 => 1,
        14 => 2,
        else => 0,
    };
}

fn expectedResultCount(index: usize) u32 {
    return switch (index) {
        14 => 0,
        else => 1,
    };
}

fn readConstantU32Body(body: []const u8) !u32 {
    var cursor: usize = 0;
    const local_group_count = try readU32(body, &cursor);
    var group_index: u32 = 0;
    while (group_index < local_group_count) : (group_index += 1) {
        _ = try readU32(body, &cursor);
        _ = try readU8(body, &cursor);
    }
    if (try readU8(body, &cursor) != 0x41) return error.InvalidFrameEncoding;
    const value = try readU32(body, &cursor);
    if (try readU8(body, &cursor) != 0x0b) return error.InvalidFrameEncoding;
    if (cursor != body.len) return error.InvalidFrameEncoding;
    return value;
}

fn checkSectionOrder(section_id: u8, seen: *u16, last_order: *u8) !void {
    if (section_id == 0) return;
    if (section_id > 12) return error.InvalidFrameEncoding;
    const mask = @as(u16, 1) << @intCast(section_id);
    if ((seen.* & mask) != 0) return error.InvalidFrameEncoding;
    seen.* |= mask;
    const order: u8 = if (section_id == 12) 9 else section_id;
    if (order < last_order.*) return error.InvalidFrameEncoding;
    last_order.* = order;
}

fn skipLimits(bytes: []const u8, cursor: *usize) !void {
    const flags = try readU32(bytes, cursor);
    _ = try readU32(bytes, cursor);
    if ((flags & 1) != 0) _ = try readU32(bytes, cursor);
}

fn readLimitsTail(bytes: []const u8, cursor: *usize, min: u32, inspection: *Inspection) !bool {
    const flags = min;
    if ((flags & ~@as(u32, 1)) != 0) return error.InvalidFrameEncoding;
    const initial = try readU32(bytes, cursor);
    inspection.memory_initial_pages = initial;
    if ((flags & 1) == 0) return false;
    inspection.memory_max_pages = try readU32(bytes, cursor);
    return true;
}

fn readName(bytes: []const u8, cursor: *usize) ![]const u8 {
    const len = try readU32(bytes, cursor);
    if (len > bytes.len - cursor.*) return error.InvalidFrameEncoding;
    const result = bytes[cursor.* .. cursor.* + len];
    cursor.* += len;
    return result;
}

fn readU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* >= bytes.len) return error.InvalidFrameEncoding;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}

fn readU32(bytes: []const u8, cursor: *usize) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;
    while (true) {
        const byte = try readU8(bytes, cursor);
        result |= @as(u32, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) return result;
        if (shift >= 28) return error.InvalidFrameEncoding;
        shift += 7;
    }
}
