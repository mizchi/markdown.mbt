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
pub fn parse_inlines(text : String, strict? : Bool = false) -> Array[Inline] {
  if strict {
    // In strict mode, always use delimiter stack for full CommonMark compliance
    parse_inlines_with_delimiter_stack(text)
  } else {
    parse_inlines_fast(text)
  }
}

///|
/// Fast path: simple inline parsing without delimiter stack
fn parse_inlines_fast(text : String) -> Array[Inline] {
  let scanner = Scanner::new(text)
  let parser = InlineParser::new(scanner)
  parser.parse()
}

///|
/// Inline parser state
priv struct InlineParser {
  scanner : Scanner
}

///|
fn InlineParser::new(scanner : Scanner) -> InlineParser {
  { scanner, }
}

///|
/// Parse all inline content
fn InlineParser::parse(self : InlineParser) -> Array[Inline] {
  let inlines : Array[Inline] = []
  while not(self.scanner.is_eof()) {
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

    // Footnote reference, Link, or Image
    Some('[') =>
      // Check for footnote reference [^label]
      if char_is(self.scanner.peek_at(1), '^') {
        match self.try_parse_footnote_reference(start) {
          Some(fn_ref) => Some(fn_ref)
          None => self.try_parse_link(start)
        }
      } else {
        self.try_parse_link(start)
      }
    Some('!') => self.try_parse_image(start)

    // Autolink
    Some('<') => self.try_parse_autolink(start)

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
  while not(self.scanner.is_eof()) {
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
        if first == Some(' ') &&
          last == Some(' ') &&
          not(is_all_spaces(content)) {
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
  while not(self.scanner.is_eof()) {
    // Check for closing marker
    let closing_count = self.scanner.count_char(marker_char)
    if closing_count >= marker_count {
      // Check if preceded by non-whitespace
      let prev_char = self.scanner.peek_at(-1)
      match prev_char {
        Some(' ') | Some('\t') | Some('\n') => () // Not valid closer
        _ => {
          // Valid closer - flush text and consume markers
          if not(text_buf.is_empty()) {
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
        if not(text_buf.is_empty()) {
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
        if not(text_buf.is_empty()) {
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
  while not(self.scanner.is_eof()) {
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
/// Try to parse link
fn InlineParser::try_parse_link(self : InlineParser, start : Int) -> Inline? {
  self.scanner.advance(1) // Skip [

  // Parse link text
  let text_buf = StringBuilder::new()
  let mut bracket_depth = 1
  while not(self.scanner.is_eof()) && bracket_depth > 0 {
    match self.scanner.peek() {
      Some('[') => {
        bracket_depth += 1
        text_buf.write_char('[')
        self.scanner.advance(1)
      }
      Some(']') => {
        bracket_depth -= 1
        if bracket_depth > 0 {
          text_buf.write_char(']')
        }
        self.scanner.advance(1)
      }
      Some('\\') => {
        self.scanner.advance(1)
        match self.scanner.consume() {
          Some(c) => text_buf.write_char(c)
          None => break
        }
      }
      Some(c) => {
        text_buf.write_char(c)
        self.scanner.advance(1)
      }
      None => break
    }
  }
  let link_text = text_buf.to_string()

  // Check for inline link (url)
  if char_is(self.scanner.peek(), '(') {
    self.scanner.advance(1)

    // Parse URL
    let url_buf = StringBuilder::new()
    let mut paren_depth = 1

    // Skip leading whitespace
    let _ = self.scanner.skip_spaces()

    // Check for angle-bracketed URL
    if char_is(self.scanner.peek(), '<') {
      self.scanner.advance(1)
      let mut angle_url_has_newline = false
      while not(self.scanner.is_eof()) {
        match self.scanner.peek() {
          Some('>') => {
            self.scanner.advance(1)
            break
          }
          Some('\n') => {
            // Newline in angle-bracket URL invalidates the link
            angle_url_has_newline = true
            break
          }
          Some(c) => {
            url_buf.write_char(c)
            self.scanner.advance(1)
          }
          None => break
        }
      }
      if angle_url_has_newline {
        self.scanner.restore(start)
        return None
      }
    } else {
      let mut url_has_newline = false
      while not(self.scanner.is_eof()) {
        match self.scanner.peek() {
          Some('(') => {
            paren_depth += 1
            url_buf.write_char('(')
            self.scanner.advance(1)
          }
          Some(')') => {
            paren_depth -= 1
            if paren_depth == 0 {
              break
            }
            url_buf.write_char(')')
            self.scanner.advance(1)
          }
          Some(' ') | Some('\t') => break // End of URL
          Some('\n') => {
            // Newline in non-angle-bracket URL invalidates the link
            url_has_newline = true
            break
          }
          Some(c) => {
            url_buf.write_char(c)
            self.scanner.advance(1)
          }
          None => break
        }
      }
      // If URL contains newline, abort link parsing
      if url_has_newline {
        self.scanner.restore(start)
        return None
      }
    }
    let url = url_buf.to_string()

    // Skip whitespace (including newlines) before title
    while not(self.scanner.is_eof()) {
      match self.scanner.peek() {
        Some(' ') | Some('\t') | Some('\n') => self.scanner.advance(1)
        _ => break
      }
    }

    // Parse optional title (supports ", ', and () delimiters)
    let title = match self.scanner.peek() {
      Some('"') | Some('\'') => {
        let quote = match self.scanner.consume() {
          Some(c) => c
          None => '"'
        }
        let title_buf = StringBuilder::new()
        while not(self.scanner.is_eof()) {
          match self.scanner.peek() {
            Some(c) if c == quote => {
              self.scanner.advance(1)
              break
            }
            Some('\\') => {
              self.scanner.advance(1)
              match self.scanner.consume() {
                Some(c) => title_buf.write_char(c)
                None => break
              }
            }
            Some(c) => {
              title_buf.write_char(c)
              self.scanner.advance(1)
            }
            None => break
          }
        }
        title_buf.to_string()
      }
      Some('(') => {
        self.scanner.advance(1) // Skip opening (
        let title_buf = StringBuilder::new()
        let mut paren_depth = 1
        while not(self.scanner.is_eof()) && paren_depth > 0 {
          match self.scanner.peek() {
            Some(')') => {
              paren_depth -= 1
              if paren_depth == 0 {
                self.scanner.advance(1)
                break
              }
              title_buf.write_char(')')
              self.scanner.advance(1)
            }
            Some('(') => {
              paren_depth += 1
              title_buf.write_char('(')
              self.scanner.advance(1)
            }
            Some('\\') => {
              self.scanner.advance(1)
              match self.scanner.consume() {
                Some(c) => title_buf.write_char(c)
                None => break
              }
            }
            Some(c) => {
              title_buf.write_char(c)
              self.scanner.advance(1)
            }
            None => break
          }
        }
        title_buf.to_string()
      }
      _ => ""
    }

    // Skip whitespace and closing paren
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), ')') {
      self.scanner.advance(1)

      // Parse link text as inlines
      let children = parse_inlines(link_text)

      // CommonMark: Links cannot contain other links
      // If link text contains a link, the outer link is invalid
      if contains_link(children) {
        self.scanner.restore(start)
        return None
      }
      return Some(
        Inline::Link(
          children~,
          url~,
          title~,
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
  }

  // Check for reference link [text][ref]
  if char_is(self.scanner.peek(), '[') {
    self.scanner.advance(1)
    let label_buf = StringBuilder::new()
    while not(self.scanner.is_eof()) {
      match self.scanner.peek() {
        Some(']') => {
          self.scanner.advance(1)
          break
        }
        Some(c) => {
          label_buf.write_char(c)
          self.scanner.advance(1)
        }
        None => break
      }
    }
    let label = label_buf.to_string()
    let children = parse_inlines(link_text)

    // CommonMark: Links cannot contain other links
    if contains_link(children) {
      self.scanner.restore(start)
      return None
    }
    return Some(
      Inline::RefLink(
        children~,
        label~,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  }

  // Not a valid link
  self.scanner.restore(start)
  None
}

///|
/// Try to parse footnote reference [^label]
fn InlineParser::try_parse_footnote_reference(
  self : InlineParser,
  start : Int,
) -> Inline? {
  self.scanner.advance(1) // Skip [
  if not(char_is(self.scanner.peek(), '^')) {
    self.scanner.restore(start)
    return None
  }
  self.scanner.advance(1) // Skip ^

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
        self.scanner.restore(start)
        return None
      }
    }
  }
  let label = label_buf.to_string()
  if label.is_empty() {
    self.scanner.restore(start)
    return None
  }
  if not(char_is(self.scanner.peek(), ']')) {
    self.scanner.restore(start)
    return None
  }
  self.scanner.advance(1) // Skip ]
  Some(
    Inline::FootnoteReference(label~, span=Span::new(start, self.scanner.pos)),
  )
}

///|
/// Try to parse image
fn InlineParser::try_parse_image(self : InlineParser, start : Int) -> Inline? {
  self.scanner.advance(1) // Skip !
  if not(char_is(self.scanner.peek(), '[')) {
    self.scanner.restore(start)
    return None
  }
  self.scanner.advance(1) // Skip [

  // Parse alt text
  let alt_buf = StringBuilder::new()
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some(']') => {
        self.scanner.advance(1)
        break
      }
      Some('\\') => {
        self.scanner.advance(1)
        match self.scanner.consume() {
          Some(c) => alt_buf.write_char(c)
          None => break
        }
      }
      Some(c) => {
        alt_buf.write_char(c)
        self.scanner.advance(1)
      }
      None => break
    }
  }
  let alt = alt_buf.to_string()

  // Check for inline image (url)
  if char_is(self.scanner.peek(), '(') {
    self.scanner.advance(1)

    // Parse URL (same as link)
    let url_buf = StringBuilder::new()
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), '<') {
      self.scanner.advance(1)
      while not(self.scanner.is_eof()) {
        match self.scanner.peek() {
          Some('>') => {
            self.scanner.advance(1)
            break
          }
          Some(c) => {
            url_buf.write_char(c)
            self.scanner.advance(1)
          }
          None => break
        }
      }
    } else {
      while not(self.scanner.is_eof()) {
        match self.scanner.peek() {
          Some(')') | Some(' ') | Some('\t') => break
          Some(c) => {
            url_buf.write_char(c)
            self.scanner.advance(1)
          }
          None => break
        }
      }
    }
    let url = url_buf.to_string()
    let _ = self.scanner.skip_spaces()

    // Parse optional title
    let title = match self.scanner.peek() {
      Some('"') | Some('\'') => {
        let quote = match self.scanner.consume() {
          Some(c) => c
          None => '"'
        }
        let title_buf = StringBuilder::new()
        while not(self.scanner.is_eof()) {
          match self.scanner.peek() {
            Some(c) if c == quote => {
              self.scanner.advance(1)
              break
            }
            Some(c) => {
              title_buf.write_char(c)
              self.scanner.advance(1)
            }
            None => break
          }
        }
        title_buf.to_string()
      }
      _ => ""
    }
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), ')') {
      self.scanner.advance(1)
      return Some(
        Inline::Image(
          alt~,
          url~,
          title~,
          span=Span::new(start, self.scanner.pos),
        ),
      )
    }
  }

  // Check for reference image ![alt][ref]
  if char_is(self.scanner.peek(), '[') {
    self.scanner.advance(1)
    let label_buf = StringBuilder::new()
    while not(self.scanner.is_eof()) {
      match self.scanner.peek() {
        Some(']') => {
          self.scanner.advance(1)
          break
        }
        Some(c) => {
          label_buf.write_char(c)
          self.scanner.advance(1)
        }
        None => break
      }
    }
    return Some(
      Inline::RefImage(
        alt~,
        label=label_buf.to_string(),
        span=Span::new(start, self.scanner.pos),
      ),
    )
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
  while not(self.scanner.is_eof()) {
    match self.scanner.peek() {
      Some('>') => {
        self.scanner.advance(1)
        let url = url_buf.to_string()

        // Check if it's an email
        if url.contains("@") && not(url.has_prefix("http")) {
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

// ============================================================================
// Delimiter Stack Algorithm for Complex Emphasis
// ============================================================================

///|
/// Delimiter entry for the stack algorithm
priv struct Delimiter {
  pos : Int // Position in text
  marker : Char // '*' or '_'
  length : Int // Number of consecutive markers
  mut remaining : Int // Remaining markers not yet matched
  can_open : Bool // Can this be an opener?
  can_close : Bool // Can this be a closer?
  mut active : Bool // Is this delimiter still active?
}

///|
/// Parse inlines using delimiter stack algorithm (CommonMark spec)
fn parse_inlines_with_delimiter_stack(text : String) -> Array[Inline] {
  let chars : Array[Char] = text.to_array()
  let len = chars.length()

  // Phase 1: Collect all delimiters
  let delimiters : Array[Delimiter] = []
  let mut i = 0
  while i < len {
    let c = chars[i]
    if c == '*' || c == '_' {
      // Count consecutive markers
      let start = i
      let marker = c
      let mut count = 0
      while i < len && chars[i] == marker {
        count += 1
        i += 1
      }

      // Determine flanking status (CommonMark rules)
      let before = if start > 0 { Some(chars[start - 1]) } else { None }
      let after = if i < len { Some(chars[i]) } else { None }
      let before_is_whitespace = match before {
        None => true
        Some(ch) => is_unicode_whitespace(ch)
      }
      let before_is_punctuation = match before {
        None => false
        Some(ch) => is_unicode_punctuation(ch)
      }
      let after_is_whitespace = match after {
        None => true
        Some(ch) => is_unicode_whitespace(ch)
      }
      let after_is_punctuation = match after {
        None => false
        Some(ch) => is_unicode_punctuation(ch)
      }

      // Left-flanking: not followed by whitespace, and either
      // (a) not followed by punctuation, or (b) preceded by whitespace or punctuation
      let left_flanking = not(after_is_whitespace) &&
        (
          not(after_is_punctuation) ||
          before_is_whitespace ||
          before_is_punctuation
        )

      // Right-flanking: not preceded by whitespace, and either
      // (a) not preceded by punctuation, or (b) followed by whitespace or punctuation
      let right_flanking = not(before_is_whitespace) &&
        (
          not(before_is_punctuation) ||
          after_is_whitespace ||
          after_is_punctuation
        )

      // For underscore, additional rules apply
      let (can_open, can_close) = if marker == '_' {
        // _ can open if left-flanking and (not right-flanking or preceded by punctuation)
        // _ can close if right-flanking and (not left-flanking or followed by punctuation)
        (
          left_flanking && (not(right_flanking) || before_is_punctuation),
          right_flanking && (not(left_flanking) || after_is_punctuation),
        )
      } else {
        // * can open if left-flanking
        // * can close if right-flanking
        (left_flanking, right_flanking)
      }
      if can_open || can_close {
        delimiters.push(Delimiter::{
          pos: start,
          marker,
          length: count,
          remaining: count,
          can_open,
          can_close,
          active: true,
        })
      }
    } else {
      i += 1
    }
  }

  // Phase 2: Process delimiters to find matching pairs
  // Result: list of (opener_pos, closer_pos, marker, is_strong)
  let matches : Array[(Int, Int, Char, Bool)] = []

  // Process closers from left to right
  for closer_idx = 0
      closer_idx < delimiters.length()
      closer_idx = closer_idx + 1 {
    let closer = delimiters[closer_idx]
    if not(closer.can_close) || closer.remaining == 0 {
      continue
    }

    // Look back for a matching opener
    for opener_idx = closer_idx - 1
        opener_idx >= 0
        opener_idx = opener_idx - 1 {
      let opener = delimiters[opener_idx]
      if not(opener.can_open) || opener.remaining == 0 || not(opener.active) {
        continue
      }
      if opener.marker != closer.marker {
        continue
      }

      // Rule: if sum of lengths is multiple of 3 and both can_open and can_close,
      // then opener length and closer length must both not be multiples of 3
      // (This prevents *foo**bar* from matching incorrectly)
      if (opener.can_open && opener.can_close) ||
        (closer.can_open && closer.can_close) {
        if (opener.length + closer.length) % 3 == 0 {
          if opener.length % 3 != 0 || closer.length % 3 != 0 {
            continue
          }
        }
      }

      // Found a match! Determine if strong or emphasis
      let use_count = if opener.remaining >= 2 && closer.remaining >= 2 {
        2
      } else {
        1
      }
      let is_strong = use_count == 2

      // Calculate positions
      let opener_end = opener.pos + opener.length - opener.remaining + use_count
      let closer_start = closer.pos + (closer.length - closer.remaining)
      matches.push(
        (opener_end - use_count, closer_start, opener.marker, is_strong),
      )

      // Update remaining counts
      delimiters[opener_idx].remaining = opener.remaining - use_count
      delimiters[closer_idx].remaining = closer.remaining - use_count

      // Deactivate delimiters between opener and closer
      for j = opener_idx + 1; j < closer_idx; j = j + 1 {
        delimiters[j].active = false
      }

      // If more remaining in closer, continue matching
      if closer.remaining > 0 {
        // Reset closer_idx to re-process this closer
        // (Actually we need to decrement to counteract the loop increment)
        // But since we modified remaining, the loop will handle it
      }
      break
    }
  }

  // Phase 3: Build inline elements from matches
  // Sort matches by opener position (they should already be mostly sorted)

  // Build result by processing text segments (even if no emphasis matches)
  let result : Array[Inline] = []
  if matches.is_empty() {
    // No emphasis matches, but still need to process other inlines correctly
    let segment_inlines = parse_segment_simple(text, 0)
    for inline in segment_inlines {
      result.push(inline)
    }
  } else {
    build_inlines_from_matches(text, chars, matches, result)
  }
  result
}

///|
/// Build inline elements from delimiter matches
fn build_inlines_from_matches(
  text : String,
  chars : Array[Char],
  matches : Array[(Int, Int, Char, Bool)],
  result : Array[Inline],
) -> Unit {
  // Sort matches by opener position
  let sorted = matches.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })

  // Build nested structure
  let len = chars.length()
  build_inlines_recursive(
    text,
    chars,
    0,
    len,
    sorted,
    0,
    sorted.length(),
    result,
  )
}

///|
/// Recursively build inline elements
fn build_inlines_recursive(
  text : String,
  chars : Array[Char],
  start : Int,
  end : Int,
  matches : Array[(Int, Int, Char, Bool)],
  match_start : Int,
  match_end : Int,
  result : Array[Inline],
) -> Unit {
  let mut pos = start
  for i = match_start; i < match_end; i = i + 1 {
    let (opener_pos, closer_pos, marker, is_strong) = matches[i]

    // Skip if outside our range or already processed
    if opener_pos < start || closer_pos > end || opener_pos < pos {
      continue
    }
    let marker_len = if is_strong { 2 } else { 1 }

    // Add text before this emphasis
    if opener_pos > pos {
      let segment = text.unsafe_substring(start=pos, end=opener_pos)
      // Parse segment for other inline elements (code, links, etc.)
      let segment_inlines = parse_segment_simple(segment, pos)
      for inline in segment_inlines {
        result.push(inline)
      }
    }

    // Build children for this emphasis
    let children : Array[Inline] = []
    let content_start = opener_pos + marker_len
    let content_end = closer_pos

    // Find nested matches within this emphasis
    let nested_start = i + 1
    let mut nested_end = i + 1
    while nested_end < match_end {
      let (np, nc, _, _) = matches[nested_end]
      if np >= content_start && nc <= content_end {
        nested_end += 1
      } else {
        break
      }
    }
    if nested_start < nested_end {
      // Has nested emphasis
      build_inlines_recursive(
        text, chars, content_start, content_end, matches, nested_start, nested_end,
        children,
      )
      // Note: nested matches will be skipped naturally by position check
    } else {
      // No nested emphasis, parse content simply
      let content = text.unsafe_substring(start=content_start, end=content_end)
      let content_inlines = parse_segment_simple(content, content_start)
      for inline in content_inlines {
        children.push(inline)
      }
    }

    // Create emphasis or strong node
    let em_marker = if marker == '*' {
      EmphasisMarker::Asterisk
    } else {
      EmphasisMarker::Underscore
    }
    let span = Span::new(opener_pos, closer_pos + marker_len)
    if is_strong {
      result.push(Inline::Strong(marker=em_marker, children~, span~))
    } else {
      result.push(Inline::Emphasis(marker=em_marker, children~, span~))
    }
    pos = closer_pos + marker_len
  }

  // Add remaining text
  if pos < end {
    let segment = text.unsafe_substring(start=pos, end~)
    let segment_inlines = parse_segment_simple(segment, pos)
    for inline in segment_inlines {
      result.push(inline)
    }
  }
}

///|
/// Parse a text segment for non-emphasis inlines (code spans, links, etc.)
fn parse_segment_simple(text : String, offset : Int) -> Array[Inline] {
  // For now, just return as text. Full implementation would parse
  // code spans, links, etc. here.
  let scanner = Scanner::new(text)
  let result : Array[Inline] = []
  let text_buf = StringBuilder::new()
  let mut text_start = 0
  while not(scanner.is_eof()) {
    let pos = scanner.pos
    match scanner.peek() {
      Some('`') => {
        // Try to parse code span
        let backtick_count = scanner.count_char('`')
        scanner.advance(backtick_count)

        // Find closing backticks
        let content_buf = StringBuilder::new()
        let mut found_closing = false
        while not(scanner.is_eof()) {
          let closing_count = scanner.count_char('`')
          if closing_count == backtick_count {
            found_closing = true
            let content = content_buf.to_string()
            scanner.advance(closing_count)

            // Flush text buffer
            if not(text_buf.is_empty()) {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }

            // Trim single leading/trailing space if present
            let trimmed = if content.length() >= 2 {
              let chars = content.to_array()
              if chars[0] == ' ' &&
                chars[chars.length() - 1] == ' ' &&
                not(is_all_spaces(content)) {
                content.unsafe_substring(start=1, end=content.length() - 1)
              } else {
                content
              }
            } else {
              content
            }
            result.push(
              Inline::Code(
                content=trimmed,
                backtick_count~,
                span=Span::new(offset + pos, offset + scanner.pos),
              ),
            )
            text_start = scanner.pos
            break
          } else if closing_count > 0 {
            for j = 0; j < closing_count; j = j + 1 {
              content_buf.write_char('`')
            }
            scanner.advance(closing_count)
          } else {
            match scanner.consume() {
              Some(c) => content_buf.write_char(c)
              None => break
            }
          }
        }
        if not(found_closing) {
          // No closing backticks, include opening backticks in text
          for j = 0; j < backtick_count; j = j + 1 {
            text_buf.write_char('`')
          }
          // Content was consumed, add it to text
          text_buf.write_string(content_buf.to_string())
        }
      }
      Some('[') => {
        // Try to parse link or image
        let link_parser = InlineParser::new(scanner)
        match link_parser.try_parse_link(pos) {
          Some(link) => {
            // Flush text buffer
            if not(text_buf.is_empty()) {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }
            result.push(link)
            text_start = scanner.pos
          }
          None => {
            text_buf.write_char('[')
            scanner.advance(1)
          }
        }
      }
      Some('!') =>
        // Try to parse image
        if char_is(scanner.peek_at(1), '[') {
          let img_parser = InlineParser::new(scanner)
          match img_parser.try_parse_image(pos) {
            Some(img) => {
              // Flush text buffer
              if not(text_buf.is_empty()) {
                result.push(
                  Inline::Text(
                    content=text_buf.to_string(),
                    span=Span::new(offset + text_start, offset + pos),
                  ),
                )
                text_buf.reset()
              }
              result.push(img)
              text_start = scanner.pos
            }
            None => {
              text_buf.write_char('!')
              scanner.advance(1)
            }
          }
        } else {
          text_buf.write_char('!')
          scanner.advance(1)
        }
      Some('<') => {
        // Try to parse autolink
        let auto_parser = InlineParser::new(scanner)
        match auto_parser.try_parse_autolink(pos) {
          Some(autolink) => {
            // Flush text buffer
            if not(text_buf.is_empty()) {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }
            result.push(autolink)
            text_start = scanner.pos
          }
          None => {
            text_buf.write_char('<')
            scanner.advance(1)
          }
        }
      }
      Some('\n') => {
        // Check for hard break (2+ trailing spaces before newline)
        let content = text_buf.to_string()
        let trimmed = content.trim_end(chars=" ").to_string()
        let trailing_spaces = content.length() - trimmed.length()
        let is_hard_break = trailing_spaces >= 2
        if not(trimmed.is_empty()) {
          result.push(
            Inline::Text(
              content=trimmed,
              span=Span::new(
                offset + text_start,
                offset + pos - trailing_spaces,
              ),
            ),
          )
        }
        text_buf.reset()
        scanner.advance(1)
        // Skip leading spaces after newline
        while char_is(scanner.peek(), ' ') {
          scanner.advance(1)
        }
        if is_hard_break {
          result.push(
            Inline::HardBreak(
              style=HardBreakStyle::TwoSpaces,
              span=Span::new(
                offset + pos - trailing_spaces,
                offset + scanner.pos,
              ),
            ),
          )
        } else {
          result.push(
            Inline::SoftBreak(
              span=Span::new(offset + pos, offset + scanner.pos),
            ),
          )
        }
        text_start = scanner.pos
      }
      Some(c) => {
        text_buf.write_char(c)
        scanner.advance(1)
      }
      None => break
    }
  }

  // Flush remaining text
  if not(text_buf.is_empty()) {
    result.push(
      Inline::Text(
        content=text_buf.to_string(),
        span=Span::new(offset + text_start, offset + scanner.pos),
      ),
    )
  }
  result
}
