///| Scanner / block-only benchmarks (split from bench.mbt).

// Scanner operation benchmarks

///|
let scanner_long_line : String = "ordinary text without markdown syntax ".repeat(
    128,
  ) +
  "\n"

///|
let scanner_line_16 : String = "123456789012345\n"

///|
let autolink_scan_text : String = "ordinary plain text and simple content ".repeat(
  128,
)

///|
test "scanner: line end scalar 16B" (b : @bench.T) {
  b.bench(fn() {
    b.keep(find_line_end_scalar(scanner_line_16, 0, scanner_line_16.length()))
  })
}

///|
test "scanner: line end SIMD dispatch 16B" (b : @bench.T) {
  b.bench(fn() {
    b.keep(find_line_end(scanner_line_16, 0, scanner_line_16.length()))
  })
}

///|
test "scanner: line end scalar 4KiB" (b : @bench.T) {
  b.bench(fn() {
    let end = find_line_end_scalar(
      scanner_long_line,
      0,
      scanner_long_line.length(),
    )
    b.keep(end)
  })
}

///|
test "scanner: line end SIMD dispatch 4KiB" (b : @bench.T) {
  b.bench(fn() {
    let end = find_line_end(scanner_long_line, 0, scanner_long_line.length())
    b.keep(end)
  })
}

///|
test "scanner: autolink candidate scalar 4KiB" (b : @bench.T) {
  b.bench(fn() {
    let found = find_autolink_candidate_scalar(
      autolink_scan_text,
      0,
      autolink_scan_text.length(),
    )
    b.keep(found)
  })
}

///|
test "scanner: autolink candidate SIMD dispatch 4KiB" (b : @bench.T) {
  b.bench(fn() {
    let found = find_autolink_candidate(
      autolink_scan_text,
      0,
      autolink_scan_text.length(),
    )
    b.keep(found)
  })
}

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
