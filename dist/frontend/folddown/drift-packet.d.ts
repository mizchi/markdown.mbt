import { type FolddownNode } from "../../js/api.js";
import type { ExpandedFolddownSource } from "./include-resolver.js";
export type FolddownDriftFold = Omit<FolddownNode, "body"> & {
    title: string;
    body: string;
};
export type FolddownDriftDocument = {
    path: string;
    source: string;
    folds: FolddownDriftFold[];
};
export type FolddownDriftComparisonGroup = {
    sync: string;
    documents: string[];
};
export type FolddownDriftPacket = {
    version: "folddown-drift/v1";
    entry: string;
    documents: FolddownDriftDocument[];
    comparisonGroups: FolddownDriftComparisonGroup[];
    reviewInstructions: string[];
};
export type FolddownDriftVerdict = "aligned" | "suspected-drift" | "insufficient-evidence";
export type FolddownDriftFinding = {
    sync: string;
    verdict: FolddownDriftVerdict;
    summary: string;
    evidence: Array<{
        path: string;
        foldIds: string[];
    }>;
};
export type FolddownDriftReview = {
    version: "folddown-drift/v1";
    findings: FolddownDriftFinding[];
};
/** Build provider-neutral input for an LLM semantic drift review. */
export declare function createFolddownDriftPacket(graph: ExpandedFolddownSource): FolddownDriftPacket;
/** Validate an LLM review before it can become a CI finding or issue. */
export declare function validateFolddownDriftReview(packet: FolddownDriftPacket, response: unknown): FolddownDriftReview;
//# sourceMappingURL=drift-packet.d.ts.map