///| CST Serializer - Convert CST back to markdown text (lossless roundtrip)

///|
/// Serialize document to markdown string
pub fn serialize(doc : Document) -> String {
  let buf = StringBuilder::new()

  // Serialize frontmatter if present
  match doc.frontmatter {
    Some(fm) => serialize_frontmatter(fm, buf)
    None => ()
  }

  // Serialize blocks with blank lines between them (GFM style)
  let mut first = true
  for block in doc.children {
    // Skip leading BlankLines
    match block {
      Block::BlankLines(..) => continue
      _ => ()
    }

    // Add blank line between blocks (except for first block)
    if not(first) {
      buf.write_char('\n')
    }
    first = false
    serialize_block(block, buf)
  }
  buf.to_string()
}

///|
/// Serialize frontmatter
fn serialize_frontmatter(fm : Frontmatter, buf : StringBuilder) -> Unit {
  buf.write_string("---\n")
  buf.write_string(fm.raw)
  if not(fm.raw.has_suffix("\n")) {
    buf.write_char('\n')
  }
  buf.write_string("---\n")
}

///|
/// Write n copies of a character
fn write_chars(buf : StringBuilder, c : Char, n : Int) -> Unit {
  for i = 0; i < n; i = i + 1 {
    buf.write_char(c)
  }
}

///| Calculate minimum backticks for code span

///|
/// Returns the smallest count that doesn't match any backtick run in content
fn calc_code_span_backticks(content : String) -> Int {
  // Track which run lengths exist using a simple bitmask for small values
  // For runs > 63, we fall back to max_run + 1
  let mut run_mask : UInt64 = 0 // bit N set means run of length N exists
  let mut max_run = 0
  let mut current_run = 0
  for c in content {
    if c == '`' {
      current_run += 1
    } else if current_run > 0 {
      if current_run <= 63 {
        run_mask = run_mask | (1UL << current_run)
      }
      if current_run > max_run {
        max_run = current_run
      }
      current_run = 0
    }
  }
  if current_run > 0 {
    if current_run <= 63 {
      run_mask = run_mask | (1UL << current_run)
    }
    if current_run > max_run {
      max_run = current_run
    }
  }

  // Find minimum N that is not in runs
  let mut n = 1
  while n <= 63 && (run_mask & (1UL << n)) != 0 {
    n += 1
  }
  // If we exceeded 63, use max_run + 1
  if n > 63 {
    max_run + 1
  } else {
    n
  }
}

///|
/// Calculate minimum fence length for code block
fn calc_fence_length(code : String) -> Int {
  let mut fence_len = 3
  let mut count = 0
  for c in code {
    if c == '`' {
      count = count + 1
    } else {
      if count >= fence_len {
        fence_len = count + 1
      }
      count = 0
    }
  }
  // Check final run of backticks
  if count >= fence_len {
    fence_len = count + 1
  }
  fence_len
}

