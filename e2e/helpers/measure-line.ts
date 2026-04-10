import type { Page } from "@playwright/test";

export interface LineMeasurement {
  idx: number;
  src: string;
  textareaWidth: number;
  overlayWidth: number;
  drift: number;
  overlayHeight: number;
  wrapped: boolean;
}

/**
 * For each line in the editor, compute the theoretical width of the textarea
 * text (via canvas measureText) and compare against the actual rendered width
 * of the overlay (via Range.getBoundingClientRect on the .highlight-line div).
 *
 * Returns one entry per source line. Wrapped lines are flagged so tests can
 * fail loudly instead of reporting misleading drift: .highlight-line is a
 * block div whose width always equals the parent container, so we must use a
 * Range around its inline content to get the true glyph-width of the rendered
 * text.
 */
export async function measureLineDrift(page: Page): Promise<LineMeasurement[]> {
  return page.evaluate(() => {
    const ta = document.querySelector(".editor-textarea") as HTMLTextAreaElement | null;
    const hl = document.querySelector(".editor-highlight") as HTMLElement | null;
    if (!ta || !hl) throw new Error("editor not found");

    const lines = Array.from(hl.querySelectorAll(".highlight-line")) as HTMLElement[];
    const srcLines = ta.value.split("\n");

    const style = getComputedStyle(ta);
    const lineHeightPx = parseFloat(style.lineHeight);
    const fontShorthand = `${style.fontStyle} ${style.fontVariant} ${style.fontWeight} ${style.fontSize}/${style.lineHeight} ${style.fontFamily}`;
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("canvas 2d context unavailable");
    ctx.font = fontShorthand;

    const results: LineMeasurement[] = [];

    for (let i = 0; i < srcLines.length; i++) {
      const src = srcLines[i] ?? "";
      const taWidth = ctx.measureText(src).width;

      let overlayWidth = 0;
      let overlayHeight = 0;
      const lineEl = lines[i];
      if (lineEl) {
        const range = document.createRange();
        range.selectNodeContents(lineEl);
        const rect = range.getBoundingClientRect();
        overlayWidth = rect.width;
        overlayHeight = rect.height;
        range.detach?.();
      }

      // A wrapped line renders taller than one line-height. Allow 1px of
      // fractional slack so sub-pixel rounding never trips this check.
      const wrapped = overlayHeight > lineHeightPx + 1;

      results.push({
        idx: i,
        src,
        textareaWidth: taWidth,
        overlayWidth,
        drift: Math.abs(taWidth - overlayWidth),
        overlayHeight,
        wrapped,
      });
    }
    return results;
  });
}
