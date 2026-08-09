---
type: reference
title: "UiSchema"
description: "The parallel JSON tree that controls how a Formosh form is presented: ui:* keys, widget overrides, field ordering, layout, and array controls."
---

# UiSchema

JSON Schema describes your **data**. UiSchema describes how to **present**
it — widget choice, field order, placeholder text, help text, array
controls — without polluting the data schema. The two live side by side:
parse a JSON Schema for the shape, parse a UiSchema for the presentation,
attach both to the same form.

```
JSON Schema  →  what the data IS      (types, validation, structure)
UiSchema     →  how the form LOOKS    (widgets, labels, order, help)
```

Formosh's UiSchema follows the [react-jsonschema-form](https://rjsf-team.github.io/react-jsonschema-form/docs/api-reference/uiSchema)
convention: a JSON object that mirrors the schema's shape, with reserved
`ui:*` keys carrying settings for the current node and every other key
treated as a child property name.

## Attaching a UiSchema

Three entry points, all covered in [Configuration](../guides/configuration.md):

```gleam
// Programmatic (parsed UiSchema value)
formosh.with_ui_schema(config, ui)

// From a JSON string — returns Error(ParseError) on bad input
formosh.with_ui_schema_json(config, json_string)
formosh.parse_ui_schema(json_string)
```

As a web-component attribute:

```html
<formosh-form
  schema='{ ... }'
  ui-schema='{ "name": { "ui:placeholder": "Your name" } }'>
</formosh-form>
```

> **Empty / null is valid.** An empty string or JSON `null` parses to
> `empty_ui_schema()` — every field then falls back to its schema-level
> defaults. You can pass through whatever the user supplied without
> guarding.

## JSON shape

The tree mirrors the schema. Three rules:

1. **`ui:*` keys** (`ui:widget`, `ui:help`, …) carry settings for *this*
   node.
2. **`items`** (reserved) is the template for array elements — applies to
   every row. Index is ignored.
3. **Every other key** is a child property name and recurses into another
   UiSchema node.

```jsonc
{
  "ui:order": ["name", "email", "age"],   // root-level field order
  "name":  { "ui:placeholder": "Ada Lovelace" },
  "email": { "ui:widget": "email", "ui:autofocus": true },
  "address": {                             // nested object → recurse
    "street": { "ui:help": "Include apt #" },
    "country": { "ui:widget": "select" }
  },
  "tags": {                                // array
    "ui:addable": true,
    "ui:removable": false,
    "items": {                             // template for each row
      "label": { "ui:placeholder": "tag name" }
    }
  }
}
```

Root-level `ui:order` applies to the form's top-level fields. Nested
`ui:order` applies to that object's children. A missing node in the
UiSchema tree simply means "no overrides — use schema defaults".

## All supported `ui:*` keys

Every key is optional. Omitting one means "fall through to the schema
default (or `x-*` extension where applicable)".

### Widget and options

