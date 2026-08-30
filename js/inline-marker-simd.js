import {
  find_inline_marker,
  memory,
} from "./inline_marker_simd.wasm";

const encoder = new TextEncoder();
let memoryBytes = new Uint8Array(memory.buffer);

/**
 * Find an inline Markdown marker in a UTF-16 string via a UTF-8 SIMD kernel.
 * Returns -1 when absent and -2 when the caller must use its UTF-16 fallback.
 */
export function findInlineMarkerUtf8(text, start, end) {
  const input = text.slice(start, end);
  const required = input.length * 3;
  if (required > memoryBytes.length) {
    memory.grow(Math.ceil((required - memoryBytes.length) / 65536));
    memoryBytes = new Uint8Array(memory.buffer);
  }

  const encoded = encoder.encodeInto(input, memoryBytes);
  if (encoded.read !== input.length) return -2;
  const found = find_inline_marker(0, encoded.written);
  return found >= 0 ? start + found : found;
}

globalThis.__mizchiMarkdownInlineMarkerSimd = { findInlineMarkerUtf8 };
