import { render, createSignal, createEffect, onMount, onCleanup, Show, batch } from "@luna_ui/luna";
import { parse } from "../js/api.js";
import type { Root } from "mdast";
import { MarkdownRenderer } from "./ast-renderer";
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
- Lists and task lists

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

// UI State helpers (localStorage for sync access)
interface UIState {
  viewMode: "split" | "editor" | "preview";
  editorMode: "highlight" | "simple";
  cursorPosition: number;
}

function loadUIState(): UIState {
  try {
    const saved = localStorage.getItem(UI_STATE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved);
      return {
        viewMode: parsed.viewMode || "split",
        editorMode: parsed.editorMode || "highlight",
        cursorPosition: parsed.cursorPosition || 0,
      };
    }
  } catch {
    // ignore parse errors
  }
  return { viewMode: "split", editorMode: "highlight", cursorPosition: 0 };
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

  return (
    <textarea
      ref={setupTextarea}
      class="simple-editor"
      onInput={(e) => props.onChange((e.target as HTMLTextAreaElement).value)}
      spellcheck={false}
    />
  );
}

// SVG Icons for view modes
const SplitIcon = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
    <rect x="1" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none" />
    <rect x="11" y="2" width="8" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none" />
  </svg>
);

const EditorIcon = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
    <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none" />
    <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1.5" />
    <line x1="5" y1="10" x2="12" y2="10" stroke="currentColor" stroke-width="1.5" />
    <line x1="5" y1="14" x2="14" y2="14" stroke="currentColor" stroke-width="1.5" />
  </svg>
);

const PreviewIcon = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
    <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none" />
    <circle cx="10" cy="10" r="3" stroke="currentColor" stroke-width="1.5" fill="none" />
    <path d="M4 10 Q7 5, 10 5 Q13 5, 16 10 Q13 15, 10 15 Q7 15, 4 10" stroke="currentColor" stroke-width="1.5" fill="none" />
  </svg>
);

// Syntax highlight editor icon (colorful brackets)
const HighlightIcon = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" fill="none">
    <text x="2" y="14" font-size="12" fill="#d73a49" font-family="monospace" font-weight="bold">&lt;</text>
    <text x="8" y="14" font-size="12" fill="#22863a" font-family="monospace">/</text>
    <text x="12" y="14" font-size="12" fill="#0366d6" font-family="monospace" font-weight="bold">&gt;</text>
  </svg>
);

// Simple textarea icon (plain text)
const SimpleIcon = () => (
  <svg viewBox="0 0 20 20" width="18" height="18" fill="currentColor">
    <rect x="2" y="2" width="16" height="16" rx="1" stroke="currentColor" stroke-width="1.5" fill="none" />
    <line x1="5" y1="6" x2="15" y2="6" stroke="currentColor" stroke-width="1" opacity="0.5" />
    <line x1="5" y1="9" x2="13" y2="9" stroke="currentColor" stroke-width="1" opacity="0.5" />
    <line x1="5" y1="12" x2="14" y2="12" stroke="currentColor" stroke-width="1" opacity="0.5" />
    <line x1="5" y1="15" x2="10" y2="15" stroke="currentColor" stroke-width="1" opacity="0.5" />
  </svg>
);



function App() {
  // Load UI state synchronously for initial render
  const initialUIState = loadUIState();

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
    setEditorMode(mode);
    saveUIState({ editorMode: mode });
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
    // Initial AST - parsed immediately (debounce effect will also fire but that's ok)
    setAst(parse(content));
    lastSyncedTimestamp = timestamp;
    setIsInitialized(true);

    // Focus editor after initialization
    requestAnimationFrame(() => {
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

  // Render preview when AST changes
  createEffect(() => {
    const currentAst = ast();
    if (!currentAst || !previewRef) return;
    previewRef.innerHTML = "";
    render(previewRef, <MarkdownRenderer ast={currentAst} />);
  });

  // Sync preview scroll with cursor position
  createEffect(() => {
    const pos = cursorPosition();
    const currentAst = ast();
    if (!previewRef || !currentAst) return;

    const blockIndex = findBlockAtPosition(currentAst, pos);
    if (blockIndex === null) return;

    const block = currentAst.children[blockIndex]!;
    const start = block.position?.start?.offset ?? 0;
    const end = block.position?.end?.offset ?? 0;
    const selector = `[data-span="${start}-${end}"]`;
    const element = previewRef.querySelector(selector);

    if (element) {
      element.scrollIntoView({ behavior: "smooth", block: "center" });
    }
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
                <button
                  class={`view-mode-btn ${viewMode() === "split" ? "active" : ""}`}
                  onClick={() => handleViewModeChange("split")}
                  title="Split view (Ctrl+1)"
                >
                  <SplitIcon />
                </button>
                <button
                  class={`view-mode-btn ${viewMode() === "editor" ? "active" : ""}`}
                  onClick={() => handleViewModeChange("editor")}
                  title="Editor only (Ctrl+2)"
                >
                  <EditorIcon />
                </button>
                <button
                  class={`view-mode-btn ${viewMode() === "preview" ? "active" : ""}`}
                  onClick={() => handleViewModeChange("preview")}
                  title="Preview only (Ctrl+3)"
                >
                  <PreviewIcon />
                </button>
              </div>
              <div class="editor-mode-buttons">
                <button
                  class={`view-mode-btn ${editorMode() === "highlight" ? "active" : ""}`}
                  onClick={() => handleEditorModeChange("highlight")}
                  title="Syntax highlight editor"
                >
                  <HighlightIcon />
                </button>
                <button
                  class={`view-mode-btn ${editorMode() === "simple" ? "active" : ""}`}
                  onClick={() => handleEditorModeChange("simple")}
                  title="Simple text editor"
                >
                  <SimpleIcon />
                </button>
              </div>
              <span class={`save-status ${saveStatus()}`}>
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
                <svg viewBox="0 0 16 16" width="20" height="20" fill="currentColor">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
                </svg>
              </a>
            </div>
          </header>
          <div class={`container view-${viewMode()}`}>
            {/* Editor panel - use CSS visibility instead of Show to prevent re-creation */}
            <div class="editor" style={{ display: viewMode() === "preview" ? "none" : undefined }}>
              {/* Syntax highlight editor - always mounted, visibility controlled by CSS */}
              <div style={{ display: editorMode() === "highlight" ? "contents" : "none" }}>
                <SyntaxHighlightEditor
                  ref={(el) => { editorRef = el; }}
                  value={source}
                  onChange={handleChange}
                  onCursorChange={handleCursorChange}
                  initialCursorPosition={initialUIState.cursorPosition}
                />
              </div>
              {/* Simple editor - always mounted, visibility controlled by CSS */}
              <div style={{ display: editorMode() === "simple" ? "contents" : "none" }}>
                <SimpleEditor
                  value={source}
                  onChange={handleChange}
                  ref={(el) => { simpleEditorRef = el; }}
                />
              </div>
            </div>
            {/* Preview panel - use CSS visibility instead of Show */}
            <div
              class="preview"
              style={{ display: viewMode() === "editor" ? "none" : undefined }}
              ref={(el) => { previewRef = el; }}
            />
          </div>
        </div>
      )}
    </Show>
  );
}

render(document.getElementById("app")!, <App />);
