# Contributing

## Development Setup

```bash
# Install dependencies
npm install

# Run tests
moon test --target js src

# Run benchmarks
moon bench
```

## CommonMark Compatibility Tests

This project includes compatibility tests against the CommonMark spec, comparing output with `remark-gfm`.

### Generating Tests

Tests are auto-generated from the CommonMark spec. The generated files are in `src/cmark_tests/` and are git-ignored.

```bash
# Generate/regenerate tests
node scripts/gen-tests.js

# Run CommonMark tests
moon test --target js src/cmark_tests
```

### Managing Skipped Tests

This parser implements a **practical subset** of CommonMark. Edge cases and complex patterns are intentionally not supported to keep the single-pass parser simple and fast.

Skipped tests are managed in `scripts/gen-tests.js` in the `SKIP_TESTS` object:

```javascript
const SKIP_TESTS = {
  'Section Name': {
    reason: 'Reason for skipping',
    examples: [123, 456, 789],  // CommonMark example numbers
  },
  // For multiple reasons within a section:
  'Links': {
    reasons: {
      url_edge: [488, 489, ...],
      ref_link: [518, 519, ...],
    },
  },
};
```

When regenerating tests, skipped tests will automatically get `#skip("reason")` annotations.

### Adding New Skips

1. Run tests to identify failures: `moon test --target js src/cmark_tests`
2. Add failing example numbers to the appropriate section in `SKIP_TESTS`
3. Regenerate tests: `node scripts/gen-tests.js`
4. Verify: `moon test --target js src/cmark_tests`

### Test Summary

- **Total tests**: 542
- **Passing**: 207 (38.2%)
- **Skipped**: 335 (61.8%)

### Skip Categories

| Category | Count | Reason |
|----------|-------|--------|
| Emphasis | 81 | Single-pass parser limitation (Rule 9/10, mod 3) |
| Links | 74 | URL edge cases, reference link complexities |
| List items | 34 | Complex indentation, lazy continuation |
| Lists | 21 | Tight/loose distinction, complex nesting |
| Setext headings | 20 | Not implemented (ATX headings sufficient) |
| Images | 17 | Similar to links edge cases |
| Block quotes | 13 | Lazy continuation and nesting |
| Code spans | 13 | Backtick counting edge cases |
| Others | ~67 | Tabs, escapes, headings, code blocks, line breaks |

## Architecture

See [docs/markdown.md](docs/markdown.md) for detailed architecture documentation.

## Code Style

- Run `moon fmt` before committing
- Follow existing patterns in the codebase
- Add tests for new features
