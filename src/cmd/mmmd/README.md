# mmmd

`mmmd` is a WebAssembly command for rendering Markdown in portable agent and
shell workflows. It reads Markdown from standard input and writes exactly one
rendered artifact to standard output.

## Local usage

```sh
moon runwasm src/cmd/mmmd --format tui < document.md
moon runwasm src/cmd/mmmd --format html < document.md
```

`--format tui` produces a terminal-friendly rendering. Mermaid fenced code
blocks are rendered as ASCII-art diagrams. `--format html` produces an HTML
fragment.

Invalid options are reported to standard error and exit with a non-zero status;
standard output remains empty.

## Mooncakes skill distribution

After the next package release, the command can be run from the Mooncakes
registry (and therefore used by skills.mooncakes.io) with its released package
coordinate:

```sh
moon runwasm mizchi/markdown/cmd/mmmd@<released-version> --format tui < document.md
```

The placeholder intentionally avoids claiming that an unpublished version is
already available from the registry.
