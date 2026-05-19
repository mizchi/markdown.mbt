# Literal rendering

> The rendering mode that lets the rendered HTML and the source Markdown
> share the same character grid.

## What problem does it solve?

A normal Markdown renderer turns `**bold**` into `<strong>bold</strong>` —
the asterisks are gone. That is right when the consumer only wants to
read the document, but loses information when the consumer also wants to
*edit* or *click on* the source.

The literal renderer keeps every source character visible in the rendered
output, wrapped in semantic HTML so screen readers still hear the
structure. Concretely:

| Markdown | Regular renderer | Literal renderer |
|---|---|---|
| `## Intro` | `<h2>Intro</h2>` | `<h2><span class="md-marker" aria-hidden="true">## </span>Intro</h2>` |
| `**bold**` | `<strong>bold</strong>` | `<strong><span class="md-marker" aria-hidden="true">**</span>bold<span class="md-marker" aria-hidden="true">**</span></strong>` |
| `` `code` `` | `<code>code</code>` | `<code><span class="md-marker" aria-hidden="true">\`</span>code<span class="md-marker" aria-hidden="true">\`</span></code>` |
| `[text](url)` | `<a href="url">text</a>` | `<a href="url"><span class="md-marker" aria-hidden="true">[</span>text<span class="md-marker" aria-hidden="true">](url)</span></a>` |
| `- item` | `<ul><li>item</li></ul>` | `<ul><li><span class="md-marker" aria-hidden="true">* </span>item</li></ul>` |
| `> quote` | `<blockquote>quote</blockquote>` | `<blockquote><span class="md-marker" aria-hidden="true">&gt; </span>quote</blockquote>` |

The two outputs side-by-side look very different in the DOM but produce
**byte-for-byte identical visible text** when rendered with
`font-family: monospace; white-space: pre-wrap`.

## The core invariant

For any document `D` parsed from a Markdown source, the renderer
guarantees:

```
strip_html(render_html_literal(D)) === serialize(D)
```

— stripping all HTML tags and decoding the basic character references
(`&amp; &lt; &gt; &quot;`) from the rendered output yields the same
string the lossless serializer would produce. That is what makes the
overlay alignment work: every visible glyph in the rendered DOM has a
1:1 partner in the source text.

This is checked by 41 invariant tests in
[`src/renderer_literal_test.mbt`](../src/renderer_literal_test.mbt),
which cover every Block and Inline variant the parser produces (all six
heading levels, ATX and setext, code spans with backtick padding,
strikethrough, tables with all three alignments, reference links,
autolinks, footnotes, raw HTML, nested blockquotes, etc.).

## Public API

### MoonBit

```moonbit
pub fn render_html_literal(
  doc : @markdown.Document,
  positions? : Bool = false,
  image_preview? : Bool = false,
) -> String

pub fn md_to_html_literal(
  source : String,
  wikilinks? : Bool = false,
  positions? : Bool = false,
  image_preview? : Bool = false,
) -> String
```

### JavaScript / TypeScript

```ts
import { toHtmlLiteral } from "@mizchi/markdown";

interface LiteralOptions {
  wikilinks?: boolean;
  positions?: boolean;
  imagePreview?: boolean;
}

function toHtmlLiteral(source: string, options?: LiteralOptions): string;
```

### FFI (consumed by `js/api.js` and external WASM/JS callers)

A single export takes the options as a bitmask:

```moonbit
pub fn md_to_html_literal(source : String, flags : Int) -> String
```

| Constant            | Value | Effect                                                    |
| ------------------- | ----- | --------------------------------------------------------- |
| `LITERAL_WIKILINKS`     | `1`   | Recognise `[[wikilink]]` syntax during parsing            |
| `LITERAL_POSITIONS`     | `2`   | Emit `data-src-start` / `data-src-end` on top-level blocks |
| `LITERAL_IMAGE_PREVIEW` | `4`   | Add `<img class="md-image-preview">` slot inside each image wrapper |

`flags = 0` means "default behaviour". OR the constants together for
combinations (`6 = positions + image preview`, etc.).

## Features

### Marker preservation + semantic HTML

