///| Bullet list and ordered list HTML tests

test "html: bullet list simple" {
  assert_html_compat("- item\n", "bullet list simple")
}

test "html: bullet list asterisk" {
  assert_html_compat("* one\n* two\n", "bullet list asterisk")
}

test "html: bullet list plus" {
  assert_html_compat("+ one\n+ two\n", "bullet list plus")
}

test "html: bullet list with emphasis" {
  assert_html_compat("- **bold** item\n- *italic* item\n", "bullet list with emphasis")
}

test "html: bullet list with code" {
  assert_html_compat("- `code` item\n- normal item\n", "bullet list with code")
}

test "html: bullet list with link" {
  assert_html_compat("- [link](url)\n- text\n", "bullet list with link")
}

test "html: ordered list simple" {
  assert_html_compat("1. item\n", "ordered list simple")
}

test "html: ordered list start 0" {
  assert_html_compat("0. zero\n1. one\n", "ordered list start 0")
}

test "html: ordered list start 10" {
  assert_html_compat("10. ten\n11. eleven\n", "ordered list start 10")
}

test "html: ordered list with emphasis" {
  assert_html_compat("1. **bold**\n2. *italic*\n", "ordered list with emphasis")
}

test "html: ordered list loose" {
  assert_html_compat("1. first\n\n2. second\n", "ordered list loose")
}

test "html: bullet list long items" {
  assert_html_compat("- This is a longer item\n- Another longer item here\n", "bullet list long items")
}
