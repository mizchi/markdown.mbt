///| Direct host JavaScript AST conversion for JS and Wasm GC.

///|
/// Opaque JavaScript value used at the JS FFI / Wasm externref boundary.
#external
type JsValue

///|
#cfg(target="js")
extern "js" fn js_null() -> JsValue =
  #| () => null

///|
#cfg(target="wasm-gc")
fn js_null() -> JsValue = "markdown_ast" "null"

///|
#cfg(target="js")
extern "js" fn js_bool(value : Bool) -> JsValue =
  #| (value) => value

///|
#cfg(target="wasm-gc")
fn js_bool(value : Bool) -> JsValue = "markdown_ast" "bool"

///|
#cfg(target="js")
extern "js" fn js_number(value : Double) -> JsValue =
  #| (value) => value

///|
#cfg(target="wasm-gc")
fn js_number(value : Double) -> JsValue = "markdown_ast" "number"

///|
#cfg(target="js")
extern "js" fn js_string(value : String) -> JsValue =
  #| (value) => value

///|
#cfg(target="wasm-gc")
fn js_string(value : String) -> JsValue = "markdown_ast" "string"

///|
#cfg(target="js")
extern "js" fn js_array_new() -> JsValue =
  #| () => []

///|
#cfg(target="wasm-gc")
fn js_array_new() -> JsValue = "markdown_ast" "array_new"

///|
#cfg(target="js")
extern "js" fn js_array_push(array : JsValue, value : JsValue) -> Unit =
  #| (array, value) => { array.push(value); }

///|
#cfg(target="wasm-gc")
fn js_array_push(array : JsValue, value : JsValue) -> Unit = "markdown_ast" "array_push"

///|
#cfg(target="js")
extern "js" fn js_object_new() -> JsValue =
  #| () => ({})

///|
#cfg(target="wasm-gc")
fn js_object_new() -> JsValue = "markdown_ast" "object_new"

///|
#cfg(target="js")
extern "js" fn js_object_with_type(kind : String) -> JsValue =
  #| (kind) => ({ type: kind })

///|
#cfg(target="wasm-gc")
fn js_object_with_type(kind : String) -> JsValue = "markdown_ast" "object_with_type"

///|
#cfg(target="js")
extern "js" fn js_position(from : Int, to : Int) -> JsValue =
  #| (from, to) => ({ start: { offset: from }, end: { offset: to } })

///|
#cfg(target="wasm-gc")
fn js_position(from : Int, to : Int) -> JsValue = "markdown_ast" "position"

///|
#cfg(target="js")
extern "js" fn js_object_set(
  object : JsValue,
  key : String,
  value : JsValue,
) -> Unit =
  #| (object, key, value) => { object[key] = value; }

///|
#cfg(target="wasm-gc")
fn js_object_set(object : JsValue, key : String, value : JsValue) -> Unit = "markdown_ast" "object_set"

///|
fn set(object : JsValue, key : String, value : JsValue) -> Unit {
  js_object_set(object, key, value)
}

///|
fn typed_object(kind : String) -> JsValue {
  js_object_with_type(kind)
}

///|
fn position_to_js(span : @markdown.Span) -> JsValue {
  js_position(span.from, span.to)
}

///|
fn string_or_null(value : String) -> JsValue {
  if value.is_empty() {
    js_null()
  } else {
    js_string(value)
  }
}

///|
fn bool_or_null(value : Bool?) -> JsValue {
  match value {
    Some(value) => js_bool(value)
    None => js_null()
  }
}

///|
fn reference_style_to_js(style : @markdown.ReferenceStyle) -> JsValue {
  js_string(
    match style {
      Full => "full"
      Collapsed => "collapsed"
      Shortcut => "shortcut"
    },
  )
}

///|
fn alert_kind_to_js(kind : @markdown.AlertKind) -> JsValue {
  js_string(
    match kind {
      Note => "note"
      Tip => "tip"
      Important => "important"
      Warning => "warning"
      Caution => "caution"
    },
  )
}

///|
fn attributes_to_js(attributes : Array[@markdown.MarkdownAttribute]) -> JsValue {
  let result = js_array_new()
  for attribute in attributes {
    let object = js_object_new()
    set(object, "name", js_string(attribute.name))
    set(object, "value", js_string(attribute.value))
    js_array_push(result, object)
  }
  result
}

///|
fn inline_children_to_js(children : Array[@markdown.Inline]) -> JsValue {
  let result = js_array_new()
  for child in children {
    js_array_push(result, inline_to_js(child))
  }
  result
}

