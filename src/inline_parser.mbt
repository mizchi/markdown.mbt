///| Inline-level markdown parser.

///| Implements the delimiter-stack algorithm described in the CommonMark spec

///| appendix: one left-to-right pass emits literal text, code spans, autolinks,

///| raw HTML and line breaks while stacking `*`/`_`/`~` runs and `[`/`![`

///| openers; a second pass turns the stacked delimiters into emphasis, links

///| and images.

///|
/// A node in the inline list under construction.
///
/// A slot either holds a finished inline (`inline`) or an unresolved run of
/// emphasis delimiters, in which case `count` markers are still unused and the
/// slot renders as literal text if nothing ever claims them.
priv struct Slot {
  mut inline : Inline?
  /// Whether following literal text may be merged into this slot. Bracket
  /// openers say no, so that link content stays in slots of its own.
  mergeable : Bool
  ch : Char
  mut count : Int
  orig : Int
  can_open : Bool
  can_close : Bool
  start : Int
  mut prev : Int
  mut next : Int
}

///|
/// An unmatched `[` or `![` on the bracket stack.
priv struct Bracket {
  slot : Int // slot holding the literal "[" / "!["
  content_start : Int // source offset just after the bracket
  image : Bool
  mut active : Bool
  delim_bottom : Int // delimiter stack height when this bracket was pushed
}

///|
/// Working state for one inline-content string.
priv struct InlineCtx {
  text : String
  len : Int
  defs : Map[String, LinkDefinition]
  wikilinks : Bool
  slots : Array[Slot]
  mut head : Int
  mut tail : Int
  delims : Array[Int]
  brackets : Array[Bracket]
}

///|
fn InlineCtx::new(
  text : String,
  defs : Map[String, LinkDefinition],
  wikilinks : Bool,
) -> InlineCtx {
  {
    text,
    len: text.length(),
    defs,
    wikilinks,
    slots: [],
    head: -1,
    tail: -1,
    delims: [],
    brackets: [],
  }
}

// =============================================================================
// Slot list plumbing
// =============================================================================

///|
fn InlineCtx::append(self : InlineCtx, slot : Slot) -> Int {
  let idx = self.slots.length()
  slot.prev = self.tail
  slot.next = -1
  self.slots.push(slot)
  if self.tail >= 0 {
    self.slots[self.tail].next = idx
  } else {
    self.head = idx
  }
  self.tail = idx
  idx
}

///|
fn InlineCtx::insert_after(self : InlineCtx, at : Int, slot : Slot) -> Int {
  let idx = self.slots.length()
  let next = self.slots[at].next
  slot.prev = at
  slot.next = next
  self.slots.push(slot)
  self.slots[at].next = idx
  if next >= 0 {
    self.slots[next].prev = idx
  } else {
    self.tail = idx
  }
  idx
}

///|
fn InlineCtx::unlink(self : InlineCtx, idx : Int) -> Unit {
  let prev = self.slots[idx].prev
  let next = self.slots[idx].next
  if prev >= 0 {
    self.slots[prev].next = next
  } else {
    self.head = next
  }
  if next >= 0 {
    self.slots[next].prev = prev
  } else {
    self.tail = prev
  }
  self.slots[idx].prev = -1
  self.slots[idx].next = -1
}

///|
fn new_inline_slot(inline : Inline, start : Int) -> Slot {
  {
    inline: Some(inline),
    mergeable: true,
    ch: ' ',
    count: 0,
    orig: 0,
    can_open: false,
    can_close: false,
    start,
    prev: -1,
    next: -1,
  }
}

///|
fn InlineCtx::push_inline(
  self : InlineCtx,
  inline : Inline,
  start : Int,
) -> Int {
  self.append(new_inline_slot(inline, start))
}

