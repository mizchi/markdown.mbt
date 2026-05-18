///| GFM table parsing benchmarks (split from bench.mbt).

// Table parsing benchmarks

///|
let table_simple : String = "| A | B |\n|---|---|\n| 1 | 2 |\n"

///|
let table_medium : String = "| Col1 | Col2 | Col3 | Col4 |\n|:---|:---:|---:|---|\n| a | b | c | d |\n| e | f | g | h |\n| i | j | k | l |\n| m | n | o | p |\n| q | r | s | t |\n"

///|
fn generate_large_table(rows : Int, cols : Int) -> String {
  let buf = StringBuilder::new()
  // Header
  buf.write_string("|")
  for c = 0; c < cols; c = c + 1 {
    buf.write_string(" H\{c} |")
  }
  buf.write_string("\n|")
  for c = 0; c < cols; c = c + 1 {
    buf.write_string("---|")
  }
  buf.write_string("\n")
  // Rows
  for r = 0; r < rows; r = r + 1 {
    buf.write_string("|")
    for c = 0; c < cols; c = c + 1 {
      buf.write_string(" R\{r}C\{c} |")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
let table_large : String = generate_large_table(20, 5)

///|
test "table: simple 2x1" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(table_simple)
    b.keep(result)
  })
}

///|
test "table: medium 4x5" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(table_medium)
    b.keep(result)
  })
}

///|
test "table: large 5x20" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(table_large)
    b.keep(result)
  })
}
