///| Stateless string-search primitives used by the Markdown scanners.

///|
#inline
fn find_line_end_scalar(source : String, start : Int, end : Int) -> Int {
  for pos in start..<end {
    let c = source.unsafe_get(pos)
    if c == '\n' || c == '\r' {
      break pos
    }
  } nobreak {
    end
  }
}

///|
#cfg(not(any(target="native", target="wasm")))
#inline
fn find_line_end(source : String, start : Int, end : Int) -> Int {
  find_line_end_scalar(source, start, end)
}

///|
/// Find CR/LF eight UTF-16 code units at a time on linear-memory targets.
#cfg(any(target="native", target="wasm"))
fn find_line_end(source : String, start : Int, end : Int) -> Int {
  // Short Markdown lines are common, and SIMD setup costs more than a scalar
  // scan there. Two vector widths is the crossover point on wasm.
  guard end - start >= 16 else {
    return find_line_end_scalar(source, start, end)
  }
  let lf = @v128.i16x8_splat('\n')
  let cr = @v128.i16x8_splat('\r')
  let tail_start = for pos = start; pos + 8 <= end; {
    let block = @v128.v128_load_i16x8(source, pos)
    let mask = @v128.i16x8_bitmask(
      @v128.v128_or_(@v128.i16x8_eq(block, lf), @v128.i16x8_eq(block, cr)),
    )
    if mask != 0 {
      return pos + mask.ctz()
    }
    continue pos + 8
  } nobreak {
    pos
  }
  find_line_end_scalar(source, tail_start, end)
}

///| Find a substring at or after `start`, returning its absolute start offset.

///|
/// `StringView::find` uses MoonBit core's SIMD scanner for linear-memory
/// targets, while keeping the JavaScript fallback optimized for that backend.
#inline
fn find_exact_from(text : String, start : Int, needle : StringView) -> Int? {
  guard start >= 0 && start <= text.length() else { return None }
  match text[start:].find(needle) {
    Some(relative) => Some(start + relative)
    None => None
  }
}

///|
/// Find a substring and return its absolute end offset.
#inline
fn find_exact_end_from(text : String, start : Int, needle : StringView) -> Int? {
  match find_exact_from(text, start, needle) {
    Some(found) => Some(found + needle.length())
    None => None
  }
}
