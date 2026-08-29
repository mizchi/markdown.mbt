///| Fenced code block parsing (split from block_parser.mbt).

///|
/// A run of at least three backticks or tildes opens a fenced code block. The
/// info string follows on the same line and, for backtick fences, may not
/// itself contain a backtick.
fn BlockParser::try_open_code_fence(
  self : BlockParser,
  container : Node,
) -> Node? {
  let c = self.peek_line(self.next_nonspace)
  guard c == '`' || c == '~' else { return None }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line.unsafe_get(i) == c {
    i = i + 1
  }
  let length = i - self.next_nonspace
  guard length >= 3 else { return None }
  let info_raw = self.line.unsafe_substring(start=i, end=self.line_len)
  if c == '`' {
    for j = 0; j < info_raw.length(); j = j + 1 {
      if info_raw.unsafe_get(j) == '`' {
        return None
      }
    }
  }
  let node = self.add_child(
    container,
    NodeKind::FencedCodeNode,
    self.line_start + self.next_nonspace,
  )
  node.marker = c.unsafe_to_char()
  node.fence_length = length
  node.fence_indent = self.indent
  node.info = info_raw.trim(chars=" \t").to_owned()
  node.info_pending = true
  node.end = self.line_end
  // Consume the rest of the line so that the info string is not mistaken for
  // the block's first content line.
  self.advance_offset(self.line_len - self.offset, false)
  Some(node)
}

///|
/// A run of the fence character, at least as long as the opening one and
/// followed by nothing but whitespace, closes the block.
fn BlockParser::scan_close_code_fence(self : BlockParser, node : Node) -> Bool {
  let c = self.peek_line(self.next_nonspace)
  guard c.to_int() == node.marker.to_int() else { return false }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line.unsafe_get(i) == c {
    i = i + 1
  }
  guard i - self.next_nonspace >= node.fence_length else { return false }
  while i < self.line_len && is_space_or_tab(self.line.unsafe_get(i)) {
    i = i + 1
  }
  i >= self.line_len
}
