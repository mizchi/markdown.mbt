# Folddown

Folddown is an experimental structured-document layer over Markdown. It keeps
a canonical document and will deterministically project reader-specific views
without turning an LLM into the rendering authority.

The current package is `mizchi/markdown/x/folddown`. It uses the generic MDX
schema checker in `mizchi/markdown/x/mdx`.

See [the MoonBit for TypeScript and Rust programmers draft](moonbit-for-programmers.mdx)
for a bilingual document using `locale`, `roles`, `level`, and external
documents together.

## Declaration Grammar

```mdx
<Fold
  id="auth.mfa.recovery-codes"
  kind="procedure"
  level="basic"
  locale="ja"
  requires={["auth.mfa"]}
  roles={["operator"]}
  familiarTo={["operator"]}>

## Recovery codes

Store recovery codes outside the primary authenticator.

</Fold>
```

`id`, `kind`, and `level` are required. `kind` is one of `concept`,
`procedure`, `reference`, and `evidence`. `level` is one of `intro`, `basic`,
`advanced`, and `expert`. A selected reader profile declares which of these
content levels start folded. `locale` is text; `requires`, `roles`, `goals`,
`evidence`, and `familiarTo` are arrays of text. `familiarTo` must name only
reader roles for which the section is a direct structural correspondence,
rather than a loose analogy. It lets an interest-focused view omit material
the selected reader already knows.

The expression subset is deliberately limited to strings, booleans, and arrays
of strings. Dynamic expressions such as `requires={loadRequirements()}` are
rejected. Unknown components and properties, duplicate properties, missing
required properties, invalid literals, and type mismatches produce diagnostics.

## Reader Profile Frontmatter

The entry document can declare the two reader states shown by the viewer. This
is a flat frontmatter DSL rather than generic nested YAML, so it remains within
the parser's deterministic key-value subset.

```yaml
---
folddown.readers: first_time,some_knowledge
folddown.reader.first_time.label.ja: 初めて知った
folddown.reader.first_time.label.en: First time
folddown.reader.first_time.collapse: none
folddown.reader.some_knowledge.label.ja: 多少知ってる
folddown.reader.some_knowledge.label.en: Know some
folddown.reader.some_knowledge.collapse: intro
---
```

`folddown.readers` must list exactly two unique IDs. Each profile requires
`label.ja`, `label.en`, and `collapse`. `collapse` is either `none` or a
comma-separated list drawn from `intro`, `basic`, `advanced`, and `expert`.
The viewer renders a two-choice segmented control from these labels; it does
not infer a numeric understanding level or render an understanding graph.

## Content Filter Frontmatter

The entry document can also declare the two reading-intent states. `all` keeps
every otherwise matching declaration. `unfamiliar` removes a declaration only
when its `familiarTo` list contains the selected reader role.

```yaml
---
folddown.content_filters: detail,interesting
folddown.content_filter.detail.label.ja: 詳しく知りたい
folddown.content_filter.detail.label.en: Learn in detail
folddown.content_filter.detail.mode: all
folddown.content_filter.interesting.label.ja: 面白い機能だけを知りたい
folddown.content_filter.interesting.label.en: Interesting features only
folddown.content_filter.interesting.mode: unfamiliar
---
```

`folddown.content_filters` must list exactly two unique IDs. Each filter
requires `label.ja`, `label.en`, and `mode`; `mode` is `all` or `unfamiliar`.
The viewer renders these labels directly. It never infers whether a feature is
interesting from prose or from an LLM classification.

## External Documents

Use a self-closing `Include` to splice another local Markdown or MDX document
into a Folddown source.

```mdx
<Include src="./fragments/recovery-codes.mdx" sync="auth-recovery" />
```

`src` must be a relative `.md` or `.mdx` path. Resolution is performed by a
caller-supplied loader, never by the parser itself. It rejects missing files,
cycles, absolute or URL paths, and a relative path that escapes the entry
document's root directory. `sync` is optional: includes sharing the same value
form a semantic-review group for the LLM drift workflow.

See [Folddown LLM Drift Review](folddown-drift.md) for packet generation, the
review prompt, response validation, and the scheduled handoff.

## Boundary

Folddown validates declaration shape and produces a canonical JSON manifest with
the typed properties and Markdown child source. The viewer consumes that
manifest directly, so the MDX document is the single source for reader-facing
content. Includes expand before rendering, while their graph remains available
for drift review. A later relationship layer will validate duplicate IDs and
references, then emit deterministic Markdown or HTML views. Formal claims
remain in their external formal authority such as Lean, TLA+, Dafny, or dspec;
a Folddown node will cite them as evidence.
