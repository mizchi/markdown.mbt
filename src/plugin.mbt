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
  let trimmed = info.trim().to_string()
  if trimmed.is_empty() {
    return { lang: "", filename: "", meta: "" }
  }

  // Find meta section (starts with space + {)
  let trimmed_len = trimmed.iter().count()
  let (main_part, meta) = match trimmed.find(" {") {
    Some(idx) => {
      let main = trimmed.unsafe_substring(start=0, end=idx)
      let meta_str = trimmed
        .unsafe_substring(start=idx + 1, end=trimmed_len)
        .trim()
        .to_string()
      (main, meta_str)
    }
    None => (trimmed, "")
  }

  // Split lang:filename
  let main_len = main_part.iter().count()
  match main_part.find(":") {
    Some(idx) => {
      let lang = main_part.unsafe_substring(start=0, end=idx)
      let filename = main_part.unsafe_substring(start=idx + 1, end=main_len)
      { lang, filename, meta }
    }
    None => { lang: main_part, filename: "", meta }
  }
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
