import { render } from "preact";
import { useState, useCallback, useEffect, useRef } from "preact/hooks";
import { parse } from "../js/api.js";
import type { Document } from "../js/api";
import { MarkdownRenderer } from "./ast-renderer";

const STORAGE_KEY = "markdown-editor-content";
const IDB_NAME = "markdown-editor";
const IDB_STORE = "documents";
const IDB_KEY = "current";
const DEBOUNCE_DELAY = 1000;

const initialMarkdown = `# Hello

This is a **bold** and *italic* text.

## Features

- Bullet point 1
- Bullet point 2
- Bullet point 3

### Task List

- [ ] Todo item
- [x] Completed item

### Code Block

\`\`\`javascript
const x = 1;
console.log(x);
\`\`\`

> Blockquote example

| Name | Age |
|------|-----|
| Alice | 30 |
| Bob | 25 |

Visit [example](https://example.com) for more.
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

async function saveToIDB(content: string): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    const store = tx.objectStore(IDB_STORE);
    const request = store.put({ content, timestamp: Date.now() }, IDB_KEY);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
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

// Debounce hook
function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

// Dark mode hook
function useDarkMode(): [boolean, () => void] {
  const [isDark, setIsDark] = useState(() => {
    const saved = localStorage.getItem("theme");
    if (saved) return saved === "dark";
    return window.matchMedia("(prefers-color-scheme: dark)").matches;
  });

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", isDark ? "dark" : "light");
    localStorage.setItem("theme", isDark ? "dark" : "light");
  }, [isDark]);

  const toggle = useCallback(() => setIsDark((v) => !v), []);

  return [isDark, toggle];
}


// Find block element at cursor position
function findBlockAtPosition(ast: Document, position: number): number | null {
  for (let i = 0; i < ast.children.length; i++) {
    const block = ast.children[i]!;
    if (position >= block.span.from && position <= block.span.to) {
      return i;
    }
  }
  // If position is beyond all blocks, return the last block
  const lastBlock = ast.children[ast.children.length - 1];
  if (ast.children.length > 0 && lastBlock && position >= lastBlock.span.to) {
    return ast.children.length - 1;
  }
  return null;
}

function App() {
  const [source, setSource] = useState(initialMarkdown);
  const [ast, setAst] = useState<Document>(() => parse(initialMarkdown));
  const [cursorPosition, setCursorPosition] = useState(0);
  const [isInitialized, setIsInitialized] = useState(false);
  const [isDark, toggleDark] = useDarkMode();
  const [saveStatus, setSaveStatus] = useState<"saved" | "saving" | "idle">("idle");

  const previewRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<HTMLTextAreaElement>(null);
  const debouncedSource = useDebounce(source, DEBOUNCE_DELAY);

  // Load initial content from localStorage or IndexedDB
  useEffect(() => {
    async function loadInitialContent() {
      // First, try localStorage for quick load
      const localContent = localStorage.getItem(STORAGE_KEY);

      // Then check IndexedDB for potentially newer content
      const idbData = await loadFromIDB();

      if (idbData && idbData.content) {
        // Compare timestamps if both exist
        const localTimestamp = parseInt(localStorage.getItem(`${STORAGE_KEY}-timestamp`) || "0", 10);
        if (idbData.timestamp >= localTimestamp) {
          setSource(idbData.content);
          setAst(parse(idbData.content));
        } else if (localContent) {
          setSource(localContent);
          setAst(parse(localContent));
        }
      } else if (localContent) {
        setSource(localContent);
        setAst(parse(localContent));
      }

      setIsInitialized(true);
    }

    loadInitialContent();
  }, []);

  // Handle visibility change for tab sync
  useEffect(() => {
    async function handleVisibilityChange() {
      if (document.visibilityState === "visible") {
        const idbData = await loadFromIDB();
        if (idbData) {
          const currentTimestamp = parseInt(localStorage.getItem(`${STORAGE_KEY}-timestamp`) || "0", 10);
          // If IDB has newer content, update
          if (idbData.timestamp > currentTimestamp) {
            setSource(idbData.content);
            setAst(parse(idbData.content));
            localStorage.setItem(STORAGE_KEY, idbData.content);
            localStorage.setItem(`${STORAGE_KEY}-timestamp`, idbData.timestamp.toString());
          }
        }
      }
    }

    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => document.removeEventListener("visibilitychange", handleVisibilityChange);
  }, []);

  // Save to localStorage with debounce
  useEffect(() => {
    if (!isInitialized) return;

    setSaveStatus("saving");
    const timestamp = Date.now();
    localStorage.setItem(STORAGE_KEY, debouncedSource);
    localStorage.setItem(`${STORAGE_KEY}-timestamp`, timestamp.toString());

    // Also save to IndexedDB
    saveToIDB(debouncedSource).then(() => {
      setSaveStatus("saved");
      setTimeout(() => setSaveStatus("idle"), 1000);
    });
  }, [debouncedSource, isInitialized]);

  // Sync preview scroll with cursor position
  useEffect(() => {
    if (!previewRef.current) return;

    const blockIndex = findBlockAtPosition(ast, cursorPosition);
    if (blockIndex === null) return;

    const block = ast.children[blockIndex]!;
    const selector = `[data-span="${block.span.from}-${block.span.to}"]`;
    const element = previewRef.current.querySelector(selector);

    if (element) {
      element.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }, [cursorPosition, ast]);

  const handleInput = useCallback((e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    const newSource = target.value;
    setSource(newSource);
    setAst(parse(newSource));
    setCursorPosition(target.selectionStart);
  }, []);

  const handleSelect = useCallback((e: Event) => {
    const target = e.target as HTMLTextAreaElement;
    setCursorPosition(target.selectionStart);
  }, []);

  const handleKeyUp = useCallback((e: KeyboardEvent) => {
    const target = e.target as HTMLTextAreaElement;
    setCursorPosition(target.selectionStart);
  }, []);

  const handleClick = useCallback((e: MouseEvent) => {
    const target = e.target as HTMLTextAreaElement;
    setCursorPosition(target.selectionStart);
  }, []);

  return (
    <div class="app-container">
      <header class="toolbar">
        <h1>Markdown.mbt Playground</h1>
        <div class="toolbar-actions">
          <span class={`save-status ${saveStatus}`}>
            {saveStatus === "saving" && "Saving..."}
            {saveStatus === "saved" && "✓ Saved"}
          </span>
          <button onClick={toggleDark} class="theme-toggle" title="Toggle dark mode">
            {isDark ? "☀️" : "🌙"}
          </button>
        </div>
      </header>
      <div class="container">
        <div class="editor">
          <textarea
            ref={editorRef}
            value={source}
            onInput={handleInput}
            onSelect={handleSelect}
            onKeyUp={handleKeyUp}
            onClick={handleClick}
          />
        </div>
        <div class="preview" ref={previewRef}>
          <MarkdownRenderer ast={ast} />
        </div>
      </div>
    </div>
  );
}

render(<App />, document.getElementById("app")!);
