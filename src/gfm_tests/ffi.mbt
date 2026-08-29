///| FFI bindings for remark compatibility testing
///| This file is JS-target only

///| Call remark with GFM support to process markdown (sync via require)
///| Returns stringified result from remark
pub extern "js" fn remark_stringify(input : String) -> String =
  #| (input) => {
  #|   const { remark } = require('remark');
  #|   const remarkGfm = require('remark-gfm').default;
  #|   const result = remark().use(remarkGfm).processSync(input);
  #|   return normalizeBulletMarkers(String(result));
  #|
  #|   function normalizeBulletMarkers(markdown) {
  #|     let inFence = false;
  #|     let fenceChar = "";
  #|     let fenceLen = 0;
  #|     return markdown.split("\n").map((line) => {
  #|       const fence = line.match(/^[ \t]{0,3}(`{3,}|~{3,})/);
  #|       if (fence) {
  #|         const marker = fence[1];
  #|         const ch = marker[0];
  #|         if (!inFence) {
  #|           inFence = true;
  #|           fenceChar = ch;
  #|           fenceLen = marker.length;
  #|         } else if (ch === fenceChar && marker.length >= fenceLen) {
  #|           inFence = false;
  #|         }
  #|         return line;
  #|       }
  #|       if (inFence) return line;
  #|       return line.replace(/^((?:[ \t]*>\s*)*[ \t]*)\* (?=\S)/, "$1- ");
  #|     }).join("\n");
  #|   }
  #| }
