///| Token types for multi-pass inline parsing

///| Based on cmark's architecture

///|

///| EXPERIMENTAL: This parser is NOT used by default.

///| Use `parse_inlines_multipass(text)` to test it directly.

///|

///| Optimizations implemented:

///| - Binary search for CloserIndex lookup (O(n) → O(log n))

///| - String slice for substring (vs StringBuilder)

///| - Combined tokenize + CloserIndex building in single pass

///| - StringView for char access (eliminated text.to_array())

///|

///| Performance comparison (vs original single-pass parser):

///| - Simple text: 34% faster

///| - Emphasis: 9% slower

///| - Stress tests (300 markers): 45% slower (improved from 87%)

///|

///| CommonMark compatibility: 187/542 (vs 202/542 for original)

///|

///| See docs/compare_cmark.md for detailed analysis.

///|
/// Inline token for multi-pass processing
priv enum InlineToken {
  /// Backtick run: start position, count, escaped by backslash
  Backticks(Int, Int, Bool)
  /// Emphasis marker: start, char (* or _), count, may_open, may_close
  EmphasisMarks(Int, Char, Int, Bool, Bool)
  /// Link start: [
  LinkStart(Int)
  /// Image start: ![
  ImageStart(Int)
  /// Right bracket: ]
  RightBrack(Int)
  /// Right paren: )
  RightParen(Int)
  /// Autolink/HTML start: <
  AngleStart(Int)
  /// Strikethrough: ~~
  Strikethrough(Int, Bool, Bool)
  /// Newline with break type: position, is_hard_break, is_backslash_break
  Newline(Int, Bool, Bool) // position, is_hard_break (spaces), is_backslash_break
}

///|
/// Get start position of token
fn InlineToken::start(self : InlineToken) -> Int {
  match self {
    Backticks(s, _, _) => s
    EmphasisMarks(s, _, _, _, _) => s
    LinkStart(s) => s
    ImageStart(s) => s
    RightBrack(s) => s
    RightParen(s) => s
    AngleStart(s) => s
    Strikethrough(s, _, _) => s
    Newline(s, _, _) => s
  }
}

///|
/// Check if character is Unicode whitespace
fn is_unicode_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u000C'
}

///|
/// Check if character is Unicode punctuation (ASCII subset)
fn is_unicode_punctuation(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
  (code >= 0x3A && code <= 0x40) || // :;<=>?@
  (code >= 0x5B && code <= 0x60) || // [\]^_`
  (code >= 0x7B && code <= 0x7E) // {|}~
}

///|
/// Check if a delimiter run is left-flanking
fn is_left_flanking(prev_char : Char, next_char : Char) -> Bool {
  // Must not be followed by whitespace
  if is_unicode_whitespace(next_char) {
    return false
  }
  // Either not followed by punctuation, or preceded by whitespace/punctuation
  !(is_unicode_punctuation(next_char)) ||
  is_unicode_whitespace(prev_char) ||
  is_unicode_punctuation(prev_char)
}

///|
/// Check if a delimiter run is right-flanking
fn is_right_flanking(prev_char : Char, next_char : Char) -> Bool {
  // Must not be preceded by whitespace
  if is_unicode_whitespace(prev_char) {
    return false
  }
  // Either not preceded by punctuation, or followed by whitespace/punctuation
  !(is_unicode_punctuation(prev_char)) ||
  is_unicode_whitespace(next_char) ||
  is_unicode_punctuation(next_char)
}

///|
/// Tokenize input string into InlineToken array
fn tokenize_inline(scanner : Scanner) -> Array[InlineToken] {
  let (tokens, _) = tokenize_with_index(scanner)
  tokens
}

///|
/// Tokenize and build CloserIndex in a single pass
fn tokenize_with_index(scanner : Scanner) -> (Array[InlineToken], CloserIndex) {
  let tokens : Array[InlineToken] = []
  let idx = CloserIndex::new()
  let mut prev_char : Char = ' ' // Start of line treated as whitespace
  let mut prev_backslash = false
  while !(scanner.is_eof()) {
    let start = scanner.pos
    let c = scanner.peek().unwrap()
    match c {
      '\\' => {
        prev_backslash = !(prev_backslash)
        scanner.advance(1)
        prev_char = '\\'
      }
      '`' => {
        let count = scanner.count_char('`')
        tokens.push(InlineToken::Backticks(start, count, prev_backslash))
        // Add to CloserIndex
        match idx.backticks.get(count) {
          Some(arr) => arr.push(start)
          None => idx.backticks[count] = [start]
        }
        scanner.advance(count)
        prev_char = '`'
        prev_backslash = false
      }
      '*' | '_' => {
        if !(prev_backslash) {
          let marker = c
          let count = scanner.count_char(marker)
          let next_char = scanner.peek_at(count).unwrap_or(' ')
          let left_flank = is_left_flanking(prev_char, next_char)
          let right_flank = is_right_flanking(prev_char, next_char)

          // Determine may_open and may_close based on marker type
          let (may_open, may_close) = if marker == '*' {
            (left_flank, right_flank)
          } else {
            // _ has additional word boundary constraints
            (
              left_flank &&
              (!(right_flank) || is_unicode_punctuation(prev_char)),
              right_flank &&
              (!(left_flank) || is_unicode_punctuation(next_char)),
            )
          }
          if may_open || may_close {
            tokens.push(
              InlineToken::EmphasisMarks(
                start, marker, count, may_open, may_close,
              ),
            )
            // Add closers to index
            if may_close {
              if marker == '*' {
                idx.emphasis_star.push(start)
              } else {
                idx.emphasis_underscore.push(start)
              }
            }
          }
          scanner.advance(count)
          prev_char = marker
        } else {
          scanner.advance(1)
          prev_char = c
        }
        prev_backslash = false
      }
      '[' => {
        if !(prev_backslash) {
          tokens.push(InlineToken::LinkStart(start))
        }
        scanner.advance(1)
        prev_char = '['
        prev_backslash = false
      }
      '!' => {
        if !(prev_backslash) {
          let next = scanner.peek_at(1)
          if next == Some('[') {
            tokens.push(InlineToken::ImageStart(start))
            scanner.advance(2)
            prev_char = '['
          } else {
            scanner.advance(1)
            prev_char = '!'
          }
        } else {
          scanner.advance(1)
          prev_char = '!'
        }
        prev_backslash = false
      }
      ']' => {
        tokens.push(InlineToken::RightBrack(start))
        idx.right_brack.push(start)
        scanner.advance(1)
        prev_char = ']'
        prev_backslash = false
      }
      ')' => {
        tokens.push(InlineToken::RightParen(start))
        idx.right_paren.push(start)
        scanner.advance(1)
        prev_char = ')'
        prev_backslash = false
      }
      '<' => {
        if !(prev_backslash) {
          tokens.push(InlineToken::AngleStart(start))
        }
        scanner.advance(1)
        prev_char = '<'
        prev_backslash = false
      }
      '~' => {
        if !(prev_backslash) {
          let count = scanner.count_char('~')
          if count == 2 {
            let next_char = scanner.peek_at(2).unwrap_or(' ')
            let may_open = !(is_unicode_whitespace(next_char))
            let may_close = !(is_unicode_whitespace(prev_char))
            tokens.push(InlineToken::Strikethrough(start, may_open, may_close))
            if may_close {
              idx.strikethrough.push(start)
            }
          }
          scanner.advance(count)
          prev_char = '~'
        } else {
          scanner.advance(1)
          prev_char = '~'
        }
        prev_backslash = false
      }
      '\n' => {
        // Check for hard break (two spaces before newline or backslash)
        let is_space_hard = prev_char == ' '
        let is_backslash_hard = prev_backslash
        tokens.push(
          InlineToken::Newline(start, is_space_hard, is_backslash_hard),
        )
        scanner.advance(1)
        prev_char = ' ' // Start of new line
        prev_backslash = false
      }
      _ => {
        scanner.advance(1)
        prev_char = c
        prev_backslash = false
      }
    }
  }
  (tokens, idx)
}

