import { Reader, UTF8, body, frame, field, concat, natural, copyBytes, digest, same } from "./wire.mjs";
import { decodeSchema, validateValue } from "./values.mjs";
export { validateValue } from "./values.mjs";
const encoder = new TextEncoder();
const empty = new Uint8Array();
export function encodeInput({ image, initialArgs, state, control = "none", value = empty, quantum = null }) {
  image = copyBytes(image);
  body("ABL_BPI3", image);
  if ((initialArgs === undefined) === (state === undefined)) throw new TypeError("supply initialArgs or state");
  const instance = state === undefined ? concat(natural(0), field(copyBytes(initialArgs))) : concat(natural(1), field(copyBytes(state)));
  if (state !== undefined) body("ABL_PST3", state);
  const tags = { none: 0, reply: 1, resume_yield: 2, cancel_text: 3, cancel_bytes: 3 };
  if (typeof control !== "string" || !Object.hasOwn(tags, control)) throw new TypeError("unknown control");
  if (state === undefined && (control === "reply" || control === "resume_yield")) throw new Error("InvalidControl");
  value = typeof value === "string" ? encoder.encode(value) : copyBytes(value);
  if ((control === "none" || control === "resume_yield") && value.length !== 0) throw new Error("InvalidControl");
  if (control === "cancel_text") UTF8.decode(value);
  const payload = control === "none" || control === "resume_yield" ? empty : control === "reply" ? field(value) : concat(natural(control === "cancel_text" ? 0 : 1), field(value));
  return frame("ABL_PKI3", concat(field(image), instance, natural(tags[control]), payload, quantum === null ? natural(0) : concat(natural(1), natural(quantum))));
}
function reason(reader) {
  const tag = reader.natural(), bytes = reader.field();
  if (tag === 0n) return { kind: "text", value: UTF8.decode(bytes) };
  if (tag === 1n) return { kind: "bytes", value: bytes };
  throw new Error("InvalidTag");
}
function failures(bytes) {
  const reader = new Reader(bytes), count = reader.natural(), result = [];
  if (count > BigInt(reader.bytes.length - reader.position)) throw new Error("Truncated");
  for (let i = 0n; i < count; i++) result.push(reader.field());
  reader.finish(); return result;
}
export function decodeOutcome(bytes) {
  const reader = new Reader(body("ABL_PKO3", bytes));
  const tag = reader.natural();
  let result;
  const checkpoint = () => reader.optional(() => { const state = reader.field(); body("ABL_PST3", state); return state; });
  switch (tag) {
    case 0n: result = { kind: "progressed", state: checkpoint() }; break;
    case 1n: result = { kind: "requested", state: checkpoint(), request: reader.field() }; body("ABL_ERQ3", result.request); break;
    case 2n: result = { kind: "yielded", state: checkpoint() }; break;
    case 3n: result = { kind: "completed", value: reader.field() }; break;
    case 4n: result = { kind: "failed", value: reader.field(), cleanupFailures: failures(reader.field()), cancellation: reader.optional(() => reason(reader)) }; break;
    case 5n: result = { kind: "cancelled", reason: reason(reader), cleanupFailures: failures(reader.field()) }; break;
    case 6n: {
      const arenas = ["input", "working", "output", "memory"], id = reader.natural();
      if (id > 3n) throw new Error("InvalidTag");
      result = { kind: "needs_capacity", arena: arenas[Number(id)] };
      for (const key of ["input", "working", "output", "memoryPages"]) {
        const bytes = reader.natural(), provenance = reader.natural();
        if (provenance > 2n || (provenance === 0n && bytes !== 0n)) throw new Error("InvalidOutcome");
        result[key] = { bytes, provenance: ["not_observed", "exact", "lower_bound"][Number(provenance)] };
      }
      break;
    }
    default: throw new Error("InvalidTag");
  }
  reader.finish(); return result;
}
export async function decodeRequest(bytes) {
  const encoded = body("ABL_ERQ3", bytes), reader = new Reader(encoded);
  const result = { programIdentity: reader.take(32), pendingStateDigest: reader.take(32), effect: reader.natural(),
    semanticIdentityBytes: reader.field(), payloadSchema: reader.field(), resumeSchema: reader.field(), payload: reader.field() };
  const bindingLength = reader.position;
  result.requestIdentity = reader.take(32); reader.finish();
  result.semanticIdentity = UTF8.decode(result.semanticIdentityBytes);
  if (!result.semanticIdentityBytes.length) throw new Error("InvalidRequest");
  const expected = await digest(concat(encoder.encode("boundary.effect-request/v3\0"), encoded.subarray(0, bindingLength)));
  if (!same(expected, result.requestIdentity)) throw new Error("InvalidRequest");
  validateValue(result.payloadSchema, result.payload); decodeSchema(result.resumeSchema);
  return result;
}
export async function encodeResult(requestBytes, value) {
  value = copyBytes(value);
  const request = await decodeRequest(requestBytes);
  validateValue(request.resumeSchema, value);
  return frame("ABL_ERS3", concat(request.requestIdentity, field(value)));
}
