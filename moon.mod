name = "mizchi/markdown"

version = "0.8.3"

import {
  "moonbitlang/async@0.20.3",
  "moonbitlang/parser@0.3.18",
  "moonbitlang/x@0.5.1",
  "mizchi/syntree@0.2.4",
  "mizchi/moomaid@0.4.0",
}

readme = "README.md"

repository = "https://github.com/mizchi/markdown.mbt"

license = "MIT"

keywords = [ "markdown", "parser", "cst", "incremental", "gfm" ]

description = "Incremental Markdown parser and compiler"

source = "src"

preferred_target = "js"

supported_targets = "js+wasm+wasm-gc+native"
