///| TUI Renderer
///| Renders markdown AST to terminal with ANSI escape codes

///| Render a document to terminal string
pub fn render_tui(doc : @markdown.Document) -> String {
  let buf = StringBuilder::new()
  for block in doc.children {
    render_block_tui(block, buf)
  }
  buf.to_string()
}

///| Render a block element to terminal
fn render_block_tui(block : @markdown.Block, buf : StringBuilder) -> Unit {
  match block {
    @markdown.Block::Paragraph(children~, ..) => {
      render_inlines_tui(children, buf)
      buf.write_string("\n\n")
    }

    @markdown.Block::Heading(level~, children~, ..) => {
      // Headings: bold + color based on level
      let color = match level {
        1 => bright_magenta
        2 => bright_blue
        3 => bright_cyan
        4 => bright_green
        5 => bright_yellow
        _ => white
      }
      buf.write_string(bold)
      buf.write_string(color)
      // Add prefix
      let prefix = "#".repeat(level)
      buf.write_string(prefix)
      buf.write_string(" ")
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
      buf.write_string("\n\n")
    }

    @markdown.Block::ThematicBreak(..) => {
      buf.write_string(dim)
      buf.write_string("─".repeat(40))
      buf.write_string(reset)
      buf.write_string("\n\n")
    }

    @markdown.Block::FencedCode(info~, code~, ..) => {
      // Calculate max line width
      let lines = code.split("\n").collect()
      let mut max_width = 0
      for i, line in lines {
        if i < lines.length() - 1 || not(line.to_string().is_empty()) {
          let w = line.to_string().iter().count()
          if w > max_width {
            max_width = w
          }
        }
      }
      // Minimum width for info string
      let info_width = if info.is_empty() { 0 } else { info.iter().count() + 4 }
      if info_width > max_width {
        max_width = info_width
      }
      // At least 20 chars wide
      if max_width < 20 {
        max_width = 20
      }

      // Top border
      buf.write_string(dim)
      if not(info.is_empty()) {
        buf.write_string("┌─ ")
        buf.write_string(info)
        buf.write_string(" ")
        let remaining = max_width - info.iter().count() - 1
        buf.write_string("─".repeat(remaining))
        buf.write_string("┐")
      } else {
        buf.write_string("┌")
        buf.write_string("─".repeat(max_width + 2))
        buf.write_string("┐")
      }
      buf.write_string(reset)
      buf.write_string("\n")

      // Code content with right border
      for i, line in lines {
        if i < lines.length() - 1 || not(line.to_string().is_empty()) {
          buf.write_string(dim)
          buf.write_string("│")
          buf.write_string(reset)
          buf.write_string(cyan)
          buf.write_string(" ")
          let line_str = line.to_string()
          buf.write_string(line_str)
          let padding = max_width - line_str.iter().count()
          buf.write_string(" ".repeat(padding))
          buf.write_string(reset)
          buf.write_string(dim)
          buf.write_string(" │")
          buf.write_string(reset)
          buf.write_string("\n")
        }
      }

      // Bottom border
      buf.write_string(dim)
      buf.write_string("└")
      buf.write_string("─".repeat(max_width + 2))
      buf.write_string("┘")
      buf.write_string(reset)
      buf.write_string("\n\n")
    }

    @markdown.Block::IndentedCode(code~, ..) => {
      buf.write_string(cyan)
      let lines = code.split("\n").collect()
      for i, line in lines {
        if i < lines.length() - 1 || not(line.to_string().is_empty()) {
          buf.write_string("    ")
          buf.write_string(line.to_string())
          buf.write_string("\n")
        }
      }
      buf.write_string(reset)
      buf.write_string("\n")
    }

    @markdown.Block::Blockquote(children~, ..) => {
      buf.write_string(dim)
      buf.write_string("│ ")
      buf.write_string(reset)
      buf.write_string(italic)
      for child in children {
        render_block_tui_inline(child, buf)
      }
      buf.write_string(reset)
      buf.write_string("\n")
    }

    @markdown.Block::BulletList(items~, ..) => {
      for item in items {
        render_list_item_tui(item, buf, "•")
      }
      buf.write_string("\n")
    }

    @markdown.Block::OrderedList(items~, start~, ..) => {
      for i, item in items {
        let num = (start + i).to_string() + "."
        render_list_item_tui(item, buf, num)
      }
      buf.write_string("\n")
    }

    @markdown.Block::HtmlBlock(html~, ..) => {
      buf.write_string(dim)
      buf.write_string(html)
      buf.write_string(reset)
      if not(html.has_suffix("\n")) {
        buf.write_string("\n")
      }
    }

    @markdown.Block::Table(header~, rows~, ..) => {
      // Calculate column widths
      let col_count = header.length()
      let widths : Array[Int] = Array::make(col_count, 0)

      // Measure header widths
      for i, cell in header {
        let w = measure_inlines_width(cell.children)
        if w > widths[i] {
          widths[i] = w
        }
      }

      // Measure row widths
      for row in rows {
        for i, cell in row {
          if i < col_count {
            let w = measure_inlines_width(cell.children)
            if w > widths[i] {
              widths[i] = w
            }
          }
        }
      }

      // Header
      buf.write_string(bold)
      buf.write_string("│")
      for i, cell in header {
        buf.write_string(" ")
        let cell_buf = StringBuilder::new()
        render_inlines_tui_raw(cell.children, cell_buf)
        let content = cell_buf.to_string()
        buf.write_string(content)
        let padding = widths[i] - measure_inlines_width(cell.children)
        buf.write_string(" ".repeat(padding))
        buf.write_string(" │")
      }
      buf.write_string(reset)
      buf.write_string("\n")

      // Separator
      buf.write_string(dim)
      buf.write_string("├")
      for i, _ in header {
        if i > 0 {
          buf.write_string("┼")
        }
        buf.write_string("─".repeat(widths[i] + 2))
      }
      buf.write_string("┤")
      buf.write_string(reset)
      buf.write_string("\n")

      // Rows
      for row in rows {
        buf.write_string("│")
        for i = 0; i < col_count; i = i + 1 {
          buf.write_string(" ")
          if i < row.length() {
            let cell = row[i]
            let cell_buf = StringBuilder::new()
            render_inlines_tui_raw(cell.children, cell_buf)
            let content = cell_buf.to_string()
            buf.write_string(content)
            let padding = widths[i] - measure_inlines_width(cell.children)
            buf.write_string(" ".repeat(padding))
          } else {
            buf.write_string(" ".repeat(widths[i]))
          }
          buf.write_string(" │")
        }
        buf.write_string("\n")
      }
      buf.write_string("\n")
    }

    @markdown.Block::BlankLines(..) => ()

    @markdown.Block::FootnoteDefinition(label~, children~, ..) => {
      buf.write_string(dim)
      buf.write_string("[^")
      buf.write_string(label)
      buf.write_string("]: ")
      buf.write_string(reset)
      for child in children {
        render_block_tui_inline(child, buf)
      }
      buf.write_string("\n")
    }
  }
}

