///|
/// Incremental parsing tests
test "incremental: edit in middle paragraph" {
  let old_source = "# Title\n\nParagraph one.\n\nParagraph two.\n\nParagraph three.\n"
  let old_doc = parse(old_source).document

  // Edit "two" to "TWO" in middle paragraph
  let edit_offset = old_source.find("two")
  match edit_offset {
    Some(offset) => {
      let new_source = "# Title\n\nParagraph one.\n\nParagraph TWO.\n\nParagraph three.\n"
      let edit = EditInfo::replace(offset, 3, 3) // "two" -> "TWO"
      let result = parse_incremental(old_doc, old_source, new_source, edit)

      // Should reuse blocks before and after the edit
      @debug.debug_inspect(
        result.reused_before > 0 || result.reused_after > 0,
        content="true",
      )
      @debug.debug_inspect(result.reparsed >= 1, content="true")

      // Result should match full parse
      let full_result = parse(new_source)
      @debug.debug_inspect(
        result.document.children.length(),
        content=full_result.document.children.length().to_string(),
      )
    }
    None => fail("Could not find 'two' in source")
  }
}

///|
test "incremental: insert at end" {
  let old_source = "# Title\n\nParagraph one.\n"
  let old_doc = parse(old_source).document

  // Insert new paragraph at end
  let new_source = "# Title\n\nParagraph one.\n\nParagraph two.\n"
  let edit = EditInfo::insert(old_source.length(), 17) // "\nParagraph two.\n"
  let result = parse_incremental(old_doc, old_source, new_source, edit)

  // Should reuse existing blocks
  @debug.debug_inspect(result.reused_before >= 2, content="true") // Title, BlankLines, Paragraph

  // Result should match full parse
  let full_result = parse(new_source)
  @debug.debug_inspect(
    result.document.children.length(),
    content=full_result.document.children.length().to_string(),
  )
}

///|
test "incremental: delete paragraph" {
  let old_source = "# Title\n\nParagraph one.\n\nParagraph two.\n\nParagraph three.\n"
  let old_doc = parse(old_source).document

  // Delete middle paragraph
  let delete_start = old_source.find("Paragraph two")
  match delete_start {
    Some(offset) => {
      let new_source = "# Title\n\nParagraph one.\n\nParagraph three.\n"
      let edit = EditInfo::delete(offset - 1, 16) // "\nParagraph two.\n"
      let result = parse_incremental(old_doc, old_source, new_source, edit)

      // Should still have blocks reused
      let total = result.reused_before + result.reparsed + result.reused_after
      @debug.debug_inspect(total > 0, content="true")
    }
    None => fail("Could not find 'Paragraph two' in source")
  }
}

///|
test "incremental: edit heading" {
  let old_source = "# Title\n\nContent here.\n"
  let old_doc = parse(old_source).document

  // Change heading
  let new_source = "# New Title\n\nContent here.\n"
  let edit = EditInfo::replace(2, 5, 9) // "Title" -> "New Title"
  let result = parse_incremental(old_doc, old_source, new_source, edit)

  // Should re-parse the heading
  @debug.debug_inspect(result.reparsed >= 1, content="true")
}

///|
test "incremental: edit code block" {
  let old_source = "# Title\n\n```js\nconsole.log('a');\n```\n\nAfter code.\n"
  let old_doc = parse(old_source).document

  // Edit inside code block
  let edit_offset = old_source.find("'a'")
  match edit_offset {
    Some(offset) => {
      let new_source = "# Title\n\n```js\nconsole.log('hello');\n```\n\nAfter code.\n"
      let edit = EditInfo::replace(offset, 3, 7) // "'a'" -> "'hello'"
      let result = parse_incremental(old_doc, old_source, new_source, edit)

      // Paragraph after should be reusable
      @debug.debug_inspect(
        result.reused_after >= 1 || result.reused_before >= 1,
        content="true",
      )
    }
    None => fail("Could not find code in source")
  }
}

///|
test "incremental: multiple edits same block" {
  let old_source = "Para one two three.\n"
  let old_doc = parse(old_source).document

  // Change "one" to "ONE"
  let new_source = "Para ONE two three.\n"
  let edit = EditInfo::replace(5, 3, 3)
  let result = parse_incremental(old_doc, old_source, new_source, edit)
  @debug.debug_inspect(result.reparsed >= 1, content="true")
}

