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
