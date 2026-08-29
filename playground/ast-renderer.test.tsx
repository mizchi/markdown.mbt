import { describe, expect, it } from "vitest";
import { highlightCode, splitBareUrlText } from "./ast-renderer";

describe("splitBareUrlText", () => {
  it("keeps bare URL link text identical to href", () => {
    expect(splitBareUrlText("Read https://example.com/docs.")).toEqual([
      { type: "text", value: "Read " },
      { type: "url", value: "https://example.com/docs" },
      { type: "text", value: "." },
    ]);
  });

  it("does not autolink URLs embedded in words", () => {
    expect(splitBareUrlText("prefixhttps://example.com")).toEqual([
      { type: "text", value: "prefixhttps://example.com" },
    ]);
  });

  it("preserves escaped ampersands in URL tokens as raw URL text", () => {
    expect(splitBareUrlText("Open https://example.com/?a=1&b=2")).toEqual([
      { type: "text", value: "Open " },
      { type: "url", value: "https://example.com/?a=1&b=2" },
    ]);
  });
});

describe("highlightCode", () => {
  it("highlights Go code", () => {
    const html = highlightCode("package main\nfunc main() {}", "go");

    expect(html).toContain('<pre class="highlight');
    expect(html).toContain('color: #ff7b72');
  });
});
