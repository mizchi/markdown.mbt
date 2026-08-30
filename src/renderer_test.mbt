///|
/// HTML Renderer tests
test "render paragraph" {
  let html = md_to_html("Hello, world!\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>Hello, world!</p>\n"
    ),
  )
}

///|
test "render heading" {
  let html = md_to_html("# Title\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<h1>Title</h1>\n"
    ),
  )
}

///|
test "render heading levels" {
  let html = md_to_html("## Level 2\n### Level 3\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<h2>Level 2</h2>\n<h3>Level 3</h3>\n"
    ),
  )
}

///|
test "render emphasis" {
  let html = md_to_html("*italic* and **bold**\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><em>italic</em> and <strong>bold</strong></p>\n"
    ),
  )
}

///|
test "render code" {
  let html = md_to_html("Use `code` here\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>Use <code>code</code> here</p>\n"
    ),
  )
}

///|
test "render fenced code block" {
  let html = md_to_html("```js\nconsole.log('hi');\n```\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<pre><code class=\"language-js\">console.log('hi');\n</code></pre>\n"
    ),
  )
}

///|
test "render link" {
  let html = md_to_html("[click](https://example.com)\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><a href=\"https://example.com\">click</a></p>\n"
    ),
  )
}

///|
test "render link with title" {
  let html = md_to_html("[click](https://example.com \"title\")\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><a href=\"https://example.com\" title=\"title\">click</a></p>\n"
    ),
  )
}

///|
test "render bare URL text as link by default" {
  let html = md_to_html("Read https://example.com/docs.\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>Read <a href=\"https://example.com/docs\">https://example.com/docs</a>.</p>\n"
    ),
  )
  let disabled = md_to_html("Read https://example.com/docs.\n", autolink=false)
  @debug.debug_inspect(
    disabled,
    content=(
      #|"<p>Read https://example.com/docs.</p>\n"
    ),
  )
}

///|
test "render bare URL text with escaped attributes" {
  let html = md_to_html("Open https://example.com/?a=1&b=2\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>Open <a href=\"https://example.com/?a=1&amp;b=2\">https://example.com/?a=1&amp;b=2</a></p>\n"
    ),
  )
}

///|
test "render markdown link label URL without nested autolink" {
  let html = md_to_html("[https://example.com](https://target.example)\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><a href=\"https://target.example\">https://example.com</a></p>\n"
    ),
  )
}

///|
test "render image" {
  let html = md_to_html("![alt](image.png)\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><img src=\"image.png\" alt=\"alt\" /></p>\n"
    ),
  )
}

///|
test "render bullet list" {
  let html = md_to_html("- one\n- two\n- three\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<ul>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ul>\n"
    ),
  )
}

///|
test "render ordered list" {
  let html = md_to_html("1. one\n2. two\n3. three\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<ol>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ol>\n"
    ),
  )
}

///|
test "render blockquote" {
  let html = md_to_html("> quote\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<blockquote>\n<p>quote</p>\n</blockquote>\n"
    ),
  )
}

///|
test "render thematic break" {
  let html = md_to_html("---\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<hr />\n"
    ),
  )
}

///|
test "render task list" {
  let html = md_to_html("- [ ] todo\n- [x] done\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<ul>\n<li><input disabled=\"\" type=\"checkbox\"> todo</li>\n<li><input checked=\"\" disabled=\"\" type=\"checkbox\"> done</li>\n</ul>\n"
    ),
  )
}

///|
test "render table" {
  let html = md_to_html("| a | b |\n|---|---|\n| 1 | 2 |\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n"
    ),
  )
}

///|
test "escape html in text" {
  let html = md_to_html("a < b && c > d\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>a &lt; b &amp;&amp; c &gt; d</p>\n"
    ),
  )
}

///|
test "render html comment block" {
  let html = md_to_html("<!-- comment -->\n\n# Title\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<!-- comment -->\n<h1>Title</h1>\n"
    ),
  )
}

///|
test "render inline html comment" {
  let html = md_to_html("a <!-- note --> b\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>a <!-- note --> b</p>\n"
    ),
  )
}

