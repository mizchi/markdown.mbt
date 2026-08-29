# Contributing

## Development Setup

```bash
# Install dependencies
npm install

# Run tests
moon test --target js src

# Run benchmarks
moon bench

# Literal renderer core only
pnpm run bench:literal:core

# Literal browser/editor controller
pnpm run bench:literal
```

Browser benchmarks should reuse `e2e/helpers/browser-benchmark.ts` for CLI
parsing, Vite startup, Playwright lifecycle, frame-settled timing, percentile
summaries, and Markdown/JSON output. Keep each concrete benchmark file focused
on page setup and scenario definitions.

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

Skipped tests are managed in `scripts/gen-tests.js` in the `SKIP_TESTS` object,
which lists the CommonMark example numbers per spec section:

```javascript
const SKIP_TESTS = {
  'Section Name': [123, 456, 789],
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
- **Passing**: 397 (73.2%)
- **Skipped**: 145 (26.8%)

What is left is serialization, not parsing: link reference definitions are
dropped rather than written back out, setext headings are kept instead of being
normalized to ATX, and a handful of escaping and autolink details differ.
Parsing itself is checked separately, and exactly, by the conformance suite
below.

## CommonMark Spec Conformance Tests

`gen-tests.js` above checks how our *Markdown* serialization lines up with
remark. The conformance suite is stricter and independent: it renders every
example in the CommonMark spec and requires byte-identical HTML. All 652 pass,
and `SKIP_TESTS` in its generator is empty — keep it that way.

```bash
# Generate/regenerate the suite (spec.json is cached under node_modules/.cache)
node scripts/gen-spec-tests.js

# Run it
moon test src/spec_tests --target js
```

The generated files live in `src/spec_tests/` and are git-ignored; only
`scripts/gen-spec-tests.js` is checked in. Should a change ever regress an
example, list it in that generator's `SKIP_TESTS` table so the gap is explicit,
and use `--no-skip` to run the whole spec regardless:

```bash
node scripts/gen-spec-tests.js --no-skip
moon test src/spec_tests --target js
```

Bare-URL autolinking is a GFM extension, so the suite renders with
`autolink=false`.

## Architecture

See [docs/markdown.md](docs/markdown.md) for detailed architecture documentation.

## Code Style

- Run `moon fmt` before committing
- Follow existing patterns in the codebase
- Add tests for new features
