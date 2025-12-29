import { createEffect, onMount, createSignal, createMemo, For } from "@luna_ui/luna";
// @ts-ignore - no type declarations for lezer_api.js
import { highlight } from "../js/lezer_api.js";

interface SyntaxHighlightEditorProps {
  value: () => string;  // Always accessor for fine-grained reactivity
  onChange: (value: string) => void;
  onCursorChange?: (position: number) => void;
  initialCursorPosition?: number;
  ref?: (handle: SyntaxHighlightEditorHandle) => void;
  showLineNumbers?: boolean; // Default: false for better performance
}

// Language alias mapping
const langMap: Record<string, string> = {
  js: "typescript",
  javascript: "typescript",
  ts: "typescript",
  tsx: "typescript",
  jsx: "typescript",
  mbt: "moonbit",
  md: "markdown",
  markdown: "markdown",
  sh: "bash",
  bash: "bash",
  shell: "bash",
  zsh: "bash",
  rs: "rust",
};

const supportedLangs = ["typescript", "moonbit", "json", "html", "css", "bash", "rust"];

// Cache for code block highlighting - avoids re-highlighting unchanged blocks
const codeBlockCache = new Map<string, string[]>();
// Cache for markdown line highlighting
const lineCache = new Map<string, string>();
// Cache for inline highlighting
const inlineCache = new Map<string, string>();
const MAX_CACHE_SIZE = 100;
const MAX_INLINE_CACHE_SIZE = 200;

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
function escapeHtml(text: string): string {
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

// Returns array of highlighted lines (for incremental updates)
function highlightMarkdownLines(source: string): string[] {
  const lines = source.split("\n");
  const result: string[] = [];
  let inCodeBlock = false;
  let codeBlockLang = "";
  let codeBlockFenceLen = 0;
  let codeBlockContent: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;

    // Check for code fence
    const fenceMatch = line.match(/^(`{3,})([\w]*)\s*$/);

    if (fenceMatch && !inCodeBlock) {
      // Start of code block
      inCodeBlock = true;
      codeBlockFenceLen = fenceMatch[1]!.length;
      codeBlockLang = (fenceMatch[2] || "").toLowerCase();
      codeBlockContent = [];
      result.push(highlightFenceLine(line, fenceMatch[1]!, fenceMatch[2] || ""));
    } else if (inCodeBlock) {
      // Check for end of code block
      const endFenceMatch = line.match(/^(`{3,})\s*$/);
      if (endFenceMatch && endFenceMatch[1]!.length >= codeBlockFenceLen) {
        // End of code block - highlight and add all content lines
        const highlightedLines = highlightCodeBlockLines(codeBlockContent, codeBlockLang);
        for (let j = 0; j < codeBlockContent.length; j++) {
          result.push(highlightedLines[j] ?? escapeHtml(codeBlockContent[j]!));
        }
        result.push(`<span class="md-fence">${escapeHtml(line)}</span>`);
        inCodeBlock = false;
        codeBlockLang = "";
        codeBlockContent = [];
      } else {
        // Inside code block - accumulate
        codeBlockContent.push(line);
      }
    } else {
      // Regular markdown line
      result.push(highlightMarkdownLine(line));
    }
  }

  // Handle unclosed code block
  if (inCodeBlock) {
    for (const line of codeBlockContent) {
      result.push(escapeHtml(line));
    }
  }

  return result;
}

// Legacy function for compatibility - returns joined string
function highlightMarkdown(source: string): string {
  return highlightMarkdownLines(source).join("\n");
}

function highlightFenceLine(line: string, fence: string, lang: string): string {
  let html = `<span class="md-fence">${escapeHtml(fence)}</span>`;
  if (lang) {
    html += `<span class="md-fence-lang">${escapeHtml(lang)}</span>`;
  }
  return html;
}

