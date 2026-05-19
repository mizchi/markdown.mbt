///|
/// Serializer tests
test "serialize heading" {
  let source = "# Hello World\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output, content=(
    #|"# Hello World\n"
  ))
}

///|
test "serialize heading with closing hashes" {
  let source = "## Title ##\n"
  let result = parse(source)
  let output = serialize(result.document)
  // GFM style: closing hashes are removed
  @debug.debug_inspect(output, content=(
    #|"## Title\n"
  ))
}

///|
test "serialize paragraph" {
  let source = "Hello world.\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output, content=(
    #|"Hello world.\n"
  ))
}

///|
test "serialize fenced code" {
  let source = "```js\nconsole.log('hello');\n```\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output, content=(
    #|"```js\nconsole.log('hello');\n```\n"
  ))
}

///|
test "serialize fenced code with tilde" {
  let source = "~~~python\nprint('hello')\n~~~\n"
  let result = parse(source)
  let output = serialize(result.document)
  // GFM style: tilde fences are converted to backtick fences
  @debug.debug_inspect(output, content=(
    #|"```python\nprint('hello')\n```\n"
  ))
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
  @debug.debug_inspect(output, content=(
    #|"> Quote\n"
  ))
}

///|
test "serialize bullet list" {
  let source = "- Item 1\n- Item 2\n"
  let result = parse(source)
  let output = serialize(result.document)
  // Output is normalized to * for GFM compatibility
  @debug.debug_inspect(output, content=(
    #|"* Item 1\n* Item 2\n"
  ))
}

///|
test "serialize frontmatter roundtrip" {
  let source = "---\ntitle: Hello\n---\n# Content\n"
  let result = parse(source)
  let output = serialize(result.document)
  @debug.debug_inspect(output.has_prefix("---\ntitle: Hello\n---\n"), content="true")
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
