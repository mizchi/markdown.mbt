import { render, createSignal, createEffect, createMemo, onMount, onCleanup, Show, batch } from "@luna_ui/luna";
import { parse } from "../js/api.js";
import type { Root } from "mdast";
import { MarkdownRenderer, RawHtml, sanitizeSvg, type RendererCallbacks, type RendererOptions } from "./ast-renderer";
import { SyntaxHighlightEditor, type SyntaxHighlightEditorHandle } from "./SyntaxHighlightEditor";

// IndexedDB for content (reliable async storage)
const IDB_NAME = "markdown-editor";
const IDB_STORE = "documents";
const IDB_KEY = "current";

// localStorage for UI state (sync access for initial render)
const UI_STATE_KEY = "markdown-editor-ui";
const DEBOUNCE_DELAY = 300;

const initialMarkdown = `# markdown.mbt Playground

A high-performance Markdown parser written in [MoonBit](https://www.moonbitlang.com/), compiled to WebAssembly.

## Features

- **Blazing Fast**: MoonBit compiles to efficient WASM for near-native performance
- **Syntax Highlighting**: Integrated code highlighting powered by Lezer
- **Live Preview**: Real-time Markdown rendering as you type
- **Auto Save**: Your content is automatically saved to browser storage (IndexedDB)

## Code Example

\`\`\`typescript
// Syntax highlighting works for multiple languages
function greet(name: string): string {
  return \`Hello, \${name}!\`;
}
\`\`\`

\`\`\`rust
fn main() {
    println!("Hello from Rust!");
}
\`\`\`

## Markdown Support

- **Bold** and *italic* text
- [Links](https://github.com/mizchi/markdown.mbt)
- \`inline code\`
- > Blockquotes

## SVG Preview

Edit the SVG below and see live preview:

\`\`\`svg
<svg width="200" height="100" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="80" height="80" fill="#4a90d9" rx="8"/>
  <circle cx="150" cy="50" r="40" fill="#e74c3c"/>
  <text x="100" y="95" text-anchor="middle" fill="#333" font-size="12">Edit me!</text>
</svg>
\`\`\`

## Interactive Task List

Click the checkboxes below - they update the source in real-time!

- [ ] Try clicking this checkbox
- [x] This one is already checked
- [ ] Interactive editing from preview

---

Source: [github.com/mizchi/markdown.mbt](https://github.com/mizchi/markdown.mbt)
`;

// IndexedDB helpers
function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(IDB_NAME, 1);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) {
        db.createObjectStore(IDB_STORE);
      }
    };
  });
}

async function saveToIDB(content: string): Promise<number> {
  const db = await openDB();
  const timestamp = Date.now();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const store = tx.objectStore(IDB_STORE);
    const request = store.put({ content, timestamp }, IDB_KEY);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(timestamp);
    tx.oncomplete = () => db.close();
  });
}

async function loadFromIDB(): Promise<{ content: string; timestamp: number } | null> {
  try {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_STORE, "readonly");
      const store = tx.objectStore(IDB_STORE);
      const request = store.get(IDB_KEY);
      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result || null);
      tx.oncomplete = () => db.close();
    });
  } catch {
    return null;
  }
}

// Mobile detection
function isMobile(): boolean {
  return window.innerWidth < 768 || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

// UI State helpers (localStorage for sync access)
interface UIState {
  viewMode: "split" | "editor" | "preview";
  editorMode: "highlight" | "simple";
  cursorPosition: number;
}

function loadUIState(): UIState {
  const mobile = isMobile();
  try {
    const saved = localStorage.getItem(UI_STATE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved);
      // On mobile, force editor-only mode if split was saved
      const viewMode = mobile && parsed.viewMode === "split" ? "editor" : (parsed.viewMode || (mobile ? "editor" : "split"));
      // On mobile, default to simple editor
      const editorMode = parsed.editorMode || (mobile ? "simple" : "highlight");
      return {
        viewMode,
        editorMode,
        cursorPosition: parsed.cursorPosition || 0,
      };
    }
  } catch {
    // ignore parse errors
  }
  // Default: mobile uses editor-only + simple, desktop uses split + highlight
  return {
    viewMode: mobile ? "editor" : "split",
    editorMode: mobile ? "simple" : "highlight",
    cursorPosition: 0,
  };
}

function saveUIState(state: Partial<UIState>): void {
  try {
    const current = loadUIState();
    const updated = { ...current, ...state };
    localStorage.setItem(UI_STATE_KEY, JSON.stringify(updated));
  } catch {
    // ignore storage errors
  }
}

