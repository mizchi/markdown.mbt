///| Search primitives used by HTML block and inline parsing.

///|
test "find the end of an exact HTML terminator" {
  let text = "aa-->bb]]>cc"
  assert_eq(find_exact_end_from(text, 0, "-->"), Some(5))
  assert_eq(find_exact_end_from(text, 3, "-->"), None)
  assert_eq(find_exact_end_from(text, 5, "]]>"), Some(10))
}

///|
test "find an HTML raw-text closing tag ignoring ASCII case" {
  let text = "prefix </ScRiPt> suffix"
  assert_eq(find_html_raw_text_closer(text, 0, "script"), Some(7))
  assert_eq(find_html_raw_text_closer(text, 8, "script"), None)
}
