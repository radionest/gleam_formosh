---
paths:
  - "src/formosh/component.gleam"
  - "src/formosh/internal/component_core.gleam"
  - "src/formosh/internal/stylesheet.gleam"
  - "src/formosh/fields/readonly_field.gleam"
  - "src/formosh/cdn.gleam"
---

# Web component contract and styling

## Surface

Registers as `<formosh-form>`. Attributes: `schema`, `ui-schema`,
`submit-url`, `submit-method`, `initial-values`, `show-readonly-fields`,
`read-only`, `upload-base-url`. Events: `formosh-ready`,
`formosh-submitting`, `formosh-submit`, `formosh-change`. Full guide:
`docs/guides/web-component.md`.

## Review mode

`read-only="true"` renders the whole form as a static label→value summary
(review mode) instead of inputs, hiding Submit/Reset — distinct from
`show-readonly-fields`, which only toggles visibility of schema `readOnly`
fields in edit mode. One exception to "plain value": `password`-format /
`ui:widget: "password"` fields show a fixed `••••••••` mask instead of the
stored value, same as in edit mode — see `docs/reference/widgets.md`.
Drives the `readonly_field` renderer
(`src/formosh/fields/readonly_field.gleam`); exposes
`::part(readonly-field|readonly-label|readonly-value|readonly-group|readonly-group-label|readonly-group-body|readonly-table|readonly-th|readonly-td)`.

## Styling rules

- The component runs in open Shadow DOM: target it via `::part()` selectors
  (`formosh-form::part(input)`, etc.) and `[part=field][data-error]` /
  `[part=field][data-readonly]` for field state, plus
  `[part=field][data-name=…]` / `[data-path=…]` for field identity (not
  state). Part catalog: `docs/guides/styling.md`.
- Parent stylesheets are auto-adopted, so plain `.formosh-input { ... }`
  rules still apply inside the shadow root.
- formosh's own defaults (the `ui:layout` Row grid, the array fold, the
  swipe row's `touch-action`) live in
  `src/formosh/internal/stylesheet.gleam`, rendered as the container's first
  child inside `@layer formosh` — the lowest layer, so consumer rules
  override them without `!important` (edge cases — plain-Lustre layer
  ordering, page sheets Lustre cannot copy — in
  `docs/guides/styling.md#cascade-and-limitations`).
- Inline `style` is reserved for runtime state (the swipe widget's
  drag/fly-off); never add an inline default. Tokens:
  `docs/guides/styling.md#tokens`.
- Before editing that stylesheet, read its comments: selector quoting and
  `.formosh-container` scoping rules live there.
