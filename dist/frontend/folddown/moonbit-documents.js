import { expandFolddownIncludes } from "./include-resolver.js";
const rawDocuments = {
    ...import.meta.glob("../../docs/moonbit-for-programmers.mdx", {
        eager: true,
        import: "default",
        query: "?raw",
    }),
    ...import.meta.glob("../../docs/moonbit-for-programmers/**/*.{md,mdx}", {
        eager: true,
        import: "default",
        query: "?raw",
    }),
};
const documentSources = new Map(Object.entries(rawDocuments).map(([path, source]) => [path.replace(/^\.\.\/\.\.\//, ""), source]));
export const moonbitForProgrammersSource = expandFolddownIncludes("docs/moonbit-for-programmers.mdx", (path) => documentSources.get(path)).source;
//# sourceMappingURL=moonbit-documents.js.map