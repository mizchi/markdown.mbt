///| Dependency Analyzer

///|

///| Build dependency graph from cells and compute execution order

///| Based on marimo's reactive execution model

// =============================================================================
// Dependency Graph Building
// =============================================================================

///|
/// Build dependency graph from cells
pub fn build_dependency_graph(cells : Array[Cell]) -> DependencyGraph {
  build_dependency_graph_with_cell_deps(cells, {})
}

///|
/// Build dependency graph with explicit cell dependencies
pub fn build_dependency_graph_with_cell_deps(
  cells : Array[Cell],
  cell_deps : Map[String, Array[String]],
) -> DependencyGraph {
  let graph = DependencyGraph::new()

  // Add all cells to the graph
  for cell in cells {
    graph.cells[cell.id] = cell
  }

  // Build edges based on variable references
  for cell in cells {
    for ref_var in cell.references {
      // Find which cell defines this variable
      for other in cells {
        if other.id != cell.id && other.defines.contains(ref_var) {
          graph.edges.push({ from: other.id, to: cell.id, variable: ref_var })
        }
      }
    }
  }

  // Build edges based on explicit cell dependencies (:deps=)
  for cell_id, deps in cell_deps {
    for dep_cell_id in deps {
      // Check if the dependency cell exists
      let mut dep_exists = false
      for cell in cells {
        if cell.id == dep_cell_id {
          dep_exists = true
          break
        }
      }
      if dep_exists {
        // Add edge from dependency to this cell
        // Use special variable name to indicate cell dependency
        let edge_exists = graph.edges
          .iter()
          .any(fn(e) { e.from == dep_cell_id && e.to == cell_id })
        if not(edge_exists) {
          graph.edges.push({
            from: dep_cell_id,
            to: cell_id,
            variable: "@cell:" + dep_cell_id,
          })
        }
      }
    }
  }

  // Compute topological order
  graph.execution_order = topological_sort(graph)
  graph
}

///|
/// Topological sort using Kahn's algorithm
fn topological_sort(graph : DependencyGraph) -> Array[String] {
  let in_degree : Map[String, Int] = {}
  let result : Array[String] = []

  // Initialize in-degree for all cells
  for id, _ in graph.cells {
    in_degree[id] = 0
  }

  // Count in-degrees
  for edge in graph.edges {
    in_degree[edge.to] = in_degree.get(edge.to).unwrap_or(0) + 1
  }

  // Queue of cells with no dependencies
  let queue : Array[String] = []
  for id, degree in in_degree {
    if degree == 0 {
      queue.push(id)
    }
  }

  // Process queue
  while queue.length() > 0 {
    let current = queue.remove(0)
    result.push(current)

    // Reduce in-degree of dependents
    for edge in graph.edges {
      if edge.from == current {
        in_degree[edge.to] = in_degree.get(edge.to).unwrap_or(1) - 1
        if in_degree.get(edge.to).unwrap_or(0) == 0 {
          queue.push(edge.to)
        }
      }
    }
  }
  result
}

// =============================================================================
// Cycle Detection
// =============================================================================

///|
/// Check for circular dependencies
pub fn detect_cycles(graph : DependencyGraph) -> Array[Array[String]] {
  let cycles : Array[Array[String]] = []
  let visited : Map[String, Bool] = {}
  let rec_stack : Map[String, Bool] = {}
  let path : Array[String] = []
  fn dfs(node : String) -> Bool {
    visited[node] = true
    rec_stack[node] = true
    path.push(node)
    for edge in graph.edges {
      if edge.from == node {
        let neighbor = edge.to
        if not(visited.get(neighbor).unwrap_or(false)) {
          if dfs(neighbor) {
            return true
          }
        } else if rec_stack.get(neighbor).unwrap_or(false) {
          // Found a cycle
          let cycle : Array[String] = []
          let mut found = false
          for n in path {
            if n == neighbor {
              found = true
            }
            if found {
              cycle.push(n)
            }
          }
          cycle.push(neighbor)
          cycles.push(cycle)
          return true
        }
      }
    }
    let _ = path.pop()
    rec_stack[node] = false
    false
  }

  for id, _ in graph.cells {
    if not(visited.get(id).unwrap_or(false)) {
      let _ = dfs(id)
    }
  }
  cycles
}

// =============================================================================
// Stale Detection
// =============================================================================

///|
/// Get cells that need re-execution after a cell changes
pub fn get_stale_cells(
  graph : DependencyGraph,
  changed_cell_id : String,
) -> Array[String] {
  let stale : Array[String] = []
  let visited : Map[String, Bool] = {}
  fn mark_stale(cell_id : String) {
    if visited.get(cell_id).unwrap_or(false) {
      return
    }
    visited[cell_id] = true
    stale.push(cell_id)

    // Mark all dependents as stale
    for edge in graph.edges {
      if edge.from == cell_id {
        mark_stale(edge.to)
      }
    }
  }

  // Mark all dependents of the changed cell
  for edge in graph.edges {
    if edge.from == changed_cell_id {
      mark_stale(edge.to)
    }
  }
  stale
}

