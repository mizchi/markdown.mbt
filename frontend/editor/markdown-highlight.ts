/**
 * Pure helpers behind the syntax-highlight editor overlay.
 *
 * The overlay is rendered one `<div>` per source line, so every function here
 * maps a source line (or the whole document) to the HTML for those lines.
 * Keeping it free of DOM access makes the fenced-code bookkeeping — the part
 * that decides whether an edit can be repainted line-locally — unit testable.
 */
import { getLoadedHighlighter, loadHighlighter, normalizeHighlightLanguage } from "../highlight/index.js";

// Cache for code block highlighting - avoids re-highlighting unchanged blocks
const codeBlockCache = new Map<string, string[]>();
// Cache for markdown line highlighting
const lineCache = new Map<string, string>();
// Cache for inline highlighting
const inlineCache = new Map<string, string>();
const MAX_CACHE_SIZE = 100;
const MAX_INLINE_CACHE_SIZE = 200;
const pendingHighlighters = new Set<string>();
const highlighterLoadedListeners = new Set<() => void>();

/**
 * Subscribe to "a lazily loaded code highlighter just became available".
 * Blocks highlighted before the load were painted as plain text, so listeners
 * have to repaint the whole document rather than a single line.
 */
export function onHighlighterLoaded(listener: () => void): () => void {
  highlighterLoadedListeners.add(listener);
  return () => highlighterLoadedListeners.delete(listener);
}

function requestHighlighter(lang: string): void {
  if (pendingHighlighters.has(lang)) return;
  pendingHighlighters.add(lang);
  void loadHighlighter(lang).then((highlighter) => {
    pendingHighlighters.delete(lang);
    if (!highlighter) return;
    codeBlockCache.clear();
    for (const listener of highlighterLoadedListeners) {
      listener();
    }
  }).catch((e) => {
    pendingHighlighters.delete(lang);
    console.error("Code highlighter load error:", e);
  });
}

function getCachedHighlight(code: string, lang: string): string[] | undefined {
  return codeBlockCache.get(`${lang}:${code}`);
}

function setCachedHighlight(code: string, lang: string, result: string[]): void {
  const key = `${lang}:${code}`;
  // Simple LRU-ish: clear oldest entries when cache is full
  if (codeBlockCache.size >= MAX_CACHE_SIZE) {
    const firstKey = codeBlockCache.keys().next().value;
    if (firstKey) codeBlockCache.delete(firstKey);
  }
  codeBlockCache.set(key, result);
}

// Optimized escapeHtml - fast path for strings without special chars
export function escapeHtml(text: string): string {
  // Fast path: check if any escaping is needed
  let needsEscape = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "&" || c === "<" || c === ">" || c === '"') {
      needsEscape = true;
      break;
    }
  }
  if (!needsEscape) return text;

  // Slow path: build escaped string
  const parts: string[] = [];
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    let escape: string | null = null;
    switch (c) {
      case "&": escape = "&amp;"; break;
      case "<": escape = "&lt;"; break;
      case ">": escape = "&gt;"; break;
      case '"': escape = "&quot;"; break;
    }
    if (escape) {
      if (i > start) parts.push(text.slice(start, i));
      parts.push(escape);
      start = i + 1;
    }
  }
  if (start < text.length) parts.push(text.slice(start));
  return parts.join("");
}

export interface FenceInfo {
  /** Leading whitespace before the fence marker (up to 3 spaces). */
  indent: string;
  /** The run of fence characters, e.g. "```" or "~~~~". */
  marker: string;
  /** Fence character: "`" or "~". */
  char: string;
  /** Everything after the marker, verbatim (info string). */
  info: string;
  /** First word of the info string, lowercased — the language. */
  lang: string;
}

