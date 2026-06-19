# World Portable Archive Format v1 Plan

## Summary
Implement World Archive as a canonical append-only byte format and replay model. Remove all xitdb coupling, replace the database-shaped backend interface with sealed Archive bytes, recover by longest valid sealed prefix, and prove native/WASM validation parity over shared fixtures.

Primary invariant: the longest valid sealed byte prefix determines Archive history; host storage, byte offsets, database cursors, and unsealed tail bytes never define World semantics.

## Implementation Brief
1. step=xitdb_excision; owner=implementation; success_criteria=remove xitdb from build.zig.zon, build.zig, src, tests, examples, docs, and README/public guidance; grep guard finds no xitdb/world-xitdb/world_xitdb/Archive.Xitdb storage-engine public API in guarded paths.
2. step=owner_codecs_and_format_types; owner=implementation; success_criteria=add Archive v1 constants, Header, SegmentKind, SegmentHeader, MomentData, Seal, AppendBatch, Image, Reader, Writer, Scan/Validation/Recovery/Replay reports, Limits, and minimal owner-codec helpers for Chronicle/Continuity canonical bytes.
3. step=byte_memory_and_append_recovery; owner=implementation; success_criteria=Archive.Memory is byte-backed, Writer appends MomentData then Seal, Reader validates header/segments and recovers the latest valid sealed prefix under truncation/corruption.
4. step=snapshot_replay_bundle; owner=implementation; success_criteria=Snapshot is immutable and materialized from Image prefix; projections/idempotency rebuild through Chronicle/Continuity owner APIs; bundle import/export remains all-or-nothing across byte clone/reopen.
5. step=native_wasm_equivalence_and_docs; owner=implementation; success_criteria=shared fixture corpus has stable expected fingerprints; native and WASM checks validate identical Archive bytes; docs/README state Archive is a format and replay model, not a database.
6. step=proof_closeout_ship; owner=verification; success_criteria=run archive-focused tests, xitdb guard, fmt/diff/build/check/wasm/lint gates, inspect diff, assert st projection, update existing PR #14 without creating a new PR.

## Required Proof
- rg guard for xitdb/world-xitdb/world_xitdb/Archive.Xitdb/@import("xitdb") in build.zig, build.zig.zon, src, test, examples, docs, README.md.
- zig build test --summary all -- --test-filter archive
- zig build check --summary all
- zig build check-world-wasm --summary all
- zig fmt --check build.zig src examples test
- git diff --check
- zig build lint -- --max-warnings 0
