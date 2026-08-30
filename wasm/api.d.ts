import type { MarkdownRoot } from "../js/api.js";
export type { MarkdownOptions, MarkdownRoot } from "../js/api.js";

export function parse(
  source: string,
  options?: import("../js/api.js").MarkdownOptions
): MarkdownRoot;

export function toHtml(
  source: string,
  options?: import("../js/api.js").MarkdownOptions
): string;

export function toMarkdown(
  source: string,
  options?: import("../js/api.js").MarkdownOptions
): string;
