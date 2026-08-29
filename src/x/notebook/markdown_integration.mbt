///| Markdown Integration

///|

///| Build notebooks from parsed Markdown documents

// =============================================================================
// Extract Code Blocks from Markdown
// =============================================================================

///|
/// Extract code blocks from a parsed Markdown document
pub fn extract_code_blocks_from_document(
  doc : @markdown.Document,
) -> Array[(String, String)] {
  let blocks : Array[(String, String)] = []
  extract_from_blocks(doc.children, blocks)
  blocks
}

///|
/// Recursively extract code blocks from block array
fn extract_from_blocks(
  children : Array[@markdown.Block],
  result : Array[(String, String)],
) -> Unit {
  for block in children {
    match block {
      @markdown.Block::FencedCode(info~, code~, ..) => result.push((info, code))
      @markdown.Block::Blockquote(children~, ..) =>
        extract_from_blocks(children, result)
      @markdown.Block::BulletList(items~, ..) =>
        for item in items {
          extract_from_blocks(item.children, result)
        }
      @markdown.Block::OrderedList(items~, ..) =>
        for item in items {
          extract_from_blocks(item.children, result)
        }
      _ => ()
    }
  }
}

///|
/// Extract frontmatter as key-value pairs
pub fn extract_frontmatter(doc : @markdown.Document) -> Map[String, String] {
  let result : Map[String, String] = {}
  match doc.frontmatter {
    Some(fm) =>
      // Use parsed entries from frontmatter
      for entry in fm.entries {
        let (key, value) = entry
        result[key] = value
      }
    None => ()
  }
  result
}

///|
/// Build a complete notebook from a Markdown document
pub fn notebook_from_document(
  path : String,
  doc : @markdown.Document,
) -> Notebook {
  let code_blocks = extract_code_blocks_from_document(doc)
  let frontmatter = extract_frontmatter(doc)
  build_notebook(path, code_blocks, frontmatter)
}

///|
/// Parse markdown string and build notebook
pub fn notebook_from_markdown(path : String, source : String) -> Notebook {
  let result = @markdown.parse(source)
  notebook_from_document(path, result.document)
}

// =============================================================================
// Extract Inline Directives from JSX
// =============================================================================

///|
/// Extract inline directives from a document
pub fn extract_inlines_from_document(
  doc : @markdown.Document,
) -> Array[InlineDirective] {
  let inlines : Array[InlineDirective] = []
  extract_inlines_from_blocks(doc.children, inlines)
  inlines
}

///|
/// Recursively extract inline directives from blocks
fn extract_inlines_from_blocks(
  children : Array[@markdown.Block],
  result : Array[InlineDirective],
) -> Unit {
  for block in children {
    match block {
      @markdown.Block::Paragraph(children~, ..) =>
        extract_inlines_from_inlines(children, result)
      @markdown.Block::Blockquote(children~, ..) =>
        extract_inlines_from_blocks(children, result)
      @markdown.Block::BulletList(items~, ..) =>
        for item in items {
          extract_inlines_from_blocks(item.children, result)
        }
      @markdown.Block::OrderedList(items~, ..) =>
        for item in items {
          extract_inlines_from_blocks(item.children, result)
        }
      _ => ()
    }
  }
}

///|
/// Extract inline directives from inline elements
fn extract_inlines_from_inlines(
  children : Array[@markdown.Inline],
  result : Array[InlineDirective],
) -> Unit {
  for inline in children {
    match inline {
      @markdown.Inline::HtmlInline(html~, ..) =>
        match parse_inline_directive(html) {
          Some(dir) => result.push(dir)
          None => ()
        }
      @markdown.Inline::Emphasis(children~, ..) =>
        extract_inlines_from_inlines(children, result)
      @markdown.Inline::Strong(children~, ..) =>
        extract_inlines_from_inlines(children, result)
      @markdown.Inline::Link(children~, ..) =>
        extract_inlines_from_inlines(children, result)
      _ => ()
    }
  }
}
