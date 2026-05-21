import { spawn } from "node:child_process";
import { chromium, type Page } from "playwright";

export interface BrowserBenchmarkOptions {
  url: string;
  iterations: number;
  warmup: number;
  trace: boolean;
  json: boolean;
  noServer: boolean;
  title: string;
  tracePath: string;
}

export interface BrowserBenchmarkDefaults {
  defaultUrl: string;
  envUrlName?: string;
  title: string;
  tracePath: string;
}

export interface BenchmarkResult {
  name: string;
  iterations: number;
  sourceBytes: number;
  sync: BenchmarkStats;
  settled: BenchmarkStats;
}

export interface BenchmarkStats {
  totalMs: number;
  meanMs: number;
  minMs: number;
  maxMs: number;
  p50Ms: number;
  p95Ms: number;
  p99Ms: number;
}

export interface TimingSample {
  syncMs: number;
  settledMs: number;
}

export function parseBrowserBenchmarkOptions(
  argv: string[],
  defaults: BrowserBenchmarkDefaults,
): BrowserBenchmarkOptions {
  const readNumber = (name: string, fallback: number): number => {
    const raw = argv.find((arg) => arg.startsWith(`--${name}=`))
      ?.slice(name.length + 3);
    if (raw == null) return fallback;
    const parsed = Number.parseInt(raw, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  };

  const readString = (name: string, fallback: string): string => {
    return argv.find((arg) => arg.startsWith(`--${name}=`))
      ?.slice(name.length + 3) ?? fallback;
  };

  const envUrl = defaults.envUrlName == null
    ? undefined
    : process.env[defaults.envUrlName];

  return {
    url: readString("url", envUrl ?? defaults.defaultUrl),
    iterations: readNumber("iterations", 60),
    warmup: readNumber("warmup", 12),
    trace: argv.includes("--trace"),
    json: argv.includes("--json"),
    noServer: argv.includes("--no-server"),
    title: defaults.title,
    tracePath: defaults.tracePath,
  };
}

export async function runBrowserBenchmark(
  options: BrowserBenchmarkOptions,
  run: (
    page: Page,
    options: BrowserBenchmarkOptions,
  ) => Promise<BenchmarkResult[]>,
): Promise<BenchmarkResult[]> {
  const stopServer = await ensureViteServer(options);
  const browser = await chromium.launch({ headless: true });

  try {
    const context = await browser.newContext({
      viewport: { width: 1280, height: 720 },
    });

    try {
      if (options.trace) {
        await context.tracing.start({ screenshots: true, snapshots: true });
      }

      const page = await context.newPage();
      const results = await run(page, options);

      if (options.trace) {
        await context.tracing.stop({ path: options.tracePath });
      }

      return results;
    } finally {
      await context.close();
    }
  } finally {
    await browser.close();
    stopServer?.();
  }
}

export async function waitTwoFrames(page: Page): Promise<void> {
  await page.evaluate(() =>
    new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    })
  );
}

export async function measureTextareaInputValues(
  page: Page,
  params: {
    selector: string;
    values: string[];
    warmup: number;
  },
): Promise<TimingSample[]> {
  return await page.evaluate(
    async ({ selector, values, warmup }) => {
      const textarea = document.querySelector(selector) as HTMLTextAreaElement;
      if (!textarea) throw new Error(`missing textarea: ${selector}`);
      const samples: Array<{ syncMs: number; settledMs: number }> = [];
      const waitFrames = () =>
        new Promise<void>((resolve) => {
          requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
        });

      for (let i = 0; i < values.length; i++) {
        const value = values[i]!;
        const start = performance.now();
        textarea.value = value;
        textarea.setSelectionRange(value.length, value.length);
        textarea.dispatchEvent(
          new InputEvent("input", {
            bubbles: true,
            inputType: "insertText",
            data: "",
          }),
        );
        const syncMs = performance.now() - start;
        await waitFrames();
        const settledMs = performance.now() - start;
        if (i >= warmup) samples.push({ syncMs, settledMs });
      }
      return samples;
    },
    params,
  );
}

