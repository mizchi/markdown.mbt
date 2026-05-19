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
///
/// - `positions`: emit `data-src-start` / `data-src-end` on top-level
///   block elements (see module docs).
/// - `image_preview`: emit an `<img class="md-image-preview">` slot
///   inside each `<span class="md-image">` wrapper alongside the
///   `![alt](url)` source characters. The `<img>` carries no visible
///   text (`textContent` is empty), so the overlay invariant is
///   preserved. Default `display: none` ships in
///   `@mizchi/markdown/editor/overlay.css`; the consumer opts in by
///   adding `.with-image-preview` to a container above the rendered
///   output (or by overriding the rule themselves).
pub fn render_html_literal(
  doc : Document,
  positions? : Bool = false,
  image_preview? : Bool = false,
) -> String {
  let opts : LiteralOpts = { positions, image_preview }
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
    render_block_literal(block, buf, opts)
  }
  buf.to_string()
}

///|
/// Parse markdown and render with the literal renderer in one step.
pub fn md_to_html_literal(
  source : String,
  wikilinks? : Bool = false,
  positions? : Bool = false,
  image_preview? : Bool = false,
) -> String {
  let result = parse(source, wikilinks~)
  render_html_literal(result.document, positions~, image_preview~)
}

///|
/// Renderer flags grouped so we don't have to thread each one through
/// every helper individually.
priv struct LiteralOpts {
  positions : Bool
  image_preview : Bool
}

///|
/// Return a copy of `opts` with `positions` disabled, for recursing into
/// nested blocks whose spans are relative to the parent and so can't be
/// used as document offsets.
fn LiteralOpts::nested(self : LiteralOpts) -> LiteralOpts {
  { positions: false, image_preview: self.image_preview }
}

// =============================================================================
// Helpers
// =============================================================================

///|
/// Emit `<span class="md-marker" aria-hidden="true">…</span>` for the given
/// syntax characters. We deliberately do *not* run the marker text through
/// the generic `escape_html` because Markdown markers can only contain
/// ASCII punctuation / digits / spaces; the only character that needs HTML
/// escaping is `>` (blockquote prefix), which the caller handles via
/// `write_marker_lit` / dedicated paths. Saving the per-call alloc was
/// measurable in `bench_renderer_literal`.
fn write_marker(buf : StringBuilder, text : String) -> Unit {
  if text.is_empty() {
    return
  }
  buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
  escape_html_into(buf, text)
  buf.write_string("</span>")
}

///|
/// Emit a marker span containing `n` copies of `c`. Skips building an
/// intermediate `String`; for the common case of `#`, `*`, `` ` ``, ` `
/// the character is HTML-safe so we can write it straight through.
fn write_marker_repeat(buf : StringBuilder, c : Char, n : Int) -> Unit {
  if n <= 0 {
    return
  }
  buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
  for k = 0; k < n; k = k + 1 {
    buf.write_char(c)
  }
  buf.write_string("</span>")
}

///|
/// Append HTML-escaped characters of `s` to `buf`. Same character set as
/// `escape_html` but without allocating an intermediate `String`.
///
/// The common case for markdown text — paragraphs, headings, code-span
/// content — contains no HTML-special characters, so a quick pre-scan
/// lets us hand the whole string to the builder in one call instead of
/// char-by-char. The slow path is only taken for inputs that actually
/// need escaping (typically blockquote prefixes, raw HTML and
/// occasional code content).
fn escape_html_into(buf : StringBuilder, s : String) -> Unit {
  if !needs_html_escape(s) {
    buf.write_string(s)
    return
  }
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      _ => buf.write_char(c)
    }
  }
}

///|
/// Like `escape_html_into` but also escapes `'` — for HTML attribute
/// values where the attribute is single-quoted or where `'` could be
/// interpreted as a delimiter by a downstream consumer.
fn escape_html_attr_into(buf : StringBuilder, s : String) -> Unit {
  if !needs_html_attr_escape(s) {
    buf.write_string(s)
    return
  }
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(c)
    }
  }
}

