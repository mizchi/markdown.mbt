///| MDX Tokenizer Tests

// =============================================================================
// Helper Functions
// =============================================================================

fn token_types(source : String) -> Array[MdxTokenType] {
  let tokenizer = MdxTokenizer::new(source)
  let tokens = tokenizer.tokenize_all()
  let types : Array[MdxTokenType] = []
  for token in tokens {
    types.push(token.token_type)
  }
  types
}

fn token_texts(source : String) -> Array[String] {
  let tokenizer = MdxTokenizer::new(source)
  let tokens = tokenizer.tokenize_all()
  let texts : Array[String] = []
  for token in tokens {
    texts.push(source.unsafe_substring(start=token.from, end=token.to))
  }
  texts
}

// =============================================================================
// Markdown Basic Tests
// =============================================================================

test "tokenize heading" {
  let types = token_types("# Hello")
  assert_eq(types[0], HeadingMarker)
  // The rest is text (whitespace included in text for simplicity)
  assert_true(types.length() >= 2)
}

test "tokenize heading level 2" {
  let types = token_types("## Title")
  assert_eq(types[0], HeadingMarker)
  let texts = token_texts("## Title")
  assert_eq(texts[0], "##")
}

test "tokenize blockquote" {
  let types = token_types("> Quote")
  assert_eq(types[0], BlockQuoteMarker)
}

test "tokenize unordered list" {
  let types = token_types("- Item")
  assert_eq(types[0], ListMarker)
}

test "tokenize ordered list" {
  let types = token_types("1. Item")
  assert_eq(types[0], ListMarker)
  let texts = token_texts("1. Item")
  assert_eq(texts[0], "1.")
}

test "tokenize thematic break" {
  // Note: --- at file start is FrontmatterMarker in MDX
  // Use --- after a newline to get ThematicBreak
  let types = token_types("\n---")
  assert_eq(types[0], Newline)
  assert_eq(types[1], ThematicBreak)
}

test "tokenize code fence" {
  let source = "```js\ncode\n```"
  let types = token_types(source)
  assert_eq(types[0], CodeFence)
  assert_eq(types[1], CodeInfo)
  assert_eq(types[2], Newline)
  assert_eq(types[3], CodeContent)
  assert_eq(types[4], Newline)
  assert_eq(types[5], CodeFence)
}

test "tokenize inline code" {
  let types = token_types("Hello `code` world")
  assert_true(types.contains(InlineCode))
}

test "tokenize emphasis" {
  let types = token_types("*emphasis*")
  assert_eq(types[0], EmphasisMarker)
  assert_eq(types[1], Text)
  assert_eq(types[2], EmphasisMarker)
}

test "tokenize strong" {
  let types = token_types("**strong**")
  assert_eq(types[0], StrongMarker)
  assert_eq(types[1], Text)
  assert_eq(types[2], StrongMarker)
}

test "tokenize link" {
  let types = token_types("[text](url)")
  assert_eq(types[0], Link)
}

test "tokenize image" {
  let types = token_types("![alt](url)")
  assert_eq(types[0], Image)
}

// =============================================================================
// Frontmatter Tests
// =============================================================================

test "tokenize frontmatter" {
  let source = "---\ntitle: Hello\n---\n"
  let types = token_types(source)
  assert_eq(types[0], FrontmatterMarker)
  assert_eq(types[1], Newline)
  assert_eq(types[2], FrontmatterContent)
  assert_eq(types[3], Newline)
  assert_eq(types[4], FrontmatterMarker)
}

// =============================================================================
// Import/Export Tests
// =============================================================================

test "tokenize simple import" {
  let source = "import Button from './Button'"
  let types = token_types(source)
  assert_eq(types[0], ImportKeyword)
  assert_eq(types[1], JsIdentifier) // Button
  assert_eq(types[2], FromKeyword)
  assert_eq(types[3], JsString)
}

