# TODO

## Current Status

- **CommonMark tests**: 189/542 passing (34.9%)
- **Main tests**: 73/73 passing (100%)
- **Serializer**: Normalized to remark-gfm output style

## High Priority

### Parser Improvements

- [ ] **Code spans**: 0/22 tests passing - parser doesn't recognize inline code properly
- [ ] **Emphasis edge cases**: Many failing tests related to delimiter matching
- [ ] **Nested lists**: Complex list nesting not handled correctly
- [ ] **Link parsing**: Nested brackets and escape handling needs work

### Serializer Options

- [ ] **Configurable hard break style**: Add option to use two-space style instead of backslash (useful for Japanese text where backslash breaks readability)
- [ ] **Configurable fence style**: Option to preserve original fence marker (tilde vs backtick)
- [ ] **Configurable bullet marker**: Option to preserve original marker (`-` vs `*`)

## Medium Priority

### Performance

- [ ] Serializer performance regressed ~15-17% due to `calc_fence_length` - consider caching or lazy evaluation
- [ ] Large table parsing shows high variance - investigate potential optimization

### Test Coverage

- [ ] **Block quotes**: 12/25 passing - improve nested blockquote handling
- [ ] **Setext headings**: 7/27 passing - edge cases with underline parsing
- [ ] **ATX headings**: 10/18 passing - escaped hash handling
- [ ] **Autolinks**: 11/19 passing - email and URL edge cases

### Features

- [ ] **Link reference definitions**: Currently parsed but not fully utilized in serialization
- [ ] **Footnotes** (GFM extension): Not yet implemented
- [ ] **Task lists**: Parsing works, but some edge cases remain

## Low Priority

### Code Quality

- [ ] Extract common patterns in block_parser.mbt
- [ ] Add more inline documentation
- [ ] Consider splitting large files (block_parser.mbt is quite large)

### Future Enhancements

- [ ] **Incremental inline parsing**: Currently only block-level incremental parsing
- [ ] **Source maps**: Track original positions through transformations
- [ ] **Custom syntax extensions**: Plugin system for custom block/inline types
- [ ] **Streaming parser**: For very large documents

## Test Categories Breakdown

| Category | Passing | Total | Rate |
|----------|---------|-------|------|
| Blank lines | 1 | 1 | 100% |
| Soft line breaks | 2 | 2 | 100% |
| Textual content | 3 | 3 | 100% |
| Paragraphs | 5 | 8 | 62.5% |
| Indented code | 7 | 12 | 58.3% |
| Autolinks | 11 | 19 | 57.9% |
| Thematic breaks | 11 | 19 | 57.9% |
| ATX headings | 10 | 18 | 55.6% |
| Fenced code | 14 | 29 | 48.3% |
| Block quotes | 12 | 25 | 48.0% |
| Hard line breaks | 6 | 15 | 40.0% |
| Emphasis | 42 | 132 | 31.8% |
| List items | 14 | 48 | 29.2% |
| Tabs | 3 | 11 | 27.3% |
| Setext headings | 7 | 27 | 25.9% |
| Backslash escapes | 4 | 13 | 30.8% |
| Images | 5 | 22 | 22.7% |
| Lists | 5 | 26 | 19.2% |
| Links | 15 | 90 | 16.7% |
| Code spans | 0 | 22 | 0% |

## Notes

- The serializer now outputs GFM-normalized markdown (matching remark-gfm behavior)
- CST preservation is partially sacrificed for compatibility (trivia, markers normalized)
- Incremental parsing still works correctly for block-level changes
