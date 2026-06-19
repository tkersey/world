# World Archive

Archive is a portable format and replay model for committed Chronicle history and canonical Continuity objects. It is not a database.

Boundary owns the algebra. World owns canonical Archive semantics and bytes. Hosts retain and retrieve those bytes.

## Public Surface

`world.Archive` exposes format records (`Header`, `SegmentHeader`, `MomentData`, `Seal`), semantic records (`Moment`, `Snapshot`, `CommitRef`), byte I/O (`Reader`, `Writer`, `Image`, `AppendBatch`, `Memory`), reports (`ScanReport`, `ValidationReport`, `RecoveryReport`, `ReplayReport`, `Capabilities`, `SafetyReport`), and `Conformance`.

There is no storage-engine-specific public API.

## Format

Every Archive starts with one immutable `Archive.Header` at byte offset zero. Header bytes carry fixed magic, explicit format/fingerprint versions, the canonical byte-order marker, compatible Chronicle and ObjectEnvelope versions, genesis cursor fingerprint, feature flags, profile fingerprint, and header fingerprint. Header identity excludes paths, host identifiers, database identifiers, wall-clock time, credentials, authority tokens, and host handles.

Committed history is framed as length-prefixed segments. V1 segment kinds are `moment_data`, `moment_seal`, and `optional_extension`. Segment headers bind segment kind, required/optional status, sequence number, payload byte length, payload fingerprint, and segment-header fingerprint.

## Commit Visibility

One committed Chronicle transaction produces one `Archive.Moment`.

An Archive moment is committed only when a complete `MomentData` segment is immediately followed by a matching valid `Seal` segment. Partial moment data, missing seals, partial seals, malformed seals, and seals for a different moment are not committed. Recovery always returns the longest valid sealed prefix.

`Archive.Moment` fingerprints bind semantic World fields and exclude byte offsets, storage identity, database cursors, file paths, allocator state, runtime pointers, and host handles. Segment payload fingerprints bind exact encoded payload bytes.

## Snapshots And Replay

`Archive.Image` is the decoded committed prefix. `Archive.Snapshot` is an immutable view at one moment in that prefix. Snapshots can read committed objects and replay projections bound to their source Chronicle cursor.

Archive does not duplicate Chronicle projection authority. Snapshot projection and replay materialize read-only Continuity state from sealed bytes and call Chronicle/Continuity owner APIs.

## Memory Byte Store

`Archive.Memory` is the in-process reference byte store. It keeps canonical Archive bytes in memory, supports append, historical snapshots, valid-prefix recovery, and simulated reopen by byte clone.

Its capabilities are honest: memory-only, not durable across process boundaries unless a host retains the bytes, wasm-memory compatible, and not a WASM filesystem.

## Host Boundary

World defines the bytes. Hosts decide where those bytes live: native files, browser storage, WASI storage, object storage, databases, or other retention mechanisms can be built outside World as adapters that depend on World.

World does not define fsync, locking, mmap, compaction scheduling, multi-writer coordination, network transport, signing, encryption, or storage-engine page layout.
