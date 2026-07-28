///| DOMPurify Compatibility Tests

///|

///|
/// Ported from https://github.com/cure53/DOMPurify/blob/main/test/fixtures/expect.mjs

// =============================================================================
// DOM Clobbering Tests
// =============================================================================

test "DOMPurify: DOM clobbering against document.createElement()" {
  let html = "<img src=x name=createElement><img src=y id=createElement>"
  let result = sanitize(html)
  // name attribute should be removed to prevent DOM clobbering
  assert_eq(result.content.contains("name="), false)
}

///|
test "DOMPurify: DOM clobbering against an empty cookie" {
  let html = "<img src=x name=cookie>"
  let result = sanitize(html)
  assert_eq(result.content.contains("name="), false)
}

///|
test "DOMPurify: DOM clobbering getElementById" {
  let html = "<img src=x name=getElementById>"
  let result = sanitize(html)
  assert_eq(result.content.contains("name="), false)
}

///|
test "DOMPurify: DOM clobbering parentNode" {
  let html = "<div onclick=alert(0)><form onsubmit=alert(1)><input onfocus=alert(2) name=parentNode>123</form></div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onclick"), false)
  assert_eq(result.content.contains("onsubmit"), false)
  assert_eq(result.content.contains("onfocus"), false)
}

///|
test "DOMPurify: DOM clobbering activeElement" {
  let config = SanitizeConfig::permissive()
  let html = "<image name=activeElement><svg onload=alert(1)>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("onload"), false)
}

// =============================================================================
// JavaScript URI Tests
// =============================================================================

///|
test "DOMPurify: JavaScript URIs using Unicode whitespace" {
  let html = "<a href=\" javascript:alert(1)\">CLICK</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("javascript:"), false)
}

///|
test "DOMPurify: safe usage of URI-like attribute values" {
  // href with javascript: should be removed, but title is safe
  let html = "<b href=\"javascript:alert(1)\" title=\"javascript:alert(2)\"></b>"
  let result = sanitize(html)
  assert_eq(result.content.contains("title"), true)
}

///|
test "DOMPurify: Image with JavaScript URI src (DoS)" {
  let html = "<img src='javascript:while(1){}'>"
  let result = sanitize(html)
  assert_eq(result.content.contains("javascript:"), false)
}

///|
test "DOMPurify: Link with data URI href" {
  let html = "<a href=data:,evilnastystuff>clickme</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("data:"), false)
}

///|
test "DOMPurify: Low-range-ASCII obfuscated JavaScript URI" {
  // Contains control characters \u0001 and \u0003
  let html = "<a href=\"\u{0001}java\u{0003}script:alert(1)\">@shafigullin</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("script:"), false)
}

// =============================================================================
// Event Handler Tests (from DOMPurify)
// =============================================================================

///|
test "DOMPurify: onclick, onsubmit, onfocus combined" {
  let html = "<div onclick=alert(0)><form onsubmit=alert(1)><input onfocus=alert(2)>123</form></div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onclick"), false)
  assert_eq(result.content.contains("onsubmit"), false)
  assert_eq(result.content.contains("onfocus"), false)
  assert_eq(result.content.contains("123"), true)
}

///|
test "DOMPurify: onmouseout bypass attempt" {
  let html = "<div onmouseout=\"javascript:alert(/superevr/)\" x=yscript: n>@superevr</div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onmouseout"), false)
  assert_eq(result.content.contains("@superevr"), true)
}

///|
test "DOMPurify: onmousedown and onclick bypass attempt" {
  let html = "<button remove=me onmousedown=\"javascript:alert(1);\" onclick=\"javascript:alert(1)\" >@giutro"
  let result = sanitize(html)
  assert_eq(result.content.contains("onmousedown"), false)
  assert_eq(result.content.contains("onclick"), false)
  assert_eq(result.content.contains("@giutro"), true)
}

///|
test "DOMPurify: onfocus with autofocus" {
  let html = "<input x=javascript: autofocus onfocus=alert(1)>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onfocus"), false)
}

