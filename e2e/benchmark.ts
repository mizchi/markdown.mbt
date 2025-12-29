/**
 * Performance benchmark for the markdown playground editor
 *
 * Measures:
 * - Input latency: Time from keypress to DOM update
 * - Frame timing: How long each input takes to process
 *
 * Usage:
 *   npx tsx e2e/benchmark.ts
 *   npx tsx e2e/benchmark.ts --trace  # Generate trace.json for DevTools
 */

import { chromium, type Page, type Browser } from "playwright";

const BASE_URL = "http://localhost:5175/";
const WARMUP_CHARS = 5;
const BENCHMARK_CHARS = 30;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

interface BenchmarkResult {
  name: string;
  inputCount: number;
  totalTime: number;
  avgTimePerInput: number;
  minTime: number;
  maxTime: number;
  p50: number;
  p95: number;
  p99: number;
}

async function measureInputLatency(page: Page, char: string): Promise<number> {
  // Inject performance marker before input
  await page.evaluate(() => {
    (window as any).__perfStart = performance.now();
  });

  // Type the character
  await page.keyboard.type(char, { delay: 0 });

  // Wait for RAF to complete (ensures DOM update)
  const elapsed = await page.evaluate(() => {
    return new Promise<number>((resolve) => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          const end = performance.now();
          const start = (window as any).__perfStart;
          resolve(end - start);
        });
      });
    });
  });

  return elapsed;
}

function calculatePercentile(sorted: number[], p: number): number {
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, index)]!;
}

async function runBenchmark(
  page: Page,
  name: string,
  inputChars: string
): Promise<BenchmarkResult> {
  const latencies: number[] = [];

  // Warmup
  console.log(`  Warmup (${WARMUP_CHARS} chars)...`);
  for (let i = 0; i < WARMUP_CHARS; i++) {
    await measureInputLatency(page, "x");
    if (i === 0) console.log(`  First warmup char done`);
  }
  console.log(`  Warmup complete`);

  // Clear warmup text
  console.log(`  Clearing warmup text...`);
  await page.keyboard.press("Meta+a");
  await page.keyboard.press("Backspace");
  await sleep(100);

  // Benchmark
  console.log(`  Running benchmark (${inputChars.length} chars)...`);
  const startTime = performance.now();
  for (let i = 0; i < inputChars.length; i++) {
    const char = inputChars[i]!;
    const latency = await measureInputLatency(page, char);
    latencies.push(latency);
    if (i === 0) console.log(`  First benchmark char done: ${latency.toFixed(2)}ms`);
    if ((i + 1) % 10 === 0) console.log(`  Progress: ${i + 1}/${inputChars.length}`);
  }
  const totalTime = performance.now() - startTime;
  console.log(`  Benchmark complete: ${totalTime.toFixed(0)}ms total`);

  // Calculate stats
  const sorted = [...latencies].sort((a, b) => a - b);
  const sum = latencies.reduce((a, b) => a + b, 0);

  return {
    name,
    inputCount: latencies.length,
    totalTime,
    avgTimePerInput: sum / latencies.length,
    minTime: sorted[0]!,
    maxTime: sorted[sorted.length - 1]!,
    p50: calculatePercentile(sorted, 50),
    p95: calculatePercentile(sorted, 95),
    p99: calculatePercentile(sorted, 99),
  };
}

function formatResult(result: BenchmarkResult): string {
  const fps60Target = 16.67; // ms per frame for 60fps
  const status = result.p95 < fps60Target ? "✅" : "❌";

  return `
## ${result.name} ${status}

| Metric | Value | Target |
|--------|-------|--------|
| Inputs | ${result.inputCount} | - |
| Total Time | ${result.totalTime.toFixed(1)}ms | - |
| Avg/Input | ${result.avgTimePerInput.toFixed(2)}ms | <16.67ms |
| Min | ${result.minTime.toFixed(2)}ms | - |
| Max | ${result.maxTime.toFixed(2)}ms | - |
| P50 | ${result.p50.toFixed(2)}ms | <16.67ms |
| P95 | ${result.p95.toFixed(2)}ms | <16.67ms |
| P99 | ${result.p99.toFixed(2)}ms | <16.67ms |

60fps target: ${result.p95 < fps60Target ? "PASS" : "FAIL"} (P95 ${result.p95 < fps60Target ? "<" : ">"} 16.67ms)
`;
}

