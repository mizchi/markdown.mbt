import { type FolddownNode } from "../../js/api.js";
import type { FoldNode } from "./model.js";
/** Split a Fold's first Markdown heading from its remaining body. */
export declare function splitFolddownTitleAndBody(source: string): Pick<FoldNode, "title" | "body">;
/** Convert a MoonBit-validated Folddown manifest into viewer-ready nodes. */
export declare function viewerNodesFromManifest(nodes: readonly FolddownNode[]): FoldNode[];
//# sourceMappingURL=from-mdx.d.ts.map