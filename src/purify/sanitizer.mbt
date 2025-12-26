///| HTML Sanitizer
///|
///| Main sanitization API for HTML content

// =============================================================================
// Main Sanitization API
// =============================================================================

///|
/// Sanitize HTML string, removing dangerous elements
pub fn sanitize(html : String, config? : SanitizeConfig) -> SanitizeResult {
  let cfg = config.unwrap_or(SanitizeConfig::default())
  let removed : Array[RemovedItem] = []

  if not(cfg.allow_html) {
    // Strip all HTML - return text only
    let text = strip_all_html(html)
    return {
      content: text,
      removed: [{
        kind: RemovedKind::Tag,
        original: html,
        reason: "HTML not allowed",
      }],
      was_modified: text != html,
    }
  }

  let result = sanitize_html(html, cfg, removed)

  { content: result, removed, was_modified: result != html }
}

///|
/// Sanitize a URL, checking for dangerous protocols
pub fn sanitize_url(url : String, config? : SanitizeConfig) -> String? {
  let cfg = config.unwrap_or(SanitizeConfig::default())

  if is_safe_url(url, cfg) {
    Some(url)
  } else {
    None
  }
}

///|
/// Check if an HTML string contains any dangerous content
pub fn is_safe_html(html : String, config? : SanitizeConfig) -> Bool {
  let cfg = config.unwrap_or(SanitizeConfig::default())
  let result = sanitize(html, config=cfg)
  not(result.was_modified)
}

// =============================================================================
// HTML Parser and Sanitizer
// =============================================================================

///|
/// Parse and sanitize HTML content
fn sanitize_html(
  html : String,
  config : SanitizeConfig,
  removed : Array[RemovedItem]
) -> String {
  let chars = html.to_array()
  let len = chars.length()
  let output = StringBuilder::new()
  let mut pos = 0

  while pos < len {
    if chars[pos] == '<' {
      // Check if this is a forbidden tag that needs content skipping
      let (_, skip_pos) = try_skip_forbidden_tag_with_content(
        chars,
        pos,
        config,
        removed,
      )
      if skip_pos > pos {
        // Forbidden tag was skipped entirely
        pos = skip_pos
        continue
      }

      // Parse tag normally
      let (tag_result, new_pos) = parse_and_sanitize_tag(chars, pos, config, removed)
      output.write_string(tag_result)
      pos = new_pos
    } else {
      output.write_char(chars[pos])
      pos += 1
    }
  }

  output.to_string()
}

///|
/// Try to skip a forbidden tag along with its content
fn try_skip_forbidden_tag_with_content(
  chars : Array[Char],
  start : Int,
  _config : SanitizeConfig,
  removed : Array[RemovedItem]
) -> (String, Int) {
  let len = chars.length()
  let mut pos = start + 1  // Skip <

  // Skip whitespace
  while pos < len && is_whitespace_char(chars[pos]) {
    pos += 1
  }

  // Check for closing tag (don't skip those)
  if pos < len && chars[pos] == '/' {
    return ("", start)
  }

  // Check for comment or doctype
  if pos < len && chars[pos] == '!' {
    return ("", start)
  }

  // Parse tag name
  let tag_start = pos
  while pos < len && is_tag_name_char(chars[pos]) {
    pos += 1
  }

  if pos == tag_start {
    return ("", start)
  }

  let tag_name = extract_string(chars, tag_start, pos)
  let lower_tag = to_lowercase_san(tag_name)

  // Check if this is a forbidden tag that has content to skip
  if not(is_content_forbidden_tag(lower_tag)) {
    return ("", start)
  }

  // This is a forbidden tag - skip until closing tag
  // First, find the end of the opening tag
  while pos < len && chars[pos] != '>' {
    pos += 1
  }
  if pos < len {
    pos += 1  // Skip >
  }

  // Check if self-closing (look for /> before >)
  let opening_end = pos
  let mut check_pos = start + 1
  let mut is_self_closing = false
  while check_pos < opening_end {
    if chars[check_pos] == '/' && check_pos + 1 < opening_end && chars[check_pos + 1] == '>' {
      is_self_closing = true
      break
    }
    check_pos += 1
  }

  if is_self_closing {
    removed.push({
      kind: RemovedKind::Tag,
      original: extract_string(chars, start, pos),
      reason: "Forbidden tag: " + tag_name,
    })
    return ("", pos)
  }

  // Find closing tag
  while pos < len {
    if chars[pos] == '<' && pos + 1 < len && chars[pos + 1] == '/' {
      // Check if this is the closing tag
      let close_tag_start = pos + 2
      let mut close_pos = close_tag_start
      while close_pos < len && is_tag_name_char(chars[close_pos]) {
        close_pos += 1
      }

      let close_tag_name = extract_string(chars, close_tag_start, close_pos)
      if to_lowercase_san(close_tag_name) == lower_tag {
        // Found closing tag - skip to end of it
        while close_pos < len && chars[close_pos] != '>' {
          close_pos += 1
        }
        if close_pos < len {
          close_pos += 1  // Skip >
        }

        removed.push({
          kind: RemovedKind::Tag,
          original: extract_string(chars, start, close_pos),
          reason: "Forbidden tag with content: " + tag_name,
        })
        return ("", close_pos)
      }
    }
    pos += 1
  }

  // No closing tag found - remove from opening tag to end
  removed.push({
    kind: RemovedKind::Tag,
    original: extract_string(chars, start, len),
    reason: "Unclosed forbidden tag: " + tag_name,
  })
  ("", len)
}

