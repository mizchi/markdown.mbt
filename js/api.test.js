import { describe, it, expect } from "vitest";
import {
  parse,
  toHtml,
  toMarkdown,
  createDocument,
  insertEdit,
  deleteEdit,
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
