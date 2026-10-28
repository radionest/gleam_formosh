---
paths:
  - "src/formosh/form/defaults.gleam"
  - "src/formosh/fields/array_*.gleam"
  - "src/formosh/form/update.gleam"
---

# Array invariants (reconcile, reindex, collapse)

## Array reconcile (`defaults.ensure_min_items`)

Runs after every values recompute that precedes validation — init, reset,
`UpdateFieldPath`, `ClearFieldPath`, `AddArrayItemPath`, `apply_answers`,
component re-init — topping arrays up to `minItems` (checkbox-group arrays —
`types.is_multi_select` — are skipped). Deliberately NOT run on
`RemoveArrayItemPath` / `MoveArrayItemPath` or in `ValidateForm` (don't fight
the user; validation reports under-min instead). New values-recompute paths
must call it too.

Validation likewise runs on every update path —
`array_collapse.incomplete_rows` leans on that invariant and skips its
per-render validation pass once `model.errors` is populated or anything is
touched (#110).

## Reindex rule

Reindex array fields after any add/remove operation. Every path-keyed model
list reindexes in the same fold that mutates `values`: `touched_fields`,
`selected_branches`, `array_collapse_off`, `array_rows_expanded` — via
`path.reindex_after_array_removal` / `reindex_after_array_move`. A future
array-mutating path must preserve all four; `clear_subtree` (the
union-branch-switch reset) prunes them on the same prefix as
`touched_fields`. `AddArrayItemPath` also force-expands the new row into
`array_rows_expanded` so it is never born collapsed.

## Collapse state

`array_collapse_off` / `array_rows_expanded` are view-only, path-keyed,
never touch `values` or validation. `array_collapse_off` is a negative list
(the user switched collapsing off), so "enabled by default" needs no entry;
`array_rows_expanded` stores only user-driven expansions — a row that
stopped validating expands from the predicate and re-collapses on its own.

Collapsing folds rather than unmounts: for a collapse-enabled array every
row's fields are wrapped in `array-item-body` (`render_item_body`) and
rendered in both states; the `grid-template-rows: 1fr↔0fr` fold and its
transition come from the library stylesheet (`internal/stylesheet.gleam`),
keyed on the row's `data-collapsed` — a wrapper appearing only once the row
is shut would have nothing to animate from. Collapsed bodies are `inert`;
arrays without `collapseCompleted` get no wrapper at all.

A row's children are unkeyed, so the summary must occupy its slot in every
state (`element.none()` when the row is incomplete): a conditionally-present
summary shifts the header and body down one index, and the positional diff
then rebuilds the body — a fresh element at `0fr` has nothing to transition
from, so the automatic fold snaps and the focused input is torn down
mid-edit. Markup is unaffected either way, so only the
`completing a row folds the body node it already had` e2e test catches a
regression here.

## Docs

- Collapse authoring (`collapseCompleted`, `summaryFields`):
  `docs/reference/ui-schema.md`,
  `docs/reference/widgets.md#collapsing-completed-rows`
- Reindex helpers: `src/formosh/form/path.gleam`
