///| YAML frontmatter parsing (split from block_parser.mbt).

///|
/// Try to parse frontmatter (YAML between --- delimiters)
fn BlockParser::try_parse_frontmatter(self : BlockParser) -> Frontmatter? {
  let start = self.scanner.pos

  // Must start at beginning of document
  if start != 0 {
    return None
  }

  // Check for opening ---
  if !self.scanner.matches("---") {
    return None
  }
  self.scanner.advance(3)

  // Skip to end of line
  let _ = self.scanner.skip_spaces()
  if !char_is(self.scanner.peek(), '\n') && !self.scanner.is_eof() {
    self.scanner.restore(start)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read YAML content until closing ---
  let yaml_buf = StringBuilder::new()
  let mut found_closing = false
  while !self.scanner.is_eof() {
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
  if !found_closing {
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
    let trimmed = line.to_owned().trim(chars=" \t\n\r")
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.find(":") {
      Some(colon_idx) => {
        let key = trimmed
          .view(end_offset=colon_idx)
          .to_owned()
          .trim(chars=" \t\n\r")
          .to_owned()
        let value = trimmed
          .view(start_offset=colon_idx + 1)
          .to_owned()
          .trim(chars=" \t\n\r")
          .to_owned()
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
