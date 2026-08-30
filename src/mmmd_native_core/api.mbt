///| The output representation produced by the native mmmd binary.
pub(all) enum OutputFormat {
  /// Return normalized Markdown suitable for terminal display.
  Tui
  /// Render an HTML fragment.
  Html
}

///| Parse the command-line value for an output format.
pub fn OutputFormat::parse(value : String) -> OutputFormat? {
  match value {
    "tui" => Some(Tui)
    "html" => Some(Html)
    _ => None
  }
}

///| Render Markdown without depending on the JS/Wasm-only Mermaid renderer.
///| Mermaid remains an ordinary fenced code block in native TUI output.
pub fn render(source : String, format : OutputFormat) -> String {
  match format {
    Tui => @markdown.md_parse_and_render(source)
    Html => @markdown.md_to_html(source)
  }
}
