/**
 * Demo entry for the literal renderer.
 *
 * Three behaviours wired together:
 *
 *  - Preview mode shows `toHtmlLiteral(source, { positions: true })`.
 *    Clicking flips into edit mode with the cursor placed at the source
 *    offset under the click.
 *  - Edit mode is a plain textarea over the same source. Typing in it
 *    triggers a *partial* re-render that diffs the new HTML against the
 *    current DOM and replaces only the top-level blocks that actually
 *    changed (see `LiteralEditor`). Press Escape (or unfocus) to flip
 *    back.
 *  - Overlay mode stacks a faded source view on top of the rendered view
 *    so the alignment can be verified visually.
 *
 * A live stats badge reports how many blocks were reused vs replaced vs
 * shifted on the latest update — useful for verifying that the partial-
 * update path is doing its job.
 */

import { toHtmlLiteral, toMarkdown } from "../../js/api.js";
import { LiteralEditor } from "../../frontend/editor/literal-editor.js";

const SAMPLE = [
  "# Compression Dictionary Transport 用の Toolkit",
  "",
  "## Intro",
  "",
  "CDT は あらかじめ辞書を作って クライアントに取得させておき、それを用いて 転送を圧縮することができる。",
  "",
  "- コマンドラインツール `cdt-toolkit` を定義した",
  "  - Rust で実装し crates.io で公開中",
  "- 詳細は <https://github.com/example/cdt-toolkit> を参照",
  "",
  "## Sample emphasis",
  "",
  "This paragraph contains *italic*, **bold**, ~~strike~~, and `inline code`.",
  "",
  "Inline image example: ![placeholder](https://placehold.co/40x40/161b22/c9d1d9?text=A)",
  "and ![another](https://placehold.co/40x40/161b22/79c0ff?text=B).",
  "",
  "> Block quotes also render with their leading `> ` marker visible.",
  "> Second line of the quote.",
  "",
  "```rust",
  "fn main() {",
  '    println!("hello, world!");',
  "}",
  "```",
  "",
].join("\n");

const sourceEl = document.getElementById("source") as HTMLTextAreaElement;
const renderedEl = document.getElementById("rendered") as HTMLDivElement;
const sourceViewEl = document.getElementById("source-view") as HTMLPreElement;
const invariantEl = document.getElementById("invariant-state") as HTMLSpanElement;
const overlayToggle = document.getElementById("overlay-toggle") as HTMLInputElement;
const imagePreviewToggle = document.getElementById("image-preview-toggle") as HTMLInputElement;
const cursorIndicatorEl = document.getElementById("cursor-indicator") as HTMLSpanElement | null;
const patchStatsEl = document.getElementById("patch-stats") as HTMLSpanElement | null;

sourceEl.value = SAMPLE;

let imagePreviewOn = false;

const renderLiteral = (src: string): string =>
  toHtmlLiteral(src, { positions: true, imagePreview: imagePreviewOn });

const editor = new LiteralEditor(renderedEl, renderLiteral, SAMPLE);

function refreshInvariant(src: string): void {
  const visible = stripHtml(renderedEl.innerHTML);
  const normalized = toMarkdown(src);
  if (visible === normalized) {
    invariantEl.textContent = "✓ overlay invariant holds";
    invariantEl.style.color = "#3fb950";
  } else {
    invariantEl.textContent = "✗ overlay drift — see console for diff";
    invariantEl.style.color = "#f85149";
    console.warn("overlay drift", { visible, normalized });
  }
}

function update(src: string): void {
  const stats = editor.setSource(src);
  sourceViewEl.textContent = src;
  if (patchStatsEl) {
    patchStatsEl.textContent =
      `patch: reused ${stats.reused} · replaced ${stats.replaced}` +
      ` · shifted ${stats.shifted} · inserted ${stats.inserted}` +
      ` · removed ${stats.removed}`;
  }
  refreshInvariant(src);
}

function stripHtml(html: string): string {
  const tmp = document.createElement("template");
  tmp.innerHTML = html;
  return tmp.content.textContent ?? "";
}

// =============================================================================
// Click-to-cursor
// =============================================================================

function findPositionedAncestor(node: Node | null): HTMLElement | null {
  let el = node instanceof Element ? node : node?.parentElement ?? null;
  while (el) {
    if (el instanceof HTMLElement && el.dataset.srcStart != null) return el;
    el = el.parentElement;
  }
  return null;
}

function visibleOffsetWithin(root: Element, target: Node, targetOffset: number): number {
  if (target === root) {
    let count = 0;
    for (const child of root.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) count += (child as Text).data.length;
      else if (child instanceof Element) count += (child.textContent ?? "").length;
    }
    return Math.min(count, targetOffset);
  }
  let count = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let current = walker.nextNode() as Text | null;
  while (current) {
    if (current === target) return count + targetOffset;
    count += current.data.length;
    current = walker.nextNode() as Text | null;
  }
  return count;
}

function sourceOffsetFromPoint(x: number, y: number): number | null {
  const range =
    (document as Document & {
      caretRangeFromPoint?: (x: number, y: number) => Range | null;
    }).caretRangeFromPoint?.(x, y) ?? null;
  if (!range) return null;
  const ancestor = findPositionedAncestor(range.startContainer);
  if (!ancestor || !ancestor.dataset.srcStart) return null;
  const base = Number.parseInt(ancestor.dataset.srcStart, 10);
  const within = visibleOffsetWithin(ancestor, range.startContainer, range.startOffset);
  return base + within;
}

// =============================================================================
// Mode toggling
// =============================================================================

function setMode(mode: "preview" | "edit"): void {
  document.body.dataset.mode = mode;
  if (mode === "preview") {
    update(sourceEl.value);
  }
}

function focusSourceAt(offset: number): void {
  setMode("edit");
  requestAnimationFrame(() => {
    sourceEl.focus();
    const clamped = Math.max(0, Math.min(offset, sourceEl.value.length));
    sourceEl.setSelectionRange(clamped, clamped);
    if (cursorIndicatorEl) {
      cursorIndicatorEl.textContent = `cursor → src offset ${clamped}`;
    }
  });
}

renderedEl.addEventListener("click", (event) => {
  if ((event.target as HTMLElement | null)?.closest("a")) return;
  const offset = sourceOffsetFromPoint(event.clientX, event.clientY);
  if (offset == null) return;
  event.preventDefault();
  focusSourceAt(offset);
});

sourceEl.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    setMode("preview");
  }
});

sourceEl.addEventListener("blur", () => {
  setMode("preview");
});

// Live updates while editing — the partial-update path keeps unchanged
// blocks' DOM nodes intact, so this stays cheap.
sourceEl.addEventListener("input", () => {
  update(sourceEl.value);
});

overlayToggle.addEventListener("change", () => {
  document.body.classList.toggle("overlay", overlayToggle.checked);
});

imagePreviewToggle.addEventListener("change", () => {
  imagePreviewOn = imagePreviewToggle.checked;
  document.body.classList.toggle("with-image-preview", imagePreviewOn);
  editor.rerender();
  refreshInvariant(sourceEl.value);
});

update(SAMPLE);
setMode("preview");
