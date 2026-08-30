# TODO

## Current status

- Core parser tests: 302/302 on both JavaScript and Wasm.
- CommonMark HTML conformance: 652/652 with no skipped examples.
- Markdown serialization parity with remark: 464 active examples and 78 skipped examples.
- CommonMark semantic round-trip: 611/652; 41 examples still change rendered HTML after normalization.
- GFM extension serialization comparison: 23 active examples and 1 intentional skipped example.
- Official GFM HTML conformance: 24/24 on both JavaScript and Wasm.
- A native `mmmd` implementation is available under `src/cmd/mmmd-native`.
- The only open GitHub issue is #1; its implementation is present locally but the issue remains open pending release/closure.
- The `strict` argument remains for compatibility; parsing is always CommonMark-conformant.

## P0: Completed

- [x] Gate GFM behavior against the official cmark-gfm HTML for all 24 extension examples on JavaScript and Wasm.
- [x] Implement GFM disallowed-raw-HTML tag filtering for block and inline HTML.
- [x] Keep GFM table bodies open for pipe-less continuation rows until a blank line or a new block begins.
- [x] Implement GFM extended autolinks, including boundary, host, punctuation, entity, and balanced-parenthesis rules.
- [x] Add a native CLI for [issue #1](https://github.com/mizchi/markdown.mbt/issues/1). Native TUI output deliberately leaves Mermaid as an ordinary fenced code block because the diagram renderer is JavaScript/Wasm-only.
- [x] Define `serialize` as a stable normalized format: ATX headings, canonical markers and spacing, a trailing reference-definition section, preserved reference styles, and idempotent/semantic round-trip tests.

## P1: Correctness and maintenance

- [ ] Fix the 41 CommonMark semantic round-trip cases classified in `docs/serializer-compat.md`; prioritize block/list structure, block-start escaping, and reference definitions.
- [ ] Decide whether the 47 formatting-only remark differences are worth matching. They do not change rendered HTML and often conflict with the normalized serializer contract.
- [ ] Decide whether the experimental notebook package remains in this repository. Its separate backlog is in `src/x/notebook/TODO.md`.

## P1: Performance

- [ ] Establish stable serializer and large-table baselines before optimizing them. The old percentage-regression notes were not backed by the current benchmark baseline.
- [ ] Keep `just bench-simd` as the regression gate for line scanning and long HTML terminator searches.

## Completed or removed

- [x] Full CommonMark HTML conformance, including nested lists, setext headings, emphasis, and reference-link resolution.
- [x] Split block parsing into focused files.
- [x] SIMD line scanning and HTML terminator search benchmarks.
- [x] Official GFM HTML conformance, tagfilter, table continuation, and extended autolinks.
- [x] Escaped pipes inside table inline elements ([issue #6](https://github.com/mizchi/markdown.mbt/issues/6), including official GFM example 200).
- [x] Native `mmmd` CLI with a deterministic Mermaid fallback.
- [x] Stable normalized serializer contract and canonical reference definitions.
- [x] GitHub alert blocks and complete footnote rendering with repeated back references.
- [x] Display-math blocks with a replaceable trusted-HTML renderer boundary for KaTeX-style integrations.
- [x] Container/text directives, definition lists, and standalone block attributes.
- [x] Shift nested ordered/unordered list-item and child-block spans during incremental reuse.
- [x] Resolve 5 of 6 GFM serializer differences. Keep example 204 intentionally different because remark exposes an overflow cell that official GFM ignores.
- [x] Remove the experimental Folddown package, public API, viewer, workflow, and documentation.
