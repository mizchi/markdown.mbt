///| Inline serialization (text, emphasis, links, images, code spans, ...).

///|

///| Split from serializer.mbt to keep that file focused on block-level

///| serialization. Table-cell variants and wikilink escaping live here

///| because they are part of the same inline-rendering surface.

///|
/// Write literal text, escaping the characters that would otherwise be read
/// back as markup. Inline text in the CST is already unescaped, so this is
/// what keeps `serialize(parse(x))` stable.
fn write_escaped_markdown_literal(
  content : String,
  buf : StringBuilder,
) -> Unit {
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
      '*' | '_' | '[' | '`' | '<' | '&' => {
        buf.write_char('\\')
        buf.write_char(c)
      }
      '~' => {
        if (i > 0 && content.unsafe_get(i - 1) == '~') ||
          (i + 1 < len && content.unsafe_get(i + 1) == '~') {
          buf.write_char('\\')
        }
        buf.write_char('~')
      }
      '@' => {
        let looks_email_like = i > 0 &&
          i + 1 < len &&
          is_email_local_char(content.unsafe_get(i - 1)) &&
          is_ascii_alnum_unit(content.unsafe_get(i + 1))
        if looks_email_like {
          buf.write_char('\\')
        }
        buf.write_char('@')
      }
      _ => buf.write_char(c)
    }
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
  }
}

///| Normalize GFM bare autolinks to explicit Markdown syntax. This shares the

