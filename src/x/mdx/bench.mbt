///| MDX Parser Benchmarks

// =============================================================================
// Test Data
// =============================================================================

///|
let simple_import : String = "import Button from './Button'\n"

///|
let named_imports : String = "import { Button, Card, Modal } from './components'\n"

///|
let complex_imports : String = "import React from 'react'\nimport { useState, useEffect } from 'react'\nimport * as Components from './components'\nimport Layout, { Header, Footer } from './layout'\n"

///|
let simple_export : String = "export const title = 'Hello World'\n"

///|
let function_export : String = "export function getLayout() { return <Layout /> }\n"

///|
let simple_jsx : String = "<Button>Click me</Button>\n"

///|
let jsx_with_attrs : String = "<Button variant=\"primary\" onClick={handleClick} disabled>Submit</Button>\n"

///|
let self_closing_jsx : String = "<Image src=\"/photo.jpg\" alt=\"Photo\" width={800} height={600} />\n"

///|
let web_component : String = "<my-component data-value=\"123\" on-click={handler}>Content</my-component>\n"

///|
fn generate_mdx_doc(imports : Int, exports : Int, components : Int) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < imports; i = i + 1 {
    buf.write_string("import Component\{i} from './Component\{i}'\n")
  }
  buf.write_string("\n")
  for i = 0; i < exports; i = i + 1 {
    buf.write_string("export const value\{i} = 'value\{i}'\n")
  }
  buf.write_string("\n# Title\n\n")
  for i = 0; i < components; i = i + 1 {
    buf.write_string(
      "<Component\{i} prop\{i}=\"value\{i}\">Content \{i}</Component\{i}>\n\n",
    )
  }
  buf.to_string()
}

///|
let small_mdx_doc : String = generate_mdx_doc(3, 2, 5)

///|
let medium_mdx_doc : String = generate_mdx_doc(10, 5, 20)

///|
let large_mdx_doc : String = generate_mdx_doc(30, 10, 50)

// Pre-parse documents for extraction benchmarks

///|
let small_parsed : @markdown.ParseResult = @markdown.parse(small_mdx_doc)

///|
let medium_parsed : @markdown.ParseResult = @markdown.parse(medium_mdx_doc)

// =============================================================================
// Import Parsing Benchmarks
// =============================================================================

///|
test "mdx: parse simple import" (b : @bench.T) {
  let result = @markdown.parse(simple_import)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse named imports" (b : @bench.T) {
  let result = @markdown.parse(named_imports)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse complex imports" (b : @bench.T) {
  let result = @markdown.parse(complex_imports)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

// =============================================================================
// Export Parsing Benchmarks
// =============================================================================

///|
test "mdx: parse simple export" (b : @bench.T) {
  let result = @markdown.parse(simple_export)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse function export" (b : @bench.T) {
  let result = @markdown.parse(function_export)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

// =============================================================================
// JSX Parsing Benchmarks
// =============================================================================

///|
test "mdx: parse simple jsx" (b : @bench.T) {
  let result = @markdown.parse(simple_jsx)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse jsx with attributes" (b : @bench.T) {
  let result = @markdown.parse(jsx_with_attrs)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse self-closing jsx" (b : @bench.T) {
  let result = @markdown.parse(self_closing_jsx)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse web component" (b : @bench.T) {
  let result = @markdown.parse(web_component)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

// =============================================================================
// Document Parsing Benchmarks
// =============================================================================

///|
test "mdx: parse small document" (b : @bench.T) {
  let result = @markdown.parse(small_mdx_doc)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse medium document" (b : @bench.T) {
  let result = @markdown.parse(medium_mdx_doc)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

///|
test "mdx: parse large document" (b : @bench.T) {
  let result = @markdown.parse(large_mdx_doc)
  b.bench(fn() {
    let blocks = parse_mdx_blocks(result.document)
    b.keep(blocks)
  })
}

// =============================================================================
// Metadata Extraction Benchmarks
// =============================================================================

///|
test "mdx: extract metadata small" (b : @bench.T) {
  b.bench(fn() {
    let metadata = extract_mdx_metadata(small_parsed.document)
    b.keep(metadata)
  })
}

///|
test "mdx: extract metadata medium" (b : @bench.T) {
  b.bench(fn() {
    let metadata = extract_mdx_metadata(medium_parsed.document)
    b.keep(metadata)
  })
}

///|
test "mdx: extract import sources" (b : @bench.T) {
  b.bench(fn() {
    let sources = extract_import_sources(medium_parsed.document)
    b.keep(sources)
  })
}

///|
test "mdx: extract component names" (b : @bench.T) {
  b.bench(fn() {
    let names = extract_component_names(medium_parsed.document)
    b.keep(names)
  })
}

// =============================================================================
// Transformer Benchmarks
// =============================================================================

///|
test "mdx: strip mdx blocks" (b : @bench.T) {
  b.bench(fn() {
    let stripped = strip_mdx_blocks(medium_parsed.document)
    b.keep(stripped)
  })
}

///|
test "mdx: strip imports only" (b : @bench.T) {
  b.bench(fn() {
    let stripped = strip_imports(medium_parsed.document)
    b.keep(stripped)
  })
}

// =============================================================================
// Attribute Parsing Benchmarks
// =============================================================================

///|
let attr_simple : String = " name=\"value\">"

///|
let attr_expression : String = " onClick={handleClick}>"

///|
let attr_complex : String = " id=\"main\" class='container' onClick={handleClick} data={{ key: 'value' }} disabled>"

///|
test "mdx: parse simple attribute" (b : @bench.T) {
  b.bench(fn() {
    let (attrs, _) = parse_attributes(attr_simple, 0)
    b.keep(attrs)
  })
}

///|
test "mdx: parse expression attribute" (b : @bench.T) {
  b.bench(fn() {
    let (attrs, _) = parse_attributes(attr_expression, 0)
    b.keep(attrs)
  })
}

///|
test "mdx: parse complex attributes" (b : @bench.T) {
  b.bench(fn() {
    let (attrs, _) = parse_attributes(attr_complex, 0)
    b.keep(attrs)
  })
}
