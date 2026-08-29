# Folddown LLM Drift Review

Folddown uses deterministic validation for document structure and an LLM only
for semantic comparison. The LLM is not a source of truth and must not edit a
document directly. It returns evidence-backed findings for human or CI policy
to act on.

## 1. Declare Comparable Documents

External documents are included with a local path. Give documents that must
stay semantically aligned the same `sync` value.

```mdx
<Include src="./moonbit-for-programmers/overview.ja.mdx" sync="moonbit-overview" />
<Include src="./moonbit-for-programmers/overview.en.mdx" sync="moonbit-overview" />
```

Every `sync` group must contain at least two documents. Documents without a
`sync` value are still structurally checked but are not submitted for semantic
comparison.

## 2. Build The Review Packet

```bash
pnpm folddown:packet -- --entry docs/moonbit-for-programmers.mdx --output /tmp/folddown-packet.json
```

The packet has a stable `folddown-drift/v1` schema. It contains the resolved
include graph, every source document, and its typed Fold properties, title, and
body. The command fails before packet generation for invalid MDX, missing
files, include cycles, absolute/URL paths, or references outside the document
root.

## 3. LLM Review Contract

Give the packet and the following instructions to the review agent. The agent
must return JSON only.

```text
You are reviewing Folddown document drift. For every comparisonGroups item,
compare only the supplied documents. Check semantic claims, prerequisites,
examples, API names, and evidence references. Do not rely on facts outside the
packet and do not propose edits.

Return exactly this JSON shape:
{
  "version": "folddown-drift/v1",
  "findings": [
    {
      "sync": "the comparisonGroups sync value",
      "verdict": "aligned | suspected-drift | insufficient-evidence",
      "summary": "concise explanation",
      "evidence": [
        { "path": "document path", "foldIds": ["Fold id"] }
      ]
    }
  ]
}

There must be exactly one finding per sync group. Every finding must cite at
least one existing Fold from every document in its group. Use
suspected-drift only for a concrete contradiction, omission, or incompatible
change. Use insufficient-evidence when the supplied documents cannot establish
the comparison.
```

## 4. Validate The Response

Save the model response without Markdown fences, then validate it before
opening an issue or failing a quality gate.

```bash
pnpm folddown:review:validate -- --packet /tmp/folddown-packet.json --response /tmp/folddown-review.json
```

The validator rejects a response with a missing group, unknown document or Fold
reference, duplicate verdict, malformed JSON shape, or unsupported verdict.
Policy can treat `suspected-drift` as a review-required signal while keeping
`insufficient-evidence` non-blocking.

## Scheduled Handoff

The `Folddown drift packet` workflow builds and stores the current packet once
per day. Attach a provider-specific agent runner to that artifact or run the
review contract above from a scheduled agent. Keeping the packet and response
as separate artifacts makes the model provider replaceable and preserves the
evidence used for every finding.