///|
/// Check if a tag is forbidden and has content that should be skipped
fn is_content_forbidden_tag(tag : String) -> Bool {
  // Tags whose content should also be removed
  // Note: form is NOT included - we remove the tag but keep content
  tag == "script" ||
  tag == "style" ||
  tag == "noscript" ||
  tag == "iframe" ||
  tag == "object" ||
  tag == "embed" ||
  tag == "applet" ||
  tag == "template"
}

///|
/// Parse a single tag and sanitize it
fn parse_and_sanitize_tag(
  chars : Array[Char],
  start : Int,
  config : SanitizeConfig,
  removed : Array[RemovedItem]
) -> (String, Int) {
  let len = chars.length()
  let mut pos = start + 1  // Skip <

  // Skip whitespace
  while pos < len && is_whitespace_char(chars[pos]) {
    pos += 1
  }

  if pos >= len {
    return ("<", start + 1)
  }

  // Check for closing tag
  let is_closing = chars[pos] == '/'
  if is_closing {
    pos += 1
  }

  // Check for comment
  if not(is_closing) && pos + 2 < len &&
     chars[pos] == '!' && chars[pos + 1] == '-' && chars[pos + 2] == '-' {
    return parse_comment(chars, start, config)
  }

  // Check for doctype
  if not(is_closing) && pos < len && chars[pos] == '!' {
    return skip_doctype(chars, start)
  }

  // Parse tag name
  let tag_start = pos
  while pos < len && is_tag_name_char(chars[pos]) {
    pos += 1
  }

  if pos == tag_start {
    // No tag name found
    return ("<", start + 1)
  }

  let tag_name = extract_string(chars, tag_start, pos)
  let lower_tag = to_lowercase_san(tag_name)

  // Check if tag is allowed
  if not(is_allowed_tag(lower_tag, config)) {
    // Find end of tag and skip it
    while pos < len && chars[pos] != '>' {
      pos += 1
    }
    if pos < len {
      pos += 1  // Skip >
    }

    removed.push({
      kind: RemovedKind::Tag,
      original: extract_string(chars, start, pos),
      reason: "Forbidden tag: " + tag_name,
    })

    return ("", pos)
  }

  // Parse attributes
  let output = StringBuilder::new()
  output.write_char('<')
  if is_closing {
    output.write_char('/')
  }
  output.write_string(tag_name)

  while pos < len {
    // Skip whitespace
    while pos < len && is_whitespace_char(chars[pos]) {
      pos += 1
    }

    if pos >= len {
      break
    }

    // Check for end of tag
    if chars[pos] == '>' {
      pos += 1
      break
    }

    // Check for self-closing
    if chars[pos] == '/' {
      if pos + 1 < len && chars[pos + 1] == '>' {
        output.write_string(" /")
        pos += 2
        break
      }
      pos += 1
      continue
    }

    // Parse attribute name
    let attr_start = pos
    while pos < len && is_attr_name_char(chars[pos]) {
      pos += 1
    }

    if pos == attr_start {
      pos += 1
      continue
    }

    let attr_name = extract_string(chars, attr_start, pos)

    // Skip whitespace
    while pos < len && is_whitespace_char(chars[pos]) {
      pos += 1
    }

    // Check for =
    let attr_value = if pos < len && chars[pos] == '=' {
      pos += 1

      // Skip whitespace
      while pos < len && is_whitespace_char(chars[pos]) {
        pos += 1
      }

      // Parse value
      if pos < len {
        let (value, new_pos) = parse_attribute_value(chars, pos)
        pos = new_pos
        value
      } else {
        ""
      }
    } else {
      ""
    }

    // Check if attribute is allowed
    if is_allowed_attribute(attr_name, attr_value, tag_name, config) {
      output.write_char(' ')
      output.write_string(attr_name)
      if attr_value.length() > 0 {
        output.write_string("=\"")
        output.write_string(escape_attr_value(attr_value))
        output.write_char('"')
      }
    } else {
      removed.push({
        kind: RemovedKind::Attribute,
        original: attr_name + "=" + attr_value,
        reason: "Forbidden attribute: " + attr_name,
      })
    }
  }

  output.write_char('>')

  (output.to_string(), pos)
}

