///| MDX Tokenizer
///|
///| A tokenizer for MDX (Markdown + JSX) for syntax highlighting.
///| Handles Markdown syntax, import/export statements, and JSX components.

// =============================================================================
// Token Types
// =============================================================================

///|
/// MDX token types
pub(all) enum MdxTokenType {
  // Markdown block elements
  Heading // # ## ### etc.
  HeadingMarker // The # characters
  Paragraph // Plain text paragraph
  CodeBlock // ``` or indented code
  CodeFence // ``` markers
  CodeInfo // Language info after ```
  CodeContent // Content inside code block
  BlockQuote // > quote
  BlockQuoteMarker // The > character
  ThematicBreak // --- or *** or ___
  ListMarker // - * + or 1. 2.
  ListItem // List item content
  HtmlBlock // HTML block

  // Markdown inline elements
  Text // Plain text
  Emphasis // *text* or _text_
  EmphasisMarker // * or _
  Strong // **text** or __text__
  StrongMarker // ** or __
  InlineCode // `code`
  InlineCodeMarker // ` markers
  Link // [text](url)
  LinkText // Text inside []
  LinkUrl // URL inside ()
  LinkTitle // Title in ""
  Image // ![alt](url)
  Autolink // <url>
  HardBreak // Two trailing spaces or \

  // Frontmatter
  FrontmatterMarker // ---
  FrontmatterContent // YAML content

  // MDX-specific: JavaScript
  ImportKeyword // import
  ExportKeyword // export
  FromKeyword // from
  AsKeyword // as
  DefaultKeyword // default
  ConstKeyword // const, let, var
  FunctionKeyword // function
  JsIdentifier // Variable names
  JsString // 'string' or "string"
  JsOperator // = , { } etc.
  JsBrace // { }
  JsComment // // or /* */

  // MDX-specific: JSX
  JsxTagOpen // < in <Component
  JsxTagClose // > or />
  JsxCloseTag // </
  JsxTagName // Component, div, my-element
  JsxAttribute // prop, className
  JsxEquals // = in prop=
  JsxExprStart // { in JSX
  JsxExprEnd // } in JSX
  JsxText // Text content in JSX

  // Special
  Whitespace // Spaces, tabs
  Newline // Line breaks
  Error
} derive(Eq, Show)

// =============================================================================
// Context
// =============================================================================

///|
/// Parser context
enum MdxContext {
  // Top-level contexts
  Normal // Normal markdown content
  Frontmatter // Inside frontmatter ---

  // Block contexts
  CodeBlock(Char, Int) // fence_char, fence_len - Inside fenced code

  // JSX contexts
  JsxTagStart // Just after <
  JsxElement // Inside JSX tag (reading attributes)
  JsxChildren // Inside JSX children
  JsxClosingTag // Inside </...>
  JsxExpression // Inside {expr}

  // JavaScript contexts (for import/export)
  JsStatement // Parsing import/export statement
} derive(Eq, Show)

// =============================================================================
// Token
// =============================================================================

///|
/// A token with position information
pub(all) struct MdxToken {
  token_type : MdxTokenType
  from : Int
  to : Int
} derive(Eq, Show)

// =============================================================================
// Tokenizer
// =============================================================================

///|
/// MDX tokenizer
pub(all) struct MdxTokenizer {
  input : String
  priv chars : Array[Char]
  priv len : Int
  priv mut pos : Int
  priv context_stack : Array[MdxContext]
  priv mut line_start : Bool // Are we at the start of a line?
}

///|
/// Create a new tokenizer
pub fn MdxTokenizer::new(input : String) -> MdxTokenizer {
  let chars = input.to_array()
  {
    input,
    chars,
    len: chars.length(),
    pos: 0,
    context_stack: [Normal],
    line_start: true,
  }
}

///|
/// Get current context
fn MdxTokenizer::context(self : MdxTokenizer) -> MdxContext {
  if self.context_stack.length() > 0 {
    self.context_stack[self.context_stack.length() - 1]
  } else {
    Normal
  }
}

///|
/// Push context
fn MdxTokenizer::push_context(self : MdxTokenizer, ctx : MdxContext) -> Unit {
  self.context_stack.push(ctx)
}

