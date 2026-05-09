export {
  SyntaxHighlightEditor,
  type SyntaxHighlightEditorHandle,
  type SyntaxHighlightEditorProps,
} from "../../playground/SyntaxHighlightEditor.js";

export {
  getLoadedHighlighter,
  highlight,
  highlightIfLoaded,
  loadHighlighter,
  normalizeHighlightLanguage,
  preloadHighlighter,
  type CodeHighlighter,
  type HighlightLanguage,
} from "../highlight/index.js";
