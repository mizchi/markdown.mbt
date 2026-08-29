import { describe, expect, it } from "vitest";

import type { FolddownNode } from "../../js/api.js";
import { viewerNodesFromManifest } from "./from-mdx.js";

const declaration: FolddownNode = {
  id: "moonbit.intro",
  kind: "concept",
  level: "intro",
  locale: "en",
  requires: [],
  roles: [],
  goals: [],
  evidence: [],
  familiarTo: [],
  body: "## Where MoonBit fits\n\nMoonBit targets WebAssembly.",
};

describe("Folddown MDX adapter", () => {
  it("uses the first child heading as the viewer title", () => {
    expect(viewerNodesFromManifest([declaration])).toEqual([
      {
        ...declaration,
        title: "Where MoonBit fits",
        body: "MoonBit targets WebAssembly.",
      },
    ]);
  });
});