///|
/// Pop context
fn MdxTokenizer::pop_context(self : MdxTokenizer) -> Unit {
  if self.context_stack.length() > 1 {
    let _ = self.context_stack.pop()
  }
}

///|
/// Peek character at current position
fn MdxTokenizer::peek(self : MdxTokenizer) -> Char {
  if self.pos < self.len {
    self.chars[self.pos]
  } else {
    '\u0000'
  }
}

///|
/// Peek character at offset from current position
fn MdxTokenizer::peek_at(self : MdxTokenizer, offset : Int) -> Char {
  let idx = self.pos + offset
  if idx < self.len && idx >= 0 {
    self.chars[idx]
  } else {
    '\u0000'
  }
}

///|
/// Check if char is whitespace (not newline)
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t'
}

///|
/// Check if char is newline
fn is_newline(c : Char) -> Bool {
  c == '\n' || c == '\r'
}

///|
/// Check if char is identifier start
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$'
}

///|
/// Check if char is identifier part
fn is_ident_part(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
/// Check if char is JSX tag name part (includes -)
fn is_jsx_name_part(c : Char) -> Bool {
  is_ident_part(c) || c == '-' || c == '.'
}

// =============================================================================
// Markdown Tokenization
// =============================================================================

///|
/// Read a heading (# ## ### etc.)
fn MdxTokenizer::read_heading_marker(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let mut count = 0
  while self.pos < self.len && self.chars[self.pos] == '#' && count < 6 {
    self.pos += 1
    count += 1
  }
  { token_type: HeadingMarker, from: start, to: self.pos }
}

///|
/// Read block quote marker
fn MdxTokenizer::read_blockquote_marker(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  self.pos += 1 // Skip >
  { token_type: BlockQuoteMarker, from: start, to: self.pos }
}

///|
/// Read list marker
fn MdxTokenizer::read_list_marker(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let c = self.chars[self.pos]
  if c == '-' || c == '*' || c == '+' {
    self.pos += 1
  } else if c >= '0' && c <= '9' {
    // Ordered list: 1. 2. etc.
    while self.pos < self.len && self.chars[self.pos] >= '0' && self.chars[self.pos] <= '9' {
      self.pos += 1
    }
    if self.pos < self.len && (self.chars[self.pos] == '.' || self.chars[self.pos] == ')') {
      self.pos += 1
    }
  }
  { token_type: ListMarker, from: start, to: self.pos }
}

///|
/// Read thematic break (--- or *** or ___)
fn MdxTokenizer::read_thematic_break(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let c = self.chars[self.pos]
  while self.pos < self.len && (self.chars[self.pos] == c || is_whitespace(self.chars[self.pos])) {
    self.pos += 1
  }
  { token_type: ThematicBreak, from: start, to: self.pos }
}

///|
/// Read code fence (``` or ~~~)
fn MdxTokenizer::read_code_fence(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let fence_char = self.chars[self.pos]
  let mut fence_len = 0
  while self.pos < self.len && self.chars[self.pos] == fence_char {
    self.pos += 1
    fence_len += 1
  }
  // Push code block context
  self.push_context(CodeBlock(fence_char, fence_len))
  { token_type: CodeFence, from: start, to: self.pos }
}

///|
/// Read code info string (language after ```)
fn MdxTokenizer::read_code_info(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len && !is_newline(self.chars[self.pos]) {
    self.pos += 1
  }
  { token_type: CodeInfo, from: start, to: self.pos }
}

///|
/// Check if current line is a closing code fence
fn MdxTokenizer::is_closing_fence(
  self : MdxTokenizer,
  fence_char : Char,
  fence_len : Int,
) -> Bool {
  if self.pos >= self.len {
    return false
  }
  // Skip leading whitespace
  let mut check_pos = self.pos
  while check_pos < self.len && is_whitespace(self.chars[check_pos]) {
    check_pos += 1
  }
  // Count fence chars
  let mut count = 0
  while check_pos < self.len && self.chars[check_pos] == fence_char {
    check_pos += 1
    count += 1
  }
  // Must have at least fence_len chars, followed by optional spaces and newline
  if count < fence_len {
    return false
  }
  while check_pos < self.len && is_whitespace(self.chars[check_pos]) {
    check_pos += 1
  }
  check_pos >= self.len || is_newline(self.chars[check_pos])
}

///|
/// Read code content line
fn MdxTokenizer::read_code_content_line(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len && !is_newline(self.chars[self.pos]) {
    self.pos += 1
  }
  { token_type: CodeContent, from: start, to: self.pos }
}

///|
/// Read inline code
fn MdxTokenizer::read_inline_code(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  // Count opening backticks
  let mut backtick_count = 0
  while self.pos < self.len && self.chars[self.pos] == '`' {
    self.pos += 1
    backtick_count += 1
  }
  // Find matching closing backticks
  while self.pos < self.len {
    if self.chars[self.pos] == '`' {
      let mut close_count = 0
      while self.pos < self.len && self.chars[self.pos] == '`' {
        self.pos += 1
        close_count += 1
      }
      if close_count == backtick_count {
        return { token_type: InlineCode, from: start, to: self.pos }
      }
      // Not matching, continue
    } else if is_newline(self.chars[self.pos]) {
      // Inline code can't span lines
      break
    } else {
      self.pos += 1
    }
  }
  // Unclosed, return as inline code anyway
  { token_type: InlineCode, from: start, to: self.pos }
}

///|
/// Read emphasis (* or _)
fn MdxTokenizer::read_emphasis_marker(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let marker = self.chars[self.pos]
  let mut count = 0
  while self.pos < self.len && self.chars[self.pos] == marker && count < 3 {
    self.pos += 1
    count += 1
  }
  let token_type = if count >= 2 { StrongMarker } else { EmphasisMarker }
  { token_type, from: start, to: self.pos }
}

///|
/// Read a link or image
fn MdxTokenizer::read_link_or_image(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  let is_image = self.chars[self.pos] == '!'
  if is_image {
    self.pos += 1
  }
  // Expect [
  if self.pos >= self.len || self.chars[self.pos] != '[' {
    return { token_type: Text, from: start, to: self.pos }
  }
  self.pos += 1
  // Read text until ]
  while self.pos < self.len && self.chars[self.pos] != ']' {
    if self.chars[self.pos] == '\\' && self.pos + 1 < self.len {
      self.pos += 2
    } else {
      self.pos += 1
    }
  }
  if self.pos < self.len {
    self.pos += 1 // Skip ]
  }
  // Expect (
  if self.pos >= self.len || self.chars[self.pos] != '(' {
    return { token_type: if is_image { Image } else { Link }, from: start, to: self.pos }
  }
  self.pos += 1
  // Read url until ) or space
  while self.pos < self.len && self.chars[self.pos] != ')' && !is_whitespace(self.chars[self.pos]) {
    self.pos += 1
  }
  // Skip optional title
  if self.pos < self.len && is_whitespace(self.chars[self.pos]) {
    while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
      self.pos += 1
    }
    if self.pos < self.len && (self.chars[self.pos] == '"' || self.chars[self.pos] == '\'') {
      let quote = self.chars[self.pos]
      self.pos += 1
      while self.pos < self.len && self.chars[self.pos] != quote {
        self.pos += 1
      }
      if self.pos < self.len {
        self.pos += 1
      }
    }
  }
  // Skip )
  if self.pos < self.len && self.chars[self.pos] == ')' {
    self.pos += 1
  }
  { token_type: if is_image { Image } else { Link }, from: start, to: self.pos }
}

