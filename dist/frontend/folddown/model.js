export const FOLD_LEVELS = ["intro", "basic", "advanced", "expert"];
/** Collapse only the content levels declared by the selected reader profile. */
export function shouldCollapseForReaderProfile(nodeLevel, profile) {
    return profile.collapseLevels.includes(nodeLevel);
}
/** Derive controlled disclosure state without mutating the canonical document. */
export function createInitialCollapsedState(nodes, profile) {
    return Object.fromEntries(nodes.map((node) => [
        node.id,
        shouldCollapseForReaderProfile(node.level, profile),
    ]));
}
/** Select shared and reader-matching nodes without changing their disclosure state. */
export function selectNodesForReader(nodes, reader, contentFilter = { id: "all", mode: "all" }) {
    return nodes.filter((node) => {
        const localeMatches = node.locale === undefined || node.locale === reader.locale;
        const roleMatches = node.roles === undefined ||
            node.roles.length === 0 ||
            node.roles.some((role) => reader.roles?.includes(role) ?? false);
        const isFamiliar = node.familiarTo?.some((role) => reader.roles?.includes(role) ?? false) ?? false;
        const contentMatches = contentFilter.mode === "all" || !isFamiliar;
        return localeMatches && roleMatches && contentMatches;
    });
}
//# sourceMappingURL=model.js.map