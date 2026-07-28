import { describe, expect, it } from "vitest";

import { expandFolddownIncludes } from "./include-resolver.js";

describe("Folddown external includes", () => {
  it("expands nested relative documents in declaration order", () => {
    const files = new Map([
      [
        "docs/root.mdx",
        '# Root\n\n<Include src="./fragments/intro.mdx" sync="intro" />\n',
      ],
      [
        "docs/fragments/intro.mdx",
        '<Include src="./details.mdx" />\n\n<Fold id="intro" kind="concept" level="intro">\n## Intro\n\nBody.\n</Fold>\n',
      ],
      [
        "docs/fragments/details.mdx",
        '<Fold id="details" kind="reference" level="basic">\n## Details\n\nMore.\n</Fold>\n',
      ],
    ]);

    const result = expandFolddownIncludes("docs/root.mdx", (path) => files.get(path));

    expect(result.source).not.toContain("<Include");
    expect(result.source).toContain('id="details"');
    expect(result.source).toContain('id="intro"');
    expect(result.edges).toEqual([
      {
        from: "docs/root.mdx",
        to: "docs/fragments/intro.mdx",
        src: "./fragments/intro.mdx",
        sync: "intro",
      },
      {
        from: "docs/fragments/intro.mdx",
        to: "docs/fragments/details.mdx",
        src: "./details.mdx",
        sync: null,
      },
    ]);
  });

  it("rejects include cycles and paths that escape the document root", () => {
    const cyclic = new Map([
      ["docs/a.mdx", '<Include src="./b.mdx" />'],
      ["docs/b.mdx", '<Include src="./a.mdx" />'],
    ]);
    expect(() => expandFolddownIncludes("docs/a.mdx", (path) => cyclic.get(path))).toThrow(
      "Include cycle",
    );

    expect(() =>
      expandFolddownIncludes(
        "docs/a.mdx",
        () => '<Include src="../../outside.mdx" />',
      ),
    ).toThrow("escapes the document root");
  });
});
