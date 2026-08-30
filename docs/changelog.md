# Changelog

## Unreleased

### Performance

- Build JavaScript and Wasm GC AST objects directly instead of materializing an intermediate `Json` tree; the Wasm path uses JS String Builtins and `externref` imports without a JSON round trip.
- Split table cells as zero-copy `StringView`s and materialize only cells containing escaped pipes.
- Add a four-anchor SIMD scanner for bare-autolink candidates on native and linear-memory Wasm targets.
- Pass output-size hints to HTML renderer buffers and keep hot bare-autolink matches as `#valtype` values.
- Add a reproducible native `moon run --profile` harness for isolated parse, render, and combined 1 MiB workloads.
- Use a size-gated, copy-inclusive Wasm SIMD scanner imported as an external `.wasm` module through WebAssembly ESM Integration for long ASCII inline-text runs on the JavaScript target, with exact UTF-16 fallback for Unicode input.
- Bypass `InlineCtx` allocation for marker-free text, reject non-definition multiline paragraphs before splitting, and materialize deferred top-level inline nodes directly into their CST child arrays.
- Extend the 1 MiB profiling harness to the JavaScript target through Node's V8 CPU profiler.

## 0.8.1 - 2026-08-30

### Breaking changes

- Remove the experimental `mizchi/markdown/x/folddown` package and its JavaScript APIs, playground viewer, drift-review workflow, and sample documents.

### Performance

- Add SIMD CR/LF scanning for linear-memory targets.
- Use MoonBit's optimized `StringView::find` path for long HTML block and inline terminators.
- Add focused scanner and HTML parsing benchmarks under `just bench-simd`.

### Compatibility

- Add an exact official GFM HTML gate for all 24 extension examples on JavaScript and Wasm.
- Implement GFM tagfilter, pipe-less table continuation rows, and extended autolinks.
- Define Markdown serialization as a normalized, idempotent format and emit reference definitions in a canonical trailing section.
- Preserve full, collapsed, and shortcut reference-link styles in the CST and JSON AST.
- Add semantic GitHub alert blocks and rendered footnotes with stable reference/back-reference IDs.
- Add display-math blocks with an injectable MoonBit HTML renderer boundary and an escaped default fallback.
- Add container/text directives, definition lists, and standalone block attributes to the CST, renderer, serializer, and JSON AST.

### CLI

- Add the native `mmmd` command under `src/cmd/mmmd-native`.
- Use normalized Markdown as native TUI output; Mermaid remains fenced when the JavaScript/Wasm renderer is unavailable.

### Maintenance

- Split stateless search primitives from the stateful scanner.
- Replace numeric HTML block kinds with a closed enum.
- Generate CommonMark/GFM test package manifests in the current `moon.pkg` format.
- Correct recursively reused nested-list item and child-block spans after incremental edits.
- Match remark's GFM table layout, escaped pipes, and literal strikethrough safety while retaining official-GFM overflow-cell semantics.

---

## 2025-12-19: Unicode (non-BMP) support for Scanner

**Commits:** `a616f73`, `8d99c3a`

### Problem

Scanner used code point indices internally (`to_array()`) but `substring()` used UTF-16 indices (`unsafe_substring()`). This caused garbled output for non-BMP characters (emoji, rare CJK).

### Changes

- Add `utf16_offsets : Array[Int]?` field to Scanner for code point → UTF-16 index mapping
- `substring()`, `remaining()`, `read_line()` now correctly convert indices
- Fast detection: `source.length() != chars.length()` (O(1) instead of O(n) loop)
- Skip offset array creation when all characters are BMP

### Performance Impact

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| parse: small | 23.86µs | 24.25µs | **+1.6%** |
| parse: medium | 97.52µs | 100.24µs | **+2.8%** |
| parse: large | 481.37µs | 503.22µs | **+4.5%** |
| scanner: read_line 100x | 5.13µs | 6.40µs | +25% |

### Compatibility

| Character Type | Status |
|----------------|--------|
| ASCII | ✅ No change |
| BMP (Japanese, Chinese, Korean) | ✅ +2-5% overhead |
| Non-BMP (emoji) | ✅ Now works correctly |

### Tests

Added `src/unicode_test.mbt` with 64 comprehensive tests for CJK and emoji handling.

---

## 2025-12-17: Nested link detection

**Commit:** `24739bc`

### Changes

- Add `contains_link()` helper to detect links in inline content
- Invalidate outer link when link text contains another link (CommonMark spec)
- Recursive check includes links inside emphasis/strong/strikethrough

### CommonMark Compliance

- Tests: 202/542 (unchanged - remark uses different escaping)

### Performance Impact

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| parse: small | 107.29µs | 118.70µs | +10.6% |
| parse: medium | 382.11µs | 424.93µs | +11.2% |
| serialize: small | 7.42µs | 5.39µs | **-27%** |
| serialize: medium | 27.11µs | 21.99µs | **-19%** |

### Notes

Parse overhead from `contains_link()` check, but serialize improved. Net roundtrip performance is similar. Test count unchanged because remark escapes `[` and `(` in "link-like but not link" patterns, which we don't do.

---

## 2025-12-17: Link parser improvements

**Commit:** `ce97f69e295aad84ae8bd902a7f4bfe84a634787`

### Changes

- Add support for `(title)` style link titles (in addition to `"..."` and `'...'`)
- Allow newlines between URL and title
- Reject links with newlines in URL (both angle-bracket and bare URLs)

### CommonMark Compliance

- Tests: 201 → 202 (+1)

### Performance Impact

| Benchmark | Before | After | Change |
|-----------|--------|-------|--------|
| parse: small | 90.70µs | 107.29µs | +18% |
| parse: medium | 361.54µs | 382.11µs | +5.7% |
| serialize: small | 5.06µs | 7.42µs | +46% |
| serialize: medium | 19.70µs | 27.11µs | +38% |
| inline: links | 4.28µs | 3.99µs | **-6.8%** |

### Notes

The performance regression is primarily due to:
1. Additional newline checks in URL parsing
2. Parenthesis-style title parsing with depth tracking
3. Extended whitespace skipping (now includes newlines)

The link-specific benchmark actually improved (-6.8%), suggesting the overhead is in the general parsing path rather than link parsing itself. Accepted as reasonable tradeoff for improved CommonMark compliance.
