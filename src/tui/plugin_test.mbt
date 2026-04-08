///|
/// Plugin system tests with reference implementations

// =============================================================================
// Core plugin tests (using @markdown.CodeBlockInfo)
// =============================================================================

test "plugin: default options" {
  let options = TuiOptions::default()
  let output = md_to_tui_with_options("# Hello\n", options)
  inspect(output.contains("Hello"), content="true")
}

///|
test "plugin: parse_code_block_info simple lang" {
  let info = @markdown.parse_code_block_info("javascript")
  inspect(info.lang, content="javascript")
  inspect(info.filename, content="")
  inspect(info.meta, content="")
}

///|
test "plugin: parse_code_block_info with filename" {
  let info = @markdown.parse_code_block_info("js:app.js")
  inspect(info.lang, content="js")
  inspect(info.filename, content="app.js")
  inspect(info.meta, content="")
}

///|
test "plugin: parse_code_block_info with meta" {
  let info = @markdown.parse_code_block_info("ts:index.ts {highlight=[1,3]}")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="index.ts")
  inspect(info.meta, content="{highlight=[1,3]}")
}

///|
test "plugin: parse_code_block_info preserves emoji filename" {
  let info = @markdown.parse_code_block_info("ts:src/😀.ts")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="src/😀.ts")
  inspect(info.meta, content="")
}

///|
test "plugin: parse_code_block_info preserves emoji meta" {
  let info = @markdown.parse_code_block_info("ts:index.ts {title=😀}")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="index.ts")
  inspect(info.meta, content="{title=😀}")
}

///|
test "plugin: parse_code_block_info empty" {
  let info = @markdown.parse_code_block_info("")
  inspect(info.lang, content="")
  inspect(info.filename, content="")
  inspect(info.meta, content="")
}

// =============================================================================
// Reference Implementation: Simple ANSI Highlighter
// =============================================================================

///|
/// Reference implementation: Simple keyword-based syntax highlighter
fn reference_keyword_highlighter(
  info : @markdown.CodeBlockInfo,
  code : String,
) -> String {
  let buf = StringBuilder::new()

  // Header with language
  buf.write_string(bold)
  buf.write_string(bright_cyan)
  buf.write_string("─── ")
  buf.write_string(info.lang)
  if !info.filename.is_empty() {
    buf.write_string(": ")
    buf.write_string(info.filename)
  }
  buf.write_string(" ───")
  buf.write_string(reset)
  buf.write_string("\n")

  // Simple keyword highlighting based on language
  let highlighted = match info.lang {
    "rust" | "rs" => highlight_rust_keywords(code)
    "javascript" | "js" | "typescript" | "ts" => highlight_js_keywords(code)
    "python" | "py" => highlight_python_keywords(code)
    _ => code // No highlighting for unknown languages
  }
  buf.write_string(highlighted)
  buf.to_string()
}

///|
/// Highlight Rust keywords
fn highlight_rust_keywords(code : String) -> String {
  code
  .replace(old="fn ", new="\u001b[35mfn \u001b[0m")
  .replace(old="let ", new="\u001b[35mlet \u001b[0m")
  .replace(old="mut ", new="\u001b[35mmut \u001b[0m")
  .replace(old="pub ", new="\u001b[35mpub \u001b[0m")
  .replace(old="struct ", new="\u001b[35mstruct \u001b[0m")
  .replace(old="impl ", new="\u001b[35mimpl \u001b[0m")
  .replace(old="use ", new="\u001b[35muse \u001b[0m")
}

///|
/// Highlight JavaScript/TypeScript keywords
fn highlight_js_keywords(code : String) -> String {
  code
  .replace(old="const ", new="\u001b[35mconst \u001b[0m")
  .replace(old="let ", new="\u001b[35mlet \u001b[0m")
  .replace(old="var ", new="\u001b[35mvar \u001b[0m")
  .replace(old="function ", new="\u001b[35mfunction \u001b[0m")
  .replace(old="return ", new="\u001b[35mreturn \u001b[0m")
  .replace(old="export ", new="\u001b[35mexport \u001b[0m")
  .replace(old="import ", new="\u001b[35mimport \u001b[0m")
}

///|
/// Highlight Python keywords
fn highlight_python_keywords(code : String) -> String {
  code
  .replace(old="def ", new="\u001b[35mdef \u001b[0m")
  .replace(old="class ", new="\u001b[35mclass \u001b[0m")
  .replace(old="import ", new="\u001b[35mimport \u001b[0m")
  .replace(old="from ", new="\u001b[35mfrom \u001b[0m")
  .replace(old="return ", new="\u001b[35mreturn \u001b[0m")
}

