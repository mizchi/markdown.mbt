import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(scriptDir, "..");
const watPath = join(root, "src", "inline_marker_simd.wat");
const outputPath = join(root, "js", "inline_marker_simd.wasm");
const checkOnly = process.argv.includes("--check");
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

  const built = readFileSync(strippedPath);
  if (checkOnly) {
    if (!existsSync(outputPath) || !readFileSync(outputPath).equals(built)) {
      throw new Error("inline-marker Wasm is stale; run `just inline-wasm-build`");
    }
    console.log(`inline-marker Wasm is current (${built.length} bytes)`);
  } else {
    copyFileSync(strippedPath, outputPath);
    console.log(`built js/inline_marker_simd.wasm (${built.length} bytes)`);
  }
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
