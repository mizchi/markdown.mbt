///| JavaScript Runtime Evaluator

///|

///| Evaluate JavaScript/MoonBit code cells via external runtime

///| This module provides FFI bindings for JS-based evaluation

// =============================================================================
// JS FFI Declarations (for wasm-gc/js target)
// =============================================================================

///|
/// Evaluate oJavaScript code and return result as string
#warnings("-1")
extern "js" fn js_eval_code(code : String) -> String =
  #|(code) => {
  #|  try {
  #|    const result = eval(code);
  #|    return JSON.stringify(result);
  #|  } catch (e) {
  #|    return JSON.stringify({ error: e.message });
  #|  }
  #|}

///| Execute JavaScript code with context variables

///|
/// Returns JSON: { result, exports: { name: value } } or { error: "..." }
extern "js" fn js_eval_with_context(
  code : String,
  context_json : String,
  exports_list : String,
) -> String =
  #|(code, contextJson, exportsList) => {
  #|  try {
  #|    const context = JSON.parse(contextJson);
  #|    const exportNames = JSON.parse(exportsList);
  #|    const contextCode = Object.entries(context)
  #|      .map(([k, v]) => `const ${k} = ${JSON.stringify(v)};`)
  #|      .join('\n');
  #|    const result = eval(contextCode + '\n' + code);
  #|
  #|    // Extract exports
  #|    const exports = {};
  #|    for (const name of exportNames) {
  #|      try {
  #|        exports[name] = eval(name);
  #|      } catch (e) {
  #|        // Export not available
  #|      }
  #|    }
  #|
  #|    return JSON.stringify({ result, exports });
  #|  } catch (e) {
  #|    return JSON.stringify({ error: e.message });
  #|  }
  #|}

// =============================================================================
// JavaScript Evaluator
// =============================================================================

///|
/// Create a JavaScript evaluator function
pub fn create_js_evaluator() -> (String, EvalContext) -> CellOutput {
  fn eval_js(source : String, context : EvalContext) -> CellOutput {
    // Analyze source to get exports
    let (defines, _, _) = analyze_cell_variables_full(source, "javascript")
    let exports_json = array_to_json(defines)

    // Build context JSON
    let context_json = build_context_json(context)

    // Evaluate via JS FFI
    let result = js_eval_with_context(source, context_json, exports_json)

    // Parse result
    parse_eval_result(result)
  }

  eval_js
}

///|
/// Build JSON string from evaluation context
fn build_context_json(context : EvalContext) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{")
  let mut first = true
  for key, value in context.variables {
    if !(first) {
      buf.write_string(",")
    }
    first = false
    buf.write_string("\"")
    buf.write_string(key)
    buf.write_string("\":")
    buf.write_string("\"")
    buf.write_string(value)
    buf.write_string("\"")
  }
  buf.write_string("}")
  buf.to_string()
}

///|
/// Parse evaluation result from JSON
fn parse_eval_result(json : String) -> CellOutput {
  // Simple JSON parsing for result
  if json.contains("\"error\"") {
    // Extract error message
    match extract_json_field(json, "error") {
      Some(msg) => Error(msg)
      None => Error("Unknown error")
    }
  } else {
    // Return as JSON output
    Json(json)
  }
}

///|
/// Extract field value from simple JSON object
fn extract_json_field(json : String, field : String) -> String? {
  let pattern = "\"" + field + "\":"
  match json.find(pattern) {
    Some(start) => {
      let value_start = start + pattern.length()
      let chars = json.to_array()

      // Skip whitespace
      let mut pos = value_start
      while pos < chars.length() && (chars[pos] == ' ' || chars[pos] == '\t') {
        pos += 1
      }
      if pos >= chars.length() {
        return None
      }

      // Check if string value
      if chars[pos] == '"' {
        pos += 1
        let buf = StringBuilder::new()
        while pos < chars.length() && chars[pos] != '"' {
          if chars[pos] == '\\' && pos + 1 < chars.length() {
            pos += 1
            buf.write_char(chars[pos])
          } else {
            buf.write_char(chars[pos])
          }
          pos += 1
        }
        return Some(buf.to_string())
      }
      None
    }
    None => None
  }
}

// =============================================================================
// MoonBit Compiler FFI
// =============================================================================

///| Compile MoonBit code to JavaScript (external service)