///|
fn needs_html_escape(s : String) -> Bool {
  for c in s {
    match c {
      '&' | '<' | '>' | '"' => return true
      _ => ()
    }
  }
  false
}

///|
fn needs_html_attr_escape(s : String) -> Bool {
  for c in s {
    match c {
      '&' | '<' | '>' | '"' | '\'' => return true
      _ => ()
    }
  }
  false
}

///|
/// Append `<img class="md-image-preview" src=… alt=… title=… loading="lazy">`.
/// The `<img>` contributes no visible text, so the overlay invariant is
/// preserved. CSS in `overlay.css` hides it by default; the consumer
/// opts in by adding `.with-image-preview` (or by overriding the rule).
fn write_image_preview_slot(
  buf : StringBuilder,
  url : String,
  alt : String,
  title : String,
) -> Unit {
  buf.write_string("<img class=\"md-image-preview\" src=\"")
  escape_html_into(buf, url)
  buf.write_string("\" alt=\"")
  escape_html_into(buf, alt)
  buf.write_char('"')
  if !title.is_empty() {
    buf.write_string(" title=\"")
    escape_html_into(buf, title)
    buf.write_char('"')
  }
  buf.write_string(" loading=\"lazy\" />")
}

///|
/// Append ` data-src-start="X" data-src-end="Y"` directly to `buf`
/// (skipping the prior implementation's intermediate `String`).
fn write_pos_attrs(buf : StringBuilder, span : Span, positions : Bool) -> Unit {
  if !positions {
    return
  }
  buf.write_string(" data-src-start=\"")
  buf.write_string(span.from.to_string())
  buf.write_string("\" data-src-end=\"")
  buf.write_string(span.to.to_string())
  buf.write_char('"')
}

///|
/// Render a fenced code block (or an indented code block normalised to
/// fenced, with `info=""`). Visible characters: ```` ```info\ncode\n``` ````
/// followed by a trailing `\n` from the block close.
fn write_fenced_code(
  buf : StringBuilder,
  code : String,
  info : String,
  span : Span,
  opts : LiteralOpts,
) -> Unit {
  let fence_len = calc_fence_length(code)
  buf.write_string("<div class=\"md-fenced-code\"")
  write_pos_attrs(buf, span, opts.positions)
  buf.write_char('>')
  // Open-fence marker: ``` + info string, emitted directly without
  // allocating an intermediate concatenation.
  buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
  for k = 0; k < fence_len; k = k + 1 {
    buf.write_char('`')
  }
  escape_html_into(buf, info)
  buf.write_string("</span>")
  buf.write_char('\n')
  if info.is_empty() {
    buf.write_string("<pre><code>")
  } else {
    // Code-block language: the substring before the first ASCII space.
    let space_at = info.find(" ")
    let lang_end = match space_at {
      Some(i) => i
      None => info.length()
    }
    buf.write_string("<pre><code class=\"language-")
    escape_html_into(buf, info.unsafe_substring(start=0, end=lang_end))
    buf.write_string("\">")
  }
  escape_html_into(buf, code)
  if !code.is_empty() && !code.has_suffix("\n") {
    buf.write_char('\n')
  }
  buf.write_string("</code></pre>")
  write_marker_repeat(buf, '`', fence_len)
  buf.write_string("</div>\n")
}

///|
/// Open `<ul>` or `<ol>` with optional `contains-task-list` class,
/// `start=…` for ordered lists (pass 1 to omit), and source-position attrs.
fn write_list_open(
  buf : StringBuilder,
  tag : String,
  items : Array[ListItem],
  span : Span,
  opts : LiteralOpts,
  ordered_start : Int,
) -> Unit {
  let has_task = items.iter().any(fn(item) { !(item.checked is None) })
  buf.write_char('<')
  buf.write_string(tag)
  if has_task {
    buf.write_string(" class=\"contains-task-list\"")
  }
  if ordered_start > 1 {
    buf.write_string(" start=\"")
    buf.write_string(ordered_start.to_string())
    buf.write_char('"')
  }
  write_pos_attrs(buf, span, opts.positions)
  buf.write_char('>')
}

