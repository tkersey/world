# World

World is the first concrete interpreter for Boundary Certified Targets. Boundary does the algebra; World handles the ports.

Boundary compiles a defunctionalized algebraic-effects program into a residual `Program.Session`, Boundary Normal Form, target-neutral `WorldSurface`, dense `WorldPortTable`, `WorldValueTable`, `WorldDispatchTable`, source/trace/evidence maps, and a `Target.Certificate`. World consumes that certified target and chooses a local Zig handler ABI for explicit residual `WorldPorts`.

## Boundary And World

Boundary owns normalization, closure, treaty resolution, provider reasoning, morphism reasoning, and target-neutral metadata. World validates the certified target surface, starts the residual `Program.Session`, steps it, dispatches residual requests by dense `world_port_id`, calls host-owned handlers in fresh mode, records deterministic transcripts, replays from transcripts, and reports audit metadata.

World does not choose for Boundary. Boundary does not choose the concrete ABI for World.

## Public API

The public root is intentionally small:

- `world.Machine`
- `world.port`
- `world.portWithOptions`
- `world.PortRequest`
- `world.PortResponse`
- `world.Mode`
- `world.Transcript`
- `world.Frame`
- `world.ValuePolicy`
- `world.TranscriptImage`
- `world.Timeline`
- `world.TargetRef`
- `world.ImportRequirement`
- `world.ImportSet`
- `world.Environment`
- `world.Binding`
- `world.PortAuthority`
- `world.AdapterDescriptor`
- `world.BindingPlan`
- `world.AcceptanceReport`
- `world.EnvironmentCertificate`
- `world.Supervision`
- `world.Supervisor`
- `world.RunPermit`
- `world.SupervisionPolicy`
- `world.RunReceipt`
- `world.RunState`
- `world.RunImage`
- `world.Handoff`
- `world.Admission`
- `world.Runspace`
- `world.RunHandle`
- `world.Guest`
- `world.Fabric`
- `world.Linker`
- `world.Assembly`
- `world.Executable`
- `world.Capsule`
- `world.AssemblyCapsule`
- `world.Actuation`
- `world.Appliance`
- `world.Continuity`
- `world.Archive`
- `world.MemoryVault`
- `world.ActuatorRef`
- `world.ConduitPlan`
- `world.ConduitRoute`
- `world.AuditImage`
- `world.AuditReport`
- `world.Error`

Typical usage:

```zig
const ToolPort = world.port(Target, TargetProgram.protocol.operationSite("tool", "call", 0), handleTool);
const Machine = world.Machine(Target, .{
    .ports = .{ToolPort},
    .strict_handler_coverage = true,
});
```

The legacy `.ports` form remains available. It is sugar over the same import-binding shape used by `world.Environment`.

`world.Executable` builds a sealed World Seed from explicit Boundary full-module bytes, provider modules, residual Actuation descriptors, Linker witnesses, dense dispatch tables, and memory bounds. It is the generic path for runtimes that do not possess a locally generated Boundary Target type. `world_universal_appliance.wasm` is an ABI v2 conformance artifact that loads canonical `world.Executable.Image` bytes and executes them through actual Boundary loaded sessions plus World Appliance/Runspace/Fabric/Actuation/Capsule/Archive owners. World pins the reviewed Boundary v0.5.0 release for this path. See [docs/executable.md](docs/executable.md), [docs/appliance.md](docs/appliance.md), and [docs/runtime_closure.md](docs/runtime_closure.md).

## Certified Targets

`Machine(Target, Config)` binds to a Boundary target with:

- `Target.Program`
- `Target.WorldSurface`
- `Target.WorldPortTable`
- `Target.WorldValueTable`
- `Target.WorldDispatchTable`
- `Target.Certificate`

Construction asserts the Boundary world surface is ready and that the target hot path is a dense dispatch surface.

## Modes

`world.Mode` has four modes:

- `fresh`: call handlers and record request/response events.
- `replay`: resume from transcript responses without calling handlers.
- `verify`: call handlers and compare fresh response fingerprints with transcript responses.
- `audit`: run with a configured source mode and return `AuditReport` counts.

## Port Handlers

Handlers are declared with `world.port(Target, Site, handler)`. The descriptor binds the exact target, residual site index, residual site fingerprint, payload type, response type, source ref, and world-port ref.

Handlers may accept either:

```zig
fn handle(ctx: *Ctx, payload: Port.Payload) !Port.Response
fn handle(ctx: *Ctx, request: world.PortRequest(Target, Site)) !Site.Resume
```

Fresh and verify modes require handler coverage. Strict coverage rejects missing target ports at compile time.

`world.port` treats handler responses as borrowed values: World clones the response into run/transcript storage before resuming Boundary, and the handler/context remains responsible for any source storage it owns. Handlers that return newly allocated response buffers can use `world.portWithOptions(..., .{ .response_deinit = deinitFn })`; World calls `deinitFn(ctx, response)` after it has retained the response.

## World Environment

World Environment binds the receiving host to the semantic WorldPort imports that Boundary exposed. `world.TargetRef` identifies the certified target by target, surface, certificate, plan, table, and profile fingerprints without carrying code, handlers, runtime pointers, request tokens, credentials, or allocator/thread identity.

`world.ImportRequirement` describes one residual WorldPort requirement. `world.ImportSet` summarizes the required imports for a target and exposes required port ids and per-port requirements. Requirements are semantic; implementations stay outside the requirement.

`world.Binding` connects an import requirement to a local adapter declaration. `world.PortAuthority` is a local audit/policy descriptor, not a Boundary capability and not cryptographic security. `world.AdapterDescriptor` fingerprints adapter declarations without native function pointer identity. `world.BindingPlan` is the deterministic dense table used by `Machine` for `world_port_id` dispatch.

