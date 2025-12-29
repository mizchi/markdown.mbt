import { test, expect } from "@playwright/test";

test.describe("Playground Editor", () => {
  test.beforeEach(async ({ page }) => {
    // Clear localStorage to ensure clean state
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.clear();
      indexedDB.deleteDatabase("markdown-editor");
    });
    await page.reload();
    // Wait for app container to be visible (rendering starts)
    await page.waitForSelector(".app-container", { timeout: 10000 });
    // Wait for editor to initialize
    await page.waitForSelector(".syntax-editor-container, .simple-editor", { timeout: 10000 });
  });

  test("loads editor with initial content", async ({ page }) => {
    // Check that editor container exists
    const editor = page.locator(".editor");
    await expect(editor).toBeVisible();

    // Check that preview exists in split view
    const preview = page.locator(".preview");
    await expect(preview).toBeVisible();

    // Check initial content is rendered
    await expect(preview).toContainText("markdown.mbt Playground");
  });

  test("typing text updates preview", async ({ page }) => {
    // Get textarea (works for both highlight and simple modes)
    const textarea = page.locator("textarea").first();
    await expect(textarea).toBeVisible();

    // Clear and type new content - use fill to replace content
    await textarea.click();
    await textarea.fill("# Hello World\n\nThis is a test paragraph.");

    // Wait for preview to update
    await page.waitForTimeout(500);

    // Check preview updated
    const preview = page.locator(".preview");
    await expect(preview).toContainText("Hello World", { timeout: 5000 });
    await expect(preview).toContainText("This is a test paragraph", { timeout: 5000 });
  });

  test("view mode toggle works - editor only", async ({ page }) => {
    // Click editor-only button (second view mode button)
    const editorOnlyBtn = page.locator(".view-mode-buttons button").nth(1);
    await editorOnlyBtn.click();

    // Editor should be visible
    await expect(page.locator(".editor")).toBeVisible();

    // Preview should not be visible
    await expect(page.locator(".preview")).not.toBeVisible();
  });

  test("view mode toggle works - preview only", async ({ page }) => {
    // Click preview-only button (third view mode button)
    const previewOnlyBtn = page.locator(".view-mode-buttons button").nth(2);
    await previewOnlyBtn.click();

    // Preview should be visible
    await expect(page.locator(".preview")).toBeVisible();

    // Editor should not be visible
    await expect(page.locator(".editor")).not.toBeVisible();
  });

  test("view mode toggle works - split view", async ({ page }) => {
    // First switch to editor only
    await page.locator(".view-mode-buttons button").nth(1).click();
    await expect(page.locator(".preview")).not.toBeVisible();

    // Then switch back to split
    await page.locator(".view-mode-buttons button").nth(0).click();

    // Both should be visible
    await expect(page.locator(".editor")).toBeVisible();
    await expect(page.locator(".preview")).toBeVisible();
  });

  test("editor mode toggle works", async ({ page }) => {
    // Check initial state (highlight mode)
    await expect(page.locator(".syntax-editor-container")).toBeVisible({ timeout: 5000 });

    // Click simple mode button
    const simpleModeBtn = page.locator(".editor-mode-buttons button").nth(1);
    await simpleModeBtn.click();

    // Wait for mode change
    await page.waitForTimeout(300);

    // Should switch to simple textarea
    await expect(page.locator(".simple-editor")).toBeVisible({ timeout: 5000 });

    // Switch back to highlight mode
    const highlightModeBtn = page.locator(".editor-mode-buttons button").nth(0);
    await highlightModeBtn.click();

    // Wait for mode change
    await page.waitForTimeout(300);

    // Should switch back
    await expect(page.locator(".syntax-editor-container")).toBeVisible({ timeout: 5000 });
  });

  test("dark mode toggle works", async ({ page }) => {
    // Get initial theme
    const initialTheme = await page.evaluate(() =>
      document.documentElement.getAttribute("data-theme")
    );

    // Click theme toggle button
    const themeToggle = page.locator(".theme-toggle");
    await themeToggle.click();

    // Theme should change
    const newTheme = await page.evaluate(() =>
      document.documentElement.getAttribute("data-theme")
    );
    expect(newTheme).not.toBe(initialTheme);
  });

  test("keyboard shortcuts for view mode", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.focus();

    // Ctrl+2 for editor only
    await page.keyboard.press("Control+2");
    await expect(page.locator(".preview")).not.toBeVisible();

    // Ctrl+3 for preview only
    await page.keyboard.press("Control+3");
    await expect(page.locator(".editor")).not.toBeVisible();

    // Ctrl+1 for split view
    await page.keyboard.press("Control+1");
    await expect(page.locator(".editor")).toBeVisible();
    await expect(page.locator(".preview")).toBeVisible();
  });

  test("markdown rendering - headings", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.click();
    await textarea.fill("# H1\n## H2\n### H3");

    await page.waitForTimeout(500);

    const preview = page.locator(".preview");
    await expect(preview.locator("h1")).toContainText("H1", { timeout: 5000 });
    await expect(preview.locator("h2").first()).toContainText("H2", { timeout: 5000 });
    await expect(preview.locator("h3").first()).toContainText("H3", { timeout: 5000 });
  });

  test("markdown rendering - emphasis", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.click();
    await textarea.fill("**bold** and *italic* text");

    await page.waitForTimeout(1000);

    const preview = page.locator(".preview");
    await expect(preview.locator("strong").first()).toContainText("bold", { timeout: 10000 });
    await expect(preview.locator("em").first()).toContainText("italic", { timeout: 10000 });
  });

  test("markdown rendering - code block", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.click();
    await textarea.fill("```js\nconst x = 1;\n```");

    await page.waitForTimeout(500);

    const preview = page.locator(".preview");
    // Code blocks can be rendered as <pre><code> or highlighted <div> with <pre>
    await expect(preview.locator("pre").first()).toBeVisible({ timeout: 5000 });
  });

  test("markdown rendering - links", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.click();
    await textarea.fill("[Example](https://example.com)");

    await page.waitForTimeout(500);

    const preview = page.locator(".preview");
    const link = preview.locator('a[href="https://example.com"]');
    await expect(link).toContainText("Example", { timeout: 5000 });
  });

  test("markdown rendering - lists", async ({ page }) => {
    const textarea = page.locator("textarea").first();
    await textarea.click();
    await textarea.fill("- Item 1\n- Item 2\n- Item 3");

    await page.waitForTimeout(500);

    const preview = page.locator(".preview");
    await expect(preview.locator("ul").first()).toBeVisible({ timeout: 5000 });
    await expect(preview.locator("li")).toHaveCount(3, { timeout: 5000 });
  });
});
