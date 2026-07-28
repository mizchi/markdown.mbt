import { describe, it, expect } from "vitest";
import {
  parse,
  toHtml,
  toHtmlLiteral,
  toMarkdown,
  createDocument,
  insertEdit,
  deleteEdit,
  parseFolddown,
  parseFolddownIncludes,
  replaceEdit,
} from "./api.js";

describe("parse", () => {
  it("parses heading", () => {
    const ast = parse("# Hello");
    expect(ast.type).toBe("root");
    expect(ast.children[0].type).toBe("heading");
    expect(ast.children[0].depth).toBe(1);
  });

  it("parses paragraph with emphasis", () => {
    const ast = parse("**Bold** text");
    expect(ast.children[0].type).toBe("paragraph");
  });

  it("parses wikilinks only when enabled", () => {
    const defaultAst = parse("[[MoonBit]]");
    expect(defaultAst.children[0].children[0]).toMatchObject({
      type: "text",
      value: "[[MoonBit]]",
    });

    const ast = parse("[[MoonBit#syntax|MoonBit syntax]]", {
      wikilinks: true,
    });
    expect(ast.children[0].children[0]).toMatchObject({
      type: "wikiLink",
      value: "MoonBit",
      data: { label: "MoonBit syntax", fragment: "syntax" },
    });
  });
});

describe("toHtml", () => {
  it("converts heading to HTML", () => {
    const html = toHtml("# Hello");
    expect(html).toBe("<h1>Hello</h1>\n");
  });

  it("converts paragraph with strong to HTML", () => {
    const html = toHtml("**Bold** text");
    expect(html).toBe("<p><strong>Bold</strong> text</p>\n");
  });

  it("renders wikilinks only when enabled", () => {
    expect(toHtml("[[MoonBit]]")).toBe("<p>[[MoonBit]]</p>\n");
    expect(toHtml("[[MoonBit|MoonBit notes]]", { wikilinks: true })).toBe(
      '<p><a href="MoonBit">MoonBit notes</a></p>\n'
    );
  });

  it("renders bare URL text as links by default", () => {
    expect(toHtml("Read https://example.com/docs.\n")).toBe(
      '<p>Read <a href="https://example.com/docs">https://example.com/docs</a>.</p>\n'
    );
    expect(toHtml("Read https://example.com/docs.\n", { autolink: false })).toBe(
      "<p>Read https://example.com/docs.</p>\n"
    );
  });

  it("combines wikilinks and bare URL autolinks", () => {
    expect(
      toHtml("[[MoonBit|MoonBit notes]] https://example.com/docs\n", {
        wikilinks: true,
        autolink: true,
      })
    ).toBe(
      '<p><a href="MoonBit">MoonBit notes</a> <a href="https://example.com/docs">https://example.com/docs</a></p>\n'
    );
    expect(
      toHtml("[[MoonBit|MoonBit notes]] https://example.com/docs\n", {
        wikilinks: true,
        autolink: false,
      })
    ).toBe('<p><a href="MoonBit">MoonBit notes</a> https://example.com/docs</p>\n');
  });

  it("renders a bullet list directly followed by a thematic break", () => {
    const source = "- a\n- m\n---------------\n";
    expect(parse(source).children.map((node) => node.type)).toEqual([
      "list",
      "thematicBreak",
    ]);
    expect(toHtml(source)).toBe("<ul>\n<li>a</li>\n<li>m</li>\n</ul>\n<hr>\n");
  });
});

describe("toHtmlLiteral", () => {
  it("preserves a thematic break marker after a bullet list", () => {
    const html = toHtmlLiteral("- a\n- m\n---------------\n");
    expect(html).toContain(
      'class="md-marker" aria-hidden="true">---------------</span>'
    );
    expect(html).not.toContain('class="md-marker" aria-hidden="true">***</span>');
  });
});

describe("toMarkdown", () => {
  it("normalizes markdown", () => {
    const md = toMarkdown("# Hello\n\n\n\nWorld");
    expect(md).toBe("# Hello\n\nWorld\n");
  });

  it("serializes wikilinks when enabled", () => {
    const md = toMarkdown("[[MoonBit|MoonBit notes]]", { wikilinks: true });
    expect(md).toBe("[[MoonBit|MoonBit notes]]\n");
  });
});

