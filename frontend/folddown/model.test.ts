import { describe, expect, it } from "vitest";

import {
  createInitialCollapsedState,
  selectNodesForReader,
  shouldCollapseForReaderProfile,
  type FoldNode,
} from "./model.js";

const nodes: FoldNode[] = [
  {
    id: "auth.password",
    kind: "concept",
    level: "intro",
    title: "Password authentication",
    body: "A password proves possession of a shared secret.",
  },
  {
    id: "auth.mfa",
    kind: "procedure",
    level: "basic",
    title: "Register MFA",
    body: "Register an authenticator and store recovery codes.",
  },
  {
    id: "auth.passkeys",
    kind: "reference",
    level: "advanced",
    title: "Passkey deployment notes",
    body: "Plan recovery and device migration before rollout.",
  },
];

describe("Folddown reader profiles", () => {
  it("keeps every node open for a first-time profile", () => {
    expect(shouldCollapseForReaderProfile("intro", { id: "first", collapseLevels: [] })).toBe(false);
    expect(shouldCollapseForReaderProfile("advanced", { id: "first", collapseLevels: [] })).toBe(false);
  });

  it("uses the frontmatter profile's explicit collapsed levels", () => {
    const someKnowledge = { id: "some", collapseLevels: ["intro"] as const };
    expect(shouldCollapseForReaderProfile("intro", someKnowledge)).toBe(true);
    expect(shouldCollapseForReaderProfile("basic", someKnowledge)).toBe(false);
    expect(shouldCollapseForReaderProfile("advanced", someKnowledge)).toBe(false);
  });

  it("derives a stable initial collapsed state from a reader profile", () => {
    expect(createInitialCollapsedState(nodes, { id: "some", collapseLevels: ["intro"] })).toEqual({
      "auth.password": true,
      "auth.mfa": false,
      "auth.passkeys": false,
    });
  });

  it("keeps shared material and selects locale and role-specific material", () => {
    const localizedNodes: FoldNode[] = [
      { ...nodes[0]!, id: "shared.ja", locale: "ja" },
      { ...nodes[0]!, id: "typescript.ja", locale: "ja", roles: ["typescript-programmer"] },
      { ...nodes[0]!, id: "rust.ja", locale: "ja", roles: ["rust-programmer"] },
      { ...nodes[0]!, id: "shared-empty.ja", locale: "ja", roles: [] },
      { ...nodes[0]!, id: "shared.en", locale: "en" },
    ];

    expect(
      selectNodesForReader(localizedNodes, {
        locale: "ja",
        roles: ["typescript-programmer"],
      }).map((node) => node.id),
    ).toEqual(["shared.ja", "typescript.ja", "shared-empty.ja"]);
  });

  it("omits only source-language-familiar material in the interesting view", () => {
    const classifiedNodes: FoldNode[] = [
      { ...nodes[0]!, id: "shared", familiarTo: ["typescript-programmer", "rust-programmer"] },
      { ...nodes[1]!, id: "moonbit-specific" },
      { ...nodes[2]!, id: "rust-only", familiarTo: ["rust-programmer"] },
    ];

    expect(
      selectNodesForReader(
        classifiedNodes,
        { locale: "ja", roles: ["typescript-programmer"] },
        { id: "interesting", mode: "unfamiliar" },
      ).map((node) => node.id),
    ).toEqual(["moonbit-specific", "rust-only"]);

    expect(
      selectNodesForReader(
        classifiedNodes,
        { locale: "ja", roles: ["typescript-programmer"] },
        { id: "detail", mode: "all" },
      ).map((node) => node.id),
    ).toEqual(["shared", "moonbit-specific", "rust-only"]);
  });
});
