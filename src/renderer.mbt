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
fn HtmlBuf::new(size_hint? : Int = 0) -> HtmlBuf {
  { inner: StringBuilder(size_hint~), at_line_start: true }
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
  tagfilter : Bool
  defs : Map[String, LinkDefinition]
  footnote_defs : Map[String, FootnoteRenderDefinition]
  footnote_order : Array[String]
  footnote_numbers : Map[String, Int]
  footnote_ref_counts : Map[String, Int]
  math_block_renderer : ((String) -> String)?
}

///|
/// Footnote content collected before rendering the document body.
priv struct FootnoteRenderDefinition {
  children : Array[Block]
}

///|
/// Render a document to HTML
pub fn render_html(
  doc : Document,
  autolink? : Bool = true,
  tagfilter? : Bool = true,
) -> String {
  render_html_with_options(doc, RenderOptions::default(), autolink~, tagfilter~)
}

///|
/// Render with replaceable block renderers such as KaTeX.
pub fn render_html_with_options(
  doc : Document,
  options : RenderOptions,
  autolink? : Bool = true,
  tagfilter? : Bool = true,
) -> String {
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
  let footnote_defs : Map[String, FootnoteRenderDefinition] = Map([])
  collect_footnote_definitions(doc.children, footnote_defs)
  let ctx = RenderCtx::{
    autolink,
    tagfilter,
    defs,
    footnote_defs,
    footnote_order: [],
    footnote_numbers: Map([]),
    footnote_ref_counts: Map([]),
    math_block_renderer: options.math_block_renderer,
  }
  let buf = HtmlBuf::new(size_hint=doc.span.to - doc.span.from)
  for block in doc.children {
    render_block_html(block, buf, ctx)
  }
  render_footnote_section(buf, ctx)
  buf.to_string()
}

///|
/// Collect definitions recursively; the first definition for a label wins.
fn collect_footnote_definitions(
  blocks : Array[Block],
  defs : Map[String, FootnoteRenderDefinition],
) -> Unit {
  for block in blocks {
    match block {
      Block::FootnoteDefinition(label~, children~, ..) => {
        let key = normalize_label(label)
        if !defs.contains(key) {
          defs[key] = { children, }
        }
      }
      Block::Blockquote(children~, ..) | Block::Alert(children~, ..) =>
        collect_footnote_definitions(children, defs)
      Block::Directive(children~, ..) =>
        collect_footnote_definitions(children, defs)
      Block::Attributed(block~, ..) =>
        collect_footnote_definitions([block], defs)
      Block::BulletList(items~, ..) | Block::OrderedList(items~, ..) =>
        for item in items {
          collect_footnote_definitions(item.children, defs)
        }
      _ => ()
    }
  }
}

