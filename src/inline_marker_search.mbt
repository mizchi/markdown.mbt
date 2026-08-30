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

///| Scan UTF-8 bytes in an embedded Wasm SIMD module.

///|
/// The module returns -2 if a non-ASCII byte precedes a marker. The caller
/// then uses the UTF-16 scalar scanner, preserving MoonBit String offsets.
#cfg(target="js")
extern "js" fn find_inline_marker_wasm_utf8(
  text : String,
  start : Int,
  end : Int,
) -> Int =
  #| ((bytes) => {
  #| let instance;
  #| let encoder;
  #| try {
  #| instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
  #| encoder = new TextEncoder();
  #| } catch {
  #| return () => -2;
  #| }
  #| const { memory, find_inline_marker } = instance.exports;
  #| let view = new Uint8Array(memory.buffer);
  #| return (text, start, end) => {
  #| const input = text.slice(start, end);
  #| const required = input.length * 3;
  #| if (required > view.length) {
  #| memory.grow(Math.ceil((required - view.length) / 65536));
  #| view = new Uint8Array(memory.buffer);
  #| }
  #| const encoded = encoder.encodeInto(input, view);
  #| if (encoded.read !== input.length) return -2;
  #| const found = find_inline_marker(0, encoded.written);
  #| return found >= 0 ? start + found : found;
  #| };
  #| })(new Uint8Array([
  #| // BEGIN GENERATED INLINE MARKER WASM BYTES
  #| 0,97,115,109,1,0,0,0,1,12,2,96,1,127,1,127,
  #| 96,2,127,127,1,127,3,3,2,0,1,5,3,1,0,1,
  #| 7,31,2,6,109,101,109,111,114,121,2,0,18,102,105,110,
  #| 100,95,105,110,108,105,110,101,95,109,97,114,107,101,114,0,
  #| 1,10,200,2,2,79,0,32,0,65,10,70,32,0,65,33,
  #| 70,114,32,0,65,38,70,114,32,0,65,42,70,114,32,0,
  #| 65,58,70,114,32,0,65,60,70,114,32,0,65,219,0,70,
  #| 114,32,0,65,220,0,70,114,32,0,65,221,0,70,114,32,
  #| 0,65,223,0,70,114,32,0,65,224,0,70,114,32,0,65,
  #| 254,0,70,114,11,245,1,3,2,127,5,123,3,127,32,1,
  #| 65,112,113,33,3,2,64,3,64,32,2,32,3,79,13,1,
  #| 32,0,32,2,106,253,0,4,0,34,4,253,12,15,15,15,
  #| 15,15,15,15,15,15,15,15,15,15,15,15,15,253,78,33,
  #| 5,32,4,65,4,253,109,33,6,253,12,64,4,0,0,0,
  #| 0,4,0,0,0,13,32,40,32,128,32,32,5,253,14,33,
  #| 7,253,12,1,2,4,8,16,32,64,128,0,0,0,0,0,
  #| 0,0,0,32,6,253,14,33,8,32,7,32,8,253,78,253,
  #| 12,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  #| 0,253,36,253,100,32,4,253,100,114,34,9,4,64,32,2,
  #| 32,9,104,106,34,10,32,0,106,45,0,0,65,128,1,79,
  #| 4,64,65,126,15,11,32,10,15,11,32,2,65,16,106,33,
  #| 2,12,0,11,11,2,64,3,64,32,2,32,1,79,13,1,
  #| 32,0,32,2,106,45,0,0,34,11,65,128,1,79,4,64,
  #| 65,126,15,11,32,11,16,0,4,64,32,2,15,11,32,2,
  #| 65,1,106,33,2,12,0,11,11,65,127,11,
  #| // END GENERATED INLINE MARKER WASM BYTES
  #| ]))

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