| Key | Type | Effect |
|-----|------|--------|
| `ui:widget` | string | Override the auto-selected widget. Recognized: `"image-upload"`, `"hidden"`, `"swipe-review"`, plus the string-field hints `"textarea"`, `"select"`, `"radio"`, `"password"`. `"select"` / `"radio"` also apply to an `anyOf` union chooser on the same path — same ≤5-radio / >5-select contract as a string `enum`, see [Union chooser](widgets.md#union-chooser-anyof-2-branches). Anything else becomes a `CustomWidget(raw)` that custom renderers can dispatch on. See [Widget Selection](widgets.md). |
| `ui:options` | object | Free-form bag of widget-specific settings, passed through to the renderer as a `Dict(String, Value)`. E.g. `swipe-review` reads `swipeRight` / `swipeLeft` / `button` / `hideAnsweredLabel` from here; an array reads `collapseCompleted` / `collapseCompletedLabel` / `summaryFields` to collapse completed rows — see [Collapse completed array rows](#collapse-completed-array-rows) below. |

### Labels and help

| Key | Type | Effect |
|-----|------|--------|
| `ui:title` | string | Overrides the schema's `title` for the field label. |
| `ui:description` | string | Overrides the schema's `description`. |
| `ui:help` | string | Help text rendered below the input (overrides `description` when both are present). |
| `ui:placeholder` | string | Placeholder text for the input. |

### Behaviour flags

| Key | Type | Effect |
|-----|------|--------|
| `ui:autofocus` | bool | Adds the HTML `autofocus` attribute. |
| `ui:disabled` | bool | Runtime disable — input rendered but not editable. |
| `ui:readonly` | bool | Augments JSON Schema `readOnly`. Distinct from form-wide review mode. |

### Field ordering

| Key | Type | Effect |
|-----|------|--------|
| `ui:order` | string[] | Reorders children of this object. Fields not listed keep their schema order after the listed ones. Use `"*"` as a wildcard to mean "the rest, in schema order". |
| `ui:layout` | array | Arranges children into `Row`/`Group` nodes instead of a flat list; unplaced fields still render after it, in `ui:order`. See [Layout with `ui:layout`](#layout-with-uilayout) below. |

### Array controls

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `ui:addable` | bool | `true` | Show/hide the "add row" button. |
| `ui:removable` | bool | `true` | Show/hide the "remove row" button (also gated by `minItems`). |
| `ui:orderable` | bool | `true` | Show/hide the move up/down buttons (auto-hidden when the array has ≤1 item). |

`x-addable` / `x-removable` on the schema node are a deprecated fallback
with the same meaning; UiSchema wins on collision.

### Collapse completed array rows

Set inside `ui:options` on the array node itself — these are not top-level
`ui:*` keys, they live in the free-form bag described above:

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `collapseCompleted` | bool | `false` | Enables the feature on this array. Absent (or `false`) means no behaviour change at all — the array renders exactly as it did before this feature existed. |
| `collapseCompletedLabel` | string | `"Collapse completed"` | Caption on the toggle checkbox. |
| `summaryFields` | string[] | `[]` | Row fields shown in the collapsed summary, in the given order. `[]` defaults to every **scalar** field of the row's resolved schema, in schema order — array- and object-typed fields are both excluded from that default, so either only appears when you list it explicitly, and even then an explicitly listed object field (or an unknown field name) is silently dropped rather than shown or erroring. A field the expanded row itself would hide — `ui:widget: "hidden"`, or `readOnly` while `show_readonly_fields` is off — is dropped the same way, named explicitly or picked up by the default: collapsing never shows a value the expanded row would not. |

A row collapses only when all three hold: it has at least one non-empty own
field, array-item validation reports no error at its index, and no recorded
error in the form's error map falls under its path. That third check treats
`model.errors` as authoritative for "nothing wrong in this row" — see
[Collapsing completed rows](widgets.md#collapsing-completed-rows) for a
known gap where a cross-field validator's error on a path only a per-row
conditional reveals never reaches that map.

Two value-formatting rules matter when picking `summaryFields`: a
non-empty `password`-format (or `ui:widget: "password"`) value renders the
fixed `••••••••` mask, never the real value — an empty one is simply
omitted, like any other blank field; and a boolean field renders its own
title when `true` and is omitted entirely when `false` (a null, empty-string,
or empty-array value is dropped before masking is considered at all; past
that, masking is decided before the value's shape is dispatched on, so a
boolean carrying a password hint masks rather than following the boolean
rule).

The worked example below leans on the second rule for its simplest case:
with `affected` set to `false`, a collapsed row shows only `zone_id` and
`label`. Both are `readOnly`, so whether they reach the summary at all
turns on `show_readonly_fields` — and the two entry points disagree on its
default: `<formosh-form>` starts it **on**, `FormConfig` starts it **off**.
Through the component those fields therefore appear unless the attribute is
set to something other than the exact string `"true"` — the parse is strict,
so `"false"`, `"1"`, `"TRUE"` and a bare valueless attribute all read as
off; built through `FormConfig` without
`with_show_readonly_fields(True)`, the suppression rule above drops them
from the summary and the row collapses to just its 1-based number. A row
that instead completes with `affected: true` (lesions filled in too) would
also show the boolean's title and an `"Очаги: N"` count.

### Image upload

Only honored when `ui:widget: "image-upload"` is also set — without the
widget, these are ignored (no silent `image/*` fallback).

| Key | Type | Effect |
|-----|------|--------|
| `ui:accept` | string | The `accept` attribute on the file input. Defaults to `"image/*"` when the widget is set. |
| `ui:maxFileSize` | number | Maximum file size in bytes. |

### Password masking

`ui:widget: "password"` forces `<input type="password">` regardless of the
field's `format` — the widget hint **wins over a conflicting `format`**.
`format: "password"` alone also forces `<input type="password">`, and both
routes win over the `maxLength > 100 → textarea` threshold
**unconditionally**: a declared password never falls back to an unmasked
textarea on length alone, no matter how large `maxLength` is. See [HTML input
type from `format`](widgets.md#html-input-type-from-format).

The one way to unmask a declared password is to ask for it explicitly: an
explicit `ui:widget` of `"textarea"`, `"select"`, or `"radio"` is dispatched
before any `format` check and renders the value **in the clear**. Setting one
of those on a `format: "password"` field is almost certainly a mistake.

Masking is presentational only, in both edit mode and read-only (review)
mode: the raw value still lives in `model.values` and is still published
via the `formosh-change` event. Do not treat it as a security boundary.

### Layout with `ui:layout`

`ui:layout` arranges a container's own fields into an explicit tree instead
of the default flat, one-field-per-row list. It is set beside the other
`ui:*` keys on the form root, a nested object, or an array's `items`
template (applied to every row alike — see
[How the tree is walked](#how-the-tree-is-walked)), and holds an ordered
array of **nodes**:

| Node | JSON shape | Renders as |
|------|-----------|------------|
| Leaf | a bare string naming a field | the field itself, unchanged |
| `Row` | `{ "type": "Row", "elements": [...] }` | `part="row"`, an inline CSS grid |
| `Group` | `{ "type": "Group", "label": "...", "elements": [...] }` | `part="group"` wrapping an optional `part="group-label"` and a `part="group-body"` |

```json
{
  "ui:layout": [
    "invalid",
    { "type": "Row", "elements": ["length_mm", "height_mm"] },
    { "type": "Group", "label": "Асцит", "elements": [
      "ascites",
      { "type": "Row", "elements": ["ascites_type", "ascites_thickness"] }
    ]}
  ]
}
```

`invalid` renders on its own line, `length_mm` and `height_mm` share a row,
and the "Асцит" group wraps its trigger checkbox and a row of two detail
fields under one label. `demo/schemas/basic_leak_signs.ui.json` is a full
working example along the same lines — it groups every conditionally
injected detail field under the checkbox that reveals it.

A few rules govern how a layout resolves:

- **A leaf names a direct child of the container the layout is anchored
  on.** Nesting a leaf inside a `Row`/`Group` changes only how it renders,
  not what it can address — it still resolves against the anchoring
  container's own fields, never a nested object's. A `.` in a leaf is
  rejected at parse time — cross-container path addressing isn't
  supported yet; the dot is reserved for it.
- **`ui:layout` must be a JSON array, and so must every node's
  `elements`.** An object (`{"a": ..., "b": ...}` instead of `["a", ...]`)
  is rejected, because object key order isn't preserved by every backing
  store and `ui:layout` depends on order.
- **Both rejections above are `Error(ParseError)` through the Gleam API**
  (`formosh.parse_ui_schema` / `with_ui_schema_json`, see
  [Attaching a UiSchema](#attaching-a-uischema)). Through `<formosh-form>`,
  a `ui-schema` attribute that fails to parse only logs a console error —
  the component never applies it, so **every** `ui:*` hint in the document
  is silently dropped, not just the offending leaf or node. Tracked as
  [#120](https://github.com/radionest/gleam_formosh/issues/120).
- **A leaf naming a field that isn't currently present is skipped
  silently**, not treated as an error — so one UiSchema file can serve
  several forms, and a `Group` can name a conditionally-injected field
  before its trigger has fired.
- **A `Row` or `Group` whose named leaves are all absent renders nothing
  at all** — no empty grid, no empty label. That covers only *absence*: a
  leaf naming a field that exists but is hidden — `ui:widget: "hidden"`,
  or `readOnly` while `show_readonly_fields` is off — still counts as a
  child, because the field dispatcher renders an empty-but-present element
  for it rather than dropping it. A `Group` wrapping only such suppressed
  leaves still renders its `part="group"` wrapper and, if given a `label`,
  a visible `part="group-label"` over an empty `part="group-body"`.
- **Fields the layout doesn't place still render, after every placed
  node, ordered by `ui:order`** — exactly as they would with no layout.
  `ui:order` keeps doing its normal job over that leftover set; a layout
  can relocate fields but never hide them.
- **Naming the same field twice is valid grammar** — `["a", "a"]`, or `a`
  inside two different `Group`s — and renders the field twice. Nothing
  detects or rejects it: the two copies get duplicate `id` attributes and,
  for a radio-backed field, duplicate `id`/`for` pairs, which is invalid
  HTML. Treat it as author error to avoid, not a constraint the parser
  validates today.
- **Review mode (`read-only="true"`) ignores `ui:layout`.** The review
  summary always renders in plain `ui:order` order, with or without a
  layout — not supported today, not a bug.

`Row`'s default grid is `repeat(auto-fit, minmax(min(100%,12rem), 1fr))`,
which collapses to fewer columns on narrow viewports with no media query
needed. Tune the gap with the `--formosh-row-gap` custom property (default
`1rem`), or override `grid-template-columns` outright via
`formosh-form::part(row)` — see
[Styling](../guides/styling.md#overriding-the-uilayout-grid) for the full
recipe, including targeting one field by name.

## How the tree is walked

Lookup follows the schema's `FieldPath` (`src/formosh/schema/ui_resolver.gleam`):

- **`PropertySegment(name)`** → descends into `.properties[name]`.
- **`ArraySegment(index)`** → descends into `.items` (the index is
  *ignored* — the items template applies to every row uniformly).
- **Any miss** → returns `empty_ui_property()`, so every field falls back
  to schema defaults without error.

Root path (`[]`) returns `empty_ui_property()` — root-level options like
`ui:order` live on the `UiSchema` itself, not on a `UiProperty`.

## Merge precedence with `x-*` extensions

JSON Schema nodes can also carry `x-widget`, `x-addable`, `x-removable`,
`x-accept`, `x-max-file-size` as vendor extensions. Formosh reconciles
both sources into a single `RenderHints` record (`ui_resolver.resolve_hints`):

| Field | Precedence |
|-------|------------|
| `widget`, `upload_config` | **UiSchema wins**; `x-*` used only when UiSchema is unset |
| `addable`, `removable` | **UiSchema wins**; falls back to the schema's parsed Bool |
| `orderable` | **UiSchema only** — no `x-*` analogue (`None` means "enabled") |
| `placeholder`, `help`, `autofocus`, `disabled`, `readonly`, `title`, `description`, `order`, `options` | **UiSchema only** — JSON Schema has no analogues |

For new schemas, **prefer `ui:*` over `x-*`**. It keeps the data schema
clean, survives serialization round-trips more reliably, and is the
forward-looking path (the `x-*` family is the deprecated fallback retained
for compatibility).

## Worked examples

All three are lifted from `demo/schemas/*.ui.json` — open them in the demo
(`make demo`) to see them live.

### Disable array controls and collapse completed rows

A medical scoring form where zones are fixed, per-zone lesions can't be
rearranged, and each row collapses to a summary once it's filled in:

```json
{
  "zones": {
    "ui:addable": false,
    "ui:removable": false,
    "ui:orderable": false,
    "ui:options": {
      "collapseCompleted": true,
      "collapseCompletedLabel": "Сворачивать заполненные",
      "summaryFields": ["zone_id", "label", "affected", "lesions"]
    },
    "items": {
      "lesions": { "ui:orderable": false }
    }
  }
}
```

The `items` block is the template applied to every zone row; the nested
`lesions.ui:orderable` reaches inside each row. `summaryFields` lists
`lesions` explicitly — the default set would have excluded it, since it's
an array (`"Очаги: 2"` only appears because the author asked for it).

A row collapses once `affected` is set to `false` — `false` still counts
as a filled field (only an absent, null, empty-string, empty-array, or
empty-object value doesn't), and with `affected` false the schema requires
no `lesions` at all, so there's nothing left that could fail. Setting
`affected` to `true` reopens the row, because the lesion the schema then
auto-creates (`minItems: 1`) starts out unfilled and fails its own
required fields.

What that collapsed row actually *shows* turns on `show_readonly_fields`,
since `zone_id` and `label` are both `readOnly`. In the demo they appear
because `<formosh-form>` defaults that flag **on** — the page's own
`show-readonly-fields="true"` only restates the default. Build the same
form through `FormConfig`, where the flag defaults to `False`, and both
fields are suppressed from the summary along with everything else the
expanded row hides, leaving the row number as the only thing left to
render.

### Help text and placeholders for pattern-validated fields

Russian-localized hints for fields whose `pattern` the user can't see:

```json
{
  "username":   { "ui:help": "Латиница, цифры и _ — от 3 до 20 символов. Пример: alice_42" },
  "postalCode": { "ui:help": "Ровно 6 цифр. Пример: 119991" },
  "phone":      { "ui:placeholder": "+7 (999) 123-45-67", "ui:help": "Российский формат с кодом страны." },
  "hexColor":   { "ui:placeholder": "#1a2b3c", "ui:help": "Цвет в формате #RRGGBB." }
}
```

### Widget override with widget-specific options

Switch an array into the `swipe-review` tap widget and configure its
choices via `ui:options`:

```json
{
  "zones": {
    "ui:widget": "swipe-review",
    "ui:options": {
      "swipeRight": { "value": "positive", "label": "Карциноматоз", "tone": "danger" },
      "swipeLeft":  { "value": "negative", "label": "Чисто", "tone": "ok" },
      "button":     { "value": "inaccessible", "label": "Недоступна", "tone": "muted" },
      "hideAnsweredLabel": "Скрывать отвеченные"
    }
  }
}
```

`swipe-review` reads its choice definitions from `ui:options` — that's the
free-form bag the renderer reads when the built-in widgets don't cover
your case.

## Source of truth

| Concern | File |
|---------|------|
| JSON parsing (`ui:*` extraction, `items` handling) | `src/formosh/schema/ui_parser.gleam` |
| Tree types (`UiSchema`, `UiProperty`) | `src/formosh/schema/ui_schema.gleam` |
| Path-based lookup + `x-*` merge + suppression predicate | `src/formosh/schema/ui_resolver.gleam` |
| Recognized `ui:widget` values | `ui_parser.extract_widget` |
| Where hints are consumed by renderers | `FieldRenderCtx.hints` in `src/formosh/fields/field_common.gleam` |
| Layout node types + `arrange` walker | `src/formosh/fields/layout.gleam` |
| `ui:layout` parsing (node/leaf validation) | `ui_parser.extract_layout` |