function highlightCodeBlockLines(lines: string[], lang: string): string[] {
  if (lines.length === 0) return [];

  const mappedLang = langMap[lang] || lang;
  const code = lines.join("\n");

  // Check cache first
  const cached = getCachedHighlight(code, mappedLang);
  if (cached) return cached;

  let result: string[];

  // For markdown blocks, recursively highlight
  if (mappedLang === "markdown") {
    const highlighted = highlightMarkdown(code);
    result = highlighted.split("\n");
  }
  // Use our syntax highlighters for supported languages
  else if (supportedLangs.includes(mappedLang)) {
    try {
      const html = highlight(code, mappedLang);
      // Extract content from shiki output
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
  } else {
    // Fallback: just escape each line
    result = lines.map((line) => escapeHtml(line));
  }

  // Cache the result
  setCachedHighlight(code, mappedLang, result);
  return result;
}

function highlightMarkdownLine(line: string): string {
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

// Fast DOM update - use textContent for plain text, innerHTML only when needed
function setLineContent(el: HTMLElement, html: string): void {
  if (!html || html === "&nbsp;") {
    el.textContent = "\u00A0"; // Non-breaking space
    return;
  }
  // Check if HTML contains any tags (fast check)
  const hasTag = html.indexOf("<") !== -1;
  if (!hasTag) {
    // Plain text with HTML entities - decode and use textContent
    // Fast path: check for common entities
    if (html.indexOf("&") !== -1) {
      // Has entities - decode them
      el.textContent = html
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"');
    } else {
      // Pure text - use directly
      el.textContent = html;
    }
  } else {
    // Has HTML formatting - must use innerHTML
    el.innerHTML = html;
  }
}

export interface SyntaxHighlightEditorHandle {
  focus: () => void;
}

export function SyntaxHighlightEditor(props: SyntaxHighlightEditorProps) {
  let editorRef: HTMLTextAreaElement | null = null;
  let highlightRef: HTMLDivElement | null = null;
  let lineNumbersRef: HTMLDivElement | null = null;
  let wrapperRef: HTMLDivElement | null = null;
  let initialized = false;

  // Incremental update state - track previous highlighted lines for diff
  let prevHighlightedLines: string[] = [];
  let lineElements: HTMLDivElement[] = [];
  let lastCursorLine = -1; // Track which line cursor is on for targeted updates
  let lastValueLength = 0; // Track value length for fast newline detection

  // Track if change came from user input (to skip redundant textarea.value update)
  let isUserInput = false;

  // Signal for line count - enables efficient updates (only when count changes)
  const [lineCount, setLineCount] = createSignal(1);

  // Expose handle via ref prop
  onMount(() => {
    if (props.ref) {
      props.ref({
        focus: () => editorRef?.focus(),
      });
    }
  });

  // Get line number and line content from cursor position (0-indexed)
  // Returns [lineNumber, lineStart, lineEnd] without splitting entire string
  const getLineInfo = (text: string, pos: number): [number, number, number] => {
    let line = 0;
    let lineStart = 0;
    for (let i = 0; i < pos && i < text.length; i++) {
      if (text[i] === "\n") {
        line++;
        lineStart = i + 1;
      }
    }
    // Find line end
    let lineEnd = text.indexOf("\n", pos);
    if (lineEnd === -1) lineEnd = text.length;
    return [line, lineStart, lineEnd];
  };

  // Count lines without creating array (faster than split for large docs)
  const countLines = (text: string): number => {
    let count = 1;
    for (let i = 0; i < text.length; i++) {
      if (text[i] === "\n") count++;
    }
    return count;
  };

  // Highlight a single line
  const highlightSingleLine = (line: string): string => {
    // Check cache first
    const cached = lineCache.get(line);
    if (cached !== undefined) return cached;
    return highlightMarkdownLine(line);
  };

  // Incremental highlight update - only update changed lines
  const updateHighlight = () => {
    if (!highlightRef || !editorRef) return;
    const value = props.value();
    const valueLen = value.length;
    const cursorPos = editorRef.selectionStart;
    const [cursorLine, lineStart, lineEnd] = getLineInfo(value, cursorPos);

    // First render - must do full highlight
    if (lineElements.length === 0) {
      const newHighlightedLines = highlightMarkdownLines(value);
      highlightRef.innerHTML = "";
      for (let i = 0; i < newHighlightedLines.length; i++) {
        const div = document.createElement("div");
        div.className = "highlight-line";
        setLineContent(div, newHighlightedLines[i]!);
        highlightRef.appendChild(div);
        lineElements.push(div);
      }
      prevHighlightedLines = newHighlightedLines;
      lastCursorLine = cursorLine;
      lastValueLength = valueLen;
      return;
    }

    // Fast check for line count change:
    // - If exactly 1 char was added/removed, check if it's a newline
    // - Otherwise, do full count
    const lengthDiff = valueLen - lastValueLength;
    let lineCountChanged = false;

    if (lengthDiff === 1) {
      // Single char added - check if it's newline at cursor-1
      lineCountChanged = cursorPos > 0 && value[cursorPos - 1] === "\n";
    } else if (lengthDiff === -1) {
      // Single char deleted - cursor line changed means newline was deleted
      lineCountChanged = cursorLine !== lastCursorLine;
    } else if (lengthDiff !== 0) {
      // Multiple chars changed (paste, cut, etc.) - must count
      const newLineCount = countLines(value);
      lineCountChanged = newLineCount !== prevHighlightedLines.length;
    }

    lastValueLength = valueLen;

    // If line count changed or cursor jumped lines, do full re-highlight
    if (lineCountChanged || Math.abs(cursorLine - lastCursorLine) > 1) {
      const newHighlightedLines = highlightMarkdownLines(value);
      const maxLen = Math.max(lineElements.length, newHighlightedLines.length);

      for (let i = 0; i < maxLen; i++) {
        if (i >= newHighlightedLines.length) {
          lineElements[i]?.remove();
        } else if (i >= lineElements.length) {
          const div = document.createElement("div");
          div.className = "highlight-line";
          setLineContent(div, newHighlightedLines[i]!);
          highlightRef.appendChild(div);
          lineElements.push(div);
        } else if (prevHighlightedLines[i] !== newHighlightedLines[i]) {
          setLineContent(lineElements[i], newHighlightedLines[i]!);
        }
      }

      if (newHighlightedLines.length < lineElements.length) {
        lineElements.length = newHighlightedLines.length;
      }

      prevHighlightedLines = newHighlightedLines;
      lastCursorLine = cursorLine;
      return;
    }

    // Fast path: only the cursor line changed (single character typed)
    // Extract just the current line without splitting entire string
    const rawLine = value.slice(lineStart, lineEnd);

    if (lineElements[cursorLine]) {
      const newHighlight = highlightSingleLine(rawLine);
      if (prevHighlightedLines[cursorLine] !== newHighlight) {
        setLineContent(lineElements[cursorLine], newHighlight);
        prevHighlightedLines[cursorLine] = newHighlight;
      }
    }

    lastCursorLine = cursorLine;
  };

  const syncScroll = () => {
    if (!editorRef || !highlightRef) return;
    highlightRef.style.transform = `translate(${-editorRef.scrollLeft}px, ${-editorRef.scrollTop}px)`;
    if (props.showLineNumbers && lineNumbersRef) {
      lineNumbersRef.style.transform = `translateY(${-editorRef.scrollTop}px)`;
    }
  };

  // Direct highlight update - Luna's signal batch handles scheduling via queueMicrotask
  const scheduleHighlight = () => {
    updateHighlight();
  };

  // Update textarea value and schedule highlight when value changes
  createEffect(() => {
    // Access props.value() to subscribe to changes
    const value = props.value();

    // Only update textarea if change came from external source (not user input)
    // Skip both the comparison and assignment for user input (both are expensive for large docs)
    if (isUserInput) {
      isUserInput = false; // Reset flag
    } else if (editorRef) {
      // External change - must update textarea
      editorRef.value = value;
    }

    // Update line count only if line numbers are shown
    if (props.showLineNumbers) {
      // Count newlines directly (faster than split for large docs)
      let newLineCount = 1;
      for (let i = 0; i < value.length; i++) {
        if (value[i] === "\n") newLineCount++;
      }
      if (newLineCount !== lineCount()) {
        setLineCount(newLineCount);
      }
    }

    // Schedule highlight update for next frame
    scheduleHighlight();
  });


  // Setup function called when editor ref is set
  const setupEditor = (el: HTMLTextAreaElement) => {
    editorRef = el;
    const value = props.value();

    // Set initial value
    el.value = value;

    // Reset scroll position
    el.scrollTop = 0;
    el.scrollLeft = 0;

    // Defer initial line count to avoid updating signal during render
    if (props.showLineNumbers) {
      queueMicrotask(() => {
        setLineCount(value.split("\n").length);
      });
    }

    // Initial highlight (synchronous for initial render)
    updateHighlight();

    // Reset transforms
    if (highlightRef) {
      highlightRef.style.transform = "translate(0px, 0px)";
    }
    if (props.showLineNumbers && lineNumbersRef) {
      lineNumbersRef.style.transform = "translateY(0px)";
    }

    // Restore cursor position
    if (props.initialCursorPosition != null && props.initialCursorPosition > 0) {
      const pos = Math.min(props.initialCursorPosition, value.length);
      el.setSelectionRange(pos, pos);
      initialized = true;
    }
  };

  const handleInput = (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    isUserInput = true; // Mark as user input to skip redundant textarea.value update
    props.onChange(target.value);
    props.onCursorChange?.(target.selectionStart);
  };

  const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key === "Tab") {
      e.preventDefault();
      const target = e.target as HTMLTextAreaElement;
      const start = target.selectionStart;
      const end = target.selectionEnd;
      target.setRangeText("  ", start, end, "end");
      isUserInput = true; // Mark as user input
      props.onChange(target.value);
    }
  };

  const handleCursorUpdate = (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    props.onCursorChange?.(target.selectionStart);
  };

  // Memoized array for For component - fine-grained updates (fixed in Luna 0.3.3)
  const lineNumbersArray = createMemo(() => {
    const count = lineCount();
    return Array.from({ length: count }, (_, i) => i + 1);
  });

  return (
    <div class="syntax-editor-container">
      {props.showLineNumbers && (
        <div class="line-numbers" ref={(el) => { lineNumbersRef = el; }}>
          <For each={lineNumbersArray}>
            {(num) => <div class="line-number">{num}</div>}
          </For>
        </div>
      )}
      <div class="editor-wrapper" ref={(el) => { wrapperRef = el; }}>
        <div class="editor-highlight" ref={(el) => { highlightRef = el; }}></div>
        <textarea
          ref={setupEditor}
          class="editor-textarea"
          onInput={handleInput}
          onScroll={syncScroll}
          onKeyDown={handleKeyDown}
          onKeyUp={handleCursorUpdate}
          onClick={handleCursorUpdate}
          spellcheck={false}
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
        />
      </div>
    </div>
  );
}
