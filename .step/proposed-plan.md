<proposed_plan>
Iteration: 7

# World Runspace Kernel Implementation Plan

## Round Delta
- Converted the passed spec into an execution campaign with a typed slot-driver architecture so `world.Runspace` can host heterogeneous `Machine.Run` instances without becoming a second interpreter.
- Added a first-wave Runspace lifecycle transition matrix proof to lock allowed `RunSlot` and `PendingPort` transitions before wiring execution.
- Tightened closure around stale handle/mailbox rejection, supervision-preserving auto-dispatch, and non-goal hot-path guards.

## Summary
Build `world.Runspace` as a deterministic, caller-driven, in-memory reactor over existing World execution owners. The chosen path is a small public API (`world.Runspace`, `world.RunHandle`) with internal slot drivers, a fingerprint-bound mailbox, and event/report surfaces; first wave is core value types plus transition tests, and completion means every requested runspace example, focused test, regression example, lint, `zig build`, and `zig build check` passes on the final head.

The implementation must not add storage, transport, scheduler threads, async runtime, WASM ABI, real integrations, Boundary loaded execution, Boundary normalization/closure, crypto, package management, or an agent framework. Runspace owns arena/mailbox lifecycle only; `Machine`, `AdmittedRun`, `Handoff`, `Supervisor`, and `Timeline` remain canonical execution and proof owners.

## Iteration Change Log
- iteration=1; focus=baseline decisions; round_decision=continue; delta_kind=material; evidence=spec-pipeline pass plus repo inspection; what_we_did=converted spec into campaign plan; change=locked first wave and completion bar; sections_touched=Summary,Implementation Brief,Tests/Acceptance
- iteration=2; focus=architecture/interfaces; round_decision=continue; delta_kind=material; evidence=existing `Machine.Run` is comptime-specialized; what_we_did=added typed slot-driver decision; change=heterogeneous run support without generic public Runspace explosion; sections_touched=Interfaces/Types/APIs Impacted,Data Flow,Decision Log
- iteration=3; focus=operability/failure handling; round_decision=continue; delta_kind=material; evidence=stale mailbox/handle confusion is dominant invariant risk; what_we_did=made generation and single-use mailbox validation explicit; change=fail-closed response routing; sections_touched=Edge Cases/Failure Modes,Rollback/Abort Criteria,Adversarial Findings
- iteration=4; focus=tests/traceability; round_decision=continue; delta_kind=material; evidence=user proof list and build table shape; what_we_did=mapped requirements to focused filters/examples/regressions; change=proof suite is executable and traceable; sections_touched=Tests/Acceptance,Requirement-to-Test Traceability
- iteration=5; focus=creativity+press verification; round_decision=continue; delta_kind=material; evidence=state-machine drift would be subtle and high-cost; what_we_did=added lifecycle transition matrix proof; change=first-wave invariant artifact prevents local tolerant patches; sections_touched=Summary,Decision Log,Decision Impact Map,Implementation Brief
- iteration=6; focus=reassessment; round_decision=continue; delta_kind=none; evidence=checked Summary, Interfaces, Data Flow, Tests, Rollback; what_we_did=press pass found no blocking gaps; change=no material delta; sections_touched=Convergence Evidence,Contract Signals
- iteration=7; focus=closure; round_decision=close; delta_kind=none; evidence=second clean reassessment; what_we_did=verified required sections, decision completeness, and anti-churn closure; change=no material delta; sections_touched=Convergence Evidence,Contract Signals

## Non-Goals/Out of Scope
No storage backend, xitdb integration, network/transport, distributed protocol, scheduler thread, async runtime, provider lifecycle manager, service discovery, real model/tool/file/human integrations, WASM ABI, Boundary `LoadedModule.Session`, Boundary closure/normalization, TreatyResolver hot path, ProviderHarness hot path, signing/encryption/security claims, package manager, artifact registry, or agent framework.

## Scope Change Log
| scope_change | reason | approved_by |
|---|---|---|
| none | Lifecycle transition matrix is proof for requested RunSlot/PendingPort state tracking, not feature expansion | user brief + spec handoff |
| reduction | Public root limited to `world.Runspace` and `world.RunHandle`; nested types live under `world.Runspace` | user preference to keep public root small |

## Interfaces/Types/APIs Impacted
- Public root: add `pub const Runspace` and `pub const RunHandle`; keep `RunSlot`, `Mailbox`, `PendingPort`, and `RunspaceReport` as nested/public names under `world.Runspace`.
- Version constants: add `world_run_handle_format_version`, `world_run_handle_fingerprint_version`, `world_pending_port_format_version`, `world_pending_port_fingerprint_version`, and `world_runspace_event_fingerprint_version`, all `= 1`.
- `world.RunHandle`: fields include format/fingerprint versions, handle fingerprint, runspace fingerprint, local run id, target ref fingerprint, optional admission receipt fingerprint, optional permit fingerprint, optional branch id, and generation.
- `world.Runspace.Config`: includes policy, `max_runs`, `max_pending_ports`, `max_events`, `preserve_completed_runs`, `require_supervision`, `require_admission`, `allow_direct_target_install`, `allow_handoff_install`, `allow_replay_install`, and `auto_dispatch=false`.
- Runtime API: `tick() !Report`, `stepOne() !Event`, `step(handle) !Event`, `poll() Report`, `report() Report`, `summary() Summary`.
- Mailbox API: `listPending()`, `get(mailbox_id)`, `respond(mailbox_id, Frame.Response)`, `respondValue(mailbox_id, value)`, `reject(mailbox_id, reason)`, `fail(mailbox_id, reason)`, `cancel(mailbox_id, reason)`.

