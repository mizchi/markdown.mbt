# Code Highlighting Implementation Research

## Overview

Investigating the feasibility of implementing Shiki/TextMate-based code highlighting in MoonBit.

## Shiki Architecture

```
+-------------------------------------------------------------+
|  textmate-grammars-themes                                    |
|  +- Collects grammars/themes from VSCode, etc.               |
|  +- Normalizes to JSON format                                |
|  +- Auto-updated daily, distributed via npm                  |
+-------------------------------------------------------------+
                          |
+-------------------------------------------------------------+
|  Shiki                                                       |
|  +- vscode-textmate (tokenizer core)                         |
|  +- engine-oniguruma (WASM regex engine)                     |
|  +- engine-javascript (via oniguruma-to-es)                  |
+-------------------------------------------------------------+
```

### Key Components

| Component | Role | Repository |
|--------------|------|-----------|
| textmate-grammars-themes | Grammar/theme collection and normalization | [shikijs/textmate-grammars-themes](https://github.com/shikijs/textmate-grammars-themes) |
| vscode-textmate | TextMate grammar interpreter | [microsoft/vscode-textmate](https://github.com/microsoft/vscode-textmate) |
| engine-oniguruma | Oniguruma WASM wrapper | shikijs/shiki |
| oniguruma-to-es | Oniguruma to JS conversion | [slevithan/oniguruma-to-es](https://github.com/slevithan/oniguruma-to-es) |

## How TextMate Grammar Works

### Basic Structure

```json
{
  "name": "JavaScript",
  "scopeName": "source.js",
  "patterns": [
    { "include": "#comments" },
    { "include": "#strings" }
  ],
  "repository": {
    "comments": {
      "match": "//.*$",
      "name": "comment.line.double-slash.js"
    },
    "strings": {
      "begin": "\"",
      "end": "\"",
      "name": "string.quoted.double.js",
      "patterns": [
        { "match": "\\\\.", "name": "constant.character.escape.js" }
      ]
    }
  }
}
```

### Pattern Types

1. **match**: Single-line pattern
   ```json
   { "match": "\\b(if|else|while)\\b", "name": "keyword.control" }
   ```

2. **begin/end**: Multi-line structures
   ```json
   {
     "begin": "/\\*",
     "end": "\\*/",
     "name": "comment.block"
   }
   ```

3. **include**: Reference other patterns
   ```json
   { "include": "#strings" }
   { "include": "source.css" }
   ```

### Tokenization Algorithm

```
Input: list of lines, grammar, initial state
Output: token list

for each line:
    tokens = []
    position = 0

    while position < line.length:
        best_match = None

        # Try all patterns in the current rule stack
        for pattern in current_rules:
            match = pattern.match(line, position)
            if match and (best_match is None or match.start < best_match.start):
                best_match = match

        if best_match:
            # Tokenize text before the match
            if best_match.start > position:
                tokens.append(Token(position, best_match.start, current_scope))

            # Process the match
            if pattern.type == 'begin':
                push_state(pattern.end, pattern.patterns)
            elif pattern.type == 'end':
                pop_state()

            tokens.append(Token(best_match, pattern.scope))
            position = best_match.end
        else:
            # No match - current scope to end of line
            tokens.append(Token(position, line.length, current_scope))
            break

    yield tokens
```

### Important Constraints

- **Line-by-line processing**: Regular expressions match against a single line only
- **State management**: `ruleStack` maintains context across lines
- **Scope nesting**: Tokens carry a list of parent scopes

## Regex Engine Comparison

### Oniguruma vs JavaScript RegExp

| Feature | Oniguruma | JS RegExp | Notes |
|------|-----------|-----------|------|
| Basic patterns | Yes | Yes | |
| Lookahead `(?=)` `(?!)` | Yes | Yes | |
| Lookbehind `(?<=)` `(?<!)` | Yes | Yes (ES2018+) | |
| Named captures | Yes | Yes (ES2018+) | |
| Unicode properties | Yes | Yes (ES2018+) | |
| Atomic groups `(?>)` | Yes | No | Can be emulated |
| Conditionals `(?(1)...)` | Yes | No | |
| `\G` anchor | Yes | No | Previous match position |
| `\K` (match reset) | Yes | No | |

### Engine Options

| Engine | Size | Compatibility | Speed |
|---------|--------|--------|------|
| Oniguruma WASM | ~1.3MB | 100% | Fast |
| oniguruma-to-es | ~3KB | 99.99% | Faster |

## Current State of MoonBit regex

### Supported Features

```moonbit
// Basic
let re = @regex.compile("a(bc|de)f")

// Character classes
let re = @regex.compile("\\d+\\.\\d{2}")

// Named captures
let re = @regex.compile("(?<year>\\d{4})-(?<month>\\d{2})")

// Unicode properties
let re = @regex.compile("\\p{Letter}+")
```

### Features Required for TextMate but Not Yet Implemented

| Feature | Usage | Importance |
|------|------|--------|
| `\G` anchor | Continuous matching | **Required** |
| Lookahead `(?=)` `(?!)` | Boundary detection | High |
| Lookbehind `(?<=)` `(?<!)` | Boundary detection | High |
| Backreference | Referencing begin in end | High |
| Atomic groups `(?>)` | Backtracking control | Medium |

### Importance of `\G`

`\G` is frequently used in TextMate grammars:

```json
{
  "begin": "\\{",
  "end": "\\}",
  "patterns": [
    {
      "match": "\\G\\s*",
      "name": "meta.brace.open"
    }
  ]
}
```

`\G` means "the position where the previous match ended" and is essential for continuous tokenization.

## Implementation Approaches

### Option A: WASM FFI (Recommended for Initial Implementation)

```
MoonBit (API) → JS FFI → vscode-textmate + oniguruma-to-es
```

**Advantages**:
- Minimal development cost
- 100% TextMate compatible
- Use existing grammars/themes as-is

**Disadvantages**:
- JS environment dependent
- Not WASM-GC native

### Option B: Implement Tokenizer in MoonBit

```moonbit
pub(all) struct Grammar {
  scope_name : String
  patterns : Array[Pattern]
  repository : Map[String, Pattern]
}

pub(all) enum Pattern {
  Match(regex~, name~, captures~)
  BeginEnd(begin~, end~, name~, patterns~, content_name~)
  Include(ref~)
}

pub(all) struct RuleStack {
  rules : Array[Rule]
  // State management
}

pub fn tokenize_line(
  grammar : Grammar,
  line : String,
  state : RuleStack,
  regex_engine : RegexEngine  // External engine
) -> (Array[Token], RuleStack)
```

**Advantages**:
- MoonBit native
- Regex engine can be swapped

**Disadvantages**:
- Medium development cost
- Regex engine issues remain

### Option C: Extending MoonBit regex

Implement required features:

1. `\G` anchor (can be substituted with position parameter)
2. Lookahead/Lookbehind
3. Backreference

**Advantages**:
- Fully MoonBit native
- Fast on WASM-GC

**Disadvantages**:
- High development cost
- Full feature implementation is difficult

### Option D: tree-sitter Approach

Use tree-sitter parsers instead of TextMate.

**MoonBit bindings**: [tonyfettes/tree_sitter](https://mooncakes.io/docs/tonyfettes/tree_sitter)

```moonbit
let moonbit = @tree_sitter_moonbit.language()
let parser = @tree_sitter.Parser::new()
parser.set_language(moonbit)
let tree = parser.parse_string(source_code)
let root = tree.root_node()
```

**Advantages**:
- Generates accurate syntax trees (AST)
- Supports incremental parsing
- MoonBit bindings already exist
- Many language grammars available

**Disadvantages**:
- No compatibility with TextMate themes (different scope systems)
- Dependency on C library (via WASM)
- Grammar files are large

### Option E: Lezer Approach

A JavaScript-based parser system used by CodeMirror 6.

**Features**:
- LR parser (GLR option)
- Supports incremental parsing
- Error recovery
- Compact output size

```javascript
// Lezer grammar example
@top Program { expression* }
expression { Number | BinaryExpression }
BinaryExpression { expression ("+" | "-") expression }
@tokens { Number { @digit+ } }
```

**Advantages**:
- Pure JavaScript (no WASM needed)
- Compact parser tables
- Memory efficient (64bit/node)
- Optimized for the web

**Disadvantages**:
- No compatibility with TextMate themes
- Small grammar ecosystem (~15 languages)
- No MoonBit bindings (needs implementation)

### Option Comparison Table

| Approach | Dev Cost | Compatibility | Performance | Ecosystem |
|-----------|-----------|--------|--------------|-------------|
| A) JS FFI (shiki) | Low | TextMate 100% | Medium | Rich |
| B) MoonBit tokenizer | Medium | TextMate 100% | High | Rich |
| C) MoonBit regex extension | High | TextMate 80-90% | High | Rich |
| D) tree-sitter | Low-Medium | tree-sitter | High | Rich |
| E) Lezer | Medium-High | Lezer | High | Limited |

