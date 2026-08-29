import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["js/**/*.test.js", "playground/**/*.test.tsx", "frontend/**/*.test.ts"],
  },
  oxc: {
    jsx: {
      runtime: "automatic",
      importSource: "@luna_ui/luna",
    },
  },
});
