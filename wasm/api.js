const wasmUrl = new URL("./markdown.wasm", import.meta.url);

// The Wasm GC parser builds ordinary JavaScript AST nodes through externref
// imports. JS String Builtins make every String argument below a host string,
// so neither source nor AST text needs a linear-memory copy.
const imports = {
  markdown_ast: {
    null: () => null,
    bool: (value) => Boolean(value),
    number: (value) => value,
    string: (value) => value,
    array_new: () => [],
    array_push: (array, value) => {
      array.push(value);
    },
    object_new: () => ({}),
    object_with_type: (type) => ({ type }),
    position: (from, to) => ({
      start: { offset: from },
      end: { offset: to },
    }),
    object_set: (object, key, value) => {
      object[key] = value;
    },
  },
};

async function loadWasm() {
  const compileOptions = {
    builtins: ["js-string"],
    importedStringConstants: "_",
  };
  if (wasmUrl.protocol === "file:") {
    const nodeFs = "node:fs/promises";
    const { readFile } = await import(nodeFs);
    return WebAssembly.instantiate(
      await readFile(wasmUrl),
      imports,
      compileOptions,
    );
  }

  const response = await fetch(wasmUrl);
  if (WebAssembly.instantiateStreaming) {
    try {
      return await WebAssembly.instantiateStreaming(
        response.clone(),
        imports,
        compileOptions
      );
    } catch {
      // Some static hosts do not serve .wasm as application/wasm.
    }
  }
  return WebAssembly.instantiate(
    await response.arrayBuffer(),
    imports,
    compileOptions
  );
}

const { instance } = await loadWasm();
const wasm = instance.exports;

function assertSource(source) {
  if (typeof source !== "string") {
    throw new TypeError("Markdown source must be a string");
  }
}

function useWikilinks(options) {
  return options?.wikilinks === true;
}

function useAutolink(options) {
  return options?.autolink !== false;
}

function useTagfilter(options) {
  return options?.tagfilter !== false;
}

const RENDER_WIKILINKS = 1;
const RENDER_AUTOLINK = 2;
const RENDER_TAGFILTER = 4;

function rendererFlags(options) {
  let flags = 0;
  if (useWikilinks(options)) flags |= RENDER_WIKILINKS;
  if (useAutolink(options)) flags |= RENDER_AUTOLINK;
  if (useTagfilter(options)) flags |= RENDER_TAGFILTER;
  return flags;
}

export function parse(source, options = {}) {
  assertSource(source);
  return useWikilinks(options)
    ? wasm.md_to_ast_object_with_wikilinks(source)
    : wasm.md_to_ast_object(source);
}

export function toHtml(source, options = {}) {
  assertSource(source);
  return wasm.md_to_html_with_options(source, rendererFlags(options));
}

export function toMarkdown(source, options = {}) {
  assertSource(source);
  return useWikilinks(options)
    ? wasm.md_to_markdown_with_wikilinks(source)
    : wasm.md_to_markdown(source);
}
