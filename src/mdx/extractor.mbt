///| MDX Metadata Extractor
///|
///| Extracts metadata (imports, exports, components) from parsed MDX documents

// =============================================================================
// Metadata Extraction API
// =============================================================================

///|
/// Extract all MDX metadata from a document
/// Returns imports, exports, and component names used
pub fn extract_mdx_metadata(doc : @markdown.Document) -> MdxMetadata {
  let imports : Array[MdxBlock] = []
  let exports : Array[MdxBlock] = []
  let components : Array[String] = []
  let seen_components : Array[String] = []

  let blocks = parse_mdx_blocks(doc)

  for block in blocks {
    match block {
      ImportDecl(..) => imports.push(block)
      ExportDecl(..) => exports.push(block)
      JsxElement(tag~, ..) => {
        // Add component name if not already seen
        if not(array_contains(seen_components, tag)) {
          seen_components.push(tag)
          components.push(tag)
        }
      }
    }
  }

  { imports, exports, components }
}

///|
/// Extract only import declarations
pub fn extract_imports(doc : @markdown.Document) -> Array[MdxBlock] {
  let blocks = parse_mdx_blocks(doc)
  let result : Array[MdxBlock] = []

  for block in blocks {
    match block {
      ImportDecl(..) => result.push(block)
      _ => ()
    }
  }

  result
}

///|
/// Extract only export declarations
pub fn extract_exports(doc : @markdown.Document) -> Array[MdxBlock] {
  let blocks = parse_mdx_blocks(doc)
  let result : Array[MdxBlock] = []

  for block in blocks {
    match block {
      ExportDecl(..) => result.push(block)
      _ => ()
    }
  }

  result
}

///|
/// Extract all JSX/Web Component elements
pub fn extract_jsx_elements(doc : @markdown.Document) -> Array[MdxBlock] {
  let blocks = parse_mdx_blocks(doc)
  let result : Array[MdxBlock] = []

  for block in blocks {
    match block {
      JsxElement(..) => result.push(block)
      _ => ()
    }
  }

  result
}

///|
/// Get all unique component names used in the document
pub fn extract_component_names(doc : @markdown.Document) -> Array[String] {
  let blocks = parse_mdx_blocks(doc)
  let names : Array[String] = []

  for block in blocks {
    match block {
      JsxElement(tag~, ..) => {
        if not(array_contains(names, tag)) {
          names.push(tag)
        }
      }
      _ => ()
    }
  }

  names
}

///|
/// Get import sources (module paths)
pub fn extract_import_sources(doc : @markdown.Document) -> Array[String] {
  let blocks = parse_mdx_blocks(doc)
  let sources : Array[String] = []

  for block in blocks {
    match block {
      ImportDecl(source~, ..) => {
        if not(array_contains(sources, source)) {
          sources.push(source)
        }
      }
      _ => ()
    }
  }

  sources
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn array_contains(arr : Array[String], item : String) -> Bool {
  for s in arr {
    if s == item {
      return true
    }
  }
  false
}

