/**
 * Demo entry for the literal renderer.
 *
 * Three behaviours wired together:
 *
 *  - Preview mode shows `toHtmlLiteral(source, { positions: true })`.
 *    Clicking flips into edit mode with the cursor placed at the source
 *    offset under the click.
 *  - Edit mode places a transparent textarea over a markdown-highlighted
 *    source layer. Typing in it triggers a *partial* re-render that diffs
 *    the new HTML against the current DOM and replaces only the top-level
 *    blocks that actually changed (see `LiteralEditor`). Press Escape (or
 *    unfocus) to flip back.
 *  - Overlay mode stacks a faded source view on top of the rendered view
 *    so the alignment can be verified visually.
 *
 * A live stats badge reports how many blocks were reused vs replaced vs
 * shifted on the latest update — useful for verifying that the partial-
 * update path is doing its job.
 */

import { toHtmlLiteral } from "../../js/api.js";
import { LiteralEditor } from "../../frontend/editor/literal-editor.js";
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
const sourceSelectionEl = document.getElementById("source-selection") as HTMLDivElement;
const sourceCaretEl = document.getElementById("source-caret") as HTMLDivElement;
const invariantEl = document.getElementById("invariant-state") as HTMLSpanElement;
const overlayToggle = document.getElementById("overlay-toggle") as HTMLInputElement;
const imagePreviewToggle = document.getElementById("image-preview-toggle") as HTMLInputElement;
const cursorIndicatorEl = document.getElementById("cursor-indicator") as HTMLSpanElement | null;
const patchStatsEl = document.getElementById("patch-stats") as HTMLSpanElement | null;

sourceEl.value = SAMPLE;

let imagePreviewOn = false;
let measureCanvas: HTMLCanvasElement | null = null;
let sourceViewDragAnchor: number | null = null;
let isComposing = false;

const renderLiteral = (src: string): string =>
  toHtmlLiteral(src, { positions: true, imagePreview: imagePreviewOn });

const editor = new LiteralEditor(renderedEl, renderLiteral, SAMPLE);
const sourceViewEditor = new LiteralEditor(sourceViewEl, renderHighlightedSourceView, SAMPLE);

function refreshInvariant(src: string): void {
  const visible = stripHtml(renderedEl.innerHTML);
  const expected = stripHtml(renderLiteral(src));
  if (visible === expected) {
    invariantEl.textContent = "✓ literal DOM matches fresh render";
    invariantEl.style.color = "#3fb950";
  } else {
    invariantEl.textContent = "✗ literal DOM drift — see console for diff";
    invariantEl.style.color = "#f85149";
    console.warn("literal DOM drift", { visible, expected });
  }
}

function update(src: string): void {
  const stats = editor.setSource(src);
  renderSourceView(src);
  syncLiteralLayout();
  if (patchStatsEl) {
    patchStatsEl.textContent =
      `patch: reused ${stats.reused} · replaced ${stats.replaced}` +
      ` · shifted ${stats.shifted} · inserted ${stats.inserted}` +
      ` · removed ${stats.removed}`;
  }
  refreshInvariant(src);
}

function renderSourceView(src: string): void {
  sourceViewEditor.setSource(src);
}

function syncLiteralLayout(): void {
  sourceViewEl.style.transform = "";
  sourceEl.scrollLeft = 0;
  sourceEl.scrollTop = 0;

  sourceEl.style.height = "auto";

  const minHeight = Math.ceil(
    parseCssPx(getComputedStyle(hostEl).minHeight) || window.innerHeight * 0.5,
  );
  const contentHeight = Math.ceil(Math.max(
    renderedEl.scrollHeight,
    sourceViewEl.scrollHeight,
    sourceEl.scrollHeight,
  ));
  const height = Math.max(minHeight, contentHeight);
  hostEl.style.height = `${height}px`;
  sourceEl.style.height = `${height}px`;
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
}

function queueLiteralLayoutSync(keepCaretVisible = false): void {
  syncLiteralLayout();
  if (keepCaretVisible) ensureSourceCaretVisible();
  requestAnimationFrame(() => {
    syncLiteralLayout();
    if (keepCaretVisible) ensureSourceCaretVisible();
    syncSourceSelection();
    syncSourceCaret();
  });
}

