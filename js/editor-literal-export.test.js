import { describe, expect, it } from "vitest";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

describe("@mizchi/markdown/editor/literal", () => {
  it("exports the framework-agnostic literal editor API without the Luna component", async () => {
    const literal = await import("@mizchi/markdown/editor/literal");

    expect(literal).toMatchObject({
      LiteralEditor: expect.any(Function),
      createLiteralMarkdownEditor: expect.any(Function),
      patchTopLevelChildren: expect.any(Function),
    });
    expect(literal.SyntaxHighlightEditor).toBeUndefined();

    const entry = fileURLToPath(
      import.meta.resolve("@mizchi/markdown/editor/literal"),
    );
    const js = await readFile(entry, "utf8");
    expect(js).not.toContain("SyntaxHighlightEditor");
    expect(js).not.toContain("@luna_ui/luna");
  });
});
