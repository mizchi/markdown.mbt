///|
test "parse: lang only" {
  let info = parse_code_block_info("javascript")
  @debug.debug_inspect(info.lang, content=(
    #|"javascript"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|""
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: lang with filename" {
  let info = parse_code_block_info("js:app.js")
  @debug.debug_inspect(info.lang, content=(
    #|"js"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"app.js"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: lang with path filename" {
  let info = parse_code_block_info("typescript:src/index.ts")
  @debug.debug_inspect(info.lang, content=(
    #|"typescript"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"src/index.ts"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: lang with meta" {
  let info = parse_code_block_info("js {highlight=[1,3]}")
  @debug.debug_inspect(info.lang, content=(
    #|"js"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|""
  ))
  @debug.debug_inspect(info.meta, content=(
    #|"{highlight=[1,3]}"
  ))
}

///|
test "parse: lang, filename, and meta" {
  let info = parse_code_block_info("ts:index.ts {highlight=[1,3]}")
  @debug.debug_inspect(info.lang, content=(
    #|"ts"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"index.ts"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|"{highlight=[1,3]}"
  ))
}

///|
test "parse: preserves emoji filename" {
  let info = parse_code_block_info("ts:src/😀.ts")
  @debug.debug_inspect(info.lang, content=(
    #|"ts"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"src/😀.ts"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: preserves emoji meta" {
  let info = parse_code_block_info("ts:index.ts {title=😀}")
  @debug.debug_inspect(info.lang, content=(
    #|"ts"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"index.ts"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|"{title=😀}"
  ))
}

///|
test "parse: empty string" {
  let info = parse_code_block_info("")
  @debug.debug_inspect(info.lang, content=(
    #|""
  ))
  @debug.debug_inspect(info.filename, content=(
    #|""
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: whitespace only" {
  let info = parse_code_block_info("  ")
  @debug.debug_inspect(info.lang, content=(
    #|""
  ))
  @debug.debug_inspect(info.filename, content=(
    #|""
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}

///|
test "parse: json package.json" {
  let info = parse_code_block_info("json:package.json")
  @debug.debug_inspect(info.lang, content=(
    #|"json"
  ))
  @debug.debug_inspect(info.filename, content=(
    #|"package.json"
  ))
  @debug.debug_inspect(info.meta, content=(
    #|""
  ))
}
