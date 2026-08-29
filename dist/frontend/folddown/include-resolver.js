import { parseFolddownIncludes } from "../../js/api.js";
function documentRoot(entry) {
    const root = entry.split("/")[0];
    if (root === undefined || root.length === 0) {
        throw new Error("A Folddown entry path must be rooted in a document directory.");
    }
    return root;
}
function isLocalMarkdownPath(source) {
    return ((source.endsWith(".md") || source.endsWith(".mdx")) &&
        !source.startsWith("/") &&
        !source.includes("\\") &&
        !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(source));
}
/** Resolve a local Include path while keeping it within the entry document root. */
export function resolveFolddownIncludePath(from, source, root) {
    if (!isLocalMarkdownPath(source)) {
        throw new Error(`<Include src="${source}"> must reference a local .md or .mdx file.`);
    }
    const rootParts = root.split("/");
    const parts = from.split("/").slice(0, -1);
    for (const segment of source.split("/")) {
        if (segment.length === 0 || segment === ".")
            continue;
        if (segment === "..") {
            if (parts.length <= rootParts.length) {
                throw new Error(`<Include src="${source}"> escapes the document root "${root}".`);
            }
            parts.pop();
            continue;
        }
        parts.push(segment);
    }
    return parts.join("/");
}
function sourceWithResolvedIncludes(path, load, root, ancestry, documents, edges) {
    if (ancestry.includes(path)) {
        throw new Error(`Include cycle: ${[...ancestry, path].join(" -> ")}`);
    }
    const source = load(path);
    if (source === undefined) {
        throw new Error(`Unable to load included Folddown document "${path}".`);
    }
    documents.set(path, source);
    const parsed = parseFolddownIncludes(source);
    if (parsed.diagnostics.length > 0) {
        const details = parsed.diagnostics
            .map((diagnostic) => `${diagnostic.code}: ${diagnostic.message}`)
            .join("\n");
        throw new Error(`Invalid Folddown document "${path}":\n${details}`);
    }
    let expanded = source;
    for (const declaration of parsed.includes) {
        const target = resolveFolddownIncludePath(path, declaration.src, root);
        edges.push({ from: path, to: target, src: declaration.src, sync: declaration.sync });
        const child = sourceWithResolvedIncludes(target, load, root, [...ancestry, path], documents, edges);
        const position = expanded.indexOf(declaration.raw);
        if (position === -1) {
            throw new Error(`Unable to replace <Include> in "${path}".`);
        }
        expanded = expanded.slice(0, position) + child + expanded.slice(position + declaration.raw.length);
    }
    return expanded;
}
/**
 * Expand typed external-document declarations without coupling Folddown to a
 * particular filesystem or bundler. The caller supplies the document loader.
 */
export function expandFolddownIncludes(entry, load) {
    const documents = new Map();
    const edges = [];
    const source = sourceWithResolvedIncludes(entry, load, documentRoot(entry), [], documents, edges);
    return {
        entry,
        source,
        documents: Array.from(documents, ([path, document]) => ({ path, source: document })),
        edges,
    };
}
//# sourceMappingURL=include-resolver.js.map