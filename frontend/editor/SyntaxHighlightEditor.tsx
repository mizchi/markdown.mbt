import { createEffect, onMount, onCleanup, createSignal, createMemo, For } from "@luna_ui/luna";
import {
  countLines,
  diffLineEdit,
  highlightMarkdownLine,
  highlightMarkdownLines,
  lineAt,
  lineNeedsFullRehighlight,
  onHighlighterLoaded,
} from "./markdown-highlight.js";

export interface SyntaxHighlightEditorProps {
  value: () => string;  // Always accessor for fine-grained reactivity
  onChange: (value: string) => void;
  onCursorChange?: (position: number) => void;
  initialCursorPosition?: number;
  ref?: (handle: SyntaxHighlightEditorHandle) => void;
  showLineNumbers?: boolean; // Default: false for better performance
}

// Fast DOM update - use textContent for plain text, innerHTML only when needed
function setLineContent(el: HTMLElement, html: string): void {
  if (!html || html === "&nbsp;") {
    el.textContent = " "; // Non-breaking space
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
  getCursorPosition: () => number;
  setCursorPosition: (pos: number) => void;
  getScrollTop: () => number;
  setScrollTop: (top: number) => void;
  /**
   * Replace the editor text. `span` is accepted for backwards compatibility and
   * ignored: the overlay diffs the old and new text itself, which is both
   * cheaper and correct when the replacement changes the line count.
   */
  setValue: (value: string, span?: { start: number; end: number }) => void;
}

export function SyntaxHighlightEditor(props: SyntaxHighlightEditorProps) {
  let editorRef: HTMLTextAreaElement | null = null;
  let highlightRef: HTMLDivElement | null = null;
  let lineNumbersRef: HTMLDivElement | null = null;
  let wrapperRef: HTMLDivElement | null = null;

  // Incremental update state - the text and the highlighted HTML the overlay
  // currently shows, so the next update can diff against what is on screen.
  let prevHighlightedLines: string[] = [];
  let prevValue = "";
  let lineElements: HTMLDivElement[] = [];

  // Track if change came from user input (to skip redundant textarea.value update)
  let isUserInput = false;

  // Signal for line count - enables efficient updates (only when count changes)
  const [lineCount, setLineCount] = createSignal(1);

  // A lazily loaded code highlighter paints blocks that were rendered as plain
  // text before it arrived, so its arrival must force a full repaint - an
  // incremental pass would see identical text and leave the block unhighlighted.
  onMount(() => {
    const unsubscribe = onHighlighterLoaded(() => {
      queueMicrotask(() => updateHighlight(undefined, true));
    });
    onCleanup(() => { unsubscribe(); });
  });

  // Expose handle via ref prop
  onMount(() => {
    if (props.ref) {
      props.ref({
        focus: () => editorRef?.focus(),
        getCursorPosition: () => editorRef?.selectionStart ?? 0,
        setCursorPosition: (pos: number) => {
          if (editorRef) {
            editorRef.setSelectionRange(pos, pos);
            editorRef.focus();
          }
        },
        getScrollTop: () => editorRef?.scrollTop ?? 0,
        setScrollTop: (top: number) => {
          if (editorRef) {
            editorRef.scrollTop = top;
          }
        },
        setValue: (value: string) => {
          if (!editorRef || !highlightRef) return;
          editorRef.value = value;
          updateHighlight(value);
        },
      });
    }
  });

  // Repaint every line, reusing the existing <div>s and touching only those
  // whose HTML actually changed.
  const renderAllLines = (value: string) => {
    if (!highlightRef) return;
    const newHighlightedLines = highlightMarkdownLines(value);

    if (lineElements.length === 0) {
      highlightRef.innerHTML = "";
    }

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
        setLineContent(lineElements[i]!, newHighlightedLines[i]!);
      }
    }

    if (newHighlightedLines.length < lineElements.length) {
      lineElements.length = newHighlightedLines.length;
    }

    prevHighlightedLines = newHighlightedLines;
    prevValue = value;
  };

  /**
   * Sync the overlay with `value`.
   *
   * The line-local fast path runs only when the edit is provably confined to a
   * single line whose rendering does not depend on its neighbours - i.e. it is
   * not inside a fenced code block and does not open one. Everything else
   * repaints the document, so highlighting can never drift from the text.
   */
  const updateHighlight = (inputValue?: string, force = false) => {
    if (!highlightRef || !editorRef) return;
    const value = inputValue ?? props.value();

    // First render - must do full highlight
    if (lineElements.length === 0) {
      renderAllLines(value);
      return;
    }

    if (!force) {
      const edit = diffLineEdit(prevValue, value);
      if (edit.kind === "none") return;

      if (edit.kind === "single" && !lineNeedsFullRehighlight(value, edit.line)) {
        const el = lineElements[edit.line];
        if (el) {
          const newHighlight = highlightMarkdownLine(lineAt(value, edit.line));
          if (prevHighlightedLines[edit.line] !== newHighlight) {
            setLineContent(el, newHighlight);
            prevHighlightedLines[edit.line] = newHighlight;
          }
          prevValue = value;
          return;
        }
      }
    }

    renderAllLines(value);
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
      const newLineCount = countLines(value);
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
        setLineCount(countLines(value));
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
        <div class="line-numbers" ref={(el) => { lineNumbersRef = el as HTMLDivElement; }}>
          <For each={lineNumbersArray}>
            {(num) => <div class="line-number">{num}</div>}
          </For>
        </div>
      )}
      <div class="editor-wrapper" ref={(el) => { wrapperRef = el as HTMLDivElement; }}>
        <div class="editor-content">
          {/* The viewport is a fixed-size window; .editor-highlight is the full-height
              surface inside it that syncScroll translates to follow the textarea. */}
          <div class="editor-highlight-viewport">
            <div class="editor-highlight" ref={(el) => { highlightRef = el as HTMLDivElement; }}></div>
          </div>
          <textarea
            ref={(el) => setupEditor(el as HTMLTextAreaElement)}
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
    </div>
  );
}
