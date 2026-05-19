/**
 * @moonbit/markdown - TypeScript type definitions
 *
 * Uses mdast types from @types/mdast for compatibility with the unified ecosystem.
 * See: https://github.com/syntax-tree/mdast
 */

// Re-export mdast types
export type {
  Root,
  RootContent,
  Content,
  Paragraph,
  Heading,
  Code,
  Blockquote,
  List,
  ListItem,
  ThematicBreak,
  Html,
  Table,
  TableRow,
  TableCell,
  Text,
  Emphasis,
  Strong,
  Delete,
  InlineCode,
  Link,
  LinkReference,
  Image,
  ImageReference,
  Break,
  FootnoteDefinition,
  FootnoteReference,
  Definition,
  AlignType,
  ReferenceType,
  PhrasingContent,
  BlockContent,
} from "mdast";

// =============================================================================
// Edit Types
// =============================================================================

/**
 * Edit information for incremental parsing.
 */
export interface EditInfo {
  /** Start position of the edit in the old source */
  start: number;
  /** End position of the edit in the old source */
  oldEnd: number;
  /** End position of the edit in the new source */
  newEnd: number;
}

/**
 * Parser extension options.
 */
export interface MarkdownOptions {
  /**
   * Enable Obsidian-style wikilinks: [[target]] and [[target|label]].
   * Disabled by default to keep CommonMark-compatible behavior.
   */
  wikilinks?: boolean;

  /**
   * Render bare http:// and https:// URL text as links.
   * Enabled by default; set false to keep bare URLs as plain text.
   */
  autolink?: boolean;
}

/**
 * mdast extension node emitted when MarkdownOptions.wikilinks is enabled.
 */
export interface WikiLink {
  type: "wikiLink";
  value: string;
  data: {
    label: string;
    fragment: string;
  };
}

// =============================================================================
// Document Handle
// =============================================================================

/**
 * A parsed markdown document with handle-based management.
 */
export interface DocumentHandle {
  /** Get the parsed AST (cached after first access) */
  readonly ast: import("mdast").Root;

  /** Render the document to HTML */
  toHtml(): string;

  /** Serialize the document back to markdown */
  toMarkdown(): string;

  /**
   * Apply an incremental edit and return a new document.
   * The original document is not modified.
   */
  update(newSource: string, edit: EditInfo): DocumentHandle;

  /** Free the document resources */
  dispose(): void;
}

// =============================================================================
// API Functions
// =============================================================================

/**
 * Parse markdown and return the AST (mdast Root).
 *
 * @example
 * const ast = parse("# Hello\n\nWorld");
 * console.log(ast.children[0].type); // "heading"
 */
export function parse(source: string, options?: MarkdownOptions): import("mdast").Root;

/**
 * Convert markdown to HTML.
 *
 * @example
 * const html = toHtml("# Hello\n\n**Bold** text");
 * // => "<h1>Hello</h1>\n<p><strong>Bold</strong> text</p>\n"
 */
export function toHtml(source: string, options?: MarkdownOptions): string;

/**
 * Normalize/serialize markdown source.
 *
 * @example
 * const normalized = toMarkdown("# Hello\n\n\n\nWorld");
 * // => "# Hello\n\nWorld\n"
 */
export function toMarkdown(source: string, options?: MarkdownOptions): string;

/**
 * Render markdown using the "literal" mode, which preserves syntax markers
 * (`#`, `*`, `` ` ``, list bullets, fence ticks, blockquote `>` …) wrapped
 * in `<span class="md-marker" aria-hidden="true">…</span>` inside the
 * rendered HTML.
 *
 * The visible text of the output (HTML tags stripped, basic character
 * references decoded) is byte-for-byte equal to `toMarkdown(source)`.
 * Combined with `font-family: monospace; white-space: pre-wrap;` (see
 * `@mizchi/markdown/editor/overlay.css`) this lets a consumer overlay the
 * rendered output on a syntax-highlighted source view so that every glyph
 * lines up.
 *
 * @example
 * toHtmlLiteral("## Intro\n");
 * // => '<h2><span class="md-marker" aria-hidden="true">## </span>Intro</h2>\n'
 */
export interface LiteralOptions extends MarkdownOptions {
  /**
   * When true, every top-level block element in the rendered HTML carries
   * `data-src-start` / `data-src-end` attributes (character offsets in
   * the original source). The literal renderer's visible-text invariant
   * means the offset of a character inside such an element equals
   * `data-src-start + char-index-within-element`, so a "click → cursor"
   * editor can compute exact source positions by walking up to the
   * nearest annotated ancestor.
   *
   * Inline elements (em, strong, code, a, ...) are NOT annotated because
   * their spans come from the inline parser and are relative to the
   * surrounding block's content, not the document.
   *
   * Defaults to false.
   */
  positions?: boolean;

  /**
   * When true, each `<span class="md-image">` wrapper also contains an
   * `<img class="md-image-preview" src=… alt=… title=…>` slot alongside
   * the source characters `![alt](url)`. The `<img>` carries no visible
   * text so the source/preview overlay invariant is preserved.
   *
   * `@mizchi/markdown/editor/overlay.css` hides the slot by default;
   * the consumer opts in by adding `.with-image-preview` to a container
   * above the rendered output. Reference images (`![alt][label]`) emit
   * an empty-`src` slot carrying `data-md-image-ref="label"` so the
   * consumer can resolve the URL from their link-definition map.
   *
   * Defaults to false.
   */
  imagePreview?: boolean;
}

export function toHtmlLiteral(source: string, options?: LiteralOptions): string;

/**
 * Create a new document handle from markdown source.
 * Use this for incremental parsing scenarios.
 *
 * @example
 * const doc = createDocument("# Hello");
 * console.log(doc.ast.children[0].type); // "heading"
 * console.log(doc.toHtml()); // "<h1>Hello</h1>\n"
 *
 * const newDoc = doc.update("# Hello World", {
 *   start: 7,
 *   oldEnd: 7,
 *   newEnd: 13
 * });
 *
 * doc.dispose(); // Free resources
 */
export function createDocument(source: string, options?: MarkdownOptions): DocumentHandle;

/**
 * Create an EditInfo for insertion.
 *
 * @example
 * const edit = insertEdit(5, 6); // Insert 6 chars at position 5
 */
export function insertEdit(position: number, length: number): EditInfo;

/**
 * Create an EditInfo for deletion.
 *
 * @example
 * const edit = deleteEdit(5, 10); // Delete from position 5 to 10
 */
export function deleteEdit(start: number, end: number): EditInfo;

/**
 * Create an EditInfo for replacement.
 *
 * @example
 * const edit = replaceEdit(5, 10, 8); // Replace 5-10 with 8 chars
 */
export function replaceEdit(start: number, oldEnd: number, newLength: number): EditInfo;
