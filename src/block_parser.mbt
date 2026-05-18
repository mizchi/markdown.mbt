///| Block-level markdown parser

///| Line-driven state machine (Lezer-style)

///|
/// Parse result
pub(all) struct ParseResult {
  document : Document
  definitions : Array[LinkDefinition]
}

///| Parse markdown source into CST

///| When strict=true, uses full CommonMark compliance (slower)

///|
/// When strict=false (default), uses fast single-pass parser
pub fn parse(
  source : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> ParseResult {
  let scanner = Scanner::new(source)
  let parser = BlockParser::new(scanner, strict, wikilinks)
  parser.parse_document()
}

///|
/// Block parser state
priv struct BlockParser {
  scanner : Scanner
  definitions : Array[LinkDefinition]
  strict : Bool
  wikilinks : Bool
}

///|
fn BlockParser::new(
  scanner : Scanner,
  strict : Bool,
  wikilinks : Bool,
) -> BlockParser {
  { scanner, definitions: [], strict, wikilinks }
}

///|
/// Parse entire document
fn BlockParser::parse_document(self : BlockParser) -> ParseResult {
  let start = self.scanner.pos

  // Try to parse frontmatter
  let frontmatter = self.try_parse_frontmatter()

  // Parse blocks
  let children = self.parse_blocks()
  let document = Document::{
    frontmatter,
    children,
    span: Span::new(start, self.scanner.pos),
  }
  { document, definitions: self.definitions }
}

///|
/// Parse sequence of blocks
fn BlockParser::parse_blocks(self : BlockParser) -> Array[Block] {
  let blocks : Array[Block] = []
  while !self.scanner.is_eof() {
    // Skip and collect blank lines
    let blank_start = self.scanner.pos
    let mut blank_count = 0
    while !self.scanner.is_eof() && self.scanner.is_blank_line() {
      blank_count += 1
      self.scanner.skip_line()
    }
    if blank_count > 0 {
      blocks.push(
        Block::BlankLines(
          count=blank_count,
          span=Span::new(blank_start, self.scanner.pos),
        ),
      )
    }
    if self.scanner.is_eof() {
      break
    }

    // Parse next block
    match self.parse_block() {
      Some(block) => blocks.push(block)
      None =>
        // Skip problematic line
        self.scanner.skip_line()
    }
  }
  blocks
}

///|
/// Parse a single block
fn BlockParser::parse_block(self : BlockParser) -> Block? {
  let start = self.scanner.pos
  let indent = self.scanner.count_leading_spaces()

  // Try each block type in order of precedence

  // Thematic break (must check before lists due to ---)
  match self.try_parse_thematic_break(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // ATX heading
  match self.try_parse_atx_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Fenced code block
  match self.try_parse_fenced_code(start, indent) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Blockquote
  match self.try_parse_blockquote(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // List (bullet or ordered)
  match self.try_parse_list(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Indented code block (4+ spaces)
  if indent >= 4 {
    match self.try_parse_indented_code(start) {
      Some(block) => return Some(block)
      None => self.scanner.restore(start)
    }
  }

  // Setext heading (underlined)
  match self.try_parse_setext_heading(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // HTML block
  match self.try_parse_html_block(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Table
  match self.try_parse_table(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // GFM Footnote definition
  match self.try_parse_footnote_definition(start) {
    Some(block) => return Some(block)
    None => self.scanner.restore(start)
  }

  // Link reference definition
  match self.try_parse_link_definition(start) {
    Some(_) => return None // Definitions don't produce blocks
    None => self.scanner.restore(start)
  }

  // Default: paragraph
  self.parse_paragraph(start)
}

///|
/// Try to parse thematic break (---, ***, ___)
fn BlockParser::try_parse_thematic_break(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = self.read_leading_trivia()
  let marker = match self.scanner.peek() {
    Some(c) if c == '-' || c == '*' || c == '_' => c
    _ => return None
  }
  let mut count = 0
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some('\n') => break
      Some(c) if c == marker => {
        count += 1
        self.scanner.advance(1)
      }
      Some(c) if c == ' ' || c == '\t' => self.scanner.advance(1)
      _ => return None // Invalid character
    }
  }
  if count < 3 {
    return None
  }
  let trailing = self.read_trailing_trivia()
  Some(
    Block::ThematicBreak(
      marker~,
      count~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Try to parse ATX heading (# Heading)
fn BlockParser::try_parse_atx_heading(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = self.read_leading_trivia()

  // Count # characters
  let level = self.scanner.count_char('#')
  if level < 1 || level > 6 {
    return None
  }
  self.scanner.advance(level)

  // Must be followed by space or end of line
  match self.scanner.peek() {
    Some(' ') | Some('\t') | Some('\n') | None => ()
    _ => return None
  }

  // Skip space after #
  let _ = self.scanner.skip_spaces()

  // Read content until end of line or closing hashes
  let line = self.scanner.read_line()

  // Check for closing hashes
  let (content, closing_hashes) = parse_heading_content(line)

  // Skip newline
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let trailing = Trivia::empty()

  // Parse inline content
  let children = parse_inlines(
    content,
    strict=self.strict,
    wikilinks=self.wikilinks,
  )
  Some(
    Block::Heading(
      level~,
      style=HeadingStyle::Atx,
      children~,
      closing_hashes~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Parse heading content, returning (content, closing_hash_count)
fn parse_heading_content(line : String) -> (String, Int) {
  let trimmed = line.trim_end(chars=" \t").to_string()

  // Count trailing #
  let mut hash_count = 0
  let mut idx = trimmed.length() - 1
  while idx >= 0 {
    match trimmed.get_char(idx) {
      Some('#') => {
        hash_count += 1
        idx -= 1
      }
      _ => break
    }
  }

  // Closing hashes must be preceded by space (or be at start)
  if hash_count > 0 && idx >= 0 {
    match trimmed.get_char(idx) {
      Some(' ') | Some('\t') => ()
      _ => return (trimmed, 0) // Not valid closing hashes
    }
  }
  if hash_count > 0 {
    let content = trimmed
      .unsafe_substring(start=0, end=idx + 1)
      .trim_end(chars=" \t")
      .to_string()
    (content, hash_count)
  } else {
    (trimmed, 0)
  }
}

///|
/// Try to parse fenced code block
fn BlockParser::try_parse_fenced_code(
  self : BlockParser,
  start : Int,
  indent : Int,
) -> Block? {
  if indent > 3 {
    return None
  }
  let leading = self.read_leading_trivia()
  let fence_char = match self.scanner.peek() {
    Some(c) if c == '`' || c == '~' => c
    _ => return None
  }
  let fence_marker = if fence_char == '`' {
    FenceMarker::Backtick
  } else {
    FenceMarker::Tilde
  }
  let fence_length = self.scanner.count_char(fence_char)
  if fence_length < 3 {
    return None
  }
  self.scanner.advance(fence_length)

  // Read info string (language + optional filename)
  let _ = self.scanner.skip_spaces()
  let info = self.scanner.read_line().trim_end(chars=" \t").to_string()

  // Skip newline
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read code content until closing fence
  let code_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    let line_indent = self.scanner.count_leading_spaces()

    // Check for closing fence
    if line_indent <= 3 {
      let saved = self.scanner.pos
      let _ = self.scanner.skip_spaces()
      if self.scanner.count_char(fence_char) >= fence_length {
        // Found closing fence
        self.scanner.advance(self.scanner.count_char(fence_char))
        let _ = self.scanner.skip_spaces()
        if char_is(self.scanner.peek(), '\n') || self.scanner.is_eof() {
          if char_is(self.scanner.peek(), '\n') {
            self.scanner.advance(1)
          }
          break
        }
      }
      self.scanner.restore(saved)
    }

    // Read code line (remove up to `indent` leading spaces)
    let line = self.scanner.read_line()
    let stripped = strip_indent(line, indent)
    code_buf.write_string(stripped)
    if char_is(self.scanner.peek(), '\n') {
      code_buf.write_char('\n')
      self.scanner.advance(1)
    }
  }
  let trailing = Trivia::empty()
  Some(
    Block::FencedCode(
      fence_marker~,
      fence_length~,
      info~,
      code=code_buf.to_string(),
      indent~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=trailing,
    ),
  )
}

///|
/// Strip up to n leading spaces from a line
fn strip_indent(line : String, n : Int) -> String {
  let mut stripped = 0
  let mut idx = 0
  while idx < line.length() && stripped < n {
    match line.get_char(idx) {
      Some(' ') => {
        stripped += 1
        idx += 1
      }
      Some('\t') => {
        stripped += 4
        idx += 1
      }
      _ => break
    }
  }
  line.unsafe_substring(start=idx, end=line.length())
}

///|
/// Try to parse indented code block
fn BlockParser::try_parse_indented_code(
  self : BlockParser,
  start : Int,
) -> Block? {
  let leading = Trivia::empty()
  let code_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    let line_start = self.scanner.pos

    // Check if line starts with 4+ spaces
    let indent = self.scanner.count_leading_spaces()
    if indent < 4 && !self.scanner.is_blank_line() {
      self.scanner.restore(line_start)
      break
    }
    if self.scanner.is_blank_line() {
      code_buf.write_char('\n')
      self.scanner.skip_line()
    } else {
      // Skip 4 spaces
      self.scanner.advance(4)
      let line = self.scanner.read_line()
      code_buf.write_string(line)
      if char_is(self.scanner.peek(), '\n') {
        code_buf.write_char('\n')
        self.scanner.advance(1)
      }
    }
  }
  let code = code_buf.to_string().trim_end(chars="\n").to_string()
  if code.is_empty() {
    return None
  }
  Some(
    Block::IndentedCode(
      code~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse blockquote
fn BlockParser::try_parse_blockquote(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  if !char_is(self.scanner.peek(), '>') {
    return None
  }

  // Collect all lines of blockquote
  let content_buf = StringBuilder::new()
  let mut first = true
  while !self.scanner.is_eof() {
    let line_start = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    if char_is(self.scanner.peek(), '>') {
      self.scanner.advance(1)
      // Optional space after >
      if char_is(self.scanner.peek(), ' ') {
        self.scanner.advance(1)
      }
      let line = self.scanner.read_line()
      if !first {
        content_buf.write_char('\n')
      }
      content_buf.write_string(line)
      first = false
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
    } else {
      // Line without > ends blockquote
      // TODO: Implement proper lazy continuation for paragraph content only
      self.scanner.restore(line_start)
      break
    }
  }

  // Parse blockquote content recursively
  let content = content_buf.to_string()
  let inner_scanner = Scanner::new(content)
  let inner_parser = BlockParser::new(
    inner_scanner,
    self.strict,
    self.wikilinks,
  )
  let inner_result = inner_parser.parse_document()

  // Merge definitions
  for def in inner_result.definitions {
    self.definitions.push(def)
  }
  Some(
    Block::Blockquote(
      children=inner_result.document.children,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}


///|
/// Try to parse setext heading
fn BlockParser::try_parse_setext_heading(
  self : BlockParser,
  start : Int,
) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // Read content line
  let content = self.scanner.read_line()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  } else {
    return None // Must have another line
  }

  // Check for setext underline
  let _ = self.scanner.skip_spaces()
  let underline_char = match self.scanner.peek() {
    Some(c) if c == '=' || c == '-' => c
    _ => return None
  }
  let level = if underline_char == '=' { 1 } else { 2 }
  let underline_count = self.scanner.count_char(underline_char)
  if underline_count < 1 {
    return None
  }
  self.scanner.advance(underline_count)

  // Rest of line must be empty
  let _ = self.scanner.skip_spaces()
  if !char_is(self.scanner.peek(), '\n') && !self.scanner.is_eof() {
    self.scanner.restore(saved)
    return None
  }
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  let content_str = content.trim(chars=" \t\n\r").to_string()
  let children = parse_inlines(
    content_str,
    strict=self.strict,
    wikilinks=self.wikilinks,
  )
  Some(
    Block::Heading(
      level~,
      style=HeadingStyle::Setext,
      children~,
      closing_hashes=0,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}


///|
/// Try to parse GFM footnote definition [^label]: content
fn BlockParser::try_parse_footnote_definition(
  self : BlockParser,
  start : Int,
) -> Block? {
  let saved = self.scanner.pos
  let leading = self.read_leading_trivia()

  // [^label]:
  if !char_is(self.scanner.peek(), '[') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)
  if !char_is(self.scanner.peek(), '^') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Read label (alphanumeric, -, _)
  let label_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some(']') => break
      Some(c) if (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '-' ||
        c == '_' => {
        label_buf.write_char(c)
        self.scanner.advance(1)
      }
      _ => {
        self.scanner.restore(saved)
        return None
      }
    }
  }
  let label = label_buf.to_string()
  if label.is_empty() {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1) // ]
  if !char_is(self.scanner.peek(), ':') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Skip optional space after :
  if char_is(self.scanner.peek(), ' ') {
    self.scanner.advance(1)
  }

  // Read content (first line + continuation lines with indentation)
  let content_buf = StringBuilder::new()
  let first_line = self.scanner.read_line()
  content_buf.write_string(first_line)
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }

  // Read continuation lines (indented with at least 2 spaces or tab)
  while !self.scanner.is_eof() {
    let line_start = self.scanner.pos
    let indent = self.scanner.skip_spaces()
    if self.scanner.is_blank_line() {
      // Blank line may continue or end footnote
      content_buf.write_char('\n')
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
      continue
    }
    if indent >= 2 {
      // Continuation line
      content_buf.write_char('\n')
      let line = self.scanner.read_line()
      content_buf.write_string(line)
      if char_is(self.scanner.peek(), '\n') {
        self.scanner.advance(1)
      }
    } else {
      // Not a continuation, restore and stop
      self.scanner.restore(line_start)
      break
    }
  }

  // Parse content as blocks
  let content = content_buf.to_string()
  let inner_scanner = Scanner::new(content)
  let inner_parser = BlockParser::new(
    inner_scanner,
    self.strict,
    self.wikilinks,
  )
  let inner_result = inner_parser.parse_document()
  Some(
    Block::FootnoteDefinition(
      label~,
      children=inner_result.document.children,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}

///|
/// Try to parse link reference definition
fn BlockParser::try_parse_link_definition(
  self : BlockParser,
  start : Int,
) -> LinkDefinition? {
  let saved = self.scanner.pos
  let _ = self.scanner.skip_spaces()

  // [label]:
  if !char_is(self.scanner.peek(), '[') {
    return None
  }
  self.scanner.advance(1)

  // Read label
  let label_buf = StringBuilder::new()
  while !self.scanner.is_eof() {
    match self.scanner.peek() {
      Some(']') => break
      Some('\n') | None => {
        self.scanner.restore(saved)
        return None
      }
      Some(c) => {
        label_buf.write_char(c)
        self.scanner.advance(1)
      }
    }
  }
  self.scanner.advance(1) // ]
  if !char_is(self.scanner.peek(), ':') {
    self.scanner.restore(saved)
    return None
  }
  self.scanner.advance(1)

  // Skip whitespace
  let _ = self.scanner.skip_spaces()
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
    let _ = self.scanner.skip_spaces()
  }

  // Read URL
  let url = if char_is(self.scanner.peek(), '<') {
    self.scanner.advance(1)
    let url_buf = StringBuilder::new()
    while !self.scanner.is_eof() && !char_is(self.scanner.peek(), '>') {
      match self.scanner.consume() {
        Some(c) => url_buf.write_char(c)
        None => break
      }
    }
    self.scanner.advance(1) // >
    url_buf.to_string()
  } else {
    let url_buf = StringBuilder::new()
    while !self.scanner.is_eof() {
      match self.scanner.peek() {
        Some(' ') | Some('\t') | Some('\n') | None => break
        Some(c) => {
          url_buf.write_char(c)
          self.scanner.advance(1)
        }
      }
    }
    url_buf.to_string()
  }
  let _ = self.scanner.skip_spaces()

  // Optional title
  let title = match self.scanner.peek() {
    Some('"') | Some('\'') => {
      let quote = match self.scanner.consume() {
        Some(c) => c
        None => '"'
      }
      let title_buf = StringBuilder::new()
      while !self.scanner.is_eof() && !char_is(self.scanner.peek(), quote) {
        match self.scanner.consume() {
          Some(c) => title_buf.write_char(c)
          None => break
        }
      }
      if char_is(self.scanner.peek(), quote) {
        self.scanner.advance(1)
      }
      title_buf.to_string()
    }
    _ => ""
  }

  // Skip to end of line
  self.scanner.skip_line()
  let def : LinkDefinition = {
    label: label_buf.to_string().to_lower(),
    url,
    title,
    span: Span::new(start, self.scanner.pos),
  }
  self.definitions.push(def)
  Some(def)
}

///|
/// Parse paragraph (default block type)
fn BlockParser::parse_paragraph(self : BlockParser, start : Int) -> Block? {
  let leading = self.read_leading_trivia()
  let content_buf = StringBuilder::new()
  let mut first = true
  while !self.scanner.is_eof() {
    if self.scanner.is_blank_line() {
      break
    }

    // Check for block-level interrupts
    let saved = self.scanner.pos
    let _ = self.scanner.skip_spaces()
    match self.scanner.peek() {
      Some('#') | Some('>') => {
        self.scanner.restore(saved)
        break
      }
      // Only break for fenced code if 3+ backticks/tildes
      // Use peek_at for O(1) check instead of count_char
      Some('`') if self.scanner.peek_at(1) == Some('`') &&
        self.scanner.peek_at(2) == Some('`') => {
        self.scanner.restore(saved)
        break
      }
      Some('~') if self.scanner.peek_at(1) == Some('~') &&
        self.scanner.peek_at(2) == Some('~') => {
        self.scanner.restore(saved)
        break
      }
      Some('-') | Some('*') | Some('_') => {
        // Could be thematic break or list
        match self.try_parse_thematic_break(saved) {
          Some(_) => {
            self.scanner.restore(saved)
            break
          }
          None => ()
        }
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      Some(c) if is_digit(c) => {
        self.scanner.restore(saved)
        match self.detect_list_marker() {
          Some(_) => break
          None => ()
        }
      }
      _ => ()
    }
    self.scanner.restore(saved)
    if !first {
      content_buf.write_char('\n')
    }
    let line = self.scanner.read_line()
    content_buf.write_string(line)
    first = false
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  let content = content_buf.to_string()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  let children = parse_inlines(
    content,
    strict=self.strict,
    wikilinks=self.wikilinks,
  )
  Some(
    Block::Paragraph(
      children~,
      span=Span::new(start, self.scanner.pos),
      leading_trivia=leading,
      trailing_trivia=Trivia::empty(),
    ),
  )
}



///|
/// Read leading trivia (whitespace before content)
fn BlockParser::read_leading_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let count = self.scanner.skip_spaces()
  if count > 0 {
    Trivia::new(self.scanner.substring(start, start + count))
  } else {
    Trivia::empty()
  }
}

///|
/// Read trailing trivia (whitespace after content including newline)
fn BlockParser::read_trailing_trivia(self : BlockParser) -> Trivia {
  let start = self.scanner.pos
  let _ = self.scanner.skip_spaces()
  if char_is(self.scanner.peek(), '\n') {
    self.scanner.advance(1)
  }
  if self.scanner.pos > start {
    Trivia::new(self.scanner.substring(start, self.scanner.pos))
  } else {
    Trivia::empty()
  }
}
