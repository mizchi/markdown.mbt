/**
 * VRT for the source-preserving ("literal") renderer.
 *
 * For a fixed set of Markdown samples we render two views of the same
 * document and verify that, character by character, they occupy the same
 * positions on screen:
 *
 *   1. A plain `<pre>` showing the source text — this is the ground truth
 *      character grid.
 *   2. The output of `toHtmlLiteral(source)` injected into a sibling
 *      element with the same fonts/spacing rules from
 *      `frontend/editor/overlay.css`.
 *
 * Both views are absolutely positioned at the same origin. We measure the
 * client-rect of each visible glyph in the rendered view and assert that
 * it falls inside the corresponding glyph cell in the source view.
 *
 * We also run a snapshot-style visual diff: with both layers fully
 * opaque, every glyph cell should be identically populated, so a
 * pixel-diff of the rendered layer vs the source layer should match
 * within a tight tolerance.
 */

import { expect, test } from "@playwright/test";

const SAMPLES = [
  { name: "headings", md: "# H1\n\n## H2\n\n### H3\n" },
  {
    name: "emphasis",
    md: "*italic* and **bold** and ~~strike~~ and `code`\n",
  },
  { name: "bullet-list", md: "- one\n- two\n- three\n" },
  { name: "bullet-list-asterisk", md: "* one\n* two\n" },
  { name: "bullet-list-plus", md: "+ one\n+ two\n" },
  { name: "ordered-list", md: "1. one\n2. two\n3. three\n" },
  { name: "ordered-list-paren", md: "1) one\n2) two\n" },
  { name: "blockquote", md: "> first\n> second\n" },
  {
    name: "autolink",
    md: "see <https://example.com> for details\n",
  },
  {
    name: "fenced-code",
    md: '```rust\nfn main() {\n    println!("hi");\n}\n```\n',
  },
  {
    name: "mixed",
    md: [
      "# Title",
      "",
      "Paragraph with *em*, **strong**, and `code`.",
      "",
      "- item one",
      "- item two",
      "",
      "> a quote",
      "",
    ].join("\n"),
  },
];

