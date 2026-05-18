///| Scanner / block-only benchmarks (split from bench.mbt).

// Scanner operation benchmarks

///|
test "scanner: read_line 100x" (b : @bench.T) {
  let text = "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n".repeat(
    10,
  )
  b.bench(fn() {
    let scanner = Scanner::new(text)
    let mut count = 0
    while !scanner.is_eof() {
      let _ = scanner.read_line()
      if char_is(scanner.peek(), '\n') {
        scanner.advance(1)
      }
      count += 1
    }
    b.keep(count)
  })
}

///|
test "scanner: peek/advance intensive" (b : @bench.T) {
  let text = "abcdefghijklmnopqrstuvwxyz".repeat(100)
  b.bench(fn() {
    let scanner = Scanner::new(text)
    let mut count = 0
    while !scanner.is_eof() {
      let _ = scanner.peek()
      scanner.advance(1)
      count += 1
    }
    b.keep(count)
  })
}

// Block-only parsing (paragraph with no inline markers)

///|
let block_only_doc : String = "# Title\n\nPlain paragraph one.\n\nPlain paragraph two.\n\n```\ncode block\n```\n\n- item 1\n- item 2\n- item 3\n\n> quote here\n"

///|
test "block: minimal inline content" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(block_only_doc)
    b.keep(result)
  })
}