`world.AcceptanceReport` answers whether a target/run can execute under an environment and mode. `world.EnvironmentCertificate` records the accepted target, import set, binding plan, policy, authority, adapter, and blocker fingerprints for audit and transcript provenance.

```zig
const Env = world.Environment(Target, .{
    .bindings = .{
        world.bind(Target.WorldPorts.model_decide, world.NativeAdapter(handleModel)),
    },
    .policy = world.EnvironmentPolicy.fresh_and_replay,
});
const Machine = world.Machine(Target, .{ .environment = Env });
```

## Transcript And Replay

`world.Transcript` is an in-memory deterministic transcript. It records run events, port requests, fresh responses, replayed responses, failures, fingerprints, replay keys, turn indexes, and stored replay values.

Replay keys include:

- WorldSurface replay-scope fingerprint
- dense `world_port_id`
- request fingerprint
- response fingerprint

Changing any of those changes the replay key. Replay also fails on target-certificate mismatch, missing responses, port mismatch, request mismatch, response-kind mismatch, full-surface mismatch, or unused response events.

## World Timeline Kernel

The timeline kernel makes residual port interactions portable. `world.Frame.Request` describes a port request without a request token, runtime pointer, allocator pointer, handler function pointer, thread id, or host-owned pointer identity. `world.Frame.Response` describes the response, status, replay key, response fingerprint, and optional portable value image.

`world.Frame.ValueImage` is a byte-oriented value image for scalar values, byte slices, and simple product/sum shapes already represented by Boundary value metadata and Zig types. Unsupported values fail closed with `UnsupportedValueImage`, `NativeOnlyValue`, or `MissingValueImage` depending on `world.ValuePolicy`.

Native Zig handlers remain ergonomic through `world.port` and `world.portWithOptions`; they are one adapter over frame semantics. The frame step API is:

```zig
var run = try Machine.start(runtime, args, options);
switch (try run.nextFrame()) {
    .port_request => |request_frame| try run.resumeFrame(response_frame),
    .done => |value| ...,
    .failed => ...,
}
```

`world.TranscriptImage` is the portable image form of a transcript. It contains ordered event images, request/response frames, replay keys, final status, and summary counts. It does not store `StoredValue`, `*anyopaque`, allocator/runtime/thread pointers, request tokens, or handler functions. Image-backed replay requires the machine's compile-time port descriptors so World can recover the residual site and response type, but it does not call native handlers or require a handler context when response frames carry portable `ValueImage` data.

`world.Timeline.Checkpoint` records deterministic metadata for a resumable or branchable point: event index, turn index, prefix fingerprint, branch id, and optional current request/last response fingerprints. `world.Timeline.Branch` records a branch id, parent, checkpoint fingerprint, event range, final status, and counts. These are metadata primitives only; World does not add persistence, scheduling, or concurrency.

`world.AuditImage` summarizes frame counts, replay/verify/failure counts, checkpoint/branch counts, portable-value blockers, and the transcript image fingerprint when available.

## World Handoff

World Handoff packages execution state. Environment binds the receiving host. Boundary supplies the semantic target.

`world.RunState` describes whether a run is not started, running, parked on a port, completed, or failed. It binds the target ref, optional transcript image, branch id, checkpoint, pending request frame fingerprint, final response/value image fingerprint, turn index, and status.

`world.RunImage` is the portable handoff object. It contains a `TargetRef`, `ImportSet` fingerprint, transcript image, current `RunState`, checkpoint and branch metadata, optional pending `Frame.Request`, optional final `ValueImage`, and optional environment/acceptance/audit fingerprints. It does not contain handlers, credentials, concrete ABI data, network or storage transport, host function pointers, allocator/runtime/thread ids, or request tokens.

`world.Handoff` decodes and validates a `RunImage`, preflights it against a local target and environment, validates parked pending frames, supports replay-only and verify-on-receive flows through transcript images, and keeps branch metadata portable. Future Boundary module images can be referenced by `TargetRef`/`RunImage` without making World a storage, transport, or module-image implementation.

## World Supervision

Environment says what the host can provide. Supervision says what the host is willing to allow.

`world.RunPermit` is a deterministic local authorization-to-run object. It binds the target ref, WorldSurface, target certificate, environment certificate, binding plan, mode, `SupervisionPolicy`, `Budget`, `CostModel`, branch policy, handoff policy, metadata bytes, and label. It is not cryptographic, contains no credentials, and excludes handler function pointers, allocator/runtime/thread pointers, and request tokens from its fingerprint.

`world.SupervisionPolicy` is the fail-closed policy membrane: it controls fresh/replay/verify/audit calls, native/byte/replay adapters, pending/rejected/failed responses, branching, checkpoints, handoff export/accept, portable value requirements, native-only value rejection, replay transcript requirements, and budget-exceeded behavior. Presets include `strict_fresh`, `strict_replay`, `verify_replay`, `agent_fixture`, `audit_only`, `handoff_receiver`, and `branch_limited`.

`world.Budget` sets deterministic quotas for steps, requests, responses, fresh/replay/verify calls, failed/rejected/pending calls, frame/value/transcript bytes, transcript events, checkpoints, branches, handoff export/accept, total cost units, and per-port budgets. `world.CostModel` accounts deterministic integer units only; World does not implement billing, money, wall-clock metering, or external price feeds.

`world.PortRule` constrains an individual dense `world_port_id` by adapter kinds, authority kinds, modes, response status permissions, portable value policy, payload/response byte caps, request caps, and per-port cost units. `world.UsageLedger` records deterministic usage during a run. `world.SupervisionCheck` records each policy decision. `world.RunReceipt` summarizes the enforced permit, environment, target, run/transcript references, ledger, final state, final status, exceeded budgets, blockers, warnings, and summary counts.

