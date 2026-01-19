///| Block-level markdown parser

///| Line-driven state machine (Lezer-style)

///|
/// Parse result
pub(all) struct ParseResult {
  document : Document
  definitions : Array[LinkDefinition]
}

///| Parse markdown source into CST

///| When strict=true, uses full CommonMark compliance (slower)

///|
/// When strict=false (default), uses fast single-pass parser
pub fn parse(source : String, strict? : Bool = false) -> ParseResult {
  let scanner = Scanner::new(source)
  let parser = BlockParser::new(scanner, strict)
  parser.parse_document()
}

///|
/// Block parser state
priv struct BlockParser {
  scanner : Scanner
  definitions : Array[LinkDefinition]
  strict : Bool
}

///|
fn BlockParser::new(scanner : Scanner, strict : Bool) -> BlockParser {
  { scanner, definitions: [], strict }
}

///|
/// Parse entire document
fn BlockParser::parse_document(self : BlockParser) -> ParseResult {
  let start = self.scanner.pos

  // Try to parse frontmatter
  let frontmatter = self.try_parse_frontmatter()

  // Parse blocks
  let children = self.parse_blocks()
  let document = Document::{
    frontmatter,
    children,
    span: Span::new(start, self.scanner.pos),
  }
  { document, definitions: self.definitions }
}

///|
/// Parse sequence of blocks
fn BlockParser::parse_blocks(self : BlockParser) -> Array[Block] {
  let blocks : Array[Block] = []
  while not(self.scanner.is_eof()) {
    // Skip and collect blank lines
    let blank_start = self.scanner.pos
    let mut blank_count = 0
    while not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
      blank_count += 1
      self.scanner.skip_line()
    }
    if blank_count > 0 {
      blocks.push(
        Block::BlankLines(
          count=blank_count,
          span=Span::new(blank_start, self.scanner.pos),
        ),
      )
    }
    if self.scanner.is_eof() {
      break
    }

    // Parse next block
    match self.parse_block() {
      Some(block) => blocks.push(block)
      None =>
        // Skip problematic line
        self.scanner.skip_line()
    }
  }
  blocks
}

