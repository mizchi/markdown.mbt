///|
/// GFM extended-autolink helpers used by the HTML renderer.
priv enum BareAutolinkKind {
  Url
  Www
  Email
}

///|
#valtype
priv struct BareAutolink {
  start : Int
  end : Int
  kind : BareAutolinkKind
}

///|
/// Find the next URL, `www.` link, or email in a plain-text inline node.
fn find_next_autolink(content : String, from : Int) -> BareAutolink? {
  let len = content.length()
  let mut pos = from
  while pos < len {
    pos = find_autolink_candidate(content, pos, len)
    if pos >= len {
      return None
    }
    let c = content.unsafe_get(pos)
    // GFM's URL forms are lowercase and can only start with h/f/w. Avoid
    // constructing and comparing four StringViews at every text position.
    if c == 'h' || c == 'f' || c == 'w' {
      match url_autolink_at(content, pos) {
        Some(found) => return Some(found)
        None => ()
      }
    }
    // An email can be identified from its single mandatory '@'. Scanning the
    // local part backwards here avoids rescanning every ordinary word as a
    // possible email address.
    if c == '@' {
      match email_autolink_at_sign(content, pos) {
        Some(found) => return Some(found)
        None => ()
      }
    }
    pos = pos + 1
  }
  None
}

///|
/// Scalar fallback for short strings and non-linear-memory targets.
#inline
fn find_autolink_candidate_scalar(
  content : String,
  start : Int,
  end : Int,
) -> Int {
  for pos in start..<end {
    let c = content.unsafe_get(pos)
    if c == 'h' || c == 'f' || c == 'w' || c == '@' {
      break pos
    }
  } nobreak {
    end
  }
}

///|
#cfg(not(any(target="native", target="wasm")))
#inline
fn find_autolink_candidate(content : String, start : Int, end : Int) -> Int {
  find_autolink_candidate_scalar(content, start, end)
}

///|
/// Find the four possible bare-autolink anchors eight code units at a time.
#cfg(any(target="native", target="wasm"))
fn find_autolink_candidate(content : String, start : Int, end : Int) -> Int {
  guard end - start >= 16 else {
    return find_autolink_candidate_scalar(content, start, end)
  }
  let h = @v128.i16x8_splat('h')
  let f = @v128.i16x8_splat('f')
  let w = @v128.i16x8_splat('w')
  let at = @v128.i16x8_splat('@')
  let tail_start = for pos = start; pos + 8 <= end; {
    let block = @v128.v128_load_i16x8(content, pos)
    let mask = @v128.i16x8_bitmask(
      @v128.v128_or_(
        @v128.v128_or_(@v128.i16x8_eq(block, h), @v128.i16x8_eq(block, f)),
        @v128.v128_or_(@v128.i16x8_eq(block, w), @v128.i16x8_eq(block, at)),
      ),
    )
    if mask != 0 {
      return pos + mask.ctz()
    }
    continue pos + 8
  } nobreak {
    pos
  }
  find_autolink_candidate_scalar(content, tail_start, end)
}

///|
/// Match an explicit `http(s)://` / `ftp://` URL or a `www.` URL.
fn url_autolink_at(content : String, start : Int) -> BareAutolink? {
  let is_www = string_has_prefix_at(content, start, "www.")
  let scheme_length = if string_has_prefix_at(content, start, "https://") {
    8
  } else if string_has_prefix_at(content, start, "http://") ||
    string_has_prefix_at(content, start, "ftp://") {
    7
  } else {
    0
  }
  if !is_www && scheme_length == 0 {
    return None
  }
  if start > 0 {
    let previous = content.unsafe_get(start - 1)
    if is_www {
      if !(is_html_space(previous) ||
        previous == '*' ||
        previous == '_' ||
        previous == '~' ||
        previous == '(') {
        return None
      }
    } else if is_ascii_alnum_unit(previous) {
      return None
    }
  }
  let host_start = if is_www { start + 4 } else { start + scheme_length }
  let host_end = scan_url_host(content, host_start)
  if host_end == host_start {
    return None
  }
  if is_www && !url_host_has_dot(content, host_start, host_end) {
    return None
  }
  if url_host_has_invalid_underscore(content, host_start, host_end) {
    return None
  }
  let raw_end = find_url_raw_end(content, host_end)
  let end = trim_url_end(content, start, raw_end)
  guard end > host_start else { return None }
  Some({ start, end, kind: if is_www { Www } else { Url } })
}

