///| Rust Tokenizer
///|
///| A tokenizer for Rust language syntax highlighting.

// =============================================================================
// Token Types
// =============================================================================

///|
/// Rust token types
pub(all) enum RustTokenType {
  // Keywords
  Keyword          // fn, let, mut, const, struct, enum, impl, trait, etc.
  ControlFlow      // if, else, match, loop, while, for, return, break, continue
  // Literals
  String           // "...", r"...", r#"..."#
  Char             // 'x'
  Number           // 123, 0x1F, 0b101, 1.5e10
  Bool             // true, false
  // Names
  Identifier       // variable names, function names
  TypeName         // Self, String, Vec, Option (uppercase start)
  Lifetime         // 'a, 'static
  // Macros
  Macro            // println!, vec!, etc.
  // Attributes
  Attribute        // #[derive(Debug)]
  // Operators
  Operator         // +, -, *, /, =, ==, etc.
  Arrow            // -> or =>
  // Punctuation
  BraceOpen        // {
  BraceClose       // }
  BracketOpen      // [
  BracketClose     // ]
  ParenOpen        // (
  ParenClose       // )
  Semicolon        // ;
  Comma            // ,
  Dot              // .
  Colon            // :
  ColonColon       // ::
  // Comments
  LineComment      // // ...
  BlockComment     // /* ... */
  DocComment       // /// or //!
  // Error
  Error
} derive(Eq, Show)

// =============================================================================
// Keywords
// =============================================================================

///|
fn is_keyword(word : String) -> Bool {
  match word {
    // Declarations
    "fn" | "let" | "const" | "static" | "type" | "struct" | "enum" | "union" |
    "trait" | "impl" | "mod" | "use" | "pub" | "crate" | "super" | "self" |
    "extern" | "unsafe" | "async" | "await" | "dyn" | "move" => true
    // Modifiers
    "mut" | "ref" | "in" | "where" => true
    // Other
    "as" | "Self" => true
    _ => false
  }
}

///|
fn is_control_flow(word : String) -> Bool {
  match word {
    "if" | "else" | "match" | "loop" | "while" | "for" | "return" | "break" |
    "continue" | "yield" => true
    _ => false
  }
}

///|
fn is_builtin_type(word : String) -> Bool {
  match word {
    // Primitive types
    "bool" | "char" | "str" | "u8" | "u16" | "u32" | "u64" | "u128" | "usize" |
    "i8" | "i16" | "i32" | "i64" | "i128" | "isize" | "f32" | "f64" => true
    // Common types
    "String" | "Vec" | "Option" | "Result" | "Box" | "Rc" | "Arc" | "Cell" |
    "RefCell" | "Mutex" | "RwLock" | "HashMap" | "HashSet" | "BTreeMap" |
    "BTreeSet" | "Cow" | "Pin" | "PhantomData" => true
    _ => false
  }
}

// =============================================================================
// Token
// =============================================================================

///|
/// A token with position information
pub(all) struct RustToken {
  token_type : RustTokenType
  from : Int
  to : Int
} derive(Eq, Show)

// =============================================================================
// Tokenizer
// =============================================================================

///|
/// Rust tokenizer
pub(all) struct RustTokenizer {
  input : String
  priv chars : Array[Char]
  priv len : Int
  priv mut pos : Int
}

///|
/// Create a new tokenizer
pub fn RustTokenizer::new(input : String) -> RustTokenizer {
  let chars = input.to_array()
  { input, chars, len: chars.length(), pos: 0 }
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex_digit(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_part(c : Char) -> Bool {
  is_ident_start(c) || is_digit(c)
}

///|
fn is_uppercase(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
/// Skip whitespace
fn RustTokenizer::skip_whitespace(self : RustTokenizer) -> Unit {
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos += 1
    } else {
      break
    }
  }
}

///|
/// Read a string literal
fn RustTokenizer::read_string(self : RustTokenizer) -> RustToken {
  let start = self.pos

  // Check for raw string r"..." or r#"..."#
  if self.chars[self.pos] == 'r' {
    self.pos += 1
    let mut hash_count = 0
    while self.pos < self.len && self.chars[self.pos] == '#' {
      hash_count += 1
      self.pos += 1
    }
    if self.pos < self.len && self.chars[self.pos] == '"' {
      self.pos += 1
      // Read until closing "# sequence
      while self.pos < self.len {
        if self.chars[self.pos] == '"' {
          self.pos += 1
          let mut closing_hashes = 0
          while self.pos < self.len && self.chars[self.pos] == '#' && closing_hashes < hash_count {
            closing_hashes += 1
            self.pos += 1
          }
          if closing_hashes == hash_count {
            break
          }
        } else {
          self.pos += 1
        }
      }
      return { token_type: String, from: start, to: self.pos }
    }
    // Not a raw string, backtrack
    self.pos = start
  }

  // Regular string "..."
  self.pos += 1  // skip opening quote
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == '"' {
      self.pos += 1
      break
    } else if c == '\\' && self.pos + 1 < self.len {
      self.pos += 2  // skip escape
    } else if c == '\n' {
      break
    } else {
      self.pos += 1
    }
  }
  { token_type: String, from: start, to: self.pos }
}