### tree-sitter vs Lezer vs TextMate

| Aspect | TextMate | tree-sitter | Lezer |
|------|----------|-------------|-------|
| Parse method | Regular expressions | LR/GLR | LR/GLR |
| Accuracy | Token level | AST level | AST level |
| Incremental | Line-by-line | Node-by-node | Node-by-node |
| Implementation language | - | C/Rust | JavaScript |
| Number of grammars | 200+ | 100+ | ~15 |
| Theme ecosystem | VSCode compatible | Custom | Custom |
| Bundle size | Small | Large (WASM) | Medium |

## Recommended Roadmap

### Phase 1: JS FFI Prototype

```
Goal: Quickly implement a working highlighter

MoonBit API
    |
JS Binding (extern "js")
    |
shiki / vscode-textmate
```

- Use existing grammars/themes
- Validate API design

### Phase 2: MoonBit-ify the Tokenizer

```
Goal: Port core processing to MoonBit

MoonBit Tokenizer
    |
Regex Engine (external)
    |
oniguruma-to-es or Oniguruma WASM
```

- Implement state management in MoonBit
- Delegate regex to external engine

### Phase 3: In-house Regex Engine (Optional)

```
Goal: Fully MoonBit implementation

MoonBit Tokenizer
    |
MoonBit Regex (extended version)
```

