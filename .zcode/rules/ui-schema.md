---
paths:
  - "src/formosh/schema/ui_parser.gleam"
  - "src/formosh/schema/ui_schema.gleam"
  - "src/formosh/schema/ui_resolver.gleam"
---

# UiSchema key semantics

Presentation hints live in a parallel `UiSchema` (react-jsonschema-form-style
JSON). Children are nested inline by field name; `items` is the
array-element template. `lookup` (`formosh/schema/ui_resolver`) walks by
`FieldPath` — an `ArraySegment` ignores the index and descends into `items`.
Full reference: `docs/reference/ui-schema.md`.

- `ui:disabled` / `ui:readonly` **OR-merge** with the parent / schema.
  `ui:disabled: false` on a child of a disabled container does NOT re-enable
  it — mirrors HTML's `disabled` inheritance and JSON Schema's `readOnly`.
  To selectively enable, hoist the disabled flag to the leaf instead of the
  container.
- `ui:orderable` toggles the per-row ▲/▼ reorder buttons on an array
  (default `true`); `false` hides them. Buttons are disabled at the ends and
  hidden when the array has one item or fewer; the controls expose classes
  `move-array-item-up` / `move-array-item-down`.
- `ui:options` on an array node additionally supports `collapseCompleted`
  (bool, default `false`), `collapseCompletedLabel` (string, default
  `"Collapse completed"`), and `summaryFields` (string[], default `[]` —
  every scalar field of the row's resolved schema, in schema order, arrays
  and objects excluded). See
  `docs/reference/ui-schema.md#collapse-completed-array-rows` and
  `docs/reference/widgets.md#collapsing-completed-rows`.
- `ui:accept` / `ui:maxFileSize` are only honoured when
  `ui:widget: "image-upload"` is set. Without the widget hint they are
  silently dropped (the `UploadConfig` is not emitted).
- `ui:layout` arranges a container's fields into `Row`/`Group` nodes instead
  of one field per row; leaves are single-segment child names — a `.` is
  rejected and reserved for future path addressing — and it has no effect in
  review mode (`read-only="true"`). See
  `docs/reference/ui-schema.md#layout-with-uilayout`.
- `ui:widget: "hidden"` suppresses rendering at any depth; the field still
  validates and submits — see `.zcode/rules/hidden-fields.md`.

Removed in v0.11: the `x-*` schema extensions (`parse_schema_with_warning`
diagnoses leftovers) — see `.zcode/rules/schema-composition.md`.