///|
/// Append literal text, merging with a preceding text slot so that escapes and
/// entity references do not fragment the node list.
fn InlineCtx::push_text(
  self : InlineCtx,
  content : String,
  start : Int,
  end : Int,
) -> Unit {
  if content.is_empty() {
    return
  }
  if self.tail >= 0 && self.slots[self.tail].mergeable {
    match self.slots[self.tail].inline {
      Some(Inline::Text(content=prev, span=prev_span)) => {
        self.slots[self.tail].inline = Some(
          Inline::Text(
            content=prev + content,
            span=Span::new(prev_span.from, end),
          ),
        )
        return
      }
      _ => ()
    }
  }
  let _ = self.push_inline(
    Inline::Text(content~, span=Span::new(start, end)),
    start,
  )
}

///|
/// The inline a slot stands for; leftover delimiters become literal text.
fn InlineCtx::slot_inline(self : InlineCtx, idx : Int) -> Inline {
  let slot = self.slots[idx]
  match slot.inline {
    Some(v) => v
    None =>
      Inline::Text(
        content=String::make(slot.count, slot.ch),
        span=Span::new(slot.start, slot.start + slot.count),
      )
  }
}

///|
/// Collect slots `[from, to)` (following `next` links) into an inline array,
/// merging adjacent text nodes.
fn InlineCtx::materialize(
  self : InlineCtx,
  from : Int,
  to : Int,
) -> Array[Inline] {
  let result : Array[Inline] = []
  let mut i = from
  while i >= 0 && i != to {
    let inline = self.slot_inline(i)
    match (result.last(), inline) {
      (
        Some(Inline::Text(content=prev, span=prev_span)),
        Inline::Text(content~, span~),
      ) => {
        let _ = result.pop()
        result.push(
          Inline::Text(
            content=prev + content,
            span=Span::new(prev_span.from, span.to),
          ),
        )
      }
      _ => result.push(inline)
    }
    i = self.slots[i].next
  }
  result
}

// =============================================================================
// Entry points
// =============================================================================