function syncSourceCaret(): void {
  if (
    !imagePreviewOn ||
    isComposing ||
    document.body.dataset.mode !== "edit" ||
    document.activeElement !== sourceEl ||
    sourceEl.selectionStart !== sourceEl.selectionEnd
  ) {
    sourceCaretEl.style.display = "none";
    return;
  }
  const rect = sourceViewCaretRectForOffset(sourceEl.selectionStart);
  if (rect == null) {
    sourceCaretEl.style.display = "none";
    return;
  }
  const hostRect = hostEl.getBoundingClientRect();
  sourceCaretEl.style.display = "";
  sourceCaretEl.style.left = `${rect.left - hostRect.left}px`;
  sourceCaretEl.style.top = `${rect.top - hostRect.top}px`;
  sourceCaretEl.style.height = `${Math.max(1, rect.height)}px`;
}

function syncSourceSelection(): void {
  sourceSelectionEl.replaceChildren();
  if (
    !imagePreviewOn ||
    isComposing ||
    document.body.dataset.mode !== "edit" ||
    document.activeElement !== sourceEl
  ) {
    sourceSelectionEl.style.display = "none";
    return;
  }
  const start = Math.min(sourceEl.selectionStart, sourceEl.selectionEnd);
  const end = Math.max(sourceEl.selectionStart, sourceEl.selectionEnd);
  if (start === end) {
    sourceSelectionEl.style.display = "none";
    return;
  }

  const hostRect = hostEl.getBoundingClientRect();
  let hasRect = false;
  for (const rect of sourceViewTextRectsForRange(start, end)) {
    const el = document.createElement("div");
    el.className = "source-selection-rect";
    el.style.left = `${rect.left - hostRect.left}px`;
    el.style.top = `${rect.top - hostRect.top}px`;
    el.style.width = `${rect.width}px`;
    el.style.height = `${rect.height}px`;
    sourceSelectionEl.appendChild(el);
    hasRect = true;
  }
  sourceSelectionEl.style.display = hasRect ? "block" : "none";
}

function sourceViewTextRectsForRange(start: number, end: number): DOMRect[] {
  const rects: DOMRect[] = [];
  const walker = document.createTreeWalker(sourceViewEl, NodeFilter.SHOW_TEXT);
  let seen = 0;
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    const len = node.data.length;
    const nodeStart = seen;
    const nodeEnd = seen + len;
    seen = nodeEnd;
    if (end <= nodeStart || start >= nodeEnd) continue;
    const localStart = Math.max(0, start - nodeStart);
    const localEnd = Math.min(len, end - nodeStart);
    if (localStart >= localEnd) continue;
    const range = document.createRange();
    range.setStart(node, localStart);
    range.setEnd(node, localEnd);
    rects.push(...Array.from(range.getClientRects()));
  }
  return rects;
}

function syncTextareaImeAnchor(): void {
  if (
    !imagePreviewOn ||
    !isComposing ||
    document.body.dataset.mode !== "edit" ||
    document.activeElement !== sourceEl
  ) {
    sourceEl.style.transform = "";
    return;
  }
  const sourceRect = sourceViewCaretRectForOffset(sourceEl.selectionStart);
  const nativeRect = estimateTextareaCaretRectForOffset(sourceEl.selectionStart);
  if (!sourceRect || !nativeRect) {
    sourceEl.style.transform = "";
    return;
  }
  const dx = sourceRect.left - nativeRect.left;
  const dy = sourceRect.top - nativeRect.top;
  if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) {
    sourceEl.style.transform = "";
    return;
  }
  sourceEl.style.transform = `translate(${dx}px, ${dy}px)`;
}

function estimateTextareaCaretRectForOffset(offset: number): DOMRect | null {
  const previousTransform = sourceEl.style.transform;
  sourceEl.style.transform = "";
  let mirror: HTMLDivElement | null = null;
  try {
    const sourceRect = sourceEl.getBoundingClientRect();
    const style = getComputedStyle(sourceEl);
    mirror = document.createElement("div");
    const marker = document.createElement("span");
    mirror.style.position = "fixed";
    mirror.style.left = `${sourceRect.left}px`;
    mirror.style.top = `${sourceRect.top}px`;
    mirror.style.width = `${sourceEl.clientWidth}px`;
    mirror.style.margin = "0";
    mirror.style.padding = "0";
    mirror.style.border = "0";
    mirror.style.visibility = "hidden";
    mirror.style.pointerEvents = "none";
    mirror.style.whiteSpace = "pre-wrap";
    mirror.style.overflowWrap = "break-word";
    mirror.style.font = style.font;
    mirror.style.letterSpacing = style.letterSpacing;
    mirror.style.lineHeight = style.lineHeight;
    mirror.textContent = sourceEl.value.slice(0, Math.max(0, Math.min(offset, sourceEl.value.length)));
    marker.textContent = "\u200b";
    mirror.appendChild(marker);
    document.body.appendChild(mirror);
    const markerRect = marker.getBoundingClientRect();
    const lineHeight = parseCssPx(style.lineHeight) || parseCssPx(style.fontSize) * 1.6;
    return new DOMRect(markerRect.left, markerRect.top, 1, lineHeight);
  } finally {
    mirror?.remove();
    sourceEl.style.transform = previousTransform;
  }
}

