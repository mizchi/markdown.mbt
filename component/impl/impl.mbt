///|
fn md_to_html(source : String) -> String {
  @markdown.md_to_html(source)
}

///|
fn md_to_ast_json(source : String) -> String {
  let result = @markdown.parse(source)
  @api.document_to_json(result.document)
}

///|
fn md_serialize(source : String) -> String {
  let result = @markdown.parse(source)
  @markdown.serialize(result.document)
}