///|
/// Serialize a block
fn serialize_block(block : Block, buf : StringBuilder) -> Unit {
  match block {
    Block::ThematicBreak(..) =>
      // GFM style: no leading trivia, always use ***
      buf.write_string("***\n")
    Block::Heading(level~, style~, children~, ..) =>
      // GFM style: no leading trivia, no closing hashes
      match style {
        HeadingStyle::Atx => {
          write_chars(buf, '#', level)
          if not(children.is_empty()) {
            buf.write_char(' ')
            serialize_inlines(children, buf)
          }
          buf.write_char('\n')
        }
        HeadingStyle::Setext => {
          serialize_inlines(children, buf)
          buf.write_char('\n')
          let underline_char = if level == 1 { '=' } else { '-' }
          write_chars(buf, underline_char, 3)
          buf.write_char('\n')
        }
      }
    Block::Paragraph(children~, ..) => {
      // GFM style: no leading/trailing trivia
      serialize_inlines(children, buf)
      buf.write_char('\n')
    }
    Block::FencedCode(info~, code~, ..) => {
      // GFM style: always use ``` (remark default)
      let fence_len = calc_fence_length(code)
      write_chars(buf, '`', fence_len)
      if not(info.is_empty()) {
        buf.write_string(info)
      }
      buf.write_char('\n')
      buf.write_string(code)
      if not(code.is_empty()) && not(code.has_suffix("\n")) {
        buf.write_char('\n')
      }
      write_chars(buf, '`', fence_len)
      buf.write_char('\n')
    }
    Block::IndentedCode(code~, ..) => {
      // remark converts indented code to fenced code
      let fence_len = calc_fence_length(code)
      write_chars(buf, '`', fence_len)
      buf.write_char('\n')
      buf.write_string(code)
      if not(code.is_empty()) && not(code.has_suffix("\n")) {
        buf.write_char('\n')
      }
      write_chars(buf, '`', fence_len)
      buf.write_char('\n')
    }
    Block::Blockquote(children~, ..) =>
      // Serialize each block with > prefix
      for child in children {
        let child_buf = StringBuilder::new()
        serialize_block(child, child_buf)
        let child_str = child_buf.to_string()
        for line in child_str.split("\n") {
          let line_str = line.to_string()
          if not(line_str.is_empty()) {
            buf.write_string("> ")
            buf.write_string(line_str)
            buf.write_char('\n')
          }
        }
      }
    Block::BulletList(items~, ..) =>
      // GFM style: always use *, no marker_offset
      serialize_bullet_list_items(items, buf, 0)
    Block::OrderedList(start~, items~, ..) =>
      // GFM style: always use ., no marker_offset
      serialize_ordered_list_items(items, buf, 0, start)
    Block::HtmlBlock(html~, ..) => {
      buf.write_string(html)
      if not(html.has_suffix("\n")) {
        buf.write_char('\n')
      }
    }
    Block::Table(
      header~,
      alignments~,
      rows~,
      leading_trivia~,
      trailing_trivia~,
      ..
    ) => {
      buf.write_string(leading_trivia.content)
      // Header row
      buf.write_char('|')
      for cell in header {
        buf.write_char(' ')
        serialize_table_cell_inlines(cell.children, buf)
        buf.write_string(" |")
      }
      buf.write_char('\n')
      // Separator row (remark-gfm style)
      buf.write_char('|')
      for align in alignments {
        match align {
          TableAlign::Left => buf.write_string(" :-- |")
          TableAlign::Center => buf.write_string(" :-: |")
          TableAlign::Right => buf.write_string(" --: |")
          TableAlign::None => buf.write_string(" --- |")
        }
      }
      buf.write_char('\n')
      // Data rows
      for row in rows {
        buf.write_char('|')
        for cell in row {
          buf.write_char(' ')
          serialize_table_cell_inlines(cell.children, buf)
          buf.write_string(" |")
        }
        buf.write_char('\n')
      }
      buf.write_string(trailing_trivia.content)
    }
    Block::BlankLines(count~, ..) =>
      for i = 0; i < count; i = i + 1 {
        buf.write_char('\n')
      }
    Block::FootnoteDefinition(
      label~,
      children~,
      leading_trivia~,
      trailing_trivia~,
      ..
    ) => {
      buf.write_string(leading_trivia.content)
      buf.write_string("[^")
      buf.write_string(label)
      buf.write_string("]: ")
      // Serialize children (usually a paragraph)
      let mut first = true
      for child in children {
        if not(first) {
          buf.write_string("\n    ") // Indent continuation
        }
        let child_buf = StringBuilder::new()
        serialize_block(child, child_buf)
        let child_str = child_buf.to_string().trim_end(chars="\n").to_string()
        buf.write_string(child_str)
        first = false
      }
      buf.write_char('\n')
      buf.write_string(trailing_trivia.content)
    }
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
      // Escape pipe characters in table cells
      for c in content {
        if c == '|' {
          buf.write_string("\\|")
        } else {
          buf.write_char(c)
        }
      }
    // For other inline types, delegate to regular serialization
    _ => serialize_inline(inline, buf)
  }
}

