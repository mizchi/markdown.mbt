///| MDX syntax highlighting

// =============================================================================
// MDX Highlighter
// =============================================================================

///|
/// Create a highlighter configured for MDX
pub fn mdx_highlighter() -> @lezer.Highlighter {
  let h = @lezer.Highlighter::new()

  // Markdown block elements
  h.add_rule("HeadingMarker", Keyword) // Use Keyword for headings
  h.add_rule("Heading", Keyword)
  h.add_rule("CodeFence", Meta)
  h.add_rule("CodeInfo", TypeName) // Use TypeName for language info
  h.add_rule("CodeContent", None) // No highlight for code content
  h.add_rule("BlockQuoteMarker", Punctuation)
  h.add_rule("ThematicBreak", Punctuation)
  h.add_rule("ListMarker", Punctuation)

  // Markdown inline elements
  h.add_rule("Text", None)
  h.add_rule("EmphasisMarker", Punctuation)
  h.add_rule("StrongMarker", Punctuation)
  h.add_rule("InlineCode", String) // Use String for inline code
  h.add_rule("Link", VariableName) // Use VariableName for links
  h.add_rule("Image", VariableName)
  h.add_rule("Autolink", VariableName)

  // Frontmatter
  h.add_rule("FrontmatterMarker", Meta)
  h.add_rule("FrontmatterContent", String)

  // JavaScript keywords
  h.add_rule("ImportKeyword", Keyword)
  h.add_rule("ExportKeyword", Keyword)
  h.add_rule("FromKeyword", Keyword)
  h.add_rule("AsKeyword", Keyword)
  h.add_rule("DefaultKeyword", Keyword)
  h.add_rule("ConstKeyword", Keyword)
  h.add_rule("FunctionKeyword", Keyword)
  h.add_rule("JsIdentifier", VariableName)
  h.add_rule("JsString", String)
  h.add_rule("JsOperator", Operator)
  h.add_rule("JsBrace", Brace)
  h.add_rule("JsComment", Comment)

  // JSX
  h.add_rule("JsxTagOpen", TagBracket)
  h.add_rule("JsxTagClose", TagBracket)
  h.add_rule("JsxCloseTag", TagBracket)
  h.add_rule("JsxTagName", TagName)
  h.add_rule("JsxAttribute", PropertyName)
  h.add_rule("JsxEquals", Operator)
  h.add_rule("JsxExprStart", Brace)
  h.add_rule("JsxExprEnd", Brace)
  h.add_rule("JsxText", None)

  // Special
  h.add_rule("Whitespace", None)
  h.add_rule("Newline", None)
  h.add_rule("Error", Invalid)
  h
}

///|
/// Convert token type to string for highlighter lookup
fn token_type_name(t : MdxTokenType) -> String {
  match t {
    // Markdown block
    Heading => "Heading"
    HeadingMarker => "HeadingMarker"
    Paragraph => "Paragraph"
    CodeBlock => "CodeBlock"
    CodeFence => "CodeFence"
    CodeInfo => "CodeInfo"
    CodeContent => "CodeContent"
    BlockQuote => "BlockQuote"
    BlockQuoteMarker => "BlockQuoteMarker"
    ThematicBreak => "ThematicBreak"
    ListMarker => "ListMarker"
    ListItem => "ListItem"
    HtmlBlock => "HtmlBlock"
    // Markdown inline
    Text => "Text"
    Emphasis => "Emphasis"
    EmphasisMarker => "EmphasisMarker"
    Strong => "Strong"
    StrongMarker => "StrongMarker"
    InlineCode => "InlineCode"
    InlineCodeMarker => "InlineCodeMarker"
    Link => "Link"
    LinkText => "LinkText"
    LinkUrl => "LinkUrl"
    LinkTitle => "LinkTitle"
    Image => "Image"
    Autolink => "Autolink"
    HardBreak => "HardBreak"
    // Frontmatter
    FrontmatterMarker => "FrontmatterMarker"
    FrontmatterContent => "FrontmatterContent"
    // JavaScript
    ImportKeyword => "ImportKeyword"
    ExportKeyword => "ExportKeyword"
    FromKeyword => "FromKeyword"
    AsKeyword => "AsKeyword"
    DefaultKeyword => "DefaultKeyword"
    ConstKeyword => "ConstKeyword"
    FunctionKeyword => "FunctionKeyword"
    JsIdentifier => "JsIdentifier"
    JsString => "JsString"
    JsOperator => "JsOperator"
    JsBrace => "JsBrace"
    JsComment => "JsComment"
    // JSX
    JsxTagOpen => "JsxTagOpen"
    JsxTagClose => "JsxTagClose"
    JsxCloseTag => "JsxCloseTag"
    JsxTagName => "JsxTagName"
    JsxAttribute => "JsxAttribute"
    JsxEquals => "JsxEquals"
    JsxExprStart => "JsxExprStart"
    JsxExprEnd => "JsxExprEnd"
    JsxText => "JsxText"
    // Special
    Whitespace => "Whitespace"
    Newline => "Newline"
    Error => "Error"
  }
}

///|
/// Highlight MDX source code
pub fn highlight_mdx(source : String) -> Array[@lezer.HighlightToken] {
  let tokenizer = MdxTokenizer::new(source)
  let tokens = tokenizer.tokenize_all()
  let highlighter = mdx_highlighter()
  let result : Array[@lezer.HighlightToken] = []
  for token in tokens {
    let name = token_type_name(token.token_type)
    let tag = highlighter.get_tag(name)
    if tag != @lezer.HighlightTag::None {
      result.push(@lezer.HighlightToken::new(token.from, token.to, tag))
    }
  }
  result
}

///|
/// Highlight MDX and generate HTML
pub fn highlight_mdx_to_html(source : String) -> String {
  let tokens = highlight_mdx(source)
  @lezer.tokens_to_html(source, tokens)
}
