///|
/// Tests for the source-preserving (literal) HTML renderer.

///|
/// The key invariant: stripping HTML tags + decoding the basic character
/// references (`&amp; &lt; &gt; &quot;`) from `render_html_literal(doc)`
/// must yield exactly `serialize(doc)`. This is what makes the rendered
/// output overlay-able with a syntax-highlighted source view under
/// monospace + `white-space: pre-wrap`.

///|
/// Strip HTML tags and decode the basic XML character references.
/// Mirrors what a browser's text-rendering engine would emit (visible
/// characters only) under `white-space: pre-wrap`.
fn strip_html(html : String) -> String {
  let buf = StringBuilder::new()
  let len = html.length()
  let mut i = 0
  while i < len {
    let c = html.get_char(i)
    match c {
      Some('<') => {
        // Skip everything up to and including the matching `>`.
        let mut j = i + 1
        while j < len {
          match html.get_char(j) {
            Some('>') => {
              j += 1
              break
            }
            _ => j += 1
          }
        }
        i = j
      }
      Some('&') => {
        // Decode &amp; &lt; &gt; &quot; &#39;
        let starts_with = fn(prefix : String) -> Bool {
          let n = prefix.length()
          i + n <= len && html.unsafe_substring(start=i, end=i + n) == prefix
        }
        if starts_with("&amp;") {
          buf.write_char('&')
          i += 5
        } else if starts_with("&lt;") {
          buf.write_char('<')
          i += 4
        } else if starts_with("&gt;") {
          buf.write_char('>')
          i += 4
        } else if starts_with("&quot;") {
          buf.write_char('"')
          i += 6
        } else if starts_with("&#39;") {
          buf.write_char('\'')
          i += 5
        } else {
          buf.write_char('&')
          i += 1
        }
      }
      Some(ch) => {
        buf.write_char(ch)
        i += 1
      }
      None => i += 1
    }
  }
  buf.to_string()
}

///|
/// Assert that `strip_html(render_html_literal(parse(src))) == serialize(parse(src))`.
fn assert_overlay_invariant(src : String) -> Unit raise {
  let doc = parse(src).document
  let expected = serialize(doc)
  let rendered = render_html_literal(doc)
  let stripped = strip_html(rendered)
  assert_eq(stripped, expected)
}

// =============================================================================
// Snapshot tests for HTML output
// =============================================================================

///|
test "literal: paragraph plain text" {
  let html = md_to_html_literal("hello world\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>hello world</p>\n"
    ),
  )
}

///|
test "literal: heading atx" {
  let html = md_to_html_literal("## Intro\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<h2><span class=\"md-marker\" aria-hidden=\"true\">## </span>Intro</h2>\n"
    ),
  )
}

///|
test "literal: emphasis and strong" {
  let html = md_to_html_literal("*em* and **strong**\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><em><span class=\"md-marker\" aria-hidden=\"true\">*</span>em<span class=\"md-marker\" aria-hidden=\"true\">*</span></em> and <strong><span class=\"md-marker\" aria-hidden=\"true\">**</span>strong<span class=\"md-marker\" aria-hidden=\"true\">**</span></strong></p>\n"
    ),
  )
}

///|
test "literal: inline code" {
  let html = md_to_html_literal("hello `code` world\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>hello <code><span class=\"md-marker\" aria-hidden=\"true\">`</span>code<span class=\"md-marker\" aria-hidden=\"true\">`</span></code> world</p>\n"
    ),
  )
}

///|
test "literal: preserves no-blank-line transition between blocks" {
  let html = md_to_html_literal("# Title\nbody\n")
  assert_eq(strip_html(html), "# Title\nbody\n")
}

///|
test "literal: preserves multiple blank lines between blocks" {
  let html = md_to_html_literal("# Title\n\n\nbody\n")
  assert_eq(strip_html(html), "# Title\n\n\nbody\n")
}

///|
test "literal: preserves leading and trailing blank lines" {
  let html = md_to_html_literal("\n# Title\n\n")
  assert_eq(strip_html(html), "\n# Title\n\n")
}

