# Incremental Markdown Editor Architecture

## -- Lezer Method x CST Source of Truth Model x SSR/Hydration x WYSIWYG --

## 1. Purpose and Requirements

This design aims to build a Markdown editing foundation that simultaneously satisfies the following:

* **Editing experience first**

  * Input latency is barely perceptible
  * A single character input does not trigger full re-parse or re-render
* **Incremental Parsing**

  * Minimal recalculation using the last input position (cursor / change range) as a hint
* **GFM Compatible**

  * Display and structure generally match GitHub Markdown
* **SSR + Hydration**

  * Safely reuse server-generated HTML on the client
* **WYSIWYG Integration**

  * Rich display + structural editing
  * Lossless round-trip to Markdown
* **Split-pane Synchronization**

  * Stable mapping between source position and preview position

---

## 2. Overall Architecture Overview

```
Markdown Text
      |
      v
+---------------+
|   DocCST      |  <- Single Source of Truth
| (Block/Inline |
|  + Trivia)    |
+---------------+
      |
      +- Incremental Repair (Lezer-style)
      |
      +- Serializer (lossless)
      |
      +- Renderer
           |
           v
     DOM (SSR / CSR)
```

### Core Philosophy

* **CST (Concrete Syntax Tree) is the truth**
* Markdown text is *the serialization result of the CST*
* The parser is a "repairer/validator", not a "generator"

---

## 3. Parsing Strategy: Lezer Method (Block-driven, Fragment Reuse)

### 3.1 Why Not CFG

Markdown has the following properties:

* Line-based, indentation-dependent
* Strongly depends on open block context
* Has backward dependencies such as reference links

> Generic CFG/LR/PEG approaches are **slow or incompatible with incremental parsing**

### 3.2 Key Points of the Lezer Method

* **Process the Block layer as a line-driven state machine**
* **Parse the Inline layer lazily within Blocks**
* Never produce syntax errors (non-failing tentative parse)
* **Subtree (Fragment) reuse** is assumed

---

## 4. DocCST Design (Lossless)

### 4.1 Common Node Structure

```text
Node {
  nodeId        // Stable ID (preserved during reuse)
  kind          // Block / Inline type
  span {from,to} // Range in original Markdown
  children[]
  leadingTrivia
  trailingTrivia
}
```

### 4.2 What is Trivia

* Information needed to reconstruct the original notation

  * Whitespace
  * Newlines
  * Indentation
  * Trailing whitespace
* Does not affect semantics, but **essential for serialization**

### 4.3 Marker Preservation (Core of Lossless Design)

Inline / Block nodes preserve "which symbol was used".

Examples:

* Emphasis: `*` or `_`
* Strong: `**` or `__`
* FencedCode: ``` or ~~~
* List: `-` / `*` / `+`
* OrderedList: `1.` / `1)`

---

## 5. Role Division of Incremental Processing

### 5.1 Normal Path (Fastest)

* Edit operation → **Patch DocCST directly**
* No parsing runs
* Only re-render changed nodes

### 5.2 Repair Path (Safety Net)

Lezer-style re-parsing is triggered only in the following cases:

* CST operation fails
* Non-structural input (HTML paste, etc.)
* Context destruction (indentation collapse, etc.)

Processing:

* Re-parse only the Block containing the change range
* Maximize reuse of old nodes via Fragment Reuse
* Merge into DocCST

---

## 6. WYSIWYG Editing Model

### 6.1 Basic Policy

* DOM is **display only**
* Editing is defined as **CST patch operations**

### 6.2 Operation Primitives

Representative examples:

* `InsertText(nodeId, offset, text)`
* `DeleteRange(anchor, focus)`
* `ToggleMark(range, kind)`
* `WrapBlock(blockId, kind)`
* `SplitParagraph(blockId, offset)`
* `JoinBlocks(a, b)`

IME input (composition) is held as temporary text until committed.

---

## 7. Serializer (Lossless Round-Trip)

### 7.1 Basic Principles

* **Reconstruct the CST as-is**
* Faithfully output Trivia + markers
* Do not auto-format

### 7.2 Normalize Mode (Optional)

* Only executed on explicit user action
* Unifies notation, cleans up whitespace, etc.

---

## 8. SSR + Hydration Design

### 8.1 SSR HTML Requirements

Always attach the following per Block:

```html
<section
  data-block-id="..."
  data-from="123"
  data-to="456"
