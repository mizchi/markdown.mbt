import { test, expect, type Page } from "@playwright/test";

/**
 * Regression tests for the syntax-highlight overlay drifting out of sync with
 * the text: highlighting that appeared or vanished depending on whether the
 * last edit happened to trigger a full repaint (pressing Enter did, typing a
 * character did not).
 */

const EDITOR = "textarea.editor-textarea";

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

async function setContent(page: Page, text: string) {
  await page.locator(EDITOR).click();
  await page.locator(EDITOR).fill(text);
  await page.waitForTimeout(600);
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
    await page.waitForSelector(".syntax-editor-container", { timeout: 10000 });
    await page.waitForTimeout(1000);
  });

  test("pressing Enter does not toggle highlighting on other lines", async ({ page }) => {
    // The default document contains fenced code blocks, including one whose
    // info string is not a plain word (```moonlight-svg).
    const before = await snapshot(page);

    await moveCursorTo(page, before.value.length);
    await page.keyboard.press("Enter");
    await page.waitForTimeout(400);

    const after = await snapshot(page);
    const changed = before.lines.filter((line, i) => line !== after.lines[i]);
    expect(changed).toEqual([]);
    // The newline added exactly one line.
    expect(after.lines.length).toBe(before.lines.length + 1);
  });

  test("code blocks are highlighted without any user edit", async ({ page }) => {
    // Highlighters load lazily; their arrival has to repaint the blocks that
    // were painted as plain text while the module was still in flight.
    await setContent(page, "# D\n\n```rust\nfn main() { let x = 1; }\n```\n\ntail");
    await page.waitForTimeout(2500); // persist to IndexedDB
    await page.reload();
    await page.waitForSelector(".syntax-editor-container", { timeout: 10000 });
    await page.waitForTimeout(2000); // no edit at all, only the async load

    const { lines } = await snapshot(page);
    expect(lines[3]).toContain("style=\"color:");
  });

  test("a fence with a non-word info string still closes", async ({ page }) => {
    await setContent(page, "# Doc\n\n```moonlight-svg\n<svg></svg>\n```\n\ntail **bold** here");

    const fromScratch = await snapshot(page);
    expect(fromScratch.lines[2]).toContain('class="md-fence-lang"');
    // The block closes, so the tail is highlighted as markdown - not swallowed
    // by an unterminated code block.
    expect(fromScratch.lines[6]).toContain('class="md-bold"');

    // Typing a character takes the line-local path; it must agree with the
    // full-document path above.
    await moveCursorTo(page, fromScratch.value.length);
    await page.keyboard.type("X");
    await page.waitForTimeout(300);

    const afterTyping = await snapshot(page);
    expect(afterTyping.lines.slice(0, 6)).toEqual(fromScratch.lines.slice(0, 6));
    expect(afterTyping.lines[6]).toContain('class="md-bold"');
  });

  test("overlay text matches the source text line for line", async ({ page }) => {
    // The overlay sits behind a transparent textarea, so any character the
    // overlay drops or adds misaligns the visible text from the caret.
    await setContent(
      page,
      [
        "# Title",
        "",
        "  ```JS  note  ",
        "const a = 1;",
        "```",
        "",
        "- item **bold** & <tag>",
        "> quote",
      ].join("\n"),
    );

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
    await page.waitForTimeout(1500);
    const before = await snapshot(page);

    await moveCursorTo(page, before.value.indexOf("const a = 1;") + "const a = 1;".length);
    await page.keyboard.press("Enter");
    await page.keyboard.type("const b = 2;");
    await page.waitForTimeout(500);

    const after = await snapshot(page);
    expect(after.lines.length).toBe(before.lines.length + 1);
    // The new code line is highlighted like its neighbour...
    expect(after.lines[4]).toContain("style=\"color:");
    // ...and the markdown after the block is untouched.
    expect(after.lines[after.lines.length - 1]).toBe(before.lines[before.lines.length - 1]);
  });
});
