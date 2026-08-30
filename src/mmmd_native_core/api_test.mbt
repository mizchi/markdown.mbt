///|
test "native mmmd: renders Markdown as HTML" {
  inspect(render("# Hello\n", Html), content="<h1>Hello</h1>\n")
}

///|
test "native mmmd: Mermaid falls back to an ordinary fenced code block" {
  let output = render(
    "```mermaid\ngraph TD\n  Start --> Finish\n```\n",
    Tui,
  )
  inspect(output.contains("```mermaid"), content="true")
  inspect(output.contains("graph TD"), content="true")
  inspect(output.contains("Start --> Finish"), content="true")
}
