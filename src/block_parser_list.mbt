///| Bullet and ordered list parsing (split from block_parser.mbt).

///|
/// Try to parse list
fn BlockParser::try_parse_list(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()

  // Check for bullet or ordered list marker
  match self.detect_list_marker() {
    Some((marker_kind, marker_width)) =>
      match marker_kind {
        ListMarkerKind::Bullet(marker) =>
          self.parse_bullet_list(start, leading, marker, marker_width)
        ListMarkerKind::Ordered(start_num, delim) =>
          self.parse_ordered_list(
            start, leading, start_num, delim, marker_width,
          )
      }
    None => None
  }
}

///|
/// List marker kind
priv enum ListMarkerKind {
  Bullet(BulletMarker)
  Ordered(Int, OrderedDelimiter)
}

///|
/// Detect list marker at current position
fn BlockParser::detect_list_marker(
  self : BlockParser,
) -> (ListMarkerKind, Int)? {
  let saved = self.scanner.pos

  // Check for bullet marker
  match self.scanner.peek() {
    Some('-') => {
      self.scanner.advance(1)
      match self.scanner.peek() {
        Some(' ') | Some('\t') => {
          self.scanner.restore(saved)
          return Some((ListMarkerKind::Bullet(BulletMarker::Dash), 2))
        }
        _ => ()
      }
    }
    Some('*') => {
      self.scanner.advance(1)
      match self.scanner.peek() {
        Some(' ') | Some('\t') => {
          self.scanner.restore(saved)
          return Some((ListMarkerKind::Bullet(BulletMarker::Asterisk), 2))
        }
        _ => ()
      }
    }
    Some('+') => {
      self.scanner.advance(1)
      match self.scanner.peek() {
        Some(' ') | Some('\t') => {
          self.scanner.restore(saved)
          return Some((ListMarkerKind::Bullet(BulletMarker::Plus), 2))
        }
        _ => ()
      }
    }
    _ => ()
  }
  self.scanner.restore(saved)

  // Check for ordered list marker (1. or 1))
  if char_is_digit(self.scanner.peek()) {
    let mut num = 0
    let mut digits = 0
    while char_is_digit(self.scanner.peek()) {
      match self.scanner.peek() {
        Some(c) => {
          num = num * 10 + (c.to_int() - '0'.to_int())
          self.scanner.advance(1)
          digits += 1
          if digits > 9 {
            self.scanner.restore(saved)
            return None
          }
        }
        None => break
      }
    }
    match self.scanner.peek() {
      Some('.') => {
        self.scanner.advance(1)
        match self.scanner.peek() {
          Some(' ') | Some('\t') => {
            self.scanner.restore(saved)
            return Some(
              (ListMarkerKind::Ordered(num, OrderedDelimiter::Dot), digits + 2),
            )
          }
          _ => ()
        }
      }
      Some(')') => {
        self.scanner.advance(1)
        match self.scanner.peek() {
          Some(' ') | Some('\t') => {
            self.scanner.restore(saved)
            return Some(
              (
                ListMarkerKind::Ordered(num, OrderedDelimiter::Paren),
                digits + 2,
              ),
            )
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
  self.scanner.restore(saved)
  None
}

///|
/// Parse bullet list
fn BlockParser::parse_bullet_list(
  self : BlockParser,
  start : Int,
  leading : Trivia,
  marker : BulletMarker,
  _marker_width : Int,
) -> Block? {
  let items : Array[ListItem] = []
  let mut tight = true
  while !self.scanner.is_eof() {
    let item_start = self.scanner.pos
    let marker_offset = self.scanner.skip_spaces()

    // Check marker matches
    let current_marker = match self.scanner.peek() {
      Some('-') => Some(BulletMarker::Dash)
      Some('*') => Some(BulletMarker::Asterisk)
      Some('+') => Some(BulletMarker::Plus)
      _ => None
    }
    if current_marker != Some(marker) {
      self.scanner.restore(item_start)
      break
    }
    self.scanner.advance(1) // Skip marker
    let content_offset = self.scanner.skip_spaces()
    let actual_offset = if content_offset == 0 { 1 } else { content_offset }

    // Parse item content
    let item = self.parse_list_item(item_start, marker_offset, actual_offset)
    items.push(item)

    // Check for blank lines (affects tight/loose)
    if !self.scanner.is_eof() && self.scanner.is_blank_line() {
      tight = false
      while !self.scanner.is_eof() && self.scanner.is_blank_line() {
        self.scanner.skip_line()
      }
    }
  }
  if items.is_empty() {
    return None
  }
  Some(
    Block::BulletList(
      marker~,
      tight~,
      items~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse ordered list
fn BlockParser::parse_ordered_list(
  self : BlockParser,
  start : Int,
  leading : Trivia,
  start_num : Int,
  delimiter : OrderedDelimiter,
  _marker_width : Int,
) -> Block? {
  let items : Array[ListItem] = []
  let mut tight = true
  while !self.scanner.is_eof() {
    let item_start = self.scanner.pos
    let marker_offset = self.scanner.skip_spaces()

    // Check for ordered marker with same delimiter
    match self.detect_list_marker() {
      Some((ListMarkerKind::Ordered(_, d), _)) if d == delimiter => ()
      _ => {
        self.scanner.restore(item_start)
        break
      }
    }

    // Skip number and delimiter
    while char_is_digit(self.scanner.peek()) {
      self.scanner.advance(1)
    }
    self.scanner.advance(1) // Skip . or )
    let content_offset = self.scanner.skip_spaces()
    let actual_offset = if content_offset == 0 { 1 } else { content_offset }

    // Parse item content
    let item = self.parse_list_item(item_start, marker_offset, actual_offset)
    items.push(item)

    // Check for blank lines
    if !self.scanner.is_eof() && self.scanner.is_blank_line() {
      tight = false
      while !self.scanner.is_eof() && self.scanner.is_blank_line() {
        self.scanner.skip_line()
      }
    }
  }
  if items.is_empty() {
    return None
  }
  Some(
    Block::OrderedList(
      start=start_num,
      delimiter~,
      tight~,
      items~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse list item content
fn BlockParser::parse_list_item(
  self : BlockParser,
  start : Int,
  marker_offset : Int,
  content_offset : Int,
) -> ListItem {
  // Parse first line content
  let content_buf = StringBuilder::new()
  let line = self.scanner.read_line()
  content_buf.write_string(line)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Parse content as blocks
  let content = content_buf.to_string()
  let children : Array[Block] = []

  // Check for task list checkbox: [ ], [x], or [X]
  let (checked, actual_content) = parse_task_checkbox(content)
  if !actual_content.is_empty() {
    let inline_content = parse_inlines(
      actual_content,
      strict=self.strict,
      wikilinks=self.wikilinks,
    )
    children.push(
      Block::Paragraph(
        children=inline_content,
        span=Span::new(start, self.scanner.pos),
        leading_trivia=Trivia::empty(),
        trailing_trivia=Trivia::empty(),
      ),
    )
  }

  // Check for nested content (indented continuation)
  // Nested list requires at least 2 spaces of indentation
  let min_indent = marker_offset + 1 + content_offset // marker position + marker char + spaces after
  while !self.scanner.is_eof() && !self.scanner.is_blank_line() {
    let saved = self.scanner.pos
    let indent = self.scanner.skip_spaces()

    // Check if indented enough to be continuation
    if indent < min_indent {
      self.scanner.restore(saved)
      break
    }

    // Check if this is a nested list
    match self.scanner.peek() {
      Some('-') | Some('*') | Some('+') => {
        // Nested bullet list
        let nested_marker = match self.scanner.peek() {
          Some('-') => BulletMarker::Dash
          Some('*') => BulletMarker::Asterisk
          Some('+') => BulletMarker::Plus
          _ => panic() // unreachable
        }
        self.scanner.restore(saved)
        match self.parse_nested_bullet_list(nested_marker, min_indent) {
          Some(nested_list) => children.push(nested_list)
          None => break
        }
      }
      _ => {
        // Not a nested list, restore and break
        self.scanner.restore(saved)
        break
      }
    }
  }
  {
    children,
    checked,
    marker_offset,
    content_offset,
    span: Span::new(start, self.scanner.pos),
  }
}

///|
/// Parse nested bullet list (indented list)
fn BlockParser::parse_nested_bullet_list(
  self : BlockParser,
  marker : BulletMarker,
  min_indent : Int,
) -> Block? {
  let items : Array[ListItem] = []
  let mut tight = true
  while !self.scanner.is_eof() {
    let item_start = self.scanner.pos
    let marker_offset = self.scanner.skip_spaces()

    // Must have at least min_indent spaces
    if marker_offset < min_indent {
      self.scanner.restore(item_start)
      break
    }

    // Check marker matches
    let current_marker = match self.scanner.peek() {
      Some('-') => Some(BulletMarker::Dash)
      Some('*') => Some(BulletMarker::Asterisk)
      Some('+') => Some(BulletMarker::Plus)
      _ => None
    }
    if current_marker != Some(marker) {
      self.scanner.restore(item_start)
      break
    }
    self.scanner.advance(1) // Skip marker
    let content_offset = self.scanner.skip_spaces()
    let actual_offset = if content_offset == 0 { 1 } else { content_offset }

    // Parse item content (non-recursive for now to avoid deep nesting issues)
    let item = self.parse_nested_list_item(
      item_start, marker_offset, actual_offset,
    )
    items.push(item)

    // Check for blank lines
    if !self.scanner.is_eof() && self.scanner.is_blank_line() {
      tight = false
      while !self.scanner.is_eof() && self.scanner.is_blank_line() {
        self.scanner.skip_line()
      }
    }
  }
  if items.is_empty() {
    return None
  }
  Some(
    Block::BulletList(
      marker~,
      tight~,
      items~,
      span=Span::new(items[0].span.from, self.scanner.pos),
      leading_trivia=Trivia::empty(),
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse nested list item (simplified, no recursion)
fn BlockParser::parse_nested_list_item(
  self : BlockParser,
  start : Int,
  marker_offset : Int,
  content_offset : Int,
) -> ListItem {
  let content_buf = StringBuilder::new()
  let line = self.scanner.read_line()
  content_buf.write_string(line)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let content = content_buf.to_string()
  let children : Array[Block] = []
  let (checked, actual_content) = parse_task_checkbox(content)
  if !actual_content.is_empty() {
    let inline_content = parse_inlines(
      actual_content,
      strict=self.strict,
      wikilinks=self.wikilinks,
    )
    children.push(
      Block::Paragraph(
        children=inline_content,
        span=Span::new(start, self.scanner.pos),
        leading_trivia=Trivia::empty(),
        trailing_trivia=Trivia::empty(),
      ),
    )
  }
  {
    children,
    checked,
    marker_offset,
    content_offset,
    span: Span::new(start, self.scanner.pos),
  }
}

///| Parse task list checkbox from content

///|
/// Returns (checked status, remaining content)
fn parse_task_checkbox(content : String) -> (Bool?, String) {
  // Check for [ ] (unchecked) or [x]/[X] (checked)
  if content.length() >= 4 {
    if content.has_prefix("[ ] ") {
      return (Some(false), skip_n_chars(content, 4))
    }
    if content.has_prefix("[x] ") || content.has_prefix("[X] ") {
      return (Some(true), skip_n_chars(content, 4))
    }
  }
  // Handle case without trailing space (end of line)
  if content == "[ ]" {
    return (Some(false), "")
  }
  if content == "[x]" || content == "[X]" {
    return (Some(true), "")
  }
  (None, content)
}

///|
/// Skip first n characters of a string
fn skip_n_chars(s : String, n : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  for c in s {
    if i >= n {
      buf.write_char(c)
    }
    i += 1
  }
  buf.to_string()
}
