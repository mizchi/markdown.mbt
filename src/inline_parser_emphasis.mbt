///| Emphasis and strong emphasis via the CommonMark delimiter stack.

///|
/// Read the code point ending just before `i`.
fn char_before(text : String, i : Int) -> Char {
  let lo = text.unsafe_get(i - 1).to_int()
  if lo >= 0xDC00 && lo <= 0xDFFF && i >= 2 {
    let hi = text.unsafe_get(i - 2).to_int()
    if hi >= 0xD800 && hi <= 0xDBFF {
      return (0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)).unsafe_to_char()
    }
  }
  lo.unsafe_to_char()
}

///|
/// Read the code point starting at `i`.
fn char_at_index(text : String, i : Int) -> Char {
  let hi = text.unsafe_get(i).to_int()
  if hi >= 0xD800 && hi <= 0xDBFF && i + 1 < text.length() {
    let lo = text.unsafe_get(i + 1).to_int()
    if lo >= 0xDC00 && lo <= 0xDFFF {
      return (0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)).unsafe_to_char()
    }
  }
  hi.unsafe_to_char()
}

///|
/// Push the run of `ch` starting at `start` onto the delimiter stack and
/// return the index just past it.
fn InlineCtx::push_delimiter_run(
  self : InlineCtx,
  start : Int,
  ch : Char,
) -> Int {
  let text = self.text
  let len = self.len
  let mut end = start
  while end < len && text.unsafe_get(end).to_int() == ch.to_int() {
    end = end + 1
  }
  let count = end - start
  let before_ws = start == 0 || is_unicode_whitespace(char_before(text, start))
  let before_punct = start > 0 && is_unicode_punctuation(char_before(text, start))
  let after_ws = end >= len || is_unicode_whitespace(char_at_index(text, end))
  let after_punct = end < len && is_unicode_punctuation(char_at_index(text, end))
  let left_flanking = !after_ws &&
    (!after_punct || before_ws || before_punct)
  let right_flanking = !before_ws &&
    (!before_punct || after_ws || after_punct)
  let (can_open, can_close) = if ch == '_' {
    (
      left_flanking && (!right_flanking || before_punct),
      right_flanking && (!left_flanking || after_punct),
    )
  } else {
    (left_flanking, right_flanking)
  }
  let idx = self.append({
    inline: None,
    mergeable: false,
    ch,
    count,
    orig: count,
    can_open,
    can_close,
    start,
    prev: -1,
    next: -1,
  })
  self.delims.push(idx)
  end
}

///|
/// Key for the `openers_bottom` table: delimiters can only be reconsidered
/// per character, per closer length modulo three, and per "can also open".
fn openers_bottom_key(ch : Char, closer_len : Int, can_open : Bool) -> Int {
  let base = match ch {
    '*' => 0
    '_' => 1
    _ => 2
  }
  base * 8 + closer_len % 3 * 2 + (if can_open { 1 } else { 0 })
}

///|
/// Turn stacked `*`/`_`/`~` runs at or above `bottom` into emphasis nodes.
fn InlineCtx::process_emphasis(self : InlineCtx, bottom : Int) -> Unit {
  let openers_bottom : Map[Int, Int] = Map([], capacity=8)
  let mut closer_i = bottom
  while closer_i < self.delims.length() {
    let closer_slot = self.delims[closer_i]
    if closer_slot < 0 {
      closer_i = closer_i + 1
      continue
    }
    let closer = self.slots[closer_slot]
    if !closer.can_close || closer.count == 0 {
      closer_i = closer_i + 1
      continue
    }
    let key = openers_bottom_key(closer.ch, closer.orig, closer.can_open)
    let limit = match openers_bottom.get(key) {
      Some(v) => v
      None => bottom
    }
    let mut opener_i = closer_i - 1
    let mut found = -1
    while opener_i >= limit {
      let opener_slot = self.delims[opener_i]
      if opener_slot < 0 {
        opener_i = opener_i - 1
        continue
      }
      let opener = self.slots[opener_slot]
      if opener.count > 0 && opener.can_open && opener.ch == closer.ch {
        // "Rule of three": runs that can both open and close only match when
        // the combined lengths are not a multiple of three, unless both are.
        let both_ways = closer.can_open || opener.can_close
        let blocked = both_ways &&
          (opener.orig + closer.orig) % 3 == 0 &&
          !(opener.orig % 3 == 0 && closer.orig % 3 == 0)
        if !blocked {
          found = opener_i
          break
        }
      }
      opener_i = opener_i - 1
    }
    if found < 0 {
      openers_bottom[key] = closer_i
      if !closer.can_open {
        self.delims[closer_i] = -1
      }
      closer_i = closer_i + 1
      continue
    }
    let opener_slot = self.delims[found]
    let opener = self.slots[opener_slot]
    if closer.ch == '~' {
      self.wrap_delimiters(found, closer_i, 2, true)
    } else {
      let use_count = if opener.count >= 2 && closer.count >= 2 { 2 } else { 1 }
      self.wrap_delimiters(found, closer_i, use_count, false)
    }
    if self.slots[closer_slot].count == 0 {
      self.delims[closer_i] = -1
      closer_i = closer_i + 1
    }
  }
  // Everything at or above `bottom` has now had its chance to match.
  let mut i = bottom
  while i < self.delims.length() {
    self.delims[i] = -1
    i = i + 1
  }
  while self.delims.length() > bottom {
    let _ = self.delims.pop()

  }
}

///|
/// Wrap the slots between two delimiter runs in an emphasis node.
fn InlineCtx::wrap_delimiters(
  self : InlineCtx,
  opener_i : Int,
  closer_i : Int,
  use_count : Int,
  strike : Bool,
) -> Unit {
  let opener_slot = self.delims[opener_i]
  let closer_slot = self.delims[closer_i]
  let opener = self.slots[opener_slot]
  let closer = self.slots[closer_slot]
  let children = self.materialize(opener.next, closer_slot)
  let mut cur = opener.next
  while cur >= 0 && cur != closer_slot {
    let next = self.slots[cur].next
    self.unlink(cur)
    cur = next
  }
  let content_start = opener.start + opener.count - use_count
  let content_end = closer.start + closer.orig - closer.count + use_count
  let span = Span::new(content_start, content_end)
  let marker = if opener.ch == '_' {
    EmphasisMarker::Underscore
  } else {
    EmphasisMarker::Asterisk
  }
  let node = if strike {
    Inline::Strikethrough(children~, span~)
  } else if use_count == 2 {
    Inline::Strong(marker~, children~, span~)
  } else {
    Inline::Emphasis(marker~, children~, span~)
  }
  let _ = self.insert_after(opener_slot, new_inline_slot(node, content_start))
  self.slots[opener_slot].count = opener.count - use_count
  self.slots[closer_slot].count = closer.count - use_count
  if self.slots[opener_slot].count == 0 {
    self.unlink(opener_slot)
    self.delims[opener_i] = -1
  }
  if self.slots[closer_slot].count == 0 {
    self.unlink(closer_slot)
  }
  // Delimiters between the pair can never match anything now.
  let mut j = opener_i + 1
  while j < closer_i {
    self.delims[j] = -1
    j = j + 1
  }
}
