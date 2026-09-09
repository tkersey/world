const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const source = b.option([]const u8, "boundary-v2-source", "Override the pinned Boundary 2 source") orelse pinned: {
        const dependency = b.lazyDependency("boundary_v2", .{
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
    const world = b.addModule("world", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    }) });
    const run_native_tests = b.addRunArtifact(tests);
    b.step("check-v2-native", "Check the World-owned v2 native interpreter")
        .dependOn(&run_native_tests.step);
    const economy = b.step("check-v2-economy", "Check sharing, captures, traversal and portable economy workloads");
    economy.dependOn(&run_native_tests.step);
    const codecs = b.addSystemCommand(&.{ "node", "--test" });
    codecs.addFileArg(b.path("test/v2/codec.test.mjs"));
    codecs.addFileArg(b.path("test/v2/cli.test.mjs"));
    codecs.addFileArg(b.path("test/v2/wasm.test.mjs"));
    codecs.addFileArg(b.path("test/v2/assets.test.mjs"));
    codecs.has_side_effects = true;
    b.step("check-v2-codecs", "Check first-order external value contracts").dependOn(&codecs.step);
    // Source agreement is an explicitly requested, separate conformance build.
    // The production build graph never constructs Boundary's authoring module.
    const source_tests = b.addSystemCommand(&.{ "zig", "build", "--build-file" });
    source_tests.addFileArg(b.path("test/v2/build_source.zig"));
    source_tests.addArg(b.fmt("-Dworld-source={s}", .{b.pathFromRoot(".")}));
    source_tests.addArg(b.fmt("-Dboundary-v2-source={s}", .{source}));
    source_tests.addArgs(&.{ "-Doptimize=ReleaseSafe", "--cache-dir", b.pathFromRoot(".cache/v2/source-local"), "--global-cache-dir", b.pathFromRoot(".cache/v2/source-global") });
    source_tests.has_side_effects = true;
    const source_step = b.step("check-v2-source", "Check source agreement in a separate compiler-dependent test build");
    source_step.dependOn(&source_tests.step);
    const fixture_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    });
    const fixture_step = b.step("emit-v2-test-fixtures", "Emit handwritten target fixtures");
    var emitted_fixtures: [11]std.Build.LazyPath = undefined;
    for ([_][]const u8{ "suspended", "loop", "deep", "choice", "local-regions", "shared-regions", "shallow", "reentrant", "cleanup", "bounded", "compact" }, 0..) |name, index| {
        const fixture = b.addExecutable(.{ .name = b.fmt("emit-v2-{s}", .{name}), .root_module = b.createModule(.{
            .root_source_file = b.path("test/v2/emit_fixture.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "boundary_data_v2", .module = data }, .{ .name = "world_test_fixtures", .module = fixture_module } },
        }) });
        const fixture_options = b.addOptions();
        fixture_options.addOption(usize, "fixture_index", index);
        fixture.root_module.addOptions("fixture_options", fixture_options);
        emitted_fixtures[index] = b.addRunArtifact(fixture).captureStdOut(.{});
        fixture_step.dependOn(&b.addInstallFileWithDir(emitted_fixtures[index], .prefix, b.fmt("{s}.bpi2", .{name})).step);
    }
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const wasm_data = b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ source, "src/v2/data/root.zig" }) },
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_world = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "boundary_data_v2", .module = wasm_data }},
    });
    const options = b.addOptions();
    options.addOption(usize, "input_capacity", b.option(usize, "v2-input-capacity", "Initial input reservation in bytes") orelse 65536);
    options.addOption(usize, "working_capacity", b.option(usize, "v2-working-capacity", "Initial working reservation in bytes") orelse 1048576);
    options.addOption(usize, "output_capacity", b.option(usize, "v2-output-capacity", "Initial output reservation in bytes") orelse 65536);
    const kernel_module = b.createModule(.{
        .root_source_file = b.path("src/kernel_v2/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{ .{ .name = "world", .module = wasm_world }, .{ .name = "boundary_data_v2", .module = wasm_data } },
    });
    kernel_module.addOptions("kernel_options", options);
    const kernel = b.addExecutable(.{ .name = "world-process-kernel-v2", .root_module = kernel_module });
    kernel.entry = .disabled;
    kernel.rdynamic = true;
    kernel.export_memory = true;
    kernel.stack_size = 65536;
    kernel.max_memory = b.option(u64, "v2-maximum-memory", "Maximum operational memory in bytes, a whole number of pages") orelse 256 << 20;
    const install = b.addInstallFileWithDir(kernel.getEmittedBin(), .prefix, "world-process-kernel-v2.wasm");
    b.step("build-v2-kernel", "Build the isolated development World v2 kernel").dependOn(&install.step);
    const wasm_test = b.addSystemCommand(&.{"node"});
    wasm_test.addFileArg(b.path("test/v2/transfer.mjs"));
    wasm_test.addFileArg(kernel.getEmittedBin());
    for (emitted_fixtures) |fixture| wasm_test.addFileArg(fixture);
    const native_records = b.addExecutable(.{ .name = "v2-native-records", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/native_records.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "boundary_data_v2", .module = data }, .{ .name = "world", .module = world } },
    }) });
    const probe = b.addExecutable(.{ .name = "v2-economy-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("test/v2/economy_probe.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{ .{ .name = "boundary_data_v2", .module = data }, .{ .name = "world", .module = world } },
    }) });
    b.step("build-v2-economy-probe", "Build the native allocation-demand observer").dependOn(&b.addInstallArtifact(probe, .{}).step);
    const phases = b.addExecutable(.{ .name = "v2-economy-phases", .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/economy_phases.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    }) });
    b.step("build-v2-economy-phases", "Build the isolated production-transition profiler").dependOn(&b.addInstallArtifact(phases, .{}).step);
    const rejections = b.addExecutable(.{ .name = "v2-emit-rejections", .root_module = b.createModule(.{
        .root_source_file = b.path("src/interpreter_v2/emit_rejections.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "boundary_data_v2", .module = data }},
    }) });
    b.step("build-v2-rejections", "Build the standalone malformed-State fixture producer").dependOn(&b.addInstallArtifact(rejections, .{}).step);
    const lifting = b.step("check-v2-bpi1", "Compare pure BPI1 lifting against the frozen public v1 kernel");
    if (b.option([]const u8, "legacy-v1-kernel", "Exact frozen public Boundary 1.8.2 kernel bytes")) |legacy_kernel| {
        const lifter = b.option([]const u8, "bpi1-lift", "Exact separately built Boundary bpi1-lift executable") orelse std.process.fatal("provide -Dbpi1-lift=/absolute/executable", .{});
        if (!std.Io.Dir.path.isAbsolute(legacy_kernel) or !std.Io.Dir.path.isAbsolute(lifter)) std.process.fatal("legacy kernel and lifter paths must be absolute", .{});
        const comparison = b.addSystemCommand(&.{"node"});
        comparison.addFileArg(b.path("test/v2/bpi1_agreement.mjs"));
        comparison.addFileArg(kernel.getEmittedBin());
        comparison.addFileArg(native_records.getEmittedBin());
        comparison.addArg(legacy_kernel);
        comparison.addArg(lifter);
        comparison.addArg(b.pathJoin(&.{ source, "test/v2/legacy" }));
        comparison.addArg(b.pathFromRoot("test/v2/wasmtime"));
        comparison.setEnvironmentVariable("UV_CACHE_DIR", b.pathFromRoot(".cache/v2/uv"));
        comparison.setEnvironmentVariable("UV_PROJECT_ENVIRONMENT", b.pathFromRoot(".cache/v2/wasmtime-environment"));
        comparison.has_side_effects = true;
        lifting.dependOn(&comparison.step);
    } else lifting.dependOn(&b.addFail("provide -Dlegacy-v1-kernel and -Dbpi1-lift for legacy comparison").step);
    wasm_test.addFileArg(native_records.getEmittedBin());
    wasm_test.has_side_effects = true; // The embedding imports ordinary JS modules.
    b.step("check-v2-wasm", "Execute transfers and recurrent programs in fresh WASM instances").dependOn(&wasm_test.step);
    const wasmtime_test = b.addSystemCommand(&.{"node"});
    wasmtime_test.addFileArg(b.path("test/v2/transfer.mjs"));
    wasmtime_test.addFileArg(kernel.getEmittedBin());
    for (emitted_fixtures) |fixture| wasmtime_test.addFileArg(fixture);
    wasmtime_test.addFileArg(native_records.getEmittedBin());
    wasmtime_test.addArg(b.pathFromRoot("test/v2/wasmtime"));
    wasmtime_test.setEnvironmentVariable("UV_CACHE_DIR", b.pathFromRoot(".cache/v2/uv"));
    wasmtime_test.setEnvironmentVariable("UV_PROJECT_ENVIRONMENT", b.pathFromRoot(".cache/v2/wasmtime-environment"));
    wasmtime_test.has_side_effects = true;
    const wasmtime_step = b.step("check-v2-wasmtime", "Check an independently implemented Wasmtime embedding and transfers");
    wasmtime_step.dependOn(&wasmtime_test.step);
    const source_wasm = b.step("check-v2-source-wasm", "Compare separately emitted source fixtures with native and WASM execution");
    const capacity_step = b.step("check-v2-capacity", "Check every guest arena and sufficient unchanged-input retries");
    if (b.option([]const u8, "boundary-v2-fixtures", "Exact directory of separately emitted Boundary source fixtures")) |fixtures| {
        if (!std.Io.Dir.path.isAbsolute(fixtures)) std.process.fatal("Boundary fixtures path must be absolute", .{});
        const capacity = b.addSystemCommand(&.{"node"});
        capacity.addFileArg(b.path("test/v2/capacity.mjs"));
        capacity.addArg(source);
        capacity.addArg(fixtures);
        capacity.addFileArg(kernel.getEmittedBin());
        capacity.addArg(b.pathFromRoot(".cache/v2/capacity"));
        capacity.has_side_effects = true;
        capacity_step.dependOn(&capacity.step);
        const check_economy = b.addSystemCommand(&.{"node"});
        check_economy.addFileArg(b.path("test/v2/economy_portability.mjs"));
        check_economy.addFileArg(kernel.getEmittedBin());
        check_economy.addFileArg(native_records.getEmittedBin());
        check_economy.addArg(fixtures);
        check_economy.addArg(b.pathFromRoot("test/v2/wasmtime"));
        check_economy.setEnvironmentVariable("UV_CACHE_DIR", b.pathFromRoot(".cache/v2/uv"));
        check_economy.setEnvironmentVariable("UV_PROJECT_ENVIRONMENT", b.pathFromRoot(".cache/v2/wasmtime-environment"));
        check_economy.has_side_effects = true;
        economy.dependOn(&check_economy.step);
        const compare_source = b.addSystemCommand(&.{"node"});
        compare_source.addFileArg(b.path("test/v2/source_transfer.mjs"));
        compare_source.addFileArg(kernel.getEmittedBin());
        compare_source.addFileArg(native_records.getEmittedBin());
        compare_source.addArg(fixtures);
        compare_source.addArg(b.pathJoin(&.{ source, "test/v2/source_oracle.mjs" }));
        compare_source.has_side_effects = true;
        source_wasm.dependOn(&compare_source.step);
        const independent_source = b.addSystemCommand(&.{"node"});
        independent_source.addFileArg(b.path("test/v2/source_transfer.mjs"));
        independent_source.addFileArg(kernel.getEmittedBin());
        independent_source.addFileArg(native_records.getEmittedBin());
        independent_source.addArg(fixtures);
        independent_source.addArg(b.pathJoin(&.{ source, "test/v2/source_oracle.mjs" }));
        independent_source.addArg(b.pathFromRoot("test/v2/wasmtime"));
        independent_source.setEnvironmentVariable("UV_CACHE_DIR", b.pathFromRoot(".cache/v2/uv"));
        independent_source.setEnvironmentVariable("UV_PROJECT_ENVIRONMENT", b.pathFromRoot(".cache/v2/wasmtime-environment"));
        independent_source.has_side_effects = true;
        wasmtime_step.dependOn(&independent_source.step);
    } else {
        const missing = b.addFail("provide -Dboundary-v2-fixtures=/absolute/emitted/fixtures");
        source_wasm.dependOn(&missing.step);
        wasmtime_step.dependOn(&missing.step);
        economy.dependOn(&missing.step);
        capacity_step.dependOn(&missing.step);
    }
    const portability = b.step("check-v2-portability", "Check exact native, JavaScript and Wasmtime records and fresh transfers");
    portability.dependOn(wasmtime_step);
    portability.dependOn(&codecs.step);
    const aggregate = b.step("check-v2", "Check native semantics, source agreement, portability, lifting and economy");
    aggregate.dependOn(&run_native_tests.step);
    aggregate.dependOn(source_step);
    aggregate.dependOn(portability);
    aggregate.dependOn(lifting);
    aggregate.dependOn(economy);
    aggregate.dependOn(capacity_step);
    const ownership = b.addSystemCommand(&.{"node"});
    ownership.addFileArg(b.path("test/v2/ownership.mjs"));
    ownership.addArg(source);
    ownership.addArg(b.pathFromRoot(".cache/v2/ownership"));
    ownership.has_side_effects = true;
    b.step("check-v2-ownership", "Build compiler-only, data-only and runtime-only physical installations").dependOn(&ownership.step);
    aggregate.dependOn(&ownership.step);
    const external = b.addSystemCommand(&.{"node"});
    external.addFileArg(b.path("test/v2/external.mjs"));
    external.addArg(source);
    external.addFileArg(kernel.getEmittedBin());
    external.addFileArg(native_records.getEmittedBin());
    external.addArg(b.pathFromRoot(".cache/v2/external"));
    external.has_side_effects = true;
    b.step("check-v2-external", "Run an externally authored handler under the previously frozen kernel").dependOn(&external.step);
    aggregate.dependOn(&external.step);
    const release_step = b.step("emit-world-v2-release", "Emit deterministic runtime and conformance assets without publishing");
    if (b.option([]const u8, "boundary-v2-release", "Exact separately emitted Boundary release asset directory")) |assets| {
        if (!std.Io.Dir.path.isAbsolute(assets)) std.process.fatal("Boundary release path must be absolute", .{});
        const release = b.addSystemCommand(&.{"node"});
        release.addFileArg(b.path("scripts/v2/release.mjs"));
        release.addFileArg(kernel.getEmittedBin());
        release.addFileArg(native_records.getEmittedBin());
        release.addFileArg(rejections.getEmittedBin());
        release.addArg(source);
        release.addArg(assets);
        release.addArg(b.pathFromRoot("test/v2/wasmtime"));
        release.addArg(b.getInstallPath(.prefix, "release"));
        release.setEnvironmentVariable("UV_CACHE_DIR", b.pathFromRoot(".cache/v2/uv"));
        release.setEnvironmentVariable("UV_PROJECT_ENVIRONMENT", b.pathFromRoot(".cache/v2/wasmtime-environment"));
        release.has_side_effects = true;
        release_step.dependOn(&release.step);
    } else release_step.dependOn(&b.addFail("provide -Dboundary-v2-release=/absolute/emitted/release").step);
}
