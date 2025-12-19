///| Preact renderer for markdown AST

import type { ComponentChildren } from "preact";
import type {
  Document,
  Block,
  Inline,
  ListItem,
  TableCell,
  TableAlign,
} from "../js/api";

// Block renderer
export function renderBlock(block: Block, key?: string | number): ComponentChildren {
  switch (block.type) {
    case "paragraph":
      return (
        <p key={key} data-span={`${block.span.from}-${block.span.to}`}>
          {block.children.map((child, i) => renderInline(child, i))}
        </p>
      );

    case "heading": {
      const Tag = `h${block.level}` as "h1" | "h2" | "h3" | "h4" | "h5" | "h6";
      return (
        <Tag key={key} data-span={`${block.span.from}-${block.span.to}`}>
          {block.children.map((child, i) => renderInline(child, i))}
        </Tag>
      );
    }

    case "code_block": {
      const info = block.info ?? "";
      const lang = info.split(/[:\s]/)[0] ?? "";
      return (
        <pre key={key} data-span={`${block.span.from}-${block.span.to}`}>
          <code class={lang ? `language-${lang}` : undefined}>{block.code}</code>
        </pre>
      );
    }

    case "blockquote":
      return (
        <blockquote key={key} data-span={`${block.span.from}-${block.span.to}`}>
          {block.children.map((child, i) => renderBlock(child, i))}
        </blockquote>
      );

    case "bullet_list": {
      const hasTaskItems = block.items.some((item) => item.checked !== null);
      return (
        <ul
          key={key}
          class={hasTaskItems ? "contains-task-list" : undefined}
          data-span={`${block.span.from}-${block.span.to}`}
        >
          {block.items.map((item, i) => renderListItem(item, i))}
        </ul>
      );
    }

    case "ordered_list":
      return (
        <ol
          key={key}
          start={block.start !== 1 ? block.start : undefined}
          data-span={`${block.span.from}-${block.span.to}`}
        >
          {block.items.map((item, i) => renderListItem(item, i))}
        </ol>
      );

    case "thematic_break":
      return <hr key={key} data-span={`${block.span.from}-${block.span.to}`} />;

    case "html_block":
      return (
        <div
          key={key}
          data-span={`${block.span.from}-${block.span.to}`}
          dangerouslySetInnerHTML={{ __html: block.html }}
        />
      );

    case "table":
      return (
        <table key={key} data-span={`${block.span.from}-${block.span.to}`}>
          <thead>
            <tr>
              {block.header.map((cell, i) =>
                renderTableCell(cell, i, "th", block.alignments[i])
              )}
            </tr>
          </thead>
          <tbody>
            {block.rows.map((row, rowIdx) => (
              <tr key={rowIdx}>
                {row.map((cell, i) =>
                  renderTableCell(cell, i, "td", block.alignments[i])
                )}
              </tr>
            ))}
          </tbody>
        </table>
      );

    case "blank_lines":
      return null;

    case "footnote_definition":
      return (
        <div
          key={key}
          class="footnote-definition"
          id={`fn-${block.label}`}
          data-span={`${block.span.from}-${block.span.to}`}
        >
          <sup>{block.label}</sup>
          {block.children.map((child, i) => renderBlock(child, i))}
        </div>
      );

    default:
      return null;
  }
}

// List item renderer
function renderListItem(item: ListItem, key: number): ComponentChildren {
  const isTask = item.checked !== null;

  if (isTask) {
    return (
      <li key={key} class="task-list-item" data-span={`${item.span.from}-${item.span.to}`}>
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
    <li key={key} data-span={`${item.span.from}-${item.span.to}`}>
      {item.children.map((child, i) => renderBlock(child, i))}
    </li>
  );
}

// Table cell renderer
function renderTableCell(
  cell: TableCell,
  key: number,
  Tag: "th" | "td",
  align: TableAlign | null | undefined
): ComponentChildren {
  const style = align ? { textAlign: align } : undefined;
  return (
    <Tag key={key} style={style} data-span={`${cell.span.from}-${cell.span.to}`}>
      {cell.children.map((child, i) => renderInline(child, i))}
    </Tag>
  );
}

// Inline renderer
export function renderInline(inline: Inline, key?: string | number): ComponentChildren {
  switch (inline.type) {
    case "text":
      return <span key={key}>{inline.content}</span>;

    case "soft_break":
      return " ";

    case "hard_break":
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

    case "strikethrough":
      return (
        <del key={key}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </del>
      );

    case "code":
      return <code key={key}>{inline.content}</code>;

    case "link":
      return (
        <a key={key} href={inline.url} title={inline.title || undefined}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </a>
      );

    case "ref_link":
      // Reference links should be resolved; for now render as text
      return (
        <span key={key}>
          {inline.children.map((child, i) => renderInline(child, i))}
        </span>
      );

    case "autolink": {
      const href = inline.is_email ? `mailto:${inline.url}` : inline.url;
      return (
        <a key={key} href={href}>
          {inline.url}
        </a>
      );
    }

    case "image":
      return (
        <img
          key={key}
          src={inline.url}
          alt={inline.alt}
          title={inline.title || undefined}
        />
      );

    case "ref_image":
      // Reference images should be resolved; for now render alt text
      return <span key={key}>[{inline.alt}]</span>;

    case "html_inline":
      return (
        <span key={key} dangerouslySetInnerHTML={{ __html: inline.html }} />
      );

    case "footnote_reference":
      return (
        <sup key={key}>
          <a href={`#fn-${inline.label}`}>[{inline.label}]</a>
        </sup>
      );

    default:
      return null;
  }
}

// Document renderer component
export function MarkdownRenderer({ ast }: { ast: Document }) {
  return (
    <div class="markdown-body" data-span={`${ast.span.from}-${ast.span.to}`}>
      {ast.children.map((block, i) => renderBlock(block, i))}
    </div>
  );
}
