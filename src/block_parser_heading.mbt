///| ATX and setext heading parsing (split from block_parser.mbt).

///|
/// `#` to `######` followed by a space, a tab or the end of the line.
fn BlockParser::try_atx_heading(self : BlockParser, container : Node) -> Node? {
  let mut i = self.next_nonspace
  let mut level = 0
  while i < self.line_len && self.line.unsafe_get(i) == '#' && level < 7 {
    level = level + 1
    i = i + 1
  }
  guard level >= 1 && level <= 6 else { return None }
  guard i >= self.line_len || is_space_or_tab(self.line.unsafe_get(i)) else {
    return None
  }
  let node = self.add_child(
    container,
    NodeKind::HeadingNode,
    self.line_start + self.next_nonspace,
  )
  node.level = level
  node.style = HeadingStyle::Atx
  node.end = self.line_end
  self.advance_offset(self.next_nonspace + level - self.offset, false)
  Some(node)
}

///|
/// Drop the optional closing run of `#`, which has to be preceded by
/// whitespace and followed by nothing but whitespace.
fn chop_trailing_hashes(text : String) -> (String, Int) {
  let mut end = text.length()
  while end > 0 && is_space_or_tab(text.unsafe_get(end - 1)) {
    end = end - 1
  }
  let mut hash_start = end
  while hash_start > 0 && text.unsafe_get(hash_start - 1) == '#' {
    hash_start = hash_start - 1
  }
  let hashes = end - hash_start
  if hashes > 0 &&
    (hash_start == 0 || is_space_or_tab(text.unsafe_get(hash_start - 1))) {
    let mut content_end = hash_start
    while content_end > 0 && is_space_or_tab(text.unsafe_get(content_end - 1)) {
      content_end = content_end - 1
    }
    return (text.unsafe_substring(start=0, end=content_end), hashes)
  }
  (text.unsafe_substring(start=0, end~), 0)
}

///|
/// A line of `=` or `-` under a paragraph turns it into a heading.
fn BlockParser::try_setext_heading(
  self : BlockParser,
  container : Node,
) -> Bool {
  let c = self.peek_line(self.next_nonspace)
  guard c == '=' || c == '-' else { return false }
  let mut i = self.next_nonspace
  while i < self.line_len && self.line.unsafe_get(i) == c {
    i = i + 1
  }
  guard i > self.next_nonspace else { return false }
  while i < self.line_len && is_space_or_tab(self.line.unsafe_get(i)) {
    i = i + 1
  }
  guard i >= self.line_len else { return false }
  // A paragraph holding nothing but link reference definitions cannot be
  // turned into a heading.
  guard !is_blank_text(self.strip_link_definitions_dry(container)) else {
    return false
  }
  container.kind = NodeKind::HeadingNode
  container.level = if c == '=' { 1 } else { 2 }
  container.style = HeadingStyle::Setext
  container.end = self.line_end
  true
}
