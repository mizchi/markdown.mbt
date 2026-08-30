# @mizchi/markdown

CST-based incremental Markdown parser for JavaScript/MoonBit.

A cross-platform (JS/WASM/native) Markdown compiler optimized for real-time editing with incremental parsing.

## Features

- **Fast**: Edit-position based incremental updates inspired by [CRDTs Go Brrr](https://josephg.com/blog/crdts-go-brrr/)
- **CommonMark compliant**: passes all 652 examples of the CommonMark 0.31.2 spec
- **Source-oriented CST**: Retains node spans so byte-preserving tools can edit the original source
- **Incremental parsing**: Re-parses only changed blocks (up to 42x faster)
- **GFM**: GitHub Flavored Markdown support (tables, task lists, strikethrough)
- **Cross-platform**: Works on JS, WASM-GC, and native targets
- **HTML rendering**: Built-in HTML renderer with remark-html compatible output
- **mdast compatible**: AST follows [mdast](https://github.com/syntax-tree/mdast) specification

----

## JavaScript API

```bash
npm install @mizchi/markdown
```

### Usage

```javascript
import { parse, toHtml, toMarkdown } from "@mizchi/markdown";

// Parse to AST
const ast = parse("# Hello\n\n**Bold** text");
console.log(ast.children[0].type); // "heading"

// Convert to HTML
const html = toHtml("See https://example.com/docs\n");
// => '<p>See <a href="https://example.com/docs">https://example.com/docs</a></p>\n'

// Disable bare URL links when you need plain text output
const plain = toHtml("See https://example.com/docs\n", { autolink: false });
// => "<p>See https://example.com/docs</p>\n"

// Match CommonMark 0.31.2 rendering by disabling GFM renderer extensions
const commonmark = toHtml("<script>raw</script>\n\nhttps://example.com\n", {
  autolink: false,
  tagfilter: false,
});
// => "<script>raw</script>\n<p>https://example.com</p>\n"

// Normalize markdown
const normalized = toMarkdown("# Hello\n\n\n\nWorld");
// => "# Hello\n\nWorld\n"
```

### WebAssembly API

The same one-shot API is available from a Wasm GC build using JS String
Builtins. JavaScript strings cross the Wasm boundary directly, without a
UTF-8 linear-memory copy. `parse()` also builds ordinary JavaScript objects
through `externref` imports, avoiding an AST JSON stringify/parse round trip.
The module initializes its Wasm instance once and then exposes synchronous
functions:

```javascript
import { parse, toHtml, toMarkdown } from "@mizchi/markdown/wasm";

const ast = parse("# Hello");
const html = toHtml("See https://example.com/docs\n");
const markdown = toMarkdown("# Hello\n\n\nWorld");
```

This subpath requires an ESM runtime with Wasm GC, JS String Builtins, and
top-level `await` support. The handle-based incremental API remains available
from the default `@mizchi/markdown` entry point.

### Cloudflare Workers

The default `@mizchi/markdown` entry point cannot currently run inside a
Cloudflare Worker. It imports the SIMD module through WebAssembly ESM
Integration named exports, while Wrangler exposes imported `.wasm` files as a
default-exported `WebAssembly.Module`. Supporting workerd therefore requires a
workerd-specific bridge that instantiates that module, selected through a
`workerd` conditional export. See Cloudflare's documentation for
[Wasm module bundling](https://developers.cloudflare.com/workers/wrangler/bundling/#including-non-javascript-modules)
and [conditional exports](https://developers.cloudflare.com/workers/wrangler/bundling/#conditional-exports).

The repository's current playground deployment is unaffected because its
Worker only serves prebuilt static assets; it does not import the parser into
the workerd runtime.

### Optional WikiLinks

WikiLinks are disabled by default to keep CommonMark-compatible behavior.
Pass `{ wikilinks: true }` to parse `[[target]]` and `[[target|label]]`.

```javascript
import { parse, toHtml } from "@mizchi/markdown";

const ast = parse("[[MoonBit#syntax|MoonBit syntax]]", { wikilinks: true });
// ast.children[0].children[0].type === "wikiLink"

const html = toHtml("[[MoonBit|MoonBit notes]]", { wikilinks: true });
// => '<p><a href="MoonBit">MoonBit notes</a></p>\n'
```

### Extended syntax

The parser also exposes semantic nodes for GitHub alerts, footnotes, display
math, container/text directives, definition lists, and block attributes:

```markdown
> [!WARNING]
> Check this first.[^details]

$$
E = mc^2
$$

:::note Optional title
Markdown stays available inside the container.
:::

Use :badge[stable]{.green level=high}.

Term
: Definition

# Attributed heading
{#intro .wide}

[^details]: Footnote content.
```

Display math is represented as a `math` block with a raw `value`. The default
HTML output is an escaped `<pre>` fallback, so JavaScript consumers can instead
send the AST value to KaTeX or another math renderer.

### Incremental Parsing

For real-time editing scenarios:

```javascript
import { createDocument, insertEdit } from "@mizchi/markdown";

// Create document handle
const doc = createDocument("# Hello");

// Access AST, HTML, or Markdown
console.log(doc.ast);        // Parsed AST
console.log(doc.toHtml());   // "<h1>Hello</h1>\n"
console.log(doc.toMarkdown()); // "# Hello\n"

// Incremental update (faster than full re-parse)
const edit = insertEdit(7, 6); // Insert 6 chars at position 7
const newDoc = doc.update("# Hello World", edit);

// Free resources when done
doc.dispose();
newDoc.dispose();
```

### TypeScript Support

Full TypeScript definitions are included:

```typescript
import { parse, Document, Block, Inline } from "@mizchi/markdown";

const ast: Document = parse("# Hello");
const heading = ast.children[0] as HeadingBlock;
console.log(heading.level); // 1
```

----

## MoonBit API

### Installation

```bash
moon add mizchi/markdown
```

### Usage

```moonbit
// Parse markdown
let result = @markdown.parse("# Hello\n\nWorld")
let doc = result.document

// Serialize back to canonical, normalized Markdown
let output = @markdown.serialize(doc)

// Render to HTML
let html = @markdown.render_html(doc)

// Or use convenience function
let html = @markdown.md_to_html("# Hello\n\nWorld")
let linked = @markdown.md_to_html("See https://example.com/docs\n")
let plain = @markdown.md_to_html("See https://example.com/docs\n", autolink=false)

// Disable the GFM tagfilter when matching plain CommonMark raw-HTML output
let commonmark_html = @markdown.md_to_html("<script>raw</script>\n", tagfilter=false)

// Enable the WikiLink extension explicitly
let wiki_html = @markdown.md_to_html("[[MoonBit|MoonBit notes]]", wikilinks=true)
```

### Display-math renderer

The MoonBit HTML renderer has an explicit display-math boundary. The callback
receives the raw block contents and returns trusted HTML, making KaTeX or a
different backend replaceable without coupling it to the parser:

```moonbit
let document = @markdown.parse("$$\nx^2\n$$\n").document
let options = @markdown.RenderOptions::default().with_math_block_renderer(
  fn(source) { render_with_katex(source) },
)
let html = @markdown.render_html_with_options(document, options)
```

Without a callback, math is safely HTML-escaped in
`<pre class="math math-display"><code>…</code></pre>`.

### Native CLI

Build the native command with `just build-native`. The executable is produced
from `src/cmd/mmmd-native` and can be installed or renamed as `mmmd`:

```bash
_build/native/release/build/cmd/mmmd-native/mmmd-native.exe --format html < document.md
_build/native/release/build/cmd/mmmd-native/mmmd-native.exe --format tui < document.md
```

The native TUI format emits normalized Markdown. Mermaid remains an ordinary
fenced code block; diagram rendering is available in the JavaScript/Wasm CLI.

### Incremental Parsing

```moonbit
// Initial parse
let result = @markdown.parse(source)
let doc = result.document

// Create edit info
let edit = @markdown.EditInfo::replace(
  change_start,    // Start position
  old_length,      // Length of replaced text
  new_length       // Length of new text
)

// Incremental update (reuses unchanged blocks)
let inc_result = @markdown.parse_incremental(doc, old_source, new_source, edit)
let new_doc = inc_result.document
```

### Typed MDX Declarations

`mizchi/markdown/x/mdx` extracts MDX JSX components and validates
their attributes against a closed, typed schema. It is intended for document
metadata and domain declarations, rather than evaluating arbitrary MDX code.

Expressions use a deterministic literal-only subset: strings, booleans, and
arrays of strings. For example, `requires={["auth.mfa"]}` is valid, while
`requires={loadRequirements()}` is rejected.

```moonbit
import {
  "mizchi/markdown",
  "mizchi/markdown/x/mdx" @mdx,
}

let schema = @mdx.MdxSchema::closed([
  @mdx.ComponentSchema::new(
    "Fold",
    [
      @mdx.PropSchema::required("id", @mdx.MdxValueType::Text),
      @mdx.PropSchema::required(
        "kind",
        @mdx.MdxValueType::OneOf(["concept", "procedure"]),
      ),
      @mdx.PropSchema::optional("requires", @mdx.MdxValueType::TextList),
    ],
  ),
])

let source = #|<Fold id="auth.mfa" kind="procedure" requires={["auth.login"]} />
let checked = @mdx.type_check_mdx(@markdown.parse(source).document, schema)
let is_valid = checked.is_valid()
```

## Playground

```bash
pnpm install
moon build --target js
pnpm exec vite
```

## Frontend Editor Package

`@mizchi/markdown/editor` exports the Luna-based markdown editor without
bundling syntax highlighters into the initial module. Code block highlighters
are loaded on demand through dynamic imports under `@mizchi/markdown/highlight`.

The editor uses [`@luna_ui/luna`](https://www.npmjs.com/package/@luna_ui/luna)
as a JSX runtime and signal library; it is declared as an **optional peer
dependency** — install it alongside `@mizchi/markdown` only if you use the
editor entry. See `frontend/editor/README.md` for the editor-specific docs.

```bash
pnpm add @mizchi/markdown @luna_ui/luna
```

```tsx
import { SyntaxHighlightEditor } from "@mizchi/markdown/editor";
import "@mizchi/markdown/editor/style.css";

<SyntaxHighlightEditor
  value={() => markdown}
  onChange={(next) => setMarkdown(next)}
/>;
```

You can also preload or call a language highlighter explicitly:

```ts
import { loadHighlighter } from "@mizchi/markdown/highlight";

const highlightMoonBit = await loadHighlighter("moonbit");
const html = highlightMoonBit?.("fn main { println(\"hi\") }");
```

The currently split lazy highlighter entries are `typescript`, `moonbit`,
`json`, `html`, `css`, `bash`, and `rust`.

## Performance

| Document | Full Parse | Incremental | Speedup |
|----------|-----------|-------------|---------|
| 10 paragraphs | 68.89µs | 7.36µs | 9.4x |
| 50 paragraphs | 327.99µs | 8.67µs | 37.8x |
| 100 paragraphs | 651.14µs | 15.25µs | 42.7x |

### Native CPU profiling

`moon run --profile` can sample the same approximately 1 MiB corpus used by
the competitor benchmark. On macOS it records an Instruments Time Profiler
trace; on Linux Moon uses `perf`.

```sh
just profile-native parse 100
just profile-native render 200
just profile-native parse-render 100
```

`parse` rebuilds the document each iteration, `render` repeatedly renders one
pre-parsed document, and `parse-render` measures the public combined path.
Moon prints a demangled hot-function summary and writes `profile.json` plus the
full trace below `_build/native/release/profile/cmd/profile/`.

The same corpus can be profiled on the JavaScript backend with Node's V8 CPU
profiler. The resulting `*.cpuprofile` file can be opened in Chrome DevTools:

```sh
just profile-js parse 50
```

Profiles are written below `_build/js/release/profile/cmd/profile/`.

### JavaScript Wasm SIMD via ESM Integration

On the JavaScript target, ASCII inline-text runs of at least 64 UTF-16 code
units use a 396-byte Wasm SIMD scanner. The default npm entry point statically
imports `js/inline_marker_simd.wasm` through WebAssembly ESM Integration;
there is no inline byte array or manual `WebAssembly.instantiate` step.
`TextEncoder` writes directly into reusable Wasm memory, while a non-ASCII
prefix falls back to the UTF-16 scalar scanner so source offsets remain exact.

The WAT source and generated `.wasm` artifact can be rebuilt and checked
separately. `just bench-js` preloads the same ESM bridge for MoonBit's direct JS
benchmark runner:

```sh
just inline-wasm-build
just inline-wasm-check
just bench-js
```

## Documentation

See [docs/markdown.md](./docs/markdown.md) for detailed architecture and design.

## CommonMark Compatibility

`md_to_html` and the public JavaScript `toHtml()` API render all 652 examples of
the [CommonMark 0.31.2 spec](https://spec.commonmark.org/0.31.2/) byte for byte.
Use `{ autolink: false, tagfilter: false }` with `toHtml()` to select the
CommonMark-faithful renderer configuration. `scripts/gen-spec-tests.js` checks
the MoonBit API on every test run, while the JavaScript regression suite locks
the 11 examples affected by these two GFM renderer extensions.

Bare-URL autolinking, tables, strikethrough, task lists and footnotes are GFM
extensions on top of CommonMark. Tagfilter is also a GFM extension and escapes
raw `script`, `style`, and `textarea` tags when enabled.

Markdown output (`md_to_markdown`) is normalized rather than byte-preserving.
It uses stable markers and block spacing, and emits parsed link reference
definitions in a canonical trailing section. Use node spans and the original
source when an editor needs byte-preserving updates.

## Credits

- Fonts: [PlemolJP](https://github.com/yuru7/PlemolJP) (SIL Open Font License 1.1) — bundled in `playground/public/fonts/`

## License

MIT