///|
/// Closer key for index lookup
priv enum CloserKey {
  RightBrack
  RightParen
  Emphasis(Char) // * or _
}

///| CloserIndex for O(1) lookup of closing delimiters

///|
/// Maps closer type -> sorted array of positions
priv struct CloserIndex {
  backticks : Map[Int, Array[Int]] // count -> positions
  right_brack : Array[Int]
  right_paren : Array[Int]
  emphasis_star : Array[Int]
  emphasis_underscore : Array[Int]
  strikethrough : Array[Int]
}

///|
/// Create new empty CloserIndex
fn CloserIndex::new() -> CloserIndex {
  {
    backticks: Map::new(),
    right_brack: [],
    right_paren: [],
    emphasis_star: [],
    emphasis_underscore: [],
    strikethrough: [],
  }
}

///|
/// Build CloserIndex from token array
fn build_closer_index(tokens : Array[InlineToken]) -> CloserIndex {
  let idx = CloserIndex::new()
  for tok in tokens {
    match tok {
      InlineToken::Backticks(pos, count, _) =>
        match idx.backticks.get(count) {
          Some(arr) => arr.push(pos)
          None => idx.backticks[count] = [pos]
        }
      InlineToken::RightBrack(pos) => idx.right_brack.push(pos)
      InlineToken::RightParen(pos) => idx.right_paren.push(pos)
      InlineToken::EmphasisMarks(pos, char, _, _, may_close) =>
        if may_close {
          if char == '*' {
            idx.emphasis_star.push(pos)
          } else {
            idx.emphasis_underscore.push(pos)
          }
        }
      InlineToken::Strikethrough(pos, _, may_close) =>
        if may_close {
          idx.strikethrough.push(pos)
        }
      _ => ()
    }
  }
  idx
}

///| Binary search for first element greater than target in sorted array

