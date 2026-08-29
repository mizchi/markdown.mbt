///| Inline serialization (text, emphasis, links, images, code spans, ...).

///|

///| Split from serializer.mbt to keep that file focused on block-level

///| serialization. Table-cell variants and wikilink escaping live here

///| because they are part of the same inline-rendering surface.

///|
/// Write literal text, escaping the characters that would otherwise be read
/// back as markup. Inline text in the CST is already unescaped, so this is
/// what keeps `serialize(parse(x))` stable.
fn write_escaped_markdown_text(content : String, buf : StringBuilder) -> Unit {
  let len = content.length()
  let mut i = 0
  for c in content {
    match c {
      '\\' =>
        // Only a backslash that would start an escape sequence needs doubling.
        if i + 1 < len &&
          is_punctuation(content.unsafe_get(i + 1).unsafe_to_char()) {
          buf.write_string("\\\\")
        } else {
          buf.write_char('\\')
        }
      '*' | '_' | '[' | '`' => {
        buf.write_char('\\')
        buf.write_char(c)
      }
      _ => buf.write_char(c)
    }
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
  }
}

///|
/// Write a link/image title inside double quotes, escaping what would end it.
/// Titles are stored unescaped in the CST, so this is what keeps them valid.
fn write_link_title(title : String, buf : StringBuilder) -> Unit {
  buf.write_string(" \"")
  for c in title {
    if c == '"' || c == '\\' {
      buf.write_char('\\')
    }
    buf.write_char(c)
  }
  buf.write_char('"')
}

///|
/// Write a link/image destination, escaping parentheses and falling back to
/// the `<...>` form when the destination contains whitespace.
fn write_link_destination(url : String, buf : StringBuilder) -> Unit {
  let mut needs_angle = false
  for c in url {
    if c == ' ' || c == '\t' || c == '\n' || c == '<' || c == '>' {
      needs_angle = true
      break
    }
  }
  let len = url.length()
  let mut i = 0
  let escape_backslash = fn(i : Int) -> Bool {
    i + 1 < len && is_punctuation(url.unsafe_get(i + 1).unsafe_to_char())
  }
  if needs_angle {
    buf.write_char('<')
    for c in url {
      match c {
        '<' | '>' => {
          buf.write_char('\\')
          buf.write_char(c)
        }
        '\\' => {
          if escape_backslash(i) {
            buf.write_char('\\')
          }
          buf.write_char(c)
        }
        _ => buf.write_char(c)
      }
      i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
    }
    buf.write_char('>')
    return
  }
  for c in url {
    match c {
      '(' | ')' => {
        buf.write_char('\\')
        buf.write_char(c)
      }
      '\\' => {
        if escape_backslash(i) {
          buf.write_char('\\')
        }
        buf.write_char(c)
      }
      _ => buf.write_char(c)
    }
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
  }
}

///|
/// Serialize inline content
fn serialize_inlines(inlines : Array[Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    serialize_inline(inline, buf)
  }
}

///|
/// Serialize table cell inline content (escapes pipes)
fn serialize_table_cell_inlines(
  inlines : Array[Inline],
  buf : StringBuilder,
) -> Unit {
  for inline in inlines {
    serialize_table_cell_inline(inline, buf)
  }
}

///|
/// Serialize a single inline element for table cells (escapes pipes in text)
fn serialize_table_cell_inline(inline : Inline, buf : StringBuilder) -> Unit {
  match inline {
    Inline::Text(content~, ..) =>
      // Escape pipe characters in table cells on top of the usual escapes
      for c in content {
        match c {
          '|' | '\\' | '*' | '_' | '[' | '`' => {
            buf.write_char('\\')
            buf.write_char(c)
          }
          _ => buf.write_char(c)
        }
      }
    // For other inline types, delegate to regular serialization
    _ => serialize_inline(inline, buf)
  }
}

///|
/// Escape characters that would terminate or split a wiki link.
fn serialize_wikilink_part(value : String, buf : StringBuilder) -> Unit {
  for c in value {
    match c {
      '\\' | '|' | ']' => {
        buf.write_char('\\')
        buf.write_char(c)
      }
      _ => buf.write_char(c)
    }
  }
}

///|
fn serialize_wikilink_destination(target : String, fragment : String) -> String {
  if fragment.is_empty() {
    target
  } else {
    target + "#" + fragment
  }
}

///|
/// Serialize a single inline element
fn serialize_inline(inline : Inline, buf : StringBuilder) -> Unit {
  match inline {
    Inline::Text(content~, ..) => write_escaped_markdown_text(content, buf)
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) =>
      // remark uses backslash style by default
      buf.write_string("\\\n")
    Inline::Emphasis(children~, ..) => {
      // Always use * for GFM compatibility (remark default)
      buf.write_char('*')
      serialize_inlines(children, buf)
      buf.write_char('*')
    }
    Inline::Strong(children~, ..) => {
      // Always use ** for GFM compatibility (remark default)
      buf.write_string("**")
      serialize_inlines(children, buf)
      buf.write_string("**")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("~~")
      serialize_inlines(children, buf)
      buf.write_string("~~")
    }
    Inline::Code(content=raw, ..) => {
      // The CST keeps the source text, padding included; drop it and let the
      // padding rules below re-add whatever this content needs.
      let content = strip_code_span_padding(raw)
      // Calculate minimum backticks needed (must not match any run in content)
      let backticks = calc_code_span_backticks(content)
      write_chars(buf, '`', backticks)
      // Add padding space if content starts/ends with backtick
      // (Spaces at both ends need padding only if NOT all spaces, to prevent trimming)
      let needs_padding = content.length() > 0 &&
        ({
          let first = content.get_char(0)
          let last = content.get_char(content.length() - 1)
          first == Some('`') || last == Some('`')
        })
      if needs_padding {
        buf.write_char(' ')
      }
      buf.write_string(content)
      if needs_padding {
        buf.write_char(' ')
      }
      write_chars(buf, '`', backticks)
    }
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      let destination = serialize_wikilink_destination(target, fragment)
      buf.write_string("[[")
      serialize_wikilink_part(destination, buf)
      if !label.is_empty() {
        buf.write_char('|')
        serialize_wikilink_part(label, buf)
      }
      buf.write_string("]]")
    }
    Inline::Link(children~, url~, title~, ..) => {
      buf.write_char('[')
      serialize_inlines(children, buf)
      buf.write_string("](")
      write_link_destination(url, buf)
      if !title.is_empty() {
        write_link_title(title, buf)
      }
      buf.write_char(')')
    }
    Inline::RefLink(children~, label~, ..) => {
      buf.write_char('[')
      serialize_inlines(children, buf)
      buf.write_string("][")
      buf.write_string(label)
      buf.write_char(']')
    }
    Inline::Autolink(url~, ..) => {
      buf.write_char('<')
      buf.write_string(url)
      buf.write_char('>')
    }
    Inline::Image(alt~, url~, title~, ..) => {
      buf.write_string("![")
      buf.write_string(alt)
      buf.write_string("](")
      write_link_destination(url, buf)
      if !title.is_empty() {
        write_link_title(title, buf)
      }
      buf.write_char(')')
    }
    Inline::RefImage(alt~, label~, ..) => {
      buf.write_string("![")
      buf.write_string(alt)
      buf.write_string("][")
      buf.write_string(label)
      buf.write_char(']')
    }
    Inline::HtmlInline(html~, ..) => buf.write_string(html)
    Inline::FootnoteReference(label~, ..) => {
      buf.write_string("[^")
      buf.write_string(label)
      buf.write_char(']')
    }
  }
}
