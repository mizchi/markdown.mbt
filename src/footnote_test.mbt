///|
/// Footnote tests
test "footnote reference parsing" {
  let input = "Here is a footnote reference[^1].\n"
  let result = parse(input)
  match result.document.children[0] {
    Paragraph(children~, ..) => {
      // "Here is a footnote reference", FootnoteReference, "."
      @debug.debug_inspect(children.length(), content="3")
      match children[1] {
        FootnoteReference(label~, ..) => @debug.debug_inspect(label, content=(
          #|"1"
        ))
        _ => fail("Expected FootnoteReference")
      }
    }
    _ => fail("Expected Paragraph")
  }
}

///|
test "footnote definition parsing" {
  let input = "[^1]: This is the footnote content.\n"
  let result = parse(input)
  @debug.debug_inspect(result.document.children.length(), content="1")
  match result.document.children[0] {
    FootnoteDefinition(label~, children~, ..) => {
      @debug.debug_inspect(label, content=(
        #|"1"
      ))
      @debug.debug_inspect(children.length(), content="1")
    }
    _ => fail("Expected FootnoteDefinition")
  }
}

///|
test "footnote roundtrip" {
  let input = "Here is a footnote reference[^1].\n\n[^1]: This is the footnote content.\n"
  let output = md_parse_and_render(input)
  @debug.debug_inspect(output == input, content="true")
}
