///| HTML block parsing (split from block_parser.mbt).

///|
/// HTML block-level tag names (CommonMark Type 6)
let html_block_tags : Array[String] = [
  "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
  "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
  "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup",
  "option", "p", "param", "search", "section", "summary", "svg", "table", "tbody",
  "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

///|
/// Check if a tag name is a block-level HTML tag
/// Also recognizes custom elements (Web Components) as block tags
fn is_html_block_tag(tag : String) -> Bool {
  // Custom elements (Web Components) are always block-level
  if is_custom_element_tag(tag) {
    return true
  }
  for t in html_block_tags {
    if tag[:].equal_ignore_ascii_case(t[:]) {
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
  let first = tag.unsafe_get(0)
  if !((first >= 0x61 && first <= 0x7A) || (first >= 0x41 && first <= 0x5A)) {
    return false
  }
  // Must contain a hyphen
  for i in 0..<tag.length() {
    if tag.unsafe_get(i) == 0x2D {
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
  if !char_is(self.scanner.peek(), '<') {
    self.scanner.restore(saved)
    return None
  }

  // Peek ahead to check for valid HTML block start
  let peek_pos = self.scanner.pos
  self.scanner.advance(1) // Skip <

  // HTML comments are raw HTML blocks, but they do not have a tag name.
  if char_is(self.scanner.peek(), '!') &&
    char_is(self.scanner.peek_at(1), '-') &&
    char_is(self.scanner.peek_at(2), '-') {
    self.scanner.restore(peek_pos)
    let content_buf = StringBuilder::new()
    while !self.scanner.is_eof() {
      let is_closed = self.scanner.line_contains("-->")
      self.scanner.append_line_to(content_buf)
      if char_is(self.scanner.peek(), '\n') {
        content_buf.write_char('\n')
        self.scanner.advance(1)
      }
      if is_closed {
        break
      }
    }
    let html = content_buf.to_string()
    return Some(
      Block::HtmlBlock(
        html~,
        span=Span::new(start, self.scanner.pos),
        leading_trivia=leading,
        trailing_trivia=Trivia::empty(),
      ),
    )
  }

  // Check for closing tag </tag>
  let is_closing = char_is(self.scanner.peek(), '/')
  if is_closing {
    self.scanner.advance(1)
  }

  // Read tag name (including hyphen for custom elements)
  let tag_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
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
  if !is_html_block_tag(tag_name) && !is_custom {
    self.scanner.restore(saved)
    return None
  }

  // Restore to start and read entire HTML block
  self.scanner.restore(peek_pos)
  let content_buf = StringBuilder::new()

  // For custom elements, we need to find the closing tag
  let closing_tag = if is_custom && !is_closing {
    Some("</\{tag_name}>")
  } else {
    None
  }

  // Read lines until closing tag (for custom elements) or blank line
  let mut first_content_line = true
  while !self.scanner.is_eof() {
    let contains_closing_tag = match closing_tag {
      Some(close) => self.scanner.line_contains(close)
      None => false
    }
    let is_self_closing_first_line = match closing_tag {
      Some(_) => first_content_line && self.scanner.line_contains("/>")
      None => false
    }
    self.scanner.append_line_to(content_buf)
    if char_is(self.scanner.peek(), '\n') {
      content_buf.write_char('\n')
      self.scanner.advance(1)
    }

    // For custom elements, check if line contains closing tag
    match closing_tag {
      Some(_) => {
        if contains_closing_tag {
          break
        }
        // Also check for self-closing tag on first line
        if is_self_closing_first_line {
          break
        }
      }
      None =>
        // Standard HTML block: end on blank line
        if self.scanner.is_blank_line() {
          break
        }
    }
    first_content_line = false
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
