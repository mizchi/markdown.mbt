///| HTML Renderer

///| Renders markdown AST to HTML

///|
/// Output buffer that remembers whether it is at the start of a line, so that
/// block-level elements can always begin on one — the `cr()` of the reference
/// implementation's HTML renderer.
priv struct HtmlBuf {
  inner : StringBuilder
  mut at_line_start : Bool
}

///|
fn HtmlBuf::new() -> HtmlBuf {
  { inner: StringBuilder::new(), at_line_start: true }
}

///|
fn HtmlBuf::write_string(self : HtmlBuf, s : String) -> Unit {
  if s.is_empty() {
    return
  }
  self.inner.write_string(s)
  self.at_line_start = s.unsafe_get(s.length() - 1) == '\n'
}

///|
fn HtmlBuf::write_char(self : HtmlBuf, c : Char) -> Unit {
  self.inner.write_char(c)
  self.at_line_start = c == '\n'
}

///|
/// Start a new line unless the output already is at one.
fn HtmlBuf::cr(self : HtmlBuf) -> Unit {
  if !self.at_line_start {
    self.write_char('\n')
  }
}

///|
fn HtmlBuf::to_string(self : HtmlBuf) -> String {
  self.inner.to_string()
}

///|
/// Everything the block/inline renderers need to know beyond the node itself.
priv struct RenderCtx {
  autolink : Bool
  defs : Map[String, LinkDefinition]
}

///|
/// Render a document to HTML
pub fn render_html(doc : Document, autolink? : Bool = true) -> String {
  let defs : Map[String, LinkDefinition] = Map(
    [],
    capacity=doc.definitions.length(),
  )
  for def in doc.definitions {
    let key = normalize_label(def.label)
    if !defs.contains(key) {
      defs[key] = def
    }
  }
  let ctx = RenderCtx::{ autolink, defs }
  let buf = HtmlBuf::new()
  for block in doc.children {
    render_block_html(block, buf, ctx)
  }
  buf.to_string()
}