function sourceViewCaretRectForOffset(offset: number): DOMRect | null {
  const sourceText = sourceViewEl.textContent ?? "";
  const clamped = Math.max(0, Math.min(offset, sourceText.length));
  const rect = sourceViewRawCaretRectForOffset(clamped);
  if (rect == null) return null;
  if (clamped > 0 && sourceText[clamped - 1] === "\n") {
    return new DOMRect(sourceViewEl.getBoundingClientRect().left, rect.top, 1, rect.height);
  }
  return rect;
}

function sourceViewRawCaretRectForOffset(clamped: number): DOMRect | null {
  const walker = document.createTreeWalker(sourceViewEl, NodeFilter.SHOW_TEXT);
  let seen = 0;
  let lastText: Text | null = null;
  for (let node = walker.nextNode() as Text | null; node; node = walker.nextNode() as Text | null) {
    const len = node.data.length;
    if (
      len > 0 &&
      clamped === seen + len &&
      hasBlockPreviewBeforeNextText(node)
    ) {
      return caretRectInTextNode(node, len);
    }
    if (clamped < seen + len || (clamped === 0 && len > 0)) {
      return caretRectInTextNode(node, clamped - seen);
    }
    seen += len;
    lastText = node;
  }
  if (lastText) return caretRectInTextNode(lastText, lastText.data.length);
  return null;
}

function hasBlockPreviewBeforeNextText(from: Node): boolean {
  for (let node = nextSourceViewNode(from); node; node = nextSourceViewNode(node)) {
    if (node.nodeType === Node.TEXT_NODE) return false;
    if (
      node instanceof Element &&
      node.classList.contains("md-image-preview-block")
    ) {
      return true;
    }
  }
  return false;
}

function nextSourceViewNode(from: Node): Node | null {
  if (from.firstChild) return from.firstChild;
  let node: Node | null = from;
  while (node && node !== sourceViewEl) {
    if (node.nextSibling) return node.nextSibling;
    node = node.parentNode;
  }
  return null;
}

function caretRectInTextNode(node: Text, offset: number): DOMRect | null {
  const local = Math.max(0, Math.min(offset, node.data.length));
  const range = document.createRange();
  range.setStart(node, local);
  range.collapse(true);
  const collapsed = range.getBoundingClientRect();
  if (collapsed.width > 0 || collapsed.height > 0) return collapsed;

  if (local > 0) {
    range.setStart(node, local - 1);
    range.setEnd(node, local);
    const rect = range.getBoundingClientRect();
    if (rect.width > 0 || rect.height > 0) {
      return new DOMRect(rect.right, rect.top, 1, rect.height);
    }
  }
  if (local < node.data.length) {
    range.setStart(node, local);
    range.setEnd(node, local + 1);
    const rect = range.getBoundingClientRect();
    if (rect.width > 0 || rect.height > 0) {
      return new DOMRect(rect.left, rect.top, 1, rect.height);
    }
  }
  return null;
}

function ensureSourceCaretVisible(): void {
  if (document.body.dataset.mode !== "edit") return;
  if (document.activeElement !== sourceEl) return;

  const style = getComputedStyle(sourceEl);
  const parsedLineHeight = parseCssPx(style.lineHeight);
  const lineHeight = parsedLineHeight > 0 ? parsedLineHeight : parseCssPx(style.fontSize) * 1.6;
  if (!Number.isFinite(lineHeight) || lineHeight <= 0) return;

  const caretLine = estimateVisualLineAtOffset(
    sourceEl.value,
    sourceEl.selectionStart,
    sourceEl,
    style,
  );
  const hostRect = hostEl.getBoundingClientRect();
  const caretTop = hostRect.top + caretLine * lineHeight;
  const caretBottom = caretTop + lineHeight;
  const margin = Math.max(48, lineHeight * 2);
  const lower = window.innerHeight - margin;
  if (caretBottom > lower) {
    window.scrollBy({ top: caretBottom - lower, left: 0 });
  } else if (caretTop < margin) {
    window.scrollBy({ top: caretTop - margin, left: 0 });
  }
}

