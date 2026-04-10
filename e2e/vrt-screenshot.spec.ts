import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const FIXTURE = readFileSync(
  resolve(__dirname, "fixtures/width-fixture.md"),
  "utf8",
);

for (const theme of ["light", "dark"] as const) {
  test(`VRT screenshot: editor renders consistently (${theme})`, async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.evaluate((t) => {
      localStorage.clear();
      localStorage.setItem("theme", t);
      indexedDB.deleteDatabase("markdown-editor");
    }, theme);
    await page.reload({ waitUntil: "domcontentloaded" });

    await page.waitForSelector(".syntax-editor-container", { timeout: 15000 });
    await page.evaluate(() => (document as unknown as { fonts: { ready: Promise<void> } }).fonts.ready);

    await page.evaluate((text) => {
      const ta = document.querySelector(".editor-textarea") as HTMLTextAreaElement;
      ta.value = text;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, FIXTURE);
    await page.waitForTimeout(400);

    const editor = page.locator(".editor-wrapper").first();
    await expect(editor).toHaveScreenshot(`editor-${theme}.png`, {
      maxDiffPixelRatio: 0.002,
    });
  });
}
