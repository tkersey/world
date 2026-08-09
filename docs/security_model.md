# Security model

World is a deterministic compiler and protocol boundary, not a cryptographic
trust system. The selected World and Boundary packages, world-host, and
receiver-local policy are trusted. Application artifacts, Frames, step inputs,
effect results, host claims, and storage bytes are validated at their owning
boundary.

Checksums and identities prevent accidental artifact confusion; they are not
signatures. Deterministic retry is not exactly-once execution. World claims no
confidentiality, authenticity, consensus, revocation, or hostile-host
protection.
