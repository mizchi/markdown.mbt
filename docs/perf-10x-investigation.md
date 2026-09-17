# Is a 10x parser speedup reachable?

Measured 2026-09-15 on the JS backend (`preferred_target = "js"`), commit
`ffe7dc0`. Every number below is reproducible with the commands quoted next to
it.

**Short answer: not on the full-parse path — the Amdahl ceiling there is about
2.4x. The win is in not re-parsing at all: `parse_incremental` is 16–33x faster
than a full re-parse, but nothing outside MoonBit could reach it. That is now
wired up, and the playground gets 6.7–9.1x per edit; see
[What it actually buys](#what-it-actually-buys-and-what-the-new-ceiling-is) for
why it is not the full 16–33x.**

## Where the time goes today

### Throughput by corpus

`moon bench -p mizchi/markdown -f bench.mbt -i 0-4`

| Corpus | Size | Parse | Throughput |
|---|---|---|---|
| large (100 sections) | 33.7 KB / 1708 lines | 2.29 ms | 15.1 MB/s |
| 32 long prose lines | 74.1 KB / 65 lines | 2.00 ms | 37.0 MB/s |
| fenced code, 32 long lines | 66.0 KB / 35 lines | 0.95 ms | 71.0 MB/s |

Structure costs roughly 5x more per byte than raw bytes do. The parser is not
scanner-bound; it is bound by what it builds.

### Backends

Same corpora, `moon bench --target <t> -f bench.mbt -i 0-4`:

| Corpus | js | wasm-gc | wasm | native |
|---|---|---|---|---|
| large (100 sections) | 2.29 ms | 1.73 ms (1.32x) | 4.14 ms (0.55x) | 1.82 ms (1.26x) |
| 32 long prose lines | 2.00 ms | 1.97 ms (1.02x) | 1.79 ms (1.12x) | 0.87 ms (2.29x) |

Native is 2.29x on prose but only 1.26x on the structure-heavy document. A
completely different runtime barely helps the case we care about, which points
at allocation rather than code quality.

### CPU profile

`just profile-js parse 50` — 1.07 MB corpus, 50 iterations, 12.45 s sampled:

| Self | Frame |
|---|---|
| **41.3%** | **(garbage collector)** |
| 6.5% | `Array::push` |
| 5.7% | `BlockParser::parse_document` |
| 4.5% | `BlockParser::to_block` |
| 2.9% | `parse_inlines_with_defs_into` |
| 2.7% | `BlockParser::finalize_lists` |
| 2.4% | `BlockParser::add_text` |
| 2.1% | `BlockParser::open_new_blocks` |
| 1.9% | `NodeKind::equal` |
| 1.9% | `InlineCtx::scan` |

Nothing below the top two is worth attacking on its own — the tail is flat, no
frame past `Array::push` reaches 6%.

## Why 10x is not reachable on full parse

GC alone is 41.3% of the run. Even if every remaining line of parsing became
instantaneous, the result is `1 / 0.413` ≈ **2.4x**. Add `Array::push` (6.5%)
and the allocation-side share is close to half the total.

So 10x is not a tuning problem. It requires cutting *allocation volume* by
roughly an order of magnitude, which means giving up one object per CST node.
A flat arena or a pulldown-cmark-style event stream is a rewrite of the data
model, not an optimization of this one — and, measured, it lands on the same
2.4x rather than 10x. See
[Would a flat binary representation (and SIMD) go faster?](./flat-representation-evaluation.md).

For calibration, 15 MB/s on a kitchen-sink document already puts this parser
level with good native implementations and well ahead of JS ones; 150 MB/s on
the same corpus would be at or past the state of the art for any parser that
preserves trivia.

## Where 10x already exists: stop re-parsing

`moon bench -f bench_incremental.mbt`:

| Document | Full parse | Incremental (edit middle) | Speedup |
|---|---|---|---|
| 10 paragraphs | 62.6 µs | 8.2 µs | 7.6x |
| 50 paragraphs | 308.1 µs | 11.4 µs | 27.0x |
| 100 paragraphs | 642.0 µs | 19.7 µs | **32.6x** |

Confirmed in the browser against the real `js/api.js` (Chromium, kitchen-sink
sections):

| Document | Full `parse()` | Incremental `update()` | Speedup |
|---|---|---|---|
| 340 lines / 4.5 KB | 1.28 ms | 0.057 ms | 22.6x |
| 1700 lines / 22.3 KB | 2.92 ms | 0.18 ms | 16.2x |
| 6800 lines / 89.1 KB | 15.2 ms | 0.92 ms | 16.5x |

That is the 10x, and it is already implemented in `parse_incremental`.

### What blocked it — now fixed

1. **The playground never called it.** `playground/main.tsx` `handleChange` ran
   `setAst(parse(newSource))` — a full parse per edit, debounced 100 ms.
2. **The JS handle API could not serve an AST incrementally.**
   `createDocument(...).ast` was a getter that fell back to a full
   `parse(source)`, so it was *slower* than calling `parse()` directly:
   30.7 ms vs 15.2 ms on the 89 KB document. Incremental only paid off through
   `toHtml()` / `toMarkdown()`.
3. **Chained edits fell back.** The handle returned by `update()` defined
   `update: (s, e) => createDocument(s, options).update(s, e)` (marked
   "Simplified" in `js/api.js`), so the second and later edits re-parsed from
   scratch.

All three are addressed: `md_ast_object(handle)` materialises the mdast from a
document that is already parsed, `documentFromHandle` gives every revision a
real incremental `update()`, and `diffEdit(oldSource, newSource)` derives the
edit for callers who only have the two texts. The playground keeps one document
alive and advances it.

### What it actually buys, and what the new ceiling is

Measured in Chromium against `js/api.js`, interleaved to cancel drift:

| Document | Before (full parse → mdast) | After (incremental → mdast) | Speedup |
|---|---|---|---|
| 241 lines / 3.8 KB | 0.437 ms | 0.048 ms | 9.1x |
| 1201 lines / 19.1 KB | 1.638 ms | 0.230 ms | 7.1x |
| 4801 lines / 76.6 KB | 6.402 ms | 0.955 ms | 6.7x |

Less than the 16–33x the parse benchmark suggests, and the breakdown says why
(76.6 KB, Node):

| Step | Time | vs full parse |
|---|---|---|
| full parse → mdast | 10.91 ms | 1.0x |
| `update()` only | 0.24 ms | 44.8x |
| `update()` + `.ast` | 1.34 ms | 8.1x |
| `update()` + `.toHtml()` | 1.51 ms | 7.2x |

The incremental parse itself is ~45x, but handing a JS consumer a full mdast
tree costs 1.10 ms regardless of how small the edit was, and rendering the whole
document to HTML costs 1.27 ms. **Output materialisation, not parsing, is now
the bottleneck.** Going past ~8x means making the output incremental too —
patching the previous mdast for the blocks that changed, or re-rendering only
those blocks — which the CST's block spans already carry enough information
to do.

## Making the output incremental too (item 1b)

`md_ast_incremental_patch(handle)` reports how the incremental parse split the
document — how many leading and trailing mdast children survived the edit
untouched — and materialises only what is between them. The JS side splices the
previous revision's array, so nodes the edit did not reach are the *same objects*
as before, not copies.

Which nodes are offered for reuse is decided in MoonBit, on purpose. Spans are
moved by `shift_block_span`, which shifts block spans but leaves inline spans
alone (they are block-relative) and leaves table rows and cells alone too. A
consumer that adjusted offsets itself would have to mirror those rules and keep
mirroring them as block types are added, so a shifted tail is never offered:
reuse is only offered when the nodes are byte-identical (`delta == 0`), and
otherwise the tail is rebuilt where the span rules live.

That makes the win depend on *where* you edit, which is the point — appending is
what writing actually looks like:

| Document | full → mdast | `update()` + `.ast` | Speedup | Edit position |
|---|---|---|---|---|
| 4 KB | 0.723 ms | 0.067 ms | 10.8x | middle |
| 4 KB | 0.464 ms | 0.024 ms | **19.7x** | end |
| 19 KB | 2.262 ms | 0.296 ms | 7.6x | middle |
| 19 KB | 2.351 ms | 0.081 ms | **29.0x** | end |
| 77 KB | 10.110 ms | 1.355 ms | 7.5x | middle |
| 77 KB | 10.445 ms | 0.308 ms | **33.9x** | end |

Before this, every edit cost the same 8.1x regardless of position.

## Correctness found along the way

Wiring the playground to `parse_incremental` turned three latent bugs in it into
visible ones. All three are fixed, each with a regression test in
`js/api.test.js`:

1. **An edit at a block's first character did not count as touching that block.**
   The overlap test was exclusive, and an insertion has `start == end`, so
   typing `> ` or `- ` at the start of a paragraph re-parsed only the gap before
   it. The playground rendered an *empty* blockquote followed by the untouched
   paragraph.
2. **Edits in trivia were attributed to the wrong block.** `get_span()` covers
   the block proper, so a fenced block's closing fence and the blank lines after
   any block fall outside it. Blocks are now matched on their extent — up to
   where the next block carrying content starts — so every offset belongs to
   exactly one block.
3. **An edit could change how the text after it parses.** Breaking a closing
   fence makes the rest of the document part of the code block, but the re-parse
   stopped at the old block boundary and the rest was reused. The region is now
   re-parsed with the following block appended: if nothing still starts at the
   old boundary, the edit leaked and the parse falls back to a full one.

A fuzzer (25 random edits × 12 seeds, every revision's AST compared against a
full parse of the same text) went from 287 mismatches in 300 to 50.

**The remaining 50 are a known gap.** They all involve documents that already
contain an unterminated fence, where an edit re-arranges the fence markers
themselves; one block of lookahead is not enough to see that the damage extends
further. Closing it properly means either re-parsing to the end of the document
(sound, but it gives up the reuse that makes `update()` fast mid-document) or
tracking when the re-parse re-syncs with the old block structure, which needs
parser state the current `parse()` does not expose. That is a design decision,
not a patch.

## FFI layer: not the problem

Same 77 KB document, in-browser:

| Operation | Time | Throughput |
|---|---|---|
| `md_parse_with_source` (CST handle only) | 9.01 ms | 8.7 MB/s |
| `api.parse` (+ JS mdast objects) | 10.16 ms | 7.8 MB/s |
| `md_to_html` (parse + render) | 15.49 ms | 5.1 MB/s |
| `md_to_ast_json` (JSON string) | 57.86 ms | 1.4 MB/s |

Materialising the JS mdast tree costs only +12% over the bare CST parse, so the
object bridge is fine. `md_to_ast_json` is **6.4x slower** than
`md_to_ast_object` for the same information — callers should not be using the
JSON API on a hot path.

## Recommended order of work

| # | Change | Expected | Risk |
|---|---|---|---|
| ~~1~~ | Make incremental parsing reachable for AST consumers, then use it in the playground — **done** | 6.7–9.1x measured | Low — the engine already existed |
| ~~1b~~ | Make the *output* incremental too: carry over the mdast nodes the edit did not touch — **done** | 7.5x mid-document, **33.9x** appending | Medium |
| 2 | Ship wasm-gc instead of js for the playground bundle | 1.3x | Low |
| 3 | Cut allocations: presize the arrays behind `Array::push`, avoid rebuilding container subtrees in the extension passes | 1.3–2x, capped at 2.4x | Medium |
| ~~4~~ | Stop materialising a `String` per line in the block parser — **done** | 1.08–1.21x, every corpus and backend | Low |
| 5 | Flat binary CST end to end, mdast as a projection | 2.4x, not 10x ([evaluation](./flat-representation-evaluation.md)) | Rewrite |

Items 1, 1b and 4 are done. Item 2 is still worth doing. Item 3 is ordinary
tuning with a known ceiling. Item 5 is a rewrite whose measured ceiling is the
same 2.4x that GC share predicts, so it should be scoped on its own merits
(memory, native throughput, SIMD reach) rather than as a playground
optimization.

## Notes

- `recognize_attributes` and `recognize_alerts` rebuild container subtrees, but
  both are already gated on `source.contains(...)` in
  `BlockParser::parse_document`, so they only cost on documents that can
  actually contain their markers. The profile corpus contains `{` (from
  `function hello() {`), which is why `recognize_attributes` shows up at 2.0%
  there — it would be absent on plain prose.
- `parse: fenced code` is the fastest corpus because fenced content skips inline
  parsing entirely; it is the closest thing here to a raw-scan floor.