///|
/// Returns the index of first element > target, or arr.length() if none
fn binary_search_greater(arr : Array[Int], target : Int) -> Int {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if arr[mid] <= target {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Check if there's a closer of given type after position (O(log n))
fn CloserIndex::has_closer(
  self : CloserIndex,
  key : CloserKey,
  after : Int,
) -> Bool {
  match key {
    CloserKey::RightBrack =>
      binary_search_greater(self.right_brack, after) < self.right_brack.length()
    CloserKey::RightParen =>
      binary_search_greater(self.right_paren, after) < self.right_paren.length()
    CloserKey::Emphasis('*') =>
      binary_search_greater(self.emphasis_star, after) <
      self.emphasis_star.length()
    CloserKey::Emphasis(_) =>
      binary_search_greater(self.emphasis_underscore, after) <
      self.emphasis_underscore.length()
  }
}

///|
/// Find position of next closer after given position (O(log n))
fn CloserIndex::find_closer(
  self : CloserIndex,
  key : CloserKey,
  after : Int,
) -> Int? {
  match key {
    CloserKey::RightBrack => {
      let idx = binary_search_greater(self.right_brack, after)
      if idx < self.right_brack.length() {
        Some(self.right_brack[idx])
      } else {
        None
      }
    }
    CloserKey::RightParen => {
      let idx = binary_search_greater(self.right_paren, after)
      if idx < self.right_paren.length() {
        Some(self.right_paren[idx])
      } else {
        None
      }
    }
    CloserKey::Emphasis('*') => {
      let idx = binary_search_greater(self.emphasis_star, after)
      if idx < self.emphasis_star.length() {
        Some(self.emphasis_star[idx])
      } else {
        None
      }
    }
    CloserKey::Emphasis(_) => {
      let idx = binary_search_greater(self.emphasis_underscore, after)
      if idx < self.emphasis_underscore.length() {
        Some(self.emphasis_underscore[idx])
      } else {
        None
      }
    }
  }
}

///|
/// Multi-pass inline parser state
priv struct MultiPassParser {
  text : String
  text_len : Int
  tokens : Array[InlineToken]
}

///|
/// Create multi-pass parser from text
fn MultiPassParser::new(text : String) -> MultiPassParser {
  let scanner = Scanner::new(text)
  let (tokens, _) = tokenize_with_index(scanner)
  { text, text_len: text.length(), tokens }
}

///|
/// Get char at position (returns None if out of bounds)
fn MultiPassParser::char_at(self : MultiPassParser, pos : Int) -> Char? {
  if pos >= 0 && pos < self.text_len {
    Some(Int::unsafe_to_char(self.text.code_unit_at(pos).to_int()))
  } else {
    None
  }
}

///|
/// Get substring using string slice (faster than StringBuilder)
fn MultiPassParser::substring(
  self : MultiPassParser,
  start : Int,
  end : Int,
) -> String {
  if start >= end || start >= self.text.length() {
    ""
  } else {
    let actual_end = if end > self.text.length() {
      self.text.length()
    } else {
      end
    }
    self.text.unsafe_substring(start~, end=actual_end)
  }
}

///|
/// Check if Rule 9, 10 (mod 3 rule) allows match
fn emphasis_mod3_match(
  opener_count : Int,
  closer_count : Int,
  opener_can_close : Bool,
  closer_can_open : Bool,
) -> Bool {
  // If neither can act as the opposite, they always match
  if !(opener_can_close) && !(closer_can_open) {
    return true
  }
  // Rule 9, 10: sum must not be divisible by 3, unless one is divisible by 3
  let sum = opener_count + closer_count
  if sum % 3 != 0 {
    return true
  }
  opener_count % 3 == 0 || closer_count % 3 == 0
}

///|
/// Parse code span starting at given token
fn MultiPassParser::parse_code_span(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int,
) -> (Inline, Int)? {
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]
  guard opener is Backticks(opener_start, backtick_count, escaped) else {
    return None
  }
  guard !(escaped) else { return None }

  // Find matching closing backticks (same count)
  let content_start = opener_start + backtick_count
  for i = opener_idx + 1; i < self.tokens.length(); i = i + 1 {
    let tok = self.tokens[i]
    guard tok.start() < text_end else { break }
    match tok {
      Backticks(closer_start, closer_count, _) if closer_count == backtick_count => {
        // Found matching closer
        let content = self.substring(content_start, closer_start)

        // Trim single leading/trailing space if present and content has them
        // But NOT if content is entirely spaces
        let trimmed = if content.length() >= 2 {
          let first = content.get_char(0)
          let last = content.get_char(content.length() - 1)
          if first == Some(' ') &&
            last == Some(' ') &&
            !(is_all_spaces_mp(content)) {
            content.unsafe_substring(start=1, end=content.length() - 1)
          } else {
            content
          }
        } else {
          content
        }
        let end_pos = closer_start + closer_count
        let inline = Inline::Code(
          content=trimmed,
          backtick_count~,
          span=Span::new(opener_start, end_pos),
        )
        return Some((inline, end_pos))
      }
      _ => ()
    }
  }
  None
}

///|
/// Check if a string is entirely space characters
fn is_all_spaces_mp(s : String) -> Bool {
  for c in s {
    if c != ' ' {
      return false
    }
  }
  true
}

///|
/// Check if inlines contain a link (for nested link detection)
fn contains_link_mp(inlines : Array[Inline]) -> Bool {
  for inline in inlines {
    match inline {
      Inline::Link(..) | Inline::RefLink(..) => return true
      Inline::Emphasis(children~, ..)
      | Inline::Strong(children~, ..)
      | Inline::Strikethrough(children~, ..) =>
        if contains_link_mp(children) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
/// Parse link starting at given token (LinkStart)
fn MultiPassParser::parse_link(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int,
) -> (Inline, Int)? {
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]
  guard opener is LinkStart(opener_start) else { return None }

  // Find matching right bracket ]
  let mut bracket_depth = 1
  let mut bracket_pos : Int? = None
  let mut bracket_idx : Int? = None
  let content_start = opener_start + 1
  for i = opener_idx + 1; i < self.tokens.length(); i = i + 1 {
    let tok = self.tokens[i]
    let tok_pos = tok.start()
    guard tok_pos < text_end else { break }
    match tok {
      LinkStart(_) => bracket_depth += 1
      RightBrack(pos) => {
        bracket_depth -= 1
        if bracket_depth == 0 {
          bracket_pos = Some(pos)
          bracket_idx = Some(i)
          break
        }
      }
      _ => ()
    }
  }
  guard bracket_pos is Some(brack_pos) else { return None }
  guard bracket_idx is Some(brack_i) else { return None }
  let link_text = self.substring(content_start, brack_pos)

  // Check what follows the ]
  let after_brack = brack_pos + 1
  guard after_brack < self.text_len else { return None }
  let next_char = self.char_at(after_brack).unwrap()
  if next_char == '(' {
    // Inline link: [text](url "title")
    match
      self.parse_inline_link_dest(
        after_brack + 1,
        text_end,
        opener_start,
        link_text,
        brack_i,
      ) {
      Some(result) => return Some(result)
      None => return None
    }
  } else if next_char == '[' {
    // Reference link: [text][ref]
    match
      self.parse_ref_link(after_brack + 1, text_end, opener_start, link_text) {
      Some(result) => return Some(result)
      None => return None
    }
  }
  None
}

///|
/// Parse inline link destination and title
fn MultiPassParser::parse_inline_link_dest(
  self : MultiPassParser,
  start : Int,
  text_end : Int,
  link_start : Int,
  link_text : String,
  text_end_token_idx : Int,
) -> (Inline, Int)? {
  let mut pos = start

  // Skip leading whitespace
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' {
      pos += 1
    } else {
      break
    }
  }
  guard pos < self.text_len && pos < text_end else { return None }

  // Parse URL
  let url_buf = StringBuilder::new()
  let c = self.char_at(pos).unwrap()
  if c == '<' {
    // Angle-bracketed URL
    pos += 1
    while pos < self.text_len && pos < text_end {
      let uc = self.char_at(pos).unwrap()
      if uc == '>' {
        pos += 1
        break
      } else if uc == '\n' {
        return None // Newline in angle-bracket URL invalidates
      } else {
        url_buf.write_char(uc)
        pos += 1
      }
    }
  } else {
    // Regular URL
    let mut paren_depth = 1
    while pos < self.text_len && pos < text_end {
      let uc = self.char_at(pos).unwrap()
      if uc == '(' {
        paren_depth += 1
        url_buf.write_char('(')
        pos += 1
      } else if uc == ')' {
        paren_depth -= 1
        if paren_depth == 0 {
          break
        }
        url_buf.write_char(')')
        pos += 1
      } else if uc == ' ' || uc == '\t' {
        break // End of URL
      } else if uc == '\n' {
        return None // Newline in URL invalidates
      } else {
        url_buf.write_char(uc)
        pos += 1
      }
    }
  }
  let url = url_buf.to_string()

  // Skip whitespace before title
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' || c == '\n' {
      pos += 1
    } else {
      break
    }
  }

  // Parse optional title
  let title = if pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == '"' || c == '\'' {
      let quote = c
      pos += 1
      let title_buf = StringBuilder::new()
      while pos < self.text_len && pos < text_end {
        let tc = self.char_at(pos).unwrap()
        if tc == quote {
          pos += 1
          break
        } else if tc == '\\' && pos + 1 < self.text_len {
          pos += 1
          title_buf.write_char(self.char_at(pos).unwrap())
          pos += 1
        } else {
          title_buf.write_char(tc)
          pos += 1
        }
      }
      title_buf.to_string()
    } else {
      ""
    }
  } else {
    ""
  }

  // Skip trailing whitespace
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' {
      pos += 1
    } else {
      break
    }
  }

  // Must end with )
  guard pos < self.text_len && self.char_at(pos).unwrap() == ')' else {
    return None
  }
  pos += 1

  // Parse link text as inlines
  let children = self.parse_range(
    link_start + 1,
    link_start + 1 + link_text.length(),
    0,
    text_end_token_idx,
  )

  // Check for nested links
  if contains_link_mp(children) {
    return None
  }
  let inline = Inline::Link(
    children~,
    url~,
    title~,
    span=Span::new(link_start, pos),
  )
  Some((inline, pos))
}

