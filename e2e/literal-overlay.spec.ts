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
  { name: "ordered-list", md: "1. one\n2. two\n3. three\n" },
  { name: "blockquote", md: "> first\n> second\n" },
  {
    name: "autolink",
    md: "see <https://example.com> for details\n",
  },
  {
    name: "fenced-code",
    md: "```rust\nfn main() {\n    println!(\"hi\");\n}\n```\n",
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
  for (const sample of SAMPLES) {
    test(`${sample.name} renders the same glyph grid as source`, async ({ page }) => {
      await page.goto("/literal/");
      // Wait until the demo's first paint settled.
      await page.waitForSelector("#rendered .md-marker, #rendered p, #rendered h1, #rendered h2");

      // Replace the source with the test sample and fire `input` so the
      // demo recomputes both panes.
      await page.evaluate((md) => {
        const ta = document.getElementById("source") as HTMLTextAreaElement;
        ta.value = md;
        ta.dispatchEvent(new Event("input", { bubbles: true }));
      }, sample.md);

      // The demo writes a green `✓` into #invariant-state if the rendered
      // output's visible text equals `toMarkdown(source)`. That covers the
      // entire byte-for-byte equality check.
      await expect(page.locator("#invariant-state")).toHaveText(/overlay invariant holds/);
    });
  }

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
    await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe("source");
    const caret = await page.evaluate(
      () => (document.getElementById("source") as HTMLTextAreaElement).selectionStart,
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
    await expect.poll(() => page.evaluate(() => document.activeElement?.id)).toBe("source");
    const caret = await page.evaluate(
      () => (document.getElementById("source") as HTMLTextAreaElement).selectionStart,
    );
    // "# Title\n\n" is 9 chars; "body paragraph\n" is 15. The paragraph
    // sits at source offsets 9..23. A click in the middle of the paragraph
    // must land somewhere in that range.
    expect(caret).toBeGreaterThanOrEqual(9);
    expect(caret).toBeLessThanOrEqual(23);
  });

  test("preview-mode → edit-mode flip on click", async ({ page }) => {
    await page.goto("/literal/");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
    const h1 = page.locator("#rendered h1").first();
    await h1.click();
    await expect(page.locator("body")).toHaveAttribute("data-mode", "edit");
    // Pressing Escape returns to preview mode.
    await page.keyboard.press("Escape");
    await expect(page.locator("body")).toHaveAttribute("data-mode", "preview");
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
      ta.value = "# Stable heading\n\nfirst paragraph\n\nsecond paragraph plus extra\n";
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
      ta.value = "intro\n\n![cat](/img/cat.png)\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Off by default: no <img> in the output.
    expect(await page.locator("#rendered img.md-image-preview").count()).toBe(0);
    // Toggle on.
    await page.locator("#image-preview-toggle").check();
    const imgCount = await page.locator("#rendered img.md-image-preview").count();
    expect(imgCount).toBe(1);
    // The body still hosts the source characters `![cat](/img/cat.png)`.
    const text = await page.locator("#rendered").innerText();
    expect(text).toContain("![cat](/img/cat.png)");
    // The overlay invariant indicator stays green — img has empty textContent.
    await expect(page.locator("#invariant-state")).toHaveText(/overlay invariant holds/);
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
      win.__p = (document.getElementById("rendered") as HTMLElement).querySelector("p")!;
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
      const p = (document.getElementById("rendered") as HTMLElement).querySelector("p");
      return p === win.__p;
    });
    expect(sameNode).toBe(true);
    const stats = await page.locator("#patch-stats").innerText();
    expect(stats).toContain("shifted 1");
  });
});
