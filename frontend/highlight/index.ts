import {
  highlightPlain,
  normalizeHighlightLanguage,
  type CodeHighlighter,
  type HighlightLanguage,
} from "./types.js";

export {
  escapeHtml,
  highlightLanguages,
  highlightPlain,
  normalizeHighlightLanguage,
  type CodeHighlighter,
  type HighlightLanguage,
} from "./types.js";

type HighlighterModule = {
  default?: CodeHighlighter;
  highlight?: CodeHighlighter;
};

const highlighterLoaders: Record<HighlightLanguage, () => Promise<HighlighterModule>> = {
  typescript: () => import("./languages/typescript.js"),
  moonbit: () => import("./languages/moonbit.js"),
  json: () => import("./languages/json.js"),
  html: () => import("./languages/html.js"),
  css: () => import("./languages/css.js"),
  bash: () => import("./languages/bash.js"),
  rust: () => import("./languages/rust.js"),
};

const loadedHighlighters = new Map<HighlightLanguage, CodeHighlighter>();
const loadingHighlighters = new Map<HighlightLanguage, Promise<CodeHighlighter>>();

export function getLoadedHighlighter(lang: string): CodeHighlighter | null {
  const normalized = normalizeHighlightLanguage(lang);
  if (!normalized) return null;
  return loadedHighlighters.get(normalized) ?? null;
}

export async function loadHighlighter(lang: string): Promise<CodeHighlighter | null> {
  const normalized = normalizeHighlightLanguage(lang);
  if (!normalized) return null;

  const loaded = loadedHighlighters.get(normalized);
  if (loaded) return loaded;

  const loading = loadingHighlighters.get(normalized);
  if (loading) return loading;

  const promise = highlighterLoaders[normalized]().then((mod) => {
    const highlighter = mod.default ?? mod.highlight;
    if (!highlighter) {
      throw new Error(`Highlighter module for ${normalized} did not export a highlighter`);
    }
    loadedHighlighters.set(normalized, highlighter);
    loadingHighlighters.delete(normalized);
    return highlighter;
  });

  loadingHighlighters.set(normalized, promise);
  return promise;
}

export function highlightIfLoaded(source: string, lang: string): string | null {
  const highlighter = getLoadedHighlighter(lang);
  return highlighter ? highlighter(source) : null;
}

export async function highlight(source: string, lang: string): Promise<string> {
  const highlighter = await loadHighlighter(lang);
  return highlighter ? highlighter(source) : highlightPlain(source);
}

export async function preloadHighlighter(lang: string): Promise<boolean> {
  return (await loadHighlighter(lang)) !== null;
}
