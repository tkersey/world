import identityRecord from "./kernel_identity.json" with { type: "json" };

const IDENTITY_FIELDS = Object.freeze([
  "abiVersion",
  "boundaryCommit",
  "boundaryVersion",
  "byteLength",
  "exportCount",
  "importCount",
  "memoryInitialPages",
  "memoryMaximumPages",
  "sha256",
]);

function requireIdentity(condition, message) {
  if (!condition) throw new Error(message);
}

/** Decode the exact inert Boundary Process kernel identity record. */
export function parseBoundaryProcessKernelIdentityV1(bytes) {
  requireIdentity(bytes instanceof Uint8Array, "runtime kernel identity must be bytes");
  return validateBoundaryProcessKernelIdentityV1(
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
  );
}

export function validateBoundaryProcessKernelIdentityV1(identity) {
  requireIdentity(identity !== null && typeof identity === "object" && !Array.isArray(identity), "runtime kernel identity must be an object");
  requireIdentity(JSON.stringify(Object.keys(identity).sort()) === JSON.stringify(IDENTITY_FIELDS), "runtime kernel identity fields are not exact");
  requireIdentity(/^\d+\.\d+\.\d+$/.test(identity.boundaryVersion), "runtime Boundary version is invalid");
  requireIdentity(/^[0-9a-f]{40}$/.test(identity.boundaryCommit), "runtime Boundary commit is invalid");
  requireIdentity(/^[0-9a-f]{64}$/.test(identity.sha256), "runtime kernel digest is invalid");
  for (const field of ["abiVersion", "byteLength", "importCount", "exportCount", "memoryInitialPages", "memoryMaximumPages"]) {
    requireIdentity(Number.isSafeInteger(identity[field]) && identity[field] >= 0, `runtime kernel ${field} is invalid`);
  }
  requireIdentity(identity.abiVersion === 1, "runtime kernel ABI version is not supported");
  return Object.freeze(identity);
}

/** Exact minimized Boundary v1.8.1 released Process kernel identity. */
export const BOUNDARY_PROCESS_KERNEL_V1 = validateBoundaryProcessKernelIdentityV1(identityRecord);