///|
test "literal: preserves blank line after list before next block" {
  let html = md_to_html_literal("- one\n- two\n\n> quote\n")
  assert_eq(strip_html(html), "- one\n- two\n\n> quote\n")
}

///|
test "literal: bullet list" {
  let html = md_to_html_literal("- one\n- two\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<ul><li><span class=\"md-marker\" aria-hidden=\"true\">- </span>one\n</li><li><span class=\"md-marker\" aria-hidden=\"true\">- </span>two\n</li></ul>"
    ),
  )
}

///|
test "literal: bullet list normalizes asterisk to dash" {
  let html = md_to_html_literal("* one\n* two\n")
  assert_eq(strip_html(html), "- one\n- two\n")
}

///|
test "literal: link" {
  let html = md_to_html_literal("see [docs](https://example.com)\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p>see <a href=\"https://example.com\"><span class=\"md-marker\" aria-hidden=\"true\">[</span>docs<span class=\"md-marker\" aria-hidden=\"true\">](https://example.com)</span></a></p>\n"
    ),
  )
}

///|
test "literal: autolink" {
  let html = md_to_html_literal("<https://example.com>\n")
  @debug.debug_inspect(
    html,
    content=(
      #|"<p><a href=\"https://example.com\"><span class=\"md-marker\" aria-hidden=\"true\">&lt;</span>https://example.com<span class=\"md-marker\" aria-hidden=\"true\">&gt;</span></a></p>\n"
    ),
  )
}

// =============================================================================
// Invariant tests: stripped HTML == serialize(doc)
// =============================================================================

///|
test "invariant: paragraph" {
  assert_overlay_invariant("hello world\n")
}

///|
test "invariant: heading levels" {
  assert_overlay_invariant("# h1\n\n## h2\n\n### h3\n")
}

///|
test "invariant: emphasis strong code" {
  assert_overlay_invariant("*em* **strong** `code`\n")
}

///|
test "invariant: bullet list" {
  assert_overlay_invariant("- one\n- two\n- three\n")
}

///|
test "invariant: ordered list" {
  assert_overlay_invariant("1. one\n2. two\n3. three\n")
}

///|
test "invariant: nested bullet list" {
  assert_overlay_invariant("- outer\n  - inner\n")
}

///|
test "invariant: link" {
  assert_overlay_invariant("see [docs](https://example.com)\n")
}

///|
test "invariant: autolink" {
  assert_overlay_invariant("<https://example.com>\n")
}

///|
test "invariant: fenced code" {
  assert_overlay_invariant("```rust\nfn main() {}\n```\n")
}

///|
test "invariant: blockquote single paragraph" {
  assert_overlay_invariant("> quote text\n")
}

///|
test "invariant: blockquote multi-line" {
  assert_overlay_invariant("> line one\n> line two\n")
}

///|
test "invariant: thematic break" {
  assert_overlay_invariant("***\n")
}

///|
test "invariant: mixed document" {
  let src =
    #|# Title
    #|
    #|A paragraph with *em*, **strong**, and `code`.
    #|
    #|- bullet one
    #|- bullet two
    #|
    #|> a quote
    #|
    #|See <https://example.com> for details.
    #|
  assert_overlay_invariant(src)
}

// =============================================================================
// Extended pattern coverage
// =============================================================================

///|
test "invariant: heading all levels" {
  assert_overlay_invariant(
    "# h1\n\n## h2\n\n### h3\n\n#### h4\n\n##### h5\n\n###### h6\n",
  )
}

///|
test "invariant: setext heading" {
  assert_overlay_invariant("Title\n===\n")
}

///|
test "invariant: setext heading level 2" {
  assert_overlay_invariant("Subtitle\n---\n")
}

///|
test "invariant: hard break backslash" {
  assert_overlay_invariant("one\\\ntwo\n")
}

///|
test "invariant: link with title" {
  assert_overlay_invariant("[label](https://example.com \"a title\")\n")
}

