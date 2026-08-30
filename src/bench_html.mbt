///| HTML block and inline parsing benchmarks.

///|
let html_long_payload : String = "ordinary HTML payload without a terminator ".repeat(
  128,
)

///|
let html_long_comment_block : String = "<!--" + html_long_payload + "-->\n"

///|
let html_long_raw_text_block : String = "<script>\n" +
  html_long_payload +
  "\n</SCRIPT>\n"

///|
let html_long_inline_comment : String = "before <!--" +
  html_long_payload +
  "--> after\n"

///|
let html_long_quoted_attribute : String = "before <span data-value=\"" +
  html_long_payload +
  "\">text</span> after\n"

///|
test "html: long comment block" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(html_long_comment_block)
    b.keep(result)
  })
}

///|
test "html: long raw text block" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(html_long_raw_text_block)
    b.keep(result)
  })
}

///|
test "html: long inline comment" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(html_long_inline_comment)
    b.keep(result)
  })
}

///|
test "html: long quoted attribute" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(html_long_quoted_attribute)
    b.keep(result)
  })
}
