///| Lazily loadable MoonBit highlighter entry.

///|
pub fn highlight_moonbit(source : String) -> String {
  @highlight_common.tokens_to_html(
    source,
    @moonbit.highlight_moonbit(source),
    @highlight_common.github_dark(),
  )
}
