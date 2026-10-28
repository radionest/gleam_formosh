---
type: internal
title: "Visibility"
description: "Runtime schema resolution: if/then/else conditionals, anyOf branch selection, and the hidden-path walker behind the submit gate."
---

# Visibility (internals)

"Visibility" spans three runtime resolvers that all answer one question:
which schema is *effective* right now — for rendering, validation, and the
submit gate.

| Concern | Module | When it runs |
|---|---|---|
| `if/then/else` conditionals | `src/formosh/schema/conditional_resolver.gleam` | Every values change |
| `anyOf` branch selection | `src/formosh/form/union_resolver.gleam` | Every values change (top level); per array row at render/validate time |
| Suppressed (hidden) paths | `src/formosh/form/visibility.gleam` | On demand, for the submit gate |

## Conditionals are fully dynamic

Unlike `allOf`, which is folded in at parse time, conditionals are
re-evaluated on every field change.
`conditional_resolver.resolve_recursive(schema, values)` produces the cached
`FormModel.resolved_schema`:

1. Root-level rules fire first (`resolve_conditional_schema`): for each
   recorded `ConditionalRule`, `evaluate_condition` matches the `if` object's
   declared properties against the current values — a single `enum` value
   acts as `const`, multiple values match-any, compared by `compare_values`
   (typed; `IntegerValue` / `NumberValue` compare cross-type). A missing
   field makes the rule False.
2. The winning branch's `properties` merge into the node
   (`properties.merge`, order-preserving) and its `required` appends,
   deduplicated.
3. Apply-then-descend: each child is resolved with its own slice of values,
   so nested conditionals evaluate against up-to-date sibling state.

Known limitations (from the module contract): defaults of fields newly
revealed by a conditional are not back-filled into `model.values` — defaults
apply at init only; conditions may only inspect fields at their own level;
conditionals on objects *inside* array items do not recurse — item-level
rules fire once, shallow.

Array `items` are recursed with `None`: per-row resolution happens at
render/validate time, where the row path is actually available. Consequence:
an array declared inside a `then` branch with `minItems` appears
pre-populated with its first default-hydrated row once the condition is met
(`demo/schemas/carcinomatosis_radiology.json`), while a checkbox group
appears empty.

## Union branches resolve before conditionals

`union_resolver` decides which `anyOf` member is active and *materializes*
it into the node, so every walker — render, validate, visibility, defaults —
sees a single effective schema and needs no union awareness.
`model.recompute_resolved_schema` composes the two resolvers, union first: a
conditional declared inside the active branch must see the branch already
materialized.

- A stored `selected_branches` entry always wins; otherwise the branch is
  inferred from the value — scalar type match, then object key overlap, else
  0. Inference is resolution-time only; nothing here writes back to the
  model. A user-driven edit persists the inference (see
  [Update](update.md)).
- `materialize_branch` takes the member's type / constraints / properties /
  items but keeps the parent's `title` / `description` / `nullable` (Pydantic
  puts them on the parent, not the member) and resets `any_of` to the full
  member list so the dispatcher can still render the chooser.

## The submit-gate walker

`visibility.invisible_paths(schema, ui_schema, values, show_readonly_fields)`
returns the set of canonical path keys whose fields are suppressed from the
UI: `ui:widget: "hidden"`, or `readOnly` (schema or UiSchema) when
`show_readonly_fields` is off. It mirrors the renderer's inheritance exactly:
effective readonly OR-merges parent→child like `field_common.make_child_ctx`,
and widget selection goes through `ui_resolver.resolve_hints` /
`is_suppressed`, so the walker's and the renderer's notions of "hidden"
cannot drift.

For a suppressed node, every error-producible descendant path is pushed too:
object children are enumerated from the *schema* (the validator reports
missing required fields that have no value), array indices from the current
`values` length (rows that don't exist cannot have errors). Result keys use
`path.to_string`, matching the encoding of `model.errors`.

The walker runs after conditional resolution so branch switches are
reflected. Known gaps (documented in the module header): item-level
conditionals inside array `items` are not recursed per row, and a union
inside array `items` stays a raw node in the pre-walk — hidden fields inside
a row's active branch are not collected.

### Gate wiring

`model.can_submit` is strict — suppressed required fields block submit.
`model.is_valid_for_submit` is the permissive alternative (suppressed errors
ignored), and `model.hidden_errors` returns the suppressed slice for custom
diagnostics. The `console.warn` for a hidden-only block fires from two sites
only — component (re)initialisation and the `FormSubmit` handler — via
`update.warn_only_hidden_blocks_effect`; entering the state mid-session does
not warn (#65). See [Update](update.md).

## Cross-links

- Where the resolvers are invoked → [Update](update.md)
- Parse-time vs runtime split → [Parser](parser.md)
- Hidden-widget authoring → [Widgets](../reference/widgets.md)
