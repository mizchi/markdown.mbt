///| Attribute Sanitization
///|
///| Checks for dangerous attributes like event handlers and javascript: URLs

// =============================================================================
// Allowed Attributes
// =============================================================================

///|
/// Safe HTML attributes that are allowed by default
pub fn allowed_attributes() -> Array[String] {
  [
    // Global attributes
    "class", "id", "title", "lang", "dir", "hidden", "tabindex",
    // Link attributes
    "href", "rel", "download", "hreflang", "type",
    // Image attributes
    "src", "alt", "width", "height", "loading", "decoding",
    "srcset", "sizes",
    // Table attributes
    "colspan", "rowspan", "headers", "scope",
    // List attributes
    "value", "reversed", "start",
    // Form attributes (limited)
    // Note: "name" is excluded to prevent DOM clobbering attacks
    "placeholder", "readonly", "disabled", "required", "checked",
    "maxlength", "minlength", "pattern", "size", "rows", "cols",
    "for", "autocomplete", "selected", "multiple",
    // Media attributes
    "controls", "loop", "muted", "poster", "preload",
    // Misc
    "align", "valign", "border", "cellpadding", "cellspacing",
    "bgcolor", "color", "face", "datetime", "cite", "open",
  ]
}

///|
/// Allowed SVG attributes
pub fn allowed_svg_attributes() -> Array[String] {
  [
    "viewbox", "xmlns", "fill", "stroke", "stroke-width", "stroke-linecap",
    "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset", "opacity",
    "fill-opacity", "stroke-opacity", "transform", "d", "cx", "cy", "r",
    "rx", "ry", "x", "y", "x1", "y1", "x2", "y2", "width", "height",
    "points", "pathlength", "clip-path", "mask", "filter",
    "gradientunits", "gradienttransform", "spreadmethod", "offset",
    "stop-color", "stop-opacity", "font-size", "font-family", "font-weight",
    "text-anchor", "dominant-baseline", "preserveaspectratio",
  ]
}

// =============================================================================
// Forbidden Attributes
// =============================================================================

///|
/// Dangerous attributes that are always forbidden
pub fn forbidden_attributes() -> Array[String] {
  [
    // Form hijacking
    "action", "formaction", "formmethod", "formenctype", "formtarget",
    "formnovalidate",
    // Script execution
    "xlink:href", "href" , // Only forbidden when contains javascript:
    // Iframe/embed
    "srcdoc", "sandbox", "allow", "allowfullscreen", "allowpaymentrequest",
    // Dangerous meta
    "http-equiv", "content", "charset",
    // Object/embed
    "data", "codebase", "code", "archive", "classid",
    // Behavior
    "autofocus", "autoplay",
    // Injection
    "ping", "dynsrc", "lowsrc",
    // Background (can load external resources)
    "background",
    // DOM clobbering prevention (name attribute on img/form elements)
    "name",
  ]
}

///|
/// Event handler attribute prefixes (always dangerous)
pub fn event_handler_prefixes() -> Array[String] {
  ["on"] // Covers: onclick, onerror, onload, onmouseover, etc.
}

// =============================================================================
// Attribute Checking Functions
// =============================================================================

///|
/// Check if an attribute is a dangerous event handler
pub fn is_event_handler(attr_name : String) -> Bool {
  let lower = to_lowercase_attr(attr_name)

  // Check if starts with "on"
  if lower.length() > 2 {
    let chars = lower.to_array()
    if chars[0] == 'o' && chars[1] == 'n' {
      // Make sure it's not "only" or similar
      let third = chars[2]
      if third >= 'a' && third <= 'z' {
        return true
      }
    }
  }

  false
}

///|
/// Check if an attribute is allowed
pub fn is_allowed_attribute(
  attr_name : String,
  attr_value : String,
  tag_name : String,
  config : SanitizeConfig
) -> Bool {
  let lower_attr = to_lowercase_attr(attr_name)
  let lower_tag = to_lowercase_attr(tag_name)

  // Event handlers are always forbidden
  if is_event_handler(lower_attr) {
    return false
  }

  // Check forbidden list
  if is_forbidden_attribute(lower_attr, config) {
    return false
  }

  // Check data-* attributes
  if starts_with(lower_attr, "data-") {
    return config.allow_data_attr
  }

  // Check aria-* attributes
  if starts_with(lower_attr, "aria-") {
    return config.allow_aria_attr
  }

  // Special handling for href/src - check URL scheme
  if lower_attr == "href" || lower_attr == "src" || lower_attr == "xlink:href" {
    return is_safe_url(attr_value, config)
  }

  // Special handling for target attribute
  if lower_attr == "target" {
    return config.allow_link_target
  }

  // Check if in additional allowed attrs
  if array_contains_attr(config.additional_attrs, lower_attr) {
    return true
  }

  // Check default allowed attributes
  if array_contains_attr(allowed_attributes(), lower_attr) {
    return true
  }

  // Check SVG attributes if SVG is allowed
  if config.allow_svg && is_svg_tag(lower_tag) {
    if array_contains_attr(allowed_svg_attributes(), lower_attr) {
      return true
    }
  }

  false
}