///|
/// Render a block element to HTML
fn render_block_html(block : Block, buf : HtmlBuf, ctx : RenderCtx) -> Unit {
  match block {
    Block::Attributed(block~, attributes~, ..) =>
      render_attributed_block(block, attributes, buf, ctx)
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
    Block::MathBlock(value~, ..) => {
      buf.cr()
      match ctx.math_block_renderer {
        Some(renderer) => {
          let html = renderer(value)
          buf.write_string(html)
          if !html.has_suffix("\n") {
            buf.write_char('\n')
          }
        }
        None => {
          buf.write_string("<pre class=\"math math-display\"><code>")
          buf.write_string(escape_html(value))
          buf.write_string("</code></pre>\n")
        }
      }
    }
    Block::Directive(name~, meta~, children~, ..) => {
      buf.cr()
      buf.write_string("<div class=\"directive directive-")
      buf.write_string(escape_html(name))
      buf.write_string("\" data-directive=\"")
      buf.write_string(escape_html(name))
      buf.write_char('"')
      if !meta.is_empty() {
        buf.write_string(" data-directive-meta=\"")
        buf.write_string(escape_html(meta))
        buf.write_char('"')
      }
      buf.write_string(">\n")
      for child in children {
        render_block_html(child, buf, ctx)
      }
      buf.write_string("</div>\n")
    }
    Block::DefinitionList(items~, ..) => {
      buf.cr()
      buf.write_string("<dl>\n")
      for item in items {
        buf.write_string("<dt>")
        render_inlines_html(item.term, buf, ctx)
        buf.write_string("</dt>\n")
        for definition in item.definitions {
          buf.write_string("<dd>")
          render_inlines_html(definition, buf, ctx)
          buf.write_string("</dd>\n")
        }
      }
      buf.write_string("</dl>\n")
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
    Block::Alert(kind~, children~, ..) => {
      let slug = alert_kind_slug(kind)
      buf.cr()
      buf.write_string("<div class=\"markdown-alert markdown-alert-")
      buf.write_string(slug)
      buf.write_string("\">\n<p class=\"markdown-alert-title\">")
      buf.write_string(alert_kind_title(kind))
      buf.write_string("</p>\n")
      for child in children {
        render_block_html(child, buf, ctx)
      }
      buf.write_string("</div>\n")
    }
    Block::BulletList(items~, tight~, ..) => {
      buf.cr()
      buf.write_string("<ul>\n")
      for item in items {
        render_list_item_html(item, buf, tight, ctx)
      }
      buf.write_string("</ul>\n")
    }
    Block::OrderedList(items~, start~, tight~, ..) => {
      buf.cr()
      if start == 1 {
        buf.write_string("<ol>\n")
      } else {
        buf.write_string("<ol start=\"")
        buf.write_string(start.to_string())
        buf.write_string("\">\n")
      }
      for item in items {
        render_list_item_html(item, buf, tight, ctx)
      }
      buf.write_string("</ol>\n")
    }
    Block::HtmlBlock(html~, ..) => {
      buf.cr()
      buf.write_string(if ctx.tagfilter { gfm_tagfilter(html) } else { html })
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
            if i >= alignments.length() {
              break
            }
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
    Block::FootnoteDefinition(..) => ()
  }
}

///| Render attributes on common semantic blocks; use a neutral wrapper for

///|
/// block kinds whose opening tag is owned by a specialized renderer.
fn render_attributed_block(
  block : Block,
  attributes : Array[MarkdownAttribute],
  buf : HtmlBuf,
  ctx : RenderCtx,
) -> Unit {
  match block {
    Block::FootnoteDefinition(..) => ()
    Block::Heading(level~, children~, ..) => {
      buf.cr()
      buf.write_string("<h")
      buf.write_string(level.to_string())
      write_markdown_attributes(attributes, buf)
      buf.write_char('>')
      render_inlines_html(children, buf, ctx)
      buf.write_string("</h")
      buf.write_string(level.to_string())
      buf.write_string(">\n")
    }
    Block::Paragraph(children~, ..) => {
      buf.cr()
      buf.write_string("<p")
      write_markdown_attributes(attributes, buf)
      buf.write_char('>')
      render_inlines_html(children, buf, ctx)
      buf.write_string("</p>\n")
    }
    _ => {
      buf.cr()
      buf.write_string("<div")
      write_markdown_attributes(attributes, buf)
      buf.write_string(">\n")
      render_block_html(block, buf, ctx)
      buf.write_string("</div>\n")
    }
  }
}

///|
/// Emit safe normalized attributes, merging repeated class shorthands.
fn write_markdown_attributes(
  attributes : Array[MarkdownAttribute],
  buf : HtmlBuf,
) -> Unit {
  let classes = StringBuilder()
  for attribute in attributes {
    if attribute.name == "id" {
      buf.write_string(" id=\"")
      buf.write_string(escape_html(attribute.value))
      buf.write_char('"')
    } else if attribute.name == "class" {
      if !classes.to_string().is_empty() {
        classes.write_char(' ')
      }
      classes.write_string(attribute.value)
    }
  }
  let class_value = classes.to_string()
  if !class_value.is_empty() {
    buf.write_string(" class=\"")
    buf.write_string(escape_html(class_value))
    buf.write_char('"')
  }
  for attribute in attributes {
    let lower = attribute.name.to_lower()
    if lower == "id" ||
      lower == "class" ||
      lower == "style" ||
      lower.has_prefix("on") {
      continue
    }
    buf.write_char(' ')
    buf.write_string(attribute.name)
    if !attribute.value.is_empty() {
      buf.write_string("=\"")
      buf.write_string(escape_html(attribute.value))
      buf.write_char('"')
    }
  }
}

///|
fn alert_kind_slug(kind : AlertKind) -> String {
  kind.slug()
}

///|
fn alert_kind_title(kind : AlertKind) -> String {
  match kind {
    Note => "Note"
    Tip => "Tip"
    Important => "Important"
    Warning => "Warning"
    Caution => "Caution"
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
  ctx : RenderCtx,
) -> Unit {
  buf.cr()
  buf.write_string("<li>")

  // Task list checkbox
  match item.checked {
    Some(true) =>
      buf.write_string("<input checked=\"\" disabled=\"\" type=\"checkbox\"> ")
    Some(false) => buf.write_string("<input disabled=\"\" type=\"checkbox\"> ")
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
    match find_next_autolink(content, pos) {
      Some(found) => {
        write_escaped_text_range(content, pos, found.start, buf)
        let display = content.unsafe_substring(start=found.start, end=found.end)
        buf.write_string("<a href=\"")
        match found.kind {
          Www => buf.write_string("http://")
          Email => buf.write_string("mailto:")
          Url => ()
        }
        write_escaped_href(display, buf)
        buf.write_string("\">")
        buf.write_string(escape_html(display))
        buf.write_string("</a>")
        pos = found.end
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
    Inline::Directive(name~, label~, attributes~, ..) => {
      buf.write_string("<span data-directive=\"")
      buf.write_string(escape_html(name, attr=true))
      buf.write_char('"')
      write_markdown_attributes(attributes, buf)
      buf.write_char('>')
      buf.write_string(escape_html(label))
      buf.write_string("</span>")
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
    Inline::HtmlInline(html~, ..) =>
      buf.write_string(if ctx.tagfilter { gfm_tagfilter(html) } else { html })
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) => buf.write_string("<br />\n")
    Inline::FootnoteReference(label~, ..) => {
      let key = normalize_label(label)
      guard ctx.footnote_defs.contains(key) else {
        buf.write_string("[^")
        buf.write_string(escape_html(label))
        buf.write_char(']')
        return
      }
      let number = match ctx.footnote_numbers.get(key) {
        Some(number) => number
        None => {
          let number = ctx.footnote_order.length() + 1
          ctx.footnote_order.push(key)
          ctx.footnote_numbers[key] = number
          number
        }
      }
      let occurrence = match ctx.footnote_ref_counts.get(key) {
        Some(count) => count + 1
        None => 1
      }
      ctx.footnote_ref_counts[key] = occurrence
      buf.write_string("<sup><a href=\"#fn-")
      write_escaped_href(key, buf)
      buf.write_string("\" id=\"fnref-")
      write_escaped_href(key, buf)
      if occurrence > 1 {
        buf.write_char('-')
        buf.write_string(occurrence.to_string())
      }
      buf.write_string(
        "\" data-footnote-ref=\"\" aria-describedby=\"footnote-label\">",
      )
      buf.write_string(number.to_string())
      buf.write_string("</a></sup>")
    }
  }
}

///|
/// Render referenced footnotes at the end of the document in reference order.
fn render_footnote_section(buf : HtmlBuf, ctx : RenderCtx) -> Unit {
  guard !ctx.footnote_order.is_empty() else { return }
  buf.cr()
  buf.write_string("<section data-footnotes=\"\" class=\"footnotes\">\n")
  buf.write_string(
    "<h2 class=\"sr-only\" id=\"footnote-label\">Footnotes</h2>\n<ol>\n",
  )
  for key in ctx.footnote_order {
    guard ctx.footnote_defs.get(key) is Some(def) else { continue }
    let number = ctx.footnote_numbers[key]
    buf.write_string("<li id=\"fn-")
    buf.write_string(escape_html(key))
    buf.write_string("\">\n")
    for child in def.children {
      render_block_html(child, buf, ctx)
    }
    let count = match ctx.footnote_ref_counts.get(key) {
      Some(count) => count
      None => 0
    }
    if count > 0 {
      buf.write_string("<p class=\"footnote-backrefs\">")
      for occurrence = 1; occurrence <= count; occurrence = occurrence + 1 {
        if occurrence > 1 {
          buf.write_char(' ')
        }
        buf.write_string("<a href=\"#fnref-")
        write_escaped_href(key, buf)
        if occurrence > 1 {
          buf.write_char('-')
          buf.write_string(occurrence.to_string())
        }
        buf.write_string(
          "\" data-footnote-backref=\"\" aria-label=\"Back to reference ",
        )
        buf.write_string(number.to_string())
        if occurrence > 1 {
          buf.write_char('-')
          buf.write_string(occurrence.to_string())
        }
        buf.write_string("\" class=\"data-footnote-backref\">↩</a>")
      }
      buf.write_string("</p>\n")
    }
    buf.write_string("</li>\n")
  }
  buf.write_string("</ol>\n</section>\n")
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
  let buf = StringBuilder(size_hint=alt.length())
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
      Inline::Directive(label~, ..) => buf.write_string(label)
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
  let buf = StringBuilder(size_hint=s.length())
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
  tagfilter? : Bool = true,
) -> String {
  let result = parse(source, wikilinks~)
  render_html(result.document, autolink~, tagfilter~)
}

///|
/// Parse markdown and render to HTML (strict mode)
///
/// Kept for backwards compatibility: the parser is now always spec-strict.
pub fn md_to_html_strict(
  source : String,
  wikilinks? : Bool = false,
  autolink? : Bool = true,
  tagfilter? : Bool = true,
) -> String {
  md_to_html(source, wikilinks~, autolink~, tagfilter~)
}