///|
test "invariant: image without title" {
  assert_overlay_invariant("![alt text](pic.png)\n")
}

///|
test "invariant: image with title" {
  assert_overlay_invariant("![alt](pic.png \"caption\")\n")
}

///|
test "invariant: reference link" {
  let html = md_to_html_literal("[ref][label]\n\n[label]: https://example.com\n")
  assert_eq(strip_html(html), "[ref][label]\n\n")
}

///|
test "invariant: reference image" {
  let html = md_to_html_literal("![alt][label]\n\n[label]: pic.png\n")
  assert_eq(strip_html(html), "![alt][label]\n\n")
}

///|
test "invariant: autolink email" {
  assert_overlay_invariant("<mail@example.com>\n")
}

///|
test "invariant: code span with backtick inside" {
  assert_overlay_invariant("``code with ` inside``\n")
}

///|
test "invariant: strikethrough" {
  assert_overlay_invariant("~~struck~~ text\n")
}

///|
test "invariant: task list" {
  assert_overlay_invariant("- [x] done\n- [ ] pending\n")
}

///|
test "invariant: nested ordered in bullet" {
  let html = md_to_html_literal("- outer\n  1. inner ordered\n  2. another\n")
  assert_eq(strip_html(html), "- outer\n1. inner ordered\n2. another\n")
}

///|
test "invariant: thematic break dashes" {
  assert_overlay_invariant("***\n")
}

///|
test "invariant: indented code block" {
  assert_overlay_invariant("    fn main() {}\n    return 0\n")
}

///|
test "invariant: fenced code without language" {
  assert_overlay_invariant("```\nplain code\n```\n")
}

///|
test "invariant: fenced code with content containing backticks" {
  assert_overlay_invariant("```\nhas ``` triple backticks inside\n```\n")
}

///|
test "invariant: gfm table left align" {
  assert_overlay_invariant("| a | b |\n| :-- | --: |\n| 1 | 2 |\n")
}

///|
test "invariant: gfm table center align" {
  assert_overlay_invariant("| a | b |\n| :-: | --- |\n| x | y |\n")
}

///|
test "invariant: html block" {
  assert_overlay_invariant("<div>raw html</div>\n")
}

///|
test "invariant: html inline" {
  assert_overlay_invariant("a <span>raw</span> b\n")
}

///|
test "invariant: footnote reference + definition" {
  assert_overlay_invariant("Look here[^1].\n\n[^1]: aside\n")
}

///|
test "invariant: deeply nested lists" {
  assert_overlay_invariant("- a\n  - b\n    - c\n")
}

///|
test "invariant: ordered list with different start" {
  assert_overlay_invariant("3. three\n4. four\n5. five\n")
}

///|
test "invariant: blockquote with heading" {
  assert_overlay_invariant("> # H1 inside\n> body\n")
}

///|
test "invariant: paragraph spanning multiple lines" {
  assert_overlay_invariant("line one\nline two\nline three\n")
}

///|
test "invariant: empty document" {
  assert_overlay_invariant("")
}

// =============================================================================
// Source-position attribute tests
// =============================================================================

///|
test "positions: heading data-src spans the source range" {
  let html = md_to_html_literal("## Intro\n", positions=true)
  @debug.debug_inspect(html.contains("data-src-start=\"0\""), content="true")
  @debug.debug_inspect(html.contains("data-src-end=\"9\""), content="true")
}

///|
test "positions: default omits data-src attributes" {
  let html = md_to_html_literal("## Intro\n")
  @debug.debug_inspect(html.contains("data-src-start"), content="false")
}

///|
test "positions: inline elements are NOT annotated" {
  let html = md_to_html_literal("a **bold** b\n", positions=true)
  @debug.debug_inspect(html.contains("<strong data-src"), content="false")
  @debug.debug_inspect(html.contains("<em data-src"), content="false")
  @debug.debug_inspect(html.contains("<code data-src"), content="false")
}

