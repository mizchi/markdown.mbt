///|
/// The output representation produced by mmmd.
pub(all) enum OutputFormat {
  /// Render a terminal-friendly representation, including Mermaid AA diagrams.
  Tui
  /// Render an HTML fragment.
  Html
}

///|
/// Parse the command-line value for an output format.
pub fn OutputFormat::parse(value : String) -> OutputFormat? {
  match value {
    "tui" => Some(Tui)
    "html" => Some(Html)
    _ => None
  }
}

///|
/// Render Markdown into the requested output format.
pub fn render(source : String, format : OutputFormat) -> String {
  match format {
    Tui => @tui.from_markdown(source)
    Html => @markdown.md_to_html(source)
  }
}
