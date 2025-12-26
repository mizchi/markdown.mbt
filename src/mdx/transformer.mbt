///| MDX Transformer
///|
///| Provides APIs for transforming MDX documents:
///| - Strip MDX blocks (imports/exports/JSX)
///| - Transform specific elements

// =============================================================================
// Block Stripping API
// =============================================================================

///|
/// Strip all MDX blocks from a document
/// Returns a new document with only pure Markdown content
pub fn strip_mdx_blocks(doc : @markdown.Document) -> @markdown.Document {
  let mdx_blocks = parse_mdx_blocks(doc)
  let mdx_spans = collect_mdx_spans(mdx_blocks)

  let new_children : Array[@markdown.Block] = []

  for block in doc.children {
    let block_span = get_block_span(block)
    if not(span_in_list(block_span, mdx_spans)) {
      new_children.push(block)
    }
  }

  { frontmatter: doc.frontmatter, children: new_children, span: doc.span }
}

///|
/// Strip only import declarations
pub fn strip_imports(doc : @markdown.Document) -> @markdown.Document {
  let blocks = parse_mdx_blocks(doc)
  let import_spans : Array[@markdown.Span] = []

  for block in blocks {
    match block {
      ImportDecl(span~, ..) => import_spans.push(span)
      _ => ()
    }
  }

  let new_children : Array[@markdown.Block] = []

  for block in doc.children {
    let block_span = get_block_span(block)
    if not(span_in_list(block_span, import_spans)) {
      new_children.push(block)
    }
  }

  { frontmatter: doc.frontmatter, children: new_children, span: doc.span }
}

///|
/// Strip only export declarations
pub fn strip_exports(doc : @markdown.Document) -> @markdown.Document {
  let blocks = parse_mdx_blocks(doc)
  let export_spans : Array[@markdown.Span] = []

  for block in blocks {
    match block {
      ExportDecl(span~, ..) => export_spans.push(span)
      _ => ()
    }
  }

  let new_children : Array[@markdown.Block] = []

  for block in doc.children {
    let block_span = get_block_span(block)
    if not(span_in_list(block_span, export_spans)) {
      new_children.push(block)
    }
  }

  { frontmatter: doc.frontmatter, children: new_children, span: doc.span }
}

///|
/// Strip only JSX elements
pub fn strip_jsx_elements(doc : @markdown.Document) -> @markdown.Document {
  let blocks = parse_mdx_blocks(doc)
  let jsx_spans : Array[@markdown.Span] = []

  for block in blocks {
    match block {
      JsxElement(span~, ..) => jsx_spans.push(span)
      _ => ()
    }
  }

  let new_children : Array[@markdown.Block] = []

  for block in doc.children {
    let block_span = get_block_span(block)
    if not(span_in_list(block_span, jsx_spans)) {
      new_children.push(block)
    }
  }

  { frontmatter: doc.frontmatter, children: new_children, span: doc.span }
}

// =============================================================================
// Transformation API
// =============================================================================

///|
/// Transform MDX blocks using a custom transformer
/// - If transformer returns Some(block), replaces the MDX block with it
/// - If transformer returns None, removes the block
/// - Non-MDX blocks pass through unchanged
pub fn transform_mdx(
  doc : @markdown.Document,
  transformer : (MdxBlock) -> @markdown.Block?
) -> @markdown.Document {
  let mdx_blocks = parse_mdx_blocks(doc)
  let mdx_map = build_span_to_mdx_map(mdx_blocks)

  let new_children : Array[@markdown.Block] = []

  for block in doc.children {
    let block_span = get_block_span(block)

    match find_mdx_for_span(mdx_map, block_span) {
      Some(mdx_block) => {
        match transformer(mdx_block) {
          Some(new_block) => new_children.push(new_block)
          None => ()  // Remove the block
        }
      }
      None => new_children.push(block)  // Keep non-MDX blocks
    }
  }

  { frontmatter: doc.frontmatter, children: new_children, span: doc.span }
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
fn collect_mdx_spans(blocks : Array[MdxBlock]) -> Array[@markdown.Span] {
  let spans : Array[@markdown.Span] = []
  for block in blocks {
    spans.push(block.span())
  }
  spans
}

///|
fn get_block_span(block : @markdown.Block) -> @markdown.Span {
  match block {
    @markdown.Block::Paragraph(span~, ..) => span
    @markdown.Block::Heading(span~, ..) => span
    @markdown.Block::FencedCode(span~, ..) => span
    @markdown.Block::IndentedCode(span~, ..) => span
    @markdown.Block::ThematicBreak(span~, ..) => span
    @markdown.Block::Blockquote(span~, ..) => span
    @markdown.Block::BulletList(span~, ..) => span
    @markdown.Block::OrderedList(span~, ..) => span
    @markdown.Block::HtmlBlock(span~, ..) => span
    @markdown.Block::Table(span~, ..) => span
    @markdown.Block::BlankLines(span~, ..) => span
    @markdown.Block::FootnoteDefinition(span~, ..) => span
  }
}

///|
fn span_in_list(span : @markdown.Span, spans : Array[@markdown.Span]) -> Bool {
  for s in spans {
    if s.from == span.from && s.to == span.to {
      return true
    }
  }
  false
}

///|
priv struct SpanMdxPair {
  span : @markdown.Span
  mdx : MdxBlock
}

///|
fn build_span_to_mdx_map(blocks : Array[MdxBlock]) -> Array[SpanMdxPair] {
  let pairs : Array[SpanMdxPair] = []
  for block in blocks {
    pairs.push({ span: block.span(), mdx: block })
  }
  pairs
}

///|
fn find_mdx_for_span(
  pairs : Array[SpanMdxPair],
  span : @markdown.Span
) -> MdxBlock? {
  for pair in pairs {
    if pair.span.from == span.from && pair.span.to == span.to {
      return Some(pair.mdx)
    }
  }
  None
}

