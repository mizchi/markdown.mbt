///| Lazily loadable Rust highlighter entry.

///|
pub fn highlight_rust(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @rust.highlight_rust(source),
    @highlight_common.github_dark(),
  )
}
