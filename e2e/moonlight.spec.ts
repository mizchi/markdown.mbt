import { test, expect } from "@playwright/test";

test.describe("Moonlight SVG Editor", () => {
  test("loads and initializes moonlight editor", async ({ page }) => {
    await page.goto("http://localhost:5180");

    // Wait for preview to be rendered
    await page.waitForSelector(".preview");

    // Wait for the moonlight editor element to exist
    const moonlightEditor = page.locator("moonlight-editor");
    await expect(moonlightEditor).toHaveCount(1, { timeout: 20000 });

    // Wait for the editor to be fully hydrated (editor-container in shadow DOM)
    await page.waitForFunction(() => {
      const editor = document.querySelector("moonlight-editor") as any;
      return editor?.shadowRoot?.querySelector(".editor-container") !== null;
    }, { timeout: 30000 });

    // Verify the editor has the expected API methods
    const hasApi = await moonlightEditor.evaluate((el: any) => {
      return {
        hasExportSvg: typeof el.exportSvg === "function",
        hasImportSvg: typeof el.importSvg === "function",
        hasOnChange: typeof el.onChange === "function",
        hasClear: typeof el.clear === "function",
      };
    });

    expect(hasApi.hasExportSvg).toBe(true);
    expect(hasApi.hasImportSvg).toBe(true);
    expect(hasApi.hasOnChange).toBe(true);
    expect(hasApi.hasClear).toBe(true);

    // Export SVG and verify it's valid
    const svg = await moonlightEditor.evaluate((el: any) => {
      return el.exportSvg();
    });

    expect(svg).toContain("<svg");
    expect(svg).toContain("</svg>");

    // Verify onChange returns an unsubscribe function
    const unsubType = await moonlightEditor.evaluate((el: any) => {
      const unsub = el.onChange(() => {});
      const type = typeof unsub;
      if (type === "function") unsub(); // cleanup
      return type;
    });
    expect(unsubType).toBe("function");
  });
});
