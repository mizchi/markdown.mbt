# @mizchi/markdown

CST-based incremental Markdown parser for JavaScript/MoonBit.

A cross-platform (JS/WASM/native) Markdown compiler optimized for real-time editing with incremental parsing.

## Features

- **Fast**: Edit-position based incremental updates inspired by [CRDTs Go Brrr](https://josephg.com/blog/crdts-go-brrr/). Optimized for speed over edge-case correctness CommonMark 207/542
- **Lossless CST**: Preserves all whitespace, markers, and formatting
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
const html = toHtml("# Hello\n\n**Bold** text");
// => "<h1>Hello</h1>\n<p><strong>Bold</strong> text</p>\n"

// Normalize markdown
const normalized = toMarkdown("# Hello\n\n\n\nWorld");
// => "# Hello\n\nWorld\n"
```

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

// Serialize back (lossless)
let output = @markdown.serialize(doc)

// Render to HTML
let html = @markdown.render_html(doc)

// Or use convenience function
let html = @markdown.md_to_html("# Hello\n\nWorld")
```

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

----

## Playground

```bash
pnpm install
moon build --target js
pnpm exec vite
```

## Performance

| Document | Full Parse | Incremental | Speedup |
|----------|-----------|-------------|---------|
| 10 paragraphs | 68.89µs | 7.36µs | 9.4x |
| 50 paragraphs | 327.99µs | 8.67µs | 37.8x |
| 100 paragraphs | 651.14µs | 15.25µs | 42.7x |

## Documentation

See [docs/markdown.md](./docs/markdown.md) for detailed architecture and design.

----

## Roadmap: Interactive Notebook (src/notebook/)

marimo-inspired reactive notebook system for MDX documents.

### Extended Syntax

```mdx
---
title: My Notebook
---

<Inline source="./intro.md" />

```moonbit {:cell=data}
let numbers = [1, 2, 3, 4, 5]
let sum = numbers.fold(init=0, fn(acc, x) { acc + x })
```

```js {:cell=viz :deps=data :output=html}
const chart = createChart(data.numbers);
chart.render();
```
```

### Code Block Attributes

| Attribute | Description |
|-----------|-------------|
| `:cell=name` | Name the cell for dependency tracking |
| `:deps=a,b` | Explicit dependencies on other cells |
| `:hide` | Hide source code, show only output |
| `:output=html\|json\|text` | Output format |
| `:exec` | Mark as executable (without cell name) |

### Inline Directive

```jsx
<Inline source="./path/to/file.md" section="#heading-id" recursive="false" />
```

### Implementation Status

- [x] Core types (Cell, Notebook, DependencyGraph)
- [x] Code block attribute parser (`:cell=`, `:deps=`, etc.)
- [x] Dependency analyzer (DAG, topological sort, cycle detection)
- [x] Markdown parser integration
- [x] Session API (execute, stale detection, JSON/HTML export)
- [x] JS FFI evaluator interface
- [ ] MoonBit code evaluator (compile & execute)
- [ ] Frontend editor component (React/Solid)
- [ ] Visualization components (Chart, Table, SVG)
- [ ] File watcher for `<Inline>` resolution
- [ ] REPL mode

### TODO

1. **MoonBit Evaluator**: Compile MoonBit cells to JS/WASM and execute
2. **Frontend Editor**: Interactive cell editing with Monaco/CodeMirror
3. **Visualization**: Built-in chart/table/svg components
4. **File Resolution**: Resolve `<Inline source="..."/>` at build time
5. **Export**: Generate static HTML or executable notebooks

----

## CommonMark Compatibility

This parser handles most common Markdown syntax correctly and works well for typical use cases like documentation, blog posts, and notes.

However, some edge cases (deeply nested structures, unusual delimiter combinations) are not fully CommonMark compliant. If you need strict CommonMark compliance, consider using [cmark.mbt](https://github.com/moonbit-community/cmark.mbt) or other fully compliant parsers.

## License

MIT
