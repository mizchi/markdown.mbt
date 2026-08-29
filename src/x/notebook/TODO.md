# notebook TODO

## Done

- [x] Core types (Cell, Notebook, DependencyGraph, CellOutput, CellState)
- [x] Code block attribute parser (`:cell=`, `:deps=`, `:hide`, `:output=`, `:exec`)
- [x] Inline directive parser (`<Inline source="..." />`)
- [x] Dependency analyzer
  - [x] DAG construction from variable references
  - [x] Explicit cell dependencies (`:deps=`)
  - [x] Topological sort (Kahn's algorithm)
  - [x] Cycle detection
  - [x] Stale cell detection
  - [x] Duplicate definition check (single-definition rule)
- [x] Variable analysis (simple let/const/var/function detection)
- [x] Markdown parser integration
  - [x] Extract code blocks from Document
  - [x] Extract frontmatter
  - [x] Build notebook from markdown
- [x] NotebookSession API
  - [x] `create_session(path, source)`
  - [x] `execute_cell(cell_id)`
  - [x] `execute_all()`
  - [x] `execute_stale(changed_cell_id)`
  - [x] `get_cell_ids()`, `get_cell_source()`, `get_cell_deps()`, `get_cell_dependents()`
  - [x] `validate()` - returns errors
  - [x] `to_json()` - serialize state
  - [x] `render_html()` - render outputs
- [x] JS FFI evaluator interface
- [x] 38 tests passing

---

## In Progress

### MoonBit Evaluator
- [x] Parse MoonBit code to extract exports (`analyze_cell_variables_full`)
- [x] Cell struct `exports` field for tracking pub definitions
- [x] Compiler FFI interface (`moonbit_compile_to_js`, `execute_compiled_moonbit`)
- [x] Cell-to-cell variable passing (`extract_exports_from_output`)
- [x] Integrated moonbitlang/parser for accurate variable extraction
- [ ] Integrate with actual MoonBit compiler (requires external service or WASM moonc)

---

## TODO

### P0: Core Functionality

#### Variable Analysis Enhancement
- [x] Proper MoonBit parser integration for variable extraction (using moonbitlang/parser)
- [x] Handle `pub` exports (Visibility enum matching)
- [x] Track function parameters vs global references
- [x] Extract variable references from expressions (AST traversal)
- [ ] Handle destructuring patterns (`let (a, b) = ...`) - TopLetDef only has single Binder

#### Cell Execution
- [ ] Implement actual MoonBit evaluation (via moon build + eval)
- [ ] Implement Python evaluator (via pyodide or external process)
- [ ] Cell timeout handling
- [ ] Error recovery (continue execution after cell failure)

#### Output Types
- [ ] Rich output: images, plots, tables
- [ ] Streaming output for long-running cells
- [ ] Interactive widgets (sliders, dropdowns)

### P1: File System Integration

#### Inline Resolution
- [ ] Resolve `<Inline source="..."/>` at parse time
- [ ] Relative path resolution from notebook path
- [ ] Section extraction (`section="#heading-id"`)
- [ ] Recursive inline expansion
- [ ] Circular reference detection

#### File Watching
- [ ] Watch inlined files for changes
- [ ] Hot reload on file change
- [ ] Dependency tracking for external files

### P2: Frontend

#### Editor Component
- [ ] React/Solid component wrapper
- [ ] Monaco/CodeMirror integration for code cells
- [ ] Cell add/delete/reorder UI
- [ ] Keyboard navigation (Ctrl+Enter to run, etc.)
- [ ] Cell status indicators (idle, running, success, error, stale)

#### Visualization
- [ ] Built-in `<Chart>` component (via Chart.js or similar)
- [ ] Built-in `<Table>` component with sorting/filtering
- [ ] SVG rendering for custom visualizations
- [ ] Mermaid diagram support

#### Theming
- [ ] Light/dark mode
- [ ] Syntax highlighting themes
- [ ] Custom CSS injection

### P3: Export & Deployment

#### Static Export
- [ ] Export to standalone HTML (all outputs pre-rendered)
- [ ] Export to PDF
- [ ] Export to Markdown (strip cell metadata)

#### Interactive Export
- [ ] Export with embedded runtime (WASM)
- [ ] Export as web component

### P4: Advanced Features

#### Collaboration
- [ ] CRDT-based real-time editing
- [ ] Conflict resolution for concurrent edits
- [ ] Presence indicators

#### Version Control
- [ ] Cell-level git diff
- [ ] Notebook checkpoints
- [ ] Undo/redo per cell

#### REPL Mode
- [ ] Interactive shell with notebook context
- [ ] Auto-complete from defined variables
- [ ] Inline documentation

---

## Architecture Notes

### Repository Separation

When extracting to separate repository:

1. Dependencies to carry:
   - `mizchi/markdown` (or make it a peer dependency)
   - `mizchi/markdown/info_string`

2. New repository structure:
   ```
   notebook/
   ├── src/
   │   ├── core/          # types, analyzer, parser
   │   ├── runtime/       # evaluators (moonbit, js, python)
   │   ├── integration/   # markdown parser integration
   │   └── api/           # public API
   ├── frontend/          # React/Solid components
   └── examples/
   ```

3. Consider making markdown parser optional (accept pre-parsed AST)

### Performance Considerations

- [ ] Lazy cell parsing (parse only when needed)
- [ ] Incremental DAG updates (don't rebuild entire graph on change)
- [ ] Worker-based evaluation (don't block main thread)
- [ ] Cell output caching (skip re-evaluation if input unchanged)
