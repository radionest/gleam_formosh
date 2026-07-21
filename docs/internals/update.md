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
- The update pipeline for a field change:
  1. write value at path in the model
  2. recompute visibility (conditional fields)
  3. re-run validation for the touched path (and dependents)
  4. return new model + any effects
- Touch gating: errors hidden until a field is touched; array-length
  violations are the exception (always visible — see README "Arrays").
- Submit flow: gather values → run validator → invoke configured handler
  (HTTP / custom / none) → surface success/error state.

**Cross-links**

- Visibility recomputation → [Visibility](visibility.md)
- Validation internals → `src/validation/`
