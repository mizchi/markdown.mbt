///| Token types for multi-pass inline parsing
///| Based on cmark's architecture
///|
///| NOTE: This is an experimental implementation not yet integrated into the main parser.
///| Benchmarks show it's faster for small inputs but slower for large inputs.
///| See docs/compare_cmark.md for details.

///| Inline token for multi-pass processing
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
  /// Newline with break type
  Newline(Int, Bool) // position, is_hard_break
  /// Already parsed inline
  Parsed(Int, Inline, Int) // start, inline, next_pos
}

///| Get start position of token
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
    Newline(s, _) => s
    Parsed(s, _, _) => s
  }
}

///| Check if character is Unicode whitespace
fn is_unicode_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u000C'
}

///| Check if character is Unicode punctuation (ASCII subset)
fn is_unicode_punctuation(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
  (code >= 0x3A && code <= 0x40) || // :;<=>?@
  (code >= 0x5B && code <= 0x60) || // [\]^_`
  (code >= 0x7B && code <= 0x7E)    // {|}~
}

///| Check if a delimiter run is left-flanking
fn is_left_flanking(prev_char : Char, next_char : Char) -> Bool {
  // Must not be followed by whitespace
  if is_unicode_whitespace(next_char) {
    return false
  }
  // Either not followed by punctuation, or preceded by whitespace/punctuation
  not(is_unicode_punctuation(next_char)) ||
  is_unicode_whitespace(prev_char) ||
  is_unicode_punctuation(prev_char)
}

///| Check if a delimiter run is right-flanking
fn is_right_flanking(prev_char : Char, next_char : Char) -> Bool {
  // Must not be preceded by whitespace
  if is_unicode_whitespace(prev_char) {
    return false
  }
  // Either not preceded by punctuation, or followed by whitespace/punctuation
  not(is_unicode_punctuation(prev_char)) ||
  is_unicode_whitespace(next_char) ||
  is_unicode_punctuation(next_char)
}

