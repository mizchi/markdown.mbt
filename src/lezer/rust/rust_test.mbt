///| Rust tokenizer tests

// =============================================================================
// Basic Token Tests
// =============================================================================

test "rust: keywords" {
  let tokenizer = RustTokenizer::new("fn let mut const pub struct enum impl trait")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 9)
  assert_eq!(tokens[0].token_type, Keyword)  // fn
  assert_eq!(tokens[1].token_type, Keyword)  // let
  assert_eq!(tokens[2].token_type, Keyword)  // mut
  assert_eq!(tokens[3].token_type, Keyword)  // const
  assert_eq!(tokens[4].token_type, Keyword)  // pub
  assert_eq!(tokens[5].token_type, Keyword)  // struct
  assert_eq!(tokens[6].token_type, Keyword)  // enum
  assert_eq!(tokens[7].token_type, Keyword)  // impl
  assert_eq!(tokens[8].token_type, Keyword)  // trait
}

test "rust: control flow" {
  let tokenizer = RustTokenizer::new("if else match loop while for return break continue")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 9)
  for token in tokens {
    assert_eq!(token.token_type, ControlFlow)
  }
}

test "rust: boolean literals" {
  let tokenizer = RustTokenizer::new("true false")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 2)
  assert_eq!(tokens[0].token_type, Bool)
  assert_eq!(tokens[1].token_type, Bool)
}

test "rust: string literal" {
  let tokenizer = RustTokenizer::new("\"hello world\"")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, String)
}

test "rust: raw string" {
  let tokenizer = RustTokenizer::new("r\"raw string\"")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, String)
}

test "rust: raw string with hashes" {
  let tokenizer = RustTokenizer::new("r#\"contains \" quote\"#")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, String)
}

test "rust: character literal" {
  let tokenizer = RustTokenizer::new("'a' '\\n' '\\''")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 3)
  for token in tokens {
    assert_eq!(token.token_type, Char)
  }
}

test "rust: lifetime" {
  let tokenizer = RustTokenizer::new("'a 'static 'lifetime")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 3)
  for token in tokens {
    assert_eq!(token.token_type, Lifetime)
  }
}

test "rust: numbers" {
  let tokenizer = RustTokenizer::new("123 0x1F 0b101 0o17 1.5 1e10 1_000_000")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 7)
  for token in tokens {
    assert_eq!(token.token_type, Number)
  }
}

test "rust: number with suffix" {
  let tokenizer = RustTokenizer::new("123u32 45i64 1.5f32")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 3)
  for token in tokens {
    assert_eq!(token.token_type, Number)
  }
}

test "rust: type names" {
  let tokenizer = RustTokenizer::new("String Vec Option Result Box")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 5)
  for token in tokens {
    assert_eq!(token.token_type, TypeName)
  }
}

test "rust: primitive types" {
  let tokenizer = RustTokenizer::new("u8 u32 i64 f32 bool str char")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 7)
  for token in tokens {
    assert_eq!(token.token_type, TypeName)
  }
}

test "rust: identifiers" {
  let tokenizer = RustTokenizer::new("foo bar_baz _private")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 3)
  for token in tokens {
    assert_eq!(token.token_type, Identifier)
  }
}

test "rust: macros" {
  let tokenizer = RustTokenizer::new("println! vec! format! assert_eq!")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 4)
  for token in tokens {
    assert_eq!(token.token_type, Macro)
  }
}

test "rust: attributes" {
  let tokenizer = RustTokenizer::new("#[derive(Debug)]")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, Attribute)
}

test "rust: inner attribute" {
  let tokenizer = RustTokenizer::new("#![allow(unused)]")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, Attribute)
}

test "rust: line comment" {
  let tokenizer = RustTokenizer::new("// this is a comment")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, LineComment)
}

test "rust: doc comment" {
  let tokenizer = RustTokenizer::new("/// documentation")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, DocComment)
}

test "rust: inner doc comment" {
  let tokenizer = RustTokenizer::new("//! module documentation")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, DocComment)
}

test "rust: block comment" {
  let tokenizer = RustTokenizer::new("/* block comment */")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, BlockComment)
}

test "rust: nested block comment" {
  let tokenizer = RustTokenizer::new("/* outer /* inner */ outer */")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 1)
  assert_eq!(tokens[0].token_type, BlockComment)
}

test "rust: arrow operators" {
  let tokenizer = RustTokenizer::new("-> =>")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 2)
  assert_eq!(tokens[0].token_type, Arrow)
  assert_eq!(tokens[1].token_type, Arrow)
}