///|
/// Check if an attribute is forbidden
pub fn is_forbidden_attribute(attr_name : String, config : SanitizeConfig) -> Bool {
  let lower = to_lowercase_attr(attr_name)

  // Check additional forbidden attrs from config
  if array_contains_attr(config.forbidden_attrs, lower) {
    return true
  }

  // Note: href/src are checked separately for URL safety
  // Don't mark them as globally forbidden
  if lower == "href" || lower == "src" {
    return false
  }

  // Check default forbidden attributes
  array_contains_attr(forbidden_attributes(), lower)
}

// =============================================================================
// URL Checking Functions
// =============================================================================

///|
/// Check if a URL is safe (no javascript:, vbscript:, data: with scripts)
pub fn is_safe_url(url : String, config : SanitizeConfig) -> Bool {
  // First strip control characters (used for obfuscation)
  let cleaned = strip_control_chars(url)
  let trimmed = trim_string(cleaned)
  let lower = to_lowercase_attr(trimmed)

  // Check for dangerous protocols
  if starts_with(lower, "javascript:") ||
     starts_with(lower, "vbscript:") ||
     starts_with(lower, "jscript:") {
    return false
  }

  // Check data: URLs carefully
  if starts_with(lower, "data:") {
    // Only allow safe data: URLs (images)
    if starts_with(lower, "data:image/") {
      // Check for embedded script in data URL
      if contains_string(lower, "script") ||
         contains_string(lower, "onerror") ||
         contains_string(lower, "onload") {
        return false
      }
      return true
    }
    // Reject all other data: URLs
    return false
  }

  // Extract protocol from URL
  match extract_protocol(lower) {
    Some(protocol) => array_contains_attr(config.allowed_schemes, protocol)
    None => true  // Relative URLs are OK
  }
}

///|
/// Extract protocol from URL (returns None for relative URLs)
fn extract_protocol(url : String) -> String? {
  let chars = url.to_array()
  let len = chars.length()
  let buf = StringBuilder::new()

  for i = 0; i < len; i = i + 1 {
    let c = chars[i]
    if c == ':' {
      if i > 0 {
        return Some(buf.to_string())
      }
      return None
    }
    if c == '/' || c == '?' || c == '#' {
      // Reached path/query/fragment without finding protocol
      return None
    }
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '+' || c == '-' || c == '.' {
      buf.write_char(c)
    } else if i == 0 {
      // First char must be letter for protocol
      return None
    }
  }

  None
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Strip control characters (ASCII 0-31) used for URL obfuscation
fn strip_control_chars(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    let code = c.to_int()
    // Keep only printable ASCII and higher Unicode
    if code >= 32 {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn to_lowercase_attr(s : String) -> String {
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
fn array_contains_attr(arr : Array[String], item : String) -> Bool {
  for s in arr {
    if s == item {
      return true
    }
  }
  false
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  let s_chars = s.to_array()
  let p_chars = prefix.to_array()

  if s_chars.length() < p_chars.length() {
    return false
  }

  for i = 0; i < p_chars.length(); i = i + 1 {
    if s_chars[i] != p_chars[i] {
      return false
    }
  }

  true
}

///|
fn contains_string(haystack : String, needle : String) -> Bool {
  let h_chars = haystack.to_array()
  let n_chars = needle.to_array()
  let h_len = h_chars.length()
  let n_len = n_chars.length()

  if n_len > h_len {
    return false
  }

  for i = 0; i <= h_len - n_len; i = i + 1 {
    let mut found = true
    for j = 0; j < n_len; j = j + 1 {
      if h_chars[i + j] != n_chars[j] {
        found = false
        break
      }
    }
    if found {
      return true
    }
  }

  false
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()

  let mut start = 0
  while start < len &&
        (chars[start] == ' ' || chars[start] == '\t' ||
         chars[start] == '\n' || chars[start] == '\r') {
    start += 1
  }

  let mut end = len
  while end > start &&
        (chars[end - 1] == ' ' || chars[end - 1] == '\t' ||
         chars[end - 1] == '\n' || chars[end - 1] == '\r') {
    end -= 1
  }

  if start == 0 && end == len {
    return s
  }

  let buf = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
fn is_svg_tag(tag : String) -> Bool {
  let svg_tags = allowed_svg_tags()
  array_contains_attr(svg_tags, tag)
}

