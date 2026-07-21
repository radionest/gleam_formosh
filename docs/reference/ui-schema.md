---
type: reference
title: "UiSchema"
description: "The parallel JSON tree that controls how a Formosh form is presented: ui:* keys, widget overrides, field ordering, and array controls."
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
| `ui:widget` | string | Override the auto-selected widget. Recognized: `"image-upload"`, `"hidden"`, `"swipe-review"`, plus the string-field hints `"textarea"`, `"select"`, `"radio"`. Anything else becomes a `CustomWidget(raw)` that custom renderers can dispatch on. See [Widget Selection](widgets.md). |
| `ui:options` | object | Free-form bag of widget-specific settings, passed through to the renderer as a `Dict(String, Value)`. E.g. `swipe-review` reads `swipeRight` / `swipeLeft` / `button` / `hideAnsweredLabel` from here. |

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

### Array controls

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `ui:addable` | bool | `true` | Show/hide the "add row" button. |
| `ui:removable` | bool | `true` | Show/hide the "remove row" button (also gated by `minItems`). |
| `ui:orderable` | bool | `false` | Show/hide the move up/down buttons. |

`x-addable` / `x-removable` on the schema node are a deprecated fallback
with the same meaning; UiSchema wins on collision.

### Image upload

Only honored when `ui:widget: "image-upload"` is also set — without the
widget, these are ignored (no silent `image/*` fallback).

| Key | Type | Effect |
|-----|------|--------|
| `ui:accept` | string | The `accept` attribute on the file input. Defaults to `"image/*"` when the widget is set. |
| `ui:maxFileSize` | number | Maximum file size in bytes. |

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

### Disable array controls and lock down nested reordering

A medical scoring form where zones are fixed and per-zone lesions can't be
rearranged:

```json
{
  "zones": {
    "ui:addable": false,
    "ui:removable": false,
    "ui:orderable": false,
    "items": {
      "lesions": { "ui:orderable": false }
    }
  }
}
```

The `items` block is the template applied to every zone row; the nested
`lesions.ui:orderable` reaches inside each row.

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