function estimateVisualLineAtOffset(
  value: string,
  offset: number,
  el: HTMLTextAreaElement,
  style: CSSStyleDeclaration,
): number {
  const before = value.slice(0, Math.max(0, Math.min(offset, value.length)));
  const charWidth = estimateMonospaceCharWidth(style);
  const paddingLeft = parseCssPx(style.paddingLeft) ?? 0;
  const paddingRight = parseCssPx(style.paddingRight) ?? 0;
  const contentWidth = Math.max(1, el.clientWidth - paddingLeft - paddingRight);
  const columns = Math.max(1, Math.floor(contentWidth / charWidth));
  let visualLine = 0;
  const lines = before.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) visualLine += 1;
    visualLine += Math.max(0, Math.ceil(lines[i]!.length / columns) - 1);
  }
  return visualLine;
}

function estimateMonospaceCharWidth(style: CSSStyleDeclaration): number {
  measureCanvas ??= document.createElement("canvas");
  const ctx = measureCanvas.getContext("2d");
  if (!ctx) return parseCssPx(style.fontSize) * 0.6;
  ctx.font = `${style.fontStyle} ${style.fontVariant} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
  return Math.max(1, ctx.measureText("M").width);
}

function parseCssPx(value: string): number {
  const n = Number.parseFloat(value);
  return Number.isFinite(n) ? n : 0;
}

function stripHtml(html: string): string {
  const tmp = document.createElement("template");
  tmp.innerHTML = html;
  return tmp.content.textContent ?? "";
}

interface SourceImageSyntax {
  end: number;
  alt: string;
  url: string | null;
  ref: string | null;
}

interface ImageAltMeta {
  alt: string;
  width: number | null;
}

function renderHighlightedSourceView(src: string): string {
  let html = "";
  let lineStart = 0;
  while (lineStart <= src.length) {
    const newline = src.indexOf("\n", lineStart);
    const lineEnd = newline < 0 ? src.length : newline;
    const line = src.slice(lineStart, lineEnd);
    const image = standaloneImageSyntaxFromLine(line);
    if (image != null) {
      html += highlightMarkdownSourceLine(line, false);
      if (imagePreviewOn) {
        html += renderSourceStandaloneImagePreviewSlot(image);
      }
    } else {
      html += renderHighlightedSourceInlineLine(line);
    }
    if (newline < 0) break;
    html += "\n";
    lineStart = newline + 1;
  }
  return html;
}

interface LinePrefixHighlight {
  prefixHtml: string;
  rest: string;
  restClass: string | null;
}

function renderHighlightedSourceInlineLine(src: string, includeImageSlots = true): string {
  const prefixed = splitMarkdownLinePrefix(src);
  const restHtml = renderHighlightedInlineWithImageSlots(prefixed.rest, includeImageSlots);
  if (prefixed.restClass == null) return prefixed.prefixHtml + restHtml;
  return `${prefixed.prefixHtml}<span class="${prefixed.restClass}">${restHtml}</span>`;
}

function splitMarkdownLinePrefix(line: string): LinePrefixHighlight {
  const fence = /^(`{3,}|~{3,})(.*)$/.exec(line);
  if (fence) {
    return {
      prefixHtml: span("md-src-code-marker", fence[1]!),
      rest: fence[2]!,
      restClass: "md-src-code",
    };
  }

  const heading = /^(#{1,6})([ \t]+)(.*)$/.exec(line);
  if (heading) {
    return {
      prefixHtml: span("md-src-heading-marker", heading[1]!) + escapeHtml(heading[2]!),
      rest: heading[3]!,
      restClass: "md-src-heading",
    };
  }

  const quote = /^(>[ \t]?)(.*)$/.exec(line);
  if (quote) {
    return {
      prefixHtml: span("md-src-quote-marker", quote[1]!),
      rest: quote[2]!,
      restClass: null,
    };
  }

  const unordered = /^([ \t]*)([-*+])([ \t]+)(.*)$/.exec(line);
  if (unordered) {
    return {
      prefixHtml: escapeHtml(unordered[1]!) +
        span("md-src-list-marker", unordered[2]!) +
        escapeHtml(unordered[3]!),
      rest: unordered[4]!,
      restClass: null,
    };
  }

  const ordered = /^([ \t]*)(\d+[.)])([ \t]+)(.*)$/.exec(line);
  if (ordered) {
    return {
      prefixHtml: escapeHtml(ordered[1]!) +
        span("md-src-list-marker", ordered[2]!) +
        escapeHtml(ordered[3]!),
      rest: ordered[4]!,
      restClass: null,
    };
  }

  if (/^[ \t]*(?:\*{3,}|-{3,}|_{3,})[ \t]*$/.test(line)) {
    return { prefixHtml: "", rest: line, restClass: "md-src-hr" };
  }

  return { prefixHtml: "", rest: line, restClass: null };
}