///|
/// The host portion ends before URL path/query punctuation.
fn scan_url_host(content : String, start : Int) -> Int {
  let len = content.length()
  let mut end = start
  while end < len {
    let c = content.unsafe_get(end)
    if is_ascii_alnum_unit(c) || c == '.' || c == '-' || c == '_' {
      end = end + 1
    } else {
      break
    }
  }
  end
}

///|
fn url_host_has_dot(content : String, start : Int, end : Int) -> Bool {
  for i = start; i < end; i = i + 1 {
    if content.unsafe_get(i) == '.' {
      return true
    }
  }
  false
}

///|
/// Hostnames reject underscores in either of their final two labels.
fn url_host_has_invalid_underscore(
  content : String,
  start : Int,
  end : Int,
) -> Bool {
  let mut last_dot = end
  let mut previous_dot = end
  for i = end - 1; i >= start; i = i - 1 {
    if content.unsafe_get(i) == '.' {
      if last_dot == end {
        last_dot = i
      } else {
        previous_dot = i
        break
      }
    }
  }
  let check_from = if previous_dot < end { previous_dot + 1 } else { start }
  for i = check_from; i < end; i = i + 1 {
    if content.unsafe_get(i) == '_' {
      return true
    }
  }
  false
}

///|
/// Match the GFM extended-email form around its mandatory `@`.
fn email_autolink_at_sign(content : String, at : Int) -> BareAutolink? {
  let len = content.length()
  guard at > 0 && at + 1 < len && content.unsafe_get(at) == '@' else {
    return None
  }
  let mut start = at
  while start > 0 && is_email_local_char(content.unsafe_get(start - 1)) {
    start = start - 1
  }
  guard start < at else { return None }
  if start > 0 && is_email_local_char(content.unsafe_get(start - 1)) {
    return None
  }
  let domain_start = at + 1
  let mut end = domain_start
  let mut dots = 0
  while end < len {
    let c = content.unsafe_get(end)
    if is_ascii_alnum_unit(c) || c == '-' || c == '_' {
      end = end + 1
    } else if c == '.' &&
      end + 1 < len &&
      is_ascii_alnum_unit(content.unsafe_get(end + 1)) {
      dots = dots + 1
      end = end + 1
    } else {
      break
    }
  }
  guard end > domain_start && dots > 0 else { return None }
  let last = content.unsafe_get(end - 1)
  guard is_ascii_letter_unit(last) else { return None }
  guard !url_host_has_invalid_underscore(content, domain_start, end) else {
    return None
  }
  Some({ start, end, kind: Email })
}

///|
fn is_email_local_char(c : UInt16) -> Bool {
  is_ascii_alnum_unit(c) || c == '.' || c == '+' || c == '-' || c == '_'
}

///|
fn string_has_prefix_at(content : String, pos : Int, prefix : String) -> Bool {
  let end = pos + prefix.length()
  guard end <= content.length() else { return false }
  for i = 0; i < prefix.length(); i = i + 1 {
    if content.unsafe_get(pos + i) != prefix.unsafe_get(i) {
      return false
    }
  }
  true
}

///|
fn find_url_raw_end(content : String, start : Int) -> Int {
  let len = content.length()
  let mut end = start
  while end < len {
    let c = content.unsafe_get(end)
    if is_html_space(c) || c == '<' {
      break
    }
    end = end + 1
  }
  end
}

///|
/// Apply cmark-gfm's balanced-parenthesis and trailing-delimiter rules.
fn trim_url_end(content : String, start : Int, raw_end : Int) -> Int {
  let mut opening = 0
  let mut closing = 0
  for i = start; i < raw_end; i = i + 1 {
    let c = content.unsafe_get(i)
    if c == '(' {
      opening = opening + 1
    } else if c == ')' {
      closing = closing + 1
    }
  }
  let mut end = raw_end
  while end > start {
    let c = content.unsafe_get(end - 1)
    if c == ')' {
      if closing <= opening {
        return end
      }
      closing = closing - 1
      end = end - 1
    } else if c == '?' ||
      c == '!' ||
      c == '.' ||
      c == ',' ||
      c == ':' ||
      c == '*' ||
      c == '_' ||
      c == '~' ||
      c == '\'' ||
      c == '"' {
      end = end - 1
    } else if c == ';' {
      let mut entity_start = end - 2
      while entity_start > start &&
            is_ascii_letter_unit(content.unsafe_get(entity_start)) {
        entity_start = entity_start - 1
      }
      if entity_start < end - 2 && content.unsafe_get(entity_start) == '&' {
        end = entity_start
      } else {
        end = end - 1
      }
    } else {
      return end
    }
  }
  end
}
