---
paths:
  - "src/formosh/form/visibility.gleam"
  - "src/formosh/internal/component_core.gleam"
  - "src/formosh/form/model.gleam"
---

# Hidden fields and the submit gate

`ui:widget: "hidden"` suppresses rendering at any depth; the field still
validates and submits. Combine with JSON Schema `default` for
`<input type="hidden">`-like behaviour.

The default submit gate (`model.can_submit`) stays **strict** — a required
hidden field without a satisfying value blocks submit. To surface the
otherwise-invisible cause, a `console.warn` (via `ffi/console`) lists the
suppressed-path errors whenever they are the *only* blockers. It is emitted
from `component_core` at form (re)initialisation — the submit button is
`disabled` in this state, so `FormSubmit` never fires through
`<formosh-form>` — via `component_core.hidden_blocks_warn` wrapping
`update.warn_only_hidden_blocks_effect`; `update.FormSubmit` emits the same
warn for headless `model.init` embeddings that have no disabled-button gate.
These are the only warn sites — entering the state mid-session (a value
change flipping a conditional branch, or a dynamic `UiSchemaChanged`) does
not emit it; tracked in #65. Visible errors keep the warn silent since the
UI already explains the block.

Callers that want a permissive gate (submit succeeds despite invisible
required errors — e.g. the backend supplies the value) can read
`model.is_valid_for_submit`. `model.hidden_errors` returns the suppressed
slice for custom diagnostics. The same suppression set covers `readOnly`
fields when `show_readonly_fields: false`.

Walker: `formosh/form/visibility.gleam`, called on demand from
`model.invisible_paths` so no `FormModel` field needs to track it. Details:
`docs/internals/visibility.md`.
