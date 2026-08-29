///|
/// Serializer tests
test "serialize heading" {
  let source = "# Hello World\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output,
    content=(
      #|"# Hello World\n"
    ),
  )
}

///|
test "serialize heading with closing hashes" {
  let source = "## Title ##\n"
  let result = parse(source)
  let output = serialize(result.document)
  // GFM style: closing hashes are removed
  @debug.debug_inspect(
    output,
    content=(
      #|"## Title\n"
    ),
  )
}

///|
test "serialize paragraph" {
  let source = "Hello world.\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output,
    content=(
      #|"Hello world.\n"
    ),
  )
}

///|
test "serialize fenced code" {
  let source = "```js\nconsole.log('hello');\n```\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output,
    content=(
      #|"```js\nconsole.log('hello');\n```\n"
    ),
  )
}

///|
test "serialize fenced code with tilde" {
  let source = "~~~python\nprint('hello')\n~~~\n"
  let result = parse(source)
  let output = serialize(result.document)
  // GFM style: tilde fences are converted to backtick fences
  @debug.debug_inspect(
    output,
    content=(
      #|"```python\nprint('hello')\n```\n"
    ),
  )
}

///|
test "serialize thematic break" {
  let source = "text\n\n---\n"
  let result = parse(source)
  let output = serialize(result.document)
  // Output is normalized to *** for GFM compatibility
  @debug.debug_inspect(output.contains("***"), content="true")
}

///|
test "serialize blockquote" {
  let source = "> Quote\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output,
    content=(
      #|"> Quote\n"
    ),
  )
}

///|
test "serialize bullet list" {
  let source = "- Item 1\n- Item 2\n"
  let result = parse(source)
  let output = serialize(result.document)
  // Output is normalized to - for stable editor/source rendering.
  @debug.debug_inspect(
    output,
    content=(
      #|"- Item 1\n- Item 2\n"
    ),
  )
}

///|
test "serialize bullet list normalizes asterisk to dash" {
  let source = "* Item 1\n* Item 2\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output,
    content=(
      #|"- Item 1\n- Item 2\n"
    ),
  )
}

///|
test "serialize frontmatter roundtrip" {
  let source = "---\ntitle: Hello\n---\n# Content\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(
    output.has_prefix("---\ntitle: Hello\n---\n"),
    content="true",
  )
}

///|
test "serialize mixed content" {
  let source = "# Title\n\nParagraph.\n\n```js\ncode\n```\n"
  let result = parse(source)
  let output = serialize(result.document)
  // Verify key parts are present
  @debug.debug_inspect(output.contains("# Title"), content="true")
  @debug.debug_inspect(output.contains("Paragraph"), content="true")
  @debug.debug_inspect(output.contains("```js"), content="true")
  @debug.debug_inspect(output.contains("code"), content="true")
}

///|
test "serialize link title with a quote" {
  // Titles are stored unescaped, so serializing has to escape them again.
  let source = "[x](/u \"a\\\"b\")\n"
  let output = serialize(parse(source).document)
  @debug.debug_inspect(
    output,
    content=(
      #|"[x](/u \"a\\\"b\")\n"
    ),
  )
  // And the result parses back to the same title.
  guard parse(output).document.children[0] is Block::Paragraph(children~, ..) else {
    fail("Expected Paragraph")
  }
  guard children[0] is Inline::Link(title~, ..) else { fail("Expected Link") }
  @debug.debug_inspect(
    title,
    content=(
      #|"a\"b"
    ),
  )
}

///|
/// GFM strips `\|` from a cell before the inline parser runs, so every pipe
/// the cell's content carries has to be written back escaped — including the
/// ones nested inside code spans, emphasis and links (GFM example 200).
/// Otherwise the serialized row splits into extra cells when re-parsed.
test "serialize: table cells re-escape pipes nested in inline elements" {
  let source =
    #|| f\|oo |
    #|| --- |
    #|| b `\|` az |
    #|| b **\|** im |
    #|| [a \| b](x) |
    #|
  let output = serialize(parse(source).document)
  @debug.debug_inspect(
    output,
    content=(
      #|"| f\\|oo |\n| --- |\n| b `\\|` az |\n| b **\\|** im |\n| [a \\| b](x) |\n"
    ),
  )
  // Re-parsing the serialized table has to give the same HTML back.
  @debug.debug_inspect(md_to_html(output) == md_to_html(source), content="true")
}

///|
/// A backslash that is itself literal content stays doubled, and the pipe
/// behind it still gets its own escape.
test "serialize: table cell keeps a literal backslash before a pipe" {
  let source = "| a |\n| --- |\n| x \\\\\\| y |\n"
  let output = serialize(parse(source).document)
  @debug.debug_inspect(md_to_html(output) == md_to_html(source), content="true")
}
