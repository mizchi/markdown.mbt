///| MDX Types
///|
///| Type definitions for MDX parsing including import/export statements,
///| JSX elements, and Web Components.

// =============================================================================
// Import/Export Types
// =============================================================================

///|
/// Import specifier (e.g., `{ X, Y as Z }` or `X` for default)
pub(all) struct ImportSpecifier {
  name : String
  local_name : String?     // as X (renamed from alias)
  is_default : Bool
  is_star : Bool           // import * as X (renamed from is_namespace)
} derive(Eq, Show)

///|
/// Create a named import specifier
pub fn ImportSpecifier::named(name : String) -> ImportSpecifier {
  { name, local_name: None, is_default: false, is_star: false }
}

///|
/// Create an aliased import specifier
pub fn ImportSpecifier::with_local(name : String, renamed : String) -> ImportSpecifier {
  { name, local_name: Some(renamed), is_default: false, is_star: false }
}

///|
/// Create a default import specifier
pub fn ImportSpecifier::default_import(name : String) -> ImportSpecifier {
  { name, local_name: None, is_default: true, is_star: false }
}

///|
/// Create a namespace import specifier
pub fn ImportSpecifier::star(name : String) -> ImportSpecifier {
  { name, local_name: None, is_default: false, is_star: true }
}

///|
/// Export declaration kind
pub(all) enum ExportKind {
  Const
  Let
  Function
  Default
  Named  // export { x, y }
} derive(Eq, Show)

// =============================================================================
// Attribute Types
// =============================================================================

///|
/// Attribute value type
pub(all) enum MdxAttrValue {
  StringValue(String)     // prop="value" or prop='value'
  ExpressionValue(String) // prop={expression}
  BooleanValue            // prop (true)
} derive(Eq, Show)

///|
/// JSX/Web Component attribute
pub(all) struct MdxAttribute {
  name : String
  value : MdxAttrValue
} derive(Eq, Show)

///|
/// Create a string attribute
pub fn MdxAttribute::string(name : String, value : String) -> MdxAttribute {
  { name, value: StringValue(value) }
}

///|
/// Create an expression attribute
pub fn MdxAttribute::expression(name : String, expr : String) -> MdxAttribute {
  { name, value: ExpressionValue(expr) }
}

///|
/// Create a boolean attribute
pub fn MdxAttribute::boolean(name : String) -> MdxAttribute {
  { name, value: BooleanValue }
}

// =============================================================================
// MDX Block Types
// =============================================================================

///|
/// MDX block-level elements
pub(all) enum MdxBlock {
  /// Import declaration: import { X } from 'source'
  ImportDecl(
    specifiers~ : Array[ImportSpecifier],
    source~ : String,
    span~ : @markdown.Span,
    raw~ : String
  )
  /// Export declaration: export const x = ...
  ExportDecl(
    kind~ : ExportKind,
    name~ : String?,
    value~ : String,
    span~ : @markdown.Span,
    raw~ : String
  )
  /// JSX/Web Component element
  JsxElement(
    tag~ : String,
    attributes~ : Array[MdxAttribute],
    children~ : String,
    self_closing~ : Bool,
    span~ : @markdown.Span
  )
} derive(Eq, Show)

///|
/// Check if a block is an import declaration
pub fn MdxBlock::is_import(self : MdxBlock) -> Bool {
  match self {
    ImportDecl(..) => true
    _ => false
  }
}

///|
/// Check if a block is an export declaration
pub fn MdxBlock::is_export(self : MdxBlock) -> Bool {
  match self {
    ExportDecl(..) => true
    _ => false
  }
}

///|
/// Check if a block is a JSX element
pub fn MdxBlock::is_jsx(self : MdxBlock) -> Bool {
  match self {
    JsxElement(..) => true
    _ => false
  }
}

///|
/// Get the span of the block
pub fn MdxBlock::span(self : MdxBlock) -> @markdown.Span {
  match self {
    ImportDecl(span~, ..) => span
    ExportDecl(span~, ..) => span
    JsxElement(span~, ..) => span
  }
}

///|
/// Get the tag name if this is a JSX element
pub fn MdxBlock::tag_name(self : MdxBlock) -> String? {
  match self {
    JsxElement(tag~, ..) => Some(tag)
    _ => None
  }
}

// =============================================================================
// MDX Metadata
// =============================================================================

///|
/// Extracted MDX metadata
pub(all) struct MdxMetadata {
  imports : Array[MdxBlock]
  exports : Array[MdxBlock]
  components : Array[String]
} derive(Eq, Show)

///|
/// Create empty metadata
pub fn MdxMetadata::empty() -> MdxMetadata {
  { imports: [], exports: [], components: [] }
}

///|
/// Check if metadata is empty
pub fn MdxMetadata::is_empty(self : MdxMetadata) -> Bool {
  self.imports.is_empty() && self.exports.is_empty() && self.components.is_empty()
}

// =============================================================================
// Helper Functions
// =============================================================================

///|
/// Check if a tag name is a JSX component (starts with uppercase)
pub fn is_jsx_component(tag : String) -> Bool {
  let chars = tag.to_array()
  if chars.length() == 0 {
    return false
  }
  let first = chars[0]
  first >= 'A' && first <= 'Z'
}

///|
/// Check if a tag name is a Web Component (contains hyphen)
pub fn is_web_component(tag : String) -> Bool {
  tag.contains("-")
}

///|
/// Check if a tag should be treated as MDX (JSX or Web Component)
pub fn is_mdx_tag(tag : String) -> Bool {
  is_jsx_component(tag) || is_web_component(tag)
}
