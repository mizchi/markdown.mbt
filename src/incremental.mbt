///| Incremental parsing support

///| Allows partial re-parsing when document changes are localized

///| Describes a text edit operation

///|
/// Using #valtype to avoid heap allocation for this small struct
#valtype
pub(all) struct EditInfo {
  offset : Int // Where the edit starts in old source
  old_len : Int // How many chars were deleted
  new_len : Int // How many chars were inserted
}

///|
/// Create an edit info for insertion
pub fn EditInfo::insert(offset : Int, len : Int) -> EditInfo {
  { offset, old_len: 0, new_len: len }
}

///|
/// Create an edit info for deletion
pub fn EditInfo::delete(offset : Int, len : Int) -> EditInfo {
  { offset, old_len: len, new_len: 0 }
}

///|
/// Create an edit info for replacement
pub fn EditInfo::replace(
  offset : Int,
  old_len : Int,
  new_len : Int,
) -> EditInfo {
  { offset, old_len, new_len }
}

///|
/// Result of incremental parsing
pub(all) struct IncrementalResult {
  document : Document
  reused_before : Int // Number of blocks reused from before edit
  reparsed : Int // Number of blocks that were re-parsed
  reused_after : Int // Number of blocks reused from after edit
}

///|
/// Parse incrementally using edit hint
pub fn parse_incremental(
  old_doc : Document,
  old_source : String,
  new_source : String,
  edit : EditInfo,
  wikilinks? : Bool = false,
) -> IncrementalResult {
  let old_blocks = old_doc.children

  // Find blocks affected by the edit
  let (before_idx, after_idx) = find_affected_range(
    old_blocks,
    edit,
    old_source.length(),
  )

  // Determine the source range to re-parse
  let reparse_start = if before_idx > 0 {
    old_blocks[before_idx - 1].get_span().to
  } else {
    match old_doc.frontmatter {
      Some(fm) => fm.span.to
      None => 0
    }
  }
  let reparse_end_old = if after_idx < old_blocks.length() {
    old_blocks[after_idx].get_span().from
  } else {
    old_source.length()
  }

  // Adjust reparse_end for new source (account for edit delta)
  let delta = edit.new_len - edit.old_len
  let reparse_end_new = reparse_end_old + delta

  // Re-parse the region with the first reused block appended, so the parse
  // itself can show whether the edit leaked past the region.
  //
  // A construct the edit leaves open - an unterminated fence is the usual one -
  // swallows whatever follows, so the blocks we were about to reuse would not
  // survive a full parse of the same text. When that happens the appended block
  // is absorbed and no block starts at the old boundary any more; when nothing
  // leaked, a block starts exactly there and everything past it is unchanged.
  let region_end = clamp_int(reparse_end_new, reparse_start, new_source.length())
  let has_guard_block = after_idx < old_blocks.length()
  let guard_end = if has_guard_block {
    clamp_int(
      old_blocks[after_idx].get_span().to + delta,
      region_end,
      new_source.length(),
    )
  } else {
    region_end
  }
  let reparse_region = new_source.unsafe_substring(
    start=reparse_start,
    end=guard_end,
  )

  // Re-parse just this region
  let region_result = parse(reparse_region, wikilinks~)

  // Where the appended block has to start for the reuse to be sound.
  let boundary = region_end - reparse_start
  let leaked = has_guard_block &&
    !has_block_starting_at(region_result.document.children, boundary)
  if leaked {
    let full = parse(new_source, wikilinks~)
    return {
      document: full.document,
      reused_before: 0,
      reparsed: full.document.children.length(),
      reused_after: 0,
    }
  }
  // The appended block was re-parsed along with the region, so the reused tail
  // starts after it.
  let after_idx = if has_guard_block { after_idx + 1 } else { after_idx }

  // Link reference definitions are document-scoped: a reused block can hold a
  // reference that this edit resolves or breaks, and the definition itself may
  // live outside the re-parsed region. Fall back to a full parse whenever any
  // are involved.
  if !old_doc.definitions.is_empty() || !region_result.definitions.is_empty() {
    let full = parse(new_source, wikilinks~)
    return {
      document: full.document,
      reused_before: 0,
      reparsed: full.document.children.length(),
      reused_after: 0,
    }
  }
  let new_blocks_raw = region_result.document.children

  // Adjust spans in re-parsed blocks
  let new_blocks = adjust_spans(new_blocks_raw, reparse_start)

  // Build final document
  let final_blocks : Array[Block] = []

  // 1. Reuse blocks before the edit
  for i = 0; i < before_idx; i = i + 1 {
    final_blocks.push(old_blocks[i])
  }
  let reused_before = before_idx

  // 2. Add re-parsed blocks
  for block in new_blocks {
    final_blocks.push(block)
  }
  let reparsed = new_blocks.length()

  // 3. Reuse blocks after the edit (with adjusted spans)
  let reused_after_count = old_blocks.length() - after_idx
  for i = after_idx; i < old_blocks.length(); i = i + 1 {
    final_blocks.push(shift_block_span(old_blocks[i], delta))
  }
  let new_doc = Document::{
    frontmatter: old_doc.frontmatter,
    children: final_blocks,
    definitions: old_doc.definitions,
    span: Span::new(0, new_source.length()),
  }
  {
    document: new_doc,
    reused_before,
    reparsed,
    reused_after: reused_after_count,
  }
}

