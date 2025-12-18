///| Debug tests for TUI output - run with `moon test --target js src/tui/check_test.mbt`

test "debug: headings" {
  println("=== Headings ===")
  println(md_to_tui("# Heading 1\n## Heading 2\n### Heading 3\n#### Heading 4\n"))
}

test "debug: text styles" {
  println("=== Text Styles ===")
  println(md_to_tui("Normal text, *italic*, **bold**, ~~strikethrough~~, `code`\n"))
}

test "debug: links and images" {
  println("=== Links and Images ===")
  println(md_to_tui("[Link text](https://example.com)\n\n![Image alt](image.png)\n"))
}

test "debug: bullet list" {
  println("=== Bullet List ===")
  println(md_to_tui("- Item one\n- Item two\n- Item three\n"))
}

test "debug: task list" {
  println("=== Task List ===")
  println(md_to_tui("- [ ] Todo item\n- [x] Done item\n- [ ] Another todo\n"))
}

test "debug: ordered list" {
  println("=== Ordered List ===")
  println(md_to_tui("1. First\n2. Second\n3. Third\n"))
}

test "debug: code block" {
  println("=== Code Block ===")
  println(md_to_tui("```javascript\nconst x = 1;\nconsole.log(x);\n```\n"))
}

test "debug: blockquote" {
  println("=== Blockquote ===")
  println(md_to_tui("> This is a quote\n> with multiple lines\n"))
}

test "debug: table" {
  println("=== Table ===")
  println(md_to_tui("| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |\n"))
}

test "debug: thematic break" {
  println("=== Thematic Break ===")
  println(md_to_tui("Before\n\n---\n\nAfter\n"))
}

test "debug: complex document" {
  println("=== Complex Document ===")
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
    #|    println!("Hello");
    #|}
    #|```
    #|
    #|Visit [our site](https://example.com) for more.
    #|
  println(md_to_tui(doc))
}
