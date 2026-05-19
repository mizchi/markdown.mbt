/**
 * `LiteralEditor` — a small controller that keeps a Markdown source string
 * and a DOM container in sync through partial updates.
 *
 * Each top-level block in the literal renderer's output is one direct
 * child element of the container; between blocks the renderer emits a
 * `"\n\n"` text node, and each block element is followed by a `"\n"` text
 * node (the trailing newline visible in the serializer output). The
 * patcher diffs *all* of these — elements and text nodes alike — against
 * the existing DOM and replaces only what actually changed. Unchanged
 * blocks keep their identity; downstream blocks whose only difference is
 * a shifted `data-src-start` / `data-src-end` pair get their attribute
 * values patched in place.
 *
 * The controller is framework-agnostic — it accepts any function that
 * renders a Markdown source string to HTML, which lets it be reused with
 * the FFI export, a mocked renderer in tests, etc.
 */
export type LiteralRenderer = (source: string) => string;
export interface PatchStats {
    /** Nodes that kept identity (same content, same offsets). */
    reused: number;
    /** Elements replaced because their content changed. */
    replaced: number;
    /** Elements whose only change was a positional shift — `data-src-*`
     *  attrs were patched in place, DOM identity preserved. */
    shifted: number;
    /** Nodes appended after the existing children. */
    inserted: number;
    /** Trailing nodes removed because the new document is shorter. */
    removed: number;
}
export declare class LiteralEditor {
    private readonly container;
    private readonly render;
    private current;
    constructor(container: HTMLElement, render: LiteralRenderer, initialSource?: string);
    get source(): string;
    /**
     * Set a new source. The container's top-level child nodes are diffed
     * one-by-one and only the changed range is replaced.
     */
    setSource(next: string): PatchStats;
    /**
     * Re-render the current source — useful when the renderer's options
     * (image preview, wikilinks, …) changed and the output therefore
     * differs even though the source string did not.
     */
    rerender(): PatchStats;
}
/**
 * Replace `container`'s top-level child nodes with the nodes obtained by
 * parsing `newHtml`. Preserves identity for any prefix/suffix that
 * matches byte-for-byte. Element nodes in the middle range are paired
 * with their counterparts in the new tree; pairs whose only difference
 * is a `data-src-*` shift get patched in place.
 */
export declare function patchTopLevelChildren(container: HTMLElement, newHtml: string): PatchStats;
//# sourceMappingURL=literal-editor.d.ts.map