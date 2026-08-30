import { describe, expect, it } from "vitest";
import { parse, toHtml, toMarkdown } from "./api.js";

describe("WebAssembly API", () => {
  it("matches the public Markdown API", () => {
    expect(parse("# Hello")).toMatchObject({
      type: "root",
      children: [{ type: "heading", depth: 1 }],
    });
    expect(toHtml("# Hello")).toBe("<h1>Hello</h1>\n");
    expect(toMarkdown("# Hello\n\n\nWorld")).toBe("# Hello\n\nWorld\n");
  });

  it("supports parser extension options", () => {
    expect(parse("[[MoonBit]]", { wikilinks: true }).children[0].children[0])
      .toMatchObject({ type: "wikiLink", value: "MoonBit" });
    expect(toHtml("[[MoonBit]] https://example.com", {
      wikilinks: true,
      autolink: false,
    })).toBe('<p><a href="MoonBit">MoonBit</a> https://example.com</p>\n');
  });

  it("reuses one instance across calls", () => {
    for (let index = 0; index < 100; index += 1) {
      expect(toHtml(`# Item ${index}`)).toBe(`<h1>Item ${index}</h1>\n`);
    }
  });

  it("passes large JavaScript strings without a linear-memory copy", () => {
    const section = "# Heading\n\nParagraph with **bold** and [link](https://example.com).\n\n";
    const source = section.repeat(1_000);
    expect(toHtml(source)).toContain("<h1>Heading</h1>");
    expect(parse(source).children.length).toBe(2_000);
  });
});
