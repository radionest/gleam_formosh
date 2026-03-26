---
globs: "src/formosh/fields/**/*.gleam"
---

# Field rendering rules

When creating or modifying field renderers, follow these business logic rules:

- `maxLength > 100` renders as textarea, otherwise as input
- `enum` with ≤5 options renders as radio buttons
- `enum` with >5 options renders as select dropdown
- Boolean fields render as Yes/No radio buttons
- Format-specific inputs: email, date, url use corresponding HTML input types
- Arrays render as dynamic list with add/remove controls
- Objects render as nested fieldset with proper indentation
- Numbers with `multipleOf` set the step attribute
- Fields with `description` get help text below the input