///|
/// Render a block element to HTML
fn render_block_html(block : Block, buf : HtmlBuf, ctx : RenderCtx) -> Unit {
  match block {
    Block::Paragraph(children~, ..) => {
      buf.cr()
      buf.write_string("<p>")
      render_inlines_html(children, buf, ctx)
      buf.write_string("</p>\n")
    }
    Block::Heading(level~, children~, ..) => {
      buf.cr()
      buf.write_string("<h")
      buf.write_string(level.to_string())
      buf.write_char('>')
      render_inlines_html(children, buf, ctx)
      buf.write_string("</h")
      buf.write_string(level.to_string())
      buf.write_string(">\n")
    }
    Block::ThematicBreak(..) => {
      buf.cr()
      buf.write_string("<hr />\n")
    }
    Block::FencedCode(info~, code~, ..) => {
      buf.cr()
      let lang = code_block_language(info)
      if lang.is_empty() {
        buf.write_string("<pre><code>")
      } else {
        buf.write_string("<pre><code class=\"language-")
        buf.write_string(escape_html(lang))
        buf.write_string("\">")
      }
      write_code_content(code, buf)
      buf.write_string("</code></pre>\n")
    }
    Block::IndentedCode(code~, ..) => {
      buf.cr()
      buf.write_string("<pre><code>")
      write_code_content(code, buf)
      buf.write_string("</code></pre>\n")
    }
    Block::Blockquote(children~, ..) => {
      buf.cr()
      buf.write_string("<blockquote>\n")
      for child in children {
        render_block_html(child, buf, ctx)
      }
      buf.write_string("</blockquote>\n")
    }
    Block::BulletList(items~, tight~, ..) => {
      buf.cr()
      // Check if this list contains task items
      let has_task = items.iter().any(fn(item) { !(item.checked is None) })
      if has_task {
        buf.write_string("<ul class=\"contains-task-list\">\n")
      } else {
        buf.write_string("<ul>\n")
      }
      for item in items {
        render_list_item_html(item, buf, tight, has_task, ctx)
      }
      buf.write_string("</ul>\n")
    }
    Block::OrderedList(items~, start~, tight~, ..) => {
      buf.cr()
      let has_task = items.iter().any(fn(item) { !(item.checked is None) })
      if start == 1 {
        if has_task {
          buf.write_string("<ol class=\"contains-task-list\">\n")
        } else {
          buf.write_string("<ol>\n")
        }
      } else {
        if has_task {
          buf.write_string("<ol class=\"contains-task-list\" start=\"")
        } else {
          buf.write_string("<ol start=\"")
        }
        buf.write_string(start.to_string())
        buf.write_string("\">\n")
      }
      for item in items {
        render_list_item_html(item, buf, tight, has_task, ctx)
      }
      buf.write_string("</ol>\n")
    }
    Block::HtmlBlock(html~, ..) => {
      buf.cr()
      buf.write_string(html)
      if !html.has_suffix("\n") {
        buf.write_char('\n')
      }
    }
    Block::Table(header~, alignments~, rows~, ..) => {
      buf.cr()
      buf.write_string("<table>\n<thead>\n<tr>\n")
      for i, cell in header {
        let align = if i < alignments.length() {
          alignments[i]
        } else {
          TableAlign::None
        }
        render_table_cell_html(cell, buf, "th", align, ctx)
      }
      buf.write_string("</tr>\n</thead>\n")
      if rows.length() > 0 {
        buf.write_string("<tbody>\n")
        for row in rows {
          buf.write_string("<tr>\n")
          for i, cell in row {
            let align = if i < alignments.length() {
              alignments[i]
            } else {
              TableAlign::None
            }
            render_table_cell_html(cell, buf, "td", align, ctx)
          }
          buf.write_string("</tr>\n")
        }
        buf.write_string("</tbody>\n")
      }
      buf.write_string("</table>\n")
    }
    Block::BlankLines(..) => () // Blank lines don't produce HTML output
    Block::FootnoteDefinition(label~, children~, ..) => {
      buf.cr()
      buf.write_string("<div class=\"footnote\" id=\"fn-")
      buf.write_string(escape_html(label))
      buf.write_string("\">\n")
      for child in children {
        render_block_html(child, buf, ctx)
      }
      buf.write_string("</div>\n")
    }
  }
}

///|
/// The language class of a fenced code block: the first word of the info
/// string, with escapes and entity references resolved.
fn code_block_language(info : String) -> String {
  let decoded = unescape_string(info)
  let len = decoded.length()
  let mut start = 0
  while start < len && is_html_space(decoded.unsafe_get(start)) {
    start = start + 1
  }
  let mut end = start
  while end < len && !is_html_space(decoded.unsafe_get(end)) {
    end = end + 1
  }
  decoded.unsafe_substring(start~, end~)
}

///|
/// Write code-block content, guaranteeing the trailing newline CommonMark
/// requires inside `<pre><code>`.
fn write_code_content(code : String, buf : HtmlBuf) -> Unit {
  if code.is_empty() {
    return
  }
  buf.write_string(escape_html(code))
  if !code.has_suffix("\n") {
    buf.write_char('\n')
  }
}

///|
/// Render a list item to HTML
fn render_list_item_html(
  item : ListItem,
  buf : HtmlBuf,
  tight : Bool,
  is_task_list : Bool,
  ctx : RenderCtx,
) -> Unit {
  buf.cr()
  // Task list items get a special class
  if is_task_list && !(item.checked is None) {
    buf.write_string("<li class=\"task-list-item\">")
  } else {
    buf.write_string("<li>")
  }

  // Task list checkbox
  match item.checked {
    Some(true) =>
      buf.write_string("<input type=\"checkbox\" checked disabled> ")
    Some(false) => buf.write_string("<input type=\"checkbox\" disabled> ")
    None => ()
  }
  for child in item.children {
    match child {
      // A tight list drops the <p> wrapper around its items' paragraphs.
      Paragraph(children~, ..) if tight =>
        render_inlines_html(children, buf, ctx)
      _ => render_block_html(child, buf, ctx)
    }
  }
  buf.write_string("</li>\n")
}

