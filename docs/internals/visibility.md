---
type: internal
title: "Visibility"
description: "How if/then/else conditionals are resolved on every field change to show/hide branches."
---

# Visibility (internals)

> **Stub.** Target length: ~350 words.

**Source**

- `src/formosh/form/visibility.gleam`
- `src/formosh/schema/conditional_resolver.gleam`

**To document**

- Conditionals are **fully dynamic** — re-evaluated on every field change
  (unlike `allOf`, which is folded in at parse time).
- Resolution algorithm:
  1. For each conditional, evaluate the `if` clause against current values.
  2. If matched, the `then` branch's properties become visible; else `else`.
  3. Multiple conditionals compose via `allOf` — each `if/then` is
     evaluated independently.
- `$ref` inside `if`/`then`/`else` is resolved, so branches can pull
  definitions from `$defs`.
- Composing with array constraints: an array declared inside `then` with
  `minItems` appears pre-populated with its first default-hydrated row
  once the condition is met (see `demo/schemas/carcinomatosis_radiology.json`).

**Cross-links**

- Where conditionals are re-evaluated → [Update](update.md)
- Parse-time vs runtime split → [Parser](parser.md)