## Data Flow
1. Caller creates `Runspace` with deterministic config and installs a typed run through admitted, direct target, handoff, or replay path.
2. Install creates `RunHandle`, internal `RunSlot`, typed slot driver, optional transcript/timeline sink, optional permit context, and `run_installed` or `run_admitted` event.
3. `tick` walks runnable slots by local run id and generation, calls the slot driver’s `nextFrame`, and records `run_stepped`.
4. On `Frame.Request`, Runspace creates one `PendingPort`, records `port_enqueued` and `run_parked_on_port`, and marks the slot parked with the mailbox id.
5. Caller responds by mailbox id. Runspace validates mailbox status, handle generation, request/frame fingerprint, target/surface identity, `world_port_id`, expected response kind/value table, and permit/admission context.
6. Valid responses call the slot driver’s concrete `resumeFrame`, consume the mailbox entry, record `port_responded` and `run_resumed`, then leave the run runnable unless configured to step immediately.
7. Completion/failure/export/checkpoint/branch/replay/verify events delegate to existing Machine/Handoff/Supervisor/Timeline primitives and update Runspace reports.

## Edge Cases/Failure Modes
- Stale `RunHandle`: reject when local id exists but generation differs.
- Stale mailbox id: reject if missing, already responded, cancelled, exported, or failed.
- Mismatched response: reject wrong surface, target certificate, port id, request fingerprint, response kind, value table, replay key, or value image.
- Duplicate pending request fingerprint: reject while an equivalent pending entry is active in the same runspace.
- Auto-dispatch over budget: deny before handler call through existing `Supervisor` checks.
- Replay-only native call attempt: fail; replay installs must not call native handlers.

## Tests/Acceptance
- Add focused runspace tests to `test/world_test.zig`: run handle, run slot, pending port, mailbox, runspace event, runspace report, handoff, agent, supervised, replay/verify, branch/checkpoint, admission/environment integration, and deterministic multi-run ordering.
- Add examples and build steps: `world_runspace_basic`, `world_runspace_multi`, `world_runspace_handoff`, `world_runspace_agent`, `world_runspace_supervised`.
- Update README and add `docs/runspace.md` with the exact framing: “Runspace is a deterministic local reactor. It does not schedule time, own storage, or perform transport.”
- Required closure commands include the user’s full proof list.

## Requirement-to-Test Traceability
| requirement | acceptance_check |
|---|---|
| Deterministic handle identity | run handle fingerprint/generation tests |
| Read-only slot summaries | run slot summary/status tests |
| Single-use pending ports | pending port and mailbox duplicate/stale tests |
| Manual tick/park/respond lifecycle | basic and multi-run tests/examples |
| Auto-dispatch stays supervised | auto-dispatch test with budget denial before handler call |
| Admission-aware install | admitted run install and target mismatch rejection tests |
| Environment integration | binding plan/byte adapter/missing binding tests |
| Handoff export | parked/completed export tests plus handoff example |
| Branch/checkpoint | branch handle generation and budget tests |
| Replay/verify | replay no-native-call and verify divergence tests |
| Non-goals preserved | lint hot-path guard and docs assertions |

## Rollout/Monitoring
- Implement on a feature branch from latest `main`.
- Use focused filters as early gates.
- Use `zig build check --summary all` as the broad local gate once examples are wired.
- Before PR, run the full proof command set and capture example outputs/fingerprints for PR summary.

## Rollback/Abort Criteria
- Abort if Runspace requires any explicit non-goal.
- Abort if response routing cannot be made single-use and fingerprint-bound.
- Abort if auto-dispatch cannot route through existing Environment and Supervision semantics.
- Abort if existing PR #1-#5 regression examples fail without a directly related, invariant-preserving fix.

## Assumptions/Defaults
| assumption | provenance | confidence | verification_plan |
|---|---|---:|---|
| `world.Runspace` can store heterogeneous runs through internal typed drivers | existing `Machine.Run` is comptime-specialized | high | compile/run direct, admitted, replay, and agent examples |
| Public root should stay small | user brief says prefer `world.Runspace`, maybe `world.RunHandle` | high | README/API review and compile examples |
| Manual mode default is safest | user brief says default false for explicitness | high | basic/multi/agent examples park until mailbox response |
| Time-sensitive repo state is `main` at `33034d72465cd3b387d93fd52bcb95cede81c33d` on 2026-06-01 | repo inspection during spec pass | medium | re-run `git status --branch` and `git rev-parse HEAD` before implementation |