///|
/// Render a table cell to HTML
fn render_table_cell_html(
  cell : TableCell,
  buf : HtmlBuf,
  tag : String,
  align : TableAlign,
  ctx : RenderCtx,
) -> Unit {
  buf.write_char('<')
  buf.write_string(tag)
  match align {
    TableAlign::Left => buf.write_string(" align=\"left\"")
    TableAlign::Center => buf.write_string(" align=\"center\"")
    TableAlign::Right => buf.write_string(" align=\"right\"")
    TableAlign::None => ()
  }
  buf.write_char('>')
  render_inlines_html(cell.children, buf, ctx)
  buf.write_string("</")
  buf.write_string(tag)
  buf.write_string(">\n")
}

///|
/// Render inline elements to HTML
fn render_inlines_html(
  inlines : Array[Inline],
  buf : HtmlBuf,
  ctx : RenderCtx,
) -> Unit {
  for inline in inlines {
    render_inline_html(inline, buf, ctx)
  }
}

///|
/// Build the rendered destination for a wiki link.
fn render_wikilink_destination(target : String, fragment : String) -> String {
  if fragment.is_empty() {
    target
  } else {
    target + "#" + fragment
  }
}

///|
/// Render text content, optionally turning bare http(s) URLs into anchors.
fn render_text_html(
  content : String,
  buf : HtmlBuf,
  autolink? : Bool = true,
) -> Unit {
  if !autolink {
    buf.write_string(escape_html(content))
    return
  }
  let len = content.length()
  let mut pos = 0
  while pos < len {
    match find_next_url_start(content, pos) {
      Some(start) => {
        write_escaped_text_range(content, pos, start, buf)
        let raw_end = find_url_raw_end(content, start)
        let url_end = trim_url_end(content, start, raw_end)
        if url_end > start {
          let url = content.unsafe_substring(start~, end=url_end)
          buf.write_string("<a href=\"")
          write_escaped_href(url, buf)
          buf.write_string("\">")
          buf.write_string(escape_html(url))
          buf.write_string("</a>")
          pos = url_end
        } else {
          write_escaped_text_range(content, start, raw_end, buf)
          pos = raw_end
        }
      }
      None => {
        write_escaped_text_range(content, pos, len, buf)
        pos = len
      }
    }
  }
}

///|
fn write_escaped_text_range(
  content : String,
  start : Int,
  end : Int,
  buf : HtmlBuf,
) -> Unit {
  if end > start {
    buf.write_string(escape_html(content.unsafe_substring(start~, end~)))
  }
}

///|
/// Resolve a reference link/image label against the document's definitions.
fn RenderCtx::lookup(self : RenderCtx, label : String) -> LinkDefinition? {
  self.defs.get(normalize_label(label))
}

