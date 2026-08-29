import { parse, type FolddownNode } from "../../js/api.js";

import type { FoldNode } from "./model.js";

type InlineNode = {
  type: string;
  value?: string | null | undefined;
  alt?: string | null | undefined;
  children?: readonly InlineNode[];
};

function inlineText(node: InlineNode): string {
  if (node.type === "text" || node.type === "inlineCode") {
    return node.value ?? "";
  }
  if (node.type === "image" || node.type === "imageReference") {
    return node.alt ?? "";
  }
  if (node.type === "break") {
    return " ";
  }
  return node.children?.map(inlineText).join("") ?? "";
}

/** Split a Fold's first Markdown heading from its remaining body. */
export function splitFolddownTitleAndBody(source: string): Pick<FoldNode, "title" | "body"> {
  const first = parse(source).children[0];
  if (first?.type !== "heading") {
    throw new Error("A Folddown declaration must begin with a Markdown heading.");
  }

  const title = first.children.map((node) => inlineText(node)).join("");
  const headingEnd = first.position?.end.offset;
  if (headingEnd === undefined) {
    throw new Error("A Folddown heading must include a source position.");
  }

  return { title, body: source.slice(headingEnd).trim() };
}

/** Convert a MoonBit-validated Folddown manifest into viewer-ready nodes. */
export function viewerNodesFromManifest(nodes: readonly FolddownNode[]): FoldNode[] {
  return nodes.map((node) => {
    const { title, body } = splitFolddownTitleAndBody(node.body);
    const shared = {
      id: node.id,
      kind: node.kind,
      level: node.level,
      title,
      body,
      requires: node.requires,
      roles: node.roles,
      goals: node.goals,
      evidence: node.evidence,
      familiarTo: node.familiarTo,
    };

    return node.locale === null ? shared : { ...shared, locale: node.locale };
  });
}
