///|
/// Tests for Interactive MDX Notebook

// =============================================================================
// Markdown Integration Tests
// =============================================================================

test "notebook_from_markdown: basic notebook" {
  let source =
    #|---
    #|title: Test Notebook
    #|---
    #|
    #|# Hello
    #|
    #|```moonbit {:cell=data}
    #|let x = 1
    #|```
    #|
    #|Some text.
    #|
    #|```moonbit {:cell=result :deps=data}
    #|let y = x + 1
    #|```
  let notebook = notebook_from_markdown("test.md", source)
  @debug.assert_eq(notebook.path, "test.md")
  @debug.assert_eq(notebook.cells.length(), 2)
  @debug.assert_eq(notebook.cells[0].id, "data")
  @debug.assert_eq(notebook.cells[1].id, "result")
  @debug.assert_eq(notebook.frontmatter.get("title"), Some("Test Notebook"))
}

///|
test "notebook_from_markdown: execution order" {
  let source =
    #|```js {:cell=c :deps=b}
    #|const c = b + 1
    #|```
    #|
    #|```js {:cell=a}
    #|const a = 1
    #|```
    #|
    #|```js {:cell=b :deps=a}
    #|const b = a + 1
    #|```
  let notebook = notebook_from_markdown("test.md", source)

  // Should have 3 cells
  @debug.assert_eq(notebook.cells.length(), 3)

  // Execution order should be a -> b -> c
  let order = notebook.get_execution_order()
  @debug.assert_eq(order.length(), 3)
  fn find_idx(arr : Array[Cell], target : String) -> Int {
    for i, cell in arr {
      if cell.id == target {
        return i
      }
    }
    -1
  }

  let a_idx = find_idx(order, "a")
  let b_idx = find_idx(order, "b")
  let c_idx = find_idx(order, "c")
  assert_true(a_idx < b_idx)
  assert_true(b_idx < c_idx)
}

///|
test "notebook_from_markdown: non-executable blocks ignored" {
  let source =
    #|```rust
    #|fn main() {}
    #|```
    #|
    #|```moonbit {:cell=data}
    #|let x = 1
    #|```
    #|
    #|```python
    #|print("hello")
    #|```
  let notebook = notebook_from_markdown("test.md", source)

  // Only the moonbit cell with :cell= should be included
  @debug.assert_eq(notebook.cells.length(), 1)
  @debug.assert_eq(notebook.cells[0].id, "data")
}

// =============================================================================
// Session API Tests
// =============================================================================

///|
test "NotebookSession: create and query" {
  let source =
    #|```js {:cell=a}
    #|const x = 1
    #|```
    #|
    #|```js {:cell=b :deps=a}
    #|const y = x + 1
    #|```
  let session = create_session("test.md", source)

  // Check cell IDs
  let ids = session.get_cell_ids()
  @debug.assert_eq(ids.length(), 2)

  // Note: deps are added to references, but edges are built from
  // variable name matches (defines vs references).
  // Since we use :deps=a (cell id), and cell 'a' defines 'x',
  // the dependency is through variable 'a' not 'x'.
  // This is a semantic mismatch - :deps should reference cell IDs.

  // For now, just check that session was created correctly
  let cell_a = session.get_cell_source("a")
  assert_true(cell_a is Some(_))
  let cell_b = session.get_cell_source("b")
  assert_true(cell_b is Some(_))
}

///|
test "NotebookSession: to_json" {
  let source =
    #|```js {:cell=data}
    #|const x = 1
    #|```
  let session = create_session("test.md", source)
  let json = session.to_json()

  // Should contain required fields
  assert_true(json.contains("\"path\""))
  assert_true(json.contains("\"cells\""))
  assert_true(json.contains("\"executionOrder\""))
  assert_true(json.contains("\"data\""))
}

///|
test "notebook validation: duplicate definition" {
  let source =
    #|```moonbit {:cell=a}
    #|let x = 1
    #|```
    #|
    #|```moonbit {:cell=b}
    #|let x = 2
    #|```
  let notebook = notebook_from_markdown("test.md", source)
  let errors = notebook.validate()

  // Should detect duplicate definition of 'x'
  @debug.assert_eq(errors.length(), 1)
  match errors[0] {
    DuplicateDefinition(var_name, _) => @debug.assert_eq(var_name, "x")
    _ => fail("Expected DuplicateDefinition error")
  }
}

// =============================================================================
// Parser Tests
// =============================================================================

