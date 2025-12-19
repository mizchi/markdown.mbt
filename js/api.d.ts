/**
 * @moonbit/markdown - TypeScript type definitions
 */

// =============================================================================
// AST Types
// =============================================================================

export interface Span {
  from: number;
  to: number;
}

export type Block =
  | ParagraphBlock
  | HeadingBlock
  | CodeBlockBlock
  | BlockquoteBlock
  | BulletListBlock
  | OrderedListBlock
  | ThematicBreakBlock
  | HtmlBlockBlock
  | TableBlock
  | BlankLinesBlock
  | FootnoteDefinitionBlock;

export interface ParagraphBlock {
  type: "paragraph";
  children: Inline[];
  span: Span;
}

export interface HeadingBlock {
  type: "heading";
  level: number;
  children: Inline[];
  span: Span;
}

export interface CodeBlockBlock {
  type: "code_block";
  info: string | null;
  code: string;
  span: Span;
}

export interface BlockquoteBlock {
  type: "blockquote";
  children: Block[];
  span: Span;
}

export interface BulletListBlock {
  type: "bullet_list";
  tight: boolean;
  items: ListItem[];
  span: Span;
}

export interface OrderedListBlock {
  type: "ordered_list";
  start: number;
  tight: boolean;
  items: ListItem[];
  span: Span;
}

export interface ThematicBreakBlock {
  type: "thematic_break";
  span: Span;
}

export interface HtmlBlockBlock {
  type: "html_block";
  html: string;
  span: Span;
}

export interface TableBlock {
  type: "table";
  header: TableCell[];
  alignments: (TableAlign | null)[];
  rows: TableCell[][];
  span: Span;
}

export interface BlankLinesBlock {
  type: "blank_lines";
  count: number;
  span: Span;
}

export interface FootnoteDefinitionBlock {
  type: "footnote_definition";
  label: string;
  children: Block[];
  span: Span;
}

export interface ListItem {
  type: "list_item";
  children: Block[];
  checked: boolean | null;
  span: Span;
}

export interface TableCell {
  type: "table_cell";
  children: Inline[];
  span: Span;
}

export type TableAlign = "left" | "center" | "right";

export type Inline =
  | TextInline
  | SoftBreakInline
  | HardBreakInline
  | EmphasisInline
  | StrongInline
  | StrikethroughInline
  | CodeInline
  | LinkInline
  | RefLinkInline
  | AutolinkInline
  | ImageInline
  | RefImageInline
  | HtmlInlineInline
  | FootnoteReferenceInline;

export interface TextInline {
  type: "text";
  content: string;
  span: Span;
}

export interface SoftBreakInline {
  type: "soft_break";
  span: Span;
}

export interface HardBreakInline {
  type: "hard_break";
  span: Span;
}

export interface EmphasisInline {
  type: "emphasis";
  children: Inline[];
  span: Span;
}

export interface StrongInline {
  type: "strong";
  children: Inline[];
  span: Span;
}

export interface StrikethroughInline {
  type: "strikethrough";
  children: Inline[];
  span: Span;
}

export interface CodeInline {
  type: "code";
  content: string;
  span: Span;
}

export interface LinkInline {
  type: "link";
  children: Inline[];
  url: string;
  title: string;
  span: Span;
}

export interface RefLinkInline {
  type: "ref_link";
  children: Inline[];
  label: string;
  span: Span;
}

export interface AutolinkInline {
  type: "autolink";
  url: string;
  is_email: boolean;
  span: Span;
}

export interface ImageInline {
  type: "image";
  alt: string;
  url: string;
  title: string;
  span: Span;
}

export interface RefImageInline {
  type: "ref_image";
  alt: string;
  label: string;
  span: Span;
}

export interface HtmlInlineInline {
  type: "html_inline";
  html: string;
  span: Span;
}

export interface FootnoteReferenceInline {
  type: "footnote_reference";
  label: string;
  span: Span;
}

export interface Document {
  type: "document";
  children: Block[];
  span: Span;
}

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

// =============================================================================
// Document Handle
// =============================================================================

/**
 * A parsed markdown document with handle-based management.
 */
export interface DocumentHandle {
  /** Get the parsed AST (cached after first access) */
  readonly ast: Document;

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
 * Parse markdown and return the AST.
 *
 * @example
 * const ast = parse("# Hello\n\nWorld");
 * console.log(ast.children[0].type); // "heading"
 */
export function parse(source: string): Document;

/**
 * Convert markdown to HTML.
 *
 * @example
 * const html = toHtml("# Hello\n\n**Bold** text");
 * // => "<h1>Hello</h1>\n<p><strong>Bold</strong> text</p>\n"
 */
export function toHtml(source: string): string;

/**
 * Normalize/serialize markdown source.
 *
 * @example
 * const normalized = toMarkdown("# Hello\n\n\n\nWorld");
 * // => "# Hello\n\nWorld\n"
 */
export function toMarkdown(source: string): string;

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
export function createDocument(source: string): DocumentHandle;

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