describe("parseFolddown", () => {
  it("returns typed metadata and child Markdown from a Fold declaration", () => {
    const result = parseFolddown(`
<Fold id="intro" kind="concept" level="basic" locale="en" roles={["typescript-programmer"]}>
## Immutable bindings

Use \`let\` by default.
</Fold>
`);

    expect(result.diagnostics).toEqual([]);
    expect(result.nodes).toHaveLength(1);
    expect(result.nodes[0]).toMatchObject({
      id: "intro",
      kind: "concept",
      level: "basic",
      locale: "en",
      roles: ["typescript-programmer"],
    });
    expect(result.nodes[0].body).toContain("Immutable bindings");
  });

  it("returns reader profiles generated from Folddown frontmatter", () => {
    const result = parseFolddown(`---
folddown.readers: first_time,some_knowledge
folddown.reader.first_time.label.ja: 初めて知った
folddown.reader.first_time.label.en: First time
folddown.reader.first_time.collapse: none
folddown.reader.some_knowledge.label.ja: 多少知ってる
folddown.reader.some_knowledge.label.en: Know some
folddown.reader.some_knowledge.collapse: intro
---
<Fold id="intro" kind="concept" level="intro">## Intro</Fold>`);

    expect(result.diagnostics).toEqual([]);
    expect(result.readerProfiles).toEqual([
      {
        id: "first_time",
        labelJa: "初めて知った",
        labelEn: "First time",
        collapseLevels: [],
      },
      {
        id: "some_knowledge",
        labelJa: "多少知ってる",
        labelEn: "Know some",
        collapseLevels: ["intro"],
      },
    ]);
  });

  it("returns content filters generated from Folddown frontmatter", () => {
    const result = parseFolddown(`---
folddown.content_filters: detail,interesting
folddown.content_filter.detail.label.ja: 詳しく知りたい
folddown.content_filter.detail.label.en: Learn in detail
folddown.content_filter.detail.mode: all
folddown.content_filter.interesting.label.ja: 面白い機能だけを知りたい
folddown.content_filter.interesting.label.en: Interesting features only
folddown.content_filter.interesting.mode: unfamiliar
---
<Fold id="intro" kind="concept" level="intro" familiarTo={["typescript-programmer"]}>## Intro</Fold>`);

    expect(result.diagnostics).toEqual([]);
    expect(result.nodes[0].familiarTo).toEqual(["typescript-programmer"]);
    expect(result.contentFilters).toEqual([
      {
        id: "detail",
        labelJa: "詳しく知りたい",
        labelEn: "Learn in detail",
        mode: "all",
      },
      {
        id: "interesting",
        labelJa: "面白い機能だけを知りたい",
        labelEn: "Interesting features only",
        mode: "unfamiliar",
      },
    ]);
  });
});

describe("parseFolddownIncludes", () => {
  it("returns typed local-document declarations", () => {
    const result = parseFolddownIncludes(
      '<Include src="./fragments/overview.en.mdx" sync="moonbit-overview" />',
    );

    expect(result.diagnostics).toEqual([]);
    expect(result.includes).toEqual([
      {
        src: "./fragments/overview.en.mdx",
        sync: "moonbit-overview",
        raw: '<Include src="./fragments/overview.en.mdx" sync="moonbit-overview" />',
      },
    ]);
  });
});

describe("Edit helpers", () => {
  describe("insertEdit", () => {
    it("creates edit info for insertion", () => {
      // Insert 6 chars at position 5
      const edit = insertEdit(5, 6);
      expect(edit).toEqual({ start: 5, oldEnd: 5, newEnd: 11 });
    });

    it("creates edit info for insertion at start", () => {
      const edit = insertEdit(0, 3);
      expect(edit).toEqual({ start: 0, oldEnd: 0, newEnd: 3 });
    });
  });

  describe("deleteEdit", () => {
    it("creates edit info for deletion", () => {
      // Delete from position 5 to 10
      const edit = deleteEdit(5, 10);
      expect(edit).toEqual({ start: 5, oldEnd: 10, newEnd: 5 });
    });

    it("creates edit info for single char deletion", () => {
      const edit = deleteEdit(5, 6);
      expect(edit).toEqual({ start: 5, oldEnd: 6, newEnd: 5 });
    });
  });

  describe("replaceEdit", () => {
    it("creates edit info for replacement", () => {
      // Replace positions 5-10 with 8 chars
      const edit = replaceEdit(5, 10, 8);
      expect(edit).toEqual({ start: 5, oldEnd: 10, newEnd: 13 });
    });

    it("creates edit info for shorter replacement", () => {
      // Replace 10 chars with 3 chars
      const edit = replaceEdit(0, 10, 3);
      expect(edit).toEqual({ start: 0, oldEnd: 10, newEnd: 3 });
    });
  });
});

describe("createDocument", () => {
  it("creates document handle with AST access", () => {
    const doc = createDocument("# Hello");
    expect(doc.ast.type).toBe("root");
    expect(doc.ast.children[0].type).toBe("heading");
    doc.dispose();
  });

  it("provides toHtml method", () => {
    const doc = createDocument("# Hello");
    expect(doc.toHtml()).toBe("<h1>Hello</h1>\n");
    doc.dispose();
  });

  it("provides toMarkdown method", () => {
    const doc = createDocument("# Hello");
    expect(doc.toMarkdown()).toBe("# Hello\n");
    doc.dispose();
  });

  it("keeps wikilink option on document handles", () => {
    const doc = createDocument("[[MoonBit]]", { wikilinks: true });
    expect(doc.ast.children[0].children[0].type).toBe("wikiLink");
    expect(doc.toHtml()).toBe('<p><a href="MoonBit">MoonBit</a></p>\n');
    doc.dispose();
  });

  it("keeps autolink default on document handles", () => {
    const doc = createDocument("Read https://example.com/docs.");
    expect(doc.toHtml()).toBe(
      '<p>Read <a href="https://example.com/docs">https://example.com/docs</a>.</p>\n'
    );
    doc.dispose();
  });

  it("can disable bare URL links on document handles", () => {
    const doc = createDocument("Read https://example.com/docs.", {
      autolink: false,
    });
    expect(doc.toHtml()).toBe("<p>Read https://example.com/docs.</p>\n");
    doc.dispose();
  });

  it("supports incremental update", () => {
    const doc = createDocument("# Hello");
    // "# Hello" -> "# Hello World" (insert " World" at position 7)
    const edit = insertEdit(7, 6);
    const newDoc = doc.update("# Hello World", edit);

    expect(newDoc.toHtml()).toBe("<h1>Hello World</h1>\n");

    doc.dispose();
    newDoc.dispose();
  });
});
