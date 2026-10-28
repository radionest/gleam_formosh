---
type: internal
title: "Parser"
description: "Schema parse pipeline: decode, $ref resolution with cycle detection, allOf deep-merge, anyOf normalization, unsatisfiable-constraint rejection."
---

# Parser (internals)

The parse pipeline (`src/formosh/schema/parser.gleam`) turns a JSON string
into the typed `JsonSchema` tree the MVU loop renders without re-parsing. It
runs once per form creation (and per `schema` attribute change on
`<formosh-form>`).

## Entry points

- `parse_schema(json_string)` — pure; returns
  `Result(JsonSchema, ParseError)`.
- `parse_schema_with_warning(json_string)` — the same parse from one JSON
  decode, plus the leftover-key diagnostic (`presentation_key_warning`):
  JSON-pointer paths of schema nodes still carrying retired `x-*` keys
  (`retired_extension_paths`: `x-widget`, `x-accept`, `x-max-file-size`,
  `x-addable`, `x-removable` — UiSchema replaced them in v0.11) or misplaced
  `ui:*` keys. The diagnostic is only *computed* here; the entry points
  (`formosh.from_json_string*`, the component's schema-attribute handling)
  emit it as a single `console.warn`.

## Pipeline

1. **Decode** the raw JSON into `Dynamic` (`json.parse`; errors map to
   `ParseError.InvalidJson` / `DecodingError`).
2. **Decode into the typed node tree** — `root_decoder` yields the root
   `SchemaProperty` plus the `$defs` / `definitions` table. The document root
   parses as a `SchemaProperty` and converts to `JsonSchema` only after
   composition, so a composition member can type a typeless root and a
   root-level `$ref` resolves.
3. **Resolve `$ref`** against the defs (`resolver.resolve_property`, JSON
   Pointer). Cycles are rejected via a visited set — do not bypass it.
   Keywords beside the `$ref` win over the definition's, with per-field
   exceptions in `resolver.merge_properties`: `array_constraints` merges
   per-keyword, stricter-wins (`resolver.merge_array_constraints`, shared
   with the `allOf` merge); `all_of` / `conditionals` concatenate;
   `read_only` / `nullable` OR-merge. A crossed `array_constraints` result
   is a `ParseError` (`resolver.array_constraints_crossed_reason`).
4. **Compose `allOf`** (`composer.flatten_property`): members fold in array
   order, parent-local keywords win last, same-key properties deep-merge
   field-by-field, bounds combine stricter-wins, scalars take the later
   value wholesale, member conditionals lift to the parent. `false` or
   malformed members are `DecodingError`s; disjoint `type` declarations and
   bound pairs that cross in the merged node are `UnsatisfiableSchema` (with
   a `#/path` breadcrumb) — a composition that validates nothing is
   rejected, not rendered. `true` members and an empty `allOf` are no-ops.
   The same fold normalizes `anyOf` (`composer.normalize_any_of`): null
   members collapse into `nullable`, a single surviving non-null member
   merges into the node itself, and 2+ survivors stay a runtime union. When
   a single survivor merges into the node, a parent `type` disjoint from it
   is a `ParseError` (the same `merge_pair` type intersection that `allOf`
   uses); with 2+ survivors the parent's own `type` is not re-checked
   against the members.
5. **Normalize locally-contradictory arrays**: `minItems > maxItems`
   authored directly on one node — its own bounds, evaluated before any
   `$ref` / `allOf` merge — normalizes to a fixed size (`minItems` wins),
   whether or not the node carries a `$ref`. Crossed bounds *arising from a
   merge* (composition, single-survivor collapse, `$ref` sibling merge)
   stay `UnsatisfiableSchema`. Canonical rule:
   [Array structure](../reference/schema-keywords.md#array-structure).
6. Return the `JsonSchema`, or the `ParseError`.

## Post-parse invariants

Outside `$defs`, `all_of` is always `None` — composition is a parse-time
concern. `$defs` entries keep their raw source material (an `allOf` there
survives the serializer round-trip, as do nested `if/then/else`), because
defs are unexpanded reference targets, not renderable nodes.

## Cross-links

- Runtime half of conditionals → [Visibility](visibility.md)
- Keyword support matrix →
  [Schema keywords](../reference/schema-keywords.md)
- Public entry points → [Public API](../reference/api.md)
