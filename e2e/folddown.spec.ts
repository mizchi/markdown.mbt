import { expect, test } from "@playwright/test";

test.describe("Folddown viewer", () => {
  test("keeps highlighted code at its source line spacing", async ({ page }) => {
    await page.goto("/folddown.html");

    const code = page.locator(
      '[data-fold-id="moonbit.async.typescript.ja"] pre.highlight.github-dark',
    ).last();
    await expect(code).toBeVisible();

    const lines = await code.evaluate((pre) => {
      const lineHeight = Number.parseFloat(getComputedStyle(pre).lineHeight);
      const sourceLines = Array.from(pre.querySelectorAll<HTMLElement>(".line"));
      const firstTop = sourceLines[0]!.getBoundingClientRect().top;

      return sourceLines.map((line, sourceLine) => ({
        sourceLine,
        top: line.getBoundingClientRect().top - firstTop,
        lineHeight,
      }));
    });

    for (const line of lines) {
      expect(Math.abs(line.top - line.sourceLine * line.lineHeight)).toBeLessThan(
        line.lineHeight / 2,
      );
    }
  });

  test("adapts a MoonBit introduction to background, knowledge, and reading intent", async ({ page }) => {
    await page.goto("/folddown.html");

    await expect(
      page.getByRole("heading", { name: "TypeScript 経験者のための MoonBit 入門" }),
    ).toBeVisible();
    await expect(page.locator(".reader-intake")).toHaveCount(0);

    const profile = page.locator(".viewer-header + .profile-bar");
    await expect(profile).toBeVisible();
    await expect(profile.getByRole("button", { name: "TypeScript" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(page.getByText("21 個の節")).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.hello-world.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.packages.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.cli.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.script-mode.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.async.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.async.typescript.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.toolchain.typescript.ja"]')).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "TypeScript の tagged union を MoonBit で書く" }),
    ).toBeVisible();
    const typeScriptComparison = page.locator(
      '[data-fold-id="moonbit.data.typescript.ja"] pre.highlight.github-dark',
    ).first();
    await expect(typeScriptComparison).toBeVisible();
    await expect(typeScriptComparison).toHaveCSS("background-color", "rgb(246, 248, 250)");
    await expect(
      typeScriptComparison.locator('span[style*="color: #ff7b72"]').first(),
    ).toHaveCSS("color", "rgb(207, 34, 46)");
    await expect(page.locator('[data-fold-id="moonbit.bench.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.verification.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.skills.ja"]')).toBeVisible();

    const firstTime = profile.getByRole("button", { name: "初めて知った" });
    const someKnowledge = profile.getByRole("button", { name: "多少知ってる" });
    const detail = profile.getByRole("button", { name: "詳しく知りたい" });
    const interesting = profile.getByRole("button", { name: "面白い機能だけを知りたい" });
    await expect(firstTime).toHaveAttribute("aria-pressed", "true");
    await expect(detail).toHaveAttribute("aria-pressed", "true");
    await someKnowledge.click();
    await expect(someKnowledge).toHaveAttribute("aria-pressed", "true");
    const introNode = page.locator('[data-fold-id="moonbit.overview.ja"]');
    const advancedNode = page.locator('[data-fold-id="moonbit.errors.ja"]');

    await expect(introNode).toHaveClass(/is-collapsed/);
    await expect(advancedNode).not.toHaveClass(/is-collapsed/);

    await introNode.getByRole("button", { name: "MoonBit の位置づけ: 開く" }).click();
    await expect(introNode).not.toHaveClass(/is-collapsed/);
    await expect(introNode).toContainText("WebAssembly を主軸に");

    await interesting.click();
    await expect(interesting).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator('[data-fold-id="moonbit.bindings.typescript.ja"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.errors.ja"]')).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "raise とパターンマッチする catch で失敗を型と関数シグネチャへ出す" }),
    ).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.errors.typescript.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.bench.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.verification.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.skills.ja"]')).toBeVisible();
    await expect(page.getByText("15 個の節")).toBeVisible();

    await profile.getByRole("button", { name: "Rust" }).click();
    await expect(page.getByRole("heading", { name: "Rust 経験者のための MoonBit 入門" })).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.data.typescript.ja"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.data.rust.ja"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.errors.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.errors.typescript.ja"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.errors.rust.ja"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.async.rust.ja"]')).toBeVisible();

    await profile.getByRole("button", { name: "English" }).click();
    await expect(
      page.getByRole("heading", { name: "MoonBit for Rust programmers" }),
    ).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.overview.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.tests.en"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.errors.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.errors.rust.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.async.rust.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.script-mode.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.json-patterns.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.verification.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.skills.en"]')).toBeVisible();
    await expect(page.getByText("14 declarations")).toBeVisible();
    await expect(profile.getByRole("button", { name: "Know some" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(profile.getByRole("button", { name: "Interesting features only" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );

    await profile.getByRole("button", { name: "Go" }).click();
    await expect(page.getByRole("heading", { name: "MoonBit for Go programmers" })).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.bindings.typescript.en"]')).toHaveCount(0);
    await expect(page.locator('[data-fold-id="moonbit.bindings.rust.en"]')).toHaveCount(0);

    await profile.getByRole("button", { name: "Learn in detail" }).click();
    await expect(page.locator('[data-fold-id="moonbit.bindings.go.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.data.go.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.errors.go.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.async.go.en"]')).toBeVisible();
    await expect(page.locator('[data-fold-id="moonbit.toolchain.go.en"]')).toBeVisible();
    const goComparison = page.locator(
      '[data-fold-id="moonbit.data.go.en"] pre.highlight.github-dark',
    ).first();
    await expect(goComparison).toBeVisible();
    await expect(goComparison).toContainText("type LoadState interface");
    await expect(
      goComparison.locator('span[style*="color: #ff7b72"]').first(),
    ).toHaveCSS("color", "rgb(207, 34, 46)");
    await expect(page.getByText("21 declarations")).toBeVisible();
  });
});
