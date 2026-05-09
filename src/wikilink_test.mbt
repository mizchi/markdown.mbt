///|
/// WikiLink extension tests
test "wikilinks stay literal by default" {
  let inlines = parse_inlines("See [[MoonBit]]")
  inspect(inlines.length(), content="1")
  match inlines[0] {
    Inline::Text(content~, ..) => inspect(content, content="See [[MoonBit]]")
    _ => fail("Expected literal Text")
  }
}

///|
test "parse wikilink when enabled" {
  let inlines = parse_inlines("See [[MoonBit]]", wikilinks=true)
  inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      inspect(target, content="MoonBit")
      inspect(label, content="")
      inspect(fragment, content="")
    }
    _ => fail("Expected WikiLink")
  }
}

///|
test "parse wikilink label and fragment" {
  let inlines = parse_inlines(
    "[[MoonBit#syntax|MoonBit syntax]]",
    wikilinks=true,
  )
  inspect(inlines.length(), content="1")
  match inlines[0] {
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      inspect(target, content="MoonBit")
      inspect(label, content="MoonBit syntax")
      inspect(fragment, content="syntax")
    }
    _ => fail("Expected WikiLink")
  }
}

///|
test "render wikilink only when enabled" {
  let default_html = md_to_html("See [[MoonBit]]\n")
  inspect(default_html, content="<p>See [[MoonBit]]</p>\n")
  let html = md_to_html(
    "See [[MoonBit#syntax|MoonBit syntax]]\n",
    wikilinks=true,
  )
  inspect(
    html,
    content="<p>See <a href=\"MoonBit#syntax\">MoonBit syntax</a></p>\n",
  )
}

///|
test "serialize wikilink" {
  let result = parse("[[MoonBit|MoonBit notes]]\n", wikilinks=true)
  inspect(serialize(result.document), content="[[MoonBit|MoonBit notes]]\n")
}