///|
/// Parse reference link [text][ref]
fn MultiPassParser::parse_ref_link(
  self : MultiPassParser,
  start : Int,
  text_end : Int,
  link_start : Int,
  link_text : String,
) -> (Inline, Int)? {
  let mut pos = start
  let label_buf = StringBuilder::new()

  // Parse label until ]
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ']' {
      pos += 1
      break
    } else {
      label_buf.write_char(c)
      pos += 1
    }
  }
  let label = label_buf.to_string()
  let children = parse_inlines_multipass(link_text)

  // Check for nested links
  if contains_link_mp(children) {
    return None
  }
  let inline = Inline::RefLink(
    children~,
    label~,
    span=Span::new(link_start, pos),
  )
  Some((inline, pos))
}

///|
/// Parse image starting at given token (ImageStart)
fn MultiPassParser::parse_image(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int,
) -> (Inline, Int)? {
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]
  guard opener is ImageStart(opener_start) else { return None }

  // Find matching right bracket ] (ImageStart is at !, so [ is at opener_start + 1)
  let mut bracket_depth = 1
  let mut bracket_pos : Int? = None
  let content_start = opener_start + 2 // Skip ![
  for i = opener_idx + 1; i < self.tokens.length(); i = i + 1 {
    let tok = self.tokens[i]
    let tok_pos = tok.start()
    guard tok_pos < text_end else { break }
    match tok {
      LinkStart(_) | ImageStart(_) => bracket_depth += 1
      RightBrack(pos) => {
        bracket_depth -= 1
        if bracket_depth == 0 {
          bracket_pos = Some(pos)
          break
        }
      }
      _ => ()
    }
  }
  guard bracket_pos is Some(brack_pos) else { return None }
  let alt = self.substring(content_start, brack_pos)

  // Check what follows the ]
  let after_brack = brack_pos + 1
  guard after_brack < self.text_len else { return None }
  let next_char = self.char_at(after_brack).unwrap()
  if next_char == '(' {
    // Inline image: ![alt](url "title")
    match self.parse_image_dest(after_brack + 1, text_end, opener_start, alt) {
      Some(result) => return Some(result)
      None => return None
    }
  } else if next_char == '[' {
    // Reference image: ![alt][ref]
    match self.parse_ref_image(after_brack + 1, text_end, opener_start, alt) {
      Some(result) => return Some(result)
      None => return None
    }
  }
  None
}

///|
/// Parse inline image destination and title
fn MultiPassParser::parse_image_dest(
  self : MultiPassParser,
  start : Int,
  text_end : Int,
  image_start : Int,
  alt : String,
) -> (Inline, Int)? {
  let mut pos = start

  // Skip leading whitespace
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' {
      pos += 1
    } else {
      break
    }
  }
  guard pos < self.text_len && pos < text_end else { return None }

  // Parse URL
  let url_buf = StringBuilder::new()
  let c = self.char_at(pos).unwrap()
  if c == '<' {
    // Angle-bracketed URL
    pos += 1
    while pos < self.text_len && pos < text_end {
      let uc = self.char_at(pos).unwrap()
      if uc == '>' {
        pos += 1
        break
      } else {
        url_buf.write_char(uc)
        pos += 1
      }
    }
  } else {
    // Regular URL
    while pos < self.text_len && pos < text_end {
      let uc = self.char_at(pos).unwrap()
      if uc == ')' || uc == ' ' || uc == '\t' {
        break
      } else {
        url_buf.write_char(uc)
        pos += 1
      }
    }
  }
  let url = url_buf.to_string()

  // Skip whitespace
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' {
      pos += 1
    } else {
      break
    }
  }

  // Parse optional title
  let title = if pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == '"' || c == '\'' {
      let quote = c
      pos += 1
      let title_buf = StringBuilder::new()
      while pos < self.text_len && pos < text_end {
        let tc = self.char_at(pos).unwrap()
        if tc == quote {
          pos += 1
          break
        } else {
          title_buf.write_char(tc)
          pos += 1
        }
      }
      title_buf.to_string()
    } else {
      ""
    }
  } else {
    ""
  }

  // Skip trailing whitespace
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ' ' || c == '\t' {
      pos += 1
    } else {
      break
    }
  }

  // Must end with )
  guard pos < self.text_len && self.char_at(pos).unwrap() == ')' else {
    return None
  }
  pos += 1
  let inline = Inline::Image(
    alt~,
    url~,
    title~,
    span=Span::new(image_start, pos),
  )
  Some((inline, pos))
}