///|
/// Read a character literal
fn RustTokenizer::read_char(self : RustTokenizer) -> RustToken {
  let start = self.pos
  self.pos += 1  // skip opening quote

  // Check if this is a lifetime 'a instead of char
  if self.pos < self.len && is_ident_start(self.chars[self.pos]) {
    // Could be lifetime or char
    while self.pos < self.len && is_ident_part(self.chars[self.pos]) {
      self.pos += 1
    }

    // If followed by ', it's a char; otherwise it's a lifetime
    if self.pos < self.len && self.chars[self.pos] == '\'' {
      self.pos += 1
      return { token_type: Char, from: start, to: self.pos }
    } else {
      // It's a lifetime
      return { token_type: Lifetime, from: start, to: self.pos }
    }
  }

  // Regular char literal
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == '\'' {
      self.pos += 1
      break
    } else if c == '\\' && self.pos + 1 < self.len {
      self.pos += 2
    } else if c == '\n' {
      break
    } else {
      self.pos += 1
    }
  }
  { token_type: Char, from: start, to: self.pos }
}

///|
/// Read a number
fn RustTokenizer::read_number(self : RustTokenizer) -> RustToken {
  let start = self.pos

  if self.pos < self.len && self.chars[self.pos] == '0' {
    if self.pos + 1 < self.len {
      let next = self.chars[self.pos + 1]
      if next == 'x' || next == 'X' {
        // Hexadecimal
        self.pos += 2
        while self.pos < self.len {
          let c = self.chars[self.pos]
          if is_hex_digit(c) || c == '_' {
            self.pos += 1
          } else {
            break
          }
        }
        // Type suffix
        self.read_number_suffix()
        return { token_type: Number, from: start, to: self.pos }
      } else if next == 'b' || next == 'B' {
        // Binary
        self.pos += 2
        while self.pos < self.len {
          let c = self.chars[self.pos]
          if c == '0' || c == '1' || c == '_' {
            self.pos += 1
          } else {
            break
          }
        }
        self.read_number_suffix()
        return { token_type: Number, from: start, to: self.pos }
      } else if next == 'o' || next == 'O' {
        // Octal
        self.pos += 2
        while self.pos < self.len {
          let c = self.chars[self.pos]
          if (c >= '0' && c <= '7') || c == '_' {
            self.pos += 1
          } else {
            break
          }
        }
        self.read_number_suffix()
        return { token_type: Number, from: start, to: self.pos }
      }
    }
  }

  // Integer part
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if is_digit(c) || c == '_' {
      self.pos += 1
    } else {
      break
    }
  }

  // Decimal part
  if self.pos < self.len && self.chars[self.pos] == '.' {
    if self.pos + 1 < self.len && is_digit(self.chars[self.pos + 1]) {
      self.pos += 1
      while self.pos < self.len {
        let c = self.chars[self.pos]
        if is_digit(c) || c == '_' {
          self.pos += 1
        } else {
          break
        }
      }
    }
  }

  // Exponent part
  if self.pos < self.len {
    let c = self.chars[self.pos]
    if c == 'e' || c == 'E' {
      self.pos += 1
      if self.pos < self.len {
        let sign = self.chars[self.pos]
        if sign == '+' || sign == '-' {
          self.pos += 1
        }
      }
      while self.pos < self.len {
        let c = self.chars[self.pos]
        if is_digit(c) || c == '_' {
          self.pos += 1
        } else {
          break
        }
      }
    }
  }

  // Type suffix
  self.read_number_suffix()

  { token_type: Number, from: start, to: self.pos }
}

