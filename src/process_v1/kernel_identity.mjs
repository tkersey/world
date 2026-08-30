/**
 * Exact public Boundary v1.7.0 Process kernel identity.
 *
 * This is a production admission constant, not a development default. The
 * acquisition check must keep it identical to conformance/boundary.lock.json
 * and boundary-process-kernel-v1.wasm.
 */
export const BOUNDARY_PROCESS_KERNEL_V1 = Object.freeze({
  boundaryVersion: "1.7.0",
  boundaryCommit: "4fd4cd959ea283a6b5af12a228f0d80a102683e3",
  abiVersion: 1,
  byteLength: 647473,
  sha256: "178f9c2fb79402a85ab5a7905586879347ad5c99f988127eec001c9ecfd813f0",
  importCount: 0,
  exportCount: 13,
  memoryInitialPages: 2457,
  memoryMaximumPages: 4096,
});
