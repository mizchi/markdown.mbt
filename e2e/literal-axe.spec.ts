/**
 * Accessibility lint for the literal renderer.
 *
 * Loads the playground literal demo, swaps in a fixture document that
 * exercises every Block / Inline variant the renderer emits, and runs
 * axe-core over the rendered output. The literal renderer is supposed
 * to expose semantic HTML to assistive technology (heading levels,
 * link targets, image alt text, table structure …) while hiding the
 * Markdown markers via `aria-hidden="true"`, so any axe violation in
 * the WCAG 2.0/2.1 A and AA tags is a regression we want to catch on
 * CI rather than discover after publishing.
 */

import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const FIXTURE = [
  "# Document title",
  "",
  "## Headings, paragraphs, emphasis",
  "",
  "A paragraph with *italic*, **bold**, ~~struck~~ text, and `inline code`.",
  "",
  "## Lists",
  "",
  "- bullet one",
  "- bullet two with *emphasis*",
  "  - nested item",
  "",
  "1. ordered one",
  "2. ordered two",
  "",
  "- [x] task done",
  "- [ ] task pending",
  "",
  "## Blockquotes",
  "",
  "> a quote with [a link](https://example.com)",
  "> and a second line",
  "",
  "## Links and inline elements",
  "",
  "Visit <https://example.com> or [the docs](https://example.com/docs \"Docs\").",
  "",
  "Image: ![Architecture diagram](/img/diagram.png \"Architecture\").",
  "",
  "## Code",
  "",
  "```rust",
  "fn main() {",
  '    println!("hello");',
  "}",
  "```",
  "",
  "## Table",
  "",
  "| Lang | Year |",
  "| :--- | ---: |",
  "| Rust | 2010 |",
  "| MoonBit | 2023 |",
  "",
  "***",
  "",
  "Footnote example[^1].",
  "",
  "[^1]: Footnote body.",
  "",
].join("\n");

test.describe("literal renderer accessibility (axe-core)", () => {
  test("no WCAG 2.0/2.1 A or AA violations on the literal output", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate((md) => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value = md;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, FIXTURE);

    // The demo's invariant indicator must stay green — if it doesn't,
    // the rendering itself is broken and the axe run would be testing
    // the wrong DOM.
    await expect(page.locator("#invariant-state")).toHaveText(
      /overlay invariant holds/,
    );

    const results = await new AxeBuilder({ page })
      .include("#rendered")
      // Scope to WCAG A / AA. Color-contrast depends on the demo's
      // palette rather than the renderer, so exclude it here — a
      // consumer with a different theme has their own contrast story.
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .disableRules(["color-contrast"])
      .analyze();

    if (results.violations.length > 0) {
      console.log(JSON.stringify(results.violations, null, 2));
    }
    expect(results.violations).toEqual([]);
  });

  test("image preview slot keeps alt-text accessibility", async ({ page }) => {
    await page.goto("/literal/");
    await page.evaluate(() => {
      const ta = document.getElementById("source") as HTMLTextAreaElement;
      ta.value =
        "Inline image: ![an example diagram](https://placehold.co/60x40/161b22/c9d1d9?text=A \"caption\").\n";
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    });
    await page.locator("#image-preview-toggle").check();

    const results = await new AxeBuilder({ page })
      .include("#rendered")
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .disableRules(["color-contrast"])
      .analyze();

    if (results.violations.length > 0) {
      console.log(JSON.stringify(results.violations, null, 2));
    }
    expect(results.violations).toEqual([]);

    // Sanity: the `<img>` carries the alt attribute the source provided.
    const altText = await page
      .locator("#rendered img.md-image-preview")
      .first()
      .getAttribute("alt");
    expect(altText).toBe("an example diagram");
  });
});
