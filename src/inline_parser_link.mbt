///| Link, image, wikilink and footnote reference parsing
///| (split from inline_parser.mbt).

///|
/// Split wiki destination into page target and optional fragment.
fn split_wikilink_destination(destination : String) -> (String, String) {
  let parts = destination.split("#").collect()
  if parts.length() <= 1 {
    (destination, "")
  } else {
    (parts[0].to_owned(), parts[1].to_owned())
  }
}

///|
/// Try to parse a wiki link: [[target]] or [[target|label]].
fn InlineParser::try_parse_wikilink(
  self : InlineParser,
  start : Int,
) -> Inline? {
  if !self.wikilinks || !self.scanner.matches("[[") {
    return None
  }
  self.scanner.advance(2) // Skip [[
  let target_buf = StringBuilder::new()
  let label_buf = StringBuilder::new()
  let mut in_label = false
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some(']') if char_is(self.scanner.peek_at(1), ']') => {
        self.scanner.advance(2)
        let raw_target = target_buf.to_string().trim(chars=" \t").to_owned()
        if raw_target.is_empty() {
          self.scanner.restore(start)
          return None
        }
        let raw_label = if in_label {
          label_buf.to_string().trim(chars=" \t").to_owned()
        } else {
          ""
        }
        let (target, fragment) = split_wikilink_destination(raw_target)
        return Some(
          Inline::WikiLink(
            target~,
            label=raw_label,
            fragment~,
            span=Span::new(start, self.scanner.pos),
          ),
        )
      }
      Some('\n') => {
        self.scanner.restore(start)
        return None
      }
      Some('[') if char_is(self.scanner.peek_at(1), '[') => {
        self.scanner.restore(start)
        return None
      }
      Some('|') if !in_label => {
        in_label = true
        self.scanner.advance(1)
      }
      Some('\\') => {
        self.scanner.advance(1)
        match self.scanner.consume() {
          Some(c) =>
            if in_label {
              label_buf.write_char(c)
            } else {
              target_buf.write_char(c)
            }
          None => break
        }
      }
      Some(c) => {
        if in_label {
          label_buf.write_char(c)
        } else {
          target_buf.write_char(c)
        }
        self.scanner.advance(1)
      }
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
  while !self.scanner.is_eof() && bracket_depth > 0 {
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
      while !self.scanner.is_eof() {
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
      while !self.scanner.is_eof() {
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
    while !self.scanner.is_eof() {
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
        while !self.scanner.is_eof() {
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
        while !self.scanner.is_eof() && paren_depth > 0 {
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
      let children = parse_inlines(link_text, wikilinks=self.wikilinks)

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
    while !self.scanner.is_eof() {
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
    let children = parse_inlines(link_text, wikilinks=self.wikilinks)

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
  if !char_is(self.scanner.peek(), '^') {
    self.scanner.restore(start)
    return None
  }
  self.scanner.advance(1) // Skip ^

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
  if !char_is(self.scanner.peek(), ']') {
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
  if !char_is(self.scanner.peek(), '[') {
    self.scanner.restore(start)
    return None
  }
  self.scanner.advance(1) // Skip [

  // Parse alt text
  let alt_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
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
      while !self.scanner.is_eof() {
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
      while !self.scanner.is_eof() {
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
        while !self.scanner.is_eof() {
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
    while !self.scanner.is_eof() {
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