///|
/// Is this block nothing but blank lines?
fn is_blank_lines(block : Block) -> Bool {
  match block {
    Block::BlankLines(..) => true
    _ => false
  }
}

///|
/// Is there a block starting exactly at `offset`?
///
/// Used to tell whether a re-parsed region still breaks where it used to. If
/// nothing starts at the old boundary, an open construct absorbed what followed
/// and the blocks past it can no longer be reused.
fn has_block_starting_at(blocks : Array[Block], offset : Int) -> Bool {
  for block in blocks {
    if block.get_span().from == offset {
      return true
    }
  }
  false
}

///| Find the range of blocks affected by the edit

///|
/// Returns (first_affected_idx, first_unaffected_after_idx)
///
/// Blocks are matched on their *extent*, not their span. `get_span()` covers
/// only the block proper: a fenced block's closing fence and the blank lines
/// after any block are trivia that sit outside it, so an edit there belongs to
/// no span at all and used to be attributed to whichever block came next -
/// which left the block it actually changed out of the re-parse. Giving each
/// block everything up to where the next one starts makes every offset in the
/// document belong to exactly one block.
///
/// Bounds are inclusive so that an insertion, which has `edit_start ==
/// edit_end`, affects the block starting at the caret as well as the one
/// ending there: typing "> " or "- " at the start of a paragraph turns that
/// paragraph into a quote or a list item.
fn find_affected_range(
  blocks : Array[Block],
  edit : EditInfo,
  source_len : Int,
) -> (Int, Int) {
  let n = blocks.length()
  if n == 0 {
    return (0, 0)
  }
  let edit_start = edit.offset
  let edit_end = edit.offset + edit.old_len
  let mut first = n
  let mut last_plus_one = 0
  for i = 0; i < n; i = i + 1 {
    let extent_from = if i == 0 { 0 } else { blocks[i].get_span().from }
    // Run on to the next block that carries content. Blank-line blocks sit in
    // the gap where a fenced block's closing fence also lives, and letting one
    // of them own that gap is what hid an edit on a closing fence from the
    // block it actually belongs to.
    let mut extent_to = source_len
    for j = i + 1; j < n; j = j + 1 {
      if !is_blank_lines(blocks[j]) {
        extent_to = blocks[j].get_span().from
        break
      }
    }
    if edit_start <= extent_to && edit_end >= extent_from {
      if first == n {
        first = i
      }
      last_plus_one = i + 1
    }
  }
  if first == n {
    (n, n)
  } else {
    (first, last_plus_one)
  }
}

///|
/// Adjust spans in blocks by adding an offset
fn adjust_spans(blocks : Array[Block], offset : Int) -> Array[Block] {
  let result : Array[Block] = []
  for block in blocks {
    result.push(shift_block_span(block, offset))
  }
  result
}

