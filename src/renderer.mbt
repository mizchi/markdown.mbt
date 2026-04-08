///| HTML Renderer

///| Renders markdown AST to HTML

///|
/// Render a document to HTML
pub fn render_html(doc : Document) -> String {
  let buf = StringBuilder::new()
  for block in doc.children {
    render_block_html(block, buf)
  }
  buf.to_string()
}

///|
/// Render a block element to HTML
fn render_block_html(block : Block, buf : StringBuilder) -> Unit {
  match block {
    Block::Paragraph(children~, ..) => {
      buf.write_string("<p>")
      render_inlines_html(children, buf)
      buf.write_string("</p>\n")
    }
    Block::Heading(level~, children~, ..) => {
      buf.write_string("<h")
      buf.write_string(level.to_string())
      buf.write_char('>')
      render_inlines_html(children, buf)
      buf.write_string("</h")
      buf.write_string(level.to_string())
      buf.write_string(">\n")
    }
    Block::ThematicBreak(..) => buf.write_string("<hr>\n")
    Block::FencedCode(info~, code~, ..) => {
      if info.is_empty() {
        buf.write_string("<pre><code>")
      } else {
        // Extract language from info string (first word)
        let parts = info.split(" ").collect()
        let lang = if parts.length() > 0 { parts[0].to_string() } else { info }
        buf.write_string("<pre><code class=\"language-")
        buf.write_string(escape_html(lang))
        buf.write_string("\">")
      }
      buf.write_string(escape_html(code))
      buf.write_string("</code></pre>\n")
    }
    Block::IndentedCode(code~, ..) => {
      buf.write_string("<pre><code>")
      buf.write_string(escape_html(code))
      buf.write_string("</code></pre>\n")
    }
    Block::Blockquote(children~, ..) => {
      buf.write_string("<blockquote>\n")
      for child in children {
        render_block_html(child, buf)
      }
      buf.write_string("</blockquote>\n")
    }
    Block::BulletList(items~, tight~, ..) => {
      // Check if this list contains task items
      let has_task = items.iter().any(fn(item) { !(item.checked is None) })
      if has_task {
        buf.write_string("<ul class=\"contains-task-list\">\n")
      } else {
        buf.write_string("<ul>\n")
      }
      for item in items {
        render_list_item_html(item, buf, tight, has_task)
      }
      buf.write_string("</ul>\n")
    }
    Block::OrderedList(items~, start~, tight~, ..) => {
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
        render_list_item_html(item, buf, tight, has_task)
      }
      buf.write_string("</ol>\n")
    }
    Block::HtmlBlock(html~, ..) => {
      buf.write_string(html)
      if !(html.has_suffix("\n")) {
        buf.write_char('\n')
      }
    }
    Block::Table(header~, alignments~, rows~, ..) => {
      buf.write_string("<table>\n<thead>\n<tr>\n")
      for i, cell in header {
        let align = if i < alignments.length() {
          alignments[i]
        } else {
          TableAlign::None
        }
        render_table_cell_html(cell, buf, "th", align)
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
            render_table_cell_html(cell, buf, "td", align)
          }
          buf.write_string("</tr>\n")
        }
        buf.write_string("</tbody>\n")
      }
      buf.write_string("</table>\n")
    }
    Block::BlankLines(..) => () // Blank lines don't produce HTML output
    Block::FootnoteDefinition(label~, children~, ..) => {
      buf.write_string("<div class=\"footnote\" id=\"fn-")
      buf.write_string(escape_html(label))
      buf.write_string("\">\n")
      for child in children {
        render_block_html(child, buf)
      }
      buf.write_string("</div>\n")
    }
  }
}

///|
/// Render a list item to HTML
fn render_list_item_html(
  item : ListItem,
  buf : StringBuilder,
  tight : Bool,
  is_task_list : Bool,
) -> Unit {
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
  if tight {
    // Tight list: render inline content without <p> wrapper
    for child in item.children {
      match child {
        Paragraph(children~, ..) => render_inlines_html(children, buf)
        _ => render_block_html(child, buf)
      }
    }
  } else {
    // Loose list: render blocks normally
    buf.write_char('\n')
    for child in item.children {
      render_block_html(child, buf)
    }
  }
  buf.write_string("</li>\n")
}