///|
test "render footnote" {
  let html = md_to_html(
    "First[^note], again[^note].\n\n[^note]: Footnote body.\n",
  )
  inspect(html.contains("id=\"fnref-note\""), content="true")
  inspect(html.contains("id=\"fnref-note-2\""), content="true")
  inspect(html.contains(">1</a></sup>"), content="true")
  inspect(
    html.contains("<section data-footnotes=\"\" class=\"footnotes\">"),
    content="true",
  )
  inspect(html.contains("<li id=\"fn-note\">"), content="true")
  inspect(html.contains("href=\"#fnref-note-2\""), content="true")
  inspect(html.has_suffix("</section>\n"), content="true")
}

///|
test "render: superscript letters are not punctuation for flanking" {
  // U+2071 is a modifier letter, so the underscore stays intraword.
  let html = md_to_html("a\u{2071}_b_\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>aⁱ_b_</p>\n"
    ),
  )
}

///|
test "render: Latin Extended-A labels fold to their own case pair" {
  // U+013A is lowercase; it must not match U+013B.
  let mismatched = md_to_html("[\u{13a}]\n\n[\u{13b}]: /wrong\n")
  @debug.debug_inspect(
    mismatched,
    content=(
      #|"<p>[ĺ]</p>\n"
    ),
  )
  let matched = md_to_html("[\u{139}]\n\n[\u{13a}]: /right\n")
  @debug.debug_inspect(
    matched,
    content=(
      #|"<p><a href=\"/right\">Ĺ</a></p>\n"
    ),
  )
}

//|

///|
test "render: raw text HTML block ends at its own closing tag" {
  // </pre> must not close a <script> block.
  let html = md_to_html("<script>\n</pre>\nstill script\n</script>\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"&lt;script>\n</pre>\nstill script\n&lt;/script>\n"
    ),
  )
}

///|
test "render can disable GFM tagfilter for CommonMark HTML" {
  inspect(
    md_to_html("<script>raw</script>\n", autolink=false, tagfilter=false),
    content="<script>raw</script>\n",
  )
}

///|
test "render GitHub alert" {
  inspect(
    md_to_html("> [!WARNING]\n> Dangerous operation.\n"),
    content="<div class=\"markdown-alert markdown-alert-warning\">\n<p class=\"markdown-alert-title\">Warning</p>\n<p>Dangerous operation.</p>\n</div>\n",
  )
}

///|
test "render display math with safe fallback" {
  inspect(
    md_to_html("$$\nx < y && y > 0\n$$\n"),
    content="<pre class=\"math math-display\"><code>x &lt; y &amp;&amp; y &gt; 0\n</code></pre>\n",
  )
}

///|
test "render display math through an injected renderer" {
  let doc = parse("$$\nx^2\n$$\n").document
  let options = RenderOptions::default().with_math_block_renderer(fn(value) {
    "<div data-katex>" + value.trim(chars="\n").to_owned() + "</div>"
  })
  inspect(
    render_html_with_options(doc, options),
    content="<div data-katex>x^2</div>\n",
  )
}

///|
test "render fenced directive with a neutral HTML contract" {
  inspect(
    md_to_html(":::note Optional title\nBody\n:::\n"),
    content="<div class=\"directive directive-note\" data-directive=\"note\" data-directive-meta=\"Optional title\">\n<p>Body</p>\n</div>\n",
  )
}

///|
test "render definition list" {
  inspect(
    md_to_html("MoonBit\n: A **fast** language\n"),
    content="<dl>\n<dt>MoonBit</dt>\n<dd>A <strong>fast</strong> language</dd>\n</dl>\n",
  )
}

///|
test "render block attributes on a heading" {
  inspect(
    md_to_html("# Heading\n\n{#intro .wide key=value}\n"),
    content="<h1 id=\"intro\" class=\"wide\" key=\"value\">Heading</h1>\n",
  )
}

///|
test "render inline directive" {
  inspect(
    md_to_html("Use :badge[stable]{.green level=high}.\n"),
    content="<p>Use <span data-directive=\"badge\" class=\"green\" level=\"high\">stable</span>.</p>\n",
  )
}

///|
test "render: delimiter row cells need a dash" {
  let html = md_to_html("a | b\n--- | :\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>a | b\n--- | :</p>\n"
    ),
  )
}

///|
test "render: a line without a cell separator continues the table" {
  let html = md_to_html("a | b\n--- | ---\nordinary text\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>ordinary text</td>\n<td></td>\n</tr>\n</tbody>\n</table>\n"
    ),
  )
}

///|
test "render: a new block ends a table without a blank line" {
  let html = md_to_html("a | b\n--- | ---\n# heading\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n</table>\n<h1>heading</h1>\n"
    ),
  )
}
