# Would a flat binary representation (and SIMD) go faster?

The question: keep the internal structure as a flat binary struct, treat mdast
as one output projection of it, and use SIMD where it fits. Measured
2026-09-17 on this machine, JS / wasm-gc / native, with the benchmarks quoted
next to each number.

**Short answer: the architecture is right and the direction is real, but the
measured ceiling is about 2.4x, not 10x — and three independent methods agree
on that number. The part of the idea that pays for itself immediately is the
cheap part: stop materialising strings the parser only reads. That is now
done and is worth 1.08–1.21x across every corpus and backend, for free.**

## First, a correction

`perf-10x-investigation.md` previously said a flat arena CST "conflicts with
the lossless-CST premise". That was wrong. Losslessness is a property of the
*information* kept — trivia, markers, exact spans — not of how it is stored. A
span-based flat representation keeps strictly more of the source than the
current one does, because today a `Text` node holds a *copy* of its text while
a flat node would hold the offsets it came from. The framing in the question —
a proper internal structure with mdast as its output form — is sound, and the
codebase already draws that boundary in `block_to_js` / `inline_to_js`.

So the objection is not architectural. It is arithmetic.

## What a parse actually costs

### The tree the parser builds

Walking the CST after a parse (`zz_census`, since removed):

| Corpus | Size | Blocks | Inlines | Arrays | Strings | Objects / 1000 chars | Throughput |
|---|---|---|---|---|---|---|---|
| large (100 sections) | 34.5 KB | 1403 | 801 | 1102 | 901 | **131** | 15.1 MB/s |
| 32 long prose lines | 75.8 KB | 64 | 32 | 33 | 32 | 2.1 | 37.0 MB/s |
| fenced code | 67.6 KB | 1 | 0 | 1 | 2 | 0.06 | 71.0 MB/s |

Throughput tracks object count per byte, not byte count. That is the whole
thesis of the question, confirmed.

Two things the census settles that guesswork would have got wrong:

- **`Trivia` is free.** Every block carries `leading_trivia` and
  `trailing_trivia`, and `Trivia::new` is never called anywhere in `src/` —
  they are always empty. That looks like 2 wasted allocations per block, but
  `moonc` constant-folds `Trivia::empty()` into one module-level singleton
  (visible in the generated `api.js`), so the real cost is zero. Removing the
  fields would buy nothing.
- **Strings are 90% of the source, copied back out.** 901 strings totalling
  31,110 chars for a 34,462-char document. A span-based node copies none.

### Where the time goes, by phase

Splitting `parse_document` and benching each prefix (`zz_phase_bench`, since
removed), large document, JS:

| Phase | Time | Share |
|---|---|---|
| 1. line loop + intermediate `Node` tree | 1.13 ms | **49.6%** |
| 2. + `Block` materialisation | +0.53 ms | 23.2% |
| 3. + inline parse and `Inline` materialisation | +0.62 ms | 27.2% |
| total | 2.28 ms | 100% |

**Half the parse is over before a single CST node exists.** That is the number
that decides the question: a flat *output* CST can only address phases 2 and 3.

## What a flat representation is worth

Building 3000 paragraphs (6000 nodes) as today's objects, versus the same
information as `Int` columns, versus one interleaved row array:

| Shape | js | wasm-gc | native |
|---|---|---|---|
| object CST (Block + Array + Inline + substring) | 259.9 µs | 358.9 µs | 368.1 µs |
| flat columns, buffers reused | 31.9 µs (**8.2x**) | 27.1 µs (**13.3x**) | 21.7 µs (**16.9x**) |
| flat columns, buffers allocated each time | 106.1 µs (2.4x) | 51.5 µs (7.0x) | 32.8 µs (11.2x) |
| one interleaved array, stride 5 | 18.4 µs (**14.1x**) | 16.2 µs (**22.2x**) | 11.9 µs (**30.8x**) |
| walking it afterwards | 20.7 → 14.8 µs (1.4x) | 17.2 → 6.9 µs (2.5x) | 10.8 → 4.4 µs (2.4x) |

And strings versus spans, 901 slices of 34 chars:

| | js | native |
|---|---|---|
| 901 substrings | 34.2 µs | 104.4 µs |
| 901 `(from, to)` pairs | 2.5 µs (**13.8x**) | 1.4 µs (**74x**) |

So the shape itself is 8–31x cheaper to build, and most so on the linear-memory
backends — exactly as the flat-array argument predicts.

## Why that does not become 10x

Apply the measured 8x to the phases it can reach, on the large document:

| | today | flat |
|---|---|---|
| phase 1 (lines + `Node` tree) | 1.13 ms | ~0.52 ms — only if the *intermediate* tree goes flat too |
| phase 2 (`Block` objects) | 0.53 ms | ~0.07 ms |
| phase 3 (inline parse + objects) | 0.62 ms | ~0.35 ms — the scanning half does not get cheaper |
| **total** | **2.28 ms** | **~0.94 ms = 2.4x** |

Three independent methods now agree:

