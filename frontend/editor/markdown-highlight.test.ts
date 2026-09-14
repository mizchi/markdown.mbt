import { describe, expect, it } from "vitest";
import {
  countLines,
  diffLineEdit,
  highlightMarkdownLine,
  highlightMarkdownLines,
  lineAt,
  lineNeedsFullRehighlight,
  matchFenceClose,
  matchFenceOpen,
} from "./markdown-highlight.js";

describe("matchFenceOpen", () => {
  it("accepts an info string with non-word characters", () => {
    // The playground's default document opens a ```moonlight-svg block; a
    // /^`{3,}([\w]*)\s*$/ style test rejects it and desyncs the code-block state.
    const fence = matchFenceOpen("```moonlight-svg");
    expect(fence).not.toBeNull();
    expect(fence!.lang).toBe("moonlight-svg");
    expect(fence!.info).toBe("moonlight-svg");
  });

  it("takes the language from the first word of the info string", () => {
    expect(matchFenceOpen("```js {1,3}")!.lang).toBe("js");
    expect(matchFenceOpen('```ts title="a.ts"')!.lang).toBe("ts");
    expect(matchFenceOpen("```TypeScript")!.lang).toBe("typescript");
  });

  it("supports tilde fences and up to three spaces of indent", () => {
    expect(matchFenceOpen("~~~python")!.char).toBe("~");
    expect(matchFenceOpen("   ```ts")!.indent).toBe("   ");
    expect(matchFenceOpen("    ```ts")).toBeNull(); // 4 spaces = indented code
  });

  it("rejects a backtick fence whose info string contains a backtick", () => {
    expect(matchFenceOpen("```a`b")).toBeNull();
    expect(matchFenceOpen("~~~a`b")).not.toBeNull();
  });

  it("rejects runs shorter than three characters", () => {
    expect(matchFenceOpen("``ts")).toBeNull();
  });
});

describe("matchFenceClose", () => {
  it("requires the same character and at least the opening length", () => {
    expect(matchFenceClose("```", "`", 3)).toBe(true);
    expect(matchFenceClose("````", "`", 3)).toBe(true);
    expect(matchFenceClose("```", "`", 4)).toBe(false);
    expect(matchFenceClose("~~~", "`", 3)).toBe(false);
  });

  it("rejects a closing fence carrying an info string", () => {
    expect(matchFenceClose("```ts", "`", 3)).toBe(false);
    expect(matchFenceClose("```   ", "`", 3)).toBe(true);
  });
});

describe("highlightMarkdownLines", () => {
  it("emits exactly one entry per source line", () => {
    const docs = [
      "",
      "a",
      "a\n\nb",
      "# h\n\n```ts\nconst a = 1;\n```\n\ntail",
      "```\nunclosed\nstill open",
      "```moonlight-svg\n<svg></svg>\n```\n\ntail",
    ];
    for (const doc of docs) {
      expect(highlightMarkdownLines(doc).length, JSON.stringify(doc)).toBe(countLines(doc));
    }
  });

  it("keeps highlighting content after a block with a non-word info string", () => {
    const doc = "```moonlight-svg\n<svg></svg>\n```\n\ntail **bold** here";
    const lines = highlightMarkdownLines(doc);
    // The fence line renders as a fence, not as inline code.
    expect(lines[0]).toContain('class="md-fence"');
    expect(lines[0]).toContain('class="md-fence-lang"');
    // ...and the closing fence really closes, so the tail is still markdown.
    expect(lines[4]).toContain('class="md-bold"');
  });

  it("renders the fence line with the info string verbatim", () => {
    // The overlay sits behind the textarea, so the painted text must match the
    // source character for character.
    const lines = highlightMarkdownLines("  ```JS  extra  \ncode\n```");
    const text = lines[0]!.replace(/<[^>]+>/g, "");
    expect(text).toBe("  ```JS  extra  ");
  });

  it("agrees with the line-local path outside code blocks", () => {
    const doc = "# Title\n\n```ts\nconst a = 1;\n```\n\n- item *one*\n\ntail **bold**";
    const full = highlightMarkdownLines(doc);
    const rawLines = doc.split("\n");
    for (let i = 0; i < rawLines.length; i++) {
      if (lineNeedsFullRehighlight(doc, i)) continue;
      expect(highlightMarkdownLine(rawLines[i]!), `line ${i}`).toBe(full[i]);
    }
  });
});

