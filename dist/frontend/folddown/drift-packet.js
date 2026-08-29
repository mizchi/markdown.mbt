import { parseFolddown } from "../../js/api.js";
import { splitFolddownTitleAndBody } from "./from-mdx.ts";
function foldsForDocument(path, source) {
    const result = parseFolddown(source);
    if (result.diagnostics.length > 0) {
        const details = result.diagnostics
            .map((diagnostic) => `${diagnostic.code}: ${diagnostic.message}`)
            .join("\n");
        throw new Error(`Invalid Folddown document "${path}":\n${details}`);
    }
    return result.nodes.map((node) => ({ ...node, ...splitFolddownTitleAndBody(node.body) }));
}
/** Build provider-neutral input for an LLM semantic drift review. */
export function createFolddownDriftPacket(graph) {
    const documents = graph.documents.map(({ path, source }) => ({
        path,
        source,
        folds: foldsForDocument(path, source),
    }));
    const groups = new Map();
    for (const edge of graph.edges) {
        if (edge.sync === null)
            continue;
        const paths = groups.get(edge.sync) ?? [];
        if (!paths.includes(edge.to))
            paths.push(edge.to);
        groups.set(edge.sync, paths);
    }
    const comparisonGroups = Array.from(groups, ([sync, paths]) => ({
        sync,
        documents: paths,
    }));
    for (const group of comparisonGroups) {
        if (group.documents.length < 2) {
            throw new Error(`sync group "${group.sync}" must include at least two documents.`);
        }
    }
    return {
        version: "folddown-drift/v1",
        entry: graph.entry,
        documents,
        comparisonGroups,
        reviewInstructions: [
            "Compare only documents within each comparison group.",
            "Check semantic claims, prerequisites, examples, API names, and evidence references.",
            "Use aligned only when every supplied document supports the same relevant claims.",
            "Use suspected-drift for a concrete contradiction, omission, or incompatible change.",
            "Use insufficient-evidence when the supplied documents do not establish a comparison.",
            "Do not propose edits or infer facts outside the supplied documents.",
        ],
    };
}
function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
function requiredString(value, field) {
    if (typeof value !== "string" || value.trim().length === 0) {
        throw new Error(`Drift review ${field} must be a non-empty string.`);
    }
    return value;
}
function requiredStringArray(value, field) {
    if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || item.length === 0)) {
        throw new Error(`Drift review ${field} must be an array of non-empty strings.`);
    }
    return value;
}
/** Validate an LLM review before it can become a CI finding or issue. */
export function validateFolddownDriftReview(packet, response) {
    if (!isRecord(response) || response.version !== packet.version || !Array.isArray(response.findings)) {
        throw new Error("Drift review must contain the matching version and a findings array.");
    }
    const groups = new Map(packet.comparisonGroups.map((group) => [group.sync, group]));
    if (response.findings.length !== groups.size) {
        throw new Error("Drift review must contain exactly one finding for every comparison group.");
    }
    const documents = new Map(packet.documents.map((document) => [document.path, document]));
    const findings = [];
    const seen = new Set();
    for (const candidate of response.findings) {
        if (!isRecord(candidate))
            throw new Error("Each drift finding must be an object.");
        const sync = requiredString(candidate.sync, "finding.sync");
        const group = groups.get(sync);
        if (group === undefined || seen.has(sync)) {
            throw new Error(`Drift review has an unknown or duplicate sync group "${sync}".`);
        }
        seen.add(sync);
        const verdict = requiredString(candidate.verdict, "finding.verdict");
        if (verdict !== "aligned" &&
            verdict !== "suspected-drift" &&
            verdict !== "insufficient-evidence") {
            throw new Error(`Drift review has an invalid verdict "${verdict}".`);
        }
        const evidenceValue = candidate.evidence;
        if (!Array.isArray(evidenceValue) || evidenceValue.length === 0) {
            throw new Error("Drift review finding.evidence must be a non-empty array.");
        }
        const evidence = [];
        const coveredDocuments = new Set();
        for (const item of evidenceValue) {
            if (!isRecord(item))
                throw new Error("Each evidence item must be an object.");
            const path = requiredString(item.path, "evidence.path");
            const document = documents.get(path);
            if (document === undefined || !group.documents.includes(path)) {
                throw new Error(`Drift review evidence references a document outside "${sync}".`);
            }
            const foldIds = requiredStringArray(item.foldIds, "evidence.foldIds");
            const knownIds = new Set(document.folds.map((fold) => fold.id));
            if (foldIds.some((id) => !knownIds.has(id))) {
                throw new Error(`Drift review evidence references an unknown Fold in "${path}".`);
            }
            coveredDocuments.add(path);
            evidence.push({ path, foldIds });
        }
        if (group.documents.some((path) => !coveredDocuments.has(path))) {
            throw new Error(`Drift review finding "${sync}" must cite every compared document.`);
        }
        findings.push({
            sync,
            verdict,
            summary: requiredString(candidate.summary, "finding.summary"),
            evidence,
        });
    }
    return { version: packet.version, findings };
}
//# sourceMappingURL=drift-packet.js.map