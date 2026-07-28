import { describe, expect, it } from "vitest";
import {
  getLoadedHighlighter,
  highlightIfLoaded,
  loadHighlighter,
  normalizeHighlightLanguage,
} from "./index.js";

describe("frontend highlight loader", () => {
  it("normalizes common aliases", () => {
    expect(normalizeHighlightLanguage("mbt")).toBe("moonbit");
    expect(normalizeHighlightLanguage("tsx")).toBe("typescript");
    expect(normalizeHighlightLanguage("sh")).toBe("bash");
    expect(normalizeHighlightLanguage("golang")).toBe("go");
    expect(normalizeHighlightLanguage("unknown")).toBeNull();
  });

  it("loads a Go highlighter on demand", async () => {
    const highlighter = await loadHighlighter("go");

    expect(highlighter).toBeTypeOf("function");
    expect(highlighter?.("package main\nfunc main() {}")).toContain(
      '<pre class="highlight',
    );
  });

  it("keeps language highlighters unloaded until requested", async () => {
    expect(getLoadedHighlighter("moonbit")).toBeNull();
    expect(highlightIfLoaded("let x = 1", "moonbit")).toBeNull();

    const highlighter = await loadHighlighter("moonbit");
    expect(highlighter).toBeTypeOf("function");
    expect(getLoadedHighlighter("moonbit")).toBe(highlighter);
    expect(highlightIfLoaded("let x = 1", "moonbit")).toContain(
      '<pre class="highlight',
    );
  });
});
