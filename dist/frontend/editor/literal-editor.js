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
const ZERO_STATS = {
    reused: 0,
    replaced: 0,
    shifted: 0,
    inserted: 0,
    removed: 0,
};
export class LiteralEditor {
    container;
    render;
    current;
    constructor(container, render, initialSource = "") {
        this.container = container;
        this.render = render;
        this.current = initialSource;
        this.container.innerHTML = render(initialSource);
    }
    get source() {
        return this.current;
    }
    /**
     * Set a new source. The container's top-level child nodes are diffed
     * one-by-one and only the changed range is replaced.
     */
    setSource(next) {
        if (next === this.current) {
            return { ...ZERO_STATS };
        }
        const newHtml = this.render(next);
        const stats = patchTopLevelChildren(this.container, newHtml);
        this.current = next;
        return stats;
    }
    /**
     * Re-render the current source — useful when the renderer's options
     * (image preview, wikilinks, …) changed and the output therefore
     * differs even though the source string did not.
     */
    rerender() {
        const newHtml = this.render(this.current);
        return patchTopLevelChildren(this.container, newHtml);
    }
}
/**
 * Replace `container`'s top-level child nodes with the nodes obtained by
 * parsing `newHtml`. Preserves identity for any prefix/suffix that
 * matches byte-for-byte. Element nodes in the middle range are paired
 * with their counterparts in the new tree; pairs whose only difference
 * is a `data-src-*` shift get patched in place.
 */
export function patchTopLevelChildren(container, newHtml) {
    const template = container.ownerDocument.createElement("template");
    template.innerHTML = newHtml;
    const next = Array.from(template.content.childNodes);
    const prev = Array.from(container.childNodes);
    const stats = { ...ZERO_STATS };
    // 1. Common prefix.
    let i = 0;
    const minLen = Math.min(prev.length, next.length);
    while (i < minLen) {
        const a = prev[i];
        const b = next[i];
        if (!a || !b || !nodesEqual(a, b))
            break;
        stats.reused++;
        i++;
    }
    // 2. Common suffix.
    let pj = prev.length - 1;
    let nj = next.length - 1;
    while (pj >= i && nj >= i) {
        const a = prev[pj];
        const b = next[nj];
        if (!a || !b || !nodesEqual(a, b))
            break;
        stats.reused++;
        pj--;
        nj--;
    }
    // 3. Middle range: walk pairwise.
    const middlePrev = prev.slice(i, pj + 1);
    const middleNext = next.slice(i, nj + 1);
    const referenceNode = prev[pj + 1] ?? null;
    const paired = Math.min(middlePrev.length, middleNext.length);
    for (let k = 0; k < paired; k++) {
        const a = middlePrev[k];
        const b = middleNext[k];
        if (a instanceof HTMLElement &&
            b instanceof HTMLElement &&
            isShiftOnly(a, b)) {
            copyPositionAttrs(b, a);
            stats.shifted++;
        }
        else {
            container.replaceChild(b, a);
            stats.replaced++;
        }
    }
    for (let k = paired; k < middlePrev.length; k++) {
        container.removeChild(middlePrev[k]);
        stats.removed++;
    }
    for (let k = paired; k < middleNext.length; k++) {
        container.insertBefore(middleNext[k], referenceNode);
        stats.inserted++;
    }
    return stats;
}
function nodesEqual(a, b) {
    if (a.nodeType !== b.nodeType)
        return false;
    if (a instanceof HTMLElement && b instanceof HTMLElement) {
        return a.outerHTML === b.outerHTML;
    }
    return a.nodeValue === b.nodeValue;
}
const POS_ATTRS = ["data-src-start", "data-src-end"];
function isShiftOnly(oldEl, newEl) {
    if (oldEl.tagName !== newEl.tagName)
        return false;
    if (oldEl.innerHTML !== newEl.innerHTML)
        return false;
    const oldAttrs = oldEl.attributes;
    const newAttrs = newEl.attributes;
    if (oldAttrs.length !== newAttrs.length)
        return false;
    for (let i = 0; i < oldAttrs.length; i++) {
        const attr = oldAttrs[i];
        if (!attr)
            continue;
        const newVal = newEl.getAttribute(attr.name);
        if (attr.value === newVal)
            continue;
        if (POS_ATTRS.includes(attr.name))
            continue;
        return false;
    }
    return true;
}
function copyPositionAttrs(from, to) {
    for (const name of POS_ATTRS) {
        const v = from.getAttribute(name);
        if (v != null)
            to.setAttribute(name, v);
    }
}
//# sourceMappingURL=literal-editor.js.map