export async function measureClickAction(
  page: Page,
  params: {
    selector: string;
    total: number;
    warmup: number;
  },
): Promise<TimingSample[]> {
  return await page.evaluate(
    async ({ selector, total, warmup }) => {
      const element = document.querySelector(selector) as HTMLElement | null;
      if (!element) throw new Error(`missing click target: ${selector}`);
      const samples: Array<{ syncMs: number; settledMs: number }> = [];
      const waitFrames = () =>
        new Promise<void>((resolve) => {
          requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
        });

      for (let i = 0; i < total; i++) {
        const start = performance.now();
        element.click();
        const syncMs = performance.now() - start;
        await waitFrames();
        const settledMs = performance.now() - start;
        if (i >= warmup) samples.push({ syncMs, settledMs });
      }
      return samples;
    },
    params,
  );
}

export function summarizeTimingSamples(
  name: string,
  samples: TimingSample[],
  sourceBytes: number,
): BenchmarkResult {
  return {
    name,
    iterations: samples.length,
    sourceBytes,
    sync: summarizeNumbers(samples.map((sample) => sample.syncMs)),
    settled: summarizeNumbers(samples.map((sample) => sample.settledMs)),
  };
}

export function printBenchmarkMarkdown(
  results: BenchmarkResult[],
  options: BrowserBenchmarkOptions,
): void {
  console.log(`# ${options.title}`);
  console.log("");
  console.log(`Date: ${new Date().toISOString()}`);
  console.log(`URL: ${options.url}`);
  console.log(`Iterations: ${options.iterations} (+${options.warmup} warmup)`);
  console.log("");
  console.log(
    "| Scenario | Source | Sync mean | Sync P95 | Settled mean | Settled P95 | Settled max |",
  );
  console.log("|---|---:|---:|---:|---:|---:|---:|");
  for (const result of results) {
    console.log(
      `| ${result.name} | ${result.sourceBytes} B | ${
        formatMs(result.sync.meanMs)
      } ms | ${formatMs(result.sync.p95Ms)} ms | ${
        formatMs(result.settled.meanMs)
      } ms | ${formatMs(result.settled.p95Ms)} ms | ${
        formatMs(result.settled.maxMs)
      } ms |`,
    );
  }
}

async function reachable(url: string): Promise<boolean> {
  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(500),
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitForUrl(url: string, timeoutMs: number): Promise<void> {
  const start = performance.now();
  while (performance.now() - start < timeoutMs) {
    if (await reachable(url)) return;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error(`timed out waiting for ${url}`);
}

async function ensureViteServer(
  options: BrowserBenchmarkOptions,
): Promise<(() => void) | null> {
  if (options.noServer || await reachable(options.url)) return null;

  const parsed = new URL(options.url);
  const port = parsed.port || (parsed.protocol === "https:" ? "443" : "80");
  const host = parsed.hostname || "127.0.0.1";
  const server = spawn("pnpm", ["vite", "--host", host, "--port", port], {
    stdio: options.json ? "ignore" : ["ignore", "ignore", "pipe"],
  });

  let stderr = "";
  let stopping = false;
  server.stderr?.on("data", (chunk) => {
    stderr += String(chunk);
  });

  server.on("exit", (code) => {
    if (stopping) return;
    if (code !== 0 && !options.json) {
      console.error(`vite exited with code ${code}`);
      if (stderr.length > 0) console.error(stderr.trim());
    }
  });

  await waitForUrl(options.url, 30_000);
  return () => {
    stopping = true;
    server.kill();
  };
}

function percentile(sorted: number[], p: number): number {
  const index = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, index)] ?? 0;
}

function summarizeNumbers(samples: number[]): BenchmarkStats {
  const sorted = [...samples].sort((a, b) => a - b);
  const totalMs = samples.reduce((sum, value) => sum + value, 0);
  return {
    totalMs,
    meanMs: totalMs / samples.length,
    minMs: sorted[0] ?? 0,
    maxMs: sorted[sorted.length - 1] ?? 0,
    p50Ms: percentile(sorted, 50),
    p95Ms: percentile(sorted, 95),
    p99Ms: percentile(sorted, 99),
  };
}

function formatMs(value: number): string {
  return value.toFixed(2);
}
