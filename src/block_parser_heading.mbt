///| ATX and setext heading parsing.

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
  let children = self.parse_inline_content(content)
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
  let trimmed = line.trim_end(chars=" \t").to_owned()

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
      .to_owned()
    (content, hash_count)
  } else {
    (trimmed, 0)
  }
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
  if !char_is(self.scanner.peek(), '\n') && !self.scanner.is_eof() {
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let content_str = content.trim(chars=" \t\n\r").to_owned()
  let children = self.parse_inline_content(content_str)
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
