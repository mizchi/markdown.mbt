export declare const FOLD_LEVELS: readonly ["intro", "basic", "advanced", "expert"];
export type FoldLevel = (typeof FOLD_LEVELS)[number];
export type FoldKind = "concept" | "procedure" | "reference" | "evidence";
export type ReaderProfile = {
    id: string;
    collapseLevels: readonly FoldLevel[];
};
export type ContentFilterMode = "all" | "unfamiliar";
/** Select all content or exclude direct correspondences for the selected reader. */
export type ContentFilter = {
    id: string;
    mode: ContentFilterMode;
};
/** A viewer-ready node produced by Folddown's future canonical IR. */
export interface FoldNode {
    id: string;
    kind: FoldKind;
    level: FoldLevel;
    title: string;
    body: string;
    locale?: string;
    requires?: readonly string[];
    roles?: readonly string[];
    goals?: readonly string[];
    evidence?: readonly string[];
    /** Reader-background roles for which this node is a direct correspondence. */
    familiarTo?: readonly string[];
}
export interface FoldReaderSelector {
    locale?: string;
    roles?: readonly string[];
}
/** Collapse only the content levels declared by the selected reader profile. */
export declare function shouldCollapseForReaderProfile(nodeLevel: FoldLevel, profile: ReaderProfile): boolean;
/** Derive controlled disclosure state without mutating the canonical document. */
export declare function createInitialCollapsedState(nodes: readonly FoldNode[], profile: ReaderProfile): Record<string, boolean>;
/** Select shared and reader-matching nodes without changing their disclosure state. */
export declare function selectNodesForReader(nodes: readonly FoldNode[], reader: FoldReaderSelector, contentFilter?: ContentFilter): FoldNode[];
//# sourceMappingURL=model.d.ts.map