test.describe("literal renderer overlay invariant", () => {
  test("demo applies literal overlay CSS reset", async ({ page }) => {
    await page.goto("/literal/");
    await page.waitForSelector("#rendered h1");
    await expect(page.locator("#overlay-toggle")).toBeChecked();
    await expect(page.locator("body")).toHaveClass(/overlay/);

    const styles = await page.evaluate(() => {
      const read = (selector: string) => {
        const el = document.querySelector(selector);
        if (!el) throw new Error(`missing ${selector}`);
        const style = getComputedStyle(el);
        return {
          display: style.display,
          margin: style.margin,
          padding: style.padding,
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          lineHeight: style.lineHeight,
          textTransform: style.textTransform,
          whiteSpace: style.whiteSpace,
        };
      };
      return {
        source: read("#source-view"),
        h1: read("#rendered h1"),
        h2: read("#rendered h2"),
        paragraph: read("#rendered p"),
        list: read("#rendered ul"),
        quote: read("#rendered blockquote"),
        code: read("#rendered pre"),
      };
    });

    for (
      const [name, style] of Object.entries(styles).filter(([name]) =>
        name !== "source"
      )
    ) {
      expect(style, name).toMatchObject({
        display: "inline",
        margin: "0px",
        padding: "0px",
        fontSize: styles.source.fontSize,
        lineHeight: styles.source.lineHeight,
        textTransform: "none",
        whiteSpace: "pre-wrap",
      });
      expect(style.fontFamily, name).toBe(styles.source.fontFamily);
    }
  });

  for (const sample of SAMPLES) {
    test(`${sample.name} renders the same glyph grid as source`, async ({ page }) => {
      await page.goto("/literal/");
      // Wait until the demo's first paint settled.
      await page.waitForSelector(
        "#rendered .md-marker, #rendered p, #rendered h1, #rendered h2",
      );

      // Replace the source with the test sample and fire `input` so the
      // demo recomputes both panes.
      await page.evaluate((md) => {
        const ta = document.getElementById("source") as HTMLTextAreaElement;
        ta.value = md;
        ta.dispatchEvent(new Event("input", { bubbles: true }));
      }, sample.md);

      // The demo writes a green `✓` into #invariant-state if the patched
      // DOM still matches a fresh literal render.
      await expect(page.locator("#invariant-state")).toHaveText(
        /literal DOM matches fresh render/,
      );
    });
  }

  test("source view follows literal serializer marker normalization", async ({ page }) => {
    const md = [
      "* asterisk bullet",
      "+ plus bullet",
      "",
      "1) paren ordered",
      "2) next ordered",
      "",
    ].join("\n");
    const expected = [
      "- asterisk bullet",
      "- plus bullet",
      "",
      "1. paren ordered",
      "2. next ordered",
      "",
    ].join("\n");
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    const state = await page.evaluate(() => {
      const rendered = document.getElementById("rendered");
      const source = document.getElementById("source-view");
      if (!rendered || !source) throw new Error("missing literal layers");
      const rectForText = (root: Element, needle: string) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          const offset = text.indexOf(needle);
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            const rect = range.getBoundingClientRect();
            return { left: rect.left, top: rect.top };
          }
        }
        throw new Error(`missing ${needle}`);
      };
      return {
        renderedText: rendered.textContent,
        sourceText: source.textContent,
        points: ["asterisk", "plus", "paren", "next"].map((needle) => ({
          needle,
          rendered: rectForText(rendered, needle),
          source: rectForText(source, needle),
        })),
      };
    });

    expect(state.renderedText).toBe(expected);
    expect(state.sourceText).toBe(expected);
    for (const point of state.points) {
      expect(Math.abs(point.rendered.left - point.source.left), point.needle)
        .toBeLessThan(1);
      expect(Math.abs(point.rendered.top - point.source.top), point.needle)
        .toBeLessThan(1);
    }
  });

  test("overlay screenshot: source view vs rendered view align", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate((md) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = md;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, SAMPLES.find((s) => s.name === "mixed")!.md);
    await page.locator("#overlay-toggle").check();
    // Give the layout a frame to settle.
    await page.waitForTimeout(50);

    // Capture each layer at the same coordinates. Under monospace +
    // `white-space: pre-wrap`, the two layers should overlap exactly;
    // we screenshot the host element so it includes both.
    const host = page.locator("#host");
    await expect(host).toHaveScreenshot("literal-overlay-mixed.png", {
      maxDiffPixelRatio: 0.02,
    });
  });

  test("overlay VRT: edit roundtrip rendered layer matches source layer pixels", async ({ page }) => {
    await page.setViewportSize({ width: 968, height: 572 });
    await page.goto("/literal/");
    await page.evaluate(
      (md) => {
        const ta = document.getElementById("source") as HTMLTextAreaElement;
        ta.value = md;
        ta.dispatchEvent(new Event("input", { bubbles: true }));
      },
      [
        "# Compression Dictionary Transport 用の Toolkit",
        "",
        "## Intro",
        "",
        "CDT は あらかじめ辞書を作って クライアントに取得させておき、それを用いて 転送を圧縮することができる。",
        "",
        "- コマンドラインツール `cdt-toolkit` を定義した",
        "  - Rust で実装し crates.io で公開中",
        "- 詳細は <https://github.com/example/cdt-toolkit> を参照",
        "",
      ].join("\n"),
    );
    await page.locator("#overlay-toggle").check();
    await page.evaluate(() => document.fonts.ready);

    await page.locator("#rendered h1").click();
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.keyboard.press("Escape");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
    await page.waitForTimeout(50);

    const host = page.locator("#host");
    const normalizeLayers = `
      #host { background: #161b22 !important; }
      #source-view,
      #rendered {
        background: transparent !important;
        color: #fff !important;
        opacity: 1 !important;
      }
      #source-view [class^="md-src-"],
      #rendered,
      #rendered * {
        background: transparent !important;
        box-shadow: none !important;
        color: #fff !important;
        font: inherit !important;
        opacity: 1 !important;
        text-decoration: none !important;
      }
    `;
    const sourcePng = await host.screenshot({
      style: `${normalizeLayers}
        #rendered { visibility: hidden !important; }
        #source-view { visibility: visible !important; }
      `,
    });
    const renderedPng = await host.screenshot({
      style: `${normalizeLayers}
        #source-view { visibility: hidden !important; }
        #rendered { visibility: visible !important; }
      `,
    });
    const diff = await page.evaluate(
      async ({ rendered, source }) => {
        const decode = async (base64: string) => {
          const img = new Image();
          img.src = `data:image/png;base64,${base64}`;
          await img.decode();
          const canvas = document.createElement("canvas");
          canvas.width = img.naturalWidth;
          canvas.height = img.naturalHeight;
          const ctx = canvas.getContext("2d");
          if (!ctx) throw new Error("missing 2d canvas context");
          ctx.drawImage(img, 0, 0);
          return {
            width: canvas.width,
            height: canvas.height,
            data: ctx.getImageData(0, 0, canvas.width, canvas.height).data,
          };
        };
        const renderedImage = await decode(rendered);
        const sourceImage = await decode(source);
        if (
          renderedImage.width !== sourceImage.width ||
          renderedImage.height !== sourceImage.height
        ) {
          throw new Error(
            `screenshot size mismatch: rendered ${renderedImage.width}x${renderedImage.height}, ` +
              `source ${sourceImage.width}x${sourceImage.height}`,
          );
        }
        let mismatched = 0;
        for (let i = 0; i < renderedImage.data.length; i += 4) {
          const dr = Math.abs(renderedImage.data[i]! - sourceImage.data[i]!);
          const dg = Math.abs(
            renderedImage.data[i + 1]! - sourceImage.data[i + 1]!,
          );
          const db = Math.abs(
            renderedImage.data[i + 2]! - sourceImage.data[i + 2]!,
          );
          const da = Math.abs(
            renderedImage.data[i + 3]! - sourceImage.data[i + 3]!,
          );
          if (dr + dg + db + da > 8) mismatched++;
        }
        const total = renderedImage.width * renderedImage.height;
        return {
          mismatched,
          total,
          ratio: mismatched / total,
        };
      },
      {
        rendered: renderedPng.toString("base64"),
        source: sourcePng.toString("base64"),
      },
    );
    expect(diff.ratio, JSON.stringify(diff)).toBeLessThan(0.002);
  });

  // Click on a known glyph in the preview, then verify that the textarea
  // ends up focused with its caret at the correct source offset.
  test("click-to-cursor: heading marker maps to source position 0", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "# Title\n\nbody paragraph\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Click the very first character of the rendered output — the '#' of
    // the heading marker. Its source offset is 0.
    const h1 = page.locator("#rendered h1");
    const box = await h1.boundingBox();
    if (!box) throw new Error("h1 has no bounding box");
    // Click 2px in from the left edge to land on the first `#`.
    await page.mouse.click(box.x + 2, box.y + box.height / 2);
    // The demo flips into edit mode and focuses the textarea (via rAF)
    // with the cursor at offset 0.
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    const caret = await page.evaluate(
      () =>
        (document.getElementById("source") as HTMLTextAreaElement)
          .selectionStart,
    );
    expect(caret).toBe(0);
  });

  test("click-to-cursor: clicking inside body paragraph lands inside body", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "# Title\n\nbody paragraph\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Click roughly the middle of the rendered <p> ("body paragraph").
    const p = page.locator("#rendered p");
    const box = await p.boundingBox();
    if (!box) throw new Error("p has no bounding box");
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    const caret = await page.evaluate(
      () =>
        (document.getElementById("source") as HTMLTextAreaElement)
          .selectionStart,
    );
    // "# Title\n\n" is 9 chars; "body paragraph\n" is 15. The paragraph
    // sits at source offsets 9..23. A click in the middle of the paragraph
    // must land somewhere in that range.
    expect(caret).toBeGreaterThanOrEqual(9);
    expect(caret).toBeLessThanOrEqual(23);
  });

  test("click-to-cursor: normalized list marker maps to the raw marker offset", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "* one\n+ two\n1) three\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    const markerPoint = await page.evaluate(() => {
      const root = document.getElementById("rendered");
      if (!root) throw new Error("missing rendered layer");
      const marker = root.querySelector(".md-src-list-marker, .md-marker") ??
        root.firstElementChild;
      if (!marker) throw new Error("missing list marker");
      const rect = marker.getBoundingClientRect();
      return { x: rect.left + 2, y: rect.top + rect.height / 2 };
    });

    await page.mouse.click(markerPoint.x, markerPoint.y);
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    const caret = await page.evaluate(
      () =>
        (document.getElementById("source") as HTMLTextAreaElement)
          .selectionStart,
    );
    expect(caret).toBe(0);
  });

  test("preview-mode → edit-mode flip on click", async ({ page }) => {
    await page.goto("/literal/");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
    const h1 = page.locator("#rendered h1").first();
    await h1.click();
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    // Pressing Escape returns to preview mode.
    await page.keyboard.press("Escape");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
  });

  test("click-to-editor: starts highlighted markdown editor without source-layer layout shift", async ({ page }) => {
    const md = "# Title\n\nThis paragraph has **bold** and `code`.\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    const rectForText = (selector: string, needle: string) =>
      page.evaluate(
        ({ selector, needle }) => {
          const root = document.querySelector(selector);
          if (!root) throw new Error(`missing ${selector}`);
          const host = document.getElementById("host");
          if (!host) throw new Error("missing #host");
          const hostRect = host.getBoundingClientRect();
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const text = node.textContent ?? "";
            const offset = text.indexOf(needle);
            if (offset >= 0) {
              const range = document.createRange();
              range.setStart(node, offset);
              range.setEnd(node, offset + 1);
              const rect = range.getBoundingClientRect();
              return {
                left: rect.left - hostRect.left,
                top: rect.top - hostRect.top,
              };
            }
          }
          throw new Error(`missing ${needle}`);
        },
        { selector, needle },
      );

    const before = await rectForText("#source-view", "Title");
    await page.locator("#rendered h1").click();

    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await expect(page.locator("#source-view .md-src-heading-marker"))
      .toHaveCount(1);
    await expect(page.locator("#source-view .md-src-heading")).toHaveText(
      "Title",
    );
    await expect(page.locator("#source-view .md-src-strong")).toHaveText(
      "**bold**",
    );
    await expect(page.locator("#source-view .md-src-code")).toHaveText("code");
    const syntaxStyles = await page.evaluate(() => {
      const strong = document.querySelector("#source-view .md-src-strong");
      const em = document.querySelector("#source-view .md-src-em");
      const code = document.querySelector("#source-view .md-src-code");
      if (!strong || !code) throw new Error("missing syntax highlight spans");
      return {
        strongWeight: getComputedStyle(strong).fontWeight,
        emStyle: em ? getComputedStyle(em).fontStyle : "normal",
        codeColor: getComputedStyle(code).color,
        sourceColor:
          getComputedStyle(document.getElementById("source-view")!).color,
      };
    });
    expect(syntaxStyles.strongWeight).not.toBe("700");
    expect(syntaxStyles.emStyle).toBe("normal");
    expect(syntaxStyles.codeColor).not.toBe(syntaxStyles.sourceColor);

    const after = await rectForText("#source-view", "Title");
    expect(Math.abs(after.left - before.left)).toBeLessThan(1);
    expect(Math.abs(after.top - before.top)).toBeLessThan(1);

    const sourceLayerText = await page.locator("#source-view").evaluate((el) =>
      el.textContent
    );
    expect(sourceLayerText).toBe(md);
    const textareaColor = await page.locator("#source").evaluate((el) =>
      getComputedStyle(el).color
    );
    expect(textareaColor).toBe("rgba(0, 0, 0, 0)");
  });

  test("edit-mode textarea grows to content instead of scrolling the source layer", async ({ page }) => {
    const md = Array.from(
      { length: 80 },
      (_, i) => `line ${String(i + 1).padStart(2, "0")}`,
    )
      .join("\n") + "\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");

    const beforeScroll = await page.evaluate(() => {
      const host = document.getElementById("host");
      const source = document.getElementById("source-view");
      const textarea = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!host || !source || !textarea) throw new Error("missing nodes");
      const hostRect = host.getBoundingClientRect();
      const sourceRect = source.getBoundingClientRect();
      return {
        hostHeight: hostRect.height,
        hostLeft: hostRect.left,
        hostTop: hostRect.top,
        sourceLeft: sourceRect.left,
        sourceTop: sourceRect.top,
        sourceTransform: getComputedStyle(source).transform,
        textareaClientHeight: textarea.clientHeight,
        textareaScrollHeight: textarea.scrollHeight,
        textareaScrollTop: textarea.scrollTop,
      };
    });

    const afterScrollAttempt = await page.evaluate(() => {
      const textarea = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      const source = document.getElementById("source-view");
      const host = document.getElementById("host");
      if (!textarea || !source || !host) throw new Error("missing nodes");
      textarea.scrollTop = 192;
      textarea.scrollLeft = 12;
      textarea.dispatchEvent(new Event("scroll", { bubbles: true }));
      const hostRect = host.getBoundingClientRect();
      const sourceRect = source.getBoundingClientRect();
      return {
        hostLeft: hostRect.left,
        hostTop: hostRect.top,
        sourceLeft: sourceRect.left,
        sourceTop: sourceRect.top,
        sourceTransform: getComputedStyle(source).transform,
        textareaClientHeight: textarea.clientHeight,
        textareaScrollHeight: textarea.scrollHeight,
        textareaScrollLeft: textarea.scrollLeft,
        textareaScrollTop: textarea.scrollTop,
      };
    });

    expect(beforeScroll.hostHeight).toBeGreaterThan(1000);
    expect(beforeScroll.textareaClientHeight).toBeGreaterThanOrEqual(
      beforeScroll.textareaScrollHeight - 1,
    );
    expect(beforeScroll.textareaScrollTop).toBe(0);
    expect(beforeScroll.sourceTransform).toBe("none");
    expect(beforeScroll.sourceLeft).toBeCloseTo(beforeScroll.hostLeft, 1);
    expect(beforeScroll.sourceTop).toBeCloseTo(beforeScroll.hostTop, 1);

    expect(afterScrollAttempt.textareaClientHeight).toBeGreaterThanOrEqual(
      afterScrollAttempt.textareaScrollHeight - 1,
    );
    expect(afterScrollAttempt.textareaScrollLeft).toBe(0);
    expect(afterScrollAttempt.textareaScrollTop).toBe(0);
    expect(afterScrollAttempt.sourceTransform).toBe("none");
    expect(afterScrollAttempt.sourceLeft).toBeCloseTo(
      afterScrollAttempt.hostLeft,
      1,
    );
    expect(afterScrollAttempt.sourceTop).toBeCloseTo(
      afterScrollAttempt.hostTop,
      1,
    );
  });

  test("edit-mode trailing Enter keeps caret at the document end while growing", async ({ page }) => {
    const md = Array.from(
      { length: 42 },
      (_, i) => `line ${String(i + 1).padStart(2, "0")}`,
    )
      .join("\n");
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
    });

    const before = await page.evaluate(() => {
      const host = document.getElementById("host");
      const ta = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!host || !ta) throw new Error("missing nodes");
      return {
        hostHeight: host.getBoundingClientRect().height,
        selectionStart: ta.selectionStart,
        valueLength: ta.value.length,
      };
    });

    for (let i = 0; i < 12; i++) {
      await page.keyboard.press("Enter");
    }
    await page.waitForTimeout(50);

    const after = await page.evaluate(() => {
      const host = document.getElementById("host");
      const ta = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!host || !ta) throw new Error("missing nodes");
      return {
        clientHeight: ta.clientHeight,
        hostHeight: host.getBoundingClientRect().height,
        scrollHeight: ta.scrollHeight,
        scrollTop: ta.scrollTop,
        selectionEnd: ta.selectionEnd,
        selectionStart: ta.selectionStart,
        value: ta.value,
        valueLength: ta.value.length,
      };
    });

    expect(before.selectionStart).toBe(before.valueLength);
    expect(after.value.endsWith("\n".repeat(12))).toBe(true);
    expect(after.selectionStart).toBe(after.valueLength);
    expect(after.selectionEnd).toBe(after.valueLength);
    expect(after.scrollTop).toBe(0);
    expect(after.clientHeight).toBeGreaterThanOrEqual(after.scrollHeight - 1);
    expect(after.hostHeight).toBeGreaterThanOrEqual(before.hostHeight);
  });

  test("edit-mode trailing Enter preserves page scroll near the caret", async ({ page }) => {
    const md = Array.from(
      { length: 120 },
      (_, i) => `line ${String(i + 1).padStart(3, "0")}`,
    )
      .join("\n");
    await page.setViewportSize({ width: 900, height: 520 });
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
      window.scrollTo(0, document.documentElement.scrollHeight);
    });

    const before = await page.evaluate(() => ({
      documentHeight: document.documentElement.scrollHeight,
      scrollY: window.scrollY,
    }));

    await page.keyboard.press("Enter");
    await page.waitForTimeout(50);

    const after = await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      return {
        documentHeight: document.documentElement.scrollHeight,
        selectionStart: ta.selectionStart,
        scrollY: window.scrollY,
        valueLength: ta.value.length,
      };
    });

    expect(before.scrollY).toBeGreaterThan(500);
    expect(after.selectionStart).toBe(after.valueLength);
    expect(after.documentHeight).toBeGreaterThanOrEqual(before.documentHeight);
    expect(after.scrollY).toBeGreaterThan(before.scrollY - 80);
  });

  test("edit-mode keeps a bottom scroll reserve for the trailing caret", async ({ page }) => {
    const md = Array.from(
      { length: 64 },
      (_, i) => `line ${String(i + 1).padStart(2, "0")}`,
    )
      .join("\n");
    await page.setViewportSize({ width: 900, height: 420 });
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
      window.scrollTo(0, document.documentElement.scrollHeight);
    });

    for (let i = 0; i < 8; i++) {
      await page.keyboard.press("Enter");
    }
    await page.waitForTimeout(50);

    const state = await page.evaluate(() => {
      const stage = document.querySelector(".stage");
      const ta = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!stage || !ta) throw new Error("missing nodes");
      const stageBottom = stage.getBoundingClientRect().bottom + window.scrollY;
      return {
        bottomGap: document.documentElement.scrollHeight - stageBottom,
        selectionStart: ta.selectionStart,
        valueLength: ta.value.length,
        visualBottom: estimateTextareaCaretBottom(ta),
        viewportHeight: window.innerHeight,
      };

      function estimateTextareaCaretBottom(el: HTMLTextAreaElement): number {
        const style = getComputedStyle(el);
        const fontSize = Number.parseFloat(style.fontSize);
        const lineHeight = Number.parseFloat(style.lineHeight) ||
          fontSize * 1.6;
        const charWidth = measureCharWidth(style);
        const contentWidth = Math.max(1, el.clientWidth);
        const columns = Math.max(1, Math.floor(contentWidth / charWidth));
        const before = el.value.slice(0, el.selectionStart);
        const lines = before.split("\n");
        let visualLine = 0;
        for (let i = 0; i < lines.length; i++) {
          if (i > 0) visualLine += 1;
          visualLine += Math.max(0, Math.ceil(lines[i]!.length / columns) - 1);
        }
        return el.getBoundingClientRect().top + visualLine * lineHeight +
          lineHeight;
      }

      function measureCharWidth(style: CSSStyleDeclaration): number {
        const canvas = document.createElement("canvas");
        const ctx = canvas.getContext("2d");
        if (!ctx) return 8;
        ctx.font =
          `${style.fontStyle} ${style.fontVariant} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
        return Math.max(1, ctx.measureText("M").width);
      }
    });

    expect(state.selectionStart).toBe(state.valueLength);
    expect(state.bottomGap).toBeGreaterThanOrEqual(96);
    expect(state.visualBottom).toBeLessThanOrEqual(state.viewportHeight - 48);
  });

  test("edit-mode repeated trailing Enter grows past the minimum height without resetting caret", async ({ page }) => {
    const md = "# Title\n\nshort body";
    await page.setViewportSize({ width: 900, height: 520 });
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered h1").click();
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
    });

    for (let i = 0; i < 40; i++) {
      await page.keyboard.press("Enter");
    }
    await page.waitForTimeout(50);

    const state = await page.evaluate(() => {
      const host = document.getElementById("host");
      const ta = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!host || !ta) throw new Error("missing nodes");
      return {
        clientHeight: ta.clientHeight,
        hostHeight: host.getBoundingClientRect().height,
        scrollHeight: ta.scrollHeight,
        scrollTop: ta.scrollTop,
        selectionEnd: ta.selectionEnd,
        selectionStart: ta.selectionStart,
        viewportHeight: window.innerHeight,
        windowScrollY: window.scrollY,
        value: ta.value,
        valueLength: ta.value.length,
      };
    });

    expect(state.value.endsWith("\n".repeat(40))).toBe(true);
    expect(state.selectionStart).toBe(state.valueLength);
    expect(state.selectionEnd).toBe(state.valueLength);
    expect(state.scrollTop).toBe(0);
    expect(state.clientHeight).toBeGreaterThanOrEqual(state.scrollHeight - 1);
    expect(state.hostHeight).toBeGreaterThan(700);
    expect(state.windowScrollY).toBeGreaterThan(100);
  });

  test("image preview: repeated trailing Enter keeps caret visible after reserved inline slot", async ({ page }) => {
    const md = "before ![cat:w260](/images/literal-preview-a.svg) after";
    await page.setViewportSize({ width: 620, height: 420 });
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);
    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
    });

    for (let i = 0; i < 34; i++) {
      await page.keyboard.press("Enter");
    }
    await page.waitForTimeout(50);

    const state = await page.evaluate(() => {
      const host = document.getElementById("host");
      const source = document.getElementById("source-view");
      const ta = document.getElementById("source") as
        | HTMLTextAreaElement
        | null;
      if (!host || !source || !ta) throw new Error("missing nodes");
      return {
        clientHeight: ta.clientHeight,
        hostHeight: host.getBoundingClientRect().height,
        scrollHeight: ta.scrollHeight,
        scrollTop: ta.scrollTop,
        selectionEnd: ta.selectionEnd,
        selectionStart: ta.selectionStart,
        sourceHeight: source.scrollHeight,
        valueLength: ta.value.length,
        windowScrollY: window.scrollY,
      };
    });

    expect(state.selectionStart).toBe(state.valueLength);
    expect(state.selectionEnd).toBe(state.valueLength);
    expect(state.scrollTop).toBe(0);
    expect(state.clientHeight).toBeGreaterThanOrEqual(state.scrollHeight - 1);
    expect(state.hostHeight).toBeGreaterThanOrEqual(state.sourceHeight - 1);
    expect(state.windowScrollY).toBeGreaterThan(100);
  });

  test("preview overlay stays monochrome and aligned after edit roundtrip", async ({ page }) => {
    const md = "# Title\n\nalpha *italic* beta **bold** gamma `code` delta\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#rendered h1").click();
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.keyboard.press("Escape");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");

    const state = await page.evaluate(() => {
      const rectForText = (selector: string, needle: string) => {
        const root = document.querySelector(selector);
        if (!root) throw new Error(`missing ${selector}`);
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          const offset = text.indexOf(needle);
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            const rect = range.getBoundingClientRect();
            return { left: rect.left, top: rect.top };
          }
        }
        throw new Error(`missing ${needle}`);
      };
      const sourceView = document.getElementById("source-view");
      const code = document.querySelector("#source-view .md-src-code");
      if (!sourceView || !code) throw new Error("missing source layer");
      return {
        sourceColor: getComputedStyle(sourceView).color,
        codeColor: getComputedStyle(code).color,
        points: ["beta", "gamma", "delta"].map((needle) => ({
          needle,
          rendered: rectForText("#rendered", needle),
          source: rectForText("#source-view", needle),
        })),
      };
    });

    expect(state.codeColor).toBe(state.sourceColor);
    for (const point of state.points) {
      expect(Math.abs(point.rendered.left - point.source.left), point.needle)
        .toBeLessThan(1);
      expect(Math.abs(point.rendered.top - point.source.top), point.needle)
        .toBeLessThan(1);
    }
  });

  test("blank lines: literal preview preserves source vertical grid", async ({ page }) => {
    const md = [
      "# Title",
      "body without blank before it",
      "",
      "",
      "- one",
      "- two",
      "",
      "> quote after list",
      "",
    ].join("\n");
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);
    await expect(page.locator("#invariant-state")).toHaveText(
      /literal DOM matches fresh render/,
    );

    const state = await page.evaluate(() => {
      const rectForText = (selector: string, needle: string) => {
        const root = document.querySelector(selector);
        if (!root) throw new Error(`missing ${selector}`);
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          const offset = text.indexOf(needle);
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            const rect = range.getBoundingClientRect();
            return { left: rect.left, top: rect.top };
          }
        }
        throw new Error(`missing ${needle}`);
      };
      return {
        renderedText: document.getElementById("rendered")?.textContent,
        points: ["body without", "one", "two", "quote after"].map((needle) => ({
          needle,
          rendered: rectForText("#rendered", needle),
          source: rectForText("#source-view", needle),
        })),
      };
    });

    expect(state.renderedText).toBe(
      "# Title\nbody without blank before it\n\n\n- one\n- two\n\n> quote after list\n",
    );
    for (const point of state.points) {
      expect(Math.abs(point.rendered.left - point.source.left), point.needle)
        .toBeLessThan(1);
      expect(Math.abs(point.rendered.top - point.source.top), point.needle)
        .toBeLessThan(1);
    }
  });

  test("partial update: unchanged blocks keep their DOM identity", async ({ page }) => {
    await page.goto("/literal/");
    // Use the textarea API to set the source we want to start from.
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "# Stable heading\n\nfirst paragraph\n\nsecond paragraph\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Capture node-identity refs by their initial position.
    await page.evaluate(() => {
      const win = window as unknown as { __initial: HTMLElement[] };
      win.__initial = Array.from(
        (document.getElementById("rendered") as HTMLElement).children,
      ) as HTMLElement[];
    });
    // Edit only the second paragraph by appending text. The heading and
    // first paragraph nodes must be the same JS objects after the patch.
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value =
        "# Stable heading\n\nfirst paragraph\n\nsecond paragraph plus extra\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    const identity = await page.evaluate(() => {
      const win = window as unknown as { __initial: HTMLElement[] };
      const now = Array.from(
        (document.getElementById("rendered") as HTMLElement).children,
      );
      return win.__initial.map((node, i) => now[i] === node);
    });
    expect(identity[0]).toBe(true); // heading reused
    expect(identity[1]).toBe(true); // first paragraph reused
    expect(identity[2]).toBe(false); // second paragraph replaced
    // Patch stats badge reports exactly one replaced element (the
    // changed paragraph); reused count includes text-node separators so
    // we only assert non-zero rather than an exact value.
    const stats = await page.locator("#patch-stats").innerText();
    expect(stats).toContain("replaced 1");
    expect(stats).toMatch(/reused \d+/);
  });

  test("image preview: toggle inserts <img> without breaking the overlay invariant", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "intro\n\n![cat](/images/literal-preview-a.svg)\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Off by default: no <img> in the output.
    expect(await page.locator("#rendered img.md-image-preview").count()).toBe(
      0,
    );
    // Toggle on.
    await page.locator("#image-preview-toggle").check();
    const imgCount = await page.locator("#rendered img.md-image-preview")
      .count();
    expect(imgCount).toBe(1);
    // The body still hosts the source characters.
    const text = await page.locator("#rendered").innerText();
    expect(text).toContain("![cat](/images/literal-preview-a.svg)");
    // The overlay invariant indicator stays green — img has empty textContent.
    await expect(page.locator("#invariant-state")).toHaveText(
      /literal DOM matches fresh render/,
    );
  });

  test("image preview: demo sample uses debuggable local images", async ({ page }) => {
    await page.goto("/literal/");
    await page.locator("#image-preview-toggle").check();

    const images = page.locator("#rendered img.md-image-preview");
    await expect(images).toHaveCount(3);
    await expect
      .poll(() =>
        images.evaluateAll((imgs) =>
          imgs.every((img) => {
            const image = img as HTMLImageElement;
            return image.complete && image.naturalWidth > 0 &&
              image.naturalHeight > 0;
          })
        )
      )
      .toBe(true);

    const states = await images.evaluateAll((imgs) =>
      imgs.map((img) => {
        const image = img as HTMLImageElement;
        return {
          pathname: new URL(image.currentSrc || image.src, window.location.href)
            .pathname,
          complete: image.complete,
          naturalWidth: image.naturalWidth,
          naturalHeight: image.naturalHeight,
        };
      })
    );

    expect(states).toEqual([
      expect.objectContaining({
        pathname: "/images/literal-preview-a.svg",
        complete: true,
        naturalWidth: expect.any(Number),
        naturalHeight: expect.any(Number),
      }),
      expect.objectContaining({
        pathname: "/images/literal-preview-b.svg",
        complete: true,
        naturalWidth: expect.any(Number),
        naturalHeight: expect.any(Number),
      }),
      expect.objectContaining({
        pathname: "/images/literal-preview-a.svg",
        complete: true,
        naturalWidth: expect.any(Number),
        naturalHeight: expect.any(Number),
      }),
    ]);
    for (const state of states) {
      expect(state.naturalWidth).toBeGreaterThan(0);
      expect(state.naturalHeight).toBeGreaterThan(0);
    }
  });

  test("image preview: thumbnail does not interrupt the markdown source text", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "before ![cat](/images/literal-preview-a.svg)\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    const markerLeftWithoutPreview = await page
      .locator("#rendered .md-image .md-marker")
      .first()
      .boundingBox()
      .then((box) => {
        if (!box) throw new Error("missing image marker box");
        return box.x;
      });

    await page.locator("#image-preview-toggle").check();

    const layout = await page.evaluate(() => {
      const image = document.querySelector("#rendered .md-image-preview") as
        | HTMLImageElement
        | null;
      const markers = Array.from(
        document.querySelectorAll("#rendered .md-image .md-marker"),
      ) as HTMLElement[];
      if (!image || markers.length === 0) {
        throw new Error("missing image preview or markers");
      }
      const imageRect = image.getBoundingClientRect();
      const markerRects = markers.map((marker) =>
        marker.getBoundingClientRect()
      );
      return {
        imageLeft: imageRect.left,
        firstMarkerLeft: markerRects[0]!.left,
        lastMarkerRight: markerRects[markerRects.length - 1]!.right,
      };
    });

    expect(layout.firstMarkerLeft).toBeCloseTo(markerLeftWithoutPreview, 0);
    expect(layout.imageLeft).toBeGreaterThanOrEqual(layout.lastMarkerRight);
  });

  test("image preview: alt :wN reserves width and blocks cursor placement", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "before ![cat:w120](/images/literal-preview-a.svg) after\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    const followingTextLeft = () =>
      page.evaluate(() => {
        const rendered = document.getElementById("rendered");
        if (!rendered) throw new Error("missing rendered");
        const walker = document.createTreeWalker(
          rendered,
          NodeFilter.SHOW_TEXT,
        );
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const offset = node.textContent?.indexOf(" after") ?? -1;
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            const rect = range.getBoundingClientRect();
            return rect.left;
          }
        }
        throw new Error("missing following text");
      });

    const afterLeftWithoutPreview = await followingTextLeft();

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.locator("#rendered img.md-image-preview").first().evaluate(
          (img) => {
            const image = img as HTMLImageElement;
            return image.complete && image.naturalWidth > 0 &&
              image.naturalHeight > 0;
          },
        )
      )
      .toBe(true);

    const afterLeftWithPreview = await followingTextLeft();
    const slot = page.locator("#rendered .md-image-preview-slot").first();
    await expect(slot).toHaveAttribute("data-md-image-width", "120");
    await expect(slot).toHaveAttribute("contenteditable", "false");
    const slotBox = await slot.boundingBox();
    if (!slotBox) throw new Error("missing image preview slot box");
    expect(slotBox.width).toBeCloseTo(120, 0);

    expect(afterLeftWithPreview - afterLeftWithoutPreview).toBeGreaterThan(116);

    await page.mouse.click(
      slotBox.x + slotBox.width / 2,
      slotBox.y + slotBox.height / 2,
    );
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id)).not
      .toBe("source");

    await expect(page.locator("#rendered img.md-image-preview").first())
      .toHaveAttribute("alt", "cat");
  });

  test("image preview: edit-mode textarea does not place caret inside reserved image slots", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "before ![cat:w120](/images/literal-preview-a.svg) after\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);
    const textBox = await page.locator("#rendered p").boundingBox();
    if (!textBox) throw new Error("missing paragraph box");
    await page.mouse.click(textBox.x + 2, textBox.y + textBox.height / 2);
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(0, 0);
    });
    const slotBox = await page.locator("#source-view .md-image-preview-slot")
      .first().boundingBox();
    if (!slotBox) throw new Error("missing source image preview slot box");
    await page.mouse.click(
      slotBox.x + slotBox.width / 2,
      slotBox.y + slotBox.height / 2,
    );

    const caret = await page.evaluate(
      () =>
        (document.getElementById("source") as HTMLTextAreaElement)
          .selectionStart,
    );
    expect(caret).toBe(0);
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
  });

  test("image preview: edit-mode source layer shows the reserved image overlay", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "before ![cat:w120](/images/literal-preview-a.svg) after\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);

    const textBox = await page.locator("#rendered p").boundingBox();
    if (!textBox) throw new Error("missing paragraph box");
    await page.mouse.click(textBox.x + 2, textBox.y + textBox.height / 2);
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    const state = await page.evaluate(() => {
      const slot = document.querySelector(
        "#source-view .md-image-preview-slot",
      ) as HTMLElement | null;
      const image = document.querySelector(
        "#source-view img.md-image-preview",
      ) as HTMLImageElement | null;
      if (!slot || !image) throw new Error("missing source image slot");
      const slotRect = slot.getBoundingClientRect();
      const imageRect = image.getBoundingClientRect();
      return {
        imageAlt: image.alt,
        imageVisibility: getComputedStyle(image).visibility,
        imageWidth: imageRect.width,
        slotWidth: slotRect.width,
      };
    });

    expect(state.imageAlt).toBe("cat");
    expect(state.imageVisibility).toBe("visible");
    expect(state.slotWidth).toBeCloseTo(120, 0);
    expect(state.imageWidth).toBeCloseTo(120, 0);
  });

  test("image preview: edit-mode source image stays mounted while surrounding text updates", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "before ![cat:w120](/images/literal-preview-a.svg) after\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const img = document.querySelector(
            "#source-view img.md-image-preview",
          ) as HTMLImageElement | null;
          return img?.complete === true && img.naturalWidth > 0 &&
            img.naturalHeight > 0;
        })
      )
      .toBe(true);

    const textBox = await page.locator("#rendered p").boundingBox();
    if (!textBox) throw new Error("missing paragraph box");
    await page.mouse.click(textBox.x + 2, textBox.y + textBox.height / 2);
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");

    await page.evaluate(() => {
      const win = window as unknown as { __sourceImage: HTMLImageElement };
      win.__sourceImage = document.querySelector(
        "#source-view img.md-image-preview",
      ) as HTMLImageElement;
    });

    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value =
        "before edited ![cat:w120](/images/literal-preview-a.svg) after\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    const sameNode = await page.evaluate(() => {
      const win = window as unknown as { __sourceImage: HTMLImageElement };
      return document.querySelector("#source-view img.md-image-preview") ===
        win.__sourceImage;
    });
    expect(sameNode).toBe(true);
  });

  test("image preview: edit-mode caret is drawn on the highlighted source grid after reserved slots", async ({ page }) => {
    const md = "before ![cat:w160](/images/literal-preview-a.svg) after\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      const offset = ta.value.indexOf(" after");
      ta.setSelectionRange(offset, offset);
      document.dispatchEvent(new Event("selectionchange"));
    });

    await expect
      .poll(() =>
        page.evaluate(() => {
          const caret = document.getElementById("source-caret");
          const source = document.getElementById("source-view");
          if (!caret || !source) return Number.POSITIVE_INFINITY;
          const walker = document.createTreeWalker(
            source,
            NodeFilter.SHOW_TEXT,
          );
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const text = node.textContent ?? "";
            const offset = text.indexOf(" after");
            if (offset >= 0) {
              const range = document.createRange();
              range.setStart(node, offset);
              range.setEnd(node, offset + 1);
              const rect = range.getBoundingClientRect();
              const caretRect = caret.getBoundingClientRect();
              return Math.abs(caretRect.left - rect.left);
            }
          }
          return Number.POSITIVE_INFINITY;
        })
      )
      .toBeLessThan(1);

    const state = await page.evaluate(() => {
      const caret = document.getElementById("source-caret");
      const source = document.getElementById("source-view");
      if (!caret || !source) throw new Error("missing caret/source layer");
      const walker = document.createTreeWalker(source, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.textContent ?? "";
        const offset = text.indexOf(" after");
        if (offset >= 0) {
          const range = document.createRange();
          range.setStart(node, offset);
          range.setEnd(node, offset + 1);
          const rect = range.getBoundingClientRect();
          const caretRect = caret.getBoundingClientRect();
          return {
            caretDisplay: getComputedStyle(caret).display,
            caretLeft: caretRect.left,
            caretTop: caretRect.top,
            textLeft: rect.left,
            textTop: rect.top,
          };
        }
      }
      throw new Error("missing following text");
    });

    expect(state.caretDisplay).not.toBe("none");
    expect(Math.abs(state.caretLeft - state.textLeft)).toBeLessThan(1);
    expect(Math.abs(state.caretTop - state.textTop)).toBeLessThan(2);
  });

  test("image preview: composition anchor follows the shifted source caret", async ({ page }) => {
    const md = "before ![cat:w180](/images/literal-preview-a.svg) after\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    const state = await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      const offset = ta.value.indexOf(" after");
      ta.setSelectionRange(offset, offset);
      ta.dispatchEvent(
        new CompositionEvent("compositionstart", { bubbles: true, data: "あ" }),
      );
      const transform = getComputedStyle(ta).transform;
      if (transform === "none") return { tx: 0, transform };
      const values =
        transform.match(/matrix\(([^)]+)\)/)?.[1]?.split(",").map((v) =>
          Number(v.trim())
        ) ?? [];
      return { tx: values[4] ?? 0, transform };
    });

    expect(state.transform).not.toBe("none");
    expect(state.tx).toBeGreaterThan(80);
  });

  test("image preview: edit-mode caret on trailing blank line stays at line start", async ({ page }) => {
    const md =
      '```rust\nfn main() {\n    println!("hello");\n}\n```\n\nAaa\n\n';
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
      document.dispatchEvent(new Event("selectionchange"));
    });

    const state = await page.evaluate(() => {
      const caret = document.getElementById("source-caret");
      const source = document.getElementById("source-view");
      if (!caret || !source) throw new Error("missing nodes");
      const walker = document.createTreeWalker(source, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.textContent ?? "";
        const offset = text.indexOf("Aaa");
        if (offset >= 0) {
          const range = document.createRange();
          range.setStart(node, offset);
          range.setEnd(node, offset + 1);
          const anchor = range.getBoundingClientRect();
          const caretRect = caret.getBoundingClientRect();
          return {
            anchorLeft: anchor.left,
            caretDisplay: getComputedStyle(caret).display,
            caretLeft: caretRect.left,
          };
        }
      }
      throw new Error("missing Aaa");
    });
    expect(state.caretDisplay).not.toBe("none");
    expect(state.caretLeft).toBeCloseTo(state.anchorLeft, 1);
  });

  test("image preview: edit-mode caret after a single trailing newline stays at line start", async ({ page }) => {
    const md = "Aaa\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(ta.value.length, ta.value.length);
      document.dispatchEvent(new Event("selectionchange"));
    });

    const state = await page.evaluate(() => {
      const caret = document.getElementById("source-caret");
      const source = document.getElementById("source-view");
      if (!caret || !source) throw new Error("missing nodes");
      const walker = document.createTreeWalker(source, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.textContent ?? "";
        const offset = text.indexOf("Aaa");
        if (offset >= 0) {
          const range = document.createRange();
          range.setStart(node, offset);
          range.setEnd(node, offset + 1);
          const anchor = range.getBoundingClientRect();
          const caretRect = caret.getBoundingClientRect();
          return {
            anchorLeft: anchor.left,
            caretDisplay: getComputedStyle(caret).display,
            caretLeft: caretRect.left,
          };
        }
      }
      throw new Error("missing Aaa");
    });
    expect(state.caretDisplay).not.toBe("none");
    expect(state.caretLeft).toBeCloseTo(state.anchorLeft, 1);
  });

  test("image preview: edit-mode click after reserved slot maps to the highlighted source offset", async ({ page }) => {
    const md = "before ![cat:w160](/images/literal-preview-a.svg) after\n";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);

    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    const target = await page.evaluate(() => {
      const source = document.getElementById("source-view");
      if (!source) throw new Error("missing source layer");
      const walker = document.createTreeWalker(source, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.textContent ?? "";
        const offset = text.indexOf(" after");
        if (offset >= 0) {
          const range = document.createRange();
          range.setStart(node, offset + 1);
          range.setEnd(node, offset + 2);
          const rect = range.getBoundingClientRect();
          return { x: rect.left + 2, y: rect.top + rect.height / 2 };
        }
      }
      throw new Error("missing following text");
    });

    await page.mouse.click(target.x, target.y);
    const caret = await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      return ta.selectionStart;
    });
    expect(caret).toBe(md.indexOf(" after") + 1);
  });

  test("image preview: overlay source layer reserves the same image width", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value =
        "before ![cat:w120](/images/literal-preview-a.svg) after\nnext line\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#overlay-toggle").check();
    await page.locator("#image-preview-toggle").check();
    await expect
      .poll(() =>
        page.evaluate(() => {
          const images = Array.from(
            document.querySelectorAll(
              "#rendered img.md-image-preview, #source-view img.md-image-preview",
            ),
          ) as HTMLImageElement[];
          return images.length === 2 &&
            images.every((img) =>
              img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
            );
        })
      )
      .toBe(true);

    const rectForText = (selector: string, needle: string) =>
      page.evaluate(
        ({ selector, needle }) => {
          const root = document.querySelector(selector);
          if (!root) throw new Error(`missing ${selector}`);
          const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const text = node.textContent ?? "";
            const offset = text.indexOf(needle);
            if (offset >= 0) {
              const range = document.createRange();
              range.setStart(node, offset);
              range.setEnd(node, offset + 1);
              const rect = range.getBoundingClientRect();
              return { left: rect.left, top: rect.top };
            }
          }
          throw new Error(`missing ${needle}`);
        },
        { selector, needle },
      );

    const rendered = await rectForText("#rendered", " after");
    const source = await rectForText("#source-view", " after");
    expect(Math.abs(rendered.left - source.left)).toBeLessThan(1);
    expect(Math.abs(rendered.top - source.top)).toBeLessThan(1);

    await expect
      .poll(() =>
        page.locator("#source-view img.md-image-preview").first().evaluate(
          (img) => {
            return getComputedStyle(img).visibility;
          },
        )
      )
      .toBe("hidden");
  });

  test("image preview: standalone image markdown previews on the next line", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "![standalone](/images/literal-preview-a.svg)\nnext line\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#overlay-toggle").check();
    await page.locator("#image-preview-toggle").check();

    const slot = page.locator("#rendered .md-image-preview-block").first();
    await expect(slot).toBeVisible();
    const layout = await page.evaluate(() => {
      const rendered = document.getElementById("rendered");
      const source = document.getElementById("source-view");
      const slot = document.querySelector("#rendered .md-image-preview-block");
      if (!rendered || !source || !slot) {
        throw new Error("missing preview nodes");
      }
      const rectForText = (root: Element, needle: string) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          const offset = text.indexOf(needle);
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + 1);
            return range.getBoundingClientRect();
          }
        }
        throw new Error(`missing ${needle}`);
      };
      const url = rectForText(rendered, "/images/literal-preview-a.svg");
      const nextRendered = rectForText(rendered, "next line");
      const nextSource = rectForText(source, "next line");
      const slotRect = slot.getBoundingClientRect();
      const renderedRect = rendered.getBoundingClientRect();
      return {
        urlTop: url.top,
        slotTop: slotRect.top,
        slotLeft: slotRect.left,
        renderedLeft: renderedRect.left,
        renderedNextTop: nextRendered.top,
        sourceNextTop: nextSource.top,
      };
    });

    expect(layout.slotTop).toBeGreaterThan(layout.urlTop + 10);
    expect(Math.abs(layout.slotLeft - layout.renderedLeft)).toBeLessThan(1);
    expect(layout.renderedNextTop).toBeGreaterThan(layout.slotTop + 20);
    expect(Math.abs(layout.renderedNextTop - layout.sourceNextTop))
      .toBeLessThan(1);
    await expect
      .poll(() =>
        page.locator("#source-view .md-image-preview-block img").first()
          .evaluate((img) => {
            return getComputedStyle(img).visibility;
          })
      )
      .toBe("hidden");
  });

  test("image preview: bare image URL line does not emit a block preview", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "/images/literal-preview-a.svg\nnext line\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });

    await page.locator("#image-preview-toggle").check();
    await expect(page.locator("#rendered .md-image-preview-block")).toHaveCount(
      0,
    );
    await expect(page.locator("#source-view .md-image-preview-block"))
      .toHaveCount(0);
  });

  test("image preview: standalone image markdown line-end caret stays on the source line", async ({ page }) => {
    const line = "![standalone](/images/literal-preview-a.svg)";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, `${line}\nnext line\n`);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    await page.evaluate((offset) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.setSelectionRange(offset, offset);
    }, line.length - 1);
    await page.keyboard.press("ArrowRight");

    const state = await page.evaluate((sourceLine) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      const caret = document.getElementById("source-caret");
      const source = document.getElementById("source-view");
      const slot = document.querySelector(
        "#source-view .md-image-preview-block",
      );
      if (!caret || !source || !slot) throw new Error("missing nodes");
      const rectForVisibleOffset = (root: Element, sourceOffset: number) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let seen = 0;
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          if (sourceOffset < seen + text.length) {
            const range = document.createRange();
            range.setStart(node, sourceOffset - seen);
            range.setEnd(node, sourceOffset - seen + 1);
            return range.getBoundingClientRect();
          }
          seen += text.length;
        }
        throw new Error(`missing source offset ${sourceOffset}`);
      };
      const closeParen = rectForVisibleOffset(source, sourceLine.length - 1);
      return {
        caret: caret.getBoundingClientRect(),
        closeParen,
        selectionStart: ta.selectionStart,
        slot: slot.getBoundingClientRect(),
      };
    }, line);

    expect(state.selectionStart).toBe(line.length);
    expect(state.caret.top).toBeCloseTo(state.closeParen.top, 1);
    expect(state.caret.left).toBeGreaterThanOrEqual(state.closeParen.right - 2);
    expect(state.caret.top).toBeLessThan(state.slot.top - 4);
  });

  test("image preview: edit-mode source text can be drag-selected", async ({ page }) => {
    const line = "![standalone](/images/literal-preview-a.svg)";
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, `${line}\nnext line\n`);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    const points = await page.evaluate((sourceLine) => {
      const root = document.getElementById("source-view");
      if (!root) throw new Error("missing source view");
      const rectForVisibleOffset = (sourceOffset: number) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        let seen = 0;
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          if (sourceOffset < seen + text.length) {
            const range = document.createRange();
            range.setStart(node, sourceOffset - seen);
            range.setEnd(node, sourceOffset - seen + 1);
            const rect = range.getBoundingClientRect();
            return { x: rect.left + 1, y: rect.top + rect.height / 2 };
          }
          seen += text.length;
        }
        throw new Error(`missing source offset ${sourceOffset}`);
      };
      return {
        start: rectForVisibleOffset(0),
        end: rectForVisibleOffset(
          sourceLine.indexOf("preview") + "preview".length,
        ),
      };
    }, line);

    await page.mouse.move(points.start.x, points.start.y);
    await page.mouse.down();
    await page.mouse.move(points.end.x, points.end.y, { steps: 8 });
    await page.mouse.up();

    const selection = await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      return ta.value.slice(
        Math.min(ta.selectionStart, ta.selectionEnd),
        Math.max(ta.selectionStart, ta.selectionEnd),
      );
    });
    expect(selection).toContain("![standalone](/images/literal-preview");
  });

  test("image preview: edit-mode selection highlight follows the source-view layout", async ({ page }) => {
    const md = [
      "Inline image example: ![placeholder:w160](/images/literal-preview-a.svg)",
      "and ![another:w96](/images/literal-preview-b.svg).",
      "",
    ].join("\n");
    await page.goto("/literal/");
    await page.evaluate((source) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = source;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, md);

    await page.locator("#image-preview-toggle").check();
    await page.locator("#rendered").click({ position: { x: 4, y: 4 } });
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    await expect.poll(() => page.evaluate(() => document.activeElement?.id))
      .toBe("source");

    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      const start = ta.value.indexOf("![another");
      const end = ta.value.indexOf(").", start) + 1;
      ta.setSelectionRange(start, end);
      document.dispatchEvent(new Event("selectionchange"));
    });
    await expect
      .poll(() =>
        page.evaluate(() => {
          return document.querySelectorAll(
            "#source-selection .source-selection-rect",
          ).length;
        })
      )
      .toBeGreaterThan(0);

    const state = await page.evaluate(() => {
      const root = document.getElementById("source-view");
      const overlay = document.getElementById("source-selection");
      if (!root || !overlay) throw new Error("missing selection nodes");
      const rectForText = (needle: string) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const text = node.textContent ?? "";
          const offset = text.indexOf(needle);
          if (offset >= 0) {
            const range = document.createRange();
            range.setStart(node, offset);
            range.setEnd(node, offset + needle.length);
            return range.getBoundingClientRect();
          }
        }
        throw new Error(`missing ${needle}`);
      };
      const target = rectForText("another:w96");
      const rects = Array.from(
        overlay.querySelectorAll<HTMLElement>(".source-selection-rect"),
      )
        .map((rect) => rect.getBoundingClientRect())
        .filter((rect) => rect.width > 0 && rect.height > 0);
      const matching = rects.find((rect) =>
        Math.abs(rect.top - target.top) < 1 &&
        Math.abs(rect.left - target.left) < 1 &&
        Math.abs(rect.height - target.height) < 2
      );
      return {
        matchingWidth: matching?.width ?? 0,
        overlayDisplay: getComputedStyle(overlay).display,
        rectCount: rects.length,
        targetWidth: target.width,
      };
    });

    expect(state.overlayDisplay).not.toBe("none");
    expect(state.rectCount).toBeGreaterThan(0);
    expect(state.matchingWidth).toBeCloseTo(state.targetWidth, 0);
  });

  test("partial update: shifted blocks keep DOM identity, only attrs change", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "# heading\n\nfirst paragraph\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await page.evaluate(() => {
      const win = window as unknown as { __p: Element };
      win.__p = (document.getElementById("rendered") as HTMLElement)
        .querySelector("p")!;
    });
    // Edit the heading: trailing paragraph's `data-src-start` shifts but
    // its body is identical, so the patcher should update the attribute
    // in place rather than replacing the node.
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = "# heading XX\n\nfirst paragraph\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    const sameNode = await page.evaluate(() => {
      const win = window as unknown as { __p: Element };
      const p = (document.getElementById("rendered") as HTMLElement)
        .querySelector("p");
      return p === win.__p;
    });
    expect(sameNode).toBe(true);
    const stats = await page.locator("#patch-stats").innerText();
    expect(stats).toContain("shifted 1");
  });
});