`world.Supervisor` owns the policy membrane around `Machine` execution. If no permit is supplied, existing machine behavior is preserved. If a permit is supplied, Machine validates the permit against the target/environment/mode, denies disallowed requests before handler calls, updates the usage ledger, and exposes a receipt on successful `Machine.run`.

Handoff receivers may issue a new local permit with tighter limits using `Handoff.preflightWithPermit` and `Handoff.resumeWithPermit`. `RunImage` can carry prior permit and receipt fingerprints for inspection; receivers do not have to trust them.

## World Actuation

Environment says what the host can provide. Actuation says how the host is allowed to commit an effect, and what receipt proves happened.

`world.Actuation` is the deterministic host-side membrane for residual `WorldPort` requests that reach the host boundary. It turns a pending request into an `Actuation.Intent`, wraps the portable call as an `Actuation.Envelope`, records a policy `Actuation.Decision`, records an `Actuation.Commit`, captures an `Actuation.Response`, and emits an `Actuation.Receipt`. These objects are deterministic local evidence, not cryptographic proof, and they exclude handler pointers, allocator/runtime/thread identity, credentials, URLs, request tokens, model handles, file handles, and network handles.

`world.ActuatorRef` identifies an actuator declaration by stable policy metadata: kind, class, supported modes, allowed response statuses, value policy, optional authority/protocol descriptor fingerprints, label, and metadata. The kind is descriptive; it is not security authority. Built-in kinds include fixture, replay source, native function, byte protocol, guest bridge, model-like, tool-like, file-like, human-like, and custom.

`world.Actuation.Class` describes effect policy: observation, deterministic fixture, idempotent mutation, non-idempotent mutation, irreversible mutation, compensatable mutation, human-gated, and unknown effect. World does not prove real-world idempotency or reversibility. It requires explicit idempotency keys, approvals, and receipts where policy demands them.

`world.Actuation.Descriptor` binds an actuator to a WorldPort-compatible shape without storing the host implementation. `world.Actuation.Binding` connects a residual import requirement to that descriptor. Environment preflight can count actuation bindings as coverage; Runspace can dispatch parked requests through the actuation membrane; Fabric and Linker can carry explicit actuation route metadata; Guest conformance vectors can include actuation receipt summaries.

`world.Actuation.IdempotencyKey` binds target, surface, port id, request fingerprint, actuator ref, and optional run/pending/capsule context. It is deterministic and local; future hosts may map it to external idempotency systems, but World does not claim exactly-once distributed semantics.

`world.Actuation.Journal` is an in-memory run-local sequence of intents, decisions, commits, responses, receipts, and idempotency keys. `Actuation.ReplaySource` satisfies intents from receipts or a journal without a fresh host call. `Actuation.VerifyReport` compares expected and fresh receipt behavior. Pending and deferred responses do not resume the parent run; Capsules can freeze pending intents and completed receipts when policy allows, then thaw under receiver-local policy.

Actuation comes before the future Continuity Vault because future storage should persist stable intent, envelope, commit, response, receipt, and journal objects without knowing any real model, tool, file, browser, network, or human integration.

## World Appliance

World Appliance is the vertical integration layer for deployment. It composes the existing World kernels into a closed, reconstructible execution fabric driven by one canonical host-turn protocol.

An appliance is defined at comptime with `world.Appliance.Define(RootTarget, config)`. The definition derives a deterministic `Appliance.Manifest`, `Appliance.Profile`, `Appliance.Capacity`, and `Appliance.MemoryPlan`; validates strict closed-world port coverage; and requires explicit Actuation bindings for external ports. Runtime does not discover providers, synthesize routes, resolve operation names, call TreatyResolver, or call ProviderHarness.

The host submits an `Appliance.Command` byte image for boot, restore, continue, inspect, cancel, or reset. Commands may bind receiver permit and evidence refs; boot commands bind the canonical root argument image; non-boot commands reject root arguments. The command execution mode must be advertised by the immutable Manifest's supported execution mode set, and unsupported modes are rejected before Core mutation. Reset emits deterministic host-visible output, then abandons pending continuation state so the Core can boot fresh again without retaining hidden archive, receipt, or host-request anchors. `Appliance.Core` advances to the next quiescent boundary and returns an `Appliance.TurnOutput`: status, quiescence report, prepared host requests, finalized Actuation receipt refs, optional root result, optional RunReceipt ref, checkpoint, TurnReceipt, optional Archive append batch fingerprint and canonical ref, blockers, warnings, and diagnostic metadata. Creating a TurnOutput performs no real host effect.

External effects cross the HostRequest/HostReply protocol. Appliance prepares host-visible work through `Actuation.Membrane.prepareHost`; hosts return `Appliance.HostOutcome` inside `Appliance.HostReply`, including a terminal response kind, bounded response bytes, bounded host-evidence bytes, and optional canonical `RetentionAck` evidence when applicable. A retention acknowledgment may be submitted at the command level or on a host reply; conflicting acknowledgments are rejected before Core mutation. Pending and deferred host outcomes remain nonterminal: Appliance records the reply evidence and keeps the same HostRequest parked until a terminal outcome arrives. World finalizes through `Actuation.Membrane.finalizeHost` and constructs its own Commit, Response, and Receipt evidence. Hosts cannot author World receipts directly.

Replay, verify, and audit commands do not ask the host for a fresh external effect. If replay evidence refs are present, Core consumes them as receiver-local replay evidence and advances without emitting a HostRequest. If an external port is still required and no replay evidence is present, Core returns a deterministic blocked TurnOutput.

`Appliance.Checkpoint` is the portable reconstruction unit. It binds the Capsule fingerprint plus explicit Capsule image bytes or a canonical Capsule image ref, and it carries pending Archive append acknowledgment state, so a host can carry the reconstruction source without hidden process state. A resident fast path may keep Core alive, but a fresh process or WASM instance must be able to restore from a completed turn's checkpoint and produce the same next semantic result. `Appliance.ReconstructionReport` records that resident/reconstructed equivalence.

