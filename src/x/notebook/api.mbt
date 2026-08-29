///| Public API for Interactive Notebook

///|

///| Exported functions for use from JavaScript/external systems

// =============================================================================
// Notebook Session
// =============================================================================

///|
/// A running notebook session
pub(all) struct NotebookSession {
  notebook : Notebook
  engine : EvalEngine
  /// Cell outputs by ID
  outputs : Map[String, CellOutput]
}

///|
pub fn NotebookSession::new(notebook : Notebook) -> NotebookSession {
  { notebook, engine: create_notebook_engine(), outputs: {} }
}

///|
/// Create a session from markdown source
pub fn create_session(path : String, source : String) -> NotebookSession {
  let notebook = notebook_from_markdown(path, source)
  NotebookSession::new(notebook)
}

// =============================================================================
// Cell Execution API
// =============================================================================

///|
/// Execute a single cell by ID
pub fn NotebookSession::execute_cell(
  self : NotebookSession,
  cell_id : String,
) -> CellOutput? {
  match self.notebook.get_cell(cell_id) {
    Some(cell) => {
      let result = self.engine.eval_cell(cell)
      self.outputs[cell_id] = result.output
      Some(result.output)
    }
    None => None
  }
}

///|
/// Execute all cells in dependency order
pub fn NotebookSession::execute_all(
  self : NotebookSession,
) -> Array[(String, CellOutput)] {
  let results : Array[(String, CellOutput)] = []
  for cell in self.notebook.get_execution_order() {
    let result = self.engine.eval_cell(cell)
    self.outputs[cell.id] = result.output
    results.push((cell.id, result.output))
  }
  results
}

///|
/// Re-execute stale cells after a cell change
pub fn NotebookSession::execute_stale(
  self : NotebookSession,
  changed_cell_id : String,
) -> Array[(String, CellOutput)] {
  let results = self.engine.eval_stale(self.notebook, changed_cell_id)
  let output : Array[(String, CellOutput)] = []
  for result in results {
    self.outputs[result.cell_id] = result.output
    output.push((result.cell_id, result.output))
  }
  output
}

///|
/// Get output for a cell
pub fn NotebookSession::get_output(
  self : NotebookSession,
  cell_id : String,
) -> CellOutput? {
  self.outputs.get(cell_id)
}

// =============================================================================
// Query API
// =============================================================================

///|
/// Get all cell IDs in execution order
pub fn NotebookSession::get_cell_ids(self : NotebookSession) -> Array[String] {
  self.notebook.graph.execution_order.copy()
}

///|
/// Get cell source by ID
pub fn NotebookSession::get_cell_source(
  self : NotebookSession,
  cell_id : String,
) -> String? {
  match self.notebook.get_cell(cell_id) {
    Some(cell) => Some(cell.source)
    None => None
  }
}

///|
/// Get dependencies of a cell
pub fn NotebookSession::get_cell_deps(
  self : NotebookSession,
  cell_id : String,
) -> Array[String] {
  let deps : Array[String] = []
  for edge in self.notebook.graph.edges {
    if edge.to == cell_id {
      deps.push(edge.from)
    }
  }
  deps
}

///|
/// Get dependents of a cell (cells that depend on this one)
pub fn NotebookSession::get_cell_dependents(
  self : NotebookSession,
  cell_id : String,
) -> Array[String] {
  let dependents : Array[String] = []
  for edge in self.notebook.graph.edges {
    if edge.from == cell_id {
      dependents.push(edge.to)
    }
  }
  dependents
}

///|
/// Validate notebook and get errors
pub fn NotebookSession::validate(
  self : NotebookSession,
) -> Array[NotebookError] {
  self.notebook.validate()
}

// =============================================================================
// Serialization
// =============================================================================

///|
/// Serialize notebook state to JSON
pub fn NotebookSession::to_json(self : NotebookSession) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{")

  // Path
  buf.write_string("\"path\":")
  buf.write_string(json_string(self.notebook.path))
  buf.write_string(",")

  // Cells
  buf.write_string("\"cells\":[")
  for i, cell in self.notebook.cells {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{")
    buf.write_string("\"id\":")
    buf.write_string(json_string(cell.id))
    buf.write_string(",\"language\":")
    buf.write_string(json_string(cell.language))
    buf.write_string(",\"source\":")
    buf.write_string(json_string(cell.source))
    buf.write_string(",\"defines\":")
    buf.write_string(json_array(cell.defines))
    buf.write_string(",\"references\":")
    buf.write_string(json_array(cell.references))
    buf.write_string("}")
  }
  buf.write_string("],")

  // Execution order
  buf.write_string("\"executionOrder\":")
  buf.write_string(json_array(self.notebook.graph.execution_order))
  buf.write_string(",")

  // Edges
  buf.write_string("\"dependencies\":[")
  for i, edge in self.notebook.graph.edges {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("{\"from\":")
    buf.write_string(json_string(edge.from))
    buf.write_string(",\"to\":")
    buf.write_string(json_string(edge.to))
    buf.write_string(",\"variable\":")
    buf.write_string(json_string(edge.variable))
    buf.write_string("}")
  }
  buf.write_string("]")
  buf.write_string("}")
  buf.to_string()
}

///|
/// Escape and quote string for JSON
fn json_string(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("\"")
  let chars = s.to_array()
  for c in chars {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.write_string("\"")
  buf.to_string()
}

///|
/// Convert string array to JSON array
fn json_array(arr : Array[String]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[")
  for i, s in arr {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(json_string(s))
  }
  buf.write_string("]")
  buf.to_string()
}

// =============================================================================
// Render API
// =============================================================================

///|
/// Render all cell outputs to HTML
pub fn NotebookSession::render_html(self : NotebookSession) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<div class=\"notebook\">")
  for cell in self.notebook.get_execution_order() {
    buf.write_string("<div class=\"cell\" data-id=\"")
    buf.write_string(cell.id)
    buf.write_string("\">")

    // Cell source
    buf.write_string("<pre class=\"cell-source\"><code class=\"language-")
    buf.write_string(cell.language)
    buf.write_string("\">")
    buf.write_string(escape_html_content(cell.source))
    buf.write_string("</code></pre>")

    // Cell output
    match self.outputs.get(cell.id) {
      Some(output) => buf.write_string(render_output_to_html(output))
      None => ()
    }
    buf.write_string("</div>")
  }
  buf.write_string("</div>")
  buf.to_string()
}

///|
/// Escape HTML content
fn escape_html_content(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    match c {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}
