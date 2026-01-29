///| Luna UI renderer for mdast AST

import type {
  Root,
  RootContent,
  PhrasingContent,
  ListItem,
  TableCell,
  AlignType,
} from "mdast";
import type { Position } from "unist";
// @ts-ignore - no type declarations for syntree_api.js
import { highlight } from "../js/syntree_api.js";

// =============================================================================
// SVG Sanitizer
// =============================================================================

// Event handler attribute patterns to remove
const EVENT_HANDLER_PATTERN = /\s+on\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi;

// Dangerous elements to remove entirely
const DANGEROUS_ELEMENTS = /<script[^>]*>[\s\S]*?<\/script>/gi;

// javascript: and data: URLs in attributes
const DANGEROUS_URL_PATTERN = /\s+(href|xlink:href|src)\s*=\s*["']?\s*(javascript:|data:text\/html)/gi;

/**
 * Sanitize SVG content by removing event handlers, scripts, and dangerous URLs.
 * This is a lightweight sanitizer for preview purposes.
 */
export function sanitizeSvg(svg: string): string {
  return svg
    // Remove <script> elements
    .replace(DANGEROUS_ELEMENTS, "")
    // Remove event handlers (onclick, onload, etc.)
    .replace(EVENT_HANDLER_PATTERN, "")
    // Remove dangerous URLs
    .replace(DANGEROUS_URL_PATTERN, "");
}

// =============================================================================
// Code Block Language Parser
// =============================================================================

/**
 * Parse language string that may include a mode suffix.
 * e.g., "svg:preview" -> { lang: "svg", mode: "preview" }
 * e.g., "typescript" -> { lang: "typescript", mode: undefined }
 */
export function parseCodeBlockLang(langString: string): { lang: string; mode?: string } {
  const colonIndex = langString.indexOf(":");
  if (colonIndex === -1) {
    return { lang: langString };
  }
  return {
    lang: langString.slice(0, colonIndex),
    mode: langString.slice(colonIndex + 1),
  };
}

// =============================================================================
// Renderer Types
// =============================================================================

// Callbacks for interactive preview (optional - works without callbacks for static rendering)
export interface RendererCallbacks {
  // Task list checkbox toggle
  onTaskToggle?: (span: string, checked: boolean) => void;
  // Element click (future extension)
  onElementClick?: (span: string, nodeType: string) => void;
  // Code block action (future extension: execute, copy, etc.)
  onCodeAction?: (span: string, lang: string, action: string) => void;
}

// Code block handler for custom rendering (e.g., SVG, mermaid, moonlight)
// Return null to fall through to default syntax highlighting
export interface CodeBlockHandler {
  render: (code: string, span: string, key?: string | number, mode?: string) => JSX.Element | null;
}

// Renderer options for customizing rendering behavior
export interface RendererOptions {
  // Custom handlers for specific code block languages
  codeBlockHandlers?: Record<string, CodeBlockHandler>;
}

// Helper component to render raw HTML using ref callback (exported for custom handlers)
export function RawHtml({ html, ...props }: { html: string } & Record<string, unknown>) {
  return (
    <div
      {...props}
      ref={(el) => {
        if (el) el.innerHTML = html;
      }}
    />
  );
}

// Helper component to render raw HTML in a span
function RawHtmlSpan({ html, ...props }: { html: string } & Record<string, unknown>) {
  return (
    <span
      {...props}
      ref={(el) => {
        if (el) el.innerHTML = html;
      }}
    />
  );
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
  rs: "rust",
  xml: "html",
  svg: "html",
  htm: "html",
};

const supportedLangs = ["typescript", "moonbit", "json", "html", "css", "bash", "rust"];

// Highlight code using syntree
function highlightCode(code: string, lang: string): string | null {
  const mappedLang = langMap[lang] || lang;
  if (!supportedLangs.includes(mappedLang)) {
    return null;
  }
  try {
    return highlight(code, mappedLang);
  } catch (e) {
    console.error("Code highlight error:", e);
    return null;
  }
}

// Helper to get position offset for data-span
function getSpan(node: { position?: Position | undefined }): string {
  const start = node.position?.start?.offset ?? 0;
  const end = node.position?.end?.offset ?? 0;
  return `${start}-${end}`;
}

// Block renderer
export function renderBlock(
  block: RootContent,
  key?: string | number,
  callbacks?: RendererCallbacks,
  options?: RendererOptions
): JSX.Element | null {
  switch (block.type) {
    case "paragraph":
      return (
        <p key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </p>
      );

    case "heading": {
      const Tag = `h${block.depth}` as "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
      return (
        <Tag key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </Tag>
      );
    }

    case "code": {
      const langString = block.lang ?? "";
      const { lang, mode } = parseCodeBlockLang(langString);
      const span = getSpan(block);

      // Check for custom handler first (supports both "svg" and "svg:preview")
      // Handler can return null to fall through to default highlighting
      const handler = options?.codeBlockHandlers?.[lang];
      if (handler) {
        const result = handler.render(block.value, span, key, mode);
        if (result !== null) {
          return result;
        }
      }

      const highlighted = lang ? highlightCode(block.value, lang) : null;

      if (highlighted) {
        // Use highlighted HTML from syntree (highlight format)
        return (
          <RawHtml
            key={key}
            data-span={span}
            html={highlighted}
          />
        );
      }

      // Fallback for unsupported languages
      return (
        <pre key={key} data-span={span}>
          <code class={lang ? `language-${lang}` : undefined}>{block.value}</code>
        </pre>
      );
    }

    case "blockquote":
      return (
        <blockquote key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderBlock(child, i, callbacks, options)).filter(Boolean)}
        </blockquote>
      );

    case "list": {
      const hasTaskItems = block.children.some((item) => item.checked != null);
      if (block.ordered) {
        return (
          <ol
            key={key}
            start={block.start !== 1 ? block.start ?? undefined : undefined}
            class={hasTaskItems ? "contains-task-list" : undefined}
            data-span={getSpan(block)}
          >
            {block.children.map((item, i) => renderListItem(item, i, callbacks, options)).filter(Boolean)}
          </ol>
        );
      }
      return (
        <ul
          key={key}
          class={hasTaskItems ? "contains-task-list" : undefined}
          data-span={getSpan(block)}
        >
          {block.children.map((item, i) => renderListItem(item, i, callbacks, options)).filter(Boolean)}
        </ul>
      );
    }

    case "thematicBreak":
      return <hr key={key} data-span={getSpan(block)} />;

    case "html":
      return (
        <RawHtml
          key={key}
          data-span={getSpan(block)}
          html={block.value}
        />
      );

    case "table": {
      const [headerRow, ...bodyRows] = block.children;
      const align = block.align ?? [];
      return (
        <table key={key} data-span={getSpan(block)}>
          {headerRow && (
            <thead>
              <tr>
                {headerRow.children.map((cell, i) =>
                  renderTableCell(cell, i, "th", align[i])
                ).filter(Boolean)}
              </tr>
            </thead>
          )}
          {bodyRows.length > 0 && (
            <tbody>
              {bodyRows.map((row, rowIdx) => (
                <tr key={rowIdx}>
                  {row.children.map((cell, i) =>
                    renderTableCell(cell, i, "td", align[i])
                  ).filter(Boolean)}
                </tr>
              ))}
            </tbody>
          )}
        </table>
      );
    }

    case "footnoteDefinition":
      return (
        <div
          key={key}
          class="footnote-definition"
          id={`fn-${block.identifier}`}
          data-span={getSpan(block)}
        >
          <sup>{block.label ?? block.identifier}</sup>
          {block.children.map((child, i) => renderBlock(child, i, callbacks, options)).filter(Boolean)}
        </div>
      );

    case "definition":
      // Link definitions don't render visually
      return null;

    default:
      return null;
  }
}

