import { copyFile, mkdir } from "node:fs/promises";

const source = new URL(
  "../_build/wasm-gc/release/build/api/api.wasm",
  import.meta.url
);
const outputDirectory = new URL("../wasm/", import.meta.url);
const output = new URL("markdown.wasm", outputDirectory);

await mkdir(outputDirectory, { recursive: true });
await copyFile(source, output);
