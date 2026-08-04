---
paths:
  - "src/formosh/fields/**/*.gleam"
---

# Field rendering rules

When creating or modifying field renderers, follow these business logic rules:

- `maxLength > 100` renders as textarea, otherwise as input — except
  `ui:widget: "password"`, which wins over the threshold and stays a
  password input
- `enum` with ≤5 options renders as radio buttons
- `enum` with >5 options renders as select dropdown
- Boolean fields render as Yes/No radio buttons
- Format-specific inputs: email, date, time, url, password use
  corresponding HTML input types (password also via `ui:widget: "password"`)
- Arrays render as dynamic list with add/remove controls
- Objects render as nested fieldset with proper indentation
- Numbers with `multipleOf` set the step attribute
- Fields with `description` get help text below the input

## Docs

- Widget decision tree + override mechanisms: `docs/reference/widgets.md`
- Part-name catalog and styling surfaces: `docs/guides/styling.md`
- `ui:*` keys consumed by renderers: `docs/reference/ui-schema.md`
