# Comparative Analysis with cmark Implementation

Analysis of rami3l/cmark (v0.4.0) emphasis implementation, summarizing adoptable approaches.

## Benchmark Comparison

| Document | mizchi/markdown | rami3l/cmark | Difference |
|----------|-----------------|--------------|-----|
| small (5) | 46.38us | 36.43us | +27% slower |
| medium (20) | 142.42us | 155.81us | **-9% faster** |
| large (100) | 660.70us | 794.09us | **-17% faster** |

Advantageous for medium to large documents. Initialization overhead for small documents remains an issue.

## Differences in Emphasis Implementation

### Issues with the Current Implementation

1. **Rule 9, 10 (mod 3 rule) not implemented**
2. **No Closer Index** - Inefficient search for closing delimiters
3. **Single-pass processing** - Cannot handle complex nesting
4. **Left/Right flanking is partial**

### cmark Architecture

#### 1. Tokenization Phase

```moonbit
// Generate TokenEmphasisMarks for each consecutive * or _
TokenEmphasisMarks { start, char, count, may_open, may_close }
```

#### 2. Left/Right Flanking Determination (CommonMark Spec)

```moonbit
// Basic determination
is_left_flanking = !is_next_white && (!is_next_punct || is_prev_white || is_prev_punct)
is_right_flanking = !is_prev_white && (!is_prev_punct || is_next_white || is_next_punct)

// For *
may_open = is_left_flanking
may_close = is_right_flanking

// For _ (additional word boundary constraints)
may_open = is_left_flanking && (!is_right_flanking || is_prev_punct)
may_close = is_right_flanking && (!is_left_flanking || is_next_punct)
```

#### 3. Closer Index

Indexing closing delimiter positions with a hash map:

```moonbit
priv struct CloserIndex(Map[Closer, Set[Int]])

fn CloserIndex::exists(self, key: Closer, after~: Int) -> Bool
fn CloserIndex::pos(self, key: Closer, after~: Int) -> Int?
```

Enables O(1) lookup for "Is there a closing `*` after this position?".

#### 4. Rule 9, 10 (mod 3 rule)

Implements CommonMark spec Rule 9, 10:

```moonbit
fn marks_match(marks: TokenEmphasisMarks, opener: TokenEmphasisMarks) -> Bool {
  opener.char == marks.char &&
  (
    (marks.may_open || !opener.may_close) ||
    marks.count % 3 == 0 ||
    (opener.count + marks.count) % 3 != 0
  )
}
```

This rule correctly handles ambiguous cases like `***foo**`.

#### 5. 3-Pass Processing

1. **First pass**: Code spans, autolinks, links
2. **Second pass**: Emphasis, strikethrough
3. **Last pass**: Text node generation

## Implementation Plan and Verification Results

### Phase 1: Adding Rule 9, 10 (mod 3 rule)

**Target file**: `src/inline_parser.mbt`

**Changes**:
- Track marker count in `try_parse_emphasis`
- Apply mod 3 rule when matching with closing markers

**Expected effect**: Major improvement in emphasis tests (currently 42/132)

**Result**: No effect (42/132 → 42/132)

### Phase 2: Full Left/Right Flanking Implementation

**Target file**: `src/inline_parser.mbt`

**Changes**:
- Strictly implement word boundary rules for `_`
- Add Unicode whitespace and punctuation detection

**Expected effect**: Improvement in `_`-related edge cases

**Result**: Regression occurred (42/132 → 41/132)

### Problem Analysis

The majority of emphasis test failures are due to **serialization differences**:
- remark: Escapes `*` `_` in text (`\*`, `\_`)
- This implementation: Outputs as-is

Example: `a * foo bar*`
- remark output: `a \* foo bar\*`
- This implementation output: `a * foo bar*`

This is a difference in CST design choices, not a parsing accuracy issue.

### Phase 3: Introducing Closer Index (Not Implemented)

**Target file**: `src/inline_parser.mbt` (new struct addition)

