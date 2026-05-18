///| Markdown parser benchmarks

///| Run with: moon bench --target js -p mizchi/luna/core/markdown

///|
/// Generate a sample markdown document of given size
fn generate_sample_markdown(paragraphs : Int) -> String {
  let buf = StringBuilder::new()

  // Frontmatter
  buf.write_string("---\n")
  buf.write_string("title: Benchmark Document\n")
  buf.write_string("author: Test\n")
  buf.write_string("---\n\n")

  // Title
  buf.write_string("# Benchmark Document\n\n")

  // Content
  for i = 0; i < paragraphs; i = i + 1 {
    // Heading
    buf.write_string("## Section \{i + 1}\n\n")

    // Paragraph
    buf.write_string(
      "This is a paragraph of text. It contains some content that needs to be parsed. ",
    )
    buf.write_string("Markdown is a lightweight markup language. ")
    buf.write_string("It is often used for formatting readme files.\n\n")

    // Code block
    buf.write_string("```javascript\n")
    buf.write_string("function hello() {\n")
    buf.write_string("  console.log('Hello, World!');\n")
    buf.write_string("}\n")
    buf.write_string("```\n\n")

    // List
    buf.write_string("- Item one\n")
    buf.write_string("- Item two\n")
    buf.write_string("- Item three\n\n")

    // Blockquote
    buf.write_string("> This is a blockquote.\n")
    buf.write_string("> It spans multiple lines.\n\n")
  }
  buf.to_string()
}

// Pre-generate test documents

///|
let small_doc : String = generate_sample_markdown(5)

///|
let medium_doc : String = generate_sample_markdown(20)

///|
let large_doc : String = generate_sample_markdown(100)

///|
test "parse: small document (5 sections)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(small_doc)
    b.keep(result)
  })
}

///|
test "parse: medium document (20 sections)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(medium_doc)
    b.keep(result)
  })
}

///|
test "parse: large document (100 sections)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(large_doc)
    b.keep(result)
  })
}

///|
test "serialize: small document" (b : @bench.T) {
  let parsed = parse(small_doc)
  b.bench(fn() {
    let output = serialize(parsed.document)
    b.keep(output)
  })
}

///|
test "serialize: medium document" (b : @bench.T) {
  let parsed = parse(medium_doc)
  b.bench(fn() {
    let output = serialize(parsed.document)
    b.keep(output)
  })
}

///|
test "roundtrip: small document" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(small_doc)
    let output = serialize(result.document)
    b.keep(output)
  })
}

///|
test "roundtrip: medium document" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(medium_doc)
    let output = serialize(result.document)
    b.keep(output)
  })
}

// === Span allocation benchmark ===

///|
test "span: creation 1000x" (b : @bench.T) {
  b.bench(fn() {
    let mut last = Span::new(0, 0)
    for i = 0; i < 1000; i = i + 1 {
      last = Span::new(i, i + 10)
    }
    b.keep(last)
  })
}
