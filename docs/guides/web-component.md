---
type: guide
title: "Web Component"
description: "Use <formosh-form> as a custom element with attribute config and custom events — no Gleam required."
---

# Web Component

Don't want to write Gleam? You don't have to. Formosh ships as a
`<formosh-form>` [custom element](https://developer.mozilla.org/en-US/docs/Web/API/Web_components).
Register it once, then drop it into any HTML page with attributes for the
schema and submission config.

This guide covers the **web component** path. For the in-Lustre programmatic
path, see [Quickstart](quickstart.md).

## Register and use

```html
<script type="module">
  import { register } from "./build/dev/javascript/formosh/formosh/component.mjs";
  register();
</script>

<formosh-form
  schema='{"type": "object", "properties": {"name": {"type": "string"}}}'
  submit-url="https://api.example.com/submit"
  submit-method="POST"
  initial-values='{"name": "John"}'>
</formosh-form>
```

`register()` calls Lustre's `lustre.register(component, "formosh-form")`,
which defines the element in the global custom-elements registry. After
that, every `<formosh-form>` on the page is a live form.

## Attributes

Attributes map one-to-one to the `FormConfig` builders. Set them as plain
HTML attributes (string values) — Formosh parses them internally.

| Attribute | Type | Maps to |
|-----------|------|---------|
| `schema` | JSON string | The JSON Schema. **Required** — the form stays in "Waiting for schema…" until it's set. |
| `submit-url` | string | `with_submit_url` |
| `submit-method` | string (`"POST"`, `"PUT"`, …) | bundled with `submit-url` |
| `submit-headers` | JSON string | bundled with `submit-url` |
| `initial-values` | JSON string (object) | `with_initial_values` |
| `show-readonly-fields` | `"true"` / `"false"` | `with_show_readonly_fields` |
| `read-only` | `"true"` / `"false"` | Review mode — render the whole form as a static summary |
| `upload-base-url` | string | Base URL for the image-upload widget (`POST {url}`, `DELETE {url}/{filename}`) |
| `ui-schema` | JSON string | `with_ui_schema_json` — full format in [UiSchema](../reference/ui-schema.md) |

### Changing attributes at runtime

Attributes are observed via `component.on_attribute_change`, so you can
mutate them after the form has mounted and Formosh will react. For example,
swapping the schema re-initializes the form (resolving conditionals against
the current values and re-validating).

```js
const form = document.querySelector('formosh-form');
form.setAttribute('schema', JSON.stringify(newSchema));
form.setAttribute('submit-url', 'https://api.example.com/v2/submit');
```

Setting `schema` to something unparseable logs a parse error to the console
and leaves the previous form in place — it does **not** throw.

## Custom events

The component emits four custom events. Listen with `addEventListener`:

```js
const form = document.querySelector('formosh-form');

form.addEventListener('formosh-ready', () => {
  console.log('Form mounted and validated');
});

form.addEventListener('formosh-change', (e) => {
  console.log('Values:', e.detail.values);    // current values object
  console.log('Valid:',  e.detail.isValid);   // boolean
  console.log('Dirty:',  e.detail.isDirty);   // boolean
});

form.addEventListener('formosh-submitting', () => {
  console.log('Submit in flight');
});

form.addEventListener('formosh-submit', (e) => {
  // e.detail.status === "success" → e.detail.data is the response body
  // e.detail.status === "error"   → e.detail.error is the message
  console.log('Submit result:', e.detail);
});
```

| Event | When it fires | `detail` |
|-------|---------------|----------|
| `formosh-ready` | Schema parsed and the form initialized | `{ schema: "loaded" }` |
| `formosh-change` | Any field value, validity, or dirtiness change | `{ values, isValid, isDirty }` |
| `formosh-submitting` | A submit attempt starts | `{ status: "submitting" }` |
| `formosh-submit` | Submit completes (success or failure) | `{ status: "success", data }` or `{ status: "error", error }` |

## Programmatic use inside Lustre — `component.element`

If you're already in a Lustre app and want to embed the form without the
attribute ceremony, use the `component.element` helper:

```gleam
import formosh/component

fn my_view(model) {
  component.element([
    component.schema(my_schema),
    component.submit_url("https://api.example.com/submit"),
    component.on_change(fn(_values) { ValuesChanged }),
  ])
}
```

The `component.*` attribute helpers (`schema`, `schema_string`,
`submit_url`, `submit_method`, `initial_values_string`,
`show_readonly_fields`, `read_only`, `upload_base_url`,
`ui_schema_string`, `on_submit`, `on_validate`, `on_change`) mirror the
HTML attributes one-for-one.

## Read-only (review) mode

Set `read-only="true"` to render the form as a static label→value summary
instead of editable inputs:

- Enums show their label, booleans show Yes/No.
- Nested objects render as groups; arrays of flat objects render as tables.
- Submit / Reset controls are hidden.

Use this to display the stored values of a record that is no longer
editable. Pair with `initial-values` to feed in the data. Styling uses the
`readonly-*` part names — see [Styling](styling.md).

## Custom cross-field validator

The web component exposes the same `with_validator` hook as the library,
but via a **JS property** rather than an attribute (functions can't be
attribute strings). Set it on the DOM node:

```js
const form = document.querySelector('formosh-form');

form.validator = (values) => {
  // values is the JS representation of the Value tree
  // return [] for valid, or [{ field: ["total_budget"], message: "...", rule: "custom" }]
  return [];
};
```

The validator is re-run on every value change. See the
[cross-field validation](configuration.md#cross-field-validation--with_validator)
section of the Configuration guide for the semantics (precedence, gating,
cost).

## Embedding checklist

- [ ] The path to `component.mjs` is correct for your build layout. The
  snippet above assumes the `build/dev/javascript/formosh/...` layout that
  `gleam build` produces; for production, bundle it (see `npm run build`,
  which produces a CDN bundle).
- [ ] `schema` is a valid JSON string. The most common failure is passing a
  JS object instead of `JSON.stringify(...)`-ing it.
- [ ] `submit-url` is set if you want submit to do anything. Without it,
  submit just validates and emits `formosh-change` / `formosh-submit`.
- [ ] You listen for `formosh-submit` (or read `e.detail.values` on
  `formosh-change`) — otherwise the submitted data goes nowhere.

## Reference

- The full attribute list lives in `src/formosh/component.gleam` (search for
  `component.on_attribute_change`).
- For the matching library-side builders → [Configuration](configuration.md).
- For styling the shadow DOM → [Styling](styling.md).
