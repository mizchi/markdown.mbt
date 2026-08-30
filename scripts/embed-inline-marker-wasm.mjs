import {
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDir, "..");
const watPath = join(root, "src", "inline_marker_simd.wat");
const moonbitPath = join(root, "src", "inline_marker_search.mbt");
const checkOnly = process.argv.includes("--check");
const beginMarker = "  #| // BEGIN GENERATED INLINE MARKER WASM BYTES";
const endMarker = "  #| // END GENERATED INLINE MARKER WASM BYTES";
const tempDir = mkdtempSync(join(tmpdir(), "markdown-inline-wasm-"));

function runWasmTools(args) {
  const result = spawnSync("wasm-tools", args, { encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(result.stderr || `wasm-tools ${args[0]} failed`);
  }
}

try {
  const rawPath = join(tempDir, "inline-marker.raw.wasm");
  const strippedPath = join(tempDir, "inline-marker.wasm");
  runWasmTools(["parse", watPath, "-o", rawPath]);
  runWasmTools(["strip", "-a", rawPath, "-o", strippedPath]);
  runWasmTools(["validate", "--features", "simd", strippedPath]);

  const bytes = [...readFileSync(strippedPath)];
  const lines = [];
  for (let offset = 0; offset < bytes.length; offset += 16) {
    lines.push(`  #| ${bytes.slice(offset, offset + 16).join(",")},`);
  }
  const generated = [beginMarker, ...lines, endMarker].join("\n");
  const current = readFileSync(moonbitPath, "utf8");
  const begin = current.indexOf(beginMarker);
  const end = current.indexOf(endMarker, begin);
  if (begin < 0 || end < 0) throw new Error("embedded Wasm markers not found");
  const next =
    current.slice(0, begin) + generated + current.slice(end + endMarker.length);

  if (checkOnly) {
    if (next !== current) {
      throw new Error("embedded Wasm is stale; run `just inline-wasm-build`");
    }
    console.log(`embedded inline-marker Wasm is current (${bytes.length} bytes)`);
  } else {
    writeFileSync(moonbitPath, next);
    console.log(`embedded inline-marker Wasm (${bytes.length} bytes)`);
  }
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
