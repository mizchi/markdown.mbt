///|
/// HTML Renderer tests
test "render paragraph" {
  let html = md_to_html("Hello, world!\n")
  inspect(html, content="<p>Hello, world!</p>\n")
}

///|
test "render heading" {
  let html = md_to_html("# Title\n")
  inspect(html, content="<h1>Title</h1>\n")
}

///|
test "render heading levels" {
  let html = md_to_html("## Level 2\n### Level 3\n")
  inspect(html, content="<h2>Level 2</h2>\n<h3>Level 3</h3>\n")
}

///|
test "render emphasis" {
  let html = md_to_html("*italic* and **bold**\n")
  inspect(html, content="<p><em>italic</em> and <strong>bold</strong></p>\n")
}

///|
test "render code" {
  let html = md_to_html("Use `code` here\n")
  inspect(html, content="<p>Use <code>code</code> here</p>\n")
}

///|
test "render fenced code block" {
  let html = md_to_html("```js\nconsole.log('hi');\n```\n")
  inspect(
    html,
    content="<pre><code class=\"language-js\">console.log('hi');\n</code></pre>\n",
  )
}

///|
test "render link" {
  let html = md_to_html("[click](https://example.com)\n")
  inspect(html, content="<p><a href=\"https://example.com\">click</a></p>\n")
}

///|
test "render link with title" {
  let html = md_to_html("[click](https://example.com \"title\")\n")
  inspect(
    html,
    content="<p><a href=\"https://example.com\" title=\"title\">click</a></p>\n",
  )
}

///|
test "render image" {
  let html = md_to_html("![alt](image.png)\n")
  inspect(html, content="<p><img src=\"image.png\" alt=\"alt\"></p>\n")
}

///|
test "render bullet list" {
  let html = md_to_html("- one\n- two\n- three\n")
  inspect(
    html,
    content="<ul>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ul>\n",
  )
}

///|
test "render ordered list" {
  let html = md_to_html("1. one\n2. two\n3. three\n")
  inspect(
    html,
    content="<ol>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ol>\n",
  )
}

///|
test "render blockquote" {
  let html = md_to_html("> quote\n")
  inspect(html, content="<blockquote>\n<p>quote</p>\n</blockquote>\n")
}

///|
test "render thematic break" {
  let html = md_to_html("---\n")
  inspect(html, content="<hr>\n")
}

///|
test "render task list" {
  let html = md_to_html("- [ ] todo\n- [x] done\n")
  inspect(
    html,
    content="<ul class=\"contains-task-list\">\n<li class=\"task-list-item\"><input type=\"checkbox\" disabled> todo</li>\n<li class=\"task-list-item\"><input type=\"checkbox\" checked disabled> done</li>\n</ul>\n",
  )
}

///|
test "render table" {
  let html = md_to_html("| a | b |\n|---|---|\n| 1 | 2 |\n")
  inspect(
    html,
    content="<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n",
  )
}

///|
test "escape html in text" {
  let html = md_to_html("a < b && c > d\n")
  inspect(html, content="<p>a &lt; b &amp;&amp; c &gt; d</p>\n")
}

///|
test "render html comment block" {
  let html = md_to_html("<!-- comment -->\n\n# Title\n")
  inspect(html, content="<!-- comment -->\n<h1>Title</h1>\n")
}

///|
test "render inline html comment" {
  let html = md_to_html("a <!-- note --> b\n")
  inspect(html, content="<p>a <!-- note --> b</p>\n")
}

///|
test "render footnote" {
  let html = md_to_html("Text[^1]\n\n[^1]: Note\n")
  inspect(html.contains("<sup><a href=\"#fn-1\""), content="true")
  inspect(html.contains("<div class=\"footnote\" id=\"fn-1\">"), content="true")
}