///|
/// Open `<h{level}>` with optional source-position attrs.
fn write_heading_open(
  buf : StringBuilder,
  level : Int,
  span : Span,
  opts : LiteralOpts,
) -> Unit {
  buf.write_string("<h")
  buf.write_string(level.to_string())
  write_pos_attrs(buf, span, opts.positions)
  buf.write_char('>')
}

///|
/// Close `<h{level}>` plus the block-terminating newline.
fn write_heading_close(buf : StringBuilder, level : Int) -> Unit {
  buf.write_string("</h")
  buf.write_string(level.to_string())
  buf.write_string(">\n")
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
  opts : LiteralOpts,
) -> Unit {
  match block {
    Block::ThematicBreak(span~, ..) => {
      buf.write_string("<div role=\"separator\"")
      write_pos_attrs(buf, span, opts.positions)
      buf.write_char('>')
      write_marker(buf, "***")
      buf.write_string("</div>\n")
    }
    Block::Heading(level~, style~, children~, span~, ..) => {
      write_heading_open(buf, level, span, opts)
      match style {
        HeadingStyle::Atx =>
          if !children.is_empty() {
            // `## ` etc. — marker text is ASCII, no escaping needed.
            buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
            for k = 0; k < level; k = k + 1 {
              buf.write_char('#')
            }
            buf.write_char(' ')
            buf.write_string("</span>")
            render_inlines_literal(children, buf, opts)
          } else {
            write_marker_repeat(buf, '#', level)
          }
        HeadingStyle::Setext => {
          render_inlines_literal(children, buf, opts)
          buf.write_char('\n')
          let underline_char = if level == 1 { '=' } else { '-' }
          write_marker_repeat(buf, underline_char, 3)
        }
      }
      write_heading_close(buf, level)
    }
    Block::Paragraph(children~, span~, ..) => {
      buf.write_string("<p")
      write_pos_attrs(buf, span, opts.positions)
      buf.write_char('>')
      render_inlines_literal(children, buf, opts)
      buf.write_string("</p>\n")
    }
    Block::FencedCode(info~, code~, span~, ..) =>
      write_fenced_code(buf, code, info, span, opts)
    Block::IndentedCode(code~, span~, ..) =>
      // The serializer canonicalises indented code to fenced (`info=""`).
      write_fenced_code(buf, code, "", span, opts)
    Block::Blockquote(children~, span~, ..) => {
      buf.write_string("<blockquote")
      write_pos_attrs(buf, span, opts.positions)
      buf.write_char('>')
      // Children are parsed inside the blockquote and their spans are
      // relative to the blockquote's content, not the document, so don't
      // emit `data-src` on them. The outer <blockquote> annotation is
      // enough — clicks inside it walk up to here.
      for child in children {
        let child_buf = StringBuilder::new()
        render_block_literal(child, child_buf, opts.nested())
        buf.write_string(prefix_blockquote_lines(child_buf.to_string()))
      }
      buf.write_string("</blockquote>")
    }
    Block::BulletList(items~, span~, ..) => {
      write_list_open(buf, "ul", items, span, opts, 1)
      render_bullet_items_literal(items, buf, 0, opts)
      buf.write_string("</ul>")
    }
    Block::OrderedList(start~, items~, span~, ..) => {
      write_list_open(buf, "ol", items, span, opts, start)
      render_ordered_items_literal(items, buf, 0, start, opts)
      buf.write_string("</ol>")
    }
    Block::HtmlBlock(html~, span~, ..) => {
      buf.write_string("<span class=\"md-html-block\"")
      write_pos_attrs(buf, span, opts.positions)
      buf.write_char('>')
      buf.write_string(escape_html(html))
      buf.write_string("</span>")
      if !html.has_suffix("\n") {
        buf.write_char('\n')
      }
    }
    Block::Table(header~, alignments~, rows~, span~, ..) =>
      render_table_literal(header, alignments, rows, span, buf, opts)
    Block::BlankLines(..) => ()
    Block::FootnoteDefinition(label~, children~, span~, ..) => {
      buf.write_string("<div class=\"footnote\" id=\"fn-")
      buf.write_string(escape_html(label))
      buf.write_char('"')
      write_pos_attrs(buf, span, opts.positions)
      buf.write_char('>')
      write_marker(buf, "[^" + label + "]: ")
      let mut first = true
      for child in children {
        if !first {
          buf.write_char('\n')
          write_marker(buf, "    ")
        }
        let child_buf = StringBuilder::new()
        render_block_literal(child, child_buf, opts)
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
  opts : LiteralOpts,
) -> Unit {
  buf.write_string("<table")
  write_pos_attrs(buf, span, opts.positions)
  buf.write_char('>')
  buf.write_string("<thead><tr>")
  write_marker(buf, "|")
  for i, cell in header {
    let align = if i < alignments.length() {
      alignments[i]
    } else {
      TableAlign::None
    }
    render_table_cell_literal(cell, "th", align, buf, opts)
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
        render_table_cell_literal(cell, "td", align, buf, opts)
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
  opts : LiteralOpts,
) -> Unit {
  // Cell spans are relative to the cell content, not the document.
  // The enclosing <table data-src-*> covers the whole grid; the click
  // handler walks up from a cell click to there.
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
  render_inlines_literal(cell.children, buf, opts)
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
  opts : LiteralOpts,
) -> Unit {
  for item in items {
    // Top-level item spans are absolute, but blocks parsed inside the
    // item (nested lists, paragraphs) carry relative spans, so only
    // annotate the <li> and stop recursion's annotation there.
    buf.write_string("<li")
    write_pos_attrs(buf, item.span, opts.positions)
    buf.write_char('>')
    // Marker: indent spaces + "* ", all ASCII so no escaping needed.
    buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
    for k = 0; k < indent; k = k + 1 {
      buf.write_char(' ')
    }
    buf.write_string("* </span>")
    match item.checked {
      Some(true) => write_marker(buf, "[x] ")
      Some(false) => write_marker(buf, "[ ] ")
      None => ()
    }
    render_list_item_content_literal(item, buf, indent + 2, opts.nested())
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
  opts : LiteralOpts,
) -> Unit {
  let mut num = start
  for item in items {
    buf.write_string("<li")
    write_pos_attrs(buf, item.span, opts.positions)
    buf.write_char('>')
    // Marker: indent spaces + "<num>. " — ASCII only, no escape.
    buf.write_string("<span class=\"md-marker\" aria-hidden=\"true\">")
    for k = 0; k < indent; k = k + 1 {
      buf.write_char(' ')
    }
    buf.write_string(num.to_string())
    buf.write_string(". </span>")
    match item.checked {
      Some(true) => write_marker(buf, "[x] ")
      Some(false) => write_marker(buf, "[ ] ")
      None => ()
    }
    render_list_item_content_literal(item, buf, indent + 3, opts.nested())
    buf.write_string("</li>")
    num += 1
  }
}

///|
fn render_list_item_content_literal(
  item : ListItem,
  buf : StringBuilder,
  nested_indent : Int,
  opts : LiteralOpts,
) -> Unit {
  let mut first_block = true
  for child in item.children {
    match child {
      Block::Paragraph(children=para_children, ..) => {
        render_inlines_literal(para_children, buf, opts)
        buf.write_char('\n')
        first_block = false
      }
      Block::BulletList(items=nested_items, ..) => {
        if first_block {
          buf.write_char('\n')
        }
        buf.write_string("<ul>")
        render_bullet_items_literal(nested_items, buf, nested_indent, opts)
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
          opts,
        )
        buf.write_string("</ol>")
      }
      _ => {
        render_block_literal(child, buf, opts)
        first_block = false
      }
    }
  }
  if first_block {
    buf.write_char('\n')
  }
}

