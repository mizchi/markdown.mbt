///| Moonlight SVG Editor wrapper component
///| Uses the ESM API for bidirectional editing of SVG in markdown code blocks

import { createSignal, onMount, onCleanup } from "@luna_ui/luna";
import { createEditor, type EditorHandle } from "@mizchi/moonlight";
import { sanitizeSvg } from "./ast-renderer";

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
  const [isLoaded, setIsLoaded] = createSignal(false);
  const [isError, setIsError] = createSignal(false);

  // Initialize moonlight editor (only once)
  const initEditor = () => {
    if (!containerRef || isInitialized) return;
    isInitialized = true;

    try {
      // Sanitize the initial SVG
      const sanitized = sanitizeSvg(initialSvg);

      // Create the editor using ESM API
      editor = createEditor(containerRef, {
        width,
        height,
        theme,
        readonly,
        initialSvg: sanitized,
      });

      if (!editor) {
        isInitialized = false;
        throw new Error("createEditor returned null/undefined");
      }

      // Subscribe to changes - skip initial change event
      if (!readonly && onSvgChange) {
        let skipInitial = true;
        editor.onChange(() => {
          if (skipInitial) {
            skipInitial = false;
            return;
          }
          if (editor) {
            const svg = editor.exportSvg();
            onSvgChange(svg, span);
          }
        });
      }

      setIsLoaded(true);
    } catch (e) {
      console.error("Failed to initialize MoonlightEditor:", e);
      isInitialized = false;
      setIsError(true);
    }
  };

  // Initialize on mount
  onMount(() => {
    initEditor();
  });

  // Cleanup
  onCleanup(() => {
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
