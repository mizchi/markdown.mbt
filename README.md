# @mizchi/markdown

CST-based incremental Markdown parser for MoonBit.

A cross-platform (JS/WASM/native) Markdown compiler optimized for real-time editing with incremental parsing.

## CommonMark Compatibility

Implements a CommonMark subset, passing 207/542 tests. Most unsupported cases are edge cases with deeply nested structures that rarely occur in practice.

For full CommonMark compliance, consider [cmark.mbt](https://github.com/moonbit-community/cmark.mbt).

## Features

- **Lossless CST**: Preserves all whitespace, markers, and formatting
- **Incremental parsing**: Re-parses only changed blocks (up to 42x faster)
- **GFM compatible**: GitHub Flavored Markdown support (tables, task lists, strikethrough)
- **Cross-platform**: Works on JS, WASM-GC, and native targets
- **HTML rendering**: Built-in HTML renderer with remark-html compatible output

## JavaScript API

### Installation

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

### Edit Helpers

```javascript
import { insertEdit, deleteEdit, replaceEdit } from "@mizchi/markdown";

// Insert 6 chars at position 5
const insert = insertEdit(5, 6);

// Delete from position 5 to 10
const del = deleteEdit(5, 10);

// Replace positions 5-10 with 8 chars
const replace = replaceEdit(5, 10, 8);
```

### TypeScript Support

Full TypeScript definitions are included:

```typescript
import { parse, Document, Block, Inline } from "@mizchi/markdown";

const ast: Document = parse("# Hello");
const heading = ast.children[0] as HeadingBlock;
console.log(heading.level); // 1
```

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

### AST Types

```moonbit
// Block types
pub enum Block {
  Paragraph(span~, children~)
  Heading(span~, level~, children~)
  FencedCode(span~, info~, code~)
  Blockquote(span~, children~)
  BulletList(span~, items~, tight~)
  OrderedList(span~, start~, items~, tight~)
  ThematicBreak(span~)
  HtmlBlock(span~, html~)
  Table(span~, header~, alignments~, rows~)
  // ...
}

// Inline types
pub enum Inline {
  Text(span~, content~)
  Code(span~, content~)
  Emphasis(span~, children~)
  Strong(span~, children~)
  Link(span~, children~, url~, title~)
  Image(span~, alt~, url~, title~)
  // ...
}
```

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

## License

MIT