When Archive evidence is enabled, Appliance plans at most one `Archive.AppendBatch` per advancing turn. The host owns retaining those bytes and may return `Appliance.RetentionAck` either on the next command or alongside a host reply. Strict profiles refuse to advance until the pending append is acknowledged, while non-strict profiles continue with an unacknowledged-archive warning in the next TurnOutput, TurnReceipt, and QuiescenceReport. Appliance performs no file or database operation.

Appliance ABI v1 is separate from Guest ABI v1. Guest ABI v1 is frame-shaped execution inside a guest. Appliance ABI v1 is the higher-level deployment ABI: canonical Manifest byte read, Capacity/MemoryPlan identity and memory-bound inspection, command submit, output read, last-error read, and reset. `needs_host`, `completed`, `failed`, `blocked`, `cancelled`, and `output_ready` are output-producing submit statuses; command errors use the remaining rejection/status ordinals plus last-error bytes. `Appliance.Native` exposes the same ABI-shaped manifest, output, last-error, submit, and reset operations over Core for CI and conformance. It requires no WASI, filesystem, network, clock, randomness, actuator imports, storage imports, or hidden runtime state.

Host responsibilities stay outside World: real effects, credentials, network clients, files, humans and approvals, Archive byte retention, checkpoint transport, WASM runtime choice, process lifecycle, and durability policy. World owns deterministic execution, effect intent and validation, internal composition, supervision evidence, portable state, causal history, and canonical host protocol.

See [docs/appliance.md](docs/appliance.md) for the full Appliance contract.

## World Continuity

Capsules define the portable execution unit. Actuation receipts define host-effect evidence. Continuity remembers both as local causal facts.

Continuity Core stores facts. Chronicle records why those facts exist and how to replay local causal history.

`world.Continuity` is the local causal memory model for capsule images and actuation evidence. It is capsule-and-actuation-native, not a universal object dump: v1 covers capsule images/manifests/certificates/runspace/fabric/link images, actuation refs/descriptors/bindings/policies/intents/envelopes/decisions/commits/responses/receipts/journals/verify reports, and selected core evidence such as frames, transcripts, run images, permits, admissions, assemblies, fabric receipts, guest reports, and bundles.

`Continuity.ObjectKind` names those stored evidence classes. `Continuity.ObjectRef` is a deterministic content-addressed local reference with format/fingerprint versions, object kind, object format version, object fingerprint, byte length, and optional diagnostic metadata. It is not cryptographic security and excludes native pointers, runtime identity, credentials, URLs, request tokens, handlers, and host handles.

`Continuity.ObjectEnvelope` wraps canonical payload bytes with the object kind/version, content fingerprint, byte length, explicit dependency refs, optional summary bytes, and labels. The envelope fingerprint binds the stored payload metadata and dependency list so stores and bundles can validate malformed, mismatched, missing, oversized, cyclic, or unsupported objects fail-closed.

`world.MemoryVault` is the v1 in-memory content-addressed vault. It deduplicates identical envelopes, stores and loads capsule images, actuation receipts, and actuation journals, lists objects by kind, validates refs, returns explicit dependencies, and looks up committed actuation receipts by idempotency key. It is append-oriented and has no delete, file backend, production database semantics, network fetch, signing, or encryption.

`Continuity.Chronicle` adds the replayable local history above MemoryVault. `Chronicle.Event` records deterministic causal events such as object commit, capsule store, actuation receipt store, idempotency registration, bundle import/export, inbox/outbox transitions, and recovery execution. Event fingerprints exclude wall-clock time, credentials, request tokens, handler pointers, host handles, allocator/runtime/thread identity, and other authority-bearing host state.

`Chronicle.Cursor` names a position in local history by event index, last event fingerprint, cumulative prefix fingerprint, object count, and committed transaction count. `Chronicle.Transaction` stages object writes and events without mutating the vault; `commit` stores all staged objects/events atomically for MemoryVault and records a `Chronicle.Commit`, while `abort` and failed validation leave the vault unchanged.

`Continuity.Session` binds a MemoryVault, Chronicle cursor, ledger summary, and `PersistPolicy`. Persistence is explicit: default policy persists nothing, presets opt into capsule evidence, actuation evidence, replay evidence, or full local evidence. `Continuity.Sink` is an optional bridge from kernel events into a session; no sink means no automatic persistence, and sink failures surface as ordinary errors.

`Continuity.ObjectGraph` builds bounded dependency closures from stored roots. `Continuity.CapsuleGraph` specializes that view for restore/replay/actuation readiness and reports missing deps, relink requirements, replay feasibility, and local fresh actuation requirements. `Continuity.ActuationGraph` specializes the view for receipts and journals, including pending, committed, replayable, duplicate idempotency, and fresh-commit summaries.

`Chronicle.Projection` rebuilds local views such as capsule indexes, actuation indexes, object indexes, inbox, outbox, recovery queues, idempotency registries, and bundle history from committed events. Projection and replay reports bind their source cursor so stale derived state can be detected. `IdempotencyRegistry` is a projection, not a distributed exactly-once system: strict local policy rejects duplicate fresh commits under one key while allowing replay receipts with `fresh_called=false`.

`Continuity.Bundle` and `Continuity.BundleManifest` export and import portable collections of object envelopes through transaction-backed session paths. Bundle validation checks envelope and payload fingerprints, dependency closure, unknown object kinds, size/count limits, duplicate identical/conflicting objects, and strict duplicate fresh actuation commits. Inbox and outbox are local Chronicle projections over handoff envelopes and events; they do not implement network transport, scheduling, or delivery.

