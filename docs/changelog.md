# Changelog

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
