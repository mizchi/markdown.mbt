import { test, expect } from "@playwright/test";

test.describe("Moonlight SVG Editor", () => {
  test("loads and initializes moonlight editor", async ({ page }) => {
    await page.goto("/");

    // Wait for preview to be rendered
    await page.waitForSelector(".preview");

    // Wait for the moonlight editor wrapper to exist and be loaded
    const wrapper = page.locator(".moonlight-editor-wrapper");
    await expect(wrapper).toHaveCount(1, { timeout: 20000 });

    // Wait for loading to complete (loading message disappears)
    await page.waitForFunction(() => {
      const wrapper = document.querySelector(".moonlight-editor-wrapper");
      return wrapper && !wrapper.textContent?.includes("Loading");
    }, { timeout: 30000 });

    // Check that the editor container has content (SVG element should be rendered)
    const hasSvgContent = await page.evaluate(() => {
      const wrapper = document.querySelector(".moonlight-editor-wrapper");
      return wrapper?.querySelector("svg") !== null;
    });

    expect(hasSvgContent).toBe(true);
  });
});
