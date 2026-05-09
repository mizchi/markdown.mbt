///| Lazily loadable Bash highlighter entry.

///|
pub fn highlight_bash(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @bash.highlight_bash(source),
    @highlight_common.github_dark(),
  )
}
