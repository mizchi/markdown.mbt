///| TUI-specific plugin support

///| Uses core plugin types from @markdown

///|
/// TUI renderer options with plugin support
pub struct TuiOptions {
  /// Custom code block highlighter
  code_highlighter : ((@markdown.CodeBlockInfo, String) -> String)?
}

///|
/// Create default TUI options
pub fn TuiOptions::default() -> TuiOptions {
  { code_highlighter: None }
}

///|
/// Create TUI options with custom code highlighter
pub fn TuiOptions::with_highlighter(
  highlighter : (@markdown.CodeBlockInfo, String) -> String,
) -> TuiOptions {
  { code_highlighter: Some(highlighter) }
}

///|
/// Create TUI options with simple highlighter (lang, code) -> String
pub fn TuiOptions::with_simple_highlighter(
  highlighter : (String, String) -> String,
) -> TuiOptions {
  {
    code_highlighter: Some(fn(
      info : @markdown.CodeBlockInfo,
      code : String,
    ) -> String {
      highlighter(info.lang, code)
    }),
  }
}

///|
/// Render document with options
pub fn render_tui_with_options(
  doc : @markdown.Document,
  options : TuiOptions,
) -> String {
  let buf = StringBuilder::new()
  for block in doc.children {
    render_block_tui_with_options(block, buf, options)
  }
  buf.to_string()
}

///|
/// Parse and render with options
pub fn md_to_tui_with_options(source : String, options : TuiOptions) -> String {
  let result = @markdown.parse(source)
  render_tui_with_options(result.document, options)
}

///|
/// Render block with options
fn render_block_tui_with_options(
  block : @markdown.Block,
  buf : StringBuilder,
  options : TuiOptions,
) -> Unit {
  match block {
    @markdown.Block::FencedCode(info~, code~, ..) =>
      match options.code_highlighter {
        Some(highlighter) => {
          // Parse info string and use custom highlighter
          let block_info = @markdown.parse_code_block_info(info)
          let highlighted = highlighter(block_info, code)
          buf.write_string(highlighted)
          buf.write_string("\n\n")
        }
        None =>
          // Use default rendering
          render_fenced_code_default(info, code, buf)
      }
    @markdown.Block::Paragraph(children~, ..) => {
      render_inlines_tui(children, buf)
      buf.write_string("\n\n")
    }
    @markdown.Block::Heading(level~, children~, ..) => {
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
      let prefix = "#".repeat(level)
      buf.write_string(prefix)
      buf.write_string(" ")
      render_inlines_tui_raw(children, buf)
      buf.write_string(reset)
      buf.write_string("\n\n")
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
    @markdown.Block::Blockquote(children~, ..) => {
      buf.write_string(dim)
      buf.write_string("│ ")
      buf.write_string(reset)
      buf.write_string(italic)
      for child in children {
        match child {
          @markdown.Block::Paragraph(children~, ..) =>
            render_inlines_tui_raw(children, buf)
          _ => render_block_tui_with_options(child, buf, options)
        }
      }
      buf.write_string(reset)
      buf.write_string("\n")
    }
    @markdown.Block::ThematicBreak(..) => {
      buf.write_string(dim)
      buf.write_string("─".repeat(40))
      buf.write_string(reset)
      buf.write_string("\n\n")
    }
    // Delegate other blocks to default renderer
    _ => render_block_tui(block, buf)
  }
}

///|
/// Default fenced code rendering (extracted for reuse)
fn render_fenced_code_default(
  info : String,
  code : String,
  buf : StringBuilder,
) -> Unit {
  // Calculate max line width
  let lines = code.split("\n").collect()
  let mut max_width = 0
  for i, line in lines {
    if i < lines.length() - 1 || !line.to_string().is_empty() {
      let w = line.to_string().iter().count()
      if w > max_width {
        max_width = w
      }
    }
  }
  let info_width = if info.is_empty() { 0 } else { info.iter().count() + 4 }
  if info_width > max_width {
    max_width = info_width
  }
  if max_width < 20 {
    max_width = 20
  }

  // Top border
  buf.write_string(dim)
  if !info.is_empty() {
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

  // Code content
  for i, line in lines {
    if i < lines.length() - 1 || !line.to_string().is_empty() {
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
}
