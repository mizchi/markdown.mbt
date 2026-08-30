///| Direct JavaScript AST conversion.

///|
/// Opaque JavaScript value used only at the JS FFI boundary.
#external
type JsValue

///|
extern "js" fn js_null() -> JsValue =
  #| () => null

///|
extern "js" fn js_bool(value : Bool) -> JsValue =
  #| (value) => value

///|
extern "js" fn js_number(value : Double) -> JsValue =
  #| (value) => value

///|
extern "js" fn js_string(value : String) -> JsValue =
  #| (value) => value

///|
extern "js" fn js_array_new() -> JsValue =
  #| () => []

///|
extern "js" fn js_array_push(array : JsValue, value : JsValue) -> Unit =
  #| (array, value) => { array.push(value); }

///|
extern "js" fn js_object_new() -> JsValue =
  #| () => ({})

///|
extern "js" fn js_object_set(
  object : JsValue,
  key : String,
  value : JsValue,
) -> Unit =
  #| (object, key, value) => { object[key] = value; }

///|
/// Convert MoonBit's structured Json representation to ordinary JavaScript
/// values without serializing and reparsing a large intermediate string.
fn json_to_js(value : Json) -> JsValue {
  match value {
    Json::Null => js_null()
    Json::True => js_bool(true)
    Json::False => js_bool(false)
    Json::Number(number, ..) => js_number(number)
    Json::String(string) => js_string(string)
    Json::Array(values) => {
      let array = js_array_new()
      for item in values {
        js_array_push(array, json_to_js(item))
      }
      array
    }
    Json::Object(members) => {
      let object = js_object_new()
      for key, item in members {
        js_object_set(object, key, json_to_js(item))
      }
      object
    }
  }
}

///|
/// Parse Markdown and return the mdast-compatible JavaScript object directly.
pub fn md_to_ast_object(source : String) -> JsValue {
  let result = @markdown.parse(source)
  json_to_js(document_to_json_value(result.document))
}

///|
/// Parse Markdown with wikilinks and return the JavaScript object directly.
pub fn md_to_ast_object_with_wikilinks(source : String) -> JsValue {
  let result = @markdown.parse(source, wikilinks=true)
  json_to_js(document_to_json_value(result.document))
}
