///| Scanner utilities for markdown parsing

///|
/// Scanner state - uses Array[Char] for O(1) character access
/// Handles Unicode correctly by tracking UTF-16 offsets for non-BMP characters
pub(all) struct Scanner {
  source : String
  chars : Array[Char] // Pre-converted for fast access (code points)
  mut pos : Int // Position in code points
  len : Int // Length in code points
  utf16_offsets : Array[Int]? // Maps code point index -> UTF-16 index (None if all BMP)
}

///|
/// Check if a character is outside BMP (needs surrogate pair in UTF-16)
fn is_non_bmp(c : Char) -> Bool {
  c.to_int() > 0xFFFF
}

///|
/// Create a new scanner
pub fn Scanner::new(source : String) -> Scanner {
  let chars = source.to_array()
  let len = chars.length()

  // Check if we have any non-BMP characters
  let mut has_non_bmp = false
  for i = 0; i < len; i = i + 1 {
    if is_non_bmp(chars[i]) {
      has_non_bmp = true
      break
    }
  }

  // Only build UTF-16 offset array if needed (has non-BMP characters)
  let utf16_offsets : Array[Int]? = if has_non_bmp {
    let offsets : Array[Int] = Array::make(len + 1, 0)
    let mut utf16_pos = 0
    for i = 0; i < len; i = i + 1 {
      offsets[i] = utf16_pos
      if is_non_bmp(chars[i]) {
        utf16_pos += 2 // Surrogate pair
      } else {
        utf16_pos += 1
      }
    }
    offsets[len] = utf16_pos
    Some(offsets)
  } else {
    None // All BMP: code point index == UTF-16 index
  }

  { source, chars, pos: 0, len, utf16_offsets }
}

///|
/// Convert code point index to UTF-16 index
fn Scanner::to_utf16_index(self : Scanner, cp_index : Int) -> Int {
  match self.utf16_offsets {
    Some(offsets) => offsets[cp_index]
    None => cp_index // All BMP: same index
  }
}

///|
/// Check if at end of input
pub fn Scanner::is_eof(self : Scanner) -> Bool {
  self.pos >= self.len
}

///|
/// Peek current character (O(1) with Array[Char])
pub fn Scanner::peek(self : Scanner) -> Char? {
  if self.pos >= self.len {
    None
  } else {
    Some(self.chars[self.pos])
  }
}

///|
/// Peek character at offset from current position (O(1))
pub fn Scanner::peek_at(self : Scanner, offset : Int) -> Char? {
  let idx = self.pos + offset
  if idx >= self.len || idx < 0 {
    None
  } else {
    Some(self.chars[idx])
  }
}

///|
/// Advance position by n characters
pub fn Scanner::advance(self : Scanner, n : Int) -> Unit {
  self.pos = self.pos + n
  if self.pos > self.len {
    self.pos = self.len
  }
}

///|
/// Consume and return current character (O(1))
pub fn Scanner::consume(self : Scanner) -> Char? {
  if self.pos >= self.len {
    None
  } else {
    let c = self.chars[self.pos]
    self.pos += 1
    Some(c)
  }
}

///|
/// Get remaining substring from current position
pub fn Scanner::remaining(self : Scanner) -> String {
  if self.pos >= self.len {
    ""
  } else {
    // Convert code point position to UTF-16 position
    let utf16_start = self.to_utf16_index(self.pos)
    let utf16_end = self.to_utf16_index(self.len)
    self.source.unsafe_substring(start=utf16_start, end=utf16_end)
  }
}

///|
/// Get substring from start to end position (code point indices)
pub fn Scanner::substring(self : Scanner, start : Int, end : Int) -> String {
  // Clamp indices to valid range
  let clamped_start = if start < 0 { 0 } else if start > self.len { self.len } else { start }
  let clamped_end = if end < 0 { 0 } else if end > self.len { self.len } else { end }
  if clamped_start >= clamped_end {
    ""
  } else {
    // Convert code point positions to UTF-16 positions
    let utf16_start = self.to_utf16_index(clamped_start)
    let utf16_end = self.to_utf16_index(clamped_end)
    self.source.unsafe_substring(start=utf16_start, end=utf16_end)
  }
}

///|
/// Skip whitespace (space and tab only) - O(1) per char
pub fn Scanner::skip_spaces(self : Scanner) -> Int {
  let start = self.pos
  while self.pos < self.len {
    let c = self.chars[self.pos]
    if c == ' ' || c == '\t' {
      self.pos += 1
    } else {
      break
    }
  }
  self.pos - start
}

