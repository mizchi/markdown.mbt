# MoonBit Markdown Parser

CST-based incremental Markdown parser implemented in MoonBit.

## Project Structure

```
src/
├── types.mbt                       # CST type definitions (Span, Block, Inline)
├── scanner.mbt                     # O(1) character access (Array[Char])
├── unicode.mbt                     # Shared Unicode classification helpers
├── entity.mbt                      # Entity / numeric character reference decoding
├── entity_data.mbt                 # Generated HTML5 named reference table
├── block_parser.mbt                # Block container algorithm / paragraph / blockquote / thematic break
├── block_parser_heading.mbt        # ATX & setext heading parsing
├── block_parser_code.mbt           # Fenced & indented code-block parsing
├── block_parser_link_def.mbt       # Link reference & GFM footnote definitions
├── block_parser_list.mbt           # Bullet & ordered list parsing
├── block_parser_table.mbt          # GFM table parsing
├── block_parser_html.mbt           # HTML block parsing
├── block_parser_frontmatter.mbt    # YAML frontmatter parsing
├── inline_parser.mbt               # Inline scan: text, escapes, code spans, autolinks, raw HTML
├── inline_parser_emphasis.mbt      # `*` / `_` / `~` delimiter stack
├── inline_parser_link.mbt          # Links, images, wikilinks, footnote refs
├── incremental.mbt                 # Incremental parsing (EditInfo)
├── serializer.mbt                  # Lossless block serializer + md_parse_and_render
├── serializer_inline.mbt           # Inline serialization (text, emphasis, links, ...)
├── renderer.mbt                    # HTML renderer + md_to_html
├── renderer_autolink.mbt           # Bare-URL autolink boundary helpers
├── renderer_literal.mbt            # Source-preserving HTML renderer (block dispatch + helpers)
├── renderer_literal_inline.mbt     # Inline rendering for the literal renderer
├── plugin.mbt                      # CodeBlockInfo + RenderOptions + parse_code_block_info
├── api/                            # FFI exports for JS/WASM consumers
├── experimental/
│   ├── crdt/                       # CRDT experimental code (isolated)
│   ├── multipass/                  # Experimental multi-pass inline parser
│   ├── notebook/                   # Notebook cells / executable code blocks
│   ├── mdx/                        # MDX (JSX-in-Markdown) extraction
│   ├── slide/                      # Slide-deck splitting
│   ├── tui/                        # Terminal renderer
│   └── purify/                     # HTML sanitization
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
- **Conformant**: `md_to_html` matches all 652 CommonMark 0.31.2 examples

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

# 2. Check the CommonMark spec conformance suite (must stay at 100%)
moon test --target js src/spec_tests

# 3. Check the remark serialization comparison
moon test --target js src/cmark_tests

# 4. Run specific category tests (e.g., code spans)
moon test --target js src/cmark_tests/code_spans_test.mbt

# 5. Run benchmarks and compare with baseline
moon bench
# Compare visually with .bench-baseline

# 6. If performance issues exist, re-test after optimization
moon test --target js src  # Verify optimization didn't break anything
moon bench                  # Confirm improvement

# 7. Update baseline (when optimization is complete)
just bench-accept
```

### Generated test suites

`src/spec_tests/`, `src/cmark_tests/` and `src/gfm_tests/` are auto-generated,
**do not edit directly**.

- `src/spec_tests/` — CommonMark 0.31.2 HTML conformance, from
  `scripts/gen-spec-tests.js`. All 652 examples pass; its `SKIP_TESTS` table is
  empty and should stay that way.
- `src/cmark_tests/` — Markdown serialization compared with remark, from
  `scripts/gen-tests.js`. Skips live in its `SKIP_TESTS` table.
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
