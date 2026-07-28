///| Declarative MDX component schemas.

///|
/// This module intentionally accepts a literal-only expression subset. It does
/// not evaluate JavaScript, so schemas remain deterministic and safe to use in
/// document build pipelines.

///|
/// The value shapes accepted by a component property.
pub(all) enum MdxValueType {
  Text
  Flag
  TextList
  OneOf(Array[String])
} derive(Eq, Debug)

///|
/// A decoded literal from an MDX attribute.
pub(all) enum MdxLiteral {
  Text(String)
  Flag(Bool)
  TextList(Array[String])
} derive(Eq, Debug)

///|
/// A component property declaration.
pub(all) struct PropSchema {
  name : String
  value_type : MdxValueType
  required : Bool
} derive(Eq, Debug)

///|
/// Create a required component property.
pub fn PropSchema::required(
  name : String,
  value_type : MdxValueType,
) -> PropSchema {
  { name, value_type, required: true }
}

///|
/// Create an optional component property.
pub fn PropSchema::optional(
  name : String,
  value_type : MdxValueType,
) -> PropSchema {
  { name, value_type, required: false }
}

///|
/// A typed MDX component declaration.
pub(all) struct ComponentSchema {
  tag : String
  props : Array[PropSchema]
} derive(Eq, Debug)

///|
/// Create a component schema.
pub fn ComponentSchema::new(
  tag : String,
  props : Array[PropSchema],
) -> ComponentSchema {
  { tag, props }
}

///|
/// A closed set of MDX components permitted in a document.
pub(all) struct MdxSchema {
  components : Array[ComponentSchema]
} derive(Eq, Debug)

///|
/// Create a schema that rejects components without a declaration.
pub fn MdxSchema::closed(components : Array[ComponentSchema]) -> MdxSchema {
  { components, }
}

///|
/// A type-checked component property.
pub(all) struct TypedMdxAttribute {
  name : String
  value : MdxLiteral
} derive(Eq, Debug)

///|
/// A component that passed schema validation.
pub(all) struct TypedMdxElement {
  tag : String
  attributes : Array[TypedMdxAttribute]
  span : @markdown.Span
} derive(Eq, Debug)

///|
/// A schema validation diagnostic.
pub(all) struct MdxDiagnostic {
  code : String
  message : String
  span : @markdown.Span
} derive(Eq, Debug)

///|
/// The typed elements and all diagnostics found in a document.
pub(all) struct MdxTypeCheckResult {
  elements : Array[TypedMdxElement]
  diagnostics : Array[MdxDiagnostic]
} derive(Debug)

///|
/// Whether the document contains no schema errors.
pub fn MdxTypeCheckResult::is_valid(self : MdxTypeCheckResult) -> Bool {
  self.diagnostics.is_empty()
}

///|
/// Parse MDX blocks and validate JSX components against a closed schema.
pub fn type_check_mdx(
  doc : @markdown.Document,
  schema : MdxSchema,
) -> MdxTypeCheckResult {
  let elements : Array[TypedMdxElement] = []
  let diagnostics : Array[MdxDiagnostic] = []
  let blocks = parse_mdx_blocks(doc)
  for block in blocks {
    match block {
      JsxElement(tag~, attributes~, span~, ..) =>
        type_check_element(tag, attributes, span, schema, elements, diagnostics)
      _ => ()
    }
  }
  { elements, diagnostics }
}

///|
/// Validate one JSX component and append its typed representation on success.
fn type_check_element(
  tag : String,
  attributes : Array[MdxAttribute],
  span : @markdown.Span,
  schema : MdxSchema,
  elements : Array[TypedMdxElement],
  diagnostics : Array[MdxDiagnostic],
) -> Unit {
  match find_component(schema, tag) {
    None =>
      diagnostics.push(MdxDiagnostic::{
        code: "unknown-component",
        message: "No schema declares <" + tag + ">",
        span,
      })
    Some(component) => {
      let diagnostic_count_before = diagnostics.length()
      let typed_attributes : Array[TypedMdxAttribute] = []
      let seen : Array[String] = []

      for prop in component.props {
        if prop.required && !has_attribute(attributes, prop.name) {
          diagnostics.push(MdxDiagnostic::{
            code: "missing-required-prop",
            message: "<" + tag + "> requires the '" + prop.name + "' prop",
            span,
          })
        }
      }

      for attribute in attributes {
        if string_in_array(seen, attribute.name) {
          diagnostics.push(MdxDiagnostic::{
            code: "duplicate-prop",
            message: "<" +
            tag +
            "> declares '" +
            attribute.name +
            "' more than once",
            span,
          })
        } else {
          seen.push(attribute.name)
          match find_prop(component, attribute.name) {
            None =>
              diagnostics.push(MdxDiagnostic::{
                code: "unknown-prop",
                message: "<" +
                tag +
                "> does not declare the '" +
                attribute.name +
                "' prop",
                span,
              })
            Some(prop) =>
              match decode_literal(attribute.value) {
                None =>
                  diagnostics.push(MdxDiagnostic::{
                    code: "invalid-literal",
                    message: "'" +
                    attribute.name +
                    "' must use a declarative literal",
                    span,
                  })
                Some(value) =>
                  if literal_matches(value, prop.value_type) {
                    typed_attributes.push({ name: attribute.name, value })
                  } else {
                    diagnostics.push(MdxDiagnostic::{
                      code: "type-mismatch",
                      message: "'" +
                      attribute.name +
                      "' does not match its schema type",
                      span,
                    })
                  }
              }
          }
        }
      }

      if diagnostics.length() == diagnostic_count_before {
        elements.push(TypedMdxElement::{
          tag,
          attributes: typed_attributes,
          span,
        })
      }
    }
  }
}