// Find block element at cursor position
function findBlockAtPosition(ast: Root, position: number): number | null {
  for (let i = 0; i < ast.children.length; i++) {
    const block = ast.children[i]!;
    const start = block.position?.start?.offset ?? 0;
    const end = block.position?.end?.offset ?? 0;
    if (position >= start && position <= end) {
      return i;
    }
  }
  // If position is beyond all blocks, return the last block
  const lastBlock = ast.children[ast.children.length - 1];
  const lastEnd = lastBlock?.position?.end?.offset ?? 0;
  if (ast.children.length > 0 && lastBlock && position >= lastEnd) {
    return ast.children.length - 1;
  }
  return null;
}

type ViewMode = "split" | "editor" | "preview";
type EditorMode = "highlight" | "simple";

// Simple editor component (created once, updated via effect)
function SimpleEditor(props: {
  value: () => string;
  onChange: (value: string) => void;
  onCursorChange?: (position: number) => void;
  ref?: (el: HTMLTextAreaElement) => void;
}) {
  let textareaRef: HTMLTextAreaElement | null = null;

  const setupTextarea = (el: HTMLTextAreaElement) => {
    textareaRef = el;
    el.value = props.value();
    props.ref?.(el);
  };

  createEffect(() => {
    const value = props.value();
    if (textareaRef && textareaRef.value !== value) {
      textareaRef.value = value;
    }
  });

  const handleInput = (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    props.onChange(target.value);
    props.onCursorChange?.(target.selectionStart);
  };

  const handleCursorUpdate = (e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    props.onCursorChange?.(target.selectionStart);
  };

  return (
    <textarea
      ref={setupTextarea}
      class="simple-editor"
      onInput={handleInput}
      onKeyUp={handleCursorUpdate}
      onClick={handleCursorUpdate}
      spellcheck={false}
    />
  );
}

// SVG Icons
function Icon(props: { svg: string }) {
  return <span dangerouslySetInnerHTML={{ __html: props.svg }} style={{ display: "flex", alignItems: "center" }} />;
}

const SPLIT_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="1" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <rect x="11" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
</svg>`;

const EDITOR_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="10" x2="12" y2="10" stroke="currentColor" stroke-width="1.5"/>
  <line x1="5" y1="14" x2="14" y2="14" stroke="currentColor" stroke-width="1.5"/>
</svg>`;

const PREVIEW_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <circle cx="10" cy="10" r="3" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <path d="M4 10 Q7 5, 10 5 Q13 5, 16 10 Q13 15, 10 15 Q7 15, 4 10" stroke="currentColor" stroke-width="1.5" fill="none"/>
</svg>`;

const HIGHLIGHT_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="none">
  <text x="2" y="14" font-size="12" fill="#d73a49" font-family="monospace" font-weight="bold">&lt;</text>
  <text x="8" y="14" font-size="12" fill="#22863a" font-family="monospace">/</text>
  <text x="12" y="14" font-size="12" fill="#0366d6" font-family="monospace" font-weight="bold">&gt;</text>
</svg>`;

const SIMPLE_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
  <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none"/>
  <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="9" x2="13" y2="9" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="12" x2="14" y2="12" stroke="currentColor" stroke-width="1" opacity="0.5"/>
  <line x1="5" y1="15" x2="10" y2="15" stroke="currentColor" stroke-width="1" opacity="0.5"/>
</svg>`;

const GITHUB_ICON = `<svg viewBox="0 0 16 16" width="20" height="20" fill="currentColor">
  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