test "tokenize named import" {
  let source = "import { Button, Card } from './components'"
  let types = token_types(source)
  assert_eq(types[0], ImportKeyword)
  assert_eq(types[1], JsBrace) // {
  assert_true(types.contains(FromKeyword))
  assert_true(types.contains(JsString))
}

test "tokenize export const" {
  let source = "export const title = 'Hello'"
  let types = token_types(source)
  assert_eq(types[0], ExportKeyword)
  assert_eq(types[1], ConstKeyword)
  assert_eq(types[2], JsIdentifier)
}

test "tokenize export default" {
  let source = "export default Layout"
  let types = token_types(source)
  assert_eq(types[0], ExportKeyword)
  assert_eq(types[1], DefaultKeyword)
  assert_eq(types[2], JsIdentifier)
}

// =============================================================================
// JSX Tests
// =============================================================================

test "tokenize simple JSX" {
  let source = "<Button>Click</Button>"
  let types = token_types(source)
  assert_eq(types[0], JsxTagOpen)
  assert_eq(types[1], JsxTagName)
  assert_eq(types[2], JsxTagClose)
  assert_eq(types[3], JsxText)
  assert_eq(types[4], JsxCloseTag)
  assert_eq(types[5], JsxTagName)
  assert_eq(types[6], JsxTagClose)
}

test "tokenize self-closing JSX" {
  let source = "<Image />"
  let types = token_types(source)
  assert_eq(types[0], JsxTagOpen)
  assert_eq(types[1], JsxTagName)
  assert_eq(types[2], JsxTagClose) // />
}

test "tokenize JSX with attribute" {
  let source = "<Button variant=\"primary\">Click</Button>"
  let types = token_types(source)
  assert_true(types.contains(JsxAttribute))
  assert_true(types.contains(JsxEquals))
  assert_true(types.contains(JsString))
}

test "tokenize JSX with expression" {
  let source = "<Button onClick={handleClick}>Click</Button>"
  let types = token_types(source)
  assert_true(types.contains(JsxExprStart))
  assert_true(types.contains(JsIdentifier))
  assert_true(types.contains(JsxExprEnd))
}

test "tokenize web component" {
  let source = "<my-component>Content</my-component>"
  let types = token_types(source)
  assert_eq(types[0], JsxTagOpen)
  assert_eq(types[1], JsxTagName)
  let texts = token_texts(source)
  assert_eq(texts[1], "my-component")
}

// =============================================================================
// Mixed Content Tests
// =============================================================================

test "tokenize import then markdown" {
  let source = "import Button from './Button'\n\n# Hello"
  let types = token_types(source)
  assert_eq(types[0], ImportKeyword)
  assert_true(types.contains(HeadingMarker))
}

test "tokenize markdown then JSX" {
  let source = "# Title\n\n<Button>Click</Button>"
  let types = token_types(source)
  assert_eq(types[0], HeadingMarker)
  assert_true(types.contains(JsxTagOpen))
  assert_true(types.contains(JsxTagName))
}

test "tokenize full MDX document" {
  let source =
    #|---
    #|title: Hello
    #|---
    #|
    #|import Button from './Button'
    #|
    #|# Welcome
    #|
    #|<Button>Click me</Button>
    #|
  let types = token_types(source)

  // Should have frontmatter
  assert_true(types.contains(FrontmatterMarker))
  assert_true(types.contains(FrontmatterContent))

  // Should have import
  assert_true(types.contains(ImportKeyword))
  assert_true(types.contains(FromKeyword))

  // Should have heading
  assert_true(types.contains(HeadingMarker))

  // Should have JSX
  assert_true(types.contains(JsxTagOpen))
  assert_true(types.contains(JsxTagName))
}

// =============================================================================
// Additional Markdown Tests
// =============================================================================

test "tokenize heading levels 1-6" {
  for i = 1; i <= 6; i = i + 1 {
    let marker = "#".repeat(i)
    let source = marker + " Title"
    let texts = token_texts(source)
    assert_eq(texts[0], marker)
  }
}

test "tokenize thematic break with asterisks" {
  let types = token_types("\n***")
  assert_eq(types[1], ThematicBreak)
}

