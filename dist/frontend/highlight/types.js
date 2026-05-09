export const highlightLanguages = [
    "typescript",
    "moonbit",
    "json",
    "html",
    "css",
    "bash",
    "rust",
];
const languageAliases = {
    ts: "typescript",
    tsx: "typescript",
    jsx: "typescript",
    javascript: "typescript",
    js: "typescript",
    typescript: "typescript",
    mbt: "moonbit",
    moonbit: "moonbit",
    json: "json",
    html: "html",
    htm: "html",
    xml: "html",
    svg: "html",
    css: "css",
    scss: "css",
    less: "css",
    bash: "bash",
    sh: "bash",
    shell: "bash",
    zsh: "bash",
    rust: "rust",
    rs: "rust",
};
export function normalizeHighlightLanguage(lang) {
    const key = lang.trim().toLowerCase();
    return languageAliases[key] ?? null;
}
export function escapeHtml(text) {
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}
export function highlightPlain(source) {
    return `<pre class="highlight" style="background-color: #0d1117; color: #c9d1d9"><code><span class="line"><span style="color: #c9d1d9">${escapeHtml(source)}</span></span></code></pre>`;
}
//# sourceMappingURL=types.js.map