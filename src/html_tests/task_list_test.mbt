///| Task list HTML tests

test "html: task list unchecked" {
  assert_html_compat("- [ ] unchecked\n", "task list unchecked")
}

test "html: task list checked" {
  assert_html_compat("- [x] checked\n", "task list checked")
}

test "html: task list uppercase X" {
  assert_html_compat("- [X] checked uppercase\n", "task list uppercase X")
}

test "html: task list mixed" {
  assert_html_compat("- [ ] todo\n- [x] done\n- [ ] pending\n", "task list mixed")
}

test "html: task list with text" {
  assert_html_compat("- [ ] buy milk\n- [x] write code\n", "task list with text")
}

test "html: task list with emphasis" {
  assert_html_compat("- [ ] **important** task\n- [x] *completed* task\n", "task list with emphasis")
}

test "html: task list with code" {
  assert_html_compat("- [ ] run `npm test`\n- [x] fix `bug`\n", "task list with code")
}

test "html: task list with link" {
  assert_html_compat("- [ ] check [docs](url)\n", "task list with link")
}

test "html: regular and task list items" {
  assert_html_compat("- regular item\n- [ ] task item\n", "regular and task list items")
}
