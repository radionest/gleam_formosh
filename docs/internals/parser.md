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
4. Compose `allOf`: deep-merge member schemas (properties, required, bounds,
   `$ref` mixins); lift member conditionals to the parent.
5. Normalize unsatisfiable constraints:
   - `minItems > maxItems` → `minItems` wins, fixed size.
   - conflicting `type` / crossed bounds → `UnsatisfiableSchema` error.
6. Emit parsed schema or `ParseError`.

**Cross-links**

- Conditional branches referencing `$defs` → [Visibility](visibility.md)
- Public entry points → [Public API](../reference/api.md)
