///| Delimiter Stack Algorithm for strict CommonMark emphasis handling
///| (split from inline_parser.mbt).

///|
/// Delimiter entry for the stack algorithm
priv struct Delimiter {
  pos : Int // Position in text
  marker : Char // '*' or '_'
  length : Int // Number of consecutive markers
  mut remaining : Int // Remaining markers not yet matched
  can_open : Bool // Can this be an opener?
  can_close : Bool // Can this be a closer?
  mut active : Bool // Is this delimiter still active?
}

///|
/// Parse inlines using delimiter stack algorithm (CommonMark spec)
fn parse_inlines_with_delimiter_stack(
  text : String,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  let chars : Array[Char] = text.to_array()
  let len = chars.length()

  // Phase 1: Collect all delimiters
  let delimiters : Array[Delimiter] = []
  let mut i = 0
  while i < len {
    let c = chars[i]
    if c == '*' || c == '_' {
      // Count consecutive markers
      let start = i
      let marker = c
      let mut count = 0
      while i < len && chars[i] == marker {
        count += 1
        i += 1
      }

      // Determine flanking status (CommonMark rules)
      let before = if start > 0 { Some(chars[start - 1]) } else { None }
      let after = if i < len { Some(chars[i]) } else { None }
      let before_is_whitespace = match before {
        None => true
        Some(ch) => is_unicode_whitespace(ch)
      }
      let before_is_punctuation = match before {
        None => false
        Some(ch) => is_unicode_punctuation(ch)
      }
      let after_is_whitespace = match after {
        None => true
        Some(ch) => is_unicode_whitespace(ch)
      }
      let after_is_punctuation = match after {
        None => false
        Some(ch) => is_unicode_punctuation(ch)
      }

      // Left-flanking: not followed by whitespace, and either
      // (a) not followed by punctuation, or (b) preceded by whitespace or punctuation
      let left_flanking = !after_is_whitespace &&
        (!after_is_punctuation || before_is_whitespace || before_is_punctuation)

      // Right-flanking: not preceded by whitespace, and either
      // (a) not preceded by punctuation, or (b) followed by whitespace or punctuation
      let right_flanking = !before_is_whitespace &&
        (!before_is_punctuation || after_is_whitespace || after_is_punctuation)

      // For underscore, additional rules apply
      let (can_open, can_close) = if marker == '_' {
        // _ can open if left-flanking and (not right-flanking or preceded by punctuation)
        // _ can close if right-flanking and (not left-flanking or followed by punctuation)
        (
          left_flanking && (!right_flanking || before_is_punctuation),
          right_flanking && (!left_flanking || after_is_punctuation),
        )
      } else {
        // * can open if left-flanking
        // * can close if right-flanking
        (left_flanking, right_flanking)
      }
      if can_open || can_close {
        delimiters.push(Delimiter::{
          pos: start,
          marker,
          length: count,
          remaining: count,
          can_open,
          can_close,
          active: true,
        })
      }
    } else {
      i += 1
    }
  }

  // Phase 2: Process delimiters to find matching pairs
  // Result: list of (opener_pos, closer_pos, marker, is_strong)
  let matches : Array[(Int, Int, Char, Bool)] = []

  // Process closers from left to right
  for closer_idx = 0
      closer_idx < delimiters.length()
      closer_idx = closer_idx + 1 {
    let closer = delimiters[closer_idx]
    if !closer.can_close || closer.remaining == 0 {
      continue
    }

    // Look back for a matching opener
    for opener_idx = closer_idx - 1
        opener_idx >= 0
        opener_idx = opener_idx - 1 {
      let opener = delimiters[opener_idx]
      if !opener.can_open || opener.remaining == 0 || !opener.active {
        continue
      }
      if opener.marker != closer.marker {
        continue
      }

      // Rule: if sum of lengths is multiple of 3 and both can_open and can_close,
      // then opener length and closer length must both not be multiples of 3
      // (This prevents *foo**bar* from matching incorrectly)
      if (opener.can_open && opener.can_close) ||
        (closer.can_open && closer.can_close) {
        if (opener.length + closer.length) % 3 == 0 {
          if opener.length % 3 != 0 || closer.length % 3 != 0 {
            continue
          }
        }
      }

      // Found a match! Determine if strong or emphasis
      let use_count = if opener.remaining >= 2 && closer.remaining >= 2 {
        2
      } else {
        1
      }
      let is_strong = use_count == 2

      // Calculate positions
      let opener_end = opener.pos + opener.length - opener.remaining + use_count
      let closer_start = closer.pos + (closer.length - closer.remaining)
      matches.push(
        (opener_end - use_count, closer_start, opener.marker, is_strong),
      )

      // Update remaining counts
      delimiters[opener_idx].remaining = opener.remaining - use_count
      delimiters[closer_idx].remaining = closer.remaining - use_count

      // Deactivate delimiters between opener and closer
      for j = opener_idx + 1; j < closer_idx; j = j + 1 {
        delimiters[j].active = false
      }

      // If more remaining in closer, continue matching
      if closer.remaining > 0 {
        // Reset closer_idx to re-process this closer
        // (Actually we need to decrement to counteract the loop increment)
        // But since we modified remaining, the loop will handle it
      }
      break
    }
  }

  // Phase 3: Build inline elements from matches
  // Sort matches by opener position (they should already be mostly sorted)

  // Build result by processing text segments (even if no emphasis matches)
  let result : Array[Inline] = []
  if matches.is_empty() {
    // No emphasis matches, but still need to process other inlines correctly
    let segment_inlines = parse_segment_simple(text, 0, wikilinks~)
    for inline in segment_inlines {
      result.push(inline)
    }
  } else {
    build_inlines_from_matches(text, chars, matches, result, wikilinks~)
  }
  result
}

