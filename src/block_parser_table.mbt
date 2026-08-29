///| GFM table parsing (split from block_parser.mbt).

///| A table is recognized while a paragraph is being built: as soon as its

///| second line turns out to be a delimiter row with the same number of columns

///| as the first, the paragraph becomes a table.

///|
/// Turn `paragraph` into a table when its second line is a delimiter row.
fn maybe_start_table(paragraph : Node) -> Unit {
  guard paragraph.lines.length() == 2 else { return }
  let header = paragraph.lines[0]
  let delimiter = paragraph.lines[1]
  guard delimiter.contains("|") && delimiter.contains("-") else { return }
  let alignments = parse_table_alignments(delimiter)
  guard !alignments.is_empty() else { return }
  let header_columns = split_table_cells(header)
    .filter(fn(c) { !c.trim(chars=" \t\r\n").is_empty() })
    .length()
  guard header_columns == alignments.length() else { return }
  paragraph.kind = NodeKind::TableNode
  paragraph.alignments = alignments
  let _ = paragraph.lines.pop()
}

///|
/// Build the CST node for a finished table.
fn BlockParser::table_to_block(
  self : BlockParser,
  node : Node,
  span : Span,
) -> Block? {
  guard node.lines.length() >= 1 else { return None }
  let columns = node.alignments.length()
  let header = self.parse_table_row(node.lines[0], columns)
  let rows : Array[Array[TableCell]] = []
  for i = 1; i < node.lines.length(); i = i + 1 {
    rows.push(self.parse_table_row(node.lines[i], columns))
  }
  Some(
    Block::Table(
      header~,
      alignments=node.alignments,
      rows~,
      span~,
      leading_trivia=Trivia::empty(),
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse table alignments from the delimiter row.
fn parse_table_alignments(line : String) -> Array[TableAlign] {
  let alignments : Array[TableAlign] = []
  let cells = split_table_cells(line)
  for cell in cells {
    let trimmed = cell.trim(chars=" \t\r\n").to_owned()
    // Every delimiter cell has to be a run of dashes, optionally fenced by
    // colons; nothing else, and never empty.
    if trimmed.is_empty() {
      return []
    }
    let mut dashes = 0
    for i = 0; i < trimmed.length(); i = i + 1 {
      let c = trimmed.unsafe_get(i)
      if c == '-' {
        dashes = dashes + 1
      } else if c != ':' {
        return []
      }
    }
    if dashes == 0 {
      return []
    }
    let starts = trimmed.unsafe_get(0) == ':'
    let ends = trimmed.unsafe_get(trimmed.length() - 1) == ':'
    let align = if starts && ends {
      TableAlign::Center
    } else if starts {
      TableAlign::Left
    } else if ends {
      TableAlign::Right
    } else {
      TableAlign::None
    }
    alignments.push(align)
  }
  alignments
}

///|
/// Parse one table row into cells.
fn BlockParser::parse_table_row(
  self : BlockParser,
  line : String,
  expected_cols : Int,
) -> Array[TableCell] {
  let cells : Array[TableCell] = []
  let raw_cells = split_table_cells(line)
  for i, cell in raw_cells {
    if i >= expected_cols {
      break
    }
    let content = cell.trim(chars=" \t\n\r").to_owned()
    cells.push({
      children: self.parse_inline_content(content),
      span: Span::new(0, content.length()),
    })
  }
  while cells.length() < expected_cols {
    cells.push({ children: [], span: Span::new(0, 0) })
  }
  cells
}

///|
/// Split a table row on unescaped pipes, ignoring the optional outer ones.
fn split_table_cells(line : String) -> Array[String] {
  let cells : Array[String] = []
  let trimmed = line.trim(chars=" \t\r\n").to_owned()
  let len = trimmed.length()
  let mut start = 0
  let mut end = len
  if len > 0 && trimmed.unsafe_get(0) == '|' {
    start = 1
  }
  if end > start && trimmed.unsafe_get(end - 1) == '|' {
    // A trailing pipe only closes the row when it is not escaped.
    let mut backslashes = 0
    let mut k = end - 2
    while k >= start && trimmed.unsafe_get(k) == '\\' {
      backslashes = backslashes + 1
      k = k - 1
    }
    if backslashes % 2 == 0 {
      end = end - 1
    }
  }
  let buf = StringBuilder::new()
  let mut i = start
  while i < end {
    let c = trimmed.unsafe_get(i)
    if c == '\\' && i + 1 < end && trimmed.unsafe_get(i + 1) == '|' {
      buf.write_char('|')
      i = i + 2
    } else if c == '|' {
      cells.push(buf.to_string())
      buf.reset()
      i = i + 1
    } else {
      buf.write_string(trimmed.unsafe_substring(start=i, end=i + 1))
      i = i + 1
    }
  }
  cells.push(buf.to_string())
  cells
}
