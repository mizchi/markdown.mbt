///| Source-preserving HTML renderer ("literal" mode).
///|
///| Renders a `Document` to HTML such that the visible text — i.e. the
///| concatenation of all character data once HTML tags are stripped and
///| character references are decoded — equals the lossless serialization
///| of the document (`serialize(doc)`). Markdown markers (`#`, `**`, `_`,
///| `` ` ``, list bullets, fence ticks, blockquote `>`, etc.) are wrapped
///| in `<span class="md-marker" aria-hidden="true">…</span>`.
///|
///| Combined with `font-family: monospace; white-space: pre-wrap;` (and the
///| CSS reset shipped at `@mizchi/markdown/editor/overlay.css`), this lets a
///| consumer overlay the rendered output on top of a syntax-highlighted
///| source view and have every glyph land at the same character grid.
///|
///| Semantic HTML elements (`<h1>` – `<h6>`, `<strong>`, `<em>`, `<code>`,
///| `<a>`, `<ul>` / `<ol>` / `<li>`, `<blockquote>`, `<pre><code>`, …) carry
///| the role for assistive technology; the marker spans are
///| `aria-hidden="true"` so screen readers skip them.
///|
///| When `positions=true` the renderer also emits `data-src-start` /
///| `data-src-end` attributes (character offsets into the original source)
///| on **block-level** elements (`<h1>` – `<h6>`, `<p>`, `<ul>`, `<ol>`,
///| `<li>`, `<blockquote>`, `<pre>`, `<table>`, `<th>` / `<td>`, the
///| thematic-break / fenced-code wrappers, footnote definitions). Inline
///| spans coming from the inline parser are recorded relative to the
///| block's content, not to the document, so they are not directly usable
///| as document offsets and are intentionally omitted.
///|
///| For a "click in the preview → place cursor in the source" editor, walk
///| up the DOM to the nearest ancestor with `data-src-start`. The literal
///| renderer's visible-text invariant guarantees that the offset of a
///| character inside that ancestor's text content equals
///| `data-src-start + that-character's-index-within-the-ancestor`, so
///| `caretRangeFromPoint` plus a quick text-node walk yields the exact
///| source offset.

///|
/// Render a document to HTML using the literal (source-preserving) mode.
pub fn render_html_literal(
  doc : Document,
  positions? : Bool = false,
) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for block in doc.children {
    match block {
      Block::BlankLines(..) => continue
      _ => ()
    }
    if !first {
      buf.write_char('\n')
    }
    first = false
    render_block_literal(block, buf, positions)
  }
  buf.to_string()
}

///|
/// Parse markdown and render with the literal renderer in one step.
pub fn md_to_html_literal(
  source : String,
  wikilinks? : Bool = false,
  positions? : Bool = false,
) -> String {
  let result = parse(source, wikilinks~)
  render_html_literal(result.document, positions~)
}

// =============================================================================
// Helpers
// =============================================================================

///|
/// Emit a marker span carrying the given syntax characters. Visible to
/// sighted users, hidden from assistive technology.
fn write_marker(buf : StringBuilder, text : String) -> Unit {
  if text.is_empty() {
    return
  }
  buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
  buf.write_string(escape_html(text))
  buf.write_string("</span>")
}

///|
/// Compose ` data-src-start="X" data-src-end="Y"` (with a leading space)
/// when `positions=true`. Otherwise an empty string.
fn pos_attrs(span : Span, positions : Bool) -> String {
  if positions {
    " data-src-start=\"" +
    span.from.to_string() +
    "\" data-src-end=\"" +
    span.to.to_string() +
    "\""
  } else {
    ""
  }
}

