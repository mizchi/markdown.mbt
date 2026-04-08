// Description Extraction
// Extract description from markdown for meta tags

///|
/// Extract description from Document
/// Returns the first paragraph's text, truncated to max_length
pub fn extract_description_from_document(
  doc : @md.Document,
  max_length? : Int = 160,
) -> String? {
  extract_description_from_blocks(doc.children, max_length~)
}

///|
/// Extract description from Block array
pub fn extract_description_from_blocks(
  blocks : Array[@md.Block],
  max_length? : Int = 160,
) -> String? {
  for block in blocks {
    match block {
      @md.Block::Paragraph(children~, ..) => {
        let text = extract_text_from_inlines(children)
        if !text.is_empty() {
          return Some(truncate_text(text, max_length))
        }
      }
      _ => continue
    }
  }
  None
}

///|
/// Truncate text to max_length, adding ellipsis if needed
fn truncate_text(text : String, max_length : Int) -> String {
  if max_length <= 0 {
    return "..."
  }
  let prefix : Array[Char] = []
  let search_start = if max_length > 30 { max_length - 30 } else { 0 }
  let mut last_space = max_length
  let mut char_count = 0
  let mut truncated = false
  for ch in text {
    if char_count >= max_length {
      truncated = true
      break
    }
    if ch == ' ' && char_count >= search_start {
      last_space = char_count
    }
    prefix.push(ch)
    char_count += 1
  }
  if !truncated {
    return text
  }
  let cut_point = if last_space < prefix.length() {
    last_space
  } else {
    prefix.length()
  }
  let result : Array[Char] = []
  for i = 0; i < cut_point; i = i + 1 {
    result.push(prefix[i])
  }
  String::from_array(result) + "..."
}
