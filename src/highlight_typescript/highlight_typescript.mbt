///| Lazily loadable TypeScript highlighter entry.

///|
pub fn highlight_typescript(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @typescript.highlight_typescript(source),
    @highlight_common.github_dark(),
  )
}