///|
/// Read autolink <url>
fn MdxTokenizer::read_autolink(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  self.pos += 1 // Skip <
  while self.pos < self.len && self.chars[self.pos] != '>' && !is_newline(self.chars[self.pos]) {
    self.pos += 1
  }
  if self.pos < self.len && self.chars[self.pos] == '>' {
    self.pos += 1
  }
  { token_type: Autolink, from: start, to: self.pos }
}

// =============================================================================
// JavaScript/MDX Tokenization
// =============================================================================

///|
/// Read JavaScript identifier
fn MdxTokenizer::read_js_identifier(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len && is_ident_part(self.chars[self.pos]) {
    self.pos += 1
  }
  let word = self.input.unsafe_substring(start~, end=self.pos)
  let token_type = match word {
    "import" => ImportKeyword
    "export" => ExportKeyword
    "from" => FromKeyword
    "as" => AsKeyword
    "default" => DefaultKeyword
    "const" | "let" | "var" => ConstKeyword
    "function" => FunctionKeyword
    _ => JsIdentifier
  }
  { token_type, from: start, to: self.pos }
}

///|
/// Read JavaScript string
fn MdxTokenizer::read_js_string(self : MdxTokenizer, quote : Char) -> MdxToken {
  let start = self.pos
  self.pos += 1 // Skip opening quote
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == quote {
      self.pos += 1
      break
    } else if c == '\\' && self.pos + 1 < self.len {
      self.pos += 2
    } else if is_newline(c) {
      break
    } else {
      self.pos += 1
    }
  }
  { token_type: JsString, from: start, to: self.pos }
}

