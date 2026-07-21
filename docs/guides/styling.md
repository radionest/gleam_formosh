---
type: guide
title: "Styling"
description: "Customize Formosh appearance: ::part() selectors, data-state attributes, and auto-adopted parent stylesheets."
---

# Styling

Formosh renders inside an **open Shadow DOM** when used as the
`<formosh-form>` web component. There are no default styles — the form
arrives unstyled and you bring your own CSS.

There are three surfaces for customization, in increasing order of
specificity. The first two only apply in web-component mode (Shadow DOM);
the third applies everywhere.

> **Plain Lustre app (no web component)?** Skip the first two sections.
> Without the shadow root there are no `::part()` hooks; only plain class
> selectors on `.formosh-*` work. That's the trade-off for inlining the
> form directly in your view tree.

## 1. `::part()` selectors — preferred

Every styled element inside the shadow root exposes a `part` name — the
class suffix without the `formosh-` prefix. Target them from the host
document's stylesheet:

```css
formosh-form { display: block; max-width: 32rem; }

formosh-form::part(input)  { border: 1px solid #d33; padding: .5rem; }
formosh-form::part(label)  { font-weight: 600; }
formosh-form::part(error)  { color: #d33; font-size: .85rem; }
formosh-form::part(submit) { background: #08a; color: white; }
```

`::part()` is the recommended surface because it's the contract: the part
names are stable even if the internal class names or DOM structure change.

## 2. `data-*` attributes for state

Some elements carry `data-*` attributes that mirror their interaction
state, so you can style by state without writing class toggles yourself:

```css
/* A field that currently has a validation error */
formosh-form::part(field)[data-error] { border-color: red; }

/* A readOnly field rendered as disabled */
formosh-form::part(field)[data-readonly] { opacity: 0.6; }

/* Boolean toggle on/off */
formosh-form::part(toggle)[data-state="on"]  { background: #0a8; }
formosh-form::part(toggle)[data-state="off"] { background: #ccc; }
```

## 3. Parent stylesheets are auto-adopted

Lustre clones the host document's CSS into the shadow root, so plain class
selectors against the internal `formosh-*` classes also apply:

```css
.formosh-input { padding: 0.5rem; }
.formosh-error { color: red; }
```

This is the lowest-specificity surface. Use it for broad resets, then reach
for `::part()` for anything more specific.

## Full part-name catalog

Every styled element exposes a part. Grouped by area:

**Core / layout:**
`container`, `header`, `title`, `description`, `form`, `footer`, `submit`,
`reset`, `success`, `error-message`, `loading`.

**Field scaffolding:**
`field`, `field-wrapper`, `label`, `required`, `help`, `errors`, `error`.

**Inputs (by widget):**
`input`, `number`, `textarea`, `select`, `radio-group`, `radio-item`,
`boolean`, `checkbox-wrapper`, `checkbox-group`, `toggle`, `toggle-wrapper`,
`toggle-slider`, `toggle-text`.

**Image upload:**
`image-upload`, `image-grid`, `image-card`, `image-preview`, `image-add`,
`image-remove`, `image-uploading`, `image-spinner`, `image-error`,
`image-error-text`.

**Read-only (review) mode** — adds:
`readonly-field`, `readonly-label`, `readonly-value`, `readonly-group`,
`readonly-group-label`, `readonly-group-body`, `readonly-table`,
`readonly-th`, `readonly-td`.

**Swipe-review widget** — adds:
`swipe-review`, `swipe-sheet`, `swipe-regions`, `swipe-region-group`,
`swipe-region`, `swipe-zones`, `swipe-row`, `swipe-zone-title`,
`swipe-choices`, `swipe-choice`, `swipe-progress`, `swipe-controls`,
`swipe-undo`, `swipe-fill`, `swipe-review-summary`, `swipe-review-title`,
`swipe-review-list`, `swipe-review-row`, `swipe-review-zone`,
`swipe-review-answer`.

## Cascade and limitations

### Cascade order

Adopted parent stylesheets and host-level `::part()` rules cascade by
normal CSS specificity — neither wins automatically just by being "inside"
or "outside" the shadow root. Concretely:

- To **override a `.formosh-*` class rule** with a `::part()` rule, give
  the `::part()` selector higher specificity or use a more specific
  compound condition. For example, `::part(input):not(:disabled)` will
  beat a plain `.formosh-input` rule.
- `!important` works from the host document inside `::part()`; use it
  sparingly.

### No descendant combinator inside `::part()`

The Shadow Parts spec does not support descendant combinators — so you
cannot write `formosh-form::part(boolean) ::part(radio-item)`. This matters
because some elements carry **two** part tokens (e.g.
`part="radio-group boolean"`) — they are reachable through either token,
but a `radio-item` inside a boolean group cannot be styled differently
from one inside an enum group through Shadow Parts alone.

Workarounds when you need to differentiate:

- Add a marker class on the host element (`<formosh-form class="compact">`)
  and select via the host — `formosh-form.compact::part(radio-item) { … }`.
- Restructure the schema so the two cases use different widgets (e.g. a
  different `ui:widget`), which then map to different parts.

### Plain Lustre app (no shadow root)

When you start Formosh via `lustre.start(formosh.from_config(...), ...)` —
no web component, no shadow root — only the class selectors (surface 3)
apply. `::part()` and `data-*` hooks don't exist because there's no shadow
boundary. If you need those hooks, switch to the web-component deployment.

## Reference

The part names are assigned in the field renderers under
`src/formosh/fields/` and the form scaffold in `src/formosh/form/view.gleam`
— search for `attribute.attribute("part", …)` to see every assignment in
context.