///|
/// Count leading spaces (without advancing) - O(1) per char
pub fn Scanner::count_leading_spaces(self : Scanner) -> Int {
  let mut count = 0
  let mut idx = self.pos
  while idx < self.len {
    let c = self.chars[idx]
    if c == ' ' {
      count += 1
      idx += 1
    } else if c == '\t' {
      // Tab counts as up to 4 spaces to next multiple of 4
      count = (count / 4 + 1) * 4
      idx += 1
    } else {
      break
    }
  }
  count
}

///|
/// Read until end of line (not consuming newline) - O(1) per char
pub fn Scanner::read_line(self : Scanner) -> String {
  let start = self.pos
  while self.pos < self.len {
    if self.chars[self.pos] == '\n' {
      break
    }
    self.pos += 1
  }
  // Convert code point positions to UTF-16 positions
  let utf16_start = self.to_utf16_index(start)
  let utf16_end = self.to_utf16_index(self.pos)
  self.source.unsafe_substring(start=utf16_start, end=utf16_end)
}

///|
/// Skip to next line (consuming newline if present) - O(1) per char
pub fn Scanner::skip_line(self : Scanner) -> Unit {
  while self.pos < self.len {
    let c = self.chars[self.pos]
    self.pos += 1
    if c == '\n' {
      break
    }
  }
}

///|
/// Check if current line is blank (only whitespace) - O(1) per char
pub fn Scanner::is_blank_line(self : Scanner) -> Bool {
  let mut idx = self.pos
  while idx < self.len {
    let c = self.chars[idx]
    if c == '\n' {
      return true
    }
    if c != ' ' && c != '\t' {
      return false
    }
    idx += 1
  }
  true
}

///|
/// Match a string at current position - optimized with Array[Char]
pub fn Scanner::matches(self : Scanner, s : String) -> Bool {
  let s_len = s.length()
  if self.pos + s_len > self.len {
    return false
  }
  // Note: s.get_char still O(n), but s is usually short (e.g. "---", "```")
  for i = 0; i < s_len; i = i + 1 {
    match s.get_char(i) {
      Some(b) if self.chars[self.pos + i] == b => continue
      _ => return false
    }
  }
  true
}

///|
/// Match and consume a string
pub fn Scanner::consume_str(self : Scanner, s : String) -> Bool {
  if self.matches(s) {
    self.pos += s.length()
    true
  } else {
    false
  }
}

///|
/// Count consecutive occurrences of a character from current position - O(1) per char
pub fn Scanner::count_char(self : Scanner, c : Char) -> Int {
  let mut count = 0
  let mut idx = self.pos
  while idx < self.len {
    if self.chars[idx] == c {
      count += 1
      idx += 1
    } else {
      break
    }
  }
  count
}

///|
/// Save current position
pub fn Scanner::save(self : Scanner) -> Int {
  self.pos
}

///|
/// Restore to saved position
pub fn Scanner::restore(self : Scanner, pos : Int) -> Unit {
  self.pos = pos
}

// =============================================================================
// Character utilities
// =============================================================================

///|
/// Check if character is ASCII whitespace
pub fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Check if character is a digit
pub fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// Check if character is ASCII letter
pub fn is_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// Check if character is alphanumeric
pub fn is_alphanumeric(c : Char) -> Bool {
  is_digit(c) || is_letter(c)
}

///|
/// Check if character is a punctuation mark
pub fn is_punctuation(c : Char) -> Bool {
  match c {
    '!'
    | '"'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '('
    | ')'
    | '*'
    | '+'
    | ','
    | '-'
    | '.'
    | '/'
    | ':'
    | ';'
    | '<'
    | '='
    | '>'
    | '?'
    | '@'
    | '['
    | '\\'
    | ']'
    | '^'
    | '_'
    | '`'
    | '{'
    | '|'
    | '}'
    | '~' => true
    _ => false
  }
}

///|
/// Check if char option matches specific char
pub fn char_is(opt : Char?, c : Char) -> Bool {
  match opt {
    Some(ch) => ch == c
    None => false
  }
}

///|
/// Check if char option is a digit
pub fn char_is_digit(opt : Char?) -> Bool {
  match opt {
    Some(c) => is_digit(c)
    None => false
  }
}
