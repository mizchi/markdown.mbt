# Serializer compatibility audit

The serializer has two separate compatibility signals:

1. Exact Markdown output compared with remark.
2. Semantic round-trip stability, measured by comparing HTML before and after
   `parse -> serialize -> parse` with the default renderer behavior.

These must not be conflated. The project intentionally emits normalized
Markdown, so exact remark formatting is not the correctness oracle.

## Current results

- CommonMark HTML parsing: 652/652.
- Exact remark serialization: 464 active, 78 skipped.
- Semantic round-trip: 611/652.
- Of the 78 exact-output skips, 31 overlap the semantic failures and 47 are
  formatting-policy differences only.
- Another 10 semantic failures are outside the exact-output skip set, giving
  41 semantic cases in total.

## Semantic failures to fix

| Area | Count | Examples | Required direction |
|---|---:|---|---|
| Lists | 9 | 301, 302, 306, 311–315, 317 | Preserve list boundaries, tight/loose state, and literal nested markers |
| Setext headings | 6 | 81, 82, 87, 93, 95, 106 | Preserve multiline heading content and escape paragraph underline hazards |
| Block quotes | 5 | 238–240, 244, 252 | Preserve empty blocks, paragraph boundaries, and container separation |
| Links | 4 | 512, 528, 550, 564 | Make labels and shortcut/reference forms unambiguous |
| ATX headings | 3 | 65, 70, 76 | Escape block-start and closing `#` text where required |
| Entities | 3 | 26, 39, 40 | Re-encode decoded block-significant characters/newlines/tabs |
| Reference definitions | 3 | 194, 200, 218 | Preserve escaped labels, empty destinations, and container placement semantics |
| Backslash escapes | 2 | 14, 15 | Preserve block-start escapes and trailing literal backslashes |
| List items | 2 | 259, 260 | Preserve loose item paragraph boundaries inside nested block quotes |
| Emphasis | 2 | 461, 463 | Do not collapse nested emphasis into strong emphasis |
| Fenced code | 1 | 146 | Encode backticks in info strings when normalizing to backtick fences |
| Code spans | 1 | 331 | Preserve significant code-span padding |

The implementation order should follow structural risk:

1. Lists, list items, and block quotes.
2. Block-start escaping and multiline headings.
3. Reference definitions and link labels.
4. Entity-derived control characters.
5. Code fence/span and nested-emphasis edge cases.

## Intentional exact-output differences

The remaining 47 exact-output skips render identically after normalization.
They primarily come from:

- ATX output replacing Setext source style.
- Stable `-` and `.` list markers.
- Canonical reference definitions moved to a trailing section.
- Canonical block spacing and escaping choices.

They should only be changed when remark source compatibility is explicitly
more important than the normalized, idempotent contract.

## GFM exception

GFM example 204 remains intentionally different. Its final row contains more
cells than the delimiter/header defines. Official GFM ignores the overflow
cell in rendered HTML, while remark's serializer expands the table and makes
that cell visible after reparse. Matching remark would therefore violate the
semantic round-trip contract.
