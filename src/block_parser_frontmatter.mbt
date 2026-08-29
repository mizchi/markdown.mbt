///| YAML frontmatter parsing (split from block_parser.mbt).

///|
/// Try to parse frontmatter (YAML between `---` delimiters) at the very start
/// of the document.
fn BlockParser::try_parse_frontmatter(self : BlockParser) -> Frontmatter? {
  guard self.len >= 3 else { return None }
  guard matches_at(self.source, 0, "---") else { return None }
  let mut i = skip_spaces_tabs(self.source, 3)
  guard i >= self.len || self.source.unsafe_get(i) == '\n' else { return None }
  if i < self.len {
    i = i + 1
  }
  let yaml = StringBuilder::new()
  let mut found_closing = false
  let mut end = i
  while i < self.len {
    let (line, next) = self.read_line(i)
    if line.has_prefix("---") &&
      is_blank_text(line.unsafe_substring(start=3, end=line.length())) {
      found_closing = true
      end = next
      break
    }
    yaml.write_string(line)
    yaml.write_char('\n')
    i = next
  }
  guard found_closing else { return None }
  let raw = yaml.to_string()
  let entries = parse_simple_yaml(raw)
  // Without any `key: value` line this is a thematic break followed by a
  // setext heading, not frontmatter.
  guard !entries.is_empty() else { return None }
  Some({ raw, entries, span: Span::new(0, end) })
}

///|
/// Parse simple YAML (key: value pairs only)
fn parse_simple_yaml(yaml : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  for line in yaml.split("\n") {
    let trimmed = line.trim(chars=" \t\r").to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    let mut colon = -1
    for i = 0; i < trimmed.length(); i = i + 1 {
      if trimmed.unsafe_get(i) == ':' {
        colon = i
        break
      }
    }
    if colon <= 0 {
      continue
    }
    let key = trimmed
      .unsafe_substring(start=0, end=colon)
      .trim(chars=" \t")
      .to_owned()
    let mut value = trimmed
      .unsafe_substring(start=colon + 1, end=trimmed.length())
      .trim(chars=" \t")
      .to_owned()
    let vlen = value.length()
    if vlen >= 2 {
      let first = value.unsafe_get(0)
      let last = value.unsafe_get(vlen - 1)
      if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
        value = value.unsafe_substring(start=1, end=vlen - 1)
      }
    }
    entries.push((key, value))
  }
  entries
}
