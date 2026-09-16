// External schema/value rules retained from the qualified value codec.
import { Reader, MAX_U64, UTF8 as decoder } from "./wire.mjs";
export function decodeSchema(bytes) {
  const reader = new Reader(bytes);
  bytes = reader.bytes;
  if (reader.natural() !== 0n) throw new Error("NonCanonical");
  const count = reader.natural();
  if (count === 0n || count > BigInt(bytes.length - reader.position)) throw new Error("InvalidSchema");
  const index = () => {
    const id = reader.natural();
    if (id >= count) throw new Error("InvalidSchema");
    return Number(id);
  };
  const types = [];
  for (let i = 0; i < Number(count); i++) {
    const tag = Number(reader.natural());
    const type = { tag, children: [], minimum: MAX_U64 };
    if (tag <= 11) type.minimum = BigInt([0, 1, 1, 2, 4, 8, 1, 2, 4, 8, 1, 1][tag]);
    else if (tag === 12 || tag === 13) {
      const length = reader.natural();
      if (length > BigInt(bytes.length - reader.position) || (tag === 13 && length === 0n)) throw new Error("InvalidSchema");
      for (let j = 0; j < Number(length); j++) type.children.push(index());
    } else if (tag === 14 || tag === 15 || tag === 17) {
      type.children.push(index());
      if (tag === 15) type.maximum = reader.natural();
      if (tag === 17) type.length = reader.natural();
      else type.minimum = 1n;
    } else if (tag === 18 || tag === 19) {
      type.maximum = reader.natural();
      type.minimum = 1n;
    } else if (tag === 20) {
      const length = reader.natural();
      if (length > BigInt(bytes.length - reader.position)) throw new Error("InvalidSchema");
      type.members = [];
      for (let j = 0; j < Number(length); j++) {
        const value = reader.natural();
        if (value > 0xffffffffn || (j > 0 && type.members[j - 1] >= value)) throw new Error("InvalidSchema");
        type.members.push(value);
      }
      type.minimum = 4n;
    } else throw new Error("InvalidSchema");
    types.push(type);
  }
  reader.finish();
  let changed = true;
  while (changed) {
    changed = false;
    for (const type of types) {
      const minimum = type.tag === 12 ? type.children.reduce((sum, id) => sum + types[id].minimum, 0n)
        : type.tag === 13 ? 1n + type.children.reduce((min, id) => types[id].minimum < min ? types[id].minimum : min, MAX_U64)
        : type.tag === 17 ? type.length * types[type.children[0]].minimum : type.minimum;
      if (minimum < type.minimum) { type.minimum = minimum; changed = true; }
    }
  }
  if (types.some((type) => type.minimum === MAX_U64)) throw new Error("InvalidSchema");
  let classes = types.map(() => 0);
  while (true) {
    const representatives = new Map();
    const next = types.map((type, i) => {
      const key = [type.tag, String(type.maximum ?? ""), String(type.length ?? ""), String(type.members ?? ""), ...type.children.map((id) => classes[id])].join(":");
      if (!representatives.has(key)) representatives.set(key, i);
      return representatives.get(key);
    });
    if (next.every((value, i) => value === classes[i])) break;
    classes = next;
  }
  if (new Set(classes).size !== types.length) throw new Error("NonCanonical");
  const pending = [0], seen = new Set();
  while (pending.length) {
    const id = pending.pop();
    if (seen.has(id)) continue;
    if (id !== seen.size) throw new Error("NonCanonical");
    seen.add(id);
    for (let i = types[id].children.length - 1; i >= 0; i--) pending.push(types[id].children[i]);
  }
  if (seen.size !== types.length) throw new Error("NonCanonical");
  return types;
}

export function validateValue(schema, bytes) {
  const types = decodeSchema(schema);
  const reader = new Reader(bytes);
  bytes = reader.bytes;
  const pending = [[0, 1n]];
  while (pending.length) {
    const [id, count] = pending.pop();
    const type = types[id];
    if (count === 0n || type.minimum === 0n) continue;
    if (count > BigInt(bytes.length - reader.position) / type.minimum) throw new Error("InvalidValue");
    if (count > 1n) pending.push([id, count - 1n]);
    if (type.tag <= 9) {
      const scalar = reader.take(Number(type.minimum));
      if (type.tag === 1 && scalar[0] > 1) throw new Error("InvalidValue");
    } else if (type.tag === 10 || type.tag === 11 || type.tag === 18 || type.tag === 19) {
      const value = reader.field();
      if (type.maximum !== undefined && BigInt(value.length) > type.maximum) throw new Error("InvalidValue");
      if (type.tag === 11 || type.tag === 19) decoder.decode(value);
    } else if (type.tag === 12) {
      for (let i = type.children.length - 1; i >= 0; i--) pending.push([type.children[i], 1n]);
    } else if (type.tag === 13) {
      const tag = reader.natural();
      if (tag >= BigInt(type.children.length)) throw new Error("InvalidValue");
      pending.push([type.children[Number(tag)], 1n]);
    } else if (type.tag === 17) {
      pending.push([type.children[0], type.length]);
    } else if (type.tag === 20) {
      const value = reader.take(4);
      const tag = BigInt(new DataView(value.buffer, value.byteOffset, 4).getUint32(0, true));
      if (!type.members.includes(tag)) throw new Error("InvalidValue");
    } else {
      const count = reader.natural();
      if (type.maximum !== undefined && count > type.maximum) throw new Error("InvalidValue");
      pending.push([type.children[0], count]);
    }
  }
  reader.finish();
}
