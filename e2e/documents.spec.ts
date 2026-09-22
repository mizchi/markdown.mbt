import { test, expect } from '@playwright/test';

test('first-line documents survive switching and reload, including empty content', async ({ page }) => {
  await page.goto('/');
  const editor = page.locator('textarea.editor-textarea');
  const firstLine = '# ' + 'Long first line '.repeat(30);
  await editor.fill(firstLine + '\nSecond line');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(editor).toHaveValue('');
  await page.locator('.document-item').filter({ hasText: 'Long first line' }).click();
  await expect(editor).toHaveValue(firstLine + '\nSecond line');
  const excerpt = page.locator('.document-excerpt').filter({ hasText: 'Long first line' });
  await expect(excerpt).toHaveText(firstLine);
  expect(await excerpt.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  await page.reload();
  await expect(editor).toHaveValue(firstLine + '\nSecond line');
  await page.getByRole('button', { name: 'Empty document', exact: true }).click();
  await expect(editor).toHaveValue('');
  await page.reload();
  await expect(editor).toHaveValue('');
});

test('sidebar and preview shortcuts work while editing without consuming tab shortcuts', async ({ page }) => {
  await page.goto('/');
  const sidebar = page.getByRole('complementary', { name: 'Documents' });
  await expect(sidebar).toBeVisible();
  await page.locator('textarea.editor-textarea').focus();
  await page.keyboard.press('Control+b');
  await expect(sidebar).toBeHidden();
  await page.keyboard.press('Control+b');
  await expect(sidebar).toBeVisible();
  await page.keyboard.press('Control+Backquote');
  await expect(page.locator('.preview')).toBeHidden();
  await page.keyboard.press('Control+Backquote');
  await expect(page.locator('.preview')).toBeVisible();
  const prevented = await page.evaluate(() => ['1', '2', '3'].map(key => {
    const event = new KeyboardEvent('keydown', { key, ctrlKey: true, bubbles: true, cancelable: true });
    window.dispatchEvent(event);
    return event.defaultPrevented;
  }));
  expect(prevented).toEqual([false, false, false]);
});

test('preserves the legacy document and reports failed saves without switching', async ({ page }) => {
  await page.goto('/');
  await page.locator('textarea.editor-textarea').waitFor();
  await page.evaluate(async () => {
    await new Promise<void>((resolve, reject) => {
      const request = indexedDB.open('markdown-editor', 1);
      request.onsuccess = () => {
        const db = request.result;
        const tx = db.transaction('documents', 'readwrite');
        tx.objectStore('documents').clear();
        tx.objectStore('documents').put({ content: '# Legacy draft', timestamp: 1 }, 'current');
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onerror = () => reject(tx.error);
      };
    });
  });
  await page.reload();
  const editor = page.locator('textarea.editor-textarea');
  await expect(editor).toHaveValue('# Legacy draft');
  await editor.fill('# Latest edit');
  await page.locator('.document-item.active').click();
  await expect(editor).toHaveValue('# Latest edit');
  await page.evaluate(() => {
    IDBObjectStore.prototype.put = () => { throw new DOMException('Full', 'QuotaExceededError'); };
  });
  await editor.fill('# Unsaved draft');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Save unavailable');
  await expect(editor).toHaveValue('# Unsaved draft');
});


test('saves 300ms after the last input without name or save controls', async ({ page }) => {
  await page.goto('/');
  const editor = page.locator('textarea.editor-textarea');
  await expect(editor).not.toHaveValue('');
  await expect(page.getByRole('textbox', { name: 'Document name', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Save document', exact: true })).toHaveCount(0);
  const newDocument = page.getByRole('button', { name: 'New document', exact: true });
  await expect(newDocument.locator('svg')).toBeVisible();
  await page.clock.install();
  await page.clock.pauseAt(new Date());
  await page.evaluate(() => {
    const original = IDBObjectStore.prototype.put;
    (window as any).documentWrites = [];
    IDBObjectStore.prototype.put = function(value, key) {
      (window as any).documentWrites.push(value.content);
      return original.call(this, value, key);
    };
  });
  await editor.fill('# First edit');
  await page.clock.runFor(200);
  await editor.fill('# Latest edit\nBody');
  await page.clock.runFor(299);
  expect(await page.evaluate(() => (window as any).documentWrites)).toEqual([]);
  await page.clock.runFor(1);
  await expect.poll(() => page.evaluate(() => (window as any).documentWrites)).toEqual(['# Latest edit\nBody']);
  await expect(page.locator('.document-item.active')).toHaveText('# Latest edit');
  await page.reload();
  await expect(editor).toHaveValue('# Latest edit\nBody');
});

test('document order stays fixed through selection, autosave and reload', async ({ page }) => {
  await page.goto('/');
  const editor = page.locator('textarea.editor-textarea');
  await editor.fill('First');
  await page.getByRole('button', { name: 'New document', exact: true }).click();
  await expect(editor).toHaveValue('');
  await editor.fill('Second');
  await expect(page.locator('.document-item.active')).toHaveText('Second');
  const items = page.locator('.document-item');
  const initialOrder = await items.allTextContents();
  await page.getByRole('button', { name: 'First', exact: true }).click();
  await expect(editor).toHaveValue('First');
  await expect(items).toHaveText(initialOrder);
  await editor.fill('First\nEdited body');
  await expect(page.getByRole('status')).toHaveText('Saved');
  await page.getByRole('button', { name: 'Second', exact: true }).click();
  await expect(editor).toHaveValue('Second');
  await expect(items).toHaveText(initialOrder);
  await page.reload();
  await expect(items).toHaveText(initialOrder);
  await page.getByRole('button', { name: 'First', exact: true }).click();
  await expect(editor).toHaveValue('First\nEdited body');
});