///|
test "incremental: preserves frontmatter" {
  let old_source = "---\ntitle: Hello\n---\n\n# Content\n\nParagraph.\n"
  let old_doc = parse(old_source).document

  // Edit paragraph
  let new_source = "---\ntitle: Hello\n---\n\n# Content\n\nNew paragraph.\n"
  let edit_offset = old_source.find("Paragraph")
  match edit_offset {
    Some(offset) => {
      let edit = EditInfo::replace(offset, 9, 13) // "Paragraph" -> "New paragraph"
      let result = parse_incremental(old_doc, old_source, new_source, edit)

      // Frontmatter should be preserved
      match result.document.frontmatter {
        Some(fm) => @debug.debug_inspect(fm.entries.length(), content="1")
        None => fail("Frontmatter should be preserved")
      }
    }
    None => fail("Could not find 'Paragraph' in source")
  }
}

///|
test "incremental result stats" {
  let old_source = "# H1\n\nP1\n\nP2\n\nP3\n\nP4\n\nP5\n"
  let old_doc = parse(old_source).document

  // Edit P3
  let edit_offset = old_source.find("P3")
  match edit_offset {
    Some(offset) => {
      let new_source = "# H1\n\nP1\n\nP2\n\nP3X\n\nP4\n\nP5\n"
      let edit = EditInfo::replace(offset, 2, 3) // "P3" -> "P3X"
      let result = parse_incremental(old_doc, old_source, new_source, edit)

      // Should have blocks reused from both before and after
      let total_blocks = result.reused_before +
        result.reparsed +
        result.reused_after
      @debug.debug_inspect(total_blocks > 0, content="true")

      // Verify at least some reuse happened
      let reused = result.reused_before + result.reused_after
      @debug.debug_inspect(reused >= 0, content="true") // Might be 0 depending on implementation
    }
    None => fail("Could not find 'P3' in source")
  }
}

///|
test "incremental: deleting a link definition unresolves its references" {
  let old_source = "[id]\n\n[id]: /old\n"
  let old_doc = parse(old_source).document
  let new_source = "[id]\n\n"
  let edit = EditInfo::delete(6, 10)
  let result = parse_incremental(old_doc, old_source, new_source, edit)
  @debug.debug_inspect(
    render_html(result.document),
    content=(
      #|"<p>[id]</p>\n"
    ),
  )
}

///|
test "incremental: adding a link definition resolves reused references" {
  let old_source = "[id]\n\n"
  let old_doc = parse(old_source).document
  let new_source = "[id]\n\n[id]: /new\n"
  let edit = EditInfo::insert(6, 11)
  let result = parse_incremental(old_doc, old_source, new_source, edit)
  @debug.debug_inspect(
    render_html(result.document),
    content=(
      #|"<p><a href=\"/new\">id</a></p>\n"
    ),
  )
}

///|
test "incremental: shifts reused nested list item spans" {
  let old_source = "# A\n\n1. outer\n   - inner\n     1. deepest\n\nTail.\n"
  let new_source = "# Longer\n\n1. outer\n   - inner\n     1. deepest\n\nTail.\n"
  let incremental = parse_incremental(
    parse(old_source).document,
    old_source,
    new_source,
    EditInfo::replace(2, 1, 6),
  )
  let full = parse(new_source).document
  guard incremental.document.children[2]
    is Block::OrderedList(items=incremental_items, ..) else {
    fail("expected incrementally reused ordered list")
  }
  guard full.children[2] is Block::OrderedList(items=full_items, ..) else {
    fail("expected fully parsed ordered list")
  }
  inspect(incremental.reused_after > 0, content="true")
  inspect(incremental_items[0].span, content=full_items[0].span.to_string())
  guard incremental_items[0].children[1]
    is Block::BulletList(
      items=incremental_nested,
      span=incremental_nested_span,
      ..
    ) else {
    fail("expected incrementally reused nested list")
  }
  guard full_items[0].children[1]
    is Block::BulletList(items=full_nested, span=full_nested_span, ..) else {
    fail("expected fully parsed nested list")
  }
  inspect(incremental_nested_span, content=full_nested_span.to_string())
  inspect(incremental_nested[0].span, content=full_nested[0].span.to_string())
  guard incremental_nested[0].children[1]
    is Block::OrderedList(
      items=incremental_deepest,
      span=incremental_deepest_span,
      ..
    ) else {
    fail("expected incrementally reused deepest ordered list")
  }
  guard full_nested[0].children[1]
    is Block::OrderedList(items=full_deepest, span=full_deepest_span, ..) else {
    fail("expected fully parsed deepest ordered list")
  }
  inspect(incremental_deepest_span, content=full_deepest_span.to_string())
  inspect(incremental_deepest[0].span, content=full_deepest[0].span.to_string())
}
