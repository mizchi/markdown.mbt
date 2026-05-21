/**
 * Browser benchmark for the literal editor controller.
 *
 * Measures the path that `moon bench` cannot cover: textarea input events,
 * partial DOM patching, source-view highlighting, image-preview layout, and
 * the controller's RAF layout sync.
 *
 * Usage:
 *   pnpm run bench:literal
 *   pnpm run bench:literal -- --iterations=100 --warmup=20
 *   pnpm run bench:literal -- --json
 */

import process from "node:process";
import { type Page } from "playwright";
import {
  type BenchmarkResult,
  type BrowserBenchmarkOptions,
  measureClickAction,
  measureTextareaInputValues,
  parseBrowserBenchmarkOptions,
  printBenchmarkMarkdown,
  runBrowserBenchmark,
  summarizeTimingSamples,
  waitTwoFrames,
} from "./helpers/browser-benchmark.ts";

const DEFAULT_URL = "http://127.0.0.1:5188/literal/";

interface LiteralScenario {
  name: string;
  source: string;
  imagePreview: boolean;
  values: (total: number) => string[];
}

function generateMarkdownDocument(sections: number): string {
  const lines: string[] = ["# Literal Benchmark", ""];
  for (let i = 0; i < sections; i++) {
    lines.push(
      `## Section ${i}`,
      "",
      `Paragraph ${i} with *italic*, **bold**, \`inline code\`, and <https://example.com/${i}>.`,
      "",
      "- first item",
      "  - nested item",
      "- second item",
      "",
    );
    if (i % 8 === 0) {
      lines.push("```ts", `const section${i} = ${i};`, "```", "");
    }
  }
  return lines.join("\n");
}

function generateImageDocument(repeats: number): string {
  const lines: string[] = ["# Literal Image Benchmark", ""];
  for (let i = 0; i < repeats; i++) {
    const image = i % 2 === 0
      ? "/images/literal-preview-a.svg"
      : "/images/literal-preview-b.svg";
    lines.push(
      `Image row ${i}: ![preview:w96](${image}) with trailing source text.`,
      "",
    );
  }
  lines.push("![standalone:w160](/images/literal-preview-a.svg)", "");
  return lines.join("\n");
}

function replaceFirst(
  source: string,
  needle: string,
  replacement: string,
): string {
  const index = source.indexOf(needle);
  if (index < 0) throw new Error(`missing benchmark needle: ${needle}`);
  return source.slice(0, index) + replacement +
    source.slice(index + needle.length);
}

function buildScenarios(): LiteralScenario[] {
  const plain = generateMarkdownDocument(32);
  const middleNeedle = "Paragraph 16";
  const image = generateImageDocument(12);
  const imageNeedle = "trailing source text";

  return [
    {
      name: "literal input: append plain text",
      source: plain,
      imagePreview: false,
      values: (total) =>
        Array.from({ length: total }, (_, i) => `${plain}\nTail edit ${i}`),
    },
    {
      name: "literal input: edit middle block",
      source: plain,
      imagePreview: false,
      values: (total) =>
        Array.from(
          { length: total },
          (_, i) =>
            replaceFirst(plain, middleNeedle, `${middleNeedle} edit ${i}`),
        ),
    },
    {
      name: "literal image preview: edit inline text",
      source: image,
      imagePreview: true,
      values: (total) =>
        Array.from(
          { length: total },
          (_, i) => replaceFirst(image, imageNeedle, `${imageNeedle} ${i}`),
        ),
    },
  ];
}

async function setupLiteralScenario(
  page: Page,
  options: BrowserBenchmarkOptions,
  scenario: LiteralScenario,
): Promise<void> {
  await page.goto(options.url);
  await page.waitForSelector("#source", { state: "attached" });
  await page.evaluate(
    ({ source, imagePreview }) => {
      const toggle = document.getElementById(
        "image-preview-toggle",
      ) as HTMLInputElement;
      if (toggle.checked !== imagePreview) toggle.click();

      const textarea = document.getElementById("source") as HTMLTextAreaElement;
      textarea.value = source;
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    },
    { source: scenario.source, imagePreview: scenario.imagePreview },
  );
  await waitTwoFrames(page);

  if (scenario.imagePreview) {
    await page.waitForFunction(() => {
      const images = Array.from(
        document.querySelectorAll("#rendered img.md-image-preview"),
      ) as HTMLImageElement[];
      return images.length > 0 &&
        images.every((img) =>
          img.complete && img.naturalWidth > 0 && img.naturalHeight > 0
        );
    });
  }

  const rendered = await page.locator("#rendered").boundingBox();
  if (!rendered) throw new Error("missing rendered benchmark target");
  await page.mouse.click(rendered.x + 4, rendered.y + 8);
  await page.waitForFunction(() => document.body.dataset.mode === "edit");
}

async function runLiteralBenchmarks(
  page: Page,
  options: BrowserBenchmarkOptions,
): Promise<BenchmarkResult[]> {
  const total = options.iterations + options.warmup;
  const scenarios = buildScenarios();
  const results: BenchmarkResult[] = [];

  for (const scenario of scenarios) {
    await setupLiteralScenario(page, options, scenario);
    const samples = await measureTextareaInputValues(page, {
      selector: "#source",
      values: scenario.values(total),
      warmup: options.warmup,
    });
    results.push(
      summarizeTimingSamples(scenario.name, samples, scenario.source.length),
    );
  }

  const imageScenario = scenarios.find((scenario) => scenario.imagePreview);
  if (!imageScenario) throw new Error("missing image benchmark scenario");
  await setupLiteralScenario(page, options, imageScenario);
  const toggleSamples = await measureClickAction(page, {
    selector: "#image-preview-toggle",
    total,
    warmup: options.warmup,
  });
  results.push(
    summarizeTimingSamples(
      "literal image preview: toggle",
      toggleSamples,
      imageScenario.source.length,
    ),
  );

  return results;
}

async function main(): Promise<void> {
  const options = parseBrowserBenchmarkOptions(process.argv.slice(2), {
    defaultUrl: DEFAULT_URL,
    envUrlName: "LITERAL_BENCH_URL",
    title: "Literal Editor Benchmark",
    tracePath: "literal-benchmark-trace.zip",
  });
  const results = await runBrowserBenchmark(options, runLiteralBenchmarks);

  if (options.json) {
    console.log(JSON.stringify({ options, results }, null, 2));
  } else {
    printBenchmarkMarkdown(results, options);
    if (options.trace) {
      console.log("");
      console.log(`Trace: ${options.tracePath}`);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
