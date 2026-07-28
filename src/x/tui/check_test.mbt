///|
/// Debug tests for TUI output - run with `moon test --target js src/tui/check_test.mbt`
const DEBUG : Bool = true

///|
fn debug_println(input : String) -> Unit {
  if DEBUG {
    println(md_to_tui(input))
  }
}

///|
test "debug: headings" {
  debug_println("=== Headings ===")
  debug_println(
    md_to_tui("# Heading 1\n## Heading 2\n### Heading 3\n#### Heading 4\n"),
  )
}

///|
test "debug: text styles" {
  debug_println("=== Text Styles ===")
  debug_println(
    md_to_tui("Normal text, *italic*, **bold**, ~~strikethrough~~, `code`\n"),
  )
}

///|
test "debug: links and images" {
  debug_println("=== Links and Images ===")
  debug_println(
    md_to_tui("[Link text](https://example.com)\n\n![Image alt](image.png)\n"),
  )
}

///|
test "debug: bullet list" {
  debug_println("=== Bullet List ===")
  debug_println(md_to_tui("- Item one\n- Item two\n- Item three\n"))
}

///|
test "debug: task list" {
  debug_println("=== Task List ===")
  debug_println(
    md_to_tui("- [ ] Todo item\n- [x] Done item\n- [ ] Another todo\n"),
  )
}

///|
test "debug: ordered list" {
  debug_println("=== Ordered List ===")
  debug_println(md_to_tui("1. First\n2. Second\n3. Third\n"))
}

///|
test "debug: code block" {
  debug_println("=== Code Block ===")
  debug_println(
    md_to_tui("```javascript\nconst x = 1;\nconsole.log(x);\n```\n"),
  )
}

///|
test "debug: blockquote" {
  debug_println("=== Blockquote ===")
  debug_println(md_to_tui("> This is a quote\n> with multiple lines\n"))
}

///|
test "debug: table" {
  debug_println("=== Table ===")
  debug_println(
    md_to_tui("| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |\n"),
  )
}

///|
test "debug: thematic break" {
  debug_println("=== Thematic Break ===")
  debug_println(md_to_tui("Before\n\n---\n\nAfter\n"))
}

///|
test "debug: complex document" {
  debug_println("=== Complex Document ===")
  let doc =
    #|# Welcome
    #|
    #|This is a **complex** document with *various* elements.
    #|
    #|## Features
    #|
    #|- Bullet points
    #|- With `inline code`
    #|
    #|### Task List
    #|
    #|- [x] Completed task
    #|- [ ] Pending task
    #|
    #|> A blockquote for emphasis
    #|
    #|```rust
    #|fn main() {
    #|    debug_println!("Hello");
    #|}
    #|```
    #|
    #|Visit [our site](https://example.com) for more.
    #|
  debug_println(md_to_tui(doc))
}