///| Measure the display width of inline elements (excluding ANSI codes)
fn measure_inlines_width(inlines : Array[@markdown.Inline]) -> Int {
  let mut width = 0
  for inline in inlines {
    width = width + measure_inline_width(inline)
  }
  width
}

///| Measure display width of a single inline element
fn measure_inline_width(inline : @markdown.Inline) -> Int {
  match inline {
    @markdown.Inline::Text(content~, ..) => content.iter().count()
    @markdown.Inline::Code(content~, ..) => content.iter().count() + 2 // backticks
    @markdown.Inline::Emphasis(children~, ..) => measure_inlines_width(children)
    @markdown.Inline::Strong(children~, ..) => measure_inlines_width(children)
    @markdown.Inline::Strikethrough(children~, ..) => measure_inlines_width(children)
    @markdown.Inline::Link(children~, ..) => measure_inlines_width(children)
    @markdown.Inline::RefLink(children~, ..) => measure_inlines_width(children)
    @markdown.Inline::Autolink(url~, ..) => url.iter().count()
    @markdown.Inline::Image(alt~, ..) => alt.iter().count() + 2 // emoji
    @markdown.Inline::RefImage(alt~, ..) => alt.iter().count() + 2
    @markdown.Inline::HtmlInline(html~, ..) => html.iter().count()
    @markdown.Inline::SoftBreak(..) => 0
    @markdown.Inline::HardBreak(..) => 0
    @markdown.Inline::FootnoteReference(label~, ..) => label.iter().count() + 3 // [^]
  }
}

