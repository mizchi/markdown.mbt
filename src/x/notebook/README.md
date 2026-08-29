# @mizchi/markdown/notebook

marimo-inspired reactive notebook system for MDX documents.

> **Note**: This module is designed to be extracted into a separate repository in the future.

## Dependencies

- `mizchi/markdown` - Markdown parser (for parsing notebook documents)
- `mizchi/markdown/info_string` - Code block info string parser

## Module Structure

```
src/notebook/
├── types.mbt              # Cell, Notebook, DependencyGraph types
├── parser.mbt             # Code block attribute parser (:cell=, :deps=)
├── analyzer.mbt           # DAG builder, topological sort, cycle detection
├── notebook.mbt           # Notebook builder from code blocks
├── markdown_integration.mbt # Integration with markdown parser
├── evaluator.mbt          # Code evaluation interface
├── js_evaluator.mbt       # JavaScript FFI evaluator
├── api.mbt                # Public API (NotebookSession)
└── notebook_test.mbt      # Tests
```

## Usage

```moonbit
// Create session from markdown
let session = @notebook.create_session("notebook.md", source)

// Execute all cells in dependency order
let results = session.execute_all()

// Re-execute stale cells after change
let stale = session.execute_stale("changed_cell_id")

// Export
let json = session.to_json()
let html = session.render_html()
```

## Extended Syntax

### Code Block Attributes

```markdown
```moonbit {:cell=data :deps=input :hide :output=html}
let result = compute(input)
```
```

| Attribute | Description |
|-----------|-------------|
| `:cell=name` | Name the cell for dependency tracking |
| `:deps=a,b` | Explicit dependencies on other cells |
| `:hide` | Hide source code in output |
| `:output=html\|json\|text` | Output format |
| `:exec` | Mark as executable without naming |

### Inline Directive

```jsx
<Inline source="./path/to/file.md" section="#heading" recursive="false" />
```

## Architecture

Based on [marimo](https://marimo.io/)'s reactive execution model:

1. **Static Analysis**: Extract variable definitions and references from code
2. **DAG Construction**: Build dependency graph from variable relationships
3. **Topological Execution**: Execute cells in dependency order
4. **Stale Detection**: Mark dependent cells as stale when source changes
5. **Single Definition Rule**: Each variable can only be defined in one cell

## Future Plans

- [ ] MoonBit code evaluator (compile to JS/WASM)
- [ ] Interactive editor UI
- [ ] Visualization components
- [ ] File resolution for `<Inline>`
- [ ] REPL mode
