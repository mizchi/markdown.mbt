import { test, expect } from '@playwright/test';

test.describe('UI Toggle Buttons', () => {
  test('view mode buttons should update container class', async ({ page }) => {
    await page.goto('/playground/');
    await page.waitForSelector('.container');

    // Initial state should be split view
    const container = page.locator('.container').first();

    // Click editor-only button
    await page.click('button[title="Editor only"]');
    await page.waitForTimeout(100);

    // Check if container has view-editor class
    await expect(container).toHaveClass(/view-editor/);

    // Click preview-only button
    await page.click('button[title="Preview only"]');
    await page.waitForTimeout(100);

    // Check if container has view-preview class
    await expect(container).toHaveClass(/view-preview/);

    // Click split button
    await page.click('button[title="Split view"]');
    await page.waitForTimeout(100);

    // Check if container has view-split class
    await expect(container).toHaveClass(/view-split/);
  });

  test('editor mode buttons should update container class', async ({ page }) => {
    await page.goto('/playground/');
    await page.waitForSelector('.container');

    const container = page.locator('.container').first();

    // Click simple editor button
    await page.click('button[title="Simple text editor"]');
    await page.waitForTimeout(100);

    // Check if container has editor-mode-simple class
    await expect(container).toHaveClass(/editor-mode-simple/);

    // Click syntax highlight button
    await page.click('button[title="Syntax highlight editor"]');
    await page.waitForTimeout(100);

    // Check if container has editor-mode-highlight class
    await expect(container).toHaveClass(/editor-mode-highlight/);
  });

  test('buttons should have active class when selected', async ({ page }) => {
    await page.goto('/playground/');
    await page.waitForSelector('.view-mode-btn');

    // Click editor-only button
    const editorBtn = page.locator('button[title="Editor only"]');
    await editorBtn.click();
    await page.waitForTimeout(100);

    // Editor button should have active class
    await expect(editorBtn).toHaveClass(/active/);

    // Split button should not have active class
    const splitBtn = page.locator('button[title="Split view"]');
    await expect(splitBtn).not.toHaveClass(/active/);
  });

  test('SVG icons should be visible', async ({ page }) => {
    await page.goto('/playground/');
    await page.waitForSelector('.view-mode-btn');

    // Check if SVG icons are rendered (inside span from Icon component)
    const svgIcons = page.locator('.view-mode-btn span svg');
    await expect(svgIcons).toHaveCount(5); // 3 view mode + 2 editor mode buttons

    // First SVG should be visible
    const firstSvg = svgIcons.first();
    await expect(firstSvg).toBeVisible();
  });
});
