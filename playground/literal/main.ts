/**
 * Demo entry for the literal renderer.
 *
 * The reusable editor wiring lives in `frontend/editor`. This file keeps only
 * the demo source, toolbar state, and status badges.
 */

import { toHtmlLiteral } from "../../js/api.js";
import { createLiteralMarkdownEditor } from "../../frontend/editor/index.js";
import "../../frontend/editor/overlay.css";

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
  "Inline image example: ![placeholder:w96](/images/literal-preview-a.svg)",
  "and ![another:w96](/images/literal-preview-b.svg).",
  "",
  "![standalone](/images/literal-preview-a.svg)",
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
const hostEl = document.getElementById("host") as HTMLDivElement;
const sourceSelectionEl = document.getElementById(
  "source-selection",
) as HTMLDivElement;
const sourceCaretEl = document.getElementById("source-caret") as HTMLDivElement;
const invariantEl = document.getElementById(
  "invariant-state",
) as HTMLSpanElement;
const overlayToggle = document.getElementById(
  "overlay-toggle",
) as HTMLInputElement;
const imagePreviewToggle = document.getElementById(
  "image-preview-toggle",
) as HTMLInputElement;
const cursorIndicatorEl = document.getElementById("cursor-indicator") as
  | HTMLSpanElement
  | null;
const patchStatsEl = document.getElementById("patch-stats") as
  | HTMLSpanElement
  | null;

const literalEditor = createLiteralMarkdownEditor({
  elements: {
    host: hostEl,
    rendered: renderedEl,
    source: sourceEl,
    sourceView: sourceViewEl,
    sourceCaret: sourceCaretEl,
    sourceSelection: sourceSelectionEl,
    modeRoot: document.body,
  },
  initialSource: SAMPLE,
  mode: "preview",
  imagePreview: imagePreviewToggle.checked,
  renderLiteral: (src, options) => toHtmlLiteral(src, options),
  onPatchStats(stats) {
    if (!patchStatsEl) return;
    patchStatsEl.textContent =
      `patch: reused ${stats.reused} · replaced ${stats.replaced}` +
      ` · shifted ${stats.shifted} · inserted ${stats.inserted}` +
      ` · removed ${stats.removed}`;
  },
  onInvariant(state) {
    invariantEl.textContent = state.ok
      ? "✓ literal DOM matches fresh render"
      : "✗ literal DOM drift — see console for diff";
    invariantEl.style.color = state.ok ? "#3fb950" : "#f85149";
  },
  onCursor(state) {
    if (!cursorIndicatorEl) return;
    cursorIndicatorEl.textContent = state.kind === "cursor"
      ? `cursor → src offset ${state.start}`
      : `selection → src offsets ${state.start}..${state.end}`;
  },
});

overlayToggle.addEventListener("change", () => {
  document.body.classList.toggle("overlay", overlayToggle.checked);
});

imagePreviewToggle.addEventListener("change", () => {
  literalEditor.setImagePreview(imagePreviewToggle.checked);
});

document.body.classList.toggle("overlay", overlayToggle.checked);
