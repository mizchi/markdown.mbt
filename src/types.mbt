///| Markdown CST (Concrete Syntax Tree) Types

///| Designed for semantic parsing, source spans, and incremental updates.

// =============================================================================
// Source Position
// =============================================================================

///| Source position in the original markdown text

///|
/// Using #valtype to avoid heap allocation for this frequently-used small struct
#valtype
pub(all) struct Span {
  from : Int
  to : Int
} derive(Eq, Debug)

///|
/// Create a span
pub fn Span::new(from : Int, to : Int) -> Span {
  { from, to }
}

///|
/// Empty span (for synthetic nodes)
pub fn Span::empty() -> Span {
  { from: 0, to: 0 }
}

// =============================================================================
// Source markers retained for editor and source-oriented rendering APIs.
// =============================================================================

///|
/// Emphasis marker: * or _
pub(all) enum EmphasisMarker {
  Asterisk // *
  Underscore // _
} derive(Eq, Debug)

///|
/// Fence marker for code blocks: ``` or ~~~
pub(all) enum FenceMarker {
  Backtick // ```
  Tilde // ~~~
} derive(Eq, Debug)

///|
/// List marker for unordered lists: -, *, +
pub(all) enum BulletMarker {
  Dash // -
  Asterisk // *
  Plus // +
} derive(Eq, Debug)

///|
/// Ordered list delimiter: . or )
pub(all) enum OrderedDelimiter {
  Dot // 1.
  Paren // 1)
} derive(Eq, Debug)

///|
/// Heading style
pub(all) enum HeadingStyle {
  Atx // # Heading
  Setext // Heading\n======
} derive(Eq, Debug)

///|
/// Syntax used by a link or image reference.
pub(all) enum ReferenceStyle {
  Full // [text][label]
  Collapsed // [text][]
  Shortcut // [text]
} derive(Eq, Debug)

// =============================================================================
// Trivia (preserved whitespace/formatting)
// =============================================================================

///|
/// Trivia represents non-semantic characters that should be preserved
pub(all) struct Trivia {
  content : String
} derive(Eq, Debug)

///|
pub fn Trivia::new(content : String) -> Trivia {
  { content, }
}

///|
pub fn Trivia::empty() -> Trivia {
  { content: "" }
}

