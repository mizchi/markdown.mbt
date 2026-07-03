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

///|
fn append_text(inlines : Array[Inline], content : String, span : Span) -> Unit {
  guard !content.is_empty() else { return }
  match inlines.last() {
    Some(Inline::Text(content=prev, span=prev_span)) => {
      let _ = inlines.pop()
      inlines.push(
        Inline::Text(
          content=prev + content,
          span=Span::new(prev_span.from, span.to),
        ),
      )
    }
    _ => inlines.push(Inline::Text(content~, span~))
  }
}

///|
fn is_inline_marker(c : Char) -> Bool {
  match c {
    '\\' | '`' | '*' | '_' | '~' | '[' | '!' | '<' | '\n' => true
    _ => false
  }
}

///|
fn is_inline_marker_code_unit(c : UInt16) -> Bool {
  match c {
    0x5C | 0x60 | 0x2A | 0x5F | 0x7E | 0x5B | 0x21 | 0x3C | 0x0A => true
    _ => false
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
fn parse_inlines_known_bmp(
  text : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  if strict {
    parse_inlines_with_delimiter_stack(text, wikilinks~, known_bmp=true)
  } else {
    let scanner = Scanner::new_bmp(text)
    let parser = InlineParser::new(scanner, wikilinks~)
    parser.parse()
  }
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
        let start = self.scanner.pos
        let text = self.read_text_run(start)
        if text.is_empty() {
          break
        }
        append_text(inlines, text, Span::new(start, self.scanner.pos))
      }
    }
  }
  inlines
}

///|
fn InlineParser::read_text_run(self : InlineParser, start : Int) -> String {
  let mut idx = start
  match self.scanner.utf16_offsets {
    Some(_) =>
      while idx < self.scanner.len {
        let c = self.scanner.chars[idx]
        if c == ' ' {
          let space_start = idx
          while idx < self.scanner.len && self.scanner.chars[idx] == ' ' {
            idx += 1
          }
          if idx - space_start >= 2 &&
            idx < self.scanner.len &&
            self.scanner.chars[idx] == '\n' {
            idx = space_start
            break
          }
        } else if is_inline_marker(c) {
          break
        } else {
          idx += 1
        }
      }
    None =>
      while idx < self.scanner.len {
        let c = self.scanner.source.unsafe_get(idx)
        if c == 0x20 {
          let space_start = idx
          while idx < self.scanner.len &&
                self.scanner.source.unsafe_get(idx) == 0x20 {
            idx += 1
          }
          if idx - space_start >= 2 &&
            idx < self.scanner.len &&
            self.scanner.source.unsafe_get(idx) == 0x0A {
            idx = space_start
            break
          }
        } else if is_inline_marker_code_unit(c) {
          break
        } else {
          idx += 1
        }
      }
  }
  self.scanner.pos = idx

  if self.scanner.pos > start {
    self.scanner.substring(start, self.scanner.pos)
  } else {
    match self.scanner.consume() {
      Some(c) => String::make(1, c)
      None => ""
    }
  }
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
