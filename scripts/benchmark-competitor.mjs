/**
 * Reproduce the @mizchi/markdown portion of ox-content's runtime benchmark.
 *
 * The corpus, size multipliers, warmup count, and iteration counts match
 * benchmarks/bundle-size/parse-benchmark.mjs in ubugeeei-prod/ox-content.
 */

import { performance } from "node:perf_hooks";

import { parse, toHtml } from "../js/api.js";
import { parse as parseWasm, toHtml as toHtmlWasm } from "../wasm/api.js";
import {
  md_to_ast_json as toAstJson,
  md_to_html as toHtmlRaw,
} from "../_build/js/release/build/api/api.js";

const sampleMarkdown = `
# Heading 1

This is a paragraph with **bold** and *italic* text.

## Heading 2

- List item 1
- List item 2
  - Nested item
- List item 3

### Code Block

\`\`\`javascript
function hello() {
  console.log("Hello, World!");
}
\`\`\`

> This is a blockquote
> with multiple lines

| Header 1 | Header 2 |
|----------|----------|
| Cell 1   | Cell 2   |
| Cell 3   | Cell 4   |

Here's a [link](https://example.com) and an image: ![alt](image.png)

---

Final paragraph with \`inline code\` and more text.
`;

const sizes = {
  large: Array(100).fill(sampleMarkdown).join("\n\n"),
  huge: Array(2150).fill(sampleMarkdown).join("\n\n"),
};

const methods = [
  ["parse (public AST)", parse],
  ["parse (Wasm AST)", parseWasm],
  ["parse (AST JSON)", toAstJson],
  ["parse + render (public)", toHtml],
  ["parse + render (Wasm)", toHtmlWasm],
  ["parse + render (raw)", toHtmlRaw],
];

const runs = readRuns(process.argv.slice(2));
const results = [];

for (const [size, input] of Object.entries(sizes)) {
  const iterations = size === "huge" ? 5 : 20;
  for (const [name, fn] of methods) {
    const samples = [];
    for (let run = 0; run < runs; run++) {
      samples.push(benchmarkOnce(fn, input, iterations));
    }
    samples.sort((a, b) => a.avgMs - b.avgMs);
    results.push({
      size,
      bytes: input.length,
      name,
      ...samples[Math.floor(runs / 2)],
    });
  }
}

console.log(`Node ${process.version}; median of ${runs} runs`);
console.log("| Size | API | avg time | ops/sec | throughput |");
console.log("|---|---|---:|---:|---:|");
for (const result of results) {
  console.log(
    `| ${result.size} (${(result.bytes / 1024).toFixed(1)} KB) | ${result.name} | ${result.avgMs.toFixed(2)} ms | ${result.opsPerSec.toFixed(1)} | ${result.throughputMBs.toFixed(2)} MB/s |`,
  );
}

function benchmarkOnce(fn, input, iterations) {
  for (let index = 0; index < 5; index++) fn(input);
  const start = performance.now();
  for (let index = 0; index < iterations; index++) fn(input);
  const avgMs = (performance.now() - start) / iterations;
  const opsPerSec = 1000 / avgMs;
  return {
    avgMs,
    opsPerSec,
    throughputMBs: (input.length / 1024 / 1024) * opsPerSec,
  };
}

function readRuns(args) {
  const raw = args.find((arg) => arg.startsWith("--runs="))?.slice(7) ?? "7";
  const value = Number.parseInt(raw, 10);
  if (
    !Number.isSafeInteger(value) ||
    value < 1 ||
    value % 2 === 0 ||
    String(value) !== raw
  ) {
    throw new Error("--runs must be a positive odd integer");
  }
  return value;
}
