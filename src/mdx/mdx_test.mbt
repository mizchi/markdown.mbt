///| MDX Parser Tests

// =============================================================================
// Attribute Parser Tests
// =============================================================================

test "parse string attribute with double quotes" {
  let (attrs, _) = parse_attributes(" name=\"value\">", 0)
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0].name, "name")
  match attrs[0].value {
    StringValue(v) => assert_eq(v, "value")
    _ => fail("Expected StringValue")
  }
}

test "parse string attribute with single quotes" {
  let (attrs, _) = parse_attributes(" name='value'>", 0)
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0].name, "name")
  match attrs[0].value {
    StringValue(v) => assert_eq(v, "value")
    _ => fail("Expected StringValue")
  }
}

test "parse expression attribute" {
  let (attrs, _) = parse_attributes(" count={42}>", 0)
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0].name, "count")
  match attrs[0].value {
    ExpressionValue(v) => assert_eq(v, "42")
    _ => fail("Expected ExpressionValue")
  }
}

test "parse boolean attribute" {
  let (attrs, _) = parse_attributes(" disabled>", 0)
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0].name, "disabled")
  match attrs[0].value {
    BooleanValue => ()
    _ => fail("Expected BooleanValue")
  }
}

test "parse multiple attributes" {
  let (attrs, _) = parse_attributes(" id=\"main\" class='container' onClick={handleClick} disabled>", 0)
  assert_eq(attrs.length(), 4)
  assert_eq(attrs[0].name, "id")
  assert_eq(attrs[1].name, "class")
  assert_eq(attrs[2].name, "onClick")
  assert_eq(attrs[3].name, "disabled")
}

test "parse nested expression" {
  let (attrs, _) = parse_attributes(" data={{ key: 'value' }}>", 0)
  assert_eq(attrs.length(), 1)
  assert_eq(attrs[0].name, "data")
  match attrs[0].value {
    ExpressionValue(v) => assert_eq(v, "{ key: 'value' }")
    _ => fail("Expected ExpressionValue")
  }
}

// =============================================================================
// Import Parser Tests
// =============================================================================

test "parse default import" {
  let result = @markdown.parse("import Layout from './Layout'\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ImportDecl(specifiers~, source~, ..) => {
      assert_eq(source, "./Layout")
      assert_eq(specifiers.length(), 1)
      assert_eq(specifiers[0].name, "Layout")
      assert_eq(specifiers[0].is_default, true)
    }
    _ => fail("Expected ImportDecl")
  }
}

test "parse named imports" {
  let result = @markdown.parse("import { Button, Card } from './components'\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ImportDecl(specifiers~, source~, ..) => {
      assert_eq(source, "./components")
      assert_eq(specifiers.length(), 2)
      assert_eq(specifiers[0].name, "Button")
      assert_eq(specifiers[1].name, "Card")
    }
    _ => fail("Expected ImportDecl")
  }
}

test "parse aliased import" {
  let result = @markdown.parse("import { Button as Btn } from './components'\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ImportDecl(specifiers~, ..) => {
      assert_eq(specifiers.length(), 1)
      assert_eq(specifiers[0].name, "Button")
      assert_eq(specifiers[0].local_name, Some("Btn"))
    }
    _ => fail("Expected ImportDecl")
  }
}

test "parse namespace import" {
  let result = @markdown.parse("import * as Components from './components'\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ImportDecl(specifiers~, ..) => {
      assert_eq(specifiers.length(), 1)
      assert_eq(specifiers[0].name, "Components")
      assert_eq(specifiers[0].is_star, true)
    }
    _ => fail("Expected ImportDecl")
  }
}

// =============================================================================
// Export Parser Tests
// =============================================================================

test "parse export const" {
  let result = @markdown.parse("export const title = 'Hello'\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ExportDecl(kind~, name~, value~, ..) => {
      assert_eq(kind, ExportKind::Const)
      assert_eq(name, Some("title"))
      assert_eq(value, "'Hello'")
    }
    _ => fail("Expected ExportDecl")
  }
}

test "parse export default" {
  let result = @markdown.parse("export default Layout\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ExportDecl(kind~, name~, value~, ..) => {
      assert_eq(kind, ExportKind::Default)
      assert_eq(name, None)
      assert_eq(value, "Layout")
    }
    _ => fail("Expected ExportDecl")
  }
}

test "parse export function" {
  let result = @markdown.parse("export function getLayout() { return <Layout /> }\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    ExportDecl(kind~, name~, ..) => {
      assert_eq(kind, ExportKind::Function)
      assert_eq(name, Some("getLayout"))
    }
    _ => fail("Expected ExportDecl")
  }
}

