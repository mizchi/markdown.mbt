# TODO

- [x] 複数行の WebComponents customElements 要素がパースできてない

## Current Status

- **Main tests**: 125/125 passing (100%)
- **CommonMark tests (strict=true)**: 205/205 passing (100%)
- **GFM tests**: 26/26 passing (100%)
- **Skipped tests**: 337 (complex edge cases)
- **Serializer**: Normalized to remark-gfm output style

## Strict Mode

New `strict` option for full CommonMark compliance:

```moonbit
// Fast mode (default) - optimized for common cases
let doc = parse(source)

// Strict mode - full CommonMark compliance with delimiter stack
let doc = parse(source, strict=true)
```

### Performance (strict=false vs baseline)
| Benchmark | Change |
|-----------|--------|
| parse: small | +5.9% |
| parse: medium | +4.1% |
| parse: large | +5.7% |

## High Priority

### Serializer Fixes

- [x] **Title quote normalization**: `'title'` and `(title)` → `"title"` (all quotes normalized to double quotes)
- [ ] **URL escape normalization**: Remove unnecessary escapes like `\:` (example 500)

### Parser Improvements

- [x] **Delimiter stack algorithm**: Implemented for strict mode
- [x] **Emphasis flanking rules**: Full CommonMark compliance in strict mode
- [x] **Hard line breaks**: Fixed in parse_segment_simple
- [x] **Link/Image parsing in strict mode**: Added to parse_segment_simple
- [x] **HTML block parsing**: Block-level HTML tags preserved as HtmlBlock
- [ ] **Nested lists**: Complex list nesting not handled correctly
- [ ] **Reference link resolution**: Parsed but not fully resolved

### Skipped Test Categories (337 total)

| Category | Count | Notes |
|----------|-------|-------|
| Emphasis edge cases | 90 | Many pass with strict=true |
| Reference links | 54 | Not fully implemented |
| List items | 35 | Complex nesting |
| URL edge cases | 22 | Spaces, newlines, escape normalization |
| Lists | 21 | Edge cases |
| Setext headings | 20 | Not implemented |
| Images | 17 | Edge cases |
| Code spans | 13 | Edge cases |
| Block quotes | 13 | Nested quotes |
| Other | 52 | Various edge cases |

## Medium Priority

### Performance

- [ ] Serializer performance regressed ~15-17% due to `calc_fence_length` - consider caching or lazy evaluation
- [ ] Large table parsing shows high variance - investigate potential optimization

### Features

- [ ] **Link reference definitions**: Currently parsed but not fully utilized in serialization
- [x] **Footnotes** (GFM extension): Implemented (FootnoteDefinition block, FootnoteReference inline)
- [x] **Task lists**: Fully working (2/2 GFM tests pass)
- [x] **HTML renderer**: `md_to_html()` and `render_html()` functions

## Low Priority

### Code Quality

- [ ] Extract common patterns in block_parser.mbt
- [ ] Consider splitting large files (block_parser.mbt is quite large)
- [ ] Clean up deprecated `substring` calls

### Benchmarks

- [ ] **rami3l/cmark comparison benchmarks**: Restore when cmark is updated for current MoonBit version (removed due to UInt16/Int incompatibility)

### Future Enhancements

- [ ] **Incremental inline parsing**: Currently only block-level incremental parsing
- [ ] **Source maps**: Track original positions through transformations
- [ ] **Custom syntax extensions**: Plugin system for custom block/inline types
- [ ] **Streaming parser**: For very large documents
- [ ] **SVG popup preview**: Show floating preview when editing SVG code blocks (use data-span for targeted updates)
- [ ] **Moonlight SVG editor integration**: Integrate [mizchi/moonlight](https://github.com/mizchi/moonlight) for bidirectional SVG editing
  - Lazy load via WebComponents (`<moonlight-editor>`)
  - Code block handler for `moonlight-svg` language
  - Bidirectional sync: editor ↔ source via `data-span`
  - See `docs/moonlight_integrate.md` for details

## Notes

- The serializer now outputs GFM-normalized markdown (matching remark-gfm behavior)
- CST preservation is partially sacrificed for compatibility (trivia, markers normalized)
- Incremental parsing still works correctly for block-level changes
- Strict mode uses delimiter stack algorithm for full CommonMark emphasis handling
