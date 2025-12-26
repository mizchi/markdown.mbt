///| MDX Block Parser

///|

///| Parses MDX block-level elements:

///| - Import declarations

///| - Export declarations

///| - JSX/Web Component elements

// =============================================================================
// Main Parser
// =============================================================================

///|
/// Parse MDX blocks from a document
/// Returns array of MDX blocks found in the document
pub fn parse_mdx_blocks(doc : @markdown.Document) -> Array[MdxBlock] {
  let blocks : Array[MdxBlock] = []
  for block in doc.children {
    let mdx_blocks = try_parse_mdx_blocks_from_block(block)
    for mdx in mdx_blocks {
      blocks.push(mdx)
    }
  }
  blocks
}

///|
/// Try to parse a single block as MDX blocks (may return multiple blocks for multi-line paragraphs)
pub fn try_parse_mdx_blocks_from_block(
  block : @markdown.Block,
) -> Array[MdxBlock] {
  let result : Array[MdxBlock] = []
  match block {
    @markdown.Block::Paragraph(children~, span~, ..) => {
      // Get the raw text content of the paragraph
      let content = get_paragraph_text(children)

      // Split by newlines to handle multiple statements
      let lines = split_lines(content)
      for line in lines {
        let trimmed = line.trim(chars=" \t\n\r")

        // Try import
        if trimmed.has_prefix("import ") || trimmed.has_prefix("import{") {
          match try_parse_import(line, span) {
            Some(mdx) => result.push(mdx)
            None => ()
          }
          continue
        }

        // Try export
        if trimmed.has_prefix("export ") {
          match try_parse_export(line, span) {
            Some(mdx) => result.push(mdx)
            None => ()
          }
          continue
        }

        // Try JSX element
        if trimmed.has_prefix("<") {
          match try_parse_jsx_element(line, span) {
            Some(mdx) => result.push(mdx)
            None => ()
          }
        }
      }
    }
    @markdown.Block::HtmlBlock(html~, span~, ..) =>
      // HTML blocks might be JSX
      match try_parse_jsx_element(html, span) {
        Some(mdx) => result.push(mdx)
        None => ()
      }
    _ => ()
  }
  result
}

///|
/// Split string by newlines
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let buf = StringBuilder::new()
  for i = 0; i < len; i = i + 1 {
    if chars[i] == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(chars[i])
    }
  }

  // Add the last line if non-empty
  let last = buf.to_string()
  if last.length() > 0 {
    lines.push(last)
  }
  lines
}

///|
/// Try to parse a single block as an MDX block (returns first match only)
pub fn try_parse_mdx_block(block : @markdown.Block) -> MdxBlock? {
  let blocks = try_parse_mdx_blocks_from_block(block)
  if blocks.length() > 0 {
    Some(blocks[0])
  } else {
    None
  }
}

// =============================================================================
// Import Parser
// =============================================================================

///|
/// Parse import declaration
/// Patterns:
/// - import X from 'source'
/// - import { X, Y as Z } from 'source'
/// - import * as X from 'source'
fn try_parse_import(content : String, span : @markdown.Span) -> MdxBlock? {
  let chars = content.to_array()
  let len = chars.length()
  let mut pos = 0

  // Skip leading whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Check for 'import'
  if not(matches_keyword(chars, pos, "import")) {
    return None
  }
  pos += 6

  // Skip whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }
  let specifiers : Array[ImportSpecifier] = []

  // Parse specifiers
  if pos < len {
    let c = chars[pos]
    if c == '{' {
      // Named imports: { X, Y as Z }
      pos += 1
      let (named, new_pos) = parse_named_imports(chars, pos)
      for spec in named {
        specifiers.push(spec)
      }
      pos = new_pos
    } else if c == '*' {
      // Namespace import: * as X
      pos += 1
      while pos < len && is_whitespace(chars[pos]) {
        pos += 1
      }
      if matches_keyword(chars, pos, "as") {
        pos += 2
        while pos < len && is_whitespace(chars[pos]) {
          pos += 1
        }
        let (name, new_pos) = parse_identifier(chars, pos)
        if name.length() > 0 {
          specifiers.push(ImportSpecifier::star(name))
          pos = new_pos
        }
      }
    } else if is_ident_start(c) {
      // Default import: X from 'source'
      let (name, new_pos) = parse_identifier(chars, pos)
      if name.length() > 0 {
        specifiers.push(ImportSpecifier::default_import(name))
        pos = new_pos
      }

      // Check for additional named imports: import X, { Y } from 'source'
      while pos < len && is_whitespace(chars[pos]) {
        pos += 1
      }
      if pos < len && chars[pos] == ',' {
        pos += 1
        while pos < len && is_whitespace(chars[pos]) {
          pos += 1
        }
        if pos < len && chars[pos] == '{' {
          pos += 1
          let (named, new_pos) = parse_named_imports(chars, pos)
          for spec in named {
            specifiers.push(spec)
          }
          pos = new_pos
        }
      }
    }
  }

  // Skip whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Check for 'from'
  if not(matches_keyword(chars, pos, "from")) {
    return None
  }
  pos += 4

  // Skip whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Parse source string
  let source = parse_string_literal(chars, pos)
  if source.is_empty() {
    return None
  }
  Some(MdxBlock::ImportDecl(specifiers~, source~, span~, raw=content))
}

