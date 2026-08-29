///| Canonical reader nodes extracted from validated Folddown MDX.

///|
/// A Fold node keeps its typed declaration and Markdown child source together.
pub(all) struct FoldNode {
  id : String
  kind : String
  level : String
  locale : String?
  requires : Array[String]
  roles : Array[String]
  goals : Array[String]
  evidence : Array[String]
  familiar_to : Array[String]
  body : String
}

///|
/// A reader state generated from Folddown's frontmatter DSL.
pub(all) struct FolddownReaderProfile {
  id : String
  label_ja : String
  label_en : String
  collapse_levels : Array[String]
}

///|
/// A content-selection state generated from Folddown's frontmatter DSL.
///
/// `unfamiliar` excludes nodes whose `familiarTo` role matches the selected
/// reader background; `all` retains every otherwise visible node.
pub(all) struct FolddownContentFilter {
  id : String
  label_ja : String
  label_en : String
  mode : String
}

///|
/// The parser either returns complete nodes or schema diagnostics.
pub(all) struct FoldParseResult {
  nodes : Array[FoldNode]
  reader_profiles : Array[FolddownReaderProfile]
  content_filters : Array[FolddownContentFilter]
  diagnostics : Array[@mdx.MdxDiagnostic]
}

///|
/// A typed reference to an external Folddown MDX document.
pub(all) struct FolddownInclude {
  src : String
  sync : String?
  raw : String
}

///|
/// Include declarations and diagnostics for a single Folddown source file.
pub(all) struct FolddownIncludeParseResult {
  includes : Array[FolddownInclude]
  diagnostics : Array[@mdx.MdxDiagnostic]
}

///|
/// Internal result shared by node and include projections.
priv struct ParsedFolddownDocument {
  nodes : Array[FoldNode]
  includes : Array[FolddownInclude]
  reader_profiles : Array[FolddownReaderProfile]
  content_filters : Array[FolddownContentFilter]
  diagnostics : Array[@mdx.MdxDiagnostic]
}

///|
/// Internal profile DSL parse result.
priv struct ReaderProfileParseResult {
  reader_profiles : Array[FolddownReaderProfile]
  diagnostics : Array[@mdx.MdxDiagnostic]
}

///|
/// Internal content-filter DSL parse result.
priv struct ContentFilterParseResult {
  content_filters : Array[FolddownContentFilter]
  diagnostics : Array[@mdx.MdxDiagnostic]
}

///|
/// Parse, type-check, and extract canonical Folddown nodes.
pub fn parse_source(source : String) -> FoldParseResult {
  let parsed = parse_document(source)
  {
    nodes: parsed.nodes,
    reader_profiles: parsed.reader_profiles,
    content_filters: parsed.content_filters,
    diagnostics: parsed.diagnostics,
  }
}

///|
/// Parse and type-check external document Include declarations.
pub fn parse_include_source(source : String) -> FolddownIncludeParseResult {
  let parsed = parse_document(source)
  { includes: parsed.includes, diagnostics: parsed.diagnostics }
}