///|
fn block_children_to_js(children : Array[@markdown.Block]) -> JsValue {
  let result = js_array_new()
  for child in children {
    match block_to_js(child) {
      Some(value) => js_array_push(result, value)
      None => ()
    }
  }
  result
}

///|
fn table_cell_to_js(cell : @markdown.TableCell) -> JsValue {
  let object = typed_object("tableCell")
  set(object, "children", inline_children_to_js(cell.children))
  set(object, "position", position_to_js(cell.span))
  object
}

///|
fn table_align_to_js(align : @markdown.TableAlign) -> JsValue {
  match align {
    @markdown.TableAlign::Left => js_string("left")
    @markdown.TableAlign::Center => js_string("center")
    @markdown.TableAlign::Right => js_string("right")
    @markdown.TableAlign::None => js_null()
  }
}

///|
fn list_item_to_js(item : @markdown.ListItem, tight : Bool) -> JsValue {
  let object = typed_object("listItem")
  set(object, "spread", js_bool(!tight))
  set(object, "checked", bool_or_null(item.checked))
  set(object, "children", block_children_to_js(item.children))
  set(object, "position", position_to_js(item.span))
  object
}

///|
/// Split a code fence info string without materializing a character array.
fn code_info_to_js(info : String) -> (JsValue, JsValue) {
  if info.is_empty() {
    return (js_null(), js_null())
  }
  match info[:].find(" "[:]) {
    None => (js_string(info), js_null())
    Some(space) => {
      let lang = info[:space].to_owned()
      let meta = info[space + 1:].to_owned()
      (js_string(lang), string_or_null(meta))
    }
  }
}

