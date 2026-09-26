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
     OR-merge; `addable`/`removable` AND-merge. The array merge is judged
     on each side's #63-clamped bounds (`resolver.clamp_array_constraints`):
     if they still cross (sibling `minItems` > definition `maxItems`, or vice
     versa) it is a `ParseError`
     (`resolver.array_constraints_crossed_reason`), same as a crossed
     `allOf`; otherwise the raw merge passes on to steps 4–5.
4. Compose `allOf`: deep-merge member schemas (properties, required, bounds,
   `$ref` mixins); lift member conditionals to the parent. A
   single-survivor `anyOf` collapses into its node through the same merge,
   but judges node-vs-survivor array bounds on clamped sides like step 3
   (`Optional[X]` parity with `type: [X, "null"]`), keeping the raw bounds.
5. Normalize unsatisfiable constraints:
   - conflicting `type` / crossed bounds reaching a step-4 merge (even
     bounds a side authored crossed on its own, bar the `anyOf` array case),
     or `minItems`/`maxItems` a `$ref` sibling merge crosses from clamped
     sides (step 3) → `UnsatisfiableSchema` error.
   - `minItems > maxItems` that never reached one → `minItems` wins, fixed
     size (`parser.clamp_crossed_array_bounds`, #63). Runs once on the
     flattened tree (properties, `items`, `anyOf` branches, `oneOf`
     members, `then`/`else`; an `if` stays raw, since conditions only match
     `enum`/`const`), never at decode — an earlier clamp would hide the
     crossing from the merges. E.g. `{"$ref": "#/$defs/Def" (no
     bounds), "minItems": 5, "maxItems": 3}` normalizes to a fixed 5; with
     an effective `allOf` (not empty / `true`-only; a `{}` member counts)
     of its own or inherited from `Def`, it fails instead. Unmerged
     string/number crossings stay raw. The subtree list is kept by hand,
     like the walks in `resolver.resolve_nested_refs` and
     `composer.do_flatten`: a new `SchemaProperty` subtree field must join
     all three (and `item_bounds` in `test/parser_test.gleam`), or crossed
     bounds inside it ship unclamped and can wedge the array (#63).
6. Emit parsed schema or `ParseError`.

**Cross-links**

- Conditional branches referencing `$defs` → [Visibility](visibility.md)
- Public entry points → [Public API](../reference/api.md)
