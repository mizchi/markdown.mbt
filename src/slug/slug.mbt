// Slug Generation
// Generate URL-friendly IDs from heading text

///|
/// Generate heading ID from text (for anchor links)
/// Converts text to lowercase, replaces spaces with hyphens,
/// and keeps non-ASCII characters (Japanese, Chinese, etc.)
///
/// Examples:
/// - "Hello World" → "hello-world"
/// - "日本語タイトル" → "日本語タイトル"
/// - "API Reference" → "api-reference"
pub fn generate_heading_id(text : String) -> String {
  let buf = StringBuilder::new()
  let lower = text.to_lower()
  let mut prev_was_separator = false
  for c in lower {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      buf.write_char(c)
      prev_was_separator = false
    } else if c == ' ' || c == '-' || c == '_' {
      // Avoid multiple consecutive separators
      if !(prev_was_separator) {
        buf.write_char('-')
        prev_was_separator = true
      }
    } else if c.to_uint() > 127 {
      // Keep non-ASCII characters (Japanese, Chinese, etc.)
      buf.write_char(c)
      prev_was_separator = false
    }
    // Skip other ASCII special characters
  }

  // Remove trailing separator
  let result = buf.to_string()
  if result.has_suffix("-") {
    result.unsafe_substring(start=0, end=result.length() - 1)
  } else {
    result
  }
}
