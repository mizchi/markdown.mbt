///|
/// Parse `{#id .class key=value}` into a normalized attribute array.
fn parse_markdown_attributes(source : String) -> Array[MarkdownAttribute]? {
  let text = source.trim(chars=" \t\r\n").to_owned()
  guard text.length() >= 2 &&
    text.unsafe_get(0) == '{' &&
    text.unsafe_get(text.length() - 1) == '}' else {
    return None
  }
  let attributes : Array[MarkdownAttribute] = []
  let mut i = 1
  let end = text.length() - 1
  while i < end {
    while i < end && is_space_or_tab(text.unsafe_get(i)) {
      i = i + 1
    }
    if i >= end {
      break
    }
    let prefix = text.unsafe_get(i)
    if prefix == '#' || prefix == '.' {
      i = i + 1
      let start = i
      while i < end && !is_space_or_tab(text.unsafe_get(i)) {
        i = i + 1
      }
      guard i > start else { return None }
      attributes.push({
        name: if prefix == '#' {
          "id"
        } else {
          "class"
        },
        value: text.unsafe_substring(start~, end=i),
      })
      continue
    }
    let name_start = i
    while i < end {
      let c = text.unsafe_get(i)
      if c == '=' || is_space_or_tab(c) {
        break
      }
      guard is_ascii_alnum_unit(c) || c == '-' || c == '_' || c == ':' else {
        return None
      }
      i = i + 1
    }
    guard i > name_start else { return None }
    let name = text.unsafe_substring(start=name_start, end=i)
    while i < end && is_space_or_tab(text.unsafe_get(i)) {
      i = i + 1
    }
    let mut value = ""
    if i < end && text.unsafe_get(i) == '=' {
      i = i + 1
      while i < end && is_space_or_tab(text.unsafe_get(i)) {
        i = i + 1
      }
      guard i < end else { return None }
      let quote = text.unsafe_get(i)
      if quote == '"' || quote == '\'' {
        i = i + 1
        let value_start = i
        while i < end && text.unsafe_get(i) != quote {
          i = i + 1
        }
        guard i < end else { return None }
        value = text.unsafe_substring(start=value_start, end=i)
        i = i + 1
      } else {
        let value_start = i
        while i < end && !is_space_or_tab(text.unsafe_get(i)) {
          i = i + 1
        }
        guard i > value_start else { return None }
        value = text.unsafe_substring(start=value_start, end=i)
      }
    }
    attributes.push({ name, value })
  }
  if attributes.is_empty() {
    None
  } else {
    Some(attributes)
  }
}

///|
/// Parse `:name[label]{attributes}` starting at `start`.
/// The attribute list is optional; nested Markdown in the label is left to
/// higher-level directive handlers rather than being interpreted here.
fn parse_inline_directive(text : String, start : Int) -> (Inline, Int)? {
  let len = text.length()
  guard start + 2 < len && text.unsafe_get(start) == ':' else { return None }
  let mut i = start + 1
  let name_start = i
  while i < len {
    let c = text.unsafe_get(i)
    if !is_ascii_alnum_unit(c) && c != '-' && c != '_' {
      break
    }
    i = i + 1
  }
  guard i > name_start && i < len && text.unsafe_get(i) == '[' else {
    return None
  }
  let name = text.unsafe_substring(start=name_start, end=i)
  i = i + 1
  let label_start = i
  let mut escaped = false
  while i < len {
    let c = text.unsafe_get(i)
    guard c != '\n' && c != '\r' else { return None }
    if escaped {
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == ']' {
      break
    }
    i = i + 1
  }
  guard i < len && text.unsafe_get(i) == ']' else { return None }
  let label_source = text.unsafe_substring(start=label_start, end=i)
  let label_buf = StringBuilder()
  let mut j = 0
  while j < label_source.length() {
    if label_source.unsafe_get(j) == '\\' &&
      j + 1 < label_source.length() &&
      (
        label_source.unsafe_get(j + 1) == ']' ||
        label_source.unsafe_get(j + 1) == '\\'
      ) {
      j = j + 1
    }
    label_buf.write_string(label_source.unsafe_substring(start=j, end=j + 1))
    j = j + 1
  }
  i = i + 1
  let mut attributes : Array[MarkdownAttribute] = []
  if i < len && text.unsafe_get(i) == '{' {
    let attr_start = i
    while i < len && text.unsafe_get(i) != '}' && text.unsafe_get(i) != '\n' {
      i = i + 1
    }
    guard i < len && text.unsafe_get(i) == '}' else { return None }
    let attr_source = text.unsafe_substring(start=attr_start, end=i + 1)
    guard parse_markdown_attributes(attr_source) is Some(parsed) else {
      return None
    }
    attributes = parsed
    i = i + 1
  }
  Some(
    (
      Inline::Directive(
        name~,
        label=label_buf.to_string(),
        attributes~,
        span=Span::new(start, i),
      ),
      i,
    ),
  )
}
