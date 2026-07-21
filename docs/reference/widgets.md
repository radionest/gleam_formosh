---
type: reference
title: "Widget Selection"
description: "How Formosh picks a concrete widget (text, textarea, radio, select, table, swipe-review...) for a given schema node, and how to override it."
---

# Widget Selection

Formosh does not ask you to declare a widget per field. It picks one
automatically from the schema node's `type`, `enum` / `oneOf`, `format`,
and constraints. This page documents the decision tree and the two override
mechanisms (`ui:widget`, `x-widget`).

> **Source of truth.** The dispatcher is
> `src/formosh/fields/field_dispatcher.gleam:77-105`; per-type logic is in
> `src/formosh/fields/string_field.gleam` and siblings. The merge of
> `ui:widget` and `x-widget` into a single `RenderHints` record happens in
> `src/formosh/schema/ui_resolver.gleam`.

## Selection priority

The dispatcher tries sources in this fixed order. First match wins.

```
1.  UiSchema `ui:widget` (or deprecated `x-widget`) override
        ├─ ImageUploadWidget   → image upload
        ├─ SwipeReviewWidget   → swipe-review
        ├─ HiddenWidget        → not rendered (still validates + gates submit)
        └─ CustomWidget(name)  → name-based dispatch (see "Custom names")
2.  field_type
        ├─ StringType          → string field renderer (see below)
        ├─ NumberType/Integer  → number input (step from multipleOf)
        ├─ BooleanType         → Yes/No radio group
        ├─ ArrayType           → add/remove list container
        └─ ObjectType          → nested fieldset
3.  enum_values / one_of (fallback for typeless nodes)
        └─ renders as a string enum (radio or select)
4.  (nothing matched) → element.none()
```

Two consequences of this order:

- A `ui:widget` override **always wins** over the type-derived widget.
- If a property has no `type` but does have `enum` / `oneOf`, it still
  renders as a string enum (step 3 is how typeless enums work).

## String field rendering

Strings have the richest sub-decision, because `format`, `enum`, `oneOf`,
and `maxLength` all compete. From `string_field.render` →
`render_string_or_enum`:

```
oneOf with const+title options?
├─ yes → oneOf radio group (≤5 options) or oneOf select (>5)
└─ no →
    ui:widget override?
    ├─ "textarea" → textarea
    ├─ "select"   → enum as select (forces dropdown even for ≤5)
    ├─ "radio"    → enum as radio (forces radios even for >5)
    └─ none →
        enum_values present?
        ├─ yes → ≤5 options → radio group
        │        >5 options → select dropdown
        └─ no → maxLength > 100?
                ├─ yes → textarea
                └─ no → text input (type from format, see below)
```

### HTML input type from `format`

When a string renders as a plain `<input>`, its `type` attribute comes from
`StringFormat` (`string_field.get_input_type`):

| `format` | `<input type=...>` |
|----------|---------------------|
| `email` | `email` |
| `url` or `uri` | `url` |
| `date` | `date` |
| `time` | `time` |
| `datetime` | `datetime-local` |
| `uuid`, custom, none | `text` |

This is what gets you the mobile-optimised keyboard and the native picker.

## Number fields

A single number input. If `multipleOf` is set, it becomes the input `step`
attribute (with the tolerant `1e-8` comparison applied during validation —
see [Schema Keywords](schema-keywords.md#number-constraints)). `minimum` /
`maximum` / `exclusiveMinimum` / `exclusiveMaximum` are enforced but do
**not** become HTML attributes (validation runs in the update loop, not in
the browser).

## Boolean fields

Rendered as a Yes/No radio group, not a checkbox — the explicit No matters
for tri-state clarity. (A toggle renderer exists in `boolean_field.gleam`
but is not yet reachable via `ui:widget` — see `ROADMAP.md`.)

## Array fields

A list container with three optional controls, each gated by constraints
and UiSchema flags:

| Control | Shown when |
|---------|-----------|
| **Add** | `addable` (default true) **and** below `maxItems` (if set) |
| **Remove** | `removable` (default true) **and** above `minItems` (if set) |
| **Move up/down** | `orderable` (default true) **and** more than one row |

Rows auto-create up to `minItems` (with item-field defaults applied). Array
items can themselves be objects or arrays — nesting to any depth — so the
container recurses through the same dispatcher.

## Object fields

A nested `<fieldset>` with one labelled child per property. Child order is
preserved from the schema (`properties` is a `List`, not a `Dict`) but can
be overridden via `ui:order`. `readOnly` fields inside the object are
hidden unless `show_readonly_fields` is on.

## Read-only (review) mode

When the whole form is in review mode (`read-only="true"` on the web
component — there is no library-side builder for it), rendering switches wholesale to
`readonly_field`: enums show their label, booleans show Yes/No, nested
objects render as groups, arrays of flat objects render as **tables**.
Submit/Reset are hidden. See [Styling](../guides/styling.md) for the
`readonly-*` part names.

## Override mechanisms

Two ways to force a widget other than the auto-selected one. Both produce
a `Widget` value that the dispatcher checks first.

### `ui:widget` (UiSchema) — recommended

Set `ui:widget` in the [UiSchema](ui-schema.md) parallel tree. This is the
primary mechanism from v0.7 onward and separates presentation from the
data schema:

```json
{
  "ui:widget": "textarea",
  "ui:placeholder": "Describe the issue…",
  "ui:help": "Be specific."
}
```

Recognised values: `"image-upload"`, `"swipe-review"`, `"hidden"`,
`"textarea"`, `"select"`, `"radio"`. Unknown values fall through as
`CustomWidget(raw)` so you can prototype without a parser change.

### `x-widget` (schema node) — deprecated fallback

The same idea as an extension field directly on the JSON Schema node:

```json
{ "type": "string", "x-widget": "textarea" }
```

Still works and is merged into the same `RenderHints.widget` slot, but
**prefer `ui:widget`** for new schemas — it keeps the data schema clean and
survives serialization round-trips more reliably. Upload-related extensions
(`x-accept`, `x-max-file-size`) follow the same pattern.

## Custom names and prototyping

`CustomWidget(String)` is the escape hatch. Anything you put in `ui:widget`
that isn't a recognised first-class variant becomes a `CustomWidget("…")`
and reaches the renderer as a plain string. The string renderers already
dispatch on three of these (`"textarea"`, `"select"`, `"radio"`); a custom
renderer can read `ctx.hints.widget` and do its own dispatch from there.

## Where to look in source

| Concern | File |
|---------|------|
| Top-level dispatch (widget → type → enum fallback) | `src/formosh/fields/field_dispatcher.gleam` |
| String sub-decision (oneOf / enum / textarea / input) | `src/formosh/fields/string_field.gleam` |
| HTML `type` from `format` | `string_field.get_input_type` |
| Array container + add/remove gating | `src/formosh/fields/array_field.gleam` |
| Object fieldset | `src/formosh/fields/object_field.gleam` |
| Image upload | `src/formosh/fields/image_field.gleam` |
| Swipe review | `src/formosh/fields/swipe_review_field.gleam` |
| Read-only rendering | `src/formosh/fields/readonly_field.gleam` |
| `ui:widget` + `x-widget` merge | `src/formosh/schema/ui_resolver.gleam` |
| Suppression decision (hidden / readonly) | `ui_resolver.is_suppressed` (shared with `form/visibility`) |
