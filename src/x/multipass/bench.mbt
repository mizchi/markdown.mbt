///| Multipass / tokenizer benchmarks

///|
let inline_simple : String = "Hello world, this is plain text without any markup."

///|
let inline_emphasis : String = "Make it *italic* and **bold** and `code` and even ***both***"

///|
fn generate_inline_stress(count : Int) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < count; i = i + 1 {
    buf.write_string("*em\{i}* **strong\{i}** `code\{i}` ")
  }
  buf.to_string()
}

///|
let inline_stress_10 : String = generate_inline_stress(10)

///|
let inline_stress_50 : String = generate_inline_stress(50)

///|
let inline_stress_100 : String = generate_inline_stress(100)

// === Tokenizer benchmarks ===

///|
test "tokenize: simple text" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_simple)
    let result = tokenize_inline(scanner)
    b.keep(result)
  })
}

///|
test "tokenize: emphasis" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_emphasis)
    let result = tokenize_inline(scanner)
    b.keep(result)
  })
}

///|
test "tokenize: stress 50" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_stress_50)
    let result = tokenize_inline(scanner)
    b.keep(result)
  })
}

///|
test "tokenize: stress 100" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_stress_100)
    let result = tokenize_inline(scanner)
    b.keep(result)
  })
}

// Pre-tokenize for CloserIndex benchmarks

///|
let _tokens_stress_50 : Array[InlineToken] = tokenize_inline(
  @markdown.Scanner::new(inline_stress_50),
)

///|
let tokens_stress_100 : Array[InlineToken] = tokenize_inline(
  @markdown.Scanner::new(inline_stress_100),
)

///|
test "closer_index: build stress 50" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_stress_50)
    let tokens = tokenize_inline(scanner)
    let idx = build_closer_index(tokens)
    b.keep(idx)
  })
}

///|
test "closer_index: build stress 100" (b : @bench.T) {
  b.bench(fn() {
    let scanner = @markdown.Scanner::new(inline_stress_100)
    let tokens = tokenize_inline(scanner)
    let idx = build_closer_index(tokens)
    b.keep(idx)
  })
}

///|
test "closer_index: lookup 100x" (b : @bench.T) {
  let idx = build_closer_index(tokens_stress_100)
  b.bench(fn() {
    let mut found = 0
    for i = 0; i < 100; i = i + 1 {
      if idx.has_closer(CloserKey::Emphasis('*'), i * 10) {
        found += 1
      }
    }
    b.keep(found)
  })
}

// === Multipass parser benchmarks ===

///|
test "multipass: simple text" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines_multipass(inline_simple)
    b.keep(result)
  })
}

///|
test "multipass: emphasis" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines_multipass(inline_emphasis)
    b.keep(result)
  })
}

///|
test "multipass: stress 10" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines_multipass(inline_stress_10)
    b.keep(result)
  })
}

///|
test "multipass: stress 50" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines_multipass(inline_stress_50)
    b.keep(result)
  })
}

///|
test "multipass: stress 100" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines_multipass(inline_stress_100)
    b.keep(result)
  })
}
