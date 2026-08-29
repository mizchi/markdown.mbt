///| Unicode character classification helpers used by the inline parser.

///|
/// A "Unicode whitespace character" as CommonMark defines it: anything in the
/// Zs general category, plus tab, line feed, form feed and carriage return.
pub fn is_unicode_whitespace(c : Char) -> Bool {
  let code = c.to_int()
  if code < 0x80 {
    return code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0C ||
      code == 0x0D
  }
  code == 0xA0 ||
  code == 0x1680 ||
  (code >= 0x2000 && code <= 0x200A) ||
  code == 0x202F ||
  code == 0x205F ||
  code == 0x3000
}

///|
/// A "Unicode punctuation character" as CommonMark 0.31.2 defines it: anything
/// in a punctuation (P*) or symbol (S*) general category.
///
/// The ranges below cover the blocks that actually carry punctuation and
/// symbols; letters, digits and marks are deliberately excluded so that
/// flanking is decided correctly for ordinary text.
pub fn is_unicode_punctuation(c : Char) -> Bool {
  let code = c.to_int()
  if code < 0x80 {
    return (code >= 0x21 && code <= 0x2F) || // !"#$%&'()*+,-./
      (code >= 0x3A && code <= 0x40) || // :;<=>?@
      (code >= 0x5B && code <= 0x60) || // [\]^_`
      (code >= 0x7B && code <= 0x7E) // {|}~
  }
  if code < 0x100 {
    // Latin-1 supplement, minus the letters (ª µ º) and digits (² ³ ¹).
    return (code >= 0xA1 && code <= 0xA9) ||
      code == 0xAB ||
      code == 0xAC ||
      (code >= 0xAE && code <= 0xB1) ||
      code == 0xB4 ||
      (code >= 0xB6 && code <= 0xB8) ||
      code == 0xBB ||
      code == 0xBF ||
      code == 0xD7 ||
      code == 0xF7
  }
  (code >= 0x2010 && code <= 0x2027) || // general punctuation
  (code >= 0x2030 && code <= 0x205E) ||
  // Only the superscript signs and brackets; the superscript digits and the
  // modifier letter next to them are No and Lm, not P* or S*.
  (code >= 0x207A && code <= 0x207E) ||
  (code >= 0x208A && code <= 0x208E) ||
  (code >= 0x20A0 && code <= 0x20C0) || // currency symbols
  (code >= 0x2100 && code <= 0x2101) ||
  (code >= 0x2103 && code <= 0x2106) ||
  (code >= 0x2108 && code <= 0x2109) ||
  code == 0x2114 ||
  (code >= 0x2116 && code <= 0x2118) ||
  (code >= 0x211E && code <= 0x2123) ||
  code == 0x2125 ||
  code == 0x2127 ||
  code == 0x2129 ||
  code == 0x212E ||
  (code >= 0x213A && code <= 0x213B) ||
  (code >= 0x2140 && code <= 0x2144) ||
  code == 0x214A ||
  (code >= 0x214C && code <= 0x214D) ||
  code == 0x214F ||
  (code >= 0x218A && code <= 0x218B) ||
  (code >= 0x2190 && code <= 0x2426) || // arrows, math, technical, misc
  (code >= 0x2440 && code <= 0x244A) ||
  (code >= 0x249C && code <= 0x24E9) ||
  (code >= 0x2500 && code <= 0x2775) ||
  (code >= 0x2794 && code <= 0x2BFF) ||
  (code >= 0x2E00 && code <= 0x2E7F) || // supplemental punctuation
  (code >= 0x3001 && code <= 0x3004) || // CJK symbols and punctuation
  (code >= 0x3008 && code <= 0x3020) ||
  code == 0x3030 ||
  (code >= 0xFE10 && code <= 0xFE19) ||
  (code >= 0xFE30 && code <= 0xFE6B) ||
  (code >= 0xFF01 && code <= 0xFF0F) || // fullwidth forms
  (code >= 0xFF1A && code <= 0xFF20) ||
  (code >= 0xFF3B && code <= 0xFF40) ||
  (code >= 0xFF5B && code <= 0xFF65) ||
  (code >= 0x1F000 && code <= 0x1FBFF) // pictographs and emoji
}