///|
/// Read number type suffix (u32, i64, f32, etc.)
fn RustTokenizer::read_number_suffix(self : RustTokenizer) -> Unit {
  if self.pos < self.len {
    let c = self.chars[self.pos]
    if c == 'u' || c == 'i' || c == 'f' {
      self.pos += 1
      while self.pos < self.len && is_digit(self.chars[self.pos]) {
        self.pos += 1
      }
    }
  }
}

///|
/// Read an identifier, keyword, or macro
fn RustTokenizer::read_identifier(self : RustTokenizer) -> RustToken {
  let start = self.pos
  let first_char = self.chars[self.pos]

  while self.pos < self.len && is_ident_part(self.chars[self.pos]) {
    self.pos += 1
  }

  // Check for macro (ends with !)
  if self.pos < self.len && self.chars[self.pos] == '!' {
    self.pos += 1
    return { token_type: Macro, from: start, to: self.pos }
  }

  let word = self.input.unsafe_substring(start~, end=self.pos)

  let token_type = match word {
    "true" | "false" => Bool
    _ if is_control_flow(word) => ControlFlow
    _ if is_keyword(word) => Keyword
    _ if is_builtin_type(word) => TypeName
    _ if is_uppercase(first_char) => TypeName
    _ => Identifier
  }

  { token_type, from: start, to: self.pos }
}

///|
/// Read a line comment
fn RustTokenizer::read_line_comment(self : RustTokenizer) -> RustToken {
  let start = self.pos

  // Check for doc comment /// or //!
  if self.pos + 2 < self.len {
    let third = self.chars[self.pos + 2]
    if third == '/' || third == '!' {
      self.pos += 3
      while self.pos < self.len && self.chars[self.pos] != '\n' {
        self.pos += 1
      }
      return { token_type: DocComment, from: start, to: self.pos }
    }
  }

  // Regular line comment
  self.pos += 2
  while self.pos < self.len && self.chars[self.pos] != '\n' {
    self.pos += 1
  }
  { token_type: LineComment, from: start, to: self.pos }
}

///|
/// Read a block comment
fn RustTokenizer::read_block_comment(self : RustTokenizer) -> RustToken {
  let start = self.pos
  self.pos += 2  // skip /*

  // Handle nested comments
  let mut depth = 1
  while self.pos + 1 < self.len && depth > 0 {
    if self.chars[self.pos] == '/' && self.chars[self.pos + 1] == '*' {
      depth += 1
      self.pos += 2
    } else if self.chars[self.pos] == '*' && self.chars[self.pos + 1] == '/' {
      depth -= 1
      self.pos += 2
    } else {
      self.pos += 1
    }
  }

  { token_type: BlockComment, from: start, to: self.pos }
}

///|
/// Read an attribute #[...]
fn RustTokenizer::read_attribute(self : RustTokenizer) -> RustToken {
  let start = self.pos
  self.pos += 1  // skip #

  // Check for #! (inner attribute)
  if self.pos < self.len && self.chars[self.pos] == '!' {
    self.pos += 1
  }

  // Check for [
  if self.pos < self.len && self.chars[self.pos] == '[' {
    self.pos += 1
    let mut depth = 1
    while self.pos < self.len && depth > 0 {
      let c = self.chars[self.pos]
      if c == '[' {
        depth += 1
      } else if c == ']' {
        depth -= 1
      }
      self.pos += 1
    }
  }

  { token_type: Attribute, from: start, to: self.pos }
}

///|
/// Read an operator
fn RustTokenizer::read_operator(self : RustTokenizer) -> RustToken {
  let start = self.pos
  let c = self.chars[self.pos]

  // Check for arrow -> or =>
  if c == '-' && self.pos + 1 < self.len && self.chars[self.pos + 1] == '>' {
    self.pos += 2
    return { token_type: Arrow, from: start, to: self.pos }
  }
  if c == '=' && self.pos + 1 < self.len && self.chars[self.pos + 1] == '>' {
    self.pos += 2
    return { token_type: Arrow, from: start, to: self.pos }
  }

  // Check for multi-character operators
  if self.pos + 2 < self.len {
    let c2 = self.chars[self.pos + 1]
    let c3 = self.chars[self.pos + 2]
    if (c == '<' && c2 == '<' && c3 == '=') ||
       (c == '>' && c2 == '>' && c3 == '=') ||
       (c == '.' && c2 == '.' && c3 == '=') ||
       (c == '.' && c2 == '.' && c3 == '.') {
      self.pos += 3
      return { token_type: Operator, from: start, to: self.pos }
    }
  }

  if self.pos + 1 < self.len {
    let c2 = self.chars[self.pos + 1]
    if (c == '=' && c2 == '=') ||
       (c == '!' && c2 == '=') ||
       (c == '<' && c2 == '=') ||
       (c == '>' && c2 == '=') ||
       (c == '+' && c2 == '=') ||
       (c == '-' && c2 == '=') ||
       (c == '*' && c2 == '=') ||
       (c == '/' && c2 == '=') ||
       (c == '%' && c2 == '=') ||
       (c == '&' && c2 == '&') ||
       (c == '|' && c2 == '|') ||
       (c == '&' && c2 == '=') ||
       (c == '|' && c2 == '=') ||
       (c == '^' && c2 == '=') ||
       (c == '<' && c2 == '<') ||
       (c == '>' && c2 == '>') ||
       (c == '.' && c2 == '.') {
      self.pos += 2
      return { token_type: Operator, from: start, to: self.pos }
    }
  }

  self.pos += 1
  { token_type: Operator, from: start, to: self.pos }
}

