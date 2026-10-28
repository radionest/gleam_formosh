---
type: internal
title: "Model"
description: "FormModel internals: the state record, path-based field addressing, the value tree, and the auxiliary path-keyed state."
---

# Model (internals)

All form state lives in one immutable `FormModel` record
(`src/formosh/form/model.gleam`). Nothing mutates: every transition returns a
new record built with record-update syntax, and the view is a pure function
of it.

## The FormModel record

| Field | Holds |
|---|---|
| `schema` | The parsed JSON Schema — parse-time `allOf` already merged, conditionals still raw rules. |
| `resolved_schema` | The *effective* schema for the current values: union branches materialized, `if/then/else` applied. Recomputed on every values change by `recompute_resolved_schema` — union resolution first, then conditionals. |
| `values` | The single hierarchical `Value` tree, always `ObjectValue` at the root. |
| `errors` | `Dict(String, List(ValidationError))` keyed by the canonical path string (`"lesions.[0].side"`). Mutate only via `add_error_at_path` / `clear_errors_at_path`; `is_valid` tracks the dict — True only while the dict is empty. |
| `touched_fields` | `List(FieldPath)` — fields the user has interacted with; marked on the first value write, not on blur. Gates error visibility (see [Update](update.md)). |
| `selected_branches` | `List(#(FieldPath, Int))` — active `anyOf` branch per field path. An association list, not a `Dict` (`FieldPath` is a list; `list.key_find` / `key_set` do the lookup). |
| `disabled_fields` | Read by `is_field_disabled`; nothing in `src/` populates it — `ui:disabled` is honoured at render time from the UiSchema hints. |
| `is_submitting`, `is_dirty`, `is_valid`, `submission_result`, `submit_config` | Submission lifecycle. |
| `show_readonly_fields`, `read_only` | Two different switches: visibility of schema-`readOnly` fields in edit mode vs. the whole-form review mode. |
| `ui_schema` | The parallel presentation tree — the only hint source since v0.11. |
| `upload_base_url`, `upload_states` | Image-upload plumbing. |
| `validator` | The optional cross-field validator (`with_validator`). |
| `swipe_drag`, `swipe_hide_answered`, `swipe_exiting` | Transient swipe-review state; view-only, never touches `values` or validation. |
| `array_collapse_off`, `array_rows_expanded` | Array-collapse view state, path-keyed like `touched_fields`. |

## Path addressing

Every field is addressed by a `FieldPath` (`src/formosh/form/path.gleam`): a
list of `PropertySegment(name)` / `ArraySegment(index)` segments, e.g.
`[PropertySegment("lesions"), ArraySegment(0), PropertySegment("side")]`.
Values are read and written through `path.get_at_path` / `path.set_at_path`
(plus the add/remove/reindex helpers) directly against the `Value` tree —
there is no `Dict`↔`Value` conversion anywhere in the update handlers.

Where a path must become a string (error keys, suppressed-path sets), it goes
through `path.to_string`, which delegates the segment format to
`src/formosh/path_format.gleam` — the bracketed index segment and the `.`
join, giving `"lesions.[0].side"`. Never hand-concatenate the dot notation;
the canonical format has exactly one owner.

## The value tree

`types.Value` (`src/formosh/schema/types.gleam`): `StringValue`,
`NumberValue` (float), `IntegerValue`, `BooleanValue`, `NullValue`,
`ArrayValue(List(Value))`, `ObjectValue(List(#(String, Value)))` — the object
is a key-ordered association list, preserving the schema's declared field
order for rendering.

Two getters with different contracts:

- `get_form_values` — the raw tree, including values of fields currently
  hidden by an inactive branch; nothing is lost when a condition toggles
  back.
- `get_resolved_values` — root fields filtered to those present in
  `resolved_schema.properties`, so inactive top-level branch fields are
  excluded from submission. Nested inactive conditional fields are not yet
  filtered.

## Auxiliary path-keyed state

`touched_fields`, `selected_branches`, `array_collapse_off` and
`array_rows_expanded` are all keyed by `FieldPath` and must reindex together
whenever an array row is removed or moved — see [Update](update.md) for the
invariants.

## Cross-links

- How paths get mutated → [Update](update.md)
- How the effective schema is computed → [Visibility](visibility.md)
