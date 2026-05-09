///| Shared HTML renderer for lazily loaded syntax highlighters.

///|
pub(all) struct HighlightTheme {
  name : String
  background : String
  foreground : String
  keyword : String
  operator : String
  punctuation : String
  string : String
  number : String
  bool : String
  null : String
  property : String
  variable : String
  function_ : String
  type_ : String
  class_ : String
  comment : String
  doc_comment : String
  regexp : String
  meta : String
  bracket : String
  tag : String
  invalid : String
}

///|
pub fn HighlightTheme::get_color(
  self : HighlightTheme,
  tag : @syntree.HighlightTag,
) -> String {
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

///|
pub fn github_dark() -> HighlightTheme {
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
priv struct ColoredToken {
  from : Int
  to : Int
  color : String
}

///|
pub fn tokens_to_html(
  source : String,
  tokens : Array[@syntree.HighlightToken],
  theme : HighlightTheme,
) -> String {
  let result = StringBuilder::new()
  let chars = source.to_array()
  let len = chars.length()
  result.write_string("<pre class=\"highlight ")
  result.write_string(theme.name)
  result.write_string("\" style=\"background-color: ")
  result.write_string(theme.background)
  result.write_string("; color: ")
  result.write_string(theme.foreground)
  result.write_string("\"><code>")
  let colored_tokens : Array[ColoredToken] = []
  for token in tokens {
    colored_tokens.push({
      from: token.from,
      to: token.to,
      color: theme.get_color(token.tag),
    })
  }
  let mut pos = 0
  let mut line_start = 0
  let mut in_line = false
  while pos <= len {
    let is_newline = pos < len && chars[pos] == '\n'
    let is_end = pos == len
    if !in_line {
      result.write_string("<span class=\"line\">")
      in_line = true
      line_start = pos
    }
    if is_newline || is_end {
      write_line_content(
        result,
        chars,
        line_start,
        pos,
        colored_tokens,
        theme.foreground,
      )
      result.write_string("</span>")
      in_line = false
      if is_newline {
        result.write_string("\n")
      }
      pos += 1
    } else {
      pos += 1
    }
  }
  result.write_string("</code></pre>")
  result.to_string()
}

///|
fn write_line_content(
  buf : StringBuilder,
  chars : Array[Char],
  line_start : Int,
  line_end : Int,
  tokens : Array[ColoredToken],
  default_color : String,
) -> Unit {
  let mut pos = line_start
  for token in tokens {
    if token.to <= line_start {
      continue
    }
    if token.from >= line_end {
      break
    }
    let token_start = if token.from > line_start {
      token.from
    } else {
      line_start
    }
    let token_end = if token.to < line_end { token.to } else { line_end }
    if token_start > pos {
      buf.write_string("<span style=\"color: ")
      buf.write_string(default_color)
      buf.write_string("\">")
      @syntree.escape_html_slice_to(chars, pos, token_start, buf)
      buf.write_string("</span>")
    }
    if token_end > token_start {
      buf.write_string("<span style=\"color: ")
      buf.write_string(token.color)
      buf.write_string("\">")
      @syntree.escape_html_slice_to(chars, token_start, token_end, buf)
      buf.write_string("</span>")
    }
    pos = token_end
  }
  if pos < line_end {
    buf.write_string("<span style=\"color: ")
    buf.write_string(default_color)
    buf.write_string("\">")
    @syntree.escape_html_slice_to(chars, pos, line_end, buf)
    buf.write_string("</span>")
  }
}
