/**
 * Demo entry for the literal renderer.
 *
 * Three modes:
 *
 *  - Preview: shows `toHtmlLiteral(source, { positions: true })` injected
 *    as HTML. Clicking anywhere flips the page into "Edit" mode with the
 *    cursor placed at the source offset corresponding to the clicked
 *    glyph.
 *  - Edit:    a plain `<textarea>` over the same source. Pressing Escape
 *    (or unfocusing) flips back to Preview.
 *  - Overlay: source view + rendered view stacked at the same coords for
 *    visual / VRT verification.
 *
 * The invariant indicator at the top reports whether stripping HTML from
 * the rendered output yields the same string as `toMarkdown(source)`.
 */

import { toHtmlLiteral, toMarkdown } from "../../js/api.js";

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
const cursorIndicatorEl = document.getElementById("cursor-indicator") as HTMLSpanElement | null;

sourceEl.value = SAMPLE;

function render(): void {
  const src = sourceEl.value;
  const html = toHtmlLiteral(src, { positions: true });
  renderedEl.innerHTML = html;
  sourceViewEl.textContent = src;
  const visible = stripHtml(html);
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

function stripHtml(html: string): string {
  const tmp = document.createElement("template");
  tmp.innerHTML = html;
  return tmp.content.textContent ?? "";
}

// =============================================================================
// Click-to-cursor: map a click in the rendered preview to a source offset.
// =============================================================================

/**
 * Find the nearest ancestor (or self) of `node` that carries
 * `data-src-start`. Returns `null` if no such element exists.
 */
function findPositionedAncestor(node: Node | null): HTMLElement | null {
  let el = node instanceof Element ? node : node?.parentElement ?? null;
  while (el) {
    if (el instanceof HTMLElement && el.dataset.srcStart != null) {
      return el;
    }
    el = el.parentElement;
  }
  return null;
}

/**
 * Count text characters from the start of `root` up to but not including
 * the position represented by (`node`, `offset`). This is the per-DOM
 * equivalent of textContent.slice(0, offsetWithinRoot).length, computed
 * via a TreeWalker so we don't materialise the whole string.
 */
function visibleOffsetWithin(root: Element, target: Node, targetOffset: number): number {
  if (target === root) {
    let count = 0;
    for (const child of root.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        count += (child as Text).data.length;
      } else if (child instanceof Element) {
        count += (child.textContent ?? "").length;
      }
      // childIndex offset semantics: caretRangeFromPoint usually returns a
      // text node + offset, so this branch is rare.
    }
    return Math.min(count, targetOffset);
  }
  let count = 0;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let current = walker.nextNode() as Text | null;
  while (current) {
    if (current === target) {
      return count + targetOffset;
    }
    count += current.data.length;
    current = walker.nextNode() as Text | null;
  }
  return count;
}

/** Compute the source offset for a (clientX, clientY) point in the preview. */
function sourceOffsetFromPoint(x: number, y: number): number | null {
  // Prefer the modern Range API; fall back to caretPositionFromPoint where
  // available (Firefox / older WebKit).
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
// Preview ↔ Edit toggling
// =============================================================================

function setMode(mode: "preview" | "edit"): void {
  document.body.dataset.mode = mode;
  if (mode === "preview") {
    render();
  }
}

function focusSourceAt(offset: number): void {
  setMode("edit");
  // Defer until the textarea is laid out / focusable.
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
  // Allow normal navigation when clicking on actual links.
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

sourceEl.addEventListener("input", () => {
  // Re-render in the background so that, once the user leaves edit mode,
  // the invariant indicator reflects the latest source.
  render();
});

overlayToggle.addEventListener("change", () => {
  document.body.classList.toggle("overlay", overlayToggle.checked);
});

setMode("preview");