///|
/// Parse a Folddown document once, then project nodes or include declarations.
fn parse_document(source : String) -> ParsedFolddownDocument {
  let document = @markdown.parse(source).document
  let checked = @mdx.type_check_mdx(document, fold_schema())
  if !checked.is_valid() {
    return {
      nodes: [],
      includes: [],
      reader_profiles: [],
      content_filters: [],
      diagnostics: checked.diagnostics,
    }
  }
  let profiles = parse_reader_profiles(document.frontmatter)
  if !profiles.diagnostics.is_empty() {
    return {
      nodes: [],
      includes: [],
      reader_profiles: [],
      content_filters: [],
      diagnostics: profiles.diagnostics,
    }
  }
  let content_filters = parse_content_filters(document.frontmatter)
  if !content_filters.diagnostics.is_empty() {
    return {
      nodes: [],
      includes: [],
      reader_profiles: [],
      content_filters: [],
      diagnostics: content_filters.diagnostics,
    }
  }

  let fold_elements : Array[@mdx.TypedMdxElement] = []
  let include_elements : Array[@mdx.TypedMdxElement] = []
  for element in checked.elements {
    if element.tag == "Fold" {
      fold_elements.push(element)
    } else if element.tag == "Include" {
      include_elements.push(element)
    }
  }

  let nodes : Array[FoldNode] = []
  let includes : Array[FolddownInclude] = []
  let diagnostics : Array[@mdx.MdxDiagnostic] = []
  let mut fold_index = 0
  let mut include_index = 0
  for block in @mdx.parse_mdx_source(source) {
    match block {
      @mdx.MdxBlock::JsxElement(tag~, children~, ..) if tag == "Fold" => {
        let typed = fold_elements[fold_index]
        nodes.push(node_from_typed_element(typed, children))
        fold_index += 1
      }
      @mdx.MdxBlock::JsxElement(tag~, self_closing~, span~, raw~, ..) if tag ==
        "Include" => {
        if !self_closing {
          diagnostics.push({
            code: "include-must-be-self-closing",
            message: "<Include> must be self-closing",
            span,
          })
        } else {
          let typed = include_elements[include_index]
          includes.push(include_from_typed_element(typed, raw))
        }
        include_index += 1
      }
      _ => ()
    }
  }
  if !diagnostics.is_empty() {
    return {
      nodes: [],
      includes: [],
      reader_profiles: [],
      content_filters: [],
      diagnostics,
    }
  }
  {
    nodes,
    includes,
    reader_profiles: profiles.reader_profiles,
    content_filters: content_filters.content_filters,
    diagnostics: [],
  }
}

///|
/// Encode a parsed document as a deterministic JSON render manifest.
pub fn parse_source_to_json(source : String) -> String {
  let result = parse_source(source)
  let nodes : Array[Json] = []
  for node in result.nodes {
    nodes.push(node_to_json(node))
  }
  let diagnostics : Array[Json] = []
  for diagnostic in result.diagnostics {
    diagnostics.push({
      "code": diagnostic.code.to_json(),
      "message": diagnostic.message.to_json(),
    })
  }
  let reader_profiles : Array[Json] = []
  for profile in result.reader_profiles {
    reader_profiles.push(reader_profile_to_json(profile))
  }
  let content_filters : Array[Json] = []
  for filter in result.content_filters {
    content_filters.push(content_filter_to_json(filter))
  }
  let manifest : Json = {
    "nodes": Json::array(nodes),
    "readerProfiles": Json::array(reader_profiles),
    "contentFilters": Json::array(content_filters),
    "diagnostics": Json::array(diagnostics),
  }
  manifest.stringify()
}

///|
/// Encode Include declarations as a deterministic JSON manifest.
pub fn parse_include_source_to_json(source : String) -> String {
  let result = parse_include_source(source)
  let includes : Array[Json] = []
  for declaration in result.includes {
    includes.push(include_to_json(declaration))
  }
  let diagnostics : Array[Json] = []
  for diagnostic in result.diagnostics {
    diagnostics.push({
      "code": diagnostic.code.to_json(),
      "message": diagnostic.message.to_json(),
    })
  }
  let manifest : Json = {
    "includes": Json::array(includes),
    "diagnostics": Json::array(diagnostics),
  }
  manifest.stringify()
}

///|
fn node_from_typed_element(
  element : @mdx.TypedMdxElement,
  children : String,
) -> FoldNode {
  {
    id: required_text(element.attributes, "id"),
    kind: required_text(element.attributes, "kind"),
    level: required_text(element.attributes, "level"),
    locale: optional_text(element.attributes, "locale"),
    requires: text_list(element.attributes, "requires"),
    roles: text_list(element.attributes, "roles"),
    goals: text_list(element.attributes, "goals"),
    evidence: text_list(element.attributes, "evidence"),
    familiar_to: text_list(element.attributes, "familiarTo"),
    body: children.trim(chars=" \t\n\r").to_owned(),
  }
}