// =============================================================================
// Variable Analysis
// =============================================================================

///| Analyze cell source to extract defined and referenced variables

///|
/// This is a simplified version - real implementation would use proper parsing
pub fn analyze_cell_variables(
  source : String,
  language : String,
) -> (Array[String], Array[String]) {
  let (defines, _, references) = analyze_cell_variables_full(source, language)
  (defines, references)
}

///| Analyze cell source to extract defines, exports, and references

///|
/// Returns (defines, exports, references)
pub fn analyze_cell_variables_full(
  source : String,
  language : String,
) -> (Array[String], Array[String], Array[String]) {
  match language {
    "moonbit" => analyze_moonbit_variables(source)
    "javascript" | "js" => {
      let (defines, references) = analyze_js_variables(source)
      // In JS, all top-level definitions are exports
      (defines, defines.copy(), references)
    }
    _ => ([], [], [])
  }
}

///| Analyze MoonBit code for variable definitions, exports, and references

///| Uses moonbitlang/parser for accurate parsing

///|
/// Returns (defines, exports, references)
fn analyze_moonbit_variables(
  source : String,
) -> (Array[String], Array[String], Array[String]) {
  let defines : Array[String] = []
  let exports : Array[String] = []
  let references : Array[String] = []

  // Parse source using moonbitlang/parser
  let (toplevel_list, _errors) = @parser.parse_string(source)

  // Extract definitions and references from AST
  for toplevel in toplevel_list {
    match toplevel {
      TopLetDef(binder~, vis~, expr~, ..) => {
        let name = binder.name
        if name.length() > 0 {
          defines.push(name)
          if is_pub_visibility(vis) {
            exports.push(name)
          }
        }
        // Extract references from the expression
        extract_refs_from_expr(expr, defines, references)
      }
      TopFuncDef(fun_decl~, decl_body~, ..) => {
        let name = fun_decl.name.name
        if name.length() > 0 {
          defines.push(name)
          if is_pub_visibility(fun_decl.vis) {
            exports.push(name)
          }
        }
        // Extract references from function body, with parameters as local bindings
        match decl_body {
          DeclBody(expr~, ..) => {
            let local_bindings = defines.copy()
            // Add function parameters to local scope
            match fun_decl.decl_params {
              Some(params) =>
                params.each(fn(param) {
                  match param {
                    Positional(binder~, ..) => local_bindings.push(binder.name)
                    Labelled(binder~, ..) => local_bindings.push(binder.name)
                    Optional(binder~, ..) => local_bindings.push(binder.name)
                    QuestionOptional(binder~, ..) =>
                      local_bindings.push(binder.name)
                    DiscardPositional(..) => ()
                  }
                })
              None => ()
            }
            extract_refs_from_expr(expr, local_bindings, references)
          }
          _ => ()
        }
      }
      TopTypeDef(type_decl) => {
        let name = type_decl.tycon
        if name.length() > 0 {
          defines.push(name)
          if is_pub_visibility(type_decl.type_vis) {
            exports.push(name)
          }
        }
      }
      TopTrait(trait_decl) => {
        let name = trait_decl.name.name
        if name.length() > 0 {
          defines.push(name)
          if is_pub_visibility(trait_decl.vis) {
            exports.push(name)
          }
        }
      }
      TopExpr(expr~, ..) => extract_refs_from_expr(expr, defines, references)
      _ => ()
    }
  }

  // Remove duplicates from references and filter out local defines
  let unique_refs : Array[String] = []
  for r in references {
    if not(unique_refs.contains(r)) && not(defines.contains(r)) {
      unique_refs.push(r)
    }
  }
  (defines, exports, unique_refs)
}

///| Extract variable references from an expression