// List item renderer
function renderListItem(
  item: ListItem,
  key: number,
  callbacks?: RendererCallbacks,
  options?: RendererOptions
): JSX.Element {
  const isTask = item.checked != null;

  if (isTask) {
    // Flatten children to avoid nested arrays which Luna doesn't handle well
    const children: JSX.Element[] = [];
    item.children.forEach((child, i) => {
      if (child.type === "paragraph") {
        // Inline the paragraph content for task items
        child.children.forEach((inline, j) => {
          const el = renderInline(inline, `${i}-${j}`);
          if (el) children.push(el);
        });
      } else {
        const el = renderBlock(child, i, callbacks, options);
        if (el) children.push(el);
      }
    });

    const span = getSpan(item);
    const handleChange = callbacks?.onTaskToggle
      ? (e: Event) => {
          const target = e.currentTarget as HTMLInputElement;
          callbacks.onTaskToggle!(span, target.checked);
        }
      : undefined;

    return (
      <li key={key} class="task-list-item" data-span={span}>
        <input
          type="checkbox"
          checked={item.checked ?? false}
          disabled={!callbacks?.onTaskToggle}
          onChange={handleChange}
        />
        {children}
      </li>
    );
  }

  return (
    <li key={key} data-span={getSpan(item)}>
      {item.children.map((child, i) => renderBlock(child, i, callbacks, options)).filter(Boolean)}
    </li>
  );
}