///|
fn include_from_typed_element(
  element : @mdx.TypedMdxElement,
  raw : String,
) -> FolddownInclude {
  {
    src: required_text(element.attributes, "src"),
    sync: optional_text(element.attributes, "sync"),
    raw,
  }
}

///|
fn required_text(
  attributes : Array[@mdx.TypedMdxAttribute],
  name : String,
) -> String {
  match optional_text(attributes, name) {
    Some(value) => value
    None => ""
  }
}

///|
fn optional_text(
  attributes : Array[@mdx.TypedMdxAttribute],
  name : String,
) -> String? {
  for attribute in attributes {
    if attribute.name == name {
      match attribute.value {
        @mdx.MdxLiteral::Text(value) => return Some(value)
        _ => ()
      }
    }
  }
  None
}

///|
fn text_list(
  attributes : Array[@mdx.TypedMdxAttribute],
  name : String,
) -> Array[String] {
  for attribute in attributes {
    if attribute.name == name {
      match attribute.value {
        @mdx.MdxLiteral::TextList(values) => return values
        _ => ()
      }
    }
  }
  []
}

///|
fn strings_to_json(values : Array[String]) -> Json {
  let json : Array[Json] = []
  for value in values {
    json.push(value.to_json())
  }
  Json::array(json)
}

///|
fn reader_profile_to_json(profile : FolddownReaderProfile) -> Json {
  {
    "id": profile.id.to_json(),
    "labelJa": profile.label_ja.to_json(),
    "labelEn": profile.label_en.to_json(),
    "collapseLevels": strings_to_json(profile.collapse_levels),
  }
}

///|
fn content_filter_to_json(filter : FolddownContentFilter) -> Json {
  {
    "id": filter.id.to_json(),
    "labelJa": filter.label_ja.to_json(),
    "labelEn": filter.label_en.to_json(),
    "mode": filter.mode.to_json(),
  }
}

///|
fn node_to_json(node : FoldNode) -> Json {
  {
    "id": node.id.to_json(),
    "kind": node.kind.to_json(),
    "level": node.level.to_json(),
    "locale": match node.locale {
      Some(locale) => locale.to_json()
      None => Json::null()
    },
    "requires": strings_to_json(node.requires),
    "roles": strings_to_json(node.roles),
    "goals": strings_to_json(node.goals),
    "evidence": strings_to_json(node.evidence),
    "familiarTo": strings_to_json(node.familiar_to),
    "body": node.body.to_json(),
  }
}

///|
fn include_to_json(declaration : FolddownInclude) -> Json {
  {
    "src": declaration.src.to_json(),
    "sync": match declaration.sync {
      Some(sync) => sync.to_json()
      None => Json::null()
    },
    "raw": declaration.raw.to_json(),
  }
}

///|
/// Parse the flat frontmatter DSL:
///
/// ```text
/// folddown.readers: first_time,some_knowledge
/// folddown.reader.first_time.label.ja: 初めて知った
/// folddown.reader.first_time.label.en: First time
/// folddown.reader.first_time.collapse: none
/// ```
fn parse_reader_profiles(
  frontmatter : @markdown.Frontmatter?,
) -> ReaderProfileParseResult {
  match frontmatter {
    None => { reader_profiles: [], diagnostics: [] }
    Some(frontmatter) => {
      let reader_ids = frontmatter_value(
        frontmatter.entries,
        "folddown.readers",
      )
      match reader_ids {
        None => {
          let has_profile_entries = has_reader_profile_entries(
            frontmatter.entries,
          )
          if has_profile_entries {
            {
              reader_profiles: [],
              diagnostics: [
                reader_profile_diagnostic(
                  "reader-profile-without-readers",
                  "Reader profile entries require 'folddown.readers'",
                  frontmatter.span,
                ),
              ],
            }
          } else {
            { reader_profiles: [], diagnostics: [] }
          }
        }
        Some(ids) => parse_declared_reader_profiles(frontmatter, split_csv(ids))
      }
    }
  }
}

