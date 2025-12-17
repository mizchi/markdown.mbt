// 
import { md_parse, md_render_to_string, md_free } from "./target/js/release/build/markdown.js";

const handle = md_parse("# Hello\n\nWorld");
const output = md_render_to_string(handle);
console.log(output); // "# Hello\n\nWorld"
md_free(handle);