>
```

Inline elements get `data-node-id` as needed.

### 8.2 Hydration Procedure

1. Hydrate SSR HTML
2. Build DocCST from the same Markdown (or receive from server)
3. Generate `nodeId → DOM element` Map
4. Thereafter, **replace DOM only for changed nodes**

---

## 9. Split-Pane Synchronization (Editing Experience)

### 9.1 Source → Preview

1. Cursor position → `(nodeId, offset)`
2. Determine sync target Block
3. `blockId → DOM element`
4. `scrollIntoView`

Note: Not based on Inline (because scrolling becomes unstable)

### 9.2 Preview → Source

* Detect center Block with `IntersectionObserver`
* Scroll source to corresponding `span.from`
* Click restores selection directly from `data-node-id`

---

## 10. Handling Global Dependencies

### 10.1 Reference Link Definitions

* Manage `ReferenceIndex` separately (label → definition)
* Incrementally update on Block changes
* Re-resolve and re-render only affected Inlines

### 10.2 List Numbering

* Notation is preserved as trivia
* No automatic normalization
* Only formatted during Normalize

---

## 11. NodeId Stability Strategy

* Reusable nodes **retain their nodeId**
* Newly generated nodes use semi-stable IDs:

```
hash(
  kind,
  parentNodeId,
  localOrdinal,
  span.from,
  markerKind
)
```

> Key for DOM map synchronization and Hydration

---

## 12. Phased Implementation Roadmap

1. Block CST + trivia (Inline as raw text)
2. Introduce Inline (Code / Emph / Link)
3. WYSIWYG operations (Toggle / Split / Join)
4. ReferenceIndex incremental update
5. Introduce Lezer-style resynchronization phase

---

## 13. Design Essence (Summary)

> Treat Markdown not as "grammar" but as
> **an editable structure (CST)**

* The Lezer method is **the foundation for speed and stability**
* The CST source of truth model is **the common basis for WYSIWYG and SSR**
* Synchronization, Hydration, and differential updates are **unified via nodeId + span**

---

Next natural steps would be:

* **Concrete type definitions for CST (MoonBit)**
* **Detailed algorithm for performing ToggleMark (bold/italic) losslessly**
* **Minimal implementation of a Lezer-style Block parser**

---

## 14. Design Considerations for CRDT Support

Design notes anticipating future real-time collaborative editing (CRDT) support.

Reference: [CRDTs Go Brrr](https://josephg.com/blog/crdts-go-brrr/)

### 14.1 Current Implementation Status

```
src/core/markdown/
├── types.mbt          # CST type definitions (Span, Block, Inline)
├── scanner.mbt        # O(1) character access (Array[Char])
├── block_parser.mbt   # Block parser
├── inline_parser.mbt  # Inline parser
├── incremental.mbt    # Incremental parsing (EditInfo)
└── serializer.mbt     # Lossless serializer
```

### 14.2 Extensions Needed for CRDT Support

#### (A) Logical ID (Logical Position)

The current `Span { from, to }` uses absolute positions. CRDT requires logical positions:

```moonbit
// Current
#valtype
pub(all) struct Span {
  from : Int  // Absolute position
  to : Int
}

// CRDT proposal
pub(all) struct LogicalId {
  agent : AgentId   // Client identifier
  seq : Int         // Lamport clock / sequence number
}

pub(all) struct CrdtSpan {
  start_id : LogicalId
  end_id : LogicalId
  // Absolute positions can also be cached
  cached_from : Int?
  cached_to : Int?
}
```

#### (B) Tombstone (Deletion Marker)

In CRDT, deletions leave markers rather than actually removing data:

```moonbit
pub(all) enum NodeState {
  Active
  Deleted(deleted_by : LogicalId)
}

// Block extension proposal
pub(all) struct BlockMeta {
  id : LogicalId
  state : NodeState
  parent_id : LogicalId?
}
```

#### (C) Run-Length Encoding

Compress consecutive insertions (the article reports reduction from 180k to 12k entries):

```moonbit
// Represent consecutive text insertions as a single entry
pub(all) struct TextRun {
  start_id : LogicalId
  content : String      // Multiple characters
  len : Int             // Character count (negative for deletions)
}
```

#### (D) Separation of Concerns

Separate metadata and content for better cache efficiency:

```
DocStructure (B-tree)     DocContent (Rope)
├── BlockMeta[]           ├── TextRun[]
│   ├── id                │   └── content
│   ├── parent_id         │
│   └── state             │
└── aggregate counts      └── (flat array)
```

### 14.3 Patterns Already Adopted

| Pattern | Status | Implementation Location |
|---------|------|---------|
| Incremental update | Implemented | `incremental.mbt` |
| Cursor cache | Implemented | `find_affected_range()` |
| #valtype optimization | Implemented | `Span`, `EditInfo` |
| Flat structure | Block array | `Document.children` |
| Run-Length (text) | Partial | Consecutive text in `Inline::Text` |

### 14.4 Initial Verification Items

1. **Cost of introducing LogicalId**
   - Memory/speed impact when adding IDs to each node

2. **Impact of Tombstones**
   - Parse speed degradation due to accumulated deletion markers

3. **ID generation overhead**
   - Cost of generating and comparing Agent + Seq

### 14.5 Phased Migration Plan

```
Phase 1: Maintain current state
  - Absolute position based (Span)
  - Local editing only

