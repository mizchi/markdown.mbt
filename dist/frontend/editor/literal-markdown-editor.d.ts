/**
 * DOM controller for the source-preserving ("literal") renderer.
 *
 * This is framework-agnostic: callers provide the DOM nodes and a renderer
 * function, and the controller wires preview/edit switching, source-view
 * highlighting, partial DOM patching, image-preview caret mapping, selection
 * overlays, and IME anchor correction.
 */
import { type PatchStats } from "./literal-editor.js";
export type LiteralMarkdownMode = "preview" | "edit";
export interface LiteralMarkdownRenderOptions {
    positions: true;
    imagePreview: boolean;
}
export type LiteralMarkdownRenderer = (source: string, options: LiteralMarkdownRenderOptions) => string;
export interface LiteralMarkdownEditorElements {
    host: HTMLDivElement;
    rendered: HTMLElement;
    source: HTMLTextAreaElement;
    sourceView: HTMLElement;
    sourceCaret: HTMLDivElement;
    sourceSelection: HTMLDivElement;
    modeRoot?: HTMLElement;
}
export interface LiteralMarkdownInvariantState {
    ok: boolean;
    visible: string;
    expected: string;
}
export interface LiteralMarkdownCursorState {
    kind: "cursor" | "selection";
    start: number;
    end: number;
}
export interface LiteralMarkdownEditorOptions {
    elements: LiteralMarkdownEditorElements;
    renderLiteral: LiteralMarkdownRenderer;
    initialSource?: string;
    mode?: LiteralMarkdownMode;
    imagePreview?: boolean;
    imagePreviewClass?: string;
    onPatchStats?: (stats: PatchStats) => void;
    onInvariant?: (state: LiteralMarkdownInvariantState) => void;
    onCursor?: (state: LiteralMarkdownCursorState) => void;
}
export interface LiteralMarkdownEditorHandle {
    readonly source: string;
    readonly mode: LiteralMarkdownMode;
    readonly imagePreview: boolean;
    setSource(source: string): PatchStats;
    setMode(mode: LiteralMarkdownMode): void;
    setImagePreview(enabled: boolean): void;
    syncLayout(keepCaretVisible?: boolean): void;
    refreshInvariant(): LiteralMarkdownInvariantState;
    destroy(): void;
}
export declare function createLiteralMarkdownEditor(options: LiteralMarkdownEditorOptions): LiteralMarkdownEditorHandle;
//# sourceMappingURL=literal-markdown-editor.d.ts.map