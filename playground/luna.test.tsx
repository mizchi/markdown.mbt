/**
 * Luna reactivity pattern tests
 * Run: npx vitest run playground/luna.test.tsx
 *
 * Key findings:
 * - Effects run ASYNC via queueMicrotask (not sync like SolidJS)
 * - Memo runs SYNC
 * - Must await microtask after signal changes to see effect results
 */
import { describe, it, expect, vi } from "vitest";
import { createSignal, createEffect, createMemo, batch } from "@luna_ui/luna";

// Helper to wait for Luna effects to run
const tick = () => new Promise<void>(resolve => queueMicrotask(resolve));

describe("Luna signals - sync behavior", () => {
  it("basic signal read/write is sync", () => {
    const [count, setCount] = createSignal(0);
    expect(count()).toBe(0);
    setCount(1);
    expect(count()).toBe(1);
  });

  it("memo derives from signal (sync)", () => {
    const [count, setCount] = createSignal(1);
    const doubled = createMemo(() => count() * 2);

    expect(doubled()).toBe(2);
    setCount(5);
    expect(doubled()).toBe(10);
  });

  it("memo with string template (sync)", () => {
    const [mode, setMode] = createSignal("split");
    const className = createMemo(() => `container view-${mode()}`);

    expect(className()).toBe("container view-split");
    setMode("editor");
    // Memo updates synchronously!
    expect(className()).toBe("container view-editor");
  });

  it("memo with conditional class (sync)", () => {
    const [active, setActive] = createSignal(false);
    const btnClass = createMemo(() => `btn ${active() ? "active" : ""}`);

    expect(btnClass()).toBe("btn ");
    setActive(true);
    expect(btnClass()).toBe("btn active");
  });
});

describe("Luna effects - async behavior", () => {
  it("effect creation is async, but signal updates trigger sync?", async () => {
    const [count, setCount] = createSignal(0);
    const log: number[] = [];

    createEffect(() => {
      log.push(count());
    });

    // Effect has NOT run yet (async on creation)
    expect(log).toEqual([]);

    await tick();
    // Now it ran for initial value
    expect(log).toEqual([0]);

    setCount(1);
    // Let's see - does it run sync or async after setState?
    console.log("After setCount(1):", log);

    // It seems effect runs sync after signal change once tracking is established
    // This is different from initial creation
    expect(log).toEqual([0, 1]);
  });

  it("batch groups updates, effect runs once after microtask", async () => {
    const [a, setA] = createSignal(0);
    const [b, setB] = createSignal(0);
    const log: string[] = [];

    createEffect(() => {
      log.push(`a=${a()}, b=${b()}`);
    });

    await tick();
    expect(log).toEqual(["a=0, b=0"]);

    batch(() => {
      setA(1);
      setB(2);
    });

    await tick();
    // Should only have one entry for batched update
    expect(log).toEqual(["a=0, b=0", "a=1, b=2"]);
  });
});

describe("Luna JSX patterns", () => {
  it("class prop with memo value (recommended pattern)", () => {
    const [mode, setMode] = createSignal<"split" | "editor">("split");

    // This is the pattern that should work in JSX
    const containerClass = createMemo(() => `container view-${mode()}`);

    // Simulating what JSX would do with class={containerClass()}
    const getClass = () => containerClass();

    expect(getClass()).toBe("container view-split");
    setMode("editor");
    expect(getClass()).toBe("container view-editor");
  });

  it("class prop with direct signal (might not work)", () => {
    const [mode, setMode] = createSignal<"split" | "editor">("split");

    // Direct template literal - does this track?
    const getClass = () => `container view-${mode()}`;

    expect(getClass()).toBe("container view-split");
    setMode("editor");
    expect(getClass()).toBe("container view-editor");
  });
});

describe("DOM simulation", () => {
  it("simulating element.className update with memo", async () => {
    const [mode, setMode] = createSignal<"split" | "editor">("split");
    const containerClass = createMemo(() => `container view-${mode()}`);

    // Simulate DOM element
    const element = { className: "" };

    // Effect to update DOM (like Luna's internal binding)
    createEffect(() => {
      element.className = containerClass();
    });

    await tick();
    expect(element.className).toBe("container view-split");

    setMode("editor");
    // Effect runs sync after signal change (once tracking established)
    expect(element.className).toBe("container view-editor");
  });

  it("simulating element.className update with direct template", async () => {
    const [mode, setMode] = createSignal<"split" | "editor">("split");

    // Simulate DOM element
    const element = { className: "" };

    // Effect to update DOM with direct template (NOT memo)
    createEffect(() => {
      element.className = `container view-${mode()}`;
    });

    await tick();
    expect(element.className).toBe("container view-split");

    setMode("editor");
    // Does this also work?
    expect(element.className).toBe("container view-editor");
  });
});

// Requires jsdom environment - skipped in default node environment
describe.skip("Luna render behavior", () => {
  it("JSX class binding pattern", async () => {
    const [mode, setMode] = createSignal<"split" | "editor">("split");

    // Simulating how Luna might handle <div class={expr}>
    // In Luna JSX, class={expr} becomes something like:
    // createEffect(() => element.className = expr)

    const containerClass = createMemo(() => `container view-${mode()}`);

    // Mock element
    const element = document.createElement("div");

    // This is what Luna should do internally for class={containerClass()}
    createEffect(() => {
      const value = containerClass();
      element.className = value;
    });

    await tick();
    expect(element.className).toBe("container view-split");

    setMode("editor");
    expect(element.className).toBe("container view-editor");
  });

  it("innerHTML binding pattern", async () => {
    const svgString = '<svg width="20"><rect/></svg>';

    const element = document.createElement("span");

    // Simulating innerHTML={svgString}
    createEffect(() => {
      element.innerHTML = svgString;
    });

    await tick();
    expect(element.innerHTML).toBe(svgString);
    expect(element.querySelector("svg")).not.toBeNull();
  });
});