///|
/// Build inline elements from delimiter matches
fn build_inlines_from_matches(
  text : String,
  chars : Array[Char],
  matches : Array[(Int, Int, Char, Bool)],
  result : Array[Inline],
  wikilinks? : Bool = false,
) -> Unit {
  // Sort matches by opener position
  let sorted = matches.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })

  // Build nested structure
  let len = chars.length()
  build_inlines_recursive(
    text,
    chars,
    0,
    len,
    sorted,
    0,
    sorted.length(),
    result,
    wikilinks~,
  )
}

///|
/// Recursively build inline elements
fn build_inlines_recursive(
  text : String,
  chars : Array[Char],
  start : Int,
  end : Int,
  matches : Array[(Int, Int, Char, Bool)],
  match_start : Int,
  match_end : Int,
  result : Array[Inline],
  wikilinks? : Bool = false,
) -> Unit {
  let mut pos = start
  for i = match_start; i < match_end; i = i + 1 {
    let (opener_pos, closer_pos, marker, is_strong) = matches[i]

    // Skip if outside our range or already processed
    if opener_pos < start || closer_pos > end || opener_pos < pos {
      continue
    }
    let marker_len = if is_strong { 2 } else { 1 }

    // Add text before this emphasis
    if opener_pos > pos {
      let segment = text.unsafe_substring(start=pos, end=opener_pos)
      // Parse segment for other inline elements (code, links, etc.)
      let segment_inlines = parse_segment_simple(segment, pos, wikilinks~)
      for inline in segment_inlines {
        result.push(inline)
      }
    }

    // Build children for this emphasis
    let children : Array[Inline] = []
    let content_start = opener_pos + marker_len
    let content_end = closer_pos

    // Find nested matches within this emphasis
    let nested_start = i + 1
    let mut nested_end = i + 1
    while nested_end < match_end {
      let (np, nc, _, _) = matches[nested_end]
      if np >= content_start && nc <= content_end {
        nested_end += 1
      } else {
        break
      }
    }
    if nested_start < nested_end {
      // Has nested emphasis
      build_inlines_recursive(
        text,
        chars,
        content_start,
        content_end,
        matches,
        nested_start,
        nested_end,
        children,
        wikilinks~,
      )
      // Note: nested matches will be skipped naturally by position check
    } else {
      // No nested emphasis, parse content simply
      let content = text.unsafe_substring(start=content_start, end=content_end)
      let content_inlines = parse_segment_simple(
        content,
        content_start,
        wikilinks~,
      )
      for inline in content_inlines {
        children.push(inline)
      }
    }

    // Create emphasis or strong node
    let em_marker = if marker == '*' {
      EmphasisMarker::Asterisk
    } else {
      EmphasisMarker::Underscore
    }
    let span = Span::new(opener_pos, closer_pos + marker_len)
    if is_strong {
      result.push(Inline::Strong(marker=em_marker, children~, span~))
    } else {
      result.push(Inline::Emphasis(marker=em_marker, children~, span~))
    }
    pos = closer_pos + marker_len
  }

  // Add remaining text
  if pos < end {
    let segment = text.unsafe_substring(start=pos, end~)
    let segment_inlines = parse_segment_simple(segment, pos, wikilinks~)
    for inline in segment_inlines {
      result.push(inline)
    }
  }
}