test "rust: double colon" {
  let tokenizer = RustTokenizer::new("std::collections::HashMap")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 5)
  assert_eq!(tokens[0].token_type, Identifier)
  assert_eq!(tokens[1].token_type, ColonColon)
  assert_eq!(tokens[2].token_type, Identifier)
  assert_eq!(tokens[3].token_type, ColonColon)
  assert_eq!(tokens[4].token_type, TypeName)
}

test "rust: punctuation" {
  let tokenizer = RustTokenizer::new("{} [] () ; , . :")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 10)
  assert_eq!(tokens[0].token_type, BraceOpen)
  assert_eq!(tokens[1].token_type, BraceClose)
  assert_eq!(tokens[2].token_type, BracketOpen)
  assert_eq!(tokens[3].token_type, BracketClose)
  assert_eq!(tokens[4].token_type, ParenOpen)
  assert_eq!(tokens[5].token_type, ParenClose)
  assert_eq!(tokens[6].token_type, Semicolon)
  assert_eq!(tokens[7].token_type, Comma)
  assert_eq!(tokens[8].token_type, Dot)
  assert_eq!(tokens[9].token_type, Colon)
}

test "rust: operators" {
  let tokenizer = RustTokenizer::new("+ - * / % == != < > && ||")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 11)
  for token in tokens {
    assert_eq!(token.token_type, Operator)
  }
}

test "rust: range operators" {
  let tokenizer = RustTokenizer::new(".. ..= ...")
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 3)
  for token in tokens {
    assert_eq!(token.token_type, Operator)
  }
}

// =============================================================================
// Complex Code Tests
// =============================================================================

test "rust: function definition" {
  let code = "fn main() -> i32 { 0 }"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, Keyword)     // fn
  assert_eq!(tokens[1].token_type, Identifier)  // main
  assert_eq!(tokens[2].token_type, ParenOpen)   // (
  assert_eq!(tokens[3].token_type, ParenClose)  // )
  assert_eq!(tokens[4].token_type, Arrow)       // ->
  assert_eq!(tokens[5].token_type, TypeName)    // i32
  assert_eq!(tokens[6].token_type, BraceOpen)   // {
  assert_eq!(tokens[7].token_type, Number)      // 0
  assert_eq!(tokens[8].token_type, BraceClose)  // }
}

test "rust: struct definition" {
  let code = "pub struct Point { x: f64, y: f64 }"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, Keyword)     // pub
  assert_eq!(tokens[1].token_type, Keyword)     // struct
  assert_eq!(tokens[2].token_type, TypeName)    // Point
}

test "rust: impl block" {
  let code = "impl MyTrait for MyStruct {}"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, Keyword)     // impl
  assert_eq!(tokens[1].token_type, TypeName)    // MyTrait
  assert_eq!(tokens[2].token_type, ControlFlow) // for (it's control flow in other contexts)
  assert_eq!(tokens[3].token_type, TypeName)    // MyStruct
}

test "rust: match expression" {
  let code = "match x { Some(v) => v, None => 0 }"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, ControlFlow) // match
  assert_eq!(tokens[1].token_type, Identifier)  // x
}

test "rust: lifetime in function" {
  let code = "fn foo<'a>(x: &'a str) -> &'a str { x }"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, Keyword)     // fn
  assert_eq!(tokens[1].token_type, Identifier)  // foo
  assert_eq!(tokens[2].token_type, Operator)    // <
  assert_eq!(tokens[3].token_type, Lifetime)    // 'a
}

test "rust: macro invocation" {
  let code = "println!(\"Hello, {}!\", name);"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens[0].token_type, Macro)       // println!
  assert_eq!(tokens[1].token_type, ParenOpen)   // (
  assert_eq!(tokens[2].token_type, String)      // "Hello, {}!"
}

test "rust: byte string and char" {
  let code = "b\"bytes\" b'x'"
  let tokenizer = RustTokenizer::new(code)
  let tokens = tokenizer.tokenize_all()
  assert_eq!(tokens.length(), 2)
  assert_eq!(tokens[0].token_type, String)
  assert_eq!(tokens[1].token_type, Char)
}

// =============================================================================
// Highlight Tests
// =============================================================================

test "rust: highlight produces tokens" {
  let code = "fn main() { println!(\"Hello\"); }"
  let tokens = highlight_rust(code)
  assert_true!(tokens.length() > 0)
}

test "rust: highlight_to_html produces HTML" {
  let code = "let x = 42;"
  let html = highlight_rust_to_html(code)
  assert_true!(html.contains("<span"))
  assert_true!(html.contains("let"))
  assert_true!(html.contains("42"))
}
