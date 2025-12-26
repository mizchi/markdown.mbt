///| Shiki-compatible syntax highlighting output
///|
///| Generates HTML output compatible with Shiki's format:
///| - `<pre class="shiki" style="background-color: ..."><code>`
///| - `<span class="line">` for each line
///| - `<span style="color: ...">` for each token

// =============================================================================
// Theme Definition
// =============================================================================

///|
/// A syntax highlighting theme with colors for each token type
pub(all) struct ShikiTheme {
  /// Theme name (e.g., "github-dark", "vitesse-light")
  name : String
  /// Background color (e.g., "#0d1117")
  background : String
  /// Default foreground color
  foreground : String
  /// Color for keywords (fn, let, if, match, etc.)
  keyword : String
  /// Color for operators (+, -, =, etc.)
  operator : String
  /// Color for punctuation
  punctuation : String
  /// Color for strings
  string : String
  /// Color for numbers
  number : String
  /// Color for booleans (true, false)
  bool : String
  /// Color for null/none values
  null : String
  /// Color for property names
  property : String
  /// Color for variable names
  variable : String
  /// Color for function names
  function_ : String
  /// Color for type names
  type_ : String
  /// Color for class names
  class_ : String
  /// Color for comments
  comment : String
  /// Color for doc comments
  doc_comment : String
  /// Color for regex
  regexp : String
  /// Color for meta/decorators (@)
  meta : String
  /// Color for brackets [], braces {}, parens ()
  bracket : String
  /// Color for JSX/HTML tag names
  tag : String
  /// Color for invalid/error tokens
  invalid : String
}

///|
/// Get color for a highlight tag from theme
pub fn ShikiTheme::get_color(self : ShikiTheme, tag : @lezer.HighlightTag) -> String {
  match tag {
    Keyword => self.keyword
    Operator => self.operator
    Punctuation => self.punctuation
    String => self.string
    Number => self.number
    Bool => self.bool
    Null => self.null
    PropertyName => self.property
    VariableName => self.variable
    FunctionName => self.function_
    TypeName => self.type_
    ClassName => self.class_
    PrivateName => self.variable
    Comment => self.comment
    DocComment => self.doc_comment
    Regexp => self.regexp
    Meta => self.meta
    Bracket => self.bracket
    Brace => self.bracket
    Paren => self.bracket
    TagName => self.tag
    TagBracket => self.punctuation
    Invalid => self.invalid
    None => self.foreground
  }
}

// =============================================================================
// Built-in Themes
// =============================================================================

///|
/// GitHub Dark theme (similar to github-dark)
pub fn github_dark() -> ShikiTheme {
  {
    name: "github-dark",
    background: "#0d1117",
    foreground: "#c9d1d9",
    keyword: "#ff7b72",
    operator: "#ff7b72",
    punctuation: "#c9d1d9",
    string: "#a5d6ff",
    number: "#79c0ff",
    bool: "#79c0ff",
    null: "#79c0ff",
    property: "#7ee787",
    variable: "#c9d1d9",
    function_: "#d2a8ff",
    type_: "#ffa657",
    class_: "#ffa657",
    comment: "#8b949e",
    doc_comment: "#8b949e",
    regexp: "#7ee787",
    meta: "#d2a8ff",
    bracket: "#c9d1d9",
    tag: "#7ee787",
    invalid: "#f85149",
  }
}

///|
/// GitHub Light theme (similar to github-light)
pub fn github_light() -> ShikiTheme {
  {
    name: "github-light",
    background: "#ffffff",
    foreground: "#24292f",
    keyword: "#cf222e",
    operator: "#cf222e",
    punctuation: "#24292f",
    string: "#0a3069",
    number: "#0550ae",
    bool: "#0550ae",
    null: "#0550ae",
    property: "#116329",
    variable: "#24292f",
    function_: "#8250df",
    type_: "#953800",
    class_: "#953800",
    comment: "#6e7781",
    doc_comment: "#6e7781",
    regexp: "#116329",
    meta: "#8250df",
    bracket: "#24292f",
    tag: "#116329",
    invalid: "#cf222e",
  }
}

///|
/// One Dark Pro theme (similar to VS Code One Dark Pro)
pub fn one_dark_pro() -> ShikiTheme {
  {
    name: "one-dark-pro",
    background: "#282c34",
    foreground: "#abb2bf",
    keyword: "#c678dd",
    operator: "#56b6c2",
    punctuation: "#abb2bf",
    string: "#98c379",
    number: "#d19a66",
    bool: "#d19a66",
    null: "#d19a66",
    property: "#e06c75",
    variable: "#e06c75",
    function_: "#61afef",
    type_: "#e5c07b",
    class_: "#e5c07b",
    comment: "#5c6370",
    doc_comment: "#5c6370",
    regexp: "#98c379",
    meta: "#c678dd",
    bracket: "#abb2bf",
    tag: "#e06c75",
    invalid: "#f44747",
  }
}

