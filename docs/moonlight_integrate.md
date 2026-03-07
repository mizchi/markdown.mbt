# Guide for Integrating Moonlight into the Markdown Editor

A guide for integrating the Moonlight SVG editor into the Luna-based Markdown Editor.

## Overview

Moonlight provides two integration methods:

1. **JavaScript API (recommended)**: Dynamically create editors with `MoonlightEditor.create()`
2. **WebComponent**: Use as a `<moonlight-editor>` custom element

For Markdown Editor integration, the **JavaScript API** is recommended. Reasons:
- Direct integration with Luna's Signal system
- Easy bidirectional sync via event callbacks
- Flexible SVG import/export

---

## 1. Dependency Setup

### 1.1 Add as a MoonBit Package

```bash
moon add mizchi/moonlight
```

### 1.2 Load in the JavaScript Entry Point

```typescript
// editor.ts
import 'mbt:mizchi/moonlight/embed';
```

This registers `window.MoonlightEditor` globally.

---

## 2. Basic Integration

### 2.1 Creating an Editor

```typescript
const container = document.getElementById('svg-editor');

const editor = MoonlightEditor.create(container, {
  width: 600,          // Canvas width (px)
  height: 400,         // Canvas height (px)
  docWidth: 600,       // SVG viewBox width
  docHeight: 400,      // SVG viewBox height
  zoom: 1.0,           // Initial zoom
  theme: 'light',      // 'light' | 'dark'
  readonly: false,     // Read-only mode
  initialSvg: null,    // Initial SVG string (optional)
});
```

### 2.2 SVG Import/Export

```typescript
// Load SVG extracted from Markdown
editor.importSvg(svgString);

// Get the editing result as SVG
const svg = editor.exportSvg();

// Clear the editor
editor.clear();
```

---

## 3. Integration Patterns with Luna

### 3.1 Managing SVG State with Signals

```moonbit
// Manage SVG within a Markdown document using Signals
let svg_content : @luna.Signal[String] = @luna.signal("")

// Receive changes from the editor
fn setup_editor_sync(editor : @js.Any) -> Unit {
  // Subscribe to change events
  let _ = editor.onChange(fn() {
    let new_svg = editor.exportSvg()
    svg_content.set(new_svg)
  })

  // Update the editor when Signal changes (bidirectional binding)
  let _ = @luna.effect(fn() {
    let svg = svg_content.get()
    if svg.length() > 0 {
      editor.importSvg(svg)
    }
  })
}
```

### 3.2 Embedding as a Markdown Block

```moonbit
fn svg_block(svg_signal : @luna.Signal[String]) -> @luna.Node[@luna.DomEvent] {
  let container_ref : Ref[@js.Any?] = { val: None }
  let editor_ref : Ref[@js.Any?] = { val: None }

  // Create container div
  let container = @element.div(
    id="svg-editor-container",
    [],
  )

  // Initialize the editor after mounting
  let _ = @luna.effect(fn() {
    match container_ref.val {
      Some(el) => {
        let editor = create_moonlight_editor(el, svg_signal.get())
        editor_ref.val = Some(editor)

        // Reflect changes to Signal
        editor.onChange(fn() {
          svg_signal.set(editor.exportSvg())
        })
      }
      None => ()
    }
  })

  container
}
```

---

## 4. Event API

### 4.1 Available Events

```typescript
// When an element is changed
editor.onChange(callback: () => void): () => void

// When an element is selected
editor.onSelect(callback: (ids: string[]) => void): () => void

// When selection is cleared
editor.onDeselect(callback: () => void): () => void

// When the editor gains focus
editor.onFocus(callback: () => void): () => void

// When the editor loses focus
editor.onBlur(callback: () => void): () => void

// When the tool mode changes ('select' | 'freedraw')
editor.onModeChange(callback: (mode: string) => void): () => void

// When an element is added
editor.onElementAdd(callback: (id: string) => void): () => void

// When an element is deleted
editor.onElementDelete(callback: (id: string) => void): () => void
```

### 4.2 Unsubscribing

Each event method returns an unsubscribe function:

```typescript
const unsubscribe = editor.onChange(() => {
  console.log('changed');
});

// Unsubscribe later
unsubscribe();
```

---

## 5. Operation API

### 5.1 Selection Operations

```typescript
// Select specific elements
editor.select(['el-1', 'el-2']);

// Select all elements
editor.selectAll();

// Deselect
editor.deselect();

// Get selected element IDs
const ids = editor.getSelectedIds();
```

