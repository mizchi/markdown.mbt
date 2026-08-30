///| Link reference definitions and GFM footnote definitions.

///| Split out from block_parser.mbt to keep that file focused on the container

///| algorithm.

///|
/// Strip the link reference definitions a paragraph starts with, registering
/// each one, and return what is left of the paragraph.
fn BlockParser::strip_link_definitions(
  self : BlockParser,
  node : Node,
) -> String {
  self.take_link_definitions(node, true)
}

///|
/// Same, but without registering anything: used to decide whether a paragraph
/// would still hold text.
fn BlockParser::strip_link_definitions_dry(
  self : BlockParser,
  node : Node,
) -> String {
  self.take_link_definitions(node, false)
}

///|
fn BlockParser::take_link_definitions(
  self : BlockParser,
  node : Node,
  register : Bool,
) -> String {
  let content = joined_lines(node)
  let len = content.length()
  let mut pos = 0
  while pos < len && content.unsafe_get(pos) == '[' {
    match self.parse_link_reference(node, content, pos, register) {
      Some(next) => pos = next
      None => break
    }
  }
  if pos == 0 {
    return content
  }
  content.unsafe_substring(start=pos, end=len)
}

///|
fn skip_spaces_tabs(text : String, start : Int) -> Int {
  let len = text.length()
  let mut i = start
  while i < len && is_space_or_tab(text.unsafe_get(i)) {
    i = i + 1
  }
  i
}

///|
/// Skip whitespace, allowing at most one line ending. Returns the new position
/// and how many line endings were crossed.
fn skip_ws_one_newline(text : String, start : Int) -> (Int, Int) {
  let len = text.length()
  let mut i = skip_spaces_tabs(text, start)
  let mut newlines = 0
  if i < len && text.unsafe_get(i) == '\n' {
    newlines = 1
    i = skip_spaces_tabs(text, i + 1)
  }
  (i, newlines)
}

///|
/// Parse `[label]: destination "title"` at `pos`, returning the position just
/// past it.
fn BlockParser::parse_link_reference(
  self : BlockParser,
  node : Node,
  text : String,
  pos : Int,
  register : Bool,
) -> Int? {
  let len = text.length()
  guard pos < len && text.unsafe_get(pos) == '[' else { return None }
  let label_start = pos + 1
  let mut i = label_start
  let mut label_end = -1
  while i < len {
    let c = text.unsafe_get(i)
    if c == '\\' && i + 1 < len {
      i = i + 2
      continue
    }
    if c == '[' {
      return None
    }
    if c == ']' {
      label_end = i
      break
    }
    i = i + 1
  }
  guard label_end >= 0 else { return None }
  let label = text.unsafe_substring(start=label_start, end=label_end)
  guard label.length() <= 999 && !is_blank_text(label) else { return None }
  i = label_end + 1
  guard i < len && text.unsafe_get(i) == ':' else { return None }
  i = i + 1
  let (after_colon, _) = skip_ws_one_newline(text, i)
  i = after_colon
  guard parse_link_destination(text, i) is Some((raw_dest, after_dest)) else {
    return None
  }
  guard after_dest > i else { return None }
  let mut end = -1
  let mut title = ""
  let (title_start, newlines) = skip_ws_one_newline(text, after_dest)
  if title_start > after_dest || newlines > 0 {
    match parse_link_title(text, title_start) {
      Some((raw_title, after_title)) => {
        let line_end = skip_spaces_tabs(text, after_title)
        if line_end >= len || text.unsafe_get(line_end) == '\n' {
          title = unescape_string(raw_title)
          end = if line_end < len { line_end + 1 } else { line_end }
        }
      }
      None => ()
    }
  }
  if end < 0 {
    let line_end = skip_spaces_tabs(text, after_dest)
    guard line_end >= len || text.unsafe_get(line_end) == '\n' else {
      return None
    }
    end = if line_end < len { line_end + 1 } else { line_end }
  }
  if register {
    self.definitions.push({
      label,
      url: normalize_destination(raw_dest),
      title,
      span: Span::new(source_offset_in(node, pos), source_offset_in(node, end)),
    })
  }
  Some(end)
}

///|
/// GFM footnote definition: `[^label]: content`.
fn BlockParser::try_footnote_definition(
  self : BlockParser,
  container : Node,
) -> Node? {
  guard self.peek_line(self.next_nonspace) == '[' else { return None }
  guard self.peek_line(self.next_nonspace + 1) == '^' else { return None }
  let mut i = self.next_nonspace + 2
  while i < self.line_len {
    let c = self.line.unsafe_get(i)
    if c == ']' {
      break
    }
    if c == '[' || c == '\n' || c == '\r' || c == 0 {
      return None
    }
    i = i + 1
  }
  guard i < self.line_len && i > self.next_nonspace + 2 else { return None }
  guard i + 1 < self.line_len && self.line.unsafe_get(i + 1) == ':' else {
    return None
  }
  let label = self.line
    .unsafe_substring(start=self.next_nonspace + 2, end=i)
    .trim(chars=" \t")
    .to_owned()
  guard !label.is_empty() else { return None }
  let node = self.add_child(
    container,
    NodeKind::FootnoteDefNode,
    self.line_start + self.next_nonspace,
  )
  node.label = label
  node.end = self.line_end
  self.advance_offset(i + 2 - self.offset, false)
  if is_space_or_tab(self.peek_line(self.offset)) {
    self.advance_offset(1, true)
  }
  Some(node)
}