1. **GC share.** The CPU profile puts the collector at 41.3% self time. Amdahl:
   `1 / 0.413` = 2.4x.
2. **Cross-corpus fit.** Regressing time per 1000 chars against objects per
   1000 chars over the three corpora gives ~311 ns per object and a 25.7 µs
   scan floor — 61% structure, 39% scan on the large document.
3. **Phase split × micro-benchmark**, the table above. 2.4x.

Converging from three directions on the same number is about as good as this
kind of estimate gets. **The flat rewrite is a ~2.4x project on the JS backend**
(more on native, where the object path is worst and the flat path is best), and
it touches the block parser, the inline parser, the serializer, the renderers
and the FFI layer. It is a rewrite, not an optimisation.

## SIMD

SIMD is already in, and the profile says it is done:

- `find_line_end` uses `@v128` eight UTF-16 units at a time on native and wasm,
  with a scalar path below 16 chars because vector setup costs more than a
  short Markdown line.
- `StringView::find` uses core's SIMD scanner on linear-memory targets.
- The JS backend calls a hand-written Wasm SIMD kernel
  (`src/inline_marker_simd.wat`) through `findInlineMarkerUtf8`.

The remaining headroom is small, and the phase table says why: the pure byte
scan is the 14.0 µs/1000-chars floor set by the fenced-code corpus, i.e. 21% of
the large document. Making *all* scanning free would be 1.27x, and it cannot be
free.

There is one genuine synergy worth recording, though. On JS the kernel has to
`encodeInto` UTF-8 for every call and bails out (`-2`) when the text is not
ASCII, which is why it only pays on long spans. **If the internal
representation were a flat UTF-8 buffer, the SIMD kernel would become directly
callable with no per-call encode.** SIMD does not justify the rewrite, but the
rewrite would make SIMD worth more than it is today.

## What was actually shipped instead

The evaluation found one item that is the same idea at 2% of the cost: the
parser materialised a fresh `String` (and a tuple) for **every line**, then
scanned it again for NUL, before any node existed. 1708 allocations per parse
of the large document, and the whole source copied out line by line.

`read_line` now only moves a cursor — `line_start` / `line_len` / `line_end` —
and characters are read as `source[line_start + i]` through `line_char`. NUL
sanitisation moved to `BlockParser::new`, where it runs once for the whole
source; U+0000 and U+FFFD are both one UTF-16 code unit, so every offset stays
where it was. Lines that genuinely need a string (HTML blocks, frontmatter)
still get one, behind the guard that already gates them.

A/B on the same machine, same session:

| Corpus | js before | js after | | native before | native after | |
|---|---|---|---|---|---|---|
| small (5 sections) | 101.86 µs | 94.43 µs | 1.08x | 93.70 µs | 85.12 µs | 1.10x |
| medium (20 sections) | 439.85 µs | 393.82 µs | 1.12x | 365.73 µs | 327.24 µs | 1.12x |
| large (100 sections) | 2.41 ms | 2.15 ms | **1.12x** | 1.81 ms | 1.65 ms | 1.10x |
| 32 long prose lines | 1.98 ms | 1.80 ms | 1.10x | 889.08 µs | 773.37 µs | **1.15x** |
| fenced code | 923.37 µs | 762.06 µs | **1.21x** | 525.93 µs | 468.99 µs | 1.12x |

No change to the data model, no change to any public type, all 1469 MoonBit
tests green.

## Recommendation

**Don't do the rewrite — at least not for the playground.** Not because it
would not work, but because of where the remaining time is:

- A full parse now happens **once**, at load. Every keystroke after it goes
  through `parse_incremental`, which is ~45x faster, and since the incremental
  output work the mdast is only rebuilt for the blocks that changed
  (33.9x when appending — see `perf-10x-investigation.md`).
- On a 77 KB document that is 10.4 ms once, then 0.3 ms per edit. A 2.4x
  rewrite turns the 10.4 ms into 4.3 ms and leaves the 0.3 ms alone.

Ranked by value per unit of risk:

| # | Change | Expected | Risk |
|---|---|---|---|
| ~~1~~ | Stop materialising a string per line — **done, this commit** | 1.08–1.21x, every corpus and backend | Low |
| 2 | Ship wasm-gc instead of js for the playground bundle | 1.3x | Low |
| 3 | Hold `Text` / code content as spans, materialise at the output boundary | up to 13.8x on that slice; a few % of a parse | Medium — touches the serializer and both renderers |
| 4 | Presize the arrays behind `Array::push`; stop rebuilding container subtrees in the extension passes | 1.3–2x, capped at 2.4x | Medium |
| 5 | Flat binary CST end to end, mdast as a projection | **2.4x** (more on native) | Rewrite — worth scoping as its own project, on its own merits (memory, native, SIMD reach), not as a playground optimisation |

Item 3 is the honest middle path if the flat direction is wanted without the
rewrite: it is the same principle — hold offsets internally, materialise only
at the boundary — applied to the one remaining place where the parser copies
the source for no reason.