///|
/// Render a table cell to HTML
fn render_table_cell_html(
  cell : TableCell,
  buf : StringBuilder,
  tag : String,
  align : TableAlign,
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
  render_inlines_html(cell.children, buf)
  buf.write_string("</")
  buf.write_string(tag)
  buf.write_string(">\n")
}

///|
/// Render inline elements to HTML
fn render_inlines_html(inlines : Array[Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    render_inline_html(inline, buf)
  }
}

///|
/// Render a single inline element to HTML
fn render_inline_html(inline : Inline, buf : StringBuilder) -> Unit {
  match inline {
    Inline::Text(content~, ..) => buf.write_string(escape_html(content))
    Inline::Code(content~, ..) => {
      buf.write_string("<code>")
      buf.write_string(escape_html(content))
      buf.write_string("</code>")
    }
    Inline::Emphasis(children~, ..) => {
      buf.write_string("<em>")
      render_inlines_html(children, buf)
      buf.write_string("</em>")
    }
    Inline::Strong(children~, ..) => {
      buf.write_string("<strong>")
      render_inlines_html(children, buf)
      buf.write_string("</strong>")
    }
    Inline::Strikethrough(children~, ..) => {
      buf.write_string("<del>")
      render_inlines_html(children, buf)
      buf.write_string("</del>")
    }
    Inline::Link(children~, url~, title~, ..) => {
      buf.write_string("<a href=\"")
      buf.write_string(escape_html_attr(url))
      buf.write_char('"')
      if !(title.is_empty()) {
        buf.write_string(" title=\"")
        buf.write_string(escape_html_attr(title))
        buf.write_char('"')
      }
      buf.write_char('>')
      render_inlines_html(children, buf)
      buf.write_string("</a>")
    }
    Inline::RefLink(children~, label~, ..) => {
      // Reference links should be resolved before rendering
      // For now, render as plain text with the label
      buf.write_char('[')
      render_inlines_html(children, buf)
      buf.write_string("][")
      buf.write_string(escape_html(label))
      buf.write_char(']')
    }
    Inline::Autolink(url~, is_email~, ..) => {
      buf.write_string("<a href=\"")
      if is_email {
        buf.write_string("mailto:")
      }
      buf.write_string(escape_html_attr(url))
      buf.write_string("\">")
      buf.write_string(escape_html(url))
      buf.write_string("</a>")
    }
    Inline::Image(alt~, url~, title~, ..) => {
      buf.write_string("<img src=\"")
      buf.write_string(escape_html_attr(url))
      buf.write_string("\" alt=\"")
      buf.write_string(escape_html_attr(alt))
      buf.write_char('"')
      if !(title.is_empty()) {
        buf.write_string(" title=\"")
        buf.write_string(escape_html_attr(title))
        buf.write_char('"')
      }
      buf.write_string(">")
    }
    Inline::RefImage(alt~, label~, ..) => {
      // Reference images should be resolved before rendering
      buf.write_string("![")
      buf.write_string(escape_html(alt))
      buf.write_string("][")
      buf.write_string(escape_html(label))
      buf.write_char(']')
    }
    Inline::HtmlInline(html~, ..) => buf.write_string(html)
    Inline::SoftBreak(..) => buf.write_char('\n')
    Inline::HardBreak(..) => buf.write_string("<br>\n")
    Inline::FootnoteReference(label~, ..) => {
      buf.write_string("<sup><a href=\"#fn-")
      buf.write_string(escape_html_attr(label))
      buf.write_string("\" id=\"fnref-")
      buf.write_string(escape_html_attr(label))
      buf.write_string("\">")
      buf.write_string(escape_html(label))
      buf.write_string("</a></sup>")
    }
  }
}

///|
/// Escape HTML special characters in text content
fn escape_html(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Escape HTML special characters in attribute values
fn escape_html_attr(s : String) -> String {
  let buf = StringBuilder::new()
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
  buf.to_string()
}

///|
/// Parse markdown and render to HTML
pub fn md_to_html(source : String) -> String {
  let result = parse(source)
  render_html(result.document)
}

///|
/// Parse markdown and render to HTML (strict mode)
pub fn md_to_html_strict(source : String) -> String {
  let result = parse(source, strict=true)
  render_html(result.document)
}
