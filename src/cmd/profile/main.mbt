///|
/// Workload isolated by the native Time Profiler harness.
priv enum ProfileMode {
  Parse
  Render
  ParseRender
}

///|
priv struct ProfileConfig {
  mode : ProfileMode
  iterations : Int
}

///|
fn parse_config(args : Array[String]) -> Result[ProfileConfig, String] {
  guard args.length() >= 3 else {
    return Err("usage: markdown-profile parse|render|parse-render ITERATIONS")
  }
  let mode_arg = args[args.length() - 2]
  let iterations_arg = args[args.length() - 1]
  let mode = match mode_arg {
    "parse" => ProfileMode::Parse
    "render" => ProfileMode::Render
    "parse-render" => ProfileMode::ParseRender
    other => return Err("unsupported mode: " + other)
  }
  let iterations = @string.parse_int(iterations_arg) catch {
    _ => return Err("iterations must be a positive integer")
  }
  guard iterations > 0 else {
    return Err("iterations must be a positive integer")
  }
  Ok({ mode, iterations })
}

///|
/// Same section and multiplier as the ox-content huge benchmark.
let profile_section : String = "\n# Heading 1\n\nThis is a paragraph with **bold** and *italic* text.\n\n## Heading 2\n\n- List item 1\n- List item 2\n  - Nested item\n- List item 3\n\n### Code Block\n\n```javascript\nfunction hello() {\n  console.log(\"Hello, World!\");\n}\n```\n\n> This is a blockquote\n> with multiple lines\n\n| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |\n| Cell 3   | Cell 4   |\n\nHere's a [link](https://example.com) and an image: ![alt](image.png)\n\n---\n\nFinal paragraph with `inline code` and more text.\n"

///|
fn run_workload(
  mode : ProfileMode,
  iterations : Int,
  source : String,
  document : @markdown.Document,
) -> Int {
  let mut checksum = 0
  match mode {
    Parse =>
      for _ in 0..<iterations {
        checksum = checksum + @markdown.parse(source).document.children.length()
      }
    Render =>
      for _ in 0..<iterations {
        checksum = checksum + @markdown.render_html(document).length()
      }
    ParseRender =>
      for _ in 0..<iterations {
        checksum = checksum + @markdown.md_to_html(source).length()
      }
  }
  checksum
}

///|
fn mode_name(mode : ProfileMode) -> String {
  match mode {
    Parse => "parse"
    Render => "render"
    ParseRender => "parse-render"
  }
}

///|
fn main {
  let config = match parse_config(@env.args()) {
    Ok(config) => config
    Err(message) => abort(message)
  }
  let source = profile_section.repeat(2150)
  let document = @markdown.parse(source).document
  // Warm parser code and allocator paths before the measured bulk workload.
  let _ = run_workload(config.mode, 3, source, document)
  let checksum = run_workload(config.mode, config.iterations, source, document)
  println(
    "mode=\{mode_name(config.mode)} iterations=\{config.iterations} input=\{source.length()} checksum=\{checksum}",
  )
}