</svg>`;



function App() {
  // Load UI state synchronously for initial render
  const initialUIState = loadUIState();
  const mobile = isMobile();

  const [source, setSource] = createSignal("");
  const [ast, setAst] = createSignal<Root | null>(null);
  const [cursorPosition, setCursorPosition] = createSignal(initialUIState.cursorPosition);
  const [isInitialized, setIsInitialized] = createSignal(false);
  const [isDark, setIsDark] = createSignal((() => {
    const saved = localStorage.getItem("theme");
    if (saved) return saved === "dark";
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  })());
  const [saveStatus, setSaveStatus] = createSignal<"saved" | "saving" | "idle">("idle");
  const [viewMode, setViewMode] = createSignal<ViewMode>(initialUIState.viewMode);
  const [editorMode, setEditorMode] = createSignal<EditorMode>(initialUIState.editorMode);

  // Memoized class names for reactivity
  const containerClass = createMemo(() => `container view-${viewMode()} editor-mode-${editorMode()}`);
  const splitBtnClass = createMemo(() => `view-mode-btn ${viewMode() === "split" ? "active" : ""}`);
  const editorBtnClass = createMemo(() => `view-mode-btn ${viewMode() === "editor" ? "active" : ""}`);
  const previewBtnClass = createMemo(() => `view-mode-btn ${viewMode() === "preview" ? "active" : ""}`);
  const highlightBtnClass = createMemo(() => `view-mode-btn ${editorMode() === "highlight" ? "active" : ""}`);
  const simpleBtnClass = createMemo(() => `view-mode-btn ${editorMode() === "simple" ? "active" : ""}`);
  const saveStatusClass = createMemo(() => `save-status ${saveStatus()}`);

  // Refs
  let editorRef: SyntaxHighlightEditorHandle | null = null;
  let simpleEditorRef: HTMLTextAreaElement | null = null;
  let previewRef: HTMLDivElement | null = null;

  // Track if content has been modified since load
  let hasModified = false;
  let lastSyncedTimestamp = 0;
  let isSaving = false;

  // Debounced source for saving
  const [debouncedSource, setDebouncedSource] = createSignal("");
  let debounceTimer: number | undefined;

  createEffect(() => {
    const value = source();
    clearTimeout(debounceTimer);
    debounceTimer = window.setTimeout(() => {
      setDebouncedSource(value);
    }, DEBOUNCE_DELAY);
  });

  // AST parsing moved to handleChange with batch() for efficiency

  const toggleDark = () => {
    setIsDark((v) => !v);
  };

  // Apply dark mode
  createEffect(() => {
    const dark = isDark();
    document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
    localStorage.setItem("theme", dark ? "dark" : "light");
  });

  const handleViewModeChange = (mode: ViewMode) => {
    setViewMode(mode);
    saveUIState({ viewMode: mode });
  };

  const handleEditorModeChange = (mode: EditorMode) => {
    const currentMode = editorMode();
    if (currentMode === mode) return;

    // Get cursor position and scroll from current editor
    let cursorPos = 0;
    let scrollTop = 0;

    if (currentMode === "highlight" && editorRef) {
      cursorPos = editorRef.getCursorPosition();
      scrollTop = editorRef.getScrollTop();
    } else if (currentMode === "simple" && simpleEditorRef) {
      cursorPos = simpleEditorRef.selectionStart;
      scrollTop = simpleEditorRef.scrollTop;
    }

    setEditorMode(mode);
    saveUIState({ editorMode: mode });

    // Apply cursor position and scroll to new editor after mode switch
    requestAnimationFrame(() => {
      if (mode === "highlight" && editorRef) {
        editorRef.setCursorPosition(cursorPos);
        editorRef.setScrollTop(scrollTop);
      } else if (mode === "simple" && simpleEditorRef) {
        simpleEditorRef.setSelectionRange(cursorPos, cursorPos);
        simpleEditorRef.scrollTop = scrollTop;
        simpleEditorRef.focus();
      }
      // Update cursor position signal for preview sync
      setCursorPosition(cursorPos);
    });
  };

  // Keyboard shortcuts for view mode
  onMount(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey) {
        if (e.key === "1") {
          e.preventDefault();
          handleViewModeChange("split");
        } else if (e.key === "2") {
          e.preventDefault();
          handleViewModeChange("editor");
        } else if (e.key === "3") {
          e.preventDefault();
          handleViewModeChange("preview");
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    onCleanup(() => window.removeEventListener("keydown", handleKeyDown));
  });

  // Load initial content from IndexedDB
  onMount(async () => {
    let content = initialMarkdown;
    let timestamp = 0;

    try {
      const idbData = await loadFromIDB();
      if (idbData && idbData.content) {
        content = idbData.content;
        timestamp = idbData.timestamp;
      }
    } catch (e) {
      console.error("Failed to load from IndexedDB:", e);
    }

    setSource(content);
    lastSyncedTimestamp = timestamp;
    // Set initialized first so Show renders and refs are set
    setIsInitialized(true);

    // Parse AST after next frame to ensure previewRef is ready
    requestAnimationFrame(() => {
      setAst(parse(content));
      editorRef?.focus();
    });
  });

  // Handle visibility change for tab sync
  onMount(() => {
    async function handleVisibilityChange() {
      if (document.visibilityState !== "visible") return;
      if (isSaving || hasModified) return;

      try {
        const idbData = await loadFromIDB();
        if (!idbData) return;

        if (idbData.timestamp > lastSyncedTimestamp) {
          setSource(idbData.content);
          // AST will be parsed by debounce effect
          lastSyncedTimestamp = idbData.timestamp;
        }
      } catch (e) {
        console.error("Failed to sync from IndexedDB:", e);
      }
    }

    document.addEventListener("visibilitychange", handleVisibilityChange);
    onCleanup(() => document.removeEventListener("visibilitychange", handleVisibilityChange));
  });

  // Save content to IndexedDB with debounce
  createEffect(() => {
    const debounced = debouncedSource();
    if (!isInitialized()) return;
    if (!hasModified) return;

    isSaving = true;
    setSaveStatus("saving");
    saveToIDB(debounced)
      .then((timestamp) => {
        lastSyncedTimestamp = timestamp;
        hasModified = false;
        isSaving = false;
        setSaveStatus("saved");
        setTimeout(() => setSaveStatus("idle"), 1000);
      })
      .catch((e) => {
        console.error("Failed to save to IndexedDB:", e);
        isSaving = false;
        setSaveStatus("idle");
      });
  });

  // Track last rendered AST version for scroll synchronization
  let lastRenderedAst: Root | null = null;

  // Handle task checkbox toggle from preview
  const handleTaskToggle = (span: string, checked: boolean) => {
    const [startStr, endStr] = span.split("-");
    const start = parseInt(startStr, 10);
    const end = parseInt(endStr, 10);

    const currentSource = source();
    const itemText = currentSource.slice(start, end);

    // Toggle [ ] <-> [x]
    const newText = checked
      ? itemText.replace(/\[ \]/, "[x]")
      : itemText.replace(/\[x\]/i, "[ ]");

    const newSource = currentSource.slice(0, start) + newText + currentSource.slice(end);

    // Update source and AST synchronously (bypass debounce for immediate feedback)
    hasModified = true;
    setSource(newSource);
    setAst(parse(newSource));

    // Sync editor text with targeted update using span
    if (editorMode() === "highlight" && editorRef) {
      editorRef.setValue(newSource, { start, end });
    } else if (simpleEditorRef) {
      simpleEditorRef.value = newSource;
    }

    // Move cursor to the toggled checkbox position and focus editor
    requestAnimationFrame(() => {
      // Find the checkbox position (the '[' in '- [x]')
      const checkboxPos = newSource.indexOf("[", start);
      if (checkboxPos !== -1) {
        setCursorPosition(checkboxPos);
        if (editorMode() === "highlight" && editorRef) {
          editorRef.setCursorPosition(checkboxPos);
          editorRef.focus();
        } else if (simpleEditorRef) {
          simpleEditorRef.setSelectionRange(checkboxPos, checkboxPos);
          simpleEditorRef.focus();
        }
      }
    });
  };

  // Callbacks for interactive preview
  const rendererCallbacks: RendererCallbacks = {
    onTaskToggle: handleTaskToggle,
  };

  // Options for custom code block rendering
  const rendererOptions: RendererOptions = {
    codeBlockHandlers: {
      // Render ```svg or ```svg:preview blocks as inline SVG
      // Mode: "preview" (default) = inline preview, "code" = syntax highlighted
      svg: {
        render: (code, span, key, mode) => {
          // If mode is "code", fall through to default syntax highlighting
          if (mode === "code") {
            return null;
          }
          // Default: render as inline SVG (sanitized for safety)
          return <RawHtml key={key} data-span={span} html={sanitizeSvg(code)} />;
        },
      },
    },
  };

  // Render preview when AST changes
  createEffect(() => {
    const currentAst = ast();
    if (!currentAst || !previewRef) return;

    // Clear and re-render
    previewRef.innerHTML = "";
    render(previewRef, <MarkdownRenderer ast={currentAst} callbacks={rendererCallbacks} options={rendererOptions} />);
    lastRenderedAst = currentAst;
  });

  // Sync preview scroll with cursor position (debounced to avoid excessive scrolling)
  let scrollTimer: number | undefined;
  createEffect(() => {
    const pos = cursorPosition();
    const currentAst = ast();
    if (!previewRef || !currentAst) return;

    // Debounce scroll updates to avoid jittery scrolling during fast typing
    clearTimeout(scrollTimer);
    scrollTimer = window.setTimeout(() => {
      // Use requestAnimationFrame to ensure DOM is ready after render
      requestAnimationFrame(() => {
        if (!previewRef || !lastRenderedAst) return;

        const blockIndex = findBlockAtPosition(lastRenderedAst, pos);
        if (blockIndex === null) return;

        const block = lastRenderedAst.children[blockIndex]!;
        const start = block.position?.start?.offset ?? 0;
        const end = block.position?.end?.offset ?? 0;
        const selector = `[data-span="${start}-${end}"]`;
        const element = previewRef.querySelector(selector);

        if (element) {
          element.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      });
    }, 150); // Small delay to let render complete first
  });


  // Debounced AST parsing - separate from source updates for better input responsiveness
  let astParseTimer: number | undefined;
  const AST_PARSE_DELAY = 100; // ms - delay AST parsing to not block input

  const handleChange = (newSource: string) => {
    hasModified = true;
    // Update source immediately for responsive input
    setSource(newSource);

    // Debounce AST parsing - preview doesn't need to update on every keystroke
    clearTimeout(astParseTimer);
    astParseTimer = window.setTimeout(() => {
      setAst(parse(newSource));
    }, AST_PARSE_DELAY);
  };

  // Debounce cursor position saving
  let cursorSaveTimer: number | undefined;
  const handleCursorChange = (position: number) => {
    setCursorPosition(position);
    // Debounce localStorage write - don't need to save every keystroke
    clearTimeout(cursorSaveTimer);
    cursorSaveTimer = window.setTimeout(() => {
      saveUIState({ cursorPosition: position });
    }, 500);
  };

  return (
    <Show when={isInitialized}>
      {() => (
        <div class="app-container">
          <header class="toolbar">
            <div class="toolbar-left">
              <div class="view-mode-buttons">
                {!mobile && (
                  <button
                    class={splitBtnClass}
                    onClick={() => handleViewModeChange("split")}
                    title="Split view (Ctrl+1)"
                  >
                    <Icon svg={SPLIT_ICON} />
                  </button>
                )}
                <button
                  class={editorBtnClass}
                  onClick={() => handleViewModeChange("editor")}
                  title="Editor only (Ctrl+2)"
                >
                  <Icon svg={EDITOR_ICON} />
                </button>
                <button
                  class={previewBtnClass}
                  onClick={() => handleViewModeChange("preview")}
                  title="Preview only (Ctrl+3)"
                >
                  <Icon svg={PREVIEW_ICON} />
                </button>
              </div>
              <div class="editor-mode-buttons">
                <button
                  class={highlightBtnClass}
                  onClick={() => handleEditorModeChange("highlight")}
                  title="Syntax highlight editor"
                >
                  <Icon svg={HIGHLIGHT_ICON} />
                </button>
                <button
                  class={simpleBtnClass}
                  onClick={() => handleEditorModeChange("simple")}
                  title="Simple text editor"
                >
                  <Icon svg={SIMPLE_ICON} />
                </button>
              </div>
              <span class={saveStatusClass}>
                {saveStatus() === "saving" && "Saving..."}
                {saveStatus() === "saved" && "Saved"}
              </span>
            </div>
            <div class="toolbar-actions">
              <button onClick={toggleDark} class="theme-toggle" title="Toggle dark mode">
                {isDark() ? "☀️" : "🌙"}
              </button>
              <a
                href="https://github.com/mizchi/markdown.mbt"
                target="_blank"
                rel="noopener noreferrer"
                class="github-link"
                title="View on GitHub"
              >
                <Icon svg={GITHUB_ICON} />
              </a>
            </div>
          </header>
          <div class={containerClass}>
            {/* Editor panel - visibility controlled by CSS class */}
            <div class="editor">
              {/* Syntax highlight editor - always mounted, visibility controlled by CSS */}
              <div class="editor-highlight-wrapper">
                <SyntaxHighlightEditor
                  ref={(el) => { editorRef = el; }}
                  value={() => source()}
                  onChange={handleChange}
                  onCursorChange={handleCursorChange}
                  initialCursorPosition={initialUIState.cursorPosition}
                />
              </div>
              {/* Simple editor - always mounted, visibility controlled by CSS */}
              <div class="editor-simple-wrapper">
                <SimpleEditor
                  value={() => source()}
                  onChange={handleChange}
                  onCursorChange={handleCursorChange}
                  ref={(el) => { simpleEditorRef = el; }}
                />
              </div>
            </div>
            {/* Preview panel - visibility controlled by CSS class, rendered via effect */}
            <div
              class="preview"
              ref={(el) => { previewRef = el; }}
            />
          </div>
        </div>
      )}
    </Show>
  );
}

render(document.getElementById("app")!, <App />);
