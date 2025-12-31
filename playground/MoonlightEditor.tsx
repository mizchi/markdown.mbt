///| Moonlight SVG Editor wrapper component
///| Uses the WebComponent API for bidirectional editing of SVG in markdown code blocks

import { createSignal, onMount, onCleanup } from "@luna_ui/luna";
import { sanitizeSvg } from "./ast-renderer";

// Type for the MoonlightEditor WebComponent API
interface MoonlightEditorElement extends HTMLElement {
  importSvg(svg: string): void;
  exportSvg(): string;
  onChange(callback: () => void): () => void;
  clear(): void;
  hasFocus(): boolean;
  startEditing(): Promise<void>;
}

// Declare the custom element
declare global {
  interface HTMLElementTagNameMap {
    "moonlight-editor": MoonlightEditorElement;
  }
}

export interface MoonlightEditorProps {
  /** Initial SVG content */
  initialSvg: string;
  /** Data span for source mapping */
  span: string;
  /** Callback when SVG is changed */
  onSvgChange?: (svg: string, span: string) => void;
  /** Editor width */
  width?: number;
  /** Editor height */
  height?: number;
  /** Read-only mode (shows preview only) */
  readonly?: boolean;
}

// Moonlight CDN URL
const MOONLIGHT_CDN_URL = "https://moonlight.mizchi.workers.dev/moonlight-editor.component.js";

// Track loading state
let loadingPromise: Promise<boolean> | null = null;

/**
 * Load moonlight editor script dynamically
 */
async function loadMoonlight(): Promise<boolean> {
  // Check if already defined
  if (customElements.get("moonlight-editor")) {
    return true;
  }

  // Return existing promise if already loading
  if (loadingPromise) {
    return loadingPromise;
  }

  loadingPromise = new Promise((resolve) => {
    const script = document.createElement("script");
    script.src = MOONLIGHT_CDN_URL;
    script.async = true;
    script.onload = () => {
      // Wait for custom element to be defined
      customElements.whenDefined("moonlight-editor").then(() => {
        console.log("Moonlight editor loaded successfully");
        resolve(true);
      });
    };
    script.onerror = () => {
      console.error("Failed to load Moonlight editor from CDN");
      loadingPromise = null; // Reset so we can retry
      resolve(false);
    };
    document.head.appendChild(script);
  });

  return loadingPromise;
}

/**
 * MoonlightEditor component for SVG editing
 * Uses the WebComponent API with automatic initialization
 */
export function MoonlightEditor(props: MoonlightEditorProps) {
  const {
    initialSvg,
    span,
    onSvgChange,
    width = 400,
    height = 300,
    readonly = false,
  } = props;

  let containerRef: HTMLDivElement | null = null;
  let editorElement: MoonlightEditorElement | null = null;
  let unsubscribe: (() => void) | null = null;
  const [isLoaded, setIsLoaded] = createSignal(false);
  const [isError, setIsError] = createSignal(false);

  // Initialize moonlight editor
  const initEditor = async () => {
    if (!containerRef) return;

    try {
      // Load the WebComponent script
      const loaded = await loadMoonlight();
      if (!loaded) {
        setIsError(true);
        return;
      }

      // Create the moonlight-editor element
      editorElement = document.createElement("moonlight-editor") as MoonlightEditorElement;
      editorElement.setAttribute("width", String(width));
      editorElement.setAttribute("height", String(height));
      editorElement.setAttribute("theme", "light");
      if (readonly) {
        editorElement.setAttribute("readonly", "");
      }

      // Add initial SVG as a child template
      const sanitized = sanitizeSvg(initialSvg);
      const template = document.createElement("template");
      template.innerHTML = sanitized;
      editorElement.appendChild(template);

      // Clear container and add the element
      containerRef.innerHTML = "";
      containerRef.appendChild(editorElement);

      // Subscribe to changes before starting (will be queued)
      if (!readonly && onSvgChange) {
        unsubscribe = editorElement.onChange(() => {
          const svg = editorElement!.exportSvg();
          onSvgChange(svg, span);
        });
      }

      // Start the editor immediately (triggers hydration)
      await editorElement.startEditing();

      setIsLoaded(true);
    } catch (e) {
      console.error("Failed to initialize MoonlightEditor:", e);
      setIsError(true);
    }
  };

  // Try to initialize moonlight editor
  onMount(() => {
    initEditor();
  });

  // Cleanup
  onCleanup(() => {
    if (unsubscribe) {
      unsubscribe();
      unsubscribe = null;
    }
    if (editorElement) {
      editorElement.remove();
      editorElement = null;
    }
  });

  // Render loading/error state or editor container
  return (
    <div
      class="moonlight-editor-wrapper"
      data-span={span}
      style={{
        width: `${width}px`,
        minHeight: `${height}px`,
      }}
    >
      <div
        ref={(el) => {
          containerRef = el;
        }}
        style={{
          width: "100%",
          minHeight: `${height}px`,
        }}
      >
        {!isLoaded() && !isError() && (
          <div
            style={{
              width: `${width}px`,
              height: `${height}px`,
              border: "1px solid #e1e4e8",
              borderRadius: "6px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              backgroundColor: "#f6f8fa",
              color: "#586069",
              fontSize: "14px",
            }}
          >
            Loading Moonlight Editor...
          </div>
        )}
        {isError() && (
          <div
            style={{
              width: `${width}px`,
              height: `${height}px`,
              border: "1px solid #f97583",
              borderRadius: "6px",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              backgroundColor: "#ffeef0",
              color: "#d73a49",
              fontSize: "14px",
              gap: "8px",
            }}
          >
            <span>Failed to load Moonlight Editor</span>
            <button
              onClick={() => {
                setIsError(false);
                initEditor();
              }}
              style={{
                padding: "4px 12px",
                background: "#d73a49",
                color: "white",
                border: "none",
                borderRadius: "4px",
                cursor: "pointer",
              }}
            >
              Retry
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