///|
/// renderer's boundary/delimiter scanner so HTML and Markdown agree.
fn write_escaped_markdown_text(content : String, buf : StringBuilder) -> Unit {
  let len = content.length()
  let mut pos = 0
  while pos < len {
    match find_next_autolink(content, pos) {
      None => {
        write_escaped_markdown_literal(
          content.unsafe_substring(start=pos, end=len),
          buf,
        )
        pos = len
      }
      Some(found) => {
        write_escaped_markdown_literal(
          content.unsafe_substring(start=pos, end=found.start),
          buf,
        )
        let display = content.unsafe_substring(start=found.start, end=found.end)
        match found.kind {
          BareAutolinkKind::Url if display.has_prefix("ftp://") => {
            // remark-gfm does not normalize bare FTP URLs as links.
            buf.write_string("ftp\\://")
            buf.write_string(
              display.unsafe_substring(start=6, end=display.length()),
            )
            pos = found.end
          }
          BareAutolinkKind::Url | BareAutolinkKind::Email => {
            buf.write_char('<')
            buf.write_string(display)
            buf.write_char('>')
            pos = found.end
          }
          BareAutolinkKind::Www => {
            buf.write_char('[')
            for c in display {
              if c == '&' || c == '[' || c == ']' || c == '\\' {
                buf.write_char('\\')
              }
              buf.write_char(c)
            }
            buf.write_string("](")
            write_link_destination("http://" + display, buf)
            buf.write_char(')')
            pos = found.end
          }
        }
      }
    }
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
      '(' | ')' | '&' => {
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
  serialize_inlines_with_autolink(inlines, buf, true)
}

///|
/// Serialize children while preventing nested links inside link labels.
fn serialize_inlines_with_autolink(
  inlines : Array[Inline],
  buf : StringBuilder,
  autolink : Bool,
) -> Unit {
  for i = 0; i < inlines.length(); i = i + 1 {
    let inline = inlines[i]
    // A literal `!` immediately followed by a link node would otherwise be
    // reparsed as an image. Inside one text node escaping `[` is sufficient,
    // so this must be handled at the inline-node boundary.
    match inline {
      Inline::Text(content~, ..) if content.has_suffix("!") &&
        i + 1 < inlines.length() &&
        inline_starts_link(inlines[i + 1]) => {
        let prefix = content.unsafe_substring(start=0, end=content.length() - 1)
        if autolink {
          write_escaped_markdown_text(prefix, buf)
        } else {
          write_escaped_markdown_literal(prefix, buf)
        }
        buf.write_string("\\!")
      }
      _ => serialize_inline(inline, buf, autolink~)
    }
  }
}

///|
/// Whether serializing this inline starts with a Markdown link opener.
fn inline_starts_link(inline : Inline) -> Bool {
  match inline {
    Inline::Link(..) | Inline::RefLink(..) => true
    _ => false
  }
}

///|
/// Serialize table cell inline content (escapes pipes)
///
/// Every pipe a cell's content produces has to leave the cell as `\|`, and
/// that includes the ones nested inside code spans, emphasis and links: GFM
/// strips those escapes before the inline parser runs, so an unescaped pipe
/// would split the row instead of staying in the cell. The inlines are
/// rendered into a scratch buffer first so the rule applies uniformly to
/// every inline kind rather than only to top-level text.
fn serialize_table_cell_inlines(
  inlines : Array[Inline],
  buf : StringBuilder,
) -> Unit {
  for inline in inlines {
    let rendered = StringBuilder()
    serialize_inline(inline, rendered)
    write_table_escaped_pipes(rendered.to_string(), buf)
  }
}

///|
/// Escape every pipe that is not already protected by an odd backslash run.
fn write_table_escaped_pipes(source : String, buf : StringBuilder) -> Unit {
  let mut backslashes = 0
  for c in source {
    if c == '|' && backslashes % 2 == 0 {
      buf.write_char('\\')
    }
    buf.write_char(c)
    if c == '\\' {
      backslashes = backslashes + 1
    } else {
      backslashes = 0
    }
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

///| Image labels serialize as plain text: nested emphasis, links, and images

///|
/// contribute their text but not their Markdown markers.
fn normalized_image_alt(alt : String) -> String {
  let buf = StringBuilder()
  write_plain_text(parse_inlines(alt), buf)
  buf.to_string()
}

///|
/// Escape the delimiters that would terminate or nest an image label.
fn write_image_alt(alt : String, buf : StringBuilder) -> Unit {
  for c in alt {
    match c {
      '\\' | '[' | ']' => {
        buf.write_char('\\')
        buf.write_char(c)
      }
      _ => buf.write_char(c)
    }
  }
}

///|
/// Serialize a single inline element
fn serialize_inline(
  inline : Inline,
  buf : StringBuilder,
  autolink? : Bool = true,
) -> Unit {
  match inline {
    Inline::Text(content~, ..) =>
      if autolink {
        write_escaped_markdown_text(content, buf)
      } else {
        write_escaped_markdown_literal(content, buf)
      }
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) =>
      // remark uses backslash style by default
      buf.write_string("\\\n")
    Inline::Emphasis(children~, ..) => {
      // Always use * for GFM compatibility (remark default)
      buf.write_char('*')
      serialize_inlines_with_autolink(children, buf, autolink)
      buf.write_char('*')
    }
    Inline::Strong(children~, ..) => {
      // Always use ** for GFM compatibility (remark default)
      buf.write_string("**")
      serialize_inlines_with_autolink(children, buf, autolink)
      buf.write_string("**")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("~~")
      serialize_inlines_with_autolink(children, buf, autolink)
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
    Inline::Directive(name~, label~, attributes~, ..) => {
      buf.write_char(':')
      buf.write_string(name)
      buf.write_char('[')
      for c in label {
        if c == ']' || c == '\\' {
          buf.write_char('\\')
        }
        buf.write_char(c)
      }
      buf.write_char(']')
      if !attributes.is_empty() {
        serialize_attribute_list(attributes, buf)
      }
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
      serialize_inlines_with_autolink(children, buf, false)
      buf.write_string("](")
      write_link_destination(url, buf)
      if !title.is_empty() {
        write_link_title(title, buf)
      }
      buf.write_char(')')
    }
    Inline::RefLink(children~, label~, style~, ..) => {
      buf.write_char('[')
      serialize_inlines_with_autolink(children, buf, false)
      match style {
        ReferenceStyle::Full => {
          buf.write_string("][")
          buf.write_string(label)
          buf.write_char(']')
        }
        ReferenceStyle::Collapsed => buf.write_string("][]")
        ReferenceStyle::Shortcut => buf.write_char(']')
      }
    }
    Inline::Autolink(url~, ..) => {
      buf.write_char('<')
      buf.write_string(url)
      buf.write_char('>')
    }
    Inline::Image(alt~, url~, title~, ..) => {
      buf.write_string("![")
      write_image_alt(normalized_image_alt(alt), buf)
      buf.write_string("](")
      write_link_destination(url, buf)
      if !title.is_empty() {
        write_link_title(title, buf)
      }
      buf.write_char(')')
    }
    Inline::RefImage(alt~, label~, style~, ..) => {
      let display = normalized_image_alt(alt)
      buf.write_string("![")
      write_image_alt(display, buf)
      let output_style = if style != ReferenceStyle::Full && display != label {
        ReferenceStyle::Full
      } else {
        style
      }
      match output_style {
        ReferenceStyle::Full => {
          buf.write_string("][")
          buf.write_string(label)
          buf.write_char(']')
        }
        ReferenceStyle::Collapsed => buf.write_string("][]")
        ReferenceStyle::Shortcut => buf.write_char(']')
      }
    }
    Inline::HtmlInline(html~, ..) => buf.write_string(html)
    Inline::FootnoteReference(label~, ..) => {
      buf.write_string("[^")
      buf.write_string(label)
      buf.write_char(']')
    }
  }
}
