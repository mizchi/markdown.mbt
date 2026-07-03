///| Link reference definitions and GFM footnote definitions.

///|

///| Split out from block_parser.mbt to keep that file focused on the block

///| dispatcher and paragraph parsing.

///|
/// Try to parse GFM footnote definition [^label]: content
fn BlockParser::try_parse_footnote_definition(
  self : BlockParser,
  start : Int,
) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // [^label]:
  if !char_is(self.scanner.peek(), '[') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)
  if !char_is(self.scanner.peek(), '^') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Read label (alphanumeric, -, _)
  let label_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
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
  if !char_is(self.scanner.peek(), ':') {
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
  self.scanner.append_line_to(content_buf)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read continuation lines (indented with at least 2 spaces or tab)
  while !self.scanner.is_eof() {
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
      self.scanner.append_line_to(content_buf)
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
  let inner_scanner = if self.scanner.is_bmp() {
    Scanner::new_bmp(content)
  } else {
    Scanner::new(content)
  }
  let inner_parser = BlockParser::new(
    inner_scanner,
    self.strict,
    self.wikilinks,
  )
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
  if !char_is(self.scanner.peek(), '[') {
    return None
  }
  self.scanner.advance(1)

  // Read label
  let label_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
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
  if !char_is(self.scanner.peek(), ':') {
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
    while !self.scanner.is_eof() && !char_is(self.scanner.peek(), '>') {
      match self.scanner.consume() {
        Some(c) => url_buf.write_char(c)
        None => break
      }
    }
    self.scanner.advance(1) // >
    url_buf.to_string()
  } else {
    let url_buf = StringBuilder::new()
    while !self.scanner.is_eof() {
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
      while !self.scanner.is_eof() && !char_is(self.scanner.peek(), quote) {
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
