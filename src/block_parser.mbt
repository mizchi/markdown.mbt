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
  IndentedCodeNode
  HtmlBlockNode
  TableNode
  FootnoteDefNode
  BlankLinesNode
} derive(Eq)

///|
/// A block under construction.
priv struct Node {
  mut kind : NodeKind
  mut parent : Node?
  children : Array[Node]
  /// Raw content lines, for blocks that accept lines.
  lines : Array[String]
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
  mut html_kind : Int
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
    html_kind: 0,
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
/// Whether the rest of the line holds an unescaped `|`, which is what makes it
/// a table row.
fn BlockParser::line_has_cell_separator(self : BlockParser) -> Bool {
  let mut i = self.next_nonspace
  while i < self.line_len {
    let c = self.line.unsafe_get(i)
    if c == '\\' {
      i = i + 2
      continue
    }
    if c == '|' {
      return true
    }
    i = i + 1
  }
  false
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
  let buf = StringBuilder::new()
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
    NodeKind::DocNode | NodeKind::BlockQuoteNode | NodeKind::FootnoteDefNode =>
      child != NodeKind::ItemNode
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
  let document = Document::{
    frontmatter,
    children,
    definitions: self.definitions,
    span: Span::new(0, self.len),
  }
  { document, definitions: self.definitions }
}

///|
/// Read the line starting at `pos`, returning its text (without the line
/// ending) and the offset of the next line.
fn BlockParser::read_line(self : BlockParser, pos : Int) -> (String, Int) {
  let mut i = pos
  while i < self.len {
    let c = self.source.unsafe_get(i)
    if c == '\n' || c == '\r' {
      break
    }
    i = i + 1
  }
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
  let buf = StringBuilder::new()
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
      NodeKind::HtmlBlockNode =>
        if self.blank && container.html_kind >= 6 {
          all_matched = false
        }
      NodeKind::ParagraphNode =>
        if self.blank {
          all_matched = false
        }
      NodeKind::TableNode =>
        // Only a line that still looks like a row keeps the table open;
        // anything else has to be reconsidered as ordinary block content.
        if self.blank || !self.line_has_cell_separator() {
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
    self.tip.lines.push(self.rest_of_line())
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
      container.lines.push(self.rest_of_line())
    }
    container.end = self.line_end
  } else if container.kind == NodeKind::HtmlBlockNode {
    container.lines.push(self.rest_of_line())
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
      container.closing_hashes = hashes
    } else {
      container.lines.push(self.rest_of_line())
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
    para.lines.push(self.rest_of_line())
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
  let buf = StringBuilder::new()
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
  let buf = StringBuilder::new()
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
  let buf = StringBuilder::new()
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
      let content = self.strip_link_definitions(joined_lines(node))
      if is_blank_text(content) {
        return None
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
        self.strip_link_definitions(joined_lines(node))
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
