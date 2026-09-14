import { test, expect, type Page } from "@playwright/test";

/**
 * Regression tests for the syntax-highlight overlay drifting out of sync with
 * the text: highlighting that appeared or vanished depending on whether the
 * last edit happened to trigger a full repaint (pressing Enter did, typing a
 * character did not).
 */

const EDITOR = "textarea.editor-textarea";

// A line of the playground's default document, inside its ```typescript block.
const DEFAULT_DOC_CODE_LINE = "function greet(name: string): string {";

type Snapshot = { value: string; lines: string[] };

async function snapshot(page: Page): Promise<Snapshot> {
  return await page.evaluate(() => {
    const textarea = document.querySelector("textarea.editor-textarea") as HTMLTextAreaElement;
    const overlay = document.querySelector(".editor-highlight") as HTMLElement;
    return {
      value: textarea.value,
      lines: Array.from(overlay.children).map((el) => el.innerHTML),
    };
  });
}

/** innerHTML of the overlay row painting `sourceLine`, or null if absent. */
async function overlayRowFor(page: Page, sourceLine: string): Promise<string | null> {
  return await page.evaluate((needle) => {
    const textarea = document.querySelector("textarea.editor-textarea") as HTMLTextAreaElement;
    const overlay = document.querySelector(".editor-highlight") as HTMLElement;
    const index = textarea.value.split("\n").indexOf(needle);
    if (index === -1) return null;
    return overlay.children[index]?.innerHTML ?? null;
  }, sourceLine);
}

/**
 * Wait until every lazily loaded code highlighter has arrived and repainted.
 * `sourceLine` must be a line inside a code block of a supported language.
 */
async function waitForHighlightersSettled(page: Page, sourceLine: string) {
  await expect
    .poll(() => overlayRowFor(page, sourceLine), { timeout: 20000 })
    .toContain('style="color:');
}

async function setContent(page: Page, text: string) {
  await page.locator(EDITOR).click();
  await page.locator(EDITOR).fill(text);
  await expect.poll(() => page.locator(EDITOR).inputValue(), { timeout: 10000 }).toBe(text);
}

async function moveCursorTo(page: Page, position: number) {
  await page.evaluate((pos) => {
    const textarea = document.querySelector("textarea.editor-textarea") as HTMLTextAreaElement;
    textarea.focus();
    textarea.setSelectionRange(pos, pos);
  }, position);
}

test.describe("Syntax highlight overlay stays in sync", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.clear();
      indexedDB.deleteDatabase("markdown-editor");
    });
    await page.reload();
    await page.waitForSelector(".syntax-editor-container", { timeout: 15000 });
  });

  test("code blocks are highlighted without any user edit", async ({ page }) => {
    // Highlighters load lazily; their arrival has to repaint the blocks that
    // were painted as plain text while the module was still in flight. Nothing
    // here touches the document - a reload is the whole scenario.
    await waitForHighlightersSettled(page, DEFAULT_DOC_CODE_LINE);
  });

  test("pressing Enter does not toggle highlighting on other lines", async ({ page }) => {
    // The default document contains fenced code blocks, including one whose
    // info string is not a plain word (```moonlight-svg).
    await waitForHighlightersSettled(page, DEFAULT_DOC_CODE_LINE);
    const before = await snapshot(page);

    await moveCursorTo(page, before.value.length);
    await page.keyboard.press("Enter");
    await expect
      .poll(async () => (await snapshot(page)).lines.length, { timeout: 10000 })
      .toBe(before.lines.length + 1);

    const after = await snapshot(page);
    // Every pre-existing row must be byte-identical: a newline elsewhere in the
    // document may not add or remove highlighting anywhere.
    expect(after.lines.slice(0, before.lines.length)).toEqual(before.lines);
  });

  test("a fence with a non-word info string still closes", async ({ page }) => {
    await setContent(page, "# Doc\n\n```moonlight-svg\n<svg></svg>\n```\n\ntail **bold** here");
    await expect
      .poll(async () => (await snapshot(page)).lines[2], { timeout: 10000 })
      .toContain('class="md-fence-lang"');

    const fromScratch = await snapshot(page);
    // The block closes, so the tail is highlighted as markdown - not swallowed
    // by an unterminated code block.
    expect(fromScratch.lines[6]).toContain('class="md-bold"');

    // Typing a character takes the line-local path; it must agree with the
    // full-document path above.
    await moveCursorTo(page, fromScratch.value.length);
    await page.keyboard.type("X");
    await expect
      .poll(async () => (await snapshot(page)).lines[6], { timeout: 10000 })
      .toContain("hereX");

    const afterTyping = await snapshot(page);
    expect(afterTyping.lines.slice(0, 6)).toEqual(fromScratch.lines.slice(0, 6));
    expect(afterTyping.lines[6]).toContain('class="md-bold"');
  });

  test("overlay text matches the source text line for line", async ({ page }) => {
    // The overlay sits behind a transparent textarea, so any character the
    // overlay drops or adds misaligns the visible text from the caret.
    const doc = [
      "# Title",
      "",
      "  ```JS  note  ",
      "const a = 1;",
      "```",
      "",
      "- item **bold** & <tag>",
      "> quote",
    ].join("\n");
    await setContent(page, doc);
    await expect
      .poll(async () => (await snapshot(page)).lines.length, { timeout: 10000 })
      .toBe(doc.split("\n").length);

    const mismatches = await page.evaluate(() => {
      const textarea = document.querySelector("textarea.editor-textarea") as HTMLTextAreaElement;
      const overlay = document.querySelector(".editor-highlight") as HTMLElement;
      const source = textarea.value.split("\n");
      const out: { index: number; source: string; painted: string }[] = [];
      Array.from(overlay.children).forEach((el, i) => {
        const painted = (el.textContent ?? "").replace(/ /g, "");
        if (painted !== source[i]) out.push({ index: i, source: source[i]!, painted });
      });
      return out;
    });

    expect(mismatches).toEqual([]);
  });

  test("editing inside a code block keeps the rest of the document stable", async ({ page }) => {
    await setContent(page, "# D\n\n```ts\nconst a = 1;\n```\n\ntail *em*");
    await waitForHighlightersSettled(page, "const a = 1;");
    const before = await snapshot(page);

    await moveCursorTo(page, before.value.indexOf("const a = 1;") + "const a = 1;".length);
    await page.keyboard.press("Enter");
    await page.keyboard.type("const b = 2;");
    await expect
      .poll(async () => (await snapshot(page)).lines.length, { timeout: 10000 })
      .toBe(before.lines.length + 1);
    await waitForHighlightersSettled(page, "const b = 2;");

    const after = await snapshot(page);
    // The markdown after the block is untouched.
    expect(after.lines[after.lines.length - 1]).toBe(before.lines[before.lines.length - 1]);
  });
});