///|
/// Read JavaScript comment
fn MdxTokenizer::read_js_comment(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  if self.peek_at(1) == '/' {
    // Line comment
    self.pos += 2
    while self.pos < self.len && !is_newline(self.chars[self.pos]) {
      self.pos += 1
    }
  } else if self.peek_at(1) == '*' {
    // Block comment
    self.pos += 2
    while self.pos + 1 < self.len {
      if self.chars[self.pos] == '*' && self.chars[self.pos + 1] == '/' {
        self.pos += 2
        break
      }
      self.pos += 1
    }
  }
  { token_type: JsComment, from: start, to: self.pos }
}

// =============================================================================
// JSX Tokenization
// =============================================================================

///|
/// Read JSX tag name
fn MdxTokenizer::read_jsx_tag_name(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len && is_jsx_name_part(self.chars[self.pos]) {
    self.pos += 1
  }
  { token_type: JsxTagName, from: start, to: self.pos }
}

///|
/// Read JSX attribute name
fn MdxTokenizer::read_jsx_attribute(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len && is_jsx_name_part(self.chars[self.pos]) {
    self.pos += 1
  }
  { token_type: JsxAttribute, from: start, to: self.pos }
}

///|
/// Read JSX text content
fn MdxTokenizer::read_jsx_text(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == '<' || c == '{' {
      break
    }
    self.pos += 1
  }
  { token_type: JsxText, from: start, to: self.pos }
}

///|
/// Tokenize in JSX element context
fn MdxTokenizer::next_jsx_element_token(self : MdxTokenizer) -> MdxToken? {
  // Skip whitespace
  while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
    self.pos += 1
  }
  if self.pos >= self.len {
    return None
  }
  let start = self.pos
  let c = self.chars[self.pos]
  match c {
    '/' => {
      if self.pos + 1 < self.len && self.chars[self.pos + 1] == '>' {
        // Self-closing />
        self.pos += 2
        self.pop_context()
        Some({ token_type: JsxTagClose, from: start, to: self.pos })
      } else {
        self.pos += 1
        Some({ token_type: JsOperator, from: start, to: self.pos })
      }
    }
    '>' => {
      self.pos += 1
      self.pop_context()
      self.push_context(JsxChildren)
      Some({ token_type: JsxTagClose, from: start, to: self.pos })
    }
    '=' => {
      self.pos += 1
      Some({ token_type: JsxEquals, from: start, to: self.pos })
    }
    '"' | '\'' => Some(self.read_js_string(c))
    '{' => {
      self.pos += 1
      self.push_context(JsxExpression)
      Some({ token_type: JsxExprStart, from: start, to: self.pos })
    }
    _ if is_ident_start(c) => Some(self.read_jsx_attribute())
    _ => {
      self.pos += 1
      Some({ token_type: Error, from: start, to: self.pos })
    }
  }
}