describe("lineNeedsFullRehighlight", () => {
  const doc = "# Title\n\n```ts\nconst a = 1;\n```\n\ntail";

  it("marks fence lines and code-block bodies", () => {
    expect(lineNeedsFullRehighlight(doc, 0)).toBe(false); // # Title
    expect(lineNeedsFullRehighlight(doc, 1)).toBe(false); // blank
    expect(lineNeedsFullRehighlight(doc, 2)).toBe(true); // ```ts
    expect(lineNeedsFullRehighlight(doc, 3)).toBe(true); // code body
    expect(lineNeedsFullRehighlight(doc, 4)).toBe(true); // closing ```
    expect(lineNeedsFullRehighlight(doc, 5)).toBe(false); // blank
    expect(lineNeedsFullRehighlight(doc, 6)).toBe(false); // tail
  });

  it("uses the same fence rule as the renderer", () => {
    const svg = "```moonlight-svg\n<svg></svg>\n```\n\ntail";
    expect(lineNeedsFullRehighlight(svg, 1)).toBe(true); // inside the block
    expect(lineNeedsFullRehighlight(svg, 4)).toBe(false); // after the block
  });

  it("reports out-of-range lines as needing a full pass", () => {
    expect(lineNeedsFullRehighlight(doc, 99)).toBe(true);
    expect(lineNeedsFullRehighlight(doc, -1)).toBe(true);
  });
});

describe("diffLineEdit", () => {
  it("detects no change", () => {
    expect(diffLineEdit("abc", "abc")).toEqual({ kind: "none" });
  });

  it("detects a single-line edit and reports its line", () => {
    expect(diffLineEdit("a\nb\nc", "a\nbx\nc")).toEqual({ kind: "single", line: 1 });
    expect(diffLineEdit("a\nb\nc", "a\nb\ncd")).toEqual({ kind: "single", line: 2 });
    expect(diffLineEdit("a\nb", "ax\nb")).toEqual({ kind: "single", line: 0 });
  });

  it("detects a deletion inside one line", () => {
    expect(diffLineEdit("a\nbxc\nd", "a\nbc\nd")).toEqual({ kind: "single", line: 1 });
  });

  it("reports any newline insertion or removal as multi-line", () => {
    expect(diffLineEdit("ab", "a\nb")).toEqual({ kind: "multi" });
    expect(diffLineEdit("a\nb", "ab")).toEqual({ kind: "multi" });
    expect(diffLineEdit("a\nb", "a\n\nb")).toEqual({ kind: "multi" });
    expect(diffLineEdit("a", "a\n")).toEqual({ kind: "multi" });
  });

  it("reports a selection replacement spanning lines as multi-line", () => {
    // Same length change as a single keystroke, but it crosses a newline -
    // a cursor/length heuristic misses this.
    expect(diffLineEdit("A\nBC\nD", "A\nXY")).toEqual({ kind: "multi" });
  });

  it("treats a multi-line paste as multi-line", () => {
    expect(diffLineEdit("start\nend", "start\nmiddle\nmore\nend")).toEqual({ kind: "multi" });
  });
});

describe("lineAt / countLines", () => {
  it("returns the raw text of a line", () => {
    const doc = "one\ntwo\nthree";
    expect(lineAt(doc, 0)).toBe("one");
    expect(lineAt(doc, 1)).toBe("two");
    expect(lineAt(doc, 2)).toBe("three");
    expect(lineAt(doc, 3)).toBe("");
  });

  it("counts a trailing newline as opening a new line", () => {
    expect(countLines("")).toBe(1);
    expect(countLines("a")).toBe(1);
    expect(countLines("a\n")).toBe(2);
    expect(countLines("a\nb")).toBe(2);
  });
});