///|
/// Walk the rendered HTML and verify that every block-level
/// `data-src-start` attribute equals the visible-text offset of that
/// tag's open position. This is the invariant the editor's
/// click-to-cursor mapping relies on.
fn assert_block_positions(src : String) -> Unit raise {
  let doc = parse(src).document
  let html = render_html_literal(doc, positions=true)
  let len = html.length()
  let mut i = 0
  let mut visible_offset = 0
  while i < len {
    match html.get_char(i) {
      Some('<') => {
        let tag_start = i
        let mut j = i + 1
        while j < len && html.get_char(j) != Some('>') {
          j += 1
        }
        let tag = html.unsafe_substring(start=tag_start, end=j + 1)
        let needle = "data-src-start=\""
        match tag.find(needle) {
          Some(pos) => {
            let val_start = pos + needle.length()
            let mut k = val_start
            while k < tag.length() && tag.get_char(k) != Some('"') {
              k += 1
            }
            let val_str = tag.unsafe_substring(start=val_start, end=k)
            let mut val = 0
            for ch in val_str {
              val = val * 10 + (ch.to_int() - '0'.to_int())
            }
            assert_eq(val, visible_offset)
          }
          None => ()
        }
        i = j + 1
      }
      Some('&') =>
        if i + 4 <= len && html.unsafe_substring(start=i, end=i + 4) == "&lt;" {
          visible_offset += 1
          i += 4
        } else if i + 4 <= len &&
          html.unsafe_substring(start=i, end=i + 4) == "&gt;" {
          visible_offset += 1
          i += 4
        } else if i + 5 <= len &&
          html.unsafe_substring(start=i, end=i + 5) == "&amp;" {
          visible_offset += 1
          i += 5
        } else if i + 6 <= len &&
          html.unsafe_substring(start=i, end=i + 6) == "&quot;" {
          visible_offset += 1
          i += 6
        } else if i + 5 <= len &&
          html.unsafe_substring(start=i, end=i + 5) == "&#39;" {
          visible_offset += 1
          i += 5
        } else {
          visible_offset += 1
          i += 1
        }
      _ => {
        visible_offset += 1
        i += 1
      }
    }
  }
}

///|
test "positions: single heading block position matches source" {
  assert_block_positions("## Intro\n")
}

///|
test "positions: multi-block positions match source" {
  assert_block_positions("# H1\n\n## H2\n\nbody paragraph\n")
}

///|
test "positions: list item positions" {
  assert_block_positions("- one\n- two\n- three\n")
}

///|
test "positions: blockquote with nested heading" {
  assert_block_positions("> # H1 inside\n> body\n")
}

// =============================================================================
// Image preview opt-in
// =============================================================================

///|
test "image preview: opt-in emits an <img> alongside source chars" {
  let html = md_to_html_literal("look ![cat](/img/cat.png)\n", image_preview=true)
  // The wrapper span contains both the <img> preview and the source chars.
  @debug.debug_inspect(
    html.contains("<img class=\"md-image-preview\""),
    content="true",
  )
  @debug.debug_inspect(html.contains("src=\"/img/cat.png\""), content="true")
  @debug.debug_inspect(html.contains("alt=\"cat\""), content="true")
  // The source characters `![cat](/img/cat.png)` are still in the output.
  @debug.debug_inspect(
    html.contains("![") && html.contains("](/img/cat.png)"),
    content="true",
  )
}

///|
test "image preview: alt :wN emits atomic width metadata and clean img alt" {
  let html = md_to_html_literal("look ![cat:w500](/img/cat.png)\n", image_preview=true)
  @debug.debug_inspect(
    html.contains("class=\"md-image-preview-slot\""),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("data-md-noneditable=\"true\""),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("contenteditable=\"false\""),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("data-md-image-width=\"500\""),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("--md-literal-image-width:500px"),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("role=\"img\" aria-label=\"cat\""),
    content="true",
  )
  @debug.debug_inspect(html.contains("alt=\"cat\""), content="true")
  @debug.debug_inspect(html.contains("![") && html.contains("cat:w500"), content="true")
}