Every Markdown marker (`#`, `**`, `_`, `` ` ``, list bullets, fence
ticks, blockquote `>`, link brackets, …) is wrapped in
`<span class="md-marker" aria-hidden="true">…</span>`. Sighted users see
them in the flow; screen readers skip them and hear only the semantic
content via the normal HTML elements (`<h1>`–`<h6>`, `<strong>`,
`<em>`, `<code>`, `<a href>`, `<ul>`/`<ol>`/`<li>`, `<blockquote>`,
`<pre><code>`, `<table>`, `<sup>`, …).

### Source-position annotations (`positions=true`)

Every top-level block element gets `data-src-start` and `data-src-end`
attributes pointing into the original source. Because the visible-text
invariant holds, the offset of a character inside such an element
equals `data-src-start + char-index-within-the-element`. This is the
foundation for "click → place cursor at the source offset" editor flows
(see [`frontend/editor/README.md`](../frontend/editor/README.md) for the
full pattern).

Inline elements are intentionally not annotated — the inline parser's
spans are relative to the surrounding block's content, not to the
document, so they cannot be used as document offsets directly. The
block-level annotations are enough.

### Inline image preview (`imagePreview=true`)

Each `<span class="md-image">` gets an `<img class="md-image-preview"
src=… alt=… loading="lazy" />` slot alongside the `![alt](url)` source
characters. Because the `<img>` has no `textContent`, the overlay
invariant is preserved whether the slot is rendered or not. The
companion stylesheet
[`@mizchi/markdown/editor/overlay.css`](../frontend/editor/overlay.css)
hides the slot by default; opt in with `.with-image-preview` on a
container.

Reference images (`![alt][label]`) emit a `data-md-image-ref="label"`
slot without a `src` so the consumer can fill the URL from their
link-definition map at display time.

### Partial DOM updates

`@mizchi/markdown/editor` ships a small framework-agnostic helper:

```ts
import { LiteralEditor } from "@mizchi/markdown/editor";

const editor = new LiteralEditor(container, render, source);
const stats = editor.setSource(newSource);
// stats: { reused, replaced, shifted, inserted, removed }
```

It diffs the new HTML against the container's current top-level child
nodes and replaces only what changed. Blocks whose only difference is a
shifted `data-src-start` / `data-src-end` get their attributes patched
in place — DOM identity, focus and selection survive.

## CSS contract

The overlay stylesheet
[`@mizchi/markdown/editor/overlay.css`](../frontend/editor/overlay.css)
provides:

1. A layout reset (no `margin` / `padding` / `display` defaults that
   would shift the character grid) on every block element under
   `.md-literal`.
2. `font-family: monospace; white-space: pre-wrap` to enforce a fixed
   character cell and preserve whitespace.
3. Semantic typography (bold for `<strong>`, italic for `<em>`,
   dimmer color for `.md-marker`) that changes appearance without
   changing horizontal advance.
4. Helper classes `.md-overlay-source` and `.md-overlay-rendered` for
   stacking two views on top of each other for VRT alignment checks.
5. An off-by-default `.md-image-preview` slot you opt into with
   `.with-image-preview`.

CSS variables let consumers override colors and sizes:
`--md-literal-text`, `--md-literal-heading`, `--md-literal-marker`,
`--md-literal-link`, `--md-literal-code`, `--md-literal-image-max-height`,
…

## Accessibility

The renderer is tested with [`axe-core`](https://github.com/dequelabs/axe-core)
in CI ([`e2e/literal-axe.spec.ts`](../e2e/literal-axe.spec.ts)) on a
fixture document that exercises every Block / Inline variant. The
literal output must have zero violations at WCAG 2.0/2.1 AA.

Key accessibility properties:

- Heading levels (`#` → `<h1>`, `##` → `<h2>`, …) are preserved so
  document outlines are accurate.
- All marker spans carry `aria-hidden="true"`. Assistive tech reads only
  the document content, not the Markdown syntax.
- `<img>` becomes `<span role="img" aria-label="alt">` containing the
  source characters; when `imagePreview=true`, a real `<img>` with `alt`
  is added alongside.
- `<a href>` and link titles are preserved unchanged.
- All decorative wrappers (`<div role="separator">` for thematic breaks,
  `<tr aria-hidden="true">` for the GFM separator row) carry their ARIA
  roles.

## Performance

Benchmarks live in
[`src/bench_renderer_literal.mbt`](../src/bench_renderer_literal.mbt).
Current numbers on JS target, sample documents from `src/bench.mbt`:

| Document          | render_html | render_html_literal | + positions | + positions + image |
| ----------------- | ----------- | ------------------- | ----------- | ------------------- |
| small (5 sec)     | 56 µs       | 22 µs               | 24 µs       | 25 µs               |
| medium (20 sec)   | 223 µs      | 88 µs               | 99 µs       | 98 µs               |
| large (100 sec)   | 1.11 ms     | 454 µs              | 528 µs      | 519 µs              |

The literal renderer is roughly **2.5× faster** than the regular HTML
renderer at every document size because most of its hot loops write
directly to the output `StringBuilder` instead of allocating
intermediate `String`s. Both renderers share the same parser, so a full
"parse + render" round-trip is dominated by parse time.

## Limitations

- The renderer's output normalises markers the same way the lossless
  serializer does (`-` → `*` for bullets, `_em_` → `*em*` for emphasis,
  `~~~` → `` ``` `` for fences). The visible text matches `serialize(doc)`,
  not necessarily the original source byte-for-byte. A "marker-preserving"
  mode that respects the AST's `marker` / `style` fields is a possible
  future extension.
- The "edit while you see inline image previews" UX (Phase 1) requires
  leaving the current textarea-overlay model — likely via
  `contenteditable`. The rendering / CSS contract above is
  forward-compatible.
