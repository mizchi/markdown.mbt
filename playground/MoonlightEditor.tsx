///| Moonlight SVG Editor wrapper component
///| Uses the ESM API for bidirectional editing of SVG in markdown code blocks

import { createSignal, onMount, onCleanup } from "@luna_ui/luna";
import { sanitizeSvg } from "./ast-renderer";

interface EditorHandle {
  exportSvg(): string;
  destroy(): void;
  onChange(callback: () => void): () => void;
}

interface EditorOptions {
  width: number;
  height: number;
  theme: "light" | "dark";
  readonly: boolean;
  initialSvg: string;
}

interface MoonlightEditorModule {
  createEditor(container: HTMLDivElement, options: EditorOptions): EditorHandle | null | undefined;
}

const MOONLIGHT_EDITOR_URL = "/moonlight-editor.editor.js";
let moonlightModulePromise: Promise<MoonlightEditorModule> | null = null;

declare global {
  interface Window {
    __moonlightEditorModule?: MoonlightEditorModule;
  }
}

function loadMoonlightEditorModule(): Promise<MoonlightEditorModule> {
  const existingModule = window.__moonlightEditorModule;
  if (existingModule) {
    return Promise.resolve(existingModule);
  }

  if (!moonlightModulePromise) {
    moonlightModulePromise = new Promise((resolve, reject) => {
      const resolveModule = () => {
        const module = window.__moonlightEditorModule;
        if (!module) {
          moonlightModulePromise = null;
          reject(new Error("Moonlight editor bundle loaded without module export"));
          return;
        }
        resolve(module);
      };

      const existingScript = document.querySelector(
        'script[data-moonlight-editor="true"]',
      ) as HTMLScriptElement | null;

      if (existingScript) {
        existingScript.addEventListener("load", resolveModule, { once: true });
        existingScript.addEventListener(
          "error",
          () => {
            moonlightModulePromise = null;
            reject(new Error("Failed to load Moonlight editor bundle"));
          },
          { once: true },
        );
        return;
      }

      const script = document.createElement("script");
      script.type = "module";
      script.src = MOONLIGHT_EDITOR_URL;
      script.dataset.moonlightEditor = "true";
      script.addEventListener("load", resolveModule, { once: true });
      script.addEventListener(
        "error",
        () => {
          moonlightModulePromise = null;
          script.remove();
          reject(new Error("Failed to load Moonlight editor bundle"));
        },
        { once: true },
      );
      document.head.appendChild(script);
    });
  }

  return moonlightModulePromise;
}

export interface MoonlightEditorProps {
  /** JSX key */
  key?: string | number | undefined;
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
  /** Theme: light or dark */
  theme?: "light" | "dark";
}

/**
 * MoonlightEditor component for SVG editing
 * Uses the ESM API with automatic initialization
 */
export function MoonlightEditor(props: MoonlightEditorProps) {
  const {
    initialSvg,
    span,
    onSvgChange,
    width = 400,
    height = 300,
    readonly = false,
    theme = "light",
  } = props;

  let containerRef: HTMLDivElement | null = null;
  let editor: EditorHandle | null = null;
  let isInitialized = false;
  let isUnmounted = false;
  const [isLoaded, setIsLoaded] = createSignal(false);
  const [isError, setIsError] = createSignal(false);

  // Initialize moonlight editor (only once)
  const initEditor = async () => {
    if (!containerRef || isInitialized) return;
    isInitialized = true;
    setIsLoaded(false);
    setIsError(false);

    try {
      // Sanitize the initial SVG
      const sanitized = sanitizeSvg(initialSvg);
      const { createEditor } = await loadMoonlightEditorModule();

      if (!containerRef || isUnmounted) {
        isInitialized = false;
        return;
      }

      containerRef.innerHTML = "";

      // Create the editor using ESM API
      const createdEditor = createEditor(containerRef, {
        width,
        height,
        theme,
        readonly,
        initialSvg: sanitized,
      });

      if (!createdEditor) {
        isInitialized = false;
        throw new Error("createEditor returned null/undefined");
      }
      editor = createdEditor;

      // Subscribe to changes - skip initial change event
      if (!readonly && onSvgChange) {
        let skipInitial = true;
        editor.onChange(() => {
          if (skipInitial) {
            skipInitial = false;
            return;
          }
          if (editor && !isUnmounted) {
            const svg = editor.exportSvg();
            onSvgChange(svg, span);
          }
        });
      }

      if (!isUnmounted) {
        setIsLoaded(true);
      }
    } catch (e) {
      console.error("Failed to initialize MoonlightEditor:", e);
      isInitialized = false;
      if (!isUnmounted) {
        setIsError(true);
      }
    }
  };

  // Initialize on mount
  onMount(() => {
    void initEditor();
  });

  // Cleanup
  onCleanup(() => {
    isUnmounted = true;
    if (editor) {
      editor.destroy();
      editor = null;
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
          containerRef = el as HTMLDivElement;
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
                void initEditor();
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
