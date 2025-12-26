import { useRef, useEffect, useCallback, useState, useImperativeHandle } from "preact/hooks";
import { forwardRef } from "preact/compat";
// @ts-ignore - no type declarations for lezer_api.js
import { highlight } from "../js/lezer_api.js";

interface SyntaxHighlightEditorProps {
  value: string;
  onChange: (value: string) => void;
  onCursorChange?: (position: number) => void;
  initialCursorPosition?: number;
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
  shell: "bash",
  zsh: "bash",
};

const supportedLangs = ["typescript", "moonbit", "json", "html", "css", "bash"];

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function highlightMarkdown(source: string): string {
  const lines = source.split("\n");
  const result: string[] = [];
  let inCodeBlock = false;
  let codeBlockLang = "";
  let codeBlockFenceLen = 0;
  let codeBlockContent: string[] = [];
  let codeBlockStartLine = -1;

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
      codeBlockStartLine = i;
      result.push(highlightFenceLine(line, fenceMatch[1]!, fenceMatch[2] || ""));
    } else if (inCodeBlock) {
      // Check for end of code block
      const endFenceMatch = line.match(/^(`{3,})\s*$/);
      if (endFenceMatch && endFenceMatch[1]!.length >= codeBlockFenceLen) {
        // End of code block - highlight and add all content lines
        const highlightedLines = highlightCodeBlockLines(codeBlockContent, codeBlockLang);
        // Ensure we have the same number of lines
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

  // Handle unclosed code block - add accumulated lines as escaped text
  if (inCodeBlock) {
    for (const line of codeBlockContent) {
      result.push(escapeHtml(line));
    }
  }

  return result.join("\n");
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

  // For markdown blocks, recursively highlight
  if (mappedLang === "markdown") {
    const code = lines.join("\n");
    const highlighted = highlightMarkdown(code);
    return highlighted.split("\n");
  }

  // Use our syntax highlighters for supported languages
  if (supportedLangs.includes(mappedLang)) {
    try {
      const code = lines.join("\n");
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
        return resultLines;
      }
    } catch (e) {
      console.error("Code highlight error:", e);
    }
  }

  // Fallback: just escape each line
  return lines.map((line) => escapeHtml(line));
}

function highlightMarkdownLine(line: string): string {
  // Empty line
  if (!line) return "";

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

export interface SyntaxHighlightEditorHandle {
  focus: () => void;
}

export const SyntaxHighlightEditor = forwardRef<SyntaxHighlightEditorHandle, SyntaxHighlightEditorProps>(
  function SyntaxHighlightEditor({ value, onChange, onCursorChange, initialCursorPosition }, ref) {
  const editorRef = useRef<HTMLTextAreaElement>(null);
  const highlightRef = useRef<HTMLDivElement>(null);
  const lineNumbersRef = useRef<HTMLDivElement>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const initializedRef = useRef(false);

  useImperativeHandle(ref, () => ({
    focus: () => editorRef.current?.focus(),
  }));

  const updateHighlight = useCallback(() => {
    if (!highlightRef.current) return;

    try {
      const html = highlightMarkdown(value);
      highlightRef.current.innerHTML = html;
    } catch (e) {
      console.error("Highlight error:", e);
      highlightRef.current.innerHTML = escapeHtml(value);
    }
  }, [value]);

  const updateLineNumbers = useCallback(() => {
    if (!lineNumbersRef.current) return;
    const lines = value.split("\n");
    let html = "";
    for (let i = 1; i <= lines.length; i++) {
      html += `<div class="line-number">${i}</div>`;
    }
    lineNumbersRef.current.innerHTML = html;
  }, [value]);

  const syncScroll = useCallback(() => {
    if (!editorRef.current || !highlightRef.current || !lineNumbersRef.current) return;
    highlightRef.current.style.transform = `translate(${-editorRef.current.scrollLeft}px, ${-editorRef.current.scrollTop}px)`;
    lineNumbersRef.current.style.transform = `translateY(${-editorRef.current.scrollTop}px)`;
  }, []);

  // Update on value change
  useEffect(() => {
    updateHighlight();
    updateLineNumbers();
  }, [updateHighlight, updateLineNumbers]);

  // Restore initial cursor position once
  useEffect(() => {
    if (!initializedRef.current && editorRef.current && initialCursorPosition != null && initialCursorPosition > 0) {
      const pos = Math.min(initialCursorPosition, value.length);
      editorRef.current.setSelectionRange(pos, pos);
      editorRef.current.focus();
      initializedRef.current = true;
    }
  }, [initialCursorPosition, value.length]);

  const handleInput = useCallback(
    (e: Event) => {
      const target = e.target as HTMLTextAreaElement;
      // Always update value to keep controlled component in sync
      onChange(target.value);
      onCursorChange?.(target.selectionStart);
    },
    [onChange, onCursorChange]
  );

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === "Tab") {
        e.preventDefault();
        const target = e.target as HTMLTextAreaElement;
        const start = target.selectionStart;
        const end = target.selectionEnd;
        target.setRangeText("  ", start, end, "end");
        onChange(target.value);
      }
    },
    [onChange]
  );


  const handleCursorUpdate = useCallback(
    (e: Event) => {
      const target = e.target as HTMLTextAreaElement;
      onCursorChange?.(target.selectionStart);
    },
    [onCursorChange]
  );

  return (
    <div class="syntax-editor-container">
      <div class="line-numbers" ref={lineNumbersRef}></div>
      <div class="editor-wrapper" ref={wrapperRef}>
        <div class="editor-highlight" ref={highlightRef}></div>
        <textarea
          ref={editorRef}
          class="editor-textarea"
          value={value}
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
});
