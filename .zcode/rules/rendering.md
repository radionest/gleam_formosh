---
paths:
  - "src/formosh/fields/**/*.gleam"
---

# Field rendering rules

When creating or modifying field renderers, follow these business logic rules:

- `maxLength > 100` renders as textarea, otherwise as input — except a
  password field (`format: "password"` or `ui:widget: "password"`), which
  always wins over the threshold and stays a password input
- `enum` with ≤5 options renders as radio buttons
- `enum` with >5 options renders as select dropdown
- Boolean fields render as Yes/No radio buttons
- Format-specific inputs: email, date, time, url, password use
  corresponding HTML input types (password also via `ui:widget: "password"`)
- Arrays render as dynamic list with add/remove controls — except a
  `uniqueItems: true` array whose scalar `items` carry options
  (`types.is_multi_select`), which renders as a checkbox group
  (`string_field.render_checkboxes`) instead
- An event's message carries the user's intent (the clicked option, the
  typed value), never a replacement value computed from the render: Lustre
  re-renders on requestAnimationFrame, so two events in one frame dispatch
  from the same stale view (#137). Derive the new state in `update` from
  `model.values`, and re-check any bound the view enforces by disabling
  (e.g. `maxItems`) there too — see `widget_msg.ToggleOption`
- Objects render as nested fieldset with proper indentation
- Numbers with `multipleOf` set the step attribute
- Fields with `description` get help text below the input

## Docs

- Widget decision tree + override mechanisms: `docs/reference/widgets.md`
- Part-name catalog and styling surfaces: `docs/guides/styling.md`
- `ui:*` keys consumed by renderers: `docs/reference/ui-schema.md`