function highlightMarkdownSourceLine(line: string, includeImageSlots = true): string {
  return renderHighlightedSourceInlineLine(line, includeImageSlots);
}

function renderHighlightedInlineWithImageSlots(src: string, includeImageSlots = true): string {
  let html = "";
  let pos = 0;
  while (pos < src.length) {
    const start = src.indexOf("![", pos);
    if (start < 0) {
      html += highlightMarkdownSourceInline(src.slice(pos));
      break;
    }
    const image = parseSourceImageSyntax(src, start);
    if (!image) {
      html += highlightMarkdownSourceInline(src.slice(pos, start + 1));
      pos = start + 1;
      continue;
    }
    html += highlightMarkdownSourceInline(src.slice(pos, image.end));
    if (includeImageSlots && imagePreviewOn) {
      html += renderSourceImagePreviewSlot(image);
    }
    pos = image.end;
  }
  return html;
}

function highlightMarkdownSourceInline(src: string): string {
  let html = "";
  let pos = 0;
  while (pos < src.length) {
    const code = readDelimited(src, pos, "`", "`", true);
    if (code != null) {
      html += span("md-src-code-marker", "`") +
        span("md-src-code", code.inner) +
        span("md-src-code-marker", "`");
      pos = code.end;
      continue;
    }

    const strong = readDelimited(src, pos, "**", "**");
    if (strong != null) {
      html += span("md-src-strong", src.slice(pos, strong.end));
      pos = strong.end;
      continue;
    }

    const strongUnderscore = readDelimited(src, pos, "__", "__");
    if (strongUnderscore != null) {
      html += span("md-src-strong", src.slice(pos, strongUnderscore.end));
      pos = strongUnderscore.end;
      continue;
    }

    const del = readDelimited(src, pos, "~~", "~~");
    if (del != null) {
      html += span("md-src-del", src.slice(pos, del.end));
      pos = del.end;
      continue;
    }

    const image = parseSourceImageSyntax(src, pos);
    if (image != null) {
      html += highlightImageSyntax(src.slice(pos, image.end), image.alt);
      pos = image.end;
      continue;
    }

    const link = readInlineLink(src, pos);
    if (link != null) {
      html += highlightLinkSyntax(src.slice(pos, link.end), link.text);
      pos = link.end;
      continue;
    }

    const em = readEmphasis(src, pos, "*") ?? readEmphasis(src, pos, "_");
    if (em != null) {
      html += span("md-src-em", src.slice(pos, em.end));
      pos = em.end;
      continue;
    }

    const autoLink = readAutoLink(src, pos);
    if (autoLink != null) {
      html += span("md-src-html", "<") + span("md-src-url", autoLink.inner) +
        span("md-src-html", ">");
      pos = autoLink.end;
      continue;
    }

    const url = readBareUrl(src, pos);
    if (url != null) {
      html += span("md-src-url", src.slice(pos, url.end));
      pos = url.end;
      continue;
    }

    if (src[pos] === "\\") {
      html += span("md-src-escape", src.slice(pos, Math.min(pos + 2, src.length)));
      pos += 2;
      continue;
    }

    html += escapeHtml(src[pos]!);
    pos++;
  }
  return html;
}

interface DelimitedSpan {
  inner: string;
  end: number;
}

interface InlineLinkSyntax {
  text: string;
  end: number;
}

function readDelimited(
  src: string,
  pos: number,
  open: string,
  close: string,
  allowEmpty = false,
): DelimitedSpan | null {
  if (!src.startsWith(open, pos)) return null;
  const innerStart = pos + open.length;
  let end = src.indexOf(close, innerStart);
  while (end >= 0 && src[end - 1] === "\\") {
    end = src.indexOf(close, end + close.length);
  }
  if (end < 0 || (!allowEmpty && end === innerStart)) return null;
  return { inner: src.slice(innerStart, end), end: end + close.length };
}

function readEmphasis(src: string, pos: number, marker: "*" | "_"): DelimitedSpan | null {
  if (!src.startsWith(marker, pos) || src.startsWith(marker + marker, pos)) return null;
  const prev = pos > 0 ? src[pos - 1] : "";
  if (prev != null && /\w/.test(prev)) return null;
  const innerStart = pos + 1;
  const end = src.indexOf(marker, innerStart);
  if (end <= innerStart || src[end + 1] === marker) return null;
  return { inner: src.slice(innerStart, end), end: end + 1 };
}

