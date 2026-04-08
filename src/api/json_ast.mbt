///| AST to JSON serialization for JS interop (mdast compatible)

///| See: https://github.com/syntax-tree/mdast

///|
/// Convert Document to JSON string (mdast format)
pub fn document_to_json(doc : @markdown.Document) -> String {
  let json = document_to_json_value(doc)
  json.stringify()
}

///|
/// Convert Document to mdast Root
fn document_to_json_value(doc : @markdown.Document) -> Json {
  let children : Array[Json] = []
  for block in doc.children {
    match block_to_json(block) {
      Some(json) => children.push(json)
      None => ()
    }
  }
  {
    "type": "root",
    "children": Json::array(children),
    "position": position_to_json(doc.span),
  }
}

///|
/// Convert Span to mdast Position
fn position_to_json(span : @markdown.Span) -> Json {
  {
    "start": { "offset": span.from.to_json() },
    "end": { "offset": span.to.to_json() },
  }
}

///|
/// Convert Block to mdast JSON (returns None for skipped nodes like BlankLines)
fn block_to_json(block : @markdown.Block) -> Json? {
  match block {
    @markdown.Block::Paragraph(children~, span~, ..) => {
      let inlines : Array[Json] = []
      for inline in children {
        match inline_to_json(inline) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "paragraph",
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::Heading(level~, children~, span~, ..) => {
      let inlines : Array[Json] = []
      for inline in children {
        match inline_to_json(inline) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "heading",
        "depth": level.to_json(),
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::FencedCode(info~, code~, span~, ..) => {
      // Parse info string: first word is lang, rest is meta
      let (lang, meta) = parse_code_info(info)
      Some({
        "type": "code",
        "lang": lang,
        "meta": meta,
        "value": code.to_json(),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::IndentedCode(code~, span~, ..) =>
      Some({
        "type": "code",
        "lang": Json::null(),
        "meta": Json::null(),
        "value": code.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Block::Blockquote(children~, span~, ..) => {
      let blocks : Array[Json] = []
      for child in children {
        match block_to_json(child) {
          Some(json) => blocks.push(json)
          None => ()
        }
      }
      Some({
        "type": "blockquote",
        "children": Json::array(blocks),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::BulletList(items~, tight~, span~, ..) => {
      let list_items : Array[Json] = []
      for item in items {
        list_items.push(list_item_to_json(item, tight))
      }
      Some({
        "type": "list",
        "ordered": false.to_json(),
        "spread": (!tight).to_json(),
        "children": Json::array(list_items),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::OrderedList(start~, items~, tight~, span~, ..) => {
      let list_items : Array[Json] = []
      for item in items {
        list_items.push(list_item_to_json(item, tight))
      }
      Some({
        "type": "list",
        "ordered": true.to_json(),
        "start": start.to_json(),
        "spread": (!tight).to_json(),
        "children": Json::array(list_items),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::ThematicBreak(span~, ..) =>
      Some({ "type": "thematicBreak", "position": position_to_json(span) })
    @markdown.Block::HtmlBlock(html~, span~, ..) =>
      Some({
        "type": "html",
        "value": html.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Block::Table(header~, alignments~, rows~, span~, ..) => {
      let table_rows : Array[Json] = []
      // Header row
      let header_cells : Array[Json] = []
      for cell in header {
        header_cells.push(table_cell_to_json(cell))
      }
      table_rows.push({
        "type": "tableRow",
        "children": Json::array(header_cells),
      })
      // Data rows
      for row in rows {
        let cells : Array[Json] = []
        for cell in row {
          cells.push(table_cell_to_json(cell))
        }
        table_rows.push({ "type": "tableRow", "children": Json::array(cells) })
      }
      // Alignments
      let align_array : Array[Json] = []
      for align in alignments {
        align_array.push(table_align_to_json(align))
      }
      Some({
        "type": "table",
        "align": Json::array(align_array),
        "children": Json::array(table_rows),
        "position": position_to_json(span),
      })
    }
    @markdown.Block::BlankLines(..) =>
      // mdast doesn't have blank lines node
      None
    @markdown.Block::FootnoteDefinition(label~, children~, span~, ..) => {
      let blocks : Array[Json] = []
      for child in children {
        match block_to_json(child) {
          Some(json) => blocks.push(json)
          None => ()
        }
      }
      Some({
        "type": "footnoteDefinition",
        "identifier": label.to_json(),
        "label": label.to_json(),
        "children": Json::array(blocks),
        "position": position_to_json(span),
      })
    }
  }
}

///|
/// Parse code info string into lang and meta
fn parse_code_info(info : String) -> (Json, Json) {
  if info.is_empty() {
    return (Json::null(), Json::null())
  }
  // Find first space to split lang and meta
  let mut space_idx = -1
  let mut idx = 0
  for c in info {
    if c == ' ' {
      space_idx = idx
      break
    }
    idx += 1
  }
  if space_idx < 0 {
    (info.to_json(), Json::null())
  } else {
    // Note: substring is deprecated but slice syntax requires error handling
    let lang = info.unsafe_substring(start=0, end=space_idx)
    let meta = info.unsafe_substring(start=space_idx + 1, end=info.length())
    (
      lang.to_json(),
      if meta.is_empty() {
        Json::null()
      } else {
        meta.to_json()
      },
    )
  }
}

///|
/// Convert ListItem to mdast JSON
fn list_item_to_json(item : @markdown.ListItem, tight : Bool) -> Json {
  let blocks : Array[Json] = []
  for child in item.children {
    match block_to_json(child) {
      Some(json) => blocks.push(json)
      None => ()
    }
  }
  let checked : Json = match item.checked {
    Some(v) => v.to_json()
    None => Json::null()
  }
  {
    "type": "listItem",
    "spread": (!tight).to_json(),
    "checked": checked,
    "children": Json::array(blocks),
    "position": position_to_json(item.span),
  }
}

///|
/// Convert TableCell to mdast JSON
fn table_cell_to_json(cell : @markdown.TableCell) -> Json {
  let inlines : Array[Json] = []
  for inline in cell.children {
    match inline_to_json(inline) {
      Some(json) => inlines.push(json)
      None => ()
    }
  }
  {
    "type": "tableCell",
    "children": Json::array(inlines),
    "position": position_to_json(cell.span),
  }
}

///|
/// Convert TableAlign to mdast AlignType
fn table_align_to_json(align : @markdown.TableAlign) -> Json {
  match align {
    @markdown.TableAlign::Left => "left".to_json()
    @markdown.TableAlign::Center => "center".to_json()
    @markdown.TableAlign::Right => "right".to_json()
    @markdown.TableAlign::None => Json::null()
  }
}

///|
/// Convert Inline to mdast JSON (returns None for soft breaks which are merged)
fn inline_to_json(inline : @markdown.Inline) -> Json? {
  match inline {
    @markdown.Inline::Text(content~, span~) =>
      Some({
        "type": "text",
        "value": content.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::SoftBreak(span~) =>
      // Represent as text with newline (mdast convention)
      Some({
        "type": "text",
        "value": "\n".to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::HardBreak(span~, ..) =>
      Some({ "type": "break", "position": position_to_json(span) })
    @markdown.Inline::Emphasis(children~, span~, ..) => {
      let inlines : Array[Json] = []
      for child in children {
        match inline_to_json(child) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "emphasis",
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::Strong(children~, span~, ..) => {
      let inlines : Array[Json] = []
      for child in children {
        match inline_to_json(child) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "strong",
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::Strikethrough(children~, span~) => {
      let inlines : Array[Json] = []
      for child in children {
        match inline_to_json(child) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "delete",
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::Code(content~, span~, ..) =>
      Some({
        "type": "inlineCode",
        "value": content.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::Link(children~, url~, title~, span~) => {
      let inlines : Array[Json] = []
      for child in children {
        match inline_to_json(child) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "link",
        "url": url.to_json(),
        "title": if title.is_empty() {
          Json::null()
        } else {
          title.to_json()
        },
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::RefLink(children~, label~, span~) => {
      let inlines : Array[Json] = []
      for child in children {
        match inline_to_json(child) {
          Some(json) => inlines.push(json)
          None => ()
        }
      }
      Some({
        "type": "linkReference",
        "identifier": label.to_json(),
        "label": label.to_json(),
        "referenceType": "full".to_json(),
        "children": Json::array(inlines),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::Autolink(url~, is_email~, span~) => {
      let href = if is_email { "mailto:" + url } else { url }
      Some({
        "type": "link",
        "url": href.to_json(),
        "title": Json::null(),
        "children": Json::array([{ "type": "text", "value": url.to_json() }]),
        "position": position_to_json(span),
      })
    }
    @markdown.Inline::Image(alt~, url~, title~, span~) =>
      Some({
        "type": "image",
        "url": url.to_json(),
        "title": if title.is_empty() {
          Json::null()
        } else {
          title.to_json()
        },
        "alt": alt.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::RefImage(alt~, label~, span~) =>
      Some({
        "type": "imageReference",
        "identifier": label.to_json(),
        "label": label.to_json(),
        "referenceType": "full".to_json(),
        "alt": alt.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::HtmlInline(html~, span~) =>
      Some({
        "type": "html",
        "value": html.to_json(),
        "position": position_to_json(span),
      })
    @markdown.Inline::FootnoteReference(label~, span~) =>
      Some({
        "type": "footnoteReference",
        "identifier": label.to_json(),
        "label": label.to_json(),
        "position": position_to_json(span),
      })
  }
}
