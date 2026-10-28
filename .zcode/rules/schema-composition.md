---
paths:
  - "src/formosh/schema/composer.gleam"
  - "src/formosh/schema/resolver.gleam"
  - "src/formosh/schema/parser.gleam"
---

# Schema composition (allOf / anyOf) — parse time

## allOf (`schema/composer.gleam`)

Merged at parse time: members fold in array order, parent-local keywords win
last, same-key properties deep-merge field-by-field, bounds combine
stricter-wins, scalars (enum/oneOf/pattern/format) take the later value
wholesale, member conditionals lift to the parent. The document root parses
as a `SchemaProperty` and converts to `JsonSchema` post-merge, so a member
can type a typeless root (the `object` default applies only when composition
supplies no type) and a root-level `$ref` resolves.

Strictness: `false` or malformed members, disjoint `type` declarations
(`number`∧`integer` narrows to `integer`), and min/max pairs that cross in a
composed node's merged constraints (even string/number bounds authored on
the node itself beside a non-empty `allOf`; `minItems`/`maxItems` are
normalized per schema object first —
`docs/reference/schema-keywords.md#array-structure`) are `ParseError`s
(`DecodingError` for `false`/malformed members; `UnsatisfiableSchema` with a
`#/path` breadcrumb for type/bounds conflicts) — a composition that
validates nothing is rejected instead of rendered. `true` members and an
empty `allOf` are no-ops.

Post-parse `all_of` is always `None` outside `$defs` (defs entries stay raw
source material; an `allOf` inside `$defs` survives the serializer
round-trip, as do nested `if/then/else` — #152).

## anyOf normalization (`composer.normalize_any_of`)

Parsed, `$ref`-resolved inside members, normalized at parse time:

- null members drop into `nullable` (an empty nullable field validates as
  satisfied, submits `null`, and never shows the required asterisk — even
  when the field is named in `required`; Pydantic `Optional[X]`-style)
- a single surviving non-null member merges into the node itself
  (`Optional[X]` renders as a plain `X` field)
- 2+ surviving members stay in `any_of` and render as a runtime branch
  chooser — see `.zcode/rules/unions.md`

Member extraction is lenient (malformed members are dropped); a parent
`type` disjoint from every surviving member's type, or bounds crossed by a
single survivor's merge, is a `ParseError` (`UnsatisfiableSchema`) — same
strictness as `allOf`.

`oneOf` remains const+title enum rendering only — not processed as a
schema-variant selector.

## Retired `x-*` keys

`x-widget` / `x-accept` / `x-max-file-size` / `x-addable` / `x-removable`
were removed in v0.11 — UiSchema is the only hint source.
`parser.parse_schema` is pure; `parser.parse_schema_with_warning` returns
the leftover-key diagnostic (retired `x-*` and misplaced `ui:*` keys on
schema nodes) from the same parse, and `formosh.from_json_string*` /
`component_core.parse_schema_attr` emit it as one `console.warn`.
Migration: `docs/reference/api.md`.

## Docs

- Full pipeline: `docs/internals/parser.md`
- Keyword matrix: `docs/reference/schema-keywords.md`
