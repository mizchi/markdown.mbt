///| Stateless search primitives used by the parsers.

///|
test "find line ending within bounds" {
  let text = "prefix\r\nbody\ntrailer"
  inspect(find_line_end(text, 0, text.length()), content="6")
  inspect(find_line_end(text, 8, text.length()), content="12")
  inspect(find_line_end(text, 13, text.length()), content="20")
  inspect(find_line_end(text, 8, 11), content="11")
}

///|
test "SIMD line scan matches scalar across chunks and tails" {
  for len in 0..<65 {
    let plain = "x".repeat(len)
    assert_eq(find_line_end(plain, 0, len), len)
    for marker_at in 0..<=len {
      let suffix = "x".repeat(len - marker_at)
      let lf = "x".repeat(marker_at) + "\n" + suffix
      let cr = "x".repeat(marker_at) + "\r" + suffix
      assert_eq(find_line_end(lf, 0, lf.length()), marker_at)
      assert_eq(find_line_end(cr, 0, cr.length()), marker_at)
    }
  }
}

///|
test "inline marker scan matches scalar across ASCII and Unicode input" {
  let markers = ["\\", "`", "*", "_", "~", ":", "[", "]", "!", "<", "&", "\n"]
  for marker in markers {
    for marker_at in [0, 1, 31, 32, 63, 64, 127, 255] {
      let text = "x".repeat(marker_at) + marker + "tail"
      assert_eq(find_inline_marker_candidate(text, 0, text.length()), marker_at)
    }
  }
  let plain = "ordinary ASCII text ".repeat(32)
  assert_eq(
    find_inline_marker_candidate(plain, 0, plain.length()),
    plain.length(),
  )
  let unicode = "ordinary text 日本語 with * marker"
  assert_eq(
    find_inline_marker_candidate(unicode, 0, unicode.length()),
    find_inline_marker_candidate_scalar(unicode, 0, unicode.length()),
  )
  for
    unicode_text in [
      "😀日本語" + "x".repeat(80) + "*tail",
      "*" + "😀日本語" + "x".repeat(80),
      "日本語" + "x".repeat(80),
    ] {
    assert_eq(
      find_inline_marker_candidate(unicode_text, 0, unicode_text.length()),
      find_inline_marker_candidate_scalar(
        unicode_text,
        0,
        unicode_text.length(),
      ),
    )
  }
  let prefixed = "日本語" + "x".repeat(80) + "*tail"
  let start = "日本語".length()
  assert_eq(
    find_inline_marker_candidate(prefixed, start, prefixed.length()),
    find_inline_marker_candidate_scalar(prefixed, start, prefixed.length()),
  )
  assert_eq(find_inline_marker_candidate("xx*yy", 3, 5), 5)
}
