# World Compatibility Policy

World v0 compatibility is defined by `world.Protocol.Manifest`, the v0
conformance corpus, the universal WASM ABI, and release receipts produced by
the build gates. Human-readable manifests and docs are diagnostic; they do not
override canonical protocol bytes.

Patch releases may fix validators, reject malformed inputs that should always
have been invalid, improve performance, and add diagnostics. They must preserve
valid v0 encodings, fingerprints, ABI exports, and release-corpus expectations.

Minor releases may add optional features and new format versions. They must not
silently change existing format versions, enum ordinals, canonical field order,
or fingerprint domains.

Major releases may intentionally break compatibility when the break is explicit
in the protocol manifest, release notes, and conformance corpus.

Hard rules:

- Enum ordinal changes require a format or ABI version bump.
- Canonical field-order changes require a format version bump.
- Fingerprint-domain changes require a fingerprint-version bump.
- ABI export signature changes require an ABI-version bump.
- Boundary dependency upgrades require World compatibility proof.
- Retained old corpora remain compatibility CI inputs.