///|
/// Parse named imports: X, Y as Z, ...
fn parse_named_imports(
  chars : Array[Char],
  start : Int,
) -> (Array[ImportSpecifier], Int) {
  let specs : Array[ImportSpecifier] = []
  let len = chars.length()
  let mut pos = start
  while pos < len {
    // Skip whitespace
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    if pos >= len || chars[pos] == '}' {
      pos += 1 // Skip }
      break
    }

    // Parse identifier
    let (name, new_pos) = parse_identifier(chars, pos)
    if name.length() == 0 {
      pos += 1
      continue
    }
    pos = new_pos

    // Skip whitespace
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }

    // Check for 'as'
    if matches_keyword(chars, pos, "as") {
      pos += 2
      while pos < len && is_whitespace(chars[pos]) {
        pos += 1
      }
      let (local_name, new_pos2) = parse_identifier(chars, pos)
      if local_name.length() > 0 {
        specs.push(ImportSpecifier::with_local(name, local_name))
        pos = new_pos2
      } else {
        specs.push(ImportSpecifier::named(name))
      }
    } else {
      specs.push(ImportSpecifier::named(name))
    }

    // Skip whitespace
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }

    // Skip comma
    if pos < len && chars[pos] == ',' {
      pos += 1
    }
  }
  (specs, pos)
}

// =============================================================================
// Export Parser
// =============================================================================

///|
/// Parsed export info
priv struct ExportInfo {
  kind : ExportKind
  name : String?
  value_start : Int
}

///|
/// Parse export kind and return info
fn parse_export_kind(chars : Array[Char], start_pos : Int) -> ExportInfo {
  let len = chars.length()
  let mut pos = start_pos
  if matches_keyword(chars, pos, "default") {
    pos += 7
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    return { kind: ExportKind::Default, name: None, value_start: pos }
  }
  if matches_keyword(chars, pos, "const") {
    pos += 5
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    let (ident, new_pos) = parse_identifier(chars, pos)
    let name = if ident.length() > 0 { Some(ident) } else { None }
    pos = new_pos
    while pos < len && chars[pos] != '=' {
      pos += 1
    }
    if pos < len {
      pos += 1
    }
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    return { kind: ExportKind::Const, name, value_start: pos }
  }
  if matches_keyword(chars, pos, "let") {
    pos += 3
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    let (ident, new_pos) = parse_identifier(chars, pos)
    let name = if ident.length() > 0 { Some(ident) } else { None }
    pos = new_pos
    while pos < len && chars[pos] != '=' {
      pos += 1
    }
    if pos < len {
      pos += 1
    }
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    return { kind: ExportKind::Let, name, value_start: pos }
  }
  if matches_keyword(chars, pos, "function") {
    pos += 8
    while pos < len && is_whitespace(chars[pos]) {
      pos += 1
    }
    let (ident, _new_pos) = parse_identifier(chars, pos)
    let name = if ident.length() > 0 { Some(ident) } else { None }
    return { kind: ExportKind::Function, name, value_start: pos }
  }

  // Named export: export { x, y }
  { kind: ExportKind::Named, name: None, value_start: pos }
}

///|
/// Parse export declaration
fn try_parse_export(content : String, span : @markdown.Span) -> MdxBlock? {
  let chars = content.to_array()
  let len = chars.length()
  let mut pos = 0

  // Skip leading whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Check for 'export'
  if not(matches_keyword(chars, pos, "export")) {
    return None
  }
  pos += 6

  // Skip whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Parse export kind
  let info = parse_export_kind(chars, pos)

  // Get the value (rest of the content)
  let value = substring(chars, info.value_start, len).trim(chars=" \t\n\r").to_string()
  Some(
    MdxBlock::ExportDecl(
      kind=info.kind,
      name=info.name,
      value~,
      span~,
      raw=content,
    ),
  )
}

// =============================================================================
// JSX Parser
// =============================================================================