///|
/// Tokenize in JSX children context
fn MdxTokenizer::next_jsx_children_token(self : MdxTokenizer) -> MdxToken? {
  if self.pos >= self.len {
    return None
  }
  let start = self.pos
  let c = self.chars[self.pos]
  match c {
    '<' => {
      if self.pos + 1 < self.len && self.chars[self.pos + 1] == '/' {
        // Closing tag </
        self.pos += 2
        self.pop_context()
        self.push_context(JsxClosingTag)
        Some({ token_type: JsxCloseTag, from: start, to: self.pos })
      } else {
        // Nested JSX
        self.pos += 1
        self.push_context(JsxTagStart)
        Some({ token_type: JsxTagOpen, from: start, to: self.pos })
      }
    }
    '{' => {
      self.pos += 1
      self.push_context(JsxExpression)
      Some({ token_type: JsxExprStart, from: start, to: self.pos })
    }
    _ => Some(self.read_jsx_text())
  }
}

// =============================================================================
// Main Tokenization
// =============================================================================

///|
/// Check if current line starts with import/export
fn MdxTokenizer::is_js_statement_start(self : MdxTokenizer) -> Bool {
  // Skip leading whitespace
  let mut check_pos = self.pos
  while check_pos < self.len && is_whitespace(self.chars[check_pos]) {
    check_pos += 1
  }
  // Check for import or export
  if check_pos + 6 <= self.len {
    let word = self.input.unsafe_substring(start=check_pos, end=check_pos + 6)
    if word == "import" || word == "export" {
      return true
    }
  }
  false
}

///|
/// Check if looks like JSX/HTML tag (starts with <letter or </)
fn MdxTokenizer::is_jsx_start(self : MdxTokenizer) -> Bool {
  if self.pos >= self.len || self.chars[self.pos] != '<' {
    return false
  }
  if self.pos + 1 >= self.len {
    return false
  }
  let next = self.chars[self.pos + 1]
  // JSX/HTML tag starts with a letter (Component, div, span, etc.)
  // or is a closing tag </
  if is_ident_start(next) || next == '/' {
    return true
  }
  false
}

///|
/// Check if current position is at frontmatter start (---)
fn MdxTokenizer::is_frontmatter_marker(self : MdxTokenizer) -> Bool {
  if !self.line_start || self.pos + 2 >= self.len {
    return false
  }
  self.chars[self.pos] == '-' &&
  self.chars[self.pos + 1] == '-' &&
  self.chars[self.pos + 2] == '-'
}

///|
/// Read text until special character or end of line
fn MdxTokenizer::read_text(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  while self.pos < self.len {
    let c = self.chars[self.pos]
    // Stop at special characters
    if c == '*' ||
      c == '_' ||
      c == '`' ||
      c == '[' ||
      c == '!' ||
      c == '<' ||
      c == '{' ||
      is_newline(c) {
      break
    }
    // Handle escapes
    if c == '\\' && self.pos + 1 < self.len {
      self.pos += 2
    } else {
      self.pos += 1
    }
  }
  { token_type: Text, from: start, to: self.pos }
}

///|
/// Read newline
fn MdxTokenizer::read_newline(self : MdxTokenizer) -> MdxToken {
  let start = self.pos
  if self.chars[self.pos] == '\r' && self.pos + 1 < self.len && self.chars[self.pos + 1] == '\n' {
    self.pos += 2
  } else {
    self.pos += 1
  }
  self.line_start = true
  { token_type: Newline, from: start, to: self.pos }
}

