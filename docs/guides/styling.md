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

> **Plain Lustre app (no web component)?** Skip section 1 — without the
> shadow root there are no `::part()` hooks. The `data-*` state attributes
> (section 2) still work everywhere: they are plain HTML attributes, so
> combine them with class selectors (`.formosh-field[data-error]`).

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
[part=field][data-error] { border-color: red; }

/* A readOnly field rendered as disabled */
[part=field][data-readonly] { opacity: 0.6; }

/* A completed array row currently collapsed to its summary */
[part=array-item][data-collapsed] { padding-block: 0.25rem; }
```

Note the `[part=…]` form rather than `::part(…)`. State selectors **cannot**
be written as `formosh-form::part(field)[data-error]` — an attribute selector
cannot follow a pseudo-element, so the browser drops the whole rule at parse
time and the style silently never applies. The `[part=…][data-…]` form above
works instead because parent stylesheets are auto-adopted into the shadow root
(§3), which is also the constraint it carries: these rules must live in a
stylesheet the page adopts. Unlike the `::part()` selectors in §1, they are not
reachable from a stylesheet that only sees the custom element from outside.

`data-collapsed` is presence-only: it appears (value `"true"`) only on a
row that is actually collapsed, and is absent — not `"false"` — on every
other row, matching `data-error` and `data-readonly` above.

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
`boolean`, `checkbox-wrapper`, `checkbox-group`.

**Arrays:**
`array-field` (outer container), `array-items` (the row list), `array-item`
(one row's wrapper), `array-item-fields` (that row's child fields — this is
the one part that disappears entirely on a collapsed row), `array-item-header`
(per-row move/remove controls — rendered regardless of collapse state, but
nothing at all in read-only mode or when neither control applies, as in the
demo's own `ui:removable`/`ui:orderable: false` zones), `array-add`.

**Collapse-completed arrays** (`ui:options.collapseCompleted`) — adds:
`array-collapse-header` (wraps the toggle and progress element),
`array-toggle` (the `<label>` wrapping the header's checkbox and caption —
the part sits on the label, not the `<input>`), `array-progress` (the
counter), `array-item-summary` (a completed row's own summary button —
while the per-array toggle is switched on, renders in **both** the
expanded and collapsed state; switched off, it doesn't render at all, for
any row), `array-item-summary-value`, `array-item-summary-sep`.

The progress text is bare `"{completed} / {total}"` — no prefix word. Add
one yourself, e.g. `formosh-form::part(array-progress)::before { content:
"Done: "; }`. `array-item-summary-value` has no descendant combinator to
lean on (see below), so every value in a row's summary — whichever field
produced it — styles identically; there's no way to single out, say, just
the first one through `::part()` alone.

**Union (`anyOf`, 2+ branches):**
`union` (outer wrapper), `union-radio` (radio-group chooser, ≤5 branches by
default), `union-select` (select chooser, >5 branches by default or
`ui:widget: "select"`). Individual radio options reuse the `radio-item` part
above — there is no separate `union-radio-item`.

(The source also assigns `toggle`, `toggle-wrapper`, `toggle-slider`,
`toggle-text` and a `data-state` attribute in a toggle renderer that is not
yet reachable through `ui:widget` — see `ROADMAP.md`.)

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
`swipe-toggle`, `swipe-undo`, `swipe-fill`, `swipe-review-summary`,
`swipe-review-title`, `swipe-review-list`, `swipe-review-row`,
`swipe-review-zone`, `swipe-review-answer`.

## Cascade and limitations

### Cascade order

Host-document `::part()` rules and adopted (cloned-in) stylesheets live in
different cascade contexts, and per CSS Scoping ("Shadow Cascading") the
**outer context wins for normal declarations regardless of specificity** —
a host `::part(input)` rule beats any adopted `.formosh-input` rule. For
`!important` declarations the order inverts: an adopted `!important` rule
beats a host `::part()` one. Specificity only breaks ties between rules in
the *same* context (two adopted rules, or two host rules).

### No descendant combinator inside `::part()`

The Shadow Parts spec does not support descendant combinators — so you
cannot write `formosh-form::part(boolean) ::part(radio-item)`. This matters
because some elements carry **two** part tokens (e.g.
`part="radio-group boolean"`) — they are reachable through either token,
but a `radio-item` inside a boolean group cannot be styled differently
from one inside an enum group through Shadow Parts alone.

The same limit applies to a completed row's summary: every
`array-item-summary-value` styles identically wherever it appears, because
there is no `formosh-form::part(array-item) ::part(array-item-summary-value)`
to scope by which row — or which field within the row — produced it.

Workarounds when you need to differentiate:

- Add a marker class on the host element (`<formosh-form class="compact">`)
  and select via the host — `formosh-form.compact::part(radio-item) { … }`.
- Restructure the schema so the two cases use different widgets (e.g. a
  different `ui:widget`), which then map to different parts.

### Plain Lustre app (no shadow root)

When you start Formosh via `lustre.start(formosh.from_config(...), ...)` —
no web component, no shadow root — `::part()` selectors don't apply (there
is no shadow boundary), but class selectors and the `data-*` state
attributes still work:

```css
.formosh-field[data-error] { border-color: red; }
```

## Reference

The part names are assigned in the field renderers under
`src/formosh/fields/` and the form scaffold in `src/formosh/form/view.gleam`
— search for `attribute.attribute("part", …)` to see every assignment in
context.
