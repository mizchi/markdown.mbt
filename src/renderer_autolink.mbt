///| Bare-URL autolink helpers used by the HTML renderer.
///|
///| Pure utilities — given a `String` and a position, classify the surrounding
///| characters and find the boundaries of an `http(s)://` URL. Extracted from
///| renderer.mbt to keep the renderer itself focused on AST traversal.

///|
fn find_next_url_start(content : String, from : Int) -> Int? {
  let len = content.length()
  let mut pos = from
  while pos < len {
    if is_url_start_at(content, pos) {
      return Some(pos)
    }
    pos = pos + 1
  }
  None
}

///|
fn is_url_start_at(content : String, pos : Int) -> Bool {
  let boundary = pos == 0 ||
    is_url_left_boundary(ascii_char_at(content, pos - 1))
  boundary &&
  (
    string_has_prefix_at(content, pos, "https://") ||
    string_has_prefix_at(content, pos, "http://")
  )
}

///|
fn ascii_char_at(content : String, pos : Int) -> Char {
  Int::unsafe_to_char(content.code_unit_at(pos).to_int())
}

///|
fn string_has_prefix_at(content : String, pos : Int, prefix : String) -> Bool {
  let end = pos + prefix.length()
  end <= content.length() && content.unsafe_substring(start=pos, end~) == prefix
}

///|
fn is_url_left_boundary(c : Char) -> Bool {
  c == ' ' ||
  c == '\n' ||
  c == '\t' ||
  c == '\r' ||
  c == '(' ||
  c == '[' ||
  c == '{' ||
  c == '<'
}

///|
fn find_url_raw_end(content : String, start : Int) -> Int {
  let len = content.length()
  let mut end = start
  while end < len && !is_url_stop_char(ascii_char_at(content, end)) {
    end = end + 1
  }
  end
}

///|
fn is_url_stop_char(c : Char) -> Bool {
  c == ' ' ||
  c == '\n' ||
  c == '\t' ||
  c == '\r' ||
  c == '<' ||
  c == '"' ||
  c == '\''
}

///|
fn trim_url_end(content : String, start : Int, raw_end : Int) -> Int {
  let mut end = raw_end
  while end > start &&
        is_url_trailing_punctuation(ascii_char_at(content, end - 1)) {
    end = end - 1
  }
  end
}

///|
fn is_url_trailing_punctuation(c : Char) -> Bool {
  c == '.' ||
  c == ',' ||
  c == ';' ||
  c == ':' ||
  c == '!' ||
  c == '?' ||
  c == ')' ||
  c == ']' ||
  c == '}'
}
