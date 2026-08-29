import { describe, expect, it } from "vitest";

import {
  createFolddownDriftPacket,
  validateFolddownDriftReview,
} from "./drift-packet.js";

const graph = {
  entry: "docs/root.mdx",
  source: "expanded source",
  documents: [
    {
      path: "docs/fragments/overview.ja.mdx",
      source:
        '<Fold id="overview.ja" kind="concept" level="intro" locale="ja">\n## 概要\n\n本文。\n</Fold>',
    },
    {
      path: "docs/fragments/overview.en.mdx",
      source:
        '<Fold id="overview.en" kind="concept" level="intro" locale="en">\n## Overview\n\nBody.\n</Fold>',
    },
  ],
  edges: [
    {
      from: "docs/root.mdx",
      to: "docs/fragments/overview.ja.mdx",
      src: "./fragments/overview.ja.mdx",
      sync: "overview",
    },
    {
      from: "docs/root.mdx",
      to: "docs/fragments/overview.en.mdx",
      src: "./fragments/overview.en.mdx",
      sync: "overview",
    },
  ],
};

describe("Folddown drift review packet", () => {
  it("groups externally included documents by their explicit sync key", () => {
    const packet = createFolddownDriftPacket(graph);

    expect(packet.comparisonGroups).toEqual([
      {
        sync: "overview",
        documents: ["docs/fragments/overview.ja.mdx", "docs/fragments/overview.en.mdx"],
      },
    ]);
    expect(packet.documents[0]).toMatchObject({
      path: "docs/fragments/overview.ja.mdx",
      folds: [{ id: "overview.ja", title: "概要" }],
    });
  });

  it("accepts one evidence-backed verdict for every comparison group", () => {
    const packet = createFolddownDriftPacket(graph);
    const review = validateFolddownDriftReview(packet, {
      version: "folddown-drift/v1",
      findings: [
        {
          sync: "overview",
          verdict: "aligned",
          summary: "Both documents introduce the same topic.",
          evidence: [
            { path: "docs/fragments/overview.ja.mdx", foldIds: ["overview.ja"] },
            { path: "docs/fragments/overview.en.mdx", foldIds: ["overview.en"] },
          ],
        },
      ],
    });

    expect(review.findings[0]?.verdict).toBe("aligned");
    expect(() => validateFolddownDriftReview(packet, { version: "folddown-drift/v1", findings: [] })).toThrow(
      "exactly one finding",
    );
  });
});