///|
/// Get next token
pub fn RustTokenizer::next_token(self : RustTokenizer) -> RustToken? {
  self.skip_whitespace()

  if self.pos >= self.len {
    return None
  }

  let start = self.pos
  let c = self.chars[self.pos]

  // Check for comments first
  if c == '/' && self.pos + 1 < self.len {
    let next = self.chars[self.pos + 1]
    if next == '/' {
      return Some(self.read_line_comment())
    } else if next == '*' {
      return Some(self.read_block_comment())
    }
  }

  // Check for attribute
  if c == '#' {
    return Some(self.read_attribute())
  }

  // Check for raw string
  if c == 'r' && self.pos + 1 < self.len {
    let next = self.chars[self.pos + 1]
    if next == '"' || next == '#' {
      return Some(self.read_string())
    }
  }

  // Check for byte string b"..." or byte b'x'
  if c == 'b' && self.pos + 1 < self.len {
    let next = self.chars[self.pos + 1]
    if next == '"' {
      self.pos += 1  // skip 'b'
      return Some(self.read_string())
    } else if next == '\'' {
      self.pos += 1  // skip 'b'
      return Some(self.read_char())
    }
  }

  let token = match c {
    '"' => self.read_string()
    '\'' => self.read_char()
    '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
      self.read_number()
    _ if is_ident_start(c) => self.read_identifier()
    '{' => {
      self.pos += 1
      { token_type: BraceOpen, from: start, to: self.pos }
    }
    '}' => {
      self.pos += 1
      { token_type: BraceClose, from: start, to: self.pos }
    }
    '[' => {
      self.pos += 1
      { token_type: BracketOpen, from: start, to: self.pos }
    }
    ']' => {
      self.pos += 1
      { token_type: BracketClose, from: start, to: self.pos }
    }
    '(' => {
      self.pos += 1
      { token_type: ParenOpen, from: start, to: self.pos }
    }
    ')' => {
      self.pos += 1
      { token_type: ParenClose, from: start, to: self.pos }
    }
    ';' => {
      self.pos += 1
      { token_type: Semicolon, from: start, to: self.pos }
    }
    ',' => {
      self.pos += 1
      { token_type: Comma, from: start, to: self.pos }
    }
    ':' => {
      if self.pos + 1 < self.len && self.chars[self.pos + 1] == ':' {
        self.pos += 2
        { token_type: ColonColon, from: start, to: self.pos }
      } else {
        self.pos += 1
        { token_type: Colon, from: start, to: self.pos }
      }
    }
    '.' => {
      // Check for range operators
      if self.pos + 1 < self.len && self.chars[self.pos + 1] == '.' {
        self.read_operator()
      } else {
        self.pos += 1
        { token_type: Dot, from: start, to: self.pos }
      }
    }
    '+' | '-' | '*' | '/' | '%' | '=' | '!' | '<' | '>' | '&' | '|' | '^' |
    '~' | '?' | '@' =>
      self.read_operator()
    _ => {
      self.pos += 1
      { token_type: Error, from: start, to: self.pos }
    }
  }

  Some(token)
}

///|
/// Tokenize entire input
pub fn RustTokenizer::tokenize_all(self : RustTokenizer) -> Array[RustToken] {
  let tokens : Array[RustToken] = []
  while true {
    match self.next_token() {
      Some(token) => tokens.push(token)
      None => break
    }
  }
  tokens
}
