///| Rust syntax highlighting

// =============================================================================
// Rust Highlighter
// =============================================================================

///|
/// Create a highlighter configured for Rust
pub fn rust_highlighter() -> @lezer.Highlighter {
  let h = @lezer.Highlighter::new()

  // Keywords
  h.add_rule("Keyword", Keyword)
  h.add_rule("ControlFlow", Keyword)

  // Literals
  h.add_rule("String", String)
  h.add_rule("Char", String)
  h.add_rule("Number", Number)
  h.add_rule("Bool", Bool)

  // Names
  h.add_rule("Identifier", VariableName)
  h.add_rule("TypeName", TypeName)
  h.add_rule("Lifetime", Meta)

  // Macros
  h.add_rule("Macro", FunctionName)

  // Attributes
  h.add_rule("Attribute", Meta)

  // Operators
  h.add_rule("Operator", Operator)
  h.add_rule("Arrow", Operator)

  // Punctuation
  h.add_rule("BraceOpen", Brace)
  h.add_rule("BraceClose", Brace)
  h.add_rule("BracketOpen", Bracket)
  h.add_rule("BracketClose", Bracket)
  h.add_rule("ParenOpen", Paren)
  h.add_rule("ParenClose", Paren)
  h.add_rule("Semicolon", Punctuation)
  h.add_rule("Comma", Punctuation)
  h.add_rule("Dot", Punctuation)
  h.add_rule("Colon", Punctuation)
  h.add_rule("ColonColon", Punctuation)

  // Comments
  h.add_rule("LineComment", Comment)
  h.add_rule("BlockComment", Comment)
  h.add_rule("DocComment", DocComment)

  h
}

///|
/// Convert token type to string for highlighter lookup
fn token_type_name(t : RustTokenType) -> String {
  match t {
    Keyword => "Keyword"
    ControlFlow => "ControlFlow"
    String => "String"
    Char => "Char"
    Number => "Number"
    Bool => "Bool"
    Identifier => "Identifier"
    TypeName => "TypeName"
    Lifetime => "Lifetime"
    Macro => "Macro"
    Attribute => "Attribute"
    Operator => "Operator"
    Arrow => "Arrow"
    BraceOpen => "BraceOpen"
    BraceClose => "BraceClose"
    BracketOpen => "BracketOpen"
    BracketClose => "BracketClose"
    ParenOpen => "ParenOpen"
    ParenClose => "ParenClose"
    Semicolon => "Semicolon"
    Comma => "Comma"
    Dot => "Dot"
    Colon => "Colon"
    ColonColon => "ColonColon"
    LineComment => "LineComment"
    BlockComment => "BlockComment"
    DocComment => "DocComment"
    Error => "Error"
  }
}

///|
/// Highlight Rust source code
pub fn highlight_rust(source : String) -> Array[@lezer.HighlightToken] {
  let tokenizer = RustTokenizer::new(source)
  let tokens = tokenizer.tokenize_all()
  let highlighter = rust_highlighter()
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
/// Convenience: highlight Rust and generate HTML
pub fn highlight_rust_to_html(source : String) -> String {
  let tokens = highlight_rust(source)
  @lezer.tokens_to_html(source, tokens)
}
