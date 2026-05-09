import { type CodeHighlighter } from "./types.js";
export { escapeHtml, highlightLanguages, highlightPlain, normalizeHighlightLanguage, type CodeHighlighter, type HighlightLanguage, } from "./types.js";
export declare function getLoadedHighlighter(lang: string): CodeHighlighter | null;
export declare function loadHighlighter(lang: string): Promise<CodeHighlighter | null>;
export declare function highlightIfLoaded(source: string, lang: string): string | null;
export declare function highlight(source: string, lang: string): Promise<string>;
export declare function preloadHighlighter(lang: string): Promise<boolean>;
//# sourceMappingURL=index.d.ts.map