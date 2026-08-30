import { defineConfig } from "vite";
import { resolve } from "node:path";

export default defineConfig({
  oxc: {
    jsx: {
      runtime: "automatic",
      importSource: "@luna_ui/luna",
    },
  },
  root: "playground",
  build: {
    rollupOptions: {
      input: {
        index: resolve(import.meta.dirname, "playground/index.html"),
        literal: resolve(import.meta.dirname, "playground/literal/index.html"),
      },
    },
  },
});