///|
test "DOMPurify: SVG onload" {
  let config = SanitizeConfig::permissive()
  let html = "<svg id=1 onload=alert(1)></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("onload"), false)
  assert_eq(result.content.contains("id"), true)
}

// =============================================================================
// Style Tag Tests
// =============================================================================

///|
test "DOMPurify: style tag removal" {
  let html = "<style>*{color: red}</style>"
  let result = sanitize(html)
  assert_eq(result.content, "")
}

///|
test "DOMPurify: style after self-closing style trick" {
  let html = "<b><style><style////><img src=x onerror=alert(1)></style>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
}

// =============================================================================
// Basic HTML Tests
// =============================================================================

///|
test "DOMPurify: simple numbers passthrough" {
  let html = "123456"
  let result = sanitize(html)
  assert_eq(result.content, "123456")
}

///|
test "DOMPurify: HTML paragraph with text" {
  let html = "<p>hello</p>"
  let result = sanitize(html)
  assert_eq(result.content, "<p>hello</p>")
}

// =============================================================================
// ARIA Attribute Tests
// =============================================================================

///|
test "DOMPurify: Don't remove ARIA attributes if not prohibited" {
  let html = "<div aria-labelledby=\"msg--title\" role=\"dialog\" class=\"msg\"><button class=\"modal-close\" aria-label=\"close\" type=\"button\">some button</button></div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("aria-labelledby"), true)
  assert_eq(result.content.contains("aria-label"), true)
  assert_eq(result.content.contains("role"), false) // role is not in default allowed
}

///|
test "DOMPurify: Don't remove binary attributes if considered safe" {
  let html = "<input type=checkbox checked><input type=checkbox onclick>"
  let result = sanitize(html)
  assert_eq(result.content.contains("checked"), true)
  assert_eq(result.content.contains("onclick"), false)
}

// =============================================================================
// Data URI Tests
// =============================================================================

///|
test "DOMPurify: Image with data URI src" {
  let html = "<img src=data:image/jpeg,ab798ewqxbaudbuoibeqbla>"
  let result = sanitize(html)
  assert_eq(result.content.contains("data:image/jpeg"), true)
}

///|
test "DOMPurify: src Attributes for IMG" {
  let html = "<img src=\"data:,123\">"
  let result = sanitize(html)
  // data:,123 is not a safe image data URI
  assert_eq(result.content.contains("data:,"), false)
}

// =============================================================================
// mXSS Variation Tests
// =============================================================================

///|
test "DOMPurify: mXSS Variation II" {
  let html = "<img src=x id/=' onerror=alert(1)//'>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
}

// =============================================================================
// Textarea and Comment Tests
// =============================================================================

///|
test "DOMPurify: Textarea and comments enabling img element" {
  let html = "<textarea>@shafigullin</textarea><!--</textarea><img src=x onerror=alert(1)>-->"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
}

// =============================================================================
// Iframe/Option Tests
// =============================================================================

///|
test "DOMPurify: Iframe inside option element" {
  let html = "<option><iframe></select><b><script>alert(1)</script>"
  let result = sanitize(html)
  assert_eq(result.content.contains("iframe"), false)
  assert_eq(result.content.contains("script"), false)
}

///|
test "DOMPurify: Closing Iframe and option" {
  let html = "</iframe></option>"
  let result = sanitize(html)
  // Closing tags without opening should be handled gracefully
  assert_eq(result.content.contains("iframe"), false)
}

// =============================================================================
// Bypass Attempt Tests
// =============================================================================

///|
test "DOMPurify: Bypass using multiple unknown attributes" {
  let html = "<div onmouseover=\"javascript:alert(/superevr/)\" x=yscript: n>@superevr</div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onmouseover"), false)
}

///|
test "DOMPurify: Bypass using DOM bugs with JS URIs" {
  let html = "<a href=\"javascript:123\" onclick=\"alert(1)\">CLICK ME</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("javascript:"), false)
  assert_eq(result.content.contains("onclick"), false)
  assert_eq(result.content.contains("CLICK ME"), true)
}

