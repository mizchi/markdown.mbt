// Markdown parser benchmark runner
// Run with different targets to compare performance:
//   moon run benches --target js
//   moon run benches --target wasm-gc
//   moon run benches --target native

///|
/// Generate a sample markdown document (CommonMark compatible, no frontmatter)
fn generate_sample_markdown(paragraphs : Int) -> String {
  let buf = StringBuilder()
  buf.write_string("# Benchmark Document\n\n")
  for i in 0..<paragraphs {
    buf.write_string("## Section \{i + 1}\n\n")
    buf.write_string(
      "This is a paragraph of text. It contains some content that needs to be parsed. ",
    )
    buf.write_string("Markdown is a lightweight markup language. ")
    buf.write_string("It is often used for formatting readme files.\n\n")
    buf.write_string("```javascript\n")
    buf.write_string("function hello() {\n")
    buf.write_string("  console.log('Hello, World!');\n")
    buf.write_string("}\n")
    buf.write_string("```\n\n")
    buf.write_string("- Item one\n")
    buf.write_string("- Item two\n")
    buf.write_string("- Item three\n\n")
    buf.write_string("> This is a blockquote.\n")
    buf.write_string("> It spans multiple lines.\n\n")
  }
  buf.to_string()
}

///|
/// Generate paragraph-only document for incremental testing
fn generate_paragraph_doc(count : Int) -> String {
  let buf = StringBuilder()
  buf.write_string("# Document Title\n\n")
  for i in 0..<count {
    buf.write_string(
      "Paragraph \{i + 1} with some content that needs parsing. ",
    )
    buf.write_string("This is a *sample* paragraph with **formatting**.\n\n")
  }
  buf.to_string()
}

///|
/// Benchmark result structure
struct BenchResult {
  name : String
  iterations : Int
  avg_us : Double // microseconds per iteration
}

///|
fn BenchResult::to_string(self : BenchResult) -> String {
  let avg_str = self.avg_us.to_string()
  "\{self.name}: \{avg_str} us/iter (\{self.iterations} iterations)"
}

///|
/// Run a benchmark
fn run_bench(name : String, iterations : Int, f : () -> Unit) -> BenchResult {
  // Warmup
  for _ in 0..<3 {
    f()
  }
  // Timed runs
  let start = instant_now()
  for _ in 0..<iterations {
    f()
  }
  let elapsed_ms = instant_elapsed_ms(start)
  let avg_us = elapsed_ms / iterations.to_double() * 1000.0
  { name, iterations, avg_us }
}