///|
/// Parse JSX/Web Component element
fn try_parse_jsx_element(content : String, span : @markdown.Span) -> MdxBlock? {
  let chars = content.to_array()
  let len = chars.length()
  let mut pos = 0

  // Skip leading whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Check for <
  if pos >= len || chars[pos] != '<' {
    return None
  }
  pos += 1

  // Check for closing tag (skip it)
  if pos < len && chars[pos] == '/' {
    return None
  }

  // Parse tag name
  let tag_start = pos
  while pos < len && is_tag_name_char(chars[pos]) {
    pos += 1
  }
  if pos == tag_start {
    return None
  }
  let tag = substring(chars, tag_start, pos)

  // Check if this is a JSX component or Web Component
  if not(is_mdx_tag(tag)) {
    return None
  }

  // Parse attributes
  let (attributes, attr_end) = parse_attributes(content, pos)
  pos = attr_end

  // Skip whitespace
  while pos < len && is_whitespace(chars[pos]) {
    pos += 1
  }

  // Check for self-closing
  let self_closing = pos < len && chars[pos] == '/'
  if self_closing {
    pos += 1
  }

  // Skip >
  while pos < len && chars[pos] != '>' {
    pos += 1
  }
  if pos < len {
    pos += 1
  }

  // Get children (content until closing tag)
  let children = if self_closing {
    ""
  } else {
    let children_start = pos
    // Find closing tag
    let closing_pos = find_closing_tag(content, pos, tag)
    if closing_pos >= 0 {
      substring(chars, children_start, closing_pos)
    } else {
      substring(chars, children_start, len)
    }
  }
  Some(MdxBlock::JsxElement(tag~, attributes~, children~, self_closing~, span~))
}

///|
/// Find closing tag position
fn find_closing_tag(content : String, start : Int, tag : String) -> Int {
  let closing = "</" + tag
  let chars = content.to_array()
  let closing_chars = closing.to_array()
  let len = chars.length()
  let closing_len = closing_chars.length()
  let mut pos = start
  let mut depth = 1
  while pos < len {
    // Check for opening tag (increase depth)
    if chars[pos] == '<' && pos + 1 < len && chars[pos + 1] != '/' {
      let tag_start = pos + 1
      let mut tag_end = tag_start
      while tag_end < len && is_tag_name_char(chars[tag_end]) {
        tag_end += 1
      }
      let found_tag = substring(chars, tag_start, tag_end)
      if found_tag == tag {
        depth += 1
      }
    }

    // Check for closing tag
    if pos + closing_len <= len {
      let mut matches = true
      for i = 0; i < closing_len; i = i + 1 {
        if chars[pos + i] != closing_chars[i] {
          matches = false
          break
        }
      }
      if matches {
        depth -= 1
        if depth == 0 {
          return pos
        }
      }
    }
    pos += 1
  }
  -1
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn get_paragraph_text(children : Array[@markdown.Inline]) -> String {
  let buf = StringBuilder::new()
  for child in children {
    match child {
      @markdown.Inline::Text(content~, ..) => buf.write_string(content)
      @markdown.Inline::Code(content~, ..) => {
        buf.write_char('`')
        buf.write_string(content)
        buf.write_char('`')
      }
      @markdown.Inline::HtmlInline(html~, ..) => buf.write_string(html)
      @markdown.Inline::Autolink(url~, ..) => {
        // Reconstruct autolink syntax: <url>
        buf.write_char('<')
        buf.write_string(url)
        buf.write_char('>')
      }
      @markdown.Inline::SoftBreak(..) => buf.write_char('\n')
      @markdown.Inline::HardBreak(..) => buf.write_char('\n')
      _ => () // Skip other inline elements for now
    }
  }
  buf.to_string()
}

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_tag_name_char(c : Char) -> Bool {
  is_ident_char(c) || c == '-' || c == '.' || c == ':'
}

///|
fn matches_keyword(chars : Array[Char], pos : Int, keyword : String) -> Bool {
  let kw_chars = keyword.to_array()
  let kw_len = kw_chars.length()
  if pos + kw_len > chars.length() {
    return false
  }
  for i = 0; i < kw_len; i = i + 1 {
    if chars[pos + i] != kw_chars[i] {
      return false
    }
  }

  // Check that keyword is not part of a larger identifier
  if pos + kw_len < chars.length() && is_ident_char(chars[pos + kw_len]) {
    return false
  }
  true
}

///|
fn parse_identifier(chars : Array[Char], start : Int) -> (String, Int) {
  let len = chars.length()
  let mut pos = start
  if pos >= len || not(is_ident_start(chars[pos])) {
    return ("", pos)
  }
  while pos < len && is_ident_char(chars[pos]) {
    pos += 1
  }
  (substring(chars, start, pos), pos)
}

///|
fn parse_string_literal(chars : Array[Char], start : Int) -> String {
  let len = chars.length()
  let mut pos = start
  if pos >= len {
    return ""
  }
  let quote = chars[pos]
  if quote != '"' && quote != '\'' {
    return ""
  }
  pos += 1
  let value_start = pos
  while pos < len && chars[pos] != quote {
    if chars[pos] == '\\' && pos + 1 < len {
      pos += 2
    } else {
      pos += 1
    }
  }
  substring(chars, value_start, pos)
}

///|
fn substring(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