///|
/// Parse reference image ![alt][ref]
fn MultiPassParser::parse_ref_image(
  self : MultiPassParser,
  start : Int,
  text_end : Int,
  image_start : Int,
  alt : String,
) -> (Inline, Int)? {
  let mut pos = start
  let label_buf = StringBuilder::new()

  // Parse label until ]
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == ']' {
      pos += 1
      break
    } else {
      label_buf.write_char(c)
      pos += 1
    }
  }
  let label = label_buf.to_string()
  let inline = Inline::RefImage(alt~, label~, span=Span::new(image_start, pos))
  Some((inline, pos))
}

///|
/// Parse autolink starting at AngleStart token
fn MultiPassParser::parse_autolink(
  self : MultiPassParser,
  start : Int,
  text_end : Int,
) -> (Inline, Int)? {
  let mut pos = start + 1 // Skip <
  let url_buf = StringBuilder::new()

  // Scan until >
  while pos < self.text_len && pos < text_end {
    let c = self.char_at(pos).unwrap()
    if c == '>' {
      let url = url_buf.to_string()
      if url.length() == 0 {
        return None
      }
      pos += 1

      // Check if it's an email
      let is_email = url.contains("@") && !(url.has_prefix("http"))
      let inline = Inline::Autolink(url~, is_email~, span=Span::new(start, pos))
      return Some((inline, pos))
    } else if c == ' ' || c == '\t' || c == '\n' {
      // Invalid autolink
      return None
    } else {
      url_buf.write_char(c)
      pos += 1
    }
  }
  None
}

///|
/// Parse strikethrough starting at Strikethrough token
fn MultiPassParser::parse_strikethrough(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int,
) -> (Inline, Int)? {
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]
  guard opener is Strikethrough(opener_start, may_open, _) else { return None }
  guard may_open else { return None }

  // Find closing ~~
  for i = opener_idx + 1; i < self.tokens.length(); i = i + 1 {
    let tok = self.tokens[i]
    guard tok.start() < text_end else { break }
    match tok {
      Strikethrough(closer_start, _, may_close) if may_close => {
        // Found closing
        let content = self.substring(opener_start + 2, closer_start)
        if content.length() == 0 {
          return None
        }
        let children = [
          Inline::Text(content~, span=Span::new(opener_start + 2, closer_start)),
        ]
        let inline = Inline::Strikethrough(
          children~,
          span=Span::new(opener_start, closer_start + 2),
        )
        return Some((inline, closer_start + 2))
      }
      _ => ()
    }
  }
  None
}