test "tokenize thematic break with underscores" {
  let types = token_types("\n___")
  assert_eq(types[1], ThematicBreak)
}

test "tokenize code fence with tilde" {
  let source = "~~~python\nprint('hello')\n~~~"
  let types = token_types(source)
  assert_eq(types[0], CodeFence)
  assert_eq(types[1], CodeInfo)
  let texts = token_texts(source)
  assert_eq(texts[1], "python")
}

test "tokenize code fence without info" {
  let source = "```\ncode\n```"
  let types = token_types(source)
  assert_eq(types[0], CodeFence)
  assert_eq(types[1], Newline) // No CodeInfo when empty
}

test "tokenize emphasis with underscore" {
  let types = token_types("_emphasis_")
  assert_eq(types[0], EmphasisMarker)
  assert_eq(types[1], Text)
  assert_eq(types[2], EmphasisMarker)
}

test "tokenize strong with underscore" {
  let types = token_types("__strong__")
  assert_eq(types[0], StrongMarker)
  assert_eq(types[1], Text)
  assert_eq(types[2], StrongMarker)
}

test "tokenize inline code with backticks" {
  let types = token_types("use `console.log()` here")
  assert_true(types.contains(InlineCode))
  assert_true(types.contains(Text))
}

test "tokenize multiple list items" {
  let source = "- first\n- second\n- third"
  let types = token_types(source)
  let count = types.iter().filter(fn(t) { t == ListMarker }).count()
  assert_eq(count, 3)
}

test "tokenize asterisk list" {
  let types = token_types("* Item")
  assert_eq(types[0], ListMarker)
}

test "tokenize plus list" {
  let types = token_types("+ Item")
  assert_eq(types[0], ListMarker)
}

test "tokenize nested blockquote markers" {
  let source = "> level1\n>> level2"
  let types = token_types(source)
  let count = types.iter().filter(fn(t) { t == BlockQuoteMarker }).count()
  assert_eq(count, 2)
}

// =============================================================================
// Additional Frontmatter Tests
// =============================================================================

test "tokenize multiline frontmatter" {
  let source =
    #|---
    #|title: Hello
    #|author: World
    #|date: 2024-01-01
    #|---
  let types = token_types(source)
  let content_count = types.iter().filter(fn(t) { t == FrontmatterContent }).count()
  assert_eq(content_count, 3)
}

// =============================================================================
// Additional Import/Export Tests
// =============================================================================

test "tokenize import star" {
  let source = "import * as React from 'react'"
  let types = token_types(source)
  assert_eq(types[0], ImportKeyword)
  assert_true(types.contains(AsKeyword))
  assert_true(types.contains(JsString))
}

test "tokenize multiple imports" {
  let source = "import A from 'a'\nimport B from 'b'"
  let types = token_types(source)
  let import_count = types.iter().filter(fn(t) { t == ImportKeyword }).count()
  assert_eq(import_count, 2)
}

test "tokenize export function" {
  let source = "export function getLayout() {}"
  let types = token_types(source)
  assert_eq(types[0], ExportKeyword)
  assert_true(types.contains(FunctionKeyword))
}

// =============================================================================
// Additional JSX Tests
// =============================================================================

test "tokenize JSX with multiple attributes" {
  let source = "<Button id=\"btn\" class=\"primary\" disabled>Click</Button>"
  let types = token_types(source)
  let attr_count = types.iter().filter(fn(t) { t == JsxAttribute }).count()
  assert_eq(attr_count, 3) // id, class, disabled
}

test "tokenize JSX with nested expression" {
  let source = "<Component data={{ key: 'value' }} />"
  let types = token_types(source)
  assert_true(types.contains(JsxExprStart))
  assert_true(types.contains(JsBrace))
}

test "tokenize JSX with boolean attribute" {
  let source = "<Input disabled />"
  let types = token_types(source)
  assert_true(types.contains(JsxAttribute))
}

