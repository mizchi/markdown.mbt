///| Scanner utilities for markdown parsing

///|
/// Scanner state - uses UTF-16 indexing directly for BMP input and Array[Char]
/// for non-BMP input. Handles Unicode correctly by tracking UTF-16 offsets for
/// non-BMP characters.
pub(all) struct Scanner {
  source : String
  chars : Array[Char] // Empty for BMP input, pre-converted code points for non-BMP
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
fn has_surrogate_pair(source : String) -> Bool {
  let len = source.length()
  let mut idx = 0
  while idx + 1 < len {
    let c = source.unsafe_get(idx)
    if c.is_leading_surrogate() &&
      source.unsafe_get(idx + 1).is_trailing_surrogate() {
      return true
    }
    idx += 1
  }
  false
}

///|
/// Create a new scanner
pub fn Scanner::new(source : String) -> Scanner {
  if !has_surrogate_pair(source) {
    return Scanner::new_bmp(source)
  }
  let chars = source.to_array()
  let len = chars.length()

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
  { source, chars, pos: 0, len, utf16_offsets: Some(offsets) }
}

///|
fn Scanner::new_bmp(source : String) -> Scanner {
  let chars : Array[Char] = []
  { source, chars, pos: 0, len: source.length(), utf16_offsets: None }
}

///|
fn Scanner::is_bmp(self : Scanner) -> Bool {
  self.utf16_offsets is None
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
fn Scanner::unsafe_char_at(self : Scanner, index : Int) -> Char {
  match self.utf16_offsets {
    Some(_) => self.chars[index]
    None => self.source.unsafe_get(index).unsafe_to_char()
  }
}

///|
fn Scanner::move_to_line_end(self : Scanner) -> (Int, Int) {
  let start = self.pos
  match self.utf16_offsets {
    Some(_) =>
      while self.pos < self.len {
        if self.chars[self.pos] == '\n' {
          break
        }
        self.pos += 1
      }
    None =>
      while self.pos < self.len {
        if self.source.unsafe_get(self.pos) == 0x0A {
          break
        }
        self.pos += 1
      }
  }
  (start, self.pos)
}

///|
fn Scanner::write_range_to(
  self : Scanner,
  buf : StringBuilder,
  start : Int,
  end : Int,
) -> Unit {
  if end <= start {
    return
  }
  let utf16_start = self.to_utf16_index(start)
  let utf16_end = self.to_utf16_index(end)
  buf.write_view(self.source[utf16_start:utf16_end])
}

///|
fn Scanner::append_line_to(self : Scanner, buf : StringBuilder) -> Unit {
  let (start, end) = self.move_to_line_end()
  self.write_range_to(buf, start, end)
}

///|
fn Scanner::append_line_stripped_indent_to(
  self : Scanner,
  buf : StringBuilder,
  indent : Int,
) -> Unit {
  let (start, end) = self.move_to_line_end()
  let mut stripped = 0
  let mut idx = start
  while idx < end && stripped < indent {
    match self.unsafe_char_at(idx) {
      ' ' => {
        stripped += 1
        idx += 1
      }
      '\t' => {
        stripped += 4
        idx += 1
      }
      _ => break
    }
  }
  self.write_range_to(buf, idx, end)
}

///|
fn Scanner::line_contains(self : Scanner, needle : String) -> Bool {
  let needle_len = needle.length()
  if needle_len == 0 {
    return true
  }
  match self.utf16_offsets {
    Some(_) => {
      let mut idx = self.pos
      while idx + needle_len <= self.len && self.chars[idx] != '\n' {
        let mut matched = true
        for j = 0; j < needle_len; j = j + 1 {
          if idx + j >= self.len || self.chars[idx + j] == '\n' {
            matched = false
            break
          }
          let code = self.chars[idx + j].to_int()
          if code > 0xFFFF || code.to_uint16() != needle.unsafe_get(j) {
            matched = false
            break
          }
        }
        if matched {
          return true
        }
        idx += 1
      }
    }
    None => {
      let mut idx = self.pos
      while idx + needle_len <= self.len && self.source.unsafe_get(idx) != 0x0A {
        let mut matched = true
        for j = 0; j < needle_len; j = j + 1 {
          if idx + j >= self.len || self.source.unsafe_get(idx + j) == 0x0A {
            matched = false
            break
          }
          if self.source.unsafe_get(idx + j) != needle.unsafe_get(j) {
            matched = false
            break
          }
        }
        if matched {
          return true
        }
        idx += 1
      }
    }
  }
  false
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
    match self.utf16_offsets {
      Some(_) => Some(self.chars[self.pos])
      None => Some(self.source.unsafe_get(self.pos).unsafe_to_char())
    }
  }
}

///|
/// Peek character at offset from current position (O(1))
pub fn Scanner::peek_at(self : Scanner, offset : Int) -> Char? {
  let idx = self.pos + offset
  if idx >= self.len || idx < 0 {
    None
  } else {
    match self.utf16_offsets {
      Some(_) => Some(self.chars[idx])
      None => Some(self.source.unsafe_get(idx).unsafe_to_char())
    }
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
    let c = match self.utf16_offsets {
      Some(_) => self.chars[self.pos]
      None => self.source.unsafe_get(self.pos).unsafe_to_char()
    }
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
  let clamped_start = if start < 0 {
    0
  } else if start > self.len {
    self.len
  } else {
    start
  }
  let clamped_end = if end < 0 {
    0
  } else if end > self.len {
    self.len
  } else {
    end
  }
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
  match self.utf16_offsets {
    Some(_) =>
      while self.pos < self.len {
        let c = self.chars[self.pos]
        if c == ' ' || c == '\t' {
          self.pos += 1
        } else {
          break
        }
      }
    None =>
      while self.pos < self.len {
        let c = self.source.unsafe_get(self.pos)
        if c == 0x20 || c == 0x09 {
          self.pos += 1
        } else {
          break
        }
      }
  }
  self.pos - start
}

///|
/// Count leading spaces (without advancing) - O(1) per char
pub fn Scanner::count_leading_spaces(self : Scanner) -> Int {
  let mut count = 0
  let mut idx = self.pos
  match self.utf16_offsets {
    Some(_) =>
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
    None =>
      while idx < self.len {
        let c = self.source.unsafe_get(idx)
        if c == 0x20 {
          count += 1
          idx += 1
        } else if c == 0x09 {
          // Tab counts as up to 4 spaces to next multiple of 4
          count = (count / 4 + 1) * 4
          idx += 1
        } else {
          break
        }
      }
  }
  count
}

///|
/// Read until end of line (not consuming newline) - O(1) per char
pub fn Scanner::read_line(self : Scanner) -> String {
  let start = self.pos
  match self.utf16_offsets {
    Some(_) =>
      while self.pos < self.len {
        if self.chars[self.pos] == '\n' {
          break
        }
        self.pos += 1
      }
    None =>
      while self.pos < self.len {
        if self.source.unsafe_get(self.pos) == 0x0A {
          break
        }
        self.pos += 1
      }
  }
  // Convert code point positions to UTF-16 positions
  let utf16_start = self.to_utf16_index(start)
  let utf16_end = self.to_utf16_index(self.pos)
  self.source.unsafe_substring(start=utf16_start, end=utf16_end)
}

///|
/// Skip to next line (consuming newline if present) - O(1) per char
pub fn Scanner::skip_line(self : Scanner) -> Unit {
  match self.utf16_offsets {
    Some(_) =>
      while self.pos < self.len {
        let c = self.chars[self.pos]
        self.pos += 1
        if c == '\n' {
          break
        }
      }
    None =>
      while self.pos < self.len {
        let c = self.source.unsafe_get(self.pos)
        self.pos += 1
        if c == 0x0A {
          break
        }
      }
  }
}

///|
/// Check if current line is blank (only whitespace) - O(1) per char
pub fn Scanner::is_blank_line(self : Scanner) -> Bool {
  let mut idx = self.pos
  match self.utf16_offsets {
    Some(_) =>
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
    None =>
      while idx < self.len {
        let c = self.source.unsafe_get(idx)
        if c == 0x0A {
          return true
        }
        if c != 0x20 && c != 0x09 {
          return false
        }
        idx += 1
      }
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
      Some(b) if self.unsafe_char_at(self.pos + i) == b => continue
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
  match self.utf16_offsets {
    Some(_) =>
      while idx < self.len {
        if self.chars[idx] == c {
          count += 1
          idx += 1
        } else {
          break
        }
      }
    None => {
      if c.to_int() > 0xFFFF {
        return 0
      }
      let code = c.to_int().to_uint16()
      while idx < self.len {
        if self.source.unsafe_get(idx) == code {
          count += 1
          idx += 1
        } else {
          break
        }
      }
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
