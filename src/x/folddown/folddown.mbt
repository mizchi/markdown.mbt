///| Typed MDX declarations for structured, reader-adaptive Markdown.

///|
/// Normalize canonical Markdown through mizchi/markdown.
pub fn normalize_markdown(source : String) -> String {
  @markdown.md_parse_and_render(source)
}

///| Return the closed schema for canonical Folddown MDX declarations.

///|
/// Domain-specific extensions should define an additional component schema,
/// rather than passing arbitrary untyped attributes to `Fold`.
pub fn fold_schema() -> @mdx.MdxSchema {
  @mdx.MdxSchema::closed([
    @mdx.ComponentSchema::new("Fold", [
      @mdx.PropSchema::required("id", @mdx.MdxValueType::Text),
      @mdx.PropSchema::required(
        "kind",
        @mdx.MdxValueType::OneOf([
          "concept", "procedure", "reference", "evidence",
        ]),
      ),
      @mdx.PropSchema::required(
        "level",
        @mdx.MdxValueType::OneOf(["intro", "basic", "advanced", "expert"]),
      ),
      @mdx.PropSchema::optional("locale", @mdx.MdxValueType::Text),
      @mdx.PropSchema::optional("requires", @mdx.MdxValueType::TextList),
      @mdx.PropSchema::optional("roles", @mdx.MdxValueType::TextList),
      @mdx.PropSchema::optional("goals", @mdx.MdxValueType::TextList),
      @mdx.PropSchema::optional("evidence", @mdx.MdxValueType::TextList),
      @mdx.PropSchema::optional("familiarTo", @mdx.MdxValueType::TextList),
    ]),
    @mdx.ComponentSchema::new("Include", [
      @mdx.PropSchema::required("src", @mdx.MdxValueType::Text),
      @mdx.PropSchema::optional("sync", @mdx.MdxValueType::Text),
    ]),
  ])
}

///| Parse and type-check declarative Folddown metadata in canonical Markdown.

///|
/// Only literal MDX values are accepted. Dynamic JavaScript is not evaluated,
/// so a document's validation result is deterministic.
pub fn validate_source(source : String) -> @mdx.MdxTypeCheckResult {
  let document = @markdown.parse(source).document
  @mdx.type_check_mdx(document, fold_schema())
}