///| Render block inline (for blockquote content)
fn render_block_tui_inline(block : @markdown.Block, buf : StringBuilder) -> Unit {
  match block {
    @markdown.Block::Paragraph(children~, ..) => {
      render_inlines_tui_raw(children, buf)
    }
    _ => render_block_tui(block, buf)
  }
}

///| Render a list item
fn render_list_item_tui(item : @markdown.ListItem, buf : StringBuilder, marker : String) -> Unit {
  // Task list checkbox
  match item.checked {
    Some(true) => {
      buf.write_string(green)
      buf.write_string("  ☑ ")
      buf.write_string(reset)
    }
    Some(false) => {
      buf.write_string(dim)
      buf.write_string("  ☐ ")
      buf.write_string(reset)
    }
    None => {
      buf.write_string(yellow)
      buf.write_string("  ")
      buf.write_string(marker)
      buf.write_string(" ")
      buf.write_string(reset)
    }
  }

  for child in item.children {
    match child {
      @markdown.Block::Paragraph(children~, ..) => render_inlines_tui(children, buf)
      _ => render_block_tui(child, buf)
    }
  }
  buf.write_string("\n")
}

///| Render inline elements
fn render_inlines_tui(inlines : Array[@markdown.Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    render_inline_tui(inline, buf)
  }
}

///| Render inline elements without trailing reset
fn render_inlines_tui_raw(inlines : Array[@markdown.Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    render_inline_tui(inline, buf)
  }
}

///| Render a single inline element
fn render_inline_tui(inline : @markdown.Inline, buf : StringBuilder) -> Unit {
  match inline {
    @markdown.Inline::Text(content~, ..) => {
      buf.write_string(content)
    }

    @markdown.Inline::Code(content~, ..) => {
      buf.write_string(bg_black)
      buf.write_string(cyan)
      buf.write_string("`")
      buf.write_string(content)
      buf.write_string("`")
      buf.write_string(reset)
    }

    @markdown.Inline::Emphasis(children~, ..) => {
      buf.write_string(italic)
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
    }

    @markdown.Inline::Strong(children~, ..) => {
      buf.write_string(bold)
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
    }

    @markdown.Inline::Strikethrough(children~, ..) => {
      buf.write_string(strikethrough)
      buf.write_string(dim)
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
    }

    @markdown.Inline::Link(children~, url~, ..) => {
      buf.write_string(underline)
      buf.write_string(blue)
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
      buf.write_string(dim)
      buf.write_string(" (")
      buf.write_string(url)
      buf.write_string(")")
      buf.write_string(reset)
    }

    @markdown.Inline::RefLink(children~, label~, ..) => {
      buf.write_string(underline)
      buf.write_string(blue)
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
      buf.write_string(dim)
      buf.write_string("[")
      buf.write_string(label)
      buf.write_string("]")
      buf.write_string(reset)
    }

    @markdown.Inline::Autolink(url~, ..) => {
      buf.write_string(underline)
      buf.write_string(blue)
      buf.write_string(url)
      buf.write_string(reset)
    }

    @markdown.Inline::Image(alt~, url~, ..) => {
      buf.write_string(magenta)
      buf.write_string("🖼 ")
      buf.write_string(alt)
      buf.write_string(reset)
      buf.write_string(dim)
      buf.write_string(" (")
      buf.write_string(url)
      buf.write_string(")")
      buf.write_string(reset)
    }

    @markdown.Inline::RefImage(alt~, label~, ..) => {
      buf.write_string(magenta)
      buf.write_string("🖼 ")
      buf.write_string(alt)
      buf.write_string(reset)
      buf.write_string(dim)
      buf.write_string("[")
      buf.write_string(label)
      buf.write_string("]")
      buf.write_string(reset)
    }

    @markdown.Inline::HtmlInline(html~, ..) => {
      buf.write_string(dim)
      buf.write_string(html)
      buf.write_string(reset)
    }

    @markdown.Inline::SoftBreak(..) => {
      buf.write_string("\n")
    }

    @markdown.Inline::HardBreak(..) => {
      buf.write_string("\n")
    }

    @markdown.Inline::FootnoteReference(label~, ..) => {
      buf.write_string(bright_cyan)
      buf.write_string("[^")
      buf.write_string(label)
      buf.write_string("]")
      buf.write_string(reset)
    }
  }
}

///| Parse markdown and render to terminal
pub fn md_to_tui(source : String) -> String {
  let result = @markdown.parse(source)
  render_tui(result.document)
}
