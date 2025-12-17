# Inline Parser Benchmark Baseline

Before multi-pass refactoring (2024-12)

## Inline Parsing Results

| Test | Time | Notes |
|------|------|-------|
| inline: simple text | 0.45 µs | Text only |
| inline: emphasis/strong/code | 1.44 µs | Basic markers |
| inline: links and images | 3.49 µs | Complex inline |
| inline: many markers | 1.70 µs | 12 markers |
| inline: nested emphasis (***) | 1.26 µs | 3x *** |
| inline: underscore emphasis | 0.99 µs | _ markers |
| inline: mixed emphasis | 0.95 µs | * and _ mixed |
| inline: unclosed markers | 1.85 µs | Worst case |
| inline: many emphasis (15 markers) | 2.38 µs | 15 markers |
| inline: stress 10 (30 markers) | 9.85 µs | 30 markers |
| inline: stress 50 (150 markers) | 39.05 µs | 150 markers |

## Parse Benchmarks

| Document | Time |
|----------|------|
| small (5 sections) | 103.14 µs |
| medium (20 sections) | 411.68 µs |
| large (100 sections) | 2.39 ms |

## Target

- Keep inline parsing within 2x of baseline
- Large document parsing should remain competitive with cmark
