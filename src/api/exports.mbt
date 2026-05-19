///| FFI exports for AST access.

// =============================================================================
// Internal handle storage
// =============================================================================

///|
/// Per-handle state. `source` is populated only when the caller intends to do
/// incremental parsing later; one-shot AST handles leave it as `""`.
priv struct AstEntry {
  document : @markdown.Document
  source : String
  has_source : Bool
  wikilinks : Bool
}

///|
let ast_store : Map[Int, AstEntry] = {}

///|
let ast_next_handle : Ref[Int] = { val: 1 }

///|
/// Allocate a new handle for the given entry and store it.
fn alloc_handle(entry : AstEntry) -> Int {
  let handle = ast_next_handle.val
  ast_next_handle.val = handle + 1
  ast_store[handle] = entry
  handle
}

///|
/// Render a handle to a string by applying `f` to its document.
/// Returns the empty string for invalid handles.
fn with_doc(handle : Int, f : (@markdown.Document) -> String) -> String {
  match ast_store.get(handle) {
    Some(entry) => f(entry.document)
    None => ""
  }
}

// =============================================================================
// AST handle APIs
// =============================================================================

///|
/// Parse markdown and return handle for AST access
pub fn md_parse_to_ast(source : String) -> Int {
  let result = @markdown.parse(source)
  alloc_handle({
    document: result.document,
    source: "",
    has_source: false,
    wikilinks: false,
  })
}

///|
/// Get AST as JSON string from handle. Returns empty string if handle is invalid.
pub fn md_get_ast(handle : Int) -> String {
  with_doc(handle, document_to_json)
}

///|
/// Free AST handle
pub fn md_free_ast(handle : Int) -> Unit {
  ast_store.remove(handle)
}

// =============================================================================
// Stateless one-shot APIs (no handle management needed)
// =============================================================================

///|
/// Parse markdown and return HTML directly
pub fn md_to_html(source : String) -> String {
  @markdown.md_to_html(source)
}

///|
/// Parse markdown with bare URL autolinks enabled and return HTML directly
pub fn md_to_html_with_autolink(source : String) -> String {
  @markdown.md_to_html(source, autolink=true)
}

///|
/// Parse markdown with bare URL autolinks disabled and return HTML directly
pub fn md_to_html_without_autolink(source : String) -> String {
  @markdown.md_to_html(source, autolink=false)
}

///|
/// Parse markdown with wikilinks enabled and return HTML directly
pub fn md_to_html_with_wikilinks(source : String) -> String {
  @markdown.md_to_html(source, wikilinks=true)
}

///|
/// Parse markdown with wikilinks and bare URL autolinks enabled and return HTML directly
pub fn md_to_html_with_wikilinks_and_autolink(source : String) -> String {
  @markdown.md_to_html(source, wikilinks=true, autolink=true)
}

///|
/// Parse markdown with wikilinks enabled and bare URL autolinks disabled.
pub fn md_to_html_with_wikilinks_without_autolink(source : String) -> String {
  @markdown.md_to_html(source, wikilinks=true, autolink=false)
}

///|
/// Parse markdown and return serialized markdown (normalized)
pub fn md_to_markdown(source : String) -> String {
  let result = @markdown.parse(source)
  @markdown.serialize(result.document)
}

///|
/// Parse markdown with wikilinks enabled and return serialized markdown.
pub fn md_to_markdown_with_wikilinks(source : String) -> String {
  let result = @markdown.parse(source, wikilinks=true)
  @markdown.serialize(result.document)
}

///|
/// Parse markdown and return JSON AST directly (no handle)
pub fn md_to_ast_json(source : String) -> String {
  let result = @markdown.parse(source)
  document_to_json(result.document)
}

///|
/// Parse markdown with wikilinks enabled and return JSON AST directly.
pub fn md_to_ast_json_with_wikilinks(source : String) -> String {
  let result = @markdown.parse(source, wikilinks=true)
  document_to_json(result.document)
}

///|
/// Parse markdown and render using the source-preserving "literal" mode.
/// The visible text of the output (HTML tags stripped, basic character
/// references decoded) equals the lossless serialization of the parsed
/// document.
///
/// `flags` is a bitmask over `LITERAL_WIKILINKS` (1), `LITERAL_POSITIONS`
/// (2) and `LITERAL_IMAGE_PREVIEW` (4). Pass `0` for the default
/// behavior; OR the constants together for combinations.
pub fn md_to_html_literal(source : String, flags : Int) -> String {
  let wikilinks = (flags & 1) != 0
  let positions = (flags & 2) != 0
  let image_preview = (flags & 4) != 0
  @markdown.md_to_html_literal(source, wikilinks~, positions~, image_preview~)
}

// =============================================================================
// Handle-based render APIs
// =============================================================================

///|
/// Render handle's document to HTML
pub fn md_render_html(handle : Int) -> String {
  with_doc(handle, fn(doc) { @markdown.render_html(doc) })
}

///|
/// Render handle's document to HTML with bare URL autolinks enabled
pub fn md_render_html_with_autolink(handle : Int) -> String {
  with_doc(handle, fn(doc) { @markdown.render_html(doc, autolink=true) })
}

///|
/// Render handle's document to HTML with bare URL autolinks disabled
pub fn md_render_html_without_autolink(handle : Int) -> String {
  with_doc(handle, fn(doc) { @markdown.render_html(doc, autolink=false) })
}

///|
/// Serialize handle's document back to markdown
pub fn md_serialize(handle : Int) -> String {
  with_doc(handle, @markdown.serialize)
}

// =============================================================================
// Incremental parsing API
// =============================================================================

///|
/// Parse markdown and store source for incremental updates
pub fn md_parse_with_source(source : String) -> Int {
  let result = @markdown.parse(source)
  alloc_handle({
    document: result.document,
    source,
    has_source: true,
    wikilinks: false,
  })
}

///|
/// Parse markdown with wikilinks enabled and store source for incremental updates
pub fn md_parse_with_source_with_wikilinks(source : String) -> Int {
  let result = @markdown.parse(source, wikilinks=true)
  alloc_handle({
    document: result.document,
    source,
    has_source: true,
    wikilinks: true,
  })
}

///|
/// Parse incrementally from an existing handle.
/// Returns new handle with updated document, or 0 if the handle is invalid
/// or was not registered for incremental updates.
pub fn md_parse_incremental(
  handle : Int,
  new_source : String,
  change_start : Int,
  old_end : Int,
  new_end : Int,
) -> Int {
  match ast_store.get(handle) {
    Some(entry) if entry.has_source => {
      let edit = @markdown.EditInfo::replace(
        change_start,
        old_end - change_start,
        new_end - change_start,
      )
      let inc_result = @markdown.parse_incremental(
        entry.document,
        entry.source,
        new_source,
        edit,
        wikilinks=entry.wikilinks,
      )
      alloc_handle({
        document: inc_result.document,
        source: new_source,
        has_source: true,
        wikilinks: entry.wikilinks,
      })
    }
    _ => 0
  }
}

///|
/// Free handle and its source
pub fn md_free(handle : Int) -> Unit {
  ast_store.remove(handle)
}
