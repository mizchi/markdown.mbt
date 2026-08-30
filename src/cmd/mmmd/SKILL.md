---
name: mmmd
description: Render Markdown as terminal-friendly text or an HTML fragment. Mermaid fenced blocks become ASCII-art diagrams in TUI output.
---

# mmmd

Read Markdown from standard input and render one artifact to standard output.

```sh
moon runwasm mizchi/markdown/cmd/mmmd@0.8.3 --format tui < document.md
moon runwasm mizchi/markdown/cmd/mmmd@0.8.3 --format html < document.md
```

- Use `--format tui` for terminal output; Mermaid fenced blocks render as
  ASCII-art diagrams.
- Use `--format html` for an HTML fragment.
- Invalid arguments are written to standard error and exit with a non-zero
  status. Successful output contains no banners or diagnostics.
