import { test, expect } from '@playwright/test';

for (const mode of ['highlight', 'simple']) {
  test(`selecting a document focuses its beginning (${mode})`, async ({ page }) => {
    await page.goto('/');
    if (mode === 'simple') await page.getByTitle('Simple text editor', { exact: true }).click();
    const editor = page.locator(mode === 'simple' ? '.simple-editor' : '.editor-textarea');
    await editor.fill('First\n' + 'Long body\n'.repeat(100));
    await editor.press('Control+End');
    await page.getByRole('button', { name: 'New document', exact: true }).click();
    await expect(editor).toHaveValue('');
    await page.getByRole('button', { name: 'First', exact: true }).click();
    await expect(editor).toBeFocused();
    expect(await editor.evaluate((el: HTMLTextAreaElement) => [el.selectionStart, el.selectionEnd])).toEqual([0, 0]);
    await editor.press('ArrowRight');
    await page.getByRole('button', { name: 'First', exact: true }).click();
    await expect(editor).toBeFocused();
    expect(await editor.evaluate((el: HTMLTextAreaElement) => el.selectionStart)).toBe(0);
  });
}

test('deletion requires confirmation and cannot be undone by pending autosave', async ({ page }) => {
  await page.goto('/');
  const editor = page.locator('.editor-textarea');
  await editor.fill('Keep');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(editor).toHaveValue('');
  await editor.fill('Delete me');
  await expect(page.locator('.document-item.active')).toHaveText('Delete me');
  const remove = page.getByRole('button', { name: 'Delete Delete me', exact: true });
  await remove.click();
  const dialog = page.getByRole('dialog', { name: 'Delete document?' });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Delete me', exact: true })).toBeVisible();
  await editor.fill('Delete me\nUnsaved edit');
  await remove.click();
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(editor).toHaveValue('Keep');
  await page.reload();
  await expect(page.locator('.document-item')).toHaveText(['Keep']);
  await page.getByRole('button', { name: 'Delete Keep', exact: true }).click();
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(editor).toHaveValue('');
  await page.reload();
  await expect(editor).toHaveValue('');
  await expect(page.locator('.document-item')).toHaveText(['Empty document']);
});

test('sidebar and preview can be resized and retain widths after reload', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  const sidebar = page.locator('.document-sidebar');
  const preview = page.locator('.preview');
  async function drag(name: string, delta: number) {
    const bounds = await page.getByRole('separator', { name, exact: true }).boundingBox();
    await page.mouse.move(bounds!.x + bounds!.width / 2, bounds!.y + 100);
    await page.mouse.down();
    await page.mouse.move(bounds!.x + bounds!.width / 2 + delta, bounds!.y + 100, { steps: 10 });
    await page.mouse.up();
  }
  await expect(sidebar).toBeVisible();
  const beforeSidebar = (await sidebar.boundingBox())!.width;
  await drag('Resize sidebar', 100);
  expect((await sidebar.boundingBox())!.width).toBeGreaterThan(beforeSidebar + 80);
  const beforePreview = (await preview.boundingBox())!.width;
  await drag('Resize preview', -100);
  expect((await preview.boundingBox())!.width).toBeGreaterThan(beforePreview + 80);
  const widths = [(await sidebar.boundingBox())!.width, (await preview.boundingBox())!.width];
  await page.reload();
  await expect(sidebar).toBeVisible();
  expect((await sidebar.boundingBox())!.width).toBeCloseTo(widths[0]!, 0);
  expect((await preview.boundingBox())!.width).toBeCloseTo(widths[1]!, 0);
  await page.getByRole('button', { name: 'Toggle sidebar', exact: true }).click();
  await expect(page.getByRole('separator', { name: 'Resize sidebar', exact: true })).toBeHidden();
  await page.getByRole('button', { name: 'Toggle preview', exact: true }).click();
  await expect(page.getByRole('separator', { name: 'Resize preview', exact: true })).toBeHidden();
});

test('deleting another document preserves the current draft and reports failures', async ({ page }) => {
  await page.goto('/');
  const editor = page.locator('.editor-textarea');
  await editor.fill('Remove other');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(editor).toHaveValue('');
  await editor.fill('Current draft');
  await page.getByRole('button', { name: 'Delete Remove other', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Delete document?' });
  await page.evaluate(() => {
    const original = IDBObjectStore.prototype.delete;
    IDBObjectStore.prototype.delete = function(key) {
      IDBObjectStore.prototype.delete = original;
      throw new DOMException('Unavailable', 'UnknownError');
    };
  });
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('Could not delete');
  await expect(editor).toHaveValue('Current draft');
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(editor).toHaveValue('Current draft');
  await page.reload();
  await expect(editor).toHaveValue('Current draft');
  await expect(page.locator('.document-item')).toHaveText(['Current draft']);
});
