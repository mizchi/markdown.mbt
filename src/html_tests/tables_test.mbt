///| Table HTML tests

test "html: table left align" {
  assert_html_compat("| a |\n|:--|\n| 1 |\n", "table left align")
}

test "html: table right align" {
  assert_html_compat("| a |\n|--:|\n| 1 |\n", "table right align")
}

test "html: table center align" {
  assert_html_compat("| a |\n|:-:|\n| 1 |\n", "table center align")
}

test "html: table multiple rows" {
  assert_html_compat("| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n", "table multiple rows")
}

test "html: table with emphasis" {
  assert_html_compat("| **bold** | *italic* |\n|----------|----------|\n| text | text |\n", "table with emphasis")
}

test "html: table empty cells" {
  assert_html_compat("| a | b |\n|---|---|\n| | |\n", "table empty cells")
}

test "html: table single column" {
  assert_html_compat("| a |\n|---|\n| 1 |\n", "table single column")
}

test "html: table many columns" {
  assert_html_compat("| a | b | c | d |\n|---|---|---|---|\n| 1 | 2 | 3 | 4 |\n", "table many columns")
}

test "html: table mixed alignment" {
  assert_html_compat("| left | center | right |\n|:-----|:------:|------:|\n| L | C | R |\n", "table mixed alignment")
}

test "html: table with code" {
  assert_html_compat("| code |\n|------|\n| `x` |\n", "table with code")
}

test "html: table with link" {
  assert_html_compat("| link |\n|------|\n| [a](b) |\n", "table with link")
}

test "html: table header only" {
  assert_html_compat("| a | b |\n|---|---|\n", "table header only")
}

test "html: table many rows" {
  assert_html_compat("| x |\n|---|\n| 1 |\n| 2 |\n| 3 |\n| 4 |\n| 5 |\n", "table many rows")
}

test "html: table with strikethrough" {
  assert_html_compat("| text |\n|------|\n| ~~del~~ |\n", "table with strikethrough")
}