///|
/// local_bindings tracks variables bound in the current scope
fn extract_refs_from_expr(
  expr : @syntax.Expr,
  local_bindings : Array[String],
  refs : Array[String],
) -> Unit {
  match expr {
    Ident(id~, ..) => {
      // Extract variable name from LongIdent
      let name = get_var_name(id)
      if name.length() > 0 && not(local_bindings.contains(name)) {
        refs.push(name)
      }
    }
    Apply(func~, args~, ..) => {
      extract_refs_from_expr(func, local_bindings, refs)
      for arg in args {
        extract_refs_from_expr(arg.value, local_bindings, refs)
      }
    }
    Infix(lhs~, rhs~, ..) => {
      extract_refs_from_expr(lhs, local_bindings, refs)
      extract_refs_from_expr(rhs, local_bindings, refs)
    }
    Unary(expr~, ..) => extract_refs_from_expr(expr, local_bindings, refs)
    Array(exprs~, ..) =>
      for e in exprs {
        extract_refs_from_expr(e, local_bindings, refs)
      }
    ArraySpread(elems~, ..) =>
      for elem in elems {
        match elem {
          Regular(e) => extract_refs_from_expr(e, local_bindings, refs)
          Spread(expr~, ..) =>
            extract_refs_from_expr(expr, local_bindings, refs)
        }
      }
    ArrayGet(array~, index~, ..) => {
      extract_refs_from_expr(array, local_bindings, refs)
      extract_refs_from_expr(index, local_bindings, refs)
    }
    ArraySet(array~, index~, value~, ..) => {
      extract_refs_from_expr(array, local_bindings, refs)
      extract_refs_from_expr(index, local_bindings, refs)
      extract_refs_from_expr(value, local_bindings, refs)
    }
    Tuple(exprs~, ..) =>
      for e in exprs {
        extract_refs_from_expr(e, local_bindings, refs)
      }
    If(cond~, ifso~, ifnot~, ..) => {
      extract_refs_from_expr(cond, local_bindings, refs)
      extract_refs_from_expr(ifso, local_bindings, refs)
      match ifnot {
        Some(e) => extract_refs_from_expr(e, local_bindings, refs)
        None => ()
      }
    }
    Let(pattern~, expr~, body~, ..) => {
      // First extract refs from the init expression
      extract_refs_from_expr(expr, local_bindings, refs)
      // Add pattern bindings to local scope
      let new_bindings = local_bindings.copy()
      extract_bindings_from_pattern(pattern, new_bindings)
      // Extract refs from body with new bindings
      extract_refs_from_expr(body, new_bindings, refs)
    }
    LetMut(binder~, expr~, body~, ..) => {
      extract_refs_from_expr(expr, local_bindings, refs)
      let new_bindings = local_bindings.copy()
      new_bindings.push(binder.name)
      extract_refs_from_expr(body, new_bindings, refs)
    }
    LetFn(name~, func~, body~, ..) => {
      let new_bindings = local_bindings.copy()
      new_bindings.push(name.name)
      extract_refs_from_func(func, new_bindings, refs)
      extract_refs_from_expr(body, new_bindings, refs)
    }
    Function(func~, ..) => extract_refs_from_func(func, local_bindings, refs)
    Sequence(exprs~, last_expr~, ..) => {
      for e in exprs {
        extract_refs_from_expr(e, local_bindings, refs)
      }
      extract_refs_from_expr(last_expr, local_bindings, refs)
    }
    Match(expr~, cases~, ..) => {
      extract_refs_from_expr(expr, local_bindings, refs)
      for case in cases {
        let new_bindings = local_bindings.copy()
        extract_bindings_from_pattern(case.pattern, new_bindings)
        extract_refs_from_expr(case.body, new_bindings, refs)
      }
    }
    While(loop_cond~, loop_body~, while_else~, ..) => {
      extract_refs_from_expr(loop_cond, local_bindings, refs)
      extract_refs_from_expr(loop_body, local_bindings, refs)
      match while_else {
        Some(e) => extract_refs_from_expr(e, local_bindings, refs)
        None => ()
      }
    }
    Field(record~, ..) => extract_refs_from_expr(record, local_bindings, refs)
    DotApply(self~, args~, ..) => {
      extract_refs_from_expr(self, local_bindings, refs)
      for arg in args {
        extract_refs_from_expr(arg.value, local_bindings, refs)
      }
    }
    Record(fields~, ..) =>
      for field in fields {
        extract_refs_from_expr(field.expr, local_bindings, refs)
      }
    RecordUpdate(record~, fields~, ..) => {
      extract_refs_from_expr(record, local_bindings, refs)
      for field in fields {
        extract_refs_from_expr(field.expr, local_bindings, refs)
      }
    }
    Assign(expr~, ..) => extract_refs_from_expr(expr, local_bindings, refs)
    Return(return_value~, ..) =>
      match return_value {
        Some(e) => extract_refs_from_expr(e, local_bindings, refs)
        None => ()
      }
    Constraint(expr~, ..) => extract_refs_from_expr(expr, local_bindings, refs)
    Pipe(lhs~, rhs~, ..) => {
      extract_refs_from_expr(lhs, local_bindings, refs)
      extract_refs_from_expr(rhs, local_bindings, refs)
    }
    Group(expr~, ..) => extract_refs_from_expr(expr, local_bindings, refs)
    _ => ()
  }
}