///|
/// Vitesse Dark theme
pub fn vitesse_dark() -> ShikiTheme {
  {
    name: "vitesse-dark",
    background: "#121212",
    foreground: "#dbd7caee",
    keyword: "#4d9375",
    operator: "#cb7676",
    punctuation: "#858585",
    string: "#c98a7d",
    number: "#4c9a91",
    bool: "#4d9375",
    null: "#4d9375",
    property: "#b8a965",
    variable: "#dbd7caee",
    function_: "#80a665",
    type_: "#5da9a1",
    class_: "#5da9a1",
    comment: "#758575dd",
    doc_comment: "#758575dd",
    regexp: "#c4704f",
    meta: "#4d9375",
    bracket: "#858585",
    tag: "#4d9375",
    invalid: "#cb7676",
  }
}

// =============================================================================
// Shiki HTML Generation
// =============================================================================

///|
/// A positioned token with highlight information
priv struct ShikiToken {
  from : Int
  to : Int
  color : String
}

///|
/// Generate Shiki-compatible HTML from source and highlight tokens
pub fn tokens_to_shiki_html(
  source : String,
  tokens : Array[@lezer.HighlightToken],
  theme : ShikiTheme
) -> String {
  let result = StringBuilder::new()
  let chars = source.to_array()
  let len = chars.length()

  // Write opening pre/code tags
  result.write_string("<pre class=\"shiki ")
  result.write_string(theme.name)
  result.write_string("\" style=\"background-color: ")
  result.write_string(theme.background)
  result.write_string("; color: ")
  result.write_string(theme.foreground)
  result.write_string("\"><code>")

  // Convert tokens to positioned colored tokens
  let colored_tokens : Array[ShikiToken] = []
  for token in tokens {
    let color = theme.get_color(token.tag)
    colored_tokens.push({ from: token.from, to: token.to, color })
  }

  // Process line by line
  let mut pos = 0
  let mut line_start = 0
  let mut in_line = false

  while pos <= len {
    let is_newline = pos < len && chars[pos] == '\n'
    let is_end = pos == len

    if not(in_line) {
      result.write_string("<span class=\"line\">")
      in_line = true
      line_start = pos
    }

    if is_newline || is_end {
      // Write content up to newline/end
      write_line_content(
        result, chars, line_start, pos, colored_tokens, theme.foreground,
      )
      result.write_string("</span>")
      in_line = false
      if is_newline {
        result.write_string("\n")
      }
      pos = pos + 1
    } else {
      pos = pos + 1
    }
  }

  result.write_string("</code></pre>")
  result.to_string()
}

///|
/// Write content for a single line with proper token highlighting
fn write_line_content(
  buf : StringBuilder,
  chars : Array[Char],
  line_start : Int,
  line_end : Int,
  tokens : Array[ShikiToken],
  default_color : String
) -> Unit {
  let mut pos = line_start

  // Find tokens that overlap with this line
  for token in tokens {
    // Skip tokens before this line
    if token.to <= line_start {
      continue
    }
    // Stop if tokens are past this line
    if token.from >= line_end {
      break
    }

    // Calculate overlap
    let token_start = if token.from > line_start { token.from } else { line_start }
    let token_end = if token.to < line_end { token.to } else { line_end }

    // Write unhighlighted text before this token
    if token_start > pos {
      buf.write_string("<span style=\"color: ")
      buf.write_string(default_color)
      buf.write_string("\">")
      @lezer.escape_html_slice_to(chars, pos, token_start, buf)
      buf.write_string("</span>")
    }

    // Write highlighted token
    if token_end > token_start {
      buf.write_string("<span style=\"color: ")
      buf.write_string(token.color)
      buf.write_string("\">")
      @lezer.escape_html_slice_to(chars, token_start, token_end, buf)
      buf.write_string("</span>")
    }
    pos = token_end
  }

  // Write remaining unhighlighted text
  if pos < line_end {
    buf.write_string("<span style=\"color: ")
    buf.write_string(default_color)
    buf.write_string("\">")
    @lezer.escape_html_slice_to(chars, pos, line_end, buf)
    buf.write_string("</span>")
  }
}

// =============================================================================
// Convenience Functions
// =============================================================================

///|
/// Highlight TypeScript code to Shiki-compatible HTML
pub fn highlight_typescript_shiki(
  source : String,
  theme : ShikiTheme
) -> String {
  let tokens = @typescript.highlight_typescript(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight MoonBit code to Shiki-compatible HTML
pub fn highlight_moonbit_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @moonbit.highlight_moonbit(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight JSON to Shiki-compatible HTML
pub fn highlight_json_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @json.highlight_json(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight HTML to Shiki-compatible HTML
pub fn highlight_html_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @html.highlight_html(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight CSS to Shiki-compatible HTML
pub fn highlight_css_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @css.highlight_css(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight Bash to Shiki-compatible HTML
pub fn highlight_bash_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @bash.highlight_bash(source)
  tokens_to_shiki_html(source, tokens, theme)
}

///|
/// Highlight Rust to Shiki-compatible HTML
pub fn highlight_rust_shiki(source : String, theme : ShikiTheme) -> String {
  let tokens = @rust.highlight_rust(source)
  tokens_to_shiki_html(source, tokens, theme)
}
