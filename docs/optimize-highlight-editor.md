# SyntaxHighlightEditor Optimization Record

## Goal

A syntax-highlighted Markdown editor running at 60fps (16.67ms/frame)

## Final Results

| Test | P95 | Average | Status |
|--------|-----|------|------|
| Simple Typing | 16.3-17.4ms | ~15.5ms | Near boundary |
| Mixed Markdown | 16.4-18.1ms | ~15.4ms | Near boundary |
| Newlines | 16.4-17.3ms | ~15.3ms | Occasionally PASS |

Average values meet the target. P95 has variance due to external factors such as GC.

---

## Optimizations That Were Effective

### 1. Disabling Line Numbers by Default

**Effect: High**

```typescript
// Before: Always display and update line numbers
<For each={lineNumbersArray}>
  {(num) => <div class="line-number">{num}</div>}
</For>

// After: Made optional (disabled by default)
{props.showLineNumbers && (
  <div class="line-numbers">...</div>
)}
```

- Reduced line count signal update cost
- Reduced DOM element count
- Simplified scroll synchronization processing

### 2. Updating Only Changed Lines (Cursor Position Based)

**Effect: High**

```typescript
// Identify the current line from cursor position (no split needed)
const [cursorLine, lineStart, lineEnd] = getLineInfo(value, cursorPos);

// For single character input, update only the affected line
const rawLine = value.slice(lineStart, lineEnd);
if (lineElements[cursorLine]) {
  const newHighlight = highlightSingleLine(rawLine);
  if (prevHighlightedLines[cursorLine] !== newHighlight) {
    setLineContent(lineElements[cursorLine], newHighlight);
  }
}
```

- From full line recalculation to single line update
- Avoids `value.split("\n")` (significant effect on large documents)

### 3. Removing Full String Comparison

**Effect: Medium**

```typescript
// Before: O(n) string comparison
if (value === lastHighlightedValue) return;

// After: Removed (unnecessary since effects fire only on signal changes)
```

- Trust Luna's signal change detection
- Avoids O(n) comparison on large documents

### 4. Optimizing Newline Detection

**Effect: Medium**

```typescript
// Before: Count entire text each time
const newLineCount = countLines(value); // O(n)

// After: O(1) check for single character changes
const lengthDiff = valueLen - lastValueLength;
if (lengthDiff === 1) {
  // Check if the added character is a newline
  lineCountChanged = cursorPos > 0 && value[cursorPos - 1] === "\n";
} else if (lengthDiff === -1) {
  // For deletions, determine by cursor line change
  lineCountChanged = cursorLine !== lastCursorLine;
}
```

### 5. Choosing Between textContent and innerHTML

**Effect: Medium**

```typescript
function setLineContent(el: HTMLElement, html: string): void {
  if (html.indexOf("<") === -1) {
    // No HTML tags → textContent (no HTML parsing needed)
    if (html.indexOf("&") !== -1) {
      el.textContent = decodeEntities(html);
    } else {
      el.textContent = html;
    }
  } else {
    // HTML tags present → innerHTML required
    el.innerHTML = html;
  }
}
```

### 6. isUserInput Flag

**Effect: Medium**

```typescript
let isUserInput = false;

const handleInput = (e: Event) => {
  isUserInput = true;
  props.onChange(target.value);
};

createEffect(() => {
  const value = props.value();
  if (isUserInput) {
    isUserInput = false; // Skip textarea.value assignment
  } else if (editorRef) {
    editorRef.value = value; // Only set for external changes
  }
});
```

- Avoids re-setting textarea.value during user input

### 7. Show → CSS display Control

**Effect: High**

```typescript
// Before: Show component (child elements recreated each time)
<Show when={editorMode() === "highlight"}>
  <SyntaxHighlightEditor ... />
</Show>

// After: CSS display control (component state preserved)
<div style={{ display: editorMode() === "highlight" ? "contents" : "none" }}>
  <SyntaxHighlightEditor ... />
</div>
```

- Prevents component recreation
- Preserves internal state (cursor position, scroll position)

---

## Optimizations That Were Ineffective or Had Limited Effect

### 1. escapeHtml Optimization

**Effect: Limited**

```typescript
// Fast path added
let needsEscape = false;
for (let i = 0; i < text.length; i++) {
  if (c === "&" || c === "<" || c === ">" || c === '"') {
    needsEscape = true;
    break;
  }
}
if (!needsEscape) return text;
```

- Effective for most text
- Overall impact was small because the bottleneck was elsewhere (innerHTML, signal processing)

### 2. Caching (lineCache, inlineCache)

**Effect: Limited**

- Effective when re-highlighting the same line
- Low hit rate during input since content changes every time
- Effective within code blocks

---

## Things to Avoid

### 1. Debouncing with setTimeout / requestAnimationFrame

**Reason**: Luna's signal batch automatically batches via queueMicrotask, making additional scheduling unnecessary

```typescript
// Bad: Unnecessary overhead
const scheduleHighlight = () => {
  clearTimeout(highlightTimer);
  highlightTimer = window.setTimeout(updateHighlight, 16);
};

// Good: Direct invocation
const scheduleHighlight = () => {
  updateHighlight();
};
```

- Makes the call stack harder to read
- Makes debugging difficult
- Does not contribute to actual performance improvement

### 2. Excessive Variable Caching

**Reason**: Trust JavaScript engine optimizations

```typescript
// Excessive caching only reduces readability
const len = arr.length; // Often unnecessary
```

### 3. Using DocumentFragment (For This Use Case)

**Reason**: No effect for line-by-line updates. Only effective for bulk DOM insertions.

---

## Profile Analysis Results

Major bottlenecks (percentage of CPU time):

| Activity | Percentage | Description |
|----------|------|------|
| set value | 44.9% | DOM property setting in general |
| Parse HTML | 23.2% | innerHTML parsing |
| CPP GC | 10.2% | Garbage collection |
| highlightMarkdownLines | 5.3% | Markdown parsing |
| set innerHTML | 3.1% | innerHTML assignment |

### Fundamental Constraints

1. **innerHTML is unavoidable**: HTML tags are required for syntax highlighting
2. **GC is hard to control**: String operations inevitably allocate memory
3. **Parse HTML cost**: Browser HTML parsing overhead

---

## Future Improvement Directions

### Short-term (Additional Optimizations)

1. **Narrowing highlight targets**
   - Highlight only lines within the visible area (virtual scrolling approach)

2. **Regex optimization**
   - Pre-compile regular expressions in highlightMarkdownLine

3. **Offloading to Web Worker**
   - Execute highlight computation off the main thread

### Medium-term (Design Changes)

1. **Canvas / WebGL rendering**
   - Completely avoid DOM
   - The approach used by Monaco Editor / CodeMirror

2. **Differential highlighting**
   - Integration with incremental parsers like Tree-sitter

### Deferred

1. **Shadow DOM**: Does not contribute to performance improvement
2. **Web Components**: Only adds complexity

---

## How to Run Benchmarks

```bash
# Start development server
pnpm dev

# Run benchmarks
npx tsx e2e/benchmark.ts

# With trace (analyzable in DevTools)
npx tsx e2e/benchmark.ts --trace
```

---

## Reference: Before and After Comparison

### Before (Pre-optimization)

- Show component recreates every time
- Re-highlight all lines every time
- Full string comparison
- Always update line numbers

### After (Post-optimization)

- CSS display preserves state
- Update only the cursor line
- Rely on signal change detection
- Line numbers made optional

**Result**: Average input latency ~25ms → ~15ms (approximately 40% improvement)