///|
/// Parse a single block
fn BlockParser::parse_block(self : BlockParser) -> Block? {
  let start = self.scanner.pos
  let indent = self.scanner.count_leading_spaces()

  // Try each block type in order of precedence

  // Thematic break (must check before lists due to ---)
  match self.try_parse_thematic_break(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // ATX heading
  match self.try_parse_atx_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Fenced code block
  match self.try_parse_fenced_code(start, indent) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Blockquote
  match self.try_parse_blockquote(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // List (bullet or ordered)
  match self.try_parse_list(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Indented code block (4+ spaces)
  if indent >= 4 {
    match self.try_parse_indented_code(start) {
      Some(block) => return Some(block)
      None => self.scanner.restore(start)
    }
  }

  // Setext heading (underlined)
  match self.try_parse_setext_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // HTML block
  match self.try_parse_html_block(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Table
  match self.try_parse_table(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Footnote definition
  match self.try_parse_footnote_definition(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Link reference definition
  match self.try_parse_link_definition(start) {
    Some(_) => return None // Definitions don't produce blocks
    None => self.scanner.restore(start)
  }

  // Default: paragraph
  self.parse_paragraph(start)
}

///|
/// Try to parse thematic break (---, ***, ___)
fn BlockParser::try_parse_thematic_break(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = self.read_leading_trivia()
  let marker = match self.scanner.peek() {
    Some(c) if c == '-' || c == '*' || c == '_' => c
    _ => return None
  }
  let mut count = 0
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some('\n') => break
      Some(c) if c == marker => {
        count += 1
        self.scanner.advance(1)
      }
      Some(c) if c == ' ' || c == '\t' => self.scanner.advance(1)
      _ => return None // Invalid character
    }
  }
  if count < 3 {
    return None
  }
  let trailing = self.read_trailing_trivia()
  Some(
    Block::ThematicBreak(
      marker~,
      count~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Try to parse ATX heading (# Heading)
fn BlockParser::try_parse_atx_heading(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = self.read_leading_trivia()

  // Count # characters
  let level = self.scanner.count_char('#')
  if level < 1 || level > 6 {
    return None
  }
  self.scanner.advance(level)

  // Must be followed by space or end of line
  match self.scanner.peek() {
    Some(' ') | Some('\t') | Some('\n') | None => ()
    _ => return None
  }

  // Skip space after #
  let _ = self.scanner.skip_spaces()

  // Read content until end of line or closing hashes
  let line = self.scanner.read_line()

  // Check for closing hashes
  let (content, closing_hashes) = parse_heading_content(line)

  // Skip newline
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let trailing = Trivia::empty()

  // Parse inline content
  let children = parse_inlines(content, strict=self.strict)
  Some(
    Block::Heading(
      level~,
      style=HeadingStyle::Atx,
      children~,
      closing_hashes~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Parse heading content, returning (content, closing_hash_count)
fn parse_heading_content(line : String) -> (String, Int) {
  let trimmed = line.trim_end(chars=" \t").to_string()

  // Count trailing #
  let mut hash_count = 0
  let mut idx = trimmed.length() - 1
  while idx >= 0 {
    match trimmed.get_char(idx) {
      Some('#') => {
        hash_count += 1
        idx -= 1
      }
      _ => break
    }
  }

  // Closing hashes must be preceded by space (or be at start)
  if hash_count > 0 && idx >= 0 {
    match trimmed.get_char(idx) {
      Some(' ') | Some('\t') => ()
      _ => return (trimmed, 0) // Not valid closing hashes
    }
  }
  if hash_count > 0 {
    let content = trimmed
      .unsafe_substring(start=0, end=idx + 1)
      .trim_end(chars=" \t")
      .to_string()
    (content, hash_count)
  } else {
    (trimmed, 0)
  }
}

///|
/// Try to parse fenced code block
fn BlockParser::try_parse_fenced_code(
  self : BlockParser,
  start : Int,
  indent : Int,
) -> Block? {
  if indent > 3 {
    return None
  }
  let leading = self.read_leading_trivia()
  let fence_char = match self.scanner.peek() {
    Some(c) if c == '`' || c == '~' => c
    _ => return None
  }
  let fence_marker = if fence_char == '`' {
    FenceMarker::Backtick
  } else {
    FenceMarker::Tilde
  }
  let fence_length = self.scanner.count_char(fence_char)
  if fence_length < 3 {
    return None
  }
  self.scanner.advance(fence_length)

  // Read info string (language + optional filename)
  let _ = self.scanner.skip_spaces()
  let info = self.scanner.read_line().trim_end(chars=" \t").to_string()

  // Skip newline
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read code content until closing fence
  let code_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    let line_indent = self.scanner.count_leading_spaces()

    // Check for closing fence
    if line_indent <= 3 {
      let saved = self.scanner.pos
      let _ = self.scanner.skip_spaces()
      if self.scanner.count_char(fence_char) >= fence_length {
        // Found closing fence
        self.scanner.advance(self.scanner.count_char(fence_char))
        let _ = self.scanner.skip_spaces()
        if char_is(self.scanner.peek(), '\n') || self.scanner.is_eof() {
          if char_is(self.scanner.peek(), '\n') {
            self.scanner.advance(1)
          }
          break
        }
      }
      self.scanner.restore(saved)
    }

    // Read code line (remove up to `indent` leading spaces)
    let line = self.scanner.read_line()
    let stripped = strip_indent(line, indent)
    code_buf.write_string(stripped)
    if char_is(self.scanner.peek(), '\n') {
      code_buf.write_char('\n')
      self.scanner.advance(1)
    }
  }
  let trailing = Trivia::empty()
  Some(
    Block::FencedCode(
      fence_marker~,
      fence_length~,
      info~,
      code=code_buf.to_string(),
      indent~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Strip up to n leading spaces from a line
fn strip_indent(line : String, n : Int) -> String {
  let mut stripped = 0
  let mut idx = 0
  while idx < line.length() && stripped < n {
    match line.get_char(idx) {
      Some(' ') => {
        stripped += 1
        idx += 1
      }
      Some('\t') => {
        stripped += 4
        idx += 1
      }
      _ => break
    }
  }
  line.unsafe_substring(start=idx, end=line.length())
}

///|
/// Try to parse indented code block
fn BlockParser::try_parse_indented_code(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = Trivia::empty()
  let code_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    let line_start = self.scanner.pos

    // Check if line starts with 4+ spaces
    let indent = self.scanner.count_leading_spaces()
    if indent < 4 && not(self.scanner.is_blank_line()) {
      self.scanner.restore(line_start)
      break
    }
    if self.scanner.is_blank_line() {
      code_buf.write_char('\n')
      self.scanner.skip_line()
    } else {
      // Skip 4 spaces
      self.scanner.advance(4)
      let line = self.scanner.read_line()
      code_buf.write_string(line)
      if char_is(self.scanner.peek(), '\n') {
        code_buf.write_char('\n')
        self.scanner.advance(1)
      }
    }
  }
  let code = code_buf.to_string().trim_end(chars="\n").to_string()
  if code.is_empty() {
    return None
  }
  Some(
    Block::IndentedCode(
      code~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse blockquote
fn BlockParser::try_parse_blockquote(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  if not(char_is(self.scanner.peek(), '>')) {
    return None
  }

  // Collect all lines of blockquote
  let content_buf = StringBuilder::new()
  let mut first = true
  while not(self.scanner.is_eof()) {
    let line_start = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), '>') {
      self.scanner.advance(1)
      // Optional space after >
      if char_is(self.scanner.peek(), ' ') {
        self.scanner.advance(1)
      }
      let line = self.scanner.read_line()
      if not(first) {
        content_buf.write_char('\n')
      }
      content_buf.write_string(line)
      first = false
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
    } else {
      // Line without > ends blockquote
      // TODO: Implement proper lazy continuation for paragraph content only
      self.scanner.restore(line_start)
      break
    }
  }

  // Parse blockquote content recursively
  let content = content_buf.to_string()
  let inner_scanner = Scanner::new(content)
  let inner_parser = BlockParser::new(inner_scanner, self.strict)
  let inner_result = inner_parser.parse_document()

  // Merge definitions
  for def in inner_result.definitions {
    self.definitions.push(def)
  }
  Some(
    Block::Blockquote(
      children=inner_result.document.children,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

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
  while not(self.scanner.is_eof()) {
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
    if not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
      tight = false
      while not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
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
  while not(self.scanner.is_eof()) {
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
    if not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
      tight = false
      while not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
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
  if not(actual_content.is_empty()) {
    let inline_content = parse_inlines(actual_content, strict=self.strict)
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
  while not(self.scanner.is_eof()) && not(self.scanner.is_blank_line()) {
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
  while not(self.scanner.is_eof()) {
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
    if not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
      tight = false
      while not(self.scanner.is_eof()) && self.scanner.is_blank_line() {
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
  if not(actual_content.is_empty()) {
    let inline_content = parse_inlines(actual_content, strict=self.strict)
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

///|
/// Try to parse setext heading
fn BlockParser::try_parse_setext_heading(
  self : BlockParser,
  start : Int,
) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // Read content line
  let content = self.scanner.read_line()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  } else {
    return None // Must have another line
  }

  // Check for setext underline
  let _ = self.scanner.skip_spaces()
  let underline_char = match self.scanner.peek() {
    Some(c) if c == '=' || c == '-' => c
    _ => return None
  }
  let level = if underline_char == '=' { 1 } else { 2 }
  let underline_count = self.scanner.count_char(underline_char)
  if underline_count < 1 {
    return None
  }
  self.scanner.advance(underline_count)

  // Rest of line must be empty
  let _ = self.scanner.skip_spaces()
  if not(char_is(self.scanner.peek(), '\n')) && not(self.scanner.is_eof()) {
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let content_str = content.trim(chars=" \t\n\r").to_string()
  let children = parse_inlines(content_str, strict=self.strict)
  Some(
    Block::Heading(
      level~,
      style=HeadingStyle::Setext,
      children~,
      closing_hashes=0,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// HTML block-level tag names (CommonMark Type 6)
let html_block_tags : Array[String] = [
  "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
  "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
  "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup",
  "option", "p", "param", "search", "section", "summary", "svg", "table", "tbody", "td",
  "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

///|
/// Check if a tag name is a block-level HTML tag
/// Also recognizes custom elements (Web Components) as block tags
fn is_html_block_tag(tag : String) -> Bool {
  // Custom elements (Web Components) are always block-level
  if is_custom_element_tag(tag) {
    return true
  }
  let lower = tag.to_lower()
  for t in html_block_tags {
    if lower == t {
      return true
    }
  }
  false
}

///|
/// Check if a tag name is a custom element (Web Component)
/// Custom elements must contain at least one hyphen and start with a letter
fn is_custom_element_tag(tag : String) -> Bool {
  if tag.is_empty() {
    return false
  }
  // Must start with a letter
  let chars = tag.to_array()
  let first = chars[0]
  if not((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')) {
    return false
  }
  // Must contain a hyphen
  for c in chars {
    if c == '-' {
      return true
    }
  }
  false
}

///|
/// Try to parse HTML block
fn BlockParser::try_parse_html_block(self : BlockParser, start : Int) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // HTML blocks must start with <
  if not(char_is(self.scanner.peek(), '<')) {
    self.scanner.restore(saved)
    return None
  }

  // Peek ahead to check for valid HTML block start
  let peek_pos = self.scanner.pos
  self.scanner.advance(1) // Skip <

  // Check for closing tag </tag>
  let is_closing = char_is(self.scanner.peek(), '/')
  if is_closing {
    self.scanner.advance(1)
  }

  // Read tag name (including hyphen for custom elements)
  let tag_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some(c) if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-' => {
        tag_buf.write_char(c)
        self.scanner.advance(1)
      }
      _ => break
    }
  }
  let tag_name = tag_buf.to_string()
  if tag_name.is_empty() {
    self.scanner.restore(saved)
    return None
  }

  // Check if this is a block-level tag or custom element
  let is_custom = is_custom_element_tag(tag_name)
  if not(is_html_block_tag(tag_name)) && not(is_custom) {
    self.scanner.restore(saved)
    return None
  }

  // Restore to start and read entire HTML block
  self.scanner.restore(peek_pos)
  let content_buf = StringBuilder::new()

  // For custom elements, we need to find the closing tag
  let closing_tag = if is_custom && not(is_closing) {
    Some("</\{tag_name}>")
  } else {
    None
  }

  // Read lines until closing tag (for custom elements) or blank line
  while not(self.scanner.is_eof()) {
    let line = self.scanner.read_line()
    content_buf.write_string(line)
    if char_is(self.scanner.peek(), '\n') {
      content_buf.write_char('\n')
      self.scanner.advance(1)
    }

    // For custom elements, check if line contains closing tag
    match closing_tag {
      Some(close) => {
        if line.contains(close) {
          break
        }
        // Also check for self-closing tag on first line
        if content_buf.to_string().char_length() == line.char_length() + 1 {
          // First line - check for self-closing />
          if line.contains("/>") {
            break
          }
        }
      }
      None => {
        // Standard HTML block: end on blank line
        if self.scanner.is_blank_line() {
          break
        }
      }
    }
  }
  let html = content_buf.to_string()
  Some(
    Block::HtmlBlock(
      html~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse GFM footnote definition [^label]: content
fn BlockParser::try_parse_footnote_definition(
  self : BlockParser,
  start : Int,
) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // [^label]:
  if not(char_is(self.scanner.peek(), '[')) {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)
  if not(char_is(self.scanner.peek(), '^')) {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Read label (alphanumeric, -, _)
  let label_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some(']') => break
      Some(c) if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-' ||
        c == '_' => {
        label_buf.write_char(c)
        self.scanner.advance(1)
      }
      _ => {
        self.scanner.restore(saved)
        return None
      }
    }
  }
  let label = label_buf.to_string()
  if label.is_empty() {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1) // ]
  if not(char_is(self.scanner.peek(), ':')) {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Skip optional space after :
  if char_is(self.scanner.peek(), ' ') {
    self.scanner.advance(1)
  }

  // Read content (first line + continuation lines with indentation)
  let content_buf = StringBuilder::new()
  let first_line = self.scanner.read_line()
  content_buf.write_string(first_line)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read continuation lines (indented with at least 2 spaces or tab)
  while not(self.scanner.is_eof()) {
    let line_start = self.scanner.pos
    let indent = self.scanner.skip_spaces()
    if self.scanner.is_blank_line() {
      // Blank line may continue or end footnote
      content_buf.write_char('\n')
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
      continue
    }
    if indent >= 2 {
      // Continuation line
      content_buf.write_char('\n')
      let line = self.scanner.read_line()
      content_buf.write_string(line)
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
    } else {
      // Not a continuation, restore and stop
      self.scanner.restore(line_start)
      break
    }
  }

  // Parse content as blocks
  let content = content_buf.to_string()
  let inner_scanner = Scanner::new(content)
  let inner_parser = BlockParser::new(inner_scanner, self.strict)
  let inner_result = inner_parser.parse_document()
  Some(
    Block::FootnoteDefinition(
      label~,
      children=inner_result.document.children,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse link reference definition
fn BlockParser::try_parse_link_definition(
  self : BlockParser,
  start : Int,
) -> LinkDefinition? {
  let saved = self.scanner.pos
  let _ = self.scanner.skip_spaces()

  // [label]:
  if not(char_is(self.scanner.peek(), '[')) {
    return None
  }
  self.scanner.advance(1)

  // Read label
  let label_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some(']') => break
      Some('\n') | None => {
        self.scanner.restore(saved)
        return None
      }
      Some(c) => {
        label_buf.write_char(c)
        self.scanner.advance(1)
      }
    }
  }
  self.scanner.advance(1) // ]
  if not(char_is(self.scanner.peek(), ':')) {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Skip whitespace
  let _ = self.scanner.skip_spaces()
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
    let _ = self.scanner.skip_spaces()

  }

  // Read URL
  let url = if char_is(self.scanner.peek(), '<') {
    self.scanner.advance(1)
    let url_buf = StringBuilder::new()
    while not(self.scanner.is_eof()) && not(char_is(self.scanner.peek(), '>')) {
      match self.scanner.consume() {
        Some(c) => url_buf.write_char(c)
        None => break
      }
    }
    self.scanner.advance(1) // >
    url_buf.to_string()
  } else {
    let url_buf = StringBuilder::new()
    while not(self.scanner.is_eof()) {
      match self.scanner.peek() {
        Some(' ') | Some('\t') | Some('\n') | None => break
        Some(c) => {
          url_buf.write_char(c)
          self.scanner.advance(1)
        }
      }
    }
    url_buf.to_string()
  }
  let _ = self.scanner.skip_spaces()

  // Optional title
  let title = match self.scanner.peek() {
    Some('"') | Some('\'') => {
      let quote = match self.scanner.consume() {
        Some(c) => c
        None => '"'
      }
      let title_buf = StringBuilder::new()
      while not(self.scanner.is_eof()) &&
            not(char_is(self.scanner.peek(), quote)) {
        match self.scanner.consume() {
          Some(c) => title_buf.write_char(c)
          None => break
        }
      }
      if char_is(self.scanner.peek(), quote) {
        self.scanner.advance(1)
      }
      title_buf.to_string()
    }
    _ => ""
  }

  // Skip to end of line
  self.scanner.skip_line()
  let def : LinkDefinition = {
    label: label_buf.to_string().to_lower(),
    url,
    title,
    span: Span::new(start, self.scanner.pos),
  }
  self.definitions.push(def)
  Some(def)
}

///|
/// Parse paragraph (default block type)
fn BlockParser::parse_paragraph(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  let content_buf = StringBuilder::new()
  let mut first = true
  while not(self.scanner.is_eof()) {
    if self.scanner.is_blank_line() {
      break
    }

    // Check for block-level interrupts
    let saved = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    match self.scanner.peek() {
      Some('#') | Some('>') => {
        self.scanner.restore(saved)
        break
      }
      // Only break for fenced code if 3+ backticks/tildes
      // Use peek_at for O(1) check instead of count_char
      Some('`') if self.scanner.peek_at(1) == Some('`') &&
        self.scanner.peek_at(2) == Some('`') => {
        self.scanner.restore(saved)
        break
      }
      Some('~') if self.scanner.peek_at(1) == Some('~') &&
        self.scanner.peek_at(2) == Some('~') => {
        self.scanner.restore(saved)
        break
      }
      Some('-') | Some('*') | Some('_') => {
        // Could be thematic break or list
        match self.try_parse_thematic_break(saved) {
          Some(_) => {
            self.scanner.restore(saved)
            break
          }
          None => ()
        }
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      Some(c) if is_digit(c) => {
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      _ => ()
    }
    self.scanner.restore(saved)
    if not(first) {
      content_buf.write_char('\n')
    }
    let line = self.scanner.read_line()
    content_buf.write_string(line)
    first = false
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  let content = content_buf.to_string()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  let children = parse_inlines(content, strict=self.strict)
  Some(
    Block::Paragraph(
      children~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse GFM table
fn BlockParser::try_parse_table(self : BlockParser, start : Int) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // First line must be a potential header row (contains |)
  let header_line = self.scanner.read_line()
  if not(header_line.contains("|")) {
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Second line must be separator row (contains | and -)
  let separator_line = self.scanner.read_line()
  if not(separator_line.contains("|")) || not(separator_line.contains("-")) {
    self.scanner.restore(saved)
    return None
  }

  // Parse alignments from separator row
  let alignments = parse_table_alignments(separator_line)
  if alignments.is_empty() {
    self.scanner.restore(saved)
    return None
  }

  // Count header columns - must match separator columns for valid table
  let header_cells = split_table_cells(header_line)
  let header_col_count = header_cells
    .filter(fn(c) { not(c.trim(chars=" \t\n\r").is_empty()) })
    .length()
  if header_col_count != alignments.length() {
    // Column count mismatch - not a valid table
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Parse header cells
  let header = parse_table_row(header_line, alignments.length(), self.strict)

  // Parse data rows
  let rows : Array[Array[TableCell]] = []
  while not(self.scanner.is_eof()) && not(self.scanner.is_blank_line()) {
    let row_start = self.scanner.pos
    let row_line = self.scanner.read_line()
    if not(row_line.contains("|")) {
      // Not a table row, restore position and stop
      self.scanner.restore(row_start)
      break
    }
    rows.push(parse_table_row(row_line, alignments.length(), self.strict))
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  Some(
    Block::Table(
      header~,
      alignments~,
      rows~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse table alignments from separator row
fn parse_table_alignments(line : String) -> Array[TableAlign] {
  let alignments : Array[TableAlign] = []
  let cells = split_table_cells(line)
  for cell in cells {
    let trimmed = cell.trim(chars=" \t\n\r").to_string()
    if trimmed.is_empty() {
      continue
    }
    let has_left_colon = trimmed.has_prefix(":")
    let has_right_colon = trimmed.has_suffix(":")

    // Check if it's a valid separator (at least one dash)
    let mut has_dash = false
    for i = 0; i < trimmed.length(); i = i + 1 {
      match trimmed.get_char(i) {
        Some('-') => has_dash = true
        Some(':') => () // Allowed
        _ =>
          // Invalid character in separator
          return []
      }
    }
    if not(has_dash) {
      return []
    }
    let align = if has_left_colon && has_right_colon {
      TableAlign::Center
    } else if has_left_colon {
      TableAlign::Left
    } else if has_right_colon {
      TableAlign::Right
    } else {
      TableAlign::None
    }
    alignments.push(align)
  }
  alignments
}

///|
/// Parse a table row into cells
fn parse_table_row(
  line : String,
  expected_cols : Int,
  strict : Bool,
) -> Array[TableCell] {
  let cells : Array[TableCell] = []
  let raw_cells = split_table_cells(line)
  for i, cell in raw_cells {
    if i >= expected_cols {
      break
    }
    let content = cell.trim(chars=" \t\n\r").to_string()
    let children = parse_inlines(content, strict~)
    cells.push({ children, span: Span::new(0, content.length()) }, // Simplified span
    )
  }

  // Pad with empty cells if needed
  while cells.length() < expected_cols {
    cells.push({ children: [], span: Span::new(0, 0) })
  }
  cells
}

///|
/// Split table row into cells by |
fn split_table_cells(line : String) -> Array[String] {
  let cells : Array[String] = []
  let buf = StringBuilder::new()
  let mut in_escape = false
  for i = 0; i < line.length(); i = i + 1 {
    match line.get_char(i) {
      Some('\\') if not(in_escape) => {
        in_escape = true
        buf.write_char('\\')
      }
      Some('|') if not(in_escape) => {
        cells.push(buf.to_string())
        // Reset buffer by creating new one
        buf.reset()
      }
      Some(c) => {
        in_escape = false
        buf.write_char(c)
      }
      None => ()
    }
  }

  // Add last cell
  let last = buf.to_string()
  if not(last.trim(chars=" \t\n\r").is_empty()) {
    cells.push(last)
  }

  // Remove first cell if empty (leading |)
  if cells.length() > 0 {
    match cells[0].trim(chars=" \t\n\r").to_string() {
      "" => {
        let _ = cells.remove(0)

      }
      _ => ()
    }
  }
  cells
}

///|
/// Try to parse frontmatter (YAML between --- delimiters)
fn BlockParser::try_parse_frontmatter(self : BlockParser) -> Frontmatter? {
  let start = self.scanner.pos

  // Must start at beginning of document
  if start != 0 {
    return None
  }

  // Check for opening ---
  if not(self.scanner.matches("---")) {
    return None
  }
  self.scanner.advance(3)

  // Skip to end of line
  let _ = self.scanner.skip_spaces()
  if not(char_is(self.scanner.peek(), '\n')) && not(self.scanner.is_eof()) {
    self.scanner.restore(start)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read YAML content until closing ---
  let yaml_buf = StringBuilder::new()
  let mut found_closing = false
  while not(self.scanner.is_eof()) {
    if self.scanner.matches("---") {
      self.scanner.advance(3)
      let _ = self.scanner.skip_spaces()
      if char_is(self.scanner.peek(), '\n') || self.scanner.is_eof() {
        if char_is(self.scanner.peek(), '\n') {
          self.scanner.advance(1)
        }
        found_closing = true
        break
      }
      // Not a valid closing, continue reading
      yaml_buf.write_string("---")
    } else {
      let line = self.scanner.read_line()
      yaml_buf.write_string(line)
      if char_is(self.scanner.peek(), '\n') {
        yaml_buf.write_char('\n')
        self.scanner.advance(1)
      }
    }
  }

  // Must have found closing --- to be valid frontmatter
  if not(found_closing) {
    self.scanner.restore(start)
    return None
  }
  let raw = yaml_buf.to_string()
  let entries = parse_simple_yaml(raw)
  Some({ raw, entries, span: Span::new(start, self.scanner.pos) })
}

///|
/// Parse simple YAML (key: value pairs only)
fn parse_simple_yaml(yaml : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  let lines = yaml.split("\n")
  for line in lines {
    let trimmed = line.to_string().trim(chars=" \t\n\r")
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.find(":") {
      Some(colon_idx) => {
        let key = trimmed
          .view(end_offset=colon_idx)
          .to_string()
          .trim(chars=" \t\n\r")
          .to_string()
        let value = trimmed
          .view(start_offset=colon_idx + 1)
          .to_string()
          .trim(chars=" \t\n\r")
          .to_string()
        // Remove quotes if present
        let clean_value = if value.has_prefix("\"") && value.has_suffix("\"") {
          value.unsafe_substring(start=1, end=value.length() - 1)
        } else if value.has_prefix("'") && value.has_suffix("'") {
          value.unsafe_substring(start=1, end=value.length() - 1)
        } else {
          value
        }
        entries.push((key, clean_value))
      }
      None => ()
    }
  }
  entries
}

///|
/// Read leading trivia (whitespace before content)
fn BlockParser::read_leading_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let count = self.scanner.skip_spaces()
  if count > 0 {
    Trivia::new(self.scanner.substring(start, start + count))
  } else {
    Trivia::empty()
  }
}

///|
/// Read trailing trivia (whitespace after content including newline)
fn BlockParser::read_trailing_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let _ = self.scanner.skip_spaces()
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  if self.scanner.pos > start {
    Trivia::new(self.scanner.substring(start, self.scanner.pos))
  } else {
    Trivia::empty()
  }
}
