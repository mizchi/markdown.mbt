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
// @ts-ignore - no type declarations for lezer_api.js
import { highlight } from "../js/lezer_api.js";

// Helper component to render raw HTML using ref callback
function RawHtml({ html, ...props }: { html: string } & Record<string, unknown>) {
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
};

const supportedLangs = ["typescript", "moonbit", "json", "html", "css", "bash", "rust"];

// Highlight code using lezer
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
export function renderBlock(block: RootContent, key?: string | number): JSX.Element | null {
  switch (block.type) {
    case "paragraph":
      return (
        <p key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderInline(child, i))}
        </p>
      );

    case "heading": {
      const Tag = `h${block.depth}` as "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
      return (
        <Tag key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderInline(child, i))}
        </Tag>
      );
    }

    case "code": {
      const lang = block.lang ?? "";
      const highlighted = lang ? highlightCode(block.value, lang) : null;

      if (highlighted) {
        // Use highlighted HTML from lezer (shiki format)
        return (
          <RawHtml
            key={key}
            data-span={getSpan(block)}
            html={highlighted}
          />
        );
      }

      // Fallback for unsupported languages
      return (
        <pre key={key} data-span={getSpan(block)}>
          <code class={lang ? `language-${lang}` : undefined}>{block.value}</code>
        </pre>
      );
    }

    case "blockquote":
      return (
        <blockquote key={key} data-span={getSpan(block)}>
          {block.children.map((child, i) => renderBlock(child, i))}
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
            {block.children.map((item, i) => renderListItem(item, i))}
          </ol>
        );
      }
      return (
        <ul
          key={key}
          class={hasTaskItems ? "contains-task-list" : undefined}
          data-span={getSpan(block)}
        >
          {block.children.map((item, i) => renderListItem(item, i))}
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
                )}
              </tr>
            </thead>
          )}
          {bodyRows.length > 0 && (
            <tbody>
              {bodyRows.map((row, rowIdx) => (
                <tr key={rowIdx}>
                  {row.children.map((cell, i) =>
                    renderTableCell(cell, i, "td", align[i])
                  )}
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
          {block.children.map((child, i) => renderBlock(child, i))}
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
function renderListItem(item: ListItem, key: number): JSX.Element {
  const isTask = item.checked != null;

  if (isTask) {
    return (
      <li key={key} class="task-list-item" data-span={getSpan(item)}>
        <input type="checkbox" checked={item.checked ?? false} disabled />
        {item.children.map((child, i) => {
          if (child.type === "paragraph") {
            // Inline the paragraph content for task items
            return child.children.map((inline, j) => renderInline(inline, `${i}-${j}`));
          }
          return renderBlock(child, i);
        })}
      </li>
    );
  }

  return (
    <li key={key} data-span={getSpan(item)}>
      {item.children.map((child, i) => renderBlock(child, i))}
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
      {cell.children.map((child, i) => renderInline(child, i))}
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
          {inline.children.map((child, i) => renderInline(child, i))}
        </em>
      );

    case "strong":
      return (
        <strong key={key}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </strong>
      );

    case "delete":
      return (
        <del key={key}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </del>
      );

    case "inlineCode":
      return <code key={key}>{inline.value}</code>;

    case "link":
      return (
        <a key={key} href={inline.url} title={inline.title ?? undefined}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </a>
      );

    case "linkReference":
      // Reference links should be resolved; for now render as text
      return (
        <span key={key}>
          {inline.children.map((child, i) => renderInline(child, i))}
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
export function MarkdownRenderer({ ast }: { ast: Root }) {
  if (!ast) return null;
  return (
    <div class="markdown-body" data-span={getSpan(ast)}>
      {ast.children.map((block, i) => renderBlock(block, i))}
    </div>
  );
}