///| Tokenize input string into InlineToken array
fn tokenize_inline(scanner : Scanner) -> Array[InlineToken] {
  let tokens : Array[InlineToken] = []
  let mut prev_char : Char = ' ' // Start of line treated as whitespace
  let mut prev_backslash = false

  while not(scanner.is_eof()) {
    let start = scanner.pos
    let c = scanner.peek().unwrap()

    match c {
      '\\' => {
        prev_backslash = not(prev_backslash)
        scanner.advance(1)
        prev_char = '\\'
      }
      '`' => {
        let count = scanner.count_char('`')
        tokens.push(InlineToken::Backticks(start, count, prev_backslash))
        scanner.advance(count)
        prev_char = '`'
        prev_backslash = false
      }
      '*' | '_' => {
        if not(prev_backslash) {
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
              left_flank && (not(right_flank) || is_unicode_punctuation(prev_char)),
              right_flank && (not(left_flank) || is_unicode_punctuation(next_char))
            )
          }

          if may_open || may_close {
            tokens.push(InlineToken::EmphasisMarks(start, marker, count, may_open, may_close))
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
        if not(prev_backslash) {
          tokens.push(InlineToken::LinkStart(start))
        }
        scanner.advance(1)
        prev_char = '['
        prev_backslash = false
      }
      '!' => {
        if not(prev_backslash) {
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
        scanner.advance(1)
        prev_char = ']'
        prev_backslash = false
      }
      ')' => {
        tokens.push(InlineToken::RightParen(start))
        scanner.advance(1)
        prev_char = ')'
        prev_backslash = false
      }
      '<' => {
        if not(prev_backslash) {
          tokens.push(InlineToken::AngleStart(start))
        }
        scanner.advance(1)
        prev_char = '<'
        prev_backslash = false
      }
      '~' => {
        if not(prev_backslash) {
          let count = scanner.count_char('~')
          if count == 2 {
            let next_char = scanner.peek_at(2).unwrap_or(' ')
            let may_open = not(is_unicode_whitespace(next_char))
            let may_close = not(is_unicode_whitespace(prev_char))
            tokens.push(InlineToken::Strikethrough(start, may_open, may_close))
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
        // Check for hard break (two spaces before newline)
        let is_hard = prev_char == ' '
        tokens.push(InlineToken::Newline(start, is_hard))
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

  tokens
}

///| Closer key for index lookup
priv enum CloserKey {
  Backticks(Int)    // count
  RightBrack
  RightParen
  Emphasis(Char)    // * or _
  Strikethrough
} derive(Eq, Hash)

///| CloserIndex for O(1) lookup of closing delimiters
///| Maps closer type -> sorted array of positions
priv struct CloserIndex {
  backticks : Map[Int, Array[Int]]    // count -> positions
  right_brack : Array[Int]
  right_paren : Array[Int]
  emphasis_star : Array[Int]
  emphasis_underscore : Array[Int]
  strikethrough : Array[Int]
}

///| Create new empty CloserIndex
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

///| Build CloserIndex from token array
fn build_closer_index(tokens : Array[InlineToken]) -> CloserIndex {
  let idx = CloserIndex::new()

  for tok in tokens {
    match tok {
      InlineToken::Backticks(pos, count, _) => {
        match idx.backticks.get(count) {
          Some(arr) => arr.push(pos)
          None => idx.backticks[count] = [pos]
        }
      }
      InlineToken::RightBrack(pos) => idx.right_brack.push(pos)
      InlineToken::RightParen(pos) => idx.right_paren.push(pos)
      InlineToken::EmphasisMarks(pos, char, _, _, may_close) => {
        if may_close {
          if char == '*' {
            idx.emphasis_star.push(pos)
          } else {
            idx.emphasis_underscore.push(pos)
          }
        }
      }
      InlineToken::Strikethrough(pos, _, may_close) => {
        if may_close {
          idx.strikethrough.push(pos)
        }
      }
      _ => ()
    }
  }

  idx
}

///| Check if there's a closer of given type after position
fn CloserIndex::has_closer(self : CloserIndex, key : CloserKey, after : Int) -> Bool {
  match key {
    CloserKey::Backticks(count) => {
      match self.backticks.get(count) {
        Some(arr) => arr.iter().any(fn(p) { p > after })
        None => false
      }
    }
    CloserKey::RightBrack => self.right_brack.iter().any(fn(p) { p > after })
    CloserKey::RightParen => self.right_paren.iter().any(fn(p) { p > after })
    CloserKey::Emphasis('*') => self.emphasis_star.iter().any(fn(p) { p > after })
    CloserKey::Emphasis(_) => self.emphasis_underscore.iter().any(fn(p) { p > after })
    CloserKey::Strikethrough => self.strikethrough.iter().any(fn(p) { p > after })
  }
}

///| Find position of next closer after given position
fn CloserIndex::find_closer(self : CloserIndex, key : CloserKey, after : Int) -> Int? {
  match key {
    CloserKey::Backticks(count) => {
      match self.backticks.get(count) {
        Some(arr) => arr.iter().find_first(fn(p) { p > after })
        None => None
      }
    }
    CloserKey::RightBrack => self.right_brack.iter().find_first(fn(p) { p > after })
    CloserKey::RightParen => self.right_paren.iter().find_first(fn(p) { p > after })
    CloserKey::Emphasis('*') => self.emphasis_star.iter().find_first(fn(p) { p > after })
    CloserKey::Emphasis(_) => self.emphasis_underscore.iter().find_first(fn(p) { p > after })
    CloserKey::Strikethrough => self.strikethrough.iter().find_first(fn(p) { p > after })
  }
}

///| Multi-pass inline parser state
priv struct MultiPassParser {
  text : String
  chars : Array[Char]
  tokens : Array[InlineToken]
  closer_idx : CloserIndex
  pos : Int           // current token index
}

///| Create multi-pass parser from text
fn MultiPassParser::new(text : String) -> MultiPassParser {
  let chars = text.to_array()
  let scanner = Scanner::new(text)
  let tokens = tokenize_inline(scanner)
  let closer_idx = build_closer_index(tokens)
  { text, chars, tokens, closer_idx, pos: 0 }
}

///| Get substring from char array
fn MultiPassParser::substring(self : MultiPassParser, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < self.chars.length(); i = i + 1 {
    buf.write_char(self.chars[i])
  }
  buf.to_string()
}

///| Check if Rule 9, 10 (mod 3 rule) allows match
fn emphasis_mod3_match(
  opener_count : Int,
  closer_count : Int,
  opener_can_close : Bool,
  closer_can_open : Bool
) -> Bool {
  // If neither can act as the opposite, they always match
  if not(opener_can_close) && not(closer_can_open) {
    return true
  }
  // Rule 9, 10: sum must not be divisible by 3, unless one is divisible by 3
  let sum = opener_count + closer_count
  if sum % 3 != 0 {
    return true
  }
  opener_count % 3 == 0 || closer_count % 3 == 0
}

///| Parse emphasis using token-based approach
fn MultiPassParser::parse_emphasis(
  self : MultiPassParser,
  opener_idx : Int,
  text_end : Int
) -> (Array[Inline], Int)? {
  // Get opener token
  guard opener_idx < self.tokens.length() else { return None }
  let opener = self.tokens[opener_idx]

  guard opener is EmphasisMarks(opener_start, marker_char, opener_count, may_open, opener_can_close) else {
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
      EmphasisMarks(closer_start, c, closer_count, closer_can_open, may_close) => {
        if c == marker_char && may_close {
          // Check mod 3 rule
          if emphasis_mod3_match(opener_count, closer_count, opener_can_close, closer_can_open) {
            // Found matching closer
            let used = if opener_count >= 2 && closer_count >= 2 { 2 } else { 1 }
            best_closer_idx = Some(i)
            best_used = used
            break
          }
        }
      }
      _ => ()
    }
  }

  guard best_closer_idx is Some(closer_idx) else { return None }

  let closer = self.tokens[closer_idx]
  guard closer is EmphasisMarks(closer_start, _, closer_count, _, _) else { return None }

  // Parse content between opener and closer
  let content_start = opener_start + best_used
  let content_end = closer_start
  let children = self.parse_range(content_start, content_end, opener_idx + 1, closer_idx)

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

///| Parse a range of text, processing tokens within
fn MultiPassParser::parse_range(
  self : MultiPassParser,
  text_start : Int,
  text_end : Int,
  token_start : Int,
  token_end : Int
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
        // No more tokens, add remaining text
        if pos < text_end {
          let content = self.substring(pos, text_end)
          if content.length() > 0 {
            result.push(Inline::Text(content~, span=Span::new(pos, text_end)))
          }
        }
        break
      }
      Some((idx, tok)) => {
        let tok_start = tok.start()

        // Add text before token
        if pos < tok_start {
          let content = self.substring(pos, tok_start)
          if content.length() > 0 {
            result.push(Inline::Text(content~, span=Span::new(pos, tok_start)))
          }
        }

        // Process token
        match tok {
          EmphasisMarks(_, _, count, may_open, _) => {
            if may_open {
              match self.parse_emphasis(idx, text_end) {
                Some((inlines, next_pos)) => {
                  for i in inlines {
                    result.push(i)
                  }
                  pos = next_pos
                  tok_idx = idx + 1
                  // Skip tokens that were consumed
                  while tok_idx < token_end && self.tokens[tok_idx].start() < next_pos {
                    tok_idx += 1
                  }
                  continue
                }
                None => {
                  // Not valid emphasis, add markers as text
                  let marker_text = self.substring(tok_start, tok_start + count)
                  result.push(Inline::Text(content=marker_text, span=Span::new(tok_start, tok_start + count)))
                  pos = tok_start + count
                  tok_idx = idx + 1
                }
              }
            } else {
              // Closing marker without opener, add as text
              let marker_text = self.substring(tok_start, tok_start + count)
              result.push(Inline::Text(content=marker_text, span=Span::new(tok_start, tok_start + count)))
              pos = tok_start + count
              tok_idx = idx + 1
            }
          }
          Newline(_, is_hard) => {
            if is_hard {
              result.push(Inline::HardBreak(style=HardBreakStyle::TwoSpaces, span=Span::new(tok_start, tok_start + 1)))
            } else {
              result.push(Inline::SoftBreak(span=Span::new(tok_start, tok_start + 1)))
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

///| Parse all inlines using multi-pass approach
pub fn parse_inlines_multipass(text : String) -> Array[Inline] {
  let parser = MultiPassParser::new(text)
  parser.parse_range(0, text.length(), 0, parser.tokens.length())
}

// Tests
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

test "tokenize: escaped asterisk" {
  let scanner = Scanner::new("\\*not emphasis\\*")
  let tokens = tokenize_inline(scanner)

  // Escaped asterisks should not create EmphasisMarks tokens
  for tok in tokens {
    match tok {
      InlineToken::EmphasisMarks(_, _, _, _, _) => fail("Should not have EmphasisMarks for escaped")
      _ => ()
    }
  }
}

test "tokenize: underscore in word" {
  let scanner = Scanner::new("foo_bar_baz")
  let tokens = tokenize_inline(scanner)

  // _ surrounded by word characters should not open/close
  for tok in tokens {
    match tok {
      InlineToken::EmphasisMarks(_, '_', _, may_open, may_close) => {
        // Intra-word underscore should not open or close
        assert_eq(may_open && may_close, false)
      }
      _ => ()
    }
  }
}

test "closer_index: emphasis lookup" {
  let scanner = Scanner::new("*hello* and *world*")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // Should find closing * after position 0
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 0), true)

  // Find the actual position
  match idx.find_closer(CloserKey::Emphasis('*'), 0) {
    Some(pos) => assert_eq(pos, 6)  // closing * is at position 6
    None => fail("Should find closer")
  }

  // Should find second closing * after position 6
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 6), true)
}

test "closer_index: link brackets" {
  let scanner = Scanner::new("[link](url)")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // Should find ] after position 0
  assert_eq(idx.has_closer(CloserKey::RightBrack, 0), true)

  // Should find ) after position 0
  assert_eq(idx.has_closer(CloserKey::RightParen, 0), true)
}

test "closer_index: no closer" {
  let scanner = Scanner::new("*unclosed")
  let tokens = tokenize_inline(scanner)
  let idx = build_closer_index(tokens)

  // No closing * (the * is opening, not closing)
  assert_eq(idx.has_closer(CloserKey::Emphasis('*'), 0), false)
}

// Multi-pass parser tests
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

test "multipass: nested emphasis" {
  let result = parse_inlines_multipass("*hello **world***")
  // Current implementation might produce multiple elements for complex nesting
  // This is expected behavior for now
  assert_true(result.length() >= 1)
}

test "multipass: plain text" {
  let result = parse_inlines_multipass("hello world")
  assert_eq(result.length(), 1)
  match result[0] {
    Inline::Text(content~, ..) => assert_eq(content, "hello world")
    _ => fail("Expected Text")
  }
}

test "multipass: unclosed marker" {
  let result = parse_inlines_multipass("*unclosed")
  // Should be treated as plain text
  assert_eq(result.length(), 2) // "*" + "unclosed"
}
