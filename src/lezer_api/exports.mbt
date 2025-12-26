///| Syntax highlighting API exports

///|
/// Highlight TypeScript code to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_typescript(source : String) -> String {
  @shiki.highlight_typescript_shiki(source, @shiki.github_dark())
}

///|
/// Highlight MoonBit code to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_moonbit(source : String) -> String {
  @shiki.highlight_moonbit_shiki(source, @shiki.github_dark())
}

///|
/// Highlight JSON to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_json(source : String) -> String {
  @shiki.highlight_json_shiki(source, @shiki.github_dark())
}

///|
/// Highlight HTML to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_html(source : String) -> String {
  @shiki.highlight_html_shiki(source, @shiki.github_dark())
}

///|
/// Highlight CSS to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_css(source : String) -> String {
  @shiki.highlight_css_shiki(source, @shiki.github_dark())
}

///|
/// Highlight Bash to Shiki-compatible HTML
/// Theme: github-dark
pub fn highlight_bash(source : String) -> String {
  @shiki.highlight_bash_shiki(source, @shiki.github_dark())
}
