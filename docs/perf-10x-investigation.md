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
roughly an order of magnitude, which means giving up one object per CST node —
and a lossless object CST is the project's core premise ("CST is the source of
truth"). A flat arena or a pulldown-cmark-style event stream would get there,
but it is a rewrite of the data model, not an optimization of this one.

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
| 1b | Make the *output* incremental too: patch the previous mdast / re-render only changed blocks | up to ~8x again | Medium |
| 2 | Ship wasm-gc instead of js for the playground bundle | 1.3x | Low |
| 3 | Cut allocations: presize the arrays behind `Array::push`, avoid rebuilding container subtrees in the extension passes | 1.3–2x, capped at 2.4x | Medium |
| 4 | Flat arena / event-stream CST | 10x | Rewrite; conflicts with the lossless-CST premise |

Item 1 is done; 1b is where the next real win is. Item 2 is still worth doing.
Item 3 is ordinary tuning with a known ceiling.
Item 4 should only be considered as a separate, explicitly-scoped project.

## Notes

- `recognize_attributes` and `recognize_alerts` rebuild container subtrees, but
  both are already gated on `source.contains(...)` in
  `BlockParser::parse_document`, so they only cost on documents that can
  actually contain their markers. The profile corpus contains `{` (from
  `function hello() {`), which is why `recognize_attributes` shows up at 2.0%
  there — it would be absent on plain prose.
- `parse: fenced code` is the fastest corpus because fenced content skips inline
  parsing entirely; it is the closest thing here to a raw-scan floor.
