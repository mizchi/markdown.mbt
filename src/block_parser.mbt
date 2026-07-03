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
fn BlockParser::parse_inline_content(
  self : BlockParser,
  content : String,
) -> Array[Inline] {
  if self.scanner.is_bmp() {
    parse_inlines_known_bmp(
      content,
      strict=self.strict,
      wikilinks=self.wikilinks,
    )
  } else {
    parse_inlines(content, strict=self.strict, wikilinks=self.wikilinks)
  }
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
      if !first {
        content_buf.write_char('\n')
      }
      self.scanner.append_line_to(content_buf)
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
  let inner_scanner = if self.scanner.is_bmp() {
    Scanner::new_bmp(content)
  } else {
    Scanner::new(content)
  }
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
    self.scanner.append_line_to(content_buf)
    first = false
    if char_is(self.scanner.peek(), '\n') {
      self.scanner.advance(1)
    }
  }
  let content = content_buf.to_string()
  if content.trim(chars=" \t\n\r").is_empty() {
    return None
  }
  let children = self.parse_inline_content(content)
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
