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
        index: resolve(__dirname, "playground/index.html"),
        literal: resolve(__dirname, "playground/literal/index.html"),
        folddown: resolve(__dirname, "playground/folddown.html"),
      },
    },
  },
});
