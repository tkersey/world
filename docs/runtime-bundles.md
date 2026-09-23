# Qualified runtime bundles

Use Node 26.9.0, Zig 0.16.0, npm, uv, Git and tar on the producer. Browser
qualification needs Chromium and Firefox and their OS dependencies. The producer
installs the repository-locked browser tooling; on Linux first run its Playwright
`install-deps chromium firefox` command. Wasmtime uses the existing uv lock.

From a clean, committed World checkout:

```sh
node bin/world.mjs runtime prepare --source "$PWD" --output /absolute/new/bundle
```

This builds through the normal Boundary-data lock in a fresh Zig package cache,
runs the existing aggregate and delivered-byte checks, and publishes `bundle`,
`bundle.tar.gz`, and `bundle.delivery.json`. Existing destinations fail without
overlay. Preparation and acquisition share one destination reservation, so neither
can publish into a destination owned by the other. An interrupted preparation keeps its `.preparing` directory and check
logs; choose a new destination after resolving the reported failure. No incomplete
directory is a qualified artifact. Preparation can take several minutes.

Source cleanliness is checked when selecting the snapshot. Commit, tree and lock
are bound to that one immutable Git commit, and all build/check inputs come from
its export. Later checkout changes do not retarget the build. Output may be inside
the checkout; unignored published output will then appear in `git status`. Prefer
an outside or ignored output location when keeping the checkout clean matters.

Obtain the archive and **expected** archive/manifest hashes from the selected
producer's external delivery record. From an already trusted source checkout:

```sh
node bin/world.mjs runtime acquire --archive /downloads/bundle.tar.gz \
  --archive-sha256 EXPECTED_ARCHIVE_HEX --manifest-sha256 EXPECTED_MANIFEST_HEX \
  --output '/new/consumer bundle'
node '/new/consumer bundle/runtime/bin/world.mjs' runtime verify \
  --root '/new/consumer bundle' --manifest-sha256 EXPECTED_MANIFEST_HEX --smoke
```

Acquisition checks the transport hash before safely extracting the bounded USTAR
profile and verifies the entire inventory before running any acquired code.
The installed verifier needs only Node and its bundle. It does not compile,
fetch, search caches, or use credentials. Static integrity and execution smoke
are separate checks. Smoke executes a pure result and transfers an actual
resource request checkpoint between fresh processes, binding replies to the
restored request. Its expectations come from the existing native fixtures.

The manifest binds source/tree, locked data dependency, package version, actual
kernel profile, file inventory and required qualification. The manifest does not
hash itself; the delivery descriptor binds it and the finalized archive. Paths
are locators: moving a complete bundle preserves validity. Archive bytes from two
hosts need not match; select and retain one qualified artifact for consumers.

Qualification records each command and outcome. The full existing source and
transfer suites use their established explicit limits; the portable smoke uses
default input/working/output budgets 65536/1048576/65536. Runtime limits do not
change the compiled ReleaseSmall kernel, 65536-byte stack or 256 MiB maximum.
No claim is made for untested platform/fixture combinations.

The `Qualified runtime bundle` Actions workflow invokes this same producer and
uploads the archive and external descriptor for its exact commit. Retrieve with:

```sh
gh run download RUN_ID --repo tkersey/world --name world-runtime-SOURCE_COMMIT \
  --dir /new/download
```

GitHub access and artifact retention apply (the workflow requests 30 days).
Record the actual run/artifact/expiry and preserve a verified durable local copy.
This is a non-release artifact, not a permanent release URL. Expiry never permits
silently replacing a pinned runtime with a newer build.