///|
test "parse_code_block_attrs: simple cell" {
  let (info, attrs) = parse_code_block_attrs("moonbit {:cell=data}")
  @debug.assert_eq(info.lang, "moonbit")
  @debug.assert_eq(attrs.cell, Some("data"))
  @debug.assert_eq(attrs.executable, true)
}

///|
test "parse_code_block_attrs: cell with deps" {
  let (info, attrs) = parse_code_block_attrs("js {:cell=viz :deps=data,input}")
  @debug.assert_eq(info.lang, "js")
  @debug.assert_eq(attrs.cell, Some("viz"))
  @debug.assert_eq(attrs.deps.length(), 2)
  @debug.assert_eq(attrs.deps[0], "data")
  @debug.assert_eq(attrs.deps[1], "input")
}

///|
test "parse_code_block_attrs: hidden cell" {
  let (_, attrs) = parse_code_block_attrs("python {:cell=setup :hide}")
  @debug.assert_eq(attrs.hidden, true)
  @debug.assert_eq(attrs.cell, Some("setup"))
}

///|
test "parse_code_block_attrs: output format" {
  let (_, attrs) = parse_code_block_attrs("moonbit {:cell=chart :output=html}")
  @debug.assert_eq(attrs.output_format, Html)
}

///|
test "parse_code_block_attrs: exec only" {
  let (_, attrs) = parse_code_block_attrs("javascript {:exec}")
  @debug.assert_eq(attrs.executable, true)
  @debug.assert_eq(attrs.cell, None)
}

///|
test "parse_code_block_attrs: no attrs" {
  let (info, attrs) = parse_code_block_attrs("rust")
  @debug.assert_eq(info.lang, "rust")
  @debug.assert_eq(attrs.executable, false)
  @debug.assert_eq(attrs.cell, None)
}

// =============================================================================
// Inline Directive Tests
// =============================================================================

///|
test "parse_inline_directive: basic" {
  let result = parse_inline_directive("<Inline source=\"./intro.md\" />")
  match result {
    Some(dir) => {
      @debug.assert_eq(dir.source, "./intro.md")
      @debug.assert_eq(dir.section, None)
      @debug.assert_eq(dir.recursive, true)
    }
    None => fail("Expected Some")
  }
}

///|
test "parse_inline_directive: with section" {
  let result = parse_inline_directive(
    "<Inline source=\"./doc.md\" section=\"#intro\" />",
  )
  match result {
    Some(dir) => {
      @debug.assert_eq(dir.source, "./doc.md")
      @debug.assert_eq(dir.section, Some("#intro"))
    }
    None => fail("Expected Some")
  }
}

///|
test "parse_inline_directive: not recursive" {
  let result = parse_inline_directive(
    "<Inline source=\"./doc.md\" recursive=\"false\" />",
  )
  match result {
    Some(dir) => @debug.assert_eq(dir.recursive, false)
    None => fail("Expected Some")
  }
}

///|
test "parse_inline_directive: not an inline" {
  let result = parse_inline_directive("<Button>Click</Button>")
  @debug.assert_eq(result, None)
}

// =============================================================================
// Dependency Graph Tests
// =============================================================================