///|
test "plugin: reference keyword highlighter rust" {
  let options = TuiOptions::with_highlighter(reference_keyword_highlighter)
  let output = md_to_tui_with_options(
    "```rust\nfn main() {\n    let x = 1;\n}\n```\n", options,
  )
  inspect(output.contains("rust"), content="true")
  inspect(output.contains("\u001b[35mfn \u001b[0m"), content="true")
  inspect(output.contains("\u001b[35mlet \u001b[0m"), content="true")
}

///|
test "plugin: reference keyword highlighter js" {
  let options = TuiOptions::with_highlighter(reference_keyword_highlighter)
  let output = md_to_tui_with_options("```js\nconst x = 1;\n```\n", options)
  inspect(output.contains("js"), content="true")
  inspect(output.contains("\u001b[35mconst \u001b[0m"), content="true")
}

// =============================================================================
// Reference Implementation: File Header Highlighter
// =============================================================================

///|
/// Reference implementation: Shows filename as header
fn reference_file_header_highlighter(
  info : @markdown.CodeBlockInfo,
  code : String,
) -> String {
  let buf = StringBuilder::new()
  if !info.filename.is_empty() {
    buf.write_string(dim)
    buf.write_string("// ")
    buf.write_string(info.filename)
    buf.write_string(reset)
    buf.write_string("\n")
  }
  buf.write_string(cyan)
  buf.write_string(code)
  buf.write_string(reset)
  buf.to_string()
}

///|
test "plugin: reference file header highlighter" {
  let options = TuiOptions::with_highlighter(reference_file_header_highlighter)
  let output = md_to_tui_with_options(
    "```ts:utils.ts\nexport const x = 1;\n```\n", options,
  )
  inspect(output.contains("// utils.ts"), content="true")
}

// =============================================================================
// Reference Implementation: Line Number Highlighter
// =============================================================================

///|
/// Reference implementation: Adds line numbers
fn reference_line_number_highlighter(
  info : @markdown.CodeBlockInfo,
  code : String,
) -> String {
  let buf = StringBuilder::new()
  let lines = code.split("\n").collect()

  // Header
  if !info.lang.is_empty() {
    buf.write_string(bold)
    buf.write_string("[")
    buf.write_string(info.lang)
    buf.write_string("]")
    buf.write_string(reset)
    buf.write_string("\n")
  }

  // Code with line numbers
  for i, line in lines {
    if i < lines.length() - 1 || !line.to_string().is_empty() {
      buf.write_string(dim)
      let num = (i + 1).to_string()
      // Right-align line numbers
      if i + 1 < 10 {
        buf.write_string(" ")
      }
      buf.write_string(num)
      buf.write_string(" │ ")
      buf.write_string(reset)
      buf.write_string(line.to_string())
      buf.write_string("\n")
    }
  }
  buf.to_string()
}

///|
test "plugin: reference line number highlighter" {
  let options = TuiOptions::with_highlighter(reference_line_number_highlighter)
  let output = md_to_tui_with_options(
    "```js\nconst a = 1;\nconst b = 2;\n```\n", options,
  )
  inspect(output.contains("[js]"), content="true")
  inspect(output.contains("1 │"), content="true")
  inspect(output.contains("2 │"), content="true")
}

// =============================================================================
// Additional Plugin Tests
// =============================================================================

///|
test "plugin: simple highlighter" {
  fn simple_highlighter(lang : String, code : String) -> String {
    "<<" + lang + ">>\n" + code
  }

  let options = TuiOptions::with_simple_highlighter(simple_highlighter)
  let output = md_to_tui_with_options("```python\nprint('hi')\n```\n", options)
  inspect(output.contains("<<python>>"), content="true")
}

///|
test "plugin: non-code blocks unaffected" {
  fn custom_highlighter(
    _info : @markdown.CodeBlockInfo,
    _code : String,
  ) -> String {
    "HIGHLIGHTED"
  }

  let options = TuiOptions::with_highlighter(custom_highlighter)
  let output = md_to_tui_with_options(
    "# Heading\n\nParagraph\n\n```js\ncode\n```\n", options,
  )
  inspect(output.contains("Heading"), content="true")
  inspect(output.contains("Paragraph"), content="true")
  inspect(output.contains("HIGHLIGHTED"), content="true")
}

///|
test "plugin: meta in info string" {
  fn meta_highlighter(info : @markdown.CodeBlockInfo, code : String) -> String {
    let buf = StringBuilder::new()
    if !info.meta.is_empty() {
      buf.write_string("META: ")
      buf.write_string(info.meta)
      buf.write_string("\n")
    }
    buf.write_string(code)
    buf.to_string()
  }

  let options = TuiOptions::with_highlighter(meta_highlighter)
  let output = md_to_tui_with_options(
    "```js {lines=[1,2]}\ncode\n```\n", options,
  )
  inspect(output.contains("META: {lines=[1,2]}"), content="true")
}