///|
test "DOMPurify: Bypass using unknown attributes III" {
  let html = "<div wow=removeme onmouseover=alert(1)>text"
  let result = sanitize(html)
  assert_eq(result.content.contains("onmouseover"), false)
  assert_eq(result.content.contains("text"), true)
}

// =============================================================================
// Template/Noscript Tests
// =============================================================================

///|
test "DOMPurify: Img element inside noscript" {
  let html = "<b><noscript><!-- </noscript><img src=x onerror=alert(1) --></noscript>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onerror"), false)
}

// =============================================================================
// Hex Encoded Entity Tests
// =============================================================================

///|
test "DOMPurify: hex encoded javascript URL" {
  // &#x6A; = j, &#x61; = a, etc.
  let html = "<a href=\"&#x6A;&#x61;&#x76;&#x61;&#x73;&#x63;&#x72;&#x69;&#x70;&#x74;&#x3A;alert(1)\">Click</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("alert"), false)
}

// =============================================================================
// Mixed Case and Obfuscation Tests
// =============================================================================

///|
test "DOMPurify: mixed case event handler" {
  let html = "<img src=x OnErRoR=alert(1)>"
  let result = sanitize(html)
  assert_eq(result.content.contains("OnErRoR"), false)
  assert_eq(result.content.contains("onerror"), false)
}

///|
test "DOMPurify: mixed case javascript URI" {
  let html = "<a href=\"JaVaScRiPt:alert(1)\">click</a>"
  let result = sanitize(html)
  assert_eq(result.content.contains("JaVaScRiPt"), false)
  assert_eq(result.content.contains("javascript"), false)
}

// =============================================================================
// Form Action Tests
// =============================================================================

///|
test "DOMPurify: form with onsubmit" {
  let html = "<form onsubmit=alert(1)><input name=nodeName>123</form>"
  let result = sanitize(html)
  assert_eq(result.content.contains("onsubmit"), false)
  assert_eq(result.content.contains("123"), true)
}

// =============================================================================
// SVG Specific Tests
// =============================================================================

///|
test "DOMPurify: SVG with script inside" {
  let config = SanitizeConfig::permissive()
  let html = "<svg><script>alert(1)</script></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("script"), false)
}

///|
test "DOMPurify: SVG foreignObject with script" {
  let config = SanitizeConfig::permissive()
  let html = "<svg><foreignObject><body><script>alert(1)</script></body></foreignObject></svg>"
  let result = sanitize(html, config~)
  assert_eq(result.content.contains("script"), false)
}

// =============================================================================
// Anchor Hash Link Tests
// =============================================================================

///|
test "DOMPurify: DOM clobbering location with hash" {
  let html = "<a href=\"#some-code-here\" id=\"location\">invisible"
  let result = sanitize(html)
  assert_eq(result.content.contains("href=\"#some-code-here\""), true)
}

// =============================================================================
// Empty/Whitespace Tests
// =============================================================================

///|
test "DOMPurify: empty input" {
  let html = ""
  let result = sanitize(html)
  assert_eq(result.content, "")
  assert_eq(result.was_modified, false)
}

///|
test "DOMPurify: whitespace only" {
  let html = "   \n\t  "
  let result = sanitize(html)
  assert_eq(result.content, "   \n\t  ")
}

// =============================================================================
// Nested Tag Tests
// =============================================================================

///|
test "DOMPurify: deeply nested safe tags" {
  let html = "<div><p><span><strong><em>text</em></strong></span></p></div>"
  let result = sanitize(html)
  assert_eq(result.content, html)
}

///|
test "DOMPurify: nested forbidden in allowed" {
  let html = "<div><p><script>alert(1)</script></p></div>"
  let result = sanitize(html)
  assert_eq(result.content.contains("script"), false)
  assert_eq(result.content.contains("div"), true)
  assert_eq(result.content.contains("p>"), true)
}
