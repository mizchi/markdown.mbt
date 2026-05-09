export declare const highlightLanguages: readonly ["typescript", "moonbit", "json", "html", "css", "bash", "rust"];
export type HighlightLanguage = (typeof highlightLanguages)[number];
export type CodeHighlighter = (source: string) => string;
export declare function normalizeHighlightLanguage(lang: string): HighlightLanguage | null;
export declare function escapeHtml(text: string): string;
export declare function highlightPlain(source: string): string;
//# sourceMappingURL=types.d.ts.map