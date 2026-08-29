///|
/// GFM extension HTML rendering tests
test "html: strikethrough" {
  assert_html_compat("~~deleted~~\n", "strikethrough")
}

///|
test "html: task list" {
  assert_html_compat("- [ ] todo\n- [x] done\n", "task list")
}

///|
test "html: table simple" {
  assert_html_compat("| a | b |\n|---|---|\n| 1 | 2 |\n", "table simple")
}

///|
test "html: table with alignment" {
  assert_html_compat(
    "| left | center | right |\n|:-----|:------:|------:|\n| 1 | 2 | 3 |\n", "table with alignment",
  )
}

///|
/// GFM example 200: `\|` puts a pipe into a cell, including inside other
/// inline spans.
test "html: table cell with escaped pipes inside inline elements" {
  assert_html_compat(
    "| f\\|oo  |\n| ------ |\n| b `\\|` az |\n| b **\\|** im |\n", "table escaped pipes",
  )
}

///|
test "html: autolink" {
  assert_html_compat("<https://example.com>\n", "autolink")
}

///|
test "html: autolink email" {
  assert_html_compat("<user@example.com>\n", "autolink email")
}
