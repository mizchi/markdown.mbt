const wasmUrl = new URL("./markdown.wasm", import.meta.url);

async function loadWasm() {
  const compileOptions = {
    builtins: ["js-string"],
    importedStringConstants: "_",
  };
  if (wasmUrl.protocol === "file:") {
    const nodeFs = "node:fs/promises";
    const { readFile } = await import(nodeFs);
    return WebAssembly.instantiate(await readFile(wasmUrl), {}, compileOptions);
  }

  const response = await fetch(wasmUrl);
  if (WebAssembly.instantiateStreaming) {
    try {
      return await WebAssembly.instantiateStreaming(
        response.clone(),
        {},
        compileOptions
      );
    } catch {
      // Some static hosts do not serve .wasm as application/wasm.
    }
  }
  return WebAssembly.instantiate(
    await response.arrayBuffer(),
    {},
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

export function parse(source, options = {}) {
  assertSource(source);
  const json = useWikilinks(options)
    ? wasm.md_to_ast_json_with_wikilinks(source)
    : wasm.md_to_ast_json(source);
  return JSON.parse(json);
}

export function toHtml(source, options = {}) {
  assertSource(source);
  const wikilinks = useWikilinks(options);
  const autolink = useAutolink(options);
  if (wikilinks && autolink) {
    return wasm.md_to_html_with_wikilinks_and_autolink(source);
  }
  if (wikilinks) {
    return wasm.md_to_html_with_wikilinks_without_autolink(source);
  }
  if (!autolink) {
    return wasm.md_to_html_without_autolink(source);
  }
  return wasm.md_to_html(source);
}

export function toMarkdown(source, options = {}) {
  assertSource(source);
  return useWikilinks(options)
    ? wasm.md_to_markdown_with_wikilinks(source)
    : wasm.md_to_markdown(source);
}
