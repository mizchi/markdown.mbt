import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { measureLineDrift } from "./helpers/measure-line";

const FIXTURE = readFileSync(
  resolve(__dirname, "fixtures/width-fixture.md"),
  "utf8",
);

const DRIFT_TOLERANCE_PX = 0.5;

for (const theme of ["light", "dark"] as const) {
  test(`VRT width: fixture lines align (${theme})`, async ({ page }) => {
    // Pin viewport so editor max-width (900px) is never tighter than fixture
    // content, and so geometry matches the screenshot VRT viewport.
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/", { waitUntil: "domcontentloaded" });
    await page.evaluate((t) => {
      localStorage.clear();
      localStorage.setItem("theme", t);
      indexedDB.deleteDatabase("markdown-editor");
    }, theme);
    await page.reload({ waitUntil: "domcontentloaded" });

    await page.waitForSelector(".syntax-editor-container", { timeout: 15000 });
    // Wait for bundled PlemolJP to finish loading before measuring.
    await page.evaluate(() => (document as unknown as { fonts: { ready: Promise<void> } }).fonts.ready);

    // Inject fixture into the textarea and push it through the editor's
    // normal input pipeline so the overlay is rebuilt.
    await page.evaluate((text) => {
      const ta = document.querySelector(".editor-textarea") as HTMLTextAreaElement;
      ta.value = text;
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }, FIXTURE);
    await page.waitForTimeout(300);

    const drifts = await measureLineDrift(page);

    // 1. No wrapped lines — fixture is designed so each row fits in the editor.
    const wrapped = drifts.filter((d) => d.wrapped);
    expect(
      wrapped,
      `wrapped lines detected:\n${JSON.stringify(wrapped, null, 2)}`,
    ).toHaveLength(0);

    // 2. Per-line drift within tolerance. Empty source lines with zero overlay
    //    width are treated as aligned (no content to compare).
    const offending = drifts.filter(
      (d) =>
        d.drift > DRIFT_TOLERANCE_PX &&
        !(d.src.trim() === "" && d.overlayWidth === 0),
    );
    expect(
      offending,
      `lines with drift > ${DRIFT_TOLERANCE_PX}px:\n${JSON.stringify(offending, null, 2)}`,
    ).toHaveLength(0);
  });
}