// =============================================================================
// JSX Element Tests
// =============================================================================

test "parse JSX component" {
  let result = @markdown.parse("<Button>Click me</Button>\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    JsxElement(tag~, children~, self_closing~, ..) => {
      assert_eq(tag, "Button")
      assert_eq(children, "Click me")
      assert_eq(self_closing, false)
    }
    _ => fail("Expected JsxElement")
  }
}

test "parse self-closing JSX" {
  let result = @markdown.parse("<Spacer />\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    JsxElement(tag~, children~, self_closing~, ..) => {
      assert_eq(tag, "Spacer")
      assert_eq(children, "")
      assert_eq(self_closing, true)
    }
    _ => fail("Expected JsxElement")
  }
}

test "parse JSX with attributes" {
  let result = @markdown.parse("<Button variant=\"primary\" onClick={handleClick}>Submit</Button>\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    JsxElement(tag~, attributes~, ..) => {
      assert_eq(tag, "Button")
      assert_eq(attributes.length(), 2)
      assert_eq(attributes[0].name, "variant")
      assert_eq(attributes[1].name, "onClick")
    }
    _ => fail("Expected JsxElement")
  }
}

test "parse Web Component" {
  let result = @markdown.parse("<my-component data-value=\"123\">Content</my-component>\n")
  let blocks = parse_mdx_blocks(result.document)
  assert_eq(blocks.length(), 1)
  match blocks[0] {
    JsxElement(tag~, attributes~, children~, ..) => {
      assert_eq(tag, "my-component")
      assert_eq(attributes.length(), 1)
      assert_eq(attributes[0].name, "data-value")
      assert_eq(children, "Content")
    }
    _ => fail("Expected JsxElement")
  }
}

// =============================================================================
// Metadata Extraction Tests
// =============================================================================

test "extract metadata from MDX document" {
  let mdx =
    #|import { Button } from './components'
    #|import Layout from './Layout'
    #|export const title = 'Hello'
    #|
    #|# Heading
    #|
    #|<Button>Click</Button>
    #|
    #|<my-element />
    #|

  let result = @markdown.parse(mdx)
  let metadata = extract_mdx_metadata(result.document)

  assert_eq(metadata.imports.length(), 2)
  assert_eq(metadata.exports.length(), 1)
  assert_eq(metadata.components.length(), 2)
}

test "extract import sources" {
  let mdx =
    #|import { Button } from './components'
    #|import Layout from './Layout'
    #|

  let result = @markdown.parse(mdx)
  let sources = extract_import_sources(result.document)

  assert_eq(sources.length(), 2)
}

test "extract component names" {
  let mdx =
    #|<Button>Click</Button>
    #|
    #|<my-element attr="value">Content</my-element>
    #|

  let result = @markdown.parse(mdx)
  let names = extract_component_names(result.document)

  assert_eq(names.length(), 2)
}

// =============================================================================
// Transformer Tests
// =============================================================================

test "strip all MDX blocks" {
  let mdx =
    #|import { Button } from './components'
    #|
    #|# Heading
    #|
    #|Some text
    #|
    #|<Button>Click</Button>
    #|

  let result = @markdown.parse(mdx)
  let stripped = strip_mdx_blocks(result.document)

  // Should have fewer blocks (import and JSX removed)
  assert_true(stripped.children.length() < result.document.children.length())
}

test "strip only imports" {
  let mdx =
    #|import { Button } from './components'
    #|
    #|# Heading
    #|
    #|<Button>Click</Button>
    #|

  let result = @markdown.parse(mdx)
  let stripped = strip_imports(result.document)

  // JSX should still be present
  let jsx_blocks = extract_jsx_elements(stripped)
  assert_eq(jsx_blocks.length(), 1)
}

// =============================================================================
// Helper Function Tests
// =============================================================================

test "is_jsx_component detects uppercase start" {
  assert_true(is_jsx_component("Button"))
  assert_true(is_jsx_component("MyComponent"))
  assert_false(is_jsx_component("button"))
  assert_false(is_jsx_component("my-element"))
}

test "is_web_component detects hyphen" {
  assert_true(is_web_component("my-element"))
  assert_true(is_web_component("custom-button"))
  assert_false(is_web_component("Button"))
  assert_false(is_web_component("div"))
}

test "is_mdx_tag combines both checks" {
  assert_true(is_mdx_tag("Button"))        // JSX
  assert_true(is_mdx_tag("my-element"))    // Web Component
  assert_false(is_mdx_tag("div"))          // HTML
  assert_false(is_mdx_tag("span"))         // HTML
}
