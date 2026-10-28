---
type: internal
title: "Update"
description: "Msg handling and state transitions: the field-edit pipeline, array invariants, union branch switching, and the submit flow."
---

# Update (internals)

`update(model, msg) -> #(FormModel, Effect(FormMsg))`
(`src/formosh/form/update.gleam`) is the only state transition function. All
messages are `FormMsg` variants (declared in
`src/formosh/form/model.gleam`):

- **Path operations** — `UpdateFieldPath`, `ClearFieldPath`,
  `AddArrayItemPath`, `RemoveArrayItemPath`, `MoveArrayItemPath`,
  `SelectUnionBranchPath`. Everything carries a `FieldPath`; there are no
  string-keyed messages.
- **Submission** — `FormSubmit`, `FormSubmitted(Result(String, String))`.
- **Validation / reset** — `ValidateForm`, `ResetForm`.
- **Widget events** — `WidgetEvent(WidgetMsg)` wrapping the
  `src/formosh/form/widget_msg.gleam` variants (`ImageUpload`,
  `SwipeReview`, `ArrayField`) so the core message type doesn't grow per
  widget. `model.image_msg` / `swipe_msg` / `array_msg` collapse the wrapper
  at emission sites.

## Field-edit pipeline

`UpdateFieldPath` (and its sibling `ClearFieldPath`) run a fixed sequence:

1. `persist_inferred_branches` against the **current** model — walk the
   edited path's prefixes; for each ancestor union with no stored selection,
   store the branch resolution is currently inferring. This must read the
   pre-edit values: a user edit inside an inferred branch pins that branch,
   so clearing the field afterwards doesn't snap the chooser back to
   branch 0.
2. Write (or remove) the value at the path in `model.values`.
3. `recompute_resolved_schema` — union branches are materialized first
   (`union_resolver.resolve_form_schema`), then conditionals are applied
   (`conditional_resolver.resolve_recursive`): a conditional declared inside
   the active branch must see the branch already materialized.
4. `defaults.ensure_min_items` tops arrays up to `minItems` (checkbox-group
   arrays — `types.is_multi_select` — are skipped). Every values-recompute
   path must call it; it deliberately does **not** run on
   `RemoveArrayItemPath` / `MoveArrayItemPath` or inside `ValidateForm` —
   validation reports under-min instead of fighting the user.
5. `mark_field_touched`.
6. `validate_all_fields` — clear all errors, re-run schema validation
   (top-level fields, then `validator.validate_nested` per subtree), then
   merge the cross-validator's errors. The custom validator is skipped while
   `touched_fields` is empty (its errors would sit invisible behind the
   touch gate yet still block submit), and its results are filtered: empty
   paths, paths that don't resolve in the resolved schema, and paths where
   the schema already produced an error are dropped.
7. Return `effect.none()` — plain edits produce no effects.

## Array edits

- `AddArrayItemPath` builds the new row from the **resolved** item schema
  (`defaults.new_array_item`, so manual rows carry the same defaults as
  auto-created ones), reads the new index from `model.values` *before*
  reconciliation (reconcile may append rows of its own and shift a post-hoc
  length reading), force-expands the new row in `array_rows_expanded` so it
  is never born collapsed, then runs reconcile + validate.
- `RemoveArrayItemPath` / `MoveArrayItemPath` reindex every path-keyed list
  (`touched_fields`, `selected_branches`, `array_collapse_off`,
  `array_rows_expanded`) with `path.reindex_after_array_removal` /
  `reindex_after_array_move` in the same fold that mutates `values`. A no-op
  move (same index, out of range, not an array path) touches nothing.
- Collapse-completed behaviour (the fold animation, the summary, why a
  conditionally-present summary breaks the diff) is documented in
  [Widgets](../reference/widgets.md#collapsing-completed-rows).

## Union branch switching

`SelectUnionBranchPath` is a three-way guard. Re-clicking the **stored**
branch is a complete no-op (a checked radio's `on_click` fires even without a
change). If there is no stored selection but the requested index is the one
resolution is already inferring, it is a *confirmation* — store it, clear
nothing. Only a genuine switch runs the destructive path: clear the subtree
(an array row resets in place so sibling indices never shift) and apply the
new branch's defaults, scoped to that field's subtree only.

## Submit flow

`FormSubmit` → `validate_all_fields` → `model.can_submit` (= `is_valid &&
!is_submitting`; strict — a required hidden field without a satisfying value
blocks). On success: `is_submitting: True` plus a submit effect —
`HttpSubmit` goes through the `rsvp` HTTP runtime, `CustomSubmit` calls the
handler, `NoSubmit` answers immediately — and every path dispatches
`FormSubmitted`, which flips `is_submitting` off and stores the
`SubmissionResult`. On failure, `warn_only_hidden_blocks_effect` emits the
diagnostic `console.warn` when the *only* blockers sit on UI-suppressed
paths (see [Visibility](visibility.md)).

Widget events never trust the render: `ToggleOption` resolves the new
checkbox-group selection against `model.values` and the resolved options
(`model.selected_options`, `model.at_max_items`), then forwards to
`UpdateFieldPath` / `ClearFieldPath` so it runs the full edit pipeline (an
event carries the user's intent, never a render-computed value — #137).

## Cross-links

- State shape → [Model](model.md)
- Suppressed paths and the submit gate → [Visibility](visibility.md)
- Error visibility semantics →
  [Configuration](../guides/configuration.md#error-visibility)
