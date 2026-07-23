# World Comptime v1 Cutover

Status: normative release policy.

## Release order

```text
World protocol/API specification
-> Boundary StaticMachine reviewed tag
-> World comptime application closure
-> application-specific WASM
-> world-host and world-capabilities v1 support
-> Agent Runtime v1 pack
-> release candidate
-> cutover
-> retirement
```

World may use an exact Boundary commit during development. Final World review begins only after Boundary has a reviewed release tag. Downstream release artifacts pin reviewed identities rather than floating branches.

## Cutover gates

Cutover requires:

- Boundary Program.Session/StaticMachine parity for the supported matrix;
- compile-time missing, ambiguous, incompatible, cyclic, and excessive-depth handler rejection;
- exact residual effect rows;
- standalone skeleton and fixture application WASM artifacts;
- zero imports and bounded memory;
- fresh-instance continuation;
- the six v0/v1 behavioral oracle scenarios;
- byte-identical v1 retry;
- replay without a fresh covered effect;
- migration with receiver-local policy preflight;
- branching from one parent;
- world-host crash recovery around result, Frame, and head persistence;
- capability policy, approval, secret, target, and idempotency checks before effect;
- a source-free Agent Runtime v1 conformance pack;
- sequential final review of Boundary, World, world-capabilities, and world-host with no unresolved correctness findings.

## Compatibility

v0 is feature-frozen except for correctness, release, and compatibility fixes. Existing v0 runs finish on v0 or restart from application-level input on v1. There is no TurnClosure/Capsule-to-Frame state translator.

World Comptime v1 becomes the default for new applications at `v1.0.0-rc.1` acceptance. The universal runtime remains an explicit legacy/dynamic profile. The planned `v1.1.0` retirement removes v0 from default world-host commands and stops generating new v0 Agent Runtime packs while preserving tags, selected oracle fixtures, and bounded legacy access.

## Review policy

Implementation completes before final repository closeout. Final review covers one repository at a time in dependency order. Each repository uses five standard reviews plus four auxiliary reviews, with a 45-minute maximum wait and per-review completion reporting. If a finding is accepted, all already-active reviews may finish; accepted liabilities are repaired together, pushed once, and the full review tuple restarts on the new head.
