///| HTML block parsing (split from block_parser.mbt).

///| The seven start conditions from the CommonMark spec, plus custom elements

///| (Web Components), which this parser treats like the block-level tags of

///| condition 6.

///|
/// HTML block-level tag names (CommonMark Type 6)
let html_block_tags : Array[String] = [
  "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption",
  "center", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "frame", "frameset", "h1",
  "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend",
  "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup",
  "option", "p", "param", "search", "section", "summary", "svg", "table", "tbody",
  "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
]

///|
/// Check if a tag name is a block-level HTML tag
/// Also recognizes custom elements (Web Components) as block tags
fn is_html_block_tag(tag : String) -> Bool {
  // Custom elements (Web Components) are always block-level
  if is_custom_element_tag(tag) {
    return true
  }
  for t in html_block_tags {
    if tag[:].equal_ignore_ascii_case(t[:]) {
      return true
    }
  }
  false
}

///|
/// Check if a tag name is a custom element (Web Component)
/// Custom elements must contain at least one hyphen and start with a letter
fn is_custom_element_tag(tag : String) -> Bool {
  if tag.is_empty() {
    return false
  }
  // Must start with a letter
  let first = tag.unsafe_get(0)
  if !((first >= 0x61 && first <= 0x7A) || (first >= 0x41 && first <= 0x5A)) {
    return false
  }
  // Must contain a hyphen
  for i in 0..<tag.length() {
    if tag.unsafe_get(i) == 0x2D {
      return true
    }
  }
  false
}

///|
/// The tags whose blocks run until a matching closing tag (condition 1).
let html_raw_text_tags : Array[String] = ["script", "pre", "style", "textarea"]

///|
fn matches_at_ignore_case(text : String, start : Int, needle : String) -> Bool {
  let n = needle.length()
  if start + n > text.length() {
    return false
  }
  text.unsafe_substring(start~, end=start + n)[:].equal_ignore_ascii_case(
    needle[:],
  )
}

///|
fn contains_from(text : String, start : Int, needle : String) -> Bool {
  let limit = text.length() - needle.length()
  let mut i = start
  while i <= limit {
    if matches_at_ignore_case(text, i, needle) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Read the tag name starting at `start` (after `<` or `</`).
fn read_tag_name(text : String, start : Int) -> Int {
  let len = text.length()
  let mut i = start
  guard i < len && is_ascii_letter_unit(text.unsafe_get(i)) else {
    return start
  }
  while i < len &&
        (is_ascii_alnum_unit(text.unsafe_get(i)) || text.unsafe_get(i) == '-') {
    i = i + 1
  }
  i
}

///|
/// Decide which HTML block start condition, if any, this line satisfies.
fn BlockParser::try_html_block_start(
  self : BlockParser,
  container : Node,
) -> Node? {
  guard self.peek_line(self.next_nonspace) == '<' else { return None }
  let line = self.line
  let start = self.next_nonspace
  let kind = html_block_kind(line, start, container)
  guard kind > 0 else { return None }
  let node = self.add_child(
    container,
    NodeKind::HtmlBlockNode,
    self.line_start + start,
  )
  node.html_kind = kind
  if kind == 1 {
    // A raw text block runs until its own closing tag, so remember which.
    node.info = raw_text_tag(line, start)
  }
  node.end = self.line_end
  Some(node)
}

///|
/// The raw text element name that opens a condition-1 block at `start`.
fn raw_text_tag(line : String, start : Int) -> String {
  let name_end = read_tag_name(line, start + 1)
  for raw in html_raw_text_tags {
    if line.unsafe_substring(start=start + 1, end=name_end)[:].equal_ignore_ascii_case(
        raw[:],
      ) {
      return raw
    }
  }
  ""
}

///|
fn html_block_kind(line : String, start : Int, container : Node) -> Int {
  let len = line.length()
  // 2: comment, 3: processing instruction, 4: declaration, 5: CDATA
  if matches_at(line, start, "<!--") {
    return 2
  }
  if matches_at(line, start, "<?") {
    return 3
  }
  if matches_at(line, start, "<![CDATA[") {
    return 5
  }
  if start + 2 < len &&
    line.unsafe_get(start + 1) == '!' &&
    is_ascii_letter_unit(line.unsafe_get(start + 2)) {
    return 4
  }
  let closing = start + 1 < len && line.unsafe_get(start + 1) == '/'
  let name_start = if closing { start + 2 } else { start + 1 }
  let name_end = read_tag_name(line, name_start)
  if name_end > name_start {
    let tag = line.unsafe_substring(start=name_start, end=name_end)
    // 1: raw text elements, which only an opening tag starts
    if !closing {
      for raw in html_raw_text_tags {
        if tag[:].equal_ignore_ascii_case(raw[:]) {
          let after = if name_end < len { line.unsafe_get(name_end) } else { 0 }
          if name_end >= len || after == '>' || is_html_space(after) {
            return 1
          }
        }
      }
    }
    // 6: known block-level tags
    if is_html_block_tag(tag) {
      if name_end >= len {
        return 6
      }
      let after = line.unsafe_get(name_end)
      if is_html_space(after) || after == '>' {
        return 6
      }
      if after == '/' &&
        name_end + 1 < len &&
        line.unsafe_get(name_end + 1) == '>' {
        return 6
      }
    }
  }
  // 7: any other complete tag alone on its line; it may not interrupt a
  // paragraph.
  if container.kind == NodeKind::ParagraphNode {
    return 0
  }
  match scan_complete_tag(line, start) {
    Some(after) => {
      let mut i = after
      while i < len && is_html_space(line.unsafe_get(i)) {
        i = i + 1
      }
      if i >= len {
        return 7
      }
      0
    }
    None => 0
  }
}

///|
/// A complete open or closing tag starting at `start`.
fn scan_complete_tag(line : String, start : Int) -> Int? {
  let len = line.length()
  if start + 1 < len && line.unsafe_get(start + 1) == '/' {
    let name_end = read_tag_name(line, start + 2)
    guard name_end > start + 2 else { return None }
    let mut i = name_end
    while i < len && is_html_space(line.unsafe_get(i)) {
      i = i + 1
    }
    return if i < len && line.unsafe_get(i) == '>' { Some(i + 1) } else { None }
  }
  parse_html_open_tag(line, start)
}

///|
/// Whether the line just added closes the block.
fn BlockParser::html_block_ends(self : BlockParser, node : Node) -> Bool {
  let line = self.line
  let from = if self.next_nonspace < line.length() {
    self.next_nonspace
  } else {
    0
  }
  match node.html_kind {
    1 => contains_from(line, from, "</" + node.info + ">")
    2 => contains_from(line, from, "-->")
    3 => contains_from(line, from, "?>")
    4 => contains_from(line, from, ">")
    5 => contains_from(line, from, "]]>")
    _ => false
  }
}