**Changes**:
- Add `CloserIndex` struct
- Index closing delimiters during tokenization
- Use O(1) lookup during search

**Expected effect**: Performance improvement (especially for large documents)

### Phase 4: Multi-Pass Processing (Not Implemented)

**Target file**: `src/inline_parser.mbt` (major refactoring)

**Changes**:
- Restructure to tokenization → pass 1 → pass 2 → pass 3
- Process different types of inlines in each pass

**Expected effect**: Accurate processing of complex nesting

### Phase 4: Multi-Pass Processing (Fully Implemented and Verified)

**Implementation**:
- Implemented Token enum, tokenize, and CloserIndex in `inline_token.mbt`
- Implemented complete inline parser as `parse_inlines_multipass()` function
- Full support for code spans, links, images, autolinks, strikethrough, and escapes

**Benchmark results** (full version):

| Test | Original | Multipass | Comparison |
|------|----------|-----------|------|
| simple text | 0.45 us | 0.46 us | Equivalent |
| emphasis/strong/code | 1.44 us | 1.84 us | 28% slower |
| links and images | 3.49 us | 4.70 us | 35% slower |
| stress 10 (30 markers) | 9.85 us | 13.45 us | 37% slower |
| stress 50 (150 markers) | 39.05 us | 72.95 us | 87% slower |

**CommonMark compatibility**:
- Original: 202/542 (37%)
- Multipass: 187/542 (35%)

**Result**: Regression in both performance and compatibility

The multi-pass parser is slower than the original parser in all cases due to the overhead of token array generation and multiple traversals. CommonMark compatibility also dropped by 15 tests.

### Phase 5: Optimization Attempts (Experimented)

The following optimizations were attempted:

1. **Binary search for CloserIndex**: Implemented (O(n) → O(log n))
2. **Changed substring to String slice**: Implemented
3. **Merged tokenize + CloserIndex construction**: Executed in 1 pass
4. **Replaced Array[Char] with StringView**: Removed `text.to_array()`

**Benchmark results**:

| Test | Original | Multipass (Initial) | Multipass (Final) | vs Original |
|------|----------|-----------------|------------------|-------------|
| simple text | 0.62 us | 0.46 us | 0.41 us | 34% faster |
| emphasis | 1.43 us | 1.84 us | 1.56 us | 9% slower |
| stress 10 | 7.74 us | 13.45 us | 9.92 us | 28% slower |
| stress 50 | 35.89 us | 72.95 us | 61.86 us | 72% slower |
| stress 100 | 70.27 us | 116.83 us | 101.61 us | 45% slower |

**Improvements from StringView**:
- stress 100: 116.83 us → 101.61 us (13% improvement)
- stress 10: 12.24 us → 9.92 us (19% improvement)
- emphasis: 1.72 us → 1.56 us (9% improvement)

### Conclusion

Improving CommonMark compatibility for emphasis requires large-scale refactoring, but optimizations significantly improved multi-pass parser performance.

| Approach | Effect | Performance |
|-----------|------|------|
| Phase 1: mod 3 rule | No effect | - |
| Phase 2: Flanking | Regression | - |
| Phase 4: Multi-pass | Regression | 87% slower |
| Phase 5: Optimization | Significant improvement | 28-45% slower |

The current architecture appears to have a ceiling at Emphasis 42/132 (32%).

**Remaining bottlenecks**:
- Recursive token traversal within parse_range
- Intermediate data structure costs are significant compared to the original "process immediately upon finding" approach

For now, `parse_inlines_multipass()` is kept as experimental code, and the main parser uses the original single-pass implementation.

## Reference Links

- [CommonMark Spec - Emphasis and strong emphasis](https://spec.commonmark.org/0.31.2/#emphasis-and-strong-emphasis)
- [rami3l/cmark](https://github.com/moonbit-community/cmark.mbt)
- Source: `.mooncakes/rami3l/cmark/src/cmark/inline_struct.mbt`
