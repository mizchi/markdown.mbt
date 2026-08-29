export const FOLD_LEVELS = ["intro", "basic", "advanced", "expert"] as const;

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
export function shouldCollapseForReaderProfile(
  nodeLevel: FoldLevel,
  profile: ReaderProfile,
): boolean {
  return profile.collapseLevels.includes(nodeLevel);
}

/** Derive controlled disclosure state without mutating the canonical document. */
export function createInitialCollapsedState(
  nodes: readonly FoldNode[],
  profile: ReaderProfile,
): Record<string, boolean> {
  return Object.fromEntries(
    nodes.map((node) => [
      node.id,
      shouldCollapseForReaderProfile(node.level, profile),
    ]),
  );
}

/** Select shared and reader-matching nodes without changing their disclosure state. */
export function selectNodesForReader(
  nodes: readonly FoldNode[],
  reader: FoldReaderSelector,
  contentFilter: ContentFilter = { id: "all", mode: "all" },
): FoldNode[] {
  return nodes.filter((node) => {
    const localeMatches = node.locale === undefined || node.locale === reader.locale;
    const roleMatches =
      node.roles === undefined ||
      node.roles.length === 0 ||
      node.roles.some((role) => reader.roles?.includes(role) ?? false);

    const isFamiliar = node.familiarTo?.some((role) => reader.roles?.includes(role) ?? false) ?? false;
    const contentMatches = contentFilter.mode === "all" || !isFamiliar;

    return localeMatches && roleMatches && contentMatches;
  });
}
