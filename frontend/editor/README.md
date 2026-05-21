# `@mizchi/markdown/editor`

Luna-based markdown editor with on-demand syntax highlighting. Published as a
subpath of [`@mizchi/markdown`](../../README.md) — install the package once and
import the editor via its dedicated entry point.

## Installation

```bash
pnpm add @mizchi/markdown @luna_ui/luna
```

`@luna_ui/luna` is an **optional peer dependency** of `@mizchi/markdown`. The
core parser and `/editor/literal` entry do not require it; only the Luna-based
`/editor` component entry does, so consumers that don't render
`SyntaxHighlightEditor` can omit it.

## Usage

```tsx
import { SyntaxHighlightEditor } from "@mizchi/markdown/editor";
import "@mizchi/markdown/editor/style.css";

<SyntaxHighlightEditor
  value={() => markdown}
  onChange={(next) => setMarkdown(next)}
/>;
```

The stylesheet ships as a separate subpath export (`@mizchi/markdown/editor/style.css`)
so build tools don't pull it into the JS module graph automatically — import it
explicitly once, anywhere in your app.

## Code-block highlighting

Highlighters for individual languages live behind dynamic imports under
`@mizchi/markdown/highlight`. They are loaded only when the editor first
encounters that language inside a fenced code block; nothing is bundled into
the initial editor module.

Currently available: `typescript`, `moonbit`, `json`, `html`, `css`, `bash`,
`rust`.

You can preload or invoke a highlighter explicitly:

```ts
import { loadHighlighter } from "@mizchi/markdown/highlight";

const highlightMoonBit = await loadHighlighter("moonbit");
const html = highlightMoonBit?.("fn main { println(\"hi\") }");
```

### How lazy loading works in your build

The published artifact uses native ES dynamic `import()`:

```js
// dist/frontend/highlight/index.js (excerpt)
const highlighterLoaders = {
  typescript: () => import("./languages/typescript.js"),
  moonbit:    () => import("./languages/moonbit.js"),
  json:       () => import("./languages/json.js"),
  // ...
};
```

Any modern bundler — Vite, Rollup, webpack, esbuild, Parcel — recognises
these calls and emits one chunk per language. As a reference point, an
unmodified Vite build of a small app that uses the editor produces roughly:

| Chunk | Size | gzip |
|---|---|---|
| main bundle (parser + editor + shared utils) | ~210 KB | ~53 KB |
| `typescript-*.js` | ~23 KB | ~6 KB |
| `moonbit-*.js`    | ~20 KB | ~5 KB |
| `rust-*.js`       | ~18 KB | ~5 KB |
| `bash-*.js`       | ~17 KB | ~5 KB |
| `json-*.js`       | ~16 KB | ~5 KB |
| `css-*.js`        | ~15 KB | ~5 KB |
| `html-*.js`       | ~12 KB | ~4 KB |

Only the main bundle is fetched on page load. A language chunk is fetched
the first time a fenced code block of that language renders. The fetch is
deduped (concurrent calls share a single promise) and the resulting
highlighter is cached in memory for the rest of the session.

While a language is still loading, the editor renders the code block as
HTML-escaped plain text. As soon as the chunk arrives, the cache is
invalidated and the affected blocks re-render with highlighting.

### Preloading languages

If you already know which languages a page will use, you can warm the cache
ahead of time so the first code block paints with colour:

```ts
import { preloadHighlighter } from "@mizchi/markdown/highlight";

await Promise.all([
  preloadHighlighter("typescript"),
  preloadHighlighter("moonbit"),
]);
```

`preloadHighlighter` resolves to `true` when the highlighter is ready and
returns `false` for unknown languages.

### One-shot highlighting outside the editor

The same API works without the editor — useful for SSR, static rendering,
or just highlighting a single snippet:

```ts
import { highlight } from "@mizchi/markdown/highlight";

const html = await highlight(source, "typescript");
```

`highlight` falls back to HTML-escaped plain text when the language is
unknown, so it is safe to call with arbitrary user input.

### Bypassing the lazy loader

If you want a specific language eagerly bundled into your main chunk
(for example because you control the document and never see other
languages), import it directly:

```ts
import highlightTs from "@mizchi/markdown/highlight/typescript";

const html = highlightTs("const x = 1;");
```

