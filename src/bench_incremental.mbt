///| Incremental parsing benchmarks (split from bench.mbt).

// === Incremental parsing benchmarks ===

// Generate a document with many paragraphs for incremental testing

///|
fn generate_paragraph_doc(count : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Document Title\n\n")
  for i = 0; i < count; i = i + 1 {
    buf.write_string(
      "Paragraph \{i + 1} with some content that needs parsing. ",
    )
    buf.write_string("This is a *sample* paragraph with **formatting**.\n\n")
  }
  buf.to_string()
}

///|
let incremental_doc_10 : String = generate_paragraph_doc(10)

///|
let incremental_doc_50 : String = generate_paragraph_doc(50)

///|
let incremental_doc_100 : String = generate_paragraph_doc(100)

// Pre-parse documents for incremental benchmarks

///|
let incremental_parsed_10 : ParseResult = parse(incremental_doc_10)

///|
let incremental_parsed_50 : ParseResult = parse(incremental_doc_50)

///|
let incremental_parsed_100 : ParseResult = parse(incremental_doc_100)

// Pre-compute edited versions for benchmarks (avoid computing in bench loop)

///|
let edited_10 : (String, EditInfo) = edit_middle_paragraph(incremental_doc_10)

///|
let edited_50 : (String, EditInfo) = edit_middle_paragraph(incremental_doc_50)

///|
let edited_100 : (String, EditInfo) = edit_middle_paragraph(incremental_doc_100)

// Pre-compute edge case edits

///|
let edited_50_start : (String, EditInfo) = {
  let new_source = "# CHANGED Title\n" +
    incremental_doc_50.unsafe_substring(
      start=18,
      end=incremental_doc_50.length(),
    )
  let edit = EditInfo::replace(2, 8, 14)
  (new_source, edit)
}

///|
let edited_50_end : (String, EditInfo) = {
  let new_source = incremental_doc_50 + "New final paragraph added here.\n\n"
  let edit = EditInfo::insert(incremental_doc_50.length(), 34)
  (new_source, edit)
}

// Helper to create edited version (change middle paragraph)

///|
fn edit_middle_paragraph(source : String) -> (String, EditInfo) {
  // Find approximately middle position
  let mid = source.length() / 2
  // Find start of a line near middle
  let mut edit_pos = mid
  for i = mid; i > 0; i = i - 1 {
    match source.get_char(i) {
      Some('\n') => {
        edit_pos = i + 1
        break
      }
      _ => continue
    }
  }

  // Replace "Paragraph" with "CHANGED" at that position
  let search = "Paragraph"
  let replace = "PARAGRAPH"
  let edit_offset = match source.find(search) {
    Some(pos) => pos + edit_pos / 10 // Offset to get middle occurrence
    None => edit_pos
  }
  let new_source = source.unsafe_substring(start=0, end=edit_offset) +
    replace +
    source.unsafe_substring(
      start=edit_offset + search.length(),
      end=source.length(),
    )
  let edit = EditInfo::replace(edit_offset, search.length(), replace.length())
  (new_source, edit)
}

// Baseline: Full re-parse of 10-paragraph document

///|
test "full parse: 10 paragraphs" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(incremental_doc_10)
    b.keep(result)
  })
}

// Incremental: Edit middle of 10-paragraph document

///|
test "incremental: 10 paragraphs, edit middle" (b : @bench.T) {
  let (new_source, edit) = edited_10
  let old_doc = incremental_parsed_10.document
  b.bench(fn() {
    let result = parse_incremental(
      old_doc, incremental_doc_10, new_source, edit,
    )
    b.keep(result)
  })
}

// Baseline: Full re-parse of 50-paragraph document

///|
test "full parse: 50 paragraphs" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(incremental_doc_50)
    b.keep(result)
  })
}

// Incremental: Edit middle of 50-paragraph document

///|
test "incremental: 50 paragraphs, edit middle" (b : @bench.T) {
  let (new_source, edit) = edited_50
  let old_doc = incremental_parsed_50.document
  b.bench(fn() {
    let result = parse_incremental(
      old_doc, incremental_doc_50, new_source, edit,
    )
    b.keep(result)
  })
}

// Baseline: Full re-parse of 100-paragraph document

///|
test "full parse: 100 paragraphs" (b : @bench.T) {
  b.bench(fn() {
    let result = parse(incremental_doc_100)
    b.keep(result)
  })
}

// Incremental: Edit middle of 100-paragraph document

///|
test "incremental: 100 paragraphs, edit middle" (b : @bench.T) {
  let (new_source, edit) = edited_100
  let old_doc = incremental_parsed_100.document
  b.bench(fn() {
    let result = parse_incremental(
      old_doc, incremental_doc_100, new_source, edit,
    )
    b.keep(result)
  })
}

// Edge case: Edit at the beginning

///|
test "incremental: 50 paragraphs, edit start" (b : @bench.T) {
  let (new_source, edit) = edited_50_start
  let old_doc = incremental_parsed_50.document
  b.bench(fn() {
    let result = parse_incremental(
      old_doc, incremental_doc_50, new_source, edit,
    )
    b.keep(result)
  })
}

// Edge case: Edit at the end

///|
test "incremental: 50 paragraphs, edit end" (b : @bench.T) {
  let (new_source, edit) = edited_50_end
  let old_doc = incremental_parsed_50.document
  b.bench(fn() {
    let result = parse_incremental(
      old_doc, incremental_doc_50, new_source, edit,
    )
    b.keep(result)
  })
}
