///| Code Block Attribute Parser

///|

///| Parses extended code block attributes for notebook cells

///|

///| Format: ```lang :cell=name :deps=a,b,c :hide :output=html

///| Example: ```moonbit :cell=data :deps=input :output=json

// =============================================================================
// Attribute Parsing
// =============================================================================

///|
/// Parse code block info string with notebook attributes
pub fn parse_code_block_attrs(
  info : String,
) -> (@markdown.CodeBlockInfo, CodeBlockAttrs) {
  let base_info = @markdown.parse_code_block_info(info)
  let attrs = CodeBlockAttrs::new()

  // Parse meta string for notebook attributes
  if base_info.meta.is_empty() {
    return (base_info, attrs)
  }

  // Parse attributes from meta
  let parsed_attrs = parse_attrs_from_meta(base_info.meta)
  (base_info, parsed_attrs)
}

///|
/// Parse notebook attributes from meta string
fn parse_attrs_from_meta(meta : String) -> CodeBlockAttrs {
  let mut cell : String? = None
  let mut deps : Array[String] = []
  let mut hidden = false
  let mut output_format = Auto
  let mut executable = false

  // Remove surrounding braces if present
  let content = if meta.has_prefix("{") && meta.has_suffix("}") {
    meta.unsafe_substring(start=1, end=meta.length() - 1)
  } else {
    meta
  }

  // Split by whitespace and parse each attribute
  let parts = split_by_whitespace(content)
  for part in parts {
    let trimmed = part.trim_start(chars=" \t").trim_end(chars=" \t").to_owned()
    if trimmed.is_empty() {
      continue
    }

    // :cell=name
    if trimmed.has_prefix(":cell=") {
      cell = Some(trimmed.unsafe_substring(start=6, end=trimmed.length()))
      executable = true
      // :deps=a,b,c
    } else if trimmed.has_prefix(":deps=") {
      let deps_str = trimmed.unsafe_substring(start=6, end=trimmed.length())
      deps = split_by_comma(deps_str)
      executable = true
      // :hide
    } else if trimmed == ":hide" {
      hidden = true
      // :output=html|json|text
    } else if trimmed.has_prefix(":output=") {
      let format_str = trimmed.unsafe_substring(start=8, end=trimmed.length())
      output_format = parse_output_format(format_str)
      // :exec (mark as executable without cell name)
    } else if trimmed == ":exec" {
      executable = true
    }
  }
  { cell, deps, hidden, output_format, executable }
}

///|
/// Parse output format from string
fn parse_output_format(s : String) -> OutputFormat {
  match s {
    "html" => Html
    "json" => Json
    "text" => Text
    _ => Auto
  }
}

///|
/// Split string by whitespace (simple implementation)
fn split_by_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    if c == ' ' || c == '\t' {
      if buf.to_string().length() > 0 {
        result.push(buf.to_string())
        buf.reset()
      }
    } else {
      buf.write_char(c)
    }
  }
  if buf.to_string().length() > 0 {
    result.push(buf.to_string())
  }
  result
}

///|
/// Split string by comma
fn split_by_comma(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    if c == ',' {
      let part = buf
        .to_string()
        .trim_start(chars=" ")
        .trim_end(chars=" ")
        .to_owned()
      if part.length() > 0 {
        result.push(part)
      }
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  let final_part = buf
    .to_string()
    .trim_start(chars=" ")
    .trim_end(chars=" ")
    .to_owned()
  if final_part.length() > 0 {
    result.push(final_part)
  }
  result
}

// =============================================================================
// Inline Directive Parsing
// =============================================================================

///|
/// Parse <Inline source="path" /> directive from JSX
pub fn parse_inline_directive(jsx : String) -> InlineDirective? {
  // Simple regex-like parsing for <Inline source="..." />
  if !jsx.contains("<Inline") {
    return None
  }

  // Extract source attribute
  let source = extract_attribute(jsx, "source")
  match source {
    None => None
    Some(src) => {
      let section = extract_attribute(jsx, "section")
      let recursive = match extract_attribute(jsx, "recursive") {
        Some("false") => false
        _ => true
      }
      Some({ source: src, section, recursive })
    }
  }
}

///|
/// Extract attribute value from JSX-like string
fn extract_attribute(jsx : String, attr_name : String) -> String? {
  // Look for attr="value" or attr='value'
  let patterns = [attr_name + "=\"", attr_name + "='"]
  for pattern in patterns {
    match jsx.find(pattern) {
      Some(start) => {
        let value_start = start + pattern.length()
        let quote_char = if pattern.has_suffix("\"") { '"' } else { '\'' }
        let chars = jsx.to_array()
        let mut end = value_start
        while end < chars.length() && chars[end] != quote_char {
          end += 1
        }
        if end > value_start {
          return Some(jsx.unsafe_substring(start=value_start, end~))
        }
      }
      None => continue
    }
  }
  None
}