## Decision Log
| decision_id | decision | rationale |
|---|---|---|
| D1 | Runspace owns arena/mailbox lifecycle, not execution semantics | prevents a second interpreter |
| D2 | Use internal typed slot drivers | supports multiple comptime-specialized run types in one arena |
| D3 | Expose only `world.Runspace` and `world.RunHandle` at root | preserves small public API |
| D4 | Manual mailbox mode defaults false for auto-dispatch | keeps host action explicit |
| D5 | Validate mailbox id plus request/frame/target/surface fingerprints | prevents stale or cross-run resume |
| D6 | Delegate supervision to existing `Supervisor` hooks | avoids tolerant downstream policy patches |
| D7 | Add lifecycle transition matrix proof in first wave | prevents invalid RunSlot/PendingPort states from becoming accepted |
| D8 | Keep examples in existing build table | preserves check-step behavior and expected stdout pattern |

## Decision Impact Map
| decision_id | impacted_sections | follow_up_action |
|---|---|---|
| D1 | Data Flow, Implementation Brief | call existing Machine/Handoff/Supervisor APIs instead of duplicating logic |
| D2 | Interfaces/Types/APIs Impacted | implement per-install typed driver create/step/resume/export/deinit functions |
| D3 | README, docs/runspace.md | document nested Runspace names and root aliases |
| D4 | Tests/Acceptance | prove manual parking before auto-dispatch examples |
| D5 | Edge Cases/Failure Modes | add stale/wrong response tests |
| D6 | Tests/Acceptance, Rollback/Abort Criteria | prove budget denial before handler call |
| D7 | Tests/Acceptance | add transition matrix tests before execution wiring |
| D8 | Rollout/Monitoring | add five entries to existing `build.zig` examples table |

## Open Questions
None.

## Stakeholder Signoff Matrix
| stakeholder | owner | status | readiness_condition |
|---|---|---|---|
| product | user | assumed-approved | user supplied milestone/success criteria |
| engineering | implementation agent | ready | plan accepted and mode switched to implementation |
| operations | implementation agent | ready | no scheduler/storage/transport operational surface added |
| security | implementation agent | ready | no crypto/security claims; pointer/credential exclusion tested |

## Adversarial Findings
| lens | type | severity | section | decision | status | probability | impact | trigger |
|---|---|---|---|---|---|---|---|---|
| feasibility | risk | high | Interfaces/Types/APIs Impacted | D2 | mitigated | medium | high | heterogeneous run storage fails to compile |
| operability | risk | high | Data Flow | D5 | mitigated | medium | high | stale mailbox response resumes wrong run |
| risk | risk | high | Tests/Acceptance | D6 | mitigated | medium | high | auto-dispatch calls handler before supervision |

## Convergence Evidence
clean_rounds=2
press_pass_clean=true
new_errors=0
last_two_no_delta_iterations=6,7
hysteresis_proof=iterations 6 and 7 both found no material delta with non-empty evidence
press_sections_checked=Summary,Interfaces/Types/APIs Impacted,Data Flow,Tests/Acceptance,Rollback/Abort Criteria
implementation_ready_reason=all major requirements map to tests, non-goals are explicit, rollback triggers are binary, and first execution wave removes the highest-risk state ambiguity before execution wiring
remaining_minor_concerns=exact deterministic fingerprints/stdout values must be filled from implementation outputs

## Contract Signals
contract_version=2
strictness_profile=balanced
blocking_errors=0
material_risks_open=0
clean_rounds=2
press_pass_clean=true
new_errors=0
rewrite_ratio=0.30
external_inputs_trusted=false
improvement_exhausted=true
stop_reason=none

## Implementation Brief
1. step=core-types-and-transition-matrix; owner=implementation agent; success_criteria=version constants, `RunHandle`, nested Runspace value types, status enums, fingerprints, and lifecycle transition tests compile and pass.
2. step=mailbox; owner=implementation agent; success_criteria=push/get/list/respond/cancel/export validations pass stale, duplicate, wrong-port, wrong-kind, and wrong-request tests.
3. step=runspace-arena-and-install; owner=implementation agent; success_criteria=config gates, deterministic handle generation, read-only summaries, and direct/admitted/replay install tests pass.
4. step=typed-slot-driver-execution; owner=implementation agent; success_criteria=`tick`, `stepOne`, `step(handle)`, parking, response resume, completion, and deterministic multi-run ordering pass.
5. step=supervision-and-auto-dispatch; owner=implementation agent; success_criteria=manual default parks; auto-dispatch uses Environment bindings; denial happens before handler calls; lint hot-path guard remains green.
6. step=handoff-branch-replay-verify; owner=implementation agent; success_criteria=parked/completed export, pending export, branch/checkpoint, replay no-native-call, verify divergence, and receipt tests pass.
7. step=examples-build-docs; owner=implementation agent; success_criteria=five new examples are in `build.zig`, README/docs explain Runspace/non-goals, expected stdout is deterministic.
8. step=full-proof-closeout; owner=implementation agent; success_criteria=all commands in Tests/Acceptance pass and PR summary includes required API/integration/example/non-goal bullets.

Iteration: 7
</proposed_plan>
