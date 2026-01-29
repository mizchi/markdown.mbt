///| Syntax highlighting API exports

///|
/// Highlight TypeScript code to HTML
/// Theme: github-dark
pub fn highlight_typescript(source : String) -> String {
  @highlight.highlight_typescript(source, @highlight.github_dark())
}

///|
/// Highlight MoonBit code to HTML
/// Theme: github-dark
pub fn highlight_moonbit(source : String) -> String {
  @highlight.highlight_moonbit(source, @highlight.github_dark())
}

///|
/// Highlight JSON to HTML
/// Theme: github-dark
pub fn highlight_json(source : String) -> String {
  @highlight.highlight_json(source, @highlight.github_dark())
}

///|
/// Highlight HTML to HTML
/// Theme: github-dark
pub fn highlight_html(source : String) -> String {
  @highlight.highlight_html(source, @highlight.github_dark())
}

///|
/// Highlight CSS to HTML
/// Theme: github-dark
pub fn highlight_css(source : String) -> String {
  @highlight.highlight_css(source, @highlight.github_dark())
}

///|
/// Highlight Bash to HTML
/// Theme: github-dark
pub fn highlight_bash(source : String) -> String {
  @highlight.highlight_bash(source, @highlight.github_dark())
}

///|
/// Highlight Rust to HTML
/// Theme: github-dark
pub fn highlight_rust(source : String) -> String {
  @highlight.highlight_rust(source, @highlight.github_dark())
}
