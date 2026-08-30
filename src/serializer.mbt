///| CST Serializer - Convert CST to normalized Markdown.

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
  let buf = StringBuilder()

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
  // Definitions are semantic document data even though they are removed from
  // paragraph blocks during parsing. Emit them in one canonical section.
  if !doc.definitions.is_empty() {
    if !first {
      buf.write_char('\n')
    }
    serialize_definitions_into(doc.definitions, buf)
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
    Block::Attributed(block~, attributes~, ..) => {
      serialize_block(block, buf)
      serialize_attribute_list(attributes, buf)
      buf.write_char('\n')
    }
    Block::ThematicBreak(..) =>
      // GFM style: no leading trivia, always use ***
      buf.write_string("***\n")
    Block::Heading(level~, children~, ..) => {
      // Canonical headings always use ATX syntax. This avoids an underline
      // whose meaning can change when adjacent block content is normalized.
      write_chars(buf, '#', level)
      if !children.is_empty() {
        buf.write_char(' ')
        serialize_inlines(children, buf)
      }
      buf.write_char('\n')
    }
    Block::Paragraph(children~, ..) => {
      // GFM style: no leading/trailing trivia
      let content = StringBuilder()
      serialize_inlines(children, content)
      write_paragraph_content(content.to_string(), buf)
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
    Block::MathBlock(value~, ..) => {
      let fence_len = math_fence_length(value)
      write_chars(buf, '$', fence_len)
      buf.write_char('\n')
      buf.write_string(value)
      if !value.has_suffix("\n") {
        buf.write_char('\n')
      }
      write_chars(buf, '$', fence_len)
      buf.write_char('\n')
    }
    Block::Directive(name~, meta~, children~, ..) => {
      buf.write_string(":::")
      buf.write_string(name)
      if !meta.is_empty() {
        buf.write_char(' ')
        buf.write_string(meta)
      }
      buf.write_char('\n')
      let body = StringBuilder()
      for child in children {
        serialize_block(child, body)
      }
      let rendered = body.to_string()
      buf.write_string(rendered)
      if !rendered.is_empty() && !rendered.has_suffix("\n") {
        buf.write_char('\n')
      }
      buf.write_string(":::\n")
    }
    Block::DefinitionList(items~, ..) =>
      for item in items {
        serialize_inlines(item.term, buf)
        buf.write_char('\n')
        for definition in item.definitions {
          buf.write_string(": ")
          serialize_inlines(definition, buf)
          buf.write_char('\n')
        }
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
        let child_buf = StringBuilder()
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
    Block::Alert(kind~, children~, ..) => {
      buf.write_string("> [!")
      buf.write_string(alert_kind_slug(kind).to_upper())
      buf.write_string("]\n")
      for child in children {
        let child_buf = StringBuilder()
        serialize_block(child, child_buf)
        for line in child_buf.to_string().split("\n") {
          let line = line.to_owned()
          if !line.is_empty() {
            buf.write_string("> ")
            buf.write_string(line)
            buf.write_char('\n')
          }
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
      serialize_pretty_table(header, alignments, rows, buf)
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
        let child_buf = StringBuilder()
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
/// Write paragraph content while protecting a leading pipe on each line.
/// This prevents a non-table paragraph from becoming a table after formatting.
fn write_paragraph_content(content : String, buf : StringBuilder) -> Unit {
  let mut line_start = true
  for c in content {
    if line_start && c == '|' {
      buf.write_char('\\')
    }
    buf.write_char(c)
    line_start = c == '\n'
  }
}

///|
/// Serialize a GFM table using stable remark-compatible column widths.
fn serialize_pretty_table(
  header : Array[TableCell],
  alignments : Array[TableAlign],
  rows : Array[Array[TableCell]],
  buf : StringBuilder,
) -> Unit {
  let rendered_header = render_table_row_cells(header)
  let rendered_rows : Array[Array[String]] = []
  let columns = alignments.length()
  for row in rows {
    let rendered = render_table_row_cells(row)
    rendered_rows.push(rendered)
  }
  let widths = calculate_table_widths(rendered_header, rendered_rows, columns)
  write_pretty_table_row(rendered_header, alignments, widths, buf)
  buf.write_char('|')
  for i = 0; i < columns; i = i + 1 {
    buf.write_char(' ')
    let align = if i < alignments.length() {
      alignments[i]
    } else {
      TableAlign::None
    }
    write_table_delimiter(align, widths[i], buf)
    buf.write_string(" |")
  }
  buf.write_char('\n')
  for row in rendered_rows {
    write_pretty_table_row(row, alignments, widths, buf)
  }
}

///|
/// Calculate the rendered width of every normalized table column.
fn calculate_table_widths(
  header : Array[String],
  rows : Array[Array[String]],
  columns : Int,
) -> Array[Int] {
  let widths = Array::make(columns, 3)
  update_table_widths(header, widths)
  for row in rows {
    update_table_widths(row, widths)
  }
  widths
}

///|
/// Render cells before measuring them so escapes and Markdown markers count.
fn render_table_row_cells(cells : Array[TableCell]) -> Array[String] {
  let rendered : Array[String] = []
  for cell in cells {
    let cell_buf = StringBuilder()
    serialize_table_cell_inlines(cell.children, cell_buf)
    rendered.push(cell_buf.to_string())
  }
  rendered
}

///|
/// Expand column widths to fit one rendered row.
fn update_table_widths(row : Array[String], widths : Array[Int]) -> Unit {
  for i, cell in row {
    if i < widths.length() && cell.length() > widths[i] {
      widths[i] = cell.length()
    }
  }
}

///|
/// Write one padded table row.
fn write_pretty_table_row(
  row : Array[String],
  alignments : Array[TableAlign],
  widths : Array[Int],
  buf : StringBuilder,
) -> Unit {
  buf.write_char('|')
  for i, width in widths {
    let cell = if i < row.length() { row[i] } else { "" }
    let gap = width - cell.length()
    let align = if i < alignments.length() {
      alignments[i]
    } else {
      TableAlign::None
    }
    let left = match align {
      TableAlign::Right => gap
      TableAlign::Center => gap / 2
      _ => 0
    }
    let right = gap - left
    buf.write_char(' ')
    write_chars(buf, ' ', left)
    buf.write_string(cell)
    write_chars(buf, ' ', right)
    buf.write_string(" |")
  }
  buf.write_char('\n')
}

///|
/// Write the alignment marker at exactly the measured column width.
fn write_table_delimiter(
  align : TableAlign,
  width : Int,
  buf : StringBuilder,
) -> Unit {
  match align {
    TableAlign::Left => {
      buf.write_char(':')
      write_chars(buf, '-', width - 1)
    }
    TableAlign::Center => {
      buf.write_char(':')
      write_chars(buf, '-', width - 2)
      buf.write_char(':')
    }
    TableAlign::Right => {
      write_chars(buf, '-', width - 1)
      buf.write_char(':')
    }
    TableAlign::None => write_chars(buf, '-', width)
  }
}

///|
/// Serialize normalized block attributes using shorthand where possible.
fn serialize_attribute_list(
  attributes : Array[MarkdownAttribute],
  buf : StringBuilder,
) -> Unit {
  buf.write_char('{')
  for i, attribute in attributes {
    if i > 0 {
      buf.write_char(' ')
    }
    if attribute.name == "id" {
      buf.write_char('#')
      buf.write_string(attribute.value)
    } else if attribute.name == "class" {
      buf.write_char('.')
      buf.write_string(attribute.value)
    } else {
      buf.write_string(attribute.name)
      if !attribute.value.is_empty() {
        buf.write_char('=')
        let needs_quotes = attribute.value.contains(" ") ||
          attribute.value.contains("\t")
        if needs_quotes {
          buf.write_char('"')
        }
        for c in attribute.value {
          if needs_quotes && (c == '"' || c == '\\') {
            buf.write_char('\\')
          }
          buf.write_char(c)
        }
        if needs_quotes {
          buf.write_char('"')
        }
      }
    }
  }
  buf.write_char('}')
}

///|
/// Choose a closing fence longer than any dollar-only line in the value.
fn math_fence_length(value : String) -> Int {
  let mut longest = 1
  for line in value.split("\n") {
    let line = line.trim(chars=" \t\r")
    let mut all_dollars = !line.is_empty()
    for c in line {
      if c != '$' {
        all_dollars = false
        break
      }
    }
    if all_dollars && line.length() > longest {
      longest = line.length()
    }
  }
  if longest < 2 {
    2
  } else {
    longest + 1
  }
}

///|
/// Serialize link definitions
pub fn serialize_definitions(defs : Array[LinkDefinition]) -> String {
  let buf = StringBuilder()
  serialize_definitions_into(defs, buf)
  buf.to_string()
}

///| Write the canonical definition section. Definitions are separated by a

///|
/// blank line to match the normalized block spacing used elsewhere.
fn serialize_definitions_into(
  defs : Array[LinkDefinition],
  buf : StringBuilder,
) -> Unit {
  for i, def in defs {
    if i > 0 {
      buf.write_char('\n')
    }
    buf.write_char('[')
    buf.write_string(def.label)
    buf.write_string("]: ")
    write_link_destination(def.url, buf)
    if !def.title.is_empty() {
      write_link_title(def.title, buf)
    }
    buf.write_char('\n')
  }
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
  let inner = StringBuilder()
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