///|
/// Build a string of `n` copies of `c`.
fn repeat_char(c : Char, n : Int) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < n; i = i + 1 {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Strip a single trailing `\n` from `s`, if present.
fn strip_trailing_newline(s : String) -> String {
  if s.has_suffix("\n") {
    s.unsafe_substring(start=0, end=s.length() - 1)
  } else {
    s
  }
}

///|
/// Prefix every non-empty line of an HTML fragment with a `> ` marker span,
/// re-joining with literal `\n` characters. Drops empty lines (matching the
/// serializer's blockquote behavior).
fn prefix_blockquote_lines(html : String) -> String {
  let stripped = strip_trailing_newline(html)
  let buf = StringBuilder::new()
  for line in stripped.split("\n") {
    let line_str = line.to_owned()
    if !line_str.is_empty() {
      write_marker(buf, "> ")
      buf.write_string(line_str)
      buf.write_char('\n')
    }
  }
  buf.to_string()
}

// =============================================================================
// Block rendering
// =============================================================================

///|
fn render_block_literal(
  block : Block,
  buf : StringBuilder,
  positions : Bool,
) -> Unit {
  match block {
    Block::ThematicBreak(span~, ..) => {
      buf.write_string("<div role=\"separator\"")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      write_marker(buf, "***")
      buf.write_string("</div>\n")
    }
    Block::Heading(level~, style~, children~, span~, ..) =>
      match style {
        HeadingStyle::Atx => {
          buf.write_string("<h")
          buf.write_string(level.to_string())
          buf.write_string(pos_attrs(span, positions))
          buf.write_char('>')
          if !children.is_empty() {
            write_marker(buf, repeat_char('#', level) + " ")
            render_inlines_literal(children, buf, positions)
          } else {
            write_marker(buf, repeat_char('#', level))
          }
          buf.write_string("</h")
          buf.write_string(level.to_string())
          buf.write_string(">\n")
        }
        HeadingStyle::Setext => {
          buf.write_string("<h")
          buf.write_string(level.to_string())
          buf.write_string(pos_attrs(span, positions))
          buf.write_char('>')
          render_inlines_literal(children, buf, positions)
          buf.write_char('\n')
          let underline_char = if level == 1 { '=' } else { '-' }
          write_marker(buf, repeat_char(underline_char, 3))
          buf.write_string("</h")
          buf.write_string(level.to_string())
          buf.write_string(">\n")
        }
      }
    Block::Paragraph(children~, span~, ..) => {
      buf.write_string("<p")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      render_inlines_literal(children, buf, positions)
      buf.write_string("</p>\n")
    }
    Block::FencedCode(info~, code~, span~, ..) => {
      let fence_len = calc_fence_length(code)
      let fence = repeat_char('`', fence_len)
      buf.write_string("<div class=\"md-fenced-code\"")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      write_marker(buf, fence + info)
      buf.write_char('\n')
      if info.is_empty() {
        buf.write_string("<pre><code>")
      } else {
        let parts = info.split(" ").collect()
        let lang = if parts.length() > 0 { parts[0].to_owned() } else { info }
        buf.write_string("<pre><code class=\"language-")
        buf.write_string(escape_html(lang))
        buf.write_string("\">")
      }
      buf.write_string(escape_html(code))
      if !code.is_empty() && !code.has_suffix("\n") {
        buf.write_char('\n')
      }
      buf.write_string("</code></pre>")
      write_marker(buf, fence)
      buf.write_string("</div>\n")
    }
    Block::IndentedCode(code~, span~, ..) => {
      let fence_len = calc_fence_length(code)
      let fence = repeat_char('`', fence_len)
      buf.write_string("<div class=\"md-fenced-code\"")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      write_marker(buf, fence)
      buf.write_char('\n')
      buf.write_string("<pre><code>")
      buf.write_string(escape_html(code))
      if !code.is_empty() && !code.has_suffix("\n") {
        buf.write_char('\n')
      }
      buf.write_string("</code></pre>")
      write_marker(buf, fence)
      buf.write_string("</div>\n")
    }
    Block::Blockquote(children~, span~, ..) => {
      buf.write_string("<blockquote")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      // Children are parsed inside the blockquote and their spans are
      // relative to the blockquote's content, not the document, so don't
      // emit `data-src` on them. The outer <blockquote> annotation is
      // enough — clicks inside it walk up to here.
      for child in children {
        let child_buf = StringBuilder::new()
        render_block_literal(child, child_buf, false)
        buf.write_string(prefix_blockquote_lines(child_buf.to_string()))
      }
      buf.write_string("</blockquote>")
    }
    Block::BulletList(items~, span~, ..) => {
      let has_task = items.iter().any(fn(item) { !(item.checked is None) })
      buf.write_string(if has_task {
        "<ul class=\"contains-task-list\""
      } else {
        "<ul"
      })
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      render_bullet_items_literal(items, buf, 0, positions)
      buf.write_string("</ul>")
    }
    Block::OrderedList(start~, items~, span~, ..) => {
      let has_task = items.iter().any(fn(item) { !(item.checked is None) })
      let open_tag = if has_task { "<ol class=\"contains-task-list\"" } else { "<ol" }
      buf.write_string(open_tag)
      if start != 1 {
        buf.write_string(" start=\"")
        buf.write_string(start.to_string())
        buf.write_char('"')
      }
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      render_ordered_items_literal(items, buf, 0, start, positions)
      buf.write_string("</ol>")
    }
    Block::HtmlBlock(html~, span~, ..) => {
      buf.write_string("<span class=\"md-html-block\"")
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      buf.write_string(escape_html(html))
      buf.write_string("</span>")
      if !html.has_suffix("\n") {
        buf.write_char('\n')
      }
    }
    Block::Table(header~, alignments~, rows~, span~, ..) =>
      render_table_literal(header, alignments, rows, span, buf, positions)
    Block::BlankLines(..) => ()
    Block::FootnoteDefinition(label~, children~, span~, ..) => {
      buf.write_string("<div class=\"footnote\" id=\"fn-")
      buf.write_string(escape_html(label))
      buf.write_char('"')
      buf.write_string(pos_attrs(span, positions))
      buf.write_char('>')
      write_marker(buf, "[^" + label + "]: ")
      let mut first = true
      for child in children {
        if !first {
          buf.write_char('\n')
          write_marker(buf, "    ")
        }
        let child_buf = StringBuilder::new()
        render_block_literal(child, child_buf, positions)
        buf.write_string(strip_trailing_newline(child_buf.to_string()))
        first = false
      }
      buf.write_string("</div>\n")
    }
  }
}

///|
fn render_table_literal(
  header : Array[TableCell],
  alignments : Array[TableAlign],
  rows : Array[Array[TableCell]],
  span : Span,
  buf : StringBuilder,
  positions : Bool,
) -> Unit {
  buf.write_string("<table")
  buf.write_string(pos_attrs(span, positions))
  buf.write_char('>')
  buf.write_string("<thead><tr>")
  write_marker(buf, "|")
  for i, cell in header {
    let align = if i < alignments.length() {
      alignments[i]
    } else {
      TableAlign::None
    }
    render_table_cell_literal(cell, "th", align, buf, positions)
  }
  buf.write_char('\n')
  buf.write_string("</tr></thead>")
  buf.write_string("<tr aria-hidden=\"true\" class=\"md-table-separator\">")
  write_marker(buf, "|")
  for align in alignments {
    let sep = match align {
      TableAlign::Left => " :-- |"
      TableAlign::Center => " :-: |"
      TableAlign::Right => " --: |"
      TableAlign::None => " --- |"
    }
    write_marker(buf, sep)
  }
  buf.write_char('\n')
  buf.write_string("</tr>")
  if rows.length() > 0 {
    buf.write_string("<tbody>")
    for row in rows {
      buf.write_string("<tr>")
      write_marker(buf, "|")
      for i, cell in row {
        let align = if i < alignments.length() {
          alignments[i]
        } else {
          TableAlign::None
        }
        render_table_cell_literal(cell, "td", align, buf, positions)
      }
      buf.write_char('\n')
      buf.write_string("</tr>")
    }
    buf.write_string("</tbody>")
  }
  buf.write_string("</table>")
}

///|
fn render_table_cell_literal(
  cell : TableCell,
  tag : String,
  align : TableAlign,
  buf : StringBuilder,
  positions : Bool,
) -> Unit {
  // Cell spans are relative to the cell content, not the document.
  // The enclosing <table data-src-*> covers the whole grid; the click
  // handler walks up from a cell click to there.
  let _ = positions
  let align_attr = match align {
    TableAlign::Left => " style=\"text-align: left\""
    TableAlign::Center => " style=\"text-align: center\""
    TableAlign::Right => " style=\"text-align: right\""
    TableAlign::None => ""
  }
  buf.write_char('<')
  buf.write_string(tag)
  buf.write_string(align_attr)
  buf.write_char('>')
  write_marker(buf, " ")
  render_inlines_literal(cell.children, buf, false)
  buf.write_string("</")
  buf.write_string(tag)
  buf.write_char('>')
  write_marker(buf, " |")
}

///|
/// Render bullet-list items.
fn render_bullet_items_literal(
  items : Array[ListItem],
  buf : StringBuilder,
  indent : Int,
  positions : Bool,
) -> Unit {
  for item in items {
    // Top-level item spans are absolute, but blocks parsed inside the
    // item (nested lists, paragraphs) carry relative spans, so only
    // annotate the <li> and stop recursion's annotation there.
    buf.write_string("<li")
    buf.write_string(pos_attrs(item.span, positions))
    buf.write_char('>')
    let prefix = repeat_char(' ', indent) + "* "
    write_marker(buf, prefix)
    match item.checked {
      Some(true) => write_marker(buf, "[x] ")
      Some(false) => write_marker(buf, "[ ] ")
      None => ()
    }
    render_list_item_content_literal(item, buf, indent + 2, false)
    buf.write_string("</li>")
  }
}

///|
/// Render ordered-list items.
fn render_ordered_items_literal(
  items : Array[ListItem],
  buf : StringBuilder,
  indent : Int,
  start : Int,
  positions : Bool,
) -> Unit {
  let mut num = start
  for item in items {
    buf.write_string("<li")
    buf.write_string(pos_attrs(item.span, positions))
    buf.write_char('>')
    let prefix = repeat_char(' ', indent) + num.to_string() + ". "
    write_marker(buf, prefix)
    match item.checked {
      Some(true) => write_marker(buf, "[x] ")
      Some(false) => write_marker(buf, "[ ] ")
      None => ()
    }
    render_list_item_content_literal(item, buf, indent + 3, false)
    buf.write_string("</li>")
    num += 1
  }
}

///|
fn render_list_item_content_literal(
  item : ListItem,
  buf : StringBuilder,
  nested_indent : Int,
  positions : Bool,
) -> Unit {
  let mut first_block = true
  for child in item.children {
    match child {
      Block::Paragraph(children=para_children, ..) => {
        render_inlines_literal(para_children, buf, positions)
        buf.write_char('\n')
        first_block = false
      }
      Block::BulletList(items=nested_items, ..) => {
        if first_block {
          buf.write_char('\n')
        }
        buf.write_string("<ul>")
        render_bullet_items_literal(nested_items, buf, nested_indent, positions)
        buf.write_string("</ul>")
      }
      Block::OrderedList(items=nested_items, start=nested_start, ..) => {
        if first_block {
          buf.write_char('\n')
        }
        buf.write_string("<ol>")
        render_ordered_items_literal(
          nested_items,
          buf,
          nested_indent,
          nested_start,
          positions,
        )
        buf.write_string("</ol>")
      }
      _ => {
        render_block_literal(child, buf, positions)
        first_block = false
      }
    }
  }
  if first_block {
    buf.write_char('\n')
  }
}

// =============================================================================
// Inline rendering
// =============================================================================

///|
fn render_inlines_literal(
  inlines : Array[Inline],
  buf : StringBuilder,
  positions : Bool,
) -> Unit {
  for inline in inlines {
    render_inline_literal(inline, buf, positions)
  }
}

///|
fn render_inline_literal(
  inline : Inline,
  buf : StringBuilder,
  positions : Bool,
) -> Unit {
  // Inline spans come from the inline parser and are relative to the
  // surrounding block's content, not the document. They are intentionally
  // omitted from `data-src-*` annotations — the block-level ancestor's
  // span is enough to recover precise source offsets via the visible-text
  // invariant.
  let _ = positions
  match inline {
    Inline::Text(content~, ..) => buf.write_string(escape_html(content))
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) => {
      write_marker(buf, "\\")
      buf.write_char('\n')
    }
    Inline::Emphasis(children~, ..) => {
      buf.write_string("<em>")
      write_marker(buf, "*")
      render_inlines_literal(children, buf, positions)
      write_marker(buf, "*")
      buf.write_string("</em>")
    }
    Inline::Strong(children~, ..) => {
      buf.write_string("<strong>")
      write_marker(buf, "**")
      render_inlines_literal(children, buf, positions)
      write_marker(buf, "**")
      buf.write_string("</strong>")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("<del>")
      write_marker(buf, "~~")
      render_inlines_literal(children, buf, positions)
      write_marker(buf, "~~")
      buf.write_string("</del>")
    }
    Inline::Code(content~, ..) => {
      let backticks = calc_code_span_backticks(content)
      let tick_str = repeat_char('`', backticks)
      let needs_padding = content.length() > 0 &&
        ({
          let first = content.get_char(0)
          let last = content.get_char(content.length() - 1)
          first == Some('`') || last == Some('`')
        })
      buf.write_string("<code>")
      write_marker(buf, tick_str)
      if needs_padding {
        buf.write_char(' ')
      }
      buf.write_string(escape_html(content))
      if needs_padding {
        buf.write_char(' ')
      }
      write_marker(buf, tick_str)
      buf.write_string("</code>")
    }
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      let href = if fragment.is_empty() {
        target
      } else {
        target + "#" + fragment
      }
      buf.write_string("<a class=\"md-wikilink\" href=\"")
      buf.write_string(escape_html_attr(href))
      buf.write_string("\">")
      write_marker(buf, "[[")
      buf.write_string(escape_html(target))
      if !fragment.is_empty() {
        buf.write_string(escape_html("#" + fragment))
      }
      if !label.is_empty() {
        write_marker(buf, "|")
        buf.write_string(escape_html(label))
      }
      write_marker(buf, "]]")
      buf.write_string("</a>")
    }
    Inline::Link(children~, url~, title~, ..) => {
      buf.write_string("<a href=\"")
      buf.write_string(escape_html_attr(url))
      buf.write_char('"')
      if !title.is_empty() {
        buf.write_string(" title=\"")
        buf.write_string(escape_html_attr(title))
        buf.write_char('"')
      }
      buf.write_char('>')
      write_marker(buf, "[")
      render_inlines_literal(children, buf, positions)
      let trailing = if title.is_empty() {
        "](" + url + ")"
      } else {
        "](" + url + " \"" + title + "\")"
      }
      write_marker(buf, trailing)
      buf.write_string("</a>")
    }
    Inline::RefLink(children~, label~, ..) => {
      buf.write_string("<a class=\"md-reflink\" href=\"#ref-")
      buf.write_string(escape_html_attr(label))
      buf.write_string("\">")
      write_marker(buf, "[")
      render_inlines_literal(children, buf, positions)
      write_marker(buf, "][" + label + "]")
      buf.write_string("</a>")
    }
    Inline::Autolink(url~, is_email~, ..) => {
      let href = if is_email { "mailto:" + url } else { url }
      buf.write_string("<a href=\"")
      buf.write_string(escape_html_attr(href))
      buf.write_string("\">")
      write_marker(buf, "<")
      buf.write_string(escape_html(url))
      write_marker(buf, ">")
      buf.write_string("</a>")
    }
    Inline::Image(alt~, url~, title~, ..) => {
      buf.write_string("<span class=\"md-image\" role=\"img\" aria-label=\"")
      buf.write_string(escape_html_attr(alt))
      buf.write_string("\">")
      write_marker(buf, "![")
      buf.write_string(escape_html(alt))
      let trailing = if title.is_empty() {
        "](" + url + ")"
      } else {
        "](" + url + " \"" + title + "\")"
      }
      write_marker(buf, trailing)
      buf.write_string("</span>")
    }
    Inline::RefImage(alt~, label~, ..) => {
      buf.write_string("<span class=\"md-image\" role=\"img\" aria-label=\"")
      buf.write_string(escape_html_attr(alt))
      buf.write_string("\">")
      write_marker(buf, "![")
      buf.write_string(escape_html(alt))
      write_marker(buf, "][" + label + "]")
      buf.write_string("</span>")
    }
    Inline::HtmlInline(html~, ..) => {
      buf.write_string("<span class=\"md-html-inline\">")
      buf.write_string(escape_html(html))
      buf.write_string("</span>")
    }
    Inline::FootnoteReference(label~, ..) => {
      buf.write_string("<sup class=\"footnote-ref\"><a href=\"#fn-")
      buf.write_string(escape_html_attr(label))
      buf.write_string("\">")
      write_marker(buf, "[^" + label + "]")
      buf.write_string("</a></sup>")
    }
  }
}
