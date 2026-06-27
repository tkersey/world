# World Security Model

World v0 is a deterministic runtime/deployment protocol, not a cryptographic
trust system.

Trusted:

- selected World runtime binary
- selected Boundary package
- selected World package
- receiver-local policy
- receiver-owned actuators and effects

Untrusted:

- Executable.Image bytes
- TurnInput bytes
- ResolutionInput bytes
- TurnClosure bytes
- Capsule bytes
- Continuity Bundle bytes
- Archive bytes
- host claim metadata
- sender permits and receipts as authority
- storage contents

Non-claims:

- fingerprints are not signatures
- receipts are not cryptographic attestations
- retention ack is not durability proof
- deterministic retry is not exactly-once
- Archive valid-prefix recovery is not malicious-tamper protection
- no confidentiality
- no authenticity
- no consensus
- no revocation
- no hostile-host protection

Threat handling:

- Malformed bytes: decoders reject before mutating Runspace, mailbox, provider,
  Capsule, Chronicle, or Archive state.
- Unsupported profiles: compatibility checks reject unknown required features
  and incompatible Boundary/World profile fingerprints.
- Replay divergence: replay and verify paths compare expected parent, request,
  response, receipt, and result identities and reject mismatches.
- Resource exhaustion: protocol manifests publish hard byte, count, depth, and
  memory budgets; decoders and release gates enforce the v0 baselines.
- Artifact confusion: release packages include byte lengths, SHA-256 checksums,
  manifest fingerprints, ABI export summaries, import counts, and memory bounds.
  SHA-256 is an artifact checksum, not a signature.
