///| Compatibility tests between this parser and remark

///| Test helper: compare our output with remark's output
fn assert_compat(input : String) -> Unit {
  let our_output = @markdown.md_parse_and_render(input)
  let remark_output = remark_stringify(input)

  // Normalize trailing newlines for comparison
  let our_normalized = our_output.trim_end(chars=" \n\t")
  let remark_normalized = remark_output.trim_end(chars=" \n\t")

  if our_normalized != remark_normalized {
    println("=== Input ===")
    println(input)
    println("=== Our output ===")
    println(our_normalized)
    println("=== Remark output ===")
    println(remark_normalized)
    panic()
  }
}

// =============================================================================
// Basic Tests
// =============================================================================

test "compat: simple paragraph" {
  assert_compat("Hello, world!")
}

test "compat: multiple paragraphs" {
  assert_compat("First paragraph.\n\nSecond paragraph.")
}

test "compat: heading h1" {
  assert_compat("# Heading 1")
}

test "compat: heading h2" {
  assert_compat("## Heading 2")
}

test "compat: heading h3" {
  assert_compat("### Heading 3")
}

// =============================================================================
// Inline Elements
// =============================================================================

test "compat: emphasis asterisk" {
  assert_compat("This is *emphasized* text.")
}

test "compat: emphasis underscore" {
  assert_compat("This is _emphasized_ text.")
}

test "compat: strong asterisk" {
  assert_compat("This is **strong** text.")
}

test "compat: strong underscore" {
  assert_compat("This is __strong__ text.")
}

test "compat: inline code" {
  assert_compat("Use `code` here.")
}

test "compat: link" {
  assert_compat("Visit [example](https://example.com) site.")
}

// =============================================================================
// Code Blocks
// =============================================================================

test "compat: fenced code block" {
  assert_compat("```\ncode here\n```")
}

test "compat: fenced code block with language" {
  assert_compat("```javascript\nconst x = 1;\n```")
}

// =============================================================================
// Lists
// =============================================================================

test "compat: unordered list dash" {
  assert_compat("- item 1\n- item 2\n- item 3")
}

test "compat: unordered list asterisk" {
  assert_compat("* item 1\n* item 2\n* item 3")
}

test "compat: ordered list" {
  assert_compat("1. first\n2. second\n3. third")
}

// =============================================================================
// Block Elements
// =============================================================================

test "compat: blockquote" {
  assert_compat("> This is a quote.")
}

test "compat: thematic break" {
  assert_compat("---")
}

test "compat: horizontal rule asterisk" {
  assert_compat("***")
}
