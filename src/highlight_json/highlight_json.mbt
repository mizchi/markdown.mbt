///| Lazily loadable JSON highlighter entry.

///|
pub fn highlight_json(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @json.highlight_json(source),
    @highlight_common.github_dark(),
  )
}
