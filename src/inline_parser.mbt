///| Inline-level markdown parser

///| Parses emphasis, strong, code, links, images, etc.

///|
/// Check if inlines array contains a link (used for nested link detection)
fn contains_link(inlines : Array[Inline]) -> Bool {
  for inline in inlines {
    match inline {
      Inline::Link(..) | Inline::RefLink(..) => return true
      Inline::Emphasis(children~, ..)
      | Inline::Strong(children~, ..)
      | Inline::Strikethrough(children~, ..) =>
        if contains_link(children) {
          return true
        }
      _ => ()
    }
  }
  false
}

///| Trim trailing spaces from the last Text element in inlines array

///|
/// Optimized to avoid allocation when no trimming is needed
fn trim_trailing_space_from_last_text(inlines : Array[Inline]) -> Unit {
  guard inlines.length() > 0 else { return }
  guard inlines[inlines.length() - 1] is Inline::Text(content~, span~) else {
    return
  }
  let len = content.length()
  guard len > 0 else { return }
  // Quick check: does it end with space?
  guard content.unsafe_get(len - 1) == ' ' else { return }
  // Find last non-space character
  let mut end = len - 1
  while end > 0 && content.unsafe_get(end - 1) == ' ' {
    end = end - 1
  }
  // Now trim
  let _ = inlines.pop()
  if end > 0 {
    inlines.push(
      Inline::Text(content=content.unsafe_substring(start=0, end~), span~),
    )
  }
}

///| Parse inline content from text

///| When strict=true, uses delimiter stack algorithm for full CommonMark compliance

///|
/// When strict=false (default), uses fast single-pass parser
pub fn parse_inlines(
  text : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  if strict {
    // In strict mode, always use delimiter stack for full CommonMark compliance
    parse_inlines_with_delimiter_stack(text, wikilinks~)
  } else {
    parse_inlines_fast(text, wikilinks~)
  }
}

///|
/// Fast path: simple inline parsing without delimiter stack
fn parse_inlines_fast(
  text : String,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  let scanner = Scanner::new(text)
  let parser = InlineParser::new(scanner, wikilinks~)
  parser.parse()
}

///|
/// Inline parser state
priv struct InlineParser {
  scanner : Scanner
  wikilinks : Bool
}

///|
fn InlineParser::new(
  scanner : Scanner,
  wikilinks? : Bool = false,
) -> InlineParser {
  { scanner, wikilinks }
}

///|
/// Parse all inline content
fn InlineParser::parse(self : InlineParser) -> Array[Inline] {
  let inlines : Array[Inline] = []
  while !self.scanner.is_eof() {
    match self.parse_inline() {
      Some(inline) => {
        // For soft/hard breaks, trim trailing whitespace from previous text
        match inline {
          Inline::SoftBreak(..) | Inline::HardBreak(..) =>
            trim_trailing_space_from_last_text(inlines)
          _ => ()
        }
        inlines.push(inline)
      }
      None => {
        // Consume single character as text
        let start = self.scanner.pos
        match self.scanner.consume() {
          Some(c) => {
            // Merge with previous text if possible
            let text = String::make(1, c)
            match inlines.last() {
              Some(Inline::Text(content~, span~)) => {
                // Merge with previous text
                let _ = inlines.pop()
                inlines.push(
                  Inline::Text(
                    content=content + text,
                    span=Span::new(span.from, self.scanner.pos),
                  ),
                )
              }
              _ =>
                inlines.push(
                  Inline::Text(
                    content=text,
                    span=Span::new(start, self.scanner.pos),
                  ),
                )
            }
          }
          None => break
        }
      }
    }
  }
  inlines
}

///|
/// Parse a single inline element
fn InlineParser::parse_inline(self : InlineParser) -> Inline? {
  let start = self.scanner.pos
  match self.scanner.peek() {
    // Backslash escape
    Some('\\') => self.try_parse_escape(start)

    // Code span
    Some('`') => self.try_parse_code_span(start)

    // Emphasis/Strong with asterisk
    Some('*') => self.try_parse_emphasis(start, '*')

    // Emphasis/Strong with underscore
    Some('_') => self.try_parse_emphasis(start, '_')

    // Strikethrough
    Some('~') => self.try_parse_strikethrough(start)

    // WikiLink, Footnote reference, Link, or Image
    Some('[') =>
      if self.wikilinks && char_is(self.scanner.peek_at(1), '[') {
        match self.try_parse_wikilink(start) {
          Some(wikilink) => Some(wikilink)
          None => self.try_parse_link(start)
        }
      } else if char_is(self.scanner.peek_at(1), '^') {
        // Check for footnote reference [^label]
        match self.try_parse_footnote_reference(start) {
          Some(fn_ref) => Some(fn_ref)
          None => self.try_parse_link(start)
        }
      } else {
        self.try_parse_link(start)
      }
    Some('!') => self.try_parse_image(start)

    // Raw inline HTML or autolink
    Some('<') =>
      match self.try_parse_html_comment(start) {
        Some(comment) => Some(comment)
        None => self.try_parse_autolink(start)
      }

    // Hard break (two spaces at end of line)
    Some(' ') => self.try_parse_hard_break(start)

    // Soft break (newline)
    Some('\n') => {
      self.scanner.advance(1)
      // Skip leading whitespace after newline (CommonMark spec)
      while char_is(self.scanner.peek(), ' ') {
        self.scanner.advance(1)
      }
      Some(Inline::SoftBreak(span=Span::new(start, self.scanner.pos)))
    }
    _ => None
  }
}

