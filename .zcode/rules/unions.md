---
paths:
  - "src/formosh/form/union_resolver.gleam"
  - "src/formosh/fields/union_field.gleam"
  - "src/formosh/form/update.gleam"
  - "src/formosh/form/model.gleam"
---

# anyOf runtime branch selection

2+ surviving `anyOf` members render as a branch chooser
(`union_field.gleam`: radio ≤5 branches, select >5; `ui:widget: "select"`
or `"radio"` overrides; parts `union` / `union-radio` / `union-select`).
The selection lives in `model.selected_branches`
(`List(#(FieldPath, Int))` — an assoc list, not a `Dict`: `FieldPath` is a
list, so `list.key_find` / `key_set` do the lookup).

- Switching to a genuinely different branch clears the subtree (an array row
  is reset in place rather than removed, so sibling indices never shift) and
  applies the new branch's own defaults, scoped to that field's subtree only
  — unrelated fields elsewhere in the form are never re-hydrated.
- Re-selecting the branch already active — stored, or currently active by
  inference — is a no-op: values/errors/touched stay untouched (a checked
  radio's `on_click` fires even without a change).
- Branch inference (no stored selection: type match for scalars,
  property-key overlap for objects, else 0) is resolution-time only for
  programmatic paths — init, `apply_answers`, component re-init all infer
  fresh and never persist — but a user-driven edit (`UpdateFieldPath` /
  `ClearFieldPath`) inside an inferred branch persists that inference on
  first edit (`model.persist_inferred_branches` runs against the CURRENT
  model, before the value changes), so clearing the field that drove it
  doesn't snap the chooser back to branch 0.
- Resolution order: union materialization runs BEFORE conditional resolution
  (`model.recompute_resolved_schema`); per array row
  `union_resolver.resolve_effective_property` composes both, union first.

## Docs

- Full runtime story: `docs/internals/visibility.md`,
  `docs/internals/update.md`
- Parse-time normalization: `.zcode/rules/schema-composition.md`