`Continuity.Recovery` now has cursor-bound `RecoveryPlan` and `RecoveryReport` evidence for executable local recovery. Planning emits Chronicle readiness or rejection events; execution denies before Runspace mutation when blockers exist and then calls Capsule thaw/replay owner APIs. Recovery still does not bypass Capsule quiescence, Linker relink checks, Admission/Supervision/Actuation invariants, fetch network dependencies, deserialize handlers, or call fresh host actuators outside local policy.

`Capsule.freezeToSession`, `Capsule.freezeAssemblyToSession`, `Capsule.freezeRunToSession`, `Actuation.commitToSession`, and `Actuation.journalToSession` are explicit transaction-backed helpers. Archive bytes retain one append-only local Chronicle stream plus object envelopes without inventing separate transaction/event/projection semantics. World still does not implement a production database, filesystem storage, network transport, a scheduler, an async runtime, real model/tool/file/human integrations, signing, encryption, exactly-once semantics, broad implicit persistence, or credential/host-handle serialization.

## World Archive

`world.Archive` is the portable byte format and replay model for canonical `Continuity.ObjectEnvelope` values and committed Chronicle history. Archive owns canonical encoding, segment framing, moment visibility, historical materialization, valid-prefix recovery, and replay from sealed bytes. Chronicle owns causal events, cursors, transactions, commits, and replayable projections.

`Archive.Moment` records one committed Chronicle transition. A moment becomes committed only when its `MomentData` segment is immediately followed by a matching valid `Seal`. `Archive.Snapshot` is a read-only view at a historical moment. `Archive.Memory` is the reference in-memory byte store and supports historical moments, simulated reopen by byte clone, replay reports, idempotency duplicate checks after reopen, and valid-prefix recovery without claiming process durability.

Archive defines canonical bytes and replay semantics. Hosts may retain those bytes, but storage adapters live outside World and must not shape World semantics.

## World Admission

Admission is the receiver-side proof that a transferred run can be interpreted locally under local environment and permit.

`world.Admission.TransferPackage` is the portable admission envelope. It can carry a target reference, Boundary module reference, full module bytes, run image, transcript image, checkpoint and branch refs, prior permit/receipt refs, requested mode, supervision hints, and metadata. It does not carry handlers, credentials, native function pointers, allocator/runtime/thread pointers, request tokens, storage, or transport.

`world.Admission.PackageManifest` summarizes package contents and binds the package fingerprint to target/module/run/transcript/checkpoint/branch/prior-receipt summaries.

`world.Admission.ModuleRef` bridges Boundary Certified Boundary Module identity into World without making World execute Boundary loaded modules. `world.Admission.ModuleGateway` validates and inspects module images through Boundary-owned `Target.Module` APIs, derives import/export summaries, and reports loaded execution as unsupported unless a local generated target matches.

`world.Admission.TargetRegistry` is an in-memory registry of local generated targets the receiver knows how to execute. `world.Admission.TargetMatch` compares transferred target/module identity with local executable target identity across surface, certificate, program plan, normal form, and available table/import summaries.

`world.Admission.AdmissionPolicy` constrains package kinds and modes. Presets include strict local execution, inspect modules, replay-only, handoff receiver, verify receiver, and test fixture. `AdmissionRequest`, `AdmissionReport`, and `AdmissionReceipt` record the requested operation, deterministic accepted/rejected decision, blockers, warnings, and accepted receipt. Receipts are not cryptographic.

`world.Admission.Admitter` coordinates package validation, target matching, environment preflight, permit checks, report/receipt issuance, and construction of an `AdmittedRun` when the mode is executable. `AdmittedRun` wraps existing Machine/Handoff data; it does not duplicate Machine execution logic.

Admission keeps storage, network transport, scheduler, async runtime, real integrations, WASM ABI, Boundary loaded execution, Boundary closure/normalization, signing, encryption, package management, and artifact registry out of World.

## World Runspace

Runspace is a deterministic local reactor. It does not schedule time, own storage, or perform transport.

`world.Runspace` hosts many admitted or local runs in one in-memory arena. It assigns each run a local `RunHandle`, keeps an internal `RunSlot`, steps runnable slots in deterministic insertion order, parks runs on `Frame.Request`, records `PendingPort` mailbox entries, routes `Frame.Response` values back to the matching parked run, and records a separate runspace event log.

`RunHandle` is local to one Runspace. Its fingerprint binds the runspace fingerprint, local run id, target ref, optional admission receipt, optional permit, optional branch id, and generation. It excludes handlers, request tokens, runtime pointers, allocators, threads, credentials, storage, and transport identity.

`RunSlot` is internal mutable state. Public callers use summaries and reports instead of mutating slots directly. Slot status tracks admitted, runnable, running, parked on port, parked on supervision, completed, failed, exported, and rejected states.

`Mailbox` stores pending `PendingPort` entries. A pending port binds the run handle, mailbox id, dense `world_port_id`, request fingerprint, request frame fingerprint, residual site, target ref, optional environment/permit fingerprints, and insertion turn. Responses are single-use and must match the pending request, port id, surface, response kind, and value table.

Runspace is caller-driven:

```zig
var runspace = world.Runspace.init(allocator, .{});
const handle = try runspace.installMachineRun(Target, Env, runtime, args, options);
_ = try runspace.tick();
const pending = try runspace.mailbox.get(0);
_ = try runspace.respondValue(pending.mailbox_id, value);
_ = try runspace.tick();
```

Manual mode is the default: every port request parks and waits for host action. `auto_dispatch = true` uses the existing `Environment`/`Machine` typed adapter path to answer synchronous local requests, while still recording mailbox and runspace events. Runspace does not call TreatyResolver or ProviderHarness on the hot path.

Runspace integrates with Admission by installing `AdmittedRun` values and preserving admission receipt fingerprints. Parked run images install into the mailbox so hosts can inspect or export the pending request. It integrates with Supervision through the existing `Machine`/`Supervisor` membrane: permits are enforced before handlers, runspace limits cap runs, pending ports, and events, and handoff/checkpoint/branch operations record runspace events. It integrates with Timeline and Handoff by exporting `RunImage` snapshots, creating `Timeline.Checkpoint` metadata, and creating local branch handles.