Phase 2: Introduce IDs (optional)
  - Add LogicalId as nullable
  - None for local, generated only during collaboration

Phase 3: Full CRDT
  - Introduce Tombstones
  - Operation-based sync
  - Rope + B-tree structure
```

---

## 15. Performance Tuning Insights

### 15.1 Benchmark Environment

- MoonBit 0.x
- Targets: JS (V8), WASM-GC
- Measurement: `moon bench`

### 15.2 Scanner Optimization

**O(1) access via Array[Char] conversion:**

```moonbit
// Before: String.get_char(idx) is O(n) for UTF-8
// After: Array[Char] for O(1)
pub(all) struct Scanner {
  source : String
  chars : Array[Char]  // Pre-converted (code point array)
  mut pos : Int        // Position in code point units
  len : Int            // Number of code points
  utf16_offsets : Array[Int]?  // UTF-16 offsets for non-BMP characters
}
```

| Target | Effect |
|-----------|------|
| JS | Slight degradation (JS string optimization is powerful) |
| WASM-GC | **56% faster** (scanner peek/advance) |

**Conclusion**: Effective for WASM-GC production; acceptable range for JS.

### 15.2.1 Unicode (Non-BMP Character) Support

MoonBit strings internally use UTF-16:

| API | Return Value |
|-----|--------|
| `String.length()` | UTF-16 code unit count |
| `String.to_array()` | Unicode code point array |
| `String.unsafe_substring()` | Expects UTF-16 indices |

**Problem**: Non-BMP characters such as emoji (U+10000 and above) become surrogate pairs (2 units) in UTF-16. The Scanner's `pos` is in code point units, but `substring` uses UTF-16 indices, causing position mismatches.

**Solution**: Build a UTF-16 offset array only when non-BMP characters are present:

```moonbit
// Fast check: if UTF-16 length != code point count, non-BMP characters exist
let has_non_bmp = source.length() != chars.length()

// Build offset array only when non-BMP characters exist
let utf16_offsets : Array[Int]? = if has_non_bmp {
  // utf16_offsets[i] = UTF-16 start position of code point i
  Some(build_offsets(chars))
} else {
  None  // BMP characters only: no index conversion needed
}
```

**Performance impact**:

| Scenario | Overhead |
|---------|---------------|
| BMP characters only (Japanese, etc.) | **+2-5%** |
| Non-BMP characters present (emoji, etc.) | Offset array construction cost |

**Design decision**: Minimal impact on BMP characters such as Japanese and Chinese. Emoji are now processed correctly.

### 15.3 #valtype Optimization

Avoid heap allocation for small structs:

```moonbit
#valtype
pub(all) struct Span {
  from : Int
  to : Int
}
```

| Target | Effect |
|-----------|------|
| JS | **7-9% faster** |
| WASM-GC | No change (already optimized) |

**Applied to**: `Span`, `EditInfo`

### 15.4 Incremental Parsing Effect

| Document | Full Parse | Incremental | Speedup |
|-------------|-----------|-----------------|--------|
| 10 paragraphs | 68.89us | 7.36us | **9.4x** |
| 50 paragraphs | 327.99us | 8.67us | **37.8x** |
| 100 paragraphs | 651.14us | 15.25us | **42.7x** |

**Key points**:
- Only re-parse changed blocks
- Preceding and following blocks are reused (Span shift only)

### 15.5 CRDT-Related Overhead Measurement

Initial verification (JS, 1000 iterations):

| Operation | Time | Per Unit |
|------|------|-----------|
| LogicalId generation | 0.87us | **0.87ns/ID** |
| LogicalId comparison | 2.93us | **2.93ns/comparison** |
| CrdtDocument insert 100 | 1.10us | 11ns/insertion |
| Tombstone traversal (50% deleted) | 0.86us | Negligible |
| Span generation | 1.31us | Baseline |
| CrdtSpan generation | 4.48us | **3.4x slower** |

**Analysis**:
- LogicalId generation and comparison are sufficiently fast (nanosecond scale)
- CrdtSpan costs about 3.4x that of Span → caching strategy is important
- Tombstone traversal overhead is minimal

### 15.6 Recommended Design Patterns

1. **Apply #valtype to small structs**
   - Effective for structs with about 2-3 Int fields
   - `Span`, `EditInfo`, `LogicalId`, etc.

2. **Optimize array access**
   - WASM-GC: Pre-converting to `Array[Char]` is effective
   - JS: Native string APIs may be faster in some cases

3. **Aggressively use incremental processing**
   - Effect scales proportionally with document size
   - 40x+ speedup for 100 paragraphs

4. **Considerations when introducing CRDT**
   - Use absolute position caching alongside CrdtSpan
   - Consider compaction when tombstone ratio becomes high

---

## 16. Syntax Highlighting Design

### 16.1 Current Implementation (SSG)

Highlighting is processed with shiki at SSG build time; not executed on the client.

```
Markdown
    |
