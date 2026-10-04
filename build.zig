const std = @import("std");
const Profile = struct {
    zig: []const u8,
    target: []const u8,
    hostMode: []const u8,
    kernelMode: []const u8,
    wasmBackend: enum { llvm },
    wasmLinker: enum { lld },
    cpu: []const u8,
    features: []const []const u8,
    stackBytes: u64,
    maximumMemoryBytes: u64,
    defaults: struct { input: usize, working: usize, output: usize },
    boundary: struct { commit: []const u8, package: []const u8, url: []const u8, inventorySha256: []const u8 },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const profile = std.json.parseFromSliceLeaky(Profile, b.allocator, @embedFile("src/node/runtime-profile.json"), .{}) catch @panic("invalid runtime profile");
    const package = @import("build.zig.zon");
    if (!std.mem.eql(u8, package.dependencies.boundary.url, profile.boundary.url) or
        !std.mem.eql(u8, package.dependencies.boundary.hash, profile.boundary.package))
        @panic("runtime profile and Boundary package selection differ");
    const kernel_mode = std.meta.stringToEnum(std.lang.Optimize, profile.kernelMode) orelse @panic("invalid kernel mode");
    const source = b.option(std.Build.LazyPath, "boundary-source", "Override the pinned Boundary source") orelse pinned: {
        const dependency = b.lazyDependency("boundary", .{
            .target = target,
            .optimize = optimize,
            .@"data-only" = true,
        }) orelse return;
        break :pinned dependency.path("");
    };
    if (source == .cwd_relative and !std.Io.Dir.path.isAbsolute(source.cwd_relative))
        @panic("Boundary source path must be absolute");
    const data = b.createModule(.{
        .root_source_file = source.path(b, "src/data/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const host_data = b.createModule(.{
        .root_source_file = source.path(b, "src/data/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    _ = b.addModule("world", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = host_data }},
    }) });
    const run_native_tests = b.addRunArtifact(tests);
    b.step("check-storage", "Check current private storage and allocation contracts")
        .dependOn(&run_native_tests.step);
    const activation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/activation_slots_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = host_data }},
    }) });
    b.step("check-activation-storage", "Check stable activation storage and failure atomicity")
        .dependOn(&b.addRunArtifact(activation_tests).step);
    const stable_source = b.addRunFile(.zig_exe);
    stable_source.addArg("build");
    stable_source.addDirectoryArg2(.zig_lib, .{ .prefix = "--zig-lib=", .make_absolute = true });
    stable_source.addArgs(&.{"--build-file"});
    stable_source.addFileArg2(b.path("test/v2/build_source.zig"), .{});
    stable_source.addDirectoryArg2(b.path(""), .{ .prefix = "-Dworld-source=", .make_absolute = true });
    stable_source.addDirectoryArg2(source, .{ .prefix = "-Dboundary-source=", .make_absolute = true });
    stable_source.addArgs(&.{ b.fmt("-Doptimize={s}", .{profile.hostMode}), "--summary", "all", "--cache-dir" });
    stable_source.addDirectoryArg2(std.Build.LazyPath.cache_root.path(b, "stable-source"), .{ .make_absolute = true });
    stable_source.has_side_effects = true;
    b.step("check-native", "Check current source semantics, sessions and restore")
        .dependOn(&stable_source.step);
    const wasm_target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = profile.target, .cpu_features = profile.cpu }) catch @panic("invalid kernel target"));
    const wasm_data = b.createModule(.{
        .root_source_file = source.path(b, "src/data/root.zig"),
        .target = wasm_target,
        .optimize = kernel_mode,
    });
    const current_runtime = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/stable_session.zig"),
        .target = wasm_target,
        .optimize = kernel_mode,
        .imports = &.{.{ .name = "boundary_data", .module = wasm_data }},
    });
    const current_options = b.addOptions();
    current_options.addOption(usize, "input_capacity", b.option(usize, "input-capacity", "Initial current input budget") orelse profile.defaults.input);
    current_options.addOption(usize, "working_capacity", b.option(usize, "working-capacity", "Initial current working budget and backing") orelse profile.defaults.working);
    current_options.addOption(usize, "output_capacity", b.option(usize, "output-capacity", "Initial current output budget") orelse profile.defaults.output);
    const current_module = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = wasm_target,
        .optimize = kernel_mode,
        .imports = &.{ .{ .name = "runtime", .module = current_runtime }, .{ .name = "boundary_data", .module = wasm_data } },
    });
    current_module.addOptions("kernel_options", current_options);
    const current_kernel = b.addExecutable(.{ .name = "world-kernel", .root_module = current_module });
    current_kernel.entry = .disabled;
    current_kernel.use_llvm = profile.wasmBackend == .llvm;
    current_kernel.use_lld = profile.wasmLinker == .lld;
    // Retain exactly the ABI functions; -rdynamic additionally exports
    // linker internals such as __stack_pointer in Zig 0.17.
    current_module.export_symbol_names = &.{
        "world_abi_version",      "world_initialize",      "world_set_limits",
        "world_input_ptr",        "world_input_capacity",  "world_prepare_input",
        "world_output_ptr",       "world_output_len",      "world_error_ptr",
        "world_error_len",        "world_prepared_handle", "world_session_handle",
        "world_working_live",     "world_working_peak",    "world_prepare",
        "world_release_prepared", "world_invoke",          "world_start",
        "world_restore",          "world_drive",           "world_checkpoint",
        "world_close",
    };
    current_kernel.export_memory = true;
    current_kernel.stack_size = profile.stackBytes;
    current_kernel.max_memory = b.option(u64, "maximum-memory", "Current wasm32 memory maximum in whole pages") orelse profile.maximumMemoryBytes;
    var features: std.ArrayList([]const u8) = .empty;
    for (wasm_target.result.cpu.arch.allFeaturesList(), 0..) |feature, index| {
        if (wasm_target.result.cpu.features.isEnabled(@intCast(index)))
            features.append(b.allocator, feature.name) catch @panic("out of memory");
    }
    if (features.items.len != profile.features.len) @panic("resolved kernel features differ from the qualified profile");
    for (features.items, profile.features) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) @panic("resolved kernel features differ from the qualified profile");
    }
    const build_profile = b.addWriteFiles().add("kernel-profile.json", std.json.Stringify.valueAlloc(b.allocator, .{
        .target = profile.target,
        .mode = kernel_mode,
        .backend = profile.wasmBackend,
        .linker = profile.wasmLinker,
        .cpu = wasm_target.result.cpu.model.name,
        .features = features.items,
        .stackBytes = current_kernel.stack_size.?,
        .maximumMemoryBytes = current_kernel.max_memory.?,
    }, .{}) catch @panic("out of memory"));
    const installed_profile = b.addInstallFileWithDir(build_profile, .prefix, "kernel-profile.json");
    b.step("build-kernel", "Build the generic ABI 3 kernel")
        .dependOn(&b.addInstallFileWithDir(current_kernel.getEmittedBin(), .prefix, "world-kernel.wasm").step);
    const runtime_package = b.step("build-runtime", "Build the standalone current JavaScript/kernel package");
    runtime_package.dependOn(&installed_profile.step);
    runtime_package.dependOn(&b.addInstallFileWithDir(current_kernel.getEmittedBin(), .prefix, "runtime/world-kernel.wasm").step);
    for ([_][]const u8{
        "LICENSE",                       "README.md",                  "package.json",                 "bin/world.mjs",               "docs/kernel-abi.md",
        "src/embedding/index.mjs",       "src/embedding/kernel.mjs",   "src/embedding/codec.mjs",      "src/embedding/values.mjs",    "src/embedding/wasm.mjs",
        "src/embedding/wire.mjs",        "src/embedding/errors.mjs",   "src/node/file-input.mjs",      "src/node/runtime-bundle.mjs", "src/node/runtime-command.mjs",
        "src/node/runtime-prepare.mjs",  "src/node/runtime-smoke.mjs", "src/node/runtime-acquire.mjs", "docs/runtime-bundles.md",     "src/node/runtime-output.mjs",
        "src/node/runtime-profile.json", "src/node/toolchain.mjs",
    }) |path| runtime_package.dependOn(&b.addInstallFileWithDir(b.path(path), .prefix, b.fmt("runtime/{s}", .{path})).step);
    const current_fixtures = b.addRunFile(.zig_exe);
    current_fixtures.addArg("build");
    current_fixtures.addDirectoryArg2(.zig_lib, .{ .prefix = "--zig-lib=", .make_absolute = true });
    current_fixtures.addArgs(&.{"--build-file"});
    current_fixtures.addFileArg2(b.path("test/v2/build_source.zig"), .{});
    current_fixtures.addDirectoryArg2(b.path(""), .{ .prefix = "-Dworld-source=", .make_absolute = true });
    current_fixtures.addDirectoryArg2(source, .{ .prefix = "-Dboundary-source=", .make_absolute = true });
    current_fixtures.addArgs(&.{ "-Dcurrent-fixtures=true", b.fmt("-Doptimize={s}", .{profile.hostMode}), "--prefix" });
    current_fixtures.addDirectoryArg2(b.graph.path(.install_prefix, "current"), .{ .make_absolute = true });
    current_fixtures.addArg("--cache-dir");
    current_fixtures.addDirectoryArg2(std.Build.LazyPath.cache_root.path(b, "current-fixture"), .{ .make_absolute = true });
    current_fixtures.has_side_effects = true;
    const current_package_check = b.addSystemCommand(&.{"node"});
    current_package_check.addFileArg2(b.path("test/current/package.mjs"), .{});
    current_package_check.addDirectoryArg2(b.graph.path(.install_prefix, "runtime"), .{ .make_absolute = true });
    current_package_check.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    current_package_check.step.dependOn(runtime_package);
    current_package_check.step.dependOn(&current_fixtures.step);
    current_package_check.has_side_effects = true;
    b.step("check-package", "Run the current API and CLI from an extracted package")
        .dependOn(&current_package_check.step);
    const current_check = b.addSystemCommand(&.{"node"});
    current_check.addFileArg2(b.path("test/current/kernel.mjs"), .{});
    current_check.addFileArg2(current_kernel.getEmittedBin(), .{});
    current_check.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    current_check.step.dependOn(&current_fixtures.step);
    current_check.has_side_effects = true;
    b.step("check-kernel", "Check ABI 3 and current native/Node transfer").dependOn(&current_check.step);
    const source_examples = b.addRunFile(.zig_exe);
    source_examples.addArg("build");
    source_examples.addDirectoryArg2(.zig_lib, .{ .prefix = "--zig-lib=", .make_absolute = true });
    source_examples.addArgs(&.{ "emit-examples", "--build-file" });
    source_examples.addFileArg2(source.path(b, "build.zig"), .{});
    source_examples.addArgs(&.{ b.fmt("-Doptimize={s}", .{profile.hostMode}), "--prefix" });
    source_examples.addDirectoryArg2(b.graph.path(.install_prefix, "source"), .{ .make_absolute = true });
    source_examples.addArg("--cache-dir");
    source_examples.addDirectoryArg2(std.Build.LazyPath.cache_root.path(b, "source-examples"), .{ .make_absolute = true });
    const source_agreement = b.addSystemCommand(&.{"node"});
    source_agreement.addFileArg2(b.path("test/current/source_agreement.mjs"), .{});
    source_agreement.addFileArg2(current_kernel.getEmittedBin(), .{});
    source_agreement.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    source_agreement.addDirectoryArg2(b.graph.path(.install_prefix, "source"), .{ .make_absolute = true });
    source_agreement.addFileArg2(source.path(b, "test/v2/source_oracle.mjs"), .{ .make_absolute = true });
    source_agreement.step.dependOn(&source_examples.step);
    source_agreement.step.dependOn(&current_fixtures.step);
    source_agreement.has_side_effects = true;
    b.step("check-source", "Compare current native/WASM execution with independent source semantics")
        .dependOn(&source_agreement.step);
    const capacity = b.addSystemCommand(&.{"node"});
    capacity.addFileArg2(b.path("test/current/capacity.mjs"), .{});
    capacity.addFileArg2(current_kernel.getEmittedBin(), .{});
    capacity.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    capacity.addDirectoryArg2(source, .{ .make_absolute = true });
    capacity.addFileArg2(.zig_exe, .{ .make_absolute = true });
    capacity.addDirectoryArg2(.zig_lib, .{ .make_absolute = true });
    capacity.step.dependOn(&current_fixtures.step);
    capacity.has_side_effects = true;
    b.step("check-capacity", "Check all current arena limits, physical memory and unchanged retries")
        .dependOn(&capacity.step);
    const current_transfer = b.addSystemCommand(&.{"node"});
    current_transfer.addFileArg2(b.path("test/current/transfer.mjs"), .{});
    current_transfer.addFileArg2(current_kernel.getEmittedBin(), .{});
    current_transfer.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    current_transfer.step.dependOn(&current_fixtures.step);
    current_transfer.has_side_effects = true;
    b.step("check-transfer", "Check current Node/Wasmtime/native State transfer").dependOn(&current_transfer.step);
    const current_browser = b.addSystemCommand(&.{"node"});
    current_browser.addFileArg2(b.path("test/current/browser.mjs"), .{});
    current_browser.addFileArg2(current_kernel.getEmittedBin(), .{});
    current_browser.addFileArg2(b.graph.path(.install_prefix, "current/bin/current-fixtures"), .{ .make_absolute = true });
    current_browser.step.dependOn(&current_fixtures.step);
    current_browser.has_side_effects = true;
    b.step("check-browser", "Check real browser Worker/native transfer on Chromium and Firefox").dependOn(&current_browser.step);
    const current_codecs = b.addSystemCommand(&.{ "node", "--test" });
    current_codecs.addFileArg2(b.path("test/current/codec.test.mjs"), .{});
    current_codecs.addFileArg2(b.path("test/current/byte_contracts.test.mjs"), .{});
    current_codecs.addFileArg2(b.path("test/current/wasm.test.mjs"), .{});
    current_codecs.addFileArg2(b.path("test/current/file_input.test.mjs"), .{});
    current_codecs.addFileArg2(b.path("test/current/runtime_bundle.test.mjs"), .{});
    current_codecs.has_side_effects = true;
    b.step("check-codecs", "Check current browser-neutral byte ownership and value contracts").dependOn(&current_codecs.step);
    const activation_wasm_store = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/activation_slots.zig"),
        .target = wasm_target,
        .optimize = .safe,
        .imports = &.{.{ .name = "boundary_data", .module = wasm_data }},
    });
    const activation_wasm = b.addExecutable(.{ .name = "activation-storage-test", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/activation_storage_wasm.zig"),
        .target = wasm_target,
        .optimize = .safe,
        .imports = &.{.{ .name = "activation_slots", .module = activation_wasm_store }},
    }) });
    activation_wasm.entry = .disabled;
    activation_wasm.rdynamic = true;
    activation_wasm.export_memory = true;
    activation_wasm.stack_size = 65536;
    activation_wasm.max_memory = 4 << 20;
    const activation_wasm_run = b.addSystemCommand(&.{"node"});
    activation_wasm_run.addFileArg2(b.path("test/v2/activation_storage_wasm.mjs"), .{});
    activation_wasm_run.addFileArg2(activation_wasm.getEmittedBin(), .{});
    b.step("check-activation-storage-wasm", "Check storage on import-free unshared wasm32")
        .dependOn(&activation_wasm_run.step);
    const check = b.step("check", "Check current native, host, portable and package contracts");
    const zig17 = b.step("check-zig17", "Check pointer-borrow diagnostics and qualified storage ownership");
    const borrow_probe = b.addExecutable(.{
        .name = "world-borrow-diagnostics",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/interpreter_v2/borrow_diagnostics.zig"),
            .target = b.graph.host,
            // Keep the named assertion frame in intentional-panic diagnostics.
            .optimize = .debug,
            .imports = &.{.{ .name = "boundary_data", .module = host_data }},
        }),
    });
    const borrow_check = b.addSystemCommand(&.{ "node", "test/current/borrow_diagnostics.mjs" });
    borrow_check.addArtifactArg2(borrow_probe, .{});
    borrow_check.has_side_effects = true;
    zig17.dependOn(&borrow_check.step);
    const package_ownership = b.addSystemCommand(&.{ "env", "-u", "NODE_TEST_CONTEXT", "node", "--test", "test/current/zig17.test.mjs" });
    package_ownership.has_side_effects = true;
    zig17.dependOn(&package_ownership.step);
    const build_selection = b.addSystemCommand(&.{ "node", "test/current/build_selection.mjs" });
    build_selection.addFileArg2(.zig_exe, .{ .make_absolute = true });
    build_selection.addDirectoryArg2(.zig_lib, .{ .make_absolute = true });
    build_selection.addDirectoryArg2(source, .{ .make_absolute = true });
    build_selection.has_side_effects = true;
    zig17.dependOn(&build_selection.step);
    check.dependOn(zig17);
    check.dependOn(&run_native_tests.step);
    check.dependOn(&stable_source.step);
    check.dependOn(&activation_wasm_run.step);
    check.dependOn(&current_check.step);
    check.dependOn(&source_agreement.step);
    check.dependOn(&capacity.step);
    check.dependOn(&current_transfer.step);
    check.dependOn(&current_browser.step);
    check.dependOn(&current_codecs.step);
    check.dependOn(&current_package_check.step);
    const economy = b.step("check-economy", "Check storage work bounds and current execution preservation");
    economy.dependOn(&run_native_tests.step);
    economy.dependOn(&stable_source.step);
}