///|
/// Get next token
pub fn MdxTokenizer::next_token(self : MdxTokenizer) -> MdxToken? {
  if self.pos >= self.len {
    return None
  }

  // Handle context-specific tokenization
  match self.context() {
    Frontmatter => {
      // Inside frontmatter, check for closing ---
      if self.line_start && self.is_frontmatter_marker() {
        let start = self.pos
        self.pos += 3
        while self.pos < self.len && self.chars[self.pos] == '-' {
          self.pos += 1
        }
        self.pop_context()
        self.line_start = false
        return Some({ token_type: FrontmatterMarker, from: start, to: self.pos })
      }
      // Read frontmatter content line
      let start = self.pos
      while self.pos < self.len && !is_newline(self.chars[self.pos]) {
        self.pos += 1
      }
      if self.pos > start {
        self.line_start = false
        return Some({ token_type: FrontmatterContent, from: start, to: self.pos })
      }
      if is_newline(self.peek()) {
        return Some(self.read_newline())
      }
      return None
    }
    CodeBlock(fence_char, fence_len) => {
      // Check for closing fence
      if self.line_start && self.is_closing_fence(fence_char, fence_len) {
        self.pop_context()
        // Read the closing fence
        let start = self.pos
        while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
          self.pos += 1
        }
        while self.pos < self.len && self.chars[self.pos] == fence_char {
          self.pos += 1
        }
        self.line_start = false
        return Some({ token_type: CodeFence, from: start, to: self.pos })
      }
      // Handle newlines
      if is_newline(self.peek()) {
        return Some(self.read_newline())
      }
      // If not at line start, we're still on the info line (after ```)
      if !self.line_start {
        let token = self.read_code_info()
        return Some(token)
      }
      // Read code content
      let token = self.read_code_content_line()
      self.line_start = false
      return Some(token)
    }
    JsxTagStart => {
      // Read tag name
      if is_ident_start(self.peek()) {
        let token = self.read_jsx_tag_name()
        self.pop_context()
        self.push_context(JsxElement)
        return Some(token)
      }
      self.pop_context()
      ()
    }
    JsxElement => {
      return self.next_jsx_element_token()
    }
    JsxChildren => {
      return self.next_jsx_children_token()
    }
    JsxClosingTag => {
      // Skip whitespace
      while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
        self.pos += 1
      }
      if self.pos >= self.len {
        return None
      }
      let c = self.chars[self.pos]
      if is_ident_start(c) {
        let token = self.read_jsx_tag_name()
        return Some(token)
      } else if c == '>' {
        let start = self.pos
        self.pos += 1
        self.pop_context()
        return Some({ token_type: JsxTagClose, from: start, to: self.pos })
      }
      self.pop_context()
      ()
    }
    JsxExpression => {
      // Skip whitespace
      while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
        self.pos += 1
      }
      if self.pos >= self.len {
        return None
      }
      let c = self.chars[self.pos]
      if c == '}' {
        let start = self.pos
        self.pos += 1
        self.pop_context()
        return Some({ token_type: JsxExprEnd, from: start, to: self.pos })
      }
      // Parse JavaScript expression tokens
      if is_ident_start(c) {
        return Some(self.read_js_identifier())
      }
      if c == '"' || c == '\'' {
        return Some(self.read_js_string(c))
      }
      if c == '{' {
        let start = self.pos
        self.pos += 1
        self.push_context(JsxExpression) // Nested expression
        return Some({ token_type: JsBrace, from: start, to: self.pos })
      }
      // Other operators
      let start = self.pos
      self.pos += 1
      return Some({ token_type: JsOperator, from: start, to: self.pos })
    }
    JsStatement => {
      // Skip whitespace
      while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
        self.pos += 1
      }
      if self.pos >= self.len {
        return None
      }
      // Check for newline (end of statement)
      if is_newline(self.peek()) {
        self.pop_context()
        return Some(self.read_newline())
      }
      let c = self.chars[self.pos]
      if is_ident_start(c) {
        return Some(self.read_js_identifier())
      }
      if c == '"' || c == '\'' {
        return Some(self.read_js_string(c))
      }
      if c == '{' || c == '}' {
        let start = self.pos
        self.pos += 1
        return Some({ token_type: JsBrace, from: start, to: self.pos })
      }
      if c == '/' && self.pos + 1 < self.len && (self.peek_at(1) == '/' || self.peek_at(1) == '*') {
        return Some(self.read_js_comment())
      }
      // Other punctuation
      let start = self.pos
      self.pos += 1
      return Some({ token_type: JsOperator, from: start, to: self.pos })
    }
    Normal => ()
  }

  // Normal context: parse markdown
  let c = self.peek()

  // Handle newlines
  if is_newline(c) {
    return Some(self.read_newline())
  }

  // At line start, check for block-level elements
  if self.line_start {
    // Check for frontmatter
    if self.pos == 0 && self.is_frontmatter_marker() {
      let start = self.pos
      self.pos += 3
      while self.pos < self.len && self.chars[self.pos] == '-' {
        self.pos += 1
      }
      self.push_context(Frontmatter)
      self.line_start = false
      return Some({ token_type: FrontmatterMarker, from: start, to: self.pos })
    }

    // Check for import/export
    if self.is_js_statement_start() {
      self.push_context(JsStatement)
      self.line_start = false
      return self.next_token()
    }

    // Check for JSX component
    if self.is_jsx_start() {
      let start = self.pos
      self.pos += 1
      self.push_context(JsxTagStart)
      self.line_start = false
      return Some({ token_type: JsxTagOpen, from: start, to: self.pos })
    }

    // Skip leading whitespace
    if is_whitespace(c) {
      let start = self.pos
      while self.pos < self.len && is_whitespace(self.chars[self.pos]) {
        self.pos += 1
      }
      return Some({ token_type: Whitespace, from: start, to: self.pos })
    }

    // Heading
    if c == '#' {
      self.line_start = false
      return Some(self.read_heading_marker())
    }

    // Block quote
    if c == '>' {
      self.line_start = false
      return Some(self.read_blockquote_marker())
    }

    // Check for thematic break with underscores (___)
    if c == '_' {
      let next = self.peek_at(1)
      if next == '_' || is_whitespace(next) {
        // Could be thematic break, check for 3+ markers
        let mut count = 0
        let mut check_pos = self.pos
        while check_pos < self.len {
          let check_c = self.chars[check_pos]
          if check_c == '_' {
            count += 1
          } else if !is_whitespace(check_c) {
            break
          }
          check_pos += 1
        }
        if count >= 3 && (check_pos >= self.len || is_newline(self.chars[check_pos])) {
          self.line_start = false
          return Some(self.read_thematic_break())
        }
      }
      // Otherwise fall through to inline handling (emphasis)
    }

    // List marker or thematic break
    if c == '-' || c == '*' || c == '+' {
      let next = self.peek_at(1)
      // Check if it's a thematic break (--- or ***)
      if (c == '-' || c == '*') && (next == c || is_whitespace(next)) {
        // Could be thematic break, check for 3+ markers
        let mut count = 0
        let mut check_pos = self.pos
        while check_pos < self.len {
          let check_c = self.chars[check_pos]
          if check_c == c {
            count += 1
          } else if !is_whitespace(check_c) {
            break
          }
          check_pos += 1
        }
        if count >= 3 && (check_pos >= self.len || is_newline(self.chars[check_pos])) {
          self.line_start = false
          return Some(self.read_thematic_break())
        }
      }
      // List marker requires whitespace after the marker
      if is_whitespace(next) || is_newline(next) {
        self.line_start = false
        return Some(self.read_list_marker())
      }
      // Otherwise fall through to inline handling (emphasis)
    }

    // Ordered list
    if c >= '0' && c <= '9' {
      self.line_start = false
      return Some(self.read_list_marker())
    }

    // Code fence
    if c == '`' || c == '~' {
      let next1 = self.peek_at(1)
      let next2 = self.peek_at(2)
      if next1 == c && next2 == c {
        self.line_start = false
        return Some(self.read_code_fence())
      }
    }
  }

  self.line_start = false

  // Inline elements
  if c == '`' {
    return Some(self.read_inline_code())
  }

  if c == '*' || c == '_' {
    return Some(self.read_emphasis_marker())
  }

  if c == '[' {
    return Some(self.read_link_or_image())
  }

  if c == '!' && self.peek_at(1) == '[' {
    return Some(self.read_link_or_image())
  }

  if c == '<' {
    // Check for JSX
    if self.is_jsx_start() {
      let start = self.pos
      self.pos += 1
      self.push_context(JsxTagStart)
      return Some({ token_type: JsxTagOpen, from: start, to: self.pos })
    }
    // Autolink or HTML
    return Some(self.read_autolink())
  }

  if c == '{' {
    // Expression in text
    let start = self.pos
    self.pos += 1
    self.push_context(JsxExpression)
    return Some({ token_type: JsxExprStart, from: start, to: self.pos })
  }

  // Plain text
  Some(self.read_text())
}

///|
/// Tokenize entire input
pub fn MdxTokenizer::tokenize_all(self : MdxTokenizer) -> Array[MdxToken] {
  let tokens : Array[MdxToken] = []
  while true {
    match self.next_token() {
      Some(token) => tokens.push(token)
      None => break
    }
  }
  tokens
}
