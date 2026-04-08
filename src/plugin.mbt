///| Plugin system for markdown renderers

///| Allows custom code block highlighters

///| Parsed info string from code block fence

///| Format: "lang:filename {meta}"

///| Examples:

///|   "javascript" → (lang="javascript", filename="", meta="")

///|   "js:app.js" → (lang="js", filename="app.js", meta="")

///|
///   "ts:index.ts {highlight=[1,3]}" → (lang="ts", filename="index.ts", meta="{highlight=[1,3]}")
pub struct CodeBlockInfo {
  lang : String
  filename : String
  meta : String
}

///|
/// Parse code block info string into components
pub fn parse_code_block_info(info : String) -> CodeBlockInfo {
  let parsed = @info_string.parse(info)
  { lang: parsed.lang, filename: parsed.filename, meta: parsed.meta }
}

///|
/// Render options with plugin support
pub struct RenderOptions {
  /// Custom code block highlighter
  code_highlighter : ((CodeBlockInfo, String) -> String)?
}

///|
/// Create default render options
pub fn RenderOptions::default() -> RenderOptions {
  { code_highlighter: None }
}

///|
/// Create render options with code highlighter
pub fn RenderOptions::with_highlighter(
  highlighter : (CodeBlockInfo, String) -> String,
) -> RenderOptions {
  { code_highlighter: Some(highlighter) }
}

///|
/// Create render options with simple highlighter (lang, code) -> String
pub fn RenderOptions::with_simple_highlighter(
  highlighter : (String, String) -> String,
) -> RenderOptions {
  {
    code_highlighter: Some(fn(info : CodeBlockInfo, code : String) -> String {
      highlighter(info.lang, code)
    }),
  }
}
