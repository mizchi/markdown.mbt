///|
fn make_fm(entries : Array[(String, String)]) -> @md.Frontmatter {
  { raw: "", entries, span: @md.Span::empty() }
}

///|
test "get_string: existing key" {
  let fm = make_fm([("title", "Hello"), ("description", "World")])
  inspect(get_string(fm, "title"), content="Some(\"Hello\")")
  inspect(get_string(fm, "description"), content="Some(\"World\")")
}

///|
test "get_string: missing key" {
  let fm = make_fm([("title", "Hello")])
  inspect(get_string(fm, "missing"), content="None")
}

///|
test "get_bool: true value" {
  let fm = make_fm([("sidebar", "true")])
  inspect(get_bool(fm, "sidebar"), content="Some(true)")
}

///|
test "get_bool: false value" {
  let fm = make_fm([("sidebar", "false")])
  inspect(get_bool(fm, "sidebar"), content="Some(false)")
}

///|
test "get_bool: non-boolean value" {
  let fm = make_fm([("sidebar", "yes")])
  inspect(get_bool(fm, "sidebar"), content="None")
}

///|
test "get_int: valid integer" {
  let fm = make_fm([("order", "42")])
  inspect(get_int(fm, "order"), content="Some(42)")
}

///|
test "get_int: invalid integer" {
  let fm = make_fm([("order", "not-a-number")])
  inspect(get_int(fm, "order"), content="None")
}

///|
test "get_list: comma-separated" {
  let fm = make_fm([("tags", "foo, bar, baz")])
  let list = get_list(fm, "tags")
  inspect(list.length(), content="3")
  inspect(list[0], content="foo")
  inspect(list[1], content="bar")
  inspect(list[2], content="baz")
}

///|
test "get_list: single item" {
  let fm = make_fm([("tags", "single")])
  let list = get_list(fm, "tags")
  inspect(list.length(), content="1")
  inspect(list[0], content="single")
}

///|
test "get_list: trims blanks and drops empty items" {
  let fm = make_fm([("tags", " foo, , bar ,, baz  ")])
  let list = get_list(fm, "tags")
  inspect(list.length(), content="3")
  inspect(list[0], content="foo")
  inspect(list[1], content="bar")
  inspect(list[2], content="baz")
}

///|
test "get_list: missing key" {
  let fm = make_fm([])
  let list = get_list(fm, "tags")
  inspect(list.length(), content="0")
}

///|
test "has_key: existing" {
  let fm = make_fm([("title", "Hello")])
  inspect(has_key(fm, "title"), content="true")
}

///|
test "has_key: missing" {
  let fm = make_fm([("title", "Hello")])
  inspect(has_key(fm, "other"), content="false")
}

///|
test "keys: multiple" {
  let fm = make_fm([("a", "1"), ("b", "2"), ("c", "3")])
  let k = keys(fm)
  inspect(k.length(), content="3")
  inspect(k[0], content="a")
  inspect(k[1], content="b")
  inspect(k[2], content="c")
}
