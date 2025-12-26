///| Allowed and Forbidden HTML Tags
///|
///| Based on DOMPurify's default tag lists

// =============================================================================
// Allowed HTML Tags
// =============================================================================

///|
/// Safe HTML tags that are allowed by default
pub fn allowed_html_tags() -> Array[String] {
  [
    // Text content
    "a", "abbr", "acronym", "address", "b", "bdi", "bdo", "big", "blockquote",
    "br", "caption", "center", "cite", "code", "col", "colgroup", "dd", "del",
    "details", "dfn", "dir", "div", "dl", "dt", "em", "figcaption", "figure",
    "font", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup",
    "hr", "i", "img", "ins", "kbd", "li", "main", "mark", "marquee", "menu",
    "nav", "ol", "p", "pre", "q", "rp", "rt", "ruby", "s", "samp", "section",
    "small", "span", "strike", "strong", "sub", "summary", "sup", "table",
    "tbody", "td", "tfoot", "th", "thead", "time", "tr", "tt", "u", "ul",
    "var", "wbr",
    // Input elements (limited)
    "input", "label", "textarea", "select", "option", "optgroup", "button",
    // Media (images only by default)
    "picture", "source",
  ]
}

///|
/// Safe SVG tags
pub fn allowed_svg_tags() -> Array[String] {
  [
    "svg", "g", "path", "circle", "ellipse", "line", "polygon", "polyline",
    "rect", "text", "tspan", "textpath", "defs", "symbol", "use", "image",
    "clippath", "mask", "pattern", "lineargradient", "radialgradient", "stop",
    "title", "desc", "metadata",
  ]
}

///|
/// Safe MathML tags
pub fn allowed_math_tags() -> Array[String] {
  [
    "math", "mi", "mn", "mo", "ms", "mtext", "mspace", "mrow", "mfrac",
    "msqrt", "mroot", "mstyle", "merror", "mpadded", "mphantom", "mfenced",
    "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts",
    "mtable", "mtr", "mtd", "maligngroup", "malignmark", "annotation",
  ]
}

// =============================================================================
// Forbidden Tags
// =============================================================================

///|
/// Dangerous tags that are always forbidden
pub fn forbidden_tags() -> Array[String] {
  [
    // Script execution
    "script", "noscript",
    // External resources
    "iframe", "frame", "frameset", "noframes",
    "object", "embed", "applet", "param",
    // Document manipulation
    "base", "basefont", "link", "meta", "title",
    // Style (can execute JS in some browsers)
    "style",
    // Form actions (can be used for data exfiltration)
    "form",
    // Template (can bypass sanitizers)
    "template",
    // XML processing
    "xml", "xmp",
    // Deprecated dangerous
    "plaintext", "listing",
    // Custom elements registry
    "slot",
  ]
}

// =============================================================================
// Tag Checking Functions
// =============================================================================

///|
/// Check if a tag is in the allowed list
pub fn is_allowed_tag(tag : String, config : SanitizeConfig) -> Bool {
  let lower = to_lowercase(tag)

  // Check forbidden first (blocklist wins)
  if is_forbidden_tag(lower, config) {
    return false
  }

  // Check if in additional allowed tags
  if array_contains_str(config.additional_tags, lower) {
    return true
  }

  // Check HTML tags
  if config.allow_html && array_contains_str(allowed_html_tags(), lower) {
    return true
  }

  // Check SVG tags
  if config.allow_svg && array_contains_str(allowed_svg_tags(), lower) {
    return true
  }

  // Check MathML tags
  if config.allow_math && array_contains_str(allowed_math_tags(), lower) {
    return true
  }

  // Check custom elements (web components)
  if config.allow_custom_elements && is_custom_element(lower) {
    // If allowed_custom_elements is empty, allow all custom elements
    // Otherwise, only allow those in the whitelist
    if config.allowed_custom_elements.length() == 0 {
      return true
    }
    if array_contains_str(config.allowed_custom_elements, lower) {
      return true
    }
  }

  false
}

///|
/// Check if a tag name is a custom element (contains hyphen)
pub fn is_custom_element(tag : String) -> Bool {
  let chars = tag.to_array()
  for c in chars {
    if c == '-' {
      return true
    }
  }
  false
}

///|
/// Check if a tag is forbidden
pub fn is_forbidden_tag(tag : String, config : SanitizeConfig) -> Bool {
  let lower = to_lowercase(tag)

  // Check additional forbidden tags from config
  if array_contains_str(config.forbidden_tags, lower) {
    return true
  }

  // Check default forbidden tags
  array_contains_str(forbidden_tags(), lower)
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn array_contains_str(arr : Array[String], item : String) -> Bool {
  for s in arr {
    if s == item {
      return true
    }
  }
  false
}

///|
fn to_lowercase(s : String) -> String {
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

