---
type: internal
title: "Update"
description: "Msg handling and state transitions: field edits, add/remove array rows, touch tracking, submit flow."
---

# Update (internals)

> **Stub.** Target length: ~400 words.

**Source**

- `src/formosh/form/update.gleam`
- `src/formosh/form/widget_msg.gleam`

**To document**

- The `Msg` variants (field change, array add/remove, submit, reset, …).
  - `WidgetEvent(ArrayField(ToggleOption(path, value)))` — checkbox-group
    toggle. Resolved against `model.values` and the resolved schema's
    options, not the dispatching render (#137): the schema-order options
    selected (`model.selected_options`, typed `compare_values`) XOR the
    clicked one, ignored past `maxItems` (`model.at_max_items`) or when the
    value is not an option, then forwarded to `UpdateFieldPath` /
    `ClearFieldPath` (empty selection removes the key). The renderer uses the
    same two helpers, so checked state and toggle can't disagree.
- The update pipeline for a field change:
  1. write value at path in the model
  2. recompute visibility (conditional fields)
  3. re-run validation for the touched path (and dependents)
  4. return new model + any effects
- Touch gating: errors hidden until a field is touched; array-level
  violations (`minItems`/`maxItems`/`uniqueItems`) are the exception
  (always visible — see [Error visibility](../guides/configuration.md#error-visibility)).
- Submit flow: gather values → run validator → invoke configured handler
  (HTTP / custom / none) → surface success/error state.

**Cross-links**

- Visibility recomputation → [Visibility](visibility.md)
- Validation internals → `src/validation/`