[MoonBit Parser] src/core/markdown/
    |
CST (FencedCode with info string)
    |
[Transformer] src/sol/ssg/markdown/transformer.mbt
    |
HTML (<pre data-lang="..." data-filename="...">)
    |
[Shiki Post-processor] scripts/shiki-highlight.ts
    |
HTML with syntax highlighting
```

**Code block info string parsing:**

```moonbit
// Decompose "ts:index.ts {highlight=[1,3]}"
pub(all) struct CodeBlockInfo {
  lang : String      // "ts"
  filename : String  // "index.ts"
  meta : String      // "{highlight=[1,3]}"
}

pub fn parse_code_block_info(info : String) -> CodeBlockInfo
```

**Performance (22 files, 135 code blocks):**

| Scenario | Total Time | shiki Processing | shiki Ratio |
|---------|---------|-----------|-----------|
| Cold cache | 2.5s | 737ms | 30% |
| Warm cache | 2.0s | 23ms | 1% |

With persistent caching (content hash), shiki does not dominate rebuild times.

### 16.2 Future Design: Trait-Based Highlighter Adapter

Platform abstraction is needed since native environments use tree-sitter.

```moonbit
// Highlight token (platform-independent)
pub(all) struct HighlightToken {
  text : String
  scope : HighlightScope
  start : Int
  end : Int
}

pub(all) enum HighlightScope {
  Keyword
  String
  Number
  Comment
  Function
  Type
  Variable
  Operator
  Punctuation
  Plain
}

// Highlighter interface
pub(all) trait Highlighter {
  highlight(Self, code : String, lang : String) -> Array[HighlightToken]
  supported_languages(Self) -> Array[String]
  is_supported(Self, lang : String) -> Bool
}

// Generate HTML from token list (common)
pub fn tokens_to_html(tokens : Array[HighlightToken]) -> String
```

**Proposed directory structure:**

```
src/core/highlight/
├── types.mbt           # HighlightToken, HighlightScope, trait Highlighter
├── html.mbt            # tokens_to_html (common)
└── moon.pkg.json       # target: all

src/platform/highlight/
├── shiki/              # For JS (FFI → shiki)
│   ├── adapter.mbt
│   └── moon.pkg.json   # target: js
└── treesitter/         # For Native (FFI → tree-sitter)
    ├── adapter.mbt
    └── moon.pkg.json   # target: native
```

**Integration with CST:**

```moonbit
fn highlight_code_block[H : Highlighter](
  highlighter : H,
  block : Block
) -> Array[HighlightToken] {
  match block {
    FencedCode(info~, code~, ..) => {
      let info = parse_code_block_info(info)
      if highlighter.is_supported(info.lang) {
        highlighter.highlight(code, info.lang)
      } else {
        [{ text: code, scope: Plain, start: 0, end: code.length() }]
      }
    }
    _ => []
  }
}
```

### 16.3 Design Considerations

| Item | Consideration |
|------|---------|
| Scope mapping | Scope names differ between shiki and tree-sitter → normalization layer needed |
| Async processing | shiki is async, tree-sitter is sync → affects trait design |
| Output format | Can generate HTML/ANSI/LSP semantic tokens from token list |
| Caching | Shareable across platforms via content hash |

### 16.4 GFM Styles

Using github-markdown-css for unified GFM styling:

```
assets/
├── github-markdown.css  # GFM styles (npm: github-markdown-css)
├── shiki.css            # For syntax highlighting
└── style.css            # For layout
```

Apply the `markdown-body` class in the HTML template:

```html
<article class="doc-content markdown-body">
  <!-- markdown content -->
</article>
```
