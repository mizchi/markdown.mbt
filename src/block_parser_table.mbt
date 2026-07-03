///| GFM table parsing (split from block_parser.mbt).

///|
/// Try to parse GFM table
fn BlockParser::try_parse_table(self : BlockParser, start : Int) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // First line must be a potential header row (contains |)
  let header_line = self.scanner.read_line()
  if !header_line.contains("|") {
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Second line must be separator row (contains | and -)
  let separator_line = self.scanner.read_line()
  if !separator_line.contains("|") || !separator_line.contains("-") {
    self.scanner.restore(saved)
    return None
  }

  // Parse alignments from separator row
  let alignments = parse_table_alignments(separator_line)
  if alignments.is_empty() {
    self.scanner.restore(saved)
    return None
  }

  // Count header columns - must match separator columns for valid table
  let header_cells = split_table_cells(header_line)
  let header_col_count = header_cells
    .filter(fn(c) { !c.trim(chars=" \t\n\r").is_empty() })
    .length()
  if header_col_count != alignments.length() {
    // Column count mismatch - not a valid table
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Parse header cells
  let header = parse_table_row(
    header_line,
    alignments.length(),
    self.strict,
    self.wikilinks,
    known_bmp=self.scanner.is_bmp(),
  )

  // Parse data rows
  let rows : Array[Array[TableCell]] = []
  while !self.scanner.is_eof() && !self.scanner.is_blank_line() {
    let row_start = self.scanner.pos
    let row_line = self.scanner.read_line()
    if !row_line.contains("|") {
      // Not a table row, restore position and stop
      self.scanner.restore(row_start)
      break
    }
    rows.push(
      parse_table_row(
        row_line,
        alignments.length(),
        self.strict,
        self.wikilinks,
        known_bmp=self.scanner.is_bmp(),
      ),
    )
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  Some(
    Block::Table(
      header~,
      alignments~,
      rows~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Parse table alignments from separator row
fn parse_table_alignments(line : String) -> Array[TableAlign] {
  let alignments : Array[TableAlign] = []
  let cells = split_table_cells(line)
  for cell in cells {
    let trimmed = cell.trim(chars=" \t\n\r").to_owned()
    if trimmed.is_empty() {
      continue
    }
    let has_left_colon = trimmed.has_prefix(":")
    let has_right_colon = trimmed.has_suffix(":")

    // Check if it's a valid separator (at least one dash)
    let mut has_dash = false
    for i = 0; i < trimmed.length(); i = i + 1 {
      match trimmed.get_char(i) {
        Some('-') => has_dash = true
        Some(':') => () // Allowed
        _ =>
          // Invalid character in separator
          return []
      }
    }
    if !has_dash {
      return []
    }
    let align = if has_left_colon && has_right_colon {
      TableAlign::Center
    } else if has_left_colon {
      TableAlign::Left
    } else if has_right_colon {
      TableAlign::Right
    } else {
      TableAlign::None
    }
    alignments.push(align)
  }
  alignments
}

///|
/// Parse a table row into cells
fn parse_table_row(
  line : String,
  expected_cols : Int,
  strict : Bool,
  wikilinks : Bool,
  known_bmp~ : Bool,
) -> Array[TableCell] {
  let cells : Array[TableCell] = []
  let raw_cells = split_table_cells(line)
  for i, cell in raw_cells {
    if i >= expected_cols {
      break
    }
    let content = cell.trim(chars=" \t\n\r").to_owned()
    let children = if known_bmp {
      parse_inlines_known_bmp(content, strict~, wikilinks~)
    } else {
      parse_inlines(content, strict~, wikilinks~)
    }
    cells.push({ children, span: Span::new(0, content.length()) }, // Simplified span
    )
  }

  // Pad with empty cells if needed
  while cells.length() < expected_cols {
    cells.push({ children: [], span: Span::new(0, 0) })
  }
  cells
}

///|
/// Split table row into cells by |
fn split_table_cells(line : String) -> Array[String] {
  let cells : Array[String] = []
  let buf = StringBuilder::new()
  let mut in_escape = false
  for i = 0; i < line.length(); i = i + 1 {
    match line.get_char(i) {
      Some('\\') if !in_escape => {
        in_escape = true
        buf.write_char('\\')
      }
      Some('|') if !in_escape => {
        cells.push(buf.to_string())
        // Reset buffer by creating new one
        buf.reset()
      }
      Some(c) => {
        in_escape = false
        buf.write_char(c)
      }
      None => ()
    }
  }

  // Add last cell
  let last = buf.to_string()
  if !last.trim(chars=" \t\n\r").is_empty() {
    cells.push(last)
  }

  // Remove first cell if empty (leading |)
  if cells.length() > 0 {
    match cells[0].trim(chars=" \t\n\r").to_owned() {
      "" => {
        let _ = cells.remove(0)
      }
      _ => ()
    }
  }
  cells
}
