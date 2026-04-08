///| Notebook Builder

///|

///| Build a notebook from parsed Markdown document

// =============================================================================
// Notebook Building
// =============================================================================

///|
/// Extract cells from markdown code blocks
pub fn extract_cells_from_code_blocks(
  code_blocks : Array[(String, String)], // (info_string, content)
) -> Array[Cell] {
  let cells : Array[Cell] = []
  let mut cell_counter = 0
  for block in code_blocks {
    let (info_str, content) = block
    let (info, attrs) = parse_code_block_attrs(info_str)

    // Only create cells for executable code blocks
    if attrs.executable {
      let cell_id = match attrs.cell {
        Some(name) => name
        None => {
          cell_counter += 1
          "cell_\{cell_counter}"
        }
      }

      // Analyze variables in the code (with exports)
      let (defines, exports, references) = analyze_cell_variables_full(
        content,
        info.lang,
      )

      // Store explicit cell dependencies (from :deps=)
      // These will be used to build edges by cell ID
      cells.push({
        id: cell_id,
        source: content,
        language: info.lang,
        defines,
        exports,
        references: references.copy(), // Only variable references
        output: None,
        state: Idle,
      })
    }
  }
  cells
}

///|
/// Extract cell dependencies from code blocks (for building edges by cell ID)
fn extract_cell_deps(
  code_blocks : Array[(String, String)],
) -> Map[String, Array[String]] {
  let deps_map : Map[String, Array[String]] = {}
  for block in code_blocks {
    let (info_str, _) = block
    let (_, attrs) = parse_code_block_attrs(info_str)
    if attrs.executable {
      match attrs.cell {
        Some(cell_id) =>
          if attrs.deps.length() > 0 {
            deps_map[cell_id] = attrs.deps.copy()
          }
        None => ()
      }
    }
  }
  deps_map
}

///|
/// Build a complete notebook from code blocks
pub fn build_notebook(
  path : String,
  code_blocks : Array[(String, String)],
  frontmatter : Map[String, String],
) -> Notebook {
  let cells = extract_cells_from_code_blocks(code_blocks)
  let cell_deps = extract_cell_deps(code_blocks)

  // Build graph with both variable-based and explicit cell dependencies
  let graph = build_dependency_graph_with_cell_deps(cells, cell_deps)
  {
    path,
    cells,
    graph,
    inlines: [], // TODO: Extract inline directives from JSX
    frontmatter,
  }
}

// =============================================================================
// Notebook Operations
// =============================================================================

///|
/// Get cells in execution order
pub fn Notebook::get_execution_order(self : Notebook) -> Array[Cell] {
  let result : Array[Cell] = []
  for cell_id in self.graph.execution_order {
    for cell in self.cells {
      if cell.id == cell_id {
        result.push(cell)
        break
      }
    }
  }
  result
}

///|
/// Get a cell by ID
pub fn Notebook::get_cell(self : Notebook, id : String) -> Cell? {
  for cell in self.cells {
    if cell.id == id {
      return Some(cell)
    }
  }
  None
}

///|
/// Check for errors in the notebook
pub fn Notebook::validate(self : Notebook) -> Array[NotebookError] {
  let errors : Array[NotebookError] = []

  // Check for duplicate definitions
  let duplicates = check_duplicate_definitions(self.cells)
  for dup in duplicates {
    let (var_name, cell_ids) = dup
    errors.push(DuplicateDefinition(var_name, cell_ids))
  }

  // Check for cycles
  let cycles = detect_cycles(self.graph)
  for cycle in cycles {
    errors.push(CyclicDependency(cycle))
  }

  // Check for undefined references
  for cell in self.cells {
    for ref_var in cell.references {
      let mut found = false
      for other in self.cells {
        if other.defines.contains(ref_var) {
          found = true
          break
        }
      }
      if !(found) {
        errors.push(UndefinedReference(cell.id, ref_var))
      }
    }
  }
  errors
}

///|
/// Mark cells as stale after a cell is modified
pub fn Notebook::mark_stale_after_change(
  self : Notebook,
  changed_cell_id : String,
) -> Unit {
  let stale_ids = get_stale_cells(self.graph, changed_cell_id)
  for cell in self.cells {
    if stale_ids.contains(cell.id) {
      // Note: In real implementation, we'd need mutable cells
      // This is just to show the concept
      let _ = cell.id
      // Placeholder
    }
  }
}

// =============================================================================
// Error Types
// =============================================================================

///|
/// Notebook validation errors
pub(all) enum NotebookError {
  /// Variable defined in multiple cells
  DuplicateDefinition(String, Array[String])
  /// Circular dependency detected
  CyclicDependency(Array[String])
  /// Reference to undefined variable
  UndefinedReference(String, String)
} derive(Debug)

pub impl Show for NotebookError with output(
  self : NotebookError,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}