function readInlineLink(src: string, pos: number): InlineLinkSyntax | null {
  if (!src.startsWith("[", pos) || src.startsWith("![", pos)) return null;
  const textEnd = findMarkdownBracketEnd(src, pos + 1);
  if (textEnd < 0 || src[textEnd + 1] !== "(") return null;
  const destEnd = findMarkdownParenEnd(src, textEnd + 2);
  if (destEnd < 0) return null;
  return { text: src.slice(pos + 1, textEnd), end: destEnd + 1 };
}

function readAutoLink(src: string, pos: number): DelimitedSpan | null {
  const match = /^<((?:https?:\/\/|mailto:)[^>\s]+)>/.exec(src.slice(pos));
  if (!match) return null;
  return { inner: match[1]!, end: pos + match[0].length };
}

function readBareUrl(src: string, pos: number): DelimitedSpan | null {
  const match = /^(?:https?:\/\/|\/)[^\s<>()]+\.(?:png|jpe?g|gif|webp|avif|svg|bmp|ico)(?:[?#][^\s<>()]*)?|^https?:\/\/[^\s<>()]+/.exec(
    src.slice(pos),
  );
  if (!match) return null;
  return { inner: match[0], end: pos + match[0].length };
}

function highlightImageSyntax(raw: string, alt: string): string {
  const altStart = raw.indexOf("[") + 1;
  const altEnd = altStart + alt.length;
  return span("md-src-marker", raw.slice(0, altStart)) +
    span("md-src-image-alt", raw.slice(altStart, altEnd)) +
    span("md-src-marker", raw.slice(altEnd, altEnd + 2)) +
    span("md-src-url", raw.slice(altEnd + 2, -1)) +
    span("md-src-marker", raw.slice(-1));
}

function highlightLinkSyntax(raw: string, text: string): string {
  const textStart = 1;
  const textEnd = textStart + text.length;
  return span("md-src-link-bracket", "[") +
    span("md-src-link-text", raw.slice(textStart, textEnd)) +
    span("md-src-link-bracket", raw.slice(textEnd, textEnd + 2)) +
    span("md-src-url", raw.slice(textEnd + 2, -1)) +
    span("md-src-link-bracket", raw.slice(-1));
}

function span(className: string, value: string): string {
  return `<span class="${className}">${escapeHtml(value)}</span>`;
}

function parseSourceImageSyntax(src: string, start: number): SourceImageSyntax | null {
  if (!src.startsWith("![", start)) return null;
  const altEnd = findMarkdownBracketEnd(src, start + 2);
  if (altEnd < 0) return null;
  const alt = src.slice(start + 2, altEnd);
  const next = src[altEnd + 1];
  if (next === "(") {
    const destEnd = findMarkdownParenEnd(src, altEnd + 2);
    if (destEnd < 0) return null;
    return {
      end: destEnd + 1,
      alt,
      url: parseInlineImageDestination(src.slice(altEnd + 2, destEnd)),
      ref: null,
    };
  }
  if (next === "[") {
    const labelEnd = findMarkdownBracketEnd(src, altEnd + 2);
    if (labelEnd < 0) return null;
    return {
      end: labelEnd + 1,
      alt,
      url: null,
      ref: src.slice(altEnd + 2, labelEnd),
    };
  }
  return null;
}

function findMarkdownBracketEnd(src: string, pos: number): number {
  let depth = 0;
  for (let i = pos; i < src.length; i++) {
    const ch = src[i];
    if (ch === "\\") {
      i++;
      continue;
    }
    if (ch === "[") {
      depth++;
      continue;
    }
    if (ch === "]") {
      if (depth === 0) return i;
      depth--;
    }
  }
  return -1;
}

function findMarkdownParenEnd(src: string, pos: number): number {
  let depth = 0;
  for (let i = pos; i < src.length; i++) {
    const ch = src[i];
    if (ch === "\\") {
      i++;
      continue;
    }
    if (ch === "(") {
      depth++;
      continue;
    }
    if (ch === ")") {
      if (depth === 0) return i;
      depth--;
    }
  }
  return -1;
}

function parseInlineImageDestination(raw: string): string {
  const value = raw.trimStart();
  if (value.startsWith("<")) {
    const end = value.indexOf(">");
    return end >= 0 ? value.slice(1, end) : "";
  }
  const match = value.match(/^\S+/);
  return match?.[0] ?? "";
}

function parseImageAltMeta(alt: string): ImageAltMeta {
  const match = /^(.*):w([0-9]+)$/.exec(alt);
  if (!match) return { alt, width: null };
  const width = Number.parseInt(match[2]!, 10);
  if (width <= 0) return { alt, width: null };
  return { alt: match[1]!.replace(/[ \t]+$/, ""), width };
}

function standaloneImageSyntaxFromLine(line: string): SourceImageSyntax | null {
  const leading = line.match(/^[ \t]*/)?.[0].length ?? 0;
  const trailing = line.match(/[ \t]*$/)?.[0].length ?? 0;
  const end = line.length - trailing;
  if (leading >= end) return null;
  const image = parseSourceImageSyntax(line, leading);
  if (!image || image.end !== end || image.url == null) return null;
  return isPreviewableImageUrl(image.url) ? image : null;
}

function isPreviewableImageUrl(url: string): boolean {
  const path = url.split(/[?#]/, 1)[0]!.toLowerCase();
  return (
    path.startsWith("data:image/") ||
    /\.(png|jpe?g|gif|webp|avif|svg|bmp|ico)$/.test(path)
  );
}

function renderSourceStandaloneImagePreviewSlot(image: SourceImageSyntax): string {
  return renderSourceImagePreviewSlot(
    image,
    "md-image-preview-block",
  );
}

function renderSourceImagePreviewSlot(image: SourceImageSyntax, extraClass = ""): string {
  const meta = parseImageAltMeta(image.alt);
  const className = extraClass.length > 0
    ? `md-image-preview-slot md-image-preview-spacer ${extraClass}`
    : "md-image-preview-slot md-image-preview-spacer";
  const attrs = [
    `class="${className}"`,
    'data-md-noneditable="true"',
    'contenteditable="false"',
  ];
  if (meta.width != null) {
    attrs.push(`data-md-image-width="${meta.width}"`);
    attrs.push(`style="--md-literal-image-width:${meta.width}px"`);
  }
  const imgAttrs = [
    'class="md-image-preview"',
    `alt="${escapeHtmlAttr(meta.alt)}"`,
    'loading="lazy"',
  ];
  if (image.url != null) {
    imgAttrs.splice(1, 0, `src="${escapeHtmlAttr(image.url)}"`);
  } else if (image.ref != null) {
    imgAttrs.splice(1, 0, `data-md-image-ref="${escapeHtmlAttr(image.ref)}"`);
  }
  return `<span ${attrs.join(" ")}><img ${imgAttrs.join(" ")} /></span>`;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeHtmlAttr(value: string): string {
  return escapeHtml(value).replaceAll('"', "&quot;");
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
  if (pointHitsNonEditable(x, y)) return null;
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

function sourceOffsetFromSourceViewPoint(x: number, y: number): number | null {
  if (pointHitsNonEditable(x, y)) return null;
  const prevSourcePointerEvents = sourceEl.style.pointerEvents;
  const prevSourceViewPointerEvents = sourceViewEl.style.pointerEvents;
  sourceEl.style.pointerEvents = "none";
  sourceViewEl.style.pointerEvents = "auto";
  try {
    const range =
      (document as Document & {
        caretRangeFromPoint?: (x: number, y: number) => Range | null;
      }).caretRangeFromPoint?.(x, y) ?? null;
    if (!range || !sourceViewEl.contains(range.startContainer)) return null;
    return visibleOffsetWithin(sourceViewEl, range.startContainer, range.startOffset);
  } finally {
    sourceEl.style.pointerEvents = prevSourcePointerEvents;
    sourceViewEl.style.pointerEvents = prevSourceViewPointerEvents;
  }
}

function pointHitsNonEditable(x: number, y: number): boolean {
  for (const root of [renderedEl, sourceViewEl]) {
    const slots = root.querySelectorAll("[data-md-noneditable]");
    for (const slot of slots) {
      for (const rect of Array.from(slot.getClientRects())) {
        if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
          return true;
        }
      }
    }
  }
  return false;
}

// =============================================================================
// Mode toggling
// =============================================================================

function setMode(mode: "preview" | "edit"): void {
  document.body.dataset.mode = mode;
  if (mode === "preview") {
    isComposing = false;
    sourceEl.style.transform = "";
    update(sourceEl.value);
  }
  queueLiteralLayoutSync();
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
    queueLiteralLayoutSync(true);
  });
}

renderedEl.addEventListener("click", (event) => {
  const target = event.target as HTMLElement | null;
  const hitNonEditable = document
    .elementsFromPoint(event.clientX, event.clientY)
    .some((el) => el instanceof HTMLElement && el.closest("[data-md-noneditable]"));
  if (
    target?.closest("[data-md-noneditable]") ||
    hitNonEditable ||
    pointHitsNonEditable(event.clientX, event.clientY)
  ) {
    event.preventDefault();
    return;
  }
  if (target?.closest("a")) return;
  const offset = sourceOffsetFromPoint(event.clientX, event.clientY);
  if (offset == null) return;
  event.preventDefault();
  focusSourceAt(offset);
});

sourceEl.addEventListener("mousedown", (event) => {
  if (pointHitsNonEditable(event.clientX, event.clientY)) {
    event.preventDefault();
    sourceViewDragAnchor = null;
    return;
  }
  if (!imagePreviewOn) return;
  const offset = sourceOffsetFromSourceViewPoint(event.clientX, event.clientY);
  if (offset == null) return;
  event.preventDefault();
  sourceEl.focus({ preventScroll: true });
  sourceEl.setSelectionRange(offset, offset);
  sourceViewDragAnchor = offset;
  if (cursorIndicatorEl) {
    cursorIndicatorEl.textContent = `cursor → src offset ${offset}`;
  }
  syncSourceSelection();
  syncSourceCaret();
});

sourceEl.addEventListener("click", (event) => {
  if (pointHitsNonEditable(event.clientX, event.clientY) || imagePreviewOn) {
    event.preventDefault();
  }
});

sourceEl.addEventListener("keyup", () => {
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
});

sourceEl.addEventListener("mouseup", () => {
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
});

document.addEventListener("mousemove", (event) => {
  if (sourceViewDragAnchor == null) return;
  if ((event.buttons & 1) === 0) {
    sourceViewDragAnchor = null;
    return;
  }
  const offset = sourceOffsetFromSourceViewPoint(event.clientX, event.clientY);
  if (offset == null) return;
  event.preventDefault();
  sourceEl.focus({ preventScroll: true });
  sourceEl.setSelectionRange(
    Math.min(sourceViewDragAnchor, offset),
    Math.max(sourceViewDragAnchor, offset),
    offset < sourceViewDragAnchor ? "backward" : "forward",
  );
  if (cursorIndicatorEl) {
    cursorIndicatorEl.textContent = `selection → src offsets ${sourceEl.selectionStart}..${sourceEl.selectionEnd}`;
  }
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
});

document.addEventListener("mouseup", () => {
  sourceViewDragAnchor = null;
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
});

sourceEl.addEventListener("scroll", () => {
  syncLiteralLayout();
});

sourceEl.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    setMode("preview");
  }
});