///|
/// Try to parse backslash escape
fn InlineParser::try_parse_escape(self : InlineParser, start : Int) -> Inline? {
  self.scanner.advance(1) // Skip backslash
  match self.scanner.peek() {
    Some('\n') => {
      // Backslash + newline = hard break
      self.scanner.advance(1)
      // Skip leading whitespace after newline (CommonMark spec)
      while char_is(self.scanner.peek(), ' ') {
        self.scanner.advance(1)
      }
      Some(
        Inline::HardBreak(
          style=HardBreakStyle::Backslash,
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
    Some(c) if is_punctuation(c) => {
      // Escaped punctuation becomes literal text
      self.scanner.advance(1)
      Some(
        Inline::Text(
          content=String::make(1, c),
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
    _ =>
      // Not a valid escape, return backslash as text
      Some(Inline::Text(content="\\", span=Span::new(start, self.scanner.pos)))
  }
}

///|
/// Try to parse code span
fn InlineParser::try_parse_code_span(
  self : InlineParser,
  start : Int,
) -> Inline? {
  // Count opening backticks
  let backtick_count = self.scanner.count_char('`')
  if backtick_count == 0 {
    return None
  }
  self.scanner.advance(backtick_count)

  // Find closing backticks
  let content_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    let closing_count = self.scanner.count_char('`')
    if closing_count == backtick_count {
      // Found matching closing backticks
      let content = content_buf.to_string()
      self.scanner.advance(closing_count)

      // Trim single leading/trailing space if present and content has them
      // But NOT if content is entirely spaces
      let trimmed = if content.length() >= 2 {
        let first = content.get_char(0)
        let last = content.get_char(content.length() - 1)
        if first == Some(' ') && last == Some(' ') && !is_all_spaces(content) {
          content.unsafe_substring(start=1, end=content.length() - 1)
        } else {
          content
        }
      } else {
        content
      }
      return Some(
        Inline::Code(
          content=trimmed,
          backtick_count~,
          span=Span::new(start, self.scanner.pos),
        ),
      )
    } else if closing_count > 0 {
      // Wrong number of backticks, include them in content
      for i = 0; i < closing_count; i = i + 1 {
        content_buf.write_char('`')
      }
      self.scanner.advance(closing_count)
    } else {
      // Regular character
      match self.scanner.consume() {
        Some(c) => content_buf.write_char(c)
        None => break
      }
    }
  }

  // No closing backticks found, restore position
  self.scanner.restore(start)
  None
}

///|
/// Try to parse emphasis or strong
fn InlineParser::try_parse_emphasis(
  self : InlineParser,
  start : Int,
  marker_char : Char,
) -> Inline? {
  // Count opening markers
  let marker_count = self.scanner.count_char(marker_char)
  if marker_count == 0 {
    return None
  }

  // Only handle 1 or 2 markers (emphasis or strong)
  let is_strong = marker_count >= 2
  let consume_count = if is_strong { 2 } else { 1 }
  self.scanner.advance(consume_count)

  // Check if followed by whitespace (not valid opener)
  match self.scanner.peek() {
    Some(' ') | Some('\t') | Some('\n') | None => {
      self.scanner.restore(start)
      return None
    }
    _ => ()
  }

  // Parse content until closing marker
  let children = self.parse_until_closing_marker(marker_char, consume_count)
  if children.is_empty() {
    self.scanner.restore(start)
    return None
  }
  let marker = if marker_char == '*' {
    EmphasisMarker::Asterisk
  } else {
    EmphasisMarker::Underscore
  }
  if is_strong {
    Some(
      Inline::Strong(
        marker~,
        children~,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  } else {
    Some(
      Inline::Emphasis(
        marker~,
        children~,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  }
}

///|
/// Parse content until closing marker
fn InlineParser::parse_until_closing_marker(
  self : InlineParser,
  marker_char : Char,
  marker_count : Int,
) -> Array[Inline] {
  let children : Array[Inline] = []
  let text_buf = StringBuilder::new()
  let text_start = self.scanner.pos
  while !self.scanner.is_eof() {
    // Check for closing marker
    let closing_count = self.scanner.count_char(marker_char)
    if closing_count >= marker_count {
      // Check if preceded by non-whitespace
      let prev_char = self.scanner.peek_at(-1)
      match prev_char {
        Some(' ') | Some('\t') | Some('\n') => () // Not valid closer
        _ => {
          // Valid closer - flush text and consume markers
          if !text_buf.is_empty() {
            children.push(
              Inline::Text(
                content=text_buf.to_string(),
                span=Span::new(text_start, self.scanner.pos),
              ),
            )
          }
          self.scanner.advance(marker_count)
          return children
        }
      }
    }

    // Handle nested inline elements
    match self.scanner.peek() {
      Some('`') => {
        // Flush text before inline
        if !text_buf.is_empty() {
          children.push(
            Inline::Text(
              content=text_buf.to_string(),
              span=Span::new(text_start, self.scanner.pos),
            ),
          )
        }
        let nested_start = self.scanner.pos
        match self.try_parse_code_span(nested_start) {
          Some(code) => {
            children.push(code)
            continue
          }
          None => ()
        }
      }
      Some('[') => {
        if !text_buf.is_empty() {
          children.push(
            Inline::Text(
              content=text_buf.to_string(),
              span=Span::new(text_start, self.scanner.pos),
            ),
          )
        }
        let nested_start = self.scanner.pos
        match self.try_parse_link(nested_start) {
          Some(link) => {
            children.push(link)
            continue
          }
          None => ()
        }
      }
      Some('\n') =>
        // Newline ends emphasis in most cases
        break
      _ => ()
    }

    // Regular character
    match self.scanner.consume() {
      Some(c) => text_buf.write_char(c)
      None => break
    }
  }

  // No closing marker found
  []
}

///|
/// Try to parse strikethrough
fn InlineParser::try_parse_strikethrough(
  self : InlineParser,
  start : Int,
) -> Inline? {
  // Need exactly two tildes
  if self.scanner.count_char('~') < 2 {
    return None
  }
  self.scanner.advance(2)

  // Parse content until closing ~~
  let content_buf = StringBuilder::new()
  let content_start = self.scanner.pos
  while !self.scanner.is_eof() {
    if self.scanner.count_char('~') >= 2 {
      // Found closing
      let content = content_buf.to_string()
      if content.is_empty() {
        self.scanner.restore(start)
        return None
      }
      self.scanner.advance(2)
      let children = [
        Inline::Text(
          content~,
          span=Span::new(content_start, self.scanner.pos - 2),
        ),
      ]
      return Some(
        Inline::Strikethrough(
          children~,
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
    match self.scanner.consume() {
      Some('\n') => break // Newline ends strikethrough
      Some(c) => content_buf.write_char(c)
      None => break
    }
  }
  self.scanner.restore(start)
  None
}


///|
/// Try to parse an inline HTML comment
fn InlineParser::try_parse_html_comment(
  self : InlineParser,
  start : Int,
) -> Inline? {
  if !self.scanner.matches("<!--") {
    return None
  }
  self.scanner.advance(4)
  while !self.scanner.is_eof() {
    if self.scanner.matches("-->") {
      self.scanner.advance(3)
      return Some(
        Inline::HtmlInline(
          html=self.scanner.substring(start, self.scanner.pos),
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
    self.scanner.advance(1)
  }
  self.scanner.restore(start)
  None
}

///|
/// Try to parse autolink
fn InlineParser::try_parse_autolink(
  self : InlineParser,
  start : Int,
) -> Inline? {
  self.scanner.advance(1) // Skip <
  let url_buf = StringBuilder::new()
  let mut is_email = false
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some('>') => {
        self.scanner.advance(1)
        let url = url_buf.to_string()

        // Check if it's an email
        if url.contains("@") && !url.has_prefix("http") {
          is_email = true
        }
        return Some(
          Inline::Autolink(
            url~,
            is_email~,
            span=Span::new(start, self.scanner.pos),
          ),
        )
      }
      Some(' ') | Some('\t') | Some('\n') => {
        // Not a valid autolink
        self.scanner.restore(start)
        return None
      }
      Some(c) => {
        url_buf.write_char(c)
        self.scanner.advance(1)
      }
      None => break
    }
  }
  self.scanner.restore(start)
  None
}

///|
/// Try to parse hard break (two or more spaces followed by newline)
fn InlineParser::try_parse_hard_break(
  self : InlineParser,
  start : Int,
) -> Inline? {
  let space_count = self.scanner.count_char(' ')
  if space_count < 2 {
    return None
  }
  self.scanner.advance(space_count)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
    // Skip leading whitespace after newline (CommonMark spec)
    while char_is(self.scanner.peek(), ' ') {
      self.scanner.advance(1)
    }
    return Some(
      Inline::HardBreak(
        style=HardBreakStyle::TwoSpaces,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  }

  // Not followed by newline, restore and return None
  self.scanner.restore(start)
  None
}

///|
/// Check if a string is entirely space characters
fn is_all_spaces(s : String) -> Bool {
  for c in s {
    if c != ' ' {
      return false
    }
  }
  true
}