///|
/// Render a single inline element to HTML
fn render_inline_html(inline : Inline, buf : HtmlBuf, ctx : RenderCtx) -> Unit {
  match inline {
    Inline::Text(content~, ..) =>
      render_text_html(content, buf, autolink=ctx.autolink)
    Inline::Code(content~, ..) => {
      buf.write_string("<code>")
      buf.write_string(escape_html(normalize_code_span(content)))
      buf.write_string("</code>")
    }
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      let href = render_wikilink_destination(target, fragment)
      let text = if label.is_empty() { href } else { label }
      buf.write_string("<a href=\"")
      write_escaped_href(href, buf)
      buf.write_string("\">")
      buf.write_string(escape_html(text))
      buf.write_string("</a>")
    }
    Inline::Emphasis(children~, ..) => {
      buf.write_string("<em>")
      render_inlines_html(children, buf, ctx)
      buf.write_string("</em>")
    }
    Inline::Strong(children~, ..) => {
      buf.write_string("<strong>")
      render_inlines_html(children, buf, ctx)
      buf.write_string("</strong>")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("<del>")
      render_inlines_html(children, buf, ctx)
      buf.write_string("</del>")
    }
    Inline::Link(children~, url~, title~, ..) =>
      write_anchor(children, url, title, buf, ctx)
    Inline::RefLink(children~, label~, ..) =>
      match ctx.lookup(label) {
        Some(def) => write_anchor(children, def.url, def.title, buf, ctx)
        None => {
          buf.write_char('[')
          render_inlines_html(children, buf, ctx)
          buf.write_string("][")
          buf.write_string(escape_html(label))
          buf.write_char(']')
        }
      }
    Inline::Autolink(url~, is_email~, ..) => {
      buf.write_string("<a href=\"")
      if is_email {
        buf.write_string("mailto:")
      }
      write_escaped_href(url, buf)
      buf.write_string("\">")
      buf.write_string(escape_html(url))
      buf.write_string("</a>")
    }
    Inline::Image(alt~, url~, title~, ..) =>
      write_image(alt, url, title, buf, ctx)
    Inline::RefImage(alt~, label~, ..) =>
      match ctx.lookup(label) {
        Some(def) => write_image(alt, def.url, def.title, buf, ctx)
        None => {
          buf.write_string("![")
          buf.write_string(escape_html(alt))
          buf.write_string("][")
          buf.write_string(escape_html(label))
          buf.write_char(']')
        }
      }
    Inline::HtmlInline(html~, ..) => buf.write_string(html)
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) => buf.write_string("<br />\n")
    Inline::FootnoteReference(label~, ..) => {
      buf.write_string("<sup><a href=\"#fn-")
      write_escaped_href(label, buf)
      buf.write_string("\" id=\"fnref-")
      write_escaped_href(label, buf)
      buf.write_string("\">")
      buf.write_string(escape_html(label))
      buf.write_string("</a></sup>")
    }
  }
}

///|
fn write_anchor(
  children : Array[Inline],
  url : String,
  title : String,
  buf : HtmlBuf,
  ctx : RenderCtx,
) -> Unit {
  buf.write_string("<a href=\"")
  write_escaped_href(url, buf)
  buf.write_char('"')
  if !title.is_empty() {
    buf.write_string(" title=\"")
    buf.write_string(escape_html(title))
    buf.write_char('"')
  }
  buf.write_char('>')
  render_inlines_html(children, buf, { ..ctx, autolink: false })
  buf.write_string("</a>")
}

///|
fn write_image(
  alt : String,
  url : String,
  title : String,
  buf : HtmlBuf,
  ctx : RenderCtx,
) -> Unit {
  buf.write_string("<img src=\"")
  write_escaped_href(url, buf)
  buf.write_string("\" alt=\"")
  buf.write_string(escape_html(render_alt_text(alt, ctx)))
  buf.write_char('"')
  if !title.is_empty() {
    buf.write_string(" title=\"")
    buf.write_string(escape_html(title))
    buf.write_char('"')
  }
  buf.write_string(" />")
}

///|
/// An image's `alt` keeps the source of its label so it round-trips; the HTML
/// form is that label rendered as plain text.
fn render_alt_text(alt : String, ctx : RenderCtx) -> String {
  let buf = StringBuilder::new()
  write_plain_text(parse_inlines_with_defs(alt, ctx.defs, false), buf)
  buf.to_string()
}

///|
fn write_plain_text(inlines : Array[Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    match inline {
      Inline::Text(content~, ..) => buf.write_string(content)
      Inline::Code(content~, ..) =>
        buf.write_string(normalize_code_span(content))
      Inline::HtmlInline(html~, ..) => buf.write_string(html)
      Inline::SoftBreak(..) | Inline::HardBreak(..) => buf.write_char('\n')
      Inline::Emphasis(children~, ..)
      | Inline::Strong(children~, ..)
      | Inline::Strikethrough(children~, ..)
      | Inline::Link(children~, ..)
      | Inline::RefLink(children~, ..) => write_plain_text(children, buf)
      Inline::Image(alt~, ..) | Inline::RefImage(alt~, ..) =>
        buf.write_string(alt)
      Inline::Autolink(url~, ..) => buf.write_string(url)
      Inline::WikiLink(target~, label~, ..) =>
        buf.write_string(if label.is_empty() { target } else { label })
      Inline::FootnoteReference(label~, ..) => buf.write_string(label)
    }
  }
}