Runspace is not a scheduler, async runtime, storage backend, network transport, agent framework, real model/tool/file/human integration, service discovery layer, WASM ABI, Boundary loaded execution path, Boundary closure/normalization path, package manager, artifact registry, signing layer, or encryption layer.

## World Fabric

Environment says what the host can provide. Fabric says how admitted Boundary runs can provide for each other.

`world.Fabric.Route` is an explicit conduit from one parent residual `WorldPort` to a local provider path. Route kinds include adapter, target export, admitted run, guest, replay, reject, and unsupported. Routes fingerprint target/module/export/admission/environment/permit/guest/value-mapping metadata, but exclude handler pointers, runtime pointers, allocator/thread identity, request tokens, credentials, URLs, model clients, file handles, and network handles.

`world.Fabric.Plan` is the deterministic routing table for a parent target. Plans are ordered by dense `world_port_id`, not operation-name dispatch, and expose lookup, coverage, cycle, depth, provider-run-limit, and summary checks. `world.Fabric.Binding` records the parent import requirement, route, provider reference, export reference, value mapping, required flag, and route kind for run-to-run composition.

`world.Fabric.ValueMapping` v1 supports only canonical relationships already represented by World/Boundary metadata: provider request descriptors and provider final result to parent response. Provider request mappings are structurally represented but are rejected by executable plan installation until provider argument identity has a witness. Fabric rejects unsupported mapping, payload/result mismatch, unsupported value images, and cross-type conversion instead of adding host conversion, JSON conversion, string conversion, or callback mappers.

Runspace integrates Fabric through `installFabricPlan`, `routePending`, `routePendingToProviderRun`, `routePendingFromReplay`, `respondFromFabric`, and `tickFabric`. A parent run parks on a `PendingPort`; an installed plan selects a route; a provider run is installed or adopted in the same deterministic Runspace; the provider result maps to one parent `Frame.Response`; the parent mailbox entry resumes; and invocation, receipt, and runspace events record the causal path. Routing requires a previously installed plan, replay routes require `routePendingFromReplay` transcript evidence, and `respondFromFabric` completes only recorded invocation occurrences.

Fabric cycle/depth controls fail closed with same-run recursion, same-target cycle, depth, and provider-run-limit errors. Supervision accounts Fabric invocations, provider runs, nested depth, and provider costs before provider installation or response emission. Replay routes satisfy parent requests from transcript images. Reject routes produce deterministic terminal responses. Fabric v1 rejects guest routes until a dedicated guest route executor exists. Active Fabric handoff fails closed in v1 with `ActiveFabricUnsupported`; completed Fabric history remains available in runspace Fabric receipts and event summaries.

Fabric is local composition only. It does not implement Boundary provider linking, Boundary normalization, TreatyResolver hot paths, ProviderHarness hot paths, service discovery, storage, network transport, scheduler threads, async runtime, real model/tool/file/human integration, provider lifecycle, WASM host packages, Boundary loaded-module execution, signing, encryption, package management, artifact registry, or an agent framework.

See `docs/fabric.md`.

## World Linker

Fabric executes explicit routes. Linker synthesizes explicit routes from a closed set of known modules.

`world.Linker.Catalog` is an in-memory closed provider set: generated targets, module refs, admitted runs, guest providers, replay providers, reject routes, and environment adapters when policy allows. Catalog entries fingerprint provider identity, import/export summaries, admission/environment/permit witnesses, labels, and metadata. Fingerprints exclude handler pointers, runtime pointers, allocator/thread identity, request tokens, credentials, storage, transport, and discovery state.

`world.Linker.ImportIndex` and `world.Linker.ExportIndex` expose root and provider import requirements plus candidate exports. `world.Linker.Match` records why one export can satisfy one parent import: exact value refs, same-schema compatibility when policy allows, explicit hint, replay, adapter, guest, reject, or unsupported. Hints are deterministic tie-breakers; they cannot bypass value compatibility, cycle/depth policy, admission, supervision, or guest-conformance policy.

`world.Linker.link` builds a `LinkGraph`, synthesizes ordinary `world.Fabric.Route` and `world.Fabric.Plan` records, derives residual environment requirements for imports not covered by Fabric, and returns a `LinkPlan`, `LinkReport`, `LinkCertificate`, and executable `world.Assembly`. The certificate is deterministic witness metadata, not a cryptographic signature.

`world.Assembly` does not execute. It installs synthesized Fabric plans into Runspace through the Fabric API and exposes residual imports for Environment preflight. Supervision and Guest conformance can bind the LinkPlan, LinkCertificate, and Assembly fingerprints as provenance.

Linker is closed-world assembly linking only. It does not implement service discovery, package management, artifact registries, storage, network transport, schedulers, async runtimes, real integrations, provider lifecycle, Boundary normalization, TreatyResolver/ProviderHarness hot paths, Boundary loaded-module execution, signing, encryption, or an agent framework.

See `docs/linker.md`.

## World Assembly Capsules

RunImage moves one run. Assembly Capsule moves a linked execution fabric.

`world.Capsule` freezes a quiescent Runspace or linked Assembly into a deterministic portable image. The image binds a `Capsule.Manifest`, `RunspaceImage`, optional `LinkImage`, optional `FabricImage`, admission/environment/supervision/guest refs, transcript/run/value refs, dependency refs, and object refs. It carries fingerprints and metadata only; it does not carry handlers, credentials, request tokens, allocator/runtime/thread state, file handles, network handles, storage addresses, or ABI-specific host data.