///|
/// Extract references from a function
fn extract_refs_from_func(
  func : @syntax.Func,
  local_bindings : Array[String],
  refs : Array[String],
) -> Unit {
  let new_bindings = local_bindings.copy()
  // Add function parameters to local scope
  for param in func.parameters {
    match param {
      @syntax.Positional(binder~, ..) => new_bindings.push(binder.name)
      @syntax.Labelled(binder~, ..) => new_bindings.push(binder.name)
      @syntax.Optional(binder~, ..) => new_bindings.push(binder.name)
      @syntax.QuestionOptional(binder~, ..) => new_bindings.push(binder.name)
      @syntax.DiscardPositional(..) => ()
    }
  }
  extract_refs_from_expr(func.body, new_bindings, refs)
}

///|
/// Extract binding names from a pattern
fn extract_bindings_from_pattern(
  pattern : @syntax.Pattern,
  bindings : Array[String],
) -> Unit {
  match pattern {
    Var(binder) => bindings.push(binder.name)
    Tuple(pats~, ..) =>
      for p in pats {
        extract_bindings_from_pattern(p, bindings)
      }
    Constr(args~, ..) =>
      match args {
        Some(arg_list) =>
          for arg in arg_list {
            extract_bindings_from_pattern(arg.pat, bindings)
          }
        None => ()
      }
    Record(fields~, ..) =>
      for field in fields {
        extract_bindings_from_pattern(field.pattern, bindings)
      }
    Constraint(pat~, ..) => extract_bindings_from_pattern(pat, bindings)
    Alias(pat~, alias_~, ..) => {
      bindings.push(alias_.name)
      extract_bindings_from_pattern(pat, bindings)
    }
    Or(pat1~, pat2~, ..) => {
      // In an or-pattern, bindings should be the same in both branches
      // We just extract from the first one
      extract_bindings_from_pattern(pat1, bindings)
      let _ = pat2
      // Acknowledge pat2 is intentionally unused
    }
    _ => ()
  }
}

///|
/// Get variable name from Var
fn get_var_name(v : @syntax.Var) -> String {
  match v.name {
    Ident(name~) => name
    Dot(id~, ..) => id // Use the identifier part, not the package
  }
}

///|
/// Check if visibility is pub
fn is_pub_visibility(vis : @syntax.Visibility) -> Bool {
  match vis {
    Pub(..) => true
    _ => false
  }
}

///|
/// Analyze JavaScript code for variable definitions and references
fn analyze_js_variables(source : String) -> (Array[String], Array[String]) {
  let defines : Array[String] = []
  let references : Array[String] = []
  let lines = split_lines(source)
  for line in lines {
    let trimmed = line.trim_start(chars=" \t").to_string()

    // const/let/var bindings
    for prefix in ["const ", "let ", "var "] {
      if trimmed.has_prefix(prefix) {
        let rest = trimmed.unsafe_substring(
          start=prefix.length(),
          end=trimmed.length(),
        )
        let name = extract_identifier(rest)
        if name.length() > 0 {
          defines.push(name)
        }
      }
    }

    // function declarations
    if trimmed.has_prefix("function ") {
      let rest = trimmed.unsafe_substring(start=9, end=trimmed.length())
      let name = extract_identifier(rest)
      if name.length() > 0 {
        defines.push(name)
      }
    }
  }
  (defines, references)
}

///|
/// Extract identifier from string start
fn extract_identifier(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for i, c in chars {
    if i == 0 {
      if is_ident_start(c) {
        buf.write_char(c)
      } else {
        break
      }
    } else if is_ident_char(c) {
      buf.write_char(c)
    } else {
      break
    }
  }
  buf.to_string()
}

///|
/// Check if character can start an identifier
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Check if character can be part of an identifier
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
/// Split string into lines
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  let chars = s.to_array()
  for c in chars {
    if c == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else if c != '\r' {
      buf.write_char(c)
    }
  }
  if buf.to_string().length() > 0 {
    result.push(buf.to_string())
  }
  result
}

// =============================================================================
// Duplicate Definition Check
// =============================================================================

///|
/// Check for duplicate variable definitions (marimo's single-definition rule)
pub fn check_duplicate_definitions(
  cells : Array[Cell],
) -> Array[(String, Array[String])] {
  let var_to_cells : Map[String, Array[String]] = {}

  // Collect all definitions
  for cell in cells {
    for var_name in cell.defines {
      match var_to_cells.get(var_name) {
        Some(arr) => arr.push(cell.id)
        None => var_to_cells[var_name] = [cell.id]
      }
    }
  }

  // Find duplicates
  let duplicates : Array[(String, Array[String])] = []
  for var_name, cell_ids in var_to_cells {
    if cell_ids.length() > 1 {
      duplicates.push((var_name, cell_ids))
    }
  }
  duplicates
}