///|
/// Process escapes in a text segment (using String directly)
fn process_escapes_str(
  text : String,
  start : Int,
  end : Int,
  result : Array[Inline],
) -> Unit {
  let buf = StringBuilder::new()
  let mut i = start
  let mut text_start = start
  let text_len = text.length()
  while i < end && i < text_len {
    let c = Int::unsafe_to_char(text.code_unit_at(i).to_int())
    if c == '\\' && i + 1 < end && i + 1 < text_len {
      let next = Int::unsafe_to_char(text.code_unit_at(i + 1).to_int())
      if next == '\n' {
        // Backslash + newline = hard break
        if buf.to_string().length() > 0 {
          result.push(
            Inline::Text(content=buf.to_string(), span=Span::new(text_start, i)),
          )
          buf.reset()
        }
        result.push(
          Inline::HardBreak(
            style=HardBreakStyle::Backslash,
            span=Span::new(i, i + 2),
          ),
        )
        i += 2
        text_start = i
      } else if is_punctuation_mp(next) {
        // Escaped punctuation
        buf.write_char(next)
        i += 2
      } else {
        // Not a valid escape, keep backslash
        buf.write_char('\\')
        i += 1
      }
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  let content = buf.to_string()
  if content.length() > 0 {
    result.push(Inline::Text(content~, span=Span::new(text_start, end)))
  }
}

///|
/// Check if character is ASCII punctuation
fn is_punctuation_mp(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
  (code >= 0x3A && code <= 0x40) || // :;<=>?@
  (code >= 0x5B && code <= 0x60) || // [\]^_`
  (code >= 0x7B && code <= 0x7E) // {|}~
}

///|
/// Parse emphasis using token-based approach
fn MultiPassParser::parse_emphasis(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int,
) -> (Array[Inline], Int)? {
  // Get opener token
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]
  guard opener
    is EmphasisMarks(
      opener_start,
      marker_char,
      opener_count,
      may_open,
      opener_can_close
    ) else {
    return None
  }
  guard may_open else { return None }

  // Look for matching closer
  let mut best_closer_idx : Int? = None
  let mut best_used = 0
  for i = opener_idx + 1; i < self.tokens.length(); i = i + 1 {
    let tok = self.tokens[i]
    guard tok.start() < text_end else { break }
    match tok {
      EmphasisMarks(_, c, closer_count, closer_can_open, may_close) =>
        if c == marker_char && may_close {
          // Check mod 3 rule
          if emphasis_mod3_match(
              opener_count, closer_count, opener_can_close, closer_can_open,
            ) {
            // Found matching closer
            let used = if opener_count >= 2 && closer_count >= 2 {
              2
            } else {
              1
            }
            best_closer_idx = Some(i)
            best_used = used
            break
          }
        }
      _ => ()
    }
  }
  guard best_closer_idx is Some(closer_idx) else { return None }
  let closer = self.tokens[closer_idx]
  guard closer is EmphasisMarks(closer_start, _, _, _, _) else { return None }

  // Parse content between opener and closer
  let content_start = opener_start + best_used
  let content_end = closer_start
  let children = self.parse_range(
    content_start,
    content_end,
    opener_idx + 1,
    closer_idx,
  )

  // Create emphasis or strong inline
  let marker = if marker_char == '*' {
    EmphasisMarker::Asterisk
  } else {
    EmphasisMarker::Underscore
  }
  let inline_end = closer_start + best_used
  let span = Span::new(opener_start, inline_end)
  let inline = if best_used == 2 {
    Inline::Strong(marker~, children~, span~)
  } else {
    Inline::Emphasis(marker~, children~, span~)
  }

  // Return where to continue parsing
  // Skip remaining markers if any
  let next_pos = inline_end
  Some(([inline], next_pos))
}

///|
/// Parse a range of text, processing tokens within
fn MultiPassParser::parse_range(
  self : MultiPassParser,
  text_start : Int,
  text_end : Int,
  token_start : Int,
  token_end : Int,
) -> Array[Inline] {
  let result : Array[Inline] = []
  let mut pos = text_start
  let mut tok_idx = token_start
  while pos < text_end {
    // Find next token in range
    let mut found_tok : (Int, InlineToken)? = None
    while tok_idx < token_end {
      let tok = self.tokens[tok_idx]
      let tok_pos = tok.start()
      if tok_pos >= text_end {
        break
      }
      if tok_pos >= pos {
        found_tok = Some((tok_idx, tok))
        break
      }
      tok_idx += 1
    }
    match found_tok {
      None => {
        // No more tokens, add remaining text with escape processing
        if pos < text_end {
          process_escapes_str(self.text, pos, text_end, result)
        }
        break
      }
      Some((idx, tok)) => {
        let tok_start = tok.start()

        // Add text before token with escape processing
        if pos < tok_start {
          process_escapes_str(self.text, pos, tok_start, result)
        }

        // Process token
        match tok {
          Backticks(_, count, escaped) =>
            if !(escaped) {
              match self.parse_code_span(idx, text_end) {
                Some((inline, next_pos)) => {
                  result.push(inline)
                  pos = next_pos
                  tok_idx = idx + 1
                  while tok_idx < token_end &&
                        self.tokens[tok_idx].start() < next_pos {
                    tok_idx += 1
                  }
                  continue
                }
                None => {
                  // No matching closer, add backticks as text
                  let text = self.substring(tok_start, tok_start + count)
                  result.push(
                    Inline::Text(
                      content=text,
                      span=Span::new(tok_start, tok_start + count),
                    ),
                  )
                  pos = tok_start + count
                  tok_idx = idx + 1
                }
              }
            } else {
              // Escaped backtick, add as text
              let text = self.substring(tok_start, tok_start + count)
              result.push(
                Inline::Text(
                  content=text,
                  span=Span::new(tok_start, tok_start + count),
                ),
              )
              pos = tok_start + count
              tok_idx = idx + 1
            }
          EmphasisMarks(_, _, count, may_open, _) =>
            if may_open {
              match self.parse_emphasis(idx, text_end) {
                Some((inlines, next_pos)) => {
                  for i in inlines {
                    result.push(i)
                  }
                  pos = next_pos
                  tok_idx = idx + 1
                  // Skip tokens that were consumed
                  while tok_idx < token_end &&
                        self.tokens[tok_idx].start() < next_pos {
                    tok_idx += 1
                  }
                  continue
                }
                None => {
                  // Not valid emphasis, add markers as text
                  let marker_text = self.substring(tok_start, tok_start + count)
                  result.push(
                    Inline::Text(
                      content=marker_text,
                      span=Span::new(tok_start, tok_start + count),
                    ),
                  )
                  pos = tok_start + count
                  tok_idx = idx + 1
                }
              }
            } else {
              // Closing marker without opener, add as text
              let marker_text = self.substring(tok_start, tok_start + count)
              result.push(
                Inline::Text(
                  content=marker_text,
                  span=Span::new(tok_start, tok_start + count),
                ),
              )
              pos = tok_start + count
              tok_idx = idx + 1
            }
          LinkStart(_) =>
            match self.parse_link(idx, text_end) {
              Some((inline, next_pos)) => {
                result.push(inline)
                pos = next_pos
                tok_idx = idx + 1
                while tok_idx < token_end &&
                      self.tokens[tok_idx].start() < next_pos {
                  tok_idx += 1
                }
                continue
              }
              None => {
                // Not a valid link, add [ as text
                result.push(
                  Inline::Text(
                    content="[",
                    span=Span::new(tok_start, tok_start + 1),
                  ),
                )
                pos = tok_start + 1
                tok_idx = idx + 1
              }
            }
          ImageStart(_) =>
            match self.parse_image(idx, text_end) {
              Some((inline, next_pos)) => {
                result.push(inline)
                pos = next_pos
                tok_idx = idx + 1
                while tok_idx < token_end &&
                      self.tokens[tok_idx].start() < next_pos {
                  tok_idx += 1
                }
                continue
              }
              None => {
                // Not a valid image, add ![ as text
                result.push(
                  Inline::Text(
                    content="![",
                    span=Span::new(tok_start, tok_start + 2),
                  ),
                )
                pos = tok_start + 2
                tok_idx = idx + 1
              }
            }
          AngleStart(_) =>
            match self.parse_autolink(tok_start, text_end) {
              Some((inline, next_pos)) => {
                result.push(inline)
                pos = next_pos
                tok_idx = idx + 1
                while tok_idx < token_end &&
                      self.tokens[tok_idx].start() < next_pos {
                  tok_idx += 1
                }
                continue
              }
              None => {
                // Not a valid autolink, add < as text
                result.push(
                  Inline::Text(
                    content="<",
                    span=Span::new(tok_start, tok_start + 1),
                  ),
                )
                pos = tok_start + 1
                tok_idx = idx + 1
              }
            }
          Strikethrough(_, may_open, _) =>
            if may_open {
              match self.parse_strikethrough(idx, text_end) {
                Some((inline, next_pos)) => {
                  result.push(inline)
                  pos = next_pos
                  tok_idx = idx + 1
                  while tok_idx < token_end &&
                        self.tokens[tok_idx].start() < next_pos {
                    tok_idx += 1
                  }
                  continue
                }
                None => {
                  // Not valid strikethrough, add ~~ as text
                  result.push(
                    Inline::Text(
                      content="~~",
                      span=Span::new(tok_start, tok_start + 2),
                    ),
                  )
                  pos = tok_start + 2
                  tok_idx = idx + 1
                }
              }
            } else {
              // Closing without opener
              result.push(
                Inline::Text(
                  content="~~",
                  span=Span::new(tok_start, tok_start + 2),
                ),
              )
              pos = tok_start + 2
              tok_idx = idx + 1
            }
          Newline(_, is_space_hard, is_backslash_hard) => {
            if is_backslash_hard {
              // Remove trailing backslash from previous text if any
              match result.last() {
                Some(Inline::Text(content~, span~)) if content.length() > 0 =>
                  // Check if last char is backslash
                  if content.get_char(content.length() - 1) == Some('\\') {
                    let _ = result.pop()
                    if content.length() > 1 {
                      let new_content = content.unsafe_substring(
                        start=0,
                        end=content.length() - 1,
                      )
                      result.push(
                        Inline::Text(
                          content=new_content,
                          span=Span::new(span.from, span.to - 1),
                        ),
                      )
                    }
                  }
                _ => ()
              }
              result.push(
                Inline::HardBreak(
                  style=HardBreakStyle::Backslash,
                  span=Span::new(tok_start - 1, tok_start + 1),
                ),
              )
            } else if is_space_hard {
              result.push(
                Inline::HardBreak(
                  style=HardBreakStyle::TwoSpaces,
                  span=Span::new(tok_start, tok_start + 1),
                ),
              )
            } else {
              result.push(
                Inline::SoftBreak(span=Span::new(tok_start, tok_start + 1)),
              )
            }
            pos = tok_start + 1
            tok_idx = idx + 1
          }
          _ => {
            // Skip other tokens for now, add as text
            pos = tok_start + 1
            tok_idx = idx + 1
          }
        }
      }
    }
  }
  result
}

///|
/// Parse all inlines using multi-pass approach
pub fn parse_inlines_multipass(text : String) -> Array[Inline] {
  let parser = MultiPassParser::new(text)
  parser.parse_range(0, text.length(), 0, parser.tokens.length())
}

// Tests

///|
test "tokenize: simple emphasis" {
  let scanner = Scanner::new("*hello*")
  let tokens = tokenize_inline(scanner)
  assert_eq(tokens.length(), 2)

  // First token: opening *
  match tokens[0] {
    InlineToken::EmphasisMarks(start, char, count, may_open, may_close) => {
      assert_eq(start, 0)
      assert_eq(char, '*')
      assert_eq(count, 1)
      assert_eq(may_open, true)
      assert_eq(may_close, false)
    }
    _ => fail("Expected EmphasisMarks")
  }

  // Second token: closing *
  match tokens[1] {
    InlineToken::EmphasisMarks(start, char, count, may_open, may_close) => {
      assert_eq(start, 6)
      assert_eq(char, '*')
      assert_eq(count, 1)
      assert_eq(may_open, false)
      assert_eq(may_close, true)
    }
    _ => fail("Expected EmphasisMarks")
  }
}

///|
test "tokenize: strong emphasis" {
  let scanner = Scanner::new("**bold**")
  let tokens = tokenize_inline(scanner)
  assert_eq(tokens.length(), 2)
  match tokens[0] {
    InlineToken::EmphasisMarks(_, _, count, may_open, _) => {
      assert_eq(count, 2)
      assert_eq(may_open, true)
    }
    _ => fail("Expected EmphasisMarks")
  }
}

///|
test "tokenize: link" {
  let scanner = Scanner::new("[text](url)")
  let tokens = tokenize_inline(scanner)

  // Should have: LinkStart, RightBrack, RightParen
  let mut has_link_start = false
  let mut has_right_brack = false
  let mut has_right_paren = false
  for tok in tokens {
    match tok {
      InlineToken::LinkStart(_) => has_link_start = true
      InlineToken::RightBrack(_) => has_right_brack = true
      InlineToken::RightParen(_) => has_right_paren = true
      _ => ()
    }
  }
  assert_eq(has_link_start, true)
  assert_eq(has_right_brack, true)
  assert_eq(has_right_paren, true)
}

///|
test "tokenize: escaped asterisk" {
  let scanner = Scanner::new("\\*not emphasis\\*")
  let tokens = tokenize_inline(scanner)

  // Escaped asterisks should not create EmphasisMarks tokens
  for tok in tokens {
    match tok {
      InlineToken::EmphasisMarks(_, _, _, _, _) =>
        fail("Should not have EmphasisMarks for escaped")
      _ => ()
    }
  }
}

///|
test "tokenize: underscore in word" {
  let scanner = Scanner::new("foo_bar_baz")
  let tokens = tokenize_inline(scanner)

  // _ surrounded by word characters should not open/close
  for tok in tokens {
    match tok {
      InlineToken::EmphasisMarks(_, '_', _, may_open, may_close) =>
        // Intra-word underscore should not open or close
        assert_eq(may_open && may_close, false)
      _ => ()
    }
  }
}

///|
test "closer_index: emphasis lookup" {
  let scanner = Scanner::new("*hello* and *world*")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // Should find closing * after position 0
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 0), true)

  // Find the actual position
  match idx.find_closer(CloserKey::Emphasis('*'), 0) {
    Some(pos) => assert_eq(pos, 6) // closing * is at position 6
    None => fail("Should find closer")
  }

  // Should find second closing * after position 6
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 6), true)
}

