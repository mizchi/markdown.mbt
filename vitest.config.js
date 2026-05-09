import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["js/**/*.test.js", "playground/**/*.test.tsx", "frontend/**/*.test.ts"],
  },
  esbuild: {
    jsx: "automatic",
    jsxImportSource: "@luna_ui/luna",
  },
});