Each `@mizchi/markdown/highlight/<lang>` entry is a thin synchronous
wrapper around the MoonBit-built highlighter for that language. Mixing
this with the lazy API is fine; whichever entry runs first populates the
shared cache.

### Bundler notes

- **Vite / Rollup** — works out of the box; each `import()` becomes a
  separate chunk in the build output.
- **webpack 5+** — same; the chunks land under `output.chunkFilename`.
  Set `output.publicPath` correctly so the editor can fetch them at
  runtime.
- **esbuild** — emits chunks when `--splitting --format=esm` is set, which
  is the default for ESM library builds.
- **No bundler (browser ESM)** — the editor still works; the browser
  fetches each `./languages/<lang>.js` on demand the first time it is
  needed.

## JSX runtime

The editor is authored against Luna's JSX runtime
(`jsxImportSource: "@luna_ui/luna"`). The published artifact is plain ES
modules with JSX already compiled, so consumers don't need any special
TypeScript config to use it. If you re-export the editor's types and rely on
TS type-checking, ensure `@luna_ui/luna` is resolvable in your
`tsconfig.json`.

## Literal (source-preserving) rendering

For tools that need to overlay rendered Markdown on a syntax-highlighted
source view, the package ships a second rendering mode whose visible text
(HTML tags stripped, basic character references decoded) is byte-for-byte
equal to the lossless serialization of the document. Markdown markers
(`#`, `**`, `_`, `` ` ``, list bullets, fence ticks, blockquote `>`, …)
are wrapped in `<span class="md-marker" aria-hidden="true">…</span>` so
screen readers skip them while sighted users still see them in flow.

```tsx
import { toHtmlLiteral } from "@mizchi/markdown";
import "@mizchi/markdown/editor/overlay.css";

<div
  class="md-literal"
  // eslint-disable-next-line react/no-danger
  dangerouslySetInnerHTML={{ __html: toHtmlLiteral(source) }}
/>;
```

`overlay.css` is opt-in: it resets layout-shifting defaults on every
block element, forces a monospace font and `white-space: pre-wrap`, then
adds back semantic typography (bold for `<strong>`, italic for `<em>`,
dim color for marker spans) without affecting the character grid.

[`docs/literal-html-reference.md`](../../docs/literal-html-reference.md)
catalogues every emitted class, ARIA role, data attribute and CSS
variable, with theming recipes (light theme, hidden-marker preview,
click-to-edit highlight, per-language code-block tinting, …).

Helper classes `.md-overlay`, `.md-overlay-source`, `.md-overlay-rendered`
provide a stacking layout for two coincident layers — one for a source
view (textarea or syntax-highlighted `<pre>`) and one for the literal
renderer output — so VRT can pixel-diff that they line up.

The repo's `playground/literal/` is a runnable demo, and
`e2e/literal-overlay.spec.ts` runs the alignment assertion across a fixed
sample set on every CI run.

### Accessibility

[`docs/literal-rendering.md`](../../docs/literal-rendering.md) covers the
overall accessibility model. The repo runs
[axe-core](https://github.com/dequelabs/axe-core) over the literal
output on a fixture document that exercises every block / inline
variant ([`e2e/literal-axe.spec.ts`](../../e2e/literal-axe.spec.ts)); it
must report zero WCAG 2.0/2.1 A or AA violations on every CI run.



- Marker spans carry `aria-hidden="true"`. Assistive tech never reads the
  raw Markdown syntax; it gets `<h1>`, `<strong>`, `<a href>`, `<ul>` etc.
- The renderer preserves heading level (`#` → `<h1>`, `##` → `<h2>`, …)
  so document outlines stay correct.
- `<img>` becomes `<span class="md-image" role="img" aria-label="…">` so
  the alt text reaches screen readers while the literal `![alt](url)`
  bytes remain visible.
- `<a href>` is preserved; the `[text](url)` characters all sit inside
  the anchor so the link target is unambiguous to keyboard users.

### Click-to-cursor source positions

Pass `{ positions: true }` to `toHtmlLiteral` and every top-level block
element gains `data-src-start` / `data-src-end` attributes pointing into
the original Markdown source:

```tsx
import { toHtmlLiteral } from "@mizchi/markdown";

const html = toHtmlLiteral(source, { positions: true });
// <h2 data-src-start="0" data-src-end="9">...</h2>
// <p data-src-start="9" data-src-end="24">...</p>
```

This is intended as the foundation for a "preview by default, edit when
you click" experience. Because the literal renderer's visible text equals
the source byte-for-byte, the offset of any character inside a positioned
element equals `data-src-start + character-index-within-the-element`.
Combined with the browser's `caretRangeFromPoint`, a click handler can
compute the exact source offset of the clicked glyph:

```ts
function findPositionedAncestor(node: Node | null): HTMLElement | null {
  let el = node instanceof Element ? node : node?.parentElement ?? null;
  while (el && !(el instanceof HTMLElement && el.dataset.srcStart != null)) {
    el = el.parentElement;
  }
  return el;
}

function sourceOffsetFromPoint(x: number, y: number): number | null {
  const range = document.caretRangeFromPoint?.(x, y);
  if (!range) return null;
  const ancestor = findPositionedAncestor(range.startContainer);
  if (!ancestor) return null;
  const base = Number(ancestor.dataset.srcStart);
  // Count text characters from the ancestor's start up to the caret.
  let within = 0;
  const walker = document.createTreeWalker(ancestor, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (n === range.startContainer) return base + within + range.startOffset;
    within += (n as Text).data.length;
  }
  return base + within;
}
```

Inline elements (`<em>`, `<strong>`, `<code>`, `<a>`, …) deliberately do
**not** carry `data-src-*`, because the inline parser's spans are relative
to the surrounding block's content, not to the document. Walking up to
the nearest annotated block ancestor is always correct and the visible-text
invariant guarantees that the per-character offset within that block is a
1:1 mapping to source offsets.

`playground/literal/` ships a runnable end-to-end demo of this pattern
(preview → click → cursor placement → edit → Escape → preview), and
`e2e/literal-overlay.spec.ts` exercises both the alignment invariant and
the click-to-cursor flow on every CI run.

### Partial DOM updates

For a live preview during editing, re-rendering the full HTML on every
keystroke and assigning it to `innerHTML` works but drops DOM identity —
selections, focus and per-node state are lost, and the browser has to
reflow the entire preview.

The `LiteralEditor` helper in `@mizchi/markdown/editor/literal` keeps a
container in sync with a source string through a partial-update strategy:

```ts
import { toHtmlLiteral } from "@mizchi/markdown";
import { LiteralEditor } from "@mizchi/markdown/editor/literal";
import "@mizchi/markdown/editor/overlay.css";

const editor = new LiteralEditor(
  document.getElementById("preview")!,
  (src) => toHtmlLiteral(src, { positions: true }),
  initialSource,
);

textarea.addEventListener("input", () => {
  const stats = editor.setSource(textarea.value);
  // stats: { reused, replaced, shifted, inserted, removed }
});
```

Internally, each call to `setSource(next)`:

1. Renders `next` to HTML through the supplied renderer.
2. Diffs the resulting top-level child nodes (elements *and* the
   text-node separators between them) against the current DOM.
3. Skips the unchanged prefix/suffix.
4. For pairs in the middle range where the only difference is a shifted
   `data-src-start` / `data-src-end`, patches the attribute values in
   place — DOM identity, focus and selection are preserved.
5. Replaces only the genuinely-changed pairs and adjusts the tail for
   length differences.

Returned `PatchStats` (`reused`, `replaced`, `shifted`, `inserted`,
`removed`) let callers report or test the partial-update behaviour. The
helper is framework-agnostic: it takes a renderer function and a
container element and makes no assumptions about UI libraries.

`patchTopLevelChildren(container, newHtml)` is exposed separately for
callers that manage their own state.

### Literal editor controller

For browser editors that want the same click-to-edit behaviour as the
playground, `createLiteralMarkdownEditor` wires the literal preview,
syntax-highlighted source layer, textarea, image-preview spacers, custom
selection overlays and IME anchor correction into one framework-agnostic
controller:

```ts
import { toHtmlLiteral } from "@mizchi/markdown";
import { createLiteralMarkdownEditor } from "@mizchi/markdown/editor/literal";
import "@mizchi/markdown/editor/overlay.css";

const editor = createLiteralMarkdownEditor({
  elements: {
    host: document.querySelector(".md-literal-editor") as HTMLDivElement,
    rendered: document.querySelector(".md-literal-rendered")!,
    source: document.querySelector(".md-literal-source-edit") as HTMLTextAreaElement,
    sourceView: document.querySelector(".md-literal-source-view")!,
    sourceCaret: document.querySelector(".md-literal-source-caret") as HTMLDivElement,
    sourceSelection: document.querySelector(".md-literal-source-selection") as HTMLDivElement,
    modeRoot: document.body,
  },
  initialSource,
  renderLiteral: (source, options) => toHtmlLiteral(source, options),
});

editor.setImagePreview(true);
editor.setMode("edit");
```

The returned handle exposes `setSource`, `setMode`, `setImagePreview`,
`syncLayout`, `refreshInvariant` and `destroy`. The controller adds stable
`md-literal-*` classes to the supplied elements; `overlay.css` contains the
matching baseline styles, while apps remain free to replace the shell layout
or status UI.

Use `@mizchi/markdown/editor/literal` when embedding only the literal
controller. That subpath exports only framework-agnostic DOM helpers and does
not import the Luna-based `SyntaxHighlightEditor` component.

### Inline image preview (Phase 0)

`toHtmlLiteral(source, { imagePreview: true })` adds a non-text
`<span class="md-image-preview-slot">` containing a real
`<img class="md-image-preview" src=… alt=… title=… loading="lazy">`
inside every `<span class="md-image">` wrapper, alongside the
`![alt](url)` source characters. The slot is appended after the Markdown
source characters. It has empty `textContent`, so the text-content
invariant continues to hold.

Use an alt suffix to reserve width, Marp-style:

```md
![diagram:w500](/diagram.png)
```

The source text remains `diagram:w500`, but the real image `alt` becomes
`diagram`, and the preview slot gets `data-md-image-width="500"` plus
`--md-literal-image-width:500px`. The slot also carries
`data-md-noneditable="true"` and `contenteditable="false"` so
click-to-cursor handlers and contenteditable hosts can treat the image
region as atomic and keep the caret out of it.

```ts
import { toHtmlLiteral } from "@mizchi/markdown";
import "@mizchi/markdown/editor/overlay.css";

container.innerHTML = toHtmlLiteral(source, {
  positions: true,
  imagePreview: true,
});
container.classList.add("with-image-preview");
```

`overlay.css` hides `.md-image-preview-slot` by default. Opt in by adding
`.with-image-preview` to a container above the rendered output (or on
the `.md-literal` element itself). CSS variables override the defaults:

```css
.with-image-preview {
  --md-literal-image-max-height: 2em;
  --md-literal-image-gap: 0.5em;
}
```

Reference images (`![alt][label]`) emit an empty-`src` slot carrying
`data-md-image-ref="label"`; the consumer's JS resolves the URL from the
document's link-definition map and assigns `src` later.

When a line contains only Markdown image syntax with a previewable URL,
for example:

```md
![diagram](/images/diagram.svg)
```

the renderer emits a `md-image-preview-block` slot after that line. The
Markdown image source remains visible as text, and `overlay.css` places
the image preview on the following visual line.

The runnable demo in `playground/literal/` has a toggle for the feature
so the side-by-side behaviour can be inspected. Phase 1 (an editing
mode that keeps images visible while you type — likely
contenteditable-based) is deferred; the rendering / CSS contract above
is forward-compatible with that work.

## Exports

| Subpath | Contents |
|---|---|
| `@mizchi/markdown` | `parse`, `toHtml`, `toMarkdown`, `toHtmlLiteral`, `createDocument` |
| `@mizchi/markdown/editor` | `SyntaxHighlightEditor`, `LiteralEditor`, `createLiteralMarkdownEditor`, editor handle/types, plus the `highlight` re-exports below |
| `@mizchi/markdown/editor/literal` | Luna-free `LiteralEditor`, `createLiteralMarkdownEditor`, `patchTopLevelChildren`, and literal editor handle/types |
| `@mizchi/markdown/editor/style.css` | Editor stylesheet |
| `@mizchi/markdown/editor/overlay.css` | CSS reset + typography for the literal renderer |
| `@mizchi/markdown/highlight` | `loadHighlighter`, `highlight`, `highlightIfLoaded`, `preloadHighlighter`, `getLoadedHighlighter`, `normalizeHighlightLanguage` |
| `@mizchi/markdown/highlight/<lang>` | Direct (non-lazy) import of a single highlighter |
