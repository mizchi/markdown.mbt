///| Lazily loadable CSS highlighter entry.

///|
pub fn highlight_css(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @css.highlight_css(source),
    @highlight_common.github_dark(),
  )
}
