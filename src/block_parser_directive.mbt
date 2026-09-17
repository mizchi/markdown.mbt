///| Generic fenced-directive parsing.

///|
/// Open `:::name optional metadata` as a container whose body is Markdown.
fn BlockParser::try_open_directive(
  self : BlockParser,
  container : Node,
) -> Node? {
  guard self.peek_line(self.next_nonspace) == ':' else { return None }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line_char(i) == ':' {
    i = i + 1
  }
  let fence_length = i - self.next_nonspace
  guard fence_length >= 3 else { return None }
  let name_start = i
  while i < self.line_len {
    let c = self.line_char(i)
    if !(is_ascii_alnum_unit(c) || c == '-' || c == '_') {
      break
    }
    i = i + 1
  }
  guard i > name_start else { return None }
  let name = self.line_slice(name_start, i)
  guard i >= self.line_len || is_space_or_tab(self.line_char(i)) else {
    return None
  }
  let meta = self.line_slice(i, self.line_len).trim(chars=" \t").to_owned()
  let node = self.add_child(
    container,
    NodeKind::DirectiveNode,
    self.line_start + self.next_nonspace,
  )
  node.label = name
  node.info = meta
  node.fence_length = fence_length
  node.end = self.line_end
  self.advance_offset(self.line_len - self.offset, false)
  Some(node)
}

///|
/// A colon-only line closes the innermost directive container.
fn BlockParser::scan_close_directive_fence(
  self : BlockParser,
  node : Node,
) -> Bool {
  guard self.peek_line(self.next_nonspace) == ':' else { return false }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line_char(i) == ':' {
    i = i + 1
  }
  guard i - self.next_nonspace >= node.fence_length else { return false }
  while i < self.line_len && is_space_or_tab(self.line_char(i)) {
    i = i + 1
  }
  i >= self.line_len
}