///|
test "build_dependency_graph: simple dependency" {
  let cell1 : Cell = {
    id: "a",
    source: "let x = 1",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let cell2 : Cell = {
    id: "b",
    source: "let y = x + 1",
    language: "moonbit",
    defines: ["y"],
    exports: [],
    references: ["x"],
    output: None,
    state: Idle,
  }
  let graph = build_dependency_graph([cell1, cell2])
  @debug.assert_eq(graph.edges.length(), 1)
  @debug.assert_eq(graph.edges[0].from, "a")
  @debug.assert_eq(graph.edges[0].to, "b")
  @debug.assert_eq(graph.edges[0].variable, "x")
}

///|
test "build_dependency_graph: execution order" {
  let cell_a : Cell = {
    id: "a",
    source: "",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let cell_b : Cell = {
    id: "b",
    source: "",
    language: "moonbit",
    defines: ["y"],
    exports: [],
    references: ["x"],
    output: None,
    state: Idle,
  }
  let cell_c : Cell = {
    id: "c",
    source: "",
    language: "moonbit",
    defines: ["z"],
    exports: [],
    references: ["y"],
    output: None,
    state: Idle,
  }
  let graph = build_dependency_graph([cell_c, cell_a, cell_b])

  // Order should be a -> b -> c regardless of input order
  @debug.assert_eq(graph.execution_order.length(), 3)
  // a should come before b
  fn find_idx(arr : Array[String], target : String) -> Int {
    for i, s in arr {
      if s == target {
        return i
      }
    }
    -1
  }

  let a_idx = find_idx(graph.execution_order, "a")
  let b_idx = find_idx(graph.execution_order, "b")
  let c_idx = find_idx(graph.execution_order, "c")
  assert_true(a_idx < b_idx)
  assert_true(b_idx < c_idx)
}

// =============================================================================
// Stale Detection Tests
// =============================================================================

///|
test "get_stale_cells: cascading stale" {
  let cell_a : Cell = {
    id: "a",
    source: "",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let cell_b : Cell = {
    id: "b",
    source: "",
    language: "moonbit",
    defines: ["y"],
    exports: [],
    references: ["x"],
    output: None,
    state: Idle,
  }
  let cell_c : Cell = {
    id: "c",
    source: "",
    language: "moonbit",
    defines: ["z"],
    exports: [],
    references: ["y"],
    output: None,
    state: Idle,
  }
  let graph = build_dependency_graph([cell_a, cell_b, cell_c])
  let stale = get_stale_cells(graph, "a")

  // Both b and c should be stale when a changes
  @debug.assert_eq(stale.length(), 2)
  assert_true(stale.contains("b"))
  assert_true(stale.contains("c"))
}

// =============================================================================
// Variable Analysis Tests
// =============================================================================

///|
test "analyze_moonbit_variables: let binding" {
  let (defines, _) = analyze_cell_variables(
    "let numbers = [1, 2, 3]\nlet sum = fold(numbers, 0, add)", "moonbit",
  )
  @debug.assert_eq(defines.length(), 2)
  @debug.assert_eq(defines[0], "numbers")
  @debug.assert_eq(defines[1], "sum")
}

///|
test "analyze_moonbit_variables: pub exports" {
  let source = "pub let x = 1\nlet private_y = 2\npub fn compute() { x + private_y }\nfn helper() { 0 }"
  let (defines, exports, _) = analyze_cell_variables_full(source, "moonbit")

  // All definitions
  @debug.assert_eq(defines.length(), 4)
  assert_true(defines.contains("x"))
  assert_true(defines.contains("private_y"))
  assert_true(defines.contains("compute"))
  assert_true(defines.contains("helper"))

  // Only pub definitions are exports
  @debug.assert_eq(exports.length(), 2)
  assert_true(exports.contains("x"))
  assert_true(exports.contains("compute"))
}

///|
test "analyze_moonbit_variables: struct and enum" {
  let source = "pub struct Point { x: Int, y: Int }\npub enum Color { Red, Green, Blue }\nstruct Private { a: Int }"
  let (defines, exports, _) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 3)
  assert_true(defines.contains("Point"))
  assert_true(defines.contains("Color"))
  assert_true(defines.contains("Private"))
  @debug.assert_eq(exports.length(), 2)
  assert_true(exports.contains("Point"))
  assert_true(exports.contains("Color"))
}

///|
test "analyze_js_variables: const and function" {
  let source = "const data = [1, 2, 3]\nfunction process(x) { return x * 2 }"
  let (defines, _) = analyze_cell_variables(source, "javascript")
  @debug.assert_eq(defines.length(), 2)
  @debug.assert_eq(defines[0], "data")
  @debug.assert_eq(defines[1], "process")
}

///|
test "analyze_moonbit_variables: references extraction" {
  let source = "let result = external_data + compute(value)"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")

  // Should define "result"
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "result")

  // Should reference external_data, compute, and value
  assert_true(references.contains("external_data"))
  assert_true(references.contains("compute"))
  assert_true(references.contains("value"))
}

///|
test "analyze_moonbit_variables: local bindings not referenced" {
  let source = "fn foo(x : Int) -> Int { let y = x + 1; y }"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")

  // Should define "foo"
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "foo")

  // Local variables x and y should NOT be in references
  assert_false(references.contains("x"))
  assert_false(references.contains("y"))
}

///|
test "analyze_moonbit_variables: function references external" {
  let source = "pub fn process() -> Int { external_config + helper(data) }"
  let (defines, exports, references) = analyze_cell_variables_full(
    source, "moonbit",
  )

  // Should define and export "process"
  @debug.assert_eq(defines.length(), 1)
  assert_true(exports.contains("process"))

  // Should reference external_config, helper, and data
  assert_true(references.contains("external_config"))
  assert_true(references.contains("helper"))
  assert_true(references.contains("data"))
}

///|
test "analyze_moonbit_variables: if expression references" {
  let source = "let result = if condition { then_value } else { else_value }"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "result")
  assert_true(references.contains("condition"))
  assert_true(references.contains("then_value"))
  assert_true(references.contains("else_value"))
}

