///| FFI exports for JS/WASM targets

///| Document handles are opaque integers that reference internal state

// =============================================================================
// Internal State Management
// =============================================================================

///|
/// Stored document with source for incremental parsing
priv struct StoredDocument {
  result : ParseResult
  source : String
  wikilinks : Bool
}

///|
/// Global document storage (handle -> StoredDocument)
let documents : Map[Int, StoredDocument] = {}

///|
/// Next available handle ID (using Ref for mutability at top level)
let next_handle : Ref[Int] = Ref::new(1)

///|
/// Allocate a new handle for a document
fn alloc_handle(
  result : ParseResult,
  source : String,
  wikilinks? : Bool = false,
) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  documents[handle] = { result, source, wikilinks }
  handle
}

///|
/// Get stored document by handle
fn get_stored(handle : Int) -> StoredDocument? {
  documents.get(handle)
}

// =============================================================================
// Public FFI API
// =============================================================================

///| Parse markdown source and return a document handle

///|
/// Returns 0 on error
pub fn md_parse(source : String) -> Int {
  let result = parse(source)
  alloc_handle(result, source)
}

///|
/// Parse markdown source with wikilinks enabled and return a document handle
pub fn md_parse_with_wikilinks(source : String) -> Int {
  let result = parse(source, wikilinks=true)
  alloc_handle(result, source, wikilinks=true)
}

///| Render document to markdown string

///|
/// Returns empty string if handle is invalid
pub fn md_render_to_string(handle : Int) -> String {
  match get_stored(handle) {
    Some(stored) => serialize(stored.result.document)
    None => ""
  }
}

///| Parse incrementally with edit information

///|
/// Returns new document handle, or 0 on error
pub fn md_parse_incremental(
  handle : Int,
  new_source : String,
  change_start : Int,
  old_end : Int,
  new_end : Int,
) -> Int {
  match get_stored(handle) {
    Some(stored) => {
      let edit = EditInfo::replace(
        change_start,
        old_end - change_start,
        new_end - change_start,
      )
      let inc_result = parse_incremental(
        stored.result.document,
        stored.source,
        new_source,
        edit,
        wikilinks=stored.wikilinks,
      )
      let new_parse_result : ParseResult = {
        document: inc_result.document,
        definitions: stored.result.definitions,
      }
      alloc_handle(new_parse_result, new_source, wikilinks=stored.wikilinks)
    }
    None => 0
  }
}

///|
/// Free a document handle to release memory
pub fn md_free(handle : Int) -> Unit {
  documents.remove(handle)
}

///| Convenience: parse and immediately render (for roundtrip testing)

///|
/// When strict=true, uses full CommonMark compliance (slower)
pub fn md_parse_and_render(
  source : String,
  strict? : Bool = false,
  wikilinks? : Bool = false,
) -> String {
  let result = parse(source, strict~, wikilinks~)
  serialize(result.document)
}

///| Render document to HTML

///|
/// Returns empty string if handle is invalid
pub fn md_render_to_html(handle : Int) -> String {
  match get_stored(handle) {
    Some(stored) => render_html(stored.result.document)
    None => ""
  }
}
