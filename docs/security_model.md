# Security model

World's trust boundary is deliberately narrow. Boundary owns Process semantics.
World authenticates the fixed Boundary 1.8.0 candidate kernel, admits its WebAssembly
shape, creates a fresh instance for one reduction, validates host-facing record
framing and memory ranges, and copies bytes across the embedding boundary.

The kernel is executable trusted runtime material identified by an exact
SHA-256 digest. The digest identifies bytes; it is not a signature or a general
supply-chain trust decision. Release provenance and the locked source/kernel
tuple provide the surrounding authentication policy.

World treats these inputs and outputs as untrusted opaque bytes:

- BPI1 images and `ABL_PST1` state;
- effect payloads and typed resume values;
- completed Result and authored Failure values.

World does not duplicate their semantic validation. It strictly validates only
`ABL_PKO1`, `ABL_ERQ1`, and `ABL_ERS1` framing needed by the host boundary. A
fresh instance prevents mutable guest state from crossing reductions or being
shared by concurrent calls. It does not make external effects exactly-once.

Effect resolution remains environmental authority. World provides no
capability registry, provider adapter, credential store, scheduler, effect
journal, persistence, retry, replay, branching, or cancellation policy. A
caller may decline to construct an EffectResult and leave a process pending.

The CLI's descriptor and generation checks protect one coherent snapshot of
ordinary local regular files. They do not protect against a hostile filesystem,
host kernel, or embedding caller. World also makes no browser-runtime,
confidentiality, multi-tenant isolation, or denial-of-service guarantee.

`WorldProcessHostError` reports a stable `WORLD_*` code and bounded metadata
such as an artifact label, byte length, digest, or outcome kind. Diagnostics do
not dump BPI1, State, effect payload, resume, Result, Failure, or raw kernel
diagnostic bytes.
