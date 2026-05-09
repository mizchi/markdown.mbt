///| Lazily loadable HTML highlighter entry.

///|
pub fn highlight_html(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @html.highlight_html(source),
    @highlight_common.github_dark(),
  )
}
