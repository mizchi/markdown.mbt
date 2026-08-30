///|
/// Find the first character that can start inline Markdown syntax.
#inline
fn find_inline_marker_candidate_scalar(
  text : String,
  start : Int,
  end : Int,
) -> Int {
  for pos in start..<end {
    if is_inline_marker_code_unit(text.unsafe_get(pos)) {
      break pos
    }
  } nobreak {
    end
  }
}

///| Scan UTF-8 bytes through the external Wasm ESM bridge.

///|
/// The module returns -2 if a non-ASCII byte precedes a marker. The caller
/// then uses the UTF-16 scalar scanner, preserving MoonBit String offsets.
#cfg(target="js")
extern "js" fn find_inline_marker_wasm_utf8(
  text : String,
  start : Int,
  end : Int,
) -> Int =
  #| (text, start, end) => {
  #| const bridge = globalThis.__mizchiMarkdownInlineMarkerSimd;
  #| return bridge === undefined
  #| ? -2
  #| : bridge.findInlineMarkerUtf8(text, start, end);
  #| }

///|
/// Use the copy-inclusive Wasm path only for runs long enough to amortize
/// TextEncoder and the JS/Wasm boundary.
#cfg(target="js")
fn find_inline_marker_candidate(text : String, start : Int, end : Int) -> Int {
  guard end - start >= 64 else {
    return find_inline_marker_candidate_scalar(text, start, end)
  }
  match find_inline_marker_wasm_utf8(text, start, end) {
    -1 => end
    -2 => find_inline_marker_candidate_scalar(text, start, end)
    found => found
  }
}

///|
#cfg(not(target="js"))
#inline
fn find_inline_marker_candidate(text : String, start : Int, end : Int) -> Int {
  find_inline_marker_candidate_scalar(text, start, end)
}
