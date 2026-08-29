///| Bullet and ordered list parsing (split from block_parser.mbt).

///|
/// A parsed list marker: its width in characters and the list it starts.
priv struct ListMarker {
  width : Int
  ordered : Bool
  bullet : Char
  start : Int
  delim : Char
}

///|
/// Read the list marker at `pos`, if there is one.
///
/// `interrupts_paragraph` applies the extra restrictions the spec puts on a
/// list that starts in the middle of a paragraph: it must be numbered 1 and
/// may not be empty.
fn BlockParser::parse_list_marker(
  self : BlockParser,
  pos : Int,
  interrupts_paragraph : Bool,
) -> ListMarker? {
  let line = self.line
  let len = self.line_len
  guard pos < len else { return None }
  let c = line.unsafe_get(pos)
  let mut i = pos
  let mut ordered = false
  let mut bullet = '-'
  let mut number = 1
  let mut delim = '.'
  if c == '*' || c == '-' || c == '+' {
    bullet = c.unsafe_to_char()
    i = i + 1
  } else if c >= '0' && c <= '9' {
    ordered = true
    let mut digits = 0
    number = 0
    while i < len && line.unsafe_get(i) >= '0' && line.unsafe_get(i) <= '9' {
      number = number * 10 + (line.unsafe_get(i).to_int() - '0'.to_int())
      digits = digits + 1
      i = i + 1
    }
    guard digits <= 9 else { return None }
    guard i < len else { return None }
    let d = line.unsafe_get(i)
    guard d == '.' || d == ')' else { return None }
    delim = d.unsafe_to_char()
    i = i + 1
  } else {
    return None
  }
  guard i >= len || is_space_or_tab(line.unsafe_get(i)) else { return None }
  if interrupts_paragraph {
    if ordered && number != 1 {
      return None
    }
    // An empty list item cannot interrupt a paragraph.
    let mut j = i
    while j < len && is_space_or_tab(line.unsafe_get(j)) {
      j = j + 1
    }
    if j >= len {
      return None
    }
  }
  Some({ width: i - pos, ordered, bullet, start: number, delim })
}

///|
fn lists_match(list : Node, marker : ListMarker) -> Bool {
  list.ordered == marker.ordered &&
  (if marker.ordered {
    list.delim == marker.delim
  } else {
    list.marker == marker.bullet
  })
}

///|
/// Open a list item, and the list around it when this starts a new one.
fn BlockParser::try_list_item(self : BlockParser, container : Node) -> Node? {
  // A `-`, `*` or `_` run that reads as a thematic break wins over a list.
  if self.would_be_thematic_break() {
    return None
  }
  let interrupts = container.kind == NodeKind::ParagraphNode
  guard self.parse_list_marker(self.next_nonspace, interrupts) is Some(marker) else {
    return None
  }
  let marker_offset = self.indent
  let item_start = self.line_start + self.next_nonspace
  self.advance_offset(self.next_nonspace + marker.width - self.offset, false)

  // Measure the whitespace after the marker: one to four spaces set the
  // content column; anything else (or nothing) falls back to a single space.
  let save_offset = self.offset
  let save_column = self.column
  let save_tab = self.partially_consumed_tab
  while self.column - save_column <= 5 &&
        is_space_or_tab(self.peek_line(self.offset)) {
    self.advance_offset(1, true)
  }
  let spaces = self.column - save_column
  let padding = if spaces >= 5 || spaces < 1 || self.offset >= self.line_len {
    self.offset = save_offset
    self.column = save_column
    self.partially_consumed_tab = save_tab
    if is_space_or_tab(self.peek_line(self.offset)) {
      self.advance_offset(1, true)
    }
    marker.width + 1
  } else {
    marker.width + spaces
  }
  let mut list = container
  if container.kind != NodeKind::ListNode || !lists_match(container, marker) {
    list = self.add_child(container, NodeKind::ListNode, item_start)
    list.ordered = marker.ordered
    list.marker = marker.bullet
    list.delim = marker.delim
    list.list_start = marker.start
  }
  list.end = self.line_end
  let item = self.add_child(list, NodeKind::ItemNode, item_start)
  item.ordered = marker.ordered
  item.marker = marker.bullet
  item.delim = marker.delim
  item.item_marker_offset = marker_offset
  item.item_padding = padding
  item.end = self.line_end
  self.take_task_checkbox(item)
  Some(item)
}

///|
/// Would the current line read as a thematic break? `- - -` is a break, not a
/// list holding a list.
fn BlockParser::would_be_thematic_break(self : BlockParser) -> Bool {
  let c = self.peek_line(self.next_nonspace)
  guard c == '*' || c == '-' || c == '_' else { return false }
  let mut i = self.next_nonspace
  let mut count = 0
  while i < self.line_len {
    let ch = self.line.unsafe_get(i)
    if ch == c {
      count = count + 1
    } else if !is_space_or_tab(ch) {
      return false
    }
    i = i + 1
  }
  count >= 3
}

///|
/// GFM task list items: `[ ]`, `[x]` or `[X]` right after the marker.
fn BlockParser::take_task_checkbox(self : BlockParser, item : Node) -> Unit {
  let i = self.offset
  guard self.peek_line(i) == '[' else { return }
  let mark = self.peek_line(i + 1)
  guard mark == ' ' || mark == 'x' || mark == 'X' else { return }
  guard self.peek_line(i + 2) == ']' else { return }
  guard i + 3 >= self.line_len || is_space_or_tab(self.peek_line(i + 3)) else {
    return
  }
  item.checked = Some(mark != ' ')
  self.advance_offset(3, false)
  if is_space_or_tab(self.peek_line(self.offset)) {
    self.advance_offset(1, true)
  }
}
