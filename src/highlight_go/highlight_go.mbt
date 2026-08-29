///| Lazily loadable Go highlighter entry.

///|
pub fn highlight_go(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @go.highlight_go(source),
    @highlight_common.github_dark(),
  )
}
