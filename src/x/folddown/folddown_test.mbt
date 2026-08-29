///|
/// Folddown declaration validation tests.
test "validate_source accepts a typed Fold declaration" {
  let source =
    #|<Fold
    #|  id="auth.mfa.recovery-codes"
    #|  kind="procedure"
    #|  level="basic"
    #|  locale="ja"
    #|  requires={["auth.mfa"]}
    #|  roles={["operator"]}>
    #|## Recovery codes
    #|
    #|Store recovery codes outside the primary authenticator.
    #|</Fold>
    #|

  let result = @folddown.validate_source(source)

  assert_true(result.is_valid())
  assert_eq(result.elements.length(), 1)
}

///|
/// Dynamic JavaScript stays outside the document declaration language.
test "validate_source rejects dynamic metadata" {
  let source =
    #|<Fold id="auth.mfa" kind="procedure" level="basic" requires={loadRequirements()} />
  let result = @folddown.validate_source(source)

  assert_false(result.is_valid())
  assert_eq(result.diagnostics[0].code, "invalid-literal")
}

///|
/// Canonical documents can contain ordinary Markdown without declarations.
test "validate_source accepts unannotated Markdown" {
  let source = "# Plain document\n\nVisible to everyone.\n"
  let result = @folddown.validate_source(source)

  assert_true(result.is_valid())
  assert_eq(result.elements.length(), 0)
}

///|
/// The Fold vocabulary is closed, so declaration typos do not pass validation.
test "validate_source rejects an unknown component" {
  let source =
    #|<Fodl id="auth.mfa" kind="procedure" />
  let result = @folddown.validate_source(source)

  assert_false(result.is_valid())
  assert_eq(result.diagnostics[0].code, "unknown-component")
}

///|
/// Disclosure needs an explicit content level; the viewer never infers one.
test "validate_source requires a Fold level" {
  let source =
    #|<Fold id="auth.mfa" kind="procedure" />
  let result = @folddown.validate_source(source)

  assert_false(result.is_valid())
  assert_eq(result.diagnostics[0].code, "missing-required-prop")
}

///|
/// A reader manifest must retain both typed metadata and Markdown children.
test "parse_source extracts a canonical Fold node" {
  let source =
    #|<Fold
    #|  id="moonbit.bindings.typescript.ja"
    #|  kind="concept"
    #|  level="basic"
    #|  locale="ja"
    #|  roles={["typescript-programmer"]}
    #|  requires={["moonbit.overview.ja"]}>
    #|## Immutable bindings
    #|
    #|Use `let mut` only where a value changes.
    #|</Fold>

  let result = @folddown.parse_source(source)

  assert_true(result.diagnostics.is_empty())
  assert_eq(result.nodes.length(), 1)
  let node = result.nodes[0]
  assert_eq(node.id, "moonbit.bindings.typescript.ja")
  assert_eq(node.roles, ["typescript-programmer"])
  assert_eq(
    node.body,
    "## Immutable bindings\n\nUse `let mut` only where a value changes.",
  )
}

///|
/// Direct correspondences are declared per source-language audience so an
/// interest-focused view can omit familiar material without guessing.
test "parse_source extracts a Fold's familiar reader roles" {
  let source =
    #|<Fold
    #|  id="moonbit.bindings.typescript.ja"
    #|  kind="concept"
    #|  level="basic"
    #|  familiarTo={[
    #|    "typescript-programmer",
    #|    "rust-programmer",
    #|  ]}>
    #|## Immutable bindings
    #|</Fold>

  let result = @folddown.parse_source(source)

  assert_true(result.diagnostics.is_empty())
  assert_eq(result.nodes[0].familiar_to, [
    "typescript-programmer", "rust-programmer",
  ])
}