///|
/// Parse a text segment for non-emphasis inlines (code spans, links, etc.)
fn parse_segment_simple(
  text : String,
  offset : Int,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  // For now, just return as text. Full implementation would parse
  // code spans, links, etc. here.
  let scanner = Scanner::new(text)
  let result : Array[Inline] = []
  let text_buf = StringBuilder::new()
  let mut text_start = 0
  while !scanner.is_eof() {
    let pos = scanner.pos
    match scanner.peek() {
      Some('`') => {
        // Try to parse code span
        let backtick_count = scanner.count_char('`')
        scanner.advance(backtick_count)

        // Find closing backticks
        let content_buf = StringBuilder::new()
        let mut found_closing = false
        while !scanner.is_eof() {
          let closing_count = scanner.count_char('`')
          if closing_count == backtick_count {
            found_closing = true
            let content = content_buf.to_string()
            scanner.advance(closing_count)

            // Flush text buffer
            if !text_buf.is_empty() {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }

            // Trim single leading/trailing space if present
            let trimmed = if content.length() >= 2 {
              let chars = content.to_array()
              if chars[0] == ' ' &&
                chars[chars.length() - 1] == ' ' &&
                !is_all_spaces(content) {
                content.unsafe_substring(start=1, end=content.length() - 1)
              } else {
                content
              }
            } else {
              content
            }
            result.push(
              Inline::Code(
                content=trimmed,
                backtick_count~,
                span=Span::new(offset + pos, offset + scanner.pos),
              ),
            )
            text_start = scanner.pos
            break
          } else if closing_count > 0 {
            for j = 0; j < closing_count; j = j + 1 {
              content_buf.write_char('`')
            }
            scanner.advance(closing_count)
          } else {
            match scanner.consume() {
              Some(c) => content_buf.write_char(c)
              None => break
            }
          }
        }
        if !found_closing {
          // No closing backticks, include opening backticks in text
          for j = 0; j < backtick_count; j = j + 1 {
            text_buf.write_char('`')
          }
          // Content was consumed, add it to text
          text_buf.write_string(content_buf.to_string())
        }
      }
      Some('[') => {
        // Try to parse wikilink before regular markdown links.
        let inline_parser = InlineParser::new(scanner, wikilinks~)
        let inline = if wikilinks && char_is(scanner.peek_at(1), '[') {
          match inline_parser.try_parse_wikilink(pos) {
            Some(wikilink) => Some(wikilink)
            None => inline_parser.try_parse_link(pos)
          }
        } else {
          inline_parser.try_parse_link(pos)
        }
        match inline {
          Some(parsed) => {
            // Flush text buffer
            if !text_buf.is_empty() {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }
            result.push(parsed)
            text_start = scanner.pos
          }
          None => {
            text_buf.write_char('[')
            scanner.advance(1)
          }
        }
      }
      Some('!') =>
        // Try to parse image
        if char_is(scanner.peek_at(1), '[') {
          let img_parser = InlineParser::new(scanner, wikilinks~)
          match img_parser.try_parse_image(pos) {
            Some(img) => {
              // Flush text buffer
              if !text_buf.is_empty() {
                result.push(
                  Inline::Text(
                    content=text_buf.to_string(),
                    span=Span::new(offset + text_start, offset + pos),
                  ),
                )
                text_buf.reset()
              }
              result.push(img)
              text_start = scanner.pos
            }
            None => {
              text_buf.write_char('!')
              scanner.advance(1)
            }
          }
        } else {
          text_buf.write_char('!')
          scanner.advance(1)
        }
      Some('<') => {
        // Try to parse raw inline HTML before autolink.
        let html_parser = InlineParser::new(scanner, wikilinks~)
        let inline = match html_parser.try_parse_html_comment(pos) {
          Some(comment) => Some(comment)
          None => {
            let auto_parser = InlineParser::new(scanner, wikilinks~)
            auto_parser.try_parse_autolink(pos)
          }
        }
        match inline {
          Some(parsed) => {
            // Flush text buffer
            if !text_buf.is_empty() {
              result.push(
                Inline::Text(
                  content=text_buf.to_string(),
                  span=Span::new(offset + text_start, offset + pos),
                ),
              )
              text_buf.reset()
            }
            result.push(parsed)
            text_start = scanner.pos
          }
          None => {
            text_buf.write_char('<')
            scanner.advance(1)
          }
        }
      }
      Some('\n') => {
        // Check for hard break (2+ trailing spaces before newline)
        let content = text_buf.to_string()
        let trimmed = content.trim_end(chars=" ").to_owned()
        let trailing_spaces = content.length() - trimmed.length()
        let is_hard_break = trailing_spaces >= 2
        if !trimmed.is_empty() {
          result.push(
            Inline::Text(
              content=trimmed,
              span=Span::new(
                offset + text_start,
                offset + pos - trailing_spaces,
              ),
            ),
          )
        }
        text_buf.reset()
        scanner.advance(1)
        // Skip leading spaces after newline
        while char_is(scanner.peek(), ' ') {
          scanner.advance(1)
        }
        if is_hard_break {
          result.push(
            Inline::HardBreak(
              style=HardBreakStyle::TwoSpaces,
              span=Span::new(
                offset + pos - trailing_spaces,
                offset + scanner.pos,
              ),
            ),
          )
        } else {
          result.push(
            Inline::SoftBreak(
              span=Span::new(offset + pos, offset + scanner.pos),
            ),
          )
        }
        text_start = scanner.pos
      }
      Some(c) => {
        text_buf.write_char(c)
        scanner.advance(1)
      }
      None => break
    }
  }

  // Flush remaining text
  if !text_buf.is_empty() {
    result.push(
      Inline::Text(
        content=text_buf.to_string(),
        span=Span::new(offset + text_start, offset + scanner.pos),
      ),
    )
  }
  result
}
