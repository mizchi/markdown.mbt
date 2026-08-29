///| CST Serializer - Convert CST back to markdown text (lossless roundtrip)

///|
/// Parse markdown source and serialize back to a normalized string.
/// Convenience wrapper around `parse` + `serialize` used by compatibility tests.
pub fn md_parse_and_render(
  source : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> String {
  let result = parse(source, strict~, wikilinks~)
  serialize(result.document)
}

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
    if !first {
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
  if !fm.raw.has_suffix("\n") {
    buf.write_char('\n')
  }
  buf.write_string("---\n")
}

///|
/// Width of the last line of `text`, used to size a setext underline.
fn last_line_width(text : String) -> Int {
  let len = text.length()
  let mut start = len
  while start > 0 && text.unsafe_get(start - 1) != '\n' {
    start = start - 1
  }
  let width = len - start
  if width < 1 {
    1
  } else {
    width
  }
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
          if !children.is_empty() {
            buf.write_char(' ')
            serialize_inlines(children, buf)
          }
          buf.write_char('\n')
        }
        HeadingStyle::Setext => {
          let content = StringBuilder::new()
          serialize_inlines(children, content)
          let text = content.to_string()
          buf.write_string(text)
          buf.write_char('\n')
          let underline_char = if level == 1 { '=' } else { '-' }
          write_chars(buf, underline_char, last_line_width(text))
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
      if !info.is_empty() {
        buf.write_string(info)
      }
      buf.write_char('\n')
      buf.write_string(code)
      if !code.is_empty() && !code.has_suffix("\n") {
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
      if !code.is_empty() && !code.has_suffix("\n") {
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
          let line_str = line.to_owned()
          if !line_str.is_empty() {
            buf.write_string("> ")
            buf.write_string(line_str)
            buf.write_char('\n')
          }
        }
      }
    Block::BulletList(items~, tight~, ..) =>
      // Stable editor/source style: always use -, no marker_offset.
      serialize_bullet_list_items(items, tight, buf)
    Block::OrderedList(start~, items~, tight~, ..) =>
      // GFM style: always use ., no marker_offset
      serialize_ordered_list_items(items, start, tight, buf)
    Block::HtmlBlock(html~, ..) => {
      buf.write_string(html)
      if !html.has_suffix("\n") {
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
        if !first {
          buf.write_string("\n    ") // Indent continuation
        }
        let child_buf = StringBuilder::new()
        serialize_block(child, child_buf)
        let child_str = child_buf.to_string().trim_end(chars="\n").to_owned()
        buf.write_string(child_str)
        first = false
      }
      buf.write_char('\n')
      buf.write_string(trailing_trivia.content)
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
    if !def.title.is_empty() {
      buf.write_string(" \"")
      buf.write_string(def.title)
      buf.write_char('"')
    }
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
/// Write `text` so that every line after the first is indented, leaving room
/// for the list marker on the first one.
fn write_with_continuation_indent(
  text : String,
  indent : Int,
  buf : StringBuilder,
) -> Unit {
  let len = text.length()
  let mut at_line_start = false
  for i = 0; i < len; i = i + 1 {
    let c = text.unsafe_get(i)
    if at_line_start && c != '\n' {
      write_chars(buf, ' ', indent)
    }
    buf.write_string(text.unsafe_substring(start=i, end=i + 1))
    at_line_start = c == '\n'
  }
}

///|
/// Serialize one list item's content, without the marker. Loose lists put a
/// blank line between the blocks of an item.
fn serialize_list_item_content(
  item : ListItem,
  tight : Bool,
  buf : StringBuilder,
) -> Unit {
  match item.checked {
    Some(true) => buf.write_string("[x] ")
    Some(false) => buf.write_string("[ ] ")
    None => ()
  }
  let mut first = true
  for child in item.children {
    if !first && !tight {
      buf.write_char('\n')
    }
    serialize_block(child, buf)
    first = false
  }
}

///|
/// Write a list item: its marker, then its content with every following line
/// indented to line up under it.
fn serialize_list_item(
  item : ListItem,
  marker : String,
  tight : Bool,
  buf : StringBuilder,
) -> Unit {
  let inner = StringBuilder::new()
  serialize_list_item_content(item, tight, inner)
  let text = inner.to_string()
  buf.write_string(marker)
  if text.is_empty() {
    buf.write_char('\n')
    return
  }
  buf.write_char(' ')
  write_with_continuation_indent(text, marker.length() + 1, buf)
}

///|
/// Serialize bullet list items
fn serialize_bullet_list_items(
  items : Array[ListItem],
  tight : Bool,
  buf : StringBuilder,
) -> Unit {
  for item in items {
    serialize_list_item(item, "-", tight, buf)
  }
}

///|
/// Serialize ordered list items
fn serialize_ordered_list_items(
  items : Array[ListItem],
  start : Int,
  tight : Bool,
  buf : StringBuilder,
) -> Unit {
  let mut num = start
  for item in items {
    serialize_list_item(item, num.to_string() + ".", tight, buf)
    num = num + 1
  }
}
