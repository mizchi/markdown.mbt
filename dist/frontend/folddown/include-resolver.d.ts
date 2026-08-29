export type FolddownIncludeEdge = {
    from: string;
    to: string;
    src: string;
    sync: string | null;
};
export type FolddownSourceDocument = {
    path: string;
    source: string;
};
export type ExpandedFolddownSource = {
    entry: string;
    source: string;
    documents: FolddownSourceDocument[];
    edges: FolddownIncludeEdge[];
};
export type FolddownSourceLoader = (path: string) => string | undefined;
/** Resolve a local Include path while keeping it within the entry document root. */
export declare function resolveFolddownIncludePath(from: string, source: string, root: string): string;
/**
 * Expand typed external-document declarations without coupling Folddown to a
 * particular filesystem or bundler. The caller supplies the document loader.
 */
export declare function expandFolddownIncludes(entry: string, load: FolddownSourceLoader): ExpandedFolddownSource;
//# sourceMappingURL=include-resolver.d.ts.map