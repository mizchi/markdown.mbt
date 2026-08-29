///|
/// TUI Renderer tests
test "tui: paragraph" {
  let output = md_to_tui("Hello, world!\n")
  inspect(output.contains("Hello, world!"), content="true")
}

///|
test "tui: heading" {
  let output = md_to_tui("# Title\n")
  inspect(output.contains("# Title"), content="true")
  inspect(output.contains("\u001b[1m"), content="true") // bold
}

///|
test "tui: emphasis" {
  let output = md_to_tui("*italic*\n")
  inspect(output.contains("\u001b[3m"), content="true") // italic
}

///|
test "tui: strong" {
  let output = md_to_tui("**bold**\n")
  inspect(output.contains("\u001b[1m"), content="true") // bold
}

///|
test "tui: code" {
  let output = md_to_tui("`code`\n")
  inspect(output.contains("`code`"), content="true")
  inspect(output.contains("\u001b[36m"), content="true") // cyan
}

///|
test "tui: link" {
  let output = md_to_tui("[text](url)\n")
  inspect(output.contains("text"), content="true")
  inspect(output.contains("(url)"), content="true")
  inspect(output.contains("\u001b[4m"), content="true") // underline
}

///|
test "tui: bullet list" {
  let output = md_to_tui("- one\n- two\n")
  inspect(output.contains("•"), content="true")
  inspect(output.contains("one"), content="true")
}

///|
test "tui: task list" {
  let output = md_to_tui("- [ ] todo\n- [x] done\n")
  inspect(output.contains("☐"), content="true")
  inspect(output.contains("☑"), content="true")
}

///|
test "tui: fenced code" {
  let output = md_to_tui("```js\ncode\n```\n")
  inspect(output.contains("js"), content="true")
  inspect(output.contains("code"), content="true")
  inspect(output.contains("┌"), content="true")
  inspect(output.contains("└"), content="true")
}

///|
test "tui: mermaid fenced code renders as an ASCII diagram" {
  let output = md_to_tui("```mermaid\ngraph TD\n  Start --> Finish\n```\n")
  inspect(output.contains("Start"), content="true")
  inspect(output.contains("Finish"), content="true")
  inspect(output.contains("┌"), content="true")
  inspect(output.contains("graph TD"), content="false")
}

///|
test "tui: thematic break" {
  let output = md_to_tui("---\n")
  inspect(output.contains("─"), content="true")
}

///|
test "tui: blockquote" {
  let output = md_to_tui("> quote\n")
  inspect(output.contains("│"), content="true")
  inspect(output.contains("quote"), content="true")
}

///|
test "tui: table" {
  let output = md_to_tui("| a | b |\n|---|---|\n| 1 | 2 |\n")
  inspect(output.contains("│"), content="true")
  inspect(output.contains("a"), content="true")
}

///|
test "tui: strikethrough" {
  let output = md_to_tui("~~deleted~~\n")
  inspect(output.contains("\u001b[9m"), content="true") // strikethrough
}

///|
test "tui: image" {
  let output = md_to_tui("![alt](url)\n")
  inspect(output.contains("🖼"), content="true")
  inspect(output.contains("alt"), content="true")
}
