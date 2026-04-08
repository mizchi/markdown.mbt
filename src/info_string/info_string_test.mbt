///|
test "parse: lang only" {
  let info = parse("javascript")
  inspect(info.lang, content="javascript")
  inspect(info.filename, content="")
  inspect(info.meta, content="")
}

///|
test "parse: lang with filename" {
  let info = parse("js:app.js")
  inspect(info.lang, content="js")
  inspect(info.filename, content="app.js")
  inspect(info.meta, content="")
}

///|
test "parse: lang with path filename" {
  let info = parse("typescript:src/index.ts")
  inspect(info.lang, content="typescript")
  inspect(info.filename, content="src/index.ts")
  inspect(info.meta, content="")
}

///|
test "parse: lang with meta" {
  let info = parse("js {highlight=[1,3]}")
  inspect(info.lang, content="js")
  inspect(info.filename, content="")
  inspect(info.meta, content="{highlight=[1,3]}")
}

///|
test "parse: lang, filename, and meta" {
  let info = parse("ts:index.ts {highlight=[1,3]}")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="index.ts")
  inspect(info.meta, content="{highlight=[1,3]}")
}

///|
test "parse: preserves emoji filename" {
  let info = parse("ts:src/😀.ts")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="src/😀.ts")
  inspect(info.meta, content="")
}

///|
test "parse: preserves emoji meta" {
  let info = parse("ts:index.ts {title=😀}")
  inspect(info.lang, content="ts")
  inspect(info.filename, content="index.ts")
  inspect(info.meta, content="{title=😀}")
}

///|
test "parse: empty string" {
  let info = parse("")
  inspect(info.lang, content="")
  inspect(info.filename, content="")
  inspect(info.meta, content="")
}

///|
test "parse: whitespace only" {
  let info = parse("  ")
  inspect(info.lang, content="")
  inspect(info.filename, content="")
  inspect(info.meta, content="")
}

///|
test "parse: json package.json" {
  let info = parse("json:package.json")
  inspect(info.lang, content="json")
  inspect(info.filename, content="package.json")
  inspect(info.meta, content="")
}