Quiescence is the freeze boundary. Completed, failed, parked, and witnessed active-Fabric parked assemblies can be frozen under policy. Running slots, mailbox mutations, missing Fabric route/provider/parent-pending witnesses, and unsafe active Fabric fail closed before image construction.

`RunspaceImage` captures run slots, mailbox pending-port state, runspace events, roots/providers, branch/checkpoint refs, transcripts, run images, receipts, admissions, permits, and active Fabric invocation refs. `FabricImage` captures active and completed Fabric causality only when provider identity, route witness, value mapping, supervision evidence, parent response mapping, and mailbox ownership are explicit. `LinkImage` captures LinkPlan, LinkCertificate, Assembly, policy/catalog, route synthesis refs, residual imports, provider refs, guest refs, and external environment requirements.

Thaw is receiver-owned. `Capsule.planThaw` validates the local root target-ref witness plus link/environment/permit policy and records handle/mailbox remapping plans. `Capsule.thawIntoRunspace` denies before destination Runspace mutation when policy fails. Sender permits and receipts are evidence only; receiver permit fingerprints are recorded as local restore evidence, not object-level authorization. Receivers configured with supervision or parked restore still fail closed until a receiver-local permit verifier and executable continuation witness exist. `Capsule.verifyLink` and `Capsule.relink` can use an embedded LinkCertificate or compare against a local catalog fingerprint, rejecting drift by default. Replay-only and inspect-only modes do not call native handlers. Guest conformance refs are carried as evidence and can be rerun by policy without requiring a real wasm runtime by default.

`Handoff.exportCapsule`, `Handoff.fromCapsule`, and `Handoff.acceptCapsule` move capsule bytes locally. `Admission.capsuleAdmissionReport` binds Capsule image/certificate/thaw/restore fingerprints into admission reports. Capsule is store-ready through object/dependency refs, but World still does not implement storage, network transport, schedulers, async runtimes, real model/tool/file/human integrations, provider lifecycle management, WASM host packages, Boundary loaded-module execution, package management, artifact registries, signing, encryption, or cryptographic security.

See `docs/capsules.md`.

## World Guest Conformance

Runspace makes execution local and deterministic. Guest Conformance proves that local execution can cross a runtime boundary.

`world.Guest.Core` wraps one manual-dispatch `Runspace` and exposes a byte-driven guest boundary: initialize, tick, read pending `Frame.Request` bytes, submit `Frame.Response` bytes, read result bytes, read receipt/transcript evidence where available, and read the last error. It does not call native handlers while parked, own storage, own transport, start scheduler threads, use wall-clock time, call TreatyResolver, call ProviderHarness, or dispatch by operation name.

`world.Guest.Abi` is World-owned ABI v1. Boundary remains target-neutral and does not define a WASM ABI. The ABI payloads are canonical World frame bytes; model/tool/file/human calls are represented as pending frames, not imported functions.

`world.Guest.NativeGuest` implements the same ABI shape in native Zig so default CI can prove native Runspace and guest-style byte driving match without a wasm runtime dependency.

`world.Guest.Wasm.inspect` validates wasm artifacts for required exports, memory/alloc convention, and forbidden imports. `zig build world-wasm` builds `world_wasm_guest_one_port.wasm`; `zig build check-world-wasm` builds and inspects it. Optional real wasm runtime execution can be added as an explicit step without changing the semantic boundary.

See `docs/guest.md`.

## Audit Reports

`world.AuditReport` includes the WorldSurface fingerprint, target certificate fingerprint, run mode, final status, request counts, fresh/replayed/rejected/failed counts, replay mismatches, missing handlers, and per-port counts.

## Examples

Run the examples with:

```sh
zig build run-world-strict
zig build run-world-ports
zig build run-world-replay-ports
zig build run-world-agent-loop
zig build run-world-frame-ports
zig build run-world-transcript-image-replay
zig build run-world-byte-adapter
zig build run-world-agent-timeline
zig build run-world-agent-branch
zig build run-world-environment-preflight
zig build run-world-handoff-parked
zig build run-world-handoff-replay
zig build run-world-handoff-verify
zig build run-world-agent-handoff
zig build run-world-admission-reference
zig build run-world-admission-full-module-inspect
zig build run-world-admission-parked-handoff
zig build run-world-admission-replay-verify
zig build run-world-admission-agent-transfer
zig build run-world-runspace-basic
zig build run-world-runspace-multi
zig build run-world-runspace-handoff
zig build run-world-runspace-agent
zig build run-world-runspace-supervised
zig build run-world-guest-one-port
zig build run-world-guest-conformance
zig build run-world-wasm-export-check
zig build run-world-guest-agent-conformance
zig build run-world-fabric-target-provider
zig build run-world-fabric-agent-tool
zig build run-world-fabric-nested
zig build run-world-fabric-supervised
zig build run-world-fabric-cycle-blocked
zig build run-world-linker-one-provider
zig build run-world-linker-agent-tool
zig build run-world-linker-nested-provider
zig build run-world-linker-ambiguity
zig build run-world-linker-cycle-blocked
zig build run-world-linker-guest-conformance
zig build run-world-capsule-linked-restore
zig build run-world-capsule-active-fabric
zig build run-world-capsule-agent-transfer
zig build run-world-capsule-relink-mismatch
zig build run-world-capsule-guest-verify
zig build run-world-capsule-supervised-restore
zig build run-world-supervised-budget
zig build run-world-supervised-agent
zig build run-world-supervised-handoff
zig build run-world-supervised-branch
zig build run-world-supervised-replay-verify
zig build world-wasm
zig build check-world-wasm
```

`world_run_strict` runs a strict closed zero-port target.

`world_run_ports` dispatches one residual WorldPort by dense `world_port_id`.

`world_replay_ports` records a fresh transcript and replays without fresh handler calls.

`world_runspace_basic` installs one machine run, parks on a mailbox request, responds manually, and completes.

