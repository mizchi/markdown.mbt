///| Literal (source-preserving) renderer benchmarks.
///|
///| The literal renderer walks the same AST as the regular `render_html`
///| but emits one or two extra `<span>`s per node and (when enabled)
///| `data-src-*` attributes / `<img>` slots. These benches measure how
///| much of the renderer's runtime that extra work costs, in absolute
///| terms and relative to `render_html` and `serialize`.

// Reuse the document generator from bench.mbt — the same shape of
// markdown stress-tests every Block / Inline variant.

///|
let lit_small_doc : ParseResult = parse(small_doc)

///|
let lit_medium_doc : ParseResult = parse(medium_doc)

///|
let lit_large_doc : ParseResult = parse(large_doc)

// === Baseline: render_html for comparison =================================

///|
test "render_html: small document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html(lit_small_doc.document)
    b.keep(output)
  })
}

///|
test "render_html: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html(lit_medium_doc.document)
    b.keep(output)
  })
}

///|
test "render_html: large document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html(lit_large_doc.document)
    b.keep(output)
  })
}

// === Literal renderer: plain mode ==========================================

///|
test "render_html_literal: small document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(lit_small_doc.document)
    b.keep(output)
  })
}

///|
test "render_html_literal: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(lit_medium_doc.document)
    b.keep(output)
  })
}

///|
test "render_html_literal: large document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(lit_large_doc.document)
    b.keep(output)
  })
}

// === Literal renderer: positions=true ======================================

///|
test "render_html_literal+positions: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(lit_medium_doc.document, positions=true)
    b.keep(output)
  })
}

///|
test "render_html_literal+positions: large document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(lit_large_doc.document, positions=true)
    b.keep(output)
  })
}

// === Literal renderer: positions + image preview ==========================

///|
test "render_html_literal+positions+image: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = render_html_literal(
      lit_medium_doc.document,
      positions=true,
      image_preview=true,
    )
    b.keep(output)
  })
}

// === Parse + literal-render in one go (closer to consumer-side cost) ======

///|
test "md_to_html_literal: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = md_to_html_literal(medium_doc)
    b.keep(output)
  })
}

///|
test "md_to_html_literal+positions: medium document" (b : @bench.T) {
  b.bench(fn() {
    let output = md_to_html_literal(medium_doc, positions=true)
    b.keep(output)
  })
}