// CommonMark: up to 3 leading spaces, then 3+ backticks or 3+ tildes.
const FENCE_RE = /^( {0,3})(`{3,}|~{3,})(.*)$/;

/**
 * Match an opening code fence. Returns null when the line does not open one.
 *
 * A backtick fence may not carry a backtick in its info string (otherwise
 * `` `x` `` inside a paragraph would read as a fence), which is why this is not
 * a plain `/^`{3,}/` test.
 */
export function matchFenceOpen(line: string): FenceInfo | null {
  const m = FENCE_RE.exec(line);
  if (!m) return null;
  const indent = m[1]!;
  const marker = m[2]!;
  const info = m[3]!;
  const char = marker[0]!;
  if (char === "`" && info.includes("`")) return null;
  const lang = info.trim().split(/\s+/)[0] ?? "";
  return { indent, marker, char, info, lang: lang.toLowerCase() };
}

/**
 * Does `line` close a fence opened with `char` repeated `length` times?
 * A closing fence uses the same character, is at least as long, and carries
 * nothing but whitespace after the marker.
 */
export function matchFenceClose(line: string, char: string, length: number): boolean {
  const m = FENCE_RE.exec(line);
  if (!m) return false;
  const marker = m[2]!;
  if (marker[0] !== char) return false;
  if (marker.length < length) return false;
  return m[3]!.trim() === "";
}

/**
 * Highlight a whole document, one entry per source line.
 * `result.length` always equals `source.split("\n").length`.
 */
export function highlightMarkdownLines(source: string): string[] {
  const lines = source.split("\n");
  const result: string[] = [];
  let open: FenceInfo | null = null;
  let codeBlockContent: string[] = [];

  const flushCodeBlock = (lang: string) => {
    if (codeBlockContent.length === 0) return;
    const highlighted = highlightCodeBlockLines(codeBlockContent, lang);
    for (let j = 0; j < codeBlockContent.length; j++) {
      result.push(highlighted[j] ?? escapeHtml(codeBlockContent[j]!));
    }
    codeBlockContent = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;

    if (open === null) {
      const fence = matchFenceOpen(line);
      if (fence) {
        open = fence;
        codeBlockContent = [];
        result.push(highlightFenceLine(fence));
      } else {
        result.push(highlightMarkdownLine(line));
      }
      continue;
    }

    if (matchFenceClose(line, open.char, open.marker.length)) {
      flushCodeBlock(open.lang);
      result.push(`<span class="md-fence">${escapeHtml(line)}</span>`);
      open = null;
      continue;
    }

    codeBlockContent.push(line);
  }

  // Unclosed code block: still highlight its body, the way an editor should
  // while the closing fence is being typed.
  if (open !== null) {
    flushCodeBlock(open.lang);
  }

  return result;
}

/**
 * Allocation-free pre-check: could `source[start, end)` be a fence line at all?
 * Runs on every line ahead of the cursor on each keystroke, so it avoids
 * slicing out lines that plainly cannot be fences.
 */
function mayBeFence(source: string, start: number, end: number): boolean {
  let i = start;
  while (i < end && i - start < 3 && source.charCodeAt(i) === 32 /* space */) i++;
  const c = source.charCodeAt(i);
  if (c !== 96 /* ` */ && c !== 126 /* ~ */) return false;
  return i + 2 < end && source.charCodeAt(i + 1) === c && source.charCodeAt(i + 2) === c;
}

/**
 * True when line `lineIdx` cannot be repainted on its own — it either sits
 * inside a fenced code block or opens one, so its rendering depends on (or
 * changes) the surrounding lines.
 */
export function lineNeedsFullRehighlight(source: string, lineIdx: number): boolean {
  if (lineIdx < 0) return true;
  let open: FenceInfo | null = null;
  let idx = 0;
  let pos = 0;
  const len = source.length;

  for (;;) {
    const nl = source.indexOf("\n", pos);
    const end = nl === -1 ? len : nl;
    const couldBeFence = mayBeFence(source, pos, end);

    if (idx === lineIdx) {
      // Inside a fence (body or closing line), or opening a new one.
      if (open !== null) return true;
      return couldBeFence && matchFenceOpen(source.slice(pos, end)) !== null;
    }

    if (couldBeFence) {
      const line = source.slice(pos, end);
      if (open === null) {
        const fence = matchFenceOpen(line);
        if (fence) open = fence;
      } else if (matchFenceClose(line, open.char, open.marker.length)) {
        open = null;
      }
    }

    if (nl === -1) return true; // lineIdx past the end of the document
    pos = nl + 1;
    idx++;
  }
}

export type LineEdit =
  | { kind: "none" }
  | { kind: "single"; line: number }
  | { kind: "multi" };

/**
 * Classify the edit between two document revisions.
 *
 * Returns `single` only when the change is provably confined to one line and
 * the line count is unchanged, which is what lets the overlay repaint a single
 * `<div>`. Everything else — newline inserted or removed, multi-line paste —
 * reports `multi`. Unlike a cursor/length heuristic this never mistakes a
 * selection replacement or a programmatic edit for a one-character keystroke.
 */
export function diffLineEdit(prev: string, next: string): LineEdit {
  if (prev === next) return { kind: "none" };

  const prevLen = prev.length;
  const nextLen = next.length;
  const maxCommon = Math.min(prevLen, nextLen);

  let prefix = 0;
  while (prefix < maxCommon && prev.charCodeAt(prefix) === next.charCodeAt(prefix)) prefix++;

  let suffix = 0;
  const maxSuffix = maxCommon - prefix;
  while (
    suffix < maxSuffix &&
    prev.charCodeAt(prevLen - 1 - suffix) === next.charCodeAt(nextLen - 1 - suffix)
  ) {
    suffix++;
  }

  // Changed regions are prev[prefix, prevEnd) and next[prefix, nextEnd).
  const prevEnd = prevLen - suffix;
  const nextEnd = nextLen - suffix;

  const prevNewline = prev.indexOf("\n", prefix);
  if (prevNewline !== -1 && prevNewline < prevEnd) return { kind: "multi" };
  const nextNewline = next.indexOf("\n", prefix);
  if (nextNewline !== -1 && nextNewline < nextEnd) return { kind: "multi" };

  let line = 0;
  for (let i = 0; i < prefix; i++) {
    if (next.charCodeAt(i) === 10 /* \n */) line++;
  }
  return { kind: "single", line };
}

/** Raw text of line `lineIdx`, without splitting the whole document. */
export function lineAt(source: string, lineIdx: number): string {
  let start = 0;
  for (let i = 0; i < lineIdx; i++) {
    const nl = source.indexOf("\n", start);
    if (nl === -1) return "";
    start = nl + 1;
  }
  const end = source.indexOf("\n", start);
  return end === -1 ? source.slice(start) : source.slice(start, end);
}

/** Number of lines in `source` (a trailing newline opens one more line). */
export function countLines(source: string): number {
  let count = 1;
  for (let i = 0; i < source.length; i++) {
    if (source.charCodeAt(i) === 10 /* \n */) count++;
  }
  return count;
}

// Legacy helper - returns the document as one joined string
function highlightMarkdown(source: string): string {
  return highlightMarkdownLines(source).join("\n");
}

function highlightFenceLine(fence: FenceInfo): string {
  let html = escapeHtml(fence.indent);
  html += `<span class="md-fence">${escapeHtml(fence.marker)}</span>`;
  if (fence.info) {
    html += `<span class="md-fence-lang">${escapeHtml(fence.info)}</span>`;
  }
  return html;
}

function highlightCodeBlockLines(lines: string[], lang: string): string[] {
  if (lines.length === 0) return [];

  const code = lines.join("\n");
  const rawLang = lang.trim().toLowerCase();
  if (rawLang === "md" || rawLang === "markdown") {
    const cachedMd = getCachedHighlight(code, "markdown");
    if (cachedMd) return cachedMd;
    const result = highlightMarkdown(code).split("\n");
    setCachedHighlight(code, "markdown", result);
    return result;
  }

  const mappedLang = normalizeHighlightLanguage(lang);

  if (mappedLang === null) {
    const result = lines.map((line) => escapeHtml(line));
    setCachedHighlight(code, lang, result);
    return result;
  }

  // Check cache first
  const cached = getCachedHighlight(code, mappedLang);
  if (cached) return cached;

  // Use lazily loaded syntax highlighters for supported languages.
  const highlighter = getLoadedHighlighter(mappedLang);
  if (!highlighter) {
    requestHighlighter(mappedLang);
    const plain = lines.map((line) => escapeHtml(line));
    setCachedHighlight(code, mappedLang, plain);
    return plain;
  }

  let result: string[];
  try {
    const html = highlighter(code);
    // Extract content from highlight output
    const match = html.match(/<code>([\s\S]*)<\/code>/);
    if (match) {
      const content = match[1]!;
      const resultLines: string[] = [];
      const rawLines = content.split("\n");
      for (const rawLine of rawLines) {
        const cleaned = rawLine.replace(/^<span class="line">/, "").replace(/<\/span>$/, "");
        resultLines.push(cleaned);
      }
      if (resultLines.length > 0 && resultLines[resultLines.length - 1] === "") {
        resultLines.pop();
      }
      result = resultLines;
    } else {
      result = lines.map((line) => escapeHtml(line));
    }
  } catch (e) {
    console.error("Code highlight error:", e);
    result = lines.map((line) => escapeHtml(line));
  }

  setCachedHighlight(code, mappedLang, result);
  return result;
}

/** Highlight one markdown line (never a fenced-code line). */
export function highlightMarkdownLine(line: string): string {
  // Empty line
  if (!line) return "";

  // Check cache first
  const cached = lineCache.get(line);
  if (cached !== undefined) return cached;

  const result = highlightMarkdownLineImpl(line);

  // Cache the result (with LRU-ish eviction)
  if (lineCache.size >= MAX_CACHE_SIZE) {
    const firstKey = lineCache.keys().next().value;
    if (firstKey !== undefined) lineCache.delete(firstKey);
  }
  lineCache.set(line, result);
  return result;
}

function highlightMarkdownLineImpl(line: string): string {
  // Heading
  const headingMatch = line.match(/^(#{1,6})\s+(.*)$/);
  if (headingMatch) {
    const marker = headingMatch[1]!;
    const text = headingMatch[2]!;
    return `<span class="md-heading-marker">${marker}</span> <span class="md-heading">${highlightInline(text)}</span>`;
  }

  // Horizontal rule
  if (/^(\*{3,}|-{3,}|_{3,})\s*$/.test(line)) {
    return `<span class="md-hr">${escapeHtml(line)}</span>`;
  }

  // Blockquote
  const quoteMatch = line.match(/^(>\s*)(.*)$/);
  if (quoteMatch) {
    return `<span class="md-blockquote">${escapeHtml(quoteMatch[1]!)}</span>${highlightInline(quoteMatch[2]!)}`;
  }

  // List items (unordered)
  const ulMatch = line.match(/^(\s*)([-*+])\s+(.*)$/);
  if (ulMatch) {
    const indent = ulMatch[1]!;
    const marker = ulMatch[2]!;
    const text = ulMatch[3]!;
    return `${escapeHtml(indent)}<span class="md-list-marker">${marker}</span> ${highlightInline(text)}`;
  }

  // List items (ordered)
  const olMatch = line.match(/^(\s*)(\d+\.)\s+(.*)$/);
  if (olMatch) {
    const indent = olMatch[1]!;
    const marker = olMatch[2]!;
    const text = olMatch[3]!;
    return `${escapeHtml(indent)}<span class="md-list-marker">${marker}</span> ${highlightInline(text)}`;
  }

  // Regular paragraph - highlight inline elements
  return highlightInline(line);
}

function highlightInline(text: string): string {
  if (!text) return "";

  // Check cache first
  const cached = inlineCache.get(text);
  if (cached !== undefined) return cached;

  const result = highlightInlineImpl(text);

  // Cache the result
  if (inlineCache.size >= MAX_INLINE_CACHE_SIZE) {
    const firstKey = inlineCache.keys().next().value;
    if (firstKey !== undefined) inlineCache.delete(firstKey);
  }
  inlineCache.set(text, result);
  return result;
}

function highlightInlineImpl(text: string): string {
  let result = "";
  let i = 0;
  const len = text.length;

  while (i < len) {
    // Escaped character
    if (text[i] === "\\" && i + 1 < len) {
      result += `<span class="md-escape">${escapeHtml(text[i]! + text[i + 1]!)}</span>`;
      i += 2;
      continue;
    }

    // Inline code
    if (text[i] === "`") {
      const endIdx = text.indexOf("`", i + 1);
      if (endIdx !== -1) {
        const code = text.slice(i + 1, endIdx);
        result += `<span class="md-code-marker">\`</span><span class="md-code">${escapeHtml(code)}</span><span class="md-code-marker">\`</span>`;
        i = endIdx + 1;
        continue;
      }
    }

    // Bold + Italic (***text*** or ___text___)
    const boldItalicMatch = text.slice(i).match(/^(\*{3}|_{3})([^\*_]+)\1/);
    if (boldItalicMatch) {
      const marker = boldItalicMatch[1]!;
      const content = boldItalicMatch[2]!;
      result += `<span class="md-bold-italic">${escapeHtml(marker)}${escapeHtml(content)}${escapeHtml(marker)}</span>`;
      i += boldItalicMatch[0].length;
      continue;
    }

    // Bold (**text** or __text__)
    const boldMatch = text.slice(i).match(/^(\*{2}|_{2})([^\*_]+)\1/);
    if (boldMatch) {
      const marker = boldMatch[1]!;
      const content = boldMatch[2]!;
      result += `<span class="md-bold">${escapeHtml(marker)}${escapeHtml(content)}${escapeHtml(marker)}</span>`;
      i += boldMatch[0].length;
      continue;
    }

    // Italic (*text* or _text_)
    const italicMatch = text.slice(i).match(/^(\*|_)([^\*_]+)\1/);
    if (italicMatch) {
      const marker = italicMatch[1]!;
      const content = italicMatch[2]!;
      result += `<span class="md-italic">${escapeHtml(marker)}${escapeHtml(content)}${escapeHtml(marker)}</span>`;
      i += italicMatch[0].length;
      continue;
    }

    // Strikethrough (~~text~~)
    const strikeMatch = text.slice(i).match(/^~~([^~]+)~~/);
    if (strikeMatch) {
      const content = strikeMatch[1]!;
      result += `<span class="md-strikethrough">~~${escapeHtml(content)}~~</span>`;
      i += strikeMatch[0].length;
      continue;
    }

    // Image (![alt](url))
    const imgMatch = text.slice(i).match(/^!\[([^\]]*)\]\(([^)]+)\)/);
    if (imgMatch) {
      const alt = imgMatch[1]!;
      const url = imgMatch[2]!;
      result += `<span class="md-image">![${escapeHtml(alt)}]</span><span class="md-link-bracket">(</span><span class="md-link-url">${escapeHtml(url)}</span><span class="md-link-bracket">)</span>`;
      i += imgMatch[0].length;
      continue;
    }

    // Link ([text](url))
    const linkMatch = text.slice(i).match(/^\[([^\]]+)\]\(([^)]+)\)/);
    if (linkMatch) {
      const linkText = linkMatch[1]!;
      const url = linkMatch[2]!;
      result += `<span class="md-link-bracket">[</span><span class="md-link-text">${escapeHtml(linkText)}</span><span class="md-link-bracket">](</span><span class="md-link-url">${escapeHtml(url)}</span><span class="md-link-bracket">)</span>`;
      i += linkMatch[0].length;
      continue;
    }

    // HTML tags
    const htmlMatch = text.slice(i).match(/^<[^>]+>/);
    if (htmlMatch) {
      result += `<span class="md-html">${escapeHtml(htmlMatch[0])}</span>`;
      i += htmlMatch[0].length;
      continue;
    }

    // Regular character
    result += escapeHtml(text[i]!);
    i++;
  }

  return result;
}