///|
test "image preview: default does not emit <img>" {
  let html = md_to_html_literal("![cat](/img/cat.png)\n")
  @debug.debug_inspect(
    html.contains("<img class=\"md-image-preview\""),
    content="false",
  )
}

///|
test "image preview: preserves overlay invariant" {
  // The <img> carries no visible text, so stripped HTML must still equal
  // the serializer output.
  let src = "![logo](https://example.com/logo.png \"title\")\n"
  let doc = parse(src).document
  let html = render_html_literal(doc, image_preview=true)
  let stripped = strip_html(html)
  assert_eq(stripped, serialize(doc))
}

///|
test "image preview: invariant holds with title" {
  let src = "look ![cat](/cat.png \"a cat\") here\n"
  let doc = parse(src).document
  assert_eq(
    strip_html(render_html_literal(doc, image_preview=true)),
    serialize(doc),
  )
}

///|
test "image preview: invariant holds with multiple images in one paragraph" {
  let src = "![one](/1.png) and ![two](/2.png)\n"
  let doc = parse(src).document
  assert_eq(
    strip_html(render_html_literal(doc, image_preview=true)),
    serialize(doc),
  )
}

///|
test "image preview: reference image emits data-md-image-ref slot" {
  let src = "![logo][L]\n\n[L]: /logo.png\n"
  let html = md_to_html_literal(src, image_preview=true)
  // RefImage slot is emitted without a resolved src; the consumer's JS
  // looks up [L] in the document's link definitions and fills it in.
  @debug.debug_inspect(html.contains("data-md-image-ref=\"L\""), content="true")
  @debug.debug_inspect(html.contains("src="), content="false")
}

///|
test "image preview: reference image supports alt width directive" {
  let src = "![logo:w320][L]\n\n[L]: /logo.png\n"
  let html = md_to_html_literal(src, image_preview=true)
  @debug.debug_inspect(
    html.contains("data-md-image-width=\"320\""),
    content="true",
  )
  @debug.debug_inspect(html.contains("alt=\"logo\""), content="true")
  @debug.debug_inspect(html.contains("logo:w320"), content="true")
}

///|
test "image preview: standalone image markdown emits block preview" {
  let src = "![cat](https://example.com/cat.png)\nnext line\n"
  let html = md_to_html_literal(src, image_preview=true)
  @debug.debug_inspect(
    html.contains("md-image-preview-block"),
    content="true",
  )
  @debug.debug_inspect(
    html.contains("src=\"https://example.com/cat.png\""),
    content="true",
  )
  assert_eq(strip_html(html), src)
}

///|
test "image preview: standalone bare image URL does not emit block preview" {
  let html = md_to_html_literal("https://example.com/cat.png\n", image_preview=true)
  @debug.debug_inspect(
    html.contains("md-image-preview-block"),
    content="false",
  )
}

///|
test "image preview: standalone non-image URL does not emit block preview" {
  let html = md_to_html_literal("https://example.com/page\n", image_preview=true)
  @debug.debug_inspect(
    html.contains("md-image-preview-block"),
    content="false",
  )
}

///|
test "image preview: combines with positions" {
  let html = md_to_html_literal(
    "intro\n\n![hi](/p.png)\n",
    image_preview=true,
    positions=true,
  )
  @debug.debug_inspect(html.contains("data-src-start"), content="true")
  @debug.debug_inspect(html.contains("md-image-preview"), content="true")
}

///|
test "positions: footnote body blocks are NOT annotated with relative offsets" {
  let html = md_to_html_literal("[^1]: body line\n", positions=true)
  // The outer footnote div is annotated — that's the absolute span.
  @debug.debug_inspect(
    html.contains("<div class=\"footnote\" id=\"fn-1\" data-src-start"),
    content="true",
  )
  // The inner <p> must NOT carry data-src-* (it would be relative to
  // the footnote's content scanner, not the document).
  @debug.debug_inspect(html.contains("<p data-src"), content="false")
}