`world_runspace_multi` installs two runs, parks both deterministically, resumes one while the other remains parked, then completes both.

`world_runspace_handoff` admits a parked transfer package, installs it into Runspace, exports the pending handoff image, and resumes through the existing Handoff path.

`world_runspace_agent` drives an agent-shaped run with manual model/tool mailbox responses.

`world_runspace_supervised` shows a supervised runspace run failing before over-budget handler dispatch.

`world_guest_one_port` drives a one-port target through NativeGuest ABI-style calls and prints request, response, and result fingerprints.

`world_guest_conformance` compares normal Runspace and NativeGuest for the one-port vector and prints a conformance report fingerprint.

`world_wasm_export_check` inspects the freestanding wasm guest artifact for ABI exports and forbidden imports.

`world_guest_agent_conformance` drives an agent-shaped target through model/tool pending frames using canonical response bytes.

`world_fabric_target_provider` routes a parent pending port to an explicit provider target route.

`world_fabric_agent_tool` routes an agent `tool.call` port through Fabric while the model port remains manually answered.

`world_fabric_nested` demonstrates a provider run that parks on its own nested WorldPort.

`world_fabric_supervised` shows Fabric invocation/provider/depth accounting under a permit.

`world_fabric_cycle_blocked` shows same-target cycle rejection before provider mutation.

`world_linker_one_provider` builds a closed catalog with one compatible provider, installs the synthesized assembly into Runspace, and completes without calling the native handler.

`world_linker_agent_tool` links an agent tool provider, routes `tool.call` through the synthesized Fabric plan, and leaves the model port as a residual Environment requirement.

`world_linker_nested_provider` installs root and nested linked assemblies and completes through a two-route provider chain.

`world_linker_ambiguity` shows strict ambiguity rejection and explicit-hint acceptance.

`world_linker_cycle_blocked` reports a LinkGraph cycle blocker before Runspace mutation.

`world_linker_guest_conformance` binds a linked assembly fingerprint to a Guest conformance report fingerprint.

`world_capsule_linked_restore` freezes a completed linked assembly capsule and thaws it into a fresh Runspace.

`world_capsule_active_fabric` freezes a witnessed active Fabric invocation while parent/provider runs are parked and reports parked restore as denied.

`world_capsule_agent_transfer` demonstrates agent-shaped capsule transfer with a residual external model import.

`world_capsule_relink_mismatch` shows local relink verification rejecting a catalog mismatch.

`world_capsule_guest_verify` carries a Guest conformance report through the inspect-only capsule thaw/restore report path.

`world_capsule_supervised_restore` shows sender permit evidence, receiver permit fingerprint recording, and fail-closed parked restore.

`world_agent_loop` demonstrates an agent-shaped residual surface with `model.decide` and `tool.call` ports. It is not an agent framework; it is a port dispatch and replay fixture.

`world_frame_ports` steps to a `Frame.Request`, resumes from a `Frame.Response`, and records frame fingerprints.

`world_admission_reference` admits a target-reference package against a local registry and runs the admitted target.

`world_admission_full_module_inspect` admits full Boundary module bytes for inspect-only admission and reports fail-closed loaded execution.

`world_admission_parked_handoff` admits a module-aware parked run with a receiver permit and resumes it through Handoff.

`world_admission_replay_verify` admits completed replay/verify packages and shows verify divergence on changed handler behavior.

`world_admission_agent_transfer` admits an agent-shaped transfer with model/tool imports, supervision, replay, and expected final output.

`world_transcript_image_replay` records a fresh transcript image, decodes it, and replays without native handler calls.

`world_byte_adapter` encodes request/response frames as canonical bytes through a fake byte host. It is not WASM and does not define a concrete ABI.

`world_agent_timeline` replays an agent-shaped transcript image without model/tool handler calls.

`world_agent_branch` records baseline and alternate agent transcripts from checkpoint metadata and shows different final results.

`world_environment_preflight` shows a missing fresh binding rejected while replay with a complete transcript image passes without a native handler.

`world_handoff_parked` packages a run parked on a port request, decodes it on the receiver side, validates the pending frame, and completes the run.

`world_handoff_replay` transfers a completed run image and replays it from a transcript image without calling a native fresh handler.

`world_handoff_verify` verifies a transferred transcript against matching local handlers and detects a changed handler.

`world_agent_handoff` packages an agent-shaped run image with checkpoint metadata and replays it on the receiver side.

`world_supervised_budget` runs under a one-call permit and then shows a zero-call permit denying execution before the handler call.

`world_supervised_agent` runs an agent-shaped target under per-run budgets and reports model/tool calls plus deterministic cost units.

`world_supervised_handoff` transfers a parked run, issues a stricter receiver permit, resumes, and receipts the receiver run.

`world_supervised_branch` records supervised checkpoint/branch usage and denies a second branch over budget.

`world_supervised_replay_verify` records a fresh receipt, replays under a replay-only permit without handlers, and detects verify divergence under a verify permit.

## Non-goals

World Supervision does not add storage, network transport, a scheduler, an async runtime, real model/tool/file/human integrations, provider lifecycle, service discovery, a WASM ABI, Boundary closure or normalization, billing, signing, encryption, or cryptographic security claims.

## Validation

Run the full local validation gate with:

```sh
zig build check --summary all
```

The `check` step runs unit tests, the forged-descriptor compile-fail fixture, all examples, formatting, and hot-path source guards.

## Non-Goals

World v0 does not implement a scheduler, async runtime, storage backend, network transport, provider lifecycle manager, service discovery, real model/tool/file/human integrations, WASI filesystem, Component Model/WIT bindings, security/signing/encryption, distributed execution, Boundary closure, Boundary normalization, treaty resolution, provider harness execution, provider catalog lookup, morphism catalog lookup, closure graph traversal, or evidence graph traversal.
