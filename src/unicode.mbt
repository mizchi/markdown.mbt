///| Unicode character classification helpers used by the inline parser.

///|
/// Check if character is Unicode whitespace
pub fn is_unicode_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ''
}

///|
/// Check if character is Unicode punctuation (ASCII subset)
pub fn is_unicode_punctuation(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
  (code >= 0x3A && code <= 0x40) || // :;<=>?@
  (code >= 0x5B && code <= 0x60) || // [\]^_`
  (code >= 0x7B && code <= 0x7E) // {|}~
}
