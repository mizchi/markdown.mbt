///| FFI exports for AST access

///|
/// Global document storage for AST access
let ast_documents : Map[Int, @markdown.Document] = {}

///|
/// Next available handle ID
let ast_next_handle : Ref[Int] = Ref::new(1)

///|
/// Parse markdown and return handle for AST access
pub fn md_parse_to_ast(source : String) -> Int {
  let result = @markdown.parse(source)
  let handle = ast_next_handle.val
  ast_next_handle.val = handle + 1
  ast_documents[handle] = result.document
  handle
}

///| Get AST as JSON string from handle

///|
/// Returns empty string if handle is invalid
pub fn md_get_ast(handle : Int) -> String {
  match ast_documents.get(handle) {
    Some(doc) => document_to_json(doc)
    None => ""
  }
}

///|
/// Free AST handle
pub fn md_free_ast(handle : Int) -> Unit {
  ast_documents.remove(handle)
}

// =============================================================================
// Stateless One-shot APIs (no handle management needed)
// =============================================================================

///|
/// Parse markdown and return HTML directly
pub fn md_to_html(source : String) -> String {
  @markdown.md_to_html(source)
}

///|
/// Parse markdown and return serialized markdown (normalized)
pub fn md_to_markdown(source : String) -> String {
  let result = @markdown.parse(source)
  @markdown.serialize(result.document)
}

///|
/// Parse markdown and return JSON AST directly (no handle)
pub fn md_to_ast_json(source : String) -> String {
  let result = @markdown.parse(source)
  document_to_json(result.document)
}

// =============================================================================
// Handle-based APIs with HTML/Serialize support
// =============================================================================

///|
/// Render handle's document to HTML
pub fn md_render_html(handle : Int) -> String {
  match ast_documents.get(handle) {
    Some(doc) => @markdown.render_html(doc)
    None => ""
  }
}

///|
/// Serialize handle's document back to markdown
pub fn md_serialize(handle : Int) -> String {
  match ast_documents.get(handle) {
    Some(doc) => @markdown.serialize(doc)
    None => ""
  }
}

// =============================================================================
// Incremental Parsing API
// =============================================================================

///|
/// Stored source for incremental parsing
let ast_sources : Map[Int, String] = {}

///|
/// Parse markdown and store source for incremental updates
pub fn md_parse_with_source(source : String) -> Int {
  let result = @markdown.parse(source)
  let handle = ast_next_handle.val
  ast_next_handle.val = handle + 1
  ast_documents[handle] = result.document
  ast_sources[handle] = source
  handle
}

///|
/// Parse incrementally from an existing handle
/// Returns new handle with updated document
pub fn md_parse_incremental(
  handle : Int,
  new_source : String,
  change_start : Int,
  old_end : Int,
  new_end : Int,
) -> Int {
  match (ast_documents.get(handle), ast_sources.get(handle)) {
    (Some(doc), Some(old_source)) => {
      let edit = @markdown.EditInfo::replace(
        change_start,
        old_end - change_start,
        new_end - change_start,
      )
      let inc_result = @markdown.parse_incremental(
        doc,
        old_source,
        new_source,
        edit,
      )
      let new_handle = ast_next_handle.val
      ast_next_handle.val = new_handle + 1
      ast_documents[new_handle] = inc_result.document
      ast_sources[new_handle] = new_source
      new_handle
    }
    _ => 0
  }
}

///|
/// Free handle and its source
pub fn md_free(handle : Int) -> Unit {
  ast_documents.remove(handle)
  ast_sources.remove(handle)
}
