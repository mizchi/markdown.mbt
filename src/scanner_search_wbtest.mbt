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
