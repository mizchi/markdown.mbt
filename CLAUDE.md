# MoonBit Markdown Parser

CST-based incremental Markdown parser implemented in MoonBit.

## Project Structure

```
src/
├── types.mbt                       # CST type definitions (Span, Block, Inline)
├── scanner.mbt                     # O(1) character access (Array[Char])
├── unicode.mbt                     # Shared Unicode classification helpers
├── block_parser.mbt                # Block parser dispatcher / paragraph / definitions
├── block_parser_list.mbt           # Bullet & ordered list parsing
├── block_parser_table.mbt          # GFM table parsing
├── block_parser_html.mbt           # HTML block parsing
├── block_parser_frontmatter.mbt    # YAML frontmatter parsing
├── inline_parser.mbt               # Inline parser (single-pass)
├── inline_parser_link.mbt          # Links, images, wikilinks, footnote refs
├── inline_parser_strict.mbt        # CommonMark delimiter-stack emphasis
├── incremental.mbt                 # Incremental parsing (EditInfo)
├── serializer.mbt                  # Lossless serializer + md_parse_and_render
├── renderer.mbt                    # HTML renderer + md_to_html
├── plugin.mbt                      # CodeBlockInfo + RenderOptions + parse_code_block_info
├── api/                            # FFI exports for JS/WASM consumers
├── experimental/
│   ├── crdt/                       # CRDT experimental code (isolated)
│   └── multipass/                  # Experimental multi-pass inline parser
├── bench.mbt                       # Document parse/serialize/roundtrip benches
├── bench_inline.mbt                # Inline parser benches
├── bench_table.mbt                 # GFM table benches
├── bench_scanner.mbt               # Scanner / block-only benches
└── bench_incremental.mbt           # Incremental parser benches
```

## Design Philosophy

- **CST is the source of truth**: Markdown text is the serialization of CST
- **Lossless**: Preserves trivia (whitespace, newlines) and markers (`*` vs `_`)
- **Incremental**: Re-parses only changed blocks, reuses before/after

## Development Commands

```bash
moon check           # Type check
moon test            # Run all tests
moon test --target js    # Test with JS target
moon test --target wasm-gc  # Test with WASM-GC target
moon bench           # Run benchmarks
moon fmt             # Format code
```

## Development Workflow

### Test / Benchmark / Iteration Cycle

When fixing features, follow this cycle:

```bash
# 1. Verify basic behavior with main tests
moon test --target js src

# 2. Check progress with CommonMark compatibility tests
moon test --target js src/cmark_tests

# 3. Run specific category tests (e.g., code spans)
moon test --target js src/cmark_tests/code_spans_test.mbt

# 4. Run benchmarks and compare with baseline
moon bench
# Compare visually with .bench-baseline

# 5. If performance issues exist, re-test after optimization
moon test --target js src  # Verify optimization didn't break anything
moon bench                  # Confirm improvement

# 6. Update baseline (when optimization is complete)
just bench-accept
```

### CommonMark Compatibility Tests (cmark_tests)

`src/cmark_tests/` is auto-generated, **do not edit directly**.

- To add/remove test skips: Edit `SKIP_TESTS` in `scripts/gen-tests.js`
- To regenerate: `node scripts/gen-tests.js`
- Details: [CONTRIBUTING.md](./CONTRIBUTING.md)

### Performance Optimization Tips

- Use `peek_at(n)` instead of `count_char` (O(n) → O(1))
- Use bitmasks instead of arrays (avoid allocations)
- Avoid String creation inside loops

## Key Types

### Block (Block Elements)

```moonbit
pub(all) enum Block {
  Paragraph(span~, children~)           # Paragraph
  Heading(span~, level~, children~)     # Heading (h1-h6)
  FencedCode(span~, fence_char~, fence_length~, info~, code~)
  ThematicBreak(span~, marker_char~)    # ---
  BlockQuote(span~, children~)          # > Quote
  List(span~, ordered~, start~, tight~, marker_char~, items~)
  HtmlBlock(span~, content~)
  LinkRefDef(span~, label~, dest~, title~)
}
```

### Inline (Inline Elements)

```moonbit
pub(all) enum Inline {
  Text(span~, content~)                 # Text
  Code(span~, content~)                 # `code`
  Emphasis(span~, marker~, children~)   # *em* or _em_
  Strong(span~, marker~, children~)     # **strong** or __strong__
  Link(span~, children~, dest~, title~)
  Image(span~, alt~, dest~, title~)
  SoftBreak(span~)                      # Line break
  HardBreak(span~)                      # Two trailing spaces
  HtmlInline(span~, content~)
}
```

## API

```moonbit
// Parse
let doc = @markdown.parse(markdown_string)

// Serialize (lossless)
let output = @markdown.serialize(doc)
assert_eq(output, markdown_string)

// Incremental parse
let edit = EditInfo::new(change_start, change_end, new_length)
let new_doc = @markdown.parse_incremental(old_doc, new_text, edit)
```

## Performance Characteristics

| Document | Full Parse | Incremental | Speedup |
|----------|-----------|-------------|---------|
| 10 paragraphs | 68.89µs | 7.36µs | 9.4x |
| 50 paragraphs | 327.99µs | 8.67µs | 37.8x |
| 100 paragraphs | 651.14µs | 15.25µs | 42.7x |

## Reference Documentation

- [Architecture](./docs/markdown.md) - Detailed design document
