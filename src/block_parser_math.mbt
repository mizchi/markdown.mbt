///| Display-math block parsing.

///|
/// A line containing only two or more `$` characters opens display math.
fn BlockParser::try_open_math_block(
  self : BlockParser,
  container : Node,
) -> Node? {
  guard self.peek_line(self.next_nonspace) == '$' else { return None }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line.unsafe_get(i) == '$' {
    i = i + 1
  }
  let length = i - self.next_nonspace
  guard length >= 2 else { return None }
  while i < self.line_len && is_space_or_tab(self.line.unsafe_get(i)) {
    i = i + 1
  }
  guard i >= self.line_len else { return None }
  let node = self.add_child(
    container,
    NodeKind::MathBlockNode,
    self.line_start + self.next_nonspace,
  )
  node.fence_length = length
  node.fence_indent = self.indent
  node.info_pending = true
  node.end = self.line_end
  self.advance_offset(self.line_len - self.offset, false)
  Some(node)
}

///|
/// A dollar run at least as long as the opener closes display math.
fn BlockParser::scan_close_math_fence(self : BlockParser, node : Node) -> Bool {
  guard self.peek_line(self.next_nonspace) == '$' else { return false }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line.unsafe_get(i) == '$' {
    i = i + 1
  }
  guard i - self.next_nonspace >= node.fence_length else { return false }
  while i < self.line_len && is_space_or_tab(self.line.unsafe_get(i)) {
    i = i + 1
  }
  i >= self.line_len
}