///|
/// Serialize a single inline element
fn serialize_inline(inline : Inline, buf : StringBuilder) -> Unit {
  match inline {
    Inline::Text(content~, ..) => buf.write_string(content)
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
    Inline::Code(content~, ..) => {
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
    Inline::Link(children~, url~, title~, ..) => {
      buf.write_char('[')
      serialize_inlines(children, buf)
      buf.write_string("](")
      buf.write_string(url)
      if not(title.is_empty()) {
        buf.write_string(" \"")
        buf.write_string(title)
        buf.write_char('"')
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
      buf.write_string(url)
      if not(title.is_empty()) {
        buf.write_string(" \"")
        buf.write_string(title)
        buf.write_char('"')
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

///|
/// Serialize link definitions
pub fn serialize_definitions(defs : Array[LinkDefinition]) -> String {
  let buf = StringBuilder::new()
  for def in defs {
    buf.write_char('[')
    buf.write_string(def.label)
    buf.write_string("]: ")
    buf.write_string(def.url)
    if not(def.title.is_empty()) {
      buf.write_string(" \"")
      buf.write_string(def.title)
      buf.write_char('"')
    }
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Serialize bullet list items with indentation
fn serialize_bullet_list_items(
  items : Array[ListItem],
  buf : StringBuilder,
  indent : Int,
) -> Unit {
  for item in items {
    // Write indentation
    write_chars(buf, ' ', indent)
    buf.write_string("* ")

    // Task list checkbox
    match item.checked {
      Some(true) => buf.write_string("[x] ")
      Some(false) => buf.write_string("[ ] ")
      None => ()
    }

    // Serialize item content
    let mut first_block = true
    for child in item.children {
      match child {
        Block::Paragraph(children=para_children, ..) => {
          serialize_inlines(para_children, buf)
          buf.write_char('\n')
          first_block = false
        }
        Block::BulletList(items=nested_items, ..) => {
          // Nested list - serialize with increased indentation
          if first_block {
            buf.write_char('\n')
          }
          serialize_bullet_list_items(nested_items, buf, indent + 2)
        }
        _ => {
          serialize_block(child, buf)
          first_block = false
        }
      }
    }

    // If no content was written, add newline
    if first_block {
      buf.write_char('\n')
    }
  }
}

///|
/// Serialize ordered list items with indentation
fn serialize_ordered_list_items(
  items : Array[ListItem],
  buf : StringBuilder,
  indent : Int,
  start : Int,
) -> Unit {
  let mut num = start
  for item in items {
    // Write indentation
    write_chars(buf, ' ', indent)
    buf.write_string(num.to_string())
    buf.write_string(". ")

    // Task list checkbox (rare for ordered lists but supported)
    match item.checked {
      Some(true) => buf.write_string("[x] ")
      Some(false) => buf.write_string("[ ] ")
      None => ()
    }

    // Serialize item content
    let mut first_block = true
    for child in item.children {
      match child {
        Block::Paragraph(children=para_children, ..) => {
          serialize_inlines(para_children, buf)
          buf.write_char('\n')
          first_block = false
        }
        Block::BulletList(items=nested_items, ..) => {
          // Nested bullet list - serialize with increased indentation
          if first_block {
            buf.write_char('\n')
          }
          serialize_bullet_list_items(nested_items, buf, indent + 3)
        }
        Block::OrderedList(items=nested_items, start=nested_start, ..) => {
          // Nested ordered list
          if first_block {
            buf.write_char('\n')
          }
          serialize_ordered_list_items(
            nested_items,
            buf,
            indent + 3,
            nested_start,
          )
        }
        _ => {
          serialize_block(child, buf)
          first_block = false
        }
      }
    }

    // If no content was written, add newline
    if first_block {
      buf.write_char('\n')
    }
    num += 1
  }
}
