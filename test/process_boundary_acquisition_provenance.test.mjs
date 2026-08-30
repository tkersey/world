import { describe, expect, test } from "bun:test";

import { classifyLocalBoundaryAssetProvenance } from "../scripts/acquire_boundary_process_assets.mjs";

describe("Boundary development asset provenance", () => {
  test("does not claim that an authenticated checkout asset was emitted by that checkout", () => {
    expect(classifyLocalBoundaryAssetProvenance(null)).toBe("local-kernel-override");
    expect(classifyLocalBoundaryAssetProvenance("/exact-boundary-checkout")).toBe("local-checkout-asset");
  });
});