async function main() {
  const enableTrace = process.argv.includes("--trace");

  console.log("🚀 Starting benchmark...\n");
  console.log(`URL: ${BASE_URL}`);
  console.log(`Warmup: ${WARMUP_CHARS} chars`);
  console.log(`Benchmark: ${BENCHMARK_CHARS} chars`);
  console.log(`Trace: ${enableTrace ? "enabled" : "disabled"}\n`);

  console.log("Launching browser...");
  const browser: Browser = await chromium.launch({
    headless: true,
  });

  try {
    console.log("Creating context...");
    const context = await browser.newContext({
      viewport: { width: 1280, height: 720 },
    });
    const page = await context.newPage();

    // Start tracing if enabled
    if (enableTrace) {
      await context.tracing.start({ screenshots: true, snapshots: true });
    }

    // Navigate and wait for editor
    console.log("Navigating to page...");
    await page.goto(BASE_URL);
    console.log("Waiting for editor container...");
    await page.waitForSelector(".syntax-editor-container", { timeout: 10000 });
    console.log("Editor container found, waiting for initialization...");
    await sleep(500); // Let everything initialize

    // Focus the textarea
    console.log("Focusing textarea...");
    const textarea = page.locator("textarea").first();
    await textarea.click();
    console.log("Textarea focused");

    // Clear initial content
    console.log("Clearing initial content...");
    await page.keyboard.press("Meta+a");
    await page.keyboard.press("Backspace");
    await sleep(100);

    // Run benchmarks
    console.log("Starting benchmarks...\n");
    const results: BenchmarkResult[] = [];

    // Benchmark 1: Simple typing (letters)
    console.log("Running benchmark 1: Simple typing...");
    const simpleChars = "a".repeat(BENCHMARK_CHARS);
    results.push(await runBenchmark(page, "Simple Typing (letters)", simpleChars));

    // Clear
    await page.keyboard.press("Meta+a");
    await page.keyboard.press("Backspace");
    await sleep(100);

    // Benchmark 2: Mixed content (markdown-like)
    const mixedChars = "# Hello World\n\nThis is **bold** and *italic* text.\n\n```js\nconst x = 1;\n```\n".slice(0, BENCHMARK_CHARS);
    results.push(await runBenchmark(page, "Mixed Markdown", mixedChars));

    // Clear
    await page.keyboard.press("Meta+a");
    await page.keyboard.press("Backspace");
    await sleep(100);

    // Benchmark 3: Newlines (triggers line number updates)
    const newlineChars = "line\n".repeat(BENCHMARK_CHARS / 5).slice(0, BENCHMARK_CHARS);
    results.push(await runBenchmark(page, "Newlines (line numbers)", newlineChars));

    // Stop tracing
    if (enableTrace) {
      await context.tracing.stop({ path: "trace.zip" });
      console.log("📊 Trace saved to trace.zip");
      console.log("   View with: npx playwright show-trace trace.zip\n");
    }

    // Output results
    console.log("# Benchmark Results\n");
    console.log(`Date: ${new Date().toISOString()}`);
    console.log(`Target: 60fps (16.67ms per frame)\n`);

    for (const result of results) {
      console.log(formatResult(result));
    }

    // Summary
    const allPass = results.every((r) => r.p95 < 16.67);
    console.log(`\n## Summary: ${allPass ? "✅ ALL PASS" : "❌ NEEDS IMPROVEMENT"}`);

    // Exit with appropriate code
    process.exit(allPass ? 0 : 1);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error("Benchmark failed:", err);
  process.exit(1);
});