///|
/// Reader states are generated from the typed frontmatter DSL, not viewer code.
test "parse_source extracts two reader profiles from frontmatter" {
  let source =
    #|---
    #|folddown.readers: first_time,some_knowledge
    #|folddown.reader.first_time.label.ja: 初めて知った
    #|folddown.reader.first_time.label.en: First time
    #|folddown.reader.first_time.collapse: none
    #|folddown.reader.some_knowledge.label.ja: 多少知ってる
    #|folddown.reader.some_knowledge.label.en: Know some
    #|folddown.reader.some_knowledge.collapse: intro
    #|---
    #|<Fold id="intro" kind="concept" level="intro">## Intro</Fold>

  let result = @folddown.parse_source(source)

  assert_true(result.diagnostics.is_empty())
  assert_eq(result.reader_profiles.length(), 2)
  assert_eq(result.reader_profiles[0].id, "first_time")
  assert_eq(result.reader_profiles[0].label_ja, "初めて知った")
  assert_eq(result.reader_profiles[0].collapse_levels, [])
  assert_eq(result.reader_profiles[1].collapse_levels, ["intro"])
}

///|
/// Content filters are generated from frontmatter and remain independent from
/// the reader's disclosure state.
test "parse_source extracts two content filters from frontmatter" {
  let source =
    #|---
    #|folddown.content_filters: detail,interesting
    #|folddown.content_filter.detail.label.ja: 詳しく知りたい
    #|folddown.content_filter.detail.label.en: Learn in detail
    #|folddown.content_filter.detail.mode: all
    #|folddown.content_filter.interesting.label.ja: 面白い機能だけを知りたい
    #|folddown.content_filter.interesting.label.en: Interesting features only
    #|folddown.content_filter.interesting.mode: unfamiliar
    #|---
    #|<Fold id="intro" kind="concept" level="intro">## Intro</Fold>

  let result = @folddown.parse_source(source)

  assert_true(result.diagnostics.is_empty())
  assert_eq(result.content_filters.length(), 2)
  assert_eq(result.content_filters[0].id, "detail")
  assert_eq(result.content_filters[0].mode, "all")
  assert_eq(result.content_filters[1].id, "interesting")
  assert_eq(result.content_filters[1].mode, "unfamiliar")
}

///|
/// A profile may only collapse declared Folddown content levels.
test "parse_source rejects an unknown reader profile collapse level" {
  let source =
    #|---
    #|folddown.readers: first_time,some_knowledge
    #|folddown.reader.first_time.label.ja: 初めて知った
    #|folddown.reader.first_time.label.en: First time
    #|folddown.reader.first_time.collapse: none
    #|folddown.reader.some_knowledge.label.ja: 多少知ってる
    #|folddown.reader.some_knowledge.label.en: Know some
    #|folddown.reader.some_knowledge.collapse: intermediate
    #|---

  let result = @folddown.parse_source(source)

  assert_false(result.diagnostics.is_empty())
  assert_eq(result.diagnostics[0].code, "unknown-reader-profile-level")
}

///|
/// The compact reader selector deliberately has two declared states.
test "parse_source requires exactly two reader profiles" {
  let source =
    #|---
    #|folddown.readers: first_time
    #|folddown.reader.first_time.label.ja: 初めて知った
    #|folddown.reader.first_time.label.en: First time
    #|folddown.reader.first_time.collapse: none
    #|---

  let result = @folddown.parse_source(source)

  assert_false(result.diagnostics.is_empty())
  assert_eq(result.diagnostics[0].code, "reader-profile-count")
}

///|
/// External documents are declared through a literal, self-closing Include.
test "parse_include_source extracts a typed external document include" {
  let source =
    #|<Include src="./fragments/overview.ja.mdx" sync="moonbit-overview" />

  let result = @folddown.parse_include_source(source)

  assert_true(result.diagnostics.is_empty())
  assert_eq(result.includes.length(), 1)
  assert_eq(result.includes[0].src, "./fragments/overview.ja.mdx")
  assert_eq(result.includes[0].sync, Some("moonbit-overview"))
}

///|
/// Include does not have a body: replacement must be unambiguous.
test "parse_include_source rejects a non-self-closing Include" {
  let source =
    #|<Include src="./fragments/overview.ja.mdx">ignored</Include>

  let result = @folddown.parse_include_source(source)

  assert_false(result.diagnostics.is_empty())
  assert_eq(result.diagnostics[0].code, "include-must-be-self-closing")
}
