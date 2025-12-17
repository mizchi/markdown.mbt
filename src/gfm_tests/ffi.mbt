///| FFI bindings for remark compatibility testing

///| This file is JS-target only

///| Call remark with GFM support to process markdown (sync via require)

///|
/// Returns stringified result from remark
pub extern "js" fn remark_stringify(input : String) -> String =
  #| (input) => {
  #|   const { remark } = require('remark');
  #|   const remarkGfm = require('remark-gfm').default;
  #|   const result = remark().use(remarkGfm).processSync(input);
  #|   return String(result);
  #| }
