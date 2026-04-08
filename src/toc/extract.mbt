// Table of Contents Extraction
// Extract TOC from Block CST

///|
/// Extract table of contents from Document
pub fn extract_from_document(doc : @md.Document) -> Array[TocItem] {
  extract_from_blocks(doc.children)
}

///|
/// Extract table of contents from Block array
pub fn extract_from_blocks(blocks : Array[@md.Block]) -> Array[TocItem] {
  let toc : Array[TocItem] = []
  collect_toc_items(blocks, toc)
  toc
}

///|
/// Extract headings recursively
fn collect_toc_items(blocks : Array[@md.Block], toc : Array[TocItem]) -> Unit {
  for block in blocks {
    match block {
      @md.Block::Heading(level~, children~, ..) if should_include_heading(level) =>
        toc.push(build_toc_item(level, children))
      @md.Block::Blockquote(children~, ..) => collect_toc_items(children, toc)
      @md.Block::BulletList(items~, ..) | @md.Block::OrderedList(items~, ..) =>
        items.each(fn(item) { collect_toc_items(item.children, toc) })
      _ => ()
    }
  }
}

///|
fn should_include_heading(level : Int) -> Bool {
  level >= 2 && level <= 4
}

///|
fn build_toc_item(level : Int, children : Array[@md.Inline]) -> TocItem {
  let text = extract_text_from_inlines(children)
  TocItem::{ level, text, id: @slug.generate_heading_id(text) }
}

// =============================================================================
// Text Extraction from Inline CST
// =============================================================================

///|
/// Extract plain text from Inline array
pub fn extract_text_from_inlines(inlines : Array[@md.Inline]) -> String {
  let buf = StringBuilder::new()
  append_inline_texts(inlines, buf)
  buf.to_string()
}

///|
/// Extract text recursively
fn append_inline_texts(inlines : Array[@md.Inline], buf : StringBuilder) -> Unit {
  for inline in inlines {
    append_inline_text(inline, buf)
  }
}

///|
fn append_inline_text(inline : @md.Inline, buf : StringBuilder) -> Unit {
  match inline {
    @md.Inline::Text(content~, ..) | @md.Inline::Code(content~, ..) =>
      buf.write_string(content)
    @md.Inline::SoftBreak(..) => buf.write_string(" ")
    @md.Inline::HardBreak(..) => buf.write_string("\n")
    @md.Inline::Emphasis(children~, ..)
    | @md.Inline::Strong(children~, ..)
    | @md.Inline::Strikethrough(children~, ..)
    | @md.Inline::Link(children~, ..)
    | @md.Inline::RefLink(children~, ..) => append_inline_texts(children, buf)
    @md.Inline::Autolink(url~, ..) => buf.write_string(url)
    @md.Inline::Image(alt~, ..) | @md.Inline::RefImage(alt~, ..) =>
      buf.write_string(alt)
    @md.Inline::HtmlInline(..) => () // Skip HTML
    @md.Inline::FootnoteReference(label~, ..) => buf.write_string("[^\{label}]")
  }
}
