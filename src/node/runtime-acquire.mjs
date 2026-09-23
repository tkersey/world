import { gunzipSync } from "node:zlib";
import { mkdir, writeFile, rename, rm, chmod } from "node:fs/promises";
import { join, dirname, resolve } from "node:path";
import { reserveOutput } from "./runtime-output.mjs";
import { readBounded, sha256, reject, verifyInventory } from "./runtime-bundle.mjs";

// Deliberately accepts only the regular-file/directory USTAR profile produced here.
export function unpackArchive(bytes) {
  const tar = gunzipSync(bytes, { maxOutputLength: 128 << 20 });
  const files = [], names = new Set();
  const string = bytes => new TextDecoder("utf-8", { fatal: true }).decode(bytes).split("\0")[0];
  const octal = bytes => {
    const value = string(bytes).trim();
    if (!/^[0-7]+$/.test(value)) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "invalid tar number");
    return parseInt(value, 8);
  };
  let offset = 0;
  while (offset + 512 <= tar.length) {
    const header = tar.subarray(offset, offset + 512); offset += 512;
    if (header.every(byte => byte === 0)) {
      if (tar.subarray(offset).some(byte => byte !== 0)) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "trailing tar content");
      return files;
    }
    let checksum = 0;
    for (let i = 0; i < 512; i++) checksum += i >= 148 && i < 156 ? 32 : header[i];
    if (checksum !== octal(header.subarray(148, 156))) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "tar checksum mismatch");
    if (!string(header.subarray(257, 263)).startsWith("ustar")) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "USTAR required");
    const prefix = string(header.subarray(345, 500));
    let path = (prefix ? prefix + "/" : "") + string(header.subarray(0, 100));
    path = path.replace(/^\.\//, "").replace(/\/$/, "");
    const type = header[156], size = octal(header.subarray(124, 136));
    if (![0, 48, 53].includes(type) || size > (64 << 20) || offset + size > tar.length)
      reject("WORLD_BUNDLE_ARCHIVE_INVALID", "unsupported tar entry");
    if (path === "." || path === "") {
      if (type !== 53 || size !== 0) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "invalid root entry");
    } else {
      if (!/^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(path) ||
          path.split("/").some(p => p === "." || p === "..") || names.has(path) || names.size >= 1024)
        reject("WORLD_BUNDLE_ARCHIVE_INVALID", "unsafe or duplicate tar path");
      names.add(path);
      if (type === 53) {
        if (size !== 0) reject("WORLD_BUNDLE_ARCHIVE_INVALID", "nonempty tar directory");
      } else {
        // Preserve executable intent without admitting setuid, setgid or writable shared files.
        const mode = octal(header.subarray(100, 108)) & 0o111 ? 0o755 : 0o644;
        files.push({ path, bytes: tar.subarray(offset, offset + size), mode });
      }
    }
    offset += Math.ceil(size / 512) * 512;
  }
  reject("WORLD_BUNDLE_ARCHIVE_INVALID", "truncated tar archive");
}
export async function acquireBundle(archive, expectedArchive, expectedManifest, output) {
  if (!/^[a-f0-9]{64}$/.test(expectedArchive ?? "")) reject("WORLD_BUNDLE_IDENTITY_INVALID", "expected archive SHA-256 required");
  const bytes = await readBounded(archive);
  if (sha256(bytes) !== expectedArchive) reject("WORLD_BUNDLE_IDENTITY_INVALID", "downloaded archive digest mismatch");
  const files = unpackArchive(bytes); // Validate all entries before creating anything.
  output = resolve(output);
  const stage = await reserveOutput(output);
  try {
    for (const file of files) {
      await mkdir(dirname(join(stage, file.path)), { recursive: true });
      await writeFile(join(stage, file.path), file.bytes, { flag: "wx" });
      await chmod(join(stage, file.path), file.mode);
    }
    await verifyInventory(stage, expectedManifest);
    await rename(stage, output);
  } catch (error) { await rm(stage, { recursive: true, force: true }); throw error; }
  return { bundle: output, archiveSha256: expectedArchive, manifestSha256: expectedManifest };
}
