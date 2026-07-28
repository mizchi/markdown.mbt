///|
test "mmmd: renders Markdown as HTML" {
  let output = render("# Hello\n", OutputFormat::Html)
  inspect(output, content="<h1>Hello</h1>\n")
}

///|
test "mmmd: renders Mermaid fenced blocks in the TUI" {
  let output = render(
    "```mermaid\ngraph TD\n  Start --> Finish\n```\n",
    OutputFormat::Tui,
  )
  inspect(output.contains("Start"), content="true")
  inspect(output.contains("Finish"), content="true")
  inspect(output.contains("┌"), content="true")
  inspect(output.contains("graph TD"), content="false")
}