///|
/// Parse HTML comment
fn parse_comment(
  chars : Array[Char],
  start : Int,
  config : SanitizeConfig
) -> (String, Int) {
  let len = chars.length()
  let mut pos = start + 4  // Skip <!--

  // Find end of comment -->
  while pos + 2 < len {
    if chars[pos] == '-' && chars[pos + 1] == '-' && chars[pos + 2] == '>' {
      if config.allow_comments {
        // Return comment as-is
        return (extract_string(chars, start, pos + 3), pos + 3)
      }
      // Remove comments for safety (default)
      // Comments can be used for XSS attacks (e.g., breaking out of textarea)
      return ("", pos + 3)
    }
    pos += 1
  }

  // Unclosed comment - remove entirely
  ("", len)
}

///|
/// Skip doctype declaration
fn skip_doctype(chars : Array[Char], start : Int) -> (String, Int) {
  let len = chars.length()
  let mut pos = start

  while pos < len && chars[pos] != '>' {
    pos += 1
  }

  if pos < len {
    pos += 1
  }

  // Remove doctype entirely
  ("", pos)
}

///|
/// Parse attribute value (quoted or unquoted)
fn parse_attribute_value(chars : Array[Char], start : Int) -> (String, Int) {
  let len = chars.length()
  let mut pos = start

  if pos >= len {
    return ("", pos)
  }

  let quote = chars[pos]
  if quote == '"' || quote == '\'' {
    pos += 1
    let value_start = pos

    while pos < len && chars[pos] != quote {
      if chars[pos] == '\\' && pos + 1 < len {
        pos += 2
      } else {
        pos += 1
      }
    }

    let value = extract_string(chars, value_start, pos)

    if pos < len {
      pos += 1  // Skip closing quote
    }

    (decode_html_entities(value), pos)
  } else {
    // Unquoted value
    // Note: '/' is valid in unquoted values (e.g., data:image/jpeg)
    // Only stop on '/>' which indicates self-closing tag
    let value_start = pos
    while pos < len &&
          not(is_whitespace_char(chars[pos])) &&
          chars[pos] != '>' {
      // Check for self-closing tag '/>'
      if chars[pos] == '/' && pos + 1 < len && chars[pos + 1] == '>' {
        break
      }
      pos += 1
    }
    (decode_html_entities(extract_string(chars, value_start, pos)), pos)
  }
}

// =============================================================================
// Strip All HTML
// =============================================================================

///|
/// Remove all HTML tags, keeping only text content
fn strip_all_html(html : String) -> String {
  let chars = html.to_array()
  let len = chars.length()
  let output = StringBuilder::new()
  let mut pos = 0
  let mut in_tag = false

  while pos < len {
    if chars[pos] == '<' {
      in_tag = true
    } else if chars[pos] == '>' {
      in_tag = false
    } else if not(in_tag) {
      output.write_char(chars[pos])
    }
    pos += 1
  }

  output.to_string()
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn is_whitespace_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_tag_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '-' || c == '_' || c == ':'
}