test "tokenize inline JSX in paragraph" {
  let source = "Hello <Badge>new</Badge> world"
  let types = token_types(source)
  assert_true(types.contains(Text))
  assert_true(types.contains(JsxTagOpen))
  assert_true(types.contains(JsxText))
}

test "tokenize JSX with single quote attribute" {
  let source = "<Button value='test'>Click</Button>"
  let types = token_types(source)
  assert_true(types.contains(JsString))
}

test "tokenize JSX fragment-like" {
  let source = "<div><span>nested</span></div>"
  let types = token_types(source)
  let open_count = types.iter().filter(fn(t) { t == JsxTagOpen }).count()
  let close_count = types.iter().filter(fn(t) { t == JsxCloseTag }).count()
  assert_eq(open_count, 2)
  assert_eq(close_count, 2)
}

test "tokenize web component with data attribute" {
  let source = "<custom-element data-id=\"123\" />"
  let types = token_types(source)
  let texts = token_texts(source)
  assert_eq(texts[1], "custom-element")
  assert_true(types.contains(JsxAttribute))
}

// =============================================================================
// Edge Cases Tests
// =============================================================================

test "tokenize emphasis at line start after text" {
  let source = "text\n*emphasis*"
  let types = token_types(source)
  assert_true(types.contains(EmphasisMarker))
}

test "tokenize strong at line start after text" {
  let source = "text\n**strong**"
  let types = token_types(source)
  assert_true(types.contains(StrongMarker))
}

test "tokenize mixed inline elements" {
  let source = "**bold** and *italic* and `code`"
  let types = token_types(source)
  assert_true(types.contains(StrongMarker))
  assert_true(types.contains(EmphasisMarker))
  assert_true(types.contains(InlineCode))
}

test "tokenize empty JSX element" {
  let source = "<Empty></Empty>"
  let types = token_types(source)
  assert_eq(types[0], JsxTagOpen)
  assert_eq(types[1], JsxTagName)
  assert_eq(types[2], JsxTagClose)
  assert_eq(types[3], JsxCloseTag)
}

test "tokenize link with title" {
  let source = "[text](url \"title\")"
  let types = token_types(source)
  assert_eq(types[0], Link)
}

test "tokenize image with title" {
  let source = "![alt](url \"title\")"
  let types = token_types(source)
  assert_eq(types[0], Image)
}

// =============================================================================
// Complex Document Tests
// =============================================================================

test "tokenize blog post structure" {
  let source =
    #|---
    #|title: Blog Post
    #|---
    #|
    #|import { Author } from './components'
    #|
    #|# Introduction
    #|
    #|This is a **bold** statement.
    #|
    #|<Author name="John" />
    #|
    #|## Code Example
    #|
    #|```javascript
    #|console.log('hello')
    #|```
    #|
  let types = token_types(source)

  // Verify all major elements exist
  assert_true(types.contains(FrontmatterMarker))
  assert_true(types.contains(ImportKeyword))
  assert_true(types.contains(HeadingMarker))
  assert_true(types.contains(StrongMarker))
  assert_true(types.contains(JsxTagOpen))
  assert_true(types.contains(CodeFence))
  assert_true(types.contains(CodeInfo))
}

// =============================================================================
// Highlight Tests
// =============================================================================

test "highlight MDX returns tokens" {
  let source = "# Hello\n\n<Button>Click</Button>"
  let tokens = highlight_mdx(source)
  assert_true(tokens.length() > 0)
}

test "highlight_mdx_to_html generates HTML" {
  let source = "# Hello"
  let html = highlight_mdx_to_html(source)
  assert_true(html.contains("<span"))
}

test "highlight complex MDX" {
  let source =
    #|import Button from './Button'
    #|
    #|# Title
    #|
    #|<Button onClick={handler}>Click</Button>
  let tokens = highlight_mdx(source)
  assert_true(tokens.length() > 5)
}

test "highlight preserves positions" {
  let source = "# Hello"
  let tokens = highlight_mdx(source)
  for token in tokens {
    assert_true(token.from >= 0)
    assert_true(token.to <= source.length())
    assert_true(token.from < token.to)
  }
}