// Table cell renderer
function renderTableCell(
  cell: TableCell,
  key: number,
  Tag: "th" | "td",
  align: AlignType | undefined
): JSX.Element {
  const style = align ? { textAlign: align } : undefined;
  return (
    <Tag key={key} style={style} data-span={getSpan(cell)}>
      {cell.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
    </Tag>
  );
}

// Inline renderer
export function renderInline(inline: PhrasingContent, key?: string | number): JSX.Element | string | null {
  switch (inline.type) {
    case "text":
      // Check for newline (soft break representation)
      if (inline.value === "\n") {
        return " ";
      }
      return <span key={key}>{inline.value}</span>;

    case "break":
      return <br key={key} />;

    case "emphasis":
      return (
        <em key={key}>
          {inline.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </em>
      );

    case "strong":
      return (
        <strong key={key}>
          {inline.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </strong>
      );

    case "delete":
      return (
        <del key={key}>
          {inline.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </del>
      );

    case "inlineCode":
      return <code key={key}>{inline.value}</code>;

    case "link":
      return (
        <a key={key} href={inline.url} title={inline.title ?? undefined}>
          {inline.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </a>
      );

    case "linkReference":
      // Reference links should be resolved; for now render as text
      return (
        <span key={key}>
          {inline.children.map((child, i) => renderInline(child, i)).filter(Boolean)}
        </span>
      );

    case "image":
      return (
        <img
          key={key}
          src={inline.url}
          alt={inline.alt ?? ""}
          title={inline.title ?? undefined}
        />
      );

    case "imageReference":
      // Reference images should be resolved; for now render alt text
      return <span key={key}>[{inline.alt}]</span>;

    case "html":
      return (
        <RawHtmlSpan key={key} html={inline.value} />
      );

    case "footnoteReference":
      return (
        <sup key={key}>
          <a href={`#fn-${inline.identifier}`}>[{inline.label ?? inline.identifier}]</a>
        </sup>
      );

    default:
      return null;
  }
}

// Document renderer component
export function MarkdownRenderer({
  ast,
  callbacks,
  options,
}: {
  ast: Root;
  callbacks?: RendererCallbacks;
  options?: RendererOptions;
}) {
  if (!ast) return null;
  return (
    <div class="markdown-body" data-span={getSpan(ast)}>
      {ast.children.map((block, i) => renderBlock(block, i, callbacks, options)).filter(Boolean)}
    </div>
  );
}