- Implement required Oniguruma features
- Performance optimization

## References

- [Shiki Official Documentation](https://shiki.style/guide/)
- [TextMate Language Grammars](https://macromates.com/manual/en/language_grammars)
- [vscode-textmate](https://github.com/microsoft/vscode-textmate)
- [oniguruma-to-es](https://github.com/slevithan/oniguruma-to-es)
- [Writing a TextMate Grammar](https://www.apeth.com/nonblog/stories/textmatebundle.html)
- [VS Code Syntax Highlight Guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)
- [MoonBit Regex Implementation](https://www.moonbitlang.com/pearls/moonbit-regex)

## vscode-textmate Implementation Details

### Key Classes

| Class | Role |
|--------|------|
| `Grammar` | Grammar management, rule registration, tokenization execution |
| `StateStackImpl` | Manages state across lines as a linked list |
| `AttributedScopeStack` | Holds scope hierarchy + attributes |
| `LineTokens` | Per-line token generation and aggregation |

### StateStackImpl Structure

```typescript
class StateStackImpl {
  ruleId: RuleId;              // Current rule identifier
  nameScopesList: ScopeStack;  // Scopes from "name" attributes
  contentNameScopesList: ScopeStack;  // Scopes from "contentName"
  enterPos: number;            // Start position within the line
  anchorPos: number;           // Anchor position
  beginRuleCapturedEOL: boolean;  // Whether a newline was captured
  parent: StateStackImpl | null;  // Parent state (linked list)
}
```

### Tokenization Flow

```
tokenizeLine(line, prevState)
    |
_tokenize(line, prevState, emitBinaryTokens)
    |
_tokenizeString(line, isFirstLine, linePos, stack, lineTokens)
    |
Match each pattern → select the best match
    |
If begin: push_state / If end: pop_state
    |
Add tokens to LineTokens
```

### Injection Grammars

A feature for dynamically injecting external grammars:

```typescript
// CSS/JS within HTML, etc.
{
  "injections": {
    "L:source.js": {
      "patterns": [...]
    }
  }
}
```

`_collectInjections()` collects selector-pattern pairs and dynamically merges them on match.

### Token Attribute Encoding

For performance, token attributes are compressed into bit fields:

```typescript
// EncodedTokenAttributes (32bit)
// [languageId:8][tokenType:8][fontStyle:3][foreground:9][background:9]
```

## MoonBit regex Detailed Investigation

### Confirmed Supported Features

| Feature | Supported | Verification |
|------|---------|---------|
| Basic patterns `a(bc|de)f` | Yes | Documentation example |
| Character classes `\d`, `\w` | Yes | Documentation example |
| Named captures `(?<name>...)` | Yes | Documentation example |
| Unicode properties `\p{Letter}` | Yes | Documentation example |
| Quantifiers `+`, `*`, `?`, `{n,m}` | Yes | Documentation example |

### Unconfirmed / Not Documented

| Feature | Supported | Notes |
|------|---------|------|
| Lookahead `(?=...)` `(?!...)` | Unknown | Not documented |
| Lookbehind `(?<=...)` `(?<!...)` | Unknown | Not documented |
| Backreference `\1` | Unknown | Not documented |
| `\G` anchor | No | Presumed difficult to implement |
| `^`, `$` anchors | Unknown | Unverified |

### lexmatch Syntax (Language Built-in)

MoonBit has a language-level regex syntax called `lexmatch`:

```moonbit
// Default mode (top-down, re2-style)
lexmatch s {
  (_, "re1" ("re2" as r), _) => ...
  "re3" => ...  // Implicitly ^ and $
}

// Longest mode (POSIX, longest match)
lexmatch s using longest {
  ("re1" ("re2" as re2), next) => ...
}
```

**Note**: `lexmatch` is a compile-time DSL and is different from `@regex.compile()`.

## tree-sitter Highlighting Mechanism

### Query-Based Highlighting

tree-sitter defines highlight rules in `.scm` (Scheme) files:

```scheme
; highlights.scm
"func" @keyword
(type_identifier) @type
(function_name) @function
(string_literal) @string
(comment) @comment
```

### Three Types of Query Files

| File | Role |
|---------|------|
| `highlights.scm` | Assign highlight names to nodes |
| `locals.scm` | Scope and variable tracking (distinguishing definitions/references) |
| `injections.scm` | Language embedding (JS within HTML, etc.) |

### locals.scm Example

```scheme
; Nodes that introduce scope
(function_definition) @local.scope

; Variable definition
(parameter name: (identifier) @local.definition)

; Variable reference
(identifier) @local.reference
```

### Differences from TextMate

| Aspect | TextMate | tree-sitter |
|------|----------|-------------|
| Match target | Text (regular expressions) | AST nodes |
| Scope system | `source.js`, `keyword.control` | `@keyword`, `@function` |
| Precision | Token level | Syntax level |
| Definition/reference distinction | Difficult | Possible via `locals.scm` |

### Theme Mapping

```json
{
  "theme": {
    "keyword": "#C678DD",
    "function": "#61AFEF",
    "string": "#98C379",
    "comment": { "color": "#5C6370", "italic": true }
  }
}
```

## Application to This Project

### Current Setup

```
markdown.mbt/
├── src/           # MoonBit parser implementation
├── js/api.js      # JS API wrapper
└── target/js/     # Build output
```

The existing `js/api.js` is a JS binding for the Markdown parser implemented in MoonBit.

### Options for Adding Highlighting

#### Option 1: Shiki Integration (Minimum Effort)

```javascript
// Add to js/api.js
import { codeToHtml } from 'shiki';

export async function highlightCode(code, lang) {
  return await codeToHtml(code, { lang, theme: 'github-dark' });
}
```

- Called when rendering FencedCode blocks
- Full TextMate compatibility
- Async API

#### Option 2: tree-sitter MoonBit Bindings

```moonbit
// src/highlight.mbt
fn highlight_code(code: String, lang: String) -> Array[Token] {
  let parser = @tree_sitter.Parser::new()
  let language = get_language(lang)  // Per-language grammar
  parser.set_language(language)
  let tree = parser.parse_string(code)

  // Highlight via queries
  let query = @tree_sitter.Query::new(language, highlights_scm)
  let captures = query.captures(tree.root_node())

  // Convert to Tokens
  captures.map(fn(c) { Token { ... } })
}
```

- MoonBit native
- Requires C bindings (WASM/Native)

#### Option 3: Simple Highlighter (Custom Implementation)

```moonbit
// Tokenize per language using lexmatch
fn highlight_js(code: StringView) -> Array[Token] {
  let tokens = []
  for rest = code {
    lexmatch rest {
      ("//[^\n]*", next) => { tokens.push(Token::Comment(...)); continue next }
      ("\"[^\"]*\"", next) => { tokens.push(Token::String(...)); continue next }
      ("\\b(function|const|let|var)\\b", next) => { tokens.push(Token::Keyword(...)); continue next }
      (_, next) => continue next
    }
  }
  tokens
}
```

- Fully MoonBit native
- Requires per-language implementation
- Less accurate than TextMate/tree-sitter

### Recommended Approach

**Phase 1**: Shiki integration (at the JS layer)
- Detect FencedCode in `toHtml()` and highlight with Shiki
- Quick to get working

**Phase 2**: Leverage tree-sitter bindings
- Use `tonyfettes/tree_sitter`
- Handle highlighting on the MoonBit side
- More integrated architecture

## Lezer MoonBit Porting Plan

### Why Lezer

| Aspect | tree-sitter | Lezer | Reason for Choice |
|------|-------------|-------|---------|
| Implementation language | C/Rust | TypeScript | TS is readable and easy to port |
| Code size | Large | Small (~3000 lines) | Less porting effort |
| Design philosophy | General-purpose | Web/editor-oriented | High affinity with markdown.mbt |
| Syntax tree | Detailed AST | Compact (64bit/node) | Memory efficiency focus |
| Incremental | Yes | Yes | Both supported |

### Lezer Core Architecture

```
+-------------------------------------------------------------+
|  @lezer/generator                                           |
|  .grammar file → parser table generation                     |
+-------------------------------------------------------------+
                          |
+-------------------------------------------------------------+
|  @lezer/lr (runtime)                                        |
|  +- LRParser: Execute parser tables                          |
|  +- Stack: LR stack management                               |
|  +- PartialParse: Incremental parsing                        |
+-------------------------------------------------------------+
                          |
+-------------------------------------------------------------+
|  @lezer/common (syntax tree)                                |
|  +- Tree: Syntax tree root                                   |
|  +- TreeBuffer: Compact node storage (Uint16Array)           |
|  +- TreeCursor: Efficient traversal                          |
|  +- SyntaxNode: Node reference                               |
+-------------------------------------------------------------+
```

### Affinity with markdown.mbt

The current markdown.mbt is CST-based:

```moonbit
// markdown.mbt Span
pub(all) struct Span {
  from : Int
  to : Int
}

// Lezer-compatible design
pub(all) struct NodeType {
  id : Int
  name : String
}

pub(all) struct TreeNode {
  node_type : NodeType
  from : Int      // Compatible with Span.from
  to : Int        // Compatible with Span.to
  children : Array[TreeNode]
}
```

**Common points**:
- Position information (from/to) concept is consistent
- Nested structure (children)
- Type annotation

**Design policy**:
1. Implement Lezer's Tree/TreeBuffer in MoonBit
2. Maintain compatibility with markdown.mbt's Span
3. Provide efficient traversal via TreeCursor

### MoonBit Porting Design

#### Phase 1: Basic Data Structures

```moonbit
// src/lezer/types.mbt

/// Node type definition
pub(all) struct NodeType {
  id : Int
  name : String
  // props to be added later
}

/// Compact syntax tree (equivalent to Lezer's TreeBuffer)
/// Each node: 4 elements of [type_id, from, to, child_end_index]
pub(all) struct TreeBuffer {
  data : Array[Int]  // Instead of Uint16Array
  length : Int
}

/// Syntax tree
pub(all) enum Tree {
  Node(
    node_type~ : NodeType,
    from~ : Int,
    to~ : Int,
    children~ : Array[Tree]
  )
  Buffer(buffer~ : TreeBuffer, from~ : Int, to~ : Int)
}

/// Cursor for efficient traversal
pub(all) struct TreeCursor {
  tree : Tree
  stack : Array[(Tree, Int)]  // (node, child_index)
  mut pos : Int
}
```

#### Phase 2: Parser Runtime

```moonbit
// src/lezer/parser.mbt

/// LR parser stack
pub(all) struct Stack {
  states : Array[Int]       // State stack
  values : Array[Tree]      // Value stack
  mut pos : Int             // Input position
}

/// Parser table (pre-generated)
pub(all) struct ParseTable {
  states : Array[StateRow]
  // goto, actions, etc.
}

/// Parser
pub(all) struct Parser {
  table : ParseTable
  node_types : Array[NodeType]
}

pub fn Parser::parse(self : Parser, input : String) -> Tree
```

#### Phase 3: Incremental Parsing

```moonbit
// src/lezer/incremental.mbt

/// Edit information (compatible with markdown.mbt's EditInfo)
pub(all) struct TreeEdit {
  from : Int
  to : Int
  new_length : Int
}

/// Incremental parsing
pub fn Parser::parse_incremental(
  self : Parser,
  old_tree : Tree,
  input : String,
  edits : Array[TreeEdit]
) -> Tree
```

### markdown.mbt Integration Design

```moonbit
// Future integration vision

// Highlighting FencedCode blocks
fn highlight_fenced_code(block : Block) -> Array[HighlightToken] {
  guard block is FencedCode(info~, code~, span~) else { return [] }

  let lang = parse_language_info(info)
  let parser = get_parser_for_language(lang)  // Lezer parser
  let tree = parser.parse(code)

  // Traverse tree to generate highlight tokens
  let tokens = []
  let cursor = tree.cursor()
  while cursor.next() {
    let highlight = get_highlight_for_node(cursor.node_type)
    if highlight.is_some() {
      tokens.push(HighlightToken {
        from: span.from + cursor.from,  // Position in original document
        to: span.from + cursor.to,
        highlight: highlight.unwrap()
      })
    }
  }
  tokens
}
```

### Implementation Roadmap

| Phase | Content | Effort | Dependencies | Status |
|-------|------|------|---------|------|
| 1 | Tree/TreeBuffer/TreeCursor | 1 week | None | Completed |
| 2 | Stack/LR parser | 2 weeks | Phase 1 | Not started |
| 3 | Incremental parsing | 2 weeks | Phase 2 | Not started |
| 4 | Grammar DSL (simplified) | 2 weeks | Phase 2 | Not started |
| 5 | Highlight queries | 1 week | Phase 1 | Not started |
| 6 | markdown.mbt integration | 1 week | Phase 1, 5 | Not started |

**MVP (Minimum Implementation)**: Phase 1 + manual parser + Phase 5 + Phase 6

### Phase 1 Implemented (src/lezer/)

```
src/lezer/
├── moon.pkg.json      # Package configuration
├── types.mbt          # Core data structures
├── types_test.mbt     # Core tests (9 cases)
├── json.mbt           # JSON parser implementation
├── json_test.mbt      # JSON tests (14 cases)
├── highlight.mbt      # Highlighting functionality
└── highlight_test.mbt # Highlighting tests (10 cases)
```

**All 33 tests pass**

**Implemented features**:

*Core data structures*:
- `NodeType`: Node type definition
- `Tree`: Syntax tree (Node/Leaf/Buffered)
- `TreeBuffer`: Compact node storage
- `TreeCursor`: Efficient traversal
- `Tree::iter()`: Depth-first iteration
- `Tree::resolve(pos)`: Node lookup by position

*JSON parser (reference implementation)*:
- `JsonTokenizer`: Tokenizer
- `JsonParser`: Recursive descent parser
- `parse_json(source)`: JSON → Tree

*Highlighting*:
- `HighlightTag`: Standard highlight tags (String, Number, Keyword, etc.)
- `Highlighter`: Node → tag mapping
- `highlight_json(source)`: JSON highlight token generation
- `highlight_json_to_html(source)`: HTML output

**Usage example**:

```moonbit
// Parse and highlight JSON
let html = highlight_json_to_html("{\"name\": \"test\", \"count\": 42}")
// => <span class="hl-brace">{</span><span class="hl-property">"name"</span>...
```

### Reference Implementations

- [Lezer LR Runtime](https://github.com/lezer-parser/lr) (~2000 lines TS)
- [Lezer Common](https://github.com/lezer-parser/common) (~1000 lines TS)
- [Lezer Reference](https://lezer.codemirror.net/docs/ref/)

## Uninvestigated Items

- [x] Detailed vscode-textmate implementation (source code analysis)
- [ ] oniguruma-to-es conversion logic details
- [x] MoonBit regex lookahead/lookbehind support status (not documented)
- [x] tree-sitter MoonBit bindings (confirmed tonyfettes/tree_sitter exists)
- [x] tree-sitter highlighting mechanism (query-based)
- [ ] MoonBit regex source code analysis (lookahead/lookbehind implementation status)
- [ ] Actual usage examples of tonyfettes/tree_sitter
- [x] Lezer MoonBit porting feasibility (design completed)