### 5.2 Element Operations

```typescript
// Get all elements
const elements = editor.getElements();

// Get an element by ID
const element = editor.getElementById('el-1');

// Delete elements
editor.deleteElements(['el-1', 'el-2']);
```

### 5.3 Mode Switching

```typescript
// Switch to freedraw mode
editor.setMode('freedraw');

// Switch to select mode
editor.setMode('select');

// Get current mode
const mode = editor.getMode(); // 'select' | 'freedraw'
```

### 5.4 Read-Only

```typescript
// Set to read-only
editor.setReadonly(true);

// Make editable again
editor.setReadonly(false);

// Get current state
const isReadonly = editor.isReadonly();
```

### 5.5 Focus

```typescript
// Check focus state
const hasFocus = editor.hasFocus();

// Programmatically focus
editor.focus();

// Remove focus
editor.blur();
```

---

## 6. Markdown Editor Integration Example

### 6.1 Code Block Extension

````markdown
```moonlight-svg
<svg viewBox="0 0 400 300">
  <rect x="50" y="50" width="100" height="80" fill="#4a90d9" />
</svg>
```
````

### 6.2 Parser Extension (MoonBit)

```moonbit
/// Detect SVG code blocks and replace with editors
fn parse_svg_blocks(markdown : String) -> Array[Block] {
  let blocks : Array[Block] = []
  // Detect moonlight-svg code blocks
  let pattern = "```moonlight-svg\n"
  // ... parsing logic
  blocks
}

/// Render a block
fn render_block(block : Block) -> @luna.Node[@luna.DomEvent] {
  match block {
    SvgBlock(svg_content) => {
      // Display as Moonlight editor
      svg_editor_component(svg_content)
    }
    TextBlock(text) => {
      // Normal text
      @element.p([], [text(text)])
    }
  }
}
```

### 6.3 Edit Mode Toggle

```moonbit
/// Preview/edit mode toggle
fn svg_block_with_toggle(
  svg : @luna.Signal[String],
  is_editing : @luna.Signal[Bool],
) -> @luna.Node[@luna.DomEvent] {
  @luna.show(
    is_editing.get(),
    // Edit mode: Moonlight editor
    then_=fn() { moonlight_editor(svg) },
    // Preview mode: Static SVG display
    else_=fn() { svg_preview(svg) },
  )
}
```

---

## 7. Styling

### 7.1 Container Size

The editor does not depend on the container size. Specify via `width`/`height` options:

```css
#svg-editor-container {
  /* Container styles */
  border: 1px solid #ccc;
  border-radius: 8px;
  overflow: hidden;
}
```

### 7.2 Theme

```typescript
// Dark theme
const editor = MoonlightEditor.create(container, {
  theme: 'dark',
  // ...
});
```

---

## 8. Important Notes

### 8.1 Cleanup

Call `destroy()` when the component is unmounted:

```typescript
editor.destroy();
```

### 8.2 Focus Conflicts

When keyboard focus conflicts between the Markdown Editor and Moonlight Editor:

```typescript
// Disable Markdown Editor shortcuts while Moonlight has focus
editor.onFocus(() => {
  markdownEditor.disableShortcuts();
});

editor.onBlur(() => {
  markdownEditor.enableShortcuts();
});
```

### 8.3 SVG Format

SVG output from Moonlight includes `data-moonlight-*` attributes. This enables re-editing:

```xml
<svg viewBox="0 0 400 300" data-moonlight-version="1">
  <rect data-id="el-1" data-moonlight="true" ... />
</svg>
```

Plain SVG (without `data-moonlight` attributes) can also be loaded, but only moving is supported -- resizing is not available.

---

## 9. Implementation Checklist

- [ ] Add `mizchi/moonlight` package
- [ ] Import embed module
- [ ] Implement Signal management for SVG blocks
- [ ] Initialize editor with `MoonlightEditor.create()`
- [ ] Sync with Markdown document via `onChange`
- [ ] Focus management (shortcut conflict mitigation)
- [ ] Implement cleanup (`destroy()`)
- [ ] Preview/edit mode toggle UI

---

## 10. Reference Files

- `examples/embed.html` - Basic integration example
- `examples/preview.html` - Preview mode example
- `embed.ts` - JavaScript entry point
- `src/embed/entry.mbt` - MoonBit entry point
- `src/main.mbt` - API implementation details
