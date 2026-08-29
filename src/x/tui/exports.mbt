///|
/// TUI module exports

// Re-export main functions
pub fn render(doc : @markdown.Document) -> String {
  render_tui(doc)
}

///|
pub fn from_markdown(source : String) -> String {
  md_to_tui(source)
}