///|
/// Returns JSON: { "success": true, "js": "..." } or { "success": false, "error": "..." }
extern "js" fn moonbit_compile_to_js(
  source : String,
  exports_json : String,
) -> String =
  #|(source, exportsJson) => {
  #|  // This is a placeholder that would call an external compile service
  #|  // In real implementation, this would:
  #|  // 1. POST to a compile server OR
  #|  // 2. Use a WASM-compiled moonc
  #|
  #|  if (typeof window !== 'undefined' && window.__moonbit_compile) {
  #|    return window.__moonbit_compile(source, exportsJson);
  #|  }
  #|
  #|  // Fallback: return a mock implementation
  #|  return JSON.stringify({
  #|    success: false,
  #|    error: "MoonBit compiler not available. Set window.__moonbit_compile to enable."
  #|  });
  #|}

///|
/// Execute compiled JavaScript with context
extern "js" fn execute_compiled_moonbit(
  compiled_js : String,
  context_json : String,
  exports_list : String,
) -> String =
  #|(compiledJs, contextJson, exportsList) => {
  #|  try {
  #|    const context = JSON.parse(contextJson);
  #|    const exports = JSON.parse(exportsList);
  #|
  #|    // Build context code to inject variables
  #|    const contextCode = Object.entries(context)
  #|      .map(([k, v]) => `const ${k} = ${JSON.stringify(v)};`)
  #|      .join('\n');
  #|
  #|    // Execute the compiled code
  #|    const fullCode = contextCode + '\n' + compiledJs;
  #|    const result = eval(fullCode);
  #|
  #|    // Extract exports
  #|    const exportedValues = {};
  #|    for (const name of exports) {
  #|      try {
  #|        exportedValues[name] = eval(name);
  #|      } catch (e) {
  #|        // Export not available
  #|      }
  #|    }
  #|
  #|    return JSON.stringify({
  #|      success: true,
  #|      result: result !== undefined ? result : null,
  #|      exports: exportedValues
  #|    });
  #|  } catch (e) {
  #|    return JSON.stringify({
  #|      success: false,
  #|      error: e.message
  #|    });
  #|  }
  #|}

// =============================================================================
// MoonBit Evaluator
// =============================================================================

///| Create a MoonBit evaluator function

///|
/// Uses external compiler service if available
pub fn create_moonbit_evaluator() -> (String, EvalContext) -> CellOutput {
  fn eval_moonbit(source : String, context : EvalContext) -> CellOutput {
    // First, analyze the source to get exports
    let (_, exports, _) = analyze_cell_variables_full(source, "moonbit")
    let exports_json = array_to_json(exports)

    // Try to compile
    let compile_result = moonbit_compile_to_js(source, exports_json)

    // Parse compile result
    if compile_result.contains("\"success\":true") {
      // Get compiled JS
      match extract_json_field(compile_result, "js") {
        Some(compiled_js) => {
          // Execute compiled code with context
          let context_json = build_context_json(context)
          let exec_result = execute_compiled_moonbit(
            compiled_js, context_json, exports_json,
          )

          // Parse execution result
          if exec_result.contains("\"success\":true") {
            match extract_json_field(exec_result, "result") {
              Some(result) => Text(result)
              None => Text("(no output)")
            }
          } else {
            match extract_json_field(exec_result, "error") {
              Some(err) => Error("Runtime error: " + err)
              None => Error("Unknown runtime error")
            }
          }
        }
        None => Error("Compile succeeded but no JS returned")
      }
    } else {
      // Compilation failed or not available
      match extract_json_field(compile_result, "error") {
        Some(err) => Error("Compile error: " + err)
        None =>
          // Return source preview when compiler not available
          Text("[MoonBit - compiler not available]\n" + source)
      }
    }
  }

  eval_moonbit
}

///|
/// Convert string array to JSON array string
fn array_to_json(arr : Array[String]) -> String {
  let buf = StringBuilder::new()
  buf.write_string("[")
  for i, s in arr {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("\"")
    buf.write_string(escape_json_string(s))
    buf.write_string("\"")
  }
  buf.write_string("]")
  buf.to_string()
}

///|
/// Escape special characters in JSON string
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
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
  buf.to_string()
}

// =============================================================================
// Engine Setup
// =============================================================================

///|
/// Create an evaluation engine with JS and MoonBit support
pub fn create_notebook_engine() -> EvalEngine {
  let engine = EvalEngine::new()
  engine.register("javascript", create_js_evaluator())
  engine.register("js", create_js_evaluator())
  engine.register("moonbit", create_moonbit_evaluator())
  engine
}
