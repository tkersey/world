const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const source = b.option([]const u8, "boundary-source", "Override the pinned Boundary source") orelse pinned: {
        const dependency = b.lazyDependency("boundary", .{
            .target = target,
            .optimize = optimize,
            .@"data-only" = true,
        }) orelse return;
        break :pinned dependency.path(".").getPath(b);
    };
    if (!std.Io.Dir.path.isAbsolute(source)) std.process.fatal("Boundary source path must be absolute", .{});
    const data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ source, "src/v2/data/root.zig" }) },
        .target = target,
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
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    const run_native_tests = b.addRunArtifact(tests);
    b.step("check-storage", "Check current private storage and allocation contracts")
        .dependOn(&run_native_tests.step);
    const activation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/activation_slots_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data", .module = data }},
    }) });
    b.step("check-activation-storage", "Check stable activation storage and failure atomicity")
        .dependOn(&b.addRunArtifact(activation_tests).step);
    const stable_source = b.addSystemCommand(&.{ "zig", "build", "--build-file" });
    stable_source.addFileArg(b.path("test/v2/build_source.zig"));
    stable_source.addArg(b.fmt("-Dworld-source={s}", .{b.pathFromRoot(".")}));
    stable_source.addArg(b.fmt("-Dboundary-source={s}", .{source}));
    stable_source.addArgs(&.{ "-Doptimize=ReleaseSafe", "--summary", "all", "--cache-dir", b.pathFromRoot(".cache/stable-source-local"), "--global-cache-dir", b.pathFromRoot(".cache/activation-global") });
    stable_source.has_side_effects = true;
    b.step("check-native", "Check current source semantics, sessions and restore")
        .dependOn(&stable_source.step);
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const wasm_data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ source, "src/v2/data/root.zig" }) },
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const current_runtime = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/stable_session.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "boundary_data", .module = wasm_data }},
    });
    const current_options = b.addOptions();
    current_options.addOption(usize, "input_capacity", b.option(usize, "input-capacity", "Initial current input budget") orelse 65536);
    current_options.addOption(usize, "working_capacity", b.option(usize, "working-capacity", "Initial current working budget and backing") orelse 1048576);
    current_options.addOption(usize, "output_capacity", b.option(usize, "output-capacity", "Initial current output budget") orelse 65536);
    const current_module = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{ .{ .name = "runtime", .module = current_runtime }, .{ .name = "boundary_data", .module = wasm_data } },
    });
    current_module.addOptions("kernel_options", current_options);
    const current_kernel = b.addExecutable(.{ .name = "world-kernel", .root_module = current_module });
    current_kernel.entry = .disabled;
    current_kernel.rdynamic = true;
    current_kernel.export_memory = true;
    current_kernel.stack_size = 65536;
    current_kernel.max_memory = b.option(u64, "maximum-memory", "Current wasm32 memory maximum in whole pages") orelse 256 << 20;
    b.step("build-kernel", "Build the generic ABI 3 kernel")
        .dependOn(&b.addInstallFileWithDir(current_kernel.getEmittedBin(), .prefix, "world-kernel.wasm").step);
    const runtime_package = b.step("build-runtime", "Build the standalone current JavaScript/kernel package");
    runtime_package.dependOn(&b.addInstallFileWithDir(current_kernel.getEmittedBin(), .prefix, "runtime/world-kernel.wasm").step);
    for ([_][]const u8{
        "LICENSE",                      "README.md",                  "package.json",                 "bin/world.mjs",               "docs/kernel-abi.md",
        "src/embedding/index.mjs",      "src/embedding/kernel.mjs",   "src/embedding/codec.mjs",      "src/embedding/values.mjs",    "src/embedding/wasm.mjs",
        "src/embedding/wire.mjs",       "src/embedding/errors.mjs",   "src/node/file-input.mjs",      "src/node/runtime-bundle.mjs", "src/node/runtime-command.mjs",
        "src/node/runtime-prepare.mjs", "src/node/runtime-smoke.mjs", "src/node/runtime-acquire.mjs", "docs/runtime-bundles.md",     "src/node/runtime-output.mjs",
    }) |path| runtime_package.dependOn(&b.addInstallFileWithDir(b.path(path), .prefix, b.fmt("runtime/{s}", .{path})).step);
    const current_fixtures = b.addSystemCommand(&.{ "zig", "build", "--build-file" });
    current_fixtures.addFileArg(b.path("test/v2/build_source.zig"));
    current_fixtures.addArg(b.fmt("-Dworld-source={s}", .{b.pathFromRoot(".")}));
    current_fixtures.addArg(b.fmt("-Dboundary-source={s}", .{source}));
    current_fixtures.addArgs(&.{ "-Dcurrent-fixtures=true", "-Doptimize=ReleaseSafe", "--prefix", b.getInstallPath(.prefix, "current"), "--cache-dir", b.pathFromRoot(".cache/current-fixture-local"), "--global-cache-dir", b.pathFromRoot(".cache/activation-global") });
    current_fixtures.has_side_effects = true;
    const current_package_check = b.addSystemCommand(&.{"node"});
    current_package_check.addFileArg(b.path("test/current/package.mjs"));
    current_package_check.addArg(b.getInstallPath(.prefix, "runtime"));
    current_package_check.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    current_package_check.step.dependOn(runtime_package);
    current_package_check.step.dependOn(&current_fixtures.step);
    current_package_check.has_side_effects = true;
    b.step("check-package", "Run the current API and CLI from an extracted package")
        .dependOn(&current_package_check.step);
    const current_check = b.addSystemCommand(&.{"node"});
    current_check.addFileArg(b.path("test/current/kernel.mjs"));
    current_check.addFileArg(current_kernel.getEmittedBin());
    current_check.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    current_check.step.dependOn(&current_fixtures.step);
    current_check.has_side_effects = true;
    b.step("check-kernel", "Check ABI 3 and current native/Node transfer").dependOn(&current_check.step);
    const source_examples = b.addSystemCommand(&.{ "zig", "build", "emit-examples", "--build-file" });
    source_examples.addArg(b.pathJoin(&.{ source, "build.zig" }));
    source_examples.addArgs(&.{ "-Doptimize=ReleaseSafe", "--prefix", b.getInstallPath(.prefix, "source"), "--cache-dir", b.pathFromRoot(".cache/source-examples"), "--global-cache-dir", b.pathFromRoot(".cache/activation-global") });
    const source_agreement = b.addSystemCommand(&.{"node"});
    source_agreement.addFileArg(b.path("test/current/source_agreement.mjs"));
    source_agreement.addFileArg(current_kernel.getEmittedBin());
    source_agreement.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    source_agreement.addArg(b.getInstallPath(.prefix, "source"));
    source_agreement.addArg(b.pathJoin(&.{ source, "test/v2/source_oracle.mjs" }));
    source_agreement.step.dependOn(&source_examples.step);
    source_agreement.step.dependOn(&current_fixtures.step);
    source_agreement.has_side_effects = true;
    b.step("check-source", "Compare current native/WASM execution with independent source semantics")
        .dependOn(&source_agreement.step);
    const capacity = b.addSystemCommand(&.{"node"});
    capacity.addFileArg(b.path("test/current/capacity.mjs"));
    capacity.addFileArg(current_kernel.getEmittedBin());
    capacity.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    capacity.addArg(source);
    capacity.step.dependOn(&current_fixtures.step);
    capacity.has_side_effects = true;
    b.step("check-capacity", "Check all current arena limits, physical memory and unchanged retries")
        .dependOn(&capacity.step);
    const current_transfer = b.addSystemCommand(&.{"node"});
    current_transfer.addFileArg(b.path("test/current/transfer.mjs"));
    current_transfer.addFileArg(current_kernel.getEmittedBin());
    current_transfer.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    current_transfer.step.dependOn(&current_fixtures.step);
    current_transfer.has_side_effects = true;
    b.step("check-transfer", "Check current Node/Wasmtime/native State transfer").dependOn(&current_transfer.step);
    const current_browser = b.addSystemCommand(&.{"node"});
    current_browser.addFileArg(b.path("test/current/browser.mjs"));
    current_browser.addFileArg(current_kernel.getEmittedBin());
    current_browser.addArg(b.getInstallPath(.prefix, "current/bin/current-fixtures"));
    current_browser.step.dependOn(&current_fixtures.step);
    current_browser.has_side_effects = true;
    b.step("check-browser", "Check real browser Worker/native transfer on Chromium and Firefox").dependOn(&current_browser.step);
    const current_codecs = b.addSystemCommand(&.{ "node", "--test" });
    current_codecs.addFileArg(b.path("test/current/codec.test.mjs"));
    current_codecs.addFileArg(b.path("test/current/byte_contracts.test.mjs"));
    current_codecs.addFileArg(b.path("test/current/wasm.test.mjs"));
    current_codecs.addFileArg(b.path("test/current/file_input.test.mjs"));
    current_codecs.addFileArg(b.path("test/current/runtime_bundle.test.mjs"));
    current_codecs.has_side_effects = true;
    b.step("check-codecs", "Check current browser-neutral byte ownership and value contracts").dependOn(&current_codecs.step);
    const activation_wasm_store = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/activation_slots.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary_data", .module = wasm_data }},
    });
    const activation_wasm = b.addExecutable(.{ .name = "activation-storage-test", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/activation_storage_wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "activation_slots", .module = activation_wasm_store }},
    }) });
    activation_wasm.entry = .disabled;
    activation_wasm.rdynamic = true;
    activation_wasm.export_memory = true;
    activation_wasm.stack_size = 65536;
    activation_wasm.max_memory = 4 << 20;
    const activation_wasm_run = b.addSystemCommand(&.{"node"});
    activation_wasm_run.addFileArg(b.path("test/v2/activation_storage_wasm.mjs"));
    activation_wasm_run.addFileArg(activation_wasm.getEmittedBin());
    b.step("check-activation-storage-wasm", "Check storage on import-free unshared wasm32")
        .dependOn(&activation_wasm_run.step);
    const check = b.step("check", "Check current native, host, portable and package contracts");
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
