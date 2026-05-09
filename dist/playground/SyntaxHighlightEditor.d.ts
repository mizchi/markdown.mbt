export interface SyntaxHighlightEditorProps {
    value: () => string;
    onChange: (value: string) => void;
    onCursorChange?: (position: number) => void;
    initialCursorPosition?: number;
    ref?: (handle: SyntaxHighlightEditorHandle) => void;
    showLineNumbers?: boolean;
}
export interface SyntaxHighlightEditorHandle {
    focus: () => void;
    getCursorPosition: () => number;
    setCursorPosition: (pos: number) => void;
    getScrollTop: () => number;
    setScrollTop: (top: number) => void;
    setValue: (value: string, span?: {
        start: number;
        end: number;
    }) => void;
}
export declare function SyntaxHighlightEditor(props: SyntaxHighlightEditorProps): unknown;
//# sourceMappingURL=SyntaxHighlightEditor.d.ts.map