///|
fn inline_to_js(inline : @markdown.Inline) -> JsValue {
  match inline {
    @markdown.Inline::Text(content~, span~) => {
      let object = typed_object("text")
      set(object, "value", js_string(content))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::SoftBreak(span~) => {
      let object = typed_object("text")
      set(object, "value", js_string("\n"))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::HardBreak(span~, ..) => {
      let object = typed_object("break")
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Emphasis(children~, span~, ..) => {
      let object = typed_object("emphasis")
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Strong(children~, span~, ..) => {
      let object = typed_object("strong")
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Strikethrough(children~, span~) => {
      let object = typed_object("delete")
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Code(content~, span~, ..) => {
      let object = typed_object("inlineCode")
      set(object, "value", js_string(content))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Directive(name~, label~, attributes~, span~) => {
      let object = typed_object("textDirective")
      set(object, "name", js_string(name))
      set(object, "label", js_string(label))
      set(object, "attributes", attributes_to_js(attributes))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::WikiLink(target~, label~, fragment~, span~) => {
      let data = js_object_new()
      set(data, "label", js_string(label))
      set(data, "fragment", js_string(fragment))
      let object = typed_object("wikiLink")
      set(object, "value", js_string(target))
      set(object, "data", data)
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Link(children~, url~, title~, span~) => {
      let object = typed_object("link")
      set(object, "url", js_string(url))
      set(object, "title", string_or_null(title))
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::RefLink(children~, label~, style~, span~) => {
      let object = typed_object("linkReference")
      set(object, "identifier", js_string(label))
      set(object, "label", js_string(label))
      set(object, "referenceType", reference_style_to_js(style))
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Autolink(url~, is_email~, span~) => {
      let text = typed_object("text")
      set(text, "value", js_string(url))
      let children = js_array_new()
      js_array_push(children, text)
      let object = typed_object("link")
      set(
        object,
        "url",
        js_string(if is_email { "mailto:" + url } else { url }),
      )
      set(object, "title", js_null())
      set(object, "children", children)
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::Image(alt~, url~, title~, span~) => {
      let object = typed_object("image")
      set(object, "url", js_string(url))
      set(object, "title", string_or_null(title))
      set(object, "alt", js_string(alt))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::RefImage(alt~, label~, style~, span~) => {
      let object = typed_object("imageReference")
      set(object, "identifier", js_string(label))
      set(object, "label", js_string(label))
      set(object, "referenceType", reference_style_to_js(style))
      set(object, "alt", js_string(alt))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::HtmlInline(html~, span~) => {
      let object = typed_object("html")
      set(object, "value", js_string(html))
      set(object, "position", position_to_js(span))
      object
    }
    @markdown.Inline::FootnoteReference(label~, span~) => {
      let object = typed_object("footnoteReference")
      set(object, "identifier", js_string(label))
      set(object, "label", js_string(label))
      set(object, "position", position_to_js(span))
      object
    }
  }
}

///|
fn block_to_js(block : @markdown.Block) -> JsValue? {
  match block {
    @markdown.Block::Paragraph(children~, span~, ..) => {
      let object = typed_object("paragraph")
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Heading(level~, children~, span~, ..) => {
      let object = typed_object("heading")
      set(object, "depth", js_number(level.to_double()))
      set(object, "children", inline_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::FencedCode(info~, code~, span~, ..) => {
      let (lang, meta) = code_info_to_js(info)
      let object = typed_object("code")
      set(object, "lang", lang)
      set(object, "meta", meta)
      set(object, "value", js_string(code))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::MathBlock(value~, span~, ..) => {
      let object = typed_object("math")
      set(object, "value", js_string(value))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Directive(name~, meta~, children~, span~, ..) => {
      let object = typed_object("containerDirective")
      set(object, "name", js_string(name))
      set(object, "meta", js_string(meta))
      set(object, "children", block_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::DefinitionList(items~, span~, ..) => {
      let js_items = js_array_new()
      for item in items {
        let definitions = js_array_new()
        for definition in item.definitions {
          js_array_push(definitions, inline_children_to_js(definition))
        }
        let js_item = js_object_new()
        set(js_item, "term", inline_children_to_js(item.term))
        set(js_item, "definitions", definitions)
        js_array_push(js_items, js_item)
      }
      let object = typed_object("definitionList")
      set(object, "items", js_items)
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Attributed(block~, attributes~, span~) => {
      let object = typed_object("attributed")
      set(object, "attributes", attributes_to_js(attributes))
      set(
        object,
        "child",
        match block_to_js(block) {
          Some(value) => value
          None => js_null()
        },
      )
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::IndentedCode(code~, span~, ..) => {
      let object = typed_object("code")
      set(object, "lang", js_null())
      set(object, "meta", js_null())
      set(object, "value", js_string(code))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Blockquote(children~, span~, ..) => {
      let object = typed_object("blockquote")
      set(object, "children", block_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Alert(kind~, children~, span~, ..) => {
      let object = typed_object("alert")
      set(object, "kind", alert_kind_to_js(kind))
      set(object, "children", block_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::BulletList(items~, tight~, span~, ..) => {
      let children = js_array_new()
      for item in items {
        js_array_push(children, list_item_to_js(item, tight))
      }
      let object = typed_object("list")
      set(object, "ordered", js_bool(false))
      set(object, "spread", js_bool(!tight))
      set(object, "children", children)
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::OrderedList(start~, items~, tight~, span~, ..) => {
      let children = js_array_new()
      for item in items {
        js_array_push(children, list_item_to_js(item, tight))
      }
      let object = typed_object("list")
      set(object, "ordered", js_bool(true))
      set(object, "start", js_number(start.to_double()))
      set(object, "spread", js_bool(!tight))
      set(object, "children", children)
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::ThematicBreak(span~, ..) => {
      let object = typed_object("thematicBreak")
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::HtmlBlock(html~, span~, ..) => {
      let object = typed_object("html")
      set(object, "value", js_string(html))
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::Table(header~, alignments~, rows~, span~, ..) => {
      let table_rows = js_array_new()
      let header_cells = js_array_new()
      for cell in header {
        js_array_push(header_cells, table_cell_to_js(cell))
      }
      let header_row = typed_object("tableRow")
      set(header_row, "children", header_cells)
      js_array_push(table_rows, header_row)
      for row in rows {
        let cells = js_array_new()
        for cell in row {
          js_array_push(cells, table_cell_to_js(cell))
        }
        let table_row = typed_object("tableRow")
        set(table_row, "children", cells)
        js_array_push(table_rows, table_row)
      }
      let align = js_array_new()
      for item in alignments {
        js_array_push(align, table_align_to_js(item))
      }
      let object = typed_object("table")
      set(object, "align", align)
      set(object, "children", table_rows)
      set(object, "position", position_to_js(span))
      Some(object)
    }
    @markdown.Block::BlankLines(..) => None
    @markdown.Block::FootnoteDefinition(label~, children~, span~, ..) => {
      let object = typed_object("footnoteDefinition")
      set(object, "identifier", js_string(label))
      set(object, "label", js_string(label))
      set(object, "children", block_children_to_js(children))
      set(object, "position", position_to_js(span))
      Some(object)
    }
  }
}

///|
fn document_to_js_value(doc : @markdown.Document) -> JsValue {
  let object = typed_object("root")
  set(object, "children", block_children_to_js(doc.children))
  set(object, "position", position_to_js(doc.span))
  object
}

///|
/// Parse Markdown and return the mdast-compatible JavaScript object directly.
pub fn md_to_ast_object(source : String) -> JsValue {
  let result = @markdown.parse(source)
  document_to_js_value(result.document)
}

///|
/// Parse Markdown with wikilinks and return the JavaScript object directly.
pub fn md_to_ast_object_with_wikilinks(source : String) -> JsValue {
  let result = @markdown.parse(source, wikilinks=true)
  document_to_js_value(result.document)
}

///|
/// Does this block contribute a node to the mdast output?
///
/// Mirrors `block_to_js`: every block maps to exactly one mdast node except
/// `BlankLines`, which is trivia the mdast shape has no place for. Callers need
/// this to translate CST block indices into mdast child indices without
/// building the nodes.
fn block_emits_ast(block : @markdown.Block) -> Bool {
  match block {
    @markdown.Block::BlankLines(..) => false
    _ => true
  }
}

///|
/// Count mdast children produced by CST blocks in `[from, to)`.
fn count_ast_children(
  blocks : Array[@markdown.Block],
  from : Int,
  to : Int,
) -> Int {
  let mut count = 0
  for i = from; i < to; i = i + 1 {
    if block_emits_ast(blocks[i]) {
      count = count + 1
    }
  }
  count
}

///|
/// What a consumer needs to rebuild its mdast from the previous revision's,
/// instead of materialising the whole document again.
///
/// `md_parse_incremental` re-parses only the blocks the edit touched and
/// carries the rest over, but `md_ast_object` still walks every block, so the
/// output costs the same as a full parse no matter how small the edit was.
/// This returns the split instead: reuse the first `before` children of the
/// previous AST and its last `after`, and take everything between them from
/// `rest`.
///
/// Deciding which nodes survive is done here rather than in the consumer on
/// purpose. Spans are shifted by `shift_block_span`, which moves block spans
/// but leaves inline spans alone (they are block-relative) and leaves table
/// rows and cells alone as well. A consumer that shifted offsets itself would
/// have to mirror those rules and keep mirroring them as block types are added.
/// So a reused tail is offered only when the edit moved nothing (`delta == 0`);
/// otherwise the tail is rebuilt here, where the span rules live.
///
/// Returns JS `null` when the handle is unknown or was not produced by an
/// incremental parse, in which case the caller must fall back to
/// `md_ast_object`.
pub fn md_ast_incremental_patch(handle : Int) -> JsValue {
  match ast_store.get(handle) {
    Some(entry) =>
      match entry.reuse {
        Some(reuse) => {
          let blocks = entry.document.children
          let total = blocks.length()
          let reparse_end = reuse.reused_before + reuse.reparsed
          // The full-parse fallback inside parse_incremental reports everything
          // as reparsed; the split still describes it (before = after = 0).
          guard reparse_end <= total else { return js_null() }
          let reuse_tail = reuse.delta == 0
          let rest_end = if reuse_tail { reparse_end } else { total }
          let rest = js_array_new()
          for i = reuse.reused_before; i < rest_end; i = i + 1 {
            match block_to_js(blocks[i]) {
              Some(value) => js_array_push(rest, value)
              None => ()
            }
          }
          let after = if reuse_tail {
            count_ast_children(blocks, reparse_end, total)
          } else {
            0
          }
          let object = js_object_new()
          set(
            object,
            "before",
            js_number(
              count_ast_children(blocks, 0, reuse.reused_before).to_double(),
            ),
          )
          set(object, "after", js_number(after.to_double()))
          set(object, "rest", rest)
          set(object, "position", position_to_js(entry.document.span))
          object
        }
        None => js_null()
      }
    None => js_null()
  }
}

///|
/// Return the mdast-compatible JavaScript object for a document that is
/// already parsed behind `handle`, without re-parsing its source.
///
/// This is what makes `md_parse_incremental` worth anything to an AST
/// consumer: without it the only way back to an AST is a full parse, which
/// costs more than the incremental update saved. Returns JS `null` for an
/// unknown handle.
pub fn md_ast_object(handle : Int) -> JsValue {
  match ast_store.get(handle) {
    Some(entry) => document_to_js_value(entry.document)
    None => js_null()
  }
}