///|
/// Parse inline content from text.
///
/// `strict` is accepted for backwards compatibility; the parser now always
/// follows the CommonMark algorithm.
pub fn parse_inlines(
  text : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> Array[Inline] {
  ignore(strict)
  parse_inlines_with_defs(text, Map([], capacity=0), wikilinks)
}

///|
/// Parse inline content with the document's link reference definitions in
/// scope, so `[foo]` style references can be resolved while parsing.
fn parse_inlines_with_defs(
  text : String,
  defs : Map[String, LinkDefinition],
  wikilinks : Bool,
) -> Array[Inline] {
  let ctx = InlineCtx::new(text, defs, wikilinks)
  ctx.scan()
  ctx.process_emphasis(0)
  ctx.materialize(ctx.head, -1)
}

// =============================================================================
// Main scan
// =============================================================================

///|
fn InlineCtx::scan(self : InlineCtx) -> Unit {
  let text = self.text
  let len = self.len
  let buf = StringBuilder()
  let mut run_start = 0
  let mut i = 0
  // Flush the pending literal run that ends just before `end`.
  fn flush(end : Int) -> Unit {
    if !buf.is_empty() {
      self.push_text(buf.to_string(), run_start, end)
      buf.reset()
    }
    run_start = end
  }

  while i < len {
    let c = text.unsafe_get(i)
    match c {
      '\n' => {
        // Trailing spaces decide between a hard and a soft line break.
        let mut sp = i
        while sp > 0 && text.unsafe_get(sp - 1) == ' ' {
          sp = sp - 1
        }
        let hard = i - sp >= 2
        trim_trailing_spaces(buf)
        flush(sp)
        let mut j = i + 1
        while j < len &&
              (text.unsafe_get(j) == ' ' || text.unsafe_get(j) == '\t') {
          j = j + 1
        }
        let span = Span::new(sp, j)
        if hard {
          let _ = self.push_inline(
            Inline::HardBreak(style=HardBreakStyle::TwoSpaces, span~),
            sp,
          )
        } else {
          let _ = self.push_inline(Inline::SoftBreak(span~), sp)
        }
        i = j
        run_start = j
      }
      '\\' =>
        if i + 1 < len && text.unsafe_get(i + 1) == '\n' {
          trim_trailing_spaces(buf)
          flush(i)
          let mut j = i + 2
          while j < len &&
                (text.unsafe_get(j) == ' ' || text.unsafe_get(j) == '\t') {
            j = j + 1
          }
          let _ = self.push_inline(
            Inline::HardBreak(
              style=HardBreakStyle::Backslash,
              span=Span::new(i, j),
            ),
            i,
          )
          i = j
          run_start = j
        } else if i + 1 < len &&
          is_punctuation(text.unsafe_get(i + 1).unsafe_to_char()) {
          buf.write_string(text.unsafe_substring(start=i + 1, end=i + 2))
          i = i + 2
        } else {
          buf.write_char('\\')
          i = i + 1
        }
      '&' =>
        match decode_entity(text, i) {
          Some((value, end)) => {
            buf.write_string(value)
            i = end
          }
          None => {
            buf.write_char('&')
            i = i + 1
          }
        }
      '`' =>
        match parse_code_span(text, i) {
          Some((content, backtick_count, end)) => {
            flush(i)
            let _ = self.push_inline(
              Inline::Code(content~, backtick_count~, span=Span::new(i, end)),
              i,
            )
            i = end
            run_start = end
          }
          None => {
            let n = count_run(text, i, '`')
            buf.write_string(text.unsafe_substring(start=i, end=i + n))
            i = i + n
          }
        }
      '<' =>
        match parse_autolink(text, i) {
          Some((url, is_email, end)) => {
            flush(i)
            let _ = self.push_inline(
              Inline::Autolink(url~, is_email~, span=Span::new(i, end)),
              i,
            )
            i = end
            run_start = end
          }
          None =>
            match parse_raw_html(text, i) {
              Some(end) => {
                flush(i)
                let _ = self.push_inline(
                  Inline::HtmlInline(
                    html=text.unsafe_substring(start=i, end~),
                    span=Span::new(i, end),
                  ),
                  i,
                )
                i = end
                run_start = end
              }
              None => {
                buf.write_char('<')
                i = i + 1
              }
            }
        }
      '*' | '_' => {
        flush(i)
        i = self.push_delimiter_run(i, c.unsafe_to_char())
        run_start = i
      }
      '~' => {
        let n = count_run(text, i, '~')
        if n == 2 {
          flush(i)
          i = self.push_delimiter_run(i, '~')
          run_start = i
        } else {
          buf.write_string(text.unsafe_substring(start=i, end=i + n))
          i = i + n
        }
      }
      '[' =>
        if self.wikilinks && i + 1 < len && text.unsafe_get(i + 1) == '[' {
          match parse_wikilink(text, i) {
            Some((inline, end)) => {
              flush(i)
              let _ = self.push_inline(inline, i)
              i = end
              run_start = end
            }
            None => {
              flush(i)
              self.open_bracket(i, false)
              i = i + 1
              run_start = i
            }
          }
        } else if i + 1 < len && text.unsafe_get(i + 1) == '^' {
          match parse_footnote_reference(text, i) {
            Some((inline, end)) => {
              flush(i)
              let _ = self.push_inline(inline, i)
              i = end
              run_start = end
            }
            None => {
              flush(i)
              self.open_bracket(i, false)
              i = i + 1
              run_start = i
            }
          }
        } else {
          flush(i)
          self.open_bracket(i, false)
          i = i + 1
          run_start = i
        }
      '!' =>
        if i + 1 < len && text.unsafe_get(i + 1) == '[' {
          flush(i)
          self.open_bracket(i, true)
          i = i + 2
          run_start = i
        } else {
          buf.write_char('!')
          i = i + 1
        }
      ']' => {
        flush(i)
        i = self.close_bracket(i)
        run_start = i
      }
      _ => {
        // Plain run up to the next character that could start markup.
        let start = i
        while i < len && !is_inline_marker_code_unit(text.unsafe_get(i)) {
          i = i + 1
        }
        if i == start {
          i = i + 1
        }
        buf.write_string(text.unsafe_substring(start~, end=i))
      }
    }
  }
  trim_trailing_spaces(buf)
  flush(len)
}

///|
fn trim_trailing_spaces(buf : StringBuilder) -> Unit {
  if buf.is_empty() {
    return
  }
  let s = buf.to_string()
  let mut end = s.length()
  while end > 0 &&
        (s.unsafe_get(end - 1) == ' ' || s.unsafe_get(end - 1) == '\t') {
    end = end - 1
  }
  if end == s.length() {
    return
  }
  buf.reset()
  if end > 0 {
    buf.write_string(s.unsafe_substring(start=0, end~))
  }
}

///|
fn is_inline_marker_code_unit(c : UInt16) -> Bool {
  match c {
    '\\' | '`' | '*' | '_' | '~' | '[' | ']' | '!' | '<' | '&' | '\n' => true
    _ => false
  }
}

///|
fn count_run(text : String, start : Int, ch : UInt16) -> Int {
  let len = text.length()
  let mut i = start
  while i < len && text.unsafe_get(i) == ch {
    i = i + 1
  }
  i - start
}

// =============================================================================
// Code spans
// =============================================================================

///|
/// Parse the code span opening at `start`, returning content, fence length and
/// the index just past the closing run.
fn parse_code_span(text : String, start : Int) -> (String, Int, Int)? {
  let len = text.length()
  let opener = count_run(text, start, '`')
  let mut i = start + opener
  while i < len {
    if text.unsafe_get(i) == '`' {
      let run = count_run(text, i, '`')
      if run == opener {
        // The CST keeps the source text; normalization happens at render time.
        return Some(
          (text.unsafe_substring(start=start + opener, end=i), opener, i + run),
        )
      }
      i = i + run
    } else {
      i = i + 1
    }
  }
  None
}

///|
/// One space is stripped from each end of a code span when it is padded on
/// both sides but is not all whitespace.
fn strip_code_span_padding(raw : String) -> String {
  let n = raw.length()
  if n < 2 {
    return raw
  }
  if !is_code_span_pad(raw.unsafe_get(0)) ||
    !is_code_span_pad(raw.unsafe_get(n - 1)) {
    return raw
  }
  for i = 0; i < n; i = i + 1 {
    if !is_code_span_pad(raw.unsafe_get(i)) {
      return raw.unsafe_substring(start=1, end=n - 1)
    }
  }
  raw
}

///|
fn is_code_span_pad(c : UInt16) -> Bool {
  c == ' ' || c == '\n' || c == '\r'
}

///|
/// The rendered form of a code span: line endings become spaces and the
/// padding is stripped.
fn normalize_code_span(raw : String) -> String {
  let stripped = strip_code_span_padding(raw)
  let len = stripped.length()
  let mut has_break = false
  for i = 0; i < len; i = i + 1 {
    let c = stripped.unsafe_get(i)
    if c == '\n' || c == '\r' {
      has_break = true
      break
    }
  }
  if !has_break {
    return stripped
  }
  let buf = StringBuilder()
  for i = 0; i < len; i = i + 1 {
    let c = stripped.unsafe_get(i)
    if c == '\n' || c == '\r' {
      buf.write_char(' ')
    } else {
      buf.write_string(stripped.unsafe_substring(start=i, end=i + 1))
    }
  }
  buf.to_string()
}

// =============================================================================
// Autolinks and raw HTML
// =============================================================================

///|
fn is_ascii_letter_unit(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_uri_scheme_char(c : UInt16) -> Bool {
  is_ascii_alnum_unit(c) || c == '+' || c == '.' || c == '-'
}

///|
/// `<scheme:...>` absolute URI autolinks and `<user@host>` email autolinks.
fn parse_autolink(text : String, start : Int) -> (String, Bool, Int)? {
  let len = text.length()
  guard start + 1 < len else { return None }
  let mut end = start + 1
  while end < len && text.unsafe_get(end) != '>' {
    let c = text.unsafe_get(end)
    if c == '<' || c == ' ' || c == '\n' || c == '\t' || c < 0x20 {
      return None
    }
    end = end + 1
  }
  guard end < len else { return None }
  let body = text.unsafe_substring(start=start + 1, end~)
  if is_absolute_uri(body) {
    return Some((body, false, end + 1))
  }
  if is_email_address(body) {
    return Some((body, true, end + 1))
  }
  None
}

///|
fn is_absolute_uri(s : String) -> Bool {
  let len = s.length()
  guard len > 0 && is_ascii_letter_unit(s.unsafe_get(0)) else { return false }
  let mut i = 1
  while i < len && is_uri_scheme_char(s.unsafe_get(i)) {
    i = i + 1
  }
  i >= 2 && i <= 32 && i < len && s.unsafe_get(i) == ':'
}

///|
fn is_email_address(s : String) -> Bool {
  let len = s.length()
  let mut i = 0
  let mut local_len = 0
  while i < len {
    let c = s.unsafe_get(i)
    if c == '@' {
      break
    }
    if !(is_ascii_alnum_unit(c) ||
      c == '.' ||
      c == '!' ||
      c == '#' ||
      c == '$' ||
      c == '%' ||
      c == '&' ||
      c == '\'' ||
      c == '*' ||
      c == '+' ||
      c == '/' ||
      c == '=' ||
      c == '?' ||
      c == '^' ||
      c == '_' ||
      c == '`' ||
      c == '{' ||
      c == '|' ||
      c == '}' ||
      c == '~' ||
      c == '-') {
      return false
    }
    local_len = local_len + 1
    i = i + 1
  }
  guard local_len > 0 && i < len && s.unsafe_get(i) == '@' else { return false }
  i = i + 1
  // One or more dot-separated labels of alphanumerics and hyphens.
  let mut labels = 0
  while i < len {
    let label_start = i
    guard is_ascii_alnum_unit(s.unsafe_get(i)) else { return false }
    while i < len &&
          (is_ascii_alnum_unit(s.unsafe_get(i)) || s.unsafe_get(i) == '-') {
      i = i + 1
    }
    if i - label_start > 63 || s.unsafe_get(i - 1) == '-' {
      return false
    }
    labels = labels + 1
    if i < len {
      guard s.unsafe_get(i) == '.' else { return false }
      i = i + 1
    }
  }
  labels > 0
}

///|
/// Raw inline HTML: open/closing tags, comments, processing instructions,
/// declarations and CDATA sections. Returns the index just past the construct.
fn parse_raw_html(text : String, start : Int) -> Int? {
  let len = text.length()
  guard start + 1 < len else { return None }
  let next = text.unsafe_get(start + 1)
  if next == '!' {
    guard start + 2 < len else { return None }
    let c2 = text.unsafe_get(start + 2)
    if c2 == '-' && start + 3 < len && text.unsafe_get(start + 3) == '-' {
      return parse_html_comment(text, start)
    }
    if c2 == '[' && matches_at(text, start + 2, "[CDATA[") {
      let mut i = start + 9
      while i + 2 < len {
        if text.unsafe_get(i) == ']' &&
          text.unsafe_get(i + 1) == ']' &&
          text.unsafe_get(i + 2) == '>' {
          return Some(i + 3)
        }
        i = i + 1
      }
      return None
    }
    if is_ascii_letter_unit(c2) {
      let mut i = start + 2
      while i < len && text.unsafe_get(i) != '>' {
        i = i + 1
      }
      return if i < len { Some(i + 1) } else { None }
    }
    return None
  }
  if next == '?' {
    let mut i = start + 2
    while i + 1 < len {
      if text.unsafe_get(i) == '?' && text.unsafe_get(i + 1) == '>' {
        return Some(i + 2)
      }
      i = i + 1
    }
    return None
  }
  if next == '/' {
    let mut i = start + 2
    guard i < len && is_ascii_letter_unit(text.unsafe_get(i)) else {
      return None
    }
    while i < len &&
          (is_ascii_alnum_unit(text.unsafe_get(i)) || text.unsafe_get(i) == '-') {
      i = i + 1
    }
    while i < len && is_html_space(text.unsafe_get(i)) {
      i = i + 1
    }
    return if i < len && text.unsafe_get(i) == '>' { Some(i + 1) } else { None }
  }
  parse_html_open_tag(text, start)
}

///|
fn matches_at(text : String, start : Int, needle : String) -> Bool {
  let len = text.length()
  let n = needle.length()
  if start + n > len {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    if text.unsafe_get(start + i) != needle.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
fn is_html_space(c : UInt16) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x0C
}

///|
/// `<!-->`, `<!--->` or `<!--` … `-->`.
fn parse_html_comment(text : String, start : Int) -> Int? {
  let len = text.length()
  if matches_at(text, start, "<!-->") {
    return Some(start + 5)
  }
  if matches_at(text, start, "<!--->") {
    return Some(start + 6)
  }
  let mut i = start + 4
  while i + 2 < len {
    if text.unsafe_get(i) == '-' &&
      text.unsafe_get(i + 1) == '-' &&
      text.unsafe_get(i + 2) == '>' {
      return Some(i + 3)
    }
    i = i + 1
  }
  None
}

///|
fn parse_html_open_tag(text : String, start : Int) -> Int? {
  let len = text.length()
  let mut i = start + 1
  guard i < len && is_ascii_letter_unit(text.unsafe_get(i)) else { return None }
  while i < len &&
        (is_ascii_alnum_unit(text.unsafe_get(i)) || text.unsafe_get(i) == '-') {
    i = i + 1
  }
  while true {
    let before = i
    while i < len && is_html_space(text.unsafe_get(i)) {
      i = i + 1
    }
    guard i < len else { return None }
    let c = text.unsafe_get(i)
    if c == '>' {
      return Some(i + 1)
    }
    if c == '/' {
      return if i + 1 < len && text.unsafe_get(i + 1) == '>' {
        Some(i + 2)
      } else {
        None
      }
    }
    // An attribute has to be preceded by whitespace.
    guard i > before else { return None }
    guard is_attribute_name_start(c) else { return None }
    i = i + 1
    while i < len && is_attribute_name_char(text.unsafe_get(i)) {
      i = i + 1
    }
    let name_end = i
    while i < len && is_html_space(text.unsafe_get(i)) {
      i = i + 1
    }
    if i < len && text.unsafe_get(i) == '=' {
      i = i + 1
      while i < len && is_html_space(text.unsafe_get(i)) {
        i = i + 1
      }
      guard i < len else { return None }
      let quote = text.unsafe_get(i)
      if quote == '"' || quote == '\'' {
        i = i + 1
        while i < len && text.unsafe_get(i) != quote {
          i = i + 1
        }
        guard i < len else { return None }
        i = i + 1
      } else {
        let value_start = i
        while i < len && !is_unquoted_value_end(text.unsafe_get(i)) {
          i = i + 1
        }
        guard i > value_start else { return None }
      }
    } else {
      i = name_end
    }
  }
  None
}

///|
fn is_attribute_name_start(c : UInt16) -> Bool {
  is_ascii_letter_unit(c) || c == '_' || c == ':'
}

///|
fn is_attribute_name_char(c : UInt16) -> Bool {
  is_ascii_alnum_unit(c) || c == '_' || c == '.' || c == ':' || c == '-'
}

///|
fn is_unquoted_value_end(c : UInt16) -> Bool {
  is_html_space(c) ||
  c == '"' ||
  c == '\'' ||
  c == '=' ||
  c == '<' ||
  c == '>' ||
  c == '`'
}
