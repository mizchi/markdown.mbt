import { describe, expect, it } from "vitest";
import { findInlineMarkerUtf8 } from "./inline-marker-simd.js";
import { toHtml } from "./api.js";

describe("inline marker Wasm ESM bridge", () => {
  it("finds markers across SIMD chunks and scalar tails", () => {
    expect(findInlineMarkerUtf8("a".repeat(64), 0, 64)).toBe(-1);
    expect(findInlineMarkerUtf8(`${"a".repeat(31)}*tail`, 0, 36)).toBe(31);
    expect(findInlineMarkerUtf8(`${"a".repeat(64)}[tail`, 0, 69)).toBe(64);
  });

  it("returns a fallback signal when UTF-8 offsets differ from UTF-16", () => {
    expect(findInlineMarkerUtf8(`${"a".repeat(32)}日本語*`, 0, 36)).toBe(-2);
  });

  it("registers the bridge used by the MoonBit JavaScript FFI", () => {
    expect(globalThis.__mizchiMarkdownInlineMarkerSimd).toEqual({
      findInlineMarkerUtf8,
    });
  });

  it("routes long inline runs from the npm API through the bridge", () => {
    const bridge = globalThis.__mizchiMarkdownInlineMarkerSimd;
    let calls = 0;
    globalThis.__mizchiMarkdownInlineMarkerSimd = {
      findInlineMarkerUtf8(...args) {
        calls += 1;
        return bridge.findInlineMarkerUtf8(...args);
      },
    };

    try {
      expect(toHtml(`${"a".repeat(80)} *tail*`)).toContain("<em>tail</em>");
      expect(calls).toBeGreaterThan(0);
    } finally {
      globalThis.__mizchiMarkdownInlineMarkerSimd = bridge;
    }
  });
});