///|
/// Find a component declaration by tag name.
fn find_component(schema : MdxSchema, tag : String) -> ComponentSchema? {
  for component in schema.components {
    if component.tag == tag {
      return Some(component)
    }
  }
  None
}

///|
/// Find a property declaration by property name.
fn find_prop(component : ComponentSchema, name : String) -> PropSchema? {
  for prop in component.props {
    if prop.name == name {
      return Some(prop)
    }
  }
  None
}

///|
/// Check whether a JSX attribute is present.
fn has_attribute(attributes : Array[MdxAttribute], name : String) -> Bool {
  for attribute in attributes {
    if attribute.name == name {
      return true
    }
  }
  false
}

///|
/// Decode a string, boolean, or string-array literal without evaluating code.
fn decode_literal(value : MdxAttrValue) -> MdxLiteral? {
  match value {
    StringValue(text) => Some(MdxLiteral::Text(text))
    BooleanValue => Some(MdxLiteral::Flag(true))
    ExpressionValue(expression) => decode_expression_literal(expression)
  }
}

///|
/// Decode the literal subset permitted inside `{...}`.
fn decode_expression_literal(expression : String) -> MdxLiteral? {
  let text = trim_expression(expression)
  if text == "true" {
    return Some(MdxLiteral::Flag(true))
  }
  if text == "false" {
    return Some(MdxLiteral::Flag(false))
  }

  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  if chars[0] == '[' {
    match parse_text_list(chars) {
      Some(values) => Some(MdxLiteral::TextList(values))
      None => None
    }
  } else {
    match parse_quoted(chars, 0) {
      Some((value, end)) if end == chars.length() =>
        Some(MdxLiteral::Text(value))
      _ => None
    }
  }
}

///|
/// Parse a bracketed array of quoted strings.
fn parse_text_list(chars : Array[Char]) -> Array[String]? {
  let len = chars.length()
  if len < 2 || chars[0] != '[' {
    return None
  }

  let values : Array[String] = []
  let mut pos = 1
  while true {
    pos = skip_space(chars, pos)
    if pos >= len {
      return None
    }
    if chars[pos] == ']' {
      return if pos + 1 == len { Some(values) } else { None }
    }

    match parse_quoted(chars, pos) {
      None => return None
      Some((value, end)) => {
        values.push(value)
        pos = skip_space(chars, end)
        if pos >= len {
          return None
        }
        if chars[pos] == ',' {
          pos += 1
        } else if chars[pos] == ']' {
          return if pos + 1 == len { Some(values) } else { None }
        } else {
          return None
        }
      }
    }
  }
  None
}

///|
/// Parse one quoted string and return the first position after its quote.
fn parse_quoted(chars : Array[Char], start : Int) -> (String, Int)? {
  if start >= chars.length() || (chars[start] != '"' && chars[start] != '\'') {
    return None
  }

  let quote = chars[start]
  let buf = StringBuilder::new()
  let mut pos = start + 1
  while pos < chars.length() {
    let current = chars[pos]
    if current == quote {
      return Some((buf.to_string(), pos + 1))
    }
    if current == '\\' && pos + 1 < chars.length() {
      pos += 1
    }
    buf.write_char(chars[pos])
    pos += 1
  }
  None
}

///|
/// Skip ASCII whitespace in a literal.
fn skip_space(chars : Array[Char], start : Int) -> Int {
  let mut pos = start
  while pos < chars.length() && is_literal_space(chars[pos]) {
    pos += 1
  }
  pos
}

///|
/// Trim ASCII whitespace from both ends of an expression.
fn trim_expression(expression : String) -> String {
  expression.trim(chars=" \t\n\r").to_owned()
}

///|
/// Check whether a character is literal whitespace.
fn is_literal_space(char : Char) -> Bool {
  char == ' ' || char == '\t' || char == '\n' || char == '\r'
}

///|
/// Check whether a literal conforms to the schema type.
fn literal_matches(value : MdxLiteral, value_type : MdxValueType) -> Bool {
  match (value, value_type) {
    (MdxLiteral::Text(_), MdxValueType::Text) => true
    (MdxLiteral::Flag(_), MdxValueType::Flag) => true
    (MdxLiteral::TextList(_), MdxValueType::TextList) => true
    (MdxLiteral::Text(text), MdxValueType::OneOf(options)) =>
      string_in_array(options, text)
    _ => false
  }
}

///|
/// Check whether an array contains a string without allocating an iterator.
fn string_in_array(values : Array[String], target : String) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}
