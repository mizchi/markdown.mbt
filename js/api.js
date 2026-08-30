/**
 * @moonbit/markdown - JavaScript API wrapper
 *
 * Provides a clean, ergonomic API for parsing and rendering Markdown.
 */

import "./inline-marker-simd.js";

import {
  md_to_html_with_options,
  md_to_html_literal,
  md_to_markdown,
  md_to_markdown_with_wikilinks,
  md_to_ast_json,
  md_to_ast_json_with_wikilinks,
  md_to_ast_object,
  md_to_ast_object_with_wikilinks,
  md_render_html_with_options,
  md_serialize,
  md_parse_with_source,
  md_parse_with_source_with_wikilinks,
  md_parse_incremental,
  md_free,
} from "../_build/js/release/build/api/api.js";

// =============================================================================
// Stateless One-shot APIs (recommended for most use cases)
// =============================================================================

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

/**
 * Parse markdown and return the AST.
 * @param {string} source - Markdown source
 * @param {{ wikilinks?: boolean, autolink?: boolean, tagfilter?: boolean }} [options] - Parser and renderer extensions
 * @returns {import('./api').Document} Parsed AST
 */
export function parse(source, options = {}) {
  return useWikilinks(options)
    ? md_to_ast_object_with_wikilinks(source)
    : md_to_ast_object(source);
}

/**
 * Convert markdown to HTML.
 * @param {string} source - Markdown source
 * @param {{ wikilinks?: boolean, autolink?: boolean, tagfilter?: boolean }} [options] - Parser and renderer extensions
 * @returns {string} HTML output
 */
export function toHtml(source, options = {}) {
  return md_to_html_with_options(source, rendererFlags(options));
}

/**
 * Normalize/serialize markdown source.
 * @param {string} source - Markdown source
 * @param {{ wikilinks?: boolean, autolink?: boolean, tagfilter?: boolean }} [options] - Parser and renderer extensions
 * @returns {string} Normalized markdown
 */
export function toMarkdown(source, options = {}) {
  return useWikilinks(options)
    ? md_to_markdown_with_wikilinks(source)
    : md_to_markdown(source);
}

/**
 * Render markdown using the "literal" mode, which keeps Markdown markers
 * (`#`, `*`, `` ` ``, `>`, list bullets, etc.) inside the rendered output
 * wrapped in `<span class="md-marker" aria-hidden="true">…</span>`.
 *
 * The visible text of the output (HTML tags stripped, character refs
 * decoded) is byte-for-byte equal to `toMarkdown(source)`. Combined with
 * `font-family: monospace; white-space: pre-wrap;` (see
 * `@mizchi/markdown/editor/overlay.css`), this lets you overlay the
 * rendered output on a syntax-highlighted source view and verify that
 * every glyph lines up.
 *
 * @param {string} source - Markdown source
 * @param {{ wikilinks?: boolean }} [options] - Parser extensions
 * @returns {string} HTML
 */
/** Bit flags accepted by the literal renderer FFI export. */
const LITERAL_WIKILINKS = 1;
const LITERAL_POSITIONS = 2;
const LITERAL_IMAGE_PREVIEW = 4;

export function toHtmlLiteral(source, options = {}) {
  let flags = 0;
  if (useWikilinks(options)) flags |= LITERAL_WIKILINKS;
  if (options?.positions === true) flags |= LITERAL_POSITIONS;
  if (options?.imagePreview === true) flags |= LITERAL_IMAGE_PREVIEW;
  return md_to_html_literal(source, flags);
}

// =============================================================================
// Handle-based API (for incremental parsing)
// =============================================================================

/**
 * Create a new document from markdown source.
 * @param {string} source - Markdown source
 * @param {{ wikilinks?: boolean, autolink?: boolean, tagfilter?: boolean }} [options] - Parser and renderer extensions
 * @returns {import('./api').DocumentHandle} Document handle
 */
export function createDocument(source, options = {}) {
  const wikilinks = useWikilinks(options);
  const renderFlags = rendererFlags(options);
  const handle = wikilinks
    ? md_parse_with_source_with_wikilinks(source)
    : md_parse_with_source(source);
  let cachedAst = null;

  return {
    get ast() {
      if (cachedAst === null) {
        cachedAst = parse(source, options);
      }
      return cachedAst;
    },

    toHtml() {
      return md_render_html_with_options(handle, renderFlags);
    },

    toMarkdown() {
      return md_serialize(handle);
    },

    update(newSource, edit) {
      const newHandle = md_parse_incremental(
        handle,
        newSource,
        edit.start,
        edit.oldEnd,
        edit.newEnd
      );
      if (newHandle === 0) {
        throw new Error("Incremental parse failed");
      }
      // Return a new document handle
      let newCachedAst = null;
      return {
        get ast() {
          if (newCachedAst === null) {
            newCachedAst = parse(newSource, options);
          }
          return newCachedAst;
        },
        toHtml: () => md_render_html_with_options(newHandle, renderFlags),
        toMarkdown: () => md_serialize(newHandle),
        update: (s, e) => createDocument(s, options).update(s, e), // Simplified
        dispose: () => md_free(newHandle),
      };
    },

    dispose() {
      md_free(handle);
      cachedAst = null;
    },
  };
}

// =============================================================================
// Edit helpers
// =============================================================================

/**
 * Create an EditInfo for insertion.
 * @param {number} position - Insert position
 * @param {number} length - Length of inserted text
 * @returns {import('./api').EditInfo}
 */
export function insertEdit(position, length) {
  return { start: position, oldEnd: position, newEnd: position + length };
}

/**
 * Create an EditInfo for deletion.
 * @param {number} start - Start of deletion
 * @param {number} end - End of deletion
 * @returns {import('./api').EditInfo}
 */
export function deleteEdit(start, end) {
  return { start, oldEnd: end, newEnd: start };
}

/**
 * Create an EditInfo for replacement.
 * @param {number} start - Start of replacement
 * @param {number} oldEnd - End in old source
 * @param {number} newLength - Length of new text
 * @returns {import('./api').EditInfo}
 */
export function replaceEdit(start, oldEnd, newLength) {
  return { start, oldEnd, newEnd: start + newLength };
}