///|
pub impl Show for Span with fn output(self : Span, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for EmphasisMarker with fn output(
  self : EmphasisMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for FenceMarker with fn output(
  self : FenceMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for BulletMarker with fn output(
  self : BulletMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for OrderedDelimiter with fn output(
  self : OrderedDelimiter,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for HeadingStyle with fn output(
  self : HeadingStyle,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for Trivia with fn output(self : Trivia, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

// =============================================================================
// Block-level CST Nodes
// =============================================================================

///|
/// Document root
pub(all) struct Document {
  frontmatter : Frontmatter?
  children : Array[Block]
  /// Link reference definitions collected from the whole document, needed to
  /// resolve `[foo]` style references when rendering.
  definitions : Array[LinkDefinition]
  span : Span
}

///|
/// Frontmatter (YAML)
pub(all) struct Frontmatter {
  raw : String // Original YAML content (between ---)
  entries : Array[(String, String)] // Parsed key-value pairs
  span : Span
}

///|
/// One normalized block attribute from `{#id .class key=value}`.
pub(all) struct MarkdownAttribute {
  name : String
  value : String
} derive(Eq, Debug)

///|
/// GitHub alert kind (`> [!NOTE]`, etc.).
pub(all) enum AlertKind {
  Note
  Tip
  Important
  Warning
  Caution
} derive(Eq, Debug)

///|
pub impl Show for AlertKind with fn output(self : AlertKind, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
/// Stable lowercase name used by renderers and JSON APIs.
pub fn AlertKind::slug(self : AlertKind) -> String {
  match self {
    Note => "note"
    Tip => "tip"
    Important => "important"
    Warning => "warning"
    Caution => "caution"
  }
}

///|
/// Block-level nodes
pub(all) enum Block {
  /// Thematic break (---, ***, ___)
  ThematicBreak(
    marker~ : Char, // '-', '*', or '_'
    count~ : Int, // Number of marker chars (>= 3)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// ATX or Setext heading
  Heading(
    level~ : Int, // 1-6
    style~ : HeadingStyle,
    children~ : Array[Inline],
    closing_hashes~ : Int, // For ATX: number of closing # (0 if none)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Paragraph
  Paragraph(
    children~ : Array[Inline],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Fenced code block
  FencedCode(
    fence_marker~ : FenceMarker,
    fence_length~ : Int, // Number of fence chars (>= 3)
    info~ : String, // Language info (e.g., "json:file.json")
    code~ : String, // Code content
    indent~ : Int, // Leading spaces on fence (0-3)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Display math fenced by a line containing two or more `$` characters.
  MathBlock(
    value~ : String,
    fence_length~ : Int,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Generic fenced directive (`:::name metadata ... :::`).
  Directive(
    name~ : String,
    meta~ : String,
    children~ : Array[Block],
    fence_length~ : Int,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Definition list (`Term` followed by one or more `: Definition` lines).
  DefinitionList(
    items~ : Array[DefinitionItem],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Apply a block attribute list without adding fields to every block kind.
  Attributed(
    block~ : Block,
    attributes~ : Array[MarkdownAttribute],
    span~ : Span
  )
  /// Indented code block
  IndentedCode(
    code~ : String,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Blockquote
  Blockquote(
    children~ : Array[Block],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// GitHub alert, recognized from a blockquote whose first line is `[!KIND]`.
  Alert(
    kind~ : AlertKind,
    children~ : Array[Block],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Unordered list
  BulletList(
    marker~ : BulletMarker,
    tight~ : Bool, // Tight (no blank lines) or loose
    items~ : Array[ListItem],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Ordered list
  OrderedList(
    start~ : Int, // Starting number
    delimiter~ : OrderedDelimiter,
    tight~ : Bool,
    items~ : Array[ListItem],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Raw HTML block
  HtmlBlock(
    html~ : String,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Table (GFM)
  Table(
    header~ : Array[TableCell],
    alignments~ : Array[TableAlign],
    rows~ : Array[Array[TableCell]],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Blank lines (preserved)
  BlankLines(count~ : Int, span~ : Span)
  /// Footnote definition [^label]: content (GFM)
  FootnoteDefinition(
    label~ : String,
    children~ : Array[Block],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
}

///|
/// List item
pub(all) struct ListItem {
  children : Array[Block]
  checked : Bool? // For task lists: Some(true), Some(false), or None
  marker_offset : Int // Spaces before marker
  content_offset : Int // Spaces after marker before content
  span : Span
}

///|
/// Table cell
pub(all) struct TableCell {
  children : Array[Inline]
  span : Span
}

///|
/// One term and one or more inline definitions in a definition list.
pub(all) struct DefinitionItem {
  term : Array[Inline]
  definitions : Array[Array[Inline]]
}

///|
/// Table alignment
pub(all) enum TableAlign {
  Left
  Center
  Right
  None
} derive(Eq, Debug)

// =============================================================================
// Inline-level CST Nodes
// =============================================================================

///|
/// Inline-level nodes
pub(all) enum Inline {
  /// Plain text
  Text(content~ : String, span~ : Span)
  /// Soft line break (single newline in source)
  SoftBreak(span~ : Span)
  /// Hard line break (two spaces + newline or backslash + newline)
  HardBreak(style~ : HardBreakStyle, span~ : Span)
  /// Emphasis (*text* or _text_)
  Emphasis(marker~ : EmphasisMarker, children~ : Array[Inline], span~ : Span)
  /// Strong emphasis (**text** or __text__)
  Strong(marker~ : EmphasisMarker, children~ : Array[Inline], span~ : Span)
  /// Strikethrough (~~text~~) - GFM
  Strikethrough(children~ : Array[Inline], span~ : Span)
  /// Inline code (`code`)
  Code(
    content~ : String,
    backtick_count~ : Int, // Number of backticks used
    span~ : Span
  )
  /// Text directive `:name[label]{#id .class key=value}`.
  ///
  /// The label intentionally stays raw text. Consumers can map this node to
  /// their own component/rendering layer without interpreting nested Markdown.
  Directive(
    name~ : String,
    label~ : String,
    attributes~ : Array[MarkdownAttribute],
    span~ : Span
  )
  /// Wiki link [[target]] or [[target|label]] (opt-in extension)
  WikiLink(target~ : String, label~ : String, fragment~ : String, span~ : Span)
  /// Link [text](url "title")
  Link(children~ : Array[Inline], url~ : String, title~ : String, span~ : Span)
  /// Reference link [text][ref]
  RefLink(
    children~ : Array[Inline],
    label~ : String,
    style~ : ReferenceStyle,
    span~ : Span
  )
  /// Autolink <url>
  Autolink(url~ : String, is_email~ : Bool, span~ : Span)
  /// Image ![alt](url "title")
  Image(alt~ : String, url~ : String, title~ : String, span~ : Span)
  /// Reference image ![alt][ref]
  RefImage(
    alt~ : String,
    label~ : String,
    style~ : ReferenceStyle,
    span~ : Span
  )
  /// Raw inline HTML
  HtmlInline(html~ : String, span~ : Span)
  /// Footnote reference [^label] (GFM)
  FootnoteReference(label~ : String, span~ : Span)
}

///|
/// Hard break style
pub(all) enum HardBreakStyle {
  TwoSpaces // "  \n"
  Backslash // "\\\n"
} derive(Eq, Debug)

///|
pub impl Show for TableAlign with fn output(self : TableAlign, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl Show for HardBreakStyle with fn output(
  self : HardBreakStyle,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

// =============================================================================
// Reference Definitions
// =============================================================================

///|
/// Link reference definition [label]: url "title"
pub(all) struct LinkDefinition {
  label : String
  url : String
  title : String
  span : Span
}
