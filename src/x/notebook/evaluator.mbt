///| Code Evaluator Interface

///|

///| Interface for evaluating code cells in various languages

///| Actual evaluation would be handled by external runtimes

// =============================================================================
// Evaluator Trait
// =============================================================================

///|
/// Interface for code evaluators
pub trait Evaluator {
  /// Evaluate code and return output
  eval(Self, source : String, context : EvalContext) -> CellOutput

  /// Get the language this evaluator handles
  language(Self) -> String

  /// Check if this evaluator can handle the given language
  can_handle(Self, lang : String) -> Bool
}

// =============================================================================
// Evaluation Result
// =============================================================================

///|
/// Result of cell evaluation
pub(all) struct EvalResult {
  /// The cell that was evaluated
  cell_id : String
  /// Output from evaluation
  output : CellOutput
  /// Variables exported by this cell
  exports : Map[String, String]
  /// Execution time in milliseconds
  duration_ms : Double
}

///|
pub fn EvalResult::new(cell_id : String, output : CellOutput) -> EvalResult {
  { cell_id, output, exports: {}, duration_ms: 0.0 }
}

// =============================================================================
// Evaluation Engine
// =============================================================================

///|
/// Engine for evaluating notebook cells
pub(all) struct EvalEngine {
  /// Available evaluators by language
  evaluators : Map[String, (String, EvalContext) -> CellOutput]
  /// Current execution context
  context : EvalContext
}

///|
pub fn EvalEngine::new() -> EvalEngine {
  { evaluators: {}, context: EvalContext::new() }
}

///|
/// Register an evaluator for a language
pub fn EvalEngine::register(
  self : EvalEngine,
  language : String,
  evaluator : (String, EvalContext) -> CellOutput,
) -> Unit {
  self.evaluators[language] = evaluator
}

///|
/// Evaluate a single cell
pub fn EvalEngine::eval_cell(self : EvalEngine, cell : Cell) -> EvalResult {
  let evaluator = self.evaluators.get(cell.language)
  let output = match evaluator {
    Some(eval_fn) => eval_fn(cell.source, self.context)
    None => Error("No evaluator registered for language: \{cell.language}")
  }
  EvalResult::new(cell.id, output)
}

///|
/// Evaluate all cells in a notebook in dependency order
pub fn EvalEngine::eval_notebook(
  self : EvalEngine,
  notebook : Notebook,
) -> Array[EvalResult] {
  let results : Array[EvalResult] = []

  // Execute cells in topological order
  for cell in notebook.get_execution_order() {
    let result = self.eval_cell(cell)

    // Update context with cell outputs
    self.context.outputs[cell.id] = result.output

    // Extract exports from result and store in context for dependent cells
    let exports = extract_exports_from_output(result.output, cell.exports)
    for name, value in exports {
      self.context.variables[name] = value
      result.exports[name] = value
    }
    results.push(result)
  }
  results
}

///| Extract exported values from cell output

///|
/// The output may be Json containing { exports: { name: value } }
fn extract_exports_from_output(
  output : CellOutput,
  export_names : Array[String],
) -> Map[String, String] {
  let exports : Map[String, String] = {}
  match output {
    Json(json_str) =>
      // Try to extract exports object from JSON result
      for name in export_names {
        match extract_nested_json_field(json_str, "exports", name) {
          Some(value) => exports[name] = value
          None => ()
        }
      }
    _ => ()
  }
  exports
}

///|
/// Extract nested field from JSON: obj.field1.field2
fn extract_nested_json_field(
  json : String,
  parent : String,
  child : String,
) -> String? {
  // Find exports object
  let exports_pattern = "\"" + parent + "\":"
  match json.find(exports_pattern) {
    Some(start) => {
      let rest_start = start + exports_pattern.length()
      let rest = json.unsafe_substring(start=rest_start, end=json.length())

      // Find the child field within exports
      let child_pattern = "\"" + child + "\":"
      match rest.find(child_pattern) {
        Some(child_start) => {
          let value_start = child_start + child_pattern.length()
          extract_json_value_at(rest, value_start)
        }
        None => None
      }
    }
    None => None
  }
}

///|
/// Extract JSON value starting at given position
fn extract_json_value_at(json : String, start : Int) -> String? {
  let chars = json.to_array()
  let mut pos = start

  // Skip whitespace
  while pos < chars.length() && (chars[pos] == ' ' || chars[pos] == '\t') {
    pos = pos + 1
  }
  if pos >= chars.length() {
    return None
  }
  let c = chars[pos]

  // String value
  if c == '"' {
    pos = pos + 1
    let buf = StringBuilder::new()
    while pos < chars.length() && chars[pos] != '"' {
      if chars[pos] == '\\' && pos + 1 < chars.length() {
        pos = pos + 1
        buf.write_char(chars[pos])
      } else {
        buf.write_char(chars[pos])
      }
      pos = pos + 1
    }
    return Some(buf.to_string())
  }

  // Number value
  if (c >= '0' && c <= '9') || c == '-' {
    let buf = StringBuilder::new()
    while pos < chars.length() &&
          (
            (chars[pos] >= '0' && chars[pos] <= '9') ||
            chars[pos] == '.' ||
            chars[pos] == '-' ||
            chars[pos] == 'e' ||
            chars[pos] == 'E'
          ) {
      buf.write_char(chars[pos])
      pos = pos + 1
    }
    return Some(buf.to_string())
  }

  // Boolean or null
  if json.unsafe_substring(start=pos, end=pos + 4) == "true" {
    return Some("true")
  }
  if json.unsafe_substring(start=pos, end=pos + 5) == "false" {
    return Some("false")
  }
  if json.unsafe_substring(start=pos, end=pos + 4) == "null" {
    return Some("null")
  }
  None
}

///|
/// Re-evaluate stale cells after a change
pub fn EvalEngine::eval_stale(
  self : EvalEngine,
  notebook : Notebook,
  changed_cell_id : String,
) -> Array[EvalResult] {
  let results : Array[EvalResult] = []
  let stale_ids = get_stale_cells(notebook.graph, changed_cell_id)

  // First, re-evaluate the changed cell
  match notebook.get_cell(changed_cell_id) {
    Some(cell) => {
      let result = self.eval_cell(cell)
      self.context.outputs[cell.id] = result.output
      results.push(result)
    }
    None => ()
  }

  // Then evaluate stale cells in order
  for cell in notebook.get_execution_order() {
    if stale_ids.contains(cell.id) {
      let result = self.eval_cell(cell)
      self.context.outputs[cell.id] = result.output
      results.push(result)
    }
  }
  results
}

// =============================================================================
// Output Rendering
// =============================================================================

///|
/// Render cell output to HTML
pub fn render_output_to_html(output : CellOutput) -> String {
  match output {
    Text(s) => "<pre class=\"cell-output text\">\{escape_html(s)}</pre>"
    Html(s) => "<div class=\"cell-output html\">\{s}</div>"
    Json(s) => "<pre class=\"cell-output json\">\{escape_html(s)}</pre>"
    Error(s) => "<pre class=\"cell-output error\">\{escape_html(s)}</pre>"
    Multi(outputs) => {
      let buf = StringBuilder::new()
      buf.write_string("<div class=\"cell-output multi\">")
      for out in outputs {
        buf.write_string(render_output_to_html(out))
      }
      buf.write_string("</div>")
      buf.to_string()
    }
  }
}

///|
/// Escape HTML special characters
fn escape_html(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    match c {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}
