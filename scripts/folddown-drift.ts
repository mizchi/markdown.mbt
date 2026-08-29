import { readFileSync, writeFileSync } from "node:fs";
import { resolve, sep } from "node:path";

import {
  createFolddownDriftPacket,
  validateFolddownDriftReview,
  type FolddownDriftPacket,
} from "../frontend/folddown/drift-packet.ts";
import { expandFolddownIncludes } from "../frontend/folddown/include-resolver.ts";

type ParsedArgs = {
  command: "packet" | "validate";
  entry?: string;
  output?: string;
  packet?: string;
  response?: string;
  check: boolean;
};

function usage(): never {
  throw new Error(
    [
      "Usage:",
      "  folddown-drift.ts packet [--entry docs/root.mdx] [--output packet.json] [--check]",
      "  folddown-drift.ts validate --packet packet.json --response review.json",
    ].join("\n"),
  );
}

function parseArgs(args: string[]): ParsedArgs {
  const command = args[0];
  if (command !== "packet" && command !== "validate") usage();

  const parsed: ParsedArgs = { command, check: false };
  for (let index = 1; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--") continue;
    if (argument === "--check") {
      parsed.check = true;
      continue;
    }
    if (argument === "--entry" || argument === "--output" || argument === "--packet" || argument === "--response") {
      const value = args[index + 1];
      if (value === undefined) usage();
      parsed[argument.slice(2) as "entry" | "output" | "packet" | "response"] = value;
      index += 1;
      continue;
    }
    usage();
  }
  return parsed;
}

const repoRoot = resolve(process.cwd());

function absoluteWithinRepository(path: string): string {
  const absolute = resolve(repoRoot, path);
  if (absolute !== repoRoot && !absolute.startsWith(`${repoRoot}${sep}`)) {
    throw new Error(`Path "${path}" escapes the repository root.`);
  }
  return absolute;
}

function readRepositoryFile(path: string): string {
  return readFileSync(absoluteWithinRepository(path), "utf8");
}

function writeOutput(path: string | undefined, value: unknown): void {
  const json = `${JSON.stringify(value, null, 2)}\n`;
  if (path === undefined) {
    process.stdout.write(json);
    return;
  }
  writeFileSync(resolve(process.cwd(), path), json);
}

function packetForEntry(entry: string): FolddownDriftPacket {
  const graph = expandFolddownIncludes(entry, readRepositoryFile);
  return createFolddownDriftPacket(graph);
}

function run(): void {
  const args = parseArgs(process.argv.slice(2));
  if (args.command === "packet") {
    const packet = packetForEntry(args.entry ?? "docs/moonbit-for-programmers.mdx");
    if (args.check) {
      process.stdout.write(
        `Folddown include graph is valid: ${packet.documents.length} documents, ${packet.comparisonGroups.length} comparison groups.\n`,
      );
      return;
    }
    writeOutput(args.output, packet);
    return;
  }

  if (args.packet === undefined || args.response === undefined) usage();
  const packet = JSON.parse(readFileSync(resolve(process.cwd(), args.packet), "utf8")) as FolddownDriftPacket;
  const response = JSON.parse(readFileSync(resolve(process.cwd(), args.response), "utf8")) as unknown;
  const validated = validateFolddownDriftReview(packet, response);
  process.stdout.write(
    `Validated Folddown drift review: ${validated.findings.length} comparison groups.\n`,
  );
}

run();