sourceEl.addEventListener("compositionstart", () => {
  isComposing = true;
  syncSourceSelection();
  syncSourceCaret();
  syncTextareaImeAnchor();
});

sourceEl.addEventListener("compositionupdate", () => {
  syncTextareaImeAnchor();
});

sourceEl.addEventListener("compositionend", () => {
  isComposing = false;
  sourceEl.style.transform = "";
  queueLiteralLayoutSync(true);
});

sourceEl.addEventListener("blur", () => {
  isComposing = false;
  sourceEl.style.transform = "";
  setMode("preview");
});

// Live updates while editing — the partial-update path keeps unchanged
// blocks' DOM nodes intact, so this stays cheap.
sourceEl.addEventListener("input", () => {
  update(sourceEl.value);
  queueLiteralLayoutSync(true);
});

document.addEventListener("selectionchange", () => {
  if (document.activeElement !== sourceEl) return;
  requestAnimationFrame(() => {
    syncSourceSelection();
    syncSourceCaret();
    syncTextareaImeAnchor();
  });
});

overlayToggle.addEventListener("change", () => {
  document.body.classList.toggle("overlay", overlayToggle.checked);
});

imagePreviewToggle.addEventListener("change", () => {
  imagePreviewOn = imagePreviewToggle.checked;
  document.body.classList.toggle("with-image-preview", imagePreviewOn);
  sourceViewEditor.rerender();
  editor.rerender();
  queueLiteralLayoutSync();
  syncSourceCaret();
  refreshInvariant(sourceEl.value);
});

renderedEl.addEventListener("load", () => syncLiteralLayout(), true);
sourceViewEl.addEventListener("load", () => syncLiteralLayout(), true);
window.addEventListener("resize", () => queueLiteralLayoutSync());

document.body.classList.toggle("overlay", overlayToggle.checked);
update(SAMPLE);
setMode("preview");
