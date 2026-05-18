///| Inline parsing benchmarks (split from bench.mbt).

// === Granular benchmarks ===

// Inline parsing benchmarks

///|
let inline_simple : String = "Hello World"

///|
let inline_emphasis : String = "Hello *world* and **bold** and `code` here"

///|
let inline_complex : String = "Check [this link](https://example.com \"title\") and ![image](img.png) with *emphasis* and **strong** and `code`"

///|
let inline_many : String = "*a* **b** `c` *d* **e** `f` *g* **h** `i` *j* **k** `l`"

// Emphasis edge cases for multi-pass testing

///|
let inline_nested_emphasis : String = "***foo*** and ***bar*** and ***baz***"

///|
let inline_emphasis_underscore : String = "_foo_ and __bar__ and ___baz___"

///|
let inline_mixed_emphasis : String = "*foo _bar* baz_ and **a _b_ c**"

///|
let inline_unclosed : String = "*unclosed and **also unclosed and more text here"

///|
let inline_many_emphasis : String = "*a* *b* *c* *d* *e* *f* *g* *h* *i* *j* **k** **l** **m** **n** **o**"

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

///|
test "inline: simple text" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_simple)
    b.keep(result)
  })
}

///|
test "inline: emphasis/strong/code" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_emphasis)
    b.keep(result)
  })
}

///|
test "inline: links and images" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_complex)
    b.keep(result)
  })
}

///|
test "inline: many markers" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_many)
    b.keep(result)
  })
}

// === Emphasis-specific benchmarks ===

///|
test "inline: nested emphasis (***)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_nested_emphasis)
    b.keep(result)
  })
}

///|
test "inline: underscore emphasis" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_emphasis_underscore)
    b.keep(result)
  })
}

///|
test "inline: mixed emphasis" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_mixed_emphasis)
    b.keep(result)
  })
}

///|
test "inline: unclosed markers" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_unclosed)
    b.keep(result)
  })
}

///|
test "inline: many emphasis (15 markers)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_many_emphasis)
    b.keep(result)
  })
}

///|
test "inline: stress 10 (30 markers)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_stress_10)
    b.keep(result)
  })
}

///|
test "inline: stress 50 (150 markers)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_stress_50)
    b.keep(result)
  })
}

///|
test "inline: stress 100 (300 markers)" (b : @bench.T) {
  b.bench(fn() {
    let result = parse_inlines(inline_stress_100)
    b.keep(result)
  })
}