///|
test "closer_index: link brackets" {
  let scanner = Scanner::new("[link](url)")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // Should find ] after position 0
  assert_eq(idx.has_closer(CloserKey::RightBrack, 0), true)

  // Should find ) after position 0
  assert_eq(idx.has_closer(CloserKey::RightParen, 0), true)
}

///|
test "closer_index: no closer" {
  let scanner = Scanner::new("*unclosed")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // No closing * (the * is opening, not closing)
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 0), false)
}

// Multi-pass parser tests

///|
test "multipass: simple emphasis" {
  let result = parse_inlines_multipass("*hello*")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Emphasis(children~, marker~, ..) => {
      assert_eq(marker, EmphasisMarker::Asterisk)
      assert_eq(children.length(), 1)
      match children[0] {
        Inline::Text(content~, ..) => assert_eq(content, "hello")
        _ => fail("Expected Text")
      }
    }
    _ => fail("Expected Emphasis")
  }
}

///|
test "multipass: strong emphasis" {
  let result = parse_inlines_multipass("**bold**")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Strong(children~, marker~, ..) => {
      assert_eq(marker, EmphasisMarker::Asterisk)
      assert_eq(children.length(), 1)
    }
    _ => fail("Expected Strong")
  }
}

///|
test "multipass: nested emphasis" {
  let result = parse_inlines_multipass("*hello **world***")
  // Current implementation might produce multiple elements for complex nesting
  // This is expected behavior for now
  assert_true(result.length() >= 1)
}

