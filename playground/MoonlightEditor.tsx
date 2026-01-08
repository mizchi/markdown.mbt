///| Moonlight SVG Editor wrapper component
///| Provides bidirectional editing of SVG in markdown code blocks

import { createSignal, onMount, onCleanup } from "@luna_ui/luna";
import { sanitizeSvg } from "./ast-renderer";

// Type for the moonlight-editor custom element
interface MoonlightEditorElement extends HTMLElement {
  importSvg(svg: string): void;
  exportSvg(): string;
  onChange(callback: () => void): () => void;
  startEditing(): void;
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

/**
 * MoonlightEditor component for SVG editing
 * Uses moonlight-editor Web Component
 * Falls back to static preview if moonlight is not loaded
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

  let editorElement: MoonlightEditorElement | null = null;
  const [isLoaded, setIsLoaded] = createSignal(false);

  // Initialize moonlight editor after custom element is defined
  const initEditor = () => {
    if (!editorElement) return false;

    // Check if custom element is defined
    if (!customElements.get("moonlight-editor")) return false;

    try {
      // Import initial SVG
      editorElement.importSvg(sanitizeSvg(initialSvg));

      // Start editing mode
      editorElement.startEditing();

      // Subscribe to changes
      if (!readonly && onSvgChange) {
        editorElement.onChange(() => {
          const svg = editorElement!.exportSvg();
          onSvgChange(svg, span);
        });
      }

      setIsLoaded(true);
      return true;
    } catch (e) {
      console.error("Failed to initialize MoonlightEditor:", e);
      return false;
    }
  };

  // Try to initialize moonlight editor
  onMount(() => {
    if (!editorElement) return;

    // Try immediate init if already loaded
    if (initEditor()) return;

    // Load script and retry
    loadMoonlight().then((loaded) => {
      if (loaded) {
        // Wait for custom element to be defined
        customElements.whenDefined("moonlight-editor").then(() => {
          initEditor();
        });
      }
    });
  });

  // Cleanup - Web Components clean up automatically when removed from DOM
  onCleanup(() => {
    editorElement = null;
  });

  // Fallback: static SVG preview
  const renderFallback = () => (
    <div
      class="moonlight-fallback"
      data-span={span}
      style={{
        width: `${width}px`,
        height: `${height}px`,
        border: "1px solid #e1e4e8",
        borderRadius: "6px",
        overflow: "hidden",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "#f6f8fa",
      }}
      ref={(el) => {
        if (el) el.innerHTML = sanitizeSvg(initialSvg);
      }}
    />
  );

  return (
    <div class="moonlight-editor-wrapper" data-span={span}>
      {/* @ts-ignore - moonlight-editor is a custom element */}
      <moonlight-editor
        ref={(el: MoonlightEditorElement) => {
          editorElement = el;
        }}
        width={width}
        height={height}
        style={{
          display: isLoaded() ? "block" : "none",
        }}
      />
      {!isLoaded() && renderFallback()}
    </div>
  );
}

// Moonlight CDN URL
const MOONLIGHT_CDN_URL = "https://moonlight.mizchi.workers.dev/moonlight-editor.component.js";

// Track loading state
let loadingPromise: Promise<boolean> | null = null;

/**
 * Load moonlight editor script dynamically
 * Call this to enable full editing capabilities
 */
export async function loadMoonlight(): Promise<boolean> {
  // Check if custom element is already defined
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
      console.log("Moonlight editor loaded successfully");
      resolve(true);
    };
    script.onerror = () => {
      console.error("Failed to load Moonlight editor from CDN");
      resolve(false);
    };
    document.head.appendChild(script);
  });

  return loadingPromise;
}