///|
fn parse_declared_reader_profiles(
  frontmatter : @markdown.Frontmatter,
  ids : Array[String],
) -> ReaderProfileParseResult {
  let diagnostics : Array[@mdx.MdxDiagnostic] = []
  if ids.length() != 2 {
    diagnostics.push(
      reader_profile_diagnostic(
        "reader-profile-count",
        "'folddown.readers' must declare exactly two reader profiles",
        frontmatter.span,
      ),
    )
  }

  let profiles : Array[FolddownReaderProfile] = []
  let seen : Array[String] = []
  for id in ids {
    if string_in_array(seen, id) {
      diagnostics.push(
        reader_profile_diagnostic(
          "duplicate-reader-profile",
          "'folddown.readers' declares '" + id + "' more than once",
          frontmatter.span,
        ),
      )
      continue
    }
    seen.push(id)
    let base = "folddown.reader." + id + "."
    let label_ja = required_profile_value(
      frontmatter.entries,
      base + "label.ja",
      frontmatter.span,
      diagnostics,
    )
    let label_en = required_profile_value(
      frontmatter.entries,
      base + "label.en",
      frontmatter.span,
      diagnostics,
    )
    let collapse = required_profile_value(
      frontmatter.entries,
      base + "collapse",
      frontmatter.span,
      diagnostics,
    )
    let collapse_levels = if collapse == "none" {
      []
    } else {
      split_csv(collapse)
    }
    for level in collapse_levels {
      if !is_fold_level(level) {
        diagnostics.push(
          reader_profile_diagnostic(
            "unknown-reader-profile-level",
            "Reader profile '" + id + "' cannot collapse level '" + level + "'",
            frontmatter.span,
          ),
        )
      }
    }
    profiles.push({ id, label_ja, label_en, collapse_levels })
  }

  if !diagnostics.is_empty() {
    return { reader_profiles: [], diagnostics }
  }
  { reader_profiles: profiles, diagnostics: [] }
}

///|
/// Parse the flat content-filter DSL:
///
/// ```text
/// folddown.content_filters: detail,interesting
/// folddown.content_filter.detail.label.ja: 詳しく知りたい
/// folddown.content_filter.detail.label.en: Learn in detail
/// folddown.content_filter.detail.mode: all
/// folddown.content_filter.interesting.mode: unfamiliar
/// ```
fn parse_content_filters(
  frontmatter : @markdown.Frontmatter?,
) -> ContentFilterParseResult {
  match frontmatter {
    None => { content_filters: [], diagnostics: [] }
    Some(frontmatter) => {
      let filter_ids = frontmatter_value(
        frontmatter.entries,
        "folddown.content_filters",
      )
      match filter_ids {
        None =>
          if has_content_filter_entries(frontmatter.entries) {
            {
              content_filters: [],
              diagnostics: [
                reader_profile_diagnostic(
                  "content-filter-without-list",
                  "Content filter entries require 'folddown.content_filters'",
                  frontmatter.span,
                ),
              ],
            }
          } else {
            { content_filters: [], diagnostics: [] }
          }
        Some(ids) => parse_declared_content_filters(frontmatter, split_csv(ids))
      }
    }
  }
}

