import { render, createSignal, createEffect, createMemo, onMount, onCleanup, Show, For, batch } from "@luna_ui/luna";
import { createDocument, diffEdit } from "../js/api.js";
import type { DocumentHandle } from "../js/api";
import type { Root } from "mdast";
import type { RendererCallbacks } from "./ast-renderer";
import { SyntaxHighlightEditor, type SyntaxHighlightEditorHandle } from "../frontend/editor/SyntaxHighlightEditor";
import { PreviewPane } from "./PreviewPane";
import { ResizeHandle } from "./ResizeHandle";

import { listDocuments, saveDocument, deleteDocument, compareDocuments, type SavedDocument } from "./document-store";

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

## Moonlight SVG Editor

Interactive SVG editing with [Moonlight](https://github.com/mizchi/moonlight):

\`\`\`moonlight-svg
<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
  <rect x="50" y="50" width="120" height="80" fill="#3498db" rx="10"/>
  <circle cx="280" cy="90" r="50" fill="#e74c3c"/>
  <polygon points="200,200 150,280 250,280" fill="#2ecc71"/>
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

// Mobile detection
function isMobile(): boolean {
  return window.innerWidth < 768 || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
}

// UI State helpers (localStorage for sync access)
interface UIState {
  viewMode: "split" | "editor" | "preview";
  editorMode: "highlight" | "simple";
  cursorPosition: number;
  sidebarOpen: boolean;
  activeDocumentId: string;
  sidebarWidth: number;
  previewRatio: number;
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
        sidebarOpen: parsed.sidebarOpen ?? !mobile,
        activeDocumentId: parsed.activeDocumentId ?? "current",
        sidebarWidth: Number.isFinite(parsed.sidebarWidth) ? Math.max(160, Math.min(window.innerWidth * 0.45, parsed.sidebarWidth)) : 240,
        previewRatio: Number.isFinite(parsed.previewRatio) ? Math.max(0.15, Math.min(0.85, parsed.previewRatio)) : 0.5,
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
    sidebarOpen: !mobile,
    activeDocumentId: "current",
    sidebarWidth: 240,
    previewRatio: 0.5,
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
      ref={(el) => setupTextarea(el as HTMLTextAreaElement)}
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

const DELETE_ICON = `<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M3 5h14M7 5V2h6v3M5 5l1 13h8l1-13M8 8v7M12 8v7"/></svg>`;

const NEW_DOCUMENT_ICON = `<svg viewBox="0 0 20 20" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
  <path d="M11 2H4a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8l-6-6Z"/>
  <path d="M11 2v6h6M7 12h6M10 9v6"/>
</svg>`;

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
  const [saveStatus, setSaveStatus] = createSignal<"saved" | "saving" | "idle" | "error">("idle");
  const [viewMode, setViewMode] = createSignal<ViewMode>(initialUIState.viewMode);
  const [editorMode, setEditorMode] = createSignal<EditorMode>(initialUIState.editorMode);
  const [sidebarOpen, setSidebarOpen] = createSignal(initialUIState.sidebarOpen);
  const [documents, setDocuments] = createSignal<SavedDocument[]>([]);
  const [documentId, setDocumentId] = createSignal(initialUIState.activeDocumentId);
  const [switching, setSwitching] = createSignal(false);
  const [sidebarWidth, setSidebarWidth] = createSignal(initialUIState.sidebarWidth);
  const [previewRatio, setPreviewRatio] = createSignal(initialUIState.previewRatio);
  const [pendingDelete, setPendingDelete] = createSignal<SavedDocument | null>(null);
  const [deleteError, setDeleteError] = createSignal("");
  let deleteDialog: HTMLDialogElement | null = null;
  const savePanelWidths = () => saveUIState({ sidebarWidth: sidebarWidth(), previewRatio: previewRatio() });
  const toggleSidebar = () => {
    setSidebarOpen(!sidebarOpen());
    saveUIState({ sidebarOpen: sidebarOpen() });
  };


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
  let editorPanelRef: HTMLDivElement | null = null;
  createEffect(() => {
    const disabled = switching();
    if (editorPanelRef) editorPanelRef.inert = disabled;
  });

  // Incremental parsing state. The playground used to run a full parse on every
  // edit; instead we keep the parsed document alive and advance it with the
  // edit that actually happened, which is what parse_incremental is for.
  let docHandle: DocumentHandle | null = null;
  let lastParsedSource = "";

  /**
   * Bring the AST up to date with `nextSource`.
   *
   * Diffs against the source the document was last parsed from - not the
   * previous keystroke - so a debounced run of edits collapses into one range,
   * and a source change that skipped the AST (the SVG editor does that) is
   * still covered by the next refresh.
   */
  const refreshAst = (nextSource: string) => {
    if (docHandle) {
      const edit = diffEdit(lastParsedSource, nextSource);
      if (edit === null) return; // nothing changed
      try {
        const updated = docHandle.update(nextSource, edit);
        docHandle.dispose();
        docHandle = updated;
        lastParsedSource = nextSource;
        setAst(docHandle.ast);
        return;
      } catch {
        // Incremental parse refused this edit; fall back to a full parse.
        docHandle.dispose();
        docHandle = null;
      }
    }
    docHandle = createDocument(nextSource);
    lastParsedSource = nextSource;
    setAst(docHandle.ast);
  };

  onCleanup(() => {
    docHandle?.dispose();
    docHandle = null;
  });

  let activeCreatedAt = Date.now();
  let hasModified = false;
  let debounceTimer: number | undefined;
  let saveQueue: Promise<void> = Promise.resolve();
  const snapshot = (): SavedDocument => ({
    id: documentId(), content: source(), timestamp: Date.now(), createdAt: activeCreatedAt,
  });
  const persist = (doc: SavedDocument) => {
    setSaveStatus("saving");
    const operation = saveQueue.then(() => saveDocument(doc));
    saveQueue = operation.catch(() => {});
    return operation.then(() => {
      setDocuments(items => [doc, ...items.filter(item => item.id !== doc.id)].sort(compareDocuments));
      if (documentId() === doc.id && source() === doc.content) {
        hasModified = false;
        setSaveStatus("saved");
      }
    }).catch((error) => {
      setSaveStatus("error");
      throw error;
    });
  };
  const flushSave = () => {
    clearTimeout(debounceTimer);
    return persist(snapshot());
  };
  const activate = (doc: SavedDocument) => {
    activeCreatedAt = doc.createdAt;
    clearTimeout(astParseTimer);
    clearTimeout(debounceTimer);
    batch(() => {
      setDocumentId(doc.id);
      setSource(doc.content);
      refreshAst(doc.content);
      setCursorPosition(0);
    });
    hasModified = false;
    saveUIState({ activeDocumentId: doc.id, cursorPosition: 0 });
    editorRef?.setValue(doc.content);
    editorRef?.setCursorPosition(0);
    editorRef?.setScrollTop(0);
    if (simpleEditorRef) simpleEditorRef.scrollTop = 0;
  };
  const focusDocumentStart = () => {
    setCursorPosition(0);
    saveUIState({ cursorPosition: 0 });
    if (viewMode() === "preview") handleViewModeChange("split");
    requestAnimationFrame(() => {
      if (editorMode() === "highlight") {
        editorRef?.focus();
        editorRef?.setCursorPosition(0);
        editorRef?.setScrollTop(0);
      } else if (simpleEditorRef) {
        simpleEditorRef.focus();
        simpleEditorRef.setSelectionRange(0, 0);
        simpleEditorRef.scrollTop = 0;
      }
      if (previewRef) previewRef.scrollTop = 0;
    });
  };
  const selectDocument = async (doc?: SavedDocument) => {
    if (switching()) return;
    if (doc?.id === documentId()) { focusDocumentStart(); return; }
    setSwitching(true);
    try {
      await flushSave();
      const next = doc ?? { id: crypto.randomUUID(), content: "", timestamp: Date.now(), createdAt: Date.now() };
      if (!doc) await persist(next);
      activate(next);
      focusDocumentStart();
    } catch {
      // Keep the current editor intact if its save failed.
    } finally {
      setSwitching(false);
    }
  };
  const askDelete = (doc: SavedDocument) => {
    if (switching()) return;
    setPendingDelete(doc);
    setDeleteError("");
    deleteDialog?.showModal();
  };
  const confirmDelete = async () => {
    const target = pendingDelete();
    if (!target || switching()) return;
    setSwitching(true);
    clearTimeout(debounceTimer);
    try {
      if (target.id !== documentId() && hasModified) await flushSave();
      await saveQueue;
      const remaining = documents().filter(doc => doc.id !== target.id);
      const replacement = remaining.length ? undefined : {
        id: crypto.randomUUID(), content: "", timestamp: Date.now(), createdAt: Date.now(),
      };
      await deleteDocument(target.id, replacement);
      const nextDocuments = replacement ? [replacement] : remaining;
      setDocuments(nextDocuments);
      if (target.id === documentId()) activate(nextDocuments[0]!);
      deleteDialog?.close();
      setPendingDelete(null);
      focusDocumentStart();
    } catch {
      setDeleteError("Could not delete the document. Please retry.");
    } finally {
      setSwitching(false);
    }
  };
  createEffect(() => {
    const doc = snapshot();
    const ready = isInitialized();
    clearTimeout(debounceTimer);
    if (!ready || !hasModified) return;
    debounceTimer = window.setTimeout(() => { void persist(doc).catch(() => {}); }, DEBOUNCE_DELAY);
  });
  onCleanup(() => { clearTimeout(debounceTimer); });

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
      if (!e.ctrlKey || e.metaKey || e.altKey || e.shiftKey || e.isComposing || e.repeat) return;
      if (e.key.toLowerCase() === "b") {
        e.preventDefault();
        toggleSidebar();
      } else if (e.code === "Backquote" || e.key === "`") {
        e.preventDefault();
        handleViewModeChange(viewMode() === "editor" ? "split" : "editor");
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    onCleanup(() => { window.removeEventListener("keydown", handleKeyDown); });
  });

  onMount(() => {
    void (async () => {
      try {
        let items = await listDocuments();
        if (!items.length) {
          const doc = { id: "current", content: initialMarkdown, timestamp: Date.now(), createdAt: Date.now() };
          await saveDocument(doc);
          items = [doc];
        }
        setDocuments(items);
        activate(items.find(doc => doc.id === initialUIState.activeDocumentId) ?? items[0]!);
      } catch {
        setSource(initialMarkdown);
        refreshAst(initialMarkdown);
        setSaveStatus("error");
      }
      setIsInitialized(true);
      requestAnimationFrame(() => editorRef?.focus());
    })();
    const sync = async () => {
      if (document.visibilityState !== "visible") {
        if (hasModified) void flushSave().catch(() => {});
        return;
      }
      if (hasModified || switching()) return;
      const id = documentId();
      try {
        await saveQueue;
        const items = await listDocuments();
        if (hasModified || switching() || id !== documentId()) return;
        setDocuments(items);
        const doc = items.find(item => item.id === id);
        if (doc && doc.content !== source()) activate(doc);
      } catch { setSaveStatus("error"); }
    };
    document.addEventListener("visibilitychange", sync);
    onCleanup(() => { document.removeEventListener("visibilitychange", sync); });
  });

  // Track last rendered AST version for scroll synchronization
  let lastRenderedAst: Root | null = null;

  // Handle task checkbox toggle from preview
  const handleTaskToggle = (span: string, checked: boolean) => {
    const [startStr = "0", endStr = "0"] = span.split("-");
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
    refreshAst(newSource);

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

  // Handle SVG change from Moonlight editor
  // Note: We only update the source text, NOT the AST, to avoid re-rendering
  // the preview and losing focus on the MoonlightEditor
  const handleSvgChange = (newSvg: string, span: string) => {
    const [startStr = "0", endStr = "0"] = span.split("-");
    const start = parseInt(startStr, 10);
    const end = parseInt(endStr, 10);

    const currentSource = source();

    // Find the code block content boundaries (skip ```moonlight-svg\n and \n```)
    // The span includes the entire code block, we need to find the actual content
    const blockText = currentSource.slice(start, end);
    const contentStart = blockText.indexOf("\n") + 1;
    const contentEnd = blockText.lastIndexOf("\n```");

    if (contentStart > 0 && contentEnd > contentStart) {
      const prefix = currentSource.slice(0, start + contentStart);
      const suffix = currentSource.slice(start + contentEnd);
      const newSource = prefix + newSvg + suffix;

      // Update source only (skip AST re-parse to prevent re-render and focus loss)
      hasModified = true;
      setSource(newSource);
      // Don't call setAst() here - AST will be updated on next text editor change

      // Sync editor text
      if (editorMode() === "highlight" && editorRef) {
        editorRef.setValue(newSource);
      } else if (simpleEditorRef) {
        simpleEditorRef.value = newSource;
      }
    }
  };

  // Callbacks for interactive preview
  const rendererCallbacks: RendererCallbacks = {
    onTaskToggle: handleTaskToggle,
  };

  // Track last rendered AST for scroll syncing
  createEffect(() => {
    const currentAst = ast();
    if (currentAst) {
      lastRenderedAst = currentAst;
    }
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
      refreshAst(newSource);
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
              <button type="button" class="panel-toggle" title="Toggle sidebar (Ctrl+B)" aria-label="Toggle sidebar" aria-expanded={sidebarOpen} onClick={toggleSidebar}>☰</button>
              <button type="button" class="panel-toggle" title="Toggle preview (Ctrl+`)" aria-label="Toggle preview" onClick={() => handleViewModeChange(viewMode() === "editor" ? "split" : "editor")}>Preview</button>
              <div class="view-mode-buttons">
                {!mobile && (
                  <button
                    class={splitBtnClass}
                    onClick={() => handleViewModeChange("split")}
                    title="Split view"
                  >
                    <Icon svg={SPLIT_ICON} />
                  </button>
                )}
                <button
                  class={editorBtnClass}
                  onClick={() => handleViewModeChange("editor")}
                  title="Editor only"
                >
                  <Icon svg={EDITOR_ICON} />
                </button>
                <button
                  class={previewBtnClass}
                  onClick={() => handleViewModeChange("preview")}
                  title="Preview only"
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
              <span class={saveStatusClass} role="status" aria-live="polite">
                {() => ({ saving: "Saving...", saved: "Saved", error: "Save unavailable. Please retry.", idle: "" })[saveStatus()]}
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
          <div class={containerClass} style={() => ({ "--sidebar-width": `${sidebarWidth()}px`, "--preview-ratio": String(previewRatio()), "--editor-ratio": String(1 - previewRatio()) })}>
            <aside class={() => sidebarOpen() ? "document-sidebar" : "document-sidebar collapsed"} aria-label="Documents">
              <div class="document-actions">
                <button type="button" class="new-document" aria-label="New document" title="New document" disabled={switching} onClick={() => void selectDocument()}>
                  <Icon svg={NEW_DOCUMENT_ICON} />
                </button>
              </div>
              <nav aria-label="Saved documents">
                <For each={documents}>{doc => (
                  <div class="document-row">
                  <button type="button" class={() => `document-item${documentId() === doc.id ? " active" : ""}`} disabled={switching} aria-current={() => documentId() === doc.id ? "page" : "false"} onClick={() => void selectDocument(doc)}>
                    <span class="document-excerpt" title={doc.content.split(/\r?\n/, 1)[0] ?? ""}>{doc.content.split(/\r?\n/, 1)[0] || "Empty document"}</span>
                  </button>
                  <button type="button" class="delete-document" aria-label={`Delete ${doc.content.split(/\r?\n/, 1)[0] || "Empty document"}`} title="Delete document" disabled={switching} onClick={() => askDelete(doc)}><Icon svg={DELETE_ICON} /></button>
                  </div>
                )}</For>
              </nav>
            </aside>
            <ResizeHandle label="Resize sidebar" class="sidebar-resizer" value={sidebarWidth} min={() => 160} max={() => Math.floor(window.innerWidth * 0.45)}
              onDelta={delta => setSidebarWidth(Math.max(160, Math.min(window.innerWidth * 0.45, sidebarWidth() + delta)))} onCommit={savePanelWidths} />
            {/* Editor panel - visibility controlled by CSS class */}
            <div class="editor" ref={(el) => { editorPanelRef = el as HTMLDivElement; editorPanelRef.inert = switching(); }}>
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
            <ResizeHandle label="Resize preview" class="preview-resizer" value={() => Math.round(previewRatio() * 100)} min={() => 15} max={() => 85}
              onDelta={delta => {
                const width = (editorPanelRef?.getBoundingClientRect().width ?? 0) + (previewRef?.getBoundingClientRect().width ?? 0);
                if (width) setPreviewRatio(Math.max(0.15, Math.min(0.85, previewRatio() - delta / width)));
              }} onCommit={savePanelWidths} />
            {/* Preview panel */}
            <PreviewPane
              ast={ast}
              isDark={isDark}
              callbacks={rendererCallbacks}
              onSvgChange={handleSvgChange}
              containerRef={(el) => {
                previewRef = el;
              }}
            />
          </div>
          <dialog class="delete-dialog" ref={el => { deleteDialog = el as HTMLDialogElement; }} aria-labelledby="delete-heading" aria-describedby="delete-description"
            onCancel={(event: Event) => { if (switching()) event.preventDefault(); }}>
            <h2 id="delete-heading">Delete document?</h2>
            <p id="delete-description">This document will be permanently deleted.</p>
            <p class="delete-title">{() => pendingDelete()?.content.split(/\r?\n/, 1)[0] || "Empty document"}</p>
            <p role="alert">{deleteError}</p>
            <div class="dialog-actions">
              <button type="button" autofocus disabled={switching} onClick={() => deleteDialog?.close()}>Cancel</button>
              <button type="button" disabled={switching} onClick={() => void confirmDelete()}>Delete</button>
            </div>
          </dialog>
        </div>
      )}
    </Show>
  );
}

render(document.getElementById("app")!, <App />);
