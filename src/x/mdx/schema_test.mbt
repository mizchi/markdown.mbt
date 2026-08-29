///| Typed declarative MDX schema tests.

///|
/// Build the schema Folddown needs without allowing arbitrary JavaScript.
fn fold_schema() -> MdxSchema {
  MdxSchema::closed([
    ComponentSchema::new("Fold", [
      PropSchema::required("id", MdxValueType::Text),
      PropSchema::required(
        "kind",
        MdxValueType::OneOf(["concept", "procedure", "reference", "evidence"]),
      ),
      PropSchema::optional("locale", MdxValueType::Text),
      PropSchema::optional("requires", MdxValueType::TextList),
      PropSchema::optional("roles", MdxValueType::TextList),
    ]),
  ])
}

///|
/// String, enum, and list declarations are decoded into typed values.
test "type checks declarative MDX attributes" {
  let source =
    #|<Fold
    #|  id="auth.mfa.recovery-codes"
    #|  kind="procedure"
    #|  locale="ja"
    #|  requires={["auth.mfa"]}
    #|  roles={["operator"]}>
    #|  Recovery codes are stored outside the primary authenticator.
    #|</Fold>
    #|
  let doc = @markdown.parse(source).document
  let result = type_check_mdx(doc, fold_schema())

  assert_true(result.is_valid())
  @debug.assert_eq(result.elements.length(), 1)
  let attributes = result.elements[0].attributes
  @debug.assert_eq(attributes.length(), 5)
  @debug.assert_eq(attributes[3].value, MdxLiteral::TextList(["auth.mfa"]))
}

///|
/// Required declarations and schema membership are checked before rendering.
test "reports missing and unknown attributes" {
  let source =
    #|<Fold locale="ja" audience="beginner" />
  let doc = @markdown.parse(source).document
  let result = type_check_mdx(doc, fold_schema())

  assert_false(result.is_valid())
  @debug.assert_eq(result.diagnostics.length(), 3)
  @debug.assert_eq(result.diagnostics[0].code, "missing-required-prop")
  @debug.assert_eq(result.diagnostics[2].code, "unknown-prop")
}

///|
/// Dynamic expressions are deliberately outside the declarative subset.
test "rejects dynamic expressions and type mismatches" {
  let source =
    #|<Fold id="auth.mfa" kind="procedure" requires={loadRequirements()} />
    #|
  let doc = @markdown.parse(source).document
  let result = type_check_mdx(doc, fold_schema())

  assert_false(result.is_valid())
  @debug.assert_eq(result.diagnostics.length(), 1)
  @debug.assert_eq(result.diagnostics[0].code, "invalid-literal")
}

///|
/// A literal still has to match the property type declared by the schema.
test "reports a literal type mismatch" {
  let source =
    #|<Fold id="auth.mfa" kind="procedure" requires="auth.login" />
  let doc = @markdown.parse(source).document
  let result = type_check_mdx(doc, fold_schema())

  assert_false(result.is_valid())
  @debug.assert_eq(result.diagnostics.length(), 1)
  @debug.assert_eq(result.diagnostics[0].code, "type-mismatch")
}