///|
fn parse_declared_content_filters(
  frontmatter : @markdown.Frontmatter,
  ids : Array[String],
) -> ContentFilterParseResult {
  let diagnostics : Array[@mdx.MdxDiagnostic] = []
  if ids.length() != 2 {
    diagnostics.push(
      reader_profile_diagnostic(
        "content-filter-count",
        "'folddown.content_filters' must declare exactly two content filters",
        frontmatter.span,
      ),
    )
  }

  let filters : Array[FolddownContentFilter] = []
  let seen : Array[String] = []
  for id in ids {
    if string_in_array(seen, id) {
      diagnostics.push(
        reader_profile_diagnostic(
          "duplicate-content-filter",
          "'folddown.content_filters' declares '" + id + "' more than once",
          frontmatter.span,
        ),
      )
      continue
    }
    seen.push(id)
    let base = "folddown.content_filter." + id + "."
    let label_ja = required_content_filter_value(
      frontmatter.entries,
      base + "label.ja",
      frontmatter.span,
      diagnostics,
    )
    let label_en = required_content_filter_value(
      frontmatter.entries,
      base + "label.en",
      frontmatter.span,
      diagnostics,
    )
    let mode = required_content_filter_value(
      frontmatter.entries,
      base + "mode",
      frontmatter.span,
      diagnostics,
    )
    if !is_content_filter_mode(mode) {
      diagnostics.push(
        reader_profile_diagnostic(
          "unknown-content-filter-mode",
          "Content filter '" + id + "' cannot use mode '" + mode + "'",
          frontmatter.span,
        ),
      )
    }
    filters.push({ id, label_ja, label_en, mode })
  }

  if !diagnostics.is_empty() {
    return { content_filters: [], diagnostics }
  }
  { content_filters: filters, diagnostics: [] }
}

///|
fn required_content_filter_value(
  entries : Array[(String, String)],
  key : String,
  span : @markdown.Span,
  diagnostics : Array[@mdx.MdxDiagnostic],
) -> String {
  match frontmatter_value(entries, key) {
    Some(value) if !value.is_empty() => value
    _ => {
      diagnostics.push(
        reader_profile_diagnostic(
          "missing-content-filter-prop",
          "Content filter requires '" + key + "'",
          span,
        ),
      )
      ""
    }
  }
}

///|
fn required_profile_value(
  entries : Array[(String, String)],
  key : String,
  span : @markdown.Span,
  diagnostics : Array[@mdx.MdxDiagnostic],
) -> String {
  match frontmatter_value(entries, key) {
    Some(value) if !value.is_empty() => value
    _ => {
      diagnostics.push(
        reader_profile_diagnostic(
          "missing-reader-profile-prop",
          "Reader profile requires '" + key + "'",
          span,
        ),
      )
      ""
    }
  }
}

///|
fn frontmatter_value(
  entries : Array[(String, String)],
  key : String,
) -> String? {
  for entry in entries {
    let (entry_key, value) = entry
    if entry_key == key {
      return Some(value)
    }
  }
  None
}

///|
fn has_reader_profile_entries(entries : Array[(String, String)]) -> Bool {
  for entry in entries {
    let (key, _) = entry
    if key.has_prefix("folddown.reader.") {
      return true
    }
  }
  false
}

///|
fn has_content_filter_entries(entries : Array[(String, String)]) -> Bool {
  for entry in entries {
    let (key, _) = entry
    if key.has_prefix("folddown.content_filter.") {
      return true
    }
  }
  false
}

///|
fn split_csv(value : String) -> Array[String] {
  let values : Array[String] = []
  for part in value.split(",") {
    let trimmed = part.to_owned().trim(chars=" \t\n\r").to_owned()
    if !trimmed.is_empty() {
      values.push(trimmed)
    }
  }
  values
}

///|
fn string_in_array(values : Array[String], needle : String) -> Bool {
  for value in values {
    if value == needle {
      return true
    }
  }
  false
}

///|
fn is_fold_level(value : String) -> Bool {
  value == "intro" ||
  value == "basic" ||
  value == "advanced" ||
  value == "expert"
}

///|
fn is_content_filter_mode(value : String) -> Bool {
  value == "all" || value == "unfamiliar"
}

///|
fn reader_profile_diagnostic(
  code : String,
  message : String,
  span : @markdown.Span,
) -> @mdx.MdxDiagnostic {
  { code, message, span }
}