///|
/// Escape HTML special characters in text content.
/// Pass `attr=true` to also escape `'` (for attribute values).
///
/// Most input strings don't contain any HTML-special characters, so a
/// quick scan-pass lets us return the input unchanged in that common
/// case and avoid building a new buffer.
fn escape_html(s : String, attr? : Bool = false) -> String {
  let mut needs_escape = false
  for c in s {
    match c {
      '&' | '<' | '>' | '"' => {
        needs_escape = true
        break
      }
      '\'' if attr => {
        needs_escape = true
        break
      }
      _ => ()
    }
  }
  if !needs_escape {
    return s
  }
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      '\'' if attr => buf.write_string("&#39;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Characters that may appear literally in an `href`; everything else is
/// percent-encoded (or, for `&` and `'`, written as a character reference).
/// The table matches the reference implementation's.
fn is_href_safe(code : Int) -> Bool {
  if code < 0x21 || code > 0x7E {
    return false
  }
  match code {
    0x22
    | 0x26
    | 0x27
    | 0x3C
    | 0x3E
    | 0x5B
    | 0x5C
    | 0x5D
    | 0x5E
    | 0x60
    | 0x7B
    | 0x7C
    | 0x7D => false
    _ => true
  }
}

///|
fn write_hex_byte(byte : Int, buf : HtmlBuf) -> Unit {
  let digits = "0123456789ABCDEF"
  buf.write_char('%')
  buf.write_string(
    digits.unsafe_substring(
      start=(byte >> 4) & 0xF,
      end=((byte >> 4) & 0xF) + 1,
    ),
  )
  buf.write_string(
    digits.unsafe_substring(start=byte & 0xF, end=(byte & 0xF) + 1),
  )
}

///|
/// Percent-encode a URL for use in an `href`/`src` attribute.
fn write_escaped_href(url : String, buf : HtmlBuf) -> Unit {
  for c in url {
    let code = c.to_int()
    if is_href_safe(code) {
      buf.write_char(c)
    } else if code == 0x26 {
      buf.write_string("&amp;")
    } else if code == 0x27 {
      buf.write_string("&#x27;")
    } else if code < 0x80 {
      write_hex_byte(code, buf)
    } else if code < 0x800 {
      write_hex_byte(0xC0 | (code >> 6), buf)
      write_hex_byte(0x80 | (code & 0x3F), buf)
    } else if code < 0x10000 {
      write_hex_byte(0xE0 | (code >> 12), buf)
      write_hex_byte(0x80 | ((code >> 6) & 0x3F), buf)
      write_hex_byte(0x80 | (code & 0x3F), buf)
    } else {
      write_hex_byte(0xF0 | (code >> 18), buf)
      write_hex_byte(0x80 | ((code >> 12) & 0x3F), buf)
      write_hex_byte(0x80 | ((code >> 6) & 0x3F), buf)
      write_hex_byte(0x80 | (code & 0x3F), buf)
    }
  }
}

///|
/// Parse markdown and render to HTML
pub fn md_to_html(
  source : String,
  wikilinks? : Bool = false,
  autolink? : Bool = true,
) -> String {
  let result = parse(source, wikilinks~)
  render_html(result.document, autolink~)
}

///|
/// Parse markdown and render to HTML (strict mode)
///
/// Kept for backwards compatibility: the parser is now always spec-strict.
pub fn md_to_html_strict(
  source : String,
  wikilinks? : Bool = false,
  autolink? : Bool = true,
) -> String {
  md_to_html(source, wikilinks~, autolink~)
}
