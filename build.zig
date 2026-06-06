const std = @import("std");

const TestArgs = struct {
    filters: []const []const u8,
    passthrough: []const []const u8,
};

fn parseTestArgs(b: *std.Build) TestArgs {
    const args = b.args orelse return .{ .filters = &.{}, .passthrough = &.{} };
    var filters: std.ArrayList([]const u8) = .empty;
    var passthrough: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--test-filter")) {
            index += 1;
            if (index >= args.len) std.process.fatal("missing --test-filter value", .{});
            filters.append(b.allocator, args[index]) catch @panic("oom");
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--test-filter=")) {
            filters.append(b.allocator, arg["--test-filter=".len..]) catch @panic("oom");
            continue;
        }
        passthrough.append(b.allocator, arg) catch @panic("oom");
    }
    return .{
        .filters = filters.toOwnedSlice(b.allocator) catch @panic("oom"),
        .passthrough = passthrough.toOwnedSlice(b.allocator) catch @panic("oom"),
    };
}

fn addRunArtifactWithArgs(
    b: *std.Build,
    artifact: *std.Build.Step.Compile,
    args: []const []const u8,
) *std.Build.Step.Run {
    const run = b.addRunArtifact(artifact);
    if (args.len != 0) run.addArgs(args);
    return run;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_args = parseTestArgs(b);

    const boundary_dep = b.dependency("boundary", .{
        .target = target,
        .optimize = optimize,
    });
    const boundary = boundary_dep.module("boundary");

    const world = b.addModule("world", .{
        .root_source_file = b.path("src/world.zig"),
        .target = target,
        .optimize = optimize,
    });
    world.addImport("boundary", boundary);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const wasm_guest_module = b.createModule(.{
        .root_source_file = b.path("examples/world_wasm_guest_one_port.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_guest = b.addExecutable(.{
        .name = "world_wasm_guest_one_port",
        .root_module = wasm_guest_module,
    });
    wasm_guest.entry = .disabled;
    wasm_guest.rdynamic = true;
    wasm_guest.export_memory = true;
    const install_wasm_guest = b.addInstallArtifact(wasm_guest, .{});
    const world_wasm_step = b.step("world-wasm", "Build World wasm guest artifacts.");
    world_wasm_step.dependOn(&install_wasm_guest.step);
    const check_world_wasm_step = b.step("check-world-wasm", "Build and inspect World wasm guest artifacts.");
    check_world_wasm_step.dependOn(&wasm_guest.step);

    const fixtures = b.createModule(.{
        .root_source_file = b.path("test/fixtures.zig"),
        .target = target,
        .optimize = optimize,
    });
    fixtures.addImport("world", world);
    fixtures.addImport("boundary", boundary);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/world_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "boundary", .module = boundary },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
        .filters = test_args.filters,
    });
    const wasm_guest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/world_wasm_guest_one_port.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
        .filters = test_args.filters,
    });
    const test_step = b.step("test", "Run world tests.");
    test_step.dependOn(&addRunArtifactWithArgs(b, wasm_guest_tests, test_args.passthrough).step);
    if (target.query.isNative()) {
        test_step.dependOn(&addRunArtifactWithArgs(b, tests, test_args.passthrough).step);
        b.default_step.dependOn(test_step);
    } else {
        test_step.dependOn(&tests.step);
        b.default_step.dependOn(&tests.step);
    }

    const forged_descriptor_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/compile_fail/forged_descriptor_metadata.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "world", .module = world },
                .{ .name = "world_fixtures", .module = fixtures },
            },
        }),
    });
    forged_descriptor_test.expect_errors = .{
        .contains = "World port descriptor metadata does not match target WorldPortTable",
    };
    const compile_fail_step = b.step("compile-fail", "Run compile-fail tests.");
    compile_fail_step.dependOn(&forged_descriptor_test.step);

    const check_step = b.step("check", "Run tests, compile-fail tests, examples, and lint.");
    check_step.dependOn(test_step);
    check_step.dependOn(compile_fail_step);

    const examples = [_]struct {
        name: []const u8,
        path: []const u8,
        step: []const u8,
        desc: []const u8,
        expected_stdout: []const u8,
    }{
        .{
            .name = "world-run-strict",
            .path = "examples/world_run_strict.zig",
            .step = "run-world-strict",
            .desc = "Run the strict zero-port World example.",
            .expected_stdout =
            \\world_surface_fingerprint=bf39bfbae5e3bb8d
            \\target_certificate_fingerprint=67c91a7de6b021f5
            \\final_result=1
            \\
            ,
        },
        .{
            .name = "world-run-ports",
            .path = "examples/world_run_ports.zig",
            .step = "run-world-ports",
            .desc = "Run the one-port World example.",
            .expected_stdout =
            \\world_surface_fingerprint=1c56147f9e4ab2ff
            \\world_port_id=0
            \\request_fingerprint=1a84e84d29103ea4
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-replay-ports",
            .path = "examples/world_replay_ports.zig",
            .step = "run-world-replay-ports",
            .desc = "Run the one-port replay World example.",
            .expected_stdout =
            \\recorded_interaction_count=1
            \\replayed_interaction_count=1
            \\replay_verified=true
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-agent-loop",
            .path = "examples/world_agent_loop.zig",
            .step = "run-world-agent-loop",
            .desc = "Run the agent-shaped World port example.",
            .expected_stdout =
            \\skeleton final=final=actuate skeleton complete events=6 tool_calls=1 responses=3
            \\fixture final=final=fixture updated events=10 tool_calls=2 responses=5
            \\fixture output=actuate updated the fixture
            \\replay fresh_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-frame-ports",
            .path = "examples/world_frame_ports.zig",
            .step = "run-world-frame-ports",
            .desc = "Run the frame-first one-port World example.",
            .expected_stdout =
            \\request_frame_fingerprint=a2e08a01b91af8f0
            \\response_frame_fingerprint=4cd51f91b59fafb3
            \\world_port_id=0
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-transcript-image-replay",
            .path = "examples/world_transcript_image_replay.zig",
            .step = "run-world-transcript-image-replay",
            .desc = "Run the transcript image replay World example.",
            .expected_stdout =
            \\transcript_image_fingerprint=64fea44e8213ec3
            \\replayed_response_count=1
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-byte-adapter",
            .path = "examples/world_byte_adapter.zig",
            .step = "run-world-byte-adapter",
            .desc = "Run the byte adapter frame World example.",
            .expected_stdout =
            \\request_frame_bytes=193
            \\response_frame_bytes=132
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-agent-timeline",
            .path = "examples/world_agent_timeline.zig",
            .step = "run-world-agent-timeline",
            .desc = "Run the agent timeline World example.",
            .expected_stdout =
            \\transcript_image_fingerprint=aa3dd05381fca5cb
            \\event_count=8
            \\tool_call_count=1
            \\replay_verified=true
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-agent-branch",
            .path = "examples/world_agent_branch.zig",
            .step = "run-world-agent-branch",
            .desc = "Run the agent branch World example.",
            .expected_stdout =
            \\checkpoint_fingerprint=41a07ca32c074d08
            \\baseline_transcript_fingerprint=aa3dd05381fca5cb
            \\branch_transcript_fingerprint=7cc91fbb223c4ca
            \\baseline_final_result=final=actuate skeleton complete
            \\branch_final_result=final=branch alternate
            \\
            ,
        },
        .{
            .name = "world-environment-preflight",
            .path = "examples/world_environment_preflight.zig",
            .step = "run-world-environment-preflight",
            .desc = "Run the World environment preflight example.",
            .expected_stdout =
            \\fresh_missing_accepted=false
            \\fresh_blocker=MissingBinding
            \\replay_without_handlers_accepted=true
            \\transcript_image_fingerprint=64fea44e8213ec3
            \\
            ,
        },
        .{
            .name = "world-handoff-parked",
            .path = "examples/world_handoff_parked.zig",
            .step = "run-world-handoff-parked",
            .desc = "Run the parked World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=703082b270df5742
            \\pending_request_fingerprint=a2e08a01b91af8f0
            \\environment_certificate_fingerprint=37227268d7e2489
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-handoff-replay",
            .path = "examples/world_handoff_replay.zig",
            .step = "run-world-handoff-replay",
            .desc = "Run the replay World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=d8ee6082faeb801c
            \\replayed_response_count=1
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-handoff-verify",
            .path = "examples/world_handoff_verify.zig",
            .step = "run-world-handoff-verify",
            .desc = "Run the verify World handoff example.",
            .expected_stdout =
            \\verification_accepted=true
            \\divergence_detected=true
            \\
            ,
        },
        .{
            .name = "world-agent-handoff",
            .path = "examples/world_agent_handoff.zig",
            .step = "run-world-agent-handoff",
            .desc = "Run the agent World handoff example.",
            .expected_stdout =
            \\run_image_fingerprint=f55a3fb93cf4962
            \\checkpoint_fingerprint=41a07ca32c074d08
            \\branch_id=1
            \\model_port_id=0
            \\tool_port_id=1
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-admission-reference",
            .path = "examples/world_admission_reference.zig",
            .step = "run-world-admission-reference",
            .desc = "Run the World admission target-reference example.",
            .expected_stdout =
            \\package_fingerprint=5a5e606018190afc
            \\target_match_fingerprint=c4108ddb5ef704d9
            \\admission_receipt_fingerprint=24b969b61b005487
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-admission-full-module-inspect",
            .path = "examples/world_admission_full_module_inspect.zig",
            .step = "run-world-admission-full-module-inspect",
            .desc = "Run the World admission full-module inspect example.",
            .expected_stdout =
            \\module_ref_fingerprint=88a2146555397dad
            \\import_count=1
            \\loaded_execution_supported=false
            \\admission_accepted=true
            \\
            ,
        },
        .{
            .name = "world-admission-parked-handoff",
            .path = "examples/world_admission_parked_handoff.zig",
            .step = "run-world-admission-parked-handoff",
            .desc = "Run the World admission parked handoff example.",
            .expected_stdout =
            \\package_fingerprint=91d0e487f35697a
            \\admission_receipt_fingerprint=2671236ba62154f9
            \\receiver_permit_fingerprint=b87664d5f288ef48
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-admission-replay-verify",
            .path = "examples/world_admission_replay_verify.zig",
            .step = "run-world-admission-replay-verify",
            .desc = "Run the World admission replay/verify example.",
            .expected_stdout =
            \\replay_admission_receipt=5e3dd80ce4473dff
            \\verify_admission_receipt=bdf86dea628f111c
            \\divergence_detected=true
            \\
            ,
        },
        .{
            .name = "world-admission-agent-transfer",
            .path = "examples/world_admission_agent_transfer.zig",
            .step = "run-world-admission-agent-transfer",
            .desc = "Run the World admission agent transfer example.",
            .expected_stdout =
            \\module_ref_fingerprint=8980705f83427fa6
            \\model_port_id=0
            \\tool_port_id=1
            \\admission_receipt=e0b215a2c9bfda0f
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-runspace-basic",
            .path = "examples/world_runspace_basic.zig",
            .step = "run-world-runspace-basic",
            .desc = "Run the basic World runspace example.",
            .expected_stdout =
            \\run_handle=367cb72b9a8188ae
            \\pending_port_id=0
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-runspace-multi",
            .path = "examples/world_runspace_multi.zig",
            .step = "run-world-runspace-multi",
            .desc = "Run the multi-run World runspace example.",
            .expected_stdout =
            \\first_run=367cb72b9a8188ae
            \\second_run=8d63b7a77a33b921
            \\pending_count=0
            \\completed_count=2
            \\
            ,
        },
        .{
            .name = "world-runspace-handoff",
            .path = "examples/world_runspace_handoff.zig",
            .step = "run-world-runspace-handoff",
            .desc = "Run the handoff World runspace example.",
            .expected_stdout =
            \\admission_receipt=19a5e9048c49e20f
            \\run_handle=cec1eb876ef00192
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-runspace-agent",
            .path = "examples/world_runspace_agent.zig",
            .step = "run-world-runspace-agent",
            .desc = "Run the agent-shaped World runspace example.",
            .expected_stdout =
            \\model_pending_count=2
            \\tool_pending_count=1
            \\event_count=18
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-runspace-supervised",
            .path = "examples/world_runspace_supervised.zig",
            .step = "run-world-runspace-supervised",
            .desc = "Run the supervised World runspace example.",
            .expected_stdout =
            \\run_permit=52999c92544b1487
            \\budget_exceeded=true
            \\event_fingerprint=d94d5587cfd19a6b
            \\
            ,
        },
        .{
            .name = "world-guest-one-port",
            .path = "examples/world_guest_one_port.zig",
            .step = "run-world-guest-one-port",
            .desc = "Run the World native guest one-port ABI example.",
            .expected_stdout =
            \\request_frame_fingerprint=a2e08a01b91af8f0
            \\response_frame_fingerprint=736978f58eeb5450
            \\result_fingerprint=3d881e9808dec3df
            \\
            ,
        },
        .{
            .name = "world-guest-conformance",
            .path = "examples/world_guest_conformance.zig",
            .step = "run-world-guest-conformance",
            .desc = "Run the World native guest conformance report example.",
            .expected_stdout =
            \\vector_fingerprint=665d5b3674bb9e2a
            \\report_fingerprint=4f0359d051363afb
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-guest-agent-conformance",
            .path = "examples/world_guest_agent_conformance.zig",
            .step = "run-world-guest-agent-conformance",
            .desc = "Run the World native guest agent conformance example.",
            .expected_stdout =
            \\model_pending_count=2
            \\tool_pending_count=1
            \\result_fingerprint=cf3a9be8873fdc38
            \\conformance=true
            \\
            ,
        },
        .{
            .name = "world-fabric-target-provider",
            .path = "examples/world_fabric_target_provider.zig",
            .step = "run-world-fabric-target-provider",
            .desc = "Run the World Fabric target provider example.",
            .expected_stdout =
            \\parent_run_handle=367cb72b9a8188ae
            \\provider_run_handle=a53ebdcc0976217b
            \\fabric_receipt_fingerprint=271db8a6e0670c1f
            \\final_result=7
            \\native_handler_calls=0
            \\
            ,
        },
        .{
            .name = "world-fabric-agent-tool",
            .path = "examples/world_fabric_agent_tool.zig",
            .step = "run-world-fabric-agent-tool",
            .desc = "Run the World Fabric agent tool example.",
            .expected_stdout =
            \\tool_port_id=1
            \\provider_target_ref=5fd6e98eae4c7db0
            \\fabric_invocation_count=1
            \\native_tool_calls=0
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-fabric-nested",
            .path = "examples/world_fabric_nested.zig",
            .step = "run-world-fabric-nested",
            .desc = "Run the World Fabric nested provider example.",
            .expected_stdout =
            \\fabric_depth=1
            \\parent_result=final=actuate skeleton complete
            \\provider_result=actuate
            \\
            ,
        },
        .{
            .name = "world-fabric-supervised",
            .path = "examples/world_fabric_supervised.zig",
            .step = "run-world-fabric-supervised",
            .desc = "Run the World Fabric supervised denial example.",
            .expected_stdout =
            \\fabric_invocation_count=1
            \\budget_exceeded=true
            \\run_receipt_fingerprint=93ec63716ec61af3
            \\
            ,
        },
        .{
            .name = "world-fabric-cycle-blocked",
            .path = "examples/world_fabric_cycle_blocked.zig",
            .step = "run-world-fabric-cycle-blocked",
            .desc = "Run the World Fabric cycle rejection example.",
            .expected_stdout =
            \\cycle_blocked=true
            \\report_fingerprint=6d79f4a5c08b55a8
            \\
            ,
        },
        .{
            .name = "world-supervised-budget",
            .path = "examples/world_supervised_budget.zig",
            .step = "run-world-supervised-budget",
            .desc = "Run the supervised budget World example.",
            .expected_stdout =
            \\permit_fingerprint=400104c204165312
            \\receipt_fingerprint=fc5131bf24e2a2d5
            \\budget_exceeded=false
            \\denied_budget_exceeded=true
            \\
            ,
        },
        .{
            .name = "world-supervised-agent",
            .path = "examples/world_supervised_agent.zig",
            .step = "run-world-supervised-agent",
            .desc = "Run the supervised agent World example.",
            .expected_stdout =
            \\model_port_calls=2
            \\tool_port_calls=1
            \\total_cost_units=13
            \\final_result=final=actuate skeleton complete
            \\
            ,
        },
        .{
            .name = "world-supervised-handoff",
            .path = "examples/world_supervised_handoff.zig",
            .step = "run-world-supervised-handoff",
            .desc = "Run the supervised handoff World example.",
            .expected_stdout =
            \\received_run_image_fingerprint=c3f6cc63bd33e649
            \\receiver_permit_fingerprint=b87664d5f288ef48
            \\receiver_receipt_fingerprint=7fcf0c2c57eaa585
            \\final_result=7
            \\
            ,
        },
        .{
            .name = "world-supervised-branch",
            .path = "examples/world_supervised_branch.zig",
            .step = "run-world-supervised-branch",
            .desc = "Run the supervised branch World example.",
            .expected_stdout =
            \\checkpoint_fingerprint=f8e9ec205791e870
            \\first_branch_result=allowed
            \\second_branch_denied=true
            \\
            ,
        },
        .{
            .name = "world-supervised-replay-verify",
            .path = "examples/world_supervised_replay_verify.zig",
            .step = "run-world-supervised-replay-verify",
            .desc = "Run the supervised replay/verify World example.",
            .expected_stdout =
            \\fresh_receipt=90098f44ecab7cbb
            \\replay_receipt=abbdbc1cf01120ed
            \\verify_divergence_detected=true
            \\
            ,
        },
    };
    inline for (examples) |example| {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("world", world);
        exe_mod.addImport("boundary", boundary);
        exe_mod.addImport("world_fixtures", fixtures);
        const exe = b.addExecutable(.{ .name = example.name, .root_module = exe_mod });
        const run_step = b.step(example.step, example.desc);
        if (target.query.isNative()) {
            const run = addRunArtifactWithArgs(b, exe, if (b.args) |args| args else &.{});
            run.expectStdOutEqual(example.expected_stdout);
            run_step.dependOn(&run.step);
        } else {
            run_step.dependOn(&exe.step);
            b.default_step.dependOn(&exe.step);
        }
        check_step.dependOn(run_step);
    }

    const host_boundary_dep = b.dependency("boundary", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const host_boundary = host_boundary_dep.module("boundary");
    const host_world = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    host_world.addImport("boundary", host_boundary);
    const wasm_export_check_mod = b.createModule(.{
        .root_source_file = b.path("examples/world_wasm_export_check.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    wasm_export_check_mod.addImport("world", host_world);
    const wasm_export_check = b.addExecutable(.{ .name = "world-wasm-export-check", .root_module = wasm_export_check_mod });
    const run_wasm_export_check = b.addRunArtifact(wasm_export_check);
    run_wasm_export_check.addFileArg(wasm_guest.getEmittedBin());
    const wasm_export_check_step = b.step("run-world-wasm-export-check", "Inspect World wasm guest exports and imports.");
    wasm_export_check_step.dependOn(&run_wasm_export_check.step);
    check_world_wasm_step.dependOn(&run_wasm_export_check.step);
    check_step.dependOn(check_world_wasm_step);
    const run_wasm_one_port_step = b.step("run-world-wasm-one-port", "Optionally run the World wasm one-port guest with an external runtime.");
    const skip_wasm_runtime = b.addSystemCommand(&.{
        "sh",
        "-c",
        "echo 'wasm_runtime=skipped'; echo 'reason=external runtime host not configured'",
    });
    skip_wasm_runtime.step.dependOn(&wasm_guest.step);
    run_wasm_one_port_step.dependOn(&skip_wasm_runtime.step);

    const lint_step = b.step("lint", "Run formatting and hot-path source guards.");
    const fmt_check = b.addSystemCommand(&.{
        "zig",
        "fmt",
        "--check",
        "build.zig",
        "src",
        "examples",
        "test",
    });
    lint_step.dependOn(&fmt_check.step);
    const hot_path_guard = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\if grep -n -E 'TreatyResolver|ProviderHarness|provider_catalog|morphism_catalog|closure_graph|normalize|operation_label_dispatch|string_match_dispatch|transcript_image.*StoredValue|StoredValue.*transcript_image|request_token|thread_id' src/world.zig; then
        \\  echo "forbidden hot-path surface reference found" >&2
        \\  exit 1
        \\fi
    });
    lint_step.dependOn(&hot_path_guard.step);
    check_step.dependOn(lint_step);
}