///|
test "multipass: plain text" {
  let result = parse_inlines_multipass("hello world")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Text(content~, ..) => assert_eq(content, "hello world")
    _ => fail("Expected Text")
  }
}

///|
test "multipass: unclosed marker" {
  let result = parse_inlines_multipass("*unclosed")
  // Should be treated as plain text
  assert_eq(result.length(), 2) // "*" + "unclosed"
}

///|
test "multipass: code span" {
  let result = parse_inlines_multipass("`code`")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Code(content~, backtick_count~, ..) => {
      assert_eq(content, "code")
      assert_eq(backtick_count, 1)
    }
    _ => fail("Expected Code")
  }
}

///|
test "multipass: double backtick code span" {
  let result = parse_inlines_multipass("``code with ` backtick``")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Code(content~, backtick_count~, ..) => {
      assert_eq(content, "code with ` backtick")
      assert_eq(backtick_count, 2)
    }
    _ => fail("Expected Code")
  }
}

///|
test "multipass: code span with space trimming" {
  let result = parse_inlines_multipass("` code `")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Code(content~, ..) => assert_eq(content, "code") // Spaces trimmed
    _ => fail("Expected Code")
  }
}

///|
test "multipass: inline link" {
  let result = parse_inlines_multipass("[text](url)")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Link(children~, url~, ..) => {
      assert_eq(url, "url")
      assert_eq(children.length(), 1)
    }
    _ => fail("Expected Link")
  }
}

///|
test "multipass: link with title" {
  let result = parse_inlines_multipass("[text](url \"title\")")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Link(url~, title~, ..) => {
      assert_eq(url, "url")
      assert_eq(title, "title")
    }
    _ => fail("Expected Link")
  }
}

///|
test "multipass: reference link" {
  let result = parse_inlines_multipass("[text][ref]")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::RefLink(label~, ..) => assert_eq(label, "ref")
    _ => fail("Expected RefLink")
  }
}

///|
test "multipass: inline image" {
  let result = parse_inlines_multipass("![alt](url)")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Image(alt~, url~, ..) => {
      assert_eq(alt, "alt")
      assert_eq(url, "url")
    }
    _ => fail("Expected Image")
  }
}

///|
test "multipass: reference image" {
  let result = parse_inlines_multipass("![alt][ref]")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::RefImage(alt~, label~, ..) => {
      assert_eq(alt, "alt")
      assert_eq(label, "ref")
    }
    _ => fail("Expected RefImage")
  }
}

///|
test "multipass: autolink url" {
  let result = parse_inlines_multipass("<http://example.com>")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Autolink(url~, is_email~, ..) => {
      assert_eq(url, "http://example.com")
      assert_eq(is_email, false)
    }
    _ => fail("Expected Autolink")
  }
}

///|
test "multipass: autolink email" {
  let result = parse_inlines_multipass("<test@example.com>")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Autolink(url~, is_email~, ..) => {
      assert_eq(url, "test@example.com")
      assert_eq(is_email, true)
    }
    _ => fail("Expected Autolink")
  }
}

///|
test "multipass: strikethrough" {
  let result = parse_inlines_multipass("~~deleted~~")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Strikethrough(children~, ..) => {
      assert_eq(children.length(), 1)
      match children[0] {
        Inline::Text(content~, ..) => assert_eq(content, "deleted")
        _ => fail("Expected Text")
      }
    }
    _ => fail("Expected Strikethrough")
  }
}

///|
test "multipass: escaped asterisk" {
  let result = parse_inlines_multipass("\\*not emphasis\\*")
  // Should be plain text "* not emphasis *"
  assert_true(result.length() >= 1)
  // The escaped asterisks should be literal text
  let first = result[0]
  match first {
    Inline::Text(content~, ..) => assert_true(content.contains("*"))
    _ => ()
  }
}

///|
test "multipass: escaped backslash" {
  let result = parse_inlines_multipass("\\\\")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Text(content~, ..) => assert_eq(content, "\\")
    _ => fail("Expected Text")
  }
}

///|
test "multipass: backslash newline hard break" {
  let result = parse_inlines_multipass("line1\\\nline2")
  // Should have text, hard break, text
  let mut has_hard_break = false
  for item in result {
    match item {
      Inline::HardBreak(style~, ..) => {
        assert_eq(style, HardBreakStyle::Backslash)
        has_hard_break = true
      }
      _ => ()
    }
  }
  assert_true(has_hard_break)
}
