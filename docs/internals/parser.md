---
type: internal
title: "Parser"
description: "Schema parse pipeline: tokenizer-free decode, $ref resolution with cycle detection, allOf deep-merge, normalization."
---

# Parser (internals)

> **Stub.** Target length: ~450 words.

**Source**

- `src/formosh/schema/parser.gleam`
- `src/formosh/schema/resolver.gleam` — `$ref`
- `src/formosh/schema/composer.gleam` — `allOf`
- `src/formosh/schema/properties.gleam`
- `src/formosh/schema/types.gleam` — `JsonSchema` type

**Pipeline (to expand)**

1. Decode raw JSON → intermediate dynamic.
2. Build `JsonSchema` node tree (typed).
3. Resolve `$ref` against `$defs` / `definitions` (JSON Pointer).
   - Cycle detection → reject circular refs.
   - Keywords beside the `$ref` win over the definition's, with several
     per-field exceptions (`resolver.merge_properties`): `array_constraints`
     merges per keyword, stricter-wins instead
     (`resolver.merge_array_constraints`, shared with the `allOf` merge
     below); `all_of`/`conditionals` concatenate; `read_only`/`nullable`
     OR-merge; `addable`/`removable` AND-merge. A crossed `array_constraints`
     result (sibling `minItems` > definition `maxItems`, or vice versa) is a
     `ParseError` (`resolver.array_constraints_crossed_reason`), same as a
     crossed `allOf`.
4. Compose `allOf`: deep-merge member schemas (properties, required, bounds,
   `$ref` mixins); lift member conditionals to the parent.
5. Normalize unsatisfiable constraints:
   - `minItems > maxItems` authored directly on a standalone node — its own
     bounds, evaluated at decode, before any `$ref` merge — → `minItems`
     wins, fixed size. E.g. `{"$ref": "#/$defs/Def" (no bounds),
     "minItems": 5, "maxItems": 3}` normalizes to a fixed 5 regardless of
     the `$ref`. A composed node — one carrying an effective `allOf` (not
     empty / `true`-only; a `{}` member counts), or an inline `allOf`
     member itself — skips this:
     its crossed bounds stay raw and fail the merge below.
   - conflicting `type` / crossed bounds arising from a merge (`allOf`
     composition or a `$ref` sibling merge) → `UnsatisfiableSchema` error.
6. Emit parsed schema or `ParseError`.

**Cross-links**

- Conditional branches referencing `$defs` → [Visibility](visibility.md)
- Public entry points → [Public API](../reference/api.md)