///|
fn is_attr_name_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '-' || c == '_' || c == ':' || c == '.'
}

///|
fn extract_string(chars : Array[Char], start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn to_lowercase_san(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    if c >= 'A' && c <= 'Z' {
      let lower = (c.to_int() + 32).unsafe_to_char()
      buf.write_char(lower)
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn escape_attr_value(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    match c {
      '"' => buf.write_string("&quot;")
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn decode_html_entities(s : String) -> String {
  // First decode numeric entities (&#NNN; and &#xHHH;)
  let result = decode_numeric_entities(s)

  // Then decode named entities
  let mut decoded = result
  if decoded.contains("&amp;") {
    decoded = replace_string(decoded, "&amp;", "&")
  }
  if decoded.contains("&lt;") {
    decoded = replace_string(decoded, "&lt;", "<")
  }
  if decoded.contains("&gt;") {
    decoded = replace_string(decoded, "&gt;", ">")
  }
  if decoded.contains("&quot;") {
    decoded = replace_string(decoded, "&quot;", "\"")
  }
  if decoded.contains("&apos;") {
    decoded = replace_string(decoded, "&apos;", "'")
  }
  if decoded.contains("&#39;") {
    decoded = replace_string(decoded, "&#39;", "'")
  }

  // Check for javascript: that might be encoded
  let lower = to_lowercase_san(decoded)
  if lower.contains("javascript") || lower.contains("vbscript") {
    // Re-check after decoding
    if contains_dangerous_protocol(lower) {
      return ""  // Remove entirely
    }
  }

  decoded
}

///|
/// Decode numeric HTML entities like &#106; or &#x6A;
fn decode_numeric_entities(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let buf = StringBuilder::new()
  let mut i = 0

  while i < len {
    if chars[i] == '&' && i + 2 < len && chars[i + 1] == '#' {
      // Check for hex (&#x...) or decimal (&#...)
      let is_hex = i + 3 < len && (chars[i + 2] == 'x' || chars[i + 2] == 'X')
      let num_start = if is_hex { i + 3 } else { i + 2 }

      // Find the end of the numeric entity
      let mut num_end = num_start
      while num_end < len && chars[num_end] != ';' && num_end - num_start < 8 {
        let c = chars[num_end]
        if is_hex {
          if (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') {
            num_end += 1
          } else {
            break
          }
        } else {
          if c >= '0' && c <= '9' {
            num_end += 1
          } else {
            break
          }
        }
      }

      if num_end > num_start && num_end < len && chars[num_end] == ';' {
        // Parse the number
        let code_point = if is_hex {
          parse_hex(chars, num_start, num_end)
        } else {
          parse_decimal(chars, num_start, num_end)
        }

        if code_point > 0 && code_point < 0x110000 {
          buf.write_char(code_point.unsafe_to_char())
          i = num_end + 1
          continue
        }
      }
    }

    buf.write_char(chars[i])
    i += 1
  }

  buf.to_string()
}

///|
fn parse_hex(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut result = 0
  for j = start; j < end; j = j + 1 {
    let c = chars[j]
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      0
    }
    result = result * 16 + digit
  }
  result
}

///|
fn parse_decimal(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut result = 0
  for j = start; j < end; j = j + 1 {
    let c = chars[j]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    }
  }
  result
}

///|
fn contains_dangerous_protocol(s : String) -> Bool {
  s.contains("javascript:") ||
  s.contains("vbscript:") ||
  s.contains("jscript:")
}

///|
fn replace_string(s : String, from : String, to : String) -> String {
  let s_chars = s.to_array()
  let f_chars = from.to_array()
  let s_len = s_chars.length()
  let f_len = f_chars.length()

  if f_len == 0 || f_len > s_len {
    return s
  }

  let buf = StringBuilder::new()
  let mut i = 0

  while i < s_len {
    let mut found = true
    if i + f_len <= s_len {
      for j = 0; j < f_len; j = j + 1 {
        if s_chars[i + j] != f_chars[j] {
          found = false
          break
        }
      }
    } else {
      found = false
    }

    if found {
      buf.write_string(to)
      i += f_len
    } else {
      buf.write_char(s_chars[i])
      i += 1
    }
  }

  buf.to_string()
}