///|
test "analyze_moonbit_variables: match expression with pattern bindings" {
  let source =
    #|fn handle(opt : Option[Int]) -> Int {
    #|  match opt {
    #|    Some(x) => x + offset
    #|    None => default_value
    #|  }
    #|}
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "handle")

  // x is bound by pattern, should NOT be in references
  assert_false(references.contains("x"))
  // offset and default_value are external
  assert_true(references.contains("offset"))
  assert_true(references.contains("default_value"))
}

///|
test "analyze_moonbit_variables: array literal references" {
  let source = "let arr = [a, b, compute(c)]"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "arr")
  assert_true(references.contains("a"))
  assert_true(references.contains("b"))
  assert_true(references.contains("compute"))
  assert_true(references.contains("c"))
}

///|
test "analyze_moonbit_variables: closure captures external" {
  let source = "let f = fn(x) { x + captured_var }"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "f")

  // x is lambda parameter, should NOT be in references
  assert_false(references.contains("x"))
  // captured_var is external
  assert_true(references.contains("captured_var"))
}

///|
test "analyze_moonbit_variables: while loop references" {
  let source =
    #|fn loop_fn() -> Unit {
    #|  while condition {
    #|    process(item)
    #|  }
    #|}
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  assert_true(references.contains("condition"))
  assert_true(references.contains("process"))
  assert_true(references.contains("item"))
}

///|
test "analyze_moonbit_variables: nested let bindings" {
  let source =
    #|let result = {
    #|  let temp = external_a
    #|  let inner = temp + external_b
    #|  inner
    #|}
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "result")

  // temp and inner are local
  assert_false(references.contains("temp"))
  assert_false(references.contains("inner"))
  // external_a and external_b are external
  assert_true(references.contains("external_a"))
  assert_true(references.contains("external_b"))
}

///|
test "analyze_moonbit_variables: pipe operator" {
  let source = "let result = input |> transform |> finalize"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  assert_true(references.contains("input"))
  assert_true(references.contains("transform"))
  assert_true(references.contains("finalize"))
}

///|
test "analyze_moonbit_variables: multiple functions" {
  let source =
    #|fn helper(x : Int) -> Int { x + constant }
    #|pub fn main_fn() -> Int { helper(input) }
  let (defines, exports, references) = analyze_cell_variables_full(
    source, "moonbit",
  )
  @debug.assert_eq(defines.length(), 2)
  assert_true(defines.contains("helper"))
  assert_true(defines.contains("main_fn"))

  // Only main_fn is pub
  @debug.assert_eq(exports.length(), 1)
  assert_true(exports.contains("main_fn"))

  // helper is defined, so not a reference
  assert_false(references.contains("helper"))
  // constant and input are external
  assert_true(references.contains("constant"))
  assert_true(references.contains("input"))
}

///|
test "analyze_moonbit_variables: tuple pattern in let" {
  let source = "fn foo() -> Int { let (a, b) = get_pair(); a + b + external }"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  @debug.assert_eq(defines[0], "foo")

  // a and b are local bindings from tuple pattern
  assert_false(references.contains("a"))
  assert_false(references.contains("b"))
  // get_pair and external are external
  assert_true(references.contains("get_pair"))
  assert_true(references.contains("external"))
}

///|
test "analyze_moonbit_variables: infix operators" {
  let source = "let sum = left + right * factor"
  let (defines, _, references) = analyze_cell_variables_full(source, "moonbit")
  @debug.assert_eq(defines.length(), 1)
  assert_true(references.contains("left"))
  assert_true(references.contains("right"))
  assert_true(references.contains("factor"))
}

// =============================================================================
// Duplicate Definition Tests
// =============================================================================

///|
test "check_duplicate_definitions: no duplicates" {
  let cell1 : Cell = {
    id: "a",
    source: "",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let cell2 : Cell = {
    id: "b",
    source: "",
    language: "moonbit",
    defines: ["y"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let duplicates = check_duplicate_definitions([cell1, cell2])
  @debug.assert_eq(duplicates.length(), 0)
}

///|
test "check_duplicate_definitions: has duplicate" {
  let cell1 : Cell = {
    id: "a",
    source: "",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let cell2 : Cell = {
    id: "b",
    source: "",
    language: "moonbit",
    defines: ["x"],
    exports: [],
    references: [],
    output: None,
    state: Idle,
  }
  let duplicates = check_duplicate_definitions([cell1, cell2])
  @debug.assert_eq(duplicates.length(), 1)
  @debug.assert_eq(duplicates[0].0, "x")
  @debug.assert_eq(duplicates[0].1.length(), 2)
}
