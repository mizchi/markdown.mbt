name = "mizchi/markdown"

version = "0.8.4"

import {
  "moonbitlang/async@0.22.5",
  "moonbitlang/parser@0.4.5",
  "moonbitlang/x@0.5.5",
  "mizchi/syntree@0.2.4",
  "mizchi/moomaid@0.4.0",
  // Minimum migrated versions for moomaid's transitive dependencies.
  "mizchi/font@0.7.4",
  "mizchi/layout@0.2.1",
  "mizchi/pixelmatch@0.6.2",
  "mizchi/tui-terminal-buffer@0.1.4",
  // MoonBit 0.10.16 reserves Float; these versions use CssFloat.
  "mizchi/css@0.7.4",
  "mizchi/crater-layout@0.19.1",
}

readme = "README.md"

repository = "https://github.com/mizchi/markdown.mbt"

license = "MIT"

keywords = [ "markdown", "parser", "cst", "incremental", "gfm" ]

description = "Incremental Markdown parser and compiler"

source = "src"

preferred_target = "js"

supported_targets = "js+wasm+wasm-gc+native"