///|
/// Shift list items and every nested block by the same document offset.
fn shift_list_item_spans(
  items : Array[ListItem],
  delta : Int,
) -> Array[ListItem] {
  let result : Array[ListItem] = []
  for item in items {
    result.push({
      ..item,
      children: adjust_spans(item.children, delta),
      span: Span::new(item.span.from + delta, item.span.to + delta),
    })
  }
  result
}

///|
/// Shift a block's span by delta
fn shift_block_span(block : Block, delta : Int) -> Block {
  match block {
    Block::ThematicBreak(
      marker~,
      count~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::ThematicBreak(
        marker~,
        count~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Heading(
      level~,
      style~,
      children~,
      closing_hashes~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::Heading(
        level~,
        style~,
        children~,
        closing_hashes~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Paragraph(children~, span~, leading_trivia~, trailing_trivia~) =>
      Block::Paragraph(
        children~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::FencedCode(
      fence_marker~,
      fence_length~,
      info~,
      code~,
      indent~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::FencedCode(
        fence_marker~,
        fence_length~,
        info~,
        code~,
        indent~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::MathBlock(
      value~,
      fence_length~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::MathBlock(
        value~,
        fence_length~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Directive(
      name~,
      meta~,
      children~,
      fence_length~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::Directive(
        name~,
        meta~,
        children=adjust_spans(children, delta),
        fence_length~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::DefinitionList(items~, span~, leading_trivia~, trailing_trivia~) =>
      Block::DefinitionList(
        items~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Attributed(block~, attributes~, span~) =>
      Block::Attributed(
        block=shift_block_span(block, delta),
        attributes~,
        span=Span::new(span.from + delta, span.to + delta),
      )
    Block::IndentedCode(code~, span~, leading_trivia~, trailing_trivia~) =>
      Block::IndentedCode(
        code~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Blockquote(children~, span~, leading_trivia~, trailing_trivia~) =>
      Block::Blockquote(
        children=adjust_spans(children, delta),
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Alert(kind~, children~, span~, leading_trivia~, trailing_trivia~) =>
      Block::Alert(
        kind~,
        children=adjust_spans(children, delta),
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::BulletList(
      marker~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::BulletList(
        marker~,
        tight~,
        items=shift_list_item_spans(items, delta),
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::OrderedList(
      start~,
      delimiter~,
      tight~,
      items~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::OrderedList(
        start~,
        delimiter~,
        tight~,
        items=shift_list_item_spans(items, delta),
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::Table(
      header~,
      alignments~,
      rows~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::Table(
        header~,
        alignments~,
        rows~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::HtmlBlock(html~, span~, leading_trivia~, trailing_trivia~) =>
      Block::HtmlBlock(
        html~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
    Block::BlankLines(count~, span~) =>
      Block::BlankLines(
        count~,
        span=Span::new(span.from + delta, span.to + delta),
      )
    Block::FootnoteDefinition(
      label~,
      children~,
      span~,
      leading_trivia~,
      trailing_trivia~
    ) =>
      Block::FootnoteDefinition(
        label~,
        children~,
        span=Span::new(span.from + delta, span.to + delta),
        leading_trivia~,
        trailing_trivia~,
      )
  }
}

///|
/// Helper to get span from a block
fn Block::get_span(self : Block) -> Span {
  match self {
    Block::ThematicBreak(span~, ..) => span
    Block::Heading(span~, ..) => span
    Block::Paragraph(span~, ..) => span
    Block::FencedCode(span~, ..) => span
    Block::MathBlock(span~, ..) => span
    Block::Directive(span~, ..) => span
    Block::DefinitionList(span~, ..) => span
    Block::Attributed(span~, ..) => span
    Block::IndentedCode(span~, ..) => span
    Block::Blockquote(span~, ..) => span
    Block::Alert(span~, ..) => span
    Block::BulletList(span~, ..) => span
    Block::OrderedList(span~, ..) => span
    Block::Table(span~, ..) => span
    Block::HtmlBlock(span~, ..) => span
    Block::BlankLines(span~, ..) => span
    Block::FootnoteDefinition(span~, ..) => span
  }
}

///|
/// Clamp a value between min and max (local helper)
fn clamp_int(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}
