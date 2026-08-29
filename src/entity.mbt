///| Entity and numeric character references.

///| See <https://spec.commonmark.org/0.31.2/#entity-and-numeric-character-references>.

///|
/// Replacement character used for code points the spec rejects (NUL, values
/// outside Unicode, and unpaired surrogates).
const ReplacementChar : String = "\u{fffd}"

///|
/// Named references, expanded from `entity_chunks` the first time one is seen.
/// Keys omit the surrounding `&` and `;`.
let entity_map : Map[String, String] = Map([], capacity=2048)

///|
fn ensure_entity_map() -> Unit {
  if !entity_map.is_empty() {
    return
  }
  for chunk in entity_chunks {
    let len = chunk.length()
    let mut i = 0
    while i < len {
      let mut eq = i
      while eq < len && chunk.unsafe_get(eq) != '=' {
        eq = eq + 1
      }
      let mut end = eq + 1
      while end < len && chunk.unsafe_get(end) != '\u{1}' {
        end = end + 1
      }
      entity_map[chunk.unsafe_substring(start=i, end=eq)] = chunk.unsafe_substring(
        start=eq + 1,
        end~,
      )
      i = end + 1
    }
  }
}

///|
/// Look up a named character reference, e.g. `"amp"` -> `"&"`.
fn lookup_entity(name : String) -> String? {
  ensure_entity_map()
  entity_map.get(name)
}

///|
fn code_point_to_string(code : Int) -> String {
  if code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
    return ReplacementChar
  }
  match code.to_char() {
    Some(c) => String::make(1, c)
    None => ReplacementChar
  }
}

///|
fn is_ascii_digit_unit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ascii_alnum_unit(c : UInt16) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn hex_digit_value(c : UInt16) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Decode the entity reference that starts with the `&` at `start`.
///
/// Returns the replacement text together with the index just past the closing
/// `;`, or `None` when this is not a valid reference and the `&` should be kept
/// as literal text.
fn decode_entity(text : String, start : Int) -> (String, Int)? {
  let len = text.length()
  guard start < len && text.unsafe_get(start) == '&' else { return None }
  let mut i = start + 1
  guard i < len else { return None }
  if text.unsafe_get(i) == '#' {
    i = i + 1
    guard i < len else { return None }
    let c = text.unsafe_get(i)
    if c == 'x' || c == 'X' {
      i = i + 1
      let digits_start = i
      let mut value = 0
      while i < len && i - digits_start < 6 {
        match hex_digit_value(text.unsafe_get(i)) {
          Some(d) => {
            value = value * 16 + d
            i = i + 1
          }
          None => break
        }
      }
      guard i > digits_start && i < len && text.unsafe_get(i) == ';' else {
        return None
      }
      return Some((code_point_to_string(value), i + 1))
    }
    let digits_start = i
    let mut value = 0
    while i < len &&
          i - digits_start < 7 &&
          is_ascii_digit_unit(text.unsafe_get(i)) {
      value = value * 10 + (text.unsafe_get(i).to_int() - '0'.to_int())
      i = i + 1
    }
    guard i > digits_start && i < len && text.unsafe_get(i) == ';' else {
      return None
    }
    return Some((code_point_to_string(value), i + 1))
  }
  let name_start = i
  while i < len && is_ascii_alnum_unit(text.unsafe_get(i)) {
    i = i + 1
  }
  guard i > name_start && i < len && text.unsafe_get(i) == ';' else {
    return None
  }
  match lookup_entity(text.unsafe_substring(start=name_start, end=i)) {
    Some(value) => Some((value, i + 1))
    None => None
  }
}
