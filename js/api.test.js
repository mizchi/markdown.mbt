import { describe, it, expect } from "vitest";
import {
  parse,
  toHtml,
  toHtmlLiteral,
  toMarkdown,
  createDocument,
  diffEdit,
  insertEdit,
  deleteEdit,
  replaceEdit,
} from "./api.js";
import {
  md_to_ast_json,
  md_to_ast_json_with_wikilinks,
} from "../_build/js/release/build/api/api.js";

describe("parse", () => {
  it("matches the serialized mdast contract for core and extension nodes", () => {
    const cases = [
      "# Heading\n\nParagraph with *emphasis*, **strong**, ~~delete~~, `code`, [link](https://example.com \"title\"), ![alt](image.png), and <b>HTML</b>.\n",
      "> quote\n\n- [x] done\n- item\n\n1. first\n2. second\n\n---\n",
      "```js meta\nconsole.log(1)\n```\n\n    indented\n\n| A | B |\n| :- | -: |\n| x | y |\n",
      "```😀 meta\nnon-BMP info\n```\n",
      "[^note]: footnote\n\nUse [^note].\n\n$$\nx^2\n$$\n",
      "> [!WARNING]\n> alert\n\n:::note Meta\nBody\n:::\n\nTerm\n: Definition\n",
      "# Attributed\n\n{#intro .wide}\n\nUse :badge[stable]{.green level=high}.\n",
    ];

    for (const source of cases) {
      expect(parse(source)).toEqual(JSON.parse(md_to_ast_json(source)));
    }

    const wikilink = "[[MoonBit#syntax|MoonBit syntax]]";
    expect(parse(wikilink, { wikilinks: true })).toEqual(
      JSON.parse(md_to_ast_json_with_wikilinks(wikilink)),
    );
  });

  it("parses heading", () => {
    const ast = parse("# Hello");
    expect(Object.getPrototypeOf(ast)).toBe(Object.prototype);
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

  it("exposes extension blocks through stable JSON contracts", () => {
    expect(parse("$$\nx^2\n$$\n").children[0]).toMatchObject({
      type: "math",
      value: "x^2\n",
    });
    expect(parse("> [!NOTE]\n> Body\n").children[0]).toMatchObject({
      type: "alert",
      kind: "note",
    });
    expect(parse(":::note Meta\nBody\n:::\n").children[0]).toMatchObject({
      type: "containerDirective",
      name: "note",
      meta: "Meta",
    });
    expect(parse("Term\n: Definition\n").children[0].type).toBe(
      "definitionList"
    );
    expect(parse("# Heading\n\n{#intro .wide}\n").children[0]).toMatchObject({
      type: "attributed",
      attributes: [
        { name: "id", value: "intro" },
        { name: "class", value: "wide" },
      ],
    });
    expect(
      parse("Use :badge[stable]{.green level=high}.\n").children[0].children[1]
    ).toMatchObject({
      type: "textDirective",
      name: "badge",
      label: "stable",
      attributes: [
        { name: "class", value: "green" },
        { name: "level", value: "high" },
      ],
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

  it("matches the remaining CommonMark examples with GFM rendering disabled", () => {
    const cases = [
      [
        '<script type="text/javascript">\n// JavaScript example\n\ndocument.getElementById("demo").innerHTML = "Hello JavaScript!";\n</script>\nokay\n',
        '<script type="text/javascript">\n// JavaScript example\n\ndocument.getElementById("demo").innerHTML = "Hello JavaScript!";\n</script>\n<p>okay</p>\n',
      ],
      [
        "<textarea>\n\n*foo*\n\n_bar_\n\n</textarea>\n",
        "<textarea>\n\n*foo*\n\n_bar_\n\n</textarea>\n",
      ],
      [
        '<style\n  type="text/css">\nh1 {color:red;}\n\np {color:blue;}\n</style>\nokay\n',
        '<style\n  type="text/css">\nh1 {color:red;}\n\np {color:blue;}\n</style>\n<p>okay</p>\n',
      ],
      [
        '<style\n  type="text/css">\n\nfoo\n',
        '<style\n  type="text/css">\n\nfoo\n',
      ],
      [
        "<style>p{color:red;}</style>\n*foo*\n",
        "<style>p{color:red;}</style>\n<p><em>foo</em></p>\n",
      ],
      [
        "<script>\nfoo\n</script>1. *bar*\n",
        "<script>\nfoo\n</script>1. *bar*\n",
      ],
      [
        "<https://foo.bar/baz bim>\n",
        "<p>&lt;https://foo.bar/baz bim&gt;</p>\n",
      ],
      [
        "<foo\\+@bar.example.com>\n",
        "<p>&lt;foo+@bar.example.com&gt;</p>\n",
      ],
      [
        "< https://foo.bar >\n",
        "<p>&lt; https://foo.bar &gt;</p>\n",
      ],
      ["https://example.com\n", "<p>https://example.com</p>\n"],
      ["foo@bar.example.com\n", "<p>foo@bar.example.com</p>\n"],
    ];

    for (const [source, expected] of cases) {
      expect(toHtml(source, { autolink: false, tagfilter: false })).toBe(expected);
    }
  });

  it("controls tagfilter independently from other extensions", () => {
    expect(
      toHtml("<script>raw</script>\n\n[[MoonBit]] https://example.com\n", {
        wikilinks: true,
        autolink: false,
        tagfilter: false,
      })
    ).toBe(
      '<script>raw</script>\n<p><a href="MoonBit">MoonBit</a> https://example.com</p>\n'
    );
  });

  it("renders a bullet list directly followed by a thematic break", () => {
    const source = "- a\n- m\n---------------\n";
    expect(parse(source).children.map((node) => node.type)).toEqual([
      "list",
      "thematicBreak",
    ]);
    expect(toHtml(source)).toBe("<ul>\n<li>a</li>\n<li>m</li>\n</ul>\n<hr />\n");
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

  it("can disable GFM tagfilter on document handles", () => {
    const doc = createDocument(
      "<script>raw</script>\n\nhttps://example.com\n",
      { autolink: false, tagfilter: false },
    );
    expect(doc.toHtml()).toBe(
      "<script>raw</script>\n<p>https://example.com</p>\n",
    );
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

  it("exposes the updated AST without re-parsing", () => {
    const doc = createDocument("# Hello");
    const newDoc = doc.update("# Hello World", insertEdit(7, 6));

    expect(newDoc.ast.type).toBe("root");
    expect(newDoc.ast.children[0].type).toBe("heading");
    expect(newDoc.ast.children[0].children[0].value).toBe("Hello World");
    // The original document keeps its own revision.
    expect(doc.ast.children[0].children[0].value).toBe("Hello");

    doc.dispose();
    newDoc.dispose();
  });

  it("chains updates without falling back to a full parse", () => {
    let doc = createDocument("# A\n\nbody\n");
    const revisions = ["# AB\n\nbody\n", "# ABC\n\nbody\n", "# ABCD\n\nbody\n"];
    let previous = "# A\n\nbody\n";

    for (const next of revisions) {
      const edit = diffEdit(previous, next);
      expect(edit).not.toBeNull();
      const updated = doc.update(next, edit);
      doc.dispose();
      doc = updated;
      previous = next;
      expect(doc.toMarkdown()).toBe(next);
    }

    expect(doc.ast.children[0].children[0].value).toBe("ABCD");
    doc.dispose();
  });

  it("rejects use after dispose", () => {
    const doc = createDocument("# Hello");
    doc.dispose();
    expect(() => doc.toHtml()).toThrow(/disposed/);
    expect(() => doc.ast).toThrow(/disposed/);
    // dispose is idempotent
    expect(() => doc.dispose()).not.toThrow();
  });
});

describe("incremental parse fidelity", () => {
  const blocks = (ast) =>
    ast.children.map(
      (c) => `${c.type}@${c.position.start.offset}-${c.position.end.offset}`,
    ).join(" ");

  /** Apply one edit through the incremental path and return both readings. */
  const applyEdit = (before, after, { materialise = true } = {}) => {
    const doc = createDocument(before);
    if (materialise) doc.ast; // enables the reuse path on the next update
    const updated = doc.update(after, diffEdit(before, after));
    const result = { incremental: blocks(updated.ast), full: blocks(parse(after)) };
    doc.dispose();
    updated.dispose();
    return result;
  };

  // Each of these edits changes how the text AFTER it parses, so a re-parse
  // limited to the edited block alone gets the document wrong.
  const STRUCTURAL = [
    ["quoting a paragraph", "# T\n\npara one\n\ntail\n", (s) => s.replace("para one", "> para one")],
    ["turning a paragraph into a list item", "# T\n\npara one\n\ntail\n", (s) => s.replace("para one", "- para one")],
    ["opening a fence", "# T\n\npara one\n\ntail\n", (s) => s.replace("para one", "```ts")],
    ["breaking a closing fence", "# T\n\n```ts\ncode\n```\n\ntail\n", (s) => s.replace("\n```\n\ntail", "\n``\n\ntail")],
    ["breaking a table delimiter", "# T\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\ntail\n", (s) => s.replace("|---|---|", "|---|")],
    ["adding a setext underline", "# T\n\npara one\n\ntail\n", (s) => s.replace("para one\n", "para one\n===\n")],
  ];

  for (const [name, before, mutate] of STRUCTURAL) {
    it(`matches a full parse after ${name}`, () => {
      const after = mutate(before);
      expect(after).not.toBe(before);
      const { incremental, full } = applyEdit(before, after);
      expect(incremental).toBe(full);
    });
  }

  it("keeps a chain of edits in step with a full parse", () => {
    let source = "# Title\n\nintro *text*\n\n- one\n- two\n\n> quote\n";
    let doc = createDocument(source);
    doc.ast;
    const steps = [
      (s) => s.replace("intro", "> intro"),
      (s) => s.replace("- one", "1. one"),
      (s) => s + "\ntail paragraph\n",
      (s) => s.replace("quote", "quote **bold**"),
      (s) => s.replace("# Title", "## Title"),
    ];
    for (const step of steps) {
      const next = step(source);
      const updated = doc.update(next, diffEdit(source, next));
      doc.dispose();
      doc = updated;
      source = next;
      expect(blocks(doc.ast)).toBe(blocks(parse(source)));
    }
    doc.dispose();
  });

  it("reuses AST nodes that the edit did not touch", () => {
    const before = "# Title\n\nfirst para\n\nsecond para\n\nthird para\n";
    const after = before + "\nfourth para\n";
    const doc = createDocument(before);
    const oldAst = doc.ast;
    const updated = doc.update(after, diffEdit(before, after));
    const newAst = updated.ast;

    // Appending at the end leaves every earlier block untouched, so the very
    // same node objects come back rather than freshly built copies.
    expect(newAst.children[0]).toBe(oldAst.children[0]);
    expect(newAst.children[1]).toBe(oldAst.children[1]);
    expect(blocks(newAst)).toBe(blocks(parse(after)));

    doc.dispose();
    updated.dispose();
  });
});

describe("diffEdit", () => {
  const apply = (source, edit, inserted) =>
    source.slice(0, edit.start) + inserted + source.slice(edit.oldEnd);

  it("returns null when nothing changed", () => {
    expect(diffEdit("same", "same")).toBeNull();
  });

  it("narrows an insertion to the inserted range", () => {
    expect(diffEdit("ac", "abc")).toEqual({ start: 1, oldEnd: 1, newEnd: 2 });
  });

  it("narrows a deletion to the removed range", () => {
    expect(diffEdit("abc", "ac")).toEqual({ start: 1, oldEnd: 2, newEnd: 1 });
  });

  it("narrows a replacement spanning lines", () => {
    expect(diffEdit("A\nBC\nD", "A\nXY")).toEqual({
      start: 2,
      oldEnd: 6,
      newEnd: 4,
    });
  });

  it("describes the edit that turns old into new", () => {
    const pairs = [
      ["# Hello", "# Hello World"],
      ["a\n\nb\n", "a\n\nb\nc\n"],
      ["one two three", "one three"],
      ["", "fresh"],
      ["gone", ""],
    ];
    for (const [oldSource, newSource] of pairs) {
      const edit = diffEdit(oldSource, newSource);
      const inserted = newSource.slice(edit.start, edit.newEnd);
      expect(apply(oldSource, edit, inserted)).toBe(newSource);
    }
  });

  it("produces an edit an incremental parse accepts", () => {
    const before = "# Title\n\nfirst\n\nsecond\n";
    const after = "# Title\n\nfirst edited\n\nsecond\n";
    const doc = createDocument(before);
    const updated = doc.update(after, diffEdit(before, after));
    expect(updated.toMarkdown()).toBe(after);
    doc.dispose();
    updated.dispose();
  });
});
