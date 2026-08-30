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

///| Find a `</tag>` raw-text closer at or after `start`.

///|
/// SIMD finds sparse `<` candidates; scalar case-insensitive comparison only
/// runs at those positions. No substring is materialized while scanning.
fn find_html_raw_text_closer(text : String, start : Int, tag : String) -> Int? {
  let text_len = text.length()
  let needle = "</" + tag + ">"
  let needle_len = needle.length()
  guard start >= 0 && start <= text_len else { return None }
  let mut search_from = start
  while search_from + needle_len <= text_len {
    match find_exact_from(text, search_from, "<") {
      Some(candidate) => {
        guard candidate + needle_len <= text_len else { return None }
        let candidate_view = text[candidate:candidate + needle_len]
        if candidate_view.equal_ignore_ascii_case(needle[:]) {
          return Some(candidate)
        }
        search_from = candidate + 1
      }
      None => return None
    }
  }
  None
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
  guard kind != HtmlBlockKind::None else { return None }
  let node = self.add_child(
    container,
    NodeKind::HtmlBlockNode,
    self.line_start + start,
  )
  node.html_kind = kind
  if kind == HtmlBlockKind::RawText {
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
fn html_block_kind(
  line : String,
  start : Int,
  container : Node,
) -> HtmlBlockKind {
  let len = line.length()
  // 2: comment, 3: processing instruction, 4: declaration, 5: CDATA
  if matches_at(line, start, "<!--") {
    return HtmlBlockKind::Comment
  }
  if matches_at(line, start, "<?") {
    return HtmlBlockKind::ProcessingInstruction
  }
  if matches_at(line, start, "<![CDATA[") {
    return HtmlBlockKind::Cdata
  }
  if start + 2 < len &&
    line.unsafe_get(start + 1) == '!' &&
    is_ascii_letter_unit(line.unsafe_get(start + 2)) {
    return HtmlBlockKind::Declaration
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
            return HtmlBlockKind::RawText
          }
        }
      }
    }
    // 6: known block-level tags
    if is_html_block_tag(tag) {
      if name_end >= len {
        return HtmlBlockKind::BlockTag
      }
      let after = line.unsafe_get(name_end)
      if is_html_space(after) || after == '>' {
        return HtmlBlockKind::BlockTag
      }
      if after == '/' &&
        name_end + 1 < len &&
        line.unsafe_get(name_end + 1) == '>' {
        return HtmlBlockKind::BlockTag
      }
    }
  }
  // 7: any other complete tag alone on its line; it may not interrupt a
  // paragraph.
  if container.kind == NodeKind::ParagraphNode {
    return HtmlBlockKind::None
  }
  match scan_complete_tag(line, start) {
    Some(after) => {
      let mut i = after
      while i < len && is_html_space(line.unsafe_get(i)) {
        i = i + 1
      }
      if i >= len {
        return HtmlBlockKind::CompleteTag
      }
      HtmlBlockKind::None
    }
    None => HtmlBlockKind::None
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
    HtmlBlockKind::RawText =>
      find_html_raw_text_closer(line, from, node.info) is Some(_)
    HtmlBlockKind::Comment => find_exact_end_from(line, from, "-->") is Some(_)
    HtmlBlockKind::ProcessingInstruction =>
      find_exact_end_from(line, from, "?>") is Some(_)
    HtmlBlockKind::Declaration =>
      find_exact_end_from(line, from, ">") is Some(_)
    HtmlBlockKind::Cdata => find_exact_end_from(line, from, "]]>") is Some(_)
    _ => false
  }
}
