# `@mizchi/markdown/editor`

Luna-based markdown editor with on-demand syntax highlighting. Published as a
subpath of [`@mizchi/markdown`](../../README.md) — install the package once and
import the editor via its dedicated entry point.

## Installation

```bash
pnpm add @mizchi/markdown @luna_ui/luna
```

`@luna_ui/luna` is an **optional peer dependency** of `@mizchi/markdown`. The
core parser does not require it; only the `/editor` entry does, so consumers
that don't render the editor can omit it.

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

## JSX runtime

The editor is authored against Luna's JSX runtime
(`jsxImportSource: "@luna_ui/luna"`). The published artifact is plain ES
modules with JSX already compiled, so consumers don't need any special
TypeScript config to use it. If you re-export the editor's types and rely on
TS type-checking, ensure `@luna_ui/luna` is resolvable in your
`tsconfig.json`.

## Exports

| Subpath | Contents |
|---|---|
| `@mizchi/markdown/editor` | `SyntaxHighlightEditor`, `SyntaxHighlightEditorHandle`, `SyntaxHighlightEditorProps`, plus the `highlight` re-exports below |
| `@mizchi/markdown/editor/style.css` | Editor stylesheet |
| `@mizchi/markdown/highlight` | `loadHighlighter`, `highlight`, `highlightIfLoaded`, `preloadHighlighter`, `getLoadedHighlighter`, `normalizeHighlightLanguage` |
| `@mizchi/markdown/highlight/<lang>` | Direct (non-lazy) import of a single highlighter |