///|
fn main {
  println("=== Markdown Parser Benchmark ===\n")

  // Pre-generate test documents
  let small_doc = generate_sample_markdown(5)
  let medium_doc = generate_sample_markdown(20)
  let large_doc = generate_sample_markdown(100)
  println("Document sizes:")
  println("  small (5 sections):   \{small_doc.length()} chars")
  println("  medium (20 sections): \{medium_doc.length()} chars")
  println("  large (100 sections): \{large_doc.length()} chars")
  println("")
  let results : Array[BenchResult] = []

  // Parse benchmarks
  println("--- Parse Benchmarks ---")
  let r1 = run_bench("parse:small", 100, fn() {
    let _ = @markdown.parse(small_doc)

  })
  println(r1.to_string())
  results.push(r1)
  let r2 = run_bench("parse:medium", 50, fn() {
    let _ = @markdown.parse(medium_doc)

  })
  println(r2.to_string())
  results.push(r2)
  let r3 = run_bench("parse:large", 20, fn() {
    let _ = @markdown.parse(large_doc)

  })
  println(r3.to_string())
  results.push(r3)
  println("")

  // Serialize benchmarks
  println("--- Serialize Benchmarks ---")
  let parsed_small = @markdown.parse(small_doc)
  let parsed_medium = @markdown.parse(medium_doc)
  let parsed_large = @markdown.parse(large_doc)
  let r4 = run_bench("serialize:small", 100, fn() {
    let _ = @markdown.serialize(parsed_small.document)

  })
  println(r4.to_string())
  results.push(r4)
  let r5 = run_bench("serialize:medium", 50, fn() {
    let _ = @markdown.serialize(parsed_medium.document)

  })
  println(r5.to_string())
  results.push(r5)
  let r6 = run_bench("serialize:large", 20, fn() {
    let _ = @markdown.serialize(parsed_large.document)

  })
  println(r6.to_string())
  results.push(r6)
  println("")

  // Roundtrip benchmarks
  println("--- Roundtrip Benchmarks ---")
  let r7 = run_bench("roundtrip:small", 100, fn() {
    let parsed = @markdown.parse(small_doc)
    let _ = @markdown.serialize(parsed.document)

  })
  println(r7.to_string())
  results.push(r7)
  let r8 = run_bench("roundtrip:medium", 50, fn() {
    let parsed = @markdown.parse(medium_doc)
    let _ = @markdown.serialize(parsed.document)

  })
  println(r8.to_string())
  results.push(r8)
  println("")

  // Incremental parse benchmarks
  println("--- Incremental Parse Benchmarks ---")
  let inc_doc_50 = generate_paragraph_doc(50)
  let inc_doc_100 = generate_paragraph_doc(100)
  let inc_parsed_50 = @markdown.parse(inc_doc_50)
  let inc_parsed_100 = @markdown.parse(inc_doc_100)

  // Edit in middle: replace "Paragraph" with "PARAGRAPH"
  let edit_offset = inc_doc_50.length() / 2
  let new_doc_50 = inc_doc_50[:edit_offset].to_owned() +
    "CHANGED" +
    inc_doc_50[edit_offset + 7:].to_owned()
  let edit_50 = @markdown.EditInfo::replace(edit_offset, 7, 7)
  let r9 = run_bench("full_parse:50_paragraphs", 50, fn() {
    let _ = @markdown.parse(inc_doc_50)

  })
  println(r9.to_string())
  results.push(r9)
  let r10 = run_bench("incremental:50_paragraphs", 100, fn() {
    let _ = @markdown.parse_incremental(
      inc_parsed_50.document,
      inc_doc_50,
      new_doc_50,
      edit_50,
    )

  })
  println(r10.to_string())
  results.push(r10)
  let edit_offset_100 = inc_doc_100.length() / 2
  let new_doc_100 = inc_doc_100[:edit_offset_100].to_owned() +
    "CHANGED" +
    inc_doc_100[edit_offset_100 + 7:].to_owned()
  let edit_100 = @markdown.EditInfo::replace(edit_offset_100, 7, 7)
  let r11 = run_bench("full_parse:100_paragraphs", 30, fn() {
    let _ = @markdown.parse(inc_doc_100)

  })
  println(r11.to_string())
  results.push(r11)
  let r12 = run_bench("incremental:100_paragraphs", 100, fn() {
    let _ = @markdown.parse_incremental(
      inc_parsed_100.document,
      inc_doc_100,
      new_doc_100,
      edit_100,
    )

  })
  println(r12.to_string())
  results.push(r12)
  println("")

  // Summary
  println("=== Summary ===")
  println("Benchmark completed with \{results.length()} tests")

  // Calculate speedup for incremental parsing
  let full_50 = results[8].avg_us
  let inc_50 = results[9].avg_us
  let speedup_50 = full_50 / inc_50
  let full_100 = results[10].avg_us
  let inc_100 = results[11].avg_us
  let speedup_100 = full_100 / inc_100
  println("\nIncremental parsing speedup:")
  println("  50 paragraphs:  \{speedup_50.to_string()}x faster")
  println("  100 paragraphs: \{speedup_100.to_string()}x faster")

  // Write results to file
  let output = StringBuilder()
  output.write_string("benchmark,iterations,avg_us\n")
  for r in results {
    output.write_string("\{r.name},\{r.iterations},\{r.avg_us}\n")
  }
  try {
    @fs.write_string_to_file("bench_results.csv", output.to_string())
    println("\nResults written to bench_results.csv")
  } catch {
    @fs.IOError(message) => println("\nFailed to write results: \{message}")
  }
}
