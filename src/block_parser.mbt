///| Block-level markdown parser.

///| Line-driven container algorithm from the CommonMark spec appendix: for each

///| line we first check which already-open blocks it still belongs to, then look

///| for new block starts, then hand the rest of the line to the deepest open

///| block. Blocks are built in a mutable tree and converted to the CST once the

///| document is complete.

///|
/// Parse result
pub(all) struct ParseResult {
  document : Document
  definitions : Array[LinkDefinition]
}

///|
/// Number of columns a tab advances to.
const TabStop : Int = 4

///|
/// Indentation at which a line becomes an indented code block.
const CodeIndent : Int = 4

///|
/// Parse markdown source into CST.
///
/// `strict` is accepted for backwards compatibility; the parser always follows
/// the CommonMark rules now.
pub fn parse(
  source : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> ParseResult {
  ignore(strict)
  BlockParser::new(source, wikilinks).parse_document()
}

///|
/// The kind of an open block.
priv enum NodeKind {
  DocNode
  BlockQuoteNode
  ListNode
  ItemNode
  ParagraphNode
  HeadingNode
  ThematicBreakNode
  FencedCodeNode
  MathBlockNode
  DirectiveNode
  IndentedCodeNode
  HtmlBlockNode
  TableNode
  FootnoteDefNode
  BlankLinesNode
} derive(Eq)

///|
/// CommonMark's seven HTML block start conditions.
priv enum HtmlBlockKind {
  None
  RawText
  Comment
  ProcessingInstruction
  Declaration
  Cdata
  BlockTag
  CompleteTag
} derive(Eq)

///|
fn HtmlBlockKind::ends_on_blank_line(self : HtmlBlockKind) -> Bool {
  match self {
    HtmlBlockKind::BlockTag | HtmlBlockKind::CompleteTag => true
    _ => false
  }
}

///|
/// A block under construction.
priv struct Node {
  mut kind : NodeKind
  mut parent : Node?
  children : Array[Node]
  /// Raw content lines, for blocks that accept lines.
  lines : Array[String]
  /// Source offset each entry of `lines` was taken from, so that positions
  /// inside the joined content can be mapped back to the document.
  line_starts : Array[Int]
  start : Int
  mut end : Int
  mut open : Bool
  mut last_line_blank : Bool
  mut level : Int
  mut style : HeadingStyle
  mut closing_hashes : Int
  mut marker : Char
  mut marker_count : Int
  mut fence_length : Int
  mut fence_indent : Int
  mut info : String
  /// Set while a fenced code block's info-string line has yet to be skipped.
  mut info_pending : Bool
  mut html_kind : HtmlBlockKind
  mut ordered : Bool
  mut list_start : Int
  mut delim : Char
  mut tight : Bool
  mut item_marker_offset : Int
  mut item_padding : Int
  mut checked : Bool?
  mut alignments : Array[TableAlign]
  mut label : String
}

///|
fn Node::new(kind : NodeKind, start : Int) -> Node {
  {
    kind,
    parent: None,
    children: [],
    lines: [],
    line_starts: [],
    start,
    end: start,
    open: true,
    last_line_blank: false,
    level: 0,
    style: HeadingStyle::Atx,
    closing_hashes: 0,
    marker: ' ',
    marker_count: 0,
    fence_length: 0,
    fence_indent: 0,
    info: "",
    info_pending: false,
    html_kind: HtmlBlockKind::None,
    ordered: false,
    list_start: 1,
    delim: '.',
    tight: true,
    item_marker_offset: 0,
    item_padding: 0,
    checked: None,
    alignments: [],
    label: "",
  }
}

///|
/// Map an offset inside `joined_lines(node)` back to a document offset.
fn source_offset_in(node : Node, content_offset : Int) -> Int {
  let mut remaining = content_offset
  for i, line in node.lines {
    let len = line.length()
    if remaining <= len {
      return node.line_starts[i] + remaining
    }
    remaining = remaining - (len + 1)
  }
  node.end
}

///|
/// Total indentation a continuation line of this list item must have.
fn Node::item_indent(self : Node) -> Int {
  self.item_marker_offset + self.item_padding
}

///|
/// Block parser state
priv struct BlockParser {
  source : String
  len : Int
  wikilinks : Bool
  definitions : Array[LinkDefinition]
  /// Inline content is parsed only after the whole document has been read, so
  /// that every link reference definition is already in scope. Each entry pairs
  /// the (still empty) children array of a block with its raw source.
  pending_inlines : Array[(Array[Inline], String)]
  doc : Node
  /// The deepest block left open by the previous line.
  mut tip : Node
  mut line : String
  mut line_len : Int
  mut line_start : Int
  mut line_end : Int
  mut offset : Int
  mut column : Int
  mut next_nonspace : Int
  mut next_nonspace_column : Int
  mut indent : Int
  mut blank : Bool
  mut partially_consumed_tab : Bool
}

///|
fn BlockParser::new(source : String, wikilinks : Bool) -> BlockParser {
  let doc = Node::new(NodeKind::DocNode, 0)
  {
    source,
    len: source.length(),
    wikilinks,
    definitions: [],
    pending_inlines: [],
    doc,
    tip: doc,
    line: "",
    line_len: 0,
    line_start: 0,
    line_end: 0,
    offset: 0,
    column: 0,
    next_nonspace: 0,
    next_nonspace_column: 0,
    indent: 0,
    blank: false,
    partially_consumed_tab: false,
  }
}

// =============================================================================
// Deferred inline parsing
// =============================================================================

///|
/// Reserve an inline children array; it is filled in by `resolve_inlines`
/// once the document's link reference definitions are all known.
fn BlockParser::parse_inline_content(
  self : BlockParser,
  content : String,
) -> Array[Inline] {
  let children : Array[Inline] = []
  self.pending_inlines.push((children, content))
  children
}

///|
/// Index the link reference definitions collected while parsing blocks. The
/// first definition of a label wins.
fn BlockParser::definition_map(
  self : BlockParser,
) -> Map[String, LinkDefinition] {
  let defs : Map[String, LinkDefinition] = Map(
    [],
    capacity=self.definitions.length(),
  )
  for def in self.definitions {
    let key = normalize_label(def.label)
    if !defs.contains(key) {
      defs[key] = def
    }
  }
  defs
}

///|
/// Parse every deferred inline run now that definitions are known.
fn BlockParser::resolve_inlines(self : BlockParser) -> Unit {
  let defs = self.definition_map()
  for entry in self.pending_inlines {
    let (children, content) = entry
    for inline in parse_inlines_with_defs(content, defs, self.wikilinks) {
      children.push(inline)
    }
  }
}

// =============================================================================
// Line scanning helpers
// =============================================================================

///|
fn BlockParser::peek_line(self : BlockParser, i : Int) -> UInt16 {
  if i >= 0 && i < self.line_len {
    self.line.unsafe_get(i)
  } else {
    0
  }
}

///|
fn is_space_or_tab(c : UInt16) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// Move `count` characters (or columns, when `columns` is set) forward,
/// expanding tabs to the next tab stop.
fn BlockParser::advance_offset(
  self : BlockParser,
  count : Int,
  columns : Bool,
) -> Unit {
  let mut remaining = count
  while remaining > 0 && self.offset < self.line_len {
    if self.line.unsafe_get(self.offset) == '\t' {
      let chars_to_tab = TabStop - self.column % TabStop
      if columns {
        self.partially_consumed_tab = chars_to_tab > remaining
        let chars_to_advance = if remaining < chars_to_tab {
          remaining
        } else {
          chars_to_tab
        }
        self.column = self.column + chars_to_advance
        if !self.partially_consumed_tab {
          self.offset = self.offset + 1
        }
        remaining = remaining - chars_to_advance
      } else {
        self.partially_consumed_tab = false
        self.column = self.column + chars_to_tab
        self.offset = self.offset + 1
        remaining = remaining - 1
      }
    } else {
      self.partially_consumed_tab = false
      self.offset = self.offset + 1
      self.column = self.column + 1
      remaining = remaining - 1
    }
  }
}

///|
fn BlockParser::find_next_nonspace(self : BlockParser) -> Unit {
  let mut chars_to_tab = TabStop - self.column % TabStop
  if self.next_nonspace <= self.offset {
    self.next_nonspace = self.offset
    self.next_nonspace_column = self.column
    while self.next_nonspace < self.line_len {
      let c = self.line.unsafe_get(self.next_nonspace)
      if c == ' ' {
        self.next_nonspace = self.next_nonspace + 1
        self.next_nonspace_column = self.next_nonspace_column + 1
        chars_to_tab = chars_to_tab - 1
        if chars_to_tab == 0 {
          chars_to_tab = TabStop
        }
      } else if c == '\t' {
        self.next_nonspace = self.next_nonspace + 1
        self.next_nonspace_column = self.next_nonspace_column + chars_to_tab
        chars_to_tab = TabStop
      } else {
        break
      }
    }
  }
  self.indent = self.next_nonspace_column - self.column
  self.blank = self.next_nonspace >= self.line_len
}

///|
/// The remainder of the current line, with a partially consumed tab expanded
/// into the spaces it stands for.
fn BlockParser::rest_of_line(self : BlockParser) -> String {
  let mut from = self.offset
  if !self.partially_consumed_tab {
    return self.line.unsafe_substring(start=from, end=self.line_len)
  }
  let buf = StringBuilder()
  from = from + 1
  let chars_to_tab = TabStop - self.column % TabStop
  for i = 0; i < chars_to_tab; i = i + 1 {
    buf.write_char(' ')
  }
  buf.write_string(self.line.unsafe_substring(start=from, end=self.line_len))
  buf.to_string()
}

// =============================================================================
// Tree manipulation
// =============================================================================

///|
fn can_contain(parent : NodeKind, child : NodeKind) -> Bool {
  match parent {
    NodeKind::DocNode
    | NodeKind::BlockQuoteNode
    | NodeKind::DirectiveNode
    | NodeKind::FootnoteDefNode => child != NodeKind::ItemNode
    NodeKind::ItemNode => child != NodeKind::ItemNode
    NodeKind::ListNode => child == NodeKind::ItemNode
    _ => false
  }
}

///|
/// Whether a block keeps absorbing raw lines.
fn accepts_lines(kind : NodeKind) -> Bool {
  kind == NodeKind::ParagraphNode ||
  kind == NodeKind::HeadingNode ||
  kind == NodeKind::FencedCodeNode ||
  kind == NodeKind::MathBlockNode ||
  kind == NodeKind::IndentedCodeNode ||
  kind == NodeKind::HtmlBlockNode ||
  kind == NodeKind::TableNode
}

///|
/// Close `node` and return its parent.
fn BlockParser::close(self : BlockParser, node : Node) -> Node {
  if node.open {
    node.open = false
    // A container ends where its last child does; leaf blocks have already
    // recorded the end of every line they took.
    match node.children.last() {
      Some(child) => if child.end > node.end { node.end = child.end }
      None => ()
    }
  }
  match node.parent {
    Some(parent) => parent
    None => self.doc
  }
}

///|
/// Close blocks until `parent` can contain `kind`, then add the child.
fn BlockParser::add_child(
  self : BlockParser,
  parent : Node,
  kind : NodeKind,
  start : Int,
) -> Node {
  let mut p = parent
  while !can_contain(p.kind, kind) {
    p = self.close(p)
  }
  let node = Node::new(kind, start)
  node.parent = Some(p)
  p.children.push(node)
  node
}

// =============================================================================
// Document parsing
// =============================================================================

///|
fn BlockParser::parse_document(self : BlockParser) -> ParseResult {
  let frontmatter = self.try_parse_frontmatter()
  let mut pos = match frontmatter {
    Some(fm) => fm.span.to
    None => 0
  }
  let mut done = pos >= self.len
  while !done {
    let (text, next) = self.read_line(pos)
    self.line = text
    self.line_len = text.length()
    self.line_start = pos
    self.line_end = next
    self.process_line()
    done = next >= self.len
    pos = next
  }
  self.line_start = self.len
  let mut node = self.tip
  while node.open {
    node = self.close(node)
  }
  self.doc.open = false
  self.doc.end = self.len
  self.finalize_lists(self.doc)
  self.insert_blank_line_nodes(
    match frontmatter {
      Some(fm) => fm.span.to
      None => 0
    },
  )
  let children = self.to_blocks(self.doc.children)
  self.resolve_inlines()
  // These extension recognizers rebuild container subtrees. Skip those
  // passes when the source cannot contain their opening marker.
  let children = if self.source.contains("[!") {
    recognize_alerts(children)
  } else {
    children
  }
  let children = if self.source.contains("{") {
    recognize_attributes(children)
  } else {
    children
  }
  let document = Document::{
    frontmatter,
    children,
    definitions: self.definitions,
    span: Span::new(0, self.len),
  }
  { document, definitions: self.definitions }
}

///|
/// Attach standalone attribute-list paragraphs to the preceding block.
fn recognize_attributes(blocks : Array[Block]) -> Array[Block] {
  let result : Array[Block] = []
  for block in blocks {
    match attributes_from_block(block) {
      Some((attributes, attr_span)) => {
        let blanks : Array[Block] = []
        while result.last() is Some(Block::BlankLines(..)) {
          match result.pop() {
            Some(blank) => blanks.push(blank)
            None => ()
          }
        }
        match result.pop() {
          Some(previous) => {
            let span = Span::new(
              previous.get_span_internal().from,
              attr_span.to,
            )
            result.push(Block::Attributed(block=previous, attributes~, span~))
          }
          None => {
            for i = blanks.length() - 1; i >= 0; i = i - 1 {
              result.push(blanks[i])
            }
            result.push(block)
          }
        }
      }
      None => result.push(recognize_attributes_in_block(block))
    }
  }
  result
}

///|
/// Recurse through block containers before looking for attached attributes.
fn recognize_attributes_in_block(block : Block) -> Block {
  match block {
    Block::Blockquote(children~, span~, leading_trivia~, trailing_trivia~) =>
      Block::Blockquote(
        children=recognize_attributes(children),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Alert(kind~, children~, span~, leading_trivia~, trailing_trivia~) =>
      Block::Alert(
        kind~,
        children=recognize_attributes(children),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Directive(
      name~,
      meta~,
      children~,
      fence_length~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::Directive(
        name~,
        meta~,
        children=recognize_attributes(children),
        fence_length~,
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Block::FootnoteDefinition(
      label~,
      children~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::FootnoteDefinition(
        label~,
        children=recognize_attributes(children),
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    Block::BulletList(
      marker~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) => {
      let nested : Array[ListItem] = []
      for item in items {
        nested.push({ ..item, children: recognize_attributes(item.children) })
      }
      Block::BulletList(
        marker~,
        tight~,
        items=nested,
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    }
    Block::OrderedList(
      start~,
      delimiter~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) => {
      let nested : Array[ListItem] = []
      for item in items {
        nested.push({ ..item, children: recognize_attributes(item.children) })
      }
      Block::OrderedList(
        start~,
        delimiter~,
        tight~,
        items=nested,
        span~,
        leading_trivia~,
        trailing_trivia~,
      )
    }
    _ => block
  }
}

///|
/// Extract attributes only from a paragraph consisting of one text node.
fn attributes_from_block(block : Block) -> (Array[MarkdownAttribute], Span)? {
  guard block is Block::Paragraph(children~, span~, ..) else { return None }
  guard children.length() == 1 else { return None }
  guard children[0] is Inline::Text(content~, ..) else { return None }
  // Attribute-only paragraphs must end in `}`. Most paragraphs do not, so do
  // not allocate a trimmed copy merely to reject them.
  guard content.length() > 0 && content.unsafe_get(content.length() - 1) == '}' else {
    return None
  }
  match parse_markdown_attributes(content) {
    Some(attributes) => Some((attributes, span))
    None => None
  }
}

///|
/// Internal span accessor used before incremental.mbt's public helper scope.
fn Block::get_span_internal(self : Block) -> Span {
  match self {
    Block::ThematicBreak(span~, ..)
    | Block::Heading(span~, ..)
    | Block::Paragraph(span~, ..)
    | Block::FencedCode(span~, ..)
    | Block::MathBlock(span~, ..)
    | Block::Directive(span~, ..)
    | Block::DefinitionList(span~, ..)
    | Block::Attributed(span~, ..)
    | Block::IndentedCode(span~, ..)
    | Block::Blockquote(span~, ..)
    | Block::Alert(span~, ..)
    | Block::BulletList(span~, ..)
    | Block::OrderedList(span~, ..)
    | Block::HtmlBlock(span~, ..)
    | Block::Table(span~, ..)
    | Block::BlankLines(span~, ..)
    | Block::FootnoteDefinition(span~, ..) => span
  }
}

///|
/// Parse the marker used by GitHub alert blockquotes.
fn alert_kind_from_marker(marker : String) -> AlertKind? {
  match marker.to_lower() {
    "[!note]" => Some(AlertKind::Note)
    "[!tip]" => Some(AlertKind::Tip)
    "[!important]" => Some(AlertKind::Important)
    "[!warning]" => Some(AlertKind::Warning)
    "[!caution]" => Some(AlertKind::Caution)
    _ => None
  }
}

///|
/// Turn the GitHub alert blockquote convention into a semantic CST node.
fn recognize_alerts(blocks : Array[Block]) -> Array[Block] {
  let result : Array[Block] = []
  for block in blocks {
    match block {
      Block::Blockquote(children~, span~, leading_trivia~, trailing_trivia~) => {
        let nested = recognize_alerts(children)
        match extract_alert(nested) {
          Some((kind, body)) =>
            result.push(
              Block::Alert(
                kind~,
                children=body,
                span~,
                leading_trivia~,
                trailing_trivia~,
              ),
            )
          None =>
            result.push(
              Block::Blockquote(
                children=nested,
                span~,
                leading_trivia~,
                trailing_trivia~,
              ),
            )
        }
      }
      Block::Alert(kind~, children~, span~, leading_trivia~, trailing_trivia~) =>
        result.push(
          Block::Alert(
            kind~,
            children=recognize_alerts(children),
            span~,
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::Directive(
        name~,
        meta~,
        children~,
        fence_length~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::Directive(
            name~,
            meta~,
            children=recognize_alerts(children),
            fence_length~,
            span~,
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::FootnoteDefinition(
        label~,
        children~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) =>
        result.push(
          Block::FootnoteDefinition(
            label~,
            children=recognize_alerts(children),
            span~,
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      Block::BulletList(
        marker~,
        tight~,
        items~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) => {
        let nested : Array[ListItem] = []
        for item in items {
          nested.push({ ..item, children: recognize_alerts(item.children) })
        }
        result.push(
          Block::BulletList(
            marker~,
            tight~,
            items=nested,
            span~,
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      }
      Block::OrderedList(
        start~,
        delimiter~,
        tight~,
        items~,
        span~,
        leading_trivia~,
        trailing_trivia~
      ) => {
        let nested : Array[ListItem] = []
        for item in items {
          nested.push({ ..item, children: recognize_alerts(item.children) })
        }
        result.push(
          Block::OrderedList(
            start~,
            delimiter~,
            tight~,
            items=nested,
            span~,
            leading_trivia~,
            trailing_trivia~,
          ),
        )
      }
      _ => result.push(block)
    }
  }
  result
}

///|
/// Remove an alert marker from the first paragraph and return its body.
fn extract_alert(children : Array[Block]) -> (AlertKind, Array[Block])? {
  guard children.length() > 0 else { return None }
  guard children[0]
    is Block::Paragraph(
      children=inlines,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) else {
    return None
  }
  guard inlines.length() > 0 else { return None }
  guard inlines[0] is Inline::Text(content=marker, ..) else { return None }
  guard alert_kind_from_marker(marker) is Some(kind) else { return None }
  let body : Array[Block] = []
  let block_start = 1
  if inlines.length() >= 2 && inlines[1] is Inline::SoftBreak(..) {
    let rest : Array[Inline] = []
    for i = 2; i < inlines.length(); i = i + 1 {
      rest.push(inlines[i])
    }
    if !rest.is_empty() {
      body.push(
        Block::Paragraph(
          children=rest,
          span~,
          leading_trivia~,
          trailing_trivia~,
        ),
      )
    }
  } else if inlines.length() != 1 {
    return None
  }
  for i = block_start; i < children.length(); i = i + 1 {
    body.push(children[i])
  }
  Some((kind, body))
}

///|
/// Read the line starting at `pos`, returning its text (without the line
/// ending) and the offset of the next line.
fn BlockParser::read_line(self : BlockParser, pos : Int) -> (String, Int) {
  let i = find_line_end(self.source, pos, self.len)
  let text = self.source.unsafe_substring(start=pos, end=i)
  let mut next = i
  if next < self.len {
    if self.source.unsafe_get(next) == '\r' {
      next = next + 1
      if next < self.len && self.source.unsafe_get(next) == '\n' {
        next = next + 1
      }
    } else {
      next = next + 1
    }
  }
  (sanitize_line(text), next)
}

///|
/// The spec replaces U+0000 with the replacement character.
fn sanitize_line(text : String) -> String {
  let len = text.length()
  let mut has_nul = false
  for i = 0; i < len; i = i + 1 {
    if text.unsafe_get(i) == 0 {
      has_nul = true
      break
    }
  }
  if !has_nul {
    return text
  }
  let buf = StringBuilder()
  for i = 0; i < len; i = i + 1 {
    if text.unsafe_get(i) == 0 {
      buf.write_string(ReplacementChar)
    } else {
      buf.write_string(text.unsafe_substring(start=i, end=i + 1))
    }
  }
  buf.to_string()
}

///|
fn BlockParser::process_line(self : BlockParser) -> Unit {
  self.offset = 0
  self.column = 0
  self.next_nonspace = 0
  self.next_nonspace_column = 0
  self.blank = false
  self.partially_consumed_tab = false
  let (last_matched, all_matched, consumed) = self.check_open_blocks()
  if consumed {
    return
  }
  let container = self.open_new_blocks(last_matched, all_matched)
  self.add_text(container, last_matched, all_matched)
}

///|
/// Walk the open blocks, checking each still contains this line. Returns the
/// deepest matching container, whether every open block matched, and whether
/// the line was already consumed (a closing code fence).
fn BlockParser::check_open_blocks(self : BlockParser) -> (Node, Bool, Bool) {
  let mut container = self.doc
  let mut all_matched = true
  while container.children.length() > 0 {
    let child = container.children[container.children.length() - 1]
    if !child.open {
      break
    }
    container = child
    self.find_next_nonspace()
    match container.kind {
      NodeKind::BlockQuoteNode =>
        if self.indent <= 3 && self.peek_line(self.next_nonspace) == '>' {
          self.advance_offset(self.indent + 1, true)
          if is_space_or_tab(self.peek_line(self.offset)) {
            self.advance_offset(1, true)
          }
        } else {
          all_matched = false
        }
      NodeKind::ItemNode =>
        if self.indent >= container.item_indent() {
          self.advance_offset(container.item_indent(), true)
        } else if self.blank && container.children.length() > 0 {
          self.advance_offset(self.next_nonspace - self.offset, false)
        } else {
          all_matched = false
        }
      NodeKind::FootnoteDefNode | NodeKind::IndentedCodeNode =>
        if self.indent >= CodeIndent {
          self.advance_offset(CodeIndent, true)
        } else if self.blank {
          self.advance_offset(self.next_nonspace - self.offset, false)
        } else {
          all_matched = false
        }
      NodeKind::FencedCodeNode =>
        if self.indent <= 3 && self.scan_close_code_fence(container) {
          let _ = self.close(container)
          return (container, false, true)
        } else {
          let mut i = container.fence_indent
          while i > 0 && is_space_or_tab(self.peek_line(self.offset)) {
            self.advance_offset(1, true)
            i = i - 1
          }
        }
      NodeKind::MathBlockNode =>
        if self.indent <= 3 && self.scan_close_math_fence(container) {
          let _ = self.close(container)
          return (container, false, true)
        }
      NodeKind::DirectiveNode =>
        if self.indent <= 3 && self.scan_close_directive_fence(container) {
          let _ = self.close(container)
          return (container, false, true)
        }
      NodeKind::HtmlBlockNode =>
        if self.blank && container.html_kind.ends_on_blank_line() {
          all_matched = false
        }
      NodeKind::ParagraphNode => if self.blank { all_matched = false }
      NodeKind::TableNode =>
        // A body row may omit pipes; a blank line or a newly opened block
        // closes the table, as required by GFM.
        if self.blank {
          all_matched = false
        }
      NodeKind::HeadingNode | NodeKind::ThematicBreakNode => all_matched = false
      _ => ()
    }
    if !all_matched {
      container = match container.parent {
        Some(p) => p
        None => self.doc
      }
      break
    }
  }
  (container, all_matched, false)
}

///|
/// Look for block starts and open the blocks this line begins.
fn BlockParser::open_new_blocks(
  self : BlockParser,
  last_matched : Node,
  all_matched : Bool,
) -> Node {
  let mut container = last_matched
  let mut maybe_lazy = self.tip.kind == NodeKind::ParagraphNode
  while container.kind != NodeKind::FencedCodeNode &&
        container.kind != NodeKind::MathBlockNode &&
        container.kind != NodeKind::HtmlBlockNode &&
        container.kind != NodeKind::IndentedCodeNode {
    self.find_next_nonspace()
    let indented = self.indent >= CodeIndent
    if !indented && self.peek_line(self.next_nonspace) == '>' {
      let start = self.line_start + self.next_nonspace
      self.advance_offset(self.indent + 1, true)
      if is_space_or_tab(self.peek_line(self.offset)) {
        self.advance_offset(1, true)
      }
      container = self.add_child(container, NodeKind::BlockQuoteNode, start)
    } else if !indented && self.try_atx_heading(container) is Some(node) {
      container = node
    } else if !indented && self.try_open_code_fence(container) is Some(node) {
      container = node
    } else if !indented && self.try_open_math_block(container) is Some(node) {
      container = node
    } else if !indented && self.try_open_directive(container) is Some(node) {
      container = node
    } else if !indented && self.try_html_block_start(container) is Some(node) {
      container = node
    } else if !indented &&
      container.kind == NodeKind::ParagraphNode &&
      self.try_setext_heading(container) {
      self.advance_offset(self.line_len - self.offset, false)
    } else if !indented &&
      !(container.kind == NodeKind::ParagraphNode && !all_matched) &&
      self.try_thematic_break(container) is Some(node) {
      container = node
    } else if !indented && self.try_footnote_definition(container) is Some(node) {
      container = node
    } else if (!indented || container.kind == NodeKind::ListNode) &&
      self.indent < CodeIndent &&
      self.try_list_item(container) is Some(node) {
      container = node
    } else if indented && !maybe_lazy && !self.blank {
      self.advance_offset(CodeIndent, true)
      container = self.add_child(
        container,
        NodeKind::IndentedCodeNode,
        self.line_start + self.offset,
      )
    } else {
      break
    }
    if accepts_lines(container.kind) {
      break
    }
    maybe_lazy = false
  }
  container
}

///|
/// Record one content line together with where it came from.
fn BlockParser::push_line(self : BlockParser, node : Node) -> Unit {
  node.lines.push(self.rest_of_line())
  node.line_starts.push(self.line_start + self.offset)
}

///|
/// Attach the remainder of the line to the deepest open block.
fn BlockParser::add_text(
  self : BlockParser,
  container : Node,
  last_matched : Node,
  all_matched : Bool,
) -> Unit {
  self.find_next_nonspace()
  if self.blank && container.children.length() > 0 {
    container.children[container.children.length() - 1].last_line_blank = true
  }
  let last_line_blank = self.blank &&
    !(container.kind == NodeKind::BlockQuoteNode ||
    container.kind == NodeKind::HeadingNode ||
    container.kind == NodeKind::ThematicBreakNode ||
    container.kind == NodeKind::FencedCodeNode ||
    container.kind == NodeKind::MathBlockNode ||
    (
      container.kind == NodeKind::ItemNode &&
      container.children.is_empty() &&
      container.start >= self.line_start
    ))
  container.last_line_blank = last_line_blank
  let mut walk = container.parent
  let mut walking = true
  while walking {
    match walk {
      Some(node) => {
        node.last_line_blank = last_line_blank
        walk = node.parent
      }
      None => walking = false
    }
  }
  let opened_new = !physical_equal(container, last_matched)
  if !opened_new &&
    !all_matched &&
    !self.blank &&
    self.tip.kind == NodeKind::ParagraphNode &&
    self.tip.open {
    // Lazy continuation of the paragraph left open by the previous line.
    self.advance_offset(self.next_nonspace - self.offset, false)
    self.push_line(self.tip)
    self.tip.end = self.line_end
    return
  }
  while !physical_equal(self.tip, last_matched) && self.tip.open {
    self.tip = self.close(self.tip)
  }
  let mut current = container
  if container.kind == NodeKind::FencedCodeNode ||
    container.kind == NodeKind::IndentedCodeNode {
    if container.info_pending {
      container.info_pending = false
    } else {
      self.push_line(container)
    }
    container.end = self.line_end
  } else if container.kind == NodeKind::HtmlBlockNode {
    self.push_line(container)
    container.end = self.line_end
    if self.html_block_ends(container) {
      current = self.close(container)
    }
  } else if self.blank {
    ()
  } else if accepts_lines(container.kind) {
    self.advance_offset(self.next_nonspace - self.offset, false)
    if container.kind == NodeKind::HeadingNode &&
      container.style == HeadingStyle::Atx {
      let (text, hashes) = chop_trailing_hashes(self.rest_of_line())
      container.lines.push(text)
      container.line_starts.push(self.line_start + self.offset)
      container.closing_hashes = hashes
    } else {
      self.push_line(container)
      if container.kind == NodeKind::ParagraphNode {
        maybe_start_table(container)
      }
    }
    container.end = self.line_end
  } else {
    let para = self.add_child(
      container,
      NodeKind::ParagraphNode,
      self.line_start + self.next_nonspace,
    )
    self.advance_offset(self.next_nonspace - self.offset, false)
    self.push_line(para)
    para.end = self.line_end
    current = para
  }
  self.tip = current
}

///|
/// Re-create the runs of blank lines that separate top-level blocks, so the
/// CST can round-trip the document's vertical spacing.
fn BlockParser::insert_blank_line_nodes(
  self : BlockParser,
  doc_start : Int,
) -> Unit {
  let children = self.doc.children
  let rebuilt : Array[Node] = []
  let mut pos = doc_start
  for child in children {
    let line_start = self.line_start_of(child.start)
    match self.blank_lines_node(pos, line_start) {
      Some(node) => rebuilt.push(node)
      None => ()
    }
    rebuilt.push(child)
    pos = child.end
  }
  match self.blank_lines_node(pos, self.len) {
    Some(node) => rebuilt.push(node)
    None => ()
  }
  children.clear()
  for node in rebuilt {
    children.push(node)
  }
}

///|
fn BlockParser::blank_lines_node(
  self : BlockParser,
  from : Int,
  to : Int,
) -> Node? {
  guard to > from else { return None }
  let mut pos = from
  let mut count = 0
  while pos < to {
    let (line, next) = self.read_line(pos)
    if is_blank_text(line) {
      count = count + 1
    }
    if next <= pos {
      break
    }
    pos = next
  }
  guard count > 0 else { return None }
  let node = Node::new(NodeKind::BlankLinesNode, from)
  node.parent = Some(self.doc)
  node.marker_count = count
  node.end = to
  node.open = false
  Some(node)
}

///|
fn BlockParser::line_start_of(self : BlockParser, pos : Int) -> Int {
  let mut i = if pos > self.len { self.len } else { pos }
  while i > 0 && self.source.unsafe_get(i - 1) != '\n' {
    i = i - 1
  }
  i
}

// =============================================================================
// List tightness
// =============================================================================

///|
fn ends_with_blank_line(node : Node) -> Bool {
  if node.last_line_blank {
    return true
  }
  if node.kind == NodeKind::ListNode || node.kind == NodeKind::ItemNode {
    match node.children.last() {
      Some(child) => return ends_with_blank_line(child)
      None => ()
    }
  }
  false
}

///|
/// A list is loose when any of its items is followed by a blank line, or when
/// any item contains blocks separated by one.
fn BlockParser::finalize_lists(self : BlockParser, node : Node) -> Unit {
  for child in node.children {
    self.finalize_lists(child)
  }
  if node.kind != NodeKind::ListNode {
    return
  }
  let items = node.children
  for i, item in items {
    if ends_with_blank_line(item) && i + 1 < items.length() {
      node.tight = false
      break
    }
    let subitems = item.children
    for j, sub in subitems {
      if (i + 1 < items.length() || j + 1 < subitems.length()) &&
        ends_with_blank_line(sub) {
        node.tight = false
        break
      }
    }
    if !node.tight {
      break
    }
  }
}

// =============================================================================
// Conversion to the CST
// =============================================================================

///|
fn joined_lines(node : Node) -> String {
  let buf = StringBuilder()
  for i, line in node.lines {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_string(line)
  }
  buf.to_string()
}

///|
fn code_lines(node : Node) -> String {
  let buf = StringBuilder()
  for line in node.lines {
    buf.write_string(line)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Indented code blocks drop the blank lines they end with.
fn trimmed_code_lines(node : Node) -> String {
  let mut end = node.lines.length()
  while end > 0 && is_blank_text(node.lines[end - 1]) {
    end = end - 1
  }
  let buf = StringBuilder()
  for i = 0; i < end; i = i + 1 {
    buf.write_string(node.lines[i])
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
fn is_blank_text(line : String) -> Bool {
  for i = 0; i < line.length(); i = i + 1 {
    let c = line.unsafe_get(i)
    if !is_space_or_tab(c) && c != '\n' && c != '\r' {
      return false
    }
  }
  true
}

///|
fn BlockParser::to_blocks(
  self : BlockParser,
  nodes : Array[Node],
) -> Array[Block] {
  let blocks : Array[Block] = []
  for node in nodes {
    match self.to_block(node) {
      Some(block) => blocks.push(block)
      None => ()
    }
  }
  blocks
}

///|
fn BlockParser::to_block(self : BlockParser, node : Node) -> Block? {
  let span = Span::new(node.start, node.end)
  let empty = Trivia::empty()
  match node.kind {
    NodeKind::BlankLinesNode =>
      Some(Block::BlankLines(count=node.marker_count, span~))
    NodeKind::ParagraphNode => {
      let content = self.strip_link_definitions(node)
      if is_blank_text(content) {
        return None
      }
      match self.try_definition_list(content, span) {
        Some(list) => return Some(list)
        None => ()
      }
      Some(
        Block::Paragraph(
          children=self.parse_inline_content(content),
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    }
    NodeKind::HeadingNode => {
      let content = if node.style == HeadingStyle::Setext {
        self.strip_link_definitions(node)
      } else {
        joined_lines(node)
      }
      Some(
        Block::Heading(
          level=node.level,
          style=node.style,
          children=self.parse_inline_content(content),
          closing_hashes=node.closing_hashes,
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    }
    NodeKind::ThematicBreakNode =>
      Some(
        Block::ThematicBreak(
          marker=node.marker,
          count=node.marker_count,
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::FencedCodeNode =>
      Some(
        Block::FencedCode(
          fence_marker=if node.marker == '~' {
            FenceMarker::Tilde
          } else {
            FenceMarker::Backtick
          },
          fence_length=node.fence_length,
          info=node.info,
          code=code_lines(node),
          indent=node.fence_indent,
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::MathBlockNode =>
      Some(
        Block::MathBlock(
          value=code_lines(node),
          fence_length=node.fence_length,
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::DirectiveNode =>
      Some(
        Block::Directive(
          name=node.label,
          meta=node.info,
          children=self.to_blocks(node.children),
          fence_length=node.fence_length,
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::IndentedCodeNode =>
      Some(
        Block::IndentedCode(
          code=trimmed_code_lines(node),
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::HtmlBlockNode =>
      Some(
        Block::HtmlBlock(
          html=code_lines(node),
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::BlockQuoteNode =>
      Some(
        Block::Blockquote(
          children=self.to_blocks(node.children),
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::FootnoteDefNode =>
      Some(
        Block::FootnoteDefinition(
          label=node.label,
          children=self.to_blocks(node.children),
          span~,
          leading_trivia=empty,
          trailing_trivia=empty,
        ),
      )
    NodeKind::TableNode => self.table_to_block(node, span)
    NodeKind::ListNode => {
      let items : Array[ListItem] = []
      for child in node.children {
        items.push({
          children: self.to_blocks(child.children),
          checked: child.checked,
          marker_offset: child.item_marker_offset,
          content_offset: child.item_padding,
          span: Span::new(child.start, child.end),
        })
      }
      if node.ordered {
        Some(
          Block::OrderedList(
            start=node.list_start,
            delimiter=if node.delim == ')' {
              OrderedDelimiter::Paren
            } else {
              OrderedDelimiter::Dot
            },
            tight=node.tight,
            items~,
            span~,
            leading_trivia=empty,
            trailing_trivia=empty,
          ),
        )
      } else {
        Some(
          Block::BulletList(
            marker=match node.marker {
              '*' => BulletMarker::Asterisk
              '+' => BulletMarker::Plus
              _ => BulletMarker::Dash
            },
            tight=node.tight,
            items~,
            span~,
            leading_trivia=empty,
            trailing_trivia=empty,
          ),
        )
      }
    }
    _ => None
  }
}

///|
/// Recognize the compact definition-list extension inside one paragraph.
fn BlockParser::try_definition_list(
  self : BlockParser,
  content : String,
  span : Span,
) -> Block? {
  // A definition list requires at least two physical lines. This keeps the
  // common one-line paragraph path allocation-free.
  guard content.contains("\n") else { return None }
  let lines : Array[String] = []
  for line in content.split("\n") {
    lines.push(line.to_owned())
  }
  guard lines.length() >= 2 else { return None }
  let items : Array[DefinitionItem] = []
  let mut i = 0
  while i < lines.length() {
    let term = lines[i].trim(chars=" \t\r").to_owned()
    guard !term.is_empty() && !term.has_prefix(":") else { return None }
    i = i + 1
    let definitions : Array[Array[Inline]] = []
    while i < lines.length() {
      let line = lines[i].trim(chars=" \t\r").to_owned()
      if !line.has_prefix(":") {
        break
      }
      guard line.length() == 1 || is_space_or_tab(line.unsafe_get(1)) else {
        return None
      }
      let definition = line
        .unsafe_substring(start=1, end=line.length())
        .trim(chars=" \t")
        .to_owned()
      definitions.push(self.parse_inline_content(definition))
      i = i + 1
    }
    guard !definitions.is_empty() else { return None }
    items.push({ term: self.parse_inline_content(term), definitions })
  }
  Some(
    Block::DefinitionList(
      items~,
      span~,
      leading_trivia=Trivia::empty(),
      trailing_trivia=Trivia::empty(),
    ),
  )
}

// =============================================================================
// Thematic breaks
// =============================================================================

///|
/// `***`, `---` or `___`, optionally separated by spaces and tabs.
fn BlockParser::try_thematic_break(
  self : BlockParser,
  container : Node,
) -> Node? {
  let c = self.peek_line(self.next_nonspace)
  guard c == '*' || c == '-' || c == '_' else { return None }
  let mut i = self.next_nonspace
  let mut count = 0
  while i < self.line_len {
    let ch = self.line.unsafe_get(i)
    if ch == c {
      count = count + 1
    } else if !is_space_or_tab(ch) {
      return None
    }
    i = i + 1
  }
  guard count >= 3 else { return None }
  let node = self.add_child(
    container,
    NodeKind::ThematicBreakNode,
    self.line_start + self.next_nonspace,
  )
  node.marker = c.unsafe_to_char()
  node.marker_count = count
  node.end = self.line_end
  self.advance_offset(self.line_len - self.offset, false)
  Some(node)
}
